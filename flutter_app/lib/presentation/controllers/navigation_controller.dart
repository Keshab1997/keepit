import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-navigation tabs of [HomeScreen].
class HomeTab {
  HomeTab._();
  static const int everything = 0;
  static const int spaces = 1;
  static const int serendipity = 2;
}

/// Currently selected home tab. Lifted into a provider so notification deep
/// links can switch tabs (e.g. the Sunday Digest opens Serendipity).
final homeTabProvider = StateProvider<int>((ref) => HomeTab.everything);
