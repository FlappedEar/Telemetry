// The background work a day owns on its runs' recordings (FET-209): slots,
// generations, superseded work and what closing the day stops. No
// recordings: the jobs are held fakes.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/fusion_jobs.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// A fusion task that finishes when the test says so.
final class _HeldTask implements FusionTask {
  _HeldTask(this.job, [this.log]);

  final FusionJob job;
  final List<String>? log;
  final _done = Completer<RunFusion?>();
  bool cancelled = false;

  void finish() {
    if (!_done.isCompleted) _done.complete(job(() => cancelled));
  }

  @override
  Future<RunFusion?> get result => _done.future;

  @override
  void cancel() {
    log?.add('fusion stopped');
    cancelled = true;
    if (!_done.isCompleted) _done.completeError(const OperationCancelled());
  }
}

/// A background task that finishes when the test says so.
final class _HeldBackground implements BackgroundTask<int> {
  _HeldBackground([this.log]);

  final List<String>? log;
  final _done = Completer<int>();
  bool cancelled = false;

  void finish(int value) {
    if (!_done.isCompleted) _done.complete(value);
  }

  @override
  Future<int> get result => _done.future;

  @override
  void cancel() {
    log?.add('reading stopped');
    cancelled = true;
    if (!_done.isCompleted) _done.completeError(const OperationCancelled());
  }
}

final class _Runner {
  _Runner([this.log]);

  final List<String>? log;
  final tasks = <_HeldTask>[];

  FusionTask call(FusionJob job) {
    final task = _HeldTask(job, log);
    tasks.add(task);
    return task;
  }
}

/// A job for the queue that runs until [release] completes.
Future<void> Function() _held(
  List<String> log,
  String name,
  Completer<void> release,
) => () async {
  log.add('start $name');
  await release.future;
  log.add('end $name');
};

void main() {
  test('takes its slot count when made, the default unless given', () {
    expect(FusionJobs.defaultSlots, inInclusiveRange(1, 3));
    expect(FusionJobs(_Runner().call).slots, FusionJobs.defaultSlots);
    expect(FusionJobs(_Runner().call, slots: 1).slots, 1);
    expect(FusionJobs(_Runner().call, slots: 2).slots, 2);
  });

  test('runs at most its slots at once, in the order asked', () async {
    final jobs = FusionJobs(_Runner().call, slots: 2);
    addTearDown(jobs.dispose);
    final log = <String>[];
    final releases = [for (var i = 0; i < 3; ++i) Completer<void>()];
    for (var i = 0; i < 3; ++i) {
      jobs.enqueue(_held(log, '$i', releases[i]));
    }
    await pumpEventQueue();
    expect(log, ['start 0', 'start 1']);
    expect(jobs.running, 2);
    releases[1].complete();
    await pumpEventQueue();
    expect(log, ['start 0', 'start 1', 'end 1', 'start 2']);
    releases[0].complete();
    releases[2].complete();
    await pumpEventQueue();
    expect(jobs.running, 0);
  });

  test(
    'work in a slot waits behind queued jobs and returns its value',
    () async {
      final jobs = FusionJobs(_Runner().call, slots: 1);
      addTearDown(jobs.dispose);
      final log = <String>[];
      final release = Completer<void>();
      jobs.enqueue(_held(log, 'first', release));
      final value = jobs.inSlot(() async {
        log.add('slot');
        return 7;
      });
      await pumpEventQueue();
      expect(log, ['start first']);
      release.complete();
      expect(await value, 7);
      expect(log, ['start first', 'end first', 'slot']);
    },
  );

  test('a failure in a slot reaches the caller and frees the slot', () async {
    final jobs = FusionJobs(_Runner().call, slots: 1);
    addTearDown(jobs.dispose);
    await expectLater(
      jobs.inSlot<int>(() async => throw StateError('broken')),
      throwsStateError,
    );
    expect(await jobs.inSlot(() async => 1), 1);
  });

  test('a newer request for a run stops the one running for it', () async {
    final runner = _Runner();
    final jobs = FusionJobs(runner.call);
    addTearDown(jobs.dispose);
    final first = jobs.runFusion('run1', (_) => null);
    final other = jobs.runFusion('run2', (_) => null);
    final second = jobs.runFusion('run1', (_) => null);
    expect(runner.tasks[0].cancelled, isTrue);
    expect(runner.tasks[1].cancelled, isFalse, reason: 'another run');
    await expectLater(first, throwsA(isA<OperationCancelled>()));
    runner.tasks[2].finish();
    runner.tasks[1].finish();
    expect(await second, isNull);
    expect(await other, isNull);
  });

  test('stop ends a run\'s fusion and reading work, not others\'', () async {
    final runner = _Runner();
    final jobs = FusionJobs(runner.call);
    addTearDown(jobs.dispose);
    final fusion = jobs.runFusion('run1', (_) => null);
    final reading = _HeldBackground();
    final read = jobs.runBackground('run1', reading);
    final otherReading = _HeldBackground();
    final otherRead = jobs.runBackground('run2', otherReading);
    jobs.cancelFusion('run1');
    expect(runner.tasks.single.cancelled, isTrue);
    expect(reading.cancelled, isFalse, reason: 'only the fusion work');
    jobs.stop('run1');
    expect(reading.cancelled, isTrue);
    expect(otherReading.cancelled, isFalse);
    await expectLater(fusion, throwsA(isA<OperationCancelled>()));
    await expectLater(read, throwsA(isA<OperationCancelled>()));
    otherReading.finish(3);
    expect(await otherRead, 3);
  });

  test('generations are per run: only the latest is current', () {
    final jobs = FusionJobs(_Runner().call);
    addTearDown(jobs.dispose);
    final a1 = jobs.nextGeneration('a');
    final b1 = jobs.nextGeneration('b');
    expect(jobs.current('a', a1), isTrue);
    final a2 = jobs.nextGeneration('a');
    expect(jobs.current('a', a1), isFalse);
    expect(jobs.current('a', a2), isTrue);
    expect(jobs.current('b', b1), isTrue, reason: 'another run');
    expect(jobs.current('c', 1), isFalse, reason: 'never started');
  });

  test('two days own their work apart', () async {
    final runnerA = _Runner(), runnerB = _Runner();
    final dayA = FusionJobs(runnerA.call, slots: 1);
    final dayB = FusionJobs(runnerB.call, slots: 1);
    addTearDown(dayB.dispose);
    final log = <String>[];
    final release = Completer<void>();
    dayA.enqueue(_held(log, 'A', release));
    dayB.enqueue(_held(log, 'B', Completer<void>()..complete()));
    final generation = dayB.nextGeneration('run1');
    dayA.nextGeneration('run1');
    unawaited(dayB.runFusion('run1', (_) => null).then((_) {}));
    unawaited(
      dayA.runFusion('run1', (_) => null).then((_) {}, onError: (_) {}),
    );
    await pumpEventQueue();
    expect(
      log,
      containsAll(['start A', 'start B', 'end B']),
      reason: 'a slot held by one day does not hold up the other',
    );
    expect(dayB.current('run1', generation), isTrue);
    dayA.dispose();
    expect(runnerA.tasks.single.cancelled, isTrue);
    expect(
      runnerB.tasks.single.cancelled,
      isFalse,
      reason: 'closing one day stops none of the other\'s work',
    );
    runnerB.tasks.single.finish();
    release.complete();
  });

  test('dispose drops queued work, fails slot waiters and stops running '
      'work, fusion first', () async {
    final stops = <String>[];
    final runner = _Runner(stops);
    final jobs = FusionJobs(runner.call, slots: 1);
    final log = <String>[];
    final release = Completer<void>();
    jobs.enqueue(_held(log, 'running', release));
    jobs.enqueue(_held(log, 'queued', Completer<void>()..complete()));
    final waiting = jobs.inSlot(() async => log.add('slot'));
    final fusion = jobs.runFusion('run1', (_) => null);
    final reading = _HeldBackground(stops);
    final read = jobs.runBackground('run1', reading);
    await pumpEventQueue();
    expect(log, ['start running']);

    jobs.dispose();
    expect(jobs.disposed, isTrue);
    // Stopped at once, the fusion work before the reading work.
    expect(stops, ['fusion stopped', 'reading stopped']);
    await expectLater(waiting, throwsA(isA<OperationCancelled>()));
    await expectLater(fusion, throwsA(isA<OperationCancelled>()));
    await expectLater(read, throwsA(isA<OperationCancelled>()));

    // The job already running finishes; nothing queued starts after it.
    release.complete();
    await pumpEventQueue();
    expect(log, ['start running', 'end running']);
    expect(jobs.running, 0);
  });

  test('after dispose nothing new starts', () async {
    final runner = _Runner();
    final jobs = FusionJobs(runner.call)..dispose();
    final log = <String>[];
    jobs.enqueue(_held(log, 'late', Completer<void>()..complete()));
    await expectLater(
      jobs.inSlot(() async => log.add('slot')),
      throwsA(isA<OperationCancelled>()),
    );
    await expectLater(
      jobs.runFusion('run1', (_) => null),
      throwsA(isA<OperationCancelled>()),
    );
    final reading = _HeldBackground();
    await expectLater(
      jobs.runBackground('run1', reading),
      throwsA(isA<OperationCancelled>()),
    );
    expect(reading.cancelled, isTrue);
    await pumpEventQueue();
    expect(log, isEmpty);
    expect(runner.tasks, isEmpty);
    jobs.dispose();
  });
}
