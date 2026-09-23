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

    // 2. YouTube Handler
    if (cleanUrl.contains('youtube.com') || cleanUrl.contains('youtu.be')) {
      final isShort = cleanUrl.contains('/shorts/');
      final videoId = _extractYouTubeId(cleanUrl);
      String? ytThumb;
      String ytTitle = isShort ? 'YouTube Short' : 'YouTube Video';
      String author = 'YouTube';

      if (videoId != null) {
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

      final tags = _generateContextualTags(
        title: ytTitle,
        content: author,
        url: cleanUrl,
        defaultType: isShort ? 'shorts' : 'youtube',
      );

      return MindItem(
        id: id,
        title: ytTitle,
        url: cleanUrl,
        thumbnailUrl: ytThumb,
        authorName: author,
        type: ItemType.youtubeVideo,
        tags: tags,
        dominantColorHex: '#FF0000',
        createdAt: now,
        updatedAt: now,
      );
    }

    // 3. Instagram Handler
    if (cleanUrl.contains('instagram.com/reel') || cleanUrl.contains('instagram.com/p/')) {
      String? igThumb;
      String igTitle = 'Instagram Reel';
      String author = 'Instagram';
      String description = '';

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
          description = igTitle;
        }
      } catch (_) {}

      if (igThumb == null || igTitle == 'Instagram Reel') {
        try {
          final scraped = await _scrapeOpenGraph(cleanUrl);
          igThumb ??= scraped['image'];
          if (scraped['title'] != null && scraped['title']!.isNotEmpty) {
            igTitle = scraped['title']!;
          }
          if (scraped['description'] != null) {
            description = scraped['description']!;
          }
        } catch (_) {}
      }

      igThumb ??= 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=700&q=80';

      final tags = _generateContextualTags(
        title: igTitle,
        content: '$description $rawText',
        url: cleanUrl,
        defaultType: 'reel',
      );

      return MindItem(
        id: id,
        title: igTitle,
        url: cleanUrl,
        content: description.isNotEmpty ? description : null,
        thumbnailUrl: igThumb,
        authorName: author,
        type: ItemType.instagramReel,
        tags: tags,
        dominantColorHex: '#E1306C',
        createdAt: now,
        updatedAt: now,
      );
    }

    // 4. General Web Articles / Links
    try {
      final scraped = await _scrapeOpenGraph(cleanUrl);
      final title = scraped['title'] ?? uri?.host ?? 'Saved Link';
      final description = scraped['description'] ?? '';

      final tags = _generateContextualTags(
        title: title,
        content: description,
        url: cleanUrl,
        defaultType: 'article',
      );

      return MindItem(
        id: id,
        title: title,
        content: description.isNotEmpty ? description : null,
        url: cleanUrl,
        thumbnailUrl: scraped['image'],
        authorName: scraped['siteName'] ?? uri?.host ?? 'Web',
        type: ItemType.webArticle,
        tags: tags,
        dominantColorHex: '#4A90E2',
        createdAt: now,
        updatedAt: now,
      );
    } catch (_) {}

    // Fallback item
    final fallbackTags = _generateContextualTags(
      title: uri?.host ?? 'Link',
      content: rawText,
      url: cleanUrl,
      defaultType: 'bookmark',
    );

    return MindItem(
      id: id,
      title: uri?.host ?? 'Saved Item',
      url: cleanUrl,
      type: ItemType.webArticle,
      tags: fallbackTags,
      dominantColorHex: '#6C757D',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// AI / Natural Language Smart Tagging Engine
  /// Analyzes titles, captions, hashtags, and keywords to produce relevant tags
  static List<String> _generateContextualTags({
    required String title,
    required String content,
    required String url,
    required String defaultType,
  }) {
    final Set<String> tags = {};
    final combinedText = '$title $content $url'.toLowerCase();

    // 1. Extract raw hashtags if present in title/caption (e.g. #productivity, #flutter)
    final hashtagRegex = RegExp(r'#(\w{3,20})');
    final matches = hashtagRegex.allMatches('$title $content');
    for (final match in matches) {
      final tag = match.group(1)!.toLowerCase();
      if (!_isStopWord(tag)) {
        tags.add(tag);
      }
    }

    // 2. Keyword Classification Dictionary (Smart Second-Brain Categorization)
    final Map<String, List<String>> keywordDictionary = {
      'ai': ['ai', 'chatgpt', 'openai', 'claude', 'gemini', 'gpt', 'llm', 'machine learning', 'robot', 'automation'],
      'coding': ['code', 'coding', 'flutter', 'dart', 'python', 'javascript', 'react', 'github', 'developer', 'software'],
      'design': ['design', 'ui', 'ux', 'figma', 'typography', 'creative', 'graphic', 'color', 'minimal', 'animation'],
      'productivity': ['productivity', 'hack', 'useful', 'tools', 'tips', 'organize', 'workflow', 'time', 'study'],
      'finance': ['money', 'finance', 'invest', 'crypto', 'stocks', 'business', 'startup', 'wealth', 'passive income'],
      'fitness': ['workout', 'gym', 'health', 'fitness', 'diet', 'exercise', 'muscle', 'yoga'],
      'photography': ['camera', 'photo', 'cinematic', 'video', 'editing', 'lightroom', 'visual'],
      'marketing': ['marketing', 'growth', 'seo', 'social media', 'creator', 'branding', 'audience'],
      'mindset': ['motivation', 'mindset', 'habits', 'books', 'psychology', 'philosophy', 'quotes'],
      'tech': ['tech', 'technology', 'gadgets', 'android', 'apple', 'ios', 'system'],
    };

    keywordDictionary.forEach((category, keywords) {
      for (final kw in keywords) {
        if (combinedText.contains(kw)) {
          tags.add(category);
          break;
        }
      }
    });

    // 3. Extract meaningful nouns / words from Title (if few tags found)
    if (tags.length < 3) {
      final words = title
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3 && !_isStopWord(w.toLowerCase()))
          .take(3);

      for (final w in words) {
        tags.add(w.toLowerCase());
      }
    }

    // 4. Ensure at least the primary content type is present
    if (tags.isEmpty) {
      tags.add(defaultType);
    }

    // Return top 4-5 unique relevant tags
    return tags.take(5).toList();
  }

  static bool _isStopWord(String word) {
    const stopWords = {
      'this', 'that', 'with', 'from', 'your', 'have', 'more', 'what', 'when',
      'video', 'reel', 'post', 'instagram', 'youtube', 'http', 'https', 'www',
      'com', 'about', 'some', 'only', 'very', 'super', 'watch', 'share',
    };
    return stopWords.contains(word);
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
