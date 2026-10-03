import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/core/theme/app_palette.dart';
import 'package:keepit/core/theme/app_theme.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/theme_mode_controller.dart';
import 'package:keepit/presentation/widgets/mind_card_widget.dart';

/// Keeps the meta box in memory: a Hive write from a test's fake-async zone
/// never completes, and this test is about what gets stored, not about Hive.
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
    tempDir = await Directory.systemTemp.createTemp('keepit_theme_');
    Hive.init(tempDir.path);
    dataSource = _InMemoryMetaDataSource();
    await dataSource.init();
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

  test('starts out following the system', () {
    expect(ThemeModeController(dataSource).state, ThemeMode.system);
  });

  test('a chosen mode survives a restart', () async {
    final controller = ThemeModeController(dataSource);
    await controller.setMode(ThemeMode.dark);

    expect(dataSource.getMeta<String>(ThemeModeController.metaKey), 'dark');
    // A fresh controller is what the next launch constructs.
    expect(ThemeModeController(dataSource).state, ThemeMode.dark);
  });

  test('every mode round-trips through storage', () async {
    for (final mode in ThemeMode.values) {
      await ThemeModeController(dataSource).setMode(mode);
      expect(ThemeModeController(dataSource).state, mode);
    }
  });

  test('an unrecognised stored value falls back to system', () async {
    await dataSource.putMeta(ThemeModeController.metaKey, 'sepia');
    expect(ThemeModeController(dataSource).state, ThemeMode.system);
  });

  testWidgets('AppTheme registers light and dark AppPalette extensions', (
    tester,
  ) async {
    final light = AppTheme.lightTheme.extension<AppPalette>();
    final dark = AppTheme.darkTheme.extension<AppPalette>();
    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.isDark, isFalse);
    expect(dark!.isDark, isTrue);
  });

  testWidgets('MindCardWidget uses dark palette surface in dark mode', (
    tester,
  ) async {
    final item = MindItem(
      id: 'card-1',
      title: 'Dark Mode Title',
      content: 'Visible on dark surface',
      type: ItemType.quickNote,
      createdAt: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 3),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: MindCardWidget(item: item, onTap: () {}, onLongPress: () {}),
        ),
      ),
    );

    expect(find.text('Dark Mode Title'), findsOneWidget);
    final containers = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(MindCardWidget),
            matching: find.byType(Container),
          ),
        )
        .toList();
    final cardSurface = containers.first.decoration as BoxDecoration?;
    expect(cardSurface?.color, AppPalette.dark.surface);
  });
}
