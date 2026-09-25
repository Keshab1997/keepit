import '../../data/datasources/local_mind_datasource.dart';
import '../../domain/entities/mind_item.dart';
import 'cloud_sync_remote.dart';

/// Outcome of one sync run.
class SyncReport {
  final int pushed;
  final int pulled;
  final int deletedLocally;
  final int deletedRemotely;
  final DateTime finishedAt;

  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.deletedLocally = 0,
    this.deletedRemotely = 0,
    required this.finishedAt,
  });

  bool get changedLocalData => pulled > 0 || deletedLocally > 0;

  String get summary {
    final parts = <String>[];
    if (pushed > 0) parts.add('$pushed uploaded');
    if (pulled > 0) parts.add('$pulled downloaded');
    final removed = deletedLocally + deletedRemotely;
    if (removed > 0) parts.add('$removed removed');
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
            // If the local version was previously marked synced, mark it dirty
            // so the newer value repairs the cloud record below.
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

    // Our own pushes will come back on the next pull (serverUpdatedAt > cursor);
    // they merge as no-ops because timestamps match.
    await local.putMeta(cursorKey(uid), maxServer);
    final finishedAt = DateTime.now();
    await local.putMeta(lastSyncKey(uid), finishedAt.millisecondsSinceEpoch);

    return SyncReport(
      pushed: unsynced.length,
      pulled: pulled,
      deletedLocally: deletedLocally,
      deletedRemotely: pendingDeletes.length,
      finishedAt: finishedAt,
    );
  }

  /// Forgets the sync cursor so the next run re-downloads everything.
  Future<void> resetCursor(String uid) => local.putMeta(cursorKey(uid), null);
}
