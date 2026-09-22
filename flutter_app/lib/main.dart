import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/local_mind_datasource.dart';
import 'presentation/controllers/mind_feed_controller.dart';
import 'presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Hive Local Database
  await Hive.initFlutter();
  final localDataSource = LocalMindDataSource();
  await localDataSource.init();

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
        if (path.startsWith('http://') || path.startsWith('https://')) {
          ref.read(mindFeedProvider.notifier).addUrl(path);
        }
      }
    });

    // Handle incoming share when app is opened from dead state
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final path = value.first.path;
        if (path.startsWith('http://') || path.startsWith('https://')) {
          ref.read(mindFeedProvider.notifier).addUrl(path);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeepIt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}
