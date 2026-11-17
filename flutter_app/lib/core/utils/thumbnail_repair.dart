import 'package:flutter/foundation.dart';

import '../../domain/entities/mind_item.dart';
import '../../presentation/controllers/mind_feed_controller.dart';
import 'metadata_extractor.dart';

/// Heals thumbnails that die over time.
///
/// A saved thumbnail URL is not ours: Instagram serves signed CDN links that
/// expire within days, and many sites hand out a per-session `og:image` that
/// starts returning 403/404 hours after the card was saved. The card then has a
/// URL, fails to load it, and shows the grey image placeholder forever — the
/// "old links lost their thumbnail" bug.
///
/// [repair] is called when the card widget sees a load error, and [repairAll]
/// sweeps the feed once per launch. Both only touch items whose thumbnail is
/// known to be broken, and only write when the new value is actually different,
/// so a working image is never re-fetched or overwritten.
class ThumbnailRepair {
  ThumbnailRepair._();

  /// Per-session memory of URLs that failed to load, per item. Keeps a whole
  /// masonry column from firing the same doomed request on every rebuild.
  static final Set<String> _attempted = <String>{};

  /// Same-origin re-scrape results, cached so several cards from one site pay
  /// for a single HTML fetch.
  static final Map<String, String?> _scrapeCache = <String, String?>{};

  /// A card whose image just failed: find it, then try to give it a live URL.
  static Future<void> repair(
    MindFeedController controller,
    String itemId,
  ) async {
    final item = _findById(controller.items, itemId);
    if (item == null) return;

    final fresh = await _freshThumbnailFor(item, failedUrl: item.thumbnailUrl);
    if (fresh == null || fresh == item.thumbnailUrl) return;

    await controller.replaceThumbnail(item.id, fresh);
  }

  /// One pass over the feed at startup: repair everything we already know is
  /// broken, concurrency-bounded so a cold launch never opens a burst of
  /// sockets across the whole library.
  static Future<void> repairAll(MindFeedController controller) async {
    // The feed loads from Hive asynchronously; without this the sweep would
    // inspect an empty list and do nothing.
    await controller.ready;
    if (_attempted.isEmpty) return;

    final targets = controller.items
        .where(
          (item) =>
              item.thumbnailUrl != null &&
              _attempted.contains(_key(item.id, item.thumbnailUrl!)),
        )
        .toList();

    for (var i = 0; i < targets.length; i += 3) {
      final slice = targets.skip(i).take(3);
      await Future.wait(slice.map((item) => repair(controller, item.id)));
    }
  }

  /// Records that [url] failed for [itemId]. The widget calls this from its
  /// error builder; [alreadyAttempted] lets it avoid asking for a repair twice
  /// for the same URL within one session.
  static bool markFailed(String itemId, String url) {
    final key = _key(itemId, url);
    if (_attempted.contains(key)) return false;
    _attempted.add(key);
    return true;
  }

  /// Forgets failure marks — used by tests and after a successful save.
  @visibleForTesting
  static void resetSessionState() {
    _attempted.clear();
    _scrapeCache.clear();
  }

  static String _key(String itemId, String url) => '$itemId|$url';

  static MindItem? _findById(List<MindItem> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Fresh URL lookup, cheapest path first
  // ---------------------------------------------------------------------------
  static Future<String?> _freshThumbnailFor(
    MindItem item, {
    required String? failedUrl,
  }) async {
    // 1. Video thumbnails are deterministic: YouTube's still-image route is
    //    unsigned and permanent, so it never needs the network to recover.
    if (item.type == ItemType.youtubeVideo) {
      final videoId = MetadataExtractor.youtubeVideoId(item.url ?? '');
      if (videoId != null) {
        return MetadataExtractor.permanentYoutubeThumbnail(videoId);
      }
    }

    // 2. Instagram's CDN link cannot be renewed from the app (that needs an
    //    authenticated Graph call), so reuse the same public fallback the
    //    extractor already relies on for caption-only saves.
    if (item.type == ItemType.instagramReel &&
        MetadataExtractor.isExpiringThumbnailHost(failedUrl)) {
      return MetadataExtractor.instagramFallbackThumbnail;
    }

    // 3. Articles: re-read the page's Open Graph image. It is usually still
    //    valid even when the URL saved months ago is not — sites rotate the
    //    signed part, and the fresh scrape hands us the new one.
    if (item.url != null && item.url!.isNotEmpty) {
      final url = item.url!;
      final cached = _scrapeCache.containsKey(url)
          ? _scrapeCache[url]
          : await _scrapeAndCache(url);
      if (cached != null && cached.isNotEmpty && cached != failedUrl) {
        return cached;
      }
    }

    return null;
  }

  static Future<String?> _scrapeAndCache(String url) async {
    try {
      final scraped = await MetadataExtractor.scrapeOpenGraph(url);
      final image = scraped['image'];
      _scrapeCache[url] = image;
      return image;
    } catch (_) {
      _scrapeCache[url] = null;
      return null;
    }
  }
}
