import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/notifications/serendipity_planner.dart';
import 'package:keepit/core/notifications/serendipity_store.dart';
import 'package:keepit/core/utils/notification_service.dart';

/// The action buttons ("Mark watched" / "Remind in 1 week") run in a background
/// isolate straight from the notification payload. A regression here is silent:
/// the button looks like it worked and the item is never marked/snoozed.
void main() {
  NotificationResponse response(String actionId, String? payload) =>
      NotificationResponse(
        notificationResponseType: actionId.isEmpty
            ? NotificationResponseType.selectedNotification
            : NotificationResponseType.selectedNotificationAction,
        actionId: actionId,
        payload: payload,
      );

  final now = DateTime(2026, 11, 18, 20, 30);

  group('payload round-trip', () {
    test('a planned spark payload decodes back to its item', () {
      final reminder = PlannedReminder(
        id: 1000001,
        kind: ReminderKind.spark,
        fireAt: DateTime(2026, 11, 21, 20, 30),
        itemId: 'abc-123',
        title: 't',
        body: 'b',
      );
      final decoded = NotificationService.decodePayload(reminder.payload);
      expect(decoded['kind'], 'spark');
      expect(decoded['itemId'], 'abc-123');
    });

    test('a legacy raw-id payload is still understood', () {
      final decoded = NotificationService.decodePayload('item-42');
      expect(decoded['kind'], 'spark');
      expect(decoded['itemId'], 'item-42');
    });

    test('junk payloads degrade to an empty map, never throw', () {
      expect(NotificationService.decodePayload(null), isEmpty);
      expect(NotificationService.decodePayload(''), isEmpty);
      // A JSON array is not a payload object.
      expect(NotificationService.decodePayload('[1,2,3]')['itemId'], '[1,2,3]');
    });
  });

  group('recordFromResponse', () {
    final sparkPayload = jsonEncode({'kind': 'spark', 'itemId': 'abc-123'});

    test('"Mark watched" becomes a watched record', () {
      final record = NotificationService.recordFromResponse(
        response(NotificationActions.markWatched, sparkPayload),
        now,
      );
      expect(record, isNotNull);
      expect(record!.type, NotificationActionRecord.watched);
      expect(record.itemId, 'abc-123');
      expect(record.until, isNull);
      expect(record.at, now);
    });

    test('"Remind in 1 week" snoozes for exactly the planner duration', () {
      final record = NotificationService.recordFromResponse(
        response(NotificationActions.snoozeWeek, sparkPayload),
        now,
      );
      expect(record!.type, NotificationActionRecord.snooze);
      expect(record.until, now.add(SerendipityPlanner.snoozeDuration));
    });

    test('a plain tap is not an action record', () {
      expect(
        NotificationService.recordFromResponse(response('', sparkPayload), now),
        isNull,
      );
      expect(
        NotificationService.recordFromResponse(
          response(NotificationActions.openItem, sparkPayload),
          now,
        ),
        isNull,
      );
    });

    test('an action without an item id is ignored, not guessed', () {
      expect(
        NotificationService.recordFromResponse(
          response(NotificationActions.markWatched, null),
          now,
        ),
        isNull,
      );
      expect(
        NotificationService.recordFromResponse(
          response(NotificationActions.markWatched, '{"kind":"spark"}'),
          now,
        ),
        isNull,
      );
    });
  });

  group('intentFromResponse', () {
    test('digest payload opens the digest', () {
      final intent = NotificationService.intentFromResponse(
        response(
            '',
            jsonEncode({
              'kind': 'digest',
              'itemIds': ['a', 'b']
            })),
      );
      expect(intent?.type, NotificationIntent.typeDigest);
    });

    test('spark payload deep-links to the item', () {
      final intent = NotificationService.intentFromResponse(
        response('', jsonEncode({'kind': 'spark', 'itemId': 'abc-123'})),
      );
      expect(intent?.type, NotificationIntent.typeItem);
      expect(intent?.itemId, 'abc-123');
    });

    test('legacy raw-id payload still deep-links', () {
      final intent = NotificationService.intentFromResponse(
        response('', 'legacy-id'),
      );
      expect(intent?.itemId, 'legacy-id');
    });

    test('an empty payload opens nothing', () {
      expect(
        NotificationService.intentFromResponse(response('', null)),
        isNull,
      );
    });
  });
}
