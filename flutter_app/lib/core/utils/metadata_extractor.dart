import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:uuid/uuid.dart';
import '../../domain/entities/mind_item.dart';

class MetadataExtractor {
  static Future<MindItem> extractFromUrl(String rawText) async {
    final cleanUrl = _extractUrlFromText(rawText);
    final uri = Uri.tryParse(cleanUrl);
    final now = DateTime.now();
    final id = const Uuid().v4();

    // 1. YouTube Handler (Videos & Shorts)
    if (cleanUrl.contains('youtube.com') || cleanUrl.contains('youtu.be')) {
      final isShort = cleanUrl.contains('/shorts/');
      final videoId = _extractYouTubeId(cleanUrl);
      String ytThumb = '';
      String ytTitle = isShort ? 'YouTube Short' : 'YouTube Video';
      String author = 'YouTube';
      String description = '';

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

        // Fetch detailed page metadata for accurate description
        try {
          final scraped = await _scrapeOpenGraph(cleanUrl);
          if (scraped['description'] != null && scraped['description']!.isNotEmpty) {
            description = scraped['description']!;
          }
        } catch (_) {}
      }

      if (description.isEmpty) {
        description = 'Video by $author on YouTube. Watch full video on YouTube app.';
      }

      final tags = _generateAccurateTags(
        title: ytTitle,
        description: description,
        rawText: rawText,
        sourceType: isShort ? 'shorts' : 'youtube',
      );

      return MindItem(
        id: id,
        title: ytTitle,
        url: cleanUrl,
        content: description,
        thumbnailUrl: ytThumb.isNotEmpty ? ytThumb : null,
        authorName: author,
        type: ItemType.youtubeVideo,
        tags: tags,
        dominantColorHex: '#FF0000',
        createdAt: now,
        updatedAt: now,
      );
    }

    // 2. Instagram Handler (Reels & Posts)
    if (cleanUrl.contains('instagram.com/reel') || cleanUrl.contains('instagram.com/p/')) {
      String? igThumb;
      String igTitle = 'Instagram Reel';
      String author = 'Instagram';
      String description = '';

      // First attempt: Instagram oEmbed API
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
          description = json['title'] ?? '';
        }
      } catch (_) {}

      // Second attempt: Scrape Open Graph meta tags for real description & title
      try {
        final scraped = await _scrapeOpenGraph(cleanUrl);
        if (scraped['title'] != null && scraped['title']!.isNotEmpty && scraped['title'] != 'Instagram') {
          igTitle = scraped['title']!;
        }
        if (scraped['image'] != null && scraped['image']!.isNotEmpty) {
          igThumb = scraped['image'];
        }
        if (scraped['description'] != null && scraped['description']!.isNotEmpty) {
          description = scraped['description']!;
        }
      } catch (_) {}

      // Fallback clean caption if extracted from raw shared text
      if (description.isEmpty && rawText != cleanUrl) {
        description = rawText.replaceAll(cleanUrl, '').trim();
      }

      if (description.isEmpty) {
        description = igTitle.isNotEmpty && igTitle != 'Instagram Reel'
            ? igTitle
            : 'Saved Instagram Reel by $author. Tap below to watch directly on Instagram.';
      }

      igThumb ??= 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=700&q=80';

      final tags = _generateAccurateTags(
        title: igTitle,
        description: description,
        rawText: rawText,
        sourceType: 'reel',
      );

      return MindItem(
        id: id,
        title: igTitle,
        url: cleanUrl,
        content: description,
        thumbnailUrl: igThumb,
        authorName: author,
        type: ItemType.instagramReel,
        tags: tags,
        dominantColorHex: '#E1306C',
        createdAt: now,
        updatedAt: now,
      );
    }

    // 3. General Web Articles / Links
    try {
      final scraped = await _scrapeOpenGraph(cleanUrl);
      final title = scraped['title'] ?? uri?.host ?? 'Saved Link';
      final description = scraped['description'] ?? 'Article from ${uri?.host}. Tap to view original content.';

      final tags = _generateAccurateTags(
        title: title,
        description: description,
        rawText: rawText,
        sourceType: 'article',
      );

      return MindItem(
        id: id,
        title: title,
        content: description,
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
    final fallbackDescription = rawText.replaceAll(cleanUrl, '').trim();
    final finalDesc = fallbackDescription.isNotEmpty
        ? fallbackDescription
        : 'Bookmark saved from ${uri?.host ?? "external source"}.';

    return MindItem(
      id: id,
      title: uri?.host ?? 'Saved Item',
      url: cleanUrl,
      content: finalDesc,
      type: ItemType.webArticle,
      tags: _generateAccurateTags(
        title: uri?.host ?? 'Link',
        description: finalDesc,
        rawText: rawText,
        sourceType: 'bookmark',
      ),
      dominantColorHex: '#6C757D',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Accurate, Multi-tag Generator (Produces 5 to 8 hyper-relevant tags)
  static List<String> _generateAccurateTags({
    required String title,
    required String description,
    required String rawText,
    required String sourceType,
  }) {
    final Set<String> tags = {};
    final fullCorpus = '$title $description $rawText'.toLowerCase();

    // 1. Explicit hashtags directly from user caption, title or description
    final hashtagRegex = RegExp(r'#(\w{2,25})');
    final matches = hashtagRegex.allMatches('$title $description $rawText');
    for (final match in matches) {
      final tag = match.group(1)!.toLowerCase();
      if (!_isStopWord(tag)) {
        tags.add(tag);
      }
    }

    // 2. High-precision semantic knowledge map
    final Map<String, List<String>> topicMap = {
      'ai': ['ai', 'chatgpt', 'openai', 'claude', 'gemini', 'deepseek', 'gpt', 'llm', 'machine learning', 'robot', 'automation', 'neural'],
      'tech': ['tech', 'technology', 'gadget', 'apple', 'iphone', 'android', 'software', 'hardware', 'app', 'update'],
      'coding': ['code', 'coding', 'flutter', 'dart', 'python', 'javascript', 'react', 'github', 'developer', 'programming', 'backend', 'api'],
      'productivity': ['productivity', 'hack', 'useful', 'tools', 'tips', 'organize', 'workflow', 'time', 'study', 'focus'],
      'design': ['design', 'ui', 'ux', 'figma', 'typography', 'graphic', 'minimal', 'animation', 'aesthetic', 'branding', 'logo'],
      'finance': ['money', 'finance', 'invest', 'crypto', 'stocks', 'business', 'startup', 'wealth', 'earning', 'income', 'trading'],
      'marketing': ['marketing', 'growth', 'seo', 'social media', 'creator', 'monetize', 'viral', 'audience', 'content'],
      'photography': ['camera', 'photo', 'cinematic', 'video', 'editing', 'lightroom', 'visual', 'color grading', 'reels'],
      'mindset': ['motivation', 'mindset', 'habits', 'books', 'psychology', 'philosophy', 'quotes', 'success', 'life'],
      'fitness': ['workout', 'gym', 'health', 'fitness', 'diet', 'exercise', 'muscle', 'yoga', 'protein'],
      'tutorial': ['how to', 'guide', 'tutorial', 'learn', 'step by step', 'course', 'tips & tricks'],
      'news': ['news', 'announcement', 'launch', 'breaking', 'feature'],
    };

    topicMap.forEach((category, keywords) {
      for (final kw in keywords) {
        if (fullCorpus.contains(kw)) {
          tags.add(category);
          break;
        }
      }
    });

    // 3. Extract meaningful key phrases & nouns from Title & Description
    final cleanWords = '$title $description'
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.length >= 4 && !_isStopWord(w));

    for (final word in cleanWords) {
      if (tags.length >= 8) break;
      tags.add(word);
    }

    // 4. Include source type tag (e.g. reel, shorts, article)
    if (!tags.contains(sourceType)) {
      tags.add(sourceType);
    }

    // Return 5 to 8 accurate tags
    return tags.take(8).toList();
  }

  static bool _isStopWord(String word) {
    const stopWords = {
      'this', 'that', 'with', 'from', 'your', 'have', 'more', 'what', 'when',
      'there', 'their', 'which', 'about', 'some', 'only', 'very', 'super',
      'watch', 'share', 'instagram', 'youtube', 'http', 'https', 'www', 'com',
      'video', 'post', 'click', 'link', 'check', 'view', 'full', 'open', 'like',
      'comment', 'subscribe', 'follow', 'reels', 'shorts',
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
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'Accept': 'text/html,application/xhtml+xml',
      },
    ).timeout(const Duration(seconds: 5));

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
        doc.querySelector('meta[name="twitter:description"]')?.attributes['content'] ??
        doc.querySelector('meta[name="description"]')?.attributes['content'];

    final siteName = doc.querySelector('meta[property="og:site_name"]')?.attributes['content'];

    return {
      'title': title?.trim(),
      'image': image?.trim(),
      'description': description?.trim(),
      'siteName': siteName?.trim(),
    };
  }
}
