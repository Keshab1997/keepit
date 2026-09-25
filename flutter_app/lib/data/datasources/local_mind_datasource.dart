import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/custom_space.dart';
import '../../domain/entities/mind_item.dart';

class LocalMindDataSource {
  static const String boxName = 'mind_items_box';
  static const String metaBoxName = 'keepit_sync_meta';

  static const String _tombstonesKey = 'tombstones';

  /// Set once demo items were seeded or the user emptied their mind, so the
  /// sample cards never come back.
  static const String demoSeededKey = 'demo_seeded';

  /// Set once the first-launch onboarding has been shown (finished or skipped).
  static const onboardingSeenKey = 'onboarding_seen';

  /// User-created Spaces are stored in the local meta box and sync through
  /// each item's `spaceId` field. Built-in smart spaces remain code-defined.
  static const customSpacesKey = 'custom_spaces';

  Box? _box;
  Box? _meta;

  Future<void> init() async {
    _box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await Hive.openBox(boxName);
    _meta = Hive.isBoxOpen(metaBoxName)
        ? Hive.box(metaBoxName)
        : await Hive.openBox(metaBoxName);
  }

  Box get box {
    if (_box == null || !_box!.isOpen) {
      throw Exception('Hive Box is not initialized.');
    }
    return _box!;
  }

  /// Small key/value box for sync bookkeeping (tombstones, cursors, prefs).
  Box get meta {
    if (_meta == null || !_meta!.isOpen) {
      throw Exception('Hive meta box is not initialized.');
    }
    return _meta!;
  }

  Future<List<MindItem>> getAllItems() async {
    final rawData = box.values.toList();
    final List<MindItem> items = [];
    for (var element in rawData) {
      try {
        if (element is Map) {
          items.add(MindItem.fromMap(element));
        }
      } catch (e) {
        // Skip corrupt entry
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  MindItem? getItem(String id) {
    final raw = box.get(id);
    if (raw is! Map) return null;
    try {
      return MindItem.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  /// Saves a user change. Every local write is marked unsynced so Cloud Sync
  /// picks it up. Pass [synced] = true only when the data came from the cloud.
  Future<void> saveItem(MindItem item, {bool synced = false}) async {
    await box.put(item.id, item.copyWith(isSynced: synced).toMap());
    // Re-created after a delete: the tombstone no longer applies.
    if (_tombstones.containsKey(item.id)) {
      final t = _tombstones..remove(item.id);
      await meta.put(_tombstonesKey, t);
    }
  }

  Future<void> updateItem(MindItem item, {bool synced = false}) =>
      saveItem(item, synced: synced);

  /// Deletes an item. Records a tombstone so the deletion reaches the cloud
  /// and other devices. Use [recordTombstone] = false for deletions that
  /// originate *from* the cloud.
  Future<void> deleteItem(String id, {bool recordTombstone = true}) async {
    await box.delete(id);
    if (recordTombstone) {
      final t = _tombstones
        ..[id] = DateTime.now().toUtc().millisecondsSinceEpoch;
      await meta.put(_tombstonesKey, t);
    }
    if (box.isEmpty && meta.get(demoSeededKey) != true) {
      await meta.put(demoSeededKey, true);
    }
  }

  List<MindItem> getUnsyncedItems() {
    return box.values
        .whereType<Map>()
        .map((e) {
          try {
            return MindItem.fromMap(e);
          } catch (_) {
            return null;
          }
        })
        .whereType<MindItem>()
        .where((item) => !item.isSynced)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Sync bookkeeping
  // ---------------------------------------------------------------------------

  Map<String, int> get _tombstones {
    final raw = meta.get(_tombstonesKey);
    if (raw is! Map) return <String, int>{};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  /// itemId -> deletedAt (UTC epoch millis) for deletions not yet pushed.
  Map<String, int> getTombstones() => Map.unmodifiable(_tombstones);

  Future<void> clearTombstones(Iterable<String> ids) async {
    final t = _tombstones;
    var changed = false;
    for (final id in ids) {
      changed |= t.remove(id) != null;
    }
    if (changed) await meta.put(_tombstonesKey, t);
  }

  T? getMeta<T>(String key) {
    final v = meta.get(key);
    return v is T ? v : null;
  }

  Future<void> putMeta(String key, Object? value) async {
    if (value == null) {
      await meta.delete(key);
    } else {
      await meta.put(key, value);
    }
  }

  Future<List<CustomSpace>> getCustomSpaces() async {
    final raw = meta.get(customSpacesKey);
    if (raw is! List) return const [];
    final spaces = <CustomSpace>[];
    for (final value in raw) {
      if (value is! Map) continue;
      try {
        spaces.add(CustomSpace.fromMap(value));
      } catch (_) {
        // Ignore one corrupt Space instead of hiding the rest of the library.
      }
    }
    return spaces;
  }

  Future<void> saveCustomSpaces(List<CustomSpace> spaces) async {
    await meta.put(
      customSpacesKey,
      spaces.map((space) => space.toMap()).toList(),
    );
  }

  /// Deletes a Space and unassigns its items so no orphaned space IDs remain.
  Future<void> deleteCustomSpace(String spaceId) async {
    final spaces = await getCustomSpaces();
    await saveCustomSpaces(
        spaces.where((space) => space.id != spaceId).toList());
    final affected = <MindItem>[];
    for (final raw in box.values) {
      if (raw is! Map) continue;
      try {
        final item = MindItem.fromMap(raw);
        if (item.spaceId == spaceId) {
          affected.add(
            item.copyWith(
              clearSpaceId: true,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        }
      } catch (_) {}
    }
    for (final item in affected) {
      await saveItem(item);
    }
  }

  /// Marks everything as needing upload (used after signing out so local data
  /// merges into whichever account signs in next).
  Future<void> markAllUnsynced() async {
    final updates = <dynamic, dynamic>{};
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map && raw['isSynced'] == true) {
        updates[key] = Map<dynamic, dynamic>.from(raw)..['isSynced'] = false;
      }
    }
    if (updates.isNotEmpty) await box.putAll(updates);
  }

  /// Wipes all saved items and sync state from this device.
  Future<void> clearAll() async {
    await box.clear();
    await meta.clear();
    // Keep the demo flag so sample cards don't reappear on an empty mind.
    await meta.put(demoSeededKey, true);
  }
}
