import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/core/cloud/auth_service.dart';
import 'package:keepit/core/cloud/cloud_sync_remote.dart';
import 'package:keepit/core/theme/app_theme.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/cloud_sync_controller.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';
import 'package:keepit/presentation/controllers/navigation_controller.dart';
import 'package:keepit/presentation/screens/home_screen.dart';

class _FakeSignedInAuth implements AuthService {
  static const user = AppUser(
      uid: 'u1', displayName: 'Keshab Sarkar', email: 'keshab@example.com');
  @override
  bool get isAvailable => true;
  @override
  AppUser? get currentUser => user;
  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(user);
  @override
  Future<AppUser> signInWithGoogle() async => user;
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

class _EmptyRemote implements CloudSyncRemote {
  int pushed = 0;
  @override
  Future<List<RemoteRecord>> fetchChanges(String uid,
          {int sinceServerMillis = 0}) async =>
      const [];
  @override
  Future<void> push(String uid,
          {List<RemoteRecord> upserts = const [],
          Map<String, int> deletions = const {}}) async =>
      pushed += upserts.length;
  @override
  Future<void> deleteAllUserData(String uid) async {}
  @override
  Future<int> countItems(String uid) async => pushed;
}

void main() {
  late Directory tempDir;
  late LocalMindDataSource dataSource;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('keepit_profile_');
    Hive.init(tempDir.path);
    dataSource = LocalMindDataSource();
    await dataSource.init();
    // Widget tests run in FakeAsync where Hive writes never complete, so turn
    // off auto-sync up front (real zone) for the signed-in widget test.
    await dataSource.putMeta('auto_sync_enabled', false);
    await dataSource.saveItem(MindItem(
      id: 'p1',
      title: 'Saved thing',
      type: ItemType.quickNote,
      isWatched: true,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    ));
  });

  tearDownAll(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<ProviderContainer> pumpProfile(WidgetTester tester,
      {AuthService? auth, CloudSyncRemote? remote}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      localDataSourceProvider.overrideWithValue(dataSource),
      if (auth != null) authServiceProvider.overrideWithValue(auth),
      if (auth != null) cloudSyncRemoteProvider.overrideWithValue(remote),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
    ));
    await tester.pump();
    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return container;
  }

  testWidgets('Profile tab shows guest state and offline cloud card',
      (tester) async {
    final container = await pumpProfile(tester);
    expect(container.read(homeTabProvider), HomeTab.profile);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Saved only on this device'), findsOneWidget);
    expect(find.text('Cloud sync not set up yet'), findsOneWidget);
    expect(find.text('Export my data'), findsOneWidget);
    expect(find.text('Serendipity reminders'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Privacy policy'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of service'), findsOneWidget);
    expect(find.text('Delete all local data'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing); // only when signed in
  });

  testWidgets(
      'Signed-in profile shows account, sync controls and delete account',
      (tester) async {
    final remote = _EmptyRemote();
    await pumpProfile(tester, auth: _FakeSignedInAuth(), remote: remote);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Keshab Sarkar'), findsOneWidget);
    expect(find.text('keshab@example.com'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Auto sync'), findsOneWidget);
    expect(find.textContaining('1 pending'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Delete account'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Delete all local data'), findsNothing);

    // Delete account requires typing DELETE.
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Delete account');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  test('CloudSyncController auto-syncs on sign-in and reports success',
      () async {
    await dataSource.putMeta('auto_sync_enabled', true);
    final remote = _EmptyRemote();
    final container = ProviderContainer(overrides: [
      localDataSourceProvider.overrideWithValue(dataSource),
      authServiceProvider.overrideWithValue(_FakeSignedInAuth()),
      cloudSyncRemoteProvider.overrideWithValue(remote),
    ]);
    addTearDown(container.dispose);
    await container.read(mindFeedProvider.notifier).ready;
    container.read(cloudSyncProvider);
    for (var i = 0; i < 100; i++) {
      final s = container.read(cloudSyncProvider);
      if (s.signedIn && s.status == SyncStatus.success) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final state = container.read(cloudSyncProvider);
    expect(state.user?.email, 'keshab@example.com');
    expect(state.status, SyncStatus.success);
    expect(state.lastSyncAt, isNotNull);
    expect(state.pendingChanges, 0);
    expect(remote.pushed, greaterThanOrEqualTo(1));

    // Manual sync is a no-op now.
    final report = await container.read(cloudSyncProvider.notifier).syncNow();
    expect(report?.summary, 'Everything is up to date');
  });
}
