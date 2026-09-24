/// AdMob configuration for KeepIt.
///
/// The app ships with Google's official **test** ad unit IDs so the whole
/// integration can be verified without an AdMob account. Before releasing:
///
///  1. Replace every ID below with your own (see docs/ADMOB_SETUP.md), and
///  2. Replace the `com.google.android.gms.ads.APPLICATION_ID` meta-data value
///     in `android/app/src/main/AndroidManifest.xml`.
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
  // Ad unit IDs — Google's official TEST units. Replace before release!
  // ---------------------------------------------------------------------------

  /// Also used as the meta-data value in AndroidManifest.xml.
  static const String androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String bannerUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static const String interstitialUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String rewardedUnitId = 'ca-app-pub-3940256099942544/5224354917';

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

  /// True while the IDs above are still Google's test units.
  static bool get usingTestAds =>
      bannerUnitId.startsWith('ca-app-pub-3940256099942544');
}
