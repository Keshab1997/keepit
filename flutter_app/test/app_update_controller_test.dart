import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';

import 'package:keepit/core/updates/app_update_service.dart';
import 'package:keepit/core/updates/update_config.dart';
import 'package:keepit/presentation/controllers/app_update_controller.dart';
import 'package:keepit/presentation/widgets/update_host.dart';

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
    expect(service.immediateStarts, 0);
    expect(service.flexibleStarts, 0);
  });

  test('directly launches Google Play native immediate update when available',
      () async {
    final container = buildContainer();
    final controller = container.read(appUpdateProvider.notifier);

    await controller.check();
    final state = container.read(appUpdateProvider);

    expect(service.immediateStarts, 1);
    expect(state.availableVersionCode, 7);
    expect(state.installedBuildNumber, 6);
    expect(state.phase, AppUpdatePhase.downloading);
  });

  test(
      'falls back to flexible update and auto-completes when immediate is disallowed',
      () async {
    service = _FakeAppUpdateService(
      info: _info(immediateAllowed: false, flexibleAllowed: true),
    );
    final container = buildContainer();
    final controller = container.read(appUpdateProvider.notifier);

    await controller.check();
    await _settle();

    expect(service.immediateStarts, 0);
    expect(service.flexibleStarts, 1);
    expect(service.completions, 1);
  });

  test('dismissing Play update dialog snoozes that build, manual check retries',
      () async {
    service.immediateResult = AppUpdateResult.userDeniedUpdate;
    final container = buildContainer();
    final controller = container.read(appUpdateProvider.notifier);

    await controller.check();
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.idle);
    expect(prefs.version, 7);
    expect(service.immediateStarts, 1);

    // Same build, automatic check → silent.
    await controller.check();
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.upToDate);
    expect(service.immediateStarts, 1);

    // Profile → Check for update still opens Play's update dialog.
    service.immediateResult = AppUpdateResult.success;
    await controller.check(manual: true);
    expect(service.immediateStarts, 2);
  });

  test('completes a previously downloaded flexible update immediately',
      () async {
    service = _FakeAppUpdateService(
      info: _info(installStatus: InstallStatus.downloaded),
    );
    final container = buildContainer();

    await container.read(appUpdateProvider.notifier).check();

    expect(
      container.read(appUpdateProvider).phase,
      AppUpdatePhase.readyToInstall,
    );
    expect(service.completions, 1);
  });

  test('blocks the app below the mandatory build number when refused',
      () async {
    service.immediateResult = AppUpdateResult.userDeniedUpdate;
    final container = buildContainer(
      installedBuild: 5,
      policy: const UpdatePolicy(mandatoryBelowBuildNumber: 6),
    );
    final controller = container.read(appUpdateProvider.notifier);

    await controller.check();
    final state = container.read(appUpdateProvider);

    expect(state.phase, AppUpdatePhase.blocked);
    expect(state.mandatory, isTrue);

    service.immediateResult = AppUpdateResult.success;
    await controller.startMandatoryUpdate();
    expect(service.immediateStarts, 2);
  });

  test('honours the in-app update priority set in Play Console', () async {
    service = _FakeAppUpdateService(info: _info(updatePriority: 4));
    service.immediateResult = AppUpdateResult.userDeniedUpdate;
    final container = buildContainer(
      installedBuild: 99,
      policy: const UpdatePolicy(mandatoryPriority: 4),
    );

    await container.read(appUpdateProvider.notifier).check();

    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.blocked);
  });

  test('does nothing where Play does not exist', () async {
    service = _FakeAppUpdateService(supported: false, info: _info());
    final container = buildContainer();

    await container.read(appUpdateProvider.notifier).check();

    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.unsupported);
  });

  test('a silent Play is never treated as an update', () async {
    service = _FakeAppUpdateService(info: null);
    final container = buildContainer();

    await container.read(appUpdateProvider.notifier).check();
    final state = container.read(appUpdateProvider);

    expect(state.phase, AppUpdatePhase.idle);
  });

  test('onAppResumed re-checks when interval elapsed', () async {
    service = _FakeAppUpdateService(
      info: _info(availability: UpdateAvailability.updateNotAvailable),
    );
    final container = buildContainer(
      policy: const UpdatePolicy(resumeRecheckInterval: Duration.zero),
    );
    final controller = container.read(appUpdateProvider.notifier);

    await controller.check();
    expect(container.read(appUpdateProvider).phase, AppUpdatePhase.upToDate);

    // Later, a new build lands on Play while KeepIt was in the background.
    service.setInfo(_info(availableVersionCode: 8));
    await controller.onAppResumed();
    expect(service.immediateStarts, 1);
  });

  testWidgets('UpdateHost triggers Play native update on startup', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(service),
          updatePreferencesProvider.overrideWithValue(prefs),
          installedBuildNumberProvider.overrideWith((ref) => 6),
        ],
        child: const MaterialApp(
          home: UpdateHost(child: Scaffold(body: Center(child: Text('Home')))),
        ),
      ),
    );

    await tester.pump(UpdateConfig.startupDelay);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(service.immediateStarts, 1);
  });

  testWidgets('replaces the app for a refused mandatory release', (
    tester,
  ) async {
    service.immediateResult = AppUpdateResult.userDeniedUpdate;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(service),
          updatePreferencesProvider.overrideWithValue(prefs),
          updatePolicyProvider.overrideWithValue(
            const UpdatePolicy(mandatoryBelowBuildNumber: 10),
          ),
          installedBuildNumberProvider.overrideWith((ref) => 6),
        ],
        child: const MaterialApp(
          home: UpdateHost(child: Scaffold(body: Center(child: Text('Home')))),
        ),
      ),
    );

    await tester.pump(UpdateConfig.startupDelay);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsNothing);
    expect(find.text('Update required'), findsOneWidget);
  });
}
