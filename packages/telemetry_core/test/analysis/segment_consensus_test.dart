import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

// FET-214: the best lap's segment proposals are adopted only when its GPS
// line agrees with the other eligible laps.

double Function(double) _speed(double metresPerSecond) =>
    (_) => metresPerSecond;

// Moved [metres] west between 400 and 470 m into the lap: a GPS line off the
// others there (a glitch, or a lap off the track).
double Function(double) _offLine(double metres) =>
    (d) => d >= 400 && d <= 470 ? metres : 0.0;
double _onLine(double _) => 0.0;

const _speeds = [28.0, 32.0, 29.0, 30.0];

// The best lap's axis and the traces of the run's other laps.
({ProgressAxis axis, List<LapTrace> others}) _laps(List<double Function(double)> westShifts) {
  final session = rectangleSession([for (final s in _speeds) _speed(s)], westShifts: westShifts);
  final laps = deriveSourceLapSession(session);
  final best = laps.timedLaps[laps.fastestLapIndex!];
  expect(best.number, laps.timedLaps[1].number);
  final review = computeSegmentReview(
    session,
    laps,
    lapNumber: best.number,
    startTime: best.startTelemetryTime,
    endTime: best.endTelemetryTime,
  );
  expect(review.proposals.proposals, isNotEmpty);
  return (
    axis: review.axis,
    others: [
      for (final trace in laps.lapTraces)
        if (trace.lapNumber != best.number) trace,
    ],
  );
}

DayRunInput _input(TelemetrySession session) => DayRunInput(
  runId: 'run1',
  name: 'Session 1',
  contentSha256: 'b' * 64,
  session: session,
  laps: deriveSourceLapSession(session),
  // A track chosen by hand: the day keeps laps off the line (KAN-137 drops
  // them only on detected routes), so only this check stops them.
  layoutName: 'Test circuit',
  direction: TrackDirection.counterclockwise,
);

DayTheoreticalBest _best(DayAnalysis day, DayRunInput run) =>
    dayTheoreticalBest(day, {'run1': OutingRun(run.session, run.laps)}, random: Random(1));

// [session] as RaceChrono writes a VBO: longitudes west-positive.
TelemetrySession _westPositive(TelemetrySession session) {
  GeoCoordinate flip(GeoCoordinate c) => GeoCoordinate(c.latitudeDegrees, -c.longitudeDegrees);
  final longitude = session.channels['longitude']!;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: {...session.metadata, 'gpsLongitudeConvention': 'west-positive'},
    channels: {
      ...session.channels,
      'longitude': TelemetryChannel(
        name: 'longitude',
        timestamps: longitude.timestamps,
        values: Float32List.fromList([for (final v in longitude.values) -v]),
      ),
    },
    aliases: session.aliases,
    warnings: session.warnings,
    timingGates: [
      for (final gate in session.timingGates)
        TimingGate(
          type: gate.type,
          sourceName: gate.sourceName,
          endpointA: flip(gate.endpointA),
          endpointB: flip(gate.endpointB),
          sourceDescription: gate.sourceDescription,
        ),
    ],
    sampleCount: session.sampleCount,
  );
}

void main() {
  test('a best lap off the others\' line disagrees', () {
    final laps = _laps([_onLine, _offLine(50), _onLine, _onLine]);
    final consensus = lineConsensus(laps.axis, laps.others);
    expect(consensus.checkedLaps, 3);
    expect(consensus.worstDistanceMeters, greaterThan(segmentConsensusMaximumMeters));
    expect(consensus.worstProgressMeters, inInclusiveRange(380, 490));
    expect(consensus.disagrees, isTrue);
  });

  test('a best lap on another line within the track agrees', () {
    final laps = _laps([_onLine, _offLine(12), _onLine, _onLine]);
    final consensus = lineConsensus(laps.axis, laps.others);
    expect(consensus.worstDistanceMeters, closeTo(12, 1.0));
    expect(consensus.disagrees, isFalse);
  });

  test('other laps off the line outvote the best lap only as a majority', () {
    // One of three other laps off the line: the best lap agrees.
    var laps = _laps([_offLine(50), _onLine, _onLine, _onLine]);
    expect(lineConsensus(laps.axis, laps.others).worstDistanceMeters, lessThan(1.0));
    // One of two: still agrees (half is not a majority).
    laps = _laps([_offLine(80), _onLine, _onLine]);
    expect(lineConsensus(laps.axis, laps.others).disagrees, isFalse);
    // Two of three: the lines disagree.
    laps = _laps([_offLine(80), _onLine, _offLine(80), _onLine]);
    expect(lineConsensus(laps.axis, laps.others).disagrees, isTrue);
  });

  test('with one other lap the line is not checked, as Overlays does', () {
    final laps = _laps([_onLine, _offLine(50)]);
    final consensus = lineConsensus(laps.axis, laps.others.take(1).toList());
    expect(consensus.checked, isFalse);
    expect(consensus.disagrees, isFalse);
  });

  test('a day says why there is no theoretical best', () {
    final run = _input(
      rectangleSession(
        [for (final s in _speeds) _speed(s)],
        westShifts: [_onLine, _offLine(50), _onLine, _onLine],
      ),
    );
    final day = analyzeDay([run]);
    expect(day.chosenGroup!.ranking!.bestOfDay!.lapNumber, 2);
    final result = _best(day, run);
    expect(result.state, DayTheoreticalBestState.unavailable);
    expect(result.message, automaticSegmentsLineDisagreement);
    expect(result.automaticSegments, isFalse);
    // Saving the day adopts nothing either.
    expect(
      automaticTrackSegments(
        documentRuns: const [],
        groupId: day.chosenGroup!.id,
        storedSegments: null,
        session: run.session,
        laps: run.laps,
        lapNumber: 2,
        startTime: day.chosenGroup!.ranking!.bestOfDay!.start,
        endTime: day.chosenGroup!.ranking!.bestOfDay!.end,
        otherLaps: otherEligibleLapTraces(
          day.chosenGroup!.ranking!,
          day.chosenGroup!.ranking!.bestOfDay!,
          {'run1': (run.session, run.laps)},
        ),
        random: Random(1),
      ),
      isNull,
    );

    // On the line, the same day has its theoretical best.
    final good = _input(rectangleSession([for (final s in _speeds) _speed(s)]));
    final ready = _best(analyzeDay([good]), good);
    expect(ready.state, DayTheoreticalBestState.ready);
    expect(ready.automaticSegments, isTrue);
  });

  test('excluding the laps whose line is wrong lets the best lap\'s segments in', () {
    // The best lap is right; laps 3 and 4 are off the line.
    final run = _input(
      rectangleSession(
        [for (final s in _speeds) _speed(s)],
        westShifts: [_onLine, _onLine, _offLine(50), _offLine(50)],
      ),
    );
    var day = analyzeDay([run]);
    expect(_best(day, run).message, automaticSegmentsLineDisagreement);
    // Excluded laps are not compared.
    day = analyzeDay(
      [run],
      exclusions: {
        for (final row in day.rows)
          if (row.lapNumber == 3 || row.lapNumber == 4) row.reference: 'GPS',
      },
    );
    final result = _best(day, run);
    expect(result.state, DayTheoreticalBestState.ready);
    expect(result.automaticSegments, isTrue);
  });

  test('a detected route already drops a lap off the line from the ranking (KAN-137)', () {
    final session = rectangleSession(
      [for (final s in _speeds) _speed(s)],
      westShifts: [_onLine, _offLine(50), _onLine, _onLine],
    );
    final run = DayRunInput(
      runId: 'run1',
      name: 'Session 1',
      contentSha256: 'b' * 64,
      session: session,
      laps: deriveSourceLapSession(session),
    );
    final day = analyzeDay([run]);
    expect(day.chosenGroup!.ranking!.bestOfDay!.lapNumber, 4);
    final result = _best(day, run);
    expect(result.state, DayTheoreticalBestState.ready);
    expect(result.automaticSegments, isTrue);
  });
  test('compares a west-positive VBO with an east-positive recording in one frame', () {
    DayRunInput input(String id, TelemetrySession session) => DayRunInput(
      runId: id,
      name: id,
      contentSha256: id.substring(id.length - 1) * 64,
      session: session,
      laps: deriveSourceLapSession(session),
    );
    // The best lap is in the west-positive run; most other laps are not.
    final vbo = input(
      'run1',
      _westPositive(
        rectangleSession([
          for (final s in [28.0, 40.0, 29.0]) _speed(s),
        ]),
      ),
    );
    final rcz = input(
      'run2',
      rectangleSession([
        for (final s in [28.0, 30.0, 29.0]) _speed(s),
      ]),
    );
    final day = analyzeDay([vbo, rcz]);
    final ranking = day.chosenGroup!.ranking!;
    expect(ranking.bestOfDay!.runId, 'run1');
    expect(day.groups.where((group) => group.resolved), hasLength(1));
    final result = dayTheoreticalBest(day, {
      for (final run in [vbo, rcz]) run.runId: OutingRun(run.session, run.laps),
    }, random: Random(1));
    expect(result.state, DayTheoreticalBestState.ready);
    expect(result.automaticSegments, isTrue);
  });
}
