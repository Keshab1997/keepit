import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// Regression guard: one malformed timestamp used to make `MindItem.fromMap`
/// throw. Callers treat a throw as "this item is not here" — the card vanished
/// from the feed, sync stopped seeing it, and the next pull could overwrite the
/// copy still sitting in Hive. Parsing must now degrade, never explode.
void main() {
  Map<String, dynamic> raw({Object? createdAt, Object? updatedAt}) => {
        'id': 'x',
        'title': 'Survives',
        'type': 'webArticle',
        'createdAt': createdAt ?? '2026-09-01T00:00:00.000Z',
        'updatedAt': updatedAt ?? '2026-09-02T00:00:00.000Z',
      };

  test('a valid item parses exactly as before', () {
    final item = MindItem.fromMap(raw());
    expect(item.createdAt, DateTime.utc(2026, 9, 1));
    expect(item.updatedAt, DateTime.utc(2026, 9, 2));
  });

  test('a corrupt updatedAt no longer throws', () {
    expect(
        () => MindItem.fromMap(raw(updatedAt: 'not-a-date')), returnsNormally);
    final item = MindItem.fromMap(raw(updatedAt: 'not-a-date'));
    expect(item.title, 'Survives');
    // Falls back to createdAt, which is still the best date we have.
    expect(item.updatedAt, DateTime.utc(2026, 9, 1));
  });

  test('both timestamps corrupt: keep the item, fall back to epoch', () {
    final item = MindItem.fromMap(
      raw(createdAt: 'garbage', updatedAt: 'garbage'),
    );
    expect(item.id, 'x');
    expect(item.createdAt.millisecondsSinceEpoch, 0);
    expect(item.updatedAt.millisecondsSinceEpoch, 0);
  });

  test('missing timestamps do not throw either', () {
    final item = MindItem.fromMap({
      'id': 'y',
      'title': 'No dates',
      'type': 'webArticle',
    });
    expect(item.title, 'No dates');
    expect(item.createdAt.millisecondsSinceEpoch, 0);
  });

  test('epoch millis written as int or numeric string still parse', () {
    final asInt = MindItem.fromMap(
      raw(createdAt: 1700000000000, updatedAt: 1700000000001),
    );
    expect(asInt.createdAt.millisecondsSinceEpoch, 1700000000000);
    final asString = MindItem.fromMap(
      raw(createdAt: '1700000000000', updatedAt: '1700000000001'),
    );
    expect(asString.updatedAt.millisecondsSinceEpoch, 1700000000001);
  });
}
