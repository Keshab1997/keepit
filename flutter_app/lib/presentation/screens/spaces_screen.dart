import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/mind_item.dart';
import '../controllers/mind_feed_controller.dart';
import '../widgets/mind_card_widget.dart';
import '../widgets/mind_card_detail_sheet.dart';

class SpaceItemScreen extends ConsumerWidget {
  final String spaceName;
  final IconData icon;
  final Color color;
  final List<MindItem> items;

  const SpaceItemScreen({
    super.key,
    required this.spaceName,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              spaceName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No items in $spaceName yet",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Items matching this space will automatically organize here.",
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : MasonryGridView.count(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return MindCardWidget(
                  key: ValueKey(item.id),
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
    );
  }
}

class SpacesScreen extends ConsumerWidget {
  const SpacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allItems = ref.watch(mindFeedProvider).items;

    // Smart Dynamic Space Categorization
    final spacesDefinition = [
      {
        'id': 'ai_tech',
        'name': 'AI & Tech Stack',
        'subtitle': 'Machine learning, tools & gadgets',
        'icon': LucideIcons.cpu,
        'color': const Color(0xFF3B82F6),
        'filter': (MindItem item) => item.tags.any(
          (t) => [
            'ai',
            'tech',
            'coding',
            'chatgpt',
            'dev',
            'tools',
            'software',
          ].contains(t.toLowerCase()),
        ),
      },
      {
        'id': 'reels_video',
        'name': 'Reels & Videos',
        'subtitle': 'Instagram reels, YouTube shorts',
        'icon': LucideIcons.video,
        'color': const Color(0xFFEC4899),
        'filter': (MindItem item) =>
            item.type == ItemType.instagramReel ||
            item.type == ItemType.youtubeVideo ||
            item.tags.any(
              (t) => ['reel', 'shorts', 'video'].contains(t.toLowerCase()),
            ),
      },
      {
        'id': 'design_art',
        'name': 'Design & Aesthetic',
        'subtitle': 'UI/UX, visual inspiration & creative',
        'icon': LucideIcons.palette,
        'color': const Color(0xFF8B5CF6),
        'filter': (MindItem item) => item.tags.any(
          (t) => [
            'design',
            'ui',
            'ux',
            'cinematic',
            'photo',
            'visual',
            'art',
          ].contains(t.toLowerCase()),
        ),
      },
      {
        'id': 'reading_articles',
        'name': 'Deep Reading List',
        'subtitle': 'Web articles, research & long reads',
        'icon': LucideIcons.bookOpen,
        'color': const Color(0xFF10B981),
        'filter': (MindItem item) =>
            item.type == ItemType.webArticle ||
            item.tags.any(
              (t) => [
                'article',
                'read',
                'guide',
                'tutorial',
              ].contains(t.toLowerCase()),
            ),
      },
      {
        'id': 'productivity_hacks',
        'name': 'Productivity & Life',
        'subtitle': 'Hacks, habits & useful contacts',
        'icon': LucideIcons.zap,
        'color': const Color(0xFFF59E0B),
        'filter': (MindItem item) => item.tags.any(
          (t) => [
            'productivity',
            'useful',
            'contacts',
            'hack',
            'mindset',
            'habits',
          ].contains(t.toLowerCase()),
        ),
      },
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Spaces',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        itemCount: spacesDefinition.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final space = spacesDefinition[index];
          final filterFn = space['filter'] as bool Function(MindItem);
          final spaceItems = allItems.where(filterFn).toList();
          final color = space['color'] as Color;
          final icon = space['icon'] as IconData;
          final name = space['name'] as String;
          final subtitle = space['subtitle'] as String;

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SpaceItemScreen(
                    spaceName: name,
                    icon: icon,
                    color: color,
                    items: spaceItems,
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xF4FFFFFF),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Space Icon with Vibrant Pastel Tint
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: color.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),

                      const SizedBox(width: 14),

                      // Space Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${spaceItems.length}',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
