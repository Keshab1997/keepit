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
      backgroundColor: Colors.transparent, // Background shows atmospheric glow
      body: Stack(
        children: [
          // Background Atmospheric Glassmorphism Gradient Glows
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x33FF5B37),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -50,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x24833AB4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Bar: Glassmorphic Floating Search Bar & Plus Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // Glass Search Pill
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xCCFFFFFF),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xB3FFFFFF), width: 1.2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0A000000),
                                    blurRadius: 14,
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
                                  hintText: "Search my mind...",
                                  hintStyle: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 15,
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

                      // Radiant Glass Plus Button
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: InkWell(
                            onTap: () => _showAddUrlDialog(context, ref),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0x66FFFFFF), width: 1.2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x40FF5B37),
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
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Masonry Grid Feed
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                          ? const Center(
                              child: Text(
                                "Nothing in your mind yet.\nShare a reel or link to get started!",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                              ),
                            )
                          : MasonryGridView.count(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: const Color(0xF2FFFFFF), // Glass popup
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0x80FFFFFF), width: 1.2),
          ),
          title: const Text("Save to Mind", style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: urlController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Paste Instagram reel, video, or link...",
              filled: true,
              fillColor: const Color(0x80F1F2F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}
