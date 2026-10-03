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

  /// Asking Play / running Play's native update flow.
  checking,

  /// A newer build exists on Play.
  updateAvailable,

  /// Google Play's update flow is downloading/installing.
  downloading,

  /// A flexible update finished downloading and is ready to complete.
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

  /// A Play call is in flight.
  final bool busy;

  /// Human-readable detail for logs; surfaced on the blocking screen.
  final String? message;

  final DateTime? lastCheckedAt;

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

/// Drives Google Play's native in-app update flow directly.
///
/// Whenever Play reports a newer build, KeepIt hands straight over to Google
/// Play's own native update UI (`InAppUpdate.performImmediateUpdate()`, with a
/// fallback to `startFlexibleUpdate()` + `completeFlexibleUpdate()` if only
/// flexible updates are permitted). Google Play handles the prompt, download,
/// installation, and app restart natively.
class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._ref) : super(const AppUpdateState());

  final Ref _ref;
  StreamSubscription<InstallStatus>? _installSub;
  bool _checking = false;

  AppUpdateService get _service => _ref.read(appUpdateServiceProvider);
  UpdatePolicy get _policy => _ref.read(updatePolicyProvider);
  UpdatePreferences get _prefs => _ref.read(updatePreferencesProvider);

  /// Called when KeepIt returns to the foreground.
  Future<void> onAppResumed() async {
    if (!UpdateConfig.enabled || !_service.isSupported || _checking) {
      return;
    }
    if (state.phase == AppUpdatePhase.blocked) {
      return;
    }
    final last = state.lastCheckedAt;
    if (last == null ||
        DateTime.now().difference(last) >= _policy.resumeRecheckInterval) {
      await check();
    }
  }

  /// Checks Google Play for an update and immediately launches Google Play's
  /// native update flow if one is available.
  ///
  /// [manual] (Profile → Check for update) ignores any earlier dismissal.
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
        state = state.copyWith(
          phase: AppUpdatePhase.idle,
          busy: false,
          message: 'Play did not answer the update check.',
        );
        return;
      }

      final available = info.availableVersionCode;
      final finishedDownload = info.installStatus == InstallStatus.downloaded;
      final inProgress = info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress;
      final isAvailable =
          info.updateAvailability == UpdateAvailability.updateAvailable;

      // If a previous flexible download already finished, complete it right away.
      if (finishedDownload) {
        state = state.copyWith(
          phase: AppUpdatePhase.readyToInstall,
          busy: false,
          installedBuildNumber: installed,
          availableVersionCode: available,
          lastCheckedAt: DateTime.now(),
        );
        await installDownloadedUpdate();
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

      if (!mandatory && !manual && !inProgress && _isSnoozed(available)) {
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
        phase:
            mandatory ? AppUpdatePhase.blocked : AppUpdatePhase.updateAvailable,
        busy: true,
        installedBuildNumber: installed,
        availableVersionCode: available,
        mandatory: mandatory,
        lastCheckedAt: DateTime.now(),
      );

      // Hand off directly to Google Play's native update UI.
      await _runNativePlayUpdate(
        info: info,
        mandatory: mandatory,
        manual: manual,
        availableVersionCode: available,
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

  Future<void> _runNativePlayUpdate({
    required AppUpdateInfo info,
    required bool mandatory,
    required bool manual,
    required int? availableVersionCode,
  }) async {
    if (info.immediateUpdateAllowed) {
      final result = await _service.performImmediateUpdate();
      if (!mounted) return;
      switch (result) {
        case AppUpdateResult.success:
          state = state.copyWith(
            phase:
                mandatory ? AppUpdatePhase.blocked : AppUpdatePhase.downloading,
            busy: false,
            clearMessage: true,
          );
          return;
        case AppUpdateResult.userDeniedUpdate:
          if (mandatory) {
            state = state.copyWith(
              phase: AppUpdatePhase.blocked,
              busy: false,
              message: 'The update was cancelled. KeepIt needs it to continue.',
            );
          } else {
            await _prefs.snooze(
              _policy.snoozeDuration,
              versionCode: availableVersionCode,
            );
            if (!mounted) return;
            state = state.copyWith(
              phase: AppUpdatePhase.idle,
              busy: false,
              message: 'Update postponed.',
            );
          }
          return;
        case AppUpdateResult.inAppUpdateFailed:
          if (mandatory) {
            state = state.copyWith(
              phase: AppUpdatePhase.blocked,
              busy: false,
              message:
                  'Play could not start the update. Try "Open in Play Store".',
            );
          } else {
            state = state.copyWith(
              phase: AppUpdatePhase.idle,
              busy: false,
              message: 'Play could not start the update.',
            );
            if (manual) {
              await openPlayStore();
            }
          }
          return;
      }
    }

    if (info.flexibleUpdateAllowed) {
      _watchInstallState();
      final result = await _service.startFlexibleUpdate();
      if (!mounted) return;
      switch (result) {
        case AppUpdateResult.success:
          state = state.copyWith(
            phase: AppUpdatePhase.readyToInstall,
            busy: false,
            clearMessage: true,
          );
          await installDownloadedUpdate();
          return;
        case AppUpdateResult.userDeniedUpdate:
          await _prefs.snooze(
            _policy.snoozeDuration,
            versionCode: availableVersionCode,
          );
          if (!mounted) return;
          state = state.copyWith(
            phase: AppUpdatePhase.idle,
            busy: false,
            message: 'Update postponed.',
          );
          return;
        case AppUpdateResult.inAppUpdateFailed:
          state = state.copyWith(
            phase: AppUpdatePhase.idle,
            busy: false,
            message: 'Play could not start the update.',
          );
          if (manual) {
            await openPlayStore();
          }
          return;
      }
    }
  }

  /// Completes a flexible update that finished downloading.
  Future<void> installDownloadedUpdate() async {
    state = state.copyWith(busy: true);
    await _service
        .completeFlexibleUpdate()
        .timeout(const Duration(milliseconds: 200), onTimeout: () {});
    if (!mounted) return;
    state = state.copyWith(busy: false);
  }

  /// "Update now" on the blocking screen: Play's own full-screen flow.
  Future<void> startMandatoryUpdate() async {
    if (!_service.isSupported) return;
    state = state.copyWith(busy: true, clearMessage: true);

    final result = await _service.performImmediateUpdate();
    if (!mounted) return;

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

  /// Postpone the current build for [UpdatePolicy.snoozeDuration].
  Future<void> snooze() async {
    await _prefs.snooze(
      _policy.snoozeDuration,
      versionCode: state.availableVersionCode,
    );
    if (!mounted) return;
    state = state.copyWith(phase: AppUpdatePhase.idle, busy: false);
  }

  /// Escape hatch: open Google Play Store listing directly.
  Future<void> openPlayStore() async {
    try {
      await launchUrl(
        Uri.parse(AppConfig.playStoreUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Ignore if store cannot be opened.
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
    return snoozedVersion == null || snoozedVersion == availableVersionCode;
  }

  void _watchInstallState() {
    if (_installSub != null) return;
    _installSub = _service.installStatus.listen((status) {
      if (status == InstallStatus.downloaded) {
        state = state.copyWith(
          phase: AppUpdatePhase.readyToInstall,
          busy: false,
          clearMessage: true,
        );
        unawaited(_service.completeFlexibleUpdate());
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
