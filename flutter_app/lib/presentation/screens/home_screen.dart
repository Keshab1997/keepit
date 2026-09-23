import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import 'mind_feed_screen.dart';
import 'spaces_screen.dart';
import 'serendipity_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const MindFeedScreen(),
    const SpacesScreen(),
    const SerendipityScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: Color(0x33E5E7EB), width: 1.0),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.textSecondary,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11.5),
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Icon(LucideIcons.layoutGrid, size: 22),
                  ),
                  activeIcon: Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Icon(LucideIcons.layoutGrid, size: 22, color: AppColors.primary),
                  ),
                  label: 'Everything',
                ),
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Icon(LucideIcons.folder, size: 22),
                  ),
                  activeIcon: Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Icon(LucideIcons.folder, size: 22, color: AppColors.primary),
                  ),
                  label: 'Spaces',
                ),
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Icon(LucideIcons.sparkles, size: 22),
                  ),
                  activeIcon: Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Icon(LucideIcons.sparkles, size: 22, color: AppColors.primary),
                  ),
                  label: 'Serendipity',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SerendipityScreen extends StatelessWidget {
  const _SerendipityScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Serendipity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.2),
                          const Color(0xFF833AB4).withValues(alpha: 0.15),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                    ),
                    child: const Icon(LucideIcons.sparkles, color: AppColors.primary, size: 48),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Rediscover Forgotten Gems',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              const Text(
                'Items saved weeks ago will resurface here intelligently to spark new creativity and memory recall.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.5, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
