import 'dart:math' as math;

/// The axis a coordinate value belongs to.
enum CoordinateAxis { latitude, longitude }

/// How a recording writes coordinates.
enum CoordinateUnit { degrees, arcMinutes }

/// A WGS 84 position in degrees.
final class GeoCoordinate {
  const GeoCoordinate(this.latitudeDegrees, this.longitudeDegrees);

  final double latitudeDegrees;
  final double longitudeDegrees;

  @override
  bool operator ==(Object other) =>
      other is GeoCoordinate &&
      other.latitudeDegrees == latitudeDegrees &&
      other.longitudeDegrees == longitudeDegrees;

  @override
  int get hashCode => Object.hash(latitudeDegrees, longitudeDegrees);

  @override
  String toString() => 'GeoCoordinate($latitudeDegrees, $longitudeDegrees)';
}

/// A position in metres east and north of a local origin.
final class MetricPoint {
  const MetricPoint(this.eastMeters, this.northMeters);

  final double eastMeters;
  final double northMeters;
}

const double earthRadiusMeters = 6371000.0;
const double radiansPerDegree = math.pi / 180.0;

/// Converts [value] in [unit] to degrees, or null when it is not finite or lies
/// outside ±90° (latitude) or ±180° (longitude).
double? normalizeCoordinateDegrees(CoordinateAxis axis, double value, CoordinateUnit unit) {
  if (!value.isFinite) return null;
  final degrees = unit == CoordinateUnit.arcMinutes ? value / 60.0 : value;
  final limit = axis == CoordinateAxis.latitude ? 90.0 : 180.0;
  return degrees.abs() <= limit ? degrees : null;
}

/// True for a finite coordinate within the latitude and longitude ranges.
bool isValidCoordinate(GeoCoordinate coordinate) =>
    coordinate.latitudeDegrees.isFinite &&
    coordinate.longitudeDegrees.isFinite &&
    coordinate.latitudeDegrees.abs() <= 90.0 &&
    coordinate.longitudeDegrees.abs() <= 180.0;

/// [degrees] of longitude in -180 to 180 (FET-213): unchanged when already
/// there, otherwise moved by whole turns, so a step across the
/// antimeridian (179.999 to -179.999) is 0.002°, not 360°.
double wrapLongitudeDegrees(double degrees) {
  if (degrees >= -180.0 && degrees <= 180.0) return degrees;
  return (degrees + 180.0) % 360.0 - 180.0;
}

/// The point halfway between [a] and [b], the short way round in longitude
/// (FET-213). The same as averaging their degrees when they are less than
/// 180° of longitude apart.
GeoCoordinate geoMidpoint(GeoCoordinate a, GeoCoordinate b) {
  final latitude = (a.latitudeDegrees + b.latitudeDegrees) / 2.0;
  final difference = b.longitudeDegrees - a.longitudeDegrees;
  if (difference.abs() <= 180.0) {
    return GeoCoordinate(latitude, (a.longitudeDegrees + b.longitudeDegrees) / 2.0);
  }
  return GeoCoordinate(
    latitude,
    wrapLongitudeDegrees(a.longitudeDegrees + wrapLongitudeDegrees(difference) / 2.0),
  );
}

/// Equirectangular projection of [coordinate] around [origin], in metres.
/// Accurate enough over the size of a circuit. The longitude difference is
/// taken the short way round, so a circuit across ±180° projects like any
/// other (FET-213; Overlays subtracts it directly, departure KAN-235).
MetricPoint projectCoordinate(GeoCoordinate coordinate, GeoCoordinate origin) {
  return MetricPoint(
    wrapLongitudeDegrees(coordinate.longitudeDegrees - origin.longitudeDegrees) *
        radiansPerDegree *
        earthRadiusMeters *
        math.cos(origin.latitudeDegrees * radiansPerDegree),
    (coordinate.latitudeDegrees - origin.latitudeDegrees) * radiansPerDegree * earthRadiusMeters,
  );
}

/// The inverse of [projectCoordinate]: [east] and [north] metres around
/// [origin] back in degrees, longitude in -180 to 180.
GeoCoordinate unprojectCoordinate(double east, double north, GeoCoordinate origin) => GeoCoordinate(
  origin.latitudeDegrees + north / earthRadiusMeters / radiansPerDegree,
  wrapLongitudeDegrees(
    origin.longitudeDegrees +
        east /
            (earthRadiusMeters * math.cos(origin.latitudeDegrees * radiansPerDegree)) /
            radiansPerDegree,
  ),
);

/// Euclidean length of (x, y), without intermediate overflow or underflow.
///
/// Reproduces glibc's correctly rounded `hypot` (e_hypot.c, the kernel built
/// without fused multiply-add), which is what Overlays' `std::hypot` calls.
/// A cheaper formula is often one ULP off, and that is enough to flip a
/// strict nearest-point comparison, e.g. which side of start/finish a sample
/// projects to.
double hypot(double x, double y) {
  if (!x.isFinite || !y.isFinite) {
    return x.isInfinite || y.isInfinite ? double.infinity : double.nan;
  }
  x = x.abs();
  y = y.abs();
  final ax = x < y ? y : x;
  final ay = x < y ? x : y;
  if (ax > _hypotLarge) {
    if (ay <= ax * _hypotEpsilon) return ax + ay;
    return _hypotKernel(ax * _hypotScale, ay * _hypotScale) / _hypotScale;
  }
  if (ay < _hypotTiny) {
    if (ax >= ay / _hypotEpsilon) return ax + ay;
    return _hypotKernel(ax / _hypotScale, ay / _hypotScale) * _hypotScale;
  }
  if (ay <= ax * _hypotEpsilon) return ax + ay;
  return _hypotKernel(ax, ay);
}

const _hypotScale = 2.409919865102884e-181; // 2^-600
const _hypotLarge = 6.703903964971299e+153; // 2^511
const _hypotTiny = 1.4916681462400413e-154; // 2^-511
const _hypotEpsilon = 5.551115123125783e-17; // 2^-54

// sqrt(ax² + ay²) for ax >= ay, then one correction step for the rounding
// error of the squares, as glibc does.
double _hypotKernel(double ax, double ay) {
  var h = math.sqrt(ax * ax + ay * ay);
  final double t1, t2;
  if (h <= 2.0 * ay) {
    final delta = h - ay;
    t1 = ax * (2.0 * delta - ax);
    t2 = (delta - 2.0 * (ax - ay)) * delta;
  } else {
    final delta = h - ax;
    t1 = 2.0 * delta * (ax - 2.0 * ay);
    t2 = (4.0 * delta - ay) * ay + delta * delta;
  }
  h -= (t1 + t2) / (2.0 * h);
  return h;
}
