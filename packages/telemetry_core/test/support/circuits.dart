import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/src/telemetry_session.dart'
    show adoptChannelTimestamps, adoptChannelValues;
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

/// A synthetic recording driving a rounded rectangle (300 m by 150 m, 30 m
/// corners, about 811 m) counter-clockwise through the gate at the origin,
/// heading north, sampled at 10 Hz: one lap per entry in [speeds], each
/// giving the speed (m/s) at a distance along the lap (0 at the gate). It
/// has four corners and four straights, so it gets segment proposals. With
/// [pedals] it also records throttle and brake (%) and longitudinal G from
/// the change of speed: braking when slowing by more than 0.4 m/s², full
/// throttle when gaining more than 0.3 m/s², part throttle otherwise. With
/// [lateral] it records lateral G too: the speed squared over the radius in
/// the corners, 0 on the straights.
TelemetrySession rectangleSession(
  List<double Function(double distance)> speeds, {
  int? firstTimestampMilliseconds,
  GeoCoordinate centre = const GeoCoordinate(_lat0, _lon0),
  bool pedals = false,
  bool lateral = false,
  List<double Function(double distance)>? westShifts,
}) {
  const width = 300.0, height = 150.0, radius = 30.0;
  // The outline from the gate, 0.5 m apart.
  final outline = <(double, double)>[];
  // Whether each outline point is on a corner's arc.
  final arc = <bool>[];
  void straight(double x0, double y0, double x1, double y1) {
    final length = math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2));
    final steps = (length / 0.5).round();
    for (var i = 0; i < steps; ++i) {
      outline.add((x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps));
      arc.add(false);
    }
  }

  void corner(double cx, double cy, double from) {
    final steps = (math.pi / 2 * radius / 0.5).round();
    for (var i = 0; i < steps; ++i) {
      final a = from + math.pi / 2 * i / steps;
      outline.add((cx + radius * math.cos(a), cy + radius * math.sin(a)));
      arc.add(true);
    }
  }

  const halfHeight = height / 2 - radius;
  const left = -width + radius, right = -radius;
  straight(0, 0, 0, halfHeight);
  corner(right, halfHeight, 0);
  straight(right, height / 2, left, height / 2);
  corner(left, halfHeight, math.pi / 2);
  straight(-width, halfHeight, -width, -halfHeight);
  corner(left, -halfHeight, math.pi);
  straight(left, -height / 2, right, -height / 2);
  corner(right, -halfHeight, 3 * math.pi / 2);
  straight(0, -halfHeight, 0, 0);
  final perimeter = outline.length * 0.5;
  (double, double) at(double distance) {
    final wrapped = distance % perimeter;
    final index = (wrapped / 0.5).floor() % outline.length;
    final next = (index + 1) % outline.length;
    final fraction = wrapped / 0.5 - (wrapped / 0.5).floor();
    return (
      outline[index].$1 + (outline[next].$1 - outline[index].$1) * fraction,
      outline[index].$2 + (outline[next].$2 - outline[index].$2) * fraction,
    );
  }

  final times = <double>[], latitudes = <double>[], longitudes = <double>[];
  final speedValues = <double>[], lateralValues = <double>[];
  var distance = -20.0, t = 0.0;
  final end = (speeds.length + 0.3) * perimeter;
  while (distance < end) {
    final lap = math.max(0, math.min(distance ~/ perimeter, speeds.length - 1));
    final speed = speeds[lap](distance - lap * perimeter);
    final (east, north) = at(distance);
    // A lap driven off the others' line: moved west by [westShifts].
    final shift = westShifts == null || lap >= westShifts.length
        ? 0.0
        : westShifts[lap](distance - lap * perimeter);
    final coordinate = _toDegrees(east - shift, north, centre);
    times.add(t);
    latitudes.add(coordinate.latitudeDegrees);
    longitudes.add(coordinate.longitudeDegrees);
    speedValues.add(speed * 3.6);
    final onArc = arc[((distance % perimeter) / 0.5).floor() % arc.length];
    lateralValues.add(onArc ? speed * speed / radius / standardGravity : 0.0);
    distance += speed / 10.0;
    t += 0.1;
  }
  final clock = adoptChannelTimestamps(Float64List.fromList(times));
  final editable = <String, Float32List>{};
  TelemetryChannel channel(String name, List<double> values) => TelemetryChannel(
    name: name,
    timestamps: clock,
    values: adoptChannelValues(editable[name] = Float32List.fromList(values)),
  );
  final throttle = <double>[], brake = <double>[], longitudinal = <double>[];
  if (pedals) {
    for (var i = 0; i < times.length; ++i) {
      final before = speedValues[math.max(0, i - 1)] / 3.6;
      final after = speedValues[math.min(times.length - 1, i + 1)] / 3.6;
      final acceleration =
          (after - before) / (times[math.min(times.length - 1, i + 1)] - times[math.max(0, i - 1)]);
      longitudinal.add(acceleration / 9.81);
      brake.add(acceleration < -0.4 ? math.min(100.0, -acceleration * 12.0) : 0.0);
      throttle.add(
        acceleration < -0.4
            ? 0.0
            : acceleration > 0.3
            ? 100.0
            : 15.0,
      );
    }
  }
  final session = TelemetrySession(
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
      if (pedals) ...{
        'throttle': channel('throttle', throttle),
        'brake': channel('brake', brake),
        'longacc': channel('longacc', longitudinal),
      },
      if (lateral) 'latacc': channel('latacc', lateralValues),
    },
    aliases: {
      'latitude': 'latitude',
      'longitude': 'longitude',
      'speed': 'velocity',
      if (pedals) ...{
        'throttle': 'throttle',
        'brake': 'brake',
        'longitudinalAcceleration': 'longacc',
      },
      if (lateral) 'lateralAcceleration': 'latacc',
    },
    warnings: const [],
    timingGates: [circuitGate(centre: centre)],
    sampleCount: times.length,
  );
  _editableValues[session] = editable;
  return session;
}

final _editableValues = Expando<Map<String, Float32List>>('editable values');

/// The writable values behind channel [name] of a [rectangleSession], for
/// tests that change a recording before analysing it. Channels are
/// read-only (FET-202); only this test helper keeps the lists it handed over.
Float32List editableValues(TelemetrySession session, String name) =>
    _editableValues[session]![name]!;
