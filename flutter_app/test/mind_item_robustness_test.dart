import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// Every caller of [MindItem.fromMap] treats a throw as "this item does not
/// exist" and skips it:
///
///   * `getAllItems` drops it from the feed
///   * `getUnsyncedItems` drops it from the upload
///   * `SyncEngine` `continue`s, so the cloud copy is never pulled back
///
/// The record stays on disk, so the card is gone for good. One malformed field
/// must cost that field only.
void main() {
  Map<String, dynamic> base() => {
        'id': 'a',
        'title': 'A saved reel',
        'type': 'instagramReel',
        'createdAt': DateTime.utc(2026, 11, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 11, 1).toIso8601String(),
      };

  test('a normal record is unaffected', () {
    final item = MindItem.fromMap({
      ...base(),
      'tags': ['design', 'ui'],
      'isWatched': true,
    });
    expect(item.tags, ['design', 'ui']);
    expect(item.isWatched, isTrue);
    expect(item.type, ItemType.instagramReel);
  });

  group('tolerates a malformed field instead of dropping the item', () {
    test('tags stored as a bare string', () {
      final item = MindItem.fromMap({...base(), 'tags': 'design'});
      expect(item.title, 'A saved reel');
      expect(item.tags, ['design']);
    });

    test('tags list containing nulls and non-strings', () {
      final item = MindItem.fromMap({
        ...base(),
        'tags': [null, 'ui', 42, '  '],
      });
      expect(item.tags, ['ui', '42']);
    });

    test('tags of the wrong shape entirely', () {
      final item = MindItem.fromMap({...base(), 'tags': 7});
      expect(item.tags, ['7']);
      expect(MindItem.fromMap({...base(), 'tags': true}).tags, ['true']);
    });

    test('a numeric id-shaped url, title and flags', () {
      final item = MindItem.fromMap({
        ...base(),
        'url': 12345,
        'isWatched': 'true',
        'isTopMind': 1,
        'isSynced': 'yes',
      });
      expect(item.title, 'A saved reel');
      expect(item.url, '12345');
      expect(item.isWatched, isTrue);
      expect(item.isTopMind, isTrue);
      expect(item.isSynced, isFalse, reason: '"yes" is not a truthy flag');
    });

    test('extra unknown keys are ignored', () {
      final item = MindItem.fromMap({
        ...base(),
        'futureField': {'a': 1}
      });
      expect(item.id, 'a');
    });
  });

  test('an unknown type falls back to webArticle, not a throw', () {
    expect(
      MindItem.fromMap({...base(), 'type': 'instagram_reel'}).type,
      ItemType.webArticle,
    );
    expect(
        MindItem.fromMap({...base(), 'type': null}).type, ItemType.webArticle);
  });

  test('a round-trip of a fully populated item is lossless', () {
    final original = MindItem(
      id: 'x',
      title: 'T',
      url: 'https://example.com/a',
      content: 'body',
      thumbnailUrl: 'https://example.com/i.jpg',
      authorName: 'Someone',
      type: ItemType.webArticle,
      tags: const ['a', 'b'],
      spaceId: 's1',
      isWatched: true,
      isTopMind: true,
      createdAt: DateTime.utc(2026, 11, 1, 9),
      updatedAt: DateTime.utc(2026, 11, 2, 10),
      isSynced: true,
    );

    final back = MindItem.fromMap(original.toMap());
    expect(back.title, original.title);
    expect(back.url, original.url);
    expect(back.content, original.content);
    expect(back.thumbnailUrl, original.thumbnailUrl);
    expect(back.authorName, original.authorName);
    expect(back.type, original.type);
    expect(back.tags, original.tags);
    expect(back.spaceId, original.spaceId);
    expect(back.isWatched, isTrue);
    expect(back.isTopMind, isTrue);
    expect(back.isSynced, isTrue);
    expect(back.createdAt.isAtSameMomentAs(original.createdAt), isTrue);
    expect(back.updatedAt.isAtSameMomentAs(original.updatedAt), isTrue);
  });
}
