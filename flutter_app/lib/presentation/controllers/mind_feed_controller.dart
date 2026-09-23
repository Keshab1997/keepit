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
    bool clearTag = false,
  }) {
    return MindFeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTag: clearTag ? null : (selectedTag ?? this.selectedTag),
    );
  }

  List<MindItem> get filteredItems {
    return items.where((item) {
      final matchesQuery = searchQuery.isEmpty ||
          item.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (item.content?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false) ||
          item.tags.any((t) => t.toLowerCase().contains(searchQuery.toLowerCase()));

      final matchesTag = selectedTag == null ||
          selectedTag!.isEmpty ||
          selectedTag == 'all' ||
          item.tags.any((t) => t.toLowerCase() == selectedTag!.toLowerCase()) ||
          item.type.name.toLowerCase().contains(selectedTag!.toLowerCase());

      return matchesQuery && matchesTag;
    }).toList();
  }
}

enum SaveResult {
  success,
  duplicate,
  empty,
}

class MindFeedController extends StateNotifier<MindFeedState> {
  final LocalMindDataSource _localDataSource;

  MindFeedController(this._localDataSource) : super(const MindFeedState()) {
    loadItems();
  }

  Future<void> loadItems() async {
    state = state.copyWith(isLoading: true);
    final items = await _localDataSource.getAllItems();
    
    // Seed initial demo items if empty
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

  /// Adds a link or text. Checks for duplicate URLs before extracting metadata.
  Future<SaveResult> addUrl(String rawText) async {
    final cleanInput = rawText.trim();
    if (cleanInput.isEmpty) return SaveResult.empty;

    final targetUrl = _extractCleanUrl(cleanInput);

    // Duplicate Check: Check if URL already exists in current mind items
    final isDuplicate = state.items.any((item) {
      if (item.url == null || item.url!.isEmpty) return false;
      return _areUrlsEquivalent(item.url!, targetUrl);
    });

    if (isDuplicate) {
      return SaveResult.duplicate;
    }

    // Extract metadata & save
    final newItem = await MetadataExtractor.extractFromUrl(cleanInput);

    // Secondary duplicate check after metadata extraction
    if (newItem.url != null && newItem.url!.isNotEmpty) {
      final secondaryDuplicate = state.items.any((item) =>
          item.url != null && _areUrlsEquivalent(item.url!, newItem.url!));
      if (secondaryDuplicate) {
        return SaveResult.duplicate;
      }
    }

    await _localDataSource.saveItem(newItem);
    state = state.copyWith(items: [newItem, ...state.items]);
    return SaveResult.success;
  }

  String _extractCleanUrl(String text) {
    final urlRegex = RegExp(r'(https?://[^\s]+)');
    final match = urlRegex.firstMatch(text);
    return match != null ? match.group(0)! : text;
  }

  bool _areUrlsEquivalent(String url1, String url2) {
    final u1 = _normalizeUrl(url1);
    final u2 = _normalizeUrl(url2);
    return u1 == u2;
  }

  String _normalizeUrl(String url) {
    var clean = url.trim().toLowerCase();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.contains('?')) {
      final parts = clean.split('?');
      final base = parts[0];
      final query = parts[1];
      final cleanParams = query.split('&').where((param) {
        return !param.startsWith('igsh=') &&
            !param.startsWith('si=') &&
            !param.startsWith('utm_') &&
            !param.startsWith('fbclid=');
      }).join('&');
      clean = cleanParams.isNotEmpty ? '$base?$cleanParams' : base;
    }
    return clean;
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

  /// Sets or clears the active tag filter.
  /// If [tag] is null, empty, or 'all', or equals current tag -> resets to all items.
  void setSelectedTag(String? tag) {
    if (tag == null || tag.isEmpty || tag.toLowerCase() == 'all' || tag.toLowerCase() == state.selectedTag?.toLowerCase()) {
      state = state.copyWith(clearTag: true);
    } else {
      state = state.copyWith(selectedTag: tag.toLowerCase(), clearTag: false);
    }
  }

  List<MindItem> _generateDemoItems() {
    final now = DateTime.now();
    return [
      MindItem(
        id: '1',
        title: 'Super Useful 3 Contacts 🔥 (No relatives, only robots ✅)',
        url: 'https://www.instagram.com/reel/C_sample1',
        content: 'Top 3 AI robot contacts that will replace 90% of manual repetitive tasks in 2026. Automated scheduling, AI assistants, and auto-replies.',
        thumbnailUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=600&q=80',
        authorName: 'Sidhartha Rai',
        type: ItemType.instagramReel,
        tags: ['useful', 'contacts', 'ai', 'productivity', 'reel', 'robots'],
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
        content: 'Deep dive into modern developer toolchains: Vite, Turbopack, Flutter 3.x engines, and zero-bundle web architectures.',
        thumbnailUrl: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=600&q=80',
        authorName: 'TechStacker AI',
        type: ItemType.webArticle,
        tags: ['build-tools', 'architecture', 'dev', 'coding', 'tech', 'article'],
        isWatched: true,
        dominantColorHex: '#4F46E5',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      ),
      MindItem(
        id: '3',
        title: '3 AI Tools You Don\'t Know Exist',
        url: 'https://www.instagram.com/reel/C_sample2',
        content: 'Hidden AI tools for students and developers to automate design, generate clean code, and summarize video reels.',
        thumbnailUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=600&q=80',
        authorName: 'AI Explorer',
        type: ItemType.instagramReel,
        tags: ['ai', 'productivity', 'tools', 'coding', 'reel', 'automation'],
        dominantColorHex: '#EC4899',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now,
      ),
      MindItem(
        id: '4',
        title: 'Cinematic Image Grading & Color Science',
        content: 'Mastering moody atmospheric tones, highlights roll-off, and cinematic look curves.',
        thumbnailUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=600&q=80',
        authorName: 'Creative Lens',
        type: ItemType.image,
        tags: ['cinematic', 'color-grading', 'photo', 'design', 'visual'],
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
