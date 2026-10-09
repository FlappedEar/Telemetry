// Superseded or abandoned analysis jobs are stopped, not just ignored
// (audit F12). Synthetic recordings.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/latest_job.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../support/inline_runners.dart';
import '../support/temp_directory.dart';
import 'day_results_page_test.dart' show circuitVbo;

// Top level, so a real isolate can run it: spins until it is killed.
int _spin(CancellationCheck cancelled) {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 60)) {
    if (cancelled()) throw const OperationCancelled();
  }
  return -1;
}

int _quick(CancellationCheck cancelled) => 7;

/// Tasks a test holds open, to see which were stopped.
final class _Held<T> {
  final tasks = <_HeldTask<T>>[];

  BackgroundTask<T> call(CancellableJob<T> job) {
    final task = _HeldTask<T>(job);
    tasks.add(task);
    return task;
  }
}

final class _HeldTask<T> implements BackgroundTask<T> {
  _HeldTask(this.job);

  final CancellableJob<T> job;
  final _done = Completer<T>();
  bool cancelled = false;

  void finish() {
    if (_done.isCompleted) return;
    _done.complete(job(() => cancelled));
  }

  @override
  Future<T> get result => _done.future;

  @override
  void cancel() {
    cancelled = true;
    if (!_done.isCompleted) _done.completeError(const OperationCancelled());
  }
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('superseded'));
  tearDown(() => deleteTemporaryDirectory(directory));

  DayImportOutcome importDay() {
    final path = '${directory.path}/a.vbo';
    File(path).writeAsStringSync(circuitVbo([30, 28, 31]));
    return runDayImport((paths: [path], includeSubfolders: false));
  }

  group('LatestJob', () {
    test(
      'a newer job stops the one running; only the newer one answers',
      () async {
        final held = _Held<int>();
        final latest = LatestJob<int>(held.call);
        final first = latest.run((cancelled) => 1);
        final second = latest.run((cancelled) => 2);
        expect(held.tasks.first.cancelled, isTrue);
        held.tasks.last.finish();
        expect(await first, isNull);
        expect(await second, 2);
        expect(latest.running, isFalse);
      },
    );

    test('cancel stops the job and its answer is left out', () async {
      final held = _Held<int>();
      final latest = LatestJob<int>(held.call);
      final running = latest.run((cancelled) => 1);
      latest.cancel();
      expect(held.tasks.single.cancelled, isTrue);
      expect(await running, isNull);
    });

    test('a failing job throws what it failed with', () async {
      final latest = LatestJob<int>(
        (job) => MicrotaskTask<int>((cancelled) => throw StateError('boom')),
      );
      await expectLater(
        latest.run((cancelled) => 1),
        throwsA(isA<BackgroundTaskFailed>()),
      );
    });

    test(
      'a real isolate is killed when superseded, and the next job finishes',
      () async {
        final latest = LatestJob<int>((job) => isolateRunner<int>(job));
        final spinning = latest.run(_spin);
        // Let the isolate start.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final clock = Stopwatch()..start();
        final next = latest.run(_quick);
        expect(await spinning, isNull);
        expect(await next, 7);
        // Killed at once, not after the 60 s it would have spun.
        expect(clock.elapsed, lessThan(const Duration(seconds: 20)));
      },
    );
  });

  group('DayResultsController', () {
    late SpeedUnitSetting unit;
    setUp(() => unit = speedUnitSetting.value);
    tearDown(() => speedUnitSetting.value = unit);

    test('a calculation superseded by a change of unit is stopped, not just ignored', () async {
      final day = importDay();
      final best = _Held<DayTheoreticalBest>();
      final channels = _Held<DayChannelSummaries>();
      final review = _Held<DayProposalReview>();
      final controller = DayResultsController(
        runs: day.runs,
        analysis: day.analysis!,
        theoreticalBestRunner: best.call,
        channelSummariesRunner: channels.call,
        segmentReviewRunner: review.call,
      );
      addTearDown(controller.dispose);
      final requested = controller.requestTheoreticalBest();
      unawaited(controller.requestChannelSummaries());
      await Future<void>.delayed(Duration.zero);
      expect(best.tasks, hasLength(1));
      expect(channels.tasks, hasLength(1));

      // The assumed speed unit changes: both results are for the old unit.
      speedUnitSetting.value =
          speedUnitSetting.value == SpeedUnitSetting.milesPerHour
          ? SpeedUnitSetting.kilometresPerHour
          : SpeedUnitSetting.milesPerHour;
      expect(best.tasks.single.cancelled, isTrue);
      expect(channels.tasks.single.cancelled, isTrue);
      await requested;
      expect(controller.theoreticalBest, isNull);
      expect(controller.theoreticalBestLoading, isFalse);
      expect(controller.channelSummaries, isNull);

      // Its replacement can finish.
      final again = controller.requestTheoreticalBest();
      await Future<void>.delayed(Duration.zero);
      expect(best.tasks, hasLength(2));
      best.tasks.last.finish();
      await again;
      expect(controller.theoreticalBest, isNotNull);
    });

    test('closing the day stops the calculations running', () async {
      final day = importDay();
      final best = _Held<DayTheoreticalBest>();
      final channels = _Held<DayChannelSummaries>();
      final controller = DayResultsController(
        runs: day.runs,
        analysis: day.analysis!,
        theoreticalBestRunner: best.call,
        channelSummariesRunner: channels.call,
      );
      final requested = controller.requestTheoreticalBest();
      unawaited(controller.requestChannelSummaries());
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      expect(best.tasks.single.cancelled, isTrue);
      expect(channels.tasks.single.cancelled, isTrue);
      // Neither a result nor an error reaches the closed day.
      await requested;
    });
  });
}
