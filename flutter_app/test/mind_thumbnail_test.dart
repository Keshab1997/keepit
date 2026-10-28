// Widget tests for the persistent thumbnail card image.
//
// The permanent store is redirected to a temp directory and all HTTP goes
// through an in-memory MockClient, so no platform channels or sockets are
// touched.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:keepit/core/theme/app_theme.dart';
import 'package:keepit/core/utils/thumbnail_store.dart';
import 'package:keepit/presentation/widgets/mind_thumbnail.dart';

/// Gives the widget several real event-loop cycles to finish its internal
/// file checks (pumps drain the fake zone, real I/O lands between them).
Future<void> pumpLoad(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDw'
    'AEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('keepit_widget_thumbs_');
    ThumbnailStore.debugDirectory = tempDir;
  });

  tearDown(() {
    ThumbnailStore.debugDirectory = null;
    ThumbnailStore.debugClient = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('serves a stored thumbnail without any network call', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(
      () => ThumbnailStore.save('https://img.test/cached.jpg', pngBytes),
    );
    var calls = 0;
    ThumbnailStore.debugClient = MockClient((request) async {
      calls += 1;
      return http.Response('', 500);
    });

    await tester.pumpWidget(
      wrap(const MindThumbnail(url: 'https://img.test/cached.jpg')),
    );
    await pumpLoad(tester);

    expect(find.byType(Image), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('downloads, stores and renders a first-time thumbnail', (
    WidgetTester tester,
  ) async {
    ThumbnailStore.debugClient = MockClient((request) async {
      return http.Response.bytes(pngBytes, 200);
    });

    await tester.pumpWidget(
      wrap(const MindThumbnail(url: 'https://img.test/fresh.jpg')),
    );
    await pumpLoad(tester);

    expect(find.byType(Image), findsOneWidget);
    final stored = await tester.runAsync(
      () => ThumbnailStore.fileFor('https://img.test/fresh.jpg'),
    );
    expect(stored, isNotNull);
  });

  testWidgets('shows the fallback icon when the source is gone', (
    WidgetTester tester,
  ) async {
    ThumbnailStore.debugClient = MockClient((request) async {
      return http.Response('', 403);
    });

    await tester.pumpWidget(
      wrap(const MindThumbnail(url: 'https://img.test/dead.jpg')),
    );
    await pumpLoad(tester);

    expect(find.byIcon(LucideIcons.image), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
