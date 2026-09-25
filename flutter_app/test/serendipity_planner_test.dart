import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/notifications/serendipity_planner.dart';
import 'package:keepit/core/notifications/serendipity_store.dart';
import 'package:keepit/core/utils/notification_service.dart';
import 'package:keepit/domain/entities/mind_item.dart';

MindItem item(
  String id, {
  required DateTime created,
  bool watched = false,
  bool top = false,
  String? title,
  String? author,
  ItemType type = ItemType.instagramReel,
}) {
  return MindItem(
    id: id,
    title: title ?? 'Item $id',
    type: type,
    authorName: author,
    isWatched: watched,
    isTopMind: top,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  // Wednesday 24 Sep 2026, 09:00 local.
  final now = DateTime(2026, 9, 24, 9, 0);
  const noDigest = SerendipityEngineState(
    settings: ReminderSettings(weeklyDigest: false),
  );

  group('SerendipityPlanner.plan', () {
    test(
      'first spark lands exactly 3 days after saving, at the chosen time',
      () {
        final items = [item('a', created: DateTime(2026, 9, 23, 18, 0))];
        final plan = SerendipityPlanner.plan(
          items: items,
          state: noDigest,
          now: now,
        );

        final sparks = plan.where((p) => p.itemId == 'a').toList();
        expect(sparks.first.fireAt, DateTime(2026, 9, 26, 20, 30));
        expect(sparks.first.stage, 0);
        expect(sparks.first.title, contains('Remember this reel'));
        expect(sparks.first.body, contains('3 days ago'));
      },
    );

    test('never schedules more than one notification per day', () {
      final items = List.generate(
        10,
        (i) =>
            item('i$i', created: DateTime(2026, 9, 1).add(Duration(hours: i))),
      );
      final plan = SerendipityPlanner.plan(
        items: items,
        state: const SerendipityEngineState(),
        now: now,
      );
      final days = plan
          .map((p) => DateTime(p.fireAt.year, p.fireAt.month, p.fireAt.day))
          .toList();
      expect(days.toSet().length, days.length);
      expect(plan.length, lessThanOrEqualTo(SerendipityPlanner.horizonDays));
    });

    test('skips watched items and returns nothing when disabled', () {
      final items = [item('w', created: DateTime(2026, 9, 1), watched: true)];
      expect(
        SerendipityPlanner.plan(items: items, state: noDigest, now: now),
        isEmpty,
      );

      final unwatched = [item('u', created: DateTime(2026, 9, 1))];
      const disabled = SerendipityEngineState(
        settings: ReminderSettings(enabled: false),
      );
      expect(
        SerendipityPlanner.plan(items: unwatched, state: disabled, now: now),
        isEmpty,
      );
    });

    test('does not schedule today if the reminder time has already passed', () {
      final late = DateTime(2026, 9, 24, 21, 0);
      final items = [item('a', created: DateTime(2026, 9, 1))];
      final plan = SerendipityPlanner.plan(
        items: items,
        state: noDigest,
        now: late,
      );
      expect(plan.first.fireAt.day, 25);
    });

    test(
      'overdue items jump to the latest due stage (no stale-stage spam)',
      () {
        // Saved 50 days ago, never reminded: day-3 and day-14 are stale,
        // day-45 is the latest due stage.
        final items = [
          item('old', created: now.subtract(const Duration(days: 50))),
        ];
        final plan = SerendipityPlanner.plan(
          items: items,
          state: noDigest,
          now: now,
        );
        expect(plan, hasLength(1));
        expect(plan.first.stage, 2);
        expect(plan.first.title, contains('hidden gem'));
      },
    );

    test('an item progresses through stages 3 → 14 across the horizon', () {
      final items = [item('a', created: DateTime(2026, 9, 20))];
      final plan = SerendipityPlanner.plan(
        items: items,
        state: noDigest,
        now: now,
        horizon: 30,
      );
      expect(plan.map((p) => p.stage).toList(), [0, 1]);
      // Day-3 was due yesterday (23rd) → catches up tonight; day-14 on Oct 4.
      expect(plan[0].fireAt, DateTime(2026, 9, 24, 20, 30));
      expect(plan[1].fireAt, DateTime(2026, 10, 4, 20, 30));
    });

    test('Top of Mind items win when several are due the same day', () {
      final created = DateTime(2026, 9, 21);
      final items = [
        item('normal', created: created),
        item('top', created: created.add(const Duration(hours: 5)), top: true),
      ];
      final plan = SerendipityPlanner.plan(
        items: items,
        state: noDigest,
        now: now,
      );
      expect(plan.first.itemId, 'top');
      expect(plan[1].itemId, 'normal');
    });

    test('Sunday Mind Digest replaces the spark on Sundays at 10:00', () {
      final items = [
        for (var i = 0; i < 5; i++)
          item('d$i', created: DateTime(2026, 9, 10 + i), title: 'Digest $i'),
      ];
      final plan = SerendipityPlanner.plan(
        items: items,
        state: const SerendipityEngineState(),
        now: now,
      );
      final digests = plan.where((p) => p.kind == ReminderKind.digest).toList();
      expect(digests, isNotEmpty);
      final d = digests.first;
      expect(d.fireAt, DateTime(2026, 9, 27, 10, 0)); // Sunday
      expect(d.itemIds, hasLength(3));
      expect(d.itemIds.first, 'd0'); // most forgotten first
      expect(d.lines.first, '• Digest 0');
      // No spark on the same Sunday.
      expect(plan.where((p) => p.fireAt.day == 27), hasLength(1));
    });

    test('snoozed item is silent until snooze ends, then resurfaces first', () {
      final items = [
        item('snoozed', created: DateTime(2026, 9, 1)),
        item('other', created: DateTime(2026, 9, 2)),
      ];
      final state = noDigest.copyWith(
        lastStage: {'snoozed': 1},
        snoozes: {'snoozed': DateTime(2026, 9, 28, 12, 0)},
      );
      final plan = SerendipityPlanner.plan(
        items: items,
        state: state,
        now: now,
      );
      final snoozedPlans = plan.where((p) => p.itemId == 'snoozed').toList();
      expect(snoozedPlans, hasLength(1));
      expect(snoozedPlans.first.snoozed, isTrue);
      expect(snoozedPlans.first.fireAt, DateTime(2026, 9, 28, 20, 30));
      expect(snoozedPlans.first.title, contains('as promised'));
    });

    test('uses stable per-day ids inside the planner id range', () {
      final items = [item('a', created: DateTime(2026, 9, 1))];
      final p1 = SerendipityPlanner.plan(
        items: items,
        state: noDigest,
        now: now,
      );
      final p2 = SerendipityPlanner.plan(
        items: items,
        state: noDigest,
        now: now,
      );
      expect(p1.map((p) => p.id), p2.map((p) => p.id));
      expect(p1.every((p) => SerendipityPlanner.isPlannedId(p.id)), isTrue);
      expect(
        SerendipityPlanner.isPlannedId(SerendipityPlanner.testNotificationId),
        isFalse,
      );
    });

    test('drops generic author names from the copy', () {
      final items = [
        item(
          'yt',
          created: DateTime(2026, 9, 21),
          author: 'YouTube',
          type: ItemType.youtubeVideo,
        ),
      ];
      final plan = SerendipityPlanner.plan(
        items: items,
        state: noDigest,
        now: now,
      );
      expect(plan.first.body, isNot(contains('by YouTube')));
      expect(plan.first.title, contains('video'));
    });
  });

  group('SerendipityPlanner.commitDelivered', () {
    test('advances stage for delivered reminders and keeps future ones', () {
      final past = PlannedReminder(
        id: 1,
        kind: ReminderKind.spark,
        fireAt: now.subtract(const Duration(hours: 1)),
        itemId: 'a',
        stage: 0,
        title: '',
        body: '',
      );
      final future = PlannedReminder(
        id: 2,
        kind: ReminderKind.spark,
        fireAt: now.add(const Duration(days: 1)),
        itemId: 'b',
        stage: 0,
        title: '',
        body: '',
      );
      final state = SerendipityEngineState(plan: [past, future]);
      final next = SerendipityPlanner.commitDelivered(
        state,
        now: now,
        existingItemIds: {'a', 'b'},
      );
      expect(next.lastStage, {'a': 0});
      expect(next.plan.map((p) => p.id), [2]);
    });

    test(
        'clears a snooze once its reminder was delivered and forgets deleted items',
        () {
      final snoozeFire = now.subtract(const Duration(minutes: 5));
      final state = SerendipityEngineState(
        lastStage: {'gone': 2},
        snoozes: {'a': snoozeFire.subtract(const Duration(hours: 1))},
        plan: [
          PlannedReminder(
            id: 1,
            kind: ReminderKind.spark,
            fireAt: snoozeFire,
            itemId: 'a',
            snoozed: true,
            title: '',
            body: '',
          ),
        ],
      );
      final next = SerendipityPlanner.commitDelivered(
        state,
        now: now,
        existingItemIds: {'a'},
      );
      expect(next.snoozes, isEmpty);
      expect(next.lastStage.containsKey('gone'), isFalse);
    });
  });

  group('State & payload serialisation', () {
    test('engine state round-trips through JSON', () {
      final state = SerendipityEngineState(
        settings: const ReminderSettings(
          hour: 8,
          minute: 15,
          weeklyDigest: false,
        ),
        lastStage: const {'a': 1},
        snoozes: {'b': DateTime(2026, 10, 1, 9)},
        plan: SerendipityPlanner.plan(
          items: [item('a', created: DateTime(2026, 9, 1))],
          state: noDigest,
          now: now,
        ),
      );
      final decoded = SerendipityEngineState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.settings.hour, 8);
      expect(decoded.settings.minute, 15);
      expect(decoded.settings.weeklyDigest, isFalse);
      expect(decoded.lastStage, {'a': 1});
      expect(decoded.snoozes['b'], DateTime(2026, 10, 1, 9));
      expect(decoded.plan.length, state.plan.length);
      expect(decoded.plan.first.payload, state.plan.first.payload);
    });

    test('notification taps map to deep-link intents', () {
      final spark = NotificationService.intentFromResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: jsonEncode({'kind': 'spark', 'itemId': 'abc'}),
        ),
      );
      expect(spark?.type, NotificationIntent.typeItem);
      expect(spark?.itemId, 'abc');

      final digest = NotificationService.intentFromResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: jsonEncode({
            'kind': 'digest',
            'itemIds': ['a', 'b'],
          }),
        ),
      );
      expect(digest?.type, NotificationIntent.typeDigest);

      // Legacy payload = raw item id.
      final legacy = NotificationService.intentFromResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'legacy-id',
        ),
      );
      expect(legacy?.itemId, 'legacy-id');
    });

    test('action buttons map to watched / snooze records', () {
      final payload = jsonEncode({'kind': 'spark', 'itemId': 'x'});
      final watched = NotificationService.recordFromResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NotificationActions.markWatched,
          payload: payload,
        ),
        now,
      );
      expect(watched?.type, NotificationActionRecord.watched);
      expect(watched?.itemId, 'x');

      final snooze = NotificationService.recordFromResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NotificationActions.snoozeWeek,
          payload: payload,
        ),
        now,
      );
      expect(snooze?.type, NotificationActionRecord.snooze);
      expect(snooze?.until, now.add(const Duration(days: 7)));

      final open = NotificationService.recordFromResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NotificationActions.openItem,
          payload: payload,
        ),
        now,
      );
      expect(open, isNull);
    });
  });

  group('SerendipityStore (file based)', () {
    late Directory dir;
    setUp(
      () async => dir = await Directory.systemTemp.createTemp('keepit_store_'),
    );
    tearDown(() async => dir.delete(recursive: true));

    test('persists state and drains the action queue exactly once', () async {
      final store = SerendipityStore(dir.path);
      expect((await store.loadState()).settings.enabled, isTrue);

      await store.saveState(
        const SerendipityEngineState(settings: ReminderSettings(hour: 7)),
      );
      expect((await SerendipityStore(dir.path).loadState()).settings.hour, 7);

      await store.appendAction(
        NotificationActionRecord(type: 'watched', itemId: 'a', at: now),
      );
      await store.appendAction(
        NotificationActionRecord(
          type: 'snooze',
          itemId: 'b',
          until: now.add(const Duration(days: 7)),
          at: now,
        ),
      );
      final drained = await store.drainActions();
      expect(drained.map((a) => a.itemId), ['a', 'b']);
      expect(drained[1].until, now.add(const Duration(days: 7)));
      expect(await store.drainActions(), isEmpty);
    });

    test('survives a corrupt state file', () async {
      await File('${dir.path}/${SerendipityStore.stateFileName}')
          .writeAsString('{not json');
      final state = await SerendipityStore(dir.path).loadState();
      expect(state.settings.enabled, isTrue);
    });
  });
}
