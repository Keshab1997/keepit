import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive/hive.dart';

import 'ad_config.dart';

/// Ads only ship in the Android build right now (iOS is not published yet).
///
/// This also keeps widget tests — which run on the host VM, not Android —
/// free of platform-channel calls.
bool get adsPlatformSupported => Platform.isAndroid;

/// AdMob lifecycle + frequency-capped ad delivery.
///
/// Placement rules (deliberately UX-first):
/// * **Banner** — bottom of the content tabs, never over the Profile tab
///   (rendered by `BannerAdSlot`).
/// * **Interstitial** — only right after a *successful save* (a natural
///   "reward moment"), capped by [AdConfig.savesBetweenInterstitials] saves
///   and [AdConfig.minInterstitialInterval].
/// * **Rewarded** — only when the user explicitly taps "Support KeepIt".
///
/// Every plugin call is guarded, so a missing/unsupported AdMob runtime can
/// never crash the app.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  Box? _prefs;
  bool _initialized = false;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;
  bool _showingInterstitial = false;

  int _savesSinceInterstitial = 0;
  DateTime? _lastInterstitialAt;

  static const _kSavesSince = 'ads_saves_since_interstitial';
  static const _kLastInterstitialAt = 'ads_last_interstitial_at';

  /// Non-personalized unless explicitly enabled in [AdConfig].
  AdRequest get request =>
      AdRequest(nonPersonalizedAds: !AdConfig.personalizedAds);

  /// Call once during startup. [prefs] (the Hive meta box) persists the
  /// frequency counters across launches; pass `null` for memory-only caps.
  Future<void> init({Box? prefs}) async {
    _prefs = prefs;
    if (!AdConfig.adsEnabled) return;
    _restoreCounters();
    if (!adsPlatformSupported) return;
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('AdMob initialize failed: $e');
      return;
    }
    _initialized = true;
    if (AdConfig.enableInterstitial) _preloadInterstitial();
    if (AdConfig.enableRewarded) _preloadRewarded();
  }

  void _restoreCounters() {
    _savesSinceInterstitial = (_prefs?.get(_kSavesSince) as int?) ?? 0;
    final last = _prefs?.get(_kLastInterstitialAt) as int?;
    _lastInterstitialAt =
        last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
  }

  Future<void> _persistCounters() async {
    try {
      await _prefs?.put(_kSavesSince, _savesSinceInterstitial);
      final last = _lastInterstitialAt;
      if (last != null) {
        await _prefs?.put(_kLastInterstitialAt, last.millisecondsSinceEpoch);
      }
    } catch (_) {
      // Prefs are best-effort — in-memory caps still apply.
    }
  }

  // ---------------------------------------------------------------------------
  // Interstitial
  // ---------------------------------------------------------------------------

  void _preloadInterstitial() {
    if (!_initialized || _loadingInterstitial || _interstitial != null) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: request,
      adLoadCallback: AdLoadCallback<InterstitialAd>(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loadingInterstitial = false;
        },
        onAdFailedToLoad: (error) {
          _interstitial = null;
          _loadingInterstitial = false;
        },
      ),
    );
  }

  /// Called after every successful save. The interstitial is a reward-moment
  /// ad: it appears once the user accomplished something, and only when the
  /// conservative frequency caps allow it.
  void onItemSaved() {
    if (!_initialized || !AdConfig.enableInterstitial) return;
    _savesSinceInterstitial++;
    _persistCounters();
    if (!_canShowInterstitial) return;
    Future.delayed(AdConfig.interstitialDelay, () {
      if (_canShowInterstitial && _interstitial != null) {
        _showInterstitial();
      }
    });
  }

  bool get _canShowInterstitial {
    if (!_initialized || !AdConfig.enableInterstitial) return false;
    if (_interstitial == null || _showingInterstitial) return false;
    if (_savesSinceInterstitial < AdConfig.savesBetweenInterstitials) {
      return false;
    }
    final last = _lastInterstitialAt;
    if (last != null &&
        DateTime.now().difference(last) < AdConfig.minInterstitialInterval) {
      return false;
    }
    return true;
  }

  Future<void> _showInterstitial() async {
    final ad = _interstitial;
    if (ad == null) return;
    _interstitial = null;
    _showingInterstitial = true;
    _lastInterstitialAt = DateTime.now();
    _savesSinceInterstitial = 0;
    await _persistCounters();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showingInterstitial = false;
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _showingInterstitial = false;
        _preloadInterstitial();
      },
    );
    try {
      await ad.show();
    } catch (e) {
      debugPrint('Interstitial show failed: $e');
      _showingInterstitial = false;
      ad.dispose();
      _preloadInterstitial();
    }
  }

  // ---------------------------------------------------------------------------
  // Rewarded (opt-in "Support KeepIt")
  // ---------------------------------------------------------------------------

  void _preloadRewarded() {
    if (!_initialized || _loadingRewarded || _rewarded != null) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AdConfig.rewardedUnitId,
      request: request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loadingRewarded = false;
        },
        onAdFailedToLoad: (error) {
          _rewarded = null;
          _loadingRewarded = false;
        },
      ),
    );
  }

  /// Shows a rewarded ad. Returns `true` when the user watched long enough to
  /// earn the reward, `false` when no ad was available.
  Future<bool> showRewarded() async {
    if (!_initialized || !AdConfig.enableRewarded) return false;
    final ad = _rewarded;
    if (ad == null) {
      _preloadRewarded();
      return false;
    }
    _rewarded = null;
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _preloadRewarded();
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, __) {
        earned = true;
      });
    } catch (e) {
      debugPrint('Rewarded show failed: $e');
      ad.dispose();
      _preloadRewarded();
      return false;
    }
    return earned;
  }
}
