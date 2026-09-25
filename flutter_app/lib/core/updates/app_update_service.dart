import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// True only where Google Play's in-app update API can answer: Android.
///
/// The check deliberately avoids `dart:io` so the web build keeps compiling —
/// `defaultTargetPlatform` resolves to `TargetPlatform.android` only on
/// Android, and to something else on iOS, macOS, Windows, Linux and web.
bool get supportsInAppUpdate =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// A seam over Google Play's in-app update API.
///
/// The real API can only be exercised from a Play-installed build, so the
/// controller talks to this interface and the unit tests supply a fake.
abstract class AppUpdateService {
  /// Whether this platform can run an in-app update at all.
  bool get isSupported;

  /// Asks Play whether a newer build of this app exists.
  ///
  /// Returns `null` when the answer could not be read (no Play Store,
  /// offline, sideloaded build, non-Android platform…).
  Future<AppUpdateInfo?> checkForUpdate();

  /// Progress of a flexible download that is already running.
  Stream<InstallStatus> get installStatus;

  /// Starts a background (flexible) download. Play shows its own consent
  /// dialog, so only call this after the user tapped "Update".
  Future<AppUpdateResult> startFlexibleUpdate();

  /// Runs Play's own full-screen (immediate) update flow.
  Future<AppUpdateResult> performImmediateUpdate();

  /// Installs a flexible update that finished downloading (restarts the app).
  Future<void> completeFlexibleUpdate();
}

/// The real implementation: talks to Play through the `in_app_update` plugin.
///
/// Every call fails soft. A broken update check must never be the reason
/// KeepIt does not open.
class PlayAppUpdateService implements AppUpdateService {
  const PlayAppUpdateService();

  @override
  bool get isSupported => supportsInAppUpdate;

  @override
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (!isSupported) return null;
    try {
      return await InAppUpdate.checkForUpdate();
    } catch (error, stack) {
      debugPrint('KeepIt update check failed: $error\n$stack');
      return null;
    }
  }

  @override
  Stream<InstallStatus> get installStatus =>
      InAppUpdate.installUpdateListener.handleError((Object error) {
        debugPrint('KeepIt install status stream error: $error');
      });

  @override
  Future<AppUpdateResult> startFlexibleUpdate() async {
    if (!isSupported) return AppUpdateResult.inAppUpdateFailed;
    try {
      return await InAppUpdate.startFlexibleUpdate();
    } catch (error, stack) {
      debugPrint('KeepIt flexible update failed: $error\n$stack');
      return AppUpdateResult.inAppUpdateFailed;
    }
  }

  @override
  Future<AppUpdateResult> performImmediateUpdate() async {
    if (!isSupported) return AppUpdateResult.inAppUpdateFailed;
    try {
      return await InAppUpdate.performImmediateUpdate();
    } catch (error, stack) {
      debugPrint('KeepIt immediate update failed: $error\n$stack');
      return AppUpdateResult.inAppUpdateFailed;
    }
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    if (!isSupported) return;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (error, stack) {
      debugPrint('KeepIt completeFlexibleUpdate failed: $error\n$stack');
    }
  }
}

/// Stand-in for platforms without Play (iOS, web, desktop) — every call is a
/// no-op so the rest of the update flow can stay platform-agnostic.
class NoopAppUpdateService implements AppUpdateService {
  const NoopAppUpdateService();

  @override
  bool get isSupported => false;

  @override
  Future<AppUpdateInfo?> checkForUpdate() async => null;

  @override
  Stream<InstallStatus> get installStatus =>
      const Stream<InstallStatus>.empty();

  @override
  Future<AppUpdateResult> startFlexibleUpdate() async =>
      AppUpdateResult.inAppUpdateFailed;

  @override
  Future<AppUpdateResult> performImmediateUpdate() async =>
      AppUpdateResult.inAppUpdateFailed;

  @override
  Future<void> completeFlexibleUpdate() async {}
}
