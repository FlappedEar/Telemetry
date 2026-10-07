import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/sessions.dart';

// FET-249: projecting a lap onto an axis whose points are not evenly spaced,
// and a fix found again behind the last one after a gap.

const double _radius = 100.0;
const double _metresPerDegree = 6371000.0 * math.pi / 180.0;
const _centre = GeoCoordinate(52.0, 21.0);
const _length = 2 * math.pi * _radius;

// The circle through the origin (centre at (−radius, 0)), counter-clockwise
// from the origin heading north, at [progress] metres.
MetricPoint _at(double progress) {
  final angle = progress / _radius;
  return MetricPoint(-_radius + _radius * math.cos(angle), _radius * math.sin(angle));
}

GeoCoordinate _degrees(MetricPoint point) => GeoCoordinate(
  _centre.latitudeDegrees + point.northMeters / _metresPerDegree,
  _centre.longitudeDegrees +
      point.eastMeters / (_metresPerDegree * math.cos(_centre.latitudeDegrees * math.pi / 180.0)),
);

// A session at 10 Hz whose position along the circle is [progress] (metres)
// at each time, skipping the times [progress] gives null for.
TelemetrySession _session(double duration, double? Function(double time) progress) {
  final times = <double>[], latitudes = <double>[], longitudes = <double>[];
  for (var i = 0; i * 0.1 <= duration; ++i) {
    final time = i * 0.1;
    final p = progress(time);
    if (p == null) continue;
    final coordinate = _degrees(_at(p));
    times.add(time);
    latitudes.add(coordinate.latitudeDegrees);
    longitudes.add(coordinate.longitudeDegrees);
  }
  return gpsSession(times, latitudes, longitudes);
}

// The circle as an axis with its points 1 m apart over the first half and
// 3 m apart over the second, so its mean spacing (1.5 m) is far from the
// spacing at most points.
ProgressAxis _unevenAxis() {
  final points = <MetricPoint>[];
  for (var p = 0.0; p < _length / 2; p += 1.0) {
    points.add(_at(p));
  }
  for (var p = _length / 2; p < _length - 1.5; p += 3.0) {
    points.add(_at(p));
  }
  final cumulative = <double>[0.0];
  for (var i = 1; i < points.length; ++i) {
    final a = points[i - 1], b = points[i];
    cumulative.add(
      cumulative.last +
          math.sqrt(
            math.pow(b.eastMeters - a.eastMeters, 2) + math.pow(b.northMeters - a.northMeters, 2),
          ),
    );
  }
  final last = points.last, first = points.first;
  final length =
      cumulative.last +
      math.sqrt(
        math.pow(first.eastMeters - last.eastMeters, 2) +
            math.pow(first.northMeters - last.northMeters, 2),
      );
  return ProgressAxis(
    points: points,
    cumulative: cumulative,
    lengthMeters: length,
    spacingMeters: length / points.length,
    origin: _centre,
    valid: true,
  );
}

void main() {
  test('follows a lap along an axis whose points are not evenly spaced', () {
    final axis = _unevenAxis();
    expect(axis.spacingMeters, closeTo(1.5, 0.01));
    // One lap at 30 m/s, starting just after the gate.
    final lapSeconds = _length / 30.0;
    final session = _session(lapSeconds + 0.05, (t) => 30.0 * t + 0.5);
    final trace = projectLapTrace(axis, session, 0.0, lapSeconds);
    expect(trace, hasLength(1));
    final samples = trace.single.samples;
    expect(samples.first.progressMeters, lessThan(5.0));
    expect(samples.last.progressMeters, closeTo(axis.lengthMeters, 5.0));
    for (var i = 1; i < samples.length; ++i) {
      expect(samples[i].progressMeters, greaterThanOrEqualTo(samples[i - 1].progressMeters));
    }
  });

  test('a fix found again a little behind after a gap stays on the same lap', () {
    final session = _session(15.0, (t) {
      if (t < 6.0) return 30.0 * t; // up to 177 m
      if (t < 6.6) return null; // a GPS gap of 0.6 s
      return 30.0 * 6.0 - 8.0 + 30.0 * (t - 6.6); // found again 8 m behind
    });
    final laps = deriveSourceLapSession(session);
    expect(laps.status, isNot(LapSessionStatus.available)); // no full lap
    final axis = _unevenAxis();
    final trace = projectLapTrace(axis, session, 0.0, 15.0);
    expect(trace, hasLength(2));
    final restart = trace[1].samples.first.progressMeters;
    // 5 m behind the last fix before the gap (177 m), on the same lap.
    expect(trace[0].samples.last.progressMeters, closeTo(177.0, 1.0));
    expect(restart, closeTo(172.0, 1.0));
    expect(trace[1].samples.last.progressMeters, lessThan(axis.lengthMeters));
  });
}
