import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/ads/ad_service.dart';
import 'core/cloud/firebase_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/notification_service.dart';
import 'data/datasources/local_mind_datasource.dart';
import 'presentation/controllers/mind_feed_controller.dart';
import 'presentation/controllers/theme_mode_controller.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/widgets/keepit_3d_splash.dart';
import 'presentation/widgets/notification_host.dart';
import 'presentation/widgets/share_capture_overlay.dart';
import 'presentation/widgets/sync_host.dart';
import 'presentation/widgets/update_host.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Set once the first [runApp] has been reached. Zone errors after that point
/// must not tear a running app down to show the boot-error screen.
bool _appStarted = false;

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      // In release builds a framework error would otherwise paint a silent
      // grey screen; make the failure visible and keep a log line.
      FlutterError.onError = (details) {
        debugPrint('KeepIt Flutter error:\n${details.exceptionAsString()}');
        FlutterError.presentError(details);
      };
      ErrorWidget.builder = (details) => Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('KeepIt hit an error:\n${details.exception}'),
              ),
            ),
          );

      // Call runApp immediately so Android dismisses the static native splash
      // screen on the very first frame and shows KeepIt3DSplashScreen while
      // Hive, Firebase, and Notifications initialize in the background.
      _appStarted = true;
      runApp(const _KeepItBootstrapHost());
    },
    (error, stack) {
      debugPrint('KeepIt uncaught error: $error\n$stack');
      if (!_appStarted) {
        runApp(_BootErrorApp(error: error));
      }
    },
  );
}

/// Immediately paints [KeepIt3DSplashScreen] on frame 1 (replacing the static
/// Android native splash screen right away) while initializing Hive, Firebase,
/// and Notifications in the background, then smoothly cross-fades into
/// [KeepItApp].
class _KeepItBootstrapHost extends StatefulWidget {
  const _KeepItBootstrapHost();

  @override
  State<_KeepItBootstrapHost> createState() => _KeepItBootstrapHostState();
}

class _KeepItBootstrapHostState extends State<_KeepItBootstrapHost> {
  LocalMindDataSource? _localDataSource;
  Object? _bootError;

  @override
  void initState() {
    super.initState();
    unawaited(_bootServices());
  }

  Future<void> _bootServices() async {
    try {
      final minSplashTime = Future<void>.delayed(
        const Duration(milliseconds: 1450),
      );

      // Local .env (git-ignored). Optional so CI and tests without the file
      // still boot; features that need a key report "not configured".
      await dotenv.load(isOptional: true);

      // 1. Initialize Hive Local Database
      await Hive.initFlutter();
      final localDataSource = LocalMindDataSource();
      await localDataSource.init();

      // 2. Initialize Firebase and Notifications in parallel while the 3D
      //    splash animation plays.
      await Future.wait<void>([
        FirebaseBootstrap.init(),
        NotificationService().init(),
        minSplashTime,
      ]);

      // 3. Ads (AdMob) — initialize non-blocking in the background so slow
      //    WebView/Play Services startup never delays app launch.
      unawaited(
        AdService.instance
            .init(prefs: localDataSource.meta)
            .catchError((Object _) {}),
      );

      if (!mounted) return;
      setState(() => _localDataSource = localDataSource);
    } catch (error, stack) {
      debugPrint('KeepIt boot error: $error\n$stack');
      if (!mounted) return;
      setState(() => _bootError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _bootError;
    if (error != null) {
      return _BootErrorApp(error: error);
    }

    final dataSource = _localDataSource;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: dataSource == null
          ? const MaterialApp(
              key: ValueKey('keepit-3d-splash'),
              debugShowCheckedModeBanner: false,
              home: KeepIt3DSplashScreen(),
            )
          : ProviderScope(
              key: const ValueKey('keepit-ready'),
              overrides: [
                localDataSourceProvider.overrideWithValue(dataSource),
              ],
              child: const KeepItApp(),
            ),
    );
  }
}

/// Minimal emergency UI shown when startup itself throws — better a visible
/// error message than a process that silently closes.
class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('KeepIt could not start.\n\n$error'),
          ),
        ),
      ),
    );
  }
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
    ReceiveSharingIntent.instance.getMediaStream().listen((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        final path = value.first.path;
        ReceiveSharingIntent.instance.reset();
        _handleIncomingShare(path);
      }
    });

    // Handle incoming share when app is opened from dead state
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        final path = value.first.path;
        ReceiveSharingIntent.instance.reset();
        _handleIncomingShare(path);
      }
    });
  }

  Future<void> _handleIncomingShare(String sharedText) async {
    if (!mounted) return;
    await ref.read(shareCaptureProvider.notifier).capture(sharedText);
  }

  @override
  Widget build(BuildContext context) {
    final showOnboarding = _showOnboarding;
    final themeMode = ref.watch(themeModeProvider);
    return SyncHost(
      child: NotificationHost(
        navigatorKey: navigatorKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          title: 'KeepIt',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: showOnboarding == null
              ? const KeepIt3DSplashScreen()
              : UpdateHost(
                  child: showOnboarding
                      ? const OnboardingScreen()
                      : const HomeScreen(),
                ),
        ),
      ),
    );
  }
}
