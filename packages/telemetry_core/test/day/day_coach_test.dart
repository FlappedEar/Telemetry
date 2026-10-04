import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';

// A lap at 30 m/s, slowing to [slow] m/s at 70 m, in the first corner, and
// back.
double Function(double) _lap(double slow) =>
    (d) => d >= 20 && d <= 120 ? slow + (30 - slow) * (d - 70).abs() / 50 : 30.0;

// The same lap slowing in the first and the second corner.
double Function(double) _twoCorners(double slow) {
  final first = _lap(slow);
  return (d) => d >= 307 && d <= 407 ? slow + (30 - slow) * (d - 357).abs() / 50 : first(d);
}

// The same lap slowing in the first three corners.
double Function(double) _threeCorners(double slow) {
  final two = _twoCorners(slow);
  return (d) => d >= 443 && d <= 543 ? slow + (30 - slow) * (d - 493).abs() / 50 : two(d);
}

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
  double Function(double) Function(double slow) shape = _lap,
  bool coachedRecording = true,
}) {
  final runs = [
    _run(
      'run1',
      rectangleSession(
        [for (final slow in earlier) shape(slow)],
        firstTimestampMilliseconds: 1000,
        pedals: pedals,
      ),
    ),
    _run(
      'run2',
      rectangleSession(
        [for (final slow in latest) shape(slow)],
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
  return dayCoach(result, {
    for (final run in runs)
      run.runId: run.runId == 'run2' && !coachedRecording ? null : run.session,
  }, runId: runId);
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

  test('a coast held at light throttle is not coasting', () {
    // The same stretch as above, with the throttle held at 5 %: the driving
    // states call it coasting (below 8 %), the coach does not.
    void light(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      _edit(session, 'throttle', 5, (d) => d >= 20 && d < 60);
      _edit(session, 'brake', 0, (d) => d >= 20 && d < 60);
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], edit: light);
    expect(coach.findings.where((f) => f.kind == CoachKind.excessiveCoasting), isEmpty);
  });

  // The latest session's first lap brakes 20 m early and its third about
  // 25 m late into the first corner (and, with [second], the second).
  void Function(String, TelemetrySession) spread({bool second = false}) => (runId, session) {
    if (runId != 'run2') return;
    for (final at in [0.0, if (second) 287.0]) {
      _edit(session, 'brake', 30, (d) => d >= at + 5 && d < at + 20, lap: 1);
      _edit(session, 'brake', 0, (d) => d >= at + 15 && d < at + 45, lap: 3);
    }
  };

  test('braking points spread over a session suggest one marker', () {
    // The earlier laps are a little faster, not enough for another pattern.
    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2, 17.1], edit: spread());
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.inconsistentBraking);
    expect(finding.affectedLaps.map((lap) => (lap.runId, lap.lapNumber)), [
      ('run2', 1),
      ('run2', 2),
      ('run2', 3),
    ]);
    // The laps off the session's typical braking point.
    expect(finding.sessionLaps.map((lap) => (lap.runId, lap.lapNumber)), [
      ('run2', 1),
      ('run2', 3),
    ]);
    expect(finding.evidence.map((e) => e.key), [
      CoachMetric.brakingSpread,
      CoachMetric.brakingStart,
      CoachMetric.segmentTime,
      CoachMetric.nextStraightTime,
    ]);
    // About 40 m in this session; the day's three fastest laps agree.
    expect(finding.evidence.first.observed, greaterThan(35));
    expect(finding.evidence.first.reference, lessThan(5));
    expect(finding.evidence.first.referenceLaps, hasLength(3));
    // Two laps off the typical point: 0.48 + 0.18 + 0.08.
    expect(finding.confidence, closeTo(0.74, 1e-9));
    final item = coach.plan.singleWhere((i) => i.finding == finding);
    expect(item.title, endsWith('— Brake at the same point every lap'));
    expect(item.action, startsWith('Pick one braking marker'));
  });

  test('one lap braking elsewhere is not a braking pattern', () {
    void once(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      _edit(session, 'brake', 0, (d) => d >= 15 && d < 45, lap: 3);
    }

    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2, 17.1], edit: once);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('two laps of a session are too few for braking consistency', () {
    void two(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      _edit(session, 'brake', 30, (d) => d >= 5 && d < 20, lap: 1);
      _edit(session, 'brake', 0, (d) => d >= 15 && d < 45, lap: 2);
    }

    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2], edit: two);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('a spread the day\'s fastest laps share is no braking item', () {
    void both(String runId, TelemetrySession session) {
      _edit(session, 'brake', 30, (d) => d >= 5 && d < 20, lap: 1);
      _edit(session, 'brake', 0, (d) => d >= 15 && d < 45, lap: 3);
    }

    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2, 17.1], edit: both);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('a brake dab is not where a lap brakes', () {
    void dab(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      // A 0.25 s dab well before the corner on lap 1; lap 3 brakes late.
      _edit(session, 'brake', 30, (d) => d >= 5 && d < 12.5, lap: 1);
      _edit(session, 'brake', 0, (d) => d >= 15 && d < 45, lap: 3);
    }

    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2, 17.1], edit: dab);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('braking already under way where the approach starts is not an onset', () {
    void early(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      // Lap 1 brakes from the start/finish line, where the first corner's
      // approach is cut off; lap 3 brakes late.
      _edit(session, 'brake', 30, (d) => d >= 0 && d < 20, lap: 1);
      _edit(session, 'brake', 0, (d) => d >= 15 && d < 45, lap: 3);
    }

    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2, 17.1], edit: early);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('a lap a few metres off the usual braking point is not off it', () {
    void near(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      // Lap 1 brakes about 7 m early, lap 3 about 25 m late: one lap off.
      _edit(session, 'brake', 30, (d) => d >= 13 && d < 20, lap: 1);
      _edit(session, 'brake', 0, (d) => d >= 15 && d < 45, lap: 3);
    }

    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2, 17.1], edit: near);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('a much slower lap is not read for braking consistency', () {
    void slowLate(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      _edit(session, 'brake', 30, (d) => d >= 5 && d < 20, lap: 1);
      // Lap 4, much slower than the session's typical lap, brakes late.
      _edit(session, 'brake', 0, (d) => d >= 15 && d < 45, lap: 4);
    }

    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2, 17.1, 3], edit: slowLate);
    expect(coach.slowLaps.map((lap) => (lap.runId, lap.lapNumber)), [('run2', 4)]);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('without pedals there is no braking item', () {
    final coach = _coach([17.3, 17.4, 17.3], [17, 17.2, 17.1], pedals: false);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('a corner shows the time through the straight after it', () {
    final coach = _coach([20, 20.5], [17, 17.2, 17.1]);
    final evidence = coach.plan.first.finding.evidence;
    final straight = evidence.singleWhere((e) => e.key == CoachMetric.nextStraightTime);
    expect(straight.observed, greaterThan(straight.reference));
  });

  test('the corner losing more time leads the plan, even on fewer laps', () {
    // The second corner is far slower on three laps, the first a little
    // slower on all four.
    final second = {20.0: 20.0, 20.5: 20.5, 17.0: 11.0, 17.2: 11.2, 17.1: 11.1, 17.3: 20.0};
    double Function(double) shape(double slow) {
      final first = _lap(slow);
      final other = second[slow]!;
      return (d) => d >= 307 && d <= 407 ? other + (30 - other) * (d - 357).abs() / 50 : first(d);
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1, 17.3], shape: shape);
    expect(coach.plan, hasLength(2));
    final [first, later] = [for (final item in coach.plan) item.finding];
    expect(first.sessionLaps, hasLength(3));
    expect(later.sessionLaps, hasLength(4));
    expect(coach.focus!.finding, same(first));
  });

  test('time lost on the straight after a corner counts toward its rank', () {
    // Both corners as slow on the latest laps; out of the second they then
    // also gain speed slowly, down the straight after it.
    double Function(double) shape(double slow) {
      final latest = slow < 19;
      double corner(double d, double apex, bool lazy) {
        final x = d - apex;
        if (x <= 25) return slow + (30 - slow) * x.abs() / 50;
        if (!lazy) return min(30.0, slow + (30 - slow) * x / 50);
        final turnIn = slow + (30 - slow) * 25 / 50;
        return min(30.0, turnIn + (30 - turnIn) * (x - 25) / 125);
      }

      return (d) => d >= 20 && d <= 120
          ? corner(d, 70, false)
          : d >= 307 && d <= 507
          ? corner(d, 357, latest)
          : 30.0;
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], shape: shape);
    expect(coach.plan, hasLength(2));
    double lost(CoachFinding f, CoachMetric key) {
      final e = f.evidence.singleWhere((e) => e.key == key);
      return e.observed - e.reference;
    }

    final [first, later] = [for (final item in coach.plan) item.finding];
    // The corners alone lose about the same; the straight decides.
    expect(
      (lost(first, CoachMetric.segmentTime) - lost(later, CoachMetric.segmentTime)).abs(),
      lessThan(coachRankSeconds),
    );
    expect(lost(first, CoachMetric.nextStraightTime), greaterThan(0.3));
    expect(lost(later, CoachMetric.nextStraightTime), lessThan(0.1));
    expect(first.segmentId, isNot(later.segmentId));
  });

  test('the straight after a corner is timed apart from the corner', () {
    final coach = _coach([20, 20.5], [17, 17.2, 17.1]);
    final evidence = coach.plan.first.finding.evidence;
    final corner = evidence.singleWhere((e) => e.key == CoachMetric.segmentTime);
    final straight = evidence.singleWhere((e) => e.key == CoachMetric.nextStraightTime);
    // Most of the 240 m straight at up to 30 m/s, not the corner again.
    expect(straight.reference, inInclusiveRange(200 / 30, 240 / 25));
    expect(straight.observed, isNot(closeTo(corner.observed, 0.5)));
  });

  test('braking points that agree make no braking item', () {
    final coach = _coach([20, 20.5], [17, 17.2, 17.1]);
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), isEmpty);
  });

  test('one braking marker at a time in the plan', () {
    final coach = _coach(
      [17.3, 17.4, 17.3],
      [17, 17.2, 17.1],
      edit: spread(second: true),
      shape: _twoCorners,
    );
    expect(coach.findings.where((f) => f.kind == CoachKind.inconsistentBraking), hasLength(2));
    expect(coach.plan.where((i) => i.finding.kind == CoachKind.inconsistentBraking), hasLength(1));
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

  void coastOnce(String runId, TelemetrySession session) {
    if (runId != 'run2') return;
    _edit(session, 'throttle', 0, (d) => d >= 20 && d < 60, lap: 1);
    _edit(session, 'brake', 0, (d) => d >= 20 && d < 60, lap: 1);
  }

  test('a coast on a single lap is a finding but not a plan item', () {
    final coach = _coach([20, 20.5], [17, 20.2], edit: coastOnce);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.excessiveCoasting);
    expect(finding.repeated, isFalse);
    expect(
      finding.evidence.first.detail,
      startsWith('One affected lap of this session (laps of the day so far showing it: 1)'),
    );
    expect(coach.plan.any((item) => item.finding == finding), isFalse);
  });

  test('a pattern on fewer than half of the session\'s laps compared is not a finding', () {
    // Every lap of the latest session has faster laps to compare with; only
    // the first coasts.
    final coach = _coach([24, 24.2], [17, 20.2, 20.4], edit: coastOnce);
    expect(coach.findings.where((f) => f.kind == CoachKind.excessiveCoasting), isEmpty);
  });

  test('patterns of earlier sessions the latest no longer repeats say so', () {
    void coastEarlier(String runId, TelemetrySession session) {
      if (runId != 'run1') return;
      for (final lap in [1, 2, 3]) {
        _edit(session, 'throttle', 0, (d) => d >= 20 && d < 60, lap: lap);
        _edit(session, 'brake', 0, (d) => d >= 20 && d < 60, lap: lap);
      }
    }

    // The earlier session coasts on every lap; the latest, faster than its
    // first two laps and slower than its third, does not.
    final coach = _coach([18, 18.2, 21.5], [20, 20.2, 20.4], edit: coastEarlier);
    expect(coach.findings.where((f) => f.kind == CoachKind.excessiveCoasting), isEmpty);
    expect(coach.reason, CoachReason.notInSession);
    expect(coach.message, contains('earlier today'));
  });

  test('a pattern repeated across sessions counts toward the plan', () {
    // Two laps of the earlier session and one of the latest are slow through
    // the corner; the latest session's other lap is the fastest.
    final coach = _coach([12, 12.2], [15.1, 20.5]);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.lowMinimumSpeed);
    expect(finding.affectedLaps.map((lap) => lap.runId), ['run1', 'run1', 'run2']);
    expect(finding.sessionLaps.map((lap) => lap.runId), ['run2']);
    expect(
      finding.evidence.first.detail,
      startsWith('One affected lap of this session (laps of the day so far showing it: 3)'),
    );
    // The values are the latest session's own: its slow lap (15.1 m/s, not
    // the earlier 12) against its fast one.
    expect(finding.evidence.first.observed, closeTo(15.1 * 3.6, 2.0));
    expect(finding.evidence.first.referenceLaps.map((lap) => lap.runId).toSet(), {'run2'});
    expect(coach.plan.map((item) => item.finding), contains(finding));
    expect(coach.reason, CoachReason.ready);
  });

  test('laps of the session with no faster lap do not count against a pattern', () {
    // The latest session holds the day's fastest laps: only its slow lap
    // has faster laps to compare with, and it shows the pattern.
    final coach = _coach([15, 15.2], [15.1, 20.5, 20.55]);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.lowMinimumSpeed);
    expect(finding.sessionLaps, hasLength(1));
    expect(finding.affectedLaps, hasLength(3));
    expect(coach.plan.map((item) => item.finding), contains(finding));
  });

  test('a lap much slower than its session\'s typical lap is left out', () {
    // The latest session's third lap is slow everywhere (traffic): its
    // corner is as slow as the others', but it is not read for a pattern.
    double Function(double) shape(double slow) =>
        slow == 15.1 ? (d) => min(_lap(slow)(d), 22.0) : _lap(slow);
    final coach = _coach([20, 20.5], [15, 15.2, 15.1], shape: shape);
    expect(coach.slowLaps.map((lap) => (lap.runId, lap.lapNumber)), [('run2', 3)]);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.lowMinimumSpeed);
    expect(finding.sessionLaps.map((lap) => lap.lapNumber), [1, 2]);
    expect(finding.affectedLaps.any((lap) => lap.lapNumber == 3 && lap.runId == 'run2'), isFalse);
  });

  test('a slow lap does not make an improvement to keep', () {
    // The latest session's first lap is a slow warm-up: without it there are
    // only two laps, so no improvement, and the change is not suppressed.
    double Function(double) shape(double slow) =>
        slow == 14 ? (d) => min(_lap(slow)(d), 22.0) : _lap(slow);
    final coach = _coach([20, 20.5], [14, 16, 17], shape: shape);
    expect(coach.slowLaps.map((lap) => (lap.runId, lap.lapNumber)), [('run2', 1)]);
    expect(coach.findings.where((f) => f.kind == CoachKind.improving), isEmpty);
  });

  test('a pattern the latest session has left behind is not advice', () {
    final coach = _coach([15, 15.2, 15.1], [20, 20.5, 20.2]);
    expect(coach.findings.where((f) => f.kind.corrective), isEmpty);
    expect(coach.plan, isEmpty);
    expect(coach.reason, CoachReason.noFasterLap);
  });

  test('faster laps within reach are preferred as references over the fastest', () {
    // run1: lap 1 about 1.8 s faster than the latest laps, lap 2 about 1.7 s,
    // lap 3 about 0.5 s.
    final coach = _coach([25, 24, 13], [10, 10.2, 10.1]);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.lowMinimumSpeed);
    final references = finding.evidence.first.referenceLaps;
    expect(references.map((lap) => (lap.runId, lap.lapNumber)), [('run1', 2), ('run1', 3)]);
    // Compared with laps slowing to 24 and 13 m/s (median 18.5), not 25 and 24.
    expect(finding.evidence.first.reference, closeTo(18.5 * 3.6, 0.5 * 3.6));
  });

  test('within reach means at most 1.5 s faster', () {
    // run1's laps are about 1.1, 1.2, 1.4 and 1.6 s faster than the latest
    // laps. The two fastest through the corner within reach are compared:
    // the third and the second, not the fourth (out of reach) or the first.
    final coach = _coach([16, 18, 19.5, 22], [10, 10.2, 10.1]);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.lowMinimumSpeed);
    expect(finding.evidence.first.referenceLaps.map((lap) => (lap.runId, lap.lapNumber)), [
      ('run1', 2),
      ('run1', 3),
    ]);
  });

  test('the main focus is the first change, before an improvement to keep', () {
    // The first corner improves lap by lap; the second stays slower than the
    // earlier, faster laps.
    double Function(double) shape(double slow) {
      final first = _lap(slow);
      final second = slow < 18 ? 15.0 : 20.0;
      return (d) => d >= 307 && d <= 407 ? second + (30 - second) * (d - 357).abs() / 50 : first(d);
    }

    // One faster lap through the second corner (run1's second lap is slow):
    // the change's confidence (0.78) is below the improvement's (0.79), so
    // it ranks second but is still the focus.
    final coach = _coach([20, 10], [15, 16, 17], shape: shape);
    expect(coach.plan.map((item) => item.finding.kind), [
      CoachKind.lowMinimumSpeed,
      CoachKind.improving,
    ]);
    expect(coach.focus, same(coach.plan.first));
    expect(coach.message, startsWith('Work on the main focus first.'));
  });

  test('improvements in two corners: one is kept in the plan', () {
    final coach = _coach([20, 20.5], [15, 16, 17], shape: _twoCorners);
    expect(coach.findings.where((f) => f.kind == CoachKind.improving), hasLength(2));
    expect(coach.plan.where((item) => !item.finding.kind.corrective), hasLength(1));
  });

  test('a coast that starts before the approach counts for its part inside it', () {
    void coasts(String runId, TelemetrySession session) {
      // The faster laps coast from before the approach of the second corner,
      // the latest about as long inside it.
      final (from, to) = runId == 'run1' ? (150.0, 215.0) : (180.0, 225.0);
      _edit(session, 'throttle', 0, (d) => d >= from && d < to);
      _edit(session, 'brake', 0, (d) => d >= from && d < to);
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], shape: _twoCorners, edit: coasts);
    expect(coach.findings.where((f) => f.kind == CoachKind.excessiveCoasting), isEmpty);
  });

  test('an earlier lift before the same braking point as faster laps', () {
    void lifts(String runId, TelemetrySession session) {
      final lift = runId == 'run1' ? 288.0 : 258.0;
      _edit(session, 'throttle', 100, (d) => d >= 200 && d < lift);
      _edit(session, 'throttle', 0, (d) => d >= lift && d < 307);
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], shape: _twoCorners, edit: lifts);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.earlyLift);
    expect(finding.affectedLaps, hasLength(3));
    expect(finding.evidence.first.key, CoachMetric.liftPoint);
    expect(finding.evidence.first.observed, lessThan(finding.evidence.first.reference - 8));
    expect(finding.evidence.map((e) => e.key), contains(CoachMetric.brakingStart));
  });

  test('a long coast mostly before the approach counts only inside it', () {
    void coast(String runId, TelemetrySession session) {
      if (runId != 'run2') return;
      _edit(session, 'throttle', 0, (d) => d >= 100 && d < 190);
      _edit(session, 'brake', 0, (d) => d >= 100 && d < 190);
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], shape: _twoCorners, edit: coast);
    expect(coach.findings.where((f) => f.kind == CoachKind.excessiveCoasting), isEmpty);
  });

  test('a lift right at the brake point, after an earlier breath, is not early', () {
    void lifts(String runId, TelemetrySession session) {
      if (runId == 'run1') {
        _edit(session, 'throttle', 100, (d) => d >= 150 && d < 288);
        _edit(session, 'throttle', 0, (d) => d >= 288 && d < 307);
      } else {
        _edit(session, 'throttle', 100, (d) => d >= 150 && d < 200);
        _edit(session, 'throttle', 0, (d) => d >= 200 && d < 215);
        _edit(session, 'throttle', 100, (d) => d >= 215 && d < 301);
        _edit(session, 'throttle', 0, (d) => d >= 301 && d < 307);
      }
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], shape: _twoCorners, edit: lifts);
    expect(coach.findings.where((f) => f.kind == CoachKind.earlyLift), isEmpty);
  });

  test('a lift with the pedals overlapping at the brake is not early', () {
    void lifts(String runId, TelemetrySession session) {
      if (runId == 'run1') {
        _edit(session, 'throttle', 100, (d) => d >= 150 && d < 288);
        _edit(session, 'throttle', 0, (d) => d >= 288 && d < 307);
      } else {
        _edit(session, 'throttle', 100, (d) => d >= 150 && d < 200);
        _edit(session, 'throttle', 0, (d) => d >= 200 && d < 215);
        _edit(session, 'throttle', 50, (d) => d >= 215 && d < 307);
        _edit(session, 'throttle', 0, (d) => d >= 307 && d < 330);
      }
    }

    final coach = _coach([20, 20.5], [17, 17.2, 17.1], shape: _twoCorners, edit: lifts);
    expect(coach.findings.where((f) => f.kind == CoachKind.earlyLift), isEmpty);
  });

  test('three corners to change: two in the plan, in different segments', () {
    final coach = _coach([20, 20.5], [15, 15.2, 15.1], shape: _threeCorners);
    final changes = coach.findings.where((f) => f.kind == CoachKind.lowMinimumSpeed);
    expect(changes.map((f) => f.segmentId).toSet().length, greaterThanOrEqualTo(3));
    final planned = coach.plan.where((item) => item.finding.kind.corrective).toList();
    expect(planned, hasLength(2));
    expect(planned.map((item) => item.finding.segmentId).toSet(), hasLength(2));
  });

  test('a confident pattern on two laps asks for more laps', () {
    final coach = _coach([20, 20.5], [15, 15.2, 20.6]);
    final finding = coach.findings.singleWhere((f) => f.kind == CoachKind.lowMinimumSpeed);
    expect(finding.affectedLaps, hasLength(2));
    expect(finding.confidence, greaterThanOrEqualTo(coachPlanConfidence));
    expect(coach.plan, isEmpty);
    expect(coach.reason, CoachReason.tooFewLaps);
  });

  test('a session whose recording is missing says so', () {
    final coach = _coach([20, 20.5], [15, 15.2, 15.1], coachedRecording: false);
    expect(coach.findings, isEmpty);
    expect(coach.reason, CoachReason.noRecording);
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
