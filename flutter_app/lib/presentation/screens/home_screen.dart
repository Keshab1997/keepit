import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/ads/ad_config.dart';
import '../../core/theme/app_palette.dart';
import '../controllers/navigation_controller.dart';
import '../widgets/banner_ad_widget.dart';
import 'mind_feed_screen.dart';
import 'spaces_screen.dart';
import 'serendipity_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Index of the Profile tab — the banner is hidden there (legal links +
  /// account actions should stay ad-free).
  static const int _profileTab = 3;

  static const List<Widget> _pages = [
    MindFeedScreen(),
    SpacesScreen(),
    SerendipityScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final currentIndex = ref.watch(homeTabProvider);
    return PopScope(
      // Back from a secondary tab returns to Everything instead of popping
      // the root route and closing the app. Back from Everything keeps the
      // normal Android behavior and exits the root route.
      canPop: currentIndex == HomeTab.everything,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || currentIndex == HomeTab.everything) return;
        ref.read(homeTabProvider.notifier).state = HomeTab.everything;
      },
      child: Scaffold(
        backgroundColor: palette.background,
        body: Column(
          children: [
            Expanded(child: _pages[currentIndex]),
            // Banner on content tabs only, pinned above the navigation bar.
            if (AdConfig.enableBanner && currentIndex != _profileTab)
              const BannerAdSlot(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(
              top: BorderSide(color: palette.cardBorderSoft, width: 1.0),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: BottomNavigationBar(
                currentIndex: currentIndex,
                onTap: (index) =>
                    ref.read(homeTabProvider.notifier).state = index,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: palette.primary,
                unselectedItemColor: palette.textSecondary,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 11.5,
                ),
                type: BottomNavigationBarType.fixed,
                items: [
                  BottomNavigationBarItem(
                    icon: const Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Icon(LucideIcons.layoutGrid, size: 22),
                    ),
                    activeIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Icon(
                        LucideIcons.layoutGrid,
                        size: 22,
                        color: palette.primary,
                      ),
                    ),
                    label: 'Everything',
                  ),
                  BottomNavigationBarItem(
                    icon: const Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Icon(LucideIcons.folder, size: 22),
                    ),
                    activeIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Icon(
                        LucideIcons.folder,
                        size: 22,
                        color: palette.primary,
                      ),
                    ),
                    label: 'Spaces',
                  ),
                  BottomNavigationBarItem(
                    icon: const Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Icon(LucideIcons.sparkles, size: 22),
                    ),
                    activeIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Icon(
                        LucideIcons.sparkles,
                        size: 22,
                        color: palette.primary,
                      ),
                    ),
                    label: 'Serendipity',
                  ),
                  BottomNavigationBarItem(
                    icon: const Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Icon(LucideIcons.userCircle, size: 22),
                    ),
                    activeIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Icon(
                        LucideIcons.userCircle,
                        size: 22,
                        color: palette.primary,
                      ),
                    ),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
