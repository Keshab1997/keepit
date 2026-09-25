/// AdMob configuration for KeepIt.
///
/// The real AdMob IDs are **not** in this file and must never be committed.
/// They are injected at release time through the CI workflow:
///
///   * `ADMOB_ENABLED=true`        — master switch (off without it)
///   * `ADMOB_APP_ID`              — also fed to Gradle for the manifest
///   * `ADMOB_BANNER_ID`
///   * `ADMOB_INTERSTITIAL_ID`
///   * `ADMOB_REWARDED_ID`
///
/// Every value has an empty default, so a plain `flutter run`, a CI check or a
/// fork build produces an **ad-free** app that never talks to AdMob. That is
/// deliberate: a checkout without the release secrets must not ship someone
/// else's ad units, and must not ship Google's test units either (the release
/// gate in the shared builder fails the build when test IDs are in `lib/`).
///
/// See `docs/SECRETS_SETUP.md` for the one-time repository configuration.
///
/// Frequency caps are deliberately conservative: ads must never get in the
/// way of saving an idea.
class AdConfig {
  AdConfig._();

  /// Master switch. Compile-time only: `--dart-define=ADMOB_ENABLED=true`.
  ///
  /// Defaults to `false` so every build that did not receive the release
  /// secrets is ad-free.
  static const bool adsEnabled =
      bool.fromEnvironment('ADMOB_ENABLED', defaultValue: false);

  /// Individual formats. Each one is off unless the whole stack is enabled.
  static const bool _enableBanner = true;
  static const bool _enableInterstitial = true;
  static const bool _enableRewarded = true;

  static bool get enableBanner => adsEnabled && _enableBanner;
  static bool get enableInterstitial => adsEnabled && _enableInterstitial;
  static bool get enableRewarded => adsEnabled && _enableRewarded;

  // ---------------------------------------------------------------------------
  // Ad unit IDs — supplied by the release workflow, empty by default.
  // ---------------------------------------------------------------------------

  /// Must match the value Gradle writes into AndroidManifest.xml
  /// (`com.google.android.gms.ads.APPLICATION_ID`).
  static const String androidAppId = String.fromEnvironment('ADMOB_APP_ID');

  static const String bannerUnitId = String.fromEnvironment('ADMOB_BANNER_ID');

  static const String interstitialUnitId =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID');

  static const String rewardedUnitId =
      String.fromEnvironment('ADMOB_REWARDED_ID');

  /// True when the switch is on but the unit IDs were not supplied.
  ///
  /// A release build should never hit this — the workflow passes every ID — but
  /// it keeps a mis-configured run from initialising AdMob with empty units.
  static bool get missingUnitIds =>
      androidAppId.isEmpty ||
      bannerUnitId.isEmpty ||
      interstitialUnitId.isEmpty ||
      rewardedUnitId.isEmpty;

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

  /// Always `false`: test IDs are no longer compiled into the app. Kept as a
  /// constant so callers that logged or branched on it keep compiling.
  static bool get usingTestAds => false;
}
