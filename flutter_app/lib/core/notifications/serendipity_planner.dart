import 'dart:convert';

import '../../domain/entities/mind_item.dart';

/// Pure (platform-free) scheduling logic for the Serendipity notification
/// engine. Everything in here is deterministic and unit-testable: it takes the
/// saved items + engine state + "now" and returns the reminders to schedule.
///
/// Why pre-planning? `flutter_local_notifications` cannot run Dart code at the
/// moment a scheduled notification fires, so we cannot "pick an item at 8:30
/// PM". Instead we simulate the next [SerendipityPlanner.horizonDays] days
/// ahead of time, and re-plan whenever the app opens or the data changes.

enum ReminderKind { spark, digest }

/// User-facing preferences for Serendipity notifications.
class ReminderSettings {
  final bool enabled;
  final int hour;
  final int minute;
  final bool weeklyDigest;

  const ReminderSettings({
    this.enabled = true,
    this.hour = 20,
    this.minute = 30,
    this.weeklyDigest = true,
  });

  ReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? weeklyDigest,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weeklyDigest: weeklyDigest ?? this.weeklyDigest,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'weeklyDigest': weeklyDigest,
      };

  factory ReminderSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReminderSettings();
    return ReminderSettings(
      enabled: json['enabled'] as bool? ?? true,
      hour: (json['hour'] as num?)?.toInt().clamp(0, 23) ?? 20,
      minute: (json['minute'] as num?)?.toInt().clamp(0, 59) ?? 30,
      weeklyDigest: json['weeklyDigest'] as bool? ?? true,
    );
  }
}

/// A single notification that is (or will be) scheduled with the OS.
class PlannedReminder {
  final int id;
  final ReminderKind kind;
  final DateTime fireAt;

  /// Spark only: the item being resurfaced.
  final String? itemId;

  /// Spark only: spaced-repetition stage index into
  /// [SerendipityPlanner.stageDays]. `-1` for snoozed reminders, which do not
  /// advance the stage.
  final int stage;

  /// Spark only: true when this reminder exists because the user tapped
  /// "Remind in 1 week".
  final bool snoozed;

  /// Digest only: the items featured in the digest.
  final List<String> itemIds;

  final String title;
  final String body;

  /// Digest only: one line per item (used for Android InboxStyle).
  final List<String> lines;

  const PlannedReminder({
    required this.id,
    required this.kind,
    required this.fireAt,
    this.itemId,
    this.stage = -1,
    this.snoozed = false,
    this.itemIds = const [],
    required this.title,
    required this.body,
    this.lines = const [],
  });

  /// Compact payload delivered back to the app when the notification (or one
  /// of its action buttons) is tapped.
  String get payload => jsonEncode({
        'kind': kind.name,
        if (itemId != null) 'itemId': itemId,
        if (itemIds.isNotEmpty) 'itemIds': itemIds,
      });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'fireAt': fireAt.toIso8601String(),
        'itemId': itemId,
        'stage': stage,
        'snoozed': snoozed,
        'itemIds': itemIds,
        'title': title,
        'body': body,
        'lines': lines,
      };

  factory PlannedReminder.fromJson(Map<String, dynamic> json) {
    return PlannedReminder(
      id: (json['id'] as num).toInt(),
      kind: ReminderKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => ReminderKind.spark,
      ),
      fireAt: DateTime.parse(json['fireAt'] as String),
      itemId: json['itemId'] as String?,
      stage: (json['stage'] as num?)?.toInt() ?? -1,
      snoozed: json['snoozed'] as bool? ?? false,
      itemIds: List<String>.from(json['itemIds'] as List? ?? const []),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      lines: List<String>.from(json['lines'] as List? ?? const []),
    );
  }
}

/// Everything the engine persists between app launches.
class SerendipityEngineState {
  final ReminderSettings settings;

  /// itemId -> highest spaced-repetition stage already delivered.
  final Map<String, int> lastStage;

  /// itemId -> "don't remind before" moment (from "Remind in 1 week").
  final Map<String, DateTime> snoozes;

  /// Reminders currently handed to the OS scheduler.
  final List<PlannedReminder> plan;

  const SerendipityEngineState({
    this.settings = const ReminderSettings(),
    this.lastStage = const {},
    this.snoozes = const {},
    this.plan = const [],
  });

  SerendipityEngineState copyWith({
    ReminderSettings? settings,
    Map<String, int>? lastStage,
    Map<String, DateTime>? snoozes,
    List<PlannedReminder>? plan,
  }) {
    return SerendipityEngineState(
      settings: settings ?? this.settings,
      lastStage: lastStage ?? this.lastStage,
      snoozes: snoozes ?? this.snoozes,
      plan: plan ?? this.plan,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'settings': settings.toJson(),
        'lastStage': lastStage,
        'snoozes': snoozes.map((k, v) => MapEntry(k, v.toIso8601String())),
        'plan': plan.map((p) => p.toJson()).toList(),
      };

  factory SerendipityEngineState.fromJson(Map<String, dynamic> json) {
    final rawStages = (json['lastStage'] as Map?) ?? const {};
    final rawSnoozes = (json['snoozes'] as Map?) ?? const {};
    final rawPlan = (json['plan'] as List?) ?? const [];
    return SerendipityEngineState(
      settings: ReminderSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>(),
      ),
      lastStage: rawStages.map(
        (k, v) => MapEntry(k as String, (v as num).toInt()),
      ),
      snoozes: rawSnoozes.map(
        (k, v) => MapEntry(k as String, DateTime.parse(v as String)),
      ),
      plan: rawPlan
          .whereType<Map>()
          .map((e) => PlannedReminder.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class SerendipityPlanner {
  SerendipityPlanner._();

  /// Adapted Ebbinghaus curve: first spark on day 3, reinforcement on day 14,
  /// deep rediscovery on days 45 and 90 (see docs/NOTIFICATION_ENGINE.md).
  static const List<int> stageDays = [3, 14, 45, 90];

  /// How many days ahead we pre-schedule. Kept well under iOS's limit of 64
  /// pending notifications (max 1 per day here).
  static const int horizonDays = 14;

  /// Sunday Mind Digest time.
  static const int digestHour = 10;
  static const int digestMinute = 0;
  static const int digestSize = 3;

  static const Duration snoozeDuration = Duration(days: 7);

  /// Notification id ranges (kept separate so re-planning never touches
  /// unrelated notifications such as the instant test notification).
  static const int sparkIdBase = 1000000;
  static const int digestIdBase = 2000000;
  static const int idRangeEnd = 3000000;
  static const int testNotificationId = 999;

  static bool isPlannedId(int id) => id >= sparkIdBase && id < idRangeEnd;

  /// Moves reminders whose fire time has passed out of the pending plan and
  /// records them as delivered (advancing each item's stage / clearing
  /// snoozes). Also forgets state for items that no longer exist.
  static SerendipityEngineState commitDelivered(
    SerendipityEngineState state, {
    required DateTime now,
    Set<String>? existingItemIds,
  }) {
    final lastStage = Map<String, int>.from(state.lastStage);
    final snoozes = Map<String, DateTime>.from(state.snoozes);
    final stillPending = <PlannedReminder>[];

    for (final p in state.plan) {
      if (p.fireAt.isAfter(now)) {
        stillPending.add(p);
        continue;
      }
      if (p.kind != ReminderKind.spark || p.itemId == null) continue;
      final id = p.itemId!;
      if (p.stage >= 0) {
        final prev = lastStage[id] ?? -1;
        if (p.stage > prev) lastStage[id] = p.stage;
      }
      if (p.snoozed) {
        final until = snoozes[id];
        if (until != null && !until.isAfter(p.fireAt)) snoozes.remove(id);
      }
    }

    if (existingItemIds != null) {
      lastStage.removeWhere((k, _) => !existingItemIds.contains(k));
      snoozes.removeWhere((k, _) => !existingItemIds.contains(k));
    }

    return state.copyWith(
      lastStage: lastStage,
      snoozes: snoozes,
      plan: stillPending,
    );
  }

  /// Builds the reminder plan for the next [horizonDays] days.
  ///
  /// Rules:
  /// * At most one Serendipity notification per day.
  /// * Daily Spark at the user's chosen time; on Sundays the Mind Digest
  ///   (10:00 AM) replaces it when enabled and there is something to show.
  /// * Only unwatched items. Snoozed items come first once their snooze ends,
  ///   then "Top of Mind" items, then whichever item has been due the longest.
  /// * If an item is overdue for several stages (e.g. it was saved 50 days
  ///   ago and never reminded), it jumps straight to the latest due stage so
  ///   the user is not spammed with stale stages.
  static List<PlannedReminder> plan({
    required List<MindItem> items,
    required SerendipityEngineState state,
    required DateTime now,
    int horizon = horizonDays,
  }) {
    final settings = state.settings;
    if (!settings.enabled) return const [];

    final candidates = items.where((i) => !i.isWatched).toList();
    if (candidates.isEmpty) return const [];

    // Simulated copies — each day's pick affects the following days.
    final lastStage = Map<String, int>.from(state.lastStage);
    final snoozes = Map<String, DateTime>.from(state.snoozes);
    final result = <PlannedReminder>[];
    final today = _dateOnly(now);

    for (var offset = 0; offset < horizon; offset++) {
      final day = DateTime(today.year, today.month, today.day + offset);

      // Sunday Mind Digest (replaces that day's Spark).
      if (settings.weeklyDigest && day.weekday == DateTime.sunday) {
        final fireAt = DateTime(
          day.year,
          day.month,
          day.day,
          digestHour,
          digestMinute,
        );
        if (fireAt.isAfter(now)) {
          final digestItems = _pickDigestItems(candidates, fireAt);
          if (digestItems.isNotEmpty) {
            result.add(_buildDigest(day, fireAt, digestItems));
            continue;
          }
        }
      }

      final fireAt = DateTime(
        day.year,
        day.month,
        day.day,
        settings.hour,
        settings.minute,
      );
      if (!fireAt.isAfter(now)) continue;

      final pick = _pickSpark(candidates, lastStage, snoozes, fireAt);
      if (pick == null) continue;

      result.add(_buildSpark(day, fireAt, pick.item, pick.stage, pick.snoozed));
      if (pick.snoozed) {
        snoozes.remove(pick.item.id);
      } else {
        lastStage[pick.item.id] = pick.stage;
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Picking
  // ---------------------------------------------------------------------------

  static _SparkPick? _pickSpark(
    List<MindItem> candidates,
    Map<String, int> lastStage,
    Map<String, DateTime> snoozes,
    DateTime fireAt,
  ) {
    final fireDay = _dateOnly(fireAt);
    final picks = <_SparkPick>[];

    for (final item in candidates) {
      final snoozedUntil = snoozes[item.id];
      if (snoozedUntil != null) {
        // A snoozed item is silenced until the snooze ends, then gets priority.
        if (!snoozedUntil.isAfter(fireAt)) {
          picks.add(_SparkPick(item, -1, true, snoozedUntil));
        }
        continue;
      }

      final nextStage = (lastStage[item.id] ?? -1) + 1;
      if (nextStage >= stageDays.length) continue;

      final created = _dateOnly(item.createdAt);
      int? dueStage;
      DateTime? dueDate;
      for (var s = nextStage; s < stageDays.length; s++) {
        final due = DateTime(
          created.year,
          created.month,
          created.day + stageDays[s],
        );
        if (due.isAfter(fireDay)) break;
        dueStage = s;
        dueDate = due;
      }
      if (dueStage != null) {
        picks.add(_SparkPick(item, dueStage, false, dueDate!));
      }
    }

    if (picks.isEmpty) return null;

    picks.sort((a, b) {
      if (a.snoozed != b.snoozed) return a.snoozed ? -1 : 1;
      if (a.item.isTopMind != b.item.isTopMind)
        return a.item.isTopMind ? -1 : 1;
      final byDue = a.dueSince.compareTo(b.dueSince); // longest-waiting first
      if (byDue != 0) return byDue;
      return a.item.createdAt.compareTo(b.item.createdAt);
    });
    return picks.first;
  }

  static List<MindItem> _pickDigestItems(
    List<MindItem> candidates,
    DateTime fireAt,
  ) {
    // Anything saved at least a day before the digest qualifies.
    final eligible = candidates
        .where(
          (i) => !i.createdAt.isAfter(fireAt.subtract(const Duration(days: 1))),
        )
        .toList();
    eligible.sort((a, b) {
      if (a.isTopMind != b.isTopMind) return a.isTopMind ? -1 : 1;
      return a.createdAt.compareTo(b.createdAt); // most forgotten first
    });
    return eligible.take(digestSize).toList();
  }

  // ---------------------------------------------------------------------------
  // Copywriting
  // ---------------------------------------------------------------------------

  static PlannedReminder _buildSpark(
    DateTime day,
    DateTime fireAt,
    MindItem item,
    int stage,
    bool snoozed,
  ) {
    final noun = nounFor(item.type);
    final title = _truncate(item.title, 70);
    final by = _byline(item);
    final age = ageLabel(item.createdAt, fireAt);

    String heading;
    String body;
    if (snoozed) {
      heading = '⏰ Reminder, as promised';
      body = '"$title"$by — you asked KeepIt to bring this $noun back today.';
    } else if (stage <= 0) {
      heading = '🧠 Remember this $noun?';
      body = '"$title"$by — you saved it $age. Tap to revisit.';
    } else if (stage == 1) {
      heading = '💡 Still relevant?';
      body = 'You saved "$title"$by $age. Worth a look now?';
    } else {
      heading = '✨ Rediscover a hidden gem';
      body = '"$title"$by — saved $age and still waiting in your mind.';
    }

    return PlannedReminder(
      id: sparkIdBase + _dayNumber(day),
      kind: ReminderKind.spark,
      fireAt: fireAt,
      itemId: item.id,
      stage: stage,
      snoozed: snoozed,
      title: heading,
      body: body,
    );
  }

  static PlannedReminder _buildDigest(
    DateTime day,
    DateTime fireAt,
    List<MindItem> items,
  ) {
    final lines = items.map((i) => '• ${_truncate(i.title, 60)}').toList();
    final count = items.length;
    final body = count == 1
        ? '1 unwatched gem is waiting: ${_truncate(items.first.title, 60)}'
        : '$count unwatched gems are waiting: ${items.map((i) => _truncate(i.title, 30)).join(' • ')}';
    return PlannedReminder(
      id: digestIdBase + _dayNumber(day),
      kind: ReminderKind.digest,
      fireAt: fireAt,
      itemIds: items.map((i) => i.id).toList(),
      title: '☀️ Your Sunday Mind Digest',
      body: body,
      lines: lines,
    );
  }

  static String nounFor(ItemType type) {
    switch (type) {
      case ItemType.instagramReel:
        return 'reel';
      case ItemType.youtubeVideo:
        return 'video';
      case ItemType.webArticle:
        return 'article';
      case ItemType.quote:
        return 'quote';
      case ItemType.image:
        return 'image';
      case ItemType.quickNote:
        return 'note';
    }
  }

  /// "today", "yesterday", "3 days ago", "2 weeks ago", "3 months ago"...
  /// measured from [createdAt] to [at] in calendar days.
  static String ageLabel(DateTime createdAt, DateTime at) {
    final days = _dateOnly(at).difference(_dateOnly(createdAt)).inHours ~/ 24;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    if (days < 14) return 'a week ago';
    if (days < 30) return '${days ~/ 7} weeks ago';
    if (days < 60) return 'a month ago';
    if (days < 365) return '${days ~/ 30} months ago';
    return 'over a year ago';
  }

  static String _byline(MindItem item) {
    final author = item.authorName?.trim();
    if (author == null || author.isEmpty) return '';
    const generic = {
      'youtube',
      'instagram',
      'keepit',
      'keepit mind',
      'web',
      'unknown',
    };
    if (generic.contains(author.toLowerCase())) return '';
    return ' by $author';
  }

  static String _truncate(String text, int max) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= max) return clean;
    return '${clean.substring(0, max - 1).trimRight()}…';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Stable per-calendar-day number (UTC-based so DST never shifts it).
  static int _dayNumber(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

class _SparkPick {
  final MindItem item;
  final int stage;
  final bool snoozed;
  final DateTime dueSince;

  _SparkPick(this.item, this.stage, this.snoozed, this.dueSince);
}
