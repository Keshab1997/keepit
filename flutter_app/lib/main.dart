import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'core/ads/ad_service.dart';
import 'core/cloud/firebase_bootstrap.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/mind_toast.dart';
import 'core/utils/notification_service.dart';
import 'data/datasources/local_mind_datasource.dart';
import 'presentation/controllers/mind_feed_controller.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/widgets/notification_host.dart';
import 'presentation/widgets/sync_host.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Hive Local Database
  await Hive.initFlutter();
  final localDataSource = LocalMindDataSource();
  await localDataSource.init();

  // 2. Firebase (optional — the app runs fully offline without it)
  await FirebaseBootstrap.init();

  // 3. Initialize Serendipity Notification Service (scheduling happens in
  //    NotificationHost once the saved items are loaded).
  await NotificationService().init();

  // 4. Ads (AdMob) — optional monetization. Best-effort: a failure here must
  //    never block startup. Frequency counters persist in the Hive meta box.
  try {
    await AdService.instance.init(prefs: localDataSource.meta);
  } catch (_) {
    // Ads are optional; keep booting.
  }

  runApp(
    ProviderScope(
      overrides: [
        localDataSourceProvider.overrideWithValue(localDataSource),
      ],
      child: const KeepItApp(),
    ),
  );
}

class KeepItApp extends ConsumerStatefulWidget {
  const KeepItApp({super.key});

  @override
  ConsumerState<KeepItApp> createState() => _KeepItAppState();
}

class _KeepItAppState extends ConsumerState<KeepItApp> {
  /// null while the first-launch flag is being read, then true → onboarding.
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _initShareIntentListener();
    _checkFirstRun();
  }

  /// Very first launch shows the onboarding; the flag lives in the Hive meta
  /// box so it never appears again (unless local data is wiped).
  Future<void> _checkFirstRun() async {
    final seen = ref
            .read(localDataSourceProvider)
            .getMeta<bool>(LocalMindDataSource.onboardingSeenKey) ??
        false;
    if (!mounted) return;
    setState(() => _showOnboarding = !seen);
  }

  void _initShareIntentListener() {
    // Listen to incoming shares while app is in memory
    ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final path = value.first.path;
        _handleIncomingShare(path);
      }
    });

    // Handle incoming share when app is opened from dead state
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final path = value.first.path;
        _handleIncomingShare(path);
      }
    });
  }

  Future<void> _handleIncomingShare(String sharedText) async {
    final result = await ref.read(mindFeedProvider.notifier).addUrl(sharedText);
    if (!mounted) return;
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      if (result == SaveResult.duplicate) {
        MindToast.showDuplicateToast(context);
      } else if (result == SaveResult.success) {
        MindToast.showSuccessToast(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOnboarding = _showOnboarding;
    return SyncHost(
      child: NotificationHost(
        navigatorKey: navigatorKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          title: 'KeepIt',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: showOnboarding == null
              ? const _BrandSplash()
              : showOnboarding
                  ? const OnboardingScreen()
                  : const HomeScreen(),
        ),
      ),
    );
  }
}

/// Shown for the few milliseconds it takes to read the first-launch flag.
class _BrandSplash extends StatelessWidget {
  const _BrandSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8A65), Color(0xFFFF5B37), Color(0xFFE03C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4DFF5B37),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                LucideIcons.sparkles,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'KeepIt',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your visual second brain',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
