/// AdMob configuration for KeepIt.
///
/// Live production IDs (see docs/ADMOB_SETUP.md). To test without serving
/// real ads, temporarily swap these with Google's official test IDs.
///
/// Frequency caps are deliberately conservative: ads must never get in the
/// way of saving an idea.
class AdConfig {
  AdConfig._();

  /// Master switch — set to `false` to ship a completely ad-free build.
  static const bool adsEnabled = true;

  /// Individual formats.
  static const bool enableBanner = true;
  static const bool enableInterstitial = true;
  static const bool enableRewarded = true;

  // ---------------------------------------------------------------------------
  // Ad unit IDs — LIVE production units (ca-app-pub-4216917764852377).
  // ---------------------------------------------------------------------------

  /// Also used as the meta-data value in AndroidManifest.xml.
  static const String androidAppId = 'ca-app-pub-4216917764852377~9499831430';
  static const String bannerUnitId = 'ca-app-pub-4216917764852377/7198025168';
  static const String interstitialUnitId =
      'ca-app-pub-4216917764852377/5884943495';
  static const String rewardedUnitId = 'ca-app-pub-4216917764852377/8263694824';

  // ---------------------------------------------------------------------------
  // Frequency caps (UX first)
  // ---------------------------------------------------------------------------

  /// An interstitial may only appear after this many *successful* saves.
  static const int savesBetweenInterstitials = 8;

  /// ...and never more often than this, no matter how fast items are saved.
  static const Duration minInterstitialInterval = Duration(hours: 3);

  /// Small pause after a save so the "Saved!" toast stays readable first.
  static const Duration interstitialDelay = Duration(milliseconds: 800);

  /// `false` = non-personalized ads (privacy-first default; no consent SDK
  /// required). Flip to `true` only once a UMP/consent flow is in place.
  static const bool personalizedAds = false;

  /// True if the IDs above are NOT the production publisher ID.
  /// Currently false — live IDs in use.
  static bool get usingTestAds =>
      !bannerUnitId.startsWith('ca-app-pub-4216917764852377');
}
