import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';

import 'package:keepit/core/updates/app_update_service.dart';
import 'package:keepit/core/updates/update_config.dart';
import 'package:keepit/presentation/controllers/app_update_controller.dart';
import 'package:keepit/presentation/widgets/update_host.dart';

/// Play's API only answers on a Play-installed Android build, so the controller
/// is driven through a fake here — this is the only place the mandatory-vs-
/// optional rules can be verified without publishing a release.
class _FakeAppUpdateService implements AppUpdateService {
  _FakeAppUpdateService({AppUpdateInfo? info, this.supported = true})
      : _info = info;

  final bool supported;
  AppUpdateInfo? _info;
  final StreamController<InstallStatus> _statuses =
      StreamController<InstallStatus>.broadcast();

  int flexibleStarts = 0;
  int immediateStarts = 0;
  int completions = 0;
  AppUpdateResult flexibleResult = AppUpdateResult.success;
  AppUpdateResult immediateResult = AppUpdateResult.success;

  void setInfo(AppUpdateInfo info) => _info = info;
  void emit(InstallStatus status) => _statuses.add(status);

  @override
  bool get isSupported => supported;

  @override
  Future<AppUpdateInfo?> checkForUpdate() async => _info;

  @override
  Stream<InstallStatus> get installStatus => _statuses.stream;

  @override
  Future<AppUpdateResult> startFlexibleUpdate() async {
    flexibleStarts++;
    if (flexibleResult == AppUpdateResult.success) {
      _statuses.add(InstallStatus.downloading);
    }
    return flexibleResult;
  }

  @override
  Future<AppUpdateResult> performImmediateUpdate() async {
    immediateStarts++;
    return immediateResult;
  }

  @override
  Future<void> completeFlexibleUpdate() async => completions++;
}

class _MemoryUpdatePreferences implements UpdatePreferences {
  DateTime? until;
  int? version;

  @override
  DateTime? snoozedUntil() => until;

  @override
  int? snoozedVersionCode() => version;

  @override
  Future<void> snooze(Duration duration, {required int? versionCode}) async {
    until = DateTime.now().add(duration);
    version = versionCode;
  }
}

AppUpdateInfo _info({
  UpdateAvailability availability = UpdateAvailability.updateAvailable,
  int? availableVersionCode = 7,
  InstallStatus installStatus = InstallStatus.unknown,
  int updatePriority = 0,
  bool flexibleAllowed = true,
  bool immediateAllowed = true,
}) {
  return AppUpdateInfo(
    updateAvailability: availability,
    immediateUpdateAllowed: immediateAllowed,
    immediateAllowedPreconditions: null,
    flexibleUpdateAllowed: flexibleAllowed,
    flexibleAllowedPreconditions: null,
    availableVersionCode: availableVersionCode,
    installStatus: installStatus,
    packageName: 'com.keshabstudios.keepit',
    clientVersionStalenessDays: null,
    updatePriority: updatePriority,
  );
}

/// Lets the fake's broadcast stream reach the controller's listener.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 1));

void main() {
  late _FakeAppUpdateService service;
  late _MemoryUpdatePreferences prefs;

  ProviderContainer buildContainer({
    int installedBuild = 6,
    UpdatePolicy policy = const UpdatePolicy(),
  }) {
    final container = ProviderContainer(
      overrides: [
        appUpdateServiceProvider.overrideWithValue(service),
        updatePreferencesProvider.overrideWithValue(prefs),
        updatePolicyProvider.overrideWithValue(policy),
        installedBuildNumberProvider.overrideWith((ref) => installedBuild),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    prefs = _MemoryUpdatePreferences();
    service = _FakeAppUpdateService(info: _info());
  });

  test('stays quiet when Play reports no newer build', () async {
    service = _FakeAppUpdateService(
      info: _info(availability: UpdateAvailability.updateNotAvailable),
    );
    final container = buildContainer();

    await container.read(appUpdateProvider.notifier).check();

    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.upToDate);
    expect(service.flexibleStarts, 0);
  });

  test('offers a newer build without opening Play first', () async {
    final container = buildContainer();
    final controller = container.read(appUpdateProvider.notifier);

    await controller.check();
    final state = container.read(appUpdateProvider);

    expect(state.phase, AppUpdatePhase.updateAvailable);
    expect(state.availableVersionCode, 7);
    expect(state.installedBuildNumber, 6);
    // Play's own consent dialog must not appear unbidden.
    expect(service.flexibleStarts, 0);
  });

  test('downloads in the background, then asks for a restart', () async {
    final container = buildContainer();
    final controller = container.read(appUpdateProvider.notifier);
    await controller.check();

    await controller.startFlexibleDownload();
    await _settle();
    expect(service.flexibleStarts, 1);
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.downloading);

    service.emit(InstallStatus.downloaded);
    await _settle();
    expect(
      container.read(appUpdateProvider).phase,
      AppUpdatePhase.readyToInstall,
    );

    await controller.installDownloadedUpdate();
    expect(service.completions, 1);
  });

  test('a cancelled download can be retried later', () async {
    service.flexibleResult = AppUpdateResult.inAppUpdateFailed;
    final container = buildContainer();
    final controller = container.read(appUpdateProvider.notifier);
    await controller.check();

    await controller.startFlexibleDownload();

    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.updateAvailable);
  });

  test('Later postpones that build only, and a manual check ignores it',
      () async {
    final container = buildContainer();
    final controller = container.read(appUpdateProvider.notifier);

    await controller.check();
    await controller.snooze();
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.idle);
    expect(prefs.version, 7);

    // Same build, automatic check → silent.
    await controller.check();
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.upToDate);

    // Profile → Check for update still answers honestly.
    await controller.check(manual: true);
    expect(
      container.read(appUpdateProvider).phase,
      AppUpdatePhase.updateAvailable,
    );

    // A genuinely newer build breaks through the snooze.
    await controller.snooze();
    service.setInfo(_info(availableVersionCode: 8));
    await controller.check();
    expect(
      container.read(appUpdateProvider).phase,
      AppUpdatePhase.updateAvailable,
    );
  });

  test('resumes a download the user never installed', () async {
    service = _FakeAppUpdateService(
      info: _info(installStatus: InstallStatus.downloaded),
    );
    final container = buildContainer();

    await container.read(appUpdateProvider.notifier).check();

    expect(
      container.read(appUpdateProvider).phase,
      AppUpdatePhase.readyToInstall,
    );
    expect(service.flexibleStarts, 0);
  });

  test('blocks the app below the mandatory build number', () async {
    final container = buildContainer(
      policy: const UpdatePolicy(mandatoryBelowBuildNumber: 7),
    );
    final controller = container.read(appUpdateProvider.notifier);

    await controller.check();
    final state = container.read(appUpdateProvider);
    expect(state.phase, AppUpdatePhase.blocked);
    expect(state.mandatory, isTrue);

    await controller.startMandatoryUpdate();
    expect(service.immediateStarts, 1);
    // Play takes over the screen; until it restarts us the app stays blocked.
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.blocked);
  });

  test('stays blocked when the user refuses the mandatory update', () async {
    service.immediateResult = AppUpdateResult.userDeniedUpdate;
    final container = buildContainer(
      policy: const UpdatePolicy(mandatoryBelowBuildNumber: 7),
    );
    final controller = container.read(appUpdateProvider.notifier);
    await controller.check();

    await controller.startMandatoryUpdate();
    final state = container.read(appUpdateProvider);

    expect(state.phase, AppUpdatePhase.blocked);
    expect(state.message, contains('cancelled'));
  });

  test('honours the in-app update priority set in Play Console', () async {
    service = _FakeAppUpdateService(info: _info(updatePriority: 4));
    final container = buildContainer(
      policy: const UpdatePolicy(mandatoryPriority: 4),
    );

    await container.read(appUpdateProvider.notifier).check();

    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.blocked);
  });

  test('never blocks a build that is already new enough', () async {
    final container = buildContainer(
      installedBuild: 9,
      policy: const UpdatePolicy(mandatoryBelowBuildNumber: 7),
    );

    await container.read(appUpdateProvider.notifier).check();
    final state = container.read(appUpdateProvider);

    expect(state.phase, AppUpdatePhase.updateAvailable);
    expect(state.mandatory, isFalse);
  });

  test('does nothing where Play does not exist', () async {
    service = _FakeAppUpdateService(info: _info(), supported: false);
    final container = buildContainer();

    await container.read(appUpdateProvider.notifier).check();

    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.unsupported);
    expect(service.flexibleStarts, 0);
  });

  test('a silent Play is never treated as an update', () async {
    service = _FakeAppUpdateService(); // checkForUpdate() → null
    final container = buildContainer();

    await container.read(appUpdateProvider.notifier).check();
    final state = container.read(appUpdateProvider);

    expect(state.phase, AppUpdatePhase.idle);
    expect(state.message, isNotNull);
  });

  // ---- widget level: is the flow actually wired into the app? ----

  testWidgets('shows KeepIt\'s update sheet on top of a usable app', (
    tester,
  ) async {
    final widgetService = _FakeAppUpdateService(info: _info());
    final widgetPrefs = _MemoryUpdatePreferences();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(widgetService),
          updatePreferencesProvider.overrideWithValue(widgetPrefs),
          updatePolicyProvider.overrideWithValue(const UpdatePolicy()),
          installedBuildNumberProvider.overrideWith((ref) => 6),
        ],
        child: const MaterialApp(
          home: UpdateHost(child: Scaffold(body: Center(child: Text('Home')))),
        ),
      ),
    );
    // initState's post-frame callback, then UpdateConfig.startupDelay.
    await tester.pump();
    await tester.pump(UpdateConfig.startupDelay);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget, reason: 'app stays usable');
    expect(find.text('A new version is ready'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(
      widgetService.flexibleStarts,
      0,
      reason: 'Play must not be contacted before the user taps Update',
    );

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('A new version is ready'), findsNothing);
    expect(widgetPrefs.version, 7, reason: 'Later postponed build 7');
  });

  testWidgets('replaces the app for a mandatory release', (tester) async {
    final widgetService = _FakeAppUpdateService(info: _info());
    final widgetPrefs = _MemoryUpdatePreferences();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(widgetService),
          updatePreferencesProvider.overrideWithValue(widgetPrefs),
          updatePolicyProvider.overrideWithValue(
            const UpdatePolicy(mandatoryBelowBuildNumber: 7),
          ),
          installedBuildNumberProvider.overrideWith((ref) => 6),
        ],
        child: const MaterialApp(
          home: UpdateHost(child: Scaffold(body: Center(child: Text('Home')))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(UpdateConfig.startupDelay);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Home'), findsNothing, reason: 'app is blocked');
    expect(find.text('Later'), findsNothing, reason: 'no way to skip');

    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(widgetService.immediateStarts, 1);
    expect(find.text('Update required'), findsOneWidget);
  });
}
