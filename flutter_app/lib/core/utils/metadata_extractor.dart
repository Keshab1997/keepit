import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:uuid/uuid.dart';
import '../../domain/entities/mind_item.dart';

class MetadataExtractor {
  static Future<MindItem> extractFromUrl(String url) async {
    final cleanUrl = url.trim();
    final uri = Uri.tryParse(cleanUrl);
    final now = DateTime.now();
    final id = const Uuid().v4();

    // 1. Detect Instagram Reel / Post
    if (cleanUrl.contains('instagram.com/reel') || cleanUrl.contains('instagram.com/p/')) {
      return MindItem(
        id: id,
        title: 'Instagram Reel',
        url: cleanUrl,
        authorName: 'Instagram Creator',
        type: ItemType.instagramReel,
        tags: ['reel', 'instagram', 'saved'],
        dominantColorHex: '#E1306C',
        createdAt: now,
        updatedAt: now,
      );
    }

    // 2. Detect YouTube Short / Video
    if (cleanUrl.contains('youtube.com') || cleanUrl.contains('youtu.be')) {
      final isShort = cleanUrl.contains('/shorts/');
      return MindItem(
        id: id,
        title: isShort ? 'YouTube Short' : 'YouTube Video',
        url: cleanUrl,
        authorName: 'YouTube Creator',
        type: ItemType.youtubeVideo,
        tags: [isShort ? 'short' : 'video', 'youtube'],
        dominantColorHex: '#FF0000',
        createdAt: now,
        updatedAt: now,
      );
    }

    // 3. Fallback to OpenGraph / HTML scraping for general web articles
    try {
      final response = await http.get(
        uri!,
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X)',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        
        // Extract Title
        final ogTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'];
        final docTitle = document.querySelector('title')?.text;
        final title = ogTitle ?? docTitle ?? uri.host;

        // Extract Description
        final ogDesc = document.querySelector('meta[property="og:description"]')?.attributes['content'];

        // Extract Thumbnail
        final ogImage = document.querySelector('meta[property="og:image"]')?.attributes['content'];

        // Extract Site Name
        final siteName = document.querySelector('meta[property="og:site_name"]')?.attributes['content'] ?? uri.host;

        return MindItem(
          id: id,
          title: title.trim(),
          content: ogDesc?.trim(),
          url: cleanUrl,
          thumbnailUrl: ogImage,
          authorName: siteName,
          type: ItemType.webArticle,
          tags: ['article', uri.host.split('.').first],
          dominantColorHex: '#4A90E2',
          createdAt: now,
          updatedAt: now,
        );
      }
    } catch (_) {
      // Offline or request failed: create fallback item instantly
    }

    // Instant local fallback
    return MindItem(
      id: id,
      title: uri?.host ?? 'Saved Link',
      url: cleanUrl,
      type: ItemType.webArticle,
      tags: ['bookmark'],
      dominantColorHex: '#6C757D',
      createdAt: now,
      updatedAt: now,
    );
  }
}
