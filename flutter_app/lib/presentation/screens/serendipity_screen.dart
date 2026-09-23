import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/mind_toast.dart';
import '../../core/utils/external_link_launcher.dart';
import '../../core/utils/notification_service.dart';
import '../../domain/entities/mind_item.dart';
import '../controllers/mind_feed_controller.dart';
import '../widgets/mind_card_detail_sheet.dart';

class SerendipityScreen extends ConsumerStatefulWidget {
  const SerendipityScreen({super.key});

  @override
  ConsumerState<SerendipityScreen> createState() => _SerendipityScreenState();
}

class _SerendipityScreenState extends ConsumerState<SerendipityScreen> {
  MindItem? _sparkedItem;

  @override
  Widget build(BuildContext context) {
    final allItems = ref.watch(mindFeedProvider).items;

    // Filter unwatched / unprocessed items
    final unwatchedItems = allItems.where((item) => !item.isWatched).toList();

    // If sparked item not yet set or deleted, pick a random candidate
    if (_sparkedItem == null && unwatchedItems.isNotEmpty) {
      _sparkedItem = unwatchedItems.first;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Serendipity',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
            tooltip: "Test Rediscovery Notification",
            icon: const Icon(LucideIcons.bell, size: 21, color: AppColors.textPrimary),
            onPressed: () async {
              if (unwatchedItems.isNotEmpty) {
                final candidate = _sparkedItem ?? unwatchedItems.first;
                await NotificationService().showSerendipityNotification(candidate);
                if (context.mounted) {
                  MindToast.showSuccessToast(context, title: "Notification sent!");
                }
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: unwatchedItems.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Color(0x2610B981),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.checkCheck, color: AppColors.success, size: 44),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Your Mind is Up to Date!",
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "You've watched and reviewed all your saved items. Save new links to spark serendipity.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, height: 1.5, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
              children: [
                // 1. Spark Random Gem Header & Shuffle Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DAILY RECALL SPARK",
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Resurfaced forgotten gem",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ],
                    ),

                    // Shuffle Spark Button
                    InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        if (unwatchedItems.isNotEmpty) {
                          final random = Random();
                          setState(() {
                            _sparkedItem = unwatchedItems[random.nextInt(unwatchedItems.length)];
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x66FF5B37), width: 0.8),
                        ),
                        child: const Row(
                          children: [
                            Icon(LucideIcons.shuffle, size: 14, color: AppColors.primary),
                            SizedBox(width: 6),
                            Text(
                              "Shuffle",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 2. Featured Spark Card
                if (_sparkedItem != null) _buildFeaturedSparkCard(context, ref, _sparkedItem!),

                const SizedBox(height: 32),

                // 3. Unwatched Queue Header
                Row(
                  children: [
                    const Text(
                      "UNWATCHED IN YOUR MIND",
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
                        color: const Color(0x1FFF5B37),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${unwatchedItems.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 4. Compact Rediscovery Queue List
                ...unwatchedItems.take(5).map((item) => _buildQueueTile(context, ref, item)),
              ],
            ),
    );
  }

  Widget _buildFeaturedSparkCard(BuildContext context, WidgetRef ref, MindItem item) {
    final daysAgo = DateTime.now().difference(item.createdAt).inDays;
    final timeAgoLabel = daysAgo == 0
        ? "Saved today"
        : (daysAgo == 1 ? "Saved yesterday" : "Saved $daysAgo days ago");

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF7FFFFFF),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Media Banner
                if (item.thumbnailUrl != null)
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 1.6,
                        child: Image.network(
                          item.thumbnailUrl!,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.8),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.history, color: Colors.white, size: 12),
                              const SizedBox(width: 5),
                              Text(
                                timeAgoLabel,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Play Button
                      Positioned.fill(
                        child: Center(
                          child: GestureDetector(
                            onTap: () => ExternalLinkLauncher.openSource(item.url),
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.8),
                              ),
                              child: const Icon(LucideIcons.play, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Card Details
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.authorName ?? 'KeepIt Mind',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Action Row: "I've Watched this" + "Details"
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                ref.read(mindFeedProvider.notifier).toggleWatched(item.id);
                                MindToast.showSuccessToast(context, title: "Marked as watched!");
                              },
                              icon: const Icon(LucideIcons.checkCheck, size: 16, color: AppColors.success),
                              label: const Text(
                                "Mark as Watched",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.success,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: const Color(0x1F10B981),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(color: Color(0x4010B981), width: 1.0),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () => MindCardDetailSheet.show(context, item),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F3F6),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(LucideIcons.arrowUpRight, size: 18, color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQueueTile(BuildContext context, WidgetRef ref, MindItem item) {
    final dateStr = DateFormat('MMM d').format(item.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xF4FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33E5E7EB), width: 0.8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: item.thumbnailUrl != null
              ? Image.network(
                  item.thumbnailUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                )
              : Container(
                  width: 48,
                  height: 48,
                  color: AppColors.tagBg,
                  child: const Icon(LucideIcons.link2, size: 20, color: AppColors.textMuted),
                ),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        subtitle: Text(
          "${item.authorName ?? 'Saved'} • $dateStr",
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        trailing: IconButton(
          icon: const Icon(LucideIcons.check, size: 18, color: AppColors.textSecondary),
          tooltip: "Mark Watched",
          onPressed: () {
            ref.read(mindFeedProvider.notifier).toggleWatched(item.id);
            MindToast.showSuccessToast(context, title: "Watched & Reviewed!");
          },
        ),
        onTap: () => MindCardDetailSheet.show(context, item),
      ),
    );
  }
}
