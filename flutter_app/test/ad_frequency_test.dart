import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/ads/ad_config.dart';
import 'package:keepit/core/ads/ad_frequency.dart';

/// Ads must never get in the way of saving an idea. These pin the two caps that
/// make that true: N saves apart, and never closer together than the interval.
void main() {
  final now = DateTime(2026, 11, 18, 12);

  test('nothing is shown before the save cap, however long it has been', () {
    const fresh = AdFrequency(
      savesSinceLast: AdConfig.savesBetweenInterstitials - 1,
      lastShownAt: null,
    );
    expect(fresh.allowsInterstitial(now), isFalse);
    expect(fresh.savesUntilEligible, 1);
  });

  test('at the save cap with no history, an ad is allowed', () {
    const ready = AdFrequency(
      savesSinceLast: AdConfig.savesBetweenInterstitials,
      lastShownAt: null,
    );
    expect(ready.allowsInterstitial(now), isTrue);
    expect(ready.savesUntilEligible, 0);
  });

  test('the time cap blocks an ad even when saves pile up', () {
    final justShown = AdFrequency(
      savesSinceLast: AdConfig.savesBetweenInterstitials * 3,
      lastShownAt: now.subtract(const Duration(minutes: 5)),
    );
    expect(justShown.allowsInterstitial(now), isFalse);
    expect(justShown.isWaitingOutInterval(now), isTrue);
  });

  test('after the interval passes, the next save shows one', () {
    final waited = AdFrequency(
      savesSinceLast: AdConfig.savesBetweenInterstitials,
      lastShownAt: now.subtract(
          AdConfig.minInterstitialInterval + const Duration(minutes: 1)),
    );
    expect(waited.allowsInterstitial(now), isTrue);
    expect(waited.isWaitingOutInterval(now), isFalse);
  });

  test('exactly at the interval boundary counts as elapsed', () {
    final boundary = AdFrequency(
      savesSinceLast: AdConfig.savesBetweenInterstitials,
      lastShownAt: now.subtract(AdConfig.minInterstitialInterval),
    );
    expect(boundary.allowsInterstitial(now), isTrue);
  });

  test('a save increments the counter and keeps the last-shown time', () {
    final before = AdFrequency(savesSinceLast: 3, lastShownAt: now);
    final after = before.afterSave();
    expect(after.savesSinceLast, 4);
    expect(after.lastShownAt, now);
  });

  test('showing an ad resets the save counter and stamps the time', () {
    final shown =
        const AdFrequency(savesSinceLast: 9, lastShownAt: null).afterShown(now);
    expect(shown.savesSinceLast, 0);
    expect(shown.lastShownAt, now);
    // ...and it must not immediately schedule another one.
    expect(shown.allowsInterstitial(now), isFalse);
  });

  test('the whole save -> show -> wait loop behaves like the UX promise', () {
    var freq = const AdFrequency(savesSinceLast: 0, lastShownAt: null);
    final shownAt = <DateTime>[];
    var clock = now;

    for (var save = 0; save < 40; save++) {
      freq = freq.afterSave();
      clock = clock.add(const Duration(minutes: 20));
      if (freq.allowsInterstitial(clock)) {
        shownAt.add(clock);
        freq = freq.afterShown(clock);
      }
    }

    // 40 saves * 20 min = 13h20m, with a 3h floor and 8 saves per ad: the ads
    // that fit are bounded by the *time* cap, not the save cap.
    for (var i = 1; i < shownAt.length; i++) {
      expect(shownAt[i].difference(shownAt[i - 1]),
          greaterThanOrEqualTo(AdConfig.minInterstitialInterval));
    }
    expect(shownAt.length, lessThanOrEqualTo(5));
    expect(shownAt, isNotEmpty);
  });

  test('an ad build is off by default (no release secrets in this build)', () {
    // The policy is pure arithmetic on purpose; AdService owns the on/off
    // switch. This pins the safe default a checkout without secrets ships.
    expect(AdConfig.adsEnabled, isFalse);
    expect(AdConfig.enableInterstitial, isFalse);
    expect(AdConfig.enableBanner, isFalse);
    expect(AdConfig.enableRewarded, isFalse);
  });
}
