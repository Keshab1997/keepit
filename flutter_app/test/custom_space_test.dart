import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/domain/entities/custom_space.dart';
import 'package:keepit/domain/entities/mind_item.dart';

void main() {
  test('CustomSpace round-trips through a map', () {
    const original = CustomSpace(
      id: 'ideas',
      name: 'Ideas',
      colorValue: 0xFFFF5B37,
      iconName: 'star',
    );

    final restored = CustomSpace.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.colorValue, original.colorValue);
    expect(restored.iconName, original.iconName);
  });

  test('clearing a Space assignment does not change other item fields', () {
    final item = MindItem(
      id: 'item-1',
      title: 'Saved idea',
      type: ItemType.quickNote,
      spaceId: 'ideas',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final cleared = item.copyWith(clearSpaceId: true);

    expect(cleared.spaceId, isNull);
    expect(cleared.id, item.id);
    expect(cleared.title, item.title);
    expect(cleared.type, item.type);
  });
}
