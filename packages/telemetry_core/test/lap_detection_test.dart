import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'support/sessions.dart';

const _startGate = TimingGate(
  type: TimingGateType.start,
  sourceName: 'Start',
  endpointA: GeoCoordinate(52.0, 21.0),
  endpointB: GeoCoordinate(52.0002, 21.0),
);
const _mid = 52.0001;
const _north = 52.0008;
const _east = 21.0002;
const _west = 20.9998;

void main() {
  test('derives directional passes and complete laps', () {
    final laps = gpsSession(
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15],
      [
        _mid,
        _mid,
        _mid,
        _north,
        _north,
        _mid,
        _mid,
        _north,
        _north,
        _mid,
        _mid,
        _north,
        _north,
        _mid,
        _mid,
      ],
      [
        _east,
        _east,
        _west,
        _west,
        _east,
        _east,
        _west,
        _west,
        _east,
        _east,
        _west,
        _west,
        _east,
        _east,
        _west,
      ],
    );
    final detected = detectLaps(laps, _startGate);
    expect(detected.status, LapSessionStatus.available);
    expect(detected.acceptedPasses, hasLength(4));
    expect(detected.timedLaps.map((lap) => lap.durationSeconds), [
      closeTo(4.0, 0.001),
      closeTo(5.0, 0.001),
      closeTo(4.0, 0.001),
    ]);
    expect(detected.fastestLapIndex, 0);
    expect(detected.timedLaps[1].deltaToBestSeconds, closeTo(1.0, 0.001));

    final reverseCrossing = gpsSession(
      [0, 1, 2, 3, 4, 5, 6],
      [_mid, _mid, _mid, _north, _mid, _mid, _north],
      [_east, _east, _west, _west, _west, _east, _east],
    );
    final directional = detectLaps(reverseCrossing, _startGate);
    expect(directional.acceptedPasses, hasLength(1));
    expect(directional.diagnostics.rejectedOppositeDirectionClusters, 1);
  });

  test('takes the direction most passes cross in, not the first one (FET-206)', () {
    // One pass west to east (a pit or reverse manoeuvre), then four laps
    // crossing east to west.
    final session = gpsSession(
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20],
      [
        _north,
        _mid,
        _mid,
        _north,
        _mid,
        _mid,
        _north,
        _north,
        _mid,
        _mid,
        _north,
        _north,
        _mid,
        _mid,
        _north,
        _north,
        _mid,
        _mid,
        _north,
        _north,
      ],
      [
        _west,
        _west,
        _east,
        _east,
        _east,
        _west,
        _west,
        _east,
        _east,
        _west,
        _west,
        _east,
        _east,
        _west,
        _west,
        _east,
        _east,
        _west,
        _west,
        _west,
      ],
    );
    final detected = detectLaps(session, _startGate);
    expect(detected.status, LapSessionStatus.available);
    expect(detected.acceptedPasses.map((pass) => pass.direction).toSet(), hasLength(1));
    expect(detected.acceptedPasses.map((pass) => pass.telemetryTime), [
      closeTo(4.5, 0.001),
      closeTo(8.5, 0.001),
      closeTo(13.5, 0.001),
      closeTo(17.5, 0.001),
    ]);
    expect(detected.diagnostics.rejectedOppositeDirectionClusters, 1);
    expect(detected.timedLaps.map((lap) => lap.durationSeconds), [
      closeTo(4.0, 0.001),
      closeTo(5.0, 0.001),
      closeTo(4.0, 0.001),
    ]);

    // With as many passes each way, the faster ones decide: two slow passes
    // west to east (out of the pits and back), then two laps east to west.
    final slowFirst = gpsSession(
      [0, 1, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16],
      [
        _north,
        _mid,
        _mid,
        _north,
        _north,
        _mid,
        _mid,
        _north,
        _mid,
        _mid,
        _north,
        _north,
        _mid,
        _mid,
        _north,
      ],
      [
        _west,
        _west,
        _east,
        _east,
        _west,
        _west,
        _east,
        _east,
        _east,
        _west,
        _west,
        _east,
        _east,
        _west,
        _west,
      ],
    );
    final faster = detectLaps(slowFirst, _startGate);
    expect(faster.acceptedPasses.map((pass) => pass.telemetryTime), [
      closeTo(10.5, 0.001),
      closeTo(14.5, 0.001),
    ]);
    expect(faster.diagnostics.rejectedOppositeDirectionClusters, 2);
    expect(faster.timedLaps.single.durationSeconds, closeTo(4.0, 0.001));

    // As many passes each way at the same speed: the first direction stays.
    final tie = gpsSession([0, 1, 2, 3, 4, 5], [_north, _mid, _mid, _north, _mid, _mid], [
      _west,
      _west,
      _east,
      _east,
      _east,
      _west,
    ]);
    final tied = detectLaps(tie, _startGate);
    expect(tied.acceptedPasses, hasLength(1));
    expect(tied.acceptedPasses.single.telemetryTime, closeTo(1.5, 0.001));
    expect(tied.diagnostics.rejectedOppositeDirectionClusters, 1);
  });

  test('detects passes under the same GPS gap rule that judges laps (FET-212)', () {
    // A crossing over a 2 s step: within the latitude's 1 Hz cadence (gap
    // 3 s), beyond the longitude's own 2 Hz one (gap 1.5 s).
    final crossing = gpsSession([0, 1, 3, 4], [_north, _mid, _mid, _north], [
      _east,
      _east,
      _west,
      _west,
    ]);
    expect(detectLaps(crossing, _startGate).acceptedPasses, hasLength(1));
    final denseLongitude = gpsSession(
      [0, 1, 3, 4],
      [_north, _mid, _mid, _north],
      [_east, _east, _west, _west, for (var i = 0; i < 8; ++i) _west],
      longitudeTimes: [0, 1, 3, 4, for (var i = 1; i <= 8; ++i) 4 + i / 2],
    );
    final latitude = denseLongitude.channels['latitude']!;
    final longitude = denseLongitude.channels['longitude']!;
    expect(gpsGapThreshold(latitude, longitude), closeTo(1.5, 1e-9));
    expect(gpsGapThreshold(longitude, latitude), closeTo(1.5, 1e-9));
    expect(detectLaps(denseLongitude, _startGate).acceptedPasses, isEmpty);
  });

  test('finalizes a pass when the recording ends inside the corridor', () {
    final session = gpsSession([0, 1, 2], [_mid, _mid, _mid], [_east, _east, 21.0]);
    final result = detectLaps(session, _startGate);
    expect(result.status, LapSessionStatus.insufficientPasses);
    expect(result.acceptedPasses, hasLength(1));
    expect(result.acceptedPasses.single.telemetryTime, closeTo(2.0, 0.001));
  });

  test('reports why no laps exist', () {
    final session = parse(fixture('event-laps.vbo'));
    final noGate = TelemetrySession(
      duration: session.duration,
      startTime: 0,
      metadata: const {},
      channels: session.channels,
      aliases: session.aliases,
      warnings: const [],
      timingGates: const [],
      sampleCount: session.sampleCount,
    );
    expect(deriveSourceLapSession(noGate).status, LapSessionStatus.noSourceStartGate);
    final twoGates = gpsSession(
      [0, 1],
      [_mid, _mid],
      [_east, _west],
      gates: [_startGate, _startGate],
    );
    expect(deriveSourceLapSession(twoGates).status, LapSessionStatus.ambiguousSourceStartGate);
    const tooLong = TimingGate(
      type: TimingGateType.start,
      sourceName: 'Start',
      endpointA: GeoCoordinate(52.0, 21.0),
      endpointB: GeoCoordinate(52.01, 21.0),
    );
    expect(detectLaps(session, tooLong).status, LapSessionStatus.invalidGate);
    final noGps = gpsSession([0], [_mid], [_east]);
    expect(detectLaps(noGps, _startGate).status, LapSessionStatus.noUsableGps);
  });

  test('validates options', () {
    final session = parse(fixture('event-laps.vbo'));
    for (final options in [
      const LapDetectionOptions(innerCorridorMeters: 10, outerCorridorMeters: 10),
      const LapDetectionOptions(minimumNormalMotionRatio: 1.5),
      const LapDetectionOptions(refractorySeconds: double.nan),
      const LapDetectionOptions(maximumAcceptedPasses: 0),
      const LapDetectionOptions(maximumGateLengthMeters: 0.5),
    ]) {
      expect(() => detectLaps(session, _startGate, options: options), throwsArgumentError);
    }
  });
}
