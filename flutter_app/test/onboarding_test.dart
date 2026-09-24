import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/data/datasources/local_mind_datasource.dart';
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
  });

  tearDownAll(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
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

  testWidgets('Next walks through all four pages', (tester) async {
    await pumpOnboarding(tester);

    expect(find.text('Save anything in one tap'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your visual second brain'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Never forget what you save'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Private by design'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('Skip stores the flag and opens the home screen',
      (tester) async {
    await dataSource.putMeta(LocalMindDataSource.onboardingSeenKey, null);
    await pumpOnboarding(tester);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

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
    await dataSource.putMeta(LocalMindDataSource.onboardingSeenKey, null);
    await pumpOnboarding(tester);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      dataSource.getMeta<bool>(LocalMindDataSource.onboardingSeenKey),
      isTrue,
    );
    expect(find.text('Everything'), findsOneWidget);
  });
}
