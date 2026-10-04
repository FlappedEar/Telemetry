// The coach on a real day, run session by session as it would be at the
// track. Set FLAPPEDEAR_REAL_DAY to a folder of one day's VBO files; nothing
// from them is written anywhere.
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test(
    'a plan after each session follows the plan rules',
    () {
      final files =
          Directory(folder)
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.vbo'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, greaterThanOrEqualTo(2));
      final runs = <DayRunInput>[
        for (final (index, file) in files.indexed)
          () {
            final session = parseVboFile(file.path);
            return DayRunInput(
              runId: 'run${index + 1}',
              name: 'Session ${index + 1}',
              contentSha256: '${index + 1}'.padLeft(64, '0'),
              session: session,
              laps: deriveSourceLapSession(session),
            );
          }(),
      ];
      // The main focus shown after the session before.
      CoachFinding? shown;
      for (var count = 2; count <= runs.length; count++) {
        final day = runs.take(count).toList();
        final analysis = analyzeDay(day);
        final outing = {for (final run in day) run.runId: OutingRun(run.session, run.laps)};
        final best = dayTheoreticalBest(analysis, outing, random: Random(1));
        final coach = dayCoach(
          best,
          {for (final run in day) run.runId: run.session},
          runId: day.last.runId,
          before: dayBeforeRun(analysis, outing, day.last.runId, random: Random(1)),
        );
        print(
          'After ${day.last.name}: ${coach.findings.length} findings, '
          '${coach.plan.length} planned. ${coach.message}',
        );
        if (coach.goal case final goal?) {
          print('  ${goal.summary} Measured at ${goal.measuredName}.');
        }
        // The goal is the focus the driver saw then.
        if (shown != null && shown.kind.corrective) {
          expect(coach.goal?.finding.kind, shown.kind);
          expect(coach.goal?.finding.segmentName, shown.segmentName);
        }
        shown = coach.focus?.finding;
        for (final item in coach.plan) {
          print(
            '  ${item.title} (${item.finding.confidence.toStringAsFixed(2)}): '
            '${item.explanation}',
          );
          for (final e in item.finding.evidence.where(
            (e) => e.key == CoachMetric.combinedG || e.key == CoachMetric.combinedGShare,
          )) {
            print(
              '    ${e.metric}: ${e.observed.toStringAsFixed(2)} ${e.unit} against '
              '${e.reference.toStringAsFixed(2)} ${e.unit}',
            );
          }
        }
        if (best.state != DayTheoreticalBestState.ready) continue;
        expect(coach.runId, day.last.runId);
        expect(coach.plan.length, lessThanOrEqualTo(3));
        final changes = coach.plan.where((item) => item.finding.kind.corrective);
        expect(changes.length, lessThanOrEqualTo(2));
        expect(changes.map((item) => item.finding.segmentId).toSet().length, changes.length);
        expect(
          coach.plan.where((item) => !item.finding.kind.corrective).length,
          lessThanOrEqualTo(1),
        );
        for (final finding in coach.findings) {
          expect(finding.confidence, inInclusiveRange(0, 0.9));
          // Laps of the whole day so far count, the latest session's among them.
          final runIds = {for (final run in day) run.runId};
          expect(finding.affectedLaps.every((lap) => runIds.contains(lap.runId)), isTrue);
          expect(finding.affectedLaps.any((lap) => lap.runId == day.last.runId), isTrue);
        }
        for (final item in coach.plan) {
          expect(item.finding.confidence, greaterThanOrEqualTo(coachPlanConfidence));
        }
        // The reference day picks up the throttle early on a minority of
        // laps at any corner: not a pattern to plan.
        expect(coach.plan.where((item) => item.finding.kind == CoachKind.earlyThrottle), isEmpty);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
