import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:uuid/uuid.dart';
import '../../domain/entities/mind_item.dart';

class MetadataExtractor {
  static Future<MindItem> extractFromUrl(String rawText) async {
    // 1. Extract pure URL if shared text contains captions or extra words
    final cleanUrl = _extractUrlFromText(rawText);
    final uri = Uri.tryParse(cleanUrl);
    final now = DateTime.now();
    final id = const Uuid().v4();

    // 2. Specialized Handler: YouTube Video / Shorts (High-res thumbnails & oEmbed)
    if (cleanUrl.contains('youtube.com') || cleanUrl.contains('youtu.be')) {
      final isShort = cleanUrl.contains('/shorts/');
      final videoId = _extractYouTubeId(cleanUrl);
      String? ytThumb;
      String ytTitle = isShort ? 'YouTube Short' : 'YouTube Video';
      String author = 'YouTube';

      if (videoId != null) {
        // High Quality YouTube Thumbnail
        ytThumb = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
        try {
          final oembedRes = await http.get(
            Uri.parse('https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json'),
          ).timeout(const Duration(seconds: 4));
          if (oembedRes.statusCode == 200) {
            final json = jsonDecode(oembedRes.body);
            ytTitle = json['title'] ?? ytTitle;
            author = json['author_name'] ?? author;
          }
        } catch (_) {}
      }

      return MindItem(
        id: id,
        title: ytTitle,
        url: cleanUrl,
        thumbnailUrl: ytThumb,
        authorName: author,
        type: ItemType.youtubeVideo,
        tags: [isShort ? 'shorts' : 'video', 'youtube'],
        dominantColorHex: '#FF0000',
        createdAt: now,
        updatedAt: now,
      );
    }

    // 3. Specialized Handler: Instagram Reel / Post
    if (cleanUrl.contains('instagram.com/reel') || cleanUrl.contains('instagram.com/p/')) {
      String? igThumb;
      String igTitle = 'Instagram Reel';
      String author = 'Instagram';

      // Method A: Query Instagram oEmbed endpoint
      try {
        final oembedUri = Uri.parse(
          'https://api.instagram.com/oembed/?url=${Uri.encodeComponent(cleanUrl)}',
        );
        final oembedRes = await http.get(oembedUri).timeout(const Duration(seconds: 4));
        if (oembedRes.statusCode == 200) {
          final json = jsonDecode(oembedRes.body);
          igTitle = json['title'] ?? igTitle;
          author = json['author_name'] ?? author;
          igThumb = json['thumbnail_url'];
        }
      } catch (_) {}

      // Method B: OpenGraph scrape if oEmbed did not return thumbnail
      if (igThumb == null) {
        try {
          final scraped = await _scrapeOpenGraph(cleanUrl);
          igThumb = scraped['image'];
          if (scraped['title'] != null && scraped['title']!.isNotEmpty) {
            igTitle = scraped['title']!;
          }
        } catch (_) {}
      }

      // Method C: Curated high-res aesthetic placeholder if Instagram blocks scraping
      igThumb ??= 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=700&q=80';

      return MindItem(
        id: id,
        title: igTitle,
        url: cleanUrl,
        thumbnailUrl: igThumb,
        authorName: author,
        type: ItemType.instagramReel,
        tags: ['reel', 'instagram', 'inspiration'],
        dominantColorHex: '#E1306C',
        createdAt: now,
        updatedAt: now,
      );
    }

    // 4. Universal Web & Article Scraping (OpenGraph, Twitter Cards, Microdata)
    try {
      final scraped = await _scrapeOpenGraph(cleanUrl);
      return MindItem(
        id: id,
        title: scraped['title'] ?? uri?.host ?? 'Saved Link',
        content: scraped['description'],
        url: cleanUrl,
        thumbnailUrl: scraped['image'],
        authorName: scraped['siteName'] ?? uri?.host ?? 'Web',
        type: ItemType.webArticle,
        tags: ['article', if (uri?.host != null) uri!.host.split('.').first],
        dominantColorHex: '#4A90E2',
        createdAt: now,
        updatedAt: now,
      );
    } catch (_) {}

    // Fallback if network fails
    return MindItem(
      id: id,
      title: uri?.host ?? 'Saved Item',
      url: cleanUrl,
      type: ItemType.webArticle,
      tags: ['bookmark'],
      dominantColorHex: '#6C757D',
      createdAt: now,
      updatedAt: now,
    );
  }

  static String _extractUrlFromText(String text) {
    final urlRegex = RegExp(r'(https?://[^\s]+)');
    final match = urlRegex.firstMatch(text);
    if (match != null) {
      return match.group(0)!;
    }
    return text.trim();
  }

  static String? _extractYouTubeId(String url) {
    final regExp = RegExp(
      r'(?:v=|\/shorts\/|youtu\.be\/|\/v\/|\/embed\/)([^#&?]+)',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  static Future<Map<String, String?>> _scrapeOpenGraph(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
        'Accept': 'text/html,application/xhtml+xml',
      },
    ).timeout(const Duration(seconds: 4));

    if (response.statusCode != 200) {
      return {};
    }

    final doc = html_parser.parse(response.body);

    final title = doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
        doc.querySelector('meta[name="twitter:title"]')?.attributes['content'] ??
        doc.querySelector('title')?.text;

    final image = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
        doc.querySelector('meta[name="twitter:image"]')?.attributes['content'] ??
        doc.querySelector('meta[property="og:image:url"]')?.attributes['content'];

    final description = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ??
        doc.querySelector('meta[name="twitter:description"]')?.attributes['content'];

    final siteName = doc.querySelector('meta[property="og:site_name"]')?.attributes['content'];

    return {
      'title': title?.trim(),
      'image': image?.trim(),
      'description': description?.trim(),
      'siteName': siteName?.trim(),
    };
  }
}
