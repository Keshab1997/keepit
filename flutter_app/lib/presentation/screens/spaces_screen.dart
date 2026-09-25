import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../data/datasources/local_mind_datasource.dart';
import '../../domain/entities/custom_space.dart';
import '../../domain/entities/mind_item.dart';
import '../controllers/cloud_sync_controller.dart';
import '../controllers/mind_feed_controller.dart';
import '../widgets/mind_card_detail_sheet.dart';
import '../widgets/mind_card_widget.dart';

class SpaceItemScreen extends ConsumerWidget {
  final String spaceName;
  final IconData icon;
  final Color color;
  final List<MindItem> items;
  final String? customSpaceId;

  const SpaceItemScreen({
    super.key,
    required this.spaceName,
    required this.icon,
    required this.color,
    required this.items,
    this.customSpaceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveItems = customSpaceId == null
        ? items
        : ref
            .watch(mindFeedProvider)
            .items
            .where((item) => item.spaceId == customSpaceId)
            .toList();

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
      body: liveItems.isEmpty
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
                    'No items in $spaceName yet',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    customSpaceId == null
                        ? 'Items matching this smart Space will appear here.'
                        : 'Open an item and choose this Space to assign it here.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
              itemCount: liveItems.length,
              itemBuilder: (context, index) {
                final item = liveItems[index];
                return MindCardWidget(
                  key: ValueKey(item.id),
                  item: item,
                  onTap: () => MindCardDetailSheet.show(context, item),
                  onLongPress: () => MindCardDetailSheet.show(context, item),
                );
              },
            ),
    );
  }
}

class _SmartSpaceDefinition {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool Function(MindItem) matches;

  const _SmartSpaceDefinition({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.matches,
  });
}

class SpacesScreen extends ConsumerStatefulWidget {
  const SpacesScreen({super.key});

  @override
  ConsumerState<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends ConsumerState<SpacesScreen> {
  static const _colors = [
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
  ];

  static const _iconNames = [
    'folder',
    'heart',
    'star',
    'code',
    'book',
    'briefcase',
    'camera',
    'music',
    'travel',
  ];

  List<CustomSpace> _customSpaces = const [];
  bool _loadingCustomSpaces = true;

  List<_SmartSpaceDefinition> get _smartSpaces => [
        _SmartSpaceDefinition(
          id: 'ai_tech',
          name: 'AI & Tech Stack',
          subtitle: 'Machine learning, tools & gadgets',
          icon: LucideIcons.cpu,
          color: const Color(0xFF3B82F6),
          matches: (item) => item.tags.any(
            (tag) => [
              'ai',
              'tech',
              'coding',
              'chatgpt',
              'dev',
              'tools',
              'software',
            ].contains(tag.toLowerCase()),
          ),
        ),
        _SmartSpaceDefinition(
          id: 'reels_video',
          name: 'Reels & Videos',
          subtitle: 'Instagram reels, YouTube shorts',
          icon: LucideIcons.video,
          color: const Color(0xFFEC4899),
          matches: (item) =>
              item.type == ItemType.instagramReel ||
              item.type == ItemType.youtubeVideo ||
              item.tags.any(
                (tag) =>
                    ['reel', 'shorts', 'video'].contains(tag.toLowerCase()),
              ),
        ),
        _SmartSpaceDefinition(
          id: 'design_art',
          name: 'Design & Aesthetic',
          subtitle: 'UI/UX, visual inspiration & creative',
          icon: LucideIcons.palette,
          color: const Color(0xFF8B5CF6),
          matches: (item) => item.tags.any(
            (tag) => [
              'design',
              'ui',
              'ux',
              'cinematic',
              'photo',
              'visual',
              'art',
            ].contains(tag.toLowerCase()),
          ),
        ),
        _SmartSpaceDefinition(
          id: 'reading_articles',
          name: 'Deep Reading List',
          subtitle: 'Web articles, research & long reads',
          icon: LucideIcons.bookOpen,
          color: const Color(0xFF10B981),
          matches: (item) =>
              item.type == ItemType.webArticle ||
              item.tags.any(
                (tag) => ['article', 'read', 'guide', 'tutorial'].contains(
                  tag.toLowerCase(),
                ),
              ),
        ),
        _SmartSpaceDefinition(
          id: 'productivity_hacks',
          name: 'Productivity & Life',
          subtitle: 'Hacks, habits & useful contacts',
          icon: LucideIcons.zap,
          color: const Color(0xFFF59E0B),
          matches: (item) => item.tags.any(
            (tag) => [
              'productivity',
              'useful',
              'contacts',
              'hack',
              'mindset',
              'habits',
            ].contains(tag.toLowerCase()),
          ),
        ),
      ];

  @override
  void initState() {
    super.initState();
    _loadCustomSpaces();
  }

  Future<void> _loadCustomSpaces() async {
    final spaces = await ref.read(localDataSourceProvider).getCustomSpaces();
    if (!mounted) return;
    setState(() {
      _customSpaces = spaces;
      _loadingCustomSpaces = false;
    });
  }

  Future<void> _createOrEditSpace([CustomSpace? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    var selectedColor = existing?.color ?? _colors.first;
    var selectedIcon = existing?.iconName ?? _iconNames.first;

    final result = await showDialog<CustomSpace>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Create Space' : 'Rename Space'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Space name',
                    hintText: 'e.g. Startup ideas',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Color',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _colors.map((color) {
                    final selected =
                        selectedColor.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(color: Colors.black, width: 3)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Icon',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _iconNames.map((name) {
                    final selected = selectedIcon == name;
                    return InkWell(
                      onTap: () => setDialogState(() => selectedIcon = name),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selected
                              ? selectedColor.withValues(alpha: 0.15)
                              : const Color(0xFFF1F3F6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                selected ? selectedColor : Colors.transparent,
                          ),
                        ),
                        child: Icon(_iconForName(name), size: 20),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  CustomSpace(
                    id: existing?.id ?? const Uuid().v4(),
                    name: name,
                    colorValue: selectedColor.toARGB32(),
                    iconName: selectedIcon,
                  ),
                );
              },
              child: Text(existing == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null) return;

    final spaces = [..._customSpaces];
    final index = spaces.indexWhere((space) => space.id == result.id);
    if (index == -1) {
      spaces.add(result);
    } else {
      spaces[index] = result;
    }
    await ref.read(localDataSourceProvider).saveCustomSpaces(spaces);
    if (!mounted) return;
    setState(() => _customSpaces = spaces);
  }

  Future<void> _deleteSpace(CustomSpace space) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${space.name}?'),
        content: const Text(
          'Items will stay safe, but their assignment to this Space will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(localDataSourceProvider).deleteCustomSpace(space.id);
    await ref.read(mindFeedProvider.notifier).loadItems(seedDemo: false);
    ref.read(cloudSyncProvider.notifier).notifyLocalChange();
    if (mounted) {
      setState(() {
        _customSpaces = _customSpaces
            .where((candidate) => candidate.id != space.id)
            .toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allItems = ref.watch(mindFeedProvider).items;
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
        actions: [
          IconButton(
            tooltip: 'Create Space',
            onPressed: () => _createOrEditSpace(),
            icon: const Icon(LucideIcons.folderPlus),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          const _SectionTitle('MY SPACES'),
          if (_loadingCustomSpaces)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_customSpaces.isEmpty)
            _EmptyCustomSpaceCard(onTap: () => _createOrEditSpace())
          else
            ..._customSpaces.map((space) {
              final count =
                  allItems.where((item) => item.spaceId == space.id).length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildSpaceCard(
                  name: space.name,
                  subtitle: 'Your custom collection',
                  icon: _iconForName(space.iconName),
                  color: space.color,
                  count: count,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SpaceItemScreen(
                        spaceName: space.name,
                        icon: _iconForName(space.iconName),
                        color: space.color,
                        items: const [],
                        customSpaceId: space.id,
                      ),
                    ),
                  ),
                  menu: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _createOrEditSpace(space);
                      if (value == 'delete') _deleteSpace(space);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'edit', child: Text('Rename / edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          const _SectionTitle('SMART SPACES'),
          ..._smartSpaces.map((space) {
            final spaceItems = allItems.where(space.matches).toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildSpaceCard(
                name: space.name,
                subtitle: space.subtitle,
                icon: space.icon,
                color: space.color,
                count: spaceItems.length,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SpaceItemScreen(
                      spaceName: space.name,
                      icon: space.icon,
                      color: space.color,
                      items: spaceItems,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSpaceCard({
    required String name,
    required String subtitle,
    required IconData icon,
    required Color color,
    required int count,
    required VoidCallback onTap,
    Widget? menu,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5,
                                color: AppColors.textPrimary,
                              ),
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
                              '$count',
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
                if (menu != null) menu,
                if (menu == null)
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
  }

  static IconData _iconForName(String name) {
    switch (name) {
      case 'heart':
        return LucideIcons.heart;
      case 'star':
        return LucideIcons.star;
      case 'code':
        return LucideIcons.code2;
      case 'book':
        return LucideIcons.bookOpen;
      case 'briefcase':
        return LucideIcons.briefcase;
      case 'camera':
        return LucideIcons.camera;
      case 'music':
        return LucideIcons.music;
      case 'travel':
        return LucideIcons.mapPin;
      default:
        return LucideIcons.folder;
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

class _EmptyCustomSpaceCard extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyCustomSpaceCard({required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
              width: 1.2,
            ),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.folderPlus, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Create a Space for your own collections',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(LucideIcons.chevronRight, color: AppColors.textMuted),
            ],
          ),
        ),
      );
}
