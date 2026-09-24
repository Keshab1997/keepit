import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/datasources/local_mind_datasource.dart';
import '../controllers/mind_feed_controller.dart';
import 'home_screen.dart';

/// One onboarding page.
class _OnboardingPage {
  const _OnboardingPage({
    required this.image,
    required this.title,
    required this.body,
  });

  final String image;
  final String title;
  final String body;
}

const List<_OnboardingPage> _pages = [
  _OnboardingPage(
    image: 'assets/onboarding/onboarding_save.jpg',
    title: 'Save anything in one tap',
    body: 'Reels, videos, articles, photos and notes — share them from Instagram, YouTube, Chrome or any app straight into KeepIt.',
  ),
  _OnboardingPage(
    image: 'assets/onboarding/onboarding_feed.jpg',
    title: 'Your visual second brain',
    body: 'Everything you save becomes a beautiful card. Smart tags and Spaces keep it organised, and search finds anything instantly.',
  ),
  _OnboardingPage(
    image: 'assets/onboarding/onboarding_serendipity.jpg',
    title: 'Never forget what you save',
    body: 'Serendipity reminders bring your saved ideas back on day 3, 14, 45 and 90 — plus a relaxing Sunday digest.',
  ),
  _OnboardingPage(
    image: 'assets/onboarding/onboarding_private.jpg',
    title: 'Private by design',
    body: 'Local-first: your mind lives on your phone. Sign in only if you want cloud backup — light, non-personalized ads keep KeepIt free.',
  ),
];

/// Shown once, on the very first launch. Finishing or skipping stores a flag
/// in the Hive meta box so it never appears again.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  Future<void> _finish() async {
    try {
      await ref
          .read(localDataSourceProvider)
          .putMeta(LocalMindDataSource.onboardingSeenKey, true);
    } catch (_) {
      // Best-effort: never block the user from entering the app.
    }
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _OnboardingPageView(page: _pages[i]),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  _Dot(active: i == _index),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    _isLast ? 'Get started' : 'Next',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            flex: 5,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.cardBorder, width: 0.8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Image.asset(page.image, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 36),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.25,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 26 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.primary : const Color(0x33FF5B37),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
