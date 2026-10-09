import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'background_task.dart';

/// Work for a [LatestJob]: it stops at [cancelled] with [OperationCancelled].
typedef CancellableJob<T> = T Function(CancellationCheck cancelled);

/// Starts a [CancellableJob] in the background; replaced in widget tests.
typedef CancellableRunner<T> = BackgroundTask<T> Function(
  CancellableJob<T> job,
);

/// The job body an isolate runs ([runInBackground] needs a top-level or
/// static function); instantiated for each result type.
T runCancellable<T>(CancellableJob<T> job, CancellationCheck cancelled) =>
    job(cancelled);

/// In a background isolate, stopped at once when cancelled; directly under
/// `flutter test`, as a microtask (which a widget test's fake clock runs
/// without a timer), stopped at its next cancellation check.
BackgroundTask<T> backgroundRunner<T>(CancellableJob<T> job) =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? MicrotaskTask<T>(job)
    : runInBackground<CancellableJob<T>, T>(runCancellable<T>, job);

/// A job run as a microtask; failures come back as in [runInBackground].
final class MicrotaskTask<T> implements BackgroundTask<T> {
  MicrotaskTask(CancellableJob<T> job) {
    result = Future.microtask(() {
      if (_cancelled) throw const OperationCancelled();
      try {
        return job(() => _cancelled);
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(backgroundFailure(error), stack);
      }
    });
  }

  bool _cancelled = false;

  @override
  late final Future<T> result;

  @override
  void cancel() => _cancelled = true;
}

/// One background job at a time for a result that is only worth having for
/// the latest request: starting another job, or [cancel], stops the one
/// running (its isolate is killed), and its outcome is left out.
final class LatestJob<T> {
  LatestJob(this._runner);

  final CancellableRunner<T> _runner;
  BackgroundTask<T>? _task;

  /// Whether a job is running.
  bool get running => _task != null;

  /// Runs [job]: its result, or null when it was stopped for a newer job
  /// or by [cancel]. A job that fails throws what it failed with.
  Future<T?> run(CancellableJob<T> job) async {
    cancel();
    final task = _runner(job);
    _task = task;
    try {
      final value = await task.result;
      return identical(_task, task) ? value : null;
    } on OperationCancelled {
      return null;
    } on Object {
      // A job stopped for a newer one fails with nothing worth showing.
      if (!identical(_task, task)) return null;
      rethrow;
    } finally {
      if (identical(_task, task)) _task = null;
    }
  }

  /// Stops the running job, if any.
  void cancel() {
    _task?.cancel();
    _task = null;
  }
}
