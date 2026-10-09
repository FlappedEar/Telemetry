// Temperature associations (analysis/temperature_association.dart,
// KAN-100), ported from FlappedEar Overlays
// native/tests/TemperatureAssociationTests.cpp: Spearman rank correlation
// with ties, minimum population, no spread, non-finite pairs, and the
// time-of-day confound.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  test('ranks monotonic associations', () {
    const temperature = <double>[90, 91, 92, 93, 94, 95, 96, 97, 98, 99];
    // Monotonic but not linear: still +1.
    final rising = [for (final value in temperature) math.exp(value / 10.0)];
    expect(spearmanCorrelation(temperature, rising).coefficient, 1.0);
    expect(spearmanCorrelation(temperature, rising.reversed.toList()).coefficient, -1.0);
    // A known value: one swapped pair among 10 gives 1 - 6*2/(10*99).
    const swapped = <double>[1, 2, 3, 4, 5, 6, 7, 8, 10, 9];
    expect(
      spearmanCorrelation(temperature, swapped).coefficient,
      closeTo(1.0 - 12.0 / 990.0, 1e-12),
    );
    expect(associationStrength(0.29), 'weak');
    expect(associationStrength(-0.45), 'moderate');
    expect(associationStrength(0.6), 'strong');
    expect(associationStrength(-0.95), 'strong');
  });

  test('averages tied ranks', () {
    // Quantized sensor values tie; ties share their average rank.
    const temperature = <double>[90, 90, 91, 91, 92, 92, 93, 93];
    const lapTime = <double>[110, 110, 111, 111, 112, 112, 113, 113];
    expect(spearmanCorrelation(temperature, lapTime).coefficient, 1.0);
    const mixed = <double>[110, 111, 110, 111, 112, 113, 112, 113];
    final result = spearmanCorrelation(temperature, mixed);
    expect(result.coefficient, isNotNull);
    expect(result.coefficient!, inExclusiveRange(0.5, 1.0));
  });

  test('requires a population and spread', () {
    const seven = <double>[1, 2, 3, 4, 5, 6, 7];
    final tooFew = spearmanCorrelation(seven, seven);
    expect(tooFew.count, 7);
    expect(tooFew.coefficient, isNull);
    expect(tooFew.unavailableReason, associationTooFewSamples);
    expect(spearmanCorrelation(seven, seven, 3).coefficient, isNotNull);
    // A temperature that never changes cannot be associated with anything.
    final flat = List<double>.filled(10, 95.0);
    const times = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    final noSpread = spearmanCorrelation(flat, times);
    expect(noSpread.coefficient, isNull);
    expect(noSpread.unavailableReason, associationNoSpread);
    expect(spearmanCorrelation([], []).coefficient, isNull);
    expect(spearmanCorrelation([1.0], [1.0], 0).coefficient, isNull);
  });

  test('skips non-finite pairs', () {
    const nan = double.nan, inf = double.infinity;
    const temperature = <double>[90, 91, nan, 92, 93, 94, 95, 96, 97, inf, 98];
    const lapTime = <double>[100, 101, 102, 103, nan, 104, 105, 106, 107, 108, 109];
    final result = spearmanCorrelation(temperature, lapTime);
    expect(result.count, 8);
    expect(result.coefficient, 1.0);
    // Mismatched lengths use the common prefix.
    expect(spearmanCorrelation([1, 2, 3], [1, 2], 2).count, 2);
  });

  test('flags a time-of-day confound', () {
    // Oil warms through the day while the driver gets faster: a strong
    // association that cannot be told apart from the day's progression.
    final warming = [
      for (var lap = 0; lap < 12; ++lap)
        AssociationObservation(100.0 + lap, 120.0 - lap * 0.8, lap * 150.0),
    ];
    final confounded = associateTemperature(warming);
    expect(confounded.withValue.coefficient, -1.0);
    expect(confounded.withOrder.coefficient, 1.0);
    expect(confounded.confoundedByOrder, isTrue);

    // Temperature that varies independently of the order is not flagged.
    const temperatures = <double>[104, 99, 107, 101, 103, 98, 106, 100, 105, 102, 97, 108];
    final independent = [
      for (var lap = 0; lap < temperatures.length; ++lap)
        AssociationObservation(
          temperatures[lap],
          110.0 + (temperatures[lap] - 100.0) * 0.2,
          lap * 150.0,
        ),
    ];
    final result = associateTemperature(independent);
    expect(result.withValue.coefficient, 1.0);
    expect(result.withOrder.coefficient!.abs(), lessThan(associationOrderConfoundLevel));
    expect(result.confoundedByOrder, isFalse);

    // Too few laps: nothing is claimed either way.
    final few = associateTemperature(warming.sublist(0, 5));
    expect(few.withValue.coefficient, isNull);
    expect(few.confoundedByOrder, isFalse);
  });

  test("measures a lap's strong acceleration", () {
    // 100 samples over 10 s: 0.01 .. 0.50 g on the way out of corners,
    // braking in between, and one implausible 9 g spike that is ignored.
    TelemetrySession session({String unit = '', bool alias = true}) => TelemetrySession(
      duration: 9.9,
      startTime: 0,
      metadata: const {},
      channels: {
        'longacc-calc': TelemetryChannel(
          name: 'longacc-calc',
          unit: unit,
          timestamps: Float64List.fromList([for (var k = 0; k < 100; ++k) k * 0.1]),
          values: Float32List.fromList([
            for (var k = 0; k < 100; ++k)
              k == 50
                  ? 9.0
                  : k.isOdd
                  ? 0.01 * (k ~/ 2 + 1)
                  : -0.6,
          ]),
        ),
      },
      aliases: alias ? const {'longitudinalAcceleration': 'longacc-calc'} : const {},
      warnings: const [],
      timingGates: const [],
      sampleCount: 100,
    );
    final lap = lapStrongAcceleration(session(), 0.0, 10.0);
    expect(lap.channel, 'longacc-calc');
    expect(lap.sampleCount, 50);
    expect(lap.strongG, closeTo(0.45, 1e-6)); // the 45th of 50 values
    // A shorter window with too few positive samples has no value.
    expect(lapStrongAcceleration(session(), 0.0, 3.0).strongG, isNull);
    expect(lapStrongAcceleration(session(), 5.0, 5.0).strongG, isNull);
    // m/s² is read as g (FET-288): 9 m/s² is 0.92 g, within the plausible
    // range, so the 90th percentile is the 46th of 51 values, 0.46 m/s².
    expect(
      lapStrongAcceleration(session(unit: 'm/s^2'), 0.0, 10.0).strongG,
      closeTo(0.46 / standardGravity, 1e-6),
    );
    // A unit that is not an acceleration gives none.
    expect(lapStrongAcceleration(session(unit: 'km/h'), 0.0, 10.0).strongG, isNull);
    expect(lapStrongAcceleration(session(unit: ' G '), 0.0, 10.0).strongG, isNotNull);
    expect(lapStrongAcceleration(session(alias: false), 0.0, 10.0).channel, isEmpty);
  });
}
