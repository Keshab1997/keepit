import 'package:flutter_riverpod/legacy.dart';

import '../../core/screenshot_mode.dart';

/// Bottom-navigation tabs of [HomeScreen].
class HomeTab {
  HomeTab._();
  static const int everything = 0;
  static const int spaces = 1;
  static const int serendipity = 2;
  static const int profile = 3;
}

/// Currently selected home tab. Lifted into a provider so notification deep
/// links can switch tabs (e.g. the Sunday Digest opens Serendipity).
final homeTabProvider = StateProvider<int>(
  (ref) =>
      ScreenshotMode.active ? ScreenshotMode.initialTab : HomeTab.everything,
);
