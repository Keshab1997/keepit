import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/serendipity_store.dart';
import '../../core/theme/mind_toast.dart';
import '../../core/utils/notification_service.dart';
import '../../domain/entities/mind_item.dart';
import '../controllers/mind_feed_controller.dart';
import '../controllers/navigation_controller.dart';
import 'mind_card_detail_sheet.dart';

/// Glue between [NotificationService] and the app:
///
/// * applies "Mark Watched" / "Remind in 1 Week" actions (including ones
///   tapped while the app was closed),
/// * re-plans reminders on launch, on resume, and whenever saved items change,
/// * handles notification taps by opening the item's detail sheet (or the
///   Serendipity tab for the Sunday Digest).
class NotificationHost extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const NotificationHost({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  ConsumerState<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends ConsumerState<NotificationHost>
    with WidgetsBindingObserver {
  final NotificationService _service = NotificationService();
  StreamSubscription<NotificationIntent>? _intentSub;
  StreamSubscription<NotificationActionRecord>? _actionSub;
  Timer? _debounce;
  String? _lastSignature;
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _intentSub = _service.intents.listen(_handleIntent);
    _actionSub = _service.foregroundActions.listen(
      (a) => _applyActions([a], showToast: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentSub?.cancel();
    _actionSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await ref.read(mindFeedProvider.notifier).ready;
    if (!mounted) return;

    await _drainPendingActions(showToast: true);
    if (!mounted) return;
    _booted = true;
    await _rescheduleNow();

    if (_service.settings.enabled) {
      // Shown once by the OS on Android 13+/iOS; no-op if already decided.
      unawaited(_service.requestPermission());
    }

    final launchIntent = _service.takeLaunchIntent();
    if (launchIntent != null) _handleIntent(launchIntent);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _booted) {
      _drainPendingActions(showToast: true).then((_) => _rescheduleNow());
    }
  }

  Future<void> _drainPendingActions({required bool showToast}) async {
    final actions = await _service.consumePendingActions();
    if (actions.isNotEmpty) await _applyActions(actions, showToast: showToast);
  }

  Future<void> _applyActions(
    List<NotificationActionRecord> actions, {
    required bool showToast,
  }) async {
    final feed = ref.read(mindFeedProvider.notifier);
    var watched = 0;
    var snoozed = 0;
    for (final a in actions) {
      if (a.type == NotificationActionRecord.watched) {
        await feed.setWatched(a.itemId, true);
        watched++;
      } else if (a.type == NotificationActionRecord.snooze) {
        snoozed++;
      }
    }
    if (snoozed > 0) await _rescheduleNow();

    final ctx = widget.navigatorKey.currentContext;
    if (!showToast || ctx == null || !ctx.mounted) return;
    if (watched > 0 && snoozed == 0) {
      MindToast.showSuccessToast(
        ctx,
        title: watched == 1
            ? 'Marked as watched!'
            : '$watched items marked watched',
      );
    } else if (snoozed > 0 && watched == 0) {
      MindToast.showSuccessToast(
        ctx,
        title: "Got it — we'll remind you in a week",
      );
    } else if (watched > 0 && snoozed > 0) {
      MindToast.showSuccessToast(ctx, title: 'Reminders updated');
    }
  }

  /// Only fields that influence the reminder plan.
  String _signature(List<MindItem> items) {
    final buffer = StringBuffer();
    for (final i in items) {
      buffer
        ..write(i.id)
        ..write(i.isWatched ? 'w' : 'u')
        ..write(i.isTopMind ? 't' : 'n')
        ..write(i.createdAt.millisecondsSinceEpoch)
        ..write(i.title.hashCode)
        ..write('|');
    }
    return buffer.toString();
  }

  Future<void> _rescheduleNow() async {
    _debounce?.cancel();
    final items = ref.read(mindFeedProvider).items;
    _lastSignature = _signature(items);
    await _service.reschedule(items);
  }

  void _scheduleDebounced(List<MindItem> items) {
    if (!_booted) return;
    final sig = _signature(items);
    if (sig == _lastSignature) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _rescheduleNow();
    });
  }

  Future<void> _handleIntent(NotificationIntent intent) async {
    await ref.read(mindFeedProvider.notifier).ready;
    if (!mounted) return;

    if (intent.type == NotificationIntent.typeDigest) {
      ref.read(homeTabProvider.notifier).state = HomeTab.serendipity;
      return;
    }

    final itemId = intent.itemId;
    if (itemId == null) return;
    final items = ref.read(mindFeedProvider).items;
    final item = items.where((i) => i.id == itemId).firstOrNull;
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    if (item == null) {
      MindToast.showDeleteToast(
        ctx,
        title: 'That item is no longer in your mind',
      );
      return;
    }

    ref.read(homeTabProvider.notifier).state = HomeTab.serendipity;
    // Close any sheet/dialog already open so the item opens on top of home.
    widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    MindCardDetailSheet.show(ctx, item);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MindFeedState>(mindFeedProvider, (prev, next) {
      if (!identical(prev?.items, next.items)) _scheduleDebounced(next.items);
    });
    return widget.child;
  }
}
