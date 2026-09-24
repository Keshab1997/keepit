import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';
import 'package:keepit/presentation/screens/onboarding_screen.dart';

/// Keeps the sync/meta box in memory for the widget tests.
///
/// A Hive write issued from a widget test's fake-async zone never completes,
/// so the onboarding flag write — and the navigation that waits for it —
/// could never be observed. Saved items still live in a real Hive box, so
/// HomeScreen and MindFeedController behave exactly as they do in the app.
class _InMemoryMetaDataSource extends LocalMindDataSource {
  final Map<String, Object?> _metaValues = <String, Object?>{};

  @override
  T? getMeta<T>(String key) {
    final value = _metaValues[key];
    return value is T ? value : null;
  }

  @override
  Future<void> putMeta(String key, Object? value) async {
    if (value == null) {
      _metaValues.remove(key);
    } else {
      _metaValues[key] = value;
    }
  }
}

void main() {
  late Directory tempDir;
  late LocalMindDataSource dataSource;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('keepit_onboarding_');
    Hive.init(tempDir.path);
    dataSource = _InMemoryMetaDataSource();
    await dataSource.init();
    // Seed one item so MindFeedController skips its demo-data seeding, which
    // would write to Hive from inside the test's fake-async zone.
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

  /// Finishing onboarding navigates once the flag is stored.
  Future<void> finishOnboarding(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
  }

  bool onboardingSeenFlag() =>
      dataSource.getMeta<bool>(LocalMindDataSource.onboardingSeenKey) == true;

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
      onboardingSeenFlag(),
      isTrue,
      reason: 'Skip did not persist the onboarding flag',
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
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await finishOnboarding(tester);

    expect(
      onboardingSeenFlag(),
      isTrue,
      reason: 'Get started did not persist the onboarding flag',
    );
    expect(find.text('Everything'), findsOneWidget);
  });
}
