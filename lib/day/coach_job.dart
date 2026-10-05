import 'dart:async';

import 'package:telemetry_core/telemetry_core.dart';

import 'background_task.dart';

/// The coach's plan for the day's latest session; stops at [cancelled]
/// with [OperationCancelled].
typedef CoachJob = DayCoach Function(CancellationCheck cancelled);

/// Starts a [CoachJob]; replaced in widget tests like the theoretical
/// best's runner.
typedef CoachRunner = BackgroundTask<DayCoach> Function(CoachJob job);

/// In a background isolate, stopped at once when cancelled; directly under
/// `flutter test`, stopped at its next cancellation check.
BackgroundTask<DayCoach> defaultCoachRunner(CoachJob job) =>
    backgroundRunsInline
    ? _InlineCoachTask(job)
    : runInBackground(_runCoachJob, job);

DayCoach _runCoachJob(CoachJob job, CancellationCheck cancelled) =>
    job(cancelled);

// As a microtask, which a widget test's fake clock runs without a timer;
// failures come back as in [runInBackground].
final class _InlineCoachTask implements BackgroundTask<DayCoach> {
  _InlineCoachTask(CoachJob job) {
    result = Future.microtask(() {
      try {
        return job(() => _cancelled);
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(backgroundFailure(error), stack);
      }
    });
  }

  bool _cancelled = false;

  @override
  late final Future<DayCoach> result;

  @override
  void cancel() => _cancelled = true;
}

/// What a [LatestCoachJob] gave: the plan, or why it failed.
typedef CoachOutcome = ({DayCoach? coach, String error});

/// The coach's job for the day as it stands: starting another, or
/// [cancel], stops the one running, whose outcome is then left out.
final class LatestCoachJob {
  LatestCoachJob(this._runner);

  final CoachRunner _runner;
  BackgroundTask<DayCoach>? _task;

  /// Runs [job]: its outcome, or null when it was stopped for a newer job
  /// or by [cancel].
  Future<CoachOutcome?> run(CoachJob job) async {
    cancel();
    final BackgroundTask<DayCoach> task;
    try {
      task = _runner(job);
    } on Object catch (failure) {
      return (coach: null, error: '$failure');
    }
    _task = task;
    CoachOutcome outcome;
    try {
      outcome = (coach: await task.result, error: '');
    } on Object catch (failure) {
      outcome = (coach: null, error: '$failure');
    }
    if (!identical(_task, task)) return null;
    _task = null;
    return outcome;
  }

  /// Stops the running job, if any.
  void cancel() {
    _task?.cancel();
    _task = null;
  }
}
