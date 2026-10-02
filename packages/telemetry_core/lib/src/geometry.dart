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

/// Equirectangular projection of [coordinate] around [origin], in metres.
/// Accurate enough over the size of a circuit.
MetricPoint projectCoordinate(GeoCoordinate coordinate, GeoCoordinate origin) {
  return MetricPoint(
    (coordinate.longitudeDegrees - origin.longitudeDegrees) *
        radiansPerDegree *
        earthRadiusMeters *
        math.cos(origin.latitudeDegrees * radiansPerDegree),
    (coordinate.latitudeDegrees - origin.latitudeDegrees) * radiansPerDegree * earthRadiusMeters,
  );
}

/// Euclidean length of (x, y), without intermediate overflow.
double hypot(double x, double y) {
  final a = x.abs();
  final b = y.abs();
  if (a == double.infinity || b == double.infinity) return double.infinity;
  if (a.isNaN || b.isNaN) return double.nan;
  final larger = a > b ? a : b;
  if (larger == 0.0 || !larger.isFinite) return larger;
  final smaller = a > b ? b : a;
  final ratio = smaller / larger;
  return larger * math.sqrt(1.0 + ratio * ratio);
}
