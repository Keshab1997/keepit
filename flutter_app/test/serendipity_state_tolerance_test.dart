import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/notifications/serendipity_planner.dart';

/// `loadState()` swallows a parse error by returning a *fresh* state, and a
/// fresh state has an empty `lastStage`. That does not merely lose history: it
/// makes every item look never-reminded, so the same spark is scheduled again
/// for things the user has already seen - the one bug this engine exists to
/// prevent. A single bad entry must therefore cost that entry only.
void main() {
  /// Parsed through real JSON, exactly like `SerendipityStore.loadState`, so
  /// these fixtures cannot lie about the runtime types.
  Map<String, dynamic> decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  String good(
          {String lastStage = '"item-a": 2, "item-b": 0',
          String snoozes = '"item-a": "2026-11-20T15:00:00.000Z"',
          String plan = ''
              '{"id": 1001, "kind": "spark", "fireAt": "2026-11-18T15:00:00.000Z",'
              ' "itemId": "item-a", "title": "t", "body": "b"}'}) =>
      '{"version": 1,'
      ' "settings": {"enabled": true, "hour": 20, "minute": 30,'
      ' "weeklyDigest": true},'
      ' "lastStage": {$lastStage},'
      ' "snoozes": {$snoozes},'
      ' "plan": [$plan]}';

  test('a clean state round-trips', () {
    final state = SerendipityEngineState.fromJson(decode(good()));
    expect(state.lastStage, {'item-a': 2, 'item-b': 0});
    expect(state.snoozes.length, 1);
    expect(state.plan.length, 1);
    expect(state.settings.hour, 20);
    expect(state.plan.first.id, 1001);
  });

  test('one unreadable stage does not erase the other stages', () {
    final json = decode(good(
      lastStage: '"item-a": 2, "item-b": 0, "item-c": {"nested": "junk"}',
    ));

    final state = SerendipityEngineState.fromJson(json);
    expect(
      state.lastStage,
      {'item-a': 2, 'item-b': 0},
      reason: 'losing the whole map re-reminds everything',
    );
  });

  test('a numeric stage stored as a string still counts', () {
    final state = SerendipityEngineState.fromJson(
      decode(good(lastStage: '"item-a": 2, "item-d": "3"')),
    );
    expect(state.lastStage['item-d'], 3);
  });

  test('one bad snooze does not erase the others', () {
    final state = SerendipityEngineState.fromJson(
      decode(good(
        snoozes: '"item-a": "2026-11-20T15:00:00.000Z",'
            ' "item-z": "not-a-date", "item-y": 42',
      )),
    );
    expect(state.snoozes.keys, ['item-a']);
    expect(
      state.snoozes['item-a']!.isAtSameMomentAs(
        DateTime.parse('2026-11-20T15:00:00.000Z'),
      ),
      isTrue,
    );
  });

  test('one bad plan entry does not erase the rest', () {
    final state = SerendipityEngineState.fromJson(
      decode(good(
        plan: '{"id": 1001, "kind": "spark",'
            ' "fireAt": "2026-11-18T15:00:00.000Z", "title": "t", "body": "b"},'
            ' {"kind": "spark"},'
            ' {"id": 1002, "kind": "spark", "fireAt": "nonsense"},'
            ' {"id": 1003, "kind": "digest",'
            ' "fireAt": "2026-11-19T15:00:00.000Z", "title": "ok", "body": "ok"}',
      )),
    );

    expect(state.plan.map((p) => p.id), [1001, 1003]);
  });

  test('settings of the wrong type fall back instead of throwing', () {
    final json = decode(good());
    json['settings'] = jsonDecode(
      '{"enabled": "yes", "hour": "eight", "minute": 30}',
    );

    final state = SerendipityEngineState.fromJson(json);
    expect(state.settings.enabled, isTrue, reason: 'default, not "yes"');
    expect(state.settings.hour, 20, reason: '"eight" is not an hour');
    expect(state.settings.minute, 30);
  });

  test('a completely empty object still produces a usable state', () {
    final state = SerendipityEngineState.fromJson({});
    expect(state.lastStage, isEmpty);
    expect(state.plan, isEmpty);
    expect(state.settings.enabled, isTrue);
  });
}
