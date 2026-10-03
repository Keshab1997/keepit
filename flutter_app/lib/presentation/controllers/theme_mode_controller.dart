import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local_mind_datasource.dart';
import 'mind_feed_controller.dart';

/// The saved Light / Dark / System choice.
///
/// Lives in the Hive meta box next to the other device-local flags, so the
/// preference survives a restart without a new dependency or a Firestore round
/// trip — a theme choice is per-device, not per-account.
///
/// Default is [ThemeMode.system]: a user who has already told the OS what they
/// prefer should not have to tell the app as well.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(LocalMindDataSource local)
      : _local = local,
        super(_read(local));

  /// Key in the Hive meta box.
  static const String metaKey = 'theme_mode';

  final LocalMindDataSource _local;

  static ThemeMode _read(LocalMindDataSource local) {
    switch (local.getMeta<String>(metaKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Persist and apply. Unknown values fall back to system on next launch.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _local.putMeta(metaKey, _encode(mode));
  }

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(localDataSourceProvider));
});
