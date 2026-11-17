import 'ad_config.dart';

/// When an interstitial may interrupt the user.
///
/// Extracted from [AdService] so the rules are testable without AdMob: they are
/// plain arithmetic over three numbers, and they are the difference between
/// "an ad after a save" and "an ad every save".
///
/// The counters live with the caller (persisted in the Hive meta box):
/// * `savesSinceLast` — successful saves since the last interstitial,
/// * `lastShownAt`    — when the last one was actually shown (null = never).
class AdFrequency {
  const AdFrequency({
    required this.savesSinceLast,
    required this.lastShownAt,
  });

  final int savesSinceLast;
  final DateTime? lastShownAt;

  /// Enough saves *and* enough quiet time. Both caps must pass; skipping one
  /// is how a "maybe once a day" ad becomes an ad per save.
  ///
  /// Deliberately free of the compile-time `AdConfig` switches: the caller
  /// ([AdService]) owns "are ads on at all", this owns "is it the right
  /// moment". Keeping them apart is what makes the rule testable.
  bool allowsInterstitial(DateTime now) {
    if (savesSinceLast < AdConfig.savesBetweenInterstitials) return false;
    final last = lastShownAt;
    if (last != null &&
        now.difference(last) < AdConfig.minInterstitialInterval) {
      return false;
    }
    return true;
  }

  /// Records a save. Returns the counters to persist.
  AdFrequency afterSave() => AdFrequency(
        savesSinceLast: savesSinceLast + 1,
        lastShownAt: lastShownAt,
      );

  /// Records that an interstitial was shown: the save counter resets and the
  /// interval starts now.
  AdFrequency afterShown(DateTime now) =>
      AdFrequency(savesSinceLast: 0, lastShownAt: now);

  /// How many more saves are needed before an ad is even considered. Used by
  /// tests and (potentially) a debug screen.
  int get savesUntilEligible {
    final missing = AdConfig.savesBetweenInterstitials - savesSinceLast;
    return missing > 0 ? missing : 0;
  }

  /// True when the save cap is met but the time cap still blocks an ad.
  bool isWaitingOutInterval(DateTime now) {
    final last = lastShownAt;
    return savesSinceLast >= AdConfig.savesBetweenInterstitials &&
        last != null &&
        now.difference(last) < AdConfig.minInterstitialInterval;
  }

  @override
  String toString() =>
      'AdFrequency(savesSinceLast: $savesSinceLast, lastShownAt: $lastShownAt)';
}
