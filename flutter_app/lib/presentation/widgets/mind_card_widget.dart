import 'dart:ui';
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
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xE6FFFFFF), // Frosted glass milky surface
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: item.isTopMind
                      ? const Color(0x80FF5B37)
                      : const Color(0x80FFFFFF),
                  width: item.isTopMind ? 1.5 : 1.0,
                ),
              ),
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

                        // Glass Top Source Badge (Instagram / YouTube / Web)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0x59000000), // Dark glass
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0x40FFFFFF), width: 0.8),
                                ),
                                child: Icon(
                                  _getSourceIcon(item.type),
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Frosted Glass Play Button for Video / Reel
                        if (item.type == ItemType.instagramReel || item.type == ItemType.youtubeVideo)
                          ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0x40000000), // Glass frost
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xB3FFFFFF), width: 1.5),
                                ),
                                child: const Icon(
                                  LucideIcons.play,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),

                        // Watched Status Glass Overlay Badge
                        if (item.isWatched)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCC10B981),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0x66FFFFFF), width: 0.8),
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
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                  // Content & Typography
                  Padding(
                    padding: const EdgeInsets.all(13),
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
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xCCF1F2F6),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(color: const Color(0x40FFFFFF), width: 0.5),
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
          ),
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
