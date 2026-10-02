import 'package:telemetry_core/src/laps/segment_geometry.dart';
import 'package:test/test.dart';

void main() {
  const gateA = Vector2(-10, 0);
  const gateB = Vector2(10, 0);

  test('a crossing has distance 0 at the intersection', () {
    final closest = closestSegments(const Vector2(5, -2), const Vector2(5, 6), gateA, gateB);
    expect(closest.distanceMeters, 0.0);
    expect(closest.vehicleFraction, closeTo(0.25, 1e-12));
    expect(closest.gateFraction, closeTo(0.75, 1e-12));
  });

  test('a crossing at the segment end still counts', () {
    final closest = closestSegments(const Vector2(0, -3), const Vector2(0, 0), gateA, gateB);
    expect(closest.distanceMeters, 0.0);
    expect(closest.vehicleFraction, 1.0);
  });

  test('a near miss gives the closest endpoint distance', () {
    final closest = closestSegments(const Vector2(12, -1), const Vector2(14, 3), gateA, gateB);
    expect(closest.distanceMeters, closeTo(2.23606797749979, 1e-12));
    expect(closest.gateFraction, 1.0);
  });

  test('parallel segments use endpoint projections', () {
    final closest = closestSegments(const Vector2(-5, 3), const Vector2(5, 3), gateA, gateB);
    expect(closest.distanceMeters, closeTo(3.0, 1e-12));
    expect(closest.vehicleFraction, 0.0);
    expect(closest.gateFraction, closeTo(0.25, 1e-12));
  });

  test('a stationary vehicle projects onto the gate', () {
    final closest = closestSegments(const Vector2(2, 4), const Vector2(2, 4), gateA, gateB);
    expect(closest.distanceMeters, closeTo(4.0, 1e-12));
    expect(closest.gateFraction, closeTo(0.6, 1e-12));
  });

  test('clamps projections onto a degenerate segment to 0', () {
    expect(
      clampedProjectionFraction(const Vector2(3, 3), const Vector2(1, 1), const Vector2(1, 1)),
      0.0,
    );
    expect(clampedProjectionFraction(const Vector2(30, 0), gateA, gateB), 1.0);
    expect(clampedProjectionFraction(const Vector2(-30, 0), gateA, gateB), 0.0);
  });
}
