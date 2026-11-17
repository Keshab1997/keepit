import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/utils/metadata_extractor.dart';
import 'package:keepit/core/utils/thumbnail_repair.dart';

void main() {
  setUp(ThumbnailRepair.resetSessionState);

  group('expiring thumbnail hosts', () {
    test('flags Instagram and other signed CDN links', () {
      expect(
        MetadataExtractor.isExpiringThumbnailHost(
          'https://scontent.cdninstagram.com/v/t51.1234-15/abc.jpg?oe=1',
        ),
        isTrue,
      );
      expect(
        MetadataExtractor.isExpiringThumbnailHost(
          'https://scontent.xx.fbcdn.net/v/t39.30808-6/123_n.jpg',
        ),
        isTrue,
      );
    });

    test('leaves stable hosts alone', () {
      expect(
        MetadataExtractor.isExpiringThumbnailHost(
          'https://img.youtube.com/vi/abc123/hqdefault.jpg',
        ),
        isFalse,
      );
      expect(
        MetadataExtractor.isExpiringThumbnailHost(
          'https://images.unsplash.com/photo-1618005182384',
        ),
        isFalse,
      );
      expect(MetadataExtractor.isExpiringThumbnailHost(null), isFalse);
    });
  });

  group('youtube recovery', () {
    test('rebuilds the permanent still from the video id', () {
      final id = MetadataExtractor.youtubeVideoId(
        'https://www.youtube.com/shorts/dQw4w9WgXcQ?feature=share',
      );
      expect(id, 'dQw4w9WgXcQ');
      expect(
        MetadataExtractor.permanentYoutubeThumbnail(id!),
        'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
    });

    test('handles watch and short URLs', () {
      expect(
        MetadataExtractor.youtubeVideoId(
          'https://www.youtube.com/watch?v=abc123XYZ_',
        ),
        'abc123XYZ_',
      );
      expect(
        MetadataExtractor.youtubeVideoId('https://youtu.be/xyz789'),
        'xyz789',
      );
      expect(MetadataExtractor.youtubeVideoId('https://example.com'), isNull);
    });
  });

  group('failure marking', () {
    test('reports a new failure once per item and URL', () {
      const url = 'https://scontent.cdninstagram.com/expired.jpg';
      expect(ThumbnailRepair.markFailed('item-1', url), isTrue);
      expect(ThumbnailRepair.markFailed('item-1', url), isFalse);
    });

    test('tracks items separately', () {
      const url = 'https://example.com/shared.jpg';
      expect(ThumbnailRepair.markFailed('item-1', url), isTrue);
      expect(ThumbnailRepair.markFailed('item-2', url), isTrue);
    });

    test('a repaired URL is not treated as already failed', () {
      const dead = 'https://scontent.cdninstagram.com/old.jpg';
      const fresh = 'https://example.com/new.jpg';
      ThumbnailRepair.markFailed('item-1', dead);
      expect(ThumbnailRepair.markFailed('item-1', fresh), isTrue);
    });
  });
}
