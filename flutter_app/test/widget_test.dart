// Smoke tests for the KeepIt app.
//
// Hive is initialized in a temp directory so the widget tree can be pumped
// without any platform channels or network access.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/core/theme/app_theme.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/main.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';
import 'package:keepit/presentation/screens/home_screen.dart';

void main() {
  late Directory tempDir;
  late LocalMindDataSource dataSource;

  setUpAll(() async {
    // Use an isolated Hive directory for tests.
    tempDir = await Directory.systemTemp.createTemp('keepit_test_');
    Hive.init(tempDir.path);
    dataSource = LocalMindDataSource();
    await dataSource.init();
    // Pre-seed one item (no thumbnail, so no network image in widget tests).
    // Pre-seeding here, in the regular zone, also keeps the widget test
    // read-only: MindFeedController skips its demo-data seeding when the box
    // already has items, which avoids Hive writes under FakeAsync.
    await dataSource.saveItem(
      MindItem(
        id: 'seed-1',
        title: 'Seed note',
        type: ItemType.quickNote,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  });

  tearDownAll(() async {
    // Hive.close() can block if a write future was created in a zone that has
    // already ended, so guard it to keep the test suite from hanging.
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore: closing is best-effort in tests.
    }
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Ignore cleanup failures.
    }
  });

  testWidgets('HomeScreen renders the bottom navigation tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDataSourceProvider.overrideWithValue(dataSource)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const HomeScreen(),
        ),
      ),
    );
    // First frame + one frame for MindFeedController.loadItems() to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Everything'), findsOneWidget);
    expect(find.text('Spaces'), findsOneWidget);
    expect(find.text('Serendipity'), findsOneWidget);
  });

  test('LocalMindDataSource saves and reads back items', () async {
    final before = await dataSource.getAllItems();
    expect(before.any((i) => i.id == 'seed-1'), isTrue);

    final item = MindItem(
      id: 'test-1',
      title: 'Test note',
      type: ItemType.quickNote,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    await dataSource.saveItem(item);
    final items = await dataSource.getAllItems();

    expect(
      items.any((i) => i.id == 'test-1' && i.title == 'Test note'),
      isTrue,
    );

    await dataSource.deleteItem('test-1');
    final afterDelete = await dataSource.getAllItems();
    expect(afterDelete.any((i) => i.id == 'test-1'), isFalse);
  });

  test('KeepItApp is exported from main.dart', () {
    expect(const KeepItApp(), isA<ConsumerStatefulWidget>());
  });
}
