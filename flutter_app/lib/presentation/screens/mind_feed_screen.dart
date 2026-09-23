import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mindFeedProvider);
    final items = state.filteredItems;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Multi-Orb Atmospheric Studio Glow (Glassmorphism backdrop)
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x38FF5B37), // Coral glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 250,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x28833AB4), // Purple glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            right: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x20F59E0B), // Warm amber glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2. Elegant Header & Floating Glass Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Row(
                    children: [
                      // Glass Search Bar
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              height: 52,
                              decoration: BoxDecoration(
                                color: AppColors.glassWhite,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: AppColors.glassBorder, width: 1.2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0A000000),
                                    blurRadius: 18,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) {
                                  ref.read(mindFeedProvider.notifier).setSearchQuery(val);
                                },
                                decoration: InputDecoration(
                                  hintText: "Search your second brain...",
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
                                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Radiant Gradient Floating Plus Button
                      InkWell(
                        onTap: () => _showAddUrlDialog(context, ref),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFF6E4C),
                                Color(0xFFFF4820),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x59FF5B37),
                                blurRadius: 14,
                                offset: Offset(0, 5),
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

                // 3. Horizontal Glass Category Filter Pills
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickFilterCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = _quickFilterCategories[index];
                      final isSelected = (category == 'All' && state.selectedTag == null) ||
                          state.selectedTag?.toLowerCase() == category.toLowerCase();

                      return GestureDetector(
                        onTap: () {
                          if (category == 'All') {
                            ref.read(mindFeedProvider.notifier).setSelectedTag(null);
                          } else {
                            ref.read(mindFeedProvider.notifier).setSelectedTag(category.toLowerCase());
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.glassWhite,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.glassBorder,
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
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),

                // 4. Masonry Visual Feed Grid
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
                                    "Your mind is quiet",
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    "Share a reel, article, or photo to preserve it here.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : MasonryGridView.count(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return MindCardWidget(
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
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: Color(0xCCFFFFFF), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(LucideIcons.sparkles, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text("Save to KeepIt", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: TextField(
            controller: urlController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Paste Instagram reel, YouTube video, or link...",
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
              onPressed: () {
                final link = urlController.text.trim();
                if (link.isNotEmpty) {
                  ref.read(mindFeedProvider.notifier).addUrl(link);
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text("Save Item", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
