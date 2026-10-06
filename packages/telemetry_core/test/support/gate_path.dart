import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';

import 'sessions.dart';

/// The gate of [GatePath]: north–south through [gatePathOrigin], about 22 m
/// long. In metres around the origin it spans north −11.1 … +11.1 at east 0.
const gatePathOrigin = GeoCoordinate(52.0001, 21.0);
const gatePathGate = TimingGate(
  type: TimingGateType.start,
  sourceName: 'Start',
  endpointA: GeoCoordinate(52.0, 21.0),
  endpointB: GeoCoordinate(52.0002, 21.0),
);

/// A GPS path through metre waypoints (east, north) around [gatePathGate],
/// one fix every [step] seconds.
final class GatePath {
  GatePath({this.step = 0.2});

  final double step;
  final times = <double>[];
  final east = <double>[];
  final north = <double>[];

  /// Adds the exact points given, one per step.
  void points(List<(double, double)> points) {
    for (final (e, n) in points) {
      times.add(times.isEmpty ? 0.0 : times.last + step);
      east.add(e);
      north.add(n);
    }
  }

  /// Moves in straight lines through [waypoints], at most [maximumStepMeters]
  /// per step.
  void travel(List<(double, double)> waypoints, {double maximumStepMeters = 8.0}) {
    for (final (e, n) in waypoints) {
      final fromE = east.last;
      final fromN = north.last;
      final distance = math.sqrt((e - fromE) * (e - fromE) + (n - fromN) * (n - fromN));
      final steps = math.max(1, (distance / maximumStepMeters).ceil());
      for (var index = 1; index <= steps; ++index) {
        final fraction = index / steps;
        points([(fromE + (e - fromE) * fraction, fromN + (n - fromN) * fraction)]);
      }
    }
  }

  /// Stays at the last point for [seconds].
  void wait(double seconds) {
    final steps = (seconds / step).round();
    for (var index = 0; index < steps; ++index) {
      points([(east.last, north.last)]);
    }
  }

  /// A crossing from east to west through the gate at [atNorth].
  void crossWestward({double atNorth = 0.0, double maximumStepMeters = 6.0}) =>
      travel([(30.0, atNorth), (-30.0, atNorth)], maximumStepMeters: maximumStepMeters);

  /// From the west side back round to the east approach, staying far from
  /// the gate: about 640 m, so a lap with [crossWestward] is about 700 m.
  void loopBackEast({double maximumStepMeters = 8.0}) => travel([
    (-100.0, 0.0),
    (-100.0, 150.0),
    (100.0, 150.0),
    (100.0, 0.0),
    (30.0, 0.0),
  ], maximumStepMeters: maximumStepMeters);

  TelemetrySession session() {
    final latitudes = <double>[];
    final longitudes = <double>[];
    for (var index = 0; index < times.length; ++index) {
      final coordinate = unprojectCoordinate(east[index], north[index], gatePathOrigin);
      latitudes.add(coordinate.latitudeDegrees);
      longitudes.add(coordinate.longitudeDegrees);
    }
    return gpsSession(times, latitudes, longitudes, gates: const [gatePathGate]);
  }
}
