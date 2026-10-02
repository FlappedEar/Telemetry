import '../geometry.dart';

/// A 2-D vector in metres.
final class Vector2 {
  const Vector2(this.x, this.y);

  final double x;
  final double y;

  Vector2 operator -(Vector2 other) => Vector2(x - other.x, y - other.y);
  Vector2 operator +(Vector2 other) => Vector2(x + other.x, y + other.y);
  Vector2 operator *(double scale) => Vector2(x * scale, y * scale);
  double dot(Vector2 other) => x * other.x + y * other.y;
  double cross(Vector2 other) => x * other.y - y * other.x;
  double get length => hypot(x, y);
}

/// The closest approach between a vehicle segment and a gate segment.
final class ClosestSegments {
  const ClosestSegments(this.distanceMeters, this.vehicleFraction, this.gateFraction);

  static const none = ClosestSegments(double.infinity, 0.0, 0.0);

  final double distanceMeters;

  /// Position along the vehicle segment, 0 at its start and 1 at its end.
  final double vehicleFraction;

  /// Position along the gate, 0 at endpoint A and 1 at endpoint B.
  final double gateFraction;
}

/// Where [point] projects onto the segment, clamped to [0, 1]. A degenerate
/// segment gives 0.
double clampedProjectionFraction(Vector2 point, Vector2 segmentStart, Vector2 segmentEnd) {
  final segment = segmentEnd - segmentStart;
  final lengthSquared = segment.dot(segment);
  if (!lengthSquared.isFinite || lengthSquared <= 0.0) return 0.0;
  final fraction = (point - segmentStart).dot(segment) / lengthSquared;
  return fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction);
}

/// Distance 0 at the intersection when the segments cross; otherwise the
/// shortest of the four endpoint-to-segment distances.
ClosestSegments closestSegments(
  Vector2 vehicleStart,
  Vector2 vehicleEnd,
  Vector2 gateStart,
  Vector2 gateEnd,
) {
  final vehicle = vehicleEnd - vehicleStart;
  final gate = gateEnd - gateStart;
  final denominator = vehicle.cross(gate);
  if (denominator.isFinite && denominator.abs() > 1e-12) {
    final offset = gateStart - vehicleStart;
    final vehicleFraction = offset.cross(gate) / denominator;
    final gateFraction = offset.cross(vehicle) / denominator;
    if (vehicleFraction >= 0.0 &&
        vehicleFraction <= 1.0 &&
        gateFraction >= 0.0 &&
        gateFraction <= 1.0) {
      return ClosestSegments(0.0, vehicleFraction, gateFraction);
    }
  }

  var best = ClosestSegments.none;
  void consider(Vector2 first, Vector2 second, double vehicleFraction, double gateFraction) {
    final distance = (first - second).length;
    if (distance.isFinite && distance < best.distanceMeters) {
      best = ClosestSegments(distance, vehicleFraction, gateFraction);
    }
  }

  final gateForVehicleStart = clampedProjectionFraction(vehicleStart, gateStart, gateEnd);
  consider(vehicleStart, gateStart + gate * gateForVehicleStart, 0.0, gateForVehicleStart);
  final gateForVehicleEnd = clampedProjectionFraction(vehicleEnd, gateStart, gateEnd);
  consider(vehicleEnd, gateStart + gate * gateForVehicleEnd, 1.0, gateForVehicleEnd);
  final vehicleForGateStart = clampedProjectionFraction(gateStart, vehicleStart, vehicleEnd);
  consider(vehicleStart + vehicle * vehicleForGateStart, gateStart, vehicleForGateStart, 0.0);
  final vehicleForGateEnd = clampedProjectionFraction(gateEnd, vehicleStart, vehicleEnd);
  consider(vehicleStart + vehicle * vehicleForGateEnd, gateEnd, vehicleForGateEnd, 1.0);
  return best;
}
