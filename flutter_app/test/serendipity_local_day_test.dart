import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/notifications/serendipity_planner.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// Items are stored as UTC instants, so their `createdAt` calendar date is the
/// UTC one. For a device east of UTC (India is +5:30) an evening save is
/// "yesterday" in UTC, and the planner used to derive the spaced-repetition
/// due date from that date — firing every reminder a day early.
///
/// The planner reads stored instants through an injectable "device zone", so
/// these tests pin IST (+5:30) explicitly and give the same answer on any CI
/// runner, whatever its TZ.
void main() {
  // 2026-11-17 20:00Z is 2026-11-18 01:30 in India: the save belongs to the
  // 18th, not the 17th.
  DateTime ist(DateTime utc) => utc.add(const Duration(hours: 5, minutes: 30));

  MindItem savedAt(DateTime utc) => MindItem(
        id: 'a',
        title: 'Late night save',
        type: ItemType.webArticle,
        createdAt: utc,
        updatedAt: utc,
      );

  DateTime firstSpark(List<PlannedReminder> plan) =>
      plan.firstWhere((p) => p.kind == ReminderKind.spark).fireAt;

  test('a save just after local midnight is not treated as the previous day',
      () {
    // 2026-11-18 01:30 IST == 2026-11-17 20:00Z. Day 3 after the *local* save
    // date is 21 Nov, not 20 Nov.
    final item = savedAt(DateTime.utc(2026, 11, 17, 20, 0));
    final plan = SerendipityPlanner.plan(
      items: [item],
      state: const SerendipityEngineState(),
      now: DateTime(2026, 11, 18, 10),
      horizon: 14,
      deviceZone: ist,
    );

    expect(plan, isNotEmpty);
    expect(firstSpark(plan).day, 21,
        reason: 'day-3 spark must count calendar days in the device timezone');
  });

  test('age labels count local calendar days too', () {
    // Saved 01:30 IST on the 18th; asked two local days later.
    final createdAt = DateTime.utc(2026, 11, 17, 20, 0);
    expect(
      SerendipityPlanner.ageLabel(
        createdAt,
        DateTime(2026, 11, 20, 9),
        deviceZone: ist,
      ),
      '2 days ago',
    );
  });

  test('stages still advance 3 / 14 / 45 / 90 days from the local save date',
      () {
    final item =
        savedAt(DateTime.utc(2026, 11, 17, 20, 0)); // 18 Nov, 01:30 IST
    final plan = SerendipityPlanner.plan(
      items: [item],
      state: const SerendipityEngineState(
          settings: ReminderSettings(weeklyDigest: false)),
      now: DateTime(2026, 11, 18, 10),
      horizon: 120,
      deviceZone: ist,
    );
    final sparks = plan.where((p) => p.kind == ReminderKind.spark).toList();
    expect(sparks.map((p) => p.stage).toList(), [0, 1, 2, 3]);
    expect(sparks.first.fireAt.day, 21); // +3 days
    expect(sparks[1].fireAt.month, 12); // +14 days
    expect(sparks.map((p) => p.fireAt.hour).toSet(), {20},
        reason: 'every spark keeps the user’s chosen 20:xx slot');
  });
}
