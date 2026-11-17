import 'package:flutter_riverpod/flutter_riverpod.dart';

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
final homeTabProvider = NotifierProvider<HomeTabNotifier, int>(
  HomeTabNotifier.new,
);

class HomeTabNotifier extends Notifier<int> {
  @override
  int build() =>
      ScreenshotMode.active ? ScreenshotMode.initialTab : HomeTab.everything;

  /// Was `ref.read(homeTabProvider.notifier).state = index` under
  /// StateProvider; a Notifier has no writable `.state`.
  void select(int index) => state = index;
}
