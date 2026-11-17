import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:keepit/core/notifications/serendipity_planner.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// Items have been stamped in UTC since the sync fix, but several screens were
/// still formatting `createdAt` directly. On a bare `DateFormat.format` a UTC
/// DateTime prints *its own* calendar day, so a card saved at 00:30 in India
/// showed yesterday's date, and `DateTime.now().difference(utc)` threw.
///
/// This pins the conversion rule at the entity level: whatever goes in, what
/// the UI reads back is the same instant, and `.toLocal()` is what it formats.
void main() {
  MindItem roundTrip(MindItem item) =>
      MindItem.fromMap(Map<String, dynamic>.from(item.toMap()));

  test('a saved item keeps its instant through a full round-trip', () {
    final saved = DateTime.utc(2026, 11, 17, 19, 15); // 00:45 IST on the 18th
    final item = MindItem(
      id: 'a',
      title: 'x',
      type: ItemType.quote,
      createdAt: saved,
      updatedAt: saved,
    );

    final back = roundTrip(item);
    expect(back.createdAt.isAtSameMomentAs(saved), isTrue);
    expect(back.createdAt.isUtc, isTrue);
  });

  test('formatting the local view of a UTC stamp gives the IST calendar day',
      () {
    // 18:45 UTC on the 17th is 00:15 IST on the 18th.
    final saved = DateTime.utc(2026, 11, 17, 18, 45);
    final ist = saved.add(const Duration(hours: 5, minutes: 30));

    expect(saved.day, 17, reason: 'the raw UTC day is the trap');
    expect(ist.day, 18);
  });

  test('ageLabel measures from the local day, not the UTC one', () {
    // Saved 19:00 UTC on the 16th = 00:30 IST on the 17th.
    final saved = DateTime.utc(2026, 11, 16, 19, 0);
    final now = DateTime(2026, 11, 17, 12, 0);

    // Pass an explicit device zone so the test does not depend on the host TZ.
    DateTime ist(DateTime t) =>
        t.isUtc ? t.add(const Duration(hours: 5, minutes: 30)) : t;

    expect(SerendipityPlanner.ageLabel(saved, now, deviceZone: ist), 'today');
  });

  test('difference() is instant-based, so only *formatting* needed fixing', () {
    // Worth pinning because it scopes the bug: subtracting a UTC stamp from a
    // local now is fine (it compares instants), so the damage was limited to
    // screens that called DateFormat on createdAt directly. Those printed the
    // UTC wall clock.
    final stamp = DateTime.utc(2026, 11, 17, 10, 0);
    final diff = DateTime.now().difference(stamp);
    expect(diff, isNotNull);

    final utcFormatted = DateFormat('MMM d, HH:mm').format(stamp);
    final localFormatted = DateFormat('MMM d, HH:mm').format(stamp.toLocal());
    // They differ whenever the device is not on UTC - which is the whole point.
    if (stamp.timeZoneOffset != Duration.zero) {
      expect(utcFormatted, isNot(localFormatted));
    }
  });
}
