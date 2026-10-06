// The track day rehearsed on real recordings (FET-47): the day's first VBO
// opens a day, then each later VBO is added one at a time, as at the track,
// and the coach's plan, its timing and the process memory are printed after
// each. The first file is imported on the test's own thread, the others
// through the day's appender as at the track, so the first "add" is not
// comparable; memory is this machine's. Set FLAPPEDEAR_REAL_DAY to a folder of one day's VBO files; nothing
// from the recordings is copied or kept. Skipped otherwise.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../support/coach_runner.dart';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test(
    'adds each session in turn and coaches the next',
    () async {
      final files =
          Directory(folder)
              .listSync()
              .whereType<File>()
              .map((file) => file.path)
              .where((path) => path.toLowerCase().endsWith('.vbo'))
              .toList()
            ..sort();
      expect(files.length, greaterThan(1));
      final clock = Stopwatch()..start();
      final first = runDayImport((
        paths: [files.first],
        includeSubfolders: false,
      ));
      final controller = DayResultsController(
        runs: first.runs,
        analysis: first.analysis!,
        coachRunner: testCoachRunner((job) async => job()),
      );
      Future<void> coached() async {
        await controller.requestTheoreticalBest();
        while (controller.coachLoading) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await controller.requestChannelSummaries();
      }

      // The driver's own goals set after the session before (FET-218),
      // checked on this one.
      var measuredGoals = 0;
      String ownGoals() {
        final coach = controller.coach;
        if (coach == null || coach.previousRunId.isEmpty) return '';
        final goals = controller.runMetadata(coach.previousRunId).goals;
        if (goals == null) return '';
        final checks = checkSessionGoals(
          goals,
          coach,
          groupId: controller.theoreticalBest!.groupId,
        );
        expect(checks, hasLength(goals.goals.length));
        measuredGoals += checks
            .where((c) => c.outcome != CoachGoalOutcome.notMeasured)
            .length;
        return '\n  own goals: ${[for (final c in checks) '${c.goal.segmentName} ${c.goal.kind.name} at ${c.measuredName}: ${c.before?.value.toStringAsFixed(1)} (${c.before?.laps}) -> ${c.now?.value.toStringAsFixed(1)} (${c.now?.laps}) ${c.outcome.name}'].join('; ')}';
      }

      // The Coach place's session summary (FET-233), from the same results.
      String summary() {
        final result = controller.theoreticalBest;
        final s = summarizeSession(
          controller.latestRunId,
          progression: controller.progression,
          sections: result?.sectionProgression([
            for (final run in controller.progression.runs) run.run,
          ]),
          coach: controller.coach,
          channels: controller.channelSummaries,
        );
        if (s == null) return '  summary: not in the group shown';
        String change(SessionSegmentChange? c) =>
            c == null ? '-' : '${c.name} ${c.deltaSeconds.toStringAsFixed(3)}';
        return '  summary: best ${s.bestLap?.durationSeconds.toStringAsFixed(3)}'
            '${s.newBest ? ' (new best)' : ''} delta ${s.bestDeltaSeconds?.toStringAsFixed(3)}'
            ', spread ${s.lapSpread?.toStringAsFixed(3)} (before ${s.previousLapSpread?.toStringAsFixed(3)})'
            ', ${s.segmentsCompared} compared, gain ${change(s.biggestGain)}'
            ', loss ${change(s.biggestLoss)}, gap ${change(s.biggestGap)}'
            ', car ${[for (final t in s.temperatures) '${t.channel} ${t.maximum.toStringAsFixed(0)}/${t.previousMaximum?.toStringAsFixed(0)}'].join(' ')}'
            ', goal ${s.goal?.outcome.name}'
            '${ownGoals()}';
      }

      // The driver takes the coach's changes as their goals for the next
      // session, as Add a goal suggests them.
      void setGoals() {
        final coach = controller.coach;
        final corners =
            controller.theoreticalBest?.corners ?? const <DayCorner>[];
        if (coach == null) return;
        final goals = [
          for (final item in coach.plan)
            if (item.finding.kind.corrective)
              for (final corner in corners)
                if (corner.segmentId == item.finding.segmentId)
                  SessionGoal(
                    kind: item.finding.kind,
                    segmentName: corner.name,
                    startProgressMeters: corner.startProgressMeters,
                    endProgressMeters: corner.endProgressMeters,
                  ),
        ];
        final runId = controller.latestRunId;
        expect(
          controller.updateRunMetadata(
            runId,
            controller.runMetadata(runId).withGoals(RunGoals(goals: goals)),
          ),
          isNull,
        );
      }

      String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(0)} MB';
      void report(String step, Duration add, Duration coach) {
        final plan = controller.coach;
        final best = controller.theoreticalBest;
        final lines = [
          '$step: add ${add.inMilliseconds} ms, best+coach '
              '${coach.inMilliseconds} ms, rss ${mb(ProcessInfo.currentRss)}, '
              'max rss ${mb(ProcessInfo.maxRss)}',
          '  coached ${controller.latestRunName}, best ${best?.state.name}, '
              'reason ${plan?.reason.name}${controller.coachError.isEmpty ? '' : ', error ${controller.coachError}'}',
          for (final item in plan?.plan ?? const <CoachItem>[])
            '  ${item.finding.kind.name} ${item.finding.segmentName} '
                '${item.finding.confidence.toStringAsFixed(2)} on '
                '${item.finding.affectedLaps.length} laps: '
                '${[for (final e in item.finding.evidence) '${e.metric} ${e.observed.toStringAsFixed(1)} vs ${e.reference.toStringAsFixed(1)} ${e.unit}'].join('; ')}\n'
                '    laps ${[for (final lap in item.finding.affectedLaps) '${lap.displayName} ${lap.durationSeconds.toStringAsFixed(1)}'].join(', ')}'
                '${item.finding.kind.corrective ? ' against' : ', from'} ${[for (final lap in item.finding.evidence.first.referenceLaps) '${lap.displayName} ${lap.durationSeconds.toStringAsFixed(1)}'].join(', ')}',
          summary(),
        ];
        // ignore: avoid_print
        print(lines.join('\n'));
      }

      final opened = clock.elapsed;
      clock.reset();
      await coached();
      report('Session 1', opened, clock.elapsed);
      setGoals();
      for (final path in files.skip(1)) {
        clock.reset();
        final addition = await controller.addRecordings([path]);
        final add = clock.elapsed;
        expect(addition.error, isEmpty);
        expect(addition.added, isNotEmpty);
        clock.reset();
        await coached();
        report(addition.added.join(', '), add, clock.elapsed);
        setGoals();
        expect(controller.coach, isNotNull);
        expect(controller.coach!.runId, controller.latestRunId);
        // The day's corners time its best lap, measured again on it when
        // the kept ones cannot (FET-170).
        final best = controller.theoreticalBest!;
        // ignore: avoid_print
        print(
          '  theoretical best ${best.theoreticalBestSeconds?.toStringAsFixed(3)}'
          ', best lap ${best.bestLapSeconds?.toStringAsFixed(3)}',
        );
        expect(bestLapHasUntimedSegment(best), isFalse);
        expect(
          best.theoreticalBestSeconds,
          lessThanOrEqualTo(best.bestLapSeconds! + 1e-6),
        );
      }
      // The driver's goals (the coach's changes) were measured on the
      // sessions after them (FET-218).
      expect(measuredGoals, greaterThan(0));
      controller.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
