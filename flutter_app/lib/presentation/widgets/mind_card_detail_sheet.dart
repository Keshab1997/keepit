import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/mind_item.dart';
import '../controllers/mind_feed_controller.dart';

class MindCardDetailSheet extends ConsumerWidget {
  final MindItem item;

  const MindCardDetailSheet({super.key, required this.item});

  static void show(BuildContext context, MindItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MindCardDetailSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveItem = ref.watch(mindFeedProvider).items.firstWhere(
          (element) => element.id == item.id,
          orElse: () => item,
        );

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header Controls (Dismiss chevron, Title, Options)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.chevronDown, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        liveItem.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.moreHorizontal, size: 24),
                      onPressed: () {
                        _showActionsMenu(context, ref, liveItem);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.cardBorder),

              // Scrollable Body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Main Media Preview Card
                    if (liveItem.thumbnailUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.network(
                              liveItem.thumbnailUrl!,
                              width: double.infinity,
                              height: 380,
                              fit: BoxFit.cover,
                            ),
                            // Frosted Play Icon
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0x66000000),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                LucideIcons.play,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),

                    // "I've watched this reel" Primary Interactive Action Button
                    ElevatedButton.icon(
                      onPressed: () {
                        ref.read(mindFeedProvider.notifier).toggleWatched(liveItem.id);
                      },
                      icon: Icon(
                        liveItem.isWatched ? LucideIcons.checkCheck : LucideIcons.eye,
                        color: liveItem.isWatched ? AppColors.success : AppColors.primary,
                      ),
                      label: Text(
                        liveItem.isWatched
                            ? "Completed & Watched"
                            : "I've watched this reel",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: liveItem.isWatched ? AppColors.success : AppColors.primary,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: liveItem.isWatched
                            ? const Color(0x1F10B981)
                            : AppColors.primaryLight,
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Tags Cloud
                    const Text(
                      "MIND TAGS",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: liveItem.tags.map((tag) {
                        return Chip(
                          label: Text('#$tag'),
                          backgroundColor: AppColors.tagBg,
                          labelStyle: const TextStyle(
                            color: AppColors.tagText,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showActionsMenu(BuildContext context, WidgetRef ref, MindItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0x66A5A9B8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildActionTile(
                icon: LucideIcons.link,
                title: "View original source",
                onTap: () async {
                  Navigator.pop(ctx);
                  if (item.url != null) {
                    final uri = Uri.parse(item.url!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
              ),
              _buildActionTile(
                icon: LucideIcons.hash,
                title: "Add tags",
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
              _buildActionTile(
                icon: LucideIcons.folderPlus,
                title: "Add to space",
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
              _buildActionTile(
                icon: LucideIcons.brain,
                title: item.isTopMind ? "Remove from Top of Mind" : "Top of Mind",
                onTap: () {
                  ref.read(mindFeedProvider.notifier).toggleTopMind(item.id);
                  Navigator.pop(ctx);
                },
              ),
              _buildActionTile(
                icon: LucideIcons.trash2,
                title: "Delete card",
                isDestructive: true,
                onTap: () {
                  ref.read(mindFeedProvider.notifier).deleteItem(item.id);
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Icon(
        icon,
        color: isDestructive ? AppColors.danger : AppColors.textPrimary,
        size: 20,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isDestructive ? AppColors.danger : AppColors.textPrimary,
        ),
      ),
      tileColor: isDestructive ? const Color(0x0FFF3B30) : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onTap: onTap,
    );
  }
}
