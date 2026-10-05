import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/coach_job.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// A task whose job runs when [release] completes, stopped at its check.
final class _HeldTask implements BackgroundTask<DayCoach> {
  _HeldTask(CoachJob job, Future<void> release) {
    result = release.then((_) => job(() => cancelled));
  }

  bool cancelled = false;

  @override
  late final Future<DayCoach> result;

  @override
  void cancel() => cancelled = true;
}

DayCoach _job(CancellationCheck cancelled) {
  throwIfCancelled(cancelled);
  return DayCoach(runId: 'run1', reason: CoachReason.noSegments);
}

void main() {
  test(
    'a newer job stops the one running, whose outcome is left out',
    () async {
      final tasks = <_HeldTask>[];
      final release = Completer<void>();
      final jobs = LatestCoachJob((job) {
        final task = _HeldTask(job, release.future);
        tasks.add(task);
        return task;
      });
      final first = jobs.run(_job);
      final second = jobs.run(_job);
      expect(tasks.first.cancelled, isTrue);
      expect(tasks.last.cancelled, isFalse);
      release.complete();
      expect(await first, isNull);
      final outcome = await second;
      expect(outcome?.coach?.runId, 'run1');
      expect(outcome?.error, isEmpty);
    },
  );

  test('a cancelled job gives no outcome', () async {
    final release = Completer<void>();
    late _HeldTask task;
    final jobs = LatestCoachJob((job) => task = _HeldTask(job, release.future));
    final running = jobs.run(_job);
    jobs.cancel();
    expect(task.cancelled, isTrue);
    release.complete();
    expect(await running, isNull);
  });

  test('a failing job says why', () async {
    final jobs = LatestCoachJob(defaultCoachRunner);
    final outcome = await jobs.run((_) => throw StateError('broken'));
    expect(outcome?.coach, isNull);
    expect(outcome?.error, 'Bad state: broken');
  });

  test('a runner that cannot start says why', () async {
    final jobs = LatestCoachJob((_) => throw StateError('no isolate'));
    final outcome = await jobs.run(_job);
    expect(outcome?.error, 'Bad state: no isolate');
  });
}
