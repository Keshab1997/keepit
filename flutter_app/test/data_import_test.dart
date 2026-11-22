import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/utils/data_export.dart';
import 'package:keepit/core/utils/data_import.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// `DataImport` is the other half of `DataExport`: what the app writes out has
/// to survive a round-trip, and a restore must never double the library.
///
/// These are pure-Dart tests on purpose - the plan is decided before anything
/// touches Hive, which is exactly what makes "what would this restore do?"
/// answerable without a database.
void main() {
  MindItem item({
    required String id,
    String? url,
    String title = 'A saved thing',
    List<String> tags = const ['ai'],
    DateTime? createdAt,
  }) {
    final stamp = createdAt ?? DateTime.utc(2026, 11, 1, 9, 30);
    return MindItem(
      id: id,
      title: title,
      url: url,
      type: url == null ? ItemType.quote : ItemType.webArticle,
      tags: tags,
      content: 'Body text',
      isWatched: true,
      isTopMind: true,
      dominantColorHex: '#FF5B37',
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  String exportOf(List<MindItem> items) => DataExport.buildJson(items);

  group('round-trip against DataExport', () {
    test('an export of N items restores all N into an empty library', () {
      final items = [
        item(id: 'a', url: 'https://example.com/one'),
        item(id: 'b', url: 'https://example.com/two', tags: ['design', 'ui']),
        item(id: 'c'),
      ];

      final plan = DataImport.plan(exportOf(items));

      expect(plan.kept, 3);
      expect(plan.duplicates, 0);
      expect(plan.malformed, 0);
      expect(plan.total, 3);
      expect(plan.items.map((i) => i.id), ['a', 'b', 'c']);
    });

    test('every field the app cares about survives the trip', () {
      final original = item(
        id: 'x1',
        url: 'https://example.com/keep',
        title: 'Cinematic grading',
        tags: ['color', 'photo'],
      );

      final restored = DataImport.plan(exportOf([original])).items.single;

      expect(restored.title, original.title);
      expect(restored.url, original.url);
      expect(restored.content, original.content);
      expect(restored.tags, original.tags);
      expect(restored.type, original.type);
      expect(restored.isWatched, isTrue);
      expect(restored.isTopMind, isTrue);
      expect(restored.dominantColorHex, original.dominantColorHex);
      // UTC instants, not local ones: a restored date must be the same moment.
      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.createdAt, original.createdAt);
    });

    test('restored items are marked unsynced so Cloud Sync uploads them', () {
      final original = item(id: 'sync-me', url: 'https://example.com/s');
      final restored = DataImport.plan(exportOf([original])).items.single;
      expect(restored.isSynced, isFalse);
    });
  });

  group('duplicates', () {
    test('an id already on the device is skipped', () {
      final existing = [item(id: 'a', url: 'https://example.com/one')];
      final plan = DataImport.plan(
        exportOf([item(id: 'a', url: 'https://example.com/one')]),
        existing: existing,
      );
      expect(plan.kept, 0);
      expect(plan.duplicates, 1);
    });

    test('the same link under another id is skipped, tracking params ignored',
        () {
      final existing = [item(id: 'local', url: 'https://example.com/post')];
      final plan = DataImport.plan(
        exportOf([
          item(
            id: 'from-backup',
            url: 'https://www.example.com/post/?utm_source=ig&igsh=abc',
          ),
        ]),
        existing: existing,
      );
      expect(plan.kept, 0);
      expect(plan.duplicates, 1);
    });

    test('two entries inside one file that share a link collapse to one', () {
      final plan = DataImport.plan(
        exportOf([
          item(id: 'one', url: 'https://example.com/same'),
          item(id: 'two', url: 'http://www.example.com/same/'),
        ]),
      );
      expect(plan.kept, 1);
      expect(plan.items.single.id, 'one');
      expect(plan.duplicates, 1);
    });

    test('a note without a link is never a URL duplicate', () {
      final existing = [item(id: 'n1')];
      final plan = DataImport.plan(
        exportOf([item(id: 'n2'), item(id: 'n3')]),
        existing: existing,
      );
      expect(plan.kept, 2);
    });
  });

  group('damaged input', () {
    test('not JSON at all throws ImportFormatException', () {
      expect(
        () => DataImport.plan('kopi theke ber kora text noi'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('valid JSON that is not a backup throws', () {
      expect(
        () => DataImport.plan('{"hello":"world"}'),
        throwsA(isA<ImportFormatException>()),
      );
      expect(
        () => DataImport.plan('[1,2,3]'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test("another app's format is refused instead of guessed at", () {
      final json = jsonEncode({
        'format': 'notion-export',
        'items': [
          {'id': 'a', 'title': 'x'},
        ],
      });
      expect(
        () => DataImport.plan(json),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('one unreadable entry costs that entry, not the restore', () {
      final good =
          jsonDecode(exportOf([item(id: 'ok')])) as Map<String, dynamic>;
      final entries = [
        ...good['items'] as List,
        'a string where an object belongs',
        {'title': 'no id at all'},
        {'id': '', 'title': 'empty id'},
      ];

      final plan = DataImport.plan(jsonEncode({...good, 'items': entries}));

      expect(plan.kept, 1);
      expect(plan.malformed, 3);
    });

    test('a hand-edited file with a bare-string tag still restores', () {
      final json = jsonEncode({
        'format': 'keepit-export',
        'items': [
          {'id': 'legacy', 'title': 'Old card', 'tags': 'ai'},
        ],
      });
      final plan = DataImport.plan(json);
      expect(plan.items.single.tags, ['ai']);
    });

    test('a missing count is counted from the list', () {
      final json = jsonEncode({
        'format': 'keepit-export',
        'items': [
          {'id': 'a', 'title': 'one'},
          {'id': 'b', 'title': 'two'},
        ],
      });
      expect(DataImport.plan(json).total, 2);
    });
  });
}
