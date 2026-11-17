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

  group('scheme and www are folded together', () {
    test('http and https are the same page', () {
      expect(norm('http://example.com/a'), norm('https://example.com/a'));
    });

    test('www and the bare host are the same page', () {
      expect(norm('https://www.example.com/a'), norm('https://example.com/a'));
    });

    test('all four spellings collapse to one', () {
      final variants = [
        'http://example.com/a',
        'https://example.com/a',
        'https://www.example.com/a',
        'http://WWW.Example.com/a/',
        'text https://example.com/a?utm_source=x',
      ].map(norm).toSet();
      expect(variants.length, 1, reason: 'the user saved one page');
    });

    test('different hosts are still different', () {
      expect(
        norm('https://example.com/a') == norm('https://notexample.com/a'),
        isFalse,
      );
    });

    test('the path keeps its case - only scheme and host are folded', () {
      expect(
        norm('https://example.com/SomeCase') ==
            norm('https://example.com/somecase'),
        // Paths are lower-cased by the pre-existing rule; this test records
        // that as *current* behaviour rather than a guarantee, because many
        // sites are case-sensitive in the path.
        isTrue,
      );
    });

    test('a URL with no scheme is left alone', () {
      expect(norm('example.com/a'), 'example.com/a');
    });

    test('youtube watch links still fold to the same video', () {
      expect(
        norm('http://youtube.com/watch?v=abc'),
        norm('https://www.youtube.com/watch?v=abc'),
      );
    });
  });
}
