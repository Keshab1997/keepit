import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/utils/data_export.dart';
import 'package:keepit/core/utils/data_import.dart';
import 'package:keepit/domain/entities/custom_space.dart';
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

  group('spaces (backup format v2)', () {
    const ideas = CustomSpace(
      id: 'space-ideas',
      name: 'Startup ideas',
      colorValue: 0xFF10B981,
      iconName: 'lightbulb',
    );
    const design = CustomSpace(
      id: 'space-design',
      name: 'Design',
      colorValue: 0xFFEC4899,
      iconName: 'palette',
    );

    test('the export is version 2 and carries the spaces', () {
      final json = jsonDecode(
        DataExport.buildJson(
          [item(id: 'a', url: 'https://example.com/a')],
          spaces: const [ideas],
        ),
      ) as Map<String, dynamic>;

      expect(json['version'], 2);
      expect(json['spaceCount'], 1);
      expect(json['spaces'], [
        {
          'id': 'space-ideas',
          'name': 'Startup ideas',
          'colorValue': 0xFF10B981,
          'iconName': 'lightbulb',
          // Spaces now carry their own timestamp, so a restored Space takes
          // part in last-write-wins instead of always losing to the cloud.
          'updatedAt': ideas.effectiveUpdatedAt.toIso8601String(),
        },
      ]);
    });

    test('spaces and their assignments survive a round-trip', () {
      final plan = DataImport.plan(
        DataExport.buildJson(
          [
            MindItem(
              id: 'a',
              title: 'A startup thought',
              type: ItemType.quickNote,
              spaceId: 'space-ideas',
              createdAt: DateTime.utc(2026, 11, 1),
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          ],
          spaces: const [ideas, design],
        ),
      );

      expect(plan.spacesKept, 2);
      expect(plan.spaces.map((s) => s.name), ['Startup ideas', 'Design']);
      expect(plan.items.single.spaceId, 'space-ideas');
      expect(plan.orphanedSpaces, 0);
    });

    test(
        'a space already on the device under another id is not duplicated '
        'and the item is re-pointed at the local one', () {
      final local = [
        const CustomSpace(
          id: 'local-startup',
          name: 'startup ideas',
          colorValue: 0xFFFF5B37,
          iconName: 'folder',
        ),
      ];

      final plan = DataImport.plan(
        DataExport.buildJson(
          [
            MindItem(
              id: 'a',
              title: 'A startup thought',
              type: ItemType.quickNote,
              spaceId: 'space-ideas',
              createdAt: DateTime.utc(2026, 11, 1),
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          ],
          spaces: const [ideas],
        ),
        existingSpaces: local,
      );

      expect(plan.spacesKept, 0);
      expect(plan.spaceDuplicates, 1);
      expect(plan.items.single.spaceId, 'local-startup');
      expect(plan.orphanedSpaces, 0);
    });

    test('a space with a familiar id is a duplicate, not an overwrite', () {
      final plan = DataImport.plan(
        DataExport.buildJson([], spaces: const [ideas]),
        existingSpaces: const [
          CustomSpace(
            id: 'space-ideas',
            name: 'Renamed on this device',
            colorValue: 0xFF000000,
            iconName: 'folder',
          ),
        ],
      );

      expect(plan.spacesKept, 0);
      expect(plan.spaceDuplicates, 1);
    });

    test(
        'an assignment to a space that exists nowhere is dropped, not '
        'left dangling', () {
      final plan = DataImport.plan(
        DataExport.buildJson([
          MindItem(
            id: 'a',
            title: 'Homeless',
            type: ItemType.quickNote,
            spaceId: 'space-gone',
            createdAt: DateTime.utc(2026, 11, 1),
            updatedAt: DateTime.utc(2026, 11, 1),
          ),
        ]),
      );

      expect(plan.items.single.spaceId, isNull);
      expect(plan.orphanedSpaces, 1);
    });

    test('a v1 backup (no spaces key) still restores its items', () {
      final v1 = jsonEncode({
        'app': 'KeepIt',
        'format': 'keepit-export',
        'version': 1,
        'count': 1,
        'items': [
          {'id': 'old', 'title': 'From v1', 'spaceId': 'space-ideas'},
        ],
      });

      final plan = DataImport.plan(
        v1,
        existingSpaces: const [
          CustomSpace(
            id: 'space-ideas',
            name: 'Startup ideas',
            colorValue: 0xFF10B981,
            iconName: 'lightbulb',
          ),
        ],
      );

      expect(plan.kept, 1);
      expect(plan.spacesKept, 0);
      expect(plan.items.single.spaceId, 'space-ideas');
      expect(plan.orphanedSpaces, 0);
    });

    test('a nameless space is skipped, the rest of the restore still runs', () {
      final json = jsonEncode({
        'format': 'keepit-export',
        'version': 2,
        'items': [
          {'id': 'ok', 'title': 'Fine'},
        ],
        'spaces': [
          {'id': 'nameless', 'name': '   '},
          {'id': 'real', 'name': 'Reading list'},
        ],
      });

      final plan = DataImport.plan(json);

      expect(plan.spacesKept, 1);
      expect(plan.spaces.single.name, 'Reading list');
      expect(plan.spaceMalformed, 1);
      expect(plan.kept, 1);
    });
  });
}
