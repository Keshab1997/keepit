import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/mind_item.dart';
import '../../data/datasources/local_mind_datasource.dart';
import '../../core/utils/metadata_extractor.dart';

final localDataSourceProvider = Provider<LocalMindDataSource>((ref) {
  return LocalMindDataSource();
});

class MindFeedState {
  final List<MindItem> items;
  final bool isLoading;
  final String searchQuery;
  final String? selectedTag;

  const MindFeedState({
    this.items = const [],
    this.isLoading = false,
    this.searchQuery = '',
    this.selectedTag,
  });

  MindFeedState copyWith({
    List<MindItem>? items,
    bool? isLoading,
    String? searchQuery,
    String? selectedTag,
  }) {
    return MindFeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTag: selectedTag ?? this.selectedTag,
    );
  }

  List<MindItem> get filteredItems {
    return items.where((item) {
      final matchesQuery = searchQuery.isEmpty ||
          item.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (item.content?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false) ||
          item.tags.any((t) => t.toLowerCase().contains(searchQuery.toLowerCase()));

      final matchesTag = selectedTag == null || item.tags.contains(selectedTag);

      return matchesQuery && matchesTag;
    }).toList();
  }
}

class MindFeedController extends StateNotifier<MindFeedState> {
  final LocalMindDataSource _localDataSource;

  MindFeedController(this._localDataSource) : super(const MindFeedState()) {
    loadItems();
  }

  Future<void> loadItems() async {
    state = state.copyWith(isLoading: true);
    final items = await _localDataSource.getAllItems();
    
    // Seed initial demo items if empty (matching the exact aesthetic of the user's screenshot)
    if (items.isEmpty) {
      final demoItems = _generateDemoItems();
      for (final demo in demoItems) {
        await _localDataSource.saveItem(demo);
      }
      state = state.copyWith(items: demoItems, isLoading: false);
      return;
    }

    state = state.copyWith(items: items, isLoading: false);
  }

  Future<void> addUrl(String url) async {
    final newItem = await MetadataExtractor.extractFromUrl(url);
    await _localDataSource.saveItem(newItem);
    state = state.copyWith(items: [newItem, ...state.items]);
  }

  Future<void> toggleWatched(String id) async {
    final updatedList = state.items.map((item) {
      if (item.id == id) {
        final updated = item.copyWith(
          isWatched: !item.isWatched,
          updatedAt: DateTime.now(),
        );
        _localDataSource.updateItem(updated);
        return updated;
      }
      return item;
    }).toList();
    state = state.copyWith(items: updatedList);
  }

  Future<void> toggleTopMind(String id) async {
    final updatedList = state.items.map((item) {
      if (item.id == id) {
        final updated = item.copyWith(
          isTopMind: !item.isTopMind,
          updatedAt: DateTime.now(),
        );
        _localDataSource.updateItem(updated);
        return updated;
      }
      return item;
    }).toList();
    state = state.copyWith(items: updatedList);
  }

  Future<void> deleteItem(String id) async {
    await _localDataSource.deleteItem(id);
    state = state.copyWith(
      items: state.items.where((element) => element.id != id).toList(),
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedTag(String? tag) {
    state = state.copyWith(selectedTag: tag == state.selectedTag ? null : tag);
  }

  List<MindItem> _generateDemoItems() {
    final now = DateTime.now();
    return [
      MindItem(
        id: '1',
        title: 'Super Useful 3 Contacts 🔥 (No relatives, only robots ✅)',
        url: 'https://www.instagram.com/reel/C_sample1',
        thumbnailUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=600&q=80',
        authorName: 'Sidhartha Rai',
        type: ItemType.instagramReel,
        tags: ['useful', 'contacts', 'ai', 'hacks'],
        isWatched: false,
        isTopMind: true,
        dominantColorHex: '#E1306C',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now,
      ),
      MindItem(
        id: '2',
        title: 'Build Tools & System Architecture in 2026',
        url: 'https://techstacker.ai/build-tools',
        thumbnailUrl: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=600&q=80',
        authorName: 'TechStacker AI',
        type: ItemType.webArticle,
        tags: ['build-tools', 'architecture', 'dev'],
        isWatched: true,
        dominantColorHex: '#4F46E5',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      ),
      MindItem(
        id: '3',
        title: '3 AI Tools You Don\'t Know Exist',
        url: 'https://www.instagram.com/reel/C_sample2',
        thumbnailUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=600&q=80',
        authorName: 'AI Explorer',
        type: ItemType.instagramReel,
        tags: ['ai', 'productivity', 'tools'],
        dominantColorHex: '#EC4899',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now,
      ),
      MindItem(
        id: '4',
        title: 'Cinematic Image Grading & Color Science',
        thumbnailUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=600&q=80',
        authorName: 'Creative Lens',
        type: ItemType.image,
        tags: ['cinematic', 'color-grading', 'photo'],
        dominantColorHex: '#10B981',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now,
      ),
    ];
  }
}

final mindFeedProvider = StateNotifierProvider<MindFeedController, MindFeedState>((ref) {
  final dataSource = ref.watch(localDataSourceProvider);
  return MindFeedController(dataSource);
});
