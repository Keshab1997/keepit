import 'dart:ui';
import 'package:flutter/material.dart';
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

class _MindFeedScreenState extends ConsumerState<MindFeedScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollProgressNotifier = ValueNotifier<double>(0.0);

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
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final progress = (offset / 450.0).clamp(0.0, 1.0);
    // Only update notifier if changed by more than 0.02 to avoid high-frequency redraws
    if ((progress - _scrollProgressNotifier.value).abs() > 0.02) {
      _scrollProgressNotifier.value = progress;
    }
  }

  @override
  void dispose() {
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

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Stack(
        children: [
          // 1. Reactive Background Glow using ValueListenableBuilder (No full-screen rebuild!)
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
                // 2. Floating Search Bar & Plus Action
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                  child: Row(
                    children: [
                      // Glass Search Input
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

                      // Radiant Action Plus Button
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
                ),

                // 3. Horizontal Category Filter Pills
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

                // 4. Masonry Feed Grid with Optimized Scroll Physics
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
                              addAutomaticKeepAlives: true, // Retains scroll position and state smoothly
                              addRepaintBoundaries: true,   // Isolates repaints on 120Hz displays
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return MindCardWidget(
                                  key: ValueKey(item.id),
                                  item: item,
                                  onTap: () {
                                    MindCardDetailSheet.show(context, item);
                                  },
                                  onLongPress: () {
                                    MindCardDetailSheet.show(context, item);
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
