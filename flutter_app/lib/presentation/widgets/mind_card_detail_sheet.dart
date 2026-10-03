import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_palette.dart';
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
  ConsumerState<MindCardDetailSheet> createState() =>
      _MindCardDetailSheetState();
}

class _MindCardDetailSheetState extends ConsumerState<MindCardDetailSheet> {
  bool _isCopied = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final liveItem = ref.watch(mindFeedProvider).items.firstWhere(
          (element) => element.id == widget.item.id,
          orElse: () => widget.item,
        );

    final formattedDate =
        DateFormat('MMM d, yyyy • h:mm a').format(liveItem.createdAt);
    final hasDescription =
        liveItem.content != null && liveItem.content!.trim().isNotEmpty;

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
                color: palette.glassWhite,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(36),
                ),
                border: Border.all(
                  color: palette.glassBorder,
                  width: 1.5,
                ),
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
                        color: palette.textMuted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // 2. Floating Action App Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: palette.tagBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: palette.glassBorder,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getSourceIcon(liveItem.type),
                                    size: 14,
                                    color: palette.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      liveItem.authorName ?? 'KeepIt Mind',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: palette.textPrimary,
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
                          onPressed: () =>
                              _showActionsMenu(context, ref, liveItem),
                        ),
                      ],
                    ),
                  ),

                  Divider(height: 1, color: palette.divider),

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
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                        height: 260,
                                        color: palette.tagBg,
                                        child: Center(
                                          child: Icon(
                                            LucideIcons.image,
                                            size: 48,
                                            color: palette.textMuted,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      height: 220,
                                      color: palette.tagBg,
                                      child: Center(
                                        child: Icon(
                                          LucideIcons.link2,
                                          size: 48,
                                          color: palette.textMuted,
                                        ),
                                      ),
                                    ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(
                                              alpha: 0.15,
                                            ),
                                            Colors.transparent,
                                            Colors.black.withValues(
                                              alpha: 0.65,
                                            ),
                                          ],
                                          stops: const [0.0, 0.45, 1.0],
                                        ),
                                      ),
                                    ),
                                  ),
                                  ClipOval(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 16,
                                        sigmaY: 16,
                                      ),
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.35,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.9,
                                            ),
                                            width: 2,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x33000000),
                                              blurRadius: 16,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          LucideIcons.play,
                                          color: palette.tagBg,
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
                                        filter: ImageFilter.blur(
                                          sigmaX: 14,
                                          sigmaY: 14,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 9,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.4,
                                              ),
                                              width: 1.0,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                LucideIcons.externalLink,
                                                color: palette.tagBg,
                                                size: 15,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                "Tap to open in app",
                                                style: TextStyle(
                                                  color: palette.tagBg,
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
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                            letterSpacing: -0.4,
                            color: palette.textPrimary,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Timestamp & Pinned status
                        Row(
                          children: [
                            Icon(
                              LucideIcons.clock,
                              size: 13,
                              color: palette.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (liveItem.isTopMind) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.primaryLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.sparkles,
                                      size: 11,
                                      color: palette.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Top of Mind",
                                      style: TextStyle(
                                        color: palette.primary,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                ref
                                    .read(mindFeedProvider.notifier)
                                    .toggleWatched(liveItem.id);
                              },
                              icon: Icon(
                                liveItem.isWatched
                                    ? LucideIcons.checkCheck
                                    : LucideIcons.eye,
                                color: liveItem.isWatched
                                    ? palette.success
                                    : palette.primary,
                                size: 20,
                              ),
                              label: Text(
                                liveItem.isWatched
                                    ? "Completed & Watched"
                                    : "I've watched this reel",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: liveItem.isWatched
                                      ? palette.success
                                      : palette.primary,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: liveItem.isWatched
                                    ? const Color(0x1F10B981)
                                    : palette.primaryLight,
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
                            Text(
                              "MIND TAGS",
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: palette.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primaryLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${liveItem.tags.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: palette.primary,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: palette.tagBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: palette.glassBorder,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: palette.tagText,
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
                                  color: palette.glassCard,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: palette.glassBorder,
                                    width: 1.4,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header Strip of Description Card
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.tagBg
                                            .withValues(alpha: 0.35),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          top: Radius.circular(24),
                                        ),
                                        border: Border(
                                          bottom: BorderSide(
                                            color: palette.divider,
                                            width: 1.0,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: palette.primaryLight,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  LucideIcons.fileText,
                                                  size: 15,
                                                  color: palette.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                "ORIGINAL CAPTION",
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.0,
                                                  color: palette.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),

                                          // Smooth Animated Copy Button
                                          if (hasDescription)
                                            GestureDetector(
                                              onTap: () {
                                                Clipboard.setData(
                                                  ClipboardData(
                                                    text: liveItem.content!,
                                                  ),
                                                );
                                                HapticFeedback.selectionClick();
                                                setState(
                                                  () => _isCopied = true,
                                                );
                                                MindToast.showSuccessToast(
                                                  context,
                                                  title: "Copied to clipboard!",
                                                );
                                                Future.delayed(
                                                  const Duration(seconds: 2),
                                                  () {
                                                    if (mounted) {
                                                      setState(
                                                        () => _isCopied = false,
                                                      );
                                                    }
                                                  },
                                                );
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _isCopied
                                                      ? const Color(0x1F10B981)
                                                      : palette.tagBg,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: _isCopied
                                                        ? const Color(
                                                            0x6610B981,
                                                          )
                                                        : palette
                                                            .cardBorderSoft,
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
                                                      _isCopied
                                                          ? LucideIcons.check
                                                          : LucideIcons.copy,
                                                      size: 13,
                                                      color: _isCopied
                                                          ? palette.success
                                                          : palette
                                                              .textSecondary,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      _isCopied
                                                          ? "Copied"
                                                          : "Copy",
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: _isCopied
                                                            ? palette.success
                                                            : palette
                                                                .textSecondary,
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
                                          color: hasDescription
                                              ? palette.textPrimary
                                              : palette.textMuted,
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

  Widget _buildCircleIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: context.palette.tagBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: context.palette.glassBorder,
            width: 0.8,
          ),
        ),
        child: Icon(icon, size: 18, color: context.palette.textPrimary),
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
                color: context.palette.glassWhite,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border.all(
                  color: context.palette.glassBorder,
                  width: 1.2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: context.palette.textMuted.withValues(alpha: 0.4),
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
                        MindToast.showSuccessToast(
                          context,
                          title: "Link copied to clipboard!",
                        );
                      }
                    },
                  ),
                  _buildActionTile(
                    icon: LucideIcons.pencil,
                    title: "Edit title, note & tags",
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditDialog(context, ref, item);
                    },
                  ),
                  _buildActionTile(
                    icon: LucideIcons.brain,
                    title: item.isTopMind
                        ? "Remove from Top of Mind"
                        : "Pin to Top of Mind",
                    onTap: () {
                      ref
                          .read(mindFeedProvider.notifier)
                          .toggleTopMind(item.id);
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
                      MindToast.showDeleteToast(
                        context,
                        title: "Deleted from mind",
                      );
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

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    MindItem item,
  ) async {
    final titleController = TextEditingController(text: item.title);
    final contentController = TextEditingController(text: item.content ?? '');
    final tagsController = TextEditingController(text: item.tags.join(', '));
    final spaces = await ref.read(localDataSourceProvider).getCustomSpaces();
    if (!context.mounted) return;
    String? selectedSpaceId =
        spaces.any((space) => space.id == item.spaceId) ? item.spaceId : null;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit item'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    autofocus: true,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Add a title'
                        : null,
                  ),
                  TextFormField(
                    controller: contentController,
                    maxLines: 5,
                    maxLength: 20000,
                    decoration: const InputDecoration(
                      labelText: 'Note or description',
                      alignLabelWithHint: true,
                    ),
                  ),
                  TextFormField(
                    controller: tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags',
                      hintText: 'ai, reading, ideas',
                    ),
                  ),
                  if (spaces.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      initialValue: selectedSpaceId,
                      decoration: const InputDecoration(labelText: 'Space'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No Space'),
                        ),
                        ...spaces.map(
                          (space) => DropdownMenuItem<String?>(
                            value: space.id,
                            child: Text(space.name),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => selectedSpaceId = value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      await ref.read(mindFeedProvider.notifier).editItem(
            item.id,
            title: titleController.text,
            content: contentController.text,
            tags: tagsController.text.split(','),
            spaceId: selectedSpaceId,
            clearSpaceId: selectedSpaceId == null,
          );
      if (context.mounted) {
        MindToast.showSuccessToast(context, title: 'Item updated');
      }
    }
    titleController.dispose();
    contentController.dispose();
    tagsController.dispose();
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
        color: isDestructive ? const Color(0x14FF3B30) : context.palette.tagBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDestructive
                ? const Color(0x33FF3B30)
                : context.palette.cardBorder,
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 3,
          ),
          leading: Icon(
            icon,
            color: isDestructive
                ? context.palette.danger
                : context.palette.textPrimary,
            size: 20,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDestructive
                  ? context.palette.danger
                  : context.palette.textPrimary,
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
