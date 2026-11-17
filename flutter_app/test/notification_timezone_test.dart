import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/utils/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// A reminder is planned as a *wall-clock* time ("20:30"), so the instant the
/// OS schedules must land on 20:30 in the user's real timezone — across a DST
/// change and after travelling. Scheduling used to assume UTC.
void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('India: 20:30 wall clock is 15:00Z (UTC+5:30, no DST)', () {
    final kolkata = tz.getLocation('Asia/Kolkata');
    final when = NotificationService.wallClockToInstant(
      DateTime(2026, 11, 21, 20, 30),
      kolkata,
    );

    expect(when.location.name, 'Asia/Kolkata');
    expect(when.hour, 20);
    expect(when.minute, 30);
    expect(when.toUtc().hour, 15);
    expect(when.toUtc().day, 21);
  });

  test('New York: the same wall clock is a different instant per season', () {
    final ny = tz.getLocation('America/New_York');

    final winter = NotificationService.wallClockToInstant(
      DateTime(2026, 1, 15, 20, 30),
      ny,
    );
    final summer = NotificationService.wallClockToInstant(
      DateTime(2026, 7, 15, 20, 30),
      ny,
    );

    // 20:30 local both times, but 01:30Z in winter and 00:30Z in summer.
    expect(winter.hour, 20);
    expect(summer.hour, 20);
    expect(winter.toUtc().hour, 1);
    expect(summer.toUtc().hour, 0);
    expect(winter.toUtc().hour, isNot(summer.toUtc().hour));
  });

  test('the DST switch day itself keeps the wall-clock time', () {
    final ny = tz.getLocation('America/New_York');
    // 2027-03-14 is the US spring-forward day.
    final before = NotificationService.wallClockToInstant(
      DateTime(2027, 3, 13, 20, 30),
      ny,
    );
    final after = NotificationService.wallClockToInstant(
      DateTime(2027, 3, 14, 20, 30),
      ny,
    );

    expect(before.hour, 20);
    expect(after.hour, 20);
    // ...which means the UTC instant shifts by an hour at the switch.
    expect(after.toUtc().hour - before.toUtc().hour, -1);
  });

  test('the resolver falls back to a fixed offset instead of throwing',
      () async {
    // The plugin is unavailable on the test VM, so this exercises the fallback.
    final zone = await NotificationService.resolveLocalZone();
    expect(zone, isA<tz.Location>());
    final when = NotificationService.wallClockToInstant(
      DateTime(2026, 11, 21, 20, 30),
      zone,
    );
    expect(when.hour, 20);
    expect(when.minute, 30);
  });
}
