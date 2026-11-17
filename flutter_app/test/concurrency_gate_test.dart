import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/utils/concurrency_gate.dart';

void main() {
  test('never runs more than maxConcurrent tasks at once', () async {
    final gate = ConcurrencyGate(3);
    var running = 0;
    var peak = 0;

    Future<void> task() => gate.run(() async {
          running++;
          if (running > peak) peak = running;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
        });

    await Future.wait(List.generate(20, (_) => task()));

    expect(peak, lessThanOrEqualTo(3));
    expect(peak, greaterThan(1), reason: 'tasks should overlap, not serialise');
    expect(gate.active, 0);
    expect(gate.waiting, 0);
  });

  test('a failing task releases its slot and the error reaches the caller',
      () async {
    final gate = ConcurrencyGate(1);

    await expectLater(
      gate.run(() async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );

    // The only slot must be free again, otherwise every later repair hangs.
    await gate.run(() async => 1).timeout(const Duration(seconds: 1));
    expect(gate.active, 0);
  });

  test('waits in order instead of dropping work', () async {
    final gate = ConcurrencyGate(1);
    final order = <int>[];

    await Future.wait([
      for (var i = 0; i < 5; i++)
        gate.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          order.add(i);
        }),
    ]);

    expect(order, [0, 1, 2, 3, 4]);
  });

  test('the slot count goes back to zero after a long burst', () async {
    final gate = ConcurrencyGate(2);
    for (var i = 0; i < 30; i++) {
      await gate.run(() async {});
    }
    expect(gate.active, 0);
    expect(gate.waiting, 0);
  });

  test('a single slot still allows recursion-free nesting', () async {
    final gate = ConcurrencyGate(1);
    final result = await gate.run(() async {
      await Future<void>.delayed(Duration.zero);
      return 'ok';
    });
    expect(result, 'ok');
    expect(gate.active, 0);
  });
}
