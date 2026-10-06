// Truth tests for fusion conflicts (FET-201): two recordings of one
// quantity conflict when they disagree where it matters, not only when
// their median difference is large.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

/// A brake pressure trace in %: 0 while not braking, braking zones of
/// 2 s every 10 s rising to [peak].
double _brake(double t, {double peak = 90.0}) {
  final phase = t % 10.0;
  return phase < 2.0 ? peak * math.sin(phase / 2.0 * math.pi) : 0.0;
}

double _throttle(double t) {
  final phase = t % 10.0;
  if (phase < 2.0) return 0.0;
  return math.min(100.0, (phase - 2.0) * 25.0);
}

(List<double>, List<double>) _pair(
  double Function(double t) primary,
  double Function(double t) alternative, {
  double seconds = 120.0,
  double step = 0.1,
}) {
  final a = <double>[], r = <double>[];
  for (var t = 0.0; t < seconds; t += step) {
    a.add(alternative(t));
    r.add(primary(t));
  }
  return (a, r);
}

TelemetrySession _session(
  String unit,
  double Function(double t) value, {
  double step = 0.1,
  double seconds = 120.0,
}) {
  final times = <double>[], values = <double>[];
  for (var index = 0; index * step <= seconds + 1e-9; ++index) {
    times.add(index * step);
    values.add(value(index * step));
  }
  return TelemetrySession(
    duration: times.last,
    startTime: 0,
    metadata: const {},
    channels: {
      'brake': TelemetryChannel(
        name: 'brake',
        unit: unit,
        timestamps: Float64List.fromList(times),
        values: Float32List.fromList(values),
      ),
    },
    aliases: const {'brake': 'brake'},
    warnings: const [],
    timingGates: const [],
    sampleCount: times.length,
  );
}

void main() {
  test('brakes that agree at rest but not while braking conflict', () {
    // 80 % of the samples are 0 in both; in every braking zone the
    // alternative reads half: the median difference is 0.
    final (a, r) = _pair(_brake, (t) => _brake(t, peak: 45.0));
    final measures = fusionConflictMeasures(a, r, fusionConflictTolerance('%', 90.0));
    expect(measures.median, 0.0);
    expect(measures.activeFractionOver, greaterThan(0.5));
    expect(measures.conflicting, isTrue);
  });

  test('throttles that disagree only above 90 % conflict', () {
    final (a, r) = _pair(_throttle, (t) => _throttle(t) > 90.0 ? 80.0 : _throttle(t));
    final measures = fusionConflictMeasures(a, r, fusionConflictTolerance('%', 100.0));
    expect(measures.median, 0.0);
    expect(measures.conflicting, isTrue);
  });

  test('a sensor that clips conflicts with one that does not', () {
    final (a, r) = _pair(_throttle, (t) => math.min(_throttle(t), 70.0));
    expect(fusionConflictMeasures(a, r, 3.0).conflicting, isTrue);
  });

  test('a primary stuck at 0 conflicts with a working alternative', () {
    final (a, r) = _pair((_) => 0.0, _brake);
    final measures = fusionConflictMeasures(a, r, 3.0);
    expect(measures.median, 0.0);
    expect(measures.conflicting, isTrue);
  });

  test('two recordings of one signal with small noise do not conflict', () {
    final random = math.Random(201);
    final (a, r) = _pair(_brake, (t) => _brake(t) + (random.nextDouble() - 0.5) * 2.0);
    final measures = fusionConflictMeasures(a, r, 3.0);
    expect(measures.conflicting, isFalse);
  });

  test('occasional spikes on a fast signal do not conflict', () {
    // A vibrating 100 Hz accelerometer read 2 ms apart, with 3 % of the
    // samples spiking by six tolerances (the real day reaches 6 %).
    final random = math.Random(2010);
    double signal(double t) => 0.4 * math.sin(t * 40.0);
    final (a, r) = _pair(
      signal,
      (t) => signal(t + 0.002) + (random.nextDouble() < 0.03 ? 0.3 : 0.0),
      step: 0.01,
      seconds: 60.0,
    );
    final measures = fusionConflictMeasures(a, r, 0.05);
    expect(measures.median, lessThanOrEqualTo(0.05));
    expect(measures.fractionOver, greaterThan(0.01));
    expect(measures.conflicting, isFalse);
  });

  test('fewer than 10 samples never conflict', () {
    expect(fusionConflictMeasures([0, 0, 0], [50, 50, 50], 3.0).conflicting, isFalse);
  });

  test('fusion reports the brake conflict and keeps the primary until a rule is chosen', () {
    final primary = _session('%', _brake);
    final alternative = _session('%', (t) => _brake(t, peak: 45.0));
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    final brake = result.channels.firstWhere((channel) => channel.key == 'brake');
    expect(brake.medianDifference, 0.0);
    expect(brake.conflicting, isTrue);
    expect(brake.rule, 'unresolvedConflict');
    expect(result.unresolved, ['brake']);
  });

  test('an undeclared unit that disagrees while braking is not fused as the same unit', () {
    // A 0..1 brake against a % brake: equal at rest, a scale apart when
    // braking. The median would call them the same unit.
    final primary = _session('%', _brake);
    final alternative = _session('', (t) => _brake(t) / 100.0);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, ['brake: rcz']);
  });

  test('a VBO brake with no unit that disagrees only while braking is a visible conflict', () {
    // A VBO declares no unit (KAN-184). Same scale, half the pressure in
    // every braking zone: the driver must see it, not a hidden mismatch.
    final primary = _session('', _brake);
    final alternative = _session('%', (t) => _brake(t, peak: 45.0));
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, isEmpty);
    expect(result.unresolved, ['brake']);
  });

  test('an undeclared unit that agrees everywhere is fused as the same unit', () {
    final primary = _session('', _brake);
    final alternative = _session('%', _brake);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, isEmpty);
    expect(result.unresolved, isEmpty);
  });

  test('an undeclared unit with fewer than 10 samples in the overlap is a mismatch', () {
    final primary = _session('%', _brake);
    final alternative = _session('', _brake, seconds: 0.5);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, ['brake: rcz']);
  });

  test('one stray low sample does not hide a conflict while braking', () {
    // The overlap minimum would sit at -50 and call every sample active.
    final (a, r) = _pair(_brake, (t) => _brake(t, peak: 45.0));
    r[7] = -50.0;
    final measures = fusionConflictMeasures(a, r, 3.0);
    expect(measures.activeFractionOver, greaterThan(0.5));
    expect(measures.conflicting, isTrue);
  });

  test('a 1 Hz primary and a 10 Hz alternative of one brake do not conflict', () {
    // Interpolating the 1 Hz primary at 10 Hz cuts every peak; compared at
    // the 1 Hz samples the two agree.
    final primary = _session('%', _brake, step: 1.0);
    final alternative = _session('%', _brake);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    final brake = result.channels.firstWhere((channel) => channel.key == 'brake');
    expect(brake.conflicting, isFalse);
    expect(result.unresolved, isEmpty);
  });

  test('a 1 Hz primary that disagrees with a 10 Hz alternative while braking conflicts', () {
    final primary = _session('%', (t) => _brake(t + 0.5, peak: 45.0), step: 1.0);
    final alternative = _session('%', (t) => _brake(t + 0.5));
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unresolved, ['brake']);
  });

  test('a brake used rarely that disagrees only while braking conflicts by the active rule', () {
    // Braking 0.5 s in every 10 s: 5 % of the samples. The overall share of
    // far-off samples stays under 10 %, the median is 0; only where the
    // brake is in use do the two disagree.
    double rare(double t, double peak) {
      final phase = t % 10.0;
      return phase < 0.5 ? peak * math.sin(phase / 0.5 * math.pi) : 0.0;
    }

    final (a, r) = _pair((t) => rare(t, 90.0), (t) => rare(t, 45.0));
    final measures = fusionConflictMeasures(a, r, 3.0);
    expect(measures.median, 0.0);
    expect(measures.fractionOver, lessThanOrEqualTo(fusionConflictFraction));
    expect(measures.activeFractionOver, greaterThan(fusionActiveConflictFraction));
    expect(measures.conflicting, isTrue);
  });

  test('a signal that drifts apart over a fifth of the session conflicts by the overall rule', () {
    // A signal with no rest value (always active): the active rule sees
    // what the overall rule sees, so the overall share alone decides.
    double level(double t) => 50.0 + 20.0 * math.sin(t / 3.0);
    final (a, r) = _pair(level, (t) => t > 90.0 ? level(t) + 15.0 : level(t));
    final measures = fusionConflictMeasures(a, r, 3.0);
    expect(measures.median, 0.0);
    expect(measures.fractionOver, greaterThan(fusionConflictFraction));
    expect(measures.conflicting, isTrue);
    // Over a twentieth only, it does not.
    final (b, q) = _pair(level, (t) => t > 115.0 ? level(t) + 15.0 : level(t));
    expect(fusionConflictMeasures(b, q, 3.0).conflicting, isFalse);
  });

  test('a VBO brake with no unit stuck at 0 is a visible conflict', () {
    final primary = _session('', (_) => 0.0);
    final alternative = _session('%', _brake);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, isEmpty);
    expect(result.unresolved, ['brake']);
  });

  test('a VBO brake with no unit reading under half is a visible conflict', () {
    final primary = _session('', _brake);
    final alternative = _session('%', (t) => _brake(t, peak: 40.0));
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, isEmpty);
    expect(result.unresolved, ['brake']);
  });

  test('a speed in m/s against one in km/h is a unit mismatch, never fused', () {
    final primary = _session('km/h', (t) => 100.0 + 50.0 * math.sin(t / 5.0));
    final alternative = _session('', (t) => (100.0 + 50.0 * math.sin(t / 5.0)) / 3.6);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, ['brake: rcz']);
  });

  test('an undeclared unit with a median difference over the limit is a mismatch', () {
    // An offset scale (°F against °C) agrees in spread but not in value.
    final primary = _session('C', (t) => 80.0 + 5.0 * math.sin(t));
    final alternative = _session('', (t) => 80.0 + 5.0 * math.sin(t) + 20.0);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, ['brake: rcz']);
  });

  test('a short overlap still conflicts by the median at the alternative rate', () {
    // 5 s of a 10 Hz alternative against a 1 Hz primary: 51 samples for
    // the median, 6 at the primary's rate.
    final primary = _session('%', (_) => 50.0, step: 1.0);
    final alternative = _session('%', (_) => 0.0, seconds: 5.0);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    final brake = result.channels.firstWhere((channel) => channel.key == 'brake');
    expect(brake.comparedSamples, greaterThanOrEqualTo(10));
    expect(brake.medianDifference, 50.0);
    expect(result.unresolved, ['brake']);
  });

  test('the median is measured at the alternative samples, as Overlays does', () {
    // A 1 Hz primary at 0 and a 10 Hz sawtooth that is 0 on every whole
    // second: at the primary's samples they agree, at the alternative's
    // the typical difference is about 4.
    double saw(double t) => (((t + 1e-9) % 1.0) * 10.0).floorToDouble();
    final primary = _session('%', (t) => 0.0, step: 1.0);
    final alternative = _session('%', saw);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    final brake = result.channels.firstWhere((channel) => channel.key == 'brake');
    expect(brake.medianDifference, closeTo(4.0, 1e-4));
  });

  test('a short recording with a few far-off samples conflicts by the overall rule', () {
    // 50 samples, 8 of them far off: too few active samples (under 10) for
    // the active rule, a median of 0, but 16 % of everything is far off.
    final a = [for (var index = 0; index < 50; ++index) index % 6 == 0 && index < 48 ? 60.0 : 0.0];
    final r = List<double>.filled(50, 0.0);
    final measures = fusionConflictMeasures(a, r, 3.0);
    expect(measures.median, 0.0);
    expect(measures.activeFractionOver, 0.0);
    expect(measures.fractionOver, greaterThan(fusionConflictFraction));
    expect(measures.conflicting, isTrue);
  });

  test('a dead VBO brake picking up noise is a conflict, not a unit', () {
    // ±0.5 of noise against a 0..90 % brake: spreads about 100 apart.
    final random = math.Random(2011);
    final primary = _session('', (_) => random.nextDouble() - 0.5);
    final alternative = _session('%', _brake);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, isEmpty);
    expect(result.unresolved, ['brake']);
  });

  test('a VBO brake reading 27 % of the other is a conflict, not km/h against m/s', () {
    final primary = _session('', (t) => _brake(t) * 0.27);
    final alternative = _session('%', _brake);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, isEmpty);
    expect(result.unresolved, ['brake']);
  });

  test('a g channel against an undeclared m/s² one with a little noise is a unit mismatch', () {
    final random = math.Random(2012);
    double g(double t) => 0.8 * math.sin(t / 2.0);
    final primary = _session('g', (t) => g(t) + (random.nextDouble() - 0.5) * 0.04);
    final alternative = _session('', (t) => g(t) * 9.80665);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ]);
    expect(result.unitMismatches, ['brake: rcz']);
    expect(
      fusionScalesDiffer(
        [for (var t = 0.0; t < 60.0; t += 0.1) g(t) * 9.80665],
        [for (var t = 0.0; t < 60.0; t += 0.1) g(t) + (random.nextDouble() - 0.5) * 0.04],
        0.05,
        unit: 'g',
      ),
      isTrue,
    );
  });
}
