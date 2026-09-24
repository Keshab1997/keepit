import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/core/theme/app_theme.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';
import 'package:keepit/presentation/controllers/navigation_controller.dart';
import 'package:keepit/presentation/screens/home_screen.dart';
import 'package:keepit/presentation/widgets/notification_host.dart';

void main() {
  late Directory tempDir;
  late LocalMindDataSource dataSource;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('keepit_reminder_ui_');
    Hive.init(tempDir.path);
    dataSource = LocalMindDataSource();
    await dataSource.init();
    await dataSource.saveItem(
      MindItem(
        id: 'old-1',
        title: 'A reel I saved and forgot',
        type: ItemType.instagramReel,
        createdAt: DateTime.now().subtract(const Duration(days: 4)),
        updatedAt: DateTime.now(),
      ),
    );
  });

  tearDownAll(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('Serendipity bell opens the reminder settings sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final navKey = GlobalKey<NavigatorState>();
    final container = ProviderContainer(
      overrides: [localDataSourceProvider.overrideWithValue(dataSource)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NotificationHost(
          navigatorKey: navKey,
          child: MaterialApp(
            navigatorKey: navKey,
            theme: AppTheme.lightTheme,
            home: const HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Switching tabs through the provider (as notification deep links do).
    container.read(homeTabProvider.notifier).state = HomeTab.serendipity;
    await tester.pump();
    expect(find.text('DAILY RECALL SPARK'), findsOneWidget);
    expect(find.byTooltip('Remind me in 1 week'), findsOneWidget);

    await tester.tap(find.byTooltip('Reminder settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Serendipity Reminders'), findsOneWidget);
    expect(find.text('Daily Spark'), findsOneWidget);
    expect(find.text('Reminder time'), findsOneWidget);
    expect(find.text('Sunday Mind Digest'), findsWidgets);
    expect(find.text('COMING UP'), findsOneWidget);

    // Let debounce timers / animations settle before teardown.
    await tester.pump(const Duration(seconds: 2));
  });
}
