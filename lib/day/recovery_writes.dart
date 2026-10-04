import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics/app_errors.dart';
import 'recovery_store.dart';

/// One day's recovery writes: the snapshot written a [delay] after changes
/// settle, and the writes and clears queued behind other days' (see
/// [queueRecovery]). Held by `DayResultsController`.
final class RecoveryWrites {
  RecoveryWrites(this.delay);

  /// How long changes wait before the snapshot is written.
  final Duration delay;

  Timer? _timer;
  Future<void> _last = Future.value();
  int _unfinished = 0;

  /// Whether a write is scheduled, queued or not finished.
  bool get waiting => (_timer?.isActive ?? false) || _unfinished > 0;

  /// Calls [write] after [delay], replacing a write already scheduled.
  void schedule(void Function() write) {
    _timer?.cancel();
    _timer = Timer(delay, write);
  }

  /// Drops the scheduled write.
  void cancel() => _timer?.cancel();

  /// Queues [operation]; a failure is reported, since the day is not
  /// protected until a write succeeds.
  void enqueue(Future<void>? Function() operation) {
    ++_unfinished;
    _last = queueRecovery(() async {
      try {
        await operation();
      } on Object catch (error, stack) {
        debugPrint('Recovery snapshot not updated: $error');
        reportError(error, stack, context: 'Recovery snapshot not updated');
      } finally {
        --_unfinished;
      }
    });
  }

  /// Calls [write] now when one is scheduled, and finishes when this day's
  /// queued writes have.
  Future<void> flush(void Function() write) {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      write();
    }
    return _last;
  }
}
