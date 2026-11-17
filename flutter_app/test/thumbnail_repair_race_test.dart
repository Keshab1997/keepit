import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';

/// Two repairs can be in flight for the same card: the one a failing image
/// asks for, and the startup sweep. Both await a scrape before writing, so the
/// second one to finish used to overwrite the first with a *different* URL and
/// bump `updatedAt` again — every round-trip of that fight is a cloud push.
class _CountingDataSource extends LocalMindDataSource {
  int writes = 0;

  @override
  Future<void> updateItem(MindItem item, {bool synced = false}) {
    writes++;
    return super.updateItem(item, synced: synced);
  }
}

void main() {
  late Directory dir;
  late _CountingDataSource dataSource;

  final item = MindItem(
    id: 'item-1',
    title: 'A reel',
    type: ItemType.instagramReel,
    thumbnailUrl: 'https://scontent.cdninstagram.com/expired.jpg',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('keepit_thumb_race');
    Hive.init(dir.path);
    dataSource = _CountingDataSource();
    await dataSource.init();
    await dataSource.saveItem(item, synced: true);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('two repairs of the same URL write once, not twice', () async {
    final container = ProviderContainer(
      overrides: [localDataSourceProvider.overrideWithValue(dataSource)],
    );
    addTearDown(container.dispose);
    final controller = container.read(mindFeedProvider.notifier);
    await controller.loadItems(seedDemo: false);

    const fresh = 'https://img.youtube.com/vi/abc123/hqdefault.jpg';

    // Exactly what happens when a card fails and the startup sweep both fire for
    // the same item: the two calls resolve at the same time.
    await Future.wait([
      controller.replaceThumbnail(item.id, fresh),
      controller.replaceThumbnail(item.id, fresh),
    ]);

    expect(dataSource.getItem(item.id)!.thumbnailUrl, fresh);
    expect(
      dataSource.writes,
      1,
      reason: 'the second write is a no-op once it sees the first one landed; '
          'writing again means a second updatedAt and a second cloud push',
    );
  });

  test('when two different URLs land together the last one wins', () async {
    final container = ProviderContainer(
      overrides: [localDataSourceProvider.overrideWithValue(dataSource)],
    );
    addTearDown(container.dispose);
    final controller = container.read(mindFeedProvider.notifier);
    await controller.loadItems(seedDemo: false);

    // Nothing is lost or interleaved: writes are serialised, so the stored
    // record is always one of the two URLs and never a half-applied mix.
    await Future.wait([
      controller.replaceThumbnail(item.id, 'https://example.com/a.jpg'),
      controller.replaceThumbnail(item.id, 'https://example.com/b.jpg'),
    ]);

    expect(
      dataSource.getItem(item.id)!.thumbnailUrl,
      'https://example.com/b.jpg',
    );
    expect(controller.pendingThumbnailWrites, 0);
  });

  test('repairing a deleted item writes nothing', () async {
    final container = ProviderContainer(
      overrides: [localDataSourceProvider.overrideWithValue(dataSource)],
    );
    addTearDown(container.dispose);
    final controller = container.read(mindFeedProvider.notifier);
    await controller.loadItems(seedDemo: false);

    await controller.deleteItem(item.id);
    await controller.replaceThumbnail(item.id, 'https://example.com/x.jpg');

    expect(dataSource.getItem(item.id), isNull);
  });
}
