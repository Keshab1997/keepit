import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:keepit/core/cloud/auth_service.dart';
import 'package:keepit/core/cloud/cloud_sync_remote.dart';
import 'package:keepit/core/cloud/sync_engine.dart';
import 'package:keepit/core/utils/data_export.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/custom_space.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// In-memory stand-in for Firestore with a monotonically increasing
/// server clock (mirrors `serverUpdatedAt`).
class FakeRemote implements CloudSyncRemote {
  final Map<String, Map<String, RemoteRecord>> users = {};
  int _clock = 1000;
  int pushCalls = 0;

  Map<String, RemoteRecord> _u(String uid) => users.putIfAbsent(uid, () => {});

  /// Simulates another device writing to the cloud.
  void putFromOtherDevice(String uid, MindItem item) {
    _u(uid)[item.id] = RemoteRecord(
      id: item.id,
      data: item.toMap()..remove('isSynced'),
      updatedAtMs: item.updatedAt.toUtc().millisecondsSinceEpoch,
      serverMillis: ++_clock,
    );
  }

  void deleteFromOtherDevice(String uid, String id, DateTime at) {
    _u(uid)[id] = RemoteRecord(
      id: id,
      data: const {},
      updatedAtMs: at.toUtc().millisecondsSinceEpoch,
      deleted: true,
      serverMillis: ++_clock,
    );
  }

  @override
  Future<List<RemoteRecord>> fetchChanges(
    String uid, {
    int sinceServerMillis = 0,
  }) async =>
      _u(uid).values.where((r) => r.serverMillis > sinceServerMillis).toList();

  @override
  Future<void> push(
    String uid, {
    List<RemoteRecord> upserts = const [],
    Map<String, int> deletions = const {},
  }) async {
    pushCalls++;
    for (final r in upserts) {
      _u(uid)[r.id] = RemoteRecord(
        id: r.id,
        data: r.data,
        updatedAtMs: r.updatedAtMs,
        serverMillis: ++_clock,
      );
    }
    deletions.forEach((id, at) {
      _u(uid)[id] = RemoteRecord(
        id: id,
        data: const {},
        updatedAtMs: at,
        deleted: true,
        serverMillis: ++_clock,
      );
    });
  }

  final Map<String, Map<String, RemoteSpaceRecord>> spaceUsers = {};
  int spacePushCalls = 0;

  Map<String, RemoteSpaceRecord> _s(String uid) =>
      spaceUsers.putIfAbsent(uid, () => {});

  /// Simulates another device writing a Space to the cloud.
  void putSpaceFromOtherDevice(String uid, CustomSpace space) {
    _s(uid)[space.id] = RemoteSpaceRecord(
      id: space.id,
      data: space.toMap()..remove('isSynced'),
      updatedAtMs: space.effectiveUpdatedAt.toUtc().millisecondsSinceEpoch,
      serverMillis: ++_clock,
    );
  }

  void deleteSpaceFromOtherDevice(String uid, String id, DateTime at) {
    _s(uid)[id] = RemoteSpaceRecord(
      id: id,
      data: const {},
      updatedAtMs: at.toUtc().millisecondsSinceEpoch,
      deleted: true,
      serverMillis: ++_clock,
    );
  }

  @override
  Future<List<RemoteSpaceRecord>> fetchSpaceChanges(
    String uid, {
    int sinceServerMillis = 0,
  }) async =>
      _s(uid).values.where((r) => r.serverMillis > sinceServerMillis).toList();

  @override
  Future<void> pushSpaces(
    String uid, {
    List<RemoteSpaceRecord> upserts = const [],
    Map<String, int> deletions = const {},
  }) async {
    spacePushCalls++;
    for (final r in upserts) {
      _s(uid)[r.id] = RemoteSpaceRecord(
        id: r.id,
        data: r.data,
        updatedAtMs: r.updatedAtMs,
        serverMillis: ++_clock,
      );
    }
    deletions.forEach((id, at) {
      _s(uid)[id] = RemoteSpaceRecord(
        id: id,
        data: const {},
        updatedAtMs: at,
        deleted: true,
        serverMillis: ++_clock,
      );
    });
  }

  @override
  Future<void> deleteAllUserData(String uid) async {
    users.remove(uid);
    spaceUsers.remove(uid);
  }

  @override
  Future<int> countItems(String uid) async =>
      _u(uid).values.where((r) => !r.deleted).length;
}

/// Firestore denies the `spaces` collection until its rule is deployed; the
/// engine has to survive that.
class _SpaceDeniedRemote extends FakeRemote {
  @override
  Future<List<RemoteSpaceRecord>> fetchSpaceChanges(
    String uid, {
    int sinceServerMillis = 0,
  }) async =>
      throw Exception('permission-denied');
}

MindItem mk(
  String id, {
  String? title,
  DateTime? updated,
  bool watched = false,
}) {
  final t = updated ?? DateTime.utc(2026, 9, 1, 12);
  return MindItem(
    id: id,
    title: title ?? 'Item $id',
    type: ItemType.webArticle,
    isWatched: watched,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: t,
  );
}

void main() {
  late Directory dir;
  var boxCounter = 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('keepit_sync_');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Two independent "devices" = two separate Hive box pairs.
  Future<LocalMindDataSource> device() async {
    boxCounter++;
    final ds = _NamedDataSource('items_$boxCounter', 'meta_$boxCounter');
    await ds.init();
    return ds;
  }

  const uid = 'user-1';

  test('first sync uploads local items and marks them synced', () async {
    final local = await device();
    final remote = FakeRemote();
    await local.saveItem(mk('a'));
    await local.saveItem(mk('b'));

    final report = await SyncEngine(local: local, remote: remote).sync(uid);

    expect(report.pushed, 2);
    expect(await remote.countItems(uid), 2);
    expect(local.getUnsyncedItems(), isEmpty);
    expect(report.summary, '2 uploaded');
  });

  test('a second device downloads everything on first sync', () async {
    final remote = FakeRemote();
    final phone = await device();
    await phone.saveItem(mk('a', title: 'From phone'));
    await SyncEngine(local: phone, remote: remote).sync(uid);

    final tablet = await device();
    final report = await SyncEngine(local: tablet, remote: remote).sync(uid);

    expect(report.pulled, 1);
    expect(tablet.getItem('a')?.title, 'From phone');
    expect(tablet.getItem('a')?.isSynced, isTrue);
  });

  test('newer remote edit overwrites an older synced local copy', () async {
    final remote = FakeRemote();
    final local = await device();
    await local.saveItem(mk('a', title: 'Old'));
    await SyncEngine(local: local, remote: remote).sync(uid);

    remote.putFromOtherDevice(
      uid,
      mk(
        'a',
        title: 'Edited elsewhere',
        updated: DateTime.utc(2026, 9, 5),
        watched: true,
      ),
    );
    final report = await SyncEngine(local: local, remote: remote).sync(uid);

    expect(report.pulled, 1);
    expect(local.getItem('a')?.title, 'Edited elsewhere');
    expect(local.getItem('a')?.isWatched, isTrue);
  });

  test('conflict: newer unsynced local edit wins and is pushed', () async {
    final remote = FakeRemote();
    final local = await device();
    remote.putFromOtherDevice(
      uid,
      mk('a', title: 'Remote v1', updated: DateTime.utc(2026, 9, 2)),
    );
    await local.saveItem(
      mk('a', title: 'Local v2', updated: DateTime.utc(2026, 9, 3)),
    );

    final report = await SyncEngine(local: local, remote: remote).sync(uid);

    expect(local.getItem('a')?.title, 'Local v2');
    expect(report.pushed, 1);
    expect(remote.users[uid]!['a']!.data['title'], 'Local v2');
  });

  test(
    'stale remote edit never overwrites a newer synced local copy',
    () async {
      final remote = FakeRemote();
      final local = await device();
      await local.saveItem(
        mk('a', title: 'Newer local', updated: DateTime.utc(2026, 9, 10)),
      );
      await SyncEngine(local: local, remote: remote).sync(uid);

      // Simulate a delayed/stale write arriving from another device.
      remote.putFromOtherDevice(
        uid,
        mk('a', title: 'Stale remote', updated: DateTime.utc(2026, 9, 2)),
      );
      final report = await SyncEngine(local: local, remote: remote).sync(uid);

      expect(local.getItem('a')?.title, 'Newer local');
      expect(local.getItem('a')?.isSynced, isTrue);
      expect(report.pushed, 1);
      expect(remote.users[uid]!['a']!.data['title'], 'Newer local');
    },
  );

  test('stale remote deletion never removes a newer local copy', () async {
    final remote = FakeRemote();
    final local = await device();
    await local.saveItem(
      mk('a', title: 'Keep this', updated: DateTime.utc(2026, 9, 10)),
    );
    await SyncEngine(local: local, remote: remote).sync(uid);

    remote.deleteFromOtherDevice(uid, 'a', DateTime.utc(2026, 9, 2));
    final report = await SyncEngine(local: local, remote: remote).sync(uid);

    expect(local.getItem('a')?.title, 'Keep this');
    expect(local.getItem('a')?.isSynced, isTrue);
    expect(report.pushed, 1);
    expect(remote.users[uid]!['a']!.deleted, isFalse);
  });

  test(
    'a stale remote tombstone neither deletes nor strands a newer local copy',
    () async {
      final remote = FakeRemote();
      final local = await device();
      await local.saveItem(
        mk('a', title: 'Rescued', updated: DateTime.utc(2026, 9, 10)),
      );
      await SyncEngine(local: local, remote: remote).sync(uid);
      expect(local.getItem('a')?.isSynced, isTrue);

      // Another device deleted an *older* version of this item.
      remote.deleteFromOtherDevice(uid, 'a', DateTime.utc(2026, 9, 2));

      final ran = await SyncEngine(local: local, remote: remote).sync(uid);

      // The item survives…
      expect(local.getItem('a')?.title, 'Rescued');
      // …and the cloud copy is repaired, not left as a tombstone.
      expect(remote.users[uid]!['a']!.deleted, isFalse);
      expect(remote.users[uid]!['a']!.data['title'], 'Rescued');
      // Repaired by the push path, so local ends up synced again (not dirty).
      expect(local.getItem('a')?.isSynced, isTrue);
      expect(ran.pushed, 1);
      // A repeat sync is a no-op — no infinite repair loop.
      final again = await SyncEngine(local: local, remote: remote).sync(uid);
      expect(again.pushed, 0);
      expect(again.pulled, 0);
    },
  );

  test('local deletions propagate as tombstones to other devices', () async {
    final remote = FakeRemote();
    final phone = await device();
    final tablet = await device();
    await phone.saveItem(mk('a'));
    await SyncEngine(local: phone, remote: remote).sync(uid);
    await SyncEngine(local: tablet, remote: remote).sync(uid);
    expect(tablet.getItem('a'), isNotNull);

    await phone.deleteItem('a');
    expect(phone.getTombstones().containsKey('a'), isTrue);
    final r1 = await SyncEngine(local: phone, remote: remote).sync(uid);
    expect(r1.deletedRemotely, 1);
    expect(phone.getTombstones(), isEmpty);
    expect(await remote.countItems(uid), 0);

    final r2 = await SyncEngine(local: tablet, remote: remote).sync(uid);
    expect(r2.deletedLocally, 1);
    expect(tablet.getItem('a'), isNull);
    // Remote-originated deletes must not create new local tombstones.
    expect(tablet.getTombstones(), isEmpty);
  });

  test(
    'local delete newer than a remote edit keeps the item deleted',
    () async {
      final remote = FakeRemote();
      final local = await device();
      await local.saveItem(mk('a'));
      await SyncEngine(local: local, remote: remote).sync(uid);

      remote.putFromOtherDevice(
        uid,
        mk('a', title: 'Old edit', updated: DateTime.utc(2026, 9, 2)),
      );
      await local.deleteItem('a'); // tombstone = now (2026+) > remote edit
      await SyncEngine(local: local, remote: remote).sync(uid);

      expect(local.getItem('a'), isNull);
      expect(remote.users[uid]!['a']!.deleted, isTrue);
    },
  );

  test(
    'remote tombstone does not delete a newer unsynced local edit',
    () async {
      final remote = FakeRemote();
      final local = await device();
      remote.deleteFromOtherDevice(uid, 'a', DateTime.utc(2026, 9, 2));
      await local.saveItem(
        mk('a', title: 'Re-edited', updated: DateTime.utc(2026, 9, 10)),
      );

      await SyncEngine(local: local, remote: remote).sync(uid);

      expect(local.getItem('a')?.title, 'Re-edited');
      expect(remote.users[uid]!['a']!.deleted, isFalse);
    },
  );

  test('demo items are never uploaded', () async {
    final remote = FakeRemote();
    final local = await device();
    for (final id in SyncEngine.demoItemIds) {
      await local.saveItem(mk(id));
    }
    await local.saveItem(mk('real'));
    await local.deleteItem('1');

    final report = await SyncEngine(local: local, remote: remote).sync(uid);

    expect(report.pushed, 1);
    expect(remote.users[uid]!.keys, ['real']);
    expect(local.getTombstones(), isEmpty);
  });

  test(
    'incremental sync only fetches changes after the cursor and is idempotent',
    () async {
      final remote = FakeRemote();
      final local = await device();
      await local.saveItem(mk('a'));
      final engine = SyncEngine(local: local, remote: remote);
      await engine.sync(uid);
      final second = await engine.sync(uid);
      final third = await engine.sync(uid);

      expect(second.pulled, 0);
      expect(second.pushed, 0);
      expect(third.summary, 'Everything is up to date');
      expect(remote.pushCalls, 1);
    },
  );

  test('markAllUnsynced lets local data merge into a new account', () async {
    final remote = FakeRemote();
    final local = await device();
    await local.saveItem(mk('a'));
    await SyncEngine(local: local, remote: remote).sync(uid);
    await local.markAllUnsynced();

    final report = await SyncEngine(
      local: local,
      remote: remote,
    ).sync('user-2');
    expect(report.pushed, 1);
    expect(remote.users['user-2']!.keys, ['a']);
  });

  test('clearAll wipes items, tombstones and cursors', () async {
    final local = await device();
    await local.saveItem(mk('a'));
    await local.deleteItem('a');
    await local.putMeta(SyncEngine.cursorKey(uid), 5);
    await local.clearAll();

    expect(await local.getAllItems(), isEmpty);
    expect(local.getTombstones(), isEmpty);
    expect(local.getMeta<int>(SyncEngine.cursorKey(uid)), isNull);
  });

  test('data export produces valid JSON with every item', () {
    final json = DataExport.buildJson([
      mk('a'),
      mk('b'),
    ], now: DateTime.utc(2026, 9, 24));
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['format'], 'keepit-export');
    expect(decoded['count'], 2);
    expect((decoded['items'] as List).first['id'], 'a');
    expect((decoded['items'] as List).first.containsKey('isSynced'), isFalse);
    expect(decoded['exportedAt'], '2026-09-24T00:00:00.000Z');
  });

  test('AppUser initials', () {
    expect(
      const AppUser(uid: '1', displayName: 'Keshab Sarkar').initials,
      'KS',
    );
    expect(const AppUser(uid: '1', email: 'keshab@gmail.com').initials, 'KG');
    expect(const AppUser(uid: '1', displayName: 'Keshab').initials, 'K');
    expect(const AppUser(uid: '1').initials, '?');
  });

  group('spaces', () {
    CustomSpace space(
      String id,
      String name, {
      DateTime? updated,
      bool synced = false,
      int color = 0xFF10B981,
      String icon = 'lightbulb',
    }) =>
        CustomSpace(
          id: id,
          name: name,
          colorValue: color,
          iconName: icon,
          updatedAt: updated ?? DateTime.utc(2026, 9, 1, 12),
          isSynced: synced,
        );

    test('a local Space is uploaded and marked synced', () async {
      final local = await device();
      final remote = FakeRemote();
      await local.saveCustomSpaces([space('s1', 'Startup ideas')]);

      final report = await SyncEngine(local: local, remote: remote).sync(uid);

      expect(report.spacesPushed, 1);
      // A Space is not a memory: it must not inflate the item count.
      expect(report.pushed, 0);
      final stored = (await local.getCustomSpaces()).single;
      expect(stored.isSynced, isTrue);
      expect(remote.spaceUsers[uid]!['s1']!.data['name'], 'Startup ideas');
    });

    test('a second device downloads the Space, colour and icon included',
        () async {
      final remote = FakeRemote();
      final phone = await device();
      await phone.saveCustomSpaces(
          [space('s1', 'Design', color: 0xFFEC4899, icon: 'palette')]);
      await SyncEngine(local: phone, remote: remote).sync(uid);

      final tablet = await device();
      final report = await SyncEngine(local: tablet, remote: remote).sync(uid);

      expect(report.spacesPulled, 1);
      final pulled = (await tablet.getCustomSpaces()).single;
      expect(pulled.name, 'Design');
      expect(pulled.colorValue, 0xFFEC4899);
      expect(pulled.iconName, 'palette');
      expect(pulled.isSynced, isTrue);
    });

    test('a rename on the phone reaches the tablet', () async {
      final remote = FakeRemote();
      final phone = await device();
      await phone.saveCustomSpaces([space('s1', 'Old name')]);
      await SyncEngine(local: phone, remote: remote).sync(uid);

      final tablet = await device();
      await SyncEngine(local: tablet, remote: remote).sync(uid);

      // Rename on the phone, at a later instant.
      await phone.saveCustomSpaces(
          [space('s1', 'New name', updated: DateTime.utc(2026, 9, 9))]);
      await SyncEngine(local: phone, remote: remote).sync(uid);
      final report = await SyncEngine(local: tablet, remote: remote).sync(uid);

      expect(report.spacesPulled, 1);
      expect((await tablet.getCustomSpaces()).single.name, 'New name');
    });

    test('a Space saved before sync existed still reaches the other device',
        () async {
      final remote = FakeRemote();
      final phone = await device();
      // No updatedAt at all: the pre-sync shape, read back as the epoch.
      await phone.saveCustomSpaces([
        const CustomSpace(
          id: 'legacy',
          name: 'Reading list',
          colorValue: 0xFF3B82F6,
          iconName: 'book',
        ),
      ]);
      await SyncEngine(local: phone, remote: remote).sync(uid);

      final tablet = await device();
      final report = await SyncEngine(local: tablet, remote: remote).sync(uid);

      // Pushing the epoch would make the cloud copy permanently "oldest" and
      // no other device could ever accept it.
      expect(report.spacesPulled, 1);
      expect((await tablet.getCustomSpaces()).single.name, 'Reading list');
    });

    test(
        'deleting a Space reaches the other device and clears the local '
        'tombstone', () async {
      final remote = FakeRemote();
      final phone = await device();
      await phone.saveCustomSpaces([space('s1', 'Doomed')]);
      await SyncEngine(local: phone, remote: remote).sync(uid);

      final tablet = await device();
      await SyncEngine(local: tablet, remote: remote).sync(uid);
      expect((await tablet.getCustomSpaces()), hasLength(1));

      await phone.deleteCustomSpace('s1');
      await SyncEngine(local: phone, remote: remote).sync(uid);
      expect(phone.getSpaceTombstones(), isEmpty);

      await SyncEngine(local: tablet, remote: remote).sync(uid);
      expect(await tablet.getCustomSpaces(), isEmpty);
    });

    test('a Space sync failure leaves the item sync untouched', () async {
      final local = await device();
      final remote = _SpaceDeniedRemote();
      await local.saveItem(mk('a'));
      await local.saveCustomSpaces([space('s1', 'Ideas')]);

      final report = await SyncEngine(local: local, remote: remote).sync(uid);

      expect(report.pushed, 1);
      expect(await remote.countItems(uid), 1);
      expect(report.spacesPushed, 0);
      // The Space stays dirty for the next run, not lost.
      expect((await local.getCustomSpaces()).single.isSynced, isFalse);
    });
  });
}

/// Same data source but with unique box names so tests can simulate several
/// devices inside one process.
class _NamedDataSource extends LocalMindDataSource {
  _NamedDataSource(this.itemsName, this.metaName);
  final String itemsName;
  final String metaName;
  Box? _items;
  Box? _m;

  @override
  Future<void> init() async {
    _items = await Hive.openBox(itemsName);
    _m = await Hive.openBox(metaName);
  }

  @override
  Box get box => _items!;

  @override
  Box get meta => _m!;
}
