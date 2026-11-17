import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/ads/ad_config.dart';
import '../../core/ads/ad_service.dart';
import '../../core/theme/app_palette.dart';

/// Bottom banner ad slot (anchored adaptive sizing).
///
/// Renders nothing until an ad is actually loaded and swallows every plugin
/// error — a missing AdMob runtime (e.g. widget tests on the host VM) must
/// never break the UI.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key});

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _ad;
  bool _requested = false;
  int _requestedWidth = 0;

  /// Incremented for every load attempt so a slow, stale request can tell it
  /// has been superseded (rotation, tab switch, hot reload) and dispose itself
  /// instead of leaking a second registered banner.
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (_requested && width == _requestedWidth) return;
    _requested = true;
    _requestedWidth = width;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!AdConfig.enableBanner || !adsPlatformSupported) return;
    final generation = ++_generation;
    try {
      final width = _requestedWidth;
      final adaptive = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      final AdSize size = adaptive ?? AdSize.banner;
      final ad = BannerAd(
        size: size,
        adUnitId: AdConfig.bannerUnitId,
        request: AdService.instance.request,
        listener: BannerAdListener(
          onAdLoaded: (loaded) {
            final banner = loaded as BannerAd;
            // A newer load (or a disposed widget) owns the slot now.
            if (!mounted || generation != _generation) {
              banner.dispose();
              return;
            }
            final previous = _ad;
            setState(() => _ad = banner);
            previous?.dispose();
          },
          onAdFailedToLoad: (failed, error) => failed.dispose(),
        ),
      );
      await ad.load();
    } catch (e) {
      debugPrint('Banner ad failed: $e');
    }
  }

  @override
  void dispose() {
    // Bump first: an in-flight load will see the stale generation and dispose
    // its own ad instead of calling setState on a dead widget.
    _generation++;
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      height: ad.size.height.toDouble(),
      color: palette.surface,
      alignment: Alignment.center,
      child: AdWidget(ad: ad),
    );
  }
}
