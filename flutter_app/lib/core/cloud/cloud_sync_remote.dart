import 'package:cloud_firestore/cloud_firestore.dart';

/// One item document as stored in the cloud.
class RemoteRecord {
  final String id;

  /// `MindItem.toMap()` payload (without `isSynced`). Empty for tombstones.
  final Map<String, dynamic> data;

  /// Client modification time, UTC epoch millis (used for last-write-wins).
  final int updatedAtMs;

  /// Tombstone: the item was deleted on some device.
  final bool deleted;

  /// Server write time, UTC epoch millis (used for incremental pulls).
  /// `0` when unknown.
  final int serverMillis;

  const RemoteRecord({
    required this.id,
    required this.data,
    required this.updatedAtMs,
    this.deleted = false,
    this.serverMillis = 0,
  });
}

/// Storage backend for sync. Abstracted so [SyncEngine] is unit-testable.
abstract class CloudSyncRemote {
  /// Records written after [sinceServerMillis] (all records when 0).
  Future<List<RemoteRecord>> fetchChanges(String uid,
      {int sinceServerMillis = 0});

  /// Upserts items and writes tombstones for deleted ids.
  Future<void> push(String uid,
      {List<RemoteRecord> upserts, Map<String, int> deletions});

  /// Removes every cloud document of the user (account deletion).
  Future<void> deleteAllUserData(String uid);

  /// Number of live (non-deleted) items in the cloud.
  Future<int> countItems(String uid);
}

/// Firestore layout:
/// ```
/// users/{uid}                   { lastSyncAt, platform }
/// users/{uid}/items/{itemId}    { ...item, updatedAtMs, deleted, serverUpdatedAt }
/// ```
/// Security rules (firestore.rules) allow access only to the owner.
class FirestoreSyncRemote implements CloudSyncRemote {
  FirestoreSyncRemote({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Firestore batches allow 500 operations; stay below for safety.
  static const int _batchSize = 400;

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection('users').doc(uid).collection('items');

  @override
  Future<List<RemoteRecord>> fetchChanges(String uid,
      {int sinceServerMillis = 0}) async {
    Query<Map<String, dynamic>> query = _items(uid);
    if (sinceServerMillis > 0) {
      query = query.where(
        'serverUpdatedAt',
        isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(sinceServerMillis),
      );
    }
    final snap = await query.get(const GetOptions(source: Source.server));
    return snap.docs.map((doc) {
      final raw = Map<String, dynamic>.from(doc.data());
      final deleted = raw.remove('deleted') == true;
      final updatedAtMs = (raw.remove('updatedAtMs') as num?)?.toInt() ?? 0;
      final server = raw.remove('serverUpdatedAt');
      raw.remove('isSynced');
      return RemoteRecord(
        id: doc.id,
        data: raw,
        updatedAtMs: updatedAtMs,
        deleted: deleted,
        serverMillis: server is Timestamp ? server.millisecondsSinceEpoch : 0,
      );
    }).toList();
  }

  @override
  Future<void> push(
    String uid, {
    List<RemoteRecord> upserts = const [],
    Map<String, int> deletions = const {},
  }) async {
    final ops = <void Function(WriteBatch)>[];
    for (final r in upserts) {
      final doc = <String, dynamic>{
        ...r.data,
        'updatedAtMs': r.updatedAtMs,
        'deleted': false,
        'serverUpdatedAt': FieldValue.serverTimestamp(),
      }..remove('isSynced');
      ops.add((b) => b.set(_items(uid).doc(r.id), doc));
    }
    deletions.forEach((id, deletedAtMs) {
      // Tombstone (not a real delete) so other devices learn about it.
      ops.add((b) => b.set(_items(uid).doc(id), {
            'id': id,
            'deleted': true,
            'updatedAtMs': deletedAtMs,
            'serverUpdatedAt': FieldValue.serverTimestamp(),
          }));
    });
    if (ops.isEmpty) return;

    for (var i = 0; i < ops.length; i += _batchSize) {
      final batch = _db.batch();
      for (final op in ops.skip(i).take(_batchSize)) {
        op(batch);
      }
      await batch.commit();
    }
    await _db.collection('users').doc(uid).set(
      {'lastSyncAt': FieldValue.serverTimestamp(), 'schema': 1},
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> deleteAllUserData(String uid) async {
    while (true) {
      final snap = await _items(uid)
          .limit(_batchSize)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await _db.collection('users').doc(uid).delete();
  }

  @override
  Future<int> countItems(String uid) async {
    final agg =
        await _items(uid).where('deleted', isEqualTo: false).count().get();
    return agg.count ?? 0;
  }
}
