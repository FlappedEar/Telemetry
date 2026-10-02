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
