import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:keepit/core/theme/app_theme.dart';
import 'package:keepit/data/datasources/local_mind_datasource.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/controllers/mind_feed_controller.dart';
import 'package:keepit/presentation/widgets/clipboard_prompt_banner.dart';

class _InMemoryMetaDataSource extends LocalMindDataSource {
  final Map<String, Object?> _metaValues = <String, Object?>{};
  final List<MindItem> _memoryItems = <MindItem>[];

  @override
  Future<List<MindItem>> getAllItems() async =>
      List<MindItem>.from(_memoryItems);

  @override
  Future<void> saveItem(MindItem item, {bool synced = false}) async {
    _memoryItems.removeWhere((i) => i.id == item.id);
    _memoryItems.insert(0, item);
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
    tempDir = await Directory.systemTemp.createTemp('keepit_clipboard_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('ClipboardLinkCandidate recognises popular sources and rejects text',
      () {
    expect(ClipboardLinkCandidate.tryParse(null), isNull);
    expect(ClipboardLinkCandidate.tryParse(''), isNull);
    expect(ClipboardLinkCandidate.tryParse('482910'), isNull);
    expect(
      ClipboardLinkCandidate.tryParse('check https://youtube.com out'),
      isNull,
    );

    final yt = ClipboardLinkCandidate.tryParse(
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    expect(yt, isNotNull);
    expect(yt!.headline, 'Save YouTube video?');
    expect(yt.displayUrl, 'youtube.com/watch');

    final reel = ClipboardLinkCandidate.tryParse(
      'https://www.instagram.com/reel/C_abc123/',
    );
    expect(reel, isNotNull);
    expect(reel!.headline, 'Save Instagram Reel?');

    final gh = ClipboardLinkCandidate.tryParse(
      'https://github.com/Keshab1997/keepit',
    );
    expect(gh, isNotNull);
    expect(gh!.headline, 'Save GitHub link?');
  });

  testWidgets('prompts once for a new clipboard URL and saves in one tap', (
    tester,
  ) async {
    final dataSource = _InMemoryMetaDataSource();
    await dataSource.putMeta(LocalMindDataSource.demoSeededKey, true);
    String? clipboardText = 'https://www.youtube.com/watch?v=abc123';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDataSourceProvider.overrideWithValue(dataSource),
          clipboardReaderProvider.overrideWithValue(() async => clipboardText),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: ClipboardPromptBanner(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Save YouTube video?'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    // Dismissing hides the prompt and records the URL so resuming with the
    // same clipboard does not nag a second time.
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Save YouTube video?'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Save YouTube video?'), findsNothing);

    // Copying a fresh Instagram Reel and resuming brings the prompt back.
    clipboardText = 'https://www.instagram.com/reel/XYZ987/?igsh=tracking';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Save Instagram Reel?'), findsOneWidget);

    // Let the auto-hide timer expire cleanly before tearing down.
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Save Instagram Reel?'), findsNothing);
  });

  testWidgets('skips URLs that are already saved in the library', (
    tester,
  ) async {
    final dataSource = _InMemoryMetaDataSource();
    await dataSource.putMeta(LocalMindDataSource.demoSeededKey, true);
    await dataSource.saveItem(
      MindItem(
        id: 'existing-1',
        title: 'Already saved',
        url: 'https://github.com/Keshab1997/keepit',
        type: ItemType.webArticle,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDataSourceProvider.overrideWithValue(dataSource),
          clipboardReaderProvider.overrideWithValue(
            () async => 'https://github.com/Keshab1997/keepit/?utm_source=x',
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: ClipboardPromptBanner()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Save GitHub link?'), findsNothing);
  });
}
