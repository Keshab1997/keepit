import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import 'mind_feed_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const MindFeedScreen(),
    const _SpacesScreen(),
    const _SerendipityScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.cardBorder, width: 0.8)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.layoutGrid),
              activeIcon: Icon(LucideIcons.layoutGrid, color: AppColors.primary),
              label: 'Everything',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.folder),
              activeIcon: Icon(LucideIcons.folder, color: AppColors.primary),
              label: 'Spaces',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.sparkles),
              activeIcon: Icon(LucideIcons.sparkles, color: AppColors.primary),
              label: 'Serendipity',
            ),
          ],
        ),
      ),
    );
  }
}

class _SpacesScreen extends StatelessWidget {
  const _SpacesScreen();

  @override
  Widget build(BuildContext context) {
    final spaces = [
      {'name': 'Design & Art', 'count': '18 items', 'icon': LucideIcons.palette},
      {'name': 'AI & Tech Stack', 'count': '42 items', 'icon': LucideIcons.cpu},
      {'name': 'Reels & Viral', 'count': '35 items', 'icon': LucideIcons.video},
      {'name': 'Reading List', 'count': '9 items', 'icon': LucideIcons.bookOpen},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spaces', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: spaces.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final space = spaces[index];
          return ListTile(
            tileColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.cardBorder, width: 0.8),
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(space['icon'] as IconData, color: AppColors.primary, size: 20),
            ),
            title: Text(space['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(space['count'] as String, style: const TextStyle(color: AppColors.textSecondary)),
            trailing: const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textMuted),
            onTap: () {},
          );
        },
      ),
    );
  }
}

class _SerendipityScreen extends StatelessWidget {
  const _SerendipityScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serendipity', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.sparkles, color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 20),
              const Text(
                'Rediscover Forgotten Gems',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Items saved weeks ago will resurface here intelligently to spark new creativity and memory recall.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
