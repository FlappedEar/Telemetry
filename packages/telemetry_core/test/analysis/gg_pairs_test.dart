// Ports GgPairsTests.cpp of FlappedEar Overlays (revision d4d1039): timed
// longitudinal/lateral acceleration pairs for G-G analysis.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

TelemetryChannel _channel(
  String name,
  String unit,
  List<double> times,
  double Function(double) value,
) => TelemetryChannel(
  name: name,
  unit: unit,
  timestamps: Float64List.fromList(times),
  values: Float32List.fromList([for (final t in times) value(t)]),
);

List<double> _clock(double start, double end, double step) => [
  for (var time = start; time <= end + 1e-9; time += step) time,
];

TelemetrySession _session(Map<String, TelemetryChannel> aliased) => TelemetrySession(
  duration: 0,
  startTime: 0,
  metadata: const {},
  channels: {for (final channel in aliased.values) channel.name: channel},
  aliases: {for (final entry in aliased.entries) entry.key: entry.value.name},
  warnings: const [],
  timingGates: const [],
  sampleCount: 0,
);

TelemetrySession _gg(TelemetryChannel longitudinal, TelemetryChannel lateral) =>
    _session({'longitudinalAcceleration': longitudinal, 'lateralAcceleration': lateral});

void main() {
  test('pairs samples on a shared clock', () {
    // Braking (-0.8 g) while turning left (+0.6 g), then accelerating right.
    final times = _clock(0.0, 1.0, 0.1);
    final session = _gg(
      _channel('longacc', 'g', times, (t) => t < 0.5 ? -0.8 : 0.3),
      _channel('latacc', 'g', times, (t) => t < 0.5 ? 0.6 : -0.4),
    );
    final pairs = buildGgPairs(session, 0.0, 1.0);
    expect(pairs.valid, isTrue);
    expect(pairs.sharedClock, isTrue);
    expect(pairs.points, hasLength(times.length));
    expect(pairs.candidateCount, times.length);
    expect(pairs.longitudinalChannel, 'longacc');
    expect(pairs.unitsDeclared, isTrue);
    expect(pairs.maximumPairingOffsetSeconds, 0.0);
    // Signs are kept as recorded.
    expect(pairs.points.first.longitudinalG, closeTo(-0.8, 1e-6));
    expect(pairs.points.first.lateralG, closeTo(0.6, 1e-6));
    expect(pairs.points.last.lateralG, closeTo(-0.4, 1e-6));
    // Only the requested range.
    expect(buildGgPairs(session, 0.25, 0.55).points, hasLength(3));
  });

  test('interpolates lateral on another clock without bridging gaps', () {
    // Longitudinal at 10 Hz; lateral at 20 Hz offset by 25 ms, linear in
    // time, with a 0.5 s hole from 0.4 to 0.9 s.
    final lateralTimes = [
      for (var time = 0.025; time <= 1.525; time += 0.05)
        if (time < 0.4 || time > 0.9) time,
    ];
    final session = _gg(
      _channel('longacc', 'g', _clock(0.0, 1.5, 0.1), (_) => -0.5),
      _channel('latacc', 'g', lateralTimes, (t) => t),
    );
    final pairs = buildGgPairs(session, 0.0, 1.5);
    expect(pairs.valid, isTrue);
    expect(pairs.sharedClock, isFalse);
    expect(pairs.maximumPairingOffsetSeconds, closeTo(0.025, 1e-6));
    for (final point in pairs.points) {
      expect(point.lateralG, closeTo(point.time, 1e-5));
      expect(point.time < 0.4 || point.time > 0.9, isTrue, reason: 'nothing across the hole');
    }
    expect(pairs.skippedForGap, greaterThanOrEqualTo(5));
    expect(pairs.points.length + pairs.skippedForGap, pairs.candidateCount);
    // No lateral sample on both sides of t = 0: skipped, not extrapolated.
    expect(pairs.points.first.time, greaterThan(0.0));
  });

  test('converts or rejects units', () {
    final times = _clock(0.0, 0.5, 0.1);
    var pairs = buildGgPairs(
      _gg(
        _channel('longacc', 'm/s^2', times, (_) => -9.80665),
        _channel('latacc', 'm/s²', times, (_) => 4.903325),
      ),
      0.0,
      0.5,
    );
    expect(pairs.valid, isTrue);
    expect(pairs.points.first.longitudinalG, closeTo(-1.0, 1e-5));
    expect(pairs.points.first.lateralG, closeTo(0.5, 1e-5));

    pairs = buildGgPairs(
      _gg(_channel('longacc', '', times, (_) => 0.2), _channel('latacc', '', times, (_) => 0.1)),
      0.0,
      0.5,
    );
    expect(pairs.valid, isTrue);
    expect(pairs.unitsDeclared, isFalse, reason: 'kept, and reported as undeclared');

    pairs = buildGgPairs(
      _gg(
        _channel('longacc', 'km/h', times, (_) => 1.0),
        _channel('latacc', 'g', times, (_) => 0.1),
      ),
      0.0,
      0.5,
    );
    expect(pairs.valid, isFalse);
    expect(pairs.unavailableReason, ggUnsupportedUnit);
    expect(pairs.points, isEmpty);
  });

  test('excludes outliers and missing axes', () {
    final times = _clock(0.0, 0.9, 0.1);
    final session = _gg(
      _channel(
        'longacc',
        'g',
        times,
        (t) => (t - 0.3).abs() < 1e-6
            ? 12.0
            : (t - 0.5).abs() < 1e-6
            ? double.nan
            : -0.4,
      ),
      _channel('latacc', 'g', times, (_) => 0.7),
    );
    final pairs = buildGgPairs(session, 0.0, 0.9);
    expect(pairs.excludedOutliers, 1, reason: '12 g is not plausible for a road car');
    expect(pairs.candidateCount, times.length - 1, reason: 'the NaN sample is no candidate');
    expect(pairs.points, hasLength(times.length - 2));
    for (final point in pairs.points) {
      expect(point.longitudinalG.abs(), lessThanOrEqualTo(ggPlausibleLimitG));
    }

    final missing = buildGgPairs(
      _session({'longitudinalAcceleration': _channel('longacc', 'g', times, (_) => 0.1)}),
      0.0,
      0.9,
    );
    expect(missing.valid, isFalse);
    expect(missing.unavailableReason, ggMissingLateral);
    expect(missing.points, isEmpty);
    expect(buildGgPairs(_session(const {}), 0.0, 1.0).unavailableReason, ggMissingLongitudinal);
    expect(buildGgPairs(session, 1.0, 0.5).points, isEmpty, reason: 'inverted range');
  });

  test('computes peaks independently of decimation', () {
    // 5000 points of a gentle circle, one braking spike and one lateral spike.
    final points = [
      for (var i = 0; i < 5000; ++i)
        GgPoint(i * 0.01, 0.3 * math.cos(i * 0.01), 0.3 * math.sin(i * 0.01)),
    ];
    points[1234] = GgPoint(points[1234].time, -1.1, points[1234].lateralG);
    points[3777] = GgPoint(points[3777].time, points[3777].longitudinalG, -1.05);
    final peaks = computeGgPeaks(points);
    expect(peaks.sampleCount, 5000);
    expect(peaks.braking!.value, closeTo(1.1, 1e-9));
    expect(peaks.braking!.point.time, points[1234].time);
    expect(peaks.lateral!.value, closeTo(1.05, 1e-9));
    expect(peaks.combined!.value, greaterThanOrEqualTo(1.1));
    expect(peaks.acceleration!.value, closeTo(0.3, 1e-3));
    final shown = decimateGgPoints(points, peaks, 300);
    expect(shown.length, lessThanOrEqualTo(304));
    // Decimation keeps the peak points and does not change the peaks.
    final again = computeGgPeaks(shown);
    expect(again.braking!.value, closeTo(peaks.braking!.value, 1e-12));
    expect(again.lateral!.value, closeTo(peaks.lateral!.value, 1e-12));
    expect(again.combined!.value, closeTo(peaks.combined!.value, 1e-12));
    expect(decimateGgPoints(points, peaks, 0), hasLength(points.length));
    expect(computeGgPeaks(const []).braking, isNull);
  });
}
