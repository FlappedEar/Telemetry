import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:telemetry_core/src/geometry.dart'
    show earthRadiusMeters, geoMidpoint, wrapLongitudeDegrees;
import 'package:telemetry_core/src/vbo/vbo_coordinates.dart' show parseTimingGate;
import 'package:test/test.dart';

import 'support/sessions.dart';

// FET-213: a circuit across the antimeridian (longitude ±180°) gives the
// same laps, distances and projections as the same circuit anywhere else.
void main() {
  test('wraps longitudes by whole turns and keeps in-range values exact', () {
    expect(wrapLongitudeDegrees(21.123456789), 21.123456789);
    expect(wrapLongitudeDegrees(180.0), 180.0);
    expect(wrapLongitudeDegrees(-180.0), -180.0);
    expect(wrapLongitudeDegrees(180.5), closeTo(-179.5, 1e-9));
    expect(wrapLongitudeDegrees(-180.5), closeTo(179.5, 1e-9));
    expect(wrapLongitudeDegrees(359.998), closeTo(-0.002, 1e-9));
    expect(wrapLongitudeDegrees(-359.998), closeTo(0.002, 1e-9));
  });

  test('takes the midpoint the short way round', () {
    const a = GeoCoordinate(52.0, 21.0);
    const b = GeoCoordinate(52.0002, 21.0004);
    final usual = geoMidpoint(a, b);
    expect(usual.latitudeDegrees, (52.0 + 52.0002) / 2.0);
    expect(usual.longitudeDegrees, (21.0 + 21.0004) / 2.0);

    final across = geoMidpoint(
      const GeoCoordinate(-17.0, 179.9998),
      const GeoCoordinate(-17.0, -179.9996),
    );
    expect(across.latitudeDegrees, -17.0);
    expect(across.longitudeDegrees, closeTo(-179.9999, 1e-9));
    final backward = geoMidpoint(
      const GeoCoordinate(-17.0, -179.9996),
      const GeoCoordinate(-17.0, 179.9998),
    );
    expect(backward.longitudeDegrees, closeTo(-179.9999, 1e-9));
  });

  test('projects, unprojects and measures across the antimeridian', () {
    const origin = GeoCoordinate(-17.0, 179.9999);
    const east = GeoCoordinate(-17.0, -179.9999);
    const west = GeoCoordinate(-17.0, 179.9997);
    final eastPoint = projectCoordinate(east, origin);
    final westPoint = projectCoordinate(west, origin);
    expect(eastPoint.eastMeters, closeTo(-westPoint.eastMeters, 1e-6));
    expect(eastPoint.eastMeters, closeTo(21.27, 0.01));
    final back = unprojectCoordinate(eastPoint.eastMeters, eastPoint.northMeters, origin);
    expect(back.longitudeDegrees, closeTo(-179.9999, 1e-9));
    expect(isValidCoordinate(back), isTrue);
    expect(distanceMeters(origin, east), closeTo(eastPoint.eastMeters, 0.01));
    // At 78° N the same 0.0002° is under 5 m.
    const arctic = GeoCoordinate(78.0, 179.9999);
    final arcticEast = projectCoordinate(const GeoCoordinate(78.0, -179.9999), arctic);
    expect(arcticEast.eastMeters, closeTo(4.62, 0.01));
    expect(arcticEast.northMeters, 0.0);
  });

  test('times the same laps on a circuit across the antimeridian', () {
    // The lap_detection_test circuit, once at 21° E and once moved onto 180°.
    final times = <double>[0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15];
    const mid = 0.0001, north = 0.0008;
    final latitudes = [
      mid,
      mid,
      mid,
      north,
      north,
      mid,
      mid,
      north,
      north,
      mid,
      mid,
      north,
      north,
      mid,
      mid,
    ];
    final east = [1, 1, -1, -1, 1, 1, -1, -1, 1, 1, -1, -1, 1, 1, -1];
    List<double> laps(double baseLatitude, double baseLongitude) {
      final gate = TimingGate(
        type: TimingGateType.start,
        sourceName: 'Start',
        endpointA: GeoCoordinate(baseLatitude, baseLongitude),
        endpointB: GeoCoordinate(baseLatitude + 0.0002, baseLongitude),
      );
      // The same width in metres at every latitude.
      final step =
          0.0002 * math.cos(52.0 * math.pi / 180.0) / math.cos(baseLatitude * math.pi / 180.0);
      final session = gpsSession(
        times,
        [for (final l in latitudes) baseLatitude + l],
        [for (final e in east) wrapLongitudeDegrees(baseLongitude + e * step)],
      );
      final detected = detectLaps(session, gate);
      expect(detected.status, LapSessionStatus.available);
      return [for (final lap in detected.timedLaps) lap.durationSeconds];
    }

    // In the tropics and at high latitude, where a degree of longitude is
    // a third as long.
    for (final latitude in [-17.0, 70.0]) {
      final reference = laps(latitude, 21.0);
      expect(reference, hasLength(3));
      for (final longitude in [180.0, -180.0, 179.9999, -179.9999]) {
        final across = laps(latitude, longitude);
        expect(across, hasLength(reference.length), reason: '$latitude $longitude');
        for (var i = 0; i < reference.length; i++) {
          expect(across[i], closeTo(reference[i], 1e-3), reason: '$latitude $longitude');
        }
      }
    }
  });

  test('builds the same traces and track axis on a circle across the antimeridian', () {
    // A 100 m circle driven at 10 Hz, 20 s a lap, through a gate at its
    // southern point.
    ({List<double> laps, List<LapTrace> traces, ProgressAxis axis, GeoCoordinate origin}) run(
      double gateLongitude,
    ) {
      const latitude = -17.0;
      const radius = 100.0;
      final metresPerDegree = earthRadiusMeters * math.pi / 180.0;
      final eastDegrees = 1.0 / (metresPerDegree * math.cos(latitude * math.pi / 180.0));
      final times = <double>[], latitudes = <double>[], longitudes = <double>[];
      for (var i = 0; i <= 700; ++i) {
        final time = i / 10.0;
        // 0.037 s out of phase, so gate crossings fall between samples.
        final angle = math.pi / 2 + 2 * math.pi * (time + 0.037) / 20.0;
        final east = radius * math.cos(angle), north = radius + radius * math.sin(angle) * -1;
        times.add(time);
        latitudes.add(latitude + north / metresPerDegree);
        longitudes.add(wrapLongitudeDegrees(gateLongitude + east * eastDegrees));
      }
      final gate = TimingGate(
        type: TimingGateType.start,
        sourceName: 'Start',
        endpointA: GeoCoordinate(latitude - 0.0002, gateLongitude),
        endpointB: GeoCoordinate(latitude + 0.0002, gateLongitude),
      );
      final detected = detectLaps(gpsSession(times, latitudes, longitudes), gate);
      final origin = geoMidpoint(gate.endpointA, gate.endpointB);
      final axis = buildProgressAxis(detected.lapTraces.first, origin, gate);
      return (
        laps: [for (final lap in detected.timedLaps) lap.durationSeconds],
        traces: detected.lapTraces,
        axis: axis,
        origin: origin,
      );
    }

    // At 150° longitude is stored in the same Float32 steps (about 1.6 m)
    // as near 180°, so the paths match closely.
    final reference = run(150.0);
    expect(reference.laps, isNotEmpty);
    expect(reference.axis.valid, isTrue);
    for (final longitude in [180.0, -180.0, 179.99995]) {
      final across = run(longitude);
      expect(across.laps, hasLength(reference.laps.length), reason: '$longitude');
      for (var i = 0; i < reference.laps.length; i++) {
        expect(across.laps[i], closeTo(reference.laps[i], 1e-3), reason: '$longitude');
      }
      expect(across.traces, hasLength(reference.traces.length));
      for (var t = 0; t < across.traces.length; t++) {
        // Every trace starts and ends at the gate, not on the far side of
        // the Earth.
        for (final point in [across.traces[t].points.first, across.traces[t].points.last]) {
          expect(
            math.sqrt(point.eastMeters * point.eastMeters + point.northMeters * point.northMeters),
            lessThan(25.0),
            reason: '$longitude trace $t',
          );
        }
      }
      expect(across.axis.valid, isTrue, reason: '$longitude');
      expect(
        across.axis.lengthMeters,
        closeTo(reference.axis.lengthMeters, 0.01 * reference.axis.lengthMeters),
        reason: '$longitude',
      );
    }
  });

  test('interpolates longitude the short way round', () {
    // Longitude is stored as Float32: about 1.5e-5° steps near 180°.
    final session = gpsSession([0.0, 1.0], [-17.0, -17.0], [179.9999, -179.9999]);
    expect(
      session.valueAt('longitude', 0.25, InterpolationMode.longitude),
      closeTo(179.99995, 2e-5),
    );
    expect(
      session.valueAt('longitude', 0.75, InterpolationMode.longitude),
      closeTo(-179.99995, 2e-5),
    );
    // Under 180° apart it is exactly the straight line.
    final usual = gpsSession([0.0, 1.0], [52.0, 52.0], [21.0, 21.0004]);
    expect(
      usual.valueAt('longitude', 0.3, InterpolationMode.longitude),
      usual.valueAt('longitude', 0.3),
    );
  });

  test('keeps a centre-and-direction gate on the antimeridian valid', () {
    // Centre on 180°, pointing backward due north: the gate runs east-west
    // across the antimeridian.
    final northward = parseTimingGate(
      'Start 180.0 -17.0 180.0 -16.9999',
      true,
      CoordinateUnit.degrees,
    );
    expect(northward.error, isEmpty);
    final gate = northward.gate!;
    expect(isValidCoordinate(gate.endpointA) && isValidCoordinate(gate.endpointB), isTrue);
    expect(distanceMeters(gate.endpointA, gate.endpointB), closeTo(11.12, 0.01));
    expect(
      geoMidpoint(gate.endpointA, gate.endpointB).longitudeDegrees.abs(),
      closeTo(180.0, 1e-9),
    );
    // Centre just west of 180°, pointing backward across it: a gate about
    // 21 m wide, not one across the whole Earth.
    final eastward = parseTimingGate(
      'Start 179.9999 -17.0 -179.9999 -17.0',
      true,
      CoordinateUnit.degrees,
    );
    expect(eastward.error, isEmpty);
    expect(
      distanceMeters(eastward.gate!.endpointA, eastward.gate!.endpointB),
      closeTo(21.27, 0.01),
    );
  });
}
