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
        ];
        // ignore: avoid_print
        print(lines.join('\n'));
      }

      final opened = clock.elapsed;
      clock.reset();
      await coached();
      report('Session 1', opened, clock.elapsed);
      for (final path in files.skip(1)) {
        clock.reset();
        final addition = await controller.addRecordings([path]);
        final add = clock.elapsed;
        expect(addition.error, isEmpty);
        expect(addition.added, isNotEmpty);
        clock.reset();
        await coached();
        report(addition.added.join(', '), add, clock.elapsed);
        expect(controller.coach, isNotNull);
        expect(controller.coach!.runId, controller.latestRunId);
      }
      controller.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
