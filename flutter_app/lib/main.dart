import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/mind_toast.dart';
import 'core/utils/notification_service.dart';
import 'data/datasources/local_mind_datasource.dart';
import 'presentation/controllers/mind_feed_controller.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/widgets/notification_host.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Hive Local Database
  await Hive.initFlutter();
  final localDataSource = LocalMindDataSource();
  await localDataSource.init();

  // 2. Initialize Serendipity Notification Service (scheduling happens in
  //    NotificationHost once the saved items are loaded).
  await NotificationService().init();

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
  @override
  void initState() {
    super.initState();
    _initShareIntentListener();
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
    return NotificationHost(
      navigatorKey: navigatorKey,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'KeepIt',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
      ),
    );
  }
}
