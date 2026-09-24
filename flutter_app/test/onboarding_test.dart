import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';
import 'package:keepit/presentation/screens/onboarding_screen.dart';

void main() {
  late Directory tempDir;
  late LocalMindDataSource dataSource;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('keepit_onboarding_');
    Hive.init(tempDir.path);
    dataSource = LocalMindDataSource();
    await dataSource.init();
    // Pre-seed one item so MindFeedController skips its demo-data seeding:
    // seeding writes to Hive from inside the test's fake-async zone, where
    // those writes never complete.
    await dataSource.saveItem(
      MindItem(
        id: 'onboarding-seed',
        title: 'Seed note',
        type: ItemType.quickNote,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  });

  tearDownAll(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Closing is best-effort in tests.
    }
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Ignore cleanup failures.
    }
  });

  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDataSourceProvider.overrideWithValue(dataSource)],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pump();
  }

  /// A page turn is a fixed 350 ms animation, so a fixed-duration pump is
  /// deterministic and never waits on unrelated scheduled frames.
  Future<void> turnPage(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Finishing onboarding persists a flag in Hive (real async file I/O) and
  /// only then navigates, so the real event loop has to be drained with
  /// runAsync before the frame that contains HomeScreen is pumped.
  Future<void> finishOnboarding(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Next walks through all four pages', (tester) async {
    await pumpOnboarding(tester);

    expect(find.text('Save anything in one tap'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);

    await tester.tap(find.text('Next'));
    await turnPage(tester);
    expect(find.text('Your visual second brain'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await turnPage(tester);
    expect(find.text('Never forget what you save'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await turnPage(tester);
    expect(find.text('Private by design'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('Skip stores the flag and opens the home screen', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('Skip'));
    await finishOnboarding(tester);

    // Flag persisted, so onboarding never shows again.
    expect(
      dataSource.getMeta<bool>(LocalMindDataSource.onboardingSeenKey),
      isTrue,
    );
    // Home screen (bottom navigation) took over.
    expect(find.text('Everything'), findsOneWidget);
    expect(find.text('Serendipity'), findsOneWidget);
  });

  testWidgets('Get started on the last page also completes onboarding',
      (tester) async {
    await pumpOnboarding(tester);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await turnPage(tester);
    }
    await tester.tap(find.text('Get started'));
    await finishOnboarding(tester);

    expect(
      dataSource.getMeta<bool>(LocalMindDataSource.onboardingSeenKey),
      isTrue,
    );
    expect(find.text('Everything'), findsOneWidget);
  });
}
