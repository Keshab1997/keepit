import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Minimal user model so the UI never depends on Firebase types directly.
@immutable
class AppUser {
  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  const AppUser(
      {required this.uid, this.displayName, this.email, this.photoUrl});

  String get initials {
    final source = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : (email ?? '?');
    final parts =
        source.split(RegExp(r'[\s@._]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  bool operator ==(Object other) => other is AppUser && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}

/// User-facing auth failure.
class AuthFailure implements Exception {
  final String message;

  /// True when the user simply dismissed the account picker.
  final bool cancelled;

  const AuthFailure(this.message, {this.cancelled = false});

  @override
  String toString() => message;
}

abstract class AuthService {
  /// Whether sign-in can work at all (Firebase configured).
  bool get isAvailable;

  AppUser? get currentUser;

  Stream<AppUser?> authStateChanges();

  Future<AppUser> signInWithGoogle();

  Future<void> signOut();

  /// Permanently deletes the Firebase Auth account (re-authenticating with
  /// Google if Firebase requires a recent login). Cloud data must be deleted
  /// *before* calling this, while the user is still authorised.
  Future<void> deleteAccount();
}

/// Used when Firebase is not configured. Everything is a no-op.
class UnavailableAuthService implements AuthService {
  const UnavailableAuthService();

  @override
  bool get isAvailable => false;

  @override
  AppUser? get currentUser => null;

  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(null);

  @override
  Future<AppUser> signInWithGoogle() async =>
      throw const AuthFailure('Cloud sync is not set up in this build yet.');

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

/// Google Sign-In → Firebase Auth.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  Future<void>? _googleInit;

  /// Optional override: `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com`.
  /// Not needed on Android when google-services.json contains the web client.
  static const String _serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  @override
  bool get isAvailable => true;

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AppUser?> authStateChanges() => _auth.userChanges().map(_map);

  Future<void> _ensureGoogleInit() {
    return _googleInit ??= _google.initialize(
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
  }

  Future<String> _googleIdToken() async {
    await _ensureGoogleInit();
    try {
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure(
            'Google did not return an ID token. Check the Firebase SHA-1 setup.');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthFailure('Sign-in cancelled', cancelled: true);
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw const AuthFailure(
          'Google Sign-In is not configured correctly (SHA-1 / OAuth client). See docs/FIREBASE_SETUP.md.',
        );
      }
      throw AuthFailure(
          'Google Sign-In failed: ${e.description ?? e.code.name}');
    }
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    final idToken = await _googleIdToken();
    try {
      final result = await _auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken));
      final user = _map(result.user);
      if (user == null) {
        throw const AuthFailure('Sign-in failed. Please try again.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _ensureGoogleInit();
      await _google.signOut();
    } catch (_) {
      // Signing out of Google is best-effort; Firebase sign-out is what matters.
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') throw AuthFailure(_friendly(e));
      final idToken = await _googleIdToken();
      await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(idToken: idToken));
      await user.delete();
    }
    try {
      await _ensureGoogleInit();
      await _google.disconnect();
    } catch (_) {}
  }

  static AppUser? _map(User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
      photoUrl: user.photoURL,
    );
  }

  static String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled in the Firebase console.';
      default:
        return e.message ?? 'Authentication failed (${e.code}).';
    }
  }
}
