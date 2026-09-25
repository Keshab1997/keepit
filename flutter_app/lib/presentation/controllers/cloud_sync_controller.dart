import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud/auth_service.dart';
import '../../core/cloud/cloud_sync_remote.dart';
import '../../core/cloud/firebase_bootstrap.dart';
import '../../core/cloud/sync_engine.dart';
import '../../data/datasources/local_mind_datasource.dart';
import 'mind_feed_controller.dart';

enum SyncStatus { idle, syncing, success, error }

@immutable
class CloudSyncState {
  final bool available;
  final AppUser? user;
  final bool autoSync;
  final SyncStatus status;
  final DateTime? lastSyncAt;
  final String? message;
  final int pendingChanges;
  final bool busy;

  const CloudSyncState({
    this.available = false,
    this.user,
    this.autoSync = true,
    this.status = SyncStatus.idle,
    this.lastSyncAt,
    this.message,
    this.pendingChanges = 0,
    this.busy = false,
  });

  bool get signedIn => user != null;

  CloudSyncState copyWith({
    bool? available,
    AppUser? user,
    bool clearUser = false,
    bool? autoSync,
    SyncStatus? status,
    DateTime? lastSyncAt,
    bool clearLastSync = false,
    String? message,
    bool clearMessage = false,
    int? pendingChanges,
    bool? busy,
  }) {
    return CloudSyncState(
      available: available ?? this.available,
      user: clearUser ? null : (user ?? this.user),
      autoSync: autoSync ?? this.autoSync,
      status: status ?? this.status,
      lastSyncAt: clearLastSync ? null : (lastSyncAt ?? this.lastSyncAt),
      message: clearMessage ? null : (message ?? this.message),
      pendingChanges: pendingChanges ?? this.pendingChanges,
      busy: busy ?? this.busy,
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return FirebaseBootstrap.isAvailable
      ? FirebaseAuthService()
      : const UnavailableAuthService();
});

final cloudSyncRemoteProvider = Provider<CloudSyncRemote?>((ref) {
  return FirebaseBootstrap.isAvailable ? FirestoreSyncRemote() : null;
});

class CloudSyncController extends StateNotifier<CloudSyncState> {
  CloudSyncController({
    required this.auth,
    required this.remote,
    required this.local,
    required this.onLocalDataChanged,
  }) : super(CloudSyncState(available: auth.isAvailable && remote != null)) {
    _init();
  }

  final AuthService auth;
  final CloudSyncRemote? remote;
  final LocalMindDataSource local;

  /// Called after a sync changed local data so the feed reloads from Hive.
  final Future<void> Function() onLocalDataChanged;

  static const String _autoSyncKey = 'auto_sync_enabled';

  /// Remote polling is deliberately infrequent to avoid paying for an empty
  /// Firestore query every time the app resumes. Local edits still sync after
  /// the normal debounce, and the Profile screen's "Sync now" always forces a
  /// check immediately.
  static const Duration _remotePollInterval = Duration(minutes: 5);

  StreamSubscription<AppUser?>? _authSub;
  Timer? _debounce;
  Future<SyncReport?>? _running;
  bool _rerunRequested = false;

  void _init() {
    final auto = local.getMeta<bool>(_autoSyncKey) ?? true;
    state = state.copyWith(autoSync: auto, pendingChanges: _pendingCount());
    if (!state.available) return;

    _authSub = auth.authStateChanges().listen(
      (user) {
        final previous = state.user;
        state = state.copyWith(
          user: user,
          clearUser: user == null,
          lastSyncAt: user == null ? null : _lastSyncFor(user.uid),
          clearLastSync: user == null,
          status: user == null ? SyncStatus.idle : state.status,
        );
        if (user != null && previous?.uid != user.uid && state.autoSync) {
          syncNow();
        }
      },
      onError: (Object e) {
        state = state.copyWith(status: SyncStatus.error, message: e.toString());
      },
    );
  }

  DateTime? _lastSyncFor(String uid) {
    final ms = local.getMeta<int>(SyncEngine.lastSyncKey(uid));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int _pendingCount() {
    try {
      final unsynced = local
          .getUnsyncedItems()
          .where((i) => !SyncEngine.demoItemIds.contains(i.id))
          .length;
      final deletes = local
          .getTombstones()
          .keys
          .where((id) => !SyncEngine.demoItemIds.contains(id))
          .length;
      return unsynced + deletes;
    } catch (_) {
      return 0;
    }
  }

  /// Call after any local data change. Debounced auto-sync when enabled.
  void notifyLocalChange() {
    if (!mounted) return;
    state = state.copyWith(pendingChanges: _pendingCount());
    if (!state.signedIn || !state.autoSync) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => syncNow(silent: true));
  }

  /// Called when the app returns to the foreground. Polling every resume is
  /// wasteful when the user only switches apps briefly, so remote checks are
  /// capped at one per [_remotePollInterval].
  void onAppResumed() {
    if (!state.signedIn || !state.autoSync || !_shouldPollRemote()) return;
    syncNow(silent: true);
  }

  bool _shouldPollRemote() {
    final last = state.lastSyncAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _remotePollInterval;
  }

  Future<SyncReport?> syncNow({bool silent = false}) {
    if (_running != null) {
      _rerunRequested = true;
      return _running!;
    }
    final future = _runSync(silent: silent);
    _running = future;
    return future.whenComplete(() {
      _running = null;
      if (_rerunRequested && mounted) {
        _rerunRequested = false;
        syncNow(silent: true);
      }
    });
  }

  Future<SyncReport?> _runSync({required bool silent}) async {
    final user = state.user;
    final remote = this.remote;
    if (user == null || remote == null) return null;
    _debounce?.cancel();
    state = state.copyWith(status: SyncStatus.syncing, clearMessage: true);
    try {
      final report = await SyncEngine(
        local: local,
        remote: remote,
      ).sync(user.uid).timeout(const Duration(seconds: 45));
      if (!mounted) return report;
      if (report.changedLocalData) await onLocalDataChanged();
      state = state.copyWith(
        status: SyncStatus.success,
        lastSyncAt: report.finishedAt,
        message: report.summary,
        pendingChanges: _pendingCount(),
      );
      return report;
    } on TimeoutException {
      if (mounted) {
        state = state.copyWith(
          status: SyncStatus.error,
          message: 'Sync timed out. Check your connection.',
        );
      }
    } catch (e) {
      debugPrint('KeepIt sync failed: $e');
      if (mounted) {
        state = state.copyWith(
          status: SyncStatus.error,
          message: _friendlyError(e),
        );
      }
    }
    return null;
  }

  static String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('permission-denied')) {
      return 'Cloud permission denied. Deploy firestore.rules (see docs/FIREBASE_SETUP.md).';
    }
    if (text.contains('unavailable') || text.contains('network')) {
      return "You're offline. Changes are saved and will sync later.";
    }
    if (text.contains('failed-precondition')) {
      return 'Cloud database is not ready (index or Firestore not enabled).';
    }
    return 'Sync failed. Please try again.';
  }

  Future<void> setAutoSync(bool value) async {
    await local.putMeta(_autoSyncKey, value);
    state = state.copyWith(autoSync: value);
    if (value) syncNow(silent: true);
  }

  /// Throws [AuthFailure] (check `.cancelled`).
  Future<void> signIn() async {
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      final user = await auth.signInWithGoogle();
      // authStateChanges also fires; set eagerly for snappier UI.
      state = state.copyWith(user: user, lastSyncAt: _lastSyncFor(user.uid));
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Signs out. With [removeLocalData] the device is wiped; otherwise items
  /// stay and will merge into whichever account signs in next.
  Future<void> signOut({required bool removeLocalData}) async {
    state = state.copyWith(busy: true);
    try {
      final user = state.user;
      if (user != null && !removeLocalData) {
        // Push anything pending first so nothing is lost.
        await syncNow(silent: true);
      }
      await auth.signOut();
      if (removeLocalData) {
        await local.clearAll();
      } else {
        await local.markAllUnsynced();
      }
      if (user != null) {
        await SyncEngine(local: local, remote: remote!).resetCursor(user.uid);
      }
      await onLocalDataChanged();
      state = state.copyWith(
        clearUser: true,
        status: SyncStatus.idle,
        clearLastSync: true,
        clearMessage: true,
        pendingChanges: _pendingCount(),
      );
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Deletes cloud data, the auth account and (optionally) local data.
  /// Required by Google Play's account-deletion policy.
  Future<void> deleteAccount({required bool removeLocalData}) async {
    final user = state.user;
    final remote = this.remote;
    if (user == null || remote == null) return;
    state = state.copyWith(busy: true);
    try {
      await remote.deleteAllUserData(user.uid);
      await auth.deleteAccount();
      await local.putMeta(SyncEngine.cursorKey(user.uid), null);
      await local.putMeta(SyncEngine.lastSyncKey(user.uid), null);
      if (removeLocalData) {
        await local.clearAll();
      } else {
        await local.markAllUnsynced();
      }
      await onLocalDataChanged();
      state = state.copyWith(
        clearUser: true,
        status: SyncStatus.idle,
        clearLastSync: true,
        message: 'Account deleted',
        pendingChanges: _pendingCount(),
      );
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Wipes local items when signed out (Profile → Data → Delete local data).
  Future<void> clearLocalData() async {
    await local.clearAll();
    await onLocalDataChanged();
    state = state.copyWith(pendingChanges: _pendingCount());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}

final cloudSyncProvider =
    StateNotifierProvider<CloudSyncController, CloudSyncState>((ref) {
      final controller = CloudSyncController(
        auth: ref.watch(authServiceProvider),
        remote: ref.watch(cloudSyncRemoteProvider),
        local: ref.watch(localDataSourceProvider),
        onLocalDataChanged: () =>
            ref.read(mindFeedProvider.notifier).loadItems(seedDemo: false),
      );
      return controller;
    });
