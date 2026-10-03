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

/// Sets [channel] of [session] to [value] wherever [where] holds for the
/// sample's distance into its lap (laps of [_perimeter] from the gate, as
/// [rectangleSession] drives them).
void _edit(
  TelemetrySession session,
  String channel,
  double value,
  bool Function(double distance) where, {
  int? lap,
}) {
  final speed = session.channels['velocity']!.values;
  final values = session.channels[channel]!.values;
  var distance = -20.0;
  for (var i = 0; i < speed.length; ++i) {
    if (distance >= 0 &&
        (lap == null || distance ~/ _perimeter == lap - 1) &&
        where(distance % _perimeter)) {
      values[i] = value;
    }
    distance += speed[i] / 3.6 / 10.0;
  }
}

// The rectangle's lap: two 240 m and two 90 m straights and four 30 m
// radius corners.
const _perimeter = 2 * 240.0 + 2 * 90.0 + 2 * pi * 30.0;

/// The coach of a day of an earlier session at [earlier] and the latest at
/// [latest] (slow speeds through the first corner, one lap each); [edit]
/// changes a session's channels first.
DayCoach _coach(
  List<double> earlier,
  List<double> latest, {
  bool pedals = true,
  void Function(String runId, TelemetrySession session)? edit,
  String runId = 'run2',
}) {
  final runs = [
    _run(
      'run1',
      rectangleSession(
        [for (final slow in earlier) _lap(slow)],
        firstTimestampMilliseconds: 1000,
        pedals: pedals,
      ),
    ),
    _run(
      'run2',
      rectangleSession(
        [for (final slow in latest) _lap(slow)],
        firstTimestampMilliseconds: 4000000,
        pedals: pedals,
      ),
    ),
  ];
  for (final run in runs) {
    edit?.call(run.runId, run.session);
  }
  final analysis = analyzeDay(runs);
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  final result = dayTheoreticalBest(analysis, outing, random: Random(1));
  expect(result.state, DayTheoreticalBestState.ready);
  return dayCoach(result, {for (final run in runs) run.runId: run.session}, runId: runId);
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
    expect(coach.reason, CoachReason.noFasterLap);
  });

  test('a session with no lap in the group is not coached in its place', () {
    final coach = _coach([20, 20.5], [15, 15.2, 15.1], runId: 'run3');
    expect(coach.runId, 'run3');
    expect(coach.findings, isEmpty);
    expect(coach.reason, CoachReason.noLapInGroup);
  });

  test('without pedals only speeds are compared, and the plan says so', () {
    final coach = _coach([21.2, 21.2], [20, 20.1, 20], pedals: false);
    expect(coach.findings, isEmpty);
    expect(coach.reason, CoachReason.noPedals);
    expect(coach.message, contains('not recorded'));
  });

  test('a repeated coast before the corner, against faster laps that keep a pedal on', () {
    void coast(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      _edit(session, 'throttle', 0, (d) => d >= 20 && d < 60);
      _edit(session, 'brake', 0, (d) => d >= 20 && d < 60);
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], edit: coast);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.excessiveCoasting);
    expect(finding.affectedLaps, hasLength(3));
    expect(finding.evidence.first.key, CoachMetric.longestCoast);
    expect(finding.evidence.first.observed, greaterThan(0.7));
    expect(finding.evidence.first.reference, lessThan(finding.evidence.first.observed - 0.4));
    expect(finding.evidence.map((e) => e.key), contains(CoachMetric.coastDistance));
  });

  test('a faster lap whose brake drops out has no coast, not a zero coast', () {
    void coastAndDropout(String runId, TelemetrySession session) {
      if (runId == 'run2') {
        _edit(session, 'throttle', 0, (d) => d >= 20 && d < 60);
        _edit(session, 'brake', 0, (d) => d >= 20 && d < 60);
      } else {
        _edit(session, 'brake', double.nan, (d) => d >= 0 && d < 140);
      }
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], edit: coastAndDropout);
    expect(coach.findings.where((f) => f.kind == CoachKind.excessiveCoasting), isEmpty);
  });

  test('a repeated late throttle return after the slow point', () {
    void late(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      _edit(session, 'throttle', 15, (d) => d >= 60 && d < 85);
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], edit: late);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.lateThrottle);
    expect(finding.affectedLaps, hasLength(3));
    expect(finding.evidence.first.key, CoachMetric.throttleReturn);
    expect(finding.evidence.first.observed, greaterThan(finding.evidence.first.reference + 8));
  });

  test('a coast on a single lap is a finding but not a plan item', () {
    void coastOnce(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      _edit(session, 'throttle', 0, (d) => d >= 20 && d < 60, lap: 1);
      _edit(session, 'brake', 0, (d) => d >= 20 && d < 60, lap: 1);
    }

    final coach = _coach([20, 20.5], [17, 20.2, 20.4], edit: coastOnce);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.excessiveCoasting);
    expect(finding.repeated, isFalse);
    expect(finding.evidence.first.detail, startsWith('One affected lap'));
    expect(coach.plan.any((item) => item.finding == finding), isFalse);
  });

  test('needs the theoretical best', () {
    final coach = dayCoach(
      DayTheoreticalBest(groupId: '', state: DayTheoreticalBestState.unavailable),
      const {},
      runId: 'run1',
    );
    expect(coach.plan, isEmpty);
    expect(coach.reason, CoachReason.noSegments);
    expect(coach.message, contains('segments'));
  });
}
