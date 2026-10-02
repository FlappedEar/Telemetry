import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';
import '../support/sessions.dart';

/// The progress axis of the first lap of [session], around the gate midpoint.
ProgressAxis _axisOf(TelemetrySession session) {
  final laps = deriveSourceLapSession(session);
  final gate = laps.selectedStartGate!;
  return buildProgressAxis(laps.lapTraces.first, _origin(gate), gate);
}

GeoCoordinate _origin(TimingGate gate) => GeoCoordinate(
  (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
  (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
);

TelemetrySession _channelSession(List<double> times, List<double> values) => TelemetrySession(
  duration: times.last,
  startTime: 0,
  metadata: const {},
  channels: {
    'value': TelemetryChannel(
      name: 'value',
      timestamps: Float64List.fromList(times),
      values: Float32List.fromList(values),
    ),
  },
  aliases: const {'alias': 'value'},
  warnings: const [],
  timingGates: const [],
  sampleCount: times.length,
);

void main() {
  group('sampledSegments', () {
    final times = [for (var i = 0; i < 100; ++i) i * 0.1];

    test('keeps every sample when the range has room for them', () {
      final session = _channelSession(times, [for (var i = 0; i < 100; ++i) i.toDouble()]);
      final segments = session.sampledSegments('alias', 0.0, 9.9, 1000);
      expect(segments, hasLength(1));
      expect(segments.single.map((p) => p.value), [for (var i = 0; i < 100; ++i) i]);
      expect(session.sampledSegments('value', 9.9, 0.0, 1000).single, hasLength(100));
    });

    test('splits at missing values and at gaps, never bridging them', () {
      final values = [for (var i = 0; i < 100; ++i) i == 30 ? double.nan : 1.0];
      final gapped = [for (var i = 0; i < 100; ++i) i < 60 ? times[i] : times[i] + 5.0];
      final segments = _channelSession(gapped, values).sampledSegments('value', 0.0, 20.0, 1000);
      expect(segments.map((s) => s.length).toList(), [30, 29, 40]);
    });

    test('reduces each bucket to its ordered minimum and maximum', () {
      final values = [for (var i = 0; i < 100; ++i) i == 37 ? 50.0 : (i == 73 ? -50.0 : 0.0)];
      final segments = _channelSession(times, values).sampledSegments('value', 0.0, 10.0, 10);
      final points = segments.single;
      expect(points.length, lessThanOrEqualTo(20));
      expect(points.map((p) => p.value), containsAll([50.0, -50.0]));
      for (var i = 1; i < points.length; ++i) {
        expect(points[i].time, greaterThan(points[i - 1].time));
      }
    });

    test('thins to the point budget while keeping the extremes', () {
      final many = [for (var i = 0; i < 1000; ++i) i * 0.1];
      final values = Float32List.fromList([
        // A missing value every 7th sample: many short segments, each keeping
        // its own bucket extremes, overflow the budget.
        for (var i = 0; i < 1000; ++i)
          i % 7 == 3 ? double.nan : math.sin(i * 0.7) * (i == 501 ? 9 : 1),
      ]);
      final segments = _channelSession(many, values).sampledSegments('value', 0.0, 99.9, 50);
      final points = segments.expand((s) => s).toList();
      expect(points.length, lessThanOrEqualTo(100));
      expect(segments.length, lessThan(143));
      final finite = values.where((v) => v.isFinite);
      expect(points.map((p) => p.value), contains(finite.reduce(math.max)));
      expect(points.map((p) => p.value), contains(finite.reduce(math.min)));
    });

    test('is empty for an invalid range or a missing channel', () {
      final session = _channelSession(times, List.filled(100, 1.0));
      expect(session.sampledSegments('value', 0.0, double.nan, 10), isEmpty);
      expect(session.sampledSegments('value', 0.0, 1.0, 1), isEmpty);
      expect(session.sampledSegments('value', -double.maxFinite, double.maxFinite, 10), isEmpty);
      expect(session.sampledSegments('missing', 0.0, 1.0, 10), isEmpty);
      expect(session.sampledSegments('value', 50.0, 60.0, 10), isEmpty);
    });
  });

  group('buildProgressAxis', () {
    final axis = _axisOf(circuitSession());

    test('spans the circumference in ~2 m steps', () {
      expect(axis.valid, isTrue);
      expect(axis.lengthMeters, closeTo(2 * math.pi * 100, 3.0));
      expect(axis.points, hasLength((axis.lengthMeters / 2).round()));
      expect(axis.spacingMeters, closeTo(2.0, 0.01));
      expect(axis.cumulative.first, 0.0);
      expect(axis.cumulative.last, lessThan(axis.lengthMeters));
    });

    test('puts progress 0 at the timing gate', () {
      final start = axis.points.first;
      expect(
        math.sqrt(start.eastMeters * start.eastMeters + start.northMeters * start.northMeters),
        lessThan(axis.spacingMeters),
      );
    });

    test('rejects a trace too short to be a lap', () {
      final gate = circuitGate();
      final trace = LapTrace(
        lapNumber: 1,
        startTelemetryTime: 0,
        durationSeconds: 1,
        points: [for (var i = 0; i < 11; ++i) LapTracePoint(i.toDouble(), i * 10.0, 0)],
      );
      expect(buildProgressAxis(trace, _origin(gate), gate).valid, isFalse);
    });

    test('stops when cancelled', () {
      final laps = deriveSourceLapSession(circuitSession());
      final gate = laps.selectedStartGate!;
      expect(
        () => buildProgressAxis(laps.lapTraces.first, _origin(gate), gate, cancelled: () => true),
        throwsA(isA<OperationCancelled>()),
      );
    });
  });

  test('computeTrackFeatures gives a constant left curvature on a counterclockwise circle', () {
    final axis = _axisOf(circuitSession());
    final features = computeTrackFeatures(axis, 15.0);
    expect(features.valid, isTrue);
    expect(features.samples, hasLength(axis.points.length));
    final mean =
        features.samples.map((s) => s.curvaturePerMeter).reduce((a, b) => a + b) /
        features.samples.length;
    expect(mean, closeTo(1 / 100, 1e-3));
    expect(computeTrackFeatures(axis, 0.0).valid, isFalse);
    expect(computeTrackFeatures(const ProgressAxis(), 15.0).valid, isFalse);
  });

  group('projectLapTrace', () {
    final session = circuitSession();
    final laps = deriveSourceLapSession(session);
    final axis = _axisOf(session);

    test('projects a clean lap as one segment of increasing progress', () {
      final lap = laps.timedLaps[1];
      final segments = projectLapTrace(axis, session, lap.startTelemetryTime, lap.endTelemetryTime);
      expect(segments, hasLength(1));
      final samples = segments.single.samples;
      expect(samples.first.progressMeters, closeTo(0.0, 3.0));
      expect(samples.last.progressMeters, closeTo(axis.lengthMeters, 3.0));
      for (var i = 1; i < samples.length; ++i) {
        expect(samples[i].telemetryTime, greaterThan(samples[i - 1].telemetryTime));
        expect(samples[i].progressMeters, greaterThan(samples[i - 1].progressMeters));
      }
      expect(timeAtProgress(segments, 10.0), isNotNull);
      final halfway = timeAtProgress(segments, axis.lengthMeters / 2)!;
      expect(progressAtTime(segments, halfway), closeTo(axis.lengthMeters / 2, 1e-6));
      expect(progressAtTime(segments, lap.endTelemetryTime + 10), isNull);
    });

    test('ends a segment at a GPS gap', () {
      final lap = laps.timedLaps[1];
      final gapStart = lap.startTelemetryTime + 5.0;
      final gapped = editGps(session, (latTimes, latValues, lonTimes, lonValues) {
        for (final (times, values) in [(latTimes, latValues), (lonTimes, lonValues)]) {
          for (var i = times.length - 1; i >= 0; --i) {
            if (times[i] > gapStart && times[i] < gapStart + 2.0) {
              times.removeAt(i);
              values.removeAt(i);
            }
          }
        }
      });
      final segments = projectLapTrace(axis, gapped, lap.startTelemetryTime, lap.endTelemetryTime);
      expect(segments, hasLength(2));
      expect(segments[0].samples.last.telemetryTime, lessThanOrEqualTo(gapStart));
      expect(segments[1].samples.first.telemetryTime, greaterThanOrEqualTo(gapStart + 2.0));
      // Nothing is invented across the gap.
      final missing =
          (segments[0].samples.last.progressMeters + segments[1].samples.first.progressMeters) / 2;
      expect(timeAtProgress(segments, missing), isNull);
    });

    test('never locks on to the same path driven the opposite way', () {
      final reversed = circuitSession(clockwise: true);
      final segments = projectLapTrace(axis, reversed, 0.0, reversed.duration);
      // Only cold-start fixes without a direction yet can be placed; the next
      // fix's heading disagrees and ends the segment.
      expect(segments, isNotEmpty);
      for (final segment in segments) {
        expect(segment.samples, hasLength(1));
      }
    });

    test('stops when cancelled', () {
      expect(
        () => projectLapTrace(axis, session, 0.0, session.duration, cancelled: () => true),
        throwsA(isA<OperationCancelled>()),
      );
    });
  });

  group('projectSample', () {
    final axis = _axisOf(circuitSession());
    final onAxis = axis.points[40];
    final next = axis.points[41];
    final forward = (next.eastMeters - onAxis.eastMeters, next.northMeters - onAxis.northMeters);

    test('locks on to a point moving with the axis', () {
      final context = ProjectionContext();
      final sample = projectSample(axis, onAxis, 1.0, 30.0, forward, context);
      expect(sample.valid, isTrue);
      expect(sample.progressMeters, closeTo(axis.cumulative[40], 1e-9));
      expect(context.hasLock, isTrue);
      expect(context.lastTelemetryTime, 1.0);
    });

    test('rejects a point moving against the axis', () {
      final context = ProjectionContext();
      final sample = projectSample(axis, onAxis, 1.0, 30.0, (-forward.$1, -forward.$2), context);
      expect(sample.valid, isFalse);
      expect(context.hasLock, isFalse);
    });

    test('rejects a point far from the track and a backward jump', () {
      final context = ProjectionContext();
      expect(
        projectSample(axis, const MetricPoint(500, 500), 1.0, 30.0, forward, context).valid,
        isFalse,
      );
      expect(projectSample(axis, axis.points[40], 1.0, 30.0, forward, context).valid, isTrue);
      expect(projectSample(axis, axis.points[35], 1.1, 30.0, (0.0, 0.0), context).valid, isFalse);
      expect(context.lastProgressMeters, closeTo(axis.cumulative[40], 1e-9));
    });
  });

  group('computeDeltaSeries', () {
    final session = circuitSession(speeds: const [30.0, 25.0, 30.0]);
    final laps = deriveSourceLapSession(session);
    final axis = _axisOf(session);
    List<ProgressSegment> project(TimedLap lap) =>
        projectLapTrace(axis, session, lap.startTelemetryTime, lap.endTelemetryTime);

    test('is zero for identical laps', () {
      final lap = project(laps.timedLaps[0]);
      final series = computeDeltaSeries(lap, lap, 5.0);
      expect(series, hasLength(1));
      expect(series.single.first.progressMeters, closeTo(0.0, 5.0));
      for (final point in series.single) {
        expect(point.deltaSeconds, 0.0);
      }
    });

    test('grows toward the lap-time difference for a slower lap', () {
      final slow = project(laps.timedLaps[1]);
      final fast = project(laps.timedLaps[0]);
      final series = computeDeltaSeries(slow, fast, 5.0);
      final expected = laps.timedLaps[1].durationSeconds - laps.timedLaps[0].durationSeconds;
      expect(series.last.last.deltaSeconds, closeTo(expected, 0.3));
      expect(series.first[series.first.length ~/ 2].deltaSeconds, closeTo(expected / 2, 0.3));
    });

    test('is empty without coverage or with a bad step', () {
      final lap = project(laps.timedLaps[0]);
      expect(computeDeltaSeries(lap, const [], 5.0), isEmpty);
      expect(computeDeltaSeries(lap, lap, 0.0), isEmpty);
      expect(timeAtProgress(const [], 0.0), isNull);
      expect(progressAtTime(const [], 0.0), isNull);
    });
  });
}
