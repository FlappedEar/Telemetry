import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';

// A lap at 30 m/s, slowing to [slow] m/s at 70 m, in the first corner, and
// back.
double Function(double) _lap(double slow) =>
    (d) => d >= 20 && d <= 120 ? slow + (30 - slow) * (d - 70).abs() / 50 : 30.0;

DayRunInput _run(String id, TelemetrySession session) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
  session: session,
  laps: deriveSourceLapSession(session),
);

/// The coach of a day of an earlier session at [earlier] and the latest at
/// [latest] (slow speeds through the first corner, one lap each).
DayCoach _coach(List<double> earlier, List<double> latest) {
  final runs = [
    _run(
      'run1',
      rectangleSession(
        [for (final slow in earlier) _lap(slow)],
        firstTimestampMilliseconds: 1000,
        pedals: true,
      ),
    ),
    _run(
      'run2',
      rectangleSession(
        [for (final slow in latest) _lap(slow)],
        firstTimestampMilliseconds: 4000000,
        pedals: true,
      ),
    ),
  ];
  final analysis = analyzeDay(runs);
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  final result = dayTheoreticalBest(analysis, outing, random: Random(1));
  expect(result.state, DayTheoreticalBestState.ready);
  return dayCoach(result, {for (final run in runs) run.runId: run.session});
}

void main() {
  test('a repeated slower minimum speed than the earlier, faster laps', () {
    final coach = _coach([20, 20.5], [15, 15.2, 15.1]);
    expect(coach.runId, 'run2');
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.lowMinimumSpeed);
    expect(finding.affectedLaps.map((lap) => lap.runId).toSet(), {'run2'});
    expect(finding.affectedLaps, hasLength(3));
    expect(finding.evidence.first.metric, 'Minimum speed');
    expect(finding.evidence.first.unit, 'km/h');
    expect(finding.evidence.first.observed, lessThan(finding.evidence.first.reference - 5));
    expect(finding.evidence.first.referenceLaps.map((lap) => lap.runId).toSet(), {'run1'});
    // Three affected laps and two distinct references: 0.48 + 0.27 + 0.08.
    expect(finding.confidence, closeTo(0.83, 1e-9));
    final item = coach.plan.singleWhere((i) => i.finding == finding);
    expect(item.title, endsWith('— Keep more speed through the slow point'));
    expect(item.explanation, startsWith('Your repeated pattern suggests an opportunity'));
    expect(item.action, contains('faster laps'));
    expect(coach.plan.length, lessThanOrEqualTo(3));
  });

  test('an improvement over three consecutive laps is kept, not corrected', () {
    final coach = _coach([20, 20.5], [15, 16, 17]);
    final improving = coach.findings.singleWhere((f) => f.kind == CoachKind.improving);
    expect(improving.affectedLaps.map((lap) => lap.lapNumber), [1, 2, 3]);
    expect(improving.evidence.first.observed, greaterThan(improving.evidence.first.reference));
    expect(improving.confidence, 0.79);
    // The corrective finding in the same segment stays out of the plan.
    expect(coach.findings.any((f) => f.kind == CoachKind.lowMinimumSpeed), isTrue);
    expect(coach.plan.map((item) => item.finding.kind), [CoachKind.improving]);
    expect(coach.plan.single.title, endsWith('— Keep current approach'));
  });

  test('without faster laps there is nothing to suggest', () {
    final coach = _coach([15, 15.2], [20, 20.5, 20.2]);
    expect(coach.findings.where((f) => f.kind.corrective), isEmpty);
    expect(coach.plan, isEmpty);
    expect(coach.message, contains('No repeated pattern'));
  });

  test('needs the theoretical best', () {
    final coach = dayCoach(
      DayTheoreticalBest(groupId: '', state: DayTheoreticalBestState.unavailable),
      const {},
    );
    expect(coach.plan, isEmpty);
    expect(coach.runId, isEmpty);
    expect(coach.message, contains('segments'));
  });
}
