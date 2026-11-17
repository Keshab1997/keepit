import 'package:flutter/foundation.dart';

/// Compile-time switches that let the screenshot workflow reach a real screen.
///
/// A freshly installed app always opens on the onboarding carousel with an
/// empty mind, so `tool/see_screen.py` used to photograph the same welcome
/// page no matter which route it was asked for. These flags are plain
/// `--dart-define`s, off by default, and only ever set by that workflow, so a
/// release build behaves exactly as before.
class ScreenshotMode {
  ScreenshotMode._();

  /// `--dart-define=KEEPIT_SCREENSHOT=true` — skip the first-launch carousel.
  static const bool enabled = bool.fromEnvironment('KEEPIT_SCREENSHOT');

  /// `--dart-define=KEEPIT_SCREENSHOT_TAB=2` — which bottom tab to open, so
  /// Serendipity and Profile can be photographed without a tap.
  static int get initialTab {
    const tab = int.fromEnvironment('KEEPIT_SCREENSHOT_TAB', defaultValue: 0);
    if (tab < 0) return 0;
    if (tab > 3) return 3;
    return tab;
  }

  /// `--dart-define=KEEPIT_SCREENSHOT_SEED=true` — seed the demo items into an
  /// empty box so the feed has something in it to look at.
  static const bool seedDemoItems = bool.fromEnvironment(
    'KEEPIT_SCREENSHOT_SEED',
  );

  /// Debug builds only: none of this should be reachable in a store build,
  /// even if someone ships the wrong define.
  static bool get active => enabled && kDebugMode;
}
