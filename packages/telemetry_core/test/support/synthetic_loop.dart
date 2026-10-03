// Synthetic closed loops built from exact straights and arcs, for tests that
// run the real buildProgressAxis -> computeTrackFeatures pipeline, and laps
// driven around them.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';

/// A straight of [meters] when [degrees] is 0, otherwise an arc turning
/// [degrees] (positive left) at [radiusMeters].
typedef LoopStep = ({double meters, double degrees, double radiusMeters});

LoopStep straight(double meters) => (meters: meters, degrees: 0.0, radiusMeters: 0.0);
LoopStep arc(double degrees, double radius) =>
    (meters: 0.0, degrees: degrees, radiusMeters: radius);

/// Traces [half] from (0, 0) heading east at ~1 m steps, then appends the
/// same path rotated 180 degrees about its end point. [half] must turn a net
/// 180 degrees, so the loop closes back at the origin, where the gate sits.
/// The origin is not repeated at the end.
List<(double, double)> loopPoints(List<LoopStep> half) {
  final points = <(double, double)>[(0.0, 0.0)];
  var heading = 0.0;
  void step(double ds) {
    final (x, y) = points.last;
    points.add((x + ds * math.cos(heading), y + ds * math.sin(heading)));
  }

  for (final part in half) {
    if (part.degrees == 0.0) {
      final steps = math.max(1, part.meters.round());
      for (var i = 0; i < steps; ++i) {
        step(part.meters / steps);
      }
    } else {
      final angle = part.degrees * math.pi / 180.0;
      final steps = math.max(1, (angle.abs() * part.radiusMeters).round());
      final turn = angle / steps;
      final ds = angle.abs() * part.radiusMeters / steps;
      for (var i = 0; i < steps; ++i) {
        heading += turn / 2.0; // midpoint heading: each step is an exact chord
        step(ds);
        heading += turn / 2.0;
      }
    }
  }
  final (endX, endY) = points.last;
  final halfCount = points.length;
  for (var i = 1; i + 1 < halfCount; ++i) {
    points.add((endX - points[i].$1, endY - points[i].$2));
  }
  return points;
}

const _origin = GeoCoordinate(0.0, 0.0);
const _gate = TimingGate(
  type: TimingGateType.start,
  sourceName: 'test',
  endpointA: _origin,
  endpointB: _origin,
);

ProgressAxis buildLoopAxis(List<LoopStep> half) {
  final points = loopPoints(half);
  return buildProgressAxis(
    LapTrace(
      lapNumber: 1,
      startTelemetryTime: 0,
      durationSeconds: points.length.toDouble(),
      points: [
        for (var i = 0; i < points.length; ++i)
          LapTracePoint(i.toDouble(), points[i].$1, points[i].$2),
      ],
    ),
    _origin,
    _gate,
  );
}

List<LoopStep> stadium() => [straight(100), arc(180, 40), straight(100)];

const double _earthRadiusMeters = 6371000.0;
double _degreesForMeters(double meters) => meters / _earthRadiusMeters * 180.0 / math.pi;

/// One lap of a loop and its last sample's time.
typedef DrivenLap = ({TelemetrySession session, double endTime});

/// Drives one lap of the loop of [half] at 20 Hz, gate to gate, at [speed]
/// m/s as a function of path distance. Fixes whose distance is within
/// [gpsGap] are dropped; speed samples within [speedGap] are NaN.
DrivenLap driveLap(
  List<LoopStep> half,
  double Function(double meters) speed, {
  (double, double) gpsGap = (-1.0, -1.0),
  (double, double) speedGap = (-1.0, -1.0),
}) {
  final points = [...loopPoints(half)];
  points.add(points.first);
  final cumulative = <double>[0.0];
  for (var i = 1; i < points.length; ++i) {
    cumulative.add(
      cumulative.last +
          math.sqrt(
            math.pow(points[i].$1 - points[i - 1].$1, 2) +
                math.pow(points[i].$2 - points[i - 1].$2, 2),
          ),
    );
  }
  final length = cumulative.last;
  final latTimes = <double>[], lats = <double>[], lonTimes = <double>[], lons = <double>[];
  final speedTimes = <double>[], speeds = <double>[];
  const dt = 0.05;
  var s = 0.0, time = 0.0;
  var segment = 1;
  while (s < length) {
    while (segment + 1 < cumulative.length && cumulative[segment] < s) {
      ++segment;
    }
    final fraction =
        (s - cumulative[segment - 1]) / (cumulative[segment] - cumulative[segment - 1]);
    final x = points[segment - 1].$1 + (points[segment].$1 - points[segment - 1].$1) * fraction;
    final y = points[segment - 1].$2 + (points[segment].$2 - points[segment - 1].$2) * fraction;
    if (!(s >= gpsGap.$1 && s <= gpsGap.$2)) {
      latTimes.add(time);
      lats.add(_degreesForMeters(y));
      lonTimes.add(time);
      lons.add(_degreesForMeters(x));
    }
    speedTimes.add(time);
    speeds.add(s >= speedGap.$1 && s <= speedGap.$2 ? double.nan : speed(s) * 3.6);
    s += speed(s) * dt;
    time += dt;
  }
  TelemetryChannel channel(String name, String unit, List<double> times, List<double> values) =>
      TelemetryChannel(
        name: name,
        unit: unit,
        timestamps: Float64List.fromList(times),
        values: Float32List.fromList(values),
      );
  return (
    session: TelemetrySession(
      duration: time,
      startTime: 0,
      metadata: const {},
      channels: {
        'lat': channel('lat', '', latTimes, lats),
        'lon': channel('lon', '', lonTimes, lons),
        'velocity': channel('velocity', 'km/h', speedTimes, speeds),
      },
      aliases: const {'latitude': 'lat', 'longitude': 'lon', 'speed': 'velocity'},
      warnings: const [],
      timingGates: const [],
      sampleCount: speedTimes.length,
    ),
    endTime: time - dt,
  );
}

/// [session] with its channels and aliases replaced.
TelemetrySession withChannels(
  TelemetrySession session, {
  Map<String, TelemetryChannel>? channels,
  Map<String, String>? aliases,
}) => TelemetrySession(
  duration: session.duration,
  startTime: session.startTime,
  metadata: session.metadata,
  channels: channels ?? session.channels,
  aliases: aliases ?? session.aliases,
  warnings: session.warnings,
  timingGates: session.timingGates,
  sampleCount: session.sampleCount,
);
