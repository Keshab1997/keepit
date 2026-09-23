import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/mind_toast.dart';
import '../../core/utils/external_link_launcher.dart';
import '../../domain/entities/mind_item.dart';
import '../controllers/mind_feed_controller.dart';

class MindCardDetailSheet extends ConsumerStatefulWidget {
  final MindItem item;

  const MindCardDetailSheet({super.key, required this.item});

  static void show(BuildContext context, MindItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => MindCardDetailSheet(item: item),
    );
  }

  @override
  ConsumerState<MindCardDetailSheet> createState() => _MindCardDetailSheetState();
}

class _MindCardDetailSheetState extends ConsumerState<MindCardDetailSheet> {
  bool _isCopied = false;

  @override
  Widget build(BuildContext context) {
    final liveItem = ref.watch(mindFeedProvider).items.firstWhere(
          (element) => element.id == widget.item.id,
          orElse: () => widget.item,
        );

    final formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(liveItem.createdAt);
    final hasDescription = liveItem.content != null && liveItem.content!.trim().isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xF8FFFFFF),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 30,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 1. Sleek Glass Grab Handle
                  Center(
                    child: Container(
                      width: 42,
                      height: 4.5,
                      margin: const EdgeInsets.only(top: 12, bottom: 6),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // 2. Floating Action App Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Row(
                      children: [
                        _buildCircleIconButton(
                          icon: LucideIcons.chevronDown,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xEBF1F3F6),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_getSourceIcon(liveItem.type), size: 14, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      liveItem.authorName ?? 'KeepIt Mind',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildCircleIconButton(
                          icon: LucideIcons.moreHorizontal,
                          onPressed: () => _showActionsMenu(context, ref, liveItem),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: Color(0x1AE5E7EB)),

                  // 3. Scrollable Card Body
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                      children: [
                        // A. Cinema Poster Media Preview
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            ExternalLinkLauncher.openSource(liveItem.url);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1F000000),
                                  blurRadius: 24,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (liveItem.thumbnailUrl != null)
                                    Image.network(
                                      liveItem.thumbnailUrl!,
                                      width: double.infinity,
                                      height: 390,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        height: 260,
                                        color: AppColors.tagBg,
                                        child: const Center(
                                          child: Icon(LucideIcons.image, size: 48, color: AppColors.textMuted),
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      height: 220,
                                      color: AppColors.tagBg,
                                      child: const Center(
                                        child: Icon(LucideIcons.link2, size: 48, color: AppColors.textMuted),
                                      ),
                                    ),

                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.15),
                                            Colors.transparent,
                                            Colors.black.withValues(alpha: 0.65),
                                          ],
                                          stops: const [0.0, 0.45, 1.0],
                                        ),
                                      ),
                                    ),
                                  ),

                                  ClipOval(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.35),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x33000000),
                                              blurRadius: 16,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          LucideIcons.play,
                                          color: Colors.white,
                                          size: 34,
                                        ),
                                      ),
                                    ),
                                  ),

                                  Positioned(
                                    bottom: 16,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.55),
                                            borderRadius: BorderRadius.circular(24),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.0),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(LucideIcons.externalLink, color: Colors.white, size: 15),
                                              SizedBox(width: 8),
                                              Text(
                                                "Tap to open in app",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.2,
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
                            ),
                          ),
                        ),

                        const SizedBox(height: 22),

                        // B. Title Showcase
                        Text(
                          liveItem.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                            letterSpacing: -0.4,
                            color: AppColors.textPrimary,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Timestamp & Pinned status
                        Row(
                          children: [
                            const Icon(LucideIcons.clock, size: 13, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text(
                              formattedDate,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (liveItem.isTopMind) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.sparkles, size: 11, color: AppColors.primary),
                                    SizedBox(width: 4),
                                    Text(
                                      "Top of Mind",
                                      style: TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 20),

                        // C. Interactive Status Action Pill
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                ref.read(mindFeedProvider.notifier).toggleWatched(liveItem.id);
                              },
                              icon: Icon(
                                liveItem.isWatched ? LucideIcons.checkCheck : LucideIcons.eye,
                                color: liveItem.isWatched ? AppColors.success : AppColors.primary,
                                size: 20,
                              ),
                              label: Text(
                                liveItem.isWatched
                                    ? "Completed & Watched"
                                    : "I've watched this reel",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: liveItem.isWatched ? AppColors.success : AppColors.primary,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: liveItem.isWatched
                                    ? const Color(0x1F10B981)
                                    : AppColors.primaryLight,
                                minimumSize: const Size(double.infinity, 56),
                                side: BorderSide(
                                  color: liveItem.isWatched
                                      ? const Color(0x6610B981)
                                      : const Color(0x66FF5B37),
                                  width: 1.2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // D. Mind Tags Section
                        Row(
                          children: [
                            const Text(
                              "MIND TAGS",
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${liveItem.tags.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: liveItem.tags.map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xE8F1F3F6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 0.8),
                              ),
                              child: Text(
                                '#$tag',
                                style: const TextStyle(
                                  color: AppColors.tagText,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 28),

                        // E. LUXURY REDESIGNED DESCRIPTION BOX
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A000000),
                                blurRadius: 20,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xF4FFFFFF),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    width: 1.4,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header Strip of Description Card
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      decoration: const BoxDecoration(
                                        color: Color(0x59F1F3F6),
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                        border: Border(
                                          bottom: BorderSide(color: Color(0x1AE5E7EB), width: 1.0),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryLight,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  LucideIcons.fileText,
                                                  size: 15,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              const Text(
                                                "ORIGINAL CAPTION",
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.0,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),

                                          // Smooth Animated Copy Button
                                          if (hasDescription)
                                            GestureDetector(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: liveItem.content!));
                                                HapticFeedback.selectionClick();
                                                setState(() => _isCopied = true);
                                                MindToast.showSuccessToast(context, title: "Copied to clipboard!");
                                                Future.delayed(const Duration(seconds: 2), () {
                                                  if (mounted) setState(() => _isCopied = false);
                                                });
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 200),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: _isCopied ? const Color(0x1F10B981) : Colors.white,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: _isCopied
                                                        ? const Color(0x6610B981)
                                                        : const Color(0x33E5E7EB),
                                                    width: 1.0,
                                                  ),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x08000000),
                                                      blurRadius: 6,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      _isCopied ? LucideIcons.check : LucideIcons.copy,
                                                      size: 13,
                                                      color: _isCopied ? AppColors.success : AppColors.textSecondary,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      _isCopied ? "Copied" : "Copy",
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: _isCopied ? AppColors.success : AppColors.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),

                                    // Body of Description Card
                                    Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: SelectableText(
                                        hasDescription
                                            ? liveItem.content!.trim()
                                            : "No caption found for this item. Tap the card preview above to view original post.",
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: hasDescription ? AppColors.textPrimary : AppColors.textMuted,
                                          height: 1.6,
                                          fontWeight: FontWeight.w400,
                                          letterSpacing: -0.1,
                                        ),
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
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCircleIconButton({required IconData icon, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xEBF1F3F6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 0.8),
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }

  void _showActionsMenu(BuildContext context, WidgetRef ref, MindItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xF8FFFFFF),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  _buildActionTile(
                    icon: LucideIcons.externalLink,
                    title: "Open in original app",
                    onTap: () {
                      Navigator.pop(ctx);
                      ExternalLinkLauncher.openSource(item.url);
                    },
                  ),
                  _buildActionTile(
                    icon: LucideIcons.copy,
                    title: "Copy link",
                    onTap: () {
                      if (item.url != null) {
                        Clipboard.setData(ClipboardData(text: item.url!));
                        Navigator.pop(ctx);
                        MindToast.showSuccessToast(context, title: "Link copied to clipboard!");
                      }
                    },
                  ),
                  _buildActionTile(
                    icon: LucideIcons.brain,
                    title: item.isTopMind ? "Remove from Top of Mind" : "Pin to Top of Mind",
                    onTap: () {
                      ref.read(mindFeedProvider.notifier).toggleTopMind(item.id);
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildActionTile(
                    icon: LucideIcons.trash2,
                    title: "Delete from mind",
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDestructive ? const Color(0x33FF3B30) : Colors.white.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          leading: Icon(
            icon,
            color: isDestructive ? AppColors.danger : AppColors.textPrimary,
            size: 20,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDestructive ? AppColors.danger : AppColors.textPrimary,
            ),
          ),
          onTap: onTap,
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
