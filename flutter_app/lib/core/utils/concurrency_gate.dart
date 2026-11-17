import 'dart:async';
import 'dart:collection';

/// Runs at most [maxConcurrent] tasks at a time, queueing the rest in order.
///
/// The thumbnail repair pass needs this: a card that fails to load asks for a
/// fresh URL from its error builder, and a masonry column of stale Instagram
/// links fails all at once. Without a cap a single scroll opens dozens of
/// sockets and the repair traffic competes with the image loads the user is
/// actually waiting for.
///
/// Kept deliberately small and dependency-free so it can be unit tested
/// without any network.
class ConcurrencyGate {
  ConcurrencyGate(this.maxConcurrent)
      : assert(maxConcurrent > 0, 'maxConcurrent must be positive');

  final int maxConcurrent;

  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Tasks running right now.
  int get active => _active;

  /// Tasks parked waiting for a slot.
  int get waiting => _waiters.length;

  /// Runs [task] once a slot is free. Errors propagate to the caller and the
  /// slot is released either way.
  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // Hand the slot straight to the next waiter: _active stays the same, so
      // a burst of completions cannot momentarily exceed the cap.
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
    if (_active < 0) _active = 0;
  }
}
