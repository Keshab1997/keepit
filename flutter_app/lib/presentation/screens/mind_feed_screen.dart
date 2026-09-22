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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Search My Mind & Floating Plus Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Search Pill
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.cardBorder, width: 0.8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
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
                          ),
                          prefixIcon: const Icon(
                            LucideIcons.menu,
                            color: AppColors.textSecondary,
                            size: 20,
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
                          contentPadding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Radiant Plus Button
                  InkWell(
                    onTap: () => _showAddUrlDialog(context, ref),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
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

            // Main Masonry Grid
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
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
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
    );
  }

  void _showAddUrlDialog(BuildContext context, WidgetRef ref) {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Save to Mind", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: urlController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Paste Instagram reel, video, or article link...",
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}
