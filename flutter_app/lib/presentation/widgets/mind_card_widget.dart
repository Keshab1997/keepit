import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/mind_item.dart';

class MindCardWidget extends StatelessWidget {
  final MindItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const MindCardWidget({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.isTopMind
                ? AppColors.primary.withOpacity(0.5)
                : AppColors.cardBorder,
            width: item.isTopMind ? 1.5 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Media Image Thumbnail / Reel Header
            if (item.thumbnailUrl != null)
              Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: item.type == ItemType.instagramReel ? 0.85 : 1.2,
                    child: Image.network(
                      item.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppColors.tagBg,
                        child: const Icon(LucideIcons.image, color: AppColors.textMuted),
                      ),
                    ),
                  ),

                  // Top Source Badge (Instagram / YouTube / Web)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getSourceIcon(item.type),
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // Center Play Button for Video / Reel
                  if (item.type == ItemType.instagramReel || item.type == ItemType.youtubeVideo)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                      ),
                      child: const Icon(
                        LucideIcons.play,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),

                  // Watched Status Overlay Badge
                  if (item.isWatched)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.check, size: 10, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Watched',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

            // Content & Typography
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (item.authorName != null)
                    Text(
                      item.authorName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: item.tags.take(2).map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.tagBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '#$tag',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.tagText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSourceIcon(ItemType type) {
    switch (type) {
      case ItemType.instagramReel:
        return LucideIcons.instagram;
      case ItemType.youtubeVideo:
        return LucideIcons.youtube;
      case ItemType.quote:
        return LucideIcons.quote;
      case ItemType.image:
        return LucideIcons.image;
      case ItemType.quickNote:
        return LucideIcons.fileText;
      case ItemType.webArticle:
        return LucideIcons.globe;
    }
  }
}
