/// Tuning knobs for KeepIt's Google Play in-app update flow.
///
/// Everything here is a compile-time constant on purpose: the account owner
/// should be able to change the update policy with a one-line edit and a
/// release, without wiring up a remote config service first.
class UpdateConfig {
  const UpdateConfig._();

  /// Master switch. Set to `false` to ship a build that never asks about
  /// updates (useful if Play's API ever misbehaves in production).
  static const bool enabled = true;

  /// Installed builds strictly older than this `versionCode` are **forced**
  /// onto the newest Play build: the app is blocked until it is updated.
  ///
  /// `0` (default) means "nothing is forced" — every update is optional.
  ///
  /// To force an update, bump `version` in `pubspec.yaml` (e.g. `1.0.4+7`),
  /// set this to that new build number (`7`), and ship the release. Everyone
  /// still on `6` or older gets the blocking update screen.
  static const int mandatoryBelowBuildNumber = 0;

  /// Play Console lets you set an "in-app update priority" (0–5) per release.
  /// An update whose priority is at or above this value is treated as
  /// mandatory, which lets you force a rollout **without** shipping code.
  ///
  /// Default `5` = only the highest priority forces an update.
  /// Set to `0` to treat every update as mandatory (not recommended).
  static const int mandatoryPriority = 5;

  /// How long the "Later" button hides the prompt **for that same build**.
  /// A different build being published on Play shows the prompt again.
  static const Duration snoozeDuration = Duration(days: 1);

  /// Grace period after the first frame before asking Play anything, so the
  /// update check never competes with Hive, Firebase or the first paint.
  static const Duration startupDelay = Duration(milliseconds: 1200);
}
