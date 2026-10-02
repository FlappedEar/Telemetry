import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';

const double _lat0 = 52.0, _lon0 = 21.0;
const double _metersPerDegree = 6371000.0 * math.pi / 180.0;

GeoCoordinate _toDegrees(double east, double north, GeoCoordinate centre) => GeoCoordinate(
  centre.latitudeDegrees + north / _metersPerDegree,
  centre.longitudeDegrees +
      east / (_metersPerDegree * math.cos(centre.latitudeDegrees * math.pi / 180.0)),
);

/// The start gate across the origin of a [circuitSession], 20 m wide.
TimingGate circuitGate({GeoCoordinate centre = const GeoCoordinate(_lat0, _lon0)}) => TimingGate(
  type: TimingGateType.start,
  sourceName: 'Start',
  endpointA: _toDegrees(-10.0, 0.0, centre),
  endpointB: _toDegrees(10.0, 0.0, centre),
);

/// A synthetic recording driving a circle of [radius] metres through the gate
/// at the origin (centre at (−radius, 0)), one lap per entry in [speeds]
/// (m/s), sampled at 10 Hz. [radiusOf] can bend the path, for example to
/// leave the line on one lap: it gets the lap index and the angle travelled
/// within the lap (0 to 2π) and returns the radius there.
TelemetrySession circuitSession({
  double radius = 100.0,
  List<double> speeds = const [30.0, 28.0, 31.0],
  bool clockwise = false,
  int? firstTimestampMilliseconds,
  double Function(int lap, double angle)? radiusOf,
  GeoCoordinate centre = const GeoCoordinate(_lat0, _lon0),
}) {
  final times = <double>[],
      latitudes = <double>[],
      longitudes = <double>[],
      speedValues = <double>[];
  const rate = 10.0;
  const startAngle = -0.25;
  final sign = clockwise ? -1.0 : 1.0;
  final total = (speeds.length + 0.5) * 2 * math.pi;
  var travelled = 0.0, t = 0.0;
  while (travelled < total) {
    final lap = math.min(travelled ~/ (2 * math.pi), speeds.length - 1);
    final speed = speeds[lap];
    final r = radiusOf?.call(lap, travelled - lap * 2 * math.pi) ?? radius;
    final a = startAngle + sign * travelled;
    final coordinate = _toDegrees(-radius + r * math.cos(a), r * math.sin(a), centre);
    times.add(t);
    latitudes.add(coordinate.latitudeDegrees);
    longitudes.add(coordinate.longitudeDegrees);
    speedValues.add(speed * 3.6);
    travelled += speed / rate / radius;
    t += 1.0 / rate;
  }
  TelemetryChannel channel(String name, List<double> values) => TelemetryChannel(
    name: name,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
  return TelemetrySession(
    duration: times.last,
    startTime: 0,
    metadata: {
      if (firstTimestampMilliseconds != null)
        'firstTimestampMilliseconds': '$firstTimestampMilliseconds',
    },
    channels: {
      'latitude': channel('latitude', latitudes),
      'longitude': channel('longitude', longitudes),
      'velocity': channel('velocity', speedValues),
    },
    aliases: const {'latitude': 'latitude', 'longitude': 'longitude', 'speed': 'velocity'},
    warnings: const [],
    timingGates: [circuitGate(centre: centre)],
    sampleCount: times.length,
  );
}
