import 'package:flutter/foundation.dart';

import '../../data/datasources/local_mind_datasource.dart';
import '../../domain/entities/custom_space.dart';
import '../../domain/entities/mind_item.dart';
import 'cloud_sync_remote.dart';

/// Outcome of one sync run.
class SyncReport {
  final int pushed;
  final int pulled;
  final int deletedLocally;
  final int deletedRemotely;

  /// Spaces are synced after the items and never counted in `pushed`: a Space
  /// is not a memory, and the Profile line would read as if two extra items
  /// had been uploaded.
  final int spacesPushed;
  final int spacesPulled;

  /// UTC. Every persisted instant in the app is UTC; a local DateTime here
  /// round-trips through `millisecondsSinceEpoch` fine, but reading it back
  /// with `DateTime.fromMillisecondsSinceEpoch` produces a *local* DateTime,
  /// so the Profile screen compared a local timestamp against UTC ones.
  final DateTime finishedAt;

  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.deletedLocally = 0,
    this.deletedRemotely = 0,
    this.spacesPushed = 0,
    this.spacesPulled = 0,
    required this.finishedAt,
  });

  bool get changedLocalData =>
      pulled > 0 || deletedLocally > 0 || spacesPulled > 0;

  String get summary {
    final parts = <String>[];
    if (pushed > 0) parts.add('$pushed uploaded');
    if (pulled > 0) parts.add('$pulled downloaded');
    final removed = deletedLocally + deletedRemotely;
    if (removed > 0) parts.add('$removed removed');
    if (spacesPulled > 0) {
      parts.add(spacesPulled == 1 ? '1 space' : '$spacesPulled spaces');
    }
    return parts.isEmpty ? 'Everything is up to date' : parts.join(' • ');
  }
}

/// Two-way, local-first sync between Hive and the cloud.
///
/// Algorithm (per run):
/// 1. **Pull** remote changes since the last server cursor (everything on the
///    first sync for this account).
/// 2. **Merge** each remote record with last-write-wins on `updatedAt`:
///    * remote newer → overwrite local (or delete locally for tombstones)
///    * local newer and unsynced → keep local, it will be pushed
///    * a local tombstone newer than the remote edit → deletion wins
/// 3. **Push** unsynced local items + pending tombstones.
/// 4. Mark pushed items synced (unless they were edited meanwhile) and advance
///    the cursor.
///
/// Demo/sample items (ids '1'..'4') are never uploaded.
class SyncEngine {
  SyncEngine({required this.local, required this.remote});

  final LocalMindDataSource local;
  final CloudSyncRemote remote;

  static const Set<String> demoItemIds = {'1', '2', '3', '4'};

  static String cursorKey(String uid) => 'sync_cursor_$uid';
  static String lastSyncKey(String uid) => 'last_sync_at_$uid';

  static int _ms(DateTime d) => d.toUtc().millisecondsSinceEpoch;

  Future<SyncReport> sync(String uid) async {
    final cursor = local.getMeta<int>(cursorKey(uid)) ?? 0;
    final remoteChanges = await remote.fetchChanges(
      uid,
      sinceServerMillis: cursor,
    );

    // Spaces are pulled with the same cursor as items, but a failure here must
    // never take the item sync down with it: the `spaces` collection needs its
    // own firewall rule, and until that is deployed a read is *denied*, which
    // is a perfectly ordinary state for this app to be in.
    var remoteSpaces = const <RemoteSpaceRecord>[];
    var spaceSyncReachable = true;
    try {
      remoteSpaces = await remote.fetchSpaceChanges(
        uid,
        sinceServerMillis: cursor,
      );
    } catch (e) {
      spaceSyncReachable = false;
      debugPrint('KeepIt: space sync unavailable this run ($e)');
    }

    var pulled = 0;
    var deletedLocally = 0;
    var maxServer = cursor;
    final tombstones = Map<String, int>.from(local.getTombstones());
    final settledTombstones = <String>{};

    for (final r in remoteChanges) {
      if (r.serverMillis > maxServer) maxServer = r.serverMillis;
      final localItem = local.getItem(r.id);
      final localTombstone = tombstones[r.id];

      if (r.deleted) {
        if (localItem != null) {
          final localMs = _ms(localItem.updatedAt);
          if (localMs > r.updatedAtMs) {
            // A stale remote tombstone must not erase a newer local version.
            // If that version is currently marked synced (so the push below
            // would skip it), save it unsynced to repair the cloud record.
            // (saveItem defaults to synced: false — that *is* the dirtying.)
            if (localItem.isSynced) {
              await local.saveItem(localItem);
            }
          } else {
            // Equal timestamps are resolved in favour of the deletion.
            await local.deleteItem(r.id, recordTombstone: false);
            deletedLocally++;
          }
        }
        if (localTombstone != null && r.updatedAtMs >= localTombstone) {
          settledTombstones.add(r.id);
        }
        continue;
      }

      // Local deletion newer than the remote edit → keep it deleted.
      if (localTombstone != null && localTombstone >= r.updatedAtMs) continue;

      MindItem remoteItem;
      try {
        remoteItem = MindItem.fromMap({...r.data, 'id': r.id});
      } catch (_) {
        continue; // Malformed cloud document — skip rather than crash.
      }

      if (localItem == null) {
        await local.saveItem(remoteItem, synced: true);
        pulled++;
        continue;
      }

      final localMs = _ms(localItem.updatedAt);
      if (r.updatedAtMs > localMs) {
        await local.saveItem(remoteItem, synced: true);
        pulled++;
      } else if (r.updatedAtMs == localMs && !localItem.isSynced) {
        // Same version already in the cloud (e.g. pushed from here before a crash).
        await local.saveItem(localItem, synced: true);
      } else if (r.updatedAtMs < localMs && localItem.isSynced) {
        // The cloud can contain a stale write when another device had a clock
        // skew or a delayed retry. Keep the newer local version and repair the
        // cloud instead of overwriting the phone with stale data.
        await local.saveItem(localItem);
      }
      // else: local is newer and unsynced → pushed below.
    }

    await local.clearTombstones(settledTombstones);

    // ---- Push ----
    final unsynced = local
        .getUnsyncedItems()
        .where((i) => !demoItemIds.contains(i.id))
        .toList();
    final pendingDeletes = Map<String, int>.from(local.getTombstones())
      ..removeWhere((id, _) => demoItemIds.contains(id));

    if (unsynced.isNotEmpty || pendingDeletes.isNotEmpty) {
      await remote.push(
        uid,
        upserts: unsynced
            .map(
              (i) => RemoteRecord(
                id: i.id,
                data: i.toMap()..remove('isSynced'),
                updatedAtMs: _ms(i.updatedAt),
              ),
            )
            .toList(),
        deletions: pendingDeletes,
      );

      for (final pushedItem in unsynced) {
        final current = local.getItem(pushedItem.id);
        // Only mark synced if not edited again while the upload was running.
        if (current != null &&
            !current.isSynced &&
            _ms(current.updatedAt) == _ms(pushedItem.updatedAt)) {
          await local.saveItem(current, synced: true);
        }
      }
      await local.clearTombstones(pendingDeletes.keys);
      // Demo tombstones never need pushing.
      await local.clearTombstones(
        local.getTombstones().keys.where(demoItemIds.contains),
      );
    }

    var spacesPushed = 0;
    var spacesPulled = 0;
    if (spaceSyncReachable) {
      try {
        final spaceResult = await _syncSpaces(
          uid,
          remoteSpaces,
          startCursor: maxServer,
        );
        spacesPulled = spaceResult.pulled;
        spacesPushed = spaceResult.pushed;
        if (spaceResult.maxServer > maxServer) {
          maxServer = spaceResult.maxServer;
        }
      } catch (e) {
        // A space problem is not worth an item sync failure. The next run
        // retries; nothing local was lost because spaces are written last.
        debugPrint('KeepIt: space sync skipped this run ($e)');
      }
    }

    // Our own pushes will come back on the next pull (serverUpdatedAt > cursor);
    // they merge as no-ops because timestamps match.
    await local.putMeta(cursorKey(uid), maxServer);
    final finishedAt = DateTime.now().toUtc();
    await local.putMeta(lastSyncKey(uid), finishedAt.millisecondsSinceEpoch);

    return SyncReport(
      pushed: unsynced.length,
      pulled: pulled,
      deletedLocally: deletedLocally,
      deletedRemotely: pendingDeletes.length,
      spacesPushed: spacesPushed,
      spacesPulled: spacesPulled,
      finishedAt: finishedAt,
    );
  }

  /// Two-way Space sync: pull with last-write-wins, then push what is left.
  ///
  /// Same shape as the item pass above, with one difference that matters: a
  /// Space saved before sync existed has no stored timestamp, so it is pushed
  /// with *now* as its client time. Pushing the epoch instead would create a
  /// cloud document no other device could ever accept as newer, and the Space
  /// would silently never arrive anywhere.
  Future<({int pushed, int pulled, int maxServer})> _syncSpaces(
    String uid,
    List<RemoteSpaceRecord> remoteSpaces, {
    required int startCursor,
  }) async {
    final localSpaces = await local.getCustomSpaces();
    final spaceTombstones = Map<String, int>.from(local.getSpaceTombstones());
    final settled = <String>{};
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

    final byId = <String, CustomSpace>{
      for (final space in localSpaces) space.id: space,
    };
    var changed = false;
    var pulled = 0;
    var maxServer = startCursor;

    for (final r in remoteSpaces) {
      if (r.serverMillis > maxServer) maxServer = r.serverMillis;
      final localSpace = byId[r.id];
      final localTombstone = spaceTombstones[r.id];

      if (r.deleted) {
        if (localSpace != null) {
          if (_ms(localSpace.effectiveUpdatedAt) > r.updatedAtMs) {
            // A stale cloud tombstone must not erase a newer local Space: keep
            // it and let the push below re-upload it.
            if (localSpace.isSynced) {
              byId[r.id] = localSpace.copyWith(isSynced: false);
              changed = true;
            }
          } else {
            byId.remove(r.id);
            changed = true;
          }
        }
        if (localTombstone != null && r.updatedAtMs >= localTombstone) {
          settled.add(r.id);
        }
        continue;
      }

      // A local deletion newer than the remote edit wins.
      if (localTombstone != null && localTombstone >= r.updatedAtMs) continue;

      CustomSpace remoteSpace;
      try {
        remoteSpace = CustomSpace.fromMap({...r.data, 'id': r.id});
      } catch (_) {
        continue; // Malformed cloud document — skip, do not crash the sync.
      }

      if (localSpace == null) {
        byId[r.id] = remoteSpace.copyWith(id: r.id, isSynced: true);
        changed = true;
        pulled++;
        continue;
      }

      final localMs = _ms(localSpace.effectiveUpdatedAt);
      if (r.updatedAtMs > localMs) {
        byId[r.id] = remoteSpace.copyWith(id: r.id, isSynced: true);
        changed = true;
        pulled++;
      } else if (r.updatedAtMs == localMs && !localSpace.isSynced) {
        byId[r.id] = localSpace.copyWith(isSynced: true);
        changed = true;
      } else if (r.updatedAtMs < localMs && localSpace.isSynced) {
        // Clock skew or a delayed retry left a stale copy in the cloud; keep
        // the newer local Space and repair the cloud instead of losing the edit.
        byId[r.id] = localSpace.copyWith(isSynced: false);
        changed = true;
      }
    }

    final unsynced = byId.values.where((space) => !space.isSynced).toList();
    final pendingDeletes = Map<String, int>.from(spaceTombstones)
      ..removeWhere((id, _) => settled.contains(id));

    if (unsynced.isNotEmpty || pendingDeletes.isNotEmpty) {
      await remote.pushSpaces(
        uid,
        upserts: unsynced
            .map(
              (space) => RemoteSpaceRecord(
                id: space.id,
                data: space.toMap()..remove('isSynced'),
                updatedAtMs: () {
                  final ms = _ms(space.effectiveUpdatedAt);
                  return ms > 0 ? ms : nowMs;
                }(),
              ),
            )
            .toList(),
        deletions: pendingDeletes,
      );
      for (final space in unsynced) {
        final current = byId[space.id];
        if (current != null && !current.isSynced) {
          byId[space.id] = current.copyWith(isSynced: true);
          changed = true;
        }
      }
      await local.clearSpaceTombstones(pendingDeletes.keys);
    }
    await local.clearSpaceTombstones(settled);

    if (changed) {
      await local.saveCustomSpaces(byId.values.toList());
    }

    return (pushed: unsynced.length, pulled: pulled, maxServer: maxServer);
  }

  /// Forgets the sync cursor so the next run re-downloads everything.
  Future<void> resetCursor(String uid) => local.putMeta(cursorKey(uid), null);
}
