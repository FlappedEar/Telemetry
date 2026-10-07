// FET-251: converting progress (metres along the axis) to an axis point.
// `ProgressAxis.cumulative` adds up the straight lines between the resampled
// points, so it is shorter than `lengthMeters` (the raw path) and the points
// are not `spacingMeters` apart. Dividing progress by `spacingMeters` lands on
// the wrong point, by up to a dozen points near the end of the lap.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart' show TrackSegmentType;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _origin = GeoCoordinate(52.0, 21.0);
const _gate = TimingGate(
  type: TimingGateType.start,
  sourceName: 'test',
  endpointA: _origin,
  endpointB: _origin,
);

double _distance(MetricPoint a, MetricPoint b) => math.sqrt(
  math.pow(a.eastMeters - b.eastMeters, 2) + math.pow(a.northMeters - b.northMeters, 2),
);

// A circle of radius 150 m with a raw point every 2 m that alternates 0.3 m
// outside and inside it, so the raw path is a zigzag. buildProgressAxis
// resamples it every ~2 m of that path, and the straight lines between the
// resampled points are about 26 m shorter than the raw path.
ProgressAxis _zigzagAxis() {
  const radius = 150.0;
  final count = (2 * math.pi * radius / 2.0).round();
  final points = <LapTracePoint>[
    for (var i = 0; i < count; ++i)
      LapTracePoint(
        i * 0.08,
        (radius + (i.isEven ? 0.3 : -0.3)) * math.cos(2 * math.pi * i / count) - radius,
        (radius + (i.isEven ? 0.3 : -0.3)) * math.sin(2 * math.pi * i / count),
      ),
  ];
  return buildProgressAxis(
    LapTrace(lapNumber: 1, startTelemetryTime: 0, durationSeconds: count * 0.08, points: points),
    _origin,
    _gate,
  );
}

double _closingChord(ProgressAxis axis) => _distance(axis.points.last, axis.points.first);

// The circle through the origin with its points 1 m apart over the first
// half and 3 m apart over the second (as 25 Hz fixes at a varying speed are),
// so the mean spacing (1.5 m) is far from the spacing at most points.
ProgressAxis _unevenAxis() {
  const radius = 100.0;
  const length = 2 * math.pi * radius;
  MetricPoint at(double progress) => MetricPoint(
    -radius + radius * math.cos(progress / radius),
    radius * math.sin(progress / radius),
  );
  final points = <MetricPoint>[
    for (var p = 0.0; p < length / 2; p += 1.0) at(p),
    for (var p = length / 2; p < length - 1.5; p += 3.0) at(p),
  ];
  final cumulative = <double>[0.0];
  for (var i = 1; i < points.length; ++i) {
    cumulative.add(cumulative.last + _distance(points[i - 1], points[i]));
  }
  final total = cumulative.last + _distance(points.last, points.first);
  return ProgressAxis(
    points: points,
    cumulative: cumulative,
    lengthMeters: total,
    spacingMeters: total / points.length,
    origin: _origin,
    valid: true,
  );
}

DayTheoreticalBest _best(ProgressAxis axis, List<(double, double)> corners) => DayTheoreticalBest(
  groupId: 'g',
  state: DayTheoreticalBestState.ready,
  computed: OutingTheoreticalBest(axis: axis, axisLengthMeters: axis.lengthMeters),
  corners: [
    for (var i = 0; i < corners.length; ++i)
      DayCorner(
        segmentIndex: i,
        segmentId: 'c$i',
        name: 'Corner $i',
        startProgressMeters: corners[i].$1,
        endProgressMeters: corners[i].$2,
        laps: const [],
      ),
  ],
);

GeoCoordinate _ground(ProgressAxis axis, int index) {
  final point = axis.points[index];
  return unprojectCoordinate(point.eastMeters, point.northMeters, axis.origin);
}

void _expectSamePlace(GeoCoordinate actual, GeoCoordinate expected, String reason) {
  // 1e-6 degrees is about 0.1 m.
  expect(actual.latitudeDegrees, closeTo(expected.latitudeDegrees, 1e-6), reason: reason);
  expect(actual.longitudeDegrees, closeTo(expected.longitudeDegrees, 1e-6), reason: reason);
}

void main() {
  group('lengthMeters against cumulative', () {
    test('the raw path is longer than the resampled chords, by metres', () {
      // Documents the difference FET-251 measured; `lengthMeters` stays the
      // raw path's length because Overlays' reference results depend on it.
      final axis = _zigzagAxis();
      final chords = axis.cumulative.last + _closingChord(axis);
      expect(axis.lengthMeters - chords, greaterThan(15.0));
      expect(axis.spacingMeters, closeTo(2.0, 0.01));
      expect(chords / axis.points.length, lessThan(axis.spacingMeters - 0.02));
    });
  });

  group('measureCornerSpans', () {
    test('puts a corner late in the lap on the axis point at its progress', () {
      final axis = _zigzagAxis();
      final startIndex = axis.points.length - 60, endIndex = axis.points.length - 30;
      final spans = measureCornerSpans(
        _best(axis, [(axis.cumulative[startIndex], axis.cumulative[endIndex])]),
      );
      expect(spans, hasLength(1));
      _expectSamePlace(spans.single.start, _ground(axis, startIndex), 'start');
      _expectSamePlace(spans.single.end, _ground(axis, endIndex), 'end');
    });

    test('is on the right point all round the lap', () {
      final axis = _zigzagAxis();
      for (final index in [0, 40, 120, 240, 360, 440, axis.points.length - 1]) {
        final progress = axis.cumulative[index];
        final spans = measureCornerSpans(_best(axis, [(progress, progress + 0.1)]));
        _expectSamePlace(spans.single.start, _ground(axis, index), 'point $index');
      }
    });

    test('follows the cumulative distances on an axis with uneven spacing', () {
      final axis = _unevenAxis();
      for (final index in [10, 200, 350, axis.points.length - 20]) {
        final progress = axis.cumulative[index];
        final spans = measureCornerSpans(_best(axis, [(progress, progress + 0.1)]));
        _expectSamePlace(spans.single.start, _ground(axis, index), 'point $index');
      }
    });

    test('a position in the last segment is the last point or the gate, never the far side', () {
      final axis = _zigzagAxis();
      final lastIndex = axis.points.length - 1;
      final spans = measureCornerSpans(
        _best(axis, [(axis.cumulative[lastIndex] + 0.2, axis.lengthMeters - 0.2)]),
      );
      _expectSamePlace(spans.single.start, _ground(axis, lastIndex), 'start');
      final end = spans.single.end;
      final nearGate =
          (end.latitudeDegrees - _ground(axis, 0).latitudeDegrees).abs() < 1e-4 &&
          (end.longitudeDegrees - _ground(axis, 0).longitudeDegrees).abs() < 1e-4;
      expect(nearGate, isTrue);
    });
  });

  // Not fixed: measured on the parity fixtures, taking the region's width from
  // the samples' own progress moves the apex progress and tolerance of
  // corner_analyzer_parity and corner_metrics_parity by up to 0.27 m, so it
  // would depart from Overlays. Left as the expectation for the departure
  // (FET-251); `corner_phases.dart` still uses count times mean spacing.
  group('proposeCornerGeometryPhases', () {
    test(
      'the apex sits half way between the region\'s own progress, not its point count',
      skip: 'departs from Overlays parity, see above',
      () {
        final axis = _unevenAxis();
        final features = computeTrackFeatures(axis, 6.0);
        expect(features.valid, isTrue);
        final corner = TrackSegmentProposal(
          type: TrackSegmentType.corner,
          name: 'Circle',
          start: SegmentProposalBoundary(10.0, 7.0),
          end: SegmentProposalBoundary(axis.lengthMeters - 10.0, 7.0),
          turnRadians: 2 * math.pi,
          peakCurvaturePerMeter: 0.01,
        );
        final phases = proposeCornerGeometryPhases(axis, features, corner);
        expect(phases.valid, isTrue);
        expect(phases.apex.resolved, isTrue, reason: phases.apex.unresolvedReason);
        final first = phases.apex.evidence['regionStartMeters']! as double;
        final last = phases.apex.evidence['regionEndMeters']! as double;
        // The region is the 3 m spaced half: its points are 3 m apart, not the
        // 1.5 m mean spacing.
        expect(last - first, greaterThan(100.0));
        expect(phases.apex.progressMeters, closeTo((first + last) / 2.0, 1e-6));
        // The tolerance covers half the region plus a point spacing, on the
        // ground it spans.
        expect(phases.apex.toleranceMeters, closeTo((last - first) / 2.0 + 3.0, 4.0));
      },
    );
  });
}
