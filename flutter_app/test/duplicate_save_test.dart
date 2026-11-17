import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keepit/core/utils/metadata_extractor.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';

/// The clipboard banner, a share intent and a quick-add tap can all save the
/// same link, and on a cold start the share arrives while the feed is still
/// loading. Extraction is two network calls, so two calls overlap easily.
void main() {
  late Directory dir;
  late LocalMindDataSource dataSource;
  late MindFeedController controller;
  late int pageFetches;

  http.Response html(String title) => http.Response.bytes(
        utf8.encode(
          '<html><head><meta property="og:title" content="$title">'
          '<meta property="og:image" content="https://example.com/i.jpg">'
          '</head><body></body></html>',
        ),
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );

  setUp(() async {
    pageFetches = 0;
    MetadataExtractor.client = MockClient((request) async {
      pageFetches++;
      // Slow the scrape down so two saves of the same link genuinely overlap.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return html('An article');
    });

    dir = await Directory.systemTemp.createTemp('keepit_dup');
    Hive.init(dir.path);
    dataSource = LocalMindDataSource();
    await dataSource.init();
    await dataSource.putMeta(LocalMindDataSource.demoSeededKey, true);

    final container = ProviderContainer(
      overrides: [localDataSourceProvider.overrideWithValue(dataSource)],
    );
    addTearDown(container.dispose);
    controller = container.read(mindFeedProvider.notifier);
    await controller.loadItems(seedDemo: false);
  });

  tearDown(() async {
    MetadataExtractor.resetClient();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('two overlapping saves of the same link store it once', () async {
    const url = 'https://example.com/article?utm_source=share';

    final results = await Future.wait([
      controller.addUrl(url),
      controller.addUrl(url),
    ]);

    expect(
      results.where((r) => r == SaveResult.success).length,
      1,
      reason: 'exactly one save may win',
    );
    expect(results.where((r) => r == SaveResult.duplicate).length, 1);

    final stored = await dataSource.getAllItems();
    expect(stored.length, 1, reason: 'no duplicate card, no second cloud push');
    expect(controller.state.items.length, 1);
  });

  test('saving a link twice in sequence is reported as a duplicate', () async {
    const url = 'https://example.com/article';

    expect(await controller.addUrl(url), SaveResult.success);
    expect(await controller.addUrl(url), SaveResult.duplicate);
    expect((await dataSource.getAllItems()).length, 1);
    // The second call must be rejected before it pays for extraction.
    expect(pageFetches, 1);
  });

  test('the tracking-parameter variant counts as the same link', () async {
    expect(
      await controller.addUrl('https://example.com/article'),
      SaveResult.success,
    );
    expect(
      await controller.addUrl('https://example.com/article?utm_medium=x'),
      SaveResult.duplicate,
    );
  });
}
