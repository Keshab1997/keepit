import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/notifications/serendipity_planner.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// Regression guard for a save/reminder crash: truncation used to slice the raw
/// UTF-16 string, so an emoji's surrogate pair could be cut in half and Dart
/// threw `RangeError: Invalid code unit` mid-save.
void main() {
  // 40 family emoji (each is multiple code units + a ZWJ sequence) and a
  // Devanagari-looking run: both are common in captions people save.
  final emojiTitle = '👨‍👩‍👧‍👦' * 40;
  final indicTitle = 'নমস্কার ' * 30;

  MindItem itemWith(String title) {
    final created = DateTime.utc(2026, 9, 1);
    return MindItem(
      id: 'e',
      title: title,
      type: ItemType.instagramReel,
      createdAt: created,
      updatedAt: created,
    );
  }

  List<PlannedReminder> planFor(MindItem item) {
    // Day 3 after the save, so the first spark stage is due.
    final now = DateTime(2026, 9, 4, 9);
    return SerendipityPlanner.plan(
      items: [item],
      state: const SerendipityEngineState(),
      now: now,
      horizon: 3,
    );
  }

  test('planning never throws on emoji-only titles', () {
    expect(() => planFor(itemWith(emojiTitle)), returnsNormally);
  });

  test('emoji titles are truncated by grapheme, never mid-code-unit', () {
    final reminders = planFor(itemWith(emojiTitle));
    expect(reminders, isNotEmpty);
    for (final r in reminders) {
      expect(r.title, isNotEmpty);
      // Never a lone high surrogate — that is what substring() produced.
      expect(r.title.contains(RegExp(r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])')),
          isFalse);
      // Far shorter than the 40-emoji source, i.e. truncation did happen.
      expect(r.title.length, lessThan(emojiTitle.length));
      // The long emoji run is what the body embeds, so check it there too.
      expect(r.body, isNotEmpty);
      expect(r.body.contains(RegExp(r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])')),
          isFalse);
    }
  });

  test('multi-code-unit titles survive planning and are shortened, not lost',
      () {
    final reminders = planFor(itemWith(indicTitle));
    expect(reminders, isNotEmpty);
    expect(reminders.first.title, isNotEmpty);
    expect(reminders.first.title.length, lessThan(indicTitle.length));
  });
}
