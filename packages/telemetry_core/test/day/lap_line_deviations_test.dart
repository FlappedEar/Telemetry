// lapLineDeviations (FET-41) gives exactly what the plain search gives: every
// point against every segment with an end in the 9 x 9 cells around it.
import 'dart:math' as math;

import 'package:telemetry_core/src/geometry.dart' show hypot;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

double _toSegment(MetricPoint p, MetricPoint a, MetricPoint b) {
  final abx = b.eastMeters - a.eastMeters, aby = b.northMeters - a.northMeters;
  final length2 = abx * abx + aby * aby;
  final t = length2 > 0
      ? (((p.eastMeters - a.eastMeters) * abx + (p.northMeters - a.northMeters) * aby) / length2)
            .clamp(0.0, 1.0)
      : 0.0;
  return hypot(p.eastMeters - (a.eastMeters + abx * t), p.northMeters - (a.northMeters + aby * t));
}

Map<int, double> _reference(List<LapTrace> traces, Set<int> laps) {
  const cell = 4.0, cap = maximumLineDeviationMeters + 4.0;
  final used = [
    for (final trace in traces)
      if (laps.contains(trace.lapNumber) && trace.points.length >= 2) trace,
  ];
  if (used.length < 3) return {};
  MetricPoint at(LapTracePoint point) => MetricPoint(point.eastMeters, point.northMeters);
  final result = <int, double>{};
  for (var lap = 0; lap < used.length; ++lap) {
    var worst = 0.0;
    for (final sample in used[lap].points) {
      final p = at(sample);
      final cx = (p.eastMeters / cell).floor(), cy = (p.northMeters / cell).floor();
      bool inWindow(LapTracePoint q) =>
          ((q.eastMeters / cell).floor() - cx).abs() <= 4 &&
          ((q.northMeters / cell).floor() - cy).abs() <= 4;
      var nearest = cap;
      for (var other = 0; other < used.length; ++other) {
        if (other == lap) continue;
        final path = used[other].points;
        for (var index = 0; index < path.length; ++index) {
          if (!inWindow(path[index])) continue;
          final q = at(path[index]);
          if (index > 0) nearest = math.min(nearest, _toSegment(p, at(path[index - 1]), q));
          if (index + 1 < path.length) {
            nearest = math.min(nearest, _toSegment(p, q, at(path[index + 1])));
          }
        }
      }
      worst = math.max(worst, nearest);
    }
    result[used[lap].lapNumber] = worst;
  }
  return result;
}

void main() {
  test('matches the plain search on wandering laps', () {
    final random = math.Random(41);
    for (var trial = 0; trial < 20; ++trial) {
      final traces = <LapTrace>[];
      for (var lap = 1; lap <= 3 + random.nextInt(4); ++lap) {
        final offset = random.nextDouble() * 6 - 3, wander = random.nextInt(3) == 0 ? 25.0 : 0.0;
        final count = 40 + random.nextInt(120);
        traces.add(
          LapTrace(
            lapNumber: lap,
            startTelemetryTime: 0,
            durationSeconds: 60,
            points: [
              for (var i = 0; i < count; ++i)
                LapTracePoint(
                  i.toDouble(),
                  (120 + offset) * math.cos(2 * math.pi * i / count) +
                      (i > count ~/ 2 && i < count * 3 ~/ 4 ? wander : 0.0) +
                      random.nextDouble(),
                  (80 + offset) * math.sin(2 * math.pi * i / count) + random.nextDouble(),
                ),
            ],
          ),
        );
      }
      final laps = {for (final trace in traces) trace.lapNumber};
      final expected = _reference(traces, laps);
      expect(lapLineDeviations(traces, laps), expected);
      expect(expected.values.every((value) => value >= 0), isTrue);
    }
  });
}
