import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:keepit/core/cloud/auth_service.dart';
import 'package:keepit/core/cloud/cloud_sync_remote.dart';
import 'package:keepit/core/cloud/sync_engine.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';

class _EmptyRemote implements CloudSyncRemote {
  @override
  Future<List<RemoteRecord>> fetchChanges(String uid,
          {int sinceServerMillis = 0}) async =>
      const [];
  @override
  Future<void> push(String uid,
      {List<RemoteRecord> upserts = const [],
      Map<String, int> deletions = const {}}) async {}
  @override
  Future<void> deleteAllUserData(String uid) async {}
  @override
  Future<int> countItems(String uid) async => 0;
}

/// A [LocalMindDataSource] on uniquely named boxes, so several "devices" can
/// live side by side inside one test binary (mirrors sync_engine_test).
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

MindItem _item(String id) {
  final t = DateTime.utc(2026, 9, 1, 12);
  return MindItem(
    id: id,
    title: 'Item $id',
    type: ItemType.webArticle,
    createdAt: t,
    updatedAt: t,
  );
}

/// Regression guard: "Delete all local data" used to wipe the whole meta box,
/// so the next cold start replayed onboarding and dropped the sync cursor.
void main() {
  late Directory dir;
  var counter = 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('keepit_clearall_');
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

  Future<LocalMindDataSource> freshDevice() async {
    counter++;
    final ds = _NamedDataSource('items_clear_$counter', 'meta_clear_$counter');
    await ds.init();
    return ds;
  }

  test('clearAll keeps onboarding_seen and demo_seeded', () async {
    final local = await freshDevice();
    await local.putMeta(LocalMindDataSource.onboardingSeenKey, true);
    await local.putMeta(LocalMindDataSource.demoSeededKey, true);
    await local.saveItem(_item('a'));

    await local.clearAll();

    expect(await local.getAllItems(), isEmpty);
    expect(local.getMeta<bool>(LocalMindDataSource.onboardingSeenKey), isTrue,
        reason: 'the user must not see onboarding again after a data wipe');
    expect(local.getMeta<bool>(LocalMindDataSource.demoSeededKey), isTrue,
        reason: 'sample cards must not reappear on an empty mind');
  });

  test('clearAll still drops the sync cursor so the cloud re-downloads',
      () async {
    final local = await freshDevice();
    await local.putMeta(LocalMindDataSource.onboardingSeenKey, true);
    await local.putMeta(SyncEngine.cursorKey('u1'), 1234);
    await local.putMeta(SyncEngine.lastSyncKey('u1'), 9999);
    await local.putMeta(LocalMindDataSource.customSpacesKey, [
      {'id': 's1', 'name': 'Space', 'color': '#FF0000', 'iconName': 'star'},
    ]);
    // A tombstone is part of the data, not first-run state.
    await local.saveItem(_item('gone'));
    await local.deleteItem('gone');

    await local.clearAll();

    expect(local.getMeta<int>(SyncEngine.cursorKey('u1')), isNull);
    expect(local.getMeta<int>(SyncEngine.lastSyncKey('u1')), isNull);
    expect(await local.getCustomSpaces(), isEmpty);
    expect(local.getTombstones(), isEmpty);
  });

  test('a wiped device does not resurrect sample cards in the feed', () async {
    final local = await freshDevice();
    await local.putMeta(LocalMindDataSource.onboardingSeenKey, true);
    // Simulate the app having seeded samples once already.
    await local.putMeta(LocalMindDataSource.demoSeededKey, true);
    await local.saveItem(_item('mine'));

    await local.clearAll();

    final feed = MindFeedController(local);
    await feed.ready;
    await feed.loadItems(seedDemo: false);

    expect(feed.state.items, isEmpty);
  });
}
