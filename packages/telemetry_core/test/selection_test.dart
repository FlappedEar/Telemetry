// selectKth (FET-41) finds the sorted value without sorting.
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/src/selection.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  test('the kth value is the sorted value', () {
    final random = Random(3);
    for (var trial = 0; trial < 2000; ++trial) {
      final count = 1 + random.nextInt(40);
      final pool = [0.5, 1.0, 1.0, 2.0, -3.0, 7.25];
      final values = [
        for (var i = 0; i < count; ++i)
          random.nextBool() ? pool[random.nextInt(pool.length)] : random.nextDouble() * 10 - 5,
      ];
      final sorted = [...values]..sort();
      final k = random.nextInt(count);
      expect(selectKth(Float64List.fromList(values), count, k), sorted[k]);
    }
  });

  test('a zero placeholder is decided by the median as before', () {
    final random = Random(5);
    for (var trial = 0; trial < 500; ++trial) {
      final values = Float32List.fromList([
        for (var i = 0; i < 1 + random.nextInt(30); ++i)
          [0.0, -0.0, 0.5, 2.0, 90.0, double.nan][random.nextInt(6)],
      ]);
      final finite = [
        for (final value in values)
          if (value.isFinite) value,
      ]..sort();
      final expected =
          finite.isNotEmpty &&
          finite[finite.length ~/ 2].abs() > temperatureSummaryPolicy.placeholderTypicalAbove;
      final channel = TelemetryChannel(
        name: 'oil temp',
        timestamps: Float64List.fromList([for (var i = 0; i < values.length; ++i) i * 0.1]),
        values: values,
      );
      expect(zeroIsPlaceholder(channel, temperatureSummaryPolicy), expected);
    }
  });
}
