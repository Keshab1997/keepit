import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/mind_item.dart';
import '../notifications/serendipity_planner.dart';
import '../notifications/serendipity_store.dart';

/// What the UI should do after the user interacts with a notification.
class NotificationIntent {
  static const String typeItem = 'open_item';
  static const String typeDigest = 'open_digest';

  final String type;
  final String? itemId;

  const NotificationIntent._(this.type, this.itemId);

  const NotificationIntent.openItem(String id) : this._(typeItem, id);
  const NotificationIntent.openDigest() : this._(typeDigest, null);

  @override
  String toString() => 'NotificationIntent($type, $itemId)';
}

/// Notification action identifiers (shared by Android buttons and the iOS
/// notification category).
class NotificationActions {
  static const String markWatched = 'keepit_mark_watched';
  static const String snoozeWeek = 'keepit_snooze_week';
  static const String openItem = 'keepit_open_item';
  static const String sparkCategory = 'keepit_spark';
}

/// Runs in a separate background isolate when an action button that does not
/// open the app ("Mark Watched" / "Remind in 1 Week") is tapped while the app
/// is not in the foreground. It only appends to the action queue file, which
/// the main isolate drains the next time the app starts or resumes.
@pragma('vm:entry-point')
Future<void> keepItNotificationBackgroundHandler(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  final record = NotificationService.recordFromResponse(response, DateTime.now());
  if (record == null) return;
  final store = await SerendipityStore.open();
  await store.appendAction(record);
}

/// Smart Serendipity notification engine.
///
/// * Plans spaced-repetition reminders (day 3 / 14 / 45 / 90) with at most one
///   notification per day at the user's chosen time, plus an optional Sunday
///   Mind Digest — see [SerendipityPlanner].
/// * Re-plans whenever the app starts, resumes, or the saved items change.
/// * Tapping a notification deep-links to the item's detail sheet; action
///   buttons let the user mark an item watched or snooze it for a week without
///   opening the app.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _sparkChannelId = 'keepit_serendipity_channel';
  static const String _sparkChannelName = 'KeepIt Serendipity & Recall';
  static const String _sparkChannelDesc =
      'Resurfaces forgotten reels, articles, and bookmarks at spaced intervals.';
  static const String _digestChannelId = 'keepit_digest_channel';
  static const String _digestChannelName = 'Sunday Mind Digest';
  static const String _digestChannelDesc = 'A weekly round-up of unwatched items in your mind.';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<NotificationIntent> _intents = StreamController<NotificationIntent>.broadcast();
  final StreamController<NotificationActionRecord> _foregroundActions =
      StreamController<NotificationActionRecord>.broadcast();

  SerendipityStore _store = SerendipityStore.inMemory();
  SerendipityEngineState _state = const SerendipityEngineState();
  bool _initialized = false;
  bool _pluginReady = false;
  NotificationIntent? _pendingLaunchIntent;
  Future<void> _queue = Future<void>.value();

  /// Emits whenever a notification tap should open something in the UI.
  Stream<NotificationIntent> get intents => _intents.stream;

  /// Emits "Mark Watched" / "Snooze" actions tapped while the app is running.
  Stream<NotificationActionRecord> get foregroundActions => _foregroundActions.stream;

  ReminderSettings get settings => _state.settings;
  List<PlannedReminder> get upcoming => List.unmodifiable(_state.plan);
  bool get isSupported => _pluginReady;

  /// The notification that cold-started the app (if any). Consumed once.
  NotificationIntent? takeLaunchIntent() {
    final intent = _pendingLaunchIntent;
    _pendingLaunchIntent = null;
    return intent;
  }

  Future<void> init({SerendipityStore? store}) async {
    if (_initialized) return;
    _initialized = true;

    _store = store ?? await SerendipityStore.open();
    _state = await _store.loadState();

    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!supported) return;

    try {
      final darwinSettings = DarwinInitializationSettings(
        // Permission is requested explicitly (see requestPermission) so the
        // prompt does not appear before the app has even rendered.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            NotificationActions.sparkCategory,
            actions: [
              DarwinNotificationAction.plain(NotificationActions.markWatched, '✅ Mark Watched'),
              DarwinNotificationAction.plain(NotificationActions.snoozeWeek, '⏰ Remind in 1 Week'),
              DarwinNotificationAction.plain(
                NotificationActions.openItem,
                'Open',
                options: {DarwinNotificationActionOption.foreground},
              ),
            ],
          ),
        ],
      );

      await _plugin.initialize(
        InitializationSettings(
          android: const AndroidInitializationSettings('@drawable/ic_stat_keepit'),
          iOS: darwinSettings,
          macOS: darwinSettings,
        ),
        onDidReceiveNotificationResponse: _onForegroundResponse,
        onDidReceiveBackgroundNotificationResponse: keepItNotificationBackgroundHandler,
      );
      _pluginReady = true;

      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp && launch.notificationResponse != null) {
        final response = launch.notificationResponse!;
        final record = recordFromResponse(response, DateTime.now());
        if (record != null) {
          await _store.appendAction(record);
        } else {
          _pendingLaunchIntent = intentFromResponse(response);
        }
      }
    } catch (e) {
      debugPrint('KeepIt notifications unavailable: $e');
      _pluginReady = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Asks for notification permission (Android 13+ / iOS). Returns whether
  /// notifications are allowed.
  Future<bool> requestPermission() async {
    if (!_pluginReady) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }
      final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (mac != null) {
        return await mac.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }
    } catch (e) {
      debugPrint('KeepIt notification permission error: $e');
    }
    return false;
  }

  /// `null` when unknown (e.g. unsupported platform).
  Future<bool?> areNotificationsEnabled() async {
    if (!_pluginReady) return null;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.areNotificationsEnabled();
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return (await ios.checkPermissions())?.isEnabled;
      final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (mac != null) return (await mac.checkPermissions())?.isEnabled;
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // Action queue (from background isolate / cold start)
  // ---------------------------------------------------------------------------

  /// Returns queued notification actions for the app to apply to its data,
  /// and immediately records snoozes in the engine state.
  Future<List<NotificationActionRecord>> consumePendingActions() {
    return _serialized(() async {
      final actions = await _store.drainActions();
      if (actions.isEmpty) return actions;
      final snoozes = Map<String, DateTime>.from(_state.snoozes);
      for (final a in actions) {
        if (a.type == NotificationActionRecord.snooze && a.until != null) {
          snoozes[a.itemId] = a.until!;
        } else if (a.type == NotificationActionRecord.watched) {
          snoozes.remove(a.itemId);
        }
      }
      _state = _state.copyWith(snoozes: snoozes);
      await _store.saveState(_state);
      return actions;
    });
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  /// Recomputes and (re)schedules all Serendipity reminders for [items].
  Future<void> reschedule(List<MindItem> items, {DateTime? now}) {
    return _serialized(() => _reschedule(items, now ?? DateTime.now()));
  }

  Future<void> updateSettings(ReminderSettings settings, List<MindItem> items) {
    return _serialized(() async {
      _state = _state.copyWith(settings: settings);
      await _reschedule(items, DateTime.now());
    });
  }

  /// "Remind in 1 week" triggered from inside the app.
  Future<void> snoozeItem(String itemId, List<MindItem> items, {Duration? duration}) {
    return _serialized(() async {
      final until = DateTime.now().add(duration ?? SerendipityPlanner.snoozeDuration);
      _state = _state.copyWith(snoozes: {..._state.snoozes, itemId: until});
      await _reschedule(items, DateTime.now());
    });
  }

  Future<void> _reschedule(List<MindItem> items, DateTime now) async {
    final ids = items.map((i) => i.id).toSet();
    _state = SerendipityPlanner.commitDelivered(_state, now: now, existingItemIds: ids);
    final newPlan = SerendipityPlanner.plan(items: items, state: _state, now: now);
    final byId = {for (final i in items) i.id: i};

    if (_pluginReady) {
      try {
        await _cancelPlanned();
        for (final reminder in newPlan) {
          await _schedule(reminder, byId);
        }
      } catch (e) {
        debugPrint('KeepIt failed to schedule reminders: $e');
      }
    }

    _state = _state.copyWith(plan: newPlan);
    await _store.saveState(_state);
  }

  Future<void> _cancelPlanned() async {
    // Cancel everything we previously scheduled, plus anything in our id range
    // the OS still knows about (covers a lost/corrupt state file).
    final ids = <int>{..._state.plan.map((p) => p.id)};
    try {
      final pending = await _plugin.pendingNotificationRequests();
      ids.addAll(pending.map((p) => p.id).where(SerendipityPlanner.isPlannedId));
    } catch (_) {}
    for (final id in ids) {
      await _plugin.cancel(id);
    }
  }

  Future<void> _schedule(PlannedReminder reminder, Map<String, MindItem> byId) async {
    // Convert the planned *local* wall-clock time into an absolute instant.
    // Using UTC avoids needing the device's IANA timezone name; the plan is
    // rebuilt on every launch/resume so DST changes self-correct.
    final when = tz.TZDateTime.from(reminder.fireAt, tz.UTC);
    final details = _detailsFor(reminder, byId);

    Future<void> scheduleWith(AndroidScheduleMode mode) {
      return _plugin.zonedSchedule(
        reminder.id,
        reminder.title,
        reminder.body,
        when,
        details,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: reminder.payload,
      );
    }

    try {
      // Inexact alarms need no special permission and are battery-friendly;
      // a few minutes of drift is fine for a gentle daily reminder.
      await scheduleWith(AndroidScheduleMode.inexactAllowWhileIdle);
    } catch (e) {
      debugPrint('KeepIt: could not schedule reminder ${reminder.id}: $e');
    }
  }

  NotificationDetails _detailsFor(PlannedReminder reminder, Map<String, MindItem> byId) {
    if (reminder.kind == ReminderKind.digest) {
      final android = AndroidNotificationDetails(
        _digestChannelId,
        _digestChannelName,
        channelDescription: _digestChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@drawable/ic_stat_keepit',
        category: AndroidNotificationCategory.recommendation,
        styleInformation: InboxStyleInformation(
          reminder.lines,
          contentTitle: reminder.title,
          summaryText: 'Tap to open Serendipity',
        ),
      );
      return NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(threadIdentifier: 'keepit_digest'),
        macOS: const DarwinNotificationDetails(threadIdentifier: 'keepit_digest'),
      );
    }

    final item = reminder.itemId == null ? null : byId[reminder.itemId!];
    final android = AndroidNotificationDetails(
      _sparkChannelId,
      _sparkChannelName,
      channelDescription: _sparkChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_keepit',
      category: AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(
        reminder.body,
        contentTitle: reminder.title,
        summaryText: item == null ? null : 'Serendipity • ${SerendipityPlanner.nounFor(item.type)}',
      ),
      actions: const [
        AndroidNotificationAction(NotificationActions.markWatched, '✅ Mark Watched'),
        AndroidNotificationAction(NotificationActions.snoozeWeek, '⏰ In 1 Week'),
        AndroidNotificationAction(NotificationActions.openItem, 'Open', showsUserInterface: true),
      ],
    );
    const darwin = DarwinNotificationDetails(
      categoryIdentifier: NotificationActions.sparkCategory,
      threadIdentifier: 'keepit_spark',
    );
    return NotificationDetails(android: android, iOS: darwin, macOS: darwin);
  }

  /// Instant preview of a Spark notification (used by "Send test" in the
  /// reminder settings). Includes the real action buttons.
  Future<bool> showTestNotification(MindItem item) async {
    if (!_pluginReady) return false;
    final granted = await requestPermission();
    if (!granted) return false;
    final preview = PlannedReminder(
      id: SerendipityPlanner.testNotificationId,
      kind: ReminderKind.spark,
      fireAt: DateTime.now(),
      itemId: item.id,
      title: '🧠 Remember this ${SerendipityPlanner.nounFor(item.type)}?',
      body: '"${item.title}" — you saved it ${SerendipityPlanner.ageLabel(item.createdAt, DateTime.now())}. '
          'Tap to revisit.',
    );
    try {
      await _plugin.show(
        preview.id,
        preview.title,
        preview.body,
        _detailsFor(preview, {item.id: item}),
        payload: preview.payload,
      );
      return true;
    } catch (e) {
      debugPrint('KeepIt test notification failed: $e');
      return false;
    }
  }

  /// Backwards-compatible alias for the old API.
  Future<void> showSerendipityNotification(MindItem item) => showTestNotification(item);

  Future<void> cancelAll() => _serialized(() async {
        if (_pluginReady) await _cancelPlanned();
        _state = _state.copyWith(plan: const []);
        await _store.saveState(_state);
      });

  // ---------------------------------------------------------------------------
  // Responses
  // ---------------------------------------------------------------------------

  void _onForegroundResponse(NotificationResponse response) {
    final record = recordFromResponse(response, DateTime.now());
    if (record != null) {
      if (record.type == NotificationActionRecord.snooze && record.until != null) {
        _serialized(() async {
          _state = _state.copyWith(snoozes: {..._state.snoozes, record.itemId: record.until!});
          await _store.saveState(_state);
        });
      }
      _foregroundActions.add(record);
      return;
    }
    final intent = intentFromResponse(response);
    if (intent != null) _intents.add(intent);
  }

  /// Maps an action-button response to a data change, or `null` if the
  /// response is a plain tap / "Open".
  static NotificationActionRecord? recordFromResponse(NotificationResponse response, DateTime now) {
    final actionId = response.actionId;
    if (actionId != NotificationActions.markWatched && actionId != NotificationActions.snoozeWeek) {
      return null;
    }
    final itemId = decodePayload(response.payload)['itemId'] as String?;
    if (itemId == null) return null;
    if (actionId == NotificationActions.markWatched) {
      return NotificationActionRecord(type: NotificationActionRecord.watched, itemId: itemId, at: now);
    }
    return NotificationActionRecord(
      type: NotificationActionRecord.snooze,
      itemId: itemId,
      until: now.add(SerendipityPlanner.snoozeDuration),
      at: now,
    );
  }

  static NotificationIntent? intentFromResponse(NotificationResponse response) {
    final payload = decodePayload(response.payload);
    final kind = payload['kind'] as String?;
    final itemId = payload['itemId'] as String?;
    if (kind == ReminderKind.digest.name) return const NotificationIntent.openDigest();
    if (itemId != null) return NotificationIntent.openItem(itemId);
    return null;
  }

  /// Supports the JSON payload and the legacy "raw item id" payload.
  static Map<String, dynamic> decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {'kind': ReminderKind.spark.name, 'itemId': payload};
  }

  /// Runs scheduling work one-at-a-time so concurrent calls never interleave.
  Future<T> _serialized<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  @visibleForTesting
  void resetForTest() {
    _initialized = false;
    _pluginReady = false;
    _state = const SerendipityEngineState();
    _store = SerendipityStore.inMemory();
    _pendingLaunchIntent = null;
  }
}
