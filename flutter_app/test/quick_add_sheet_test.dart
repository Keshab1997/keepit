import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/core/theme/app_theme.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';
import 'package:keepit/presentation/screens/mind_feed_screen.dart';
import 'package:keepit/presentation/widgets/clipboard_prompt_banner.dart';
import 'package:keepit/presentation/widgets/quick_add_sheet.dart';

class _MemoryDataSource extends LocalMindDataSource {
  final Map<String, Object?> _metaValues = <String, Object?>{};
  final List<MindItem> _items = <MindItem>[];

  @override
  Future<List<MindItem>> getAllItems() async => List<MindItem>.from(_items);

  @override
  Future<void> saveItem(MindItem item, {bool synced = false}) async {
    _items.removeWhere((existing) => existing.id == item.id);
    _items.insert(0, item);
  }

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

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('keepit_quick_add_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required _MemoryDataSource dataSource,
    required String? clipboardText,
  }) async {
    await dataSource.putMeta(LocalMindDataSource.demoSeededKey, true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDataSourceProvider.overrideWithValue(dataSource),
          clipboardReaderProvider.overrideWithValue(
            () async => clipboardText,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAddSheet(
              onPickImage: () async {},
              onLinkSaved: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('prefills a copied link and previews its source', (tester) async {
    final dataSource = _MemoryDataSource();
    const copiedUrl = 'https://www.youtube.com/watch?v=abc123';
    await pumpSheet(
      tester,
      dataSource: dataSource,
      clipboardText: copiedUrl,
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, copiedUrl);
    expect(find.text('Link found in clipboard'), findsOneWidget);
    expect(find.text('YouTube video'), findsOneWidget);
    expect(find.text('youtube.com/watch'), findsOneWidget);
    expect(find.text('KeepIt will find the title and preview for you.'),
        findsOneWidget);

    final saveButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(saveButton.onPressed, isNotNull);
    expect(find.text('Choose an image from gallery'), findsOneWidget);
  });

  testWidgets('detects a duplicate and blocks saving it', (tester) async {
    final dataSource = _MemoryDataSource();
    await dataSource.saveItem(
      MindItem(
        id: 'existing-youtube',
        title: 'Already saved',
        url: 'https://www.youtube.com/watch?v=abc123',
        type: ItemType.youtubeVideo,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    );

    await pumpSheet(
      tester,
      dataSource: dataSource,
      clipboardText: 'https://www.youtube.com/watch?v=abc123&utm_source=copy',
    );

    expect(find.text('Already in your Mind'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(saveButton.onPressed, isNull);
    expect(find.text('Already saved'), findsOneWidget);
  });

  testWidgets('asks for a valid URL before enabling save', (tester) async {
    final dataSource = _MemoryDataSource();
    await pumpSheet(
      tester,
      dataSource: dataSource,
      clipboardText: null,
    );

    await tester.enterText(find.byType(TextField), 'not a link');
    await tester.pump();

    expect(
      find.text('Add a complete link starting with http:// or https://.'),
      findsOneWidget,
    );
    final saveButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('plus button opens the new quick-add sheet', (tester) async {
    final dataSource = _MemoryDataSource();
    await dataSource.putMeta(LocalMindDataSource.demoSeededKey, true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDataSourceProvider.overrideWithValue(dataSource),
          clipboardReaderProvider.overrideWithValue(() async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MindFeedScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('quick_add_button')));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddSheet), findsOneWidget);
    expect(find.text('Quick save'), findsOneWidget);
    expect(find.text('Choose an image from gallery'), findsOneWidget);
  });
}
