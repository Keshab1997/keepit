import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keepit/core/utils/metadata_extractor.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// The share/save path had zero tests despite ~750 lines of parsing. These
/// drive [MetadataExtractor.extractFromUrl] end to end against a fake HTTP
/// client, so the branches real share sheets hit are pinned without a network.
void main() {
  /// Routes a request by host+path to a canned response; anything unexpected
  /// fails the test instead of silently reaching the internet.
  http.Client fakeClient({
    Map<String, http.Response> routes = const {},
    List<String>? seen,
  }) {
    return MockClient((request) async {
      seen?.add('${request.method} ${request.url}');
      final key = '${request.url.host}${request.url.path}';
      final response = routes[key];
      if (response == null) {
        fail('unexpected request: ${request.url}');
      }
      return response;
    });
  }

  /// [http.Response] encodes a plain String as latin-1 unless it is told
  /// otherwise; every HTML fixture here may contain emoji or Devanagari.
  http.Response html(String body, [int status = 200]) => http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );

  http.Response json(Object body) => html(jsonEncode(body));

  setUp(MetadataExtractor.resetClient);
  tearDown(MetadataExtractor.resetClient);

  group('extractFromUrl — YouTube', () {
    test('builds a permanent thumbnail and uses oEmbed copy', () async {
      MetadataExtractor.client = fakeClient(routes: {
        'www.youtube.com/oembed': json(
          {'title': 'Flutter in 100 seconds', 'author_name': 'Fireship'},
        ),
        // The page scrape is best-effort; 404 leaves the oEmbed values in place.
        'youtu.be/dQw4w9WgXcQ': html('', 404),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'Look at this https://youtu.be/dQw4w9WgXcQ?si=tracking-id',
      );

      expect(item.type, ItemType.youtubeVideo);
      expect(item.title, 'Flutter in 100 seconds');
      expect(item.authorName, 'Fireship');
      expect(item.thumbnailUrl,
          'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      // Tracking params are part of the saved URL; duplicate detection
      // normalises them away later.
      expect(item.url, contains('dQw4w9WgXcQ'));
      expect(item.dominantColorHex, '#FF0000');
    });

    test('a Short is typed as a reel-ish video and never without a thumbnail',
        () async {
      MetadataExtractor.client = fakeClient(routes: {
        'www.youtube.com/oembed': html('', 500),
        'www.youtube.com/shorts/abc123': html('', 500),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'https://www.youtube.com/shorts/abc123',
      );

      expect(item.type, ItemType.youtubeVideo);
      expect(item.title, isNotEmpty);
      expect(item.thumbnailUrl, contains('/vi/abc123/'));
    });

    test('a bare YouTube URL with no id still produces a usable item',
        () async {
      MetadataExtractor.client = fakeClient();

      final item = await MetadataExtractor.extractFromUrl(
        'https://www.youtube.com/feed/subscriptions',
      );

      expect(item.type, ItemType.youtubeVideo);
      expect(item.title, isNotEmpty);
      expect(item.thumbnailUrl, isNull);
      expect(item.url, 'https://www.youtube.com/feed/subscriptions');
    });
  });

  group('extractFromUrl — Instagram', () {
    test('strips the "12K likes, 45 comments" prefix from the caption',
        () async {
      MetadataExtractor.client = fakeClient(routes: {
        'api.instagram.com/oembed/': html('', 404),
        'www.instagram.com/reel/Cabc123': html('''<html><head>
             <meta property="og:description" content="12K likes, 45 comments - @chef on Sept 20: The best dal recipe nobody talks about" />
             <meta property="og:image" content="https://scontent.cdninstagram.com/signed.jpg" />
           </head></html>'''),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'https://www.instagram.com/reel/Cabc123',
      );

      expect(item.type, ItemType.instagramReel);
      expect(item.title, 'The best dal recipe nobody talks about');
      expect(item.title, isNot(contains('likes')));
      expect(item.content, isNot(contains('likes,')));
      expect(item.authorName, isNotEmpty);
      expect(item.dominantColorHex, '#E1306C');
    });

    test('an image-less Reel gets the fallback poster, never a null thumbnail',
        () async {
      MetadataExtractor.client = fakeClient(routes: {
        'api.instagram.com/oembed/': html('', 404),
        'www.instagram.com/reel/Cxyz789': html('<html></html>'),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'https://www.instagram.com/reel/Cxyz789',
      );

      expect(item.thumbnailUrl, MetadataExtractor.instagramFallbackThumbnail);
      expect(item.title, isNotEmpty);
    });

    test('oEmbed wins over scraping and supplies author + thumbnail', () async {
      MetadataExtractor.client = fakeClient(routes: {
        'api.instagram.com/oembed/': json({
          'author_name': 'chef.keshab',
          'thumbnail_url': 'https://scontent.cdninstagram.com/thumb.jpg',
          'title': 'A reel about mishti doi',
        }),
        'www.instagram.com/p/Cdef456': html('', 500),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'https://www.instagram.com/p/Cdef456',
      );

      expect(item.authorName, 'chef.keshab');
      expect(item.thumbnailUrl, contains('thumb.jpg'));
      expect(item.title, contains('mishti doi'));
    });

    test('a caption of only emoji never crashes the save (grapheme cut)',
        () async {
      final emojiCaption = '🎉' * 40;
      MetadataExtractor.client = fakeClient(routes: {
        'api.instagram.com/oembed/': html('', 404),
        'www.instagram.com/reel/Cemoji': html(
            '<html><head><meta property="og:title" content="$emojiCaption" />'
            '</head></html>'),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'https://www.instagram.com/reel/Cemoji',
      );

      expect(item.title, isNotEmpty);
      // No lone surrogate left behind by the truncation.
      expect(
        item.title.contains(RegExp(r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])')),
        isFalse,
      );
    });
  });

  group('extractFromUrl — web articles', () {
    test('prefers Open Graph title/image/description', () async {
      MetadataExtractor.client = fakeClient(routes: {
        'example.com/articles/one': html('''<html><head>
             <title>Fallback title</title>
             <meta property="og:title" content="How Hive keeps Flutter fast" />
             <meta property="og:description" content="A look at local-first storage." />
             <meta property="og:image" content="https://example.com/cover.png" />
             <meta property="og:site_name" content="Example" />
             <link rel="canonical" href="https://example.com/articles/one?ref=feed" />
           </head></html>'''),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'https://example.com/articles/one',
      );

      expect(item.type, ItemType.webArticle);
      expect(item.title, 'How Hive keeps Flutter fast');
      expect(item.thumbnailUrl, 'https://example.com/cover.png');
      expect(item.authorName, 'Example');
      // The canonical URL is stored, so sharing a tracked link dedupes later.
      expect(item.url, 'https://example.com/articles/one?ref=feed');
    });

    test('falls back to JSON-LD when Open Graph is absent', () async {
      MetadataExtractor.client = fakeClient(routes: {
        'blog.dev/post': html('''<html><head>
             <script type="application/ld+json">
               {"@type":"BlogPosting","headline":"Typed Dart, explained",
                "author":{"name":"Keshab"},"image":{"url":"https://blog.dev/i.png"}}
             </script>
           </head></html>'''),
      });

      final item =
          await MetadataExtractor.extractFromUrl('https://blog.dev/post');

      expect(item.title, 'Typed Dart, explained');
      expect(item.authorName, 'Keshab');
      expect(item.thumbnailUrl, 'https://blog.dev/i.png');
    });

    test('structural JSON-LD nodes are skipped, content nodes are not',
        () async {
      MetadataExtractor.client = fakeClient(routes: {
        'shop.example/item': html('''<html><head>
             <script type="application/ld+json">
               {"@graph":[
                 {"@type":"Organization","name":"Shop Inc"},
                 {"@type":"WebSite","url":"https://shop.example"},
                 {"@type":"Product","name":"Blue widget",
                  "image":"https://shop.example/w.png"}
               ]}
             </script>
           </head></html>'''),
      });

      final item =
          await MetadataExtractor.extractFromUrl('https://shop.example/item');

      // "Shop Inc" (Organization) must not become the title.
      expect(item.title, 'Blue widget');
      expect(item.thumbnailUrl, 'https://shop.example/w.png');
    });

    test('a site that refuses the scrape still saves something useful',
        () async {
      MetadataExtractor.client = fakeClient(routes: {
        'paywall.example/x': html('nope', 403),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'https://paywall.example/x',
      );

      expect(item.type, ItemType.webArticle);
      expect(item.title, 'paywall.example');
      expect(item.url, 'https://paywall.example/x');
      expect(item.tags, isNotEmpty);
    });

    test('trailing punctuation from a share sheet is trimmed off the URL',
        () async {
      MetadataExtractor.client = fakeClient(routes: {
        'example.com/a': html('<html><title>Hello</title></html>'),
      });

      final item = await MetadataExtractor.extractFromUrl(
        'Read this: https://example.com/a).',
      );

      expect(item.url, 'https://example.com/a');
      expect(item.title, 'Hello');
    });

    test('text with no URL at all does not invent one', () async {
      MetadataExtractor.client = fakeClient();

      final item = await MetadataExtractor.extractFromUrl('just a thought');

      expect(item.url, 'just a thought');
      expect(item.type, ItemType.webArticle);
    });
  });

  group('tags', () {
    test('keeps explicit hashtags and adds one semantic category', () async {
      MetadataExtractor.client = fakeClient(routes: {
        'example.com/ai': html('<html><head><meta property="og:title" '
            'content="#flutter Building an AI workflow with ChatGPT" />'
            '</head></html>'),
      });

      final item =
          await MetadataExtractor.extractFromUrl('https://example.com/ai');

      expect(item.tags, contains('flutter'));
      expect(item.tags, contains('ai'));
      // Bounded so a card never carries a wall of tags.
      expect(item.tags.length, lessThanOrEqualTo(8));
      expect(item.tags.toSet().length, item.tags.length, reason: 'no dupes');
    });
  });

  group('tags — word boundaries', () {
    Future<MindItem> saveArticle(String title) async {
      MetadataExtractor.client = fakeClient(routes: {
        'example.com/a': html(
          '<html><head><meta property="og:title" content="$title" />'
          '</head></html>',
        ),
      });
      return MetadataExtractor.extractFromUrl('https://example.com/a');
    }

    test('"email" is not tagged as AI', () async {
      final item = await saveArticle('Email marketing for beginners');
      expect(item.tags, isNot(contains('ai')));
      expect(item.tags, contains('marketing'));
    });

    test('"said" does not tag AI, "AI" does', () async {
      expect(
          (await saveArticle('Said no one ever')).tags, isNot(contains('ai')));
      expect((await saveArticle('AI agents in 2026')).tags, contains('ai'));
    });

    test('multi-word keywords still match as phrases', () async {
      expect((await saveArticle('How to budget every month')).tags,
          contains('tutorial'));
    });
  });

  group('timestamps', () {
    test('saved items carry UTC instants, so a round-trip keeps the moment',
        () async {
      MetadataExtractor.client = fakeClient(routes: {
        'example.com/utc': html('<html><title>Instant</title></html>'),
      });
      final before = DateTime.now().toUtc();
      final item =
          await MetadataExtractor.extractFromUrl('https://example.com/utc');
      final after = DateTime.now().toUtc();

      expect(item.createdAt.isUtc, isTrue);
      expect(item.updatedAt.isUtc, isTrue);
      expect(item.createdAt.isBefore(before), isFalse);
      expect(item.createdAt.isAfter(after), isFalse);

      // The bug: a local stamp serialised without a designator came back as a
      // *different* instant (and in local time). Round-tripping must not move
      // the moment at all.
      final restored = MindItem.fromMap(item.toMap());
      expect(restored.createdAt.isAtSameMomentAs(item.createdAt), isTrue);
      expect(restored.createdAt.isUtc, isTrue);
    });
  });

  group('public helpers', () {
    test('youtubeVideoId understands every share shape', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ?t=10',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
        'https://www.youtube.com/v/dQw4w9WgXcQ',
      ]) {
        expect(MetadataExtractor.youtubeVideoId(url), 'dQw4w9WgXcQ',
            reason: url);
      }
      expect(MetadataExtractor.youtubeVideoId('https://example.com'), isNull);
    });

    test('isExpiringThumbnailHost flags signed CDN links only', () {
      expect(
        MetadataExtractor.isExpiringThumbnailHost(
          'https://scontent.cdninstagram.com/v/t51/abc.jpg',
        ),
        isTrue,
      );
      expect(
        MetadataExtractor.isExpiringThumbnailHost(
            'https://img.youtube.com/vi/x/hq.jpg'),
        isFalse,
      );
      expect(MetadataExtractor.isExpiringThumbnailHost(null), isFalse);
      expect(MetadataExtractor.isExpiringThumbnailHost(''), isFalse);
    });

    test('cleanTitle drops the site suffix and never returns empty', () {
      expect(MetadataExtractor.cleanTitle('  A title | YouTube '), 'A title');
      expect(MetadataExtractor.cleanTitle('Something - Medium'), 'Something');
      expect(MetadataExtractor.cleanTitle('Song – YouTube'), 'Song');
      expect(MetadataExtractor.cleanTitle('Photo — Instagram'), 'Photo');
      expect(MetadataExtractor.cleanTitle('Read · Medium'), 'Read');
      expect(MetadataExtractor.cleanTitle('   '), 'Saved Item');
    });
  });
}
