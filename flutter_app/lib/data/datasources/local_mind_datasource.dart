import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/mind_item.dart';

class LocalMindDataSource {
  static const String boxName = 'mind_items_box';
  Box? _box;

  Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      _box = await Hive.openBox(boxName);
    } else {
      _box = Hive.box(boxName);
    }
  }

  Box get box {
    if (_box == null || !_box!.isOpen) {
      throw Exception('Hive Box is not initialized.');
    }
    return _box!;
  }

  Future<List<MindItem>> getAllItems() async {
    final rawData = box.values.toList();
    final List<MindItem> items = [];
    for (var element in rawData) {
      try {
        if (element is Map) {
          items.add(MindItem.fromMap(element));
        }
      } catch (e) {
        // Skip corrupt entry
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> saveItem(MindItem item) async {
    await box.put(item.id, item.toMap());
  }

  Future<void> deleteItem(String id) async {
    await box.delete(id);
  }

  Future<void> updateItem(MindItem item) async {
    await box.put(item.id, item.toMap());
  }

  List<MindItem> getUnsyncedItems() {
    return box.values
        .whereType<Map>()
        .map((e) => MindItem.fromMap(e))
        .where((item) => !item.isSynced)
        .toList();
  }
}
