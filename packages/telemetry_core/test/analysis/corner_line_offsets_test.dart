// The line where a corner starts and ends (FET-225), on laps whose line is
// moved sideways by a known amount.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

GeoCoordinate _origin(TimingGate gate) => GeoCoordinate(
  (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
  (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
);

ApprovedSegmentation _corner(double start, double end) => ApprovedSegmentation(
  trackConfigurationReference: 'x',
  valid: true,
  segments: [
    {
      'id': 'c',
      'name': 'C',
      'type': 'corner',
      'startProgressMeters': start,
      'endProgressMeters': end,
    },
  ],
);

// [session] without any fix from [from] to [to] seconds.
TelemetrySession _withGap(TelemetrySession session, double from, double to) {
  TelemetryChannel cut(TelemetryChannel channel) {
    final times = <double>[], values = <double>[];
    for (var i = 0; i < channel.timestamps.length; i++) {
      if (channel.timestamps[i] >= from && channel.timestamps[i] <= to) continue;
      times.add(channel.timestamps[i]);
      values.add(channel.values[i]);
    }
    return TelemetryChannel(
      name: channel.name,
      timestamps: Float64List.fromList(times),
      values: Float32List.fromList(values),
    );
  }

  return TelemetrySession(
    duration: session.duration,
    startTime: 0,
    metadata: session.metadata,
    channels: {for (final entry in session.channels.entries) entry.key: cut(entry.value)},
    aliases: session.aliases,
    warnings: const [],
    timingGates: session.timingGates,
    sampleCount: session.sampleCount,
  );
}

void main() {
  // Each lap's line moved out (or in) by its own amount, fading to none at
  // the gate so every lap crosses it the same way.
  const shift = [0.0, 0.0, 2.0, -2.0, 4.0, 1.0];
  final session = circuitSession(
    speeds: [for (final _ in shift) 30.0],
    radiusOf: (lap, angle) => 100 + shift[lap] * math.pow(math.sin((angle - 0.25) / 2), 2),
  );
  final laps = deriveSourceLapSession(session);
  final gate = laps.selectedStartGate!;
  final axis = buildProgressAxis(laps.lapTraces.first, _origin(gate), gate);
  final features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
  final length = axis.lengthMeters;

  List<CornerLapObservation> measure(double start, double end, [TelemetrySession? recording]) {
    final source = recording ?? session;
    return [
      for (final lap in laps.lapTraces)
        () {
          final lapEnd = lap.startTelemetryTime + lap.durationSeconds;
          final trace = projectLapTrace(axis, source, lap.startTelemetryTime, lapEnd);
          return measureCornerLap(
            axis,
            features,
            _corner(start, end),
            'c',
            start,
            end,
            trace,
            source,
            lap.startTelemetryTime,
            lapEnd,
            lap.lapNumber,
          ).observation;
        }(),
    ];
  }

  // How far a lap's line is from the circle's centre where it passes
  // [progress].
  double radiusAt(int index, double progress) {
    final lap = laps.lapTraces[index];
    final trace = projectLapTrace(
      axis,
      session,
      lap.startTelemetryTime,
      lap.startTelemetryTime + lap.durationSeconds,
    );
    final time = timeAtProgress(trace, progress)!;
    final point = projectCoordinate(
      GeoCoordinate(session.valueAt('latitude', time)!, session.valueAt('longitude', time)!),
      axis.origin,
    );
    // The circle's centre is 100 m west of the gate.
    final east = point.eastMeters + 100;
    return math.sqrt(east * east + point.northMeters * point.northMeters);
  }

  test("each lap's line where the corner starts and ends is its sideways shift", () {
    final start = length * 0.25, end = length * 0.75;
    final observations = measure(start, end);
    expect(observations, hasLength(shift.length));
    for (final (index, observation) in observations.indexed) {
      // Outwards on this anticlockwise circle is to the right: negative.
      expect(
        observation.entryLineOffsetMeters,
        closeTo(radiusAt(0, start) - radiusAt(index, start), 0.02),
        reason: 'lap ${index + 1} entry',
      );
      expect(
        observation.exitLineOffsetMeters,
        closeTo(radiusAt(0, end) - radiusAt(index, end), 0.02),
        reason: 'lap ${index + 1} exit',
      );
    }
    // Moved laps differ from the reference lap, and the ends from each other.
    expect(observations[4].entryLineOffsetMeters, lessThan(-1));
    expect(observations[3].exitLineOffsetMeters, greaterThan(1));
    final variability = summarizeCornerVariability('c', 'C', observations);
    expect(variability.entryLineOffset.count, shift.length);
    expect(variability.exitLineOffset.count, shift.length);
  });

  test('a corner at the timing gate is measured where each lap starts and ends', () {
    for (final observation in measure(0, length)) {
      expect(observation.entryLineOffsetMeters, isNotNull);
      expect(observation.entryLineOffsetMeters!.abs(), lessThan(0.5));
      expect(observation.exitLineOffsetMeters, isNotNull);
      expect(observation.exitLineOffsetMeters!.abs(), lessThan(0.5));
    }
  });

  test('a boundary off the track is no data', () {
    for (final observation in measure(-20, length + 20)) {
      expect(observation.entryLineOffsetMeters, isNull);
      expect(observation.exitLineOffsetMeters, isNull);
    }
  });

  test('a corner across start/finish has both ends on every lap', () {
    for (final observation in measure(length * 0.85, length * 0.15)) {
      expect(observation.entryLineOffsetMeters?.isFinite, isTrue);
      expect(observation.exitLineOffsetMeters?.isFinite, isTrue);
    }
  });

  test('a gap where the corner starts leaves that lap without its entry', () {
    final lap = laps.lapTraces[1];
    final from = lap.startTelemetryTime + lap.durationSeconds * 0.20;
    final observations = measure(length * 0.25, length * 0.75, _withGap(session, from, from + 3));
    expect(observations[1].entryLineOffsetMeters, isNull);
    expect(observations[1].exitLineOffsetMeters, isNotNull);
    expect(observations[0].entryLineOffsetMeters, isNotNull);
  });
}
