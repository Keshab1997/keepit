import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Initialises Firebase if (and only if) the project has been configured.
///
/// KeepIt is local-first: the app must work perfectly without Firebase. When
/// `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) are not
/// present, [Firebase.initializeApp] throws and we simply run in offline mode —
/// the Profile screen then shows "Cloud sync not configured" instead of the
/// sign-in button. See docs/FIREBASE_SETUP.md.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _available = false;
  static String? _error;

  /// Whether Firebase was initialised successfully.
  static bool get isAvailable => _available;

  /// Why Firebase is unavailable (for diagnostics).
  static String? get error => _error;

  static Future<void> init() async {
    if (kIsWeb) {
      _error = 'Cloud sync is not supported on web builds.';
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(const Duration(seconds: 8));
      }
      _available = true;
    } catch (e) {
      _available = false;
      _error = e.toString();
      debugPrint('KeepIt: Firebase not configured, running offline. ($e)');
    }
  }

  @visibleForTesting
  static void setAvailableForTest(bool value) => _available = value;
}
