import 'dart:ui';
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
      barrierColor: const Color(0x33000000), // Frosted dark backdrop
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
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xF2FFFFFF), // Translucent milky glass
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: const Color(0xB3FFFFFF), width: 1.2),
              ),
              child: Column(
                children: [
                  // Little Glass Grab Handle
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x40A5A9B8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header Controls (Dismiss chevron, Title, Options)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  const Divider(height: 1, color: Color(0x33EBECEF)),

                  // Scrollable Body
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Main Media Preview Card
                        if (liveItem.thumbnailUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.network(
                                  liveItem.thumbnailUrl!,
                                  width: double.infinity,
                                  height: 380,
                                  fit: BoxFit.cover,
                                ),
                                // Frosted Glass Play Button
                                ClipOval(
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                    child: Container(
                                      width: 68,
                                      height: 68,
                                      decoration: BoxDecoration(
                                        color: const Color(0x40000000),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xCCFFFFFF), width: 2),
                                      ),
                                      child: const Icon(
                                        LucideIcons.play,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 22),

                        // "I've watched this reel" Glass Action Button
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: ElevatedButton.icon(
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
                                    ? const Color(0x2610B981)
                                    : const Color(0x33FFECE7),
                                minimumSize: const Size(double.infinity, 56),
                                side: BorderSide(
                                  color: liveItem.isWatched
                                      ? const Color(0x6610B981)
                                      : const Color(0x66FF5B37),
                                  width: 1.0,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
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
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0x99F1F2F6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0x66FFFFFF), width: 0.8),
                              ),
                              child: Text(
                                '#$tag',
                                style: const TextStyle(
                                  color: AppColors.tagText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xF5FFFFFF),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: const Color(0xB3FFFFFF), width: 1.2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0x40A5A9B8),
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
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isDestructive ? const Color(0x14FF3B30) : const Color(0x66F9F9FB),
        borderRadius: BorderRadius.circular(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDestructive ? const Color(0x33FF3B30) : const Color(0x66FFFFFF),
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
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
          onTap: onTap,
        ),
      ),
    );
  }
}
