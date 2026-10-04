import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  final path = LapPath(
    origin: const GeoCoordinate(0, 0),
    segments: [
      [
        const PathPoint(0, 0, 0, null),
        const PathPoint(1, 10, 0, null),
        const PathPoint(2, 10, 20, null),
      ],
      // After a GPS gap.
      [const PathPoint(5, 50, 50, null), const PathPoint(6, 60, 50, null)],
    ],
  );

  test('a time between two fixes is between them', () {
    expect(lapPathPointAt(path, 0.5), (east: 5.0, north: 0.0));
    expect(lapPathPointAt(path, 1.5), (east: 10.0, north: 10.0));
    expect(lapPathPointAt(path, 2), (east: 10.0, north: 20.0));
    expect(lapPathPointAt(path, 5.5), (east: 55.0, north: 50.0));
  });

  test('none in a gap or outside the lap', () {
    expect(lapPathPointAt(path, 3), isNull);
    expect(lapPathPointAt(path, -1), isNull);
    expect(lapPathPointAt(path, 7), isNull);
    expect(
      lapPathPointAt(LapPath(origin: const GeoCoordinate(0, 0), segments: const []), 1),
      isNull,
    );
  });
}
