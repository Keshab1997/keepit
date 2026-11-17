import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';

/// `normalizeUrl` decides "have I already saved this?" for the quick-add sheet,
/// the clipboard banner, the share capture and `addUrl` itself. If it is too
/// loose, two different reels collapse into one; if it is too strict, the same
/// link gets saved twice from two apps.
void main() {
  late Directory dir;
  late LocalMindDataSource dataSource;
  late MindFeedController controller;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('keepit_urls');
    Hive.init(dir.path);
    dataSource = LocalMindDataSource();
    await dataSource.init();
    // loadItems() seeds demo cards into the meta box unless it is told not to;
    // the box has to exist before the controller is read.
    await dataSource.putMeta(LocalMindDataSource.demoSeededKey, true);

    final container = ProviderContainer(
      overrides: [localDataSourceProvider.overrideWithValue(dataSource)],
    );
    addTearDown(container.dispose);
    controller = container.read(mindFeedProvider.notifier);
    await controller.loadItems(seedDemo: false);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  String norm(String url) => controller.normalizeUrl(url);

  test('strips tracking parameters', () {
    expect(
      norm('https://example.com/a?utm_source=x&utm_medium=y'),
      'https://example.com/a',
    );
    expect(norm('https://example.com/a?fbclid=abc'), 'https://example.com/a');
    expect(
      norm('https://instagram.com/reel/abc?igsh=xyz&si=1'),
      'https://instagram.com/reel/abc',
    );
  });

  test('keeps meaningful parameters', () {
    expect(
      norm('https://youtube.com/watch?v=abc123'),
      'https://youtube.com/watch?v=abc123',
    );
    expect(
      norm('https://example.com/a?utm_source=x&page=2'),
      'https://example.com/a?page=2',
      reason: 'the tracked and the real param must survive together',
    );
  });

  test('ignores case, trailing slashes and surrounding text', () {
    expect(norm('  HTTPS://Example.COM/Path/  '), 'https://example.com/path');
    expect(
      norm('check this out https://example.com/x?utm_source=a'),
      'https://example.com/x',
    );
  });

  test('different paths stay different', () {
    expect(
      norm('https://example.com/a') == norm('https://example.com/b'),
      isFalse,
    );
  });

  group('known gap: scheme and host are not normalised', () {
    test('http vs https of the same page do not match', () {
      // Documents the current behaviour rather than blessing it: a link shared
      // from an app that writes http:// will not be seen as a duplicate.
      expect(
        norm('http://example.com/a') == norm('https://example.com/a'),
        isFalse,
      );
    });

    test('www vs bare host do not match', () {
      expect(
        norm('https://www.example.com/a') == norm('https://example.com/a'),
        isFalse,
      );
    });
  });
}
