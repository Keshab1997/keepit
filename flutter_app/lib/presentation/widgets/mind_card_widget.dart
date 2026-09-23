import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    // RepaintBoundary isolates this card's render tree so scrolling never triggers unnecessary repaints
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF5FFFFFF), // High performance opaque frosted tint (No GPU expensive backdrop filter)
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: item.isTopMind
                  ? AppColors.primary.withValues(alpha: 0.7)
                  : const Color(0x33E5E7EB),
              width: item.isTopMind ? 1.6 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: item.isTopMind
                    ? const Color(0x24FF5B37)
                    : const Color(0x0A000000),
                blurRadius: item.isTopMind ? 16 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. High Performance Cached Image Thumbnail
              if (item.thumbnailUrl != null)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: item.type == ItemType.instagramReel ? 0.82 : 1.25,
                      child: CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 450, // Optimize memory downsampling for 120 FPS buttery scrolling
                        memCacheHeight: 600,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (context, url) => Container(
                          color: const Color(0xFFF1F3F6),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0x40FF5B37),
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.tagBg,
                          child: const Center(
                            child: Icon(LucideIcons.image, color: AppColors.textMuted, size: 28),
                          ),
                        ),
                      ),
                    ),

                    // Subtle Vignette Gradient Overlay at Bottom of Image
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.35),
                            ],
                            stops: const [0.65, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Source Badge (Top Left)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getSourceIcon(item.type),
                              size: 13,
                              color: Colors.white,
                            ),
                            if (item.type == ItemType.instagramReel) ...[
                              const SizedBox(width: 4),
                              const Text(
                                'Reel',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Pinned Top of Mind Indicator (Top Right)
                    if (item.isTopMind)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x66FF5B37),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 12),
                        ),
                      ),

                    // Play Button for Videos
                    if (item.type == ItemType.instagramReel || item.type == ItemType.youtubeVideo)
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
                        ),
                        child: const Icon(
                          LucideIcons.play,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),

                    // Watched Status Badge (Bottom Right)
                    if (item.isWatched)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xE610B981),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.checkCheck, size: 11, color: Colors.white),
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
                  ],
                ),

              // 2. Card Content & Typography
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
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.35,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (item.authorName != null)
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.authorName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (item.tags.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: item.tags.take(3).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F3F6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0x33E5E7EB), width: 0.6),
                            ),
                            child: Text(
                              '#$tag',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.tagText,
                                fontWeight: FontWeight.w600,
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
