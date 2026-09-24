import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/ads/ad_config.dart';
import '../../core/ads/ad_service.dart';
import '../../core/theme/app_colors.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _load();
    }
  }

  Future<void> _load() async {
    if (!AdConfig.enableBanner || !adsPlatformSupported) return;
    try {
      final width = MediaQuery.of(context).size.width.truncate();
      final adaptive =
          await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      final AdSize size = adaptive ?? AdSize.banner;
      final ad = BannerAd(
        size: size,
        adUnitId: AdConfig.bannerUnitId,
        request: AdService.instance.request,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() => _ad = ad);
          },
          onAdFailedToLoad: (ad, error) => ad.dispose(),
        ),
      );
      await ad.load();
    } catch (e) {
      debugPrint('Banner ad failed: $e');
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      height: ad.size.height.toDouble(),
      color: AppColors.surface,
      alignment: Alignment.center,
      child: AdWidget(ad: ad),
    );
  }
}
