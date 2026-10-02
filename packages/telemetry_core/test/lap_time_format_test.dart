import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  test('rounds before splitting minutes, so a time never reads x:60', () {
    expect(formatLapTime(59.96, 1), '1:00.0');
    expect(formatLapTime(59.95, 1), '1:00.0'); // half away from zero
    expect(formatLapTime(59.94, 1), '0:59.9');
    expect(formatLapTime(60.0, 1), '1:00.0');
    expect(formatLapTime(59.995, 2), '1:00.00');
    expect(formatLapTime(119.996, 2), '2:00.00');
    expect(formatLapTime(119.995, 2), '2:00.00');
    expect(formatLapTime(119.994, 2), '1:59.99');
    expect(formatLapTime(3599.9995, 3), '60:00.000');
    expect(formatLapTime(3599.9994, 3), '59:59.999');
    expect(formatLapTime(100.234, 2), '1:40.23');
    expect(formatLapTime(100.234, 3), '1:40.234');
    expect(formatLapTime(65.4, 0), '1:05');
    expect(formatLapTime(0.0, 3), '0:00.000');
    expect(formatLapTime(5.5, 9), '0:05.500'); // at most 3 decimals
    expect(formatLapTime(-0.001, 2), isNull);
    expect(formatLapTime(double.nan, 2), isNull);
    expect(formatLapTime(double.infinity, 2), isNull);
  });
}
