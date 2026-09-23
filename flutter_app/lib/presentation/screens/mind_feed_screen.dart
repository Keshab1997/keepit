import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/mind_toast.dart';
import '../controllers/mind_feed_controller.dart';
import '../widgets/mind_card_widget.dart';
import '../widgets/mind_card_detail_sheet.dart';

class MindFeedScreen extends ConsumerStatefulWidget {
  const MindFeedScreen({super.key});

  @override
  ConsumerState<MindFeedScreen> createState() => _MindFeedScreenState();
}

class _MindFeedScreenState extends ConsumerState<MindFeedScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollProgressNotifier = ValueNotifier<double>(0.0);

  // Multi-Select & Jiggle Mode State
  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = {};
  late AnimationController _jiggleController;

  final List<String> _quickFilterCategories = [
    'All',
    'Reels',
    'AI',
    'Coding',
    'Design',
    'Productivity',
    'Articles',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // iOS style subtle jiggle animation
    _jiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final progress = (offset / 450.0).clamp(0.0, 1.0);
    if ((progress - _scrollProgressNotifier.value).abs() > 0.02) {
      _scrollProgressNotifier.value = progress;
    }
  }

  void _enterSelectionMode(String initialId) {
    HapticFeedback.heavyImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedItemIds.add(initialId);
    });
    _jiggleController.repeat(reverse: true);
  }

  void _exitSelectionMode() {
    HapticFeedback.lightImpact();
    _jiggleController.stop();
    _jiggleController.reset();
    setState(() {
      _isSelectionMode = false;
      _selectedItemIds.clear();
    });
  }

  void _toggleItemSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedItemIds.contains(id)) {
        _selectedItemIds.remove(id);
        if (_selectedItemIds.isEmpty) {
          _exitSelectionMode();
        }
      } else {
        _selectedItemIds.add(id);
      }
    });
  }

  void _confirmDeleteSelected(BuildContext context) {
    if (_selectedItemIds.isEmpty) return;

    final count = _selectedItemIds.length;
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AlertDialog(
          backgroundColor: const Color(0xF7FFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: Color(0xCCFFFFFF), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0x1FFF3B30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.trash2, color: AppColors.danger, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                count == 1 ? "Delete item?" : "Delete $count items?",
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            count == 1
                ? "This item will be permanently removed from your mind."
                : "These $count items will be permanently removed from your mind.",
            style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                final idsToDelete = List<String>.from(_selectedItemIds);
                for (final id in idsToDelete) {
                  ref.read(mindFeedProvider.notifier).deleteItem(id);
                }
                Navigator.pop(ctx);
                _exitSelectionMode();
                MindToast.showDeleteToast(
                  context,
                  title: count == 1 ? "1 item deleted" : "$count items deleted",
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _jiggleController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _scrollProgressNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mindFeedProvider);
    final items = state.filteredItems;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvoked: (didPop) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: Stack(
          children: [
            // 1. Reactive Background Glow
            ValueListenableBuilder<double>(
              valueListenable: _scrollProgressNotifier,
              builder: (context, progress, child) {
                final primaryOrb = Color.lerp(
                  const Color(0x38FF5B37),
                  const Color(0x306366F1),
                  progress,
                )!;
                final secondaryOrb = Color.lerp(
                  const Color(0x28833AB4),
                  const Color(0x2806B6D4),
                  progress,
                )!;

                return Stack(
                  children: [
                    Positioned(
                      top: -80 + (progress * 60),
                      right: -60 - (progress * 40),
                      child: Container(
                        width: 320,
                        height: 320,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [primaryOrb, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 260 - (progress * 80),
                      left: -80 + (progress * 50),
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [secondaryOrb, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2. Dynamic Top Bar: Standard Search or Selection Bar
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _isSelectionMode
                        ? _buildSelectionAppBar(context, items.length)
                        : _buildStandardSearchBar(),
                  ),

                  // 3. Category Filter Pills (hidden in selection mode for cleaner focus)
                  if (!_isSelectionMode) ...[
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        scrollDirection: Axis.horizontal,
                        itemCount: _quickFilterCategories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final category = _quickFilterCategories[index];
                          final isAll = category == 'All';
                          final isSelected = isAll
                              ? (state.selectedTag == null || state.selectedTag!.isEmpty)
                              : (state.selectedTag?.toLowerCase() == category.toLowerCase());

                          return GestureDetector(
                            onTap: () {
                              ref.read(mindFeedProvider.notifier).setSelectedTag(isAll ? null : category);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : const Color(0xF2FFFFFF),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : const Color(0x33E5E7EB),
                                  width: 1,
                                ),
                                boxShadow: [
                                  if (isSelected)
                                    const BoxShadow(
                                      color: Color(0x40FF5B37),
                                      blurRadius: 10,
                                      offset: Offset(0, 3),
                                    ),
                                ],
                              ),
                              child: Text(
                                category,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? Colors.white : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 4. Masonry Feed Grid with Jiggle Animation on long-press
                  Expanded(
                    child: state.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : items.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 70,
                                      height: 70,
                                      decoration: const BoxDecoration(
                                        color: Color(0x26FF5B37),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(LucideIcons.sparkles, color: AppColors.primary, size: 32),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "No items found in this category",
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(height: 6),
                                    TextButton(
                                      onPressed: () {
                                        ref.read(mindFeedProvider.notifier).setSelectedTag(null);
                                      },
                                      child: const Text("Show all items", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              )
                            : MasonryGridView.count(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                                itemCount: items.length,
                                addAutomaticKeepAlives: true,
                                addRepaintBoundaries: true,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  final isSelected = _selectedItemIds.contains(item.id);

                                  return AnimatedBuilder(
                                    animation: _jiggleController,
                                    builder: (context, child) {
                                      // Alternate tilt angles for neighboring cards (iOS Wiggle effect)
                                      final angle = _isSelectionMode
                                          ? (index.isEven ? 0.015 : -0.015) * (_jiggleController.value - 0.5) * 2
                                          : 0.0;

                                      return Transform.rotate(
                                        angle: angle,
                                        child: Stack(
                                          children: [
                                            // The Masonry Card
                                            MindCardWidget(
                                              key: ValueKey(item.id),
                                              item: item,
                                              onTap: () {
                                                if (_isSelectionMode) {
                                                  _toggleItemSelection(item.id);
                                                } else {
                                                  MindCardDetailSheet.show(context, item);
                                                }
                                              },
                                              onLongPress: () {
                                                if (!_isSelectionMode) {
                                                  _enterSelectionMode(item.id);
                                                } else {
                                                  _toggleItemSelection(item.id);
                                                }
                                              },
                                            ),

                                            // Jiggle Mode Delete Badge / Selection Indicator
                                            if (_isSelectionMode)
                                              Positioned(
                                                top: 6,
                                                right: 6,
                                                child: GestureDetector(
                                                  onTap: () => _toggleItemSelection(item.id),
                                                  child: Container(
                                                    width: 30,
                                                    height: 30,
                                                    decoration: BoxDecoration(
                                                      color: isSelected ? AppColors.danger : Colors.white,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: isSelected ? AppColors.danger : const Color(0x66000000),
                                                        width: 2,
                                                      ),
                                                      boxShadow: const [
                                                        BoxShadow(
                                                          color: Color(0x33000000),
                                                          blurRadius: 8,
                                                          offset: Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Icon(
                                                      isSelected ? LucideIcons.check : LucideIcons.circle,
                                                      color: isSelected ? Colors.white : Colors.transparent,
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardSearchBar() {
    return Padding(
      key: const ValueKey('standard_search_bar'),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.glassBorder, width: 1.1),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x08000000),
                        blurRadius: 14,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      ref.read(mindFeedProvider.notifier).setSearchQuery(val);
                    },
                    decoration: InputDecoration(
                      hintText: "Search my mind...",
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: const Icon(
                        LucideIcons.search,
                        color: AppColors.textSecondary,
                        size: 19,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(mindFeedProvider.notifier).setSearchQuery('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => _showAddUrlDialog(context, ref),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4DFF5B37),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                LucideIcons.plus,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionAppBar(BuildContext context, int totalCount) {
    final count = _selectedItemIds.length;
    final isAllSelected = _selectedItemIds.length == totalCount && totalCount > 0;

    return Padding(
      key: const ValueKey('selection_app_bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xF8FFFFFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Close / Done Icon Button
                InkWell(
                  onTap: _exitSelectionMode,
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(LucideIcons.x, size: 19, color: AppColors.textPrimary),
                  ),
                ),

                const SizedBox(width: 4),

                // Selected Count Title
                Text(
                  "$count",
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),

                const Spacer(),

                // Select All / Deselect Action
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (isAllSelected) {
                        _selectedItemIds.clear();
                        _exitSelectionMode();
                      } else {
                        final allItems = ref.read(mindFeedProvider).filteredItems;
                        _selectedItemIds.addAll(allItems.map((e) => e.id));
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      isAllSelected ? "Deselect" : "Select All",
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Compact Delete Button
                InkWell(
                  onTap: () => _confirmDeleteSelected(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40FF3B30),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.trash2, color: Colors.white, size: 14),
                        SizedBox(width: 5),
                        Text(
                          "Delete",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddUrlDialog(BuildContext context, WidgetRef ref) {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          backgroundColor: const Color(0xF7FFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xCCFFFFFF), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(LucideIcons.sparkles, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text("Save to Mind", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: TextField(
            controller: urlController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Paste Instagram reel, video, or link...",
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              filled: true,
              fillColor: const Color(0x99F1F3F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final link = urlController.text.trim();
                if (link.isNotEmpty) {
                  Navigator.pop(ctx);
                  final result = await ref.read(mindFeedProvider.notifier).addUrl(link);
                  if (!context.mounted) return;

                  if (result == SaveResult.duplicate) {
                    MindToast.showDuplicateToast(context);
                  } else if (result == SaveResult.success) {
                    MindToast.showSuccessToast(context);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}
