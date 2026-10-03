import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/updates/app_update_service.dart';
import '../../core/updates/update_config.dart';
import '../../data/datasources/local_mind_datasource.dart';
import 'mind_feed_controller.dart';

/// Where the update flow currently is.
enum AppUpdatePhase {
  /// Nothing to show: never checked, Play was silent, or the user postponed.
  idle,

  /// Asking Play / waiting for an answer.
  checking,

  /// A newer build exists on Play and KeepIt is asking the user about it.
  updateAvailable,

  /// A flexible update is downloading in the background.
  downloading,

  /// The update is downloaded; the user only has to let KeepIt restart.
  readyToInstall,

  /// The installed build is no longer accepted — the app is blocked.
  blocked,

  /// Play says this install is current.
  upToDate,

  /// This platform has no Google Play (iOS, web, desktop).
  unsupported,
}

@immutable
class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.installedBuildNumber,
    this.availableVersionCode,
    this.mandatory = false,
    this.busy = false,
    this.message,
    this.lastCheckedAt,
  });

  final AppUpdatePhase phase;
  final int? installedBuildNumber;
  final int? availableVersionCode;

  /// Whether this update may not be skipped.
  final bool mandatory;

  /// A Play call (consent dialog, install, …) is in flight.
  final bool busy;

  /// Human-readable detail for logs; surfaced on the update/blocking screens.
  final String? message;

  final DateTime? lastCheckedAt;

  /// Whether the host should open an update sheet right now.
  bool get hasPrompt =>
      phase == AppUpdatePhase.updateAvailable ||
      phase == AppUpdatePhase.readyToInstall;

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    int? installedBuildNumber,
    int? availableVersionCode,
    bool? mandatory,
    bool? busy,
    String? message,
    bool clearMessage = false,
    DateTime? lastCheckedAt,
  }) {
    return AppUpdateState(
      phase: phase ?? this.phase,
      installedBuildNumber: installedBuildNumber ?? this.installedBuildNumber,
      availableVersionCode: availableVersionCode ?? this.availableVersionCode,
      mandatory: mandatory ?? this.mandatory,
      busy: busy ?? this.busy,
      message: clearMessage ? null : (message ?? this.message),
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

/// The rules that decide whether a release may be skipped.
///
/// Defaults come from [UpdateConfig]; the provider exists so tests (and a
/// future remote-config source) can swap the numbers without touching
/// production code paths.
@immutable
class UpdatePolicy {
  const UpdatePolicy({
    this.mandatoryBelowBuildNumber = UpdateConfig.mandatoryBelowBuildNumber,
    this.mandatoryPriority = UpdateConfig.mandatoryPriority,
    this.snoozeDuration = UpdateConfig.snoozeDuration,
    this.resumeRecheckInterval = UpdateConfig.resumeRecheckInterval,
  });

  final int mandatoryBelowBuildNumber;
  final int mandatoryPriority;
  final Duration snoozeDuration;
  final Duration resumeRecheckInterval;
}

/// Remembers that the user postponed one specific Play build.
abstract class UpdatePreferences {
  DateTime? snoozedUntil();
  int? snoozedVersionCode();
  Future<void> snooze(Duration duration, {required int? versionCode});
}

/// Stores the snooze in the Hive meta box, next to the onboarding flag.
class HiveUpdatePreferences implements UpdatePreferences {
  HiveUpdatePreferences(this._dataSource);

  static const String untilKey = 'update_snooze_until_ms';
  static const String versionKey = 'update_snooze_version_code';

  final LocalMindDataSource _dataSource;

  @override
  DateTime? snoozedUntil() {
    final millis = _dataSource.getMeta<int>(untilKey);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  int? snoozedVersionCode() => _dataSource.getMeta<int>(versionKey);

  @override
  Future<void> snooze(Duration duration, {required int? versionCode}) async {
    await _dataSource.putMeta(
      untilKey,
      DateTime.now().add(duration).millisecondsSinceEpoch,
    );
    await _dataSource.putMeta(versionKey, versionCode);
  }
}

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  if (!supportsInAppUpdate) return const NoopAppUpdateService();
  return const PlayAppUpdateService();
});

final updatePolicyProvider =
    Provider<UpdatePolicy>((ref) => const UpdatePolicy());

final updatePreferencesProvider = Provider<UpdatePreferences>(
  (ref) => HiveUpdatePreferences(ref.watch(localDataSourceProvider)),
);

/// The `versionCode` of the running build (`1.0.3+6` → `6`).
final installedBuildNumberProvider = FutureProvider<int?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber);
  } catch (_) {
    return null;
  }
});

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>(
  (ref) => AppUpdateController(ref),
);

/// Drives Google Play's in-app update flow.
///
/// The flow is deliberately KeepIt-first: the app asks Play *silently*, shows
/// its own screen, and only hands over to Play's consent dialog or full-screen
/// installer once the user taps "Update". That way a cold start never throws
/// a Play dialog in the user's face before the app has even painted.
class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._ref) : super(const AppUpdateState());

  final Ref _ref;
  StreamSubscription<InstallStatus>? _installSub;
  bool _checking = false;
  bool _downloadInFlight = false;
  InstallStatus? _lastInstallStatus;
  bool _flexibleAllowed = true;
  bool _immediateAllowed = true;

  AppUpdateService get _service => _ref.read(appUpdateServiceProvider);
  UpdatePolicy get _policy => _ref.read(updatePolicyProvider);
  UpdatePreferences get _prefs => _ref.read(updatePreferencesProvider);

  /// Called when KeepIt returns to the foreground.
  ///
  /// Avoids calling `checkForUpdate` while `startFlexibleUpdate` is actively
  /// running (`_downloadInFlight`), because the `in_app_update` Android plugin
  /// recreates `AppUpdateManager` inside `checkForUpdate` and would detach its
  /// own download progress listener.
  Future<void> onAppResumed() async {
    if (!UpdateConfig.enabled ||
        !_service.isSupported ||
        _checking ||
        _downloadInFlight) {
      return;
    }
    if (state.phase == AppUpdatePhase.downloading) {
      await check();
      return;
    }
    if (state.phase == AppUpdatePhase.blocked ||
        state.phase == AppUpdatePhase.updateAvailable ||
        state.phase == AppUpdatePhase.readyToInstall) {
      return;
    }
    final last = state.lastCheckedAt;
    if (last == null ||
        DateTime.now().difference(last) >= _policy.resumeRecheckInterval) {
      await check();
    }
  }

  /// Asks Play whether a newer build exists.
  ///
  /// [manual] (Profile → Check for update) ignores the "Later" snooze.
  Future<void> check({bool manual = false}) async {
    if (!UpdateConfig.enabled || !_service.isSupported) {
      state = state.copyWith(
        phase: AppUpdatePhase.unsupported,
        clearMessage: true,
      );
      return;
    }
    if (_checking) return;
    _checking = true;
    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      busy: true,
      clearMessage: true,
    );

    try {
      final installed = await _ref.read(installedBuildNumberProvider.future);
      final info = await _service.checkForUpdate();

      if (info == null) {
        // No Play Store, offline, or a sideloaded build. Nothing to offer.
        state = state.copyWith(
          phase: AppUpdatePhase.idle,
          busy: false,
          message: 'Play did not answer the update check.',
        );
        return;
      }

      _flexibleAllowed = info.flexibleUpdateAllowed;
      _immediateAllowed = info.immediateUpdateAllowed;
      final available = info.availableVersionCode;
      final finishedDownload = info.installStatus == InstallStatus.downloaded;
      final inProgress = info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress;
      final isAvailable =
          info.updateAvailability == UpdateAvailability.updateAvailable;

      // A build downloaded earlier (the user never restarted) is the easiest
      // win — offer the restart instead of downloading again.
      if (finishedDownload) {
        _watchInstallState();
        state = state.copyWith(
          phase: AppUpdatePhase.readyToInstall,
          busy: false,
          installedBuildNumber: installed,
          availableVersionCode: available,
          lastCheckedAt: DateTime.now(),
        );
        return;
      }

      if (!isAvailable && !inProgress) {
        state = state.copyWith(
          phase: AppUpdatePhase.upToDate,
          busy: false,
          installedBuildNumber: installed,
          availableVersionCode: available,
          lastCheckedAt: DateTime.now(),
        );
        return;
      }

      final mandatory = _isMandatory(installed: installed, info: info);

      if (mandatory) {
        // Block immediately: the user may not continue on this build.
        state = state.copyWith(
          phase: AppUpdatePhase.blocked,
          busy: false,
          installedBuildNumber: installed,
          availableVersionCode: available,
          mandatory: true,
          lastCheckedAt: DateTime.now(),
        );
        return;
      }

      if (inProgress) {
        _watchInstallState();
        state = state.copyWith(
          phase: AppUpdatePhase.downloading,
          busy: false,
          installedBuildNumber: installed,
          availableVersionCode: available,
          lastCheckedAt: DateTime.now(),
        );
        return;
      }

      if (!manual && _isSnoozed(available)) {
        state = state.copyWith(
          phase: AppUpdatePhase.upToDate,
          busy: false,
          installedBuildNumber: installed,
          availableVersionCode: available,
          lastCheckedAt: DateTime.now(),
        );
        return;
      }

      state = state.copyWith(
        phase: AppUpdatePhase.updateAvailable,
        busy: false,
        installedBuildNumber: installed,
        availableVersionCode: available,
        mandatory: false,
        lastCheckedAt: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.idle,
        busy: false,
        message: '$error',
      );
    } finally {
      _checking = false;
    }
  }

  /// "Update" on the prompt: downloads the new build in the background while
  /// the user keeps using KeepIt (or falls back to Play's immediate flow when
  /// Play only permits an immediate update).
  ///
  /// Note on `in_app_update` Android plugin behaviour:
  /// `InAppUpdate.startFlexibleUpdate()` emits `InstallStatus.downloading` on
  /// [AppUpdateService.installStatus] while downloading, and only resolves its
  /// returned Future with [AppUpdateResult.success] once `InstallStatus.DOWNLOADED`
  /// is reached. We therefore subscribe to `_watchInstallState()` *before*
  /// calling `startFlexibleUpdate()` and trigger `completeFlexibleUpdate()` as
  /// soon as the download finishes.
  Future<bool> startFlexibleDownload() async {
    if (!_service.isSupported) return false;
    final version = state.availableVersionCode;
    final useImmediate = !_flexibleAllowed && _immediateAllowed;

    if (!useImmediate) {
      _lastInstallStatus = null;
      _watchInstallState();
    }

    _downloadInFlight = true;
    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      busy: true,
      clearMessage: true,
    );

    final result = useImmediate
        ? await _service.performImmediateUpdate()
        : await _service.startFlexibleUpdate();
    _downloadInFlight = false;
    // Let any synchronous stream event emitted by startFlexibleUpdate arrive.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return false;

    switch (result) {
      case AppUpdateResult.success:
        if (useImmediate) {
          state = state.copyWith(
            phase: AppUpdatePhase.downloading,
            busy: false,
            clearMessage: true,
          );
          return true;
        }
        // If the stream is still at `downloading` (e.g. a mock service that
        // resolves `startFlexibleUpdate` when the download begins), stay in
        // `downloading` until `InstallStatus.downloaded` arrives.
        // On real Android, `InAppUpdatePlugin.kt` resolves `startFlexibleUpdate`
        // only when `InstallStatus.DOWNLOADED` is reached — transition to
        // `readyToInstall` and trigger `completeFlexibleUpdate()` right away.
        if (_lastInstallStatus == InstallStatus.downloading ||
            _lastInstallStatus == InstallStatus.pending) {
          state = state.copyWith(
            phase: AppUpdatePhase.downloading,
            busy: false,
            clearMessage: true,
          );
        } else {
          final alreadyCompleted = state.phase == AppUpdatePhase.readyToInstall;
          state = state.copyWith(
            phase: AppUpdatePhase.readyToInstall,
            busy: false,
            clearMessage: true,
          );
          if (!alreadyCompleted) {
            unawaited(_service.completeFlexibleUpdate());
          }
        }
        return true;
      case AppUpdateResult.userDeniedUpdate:
        // Play's dialog was dismissed — do not nag again today.
        await _prefs.snooze(_policy.snoozeDuration, versionCode: version);
        if (!mounted) return false;
        state = state.copyWith(
          phase: AppUpdatePhase.idle,
          busy: false,
          message: 'Update postponed.',
        );
        return true;
      case AppUpdateResult.inAppUpdateFailed:
        state = state.copyWith(
          phase: AppUpdatePhase.updateAvailable,
          busy: false,
          message:
              'Play could not start the download. Try "Open in Play Store".',
        );
        return false;
    }
  }

  /// "Restart & install": installs a flexible update that finished
  /// downloading. Play restarts KeepIt; if it cannot, the app stays put.
  ///
  /// `InAppUpdatePlugin.kt`'s `completeFlexibleUpdate` calls
  /// `appUpdateManager.completeUpdate()` without completing the MethodChannel
  /// `Result`, so we bound the await with a short timeout.
  Future<void> installDownloadedUpdate() async {
    state = state.copyWith(busy: true);
    await _service
        .completeFlexibleUpdate()
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    if (!mounted) return;
    state = state.copyWith(busy: false);
  }

  /// "Update now" on the blocking screen: Play's own full-screen flow.
  Future<void> startMandatoryUpdate() async {
    if (!_service.isSupported) return;
    state = state.copyWith(busy: true, clearMessage: true);

    final result = await _service.performImmediateUpdate();
    if (!mounted) return;

    // Success or failure, a mandatory update keeps the app blocked: on success
    // Play is already covering the screen and will restart us.
    switch (result) {
      case AppUpdateResult.success:
        state = state.copyWith(busy: false, phase: AppUpdatePhase.blocked);
        break;
      case AppUpdateResult.userDeniedUpdate:
        state = state.copyWith(
          phase: AppUpdatePhase.blocked,
          busy: false,
          message: 'The update was cancelled. KeepIt needs it to continue.',
        );
        break;
      case AppUpdateResult.inAppUpdateFailed:
        state = state.copyWith(
          phase: AppUpdatePhase.blocked,
          busy: false,
          message: 'Play could not start the update. Try "Open in Play Store".',
        );
        break;
    }
  }

  /// "Later": hide the prompt for [UpdatePolicy.snoozeDuration], but only for
  /// this exact Play build.
  Future<void> snooze() async {
    await _prefs.snooze(
      _policy.snoozeDuration,
      versionCode: state.availableVersionCode,
    );
    if (!mounted) return;
    state = state.copyWith(phase: AppUpdatePhase.idle, busy: false);
  }

  /// Escape hatch on the update or blocking screen: the user updates by hand.
  Future<void> openPlayStore() async {
    try {
      await launchUrl(
        Uri.parse(AppConfig.playStoreUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Nothing sensible to do if even the store listing cannot be opened.
    }
  }

  bool _isMandatory({required int? installed, required AppUpdateInfo info}) {
    final floor = _policy.mandatoryBelowBuildNumber;
    if (floor > 0 && installed != null && installed < floor) return true;
    final priority = _policy.mandatoryPriority;
    return priority > 0 && info.updatePriority >= priority;
  }

  bool _isSnoozed(int? availableVersionCode) {
    final until = _prefs.snoozedUntil();
    if (until == null || !DateTime.now().isBefore(until)) return false;
    final snoozedVersion = _prefs.snoozedVersionCode();
    // A *newer* build on Play overrides an older snooze.
    return snoozedVersion == null || snoozedVersion == availableVersionCode;
  }

  void _watchInstallState() {
    if (_installSub != null) return;
    _installSub = _service.installStatus.listen((status) {
      _lastInstallStatus = status;
      switch (status) {
        case InstallStatus.pending:
        case InstallStatus.downloading:
          if (state.phase != AppUpdatePhase.readyToInstall) {
            state = state.copyWith(
              phase: AppUpdatePhase.downloading,
              busy: false,
              clearMessage: true,
            );
          }
          break;
        case InstallStatus.downloaded:
          final wasReady = state.phase == AppUpdatePhase.readyToInstall;
          state = state.copyWith(
            phase: AppUpdatePhase.readyToInstall,
            busy: false,
            clearMessage: true,
          );
          if (!wasReady) {
            // Automatically hand off to Play to install and restart the app.
            unawaited(_service.completeFlexibleUpdate());
          }
          break;
        case InstallStatus.installing:
        case InstallStatus.installed:
          state =
              state.copyWith(phase: AppUpdatePhase.downloading, busy: false);
          break;
        case InstallStatus.failed:
        case InstallStatus.canceled:
          state = state.copyWith(
            phase: AppUpdatePhase.idle,
            busy: false,
            message: 'The update download stopped.',
          );
          break;
        case InstallStatus.unknown:
          break;
      }
    });
  }

  @override
  void dispose() {
    _installSub?.cancel();
    _installSub = null;
    super.dispose();
  }
}
