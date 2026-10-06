// Truth tests for lap plausibility (FET-199): a lap that cannot be a lap of
// the circuit stays listed but is never ranked or the best of the day.
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'support/gate_path.dart';

/// [count] laps of about 700 m at 8 m per 0.2 s (40 m/s), about 18 s each.
GatePath _laps(int count) {
  final path = GatePath()..points([(30.0, 0.0)]);
  for (var lap = 0; lap < count; ++lap) {
    path
      ..crossWestward()
      ..loopBackEast();
  }
  return path..crossWestward();
}

List<LapReferenceIssue> _issues(LapSession laps) => [
  for (final lap in laps.timedLaps) lap.referenceIssue,
];

void main() {
  test('normal laps are plausible and ranked', () {
    final laps = detectLaps(_laps(3).session(), gatePathGate);
    expect(laps.timedLaps, hasLength(3));
    expect(_issues(laps), everyElement(LapReferenceIssue.none));
    for (final lap in laps.timedLaps) {
      expect(lap.distanceMeters, closeTo(700, 30));
    }
    expect(laps.diagnostics.implausibleLaps, 0);
  });

  test('a tiny loop over the line is listed but can never be the best lap', () {
    // Two real laps, then a 180 m loop back over the line: a "lap" of
    // about 5 s that is far faster than the real ones.
    final path = _laps(2)
      ..travel([(-30.0, 30.0), (30.0, 30.0), (30.0, 0.0)])
      ..crossWestward();
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.timedLaps, hasLength(3));
    expect(_issues(laps), [
      LapReferenceIssue.none,
      LapReferenceIssue.none,
      LapReferenceIssue.implausibleLap,
    ]);
    final fake = laps.timedLaps[2];
    expect(fake.durationSeconds, lessThan(laps.timedLaps[0].durationSeconds));
    expect(fake.referenceEligible, isFalse);
    expect(laps.fastestLapIndex, isNot(2));
    expect(fake.deltaToBestSeconds, 0.0);
  });

  test('a lap much shorter than the session\'s other laps is not plausible', () {
    // About 360 m: over the 200 m floor but half the session's median lap.
    final path = _laps(3)
      ..travel([(-60.0, 0.0), (-60.0, 60.0), (60.0, 60.0), (60.0, 0.0), (30.0, 0.0)])
      ..crossWestward();
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.timedLaps, hasLength(4));
    expect(laps.timedLaps.last.referenceIssue, LapReferenceIssue.implausibleLap);
    expect(laps.timedLaps.last.distanceMeters, closeTo(360, 30));
    expect(laps.diagnostics.implausibleLaps, 1);
  });

  test('a ten-hour lap is not plausible', () {
    final path = GatePath(step: 1.0)..points([(30.0, 0.0)]);
    path
      ..crossWestward(maximumStepMeters: 30.0)
      ..loopBackEast(maximumStepMeters: 30.0);
    path
      ..travel([(300.0, 300.0)], maximumStepMeters: 30.0)
      ..wait(36000)
      ..travel([(30.0, 0.0)], maximumStepMeters: 30.0)
      ..crossWestward(maximumStepMeters: 30.0);
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.timedLaps, hasLength(1));
    expect(laps.timedLaps.single.durationSeconds, greaterThan(36000));
    expect(laps.timedLaps.single.referenceIssue, LapReferenceIssue.implausibleLap);
    expect(laps.fastestLapIndex, isNull);
  });

  test('a lap faster than 100 m/s on average is not plausible', () {
    // The same 700 m lap at 8 m per 0.05 s (160 m/s): about 4.4 s, so only
    // the speed rule catches it.
    final path = GatePath(step: 0.05)..points([(30.0, 0.0)]);
    path
      ..crossWestward()
      ..loopBackEast()
      ..crossWestward();
    final laps = detectLaps(path.session(), gatePathGate);
    final lap = laps.timedLaps.single;
    expect(lap.durationSeconds, greaterThan(3.0));
    expect(lap.distanceMeters, greaterThan(200.0));
    expect(lap.referenceIssue, LapReferenceIssue.implausibleLap);
  });

  test('a lap under 3 s is not plausible even when its path and speed are', () {
    // A 220 m loop at 96 m/s: about 2.3 s.
    final path = GatePath(step: 0.05)..points([(30.0, 0.0)]);
    path
      ..crossWestward(maximumStepMeters: 4.8)
      ..travel([(-30.0, 50.0), (30.0, 50.0), (30.0, 0.0)], maximumStepMeters: 4.8)
      ..crossWestward(maximumStepMeters: 4.8);
    final laps = detectLaps(path.session(), gatePathGate);
    final lap = laps.timedLaps.single;
    expect(lap.durationSeconds, lessThan(3.0));
    expect(lap.distanceMeters, greaterThan(200.0));
    expect(lap.distanceMeters! / lap.durationSeconds, lessThan(100.0));
    expect(lap.referenceIssue, LapReferenceIssue.implausibleLap);
  });

  test('of two laps, the fake one is flagged and the real one ranked', () {
    // 700 m, then a 440 m shortcut loop.
    final path = _laps(1)
      ..travel([(-60.0, 0.0), (-60.0, 100.0), (60.0, 100.0), (60.0, 0.0), (30.0, 0.0)])
      ..crossWestward();
    final laps = detectLaps(path.session(), gatePathGate);
    expect(_issues(laps), [LapReferenceIssue.none, LapReferenceIssue.implausibleLap]);
    expect(laps.fastestLapIndex, 0);
  });

  test('real laps sampled at 1 Hz are plausible', () {
    final path = GatePath(step: 1.0)..points([(30.0, 0.0)]);
    for (var lap = 0; lap < 3; ++lap) {
      path
        ..crossWestward(maximumStepMeters: 40.0)
        ..loopBackEast(maximumStepMeters: 40.0);
    }
    path.crossWestward(maximumStepMeters: 40.0);
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.timedLaps, hasLength(3));
    expect(_issues(laps), everyElement(LapReferenceIssue.none));
  });

  test('a parked hour does not move the median and reject the real lap', () {
    // One real lap, then a "lap" of over an hour of GPS jitter while parked.
    final path = _laps(1)..travel([(-100.0, 0.0), (-100.0, 150.0)]);
    for (var index = 0; index < 20000; ++index) {
      path.points([(-100.0 + (index.isEven ? 2.0 : -2.0), 150.0)]);
    }
    path
      ..travel([(100.0, 150.0), (100.0, 0.0), (30.0, 0.0)])
      ..crossWestward();
    final laps = detectLaps(path.session(), gatePathGate);
    expect(_issues(laps), [LapReferenceIssue.none, LapReferenceIssue.implausibleLap]);
    expect(laps.fastestLapIndex, 0);
  });

  test('across the day, one session\'s single short lap is never the best of the day', () {
    DayRunInput run(String id, GatePath path) {
      final session = path.session();
      return DayRunInput(
        runId: id,
        name: id,
        contentSha256: id.padRight(64, '0'),
        session: session,
        laps: deriveSourceLapSession(session),
        layoutName: 'X',
        direction: TrackDirection.clockwise,
      );
    }

    // Session 2: one 360 m loop over the line, about 10 s: plausible on its
    // own, half the circuit's typical lap.
    final short = GatePath()..points([(30.0, 0.0)]);
    short
      ..crossWestward()
      ..travel([(-60.0, 0.0), (-60.0, 60.0), (60.0, 60.0), (60.0, 0.0), (30.0, 0.0)])
      ..crossWestward();
    final day = analyzeDay([run('a', _laps(3)), run('b', short)]);
    final shortRow = day.rows.firstWhere(
      (row) => row.runId == 'b' && row.type == LapSectionType.lap,
    );
    expect(shortRow.referenceIssue, LapReferenceIssue.none);
    expect(shortRow.shortForGroup, isTrue);
    final ranking = day.chosenGroup!.ranking!;
    expect(ranking.bestOfDay!.runId, 'a');
    expect(ranking.eligibleLapCount, 3);
    final excluded = ranking.excludedLaps.singleWhere((lap) => lap.row.runId == 'b');
    expect(excluded.issues, contains(LapIssue.implausibleLap));
    expect(dayLapIssues(shortRow, day.configurations['b']!), contains(LapIssue.implausibleLap));
  });

  test('one plausible lap alone is ranked', () {
    final laps = detectLaps(_laps(1).session(), gatePathGate);
    expect(laps.timedLaps.single.referenceIssue, LapReferenceIssue.none);
    expect(laps.fastestLapIndex, 0);
  });

  test('a much slower lap of the same length stays plausible', () {
    // A lap at half speed (a cool-down or a wet lap) is still a lap.
    final path = _laps(2)
      ..loopBackEast(maximumStepMeters: 3.0)
      ..crossWestward(maximumStepMeters: 3.0);
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.timedLaps, hasLength(3));
    expect(laps.timedLaps[2].durationSeconds, greaterThan(laps.timedLaps[0].durationSeconds * 2));
    expect(_issues(laps), everyElement(LapReferenceIssue.none));
  });

  test('a GPS issue is kept as the reason before plausibility', () {
    final path = _laps(2)
      ..travel([(-30.0, 30.0), (30.0, 30.0), (30.0, 0.0)])
      ..crossWestward();
    // An invalid fix inside the tiny last lap.
    path.east[path.east.length - 12] = double.nan;
    final session = path.session();
    final laps = detectLaps(session, gatePathGate);
    expect(laps.timedLaps.last.referenceIssue, LapReferenceIssue.invalidGps);
  });

  test('day ranking leaves an implausible lap out with its reason', () {
    expect(
      lapCompatibilityIssues(const TrackConfiguration(), issue: LapReferenceIssue.implausibleLap),
      contains(LapIssue.implausibleLap),
    );
  });

  test('invariant: the best lap is always plausible and every delta is to it', () {
    for (var extra = 0; extra < 4; ++extra) {
      final path = _laps(2 + extra)
        ..travel([(-30.0, 30.0), (30.0, 30.0), (30.0, 0.0)])
        ..crossWestward();
      final laps = detectLaps(path.session(), gatePathGate);
      final best = laps.timedLaps[laps.fastestLapIndex!];
      expect(best.referenceEligible, isTrue);
      for (final lap in laps.timedLaps) {
        if (!lap.referenceEligible) continue;
        expect(lap.durationSeconds, greaterThanOrEqualTo(best.durationSeconds));
        expect(lap.deltaToBestSeconds, closeTo(lap.durationSeconds - best.durationSeconds, 1e-9));
      }
    }
  });
}
