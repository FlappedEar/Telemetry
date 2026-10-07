import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max, min;

import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'background_task.dart';

/// Aligns and fuses a run's alternative recording, or fuses it again with
/// a changed rule; stops at [cancelled] with [OperationCancelled].
typedef FusionJob = RunFusion? Function(CancellationCheck cancelled);

/// A running [FusionJob]. [result] completes with [OperationCancelled]
/// after [cancel].
abstract interface class FusionTask {
  Future<RunFusion?> get result;
  void cancel();
}

/// Starts a [FusionJob]. Replaced in widget tests, which run it on the
/// test's own thread.
typedef FusionRunner = FusionTask Function(FusionJob job);

/// In a background isolate, stopped at once when cancelled; directly under
/// `flutter test`, stopped at its next cancellation check.
FusionTask defaultFusionRunner(FusionJob job) =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? _InlineFusionTask(job)
    : isolateFusionRunner(job);

/// Runs [job] in its own isolate, killed when cancelled.
FusionTask isolateFusionRunner(FusionJob job) => _IsolateFusionTask(job);

final class _InlineFusionTask implements FusionTask {
  _InlineFusionTask(FusionJob job) {
    result = Future.microtask(() => job(() => _cancelled));
  }

  bool _cancelled = false;

  @override
  late final Future<RunFusion?> result;

  @override
  void cancel() => _cancelled = true;
}

/// What a fusion isolate sends back.
final class _FusionResult {
  const _FusionResult(this.fusion);
  final RunFusion? fusion;
}

final class _IsolateFusionTask implements FusionTask {
  _IsolateFusionTask(FusionJob job) {
    _port.listen((message) {
      switch (message) {
        case _FusionResult(:final fusion):
          _finish(() => _done.complete(fusion));
        case [Object? error, Object? stack]:
          _finish(
            () => _done.completeError(
              error ?? 'Not combined.',
              stack is String ? StackTrace.fromString(stack) : null,
            ),
          );
        default:
          _finish(
            () => _done.completeError(
              StateError('The alignment stopped unexpectedly.'),
            ),
          );
      }
    });
    Isolate.spawn(
      _entry,
      (_port.sendPort, job),
      onError: _port.sendPort,
      onExit: _port.sendPort,
      debugName: 'fusion',
    ).then(
      (isolate) {
        _isolate = isolate;
        if (_cancelled) isolate.kill(priority: Isolate.immediate);
      },
      onError: (Object error, StackTrace stack) =>
          _finish(() => _done.completeError(error, stack)),
    );
  }

  final _port = ReceivePort();
  final _done = Completer<RunFusion?>();
  Isolate? _isolate;
  bool _cancelled = false;

  @override
  Future<RunFusion?> get result => _done.future;

  @override
  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _finish(() => _done.completeError(const OperationCancelled()));
  }

  void _finish(void Function() complete) {
    if (_done.isCompleted) return;
    _port.close();
    complete();
  }

  static void _entry((SendPort, FusionJob) message) {
    final (port, job) = message;
    Isolate.exit(port, _FusionResult(job(() => false)));
  }
}

/// The background work on one day's runs' recordings (aligning and fusing
/// an alternative recording, changing a fusion rule, checking a clock,
/// reading a new primary), owned by that day (FET-209). It holds what the
/// day's controller must not hold itself: each run's generation, the queue
/// of work waiting for one of [slots], and the work running for each run,
/// which a newer request for the run supersedes and [dispose] stops.
final class FusionJobs {
  FusionJobs(this._runner, {int? slots}) : slots = slots ?? defaultSlots;

  /// How many runs a day aligns at once unless told otherwise: each
  /// isolate holds both recordings.
  static final int defaultSlots = kIsWeb
      ? 1
      : max(1, min(3, Platform.numberOfProcessors - 1));

  final FusionRunner _runner;

  /// How many jobs of this day run at once.
  final int slots;

  final Map<String, int> _generations = {};
  final Map<String, FusionTask> _fusionTasks = {};
  final Map<String, BackgroundTask<Object?>> _backgroundTasks = {};
  final List<Future<void> Function()> _queue = [];
  int _running = 0;

  // Work waiting for a slot ([inSlot]); failed with [OperationCancelled]
  // on [dispose].
  final Set<Completer<Object?>> _slotWaiters = {};
  bool _disposed = false;

  /// Whether [dispose] has run.
  bool get disposed => _disposed;

  /// How many jobs run now; at most [slots].
  @visibleForTesting
  int get running => _running;

  /// A new generation for [runId]: whatever was started under an earlier
  /// one is no longer [current].
  int nextGeneration(String runId) =>
      _generations[runId] = (_generations[runId] ?? 0) + 1;

  /// Whether [generation] is still [runId]'s latest.
  bool current(String runId, int generation) =>
      _generations[runId] == generation;

  /// Runs [job] for [runId] with the day's [FusionRunner]; the work running
  /// for the run before is stopped, as is this one by a newer request,
  /// [cancelFusion] or [dispose] ([OperationCancelled]).
  Future<RunFusion?> runFusion(String runId, FusionJob job) async {
    if (_disposed) throw const OperationCancelled();
    _fusionTasks.remove(runId)?.cancel();
    final task = _runner(job);
    _fusionTasks[runId] = task;
    try {
      return await task.result;
    } finally {
      if (identical(_fusionTasks[runId], task)) _fusionTasks.remove(runId);
    }
  }

  /// Waits for [task], the work reading [runId]'s recordings beside its
  /// fusion work, which [stop] or [dispose] stops.
  Future<T> runBackground<T>(String runId, BackgroundTask<T> task) async {
    if (_disposed) {
      task.cancel();
      return task.result;
    }
    _backgroundTasks[runId] = task;
    try {
      return await task.result;
    } finally {
      if (identical(_backgroundTasks[runId], task)) {
        _backgroundTasks.remove(runId);
      }
    }
  }

  /// Stops [runId]'s running [runFusion] job, if any.
  void cancelFusion(String runId) => _fusionTasks.remove(runId)?.cancel();

  /// Stops all of [runId]'s running work.
  void stop(String runId) {
    cancelFusion(runId);
    _backgroundTasks.remove(runId)?.cancel();
  }

  /// Runs [job] once one of the [slots] is free, in the order asked. Not
  /// started after [dispose].
  void enqueue(Future<void> Function() job) {
    if (_disposed) return;
    _queue.add(job);
    _runQueued();
  }

  /// Runs [work] once one of the [slots] is free, as [enqueue]; fails with
  /// [OperationCancelled] when the day closes first.
  Future<T> inSlot<T>(Future<T> Function() work) {
    if (_disposed) return Future.error(const OperationCancelled());
    final done = Completer<Object?>();
    _slotWaiters.add(done);
    _queue.add(() async {
      if (!_slotWaiters.remove(done)) return;
      try {
        done.complete(await work());
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    _runQueued();
    return done.future.then((value) => value as T);
  }

  void _runQueued() {
    while (_running < slots && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      ++_running;
      unawaited(
        job().whenComplete(() {
          --_running;
          _runQueued();
        }),
      );
    }
  }

  /// The day closed: work not started is dropped, work waiting for a slot
  /// fails with [OperationCancelled] and running work is stopped.
  void dispose() {
    _disposed = true;
    _queue.clear();
    for (final waiter in _slotWaiters) {
      waiter.completeError(const OperationCancelled());
    }
    _slotWaiters.clear();
    for (final task in _fusionTasks.values) {
      task.cancel();
    }
    _fusionTasks.clear();
    for (final task in _backgroundTasks.values) {
      task.cancel();
    }
    _backgroundTasks.clear();
  }
}
