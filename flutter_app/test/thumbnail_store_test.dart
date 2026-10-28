import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keepit/core/utils/thumbnail_store.dart';

void main() {
  // A real 1x1 PNG: passes ThumbnailStore's signature sniffing.
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDw'
    'AEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('keepit_thumbs_');
    ThumbnailStore.debugDirectory = tempDir;
  });

  tearDown(() {
    ThumbnailStore.debugDirectory = null;
    ThumbnailStore.debugClient = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('save keeps a permanent copy that fileFor finds again', () async {
    final file = await ThumbnailStore.save('https://x.test/a.jpg', pngBytes);

    expect(file.existsSync(), isTrue);
    final found = await ThumbnailStore.fileFor('https://x.test/a.jpg');
    expect(found, isNotNull);
    expect(await found!.readAsBytes(), pngBytes);
  });

  test('fetch downloads once, stores the file, and dedupes callers', () async {
    var calls = 0;
    ThumbnailStore.debugClient = MockClient((request) async {
      calls += 1;
      return http.Response.bytes(pngBytes, 200);
    });

    final results = await Future.wait(<Future<File?>>[
      ThumbnailStore.fetch('https://x.test/b.jpg'),
      ThumbnailStore.fetch('https://x.test/b.jpg'),
    ]);

    expect(calls, 1);
    expect(results[0], isNotNull);
    expect(results[1]!.path, results[0]!.path);
    final found = await ThumbnailStore.fileFor('https://x.test/b.jpg');
    expect(found, isNotNull);
  });

  test('fetch refuses non-image payloads and HTTP errors', () async {
    ThumbnailStore.debugClient = MockClient((request) async {
      if (request.url.path.endsWith('.html')) {
        return http.Response('<html>gone</html>', 200);
      }
      return http.Response('', 500);
    });

    expect(await ThumbnailStore.fetch('https://x.test/page.html'), isNull);
    expect(await ThumbnailStore.fetch('https://x.test/photo.jpg'), isNull);
    final found = await ThumbnailStore.fileFor('https://x.test/photo.jpg');
    expect(found, isNull);
  });

  test('fetch never calls the client for non-http URLs', () async {
    var calls = 0;
    ThumbnailStore.debugClient = MockClient((request) async {
      calls += 1;
      return http.Response.bytes(pngBytes, 200);
    });

    expect(await ThumbnailStore.fetch('data:image/png;base64,AAAA'), isNull);
    expect(calls, 0);
  });
}
