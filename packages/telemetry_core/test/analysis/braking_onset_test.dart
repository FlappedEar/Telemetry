// Braking-onset candidates with explicit provenance (braking_onset.dart),
// ported from Overlays' BrakingOnsetTests.cpp: measured brake with explicit
// hysteresis thresholds, otherwise deceleration labelled inferred; spikes,
// gaps and units are handled, never manufactured.
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _dt = 0.05; // 20 Hz
const _sampleCount = 201; // t = 0 .. 10 s

// Sample k at t = k * dt; [value] may return NaN; [present] false omits it.
TelemetryChannel _channel(
  String name,
  String unit,
  double Function(int) value, [
  bool Function(int)? present,
]) {
  final ks = [
    for (var k = 0; k < _sampleCount; ++k)
      if (present?.call(k) ?? true) k,
  ];
  return TelemetryChannel(
    name: name,
    unit: unit,
    timestamps: Float64List.fromList([for (final k in ks) k * _dt]),
    values: Float32List.fromList([for (final k in ks) value(k)]),
  );
}

// 0 until k=100 (5.0 s), ramps to 80 over 4 samples, holds, releases over 4
// samples from k=140 (7.0 s).
double _brakeProfile(int k) {
  if (k <= 100) return 0.0;
  if (k < 104) return (k - 100) * 20.0;
  if (k <= 140) return 80.0;
  if (k < 144) return 80.0 - (k - 140) * 20.0;
  return 0.0;
}

// 0 until k=120 (6.0 s), ramps to -0.8 g over 4 samples, holds until k=140.
double _decelerationProfile(int k) {
  if (k <= 120) return 0.0;
  if (k < 124) return -(k - 120) * 0.2;
  if (k <= 140) return -0.8;
  return 0.0;
}

TelemetrySession _session(Map<String, TelemetryChannel> aliased) => TelemetrySession(
  duration: (_sampleCount - 1) * _dt,
  startTime: 0,
  metadata: const {},
  channels: {for (final channel in aliased.values) channel.name: channel},
  aliases: {for (final MapEntry(:key, :value) in aliased.entries) key: value.name},
  warnings: const [],
  timingGates: const [],
  sampleCount: _sampleCount,
);

TelemetrySession _brake([
  double Function(int) value = _brakeProfile,
  bool Function(int)? present,
]) => _session({'brake': _channel('brake_pos', '%', value, present)});

void main() {
  test('a measured brake uses an explicit threshold crossing', () {
    // A deceleration event at 2 s does not appear: a brake channel exists.
    final result = detectBrakingOnsets(
      _session({
        'brake': _channel('brake_pos', '%', _brakeProfile),
        'longitudinalAcceleration': _channel('longacc', 'g', (k) => k >= 40 && k < 60 ? -0.9 : 0.0),
      }),
      0.0,
      10.0,
    );
    expect(result.valid, isTrue);
    expect(result.unresolvedReason, isEmpty);
    expect(result.method, brakingMethodMeasured);
    expect(result.provenance, brakingProvenanceMeasured);
    expect(result.channel, 'brake_pos');
    expect(result.channelUnit, '%');
    expect([result.threshold.on, result.threshold.off, result.threshold.unit], [10.0, 5.0, '%']);
    expect(result.candidates, hasLength(1));
    final onset = result.candidates.first;
    // 0 at 5.00 s, 20 at 5.05 s: the 10% crossing is interpolated at 5.025 s.
    expect(onset.telemetryTime, closeTo(5.025, 1e-3));
    expect(onset.toleranceSeconds, closeTo(_dt, 1e-6));
    expect(onset.peakValue, closeTo(80.0, 1e-3));
    expect(onset.durationSeconds, inExclusiveRange(2.0, 2.3));
    expect(onset.uncertaintyReasons, isEmpty);
    expect(onset.progressMeters, isNull);
    expect(result.rejectedSpikes, 0);
    expect(result.gaps, 0);
  });

  test('brief spikes are rejected and chatter is held', () {
    final spikes = detectBrakingOnsets(_brake((k) => k == 60 ? 50.0 : _brakeProfile(k)), 0.0, 10.0);
    expect(spikes.rejectedSpikes, 1);
    expect(spikes.candidates, hasLength(1));
    expect(spikes.candidates.first.telemetryTime, closeTo(5.025, 1e-3));

    // 12/8 alternating around the 10% on-threshold stays above the 5%
    // off-threshold: one episode.
    final held = detectBrakingOnsets(
      _brake((k) => k > 100 && k <= 120 ? (k.isEven ? 12.0 : 8.0) : 0.0),
      0.0,
      10.0,
    );
    expect(held.candidates, hasLength(1));
    expect(held.rejectedSpikes, 0);
    expect(held.candidates.first.durationSeconds, greaterThan(0.9));
  });

  test('gaps are never bridged', () {
    // Samples 99..109 (4.95..5.45 s) are missing while the brake is applied.
    final afterGap = detectBrakingOnsets(
      _brake(_brakeProfile, (k) => k < 99 || k > 109),
      0.0,
      10.0,
    );
    expect(afterGap.gaps, 1);
    expect(afterGap.candidates, hasLength(1));
    expect(afterGap.candidates.first.telemetryTime, closeTo(5.5, 1e-6));
    expect(afterGap.candidates.first.uncertaintyReasons, contains(brakingFollowsGap));

    // Non-finite samples 120..125 split one application into two flagged
    // candidates.
    final split = detectBrakingOnsets(
      _brake((k) => k >= 120 && k <= 125 ? double.nan : _brakeProfile(k)),
      0.0,
      10.0,
    );
    expect(split.gaps, 1);
    expect(split.candidates, hasLength(2));
    expect(split.candidates[0].uncertaintyReasons, contains(brakingInterruptedByGap));
    expect(split.candidates[0].durationSeconds, closeTo(5.95 - 5.025, 1e-3));
    expect(split.candidates[1].uncertaintyReasons, contains(brakingFollowsGap));
    expect(split.candidates[1].telemetryTime, closeTo(6.3, 1e-6));
  });

  test('window edges are flagged', () {
    final started = detectBrakingOnsets(_brake(), 5.5, 10.0);
    expect(started.candidates, hasLength(1));
    expect(started.candidates.first.uncertaintyReasons, contains(brakingAlreadyActive));

    final truncated = detectBrakingOnsets(_brake(), 0.0, 6.0);
    expect(truncated.candidates, hasLength(1));
    expect(truncated.candidates.first.uncertaintyReasons, contains(brakingTruncatedAtWindowEnd));
  });

  test('deceleration is used, labelled inferred, only without a brake channel', () {
    final session = _session({
      'longitudinalAcceleration': _channel('longacc', 'g', _decelerationProfile),
    });
    final result = detectBrakingOnsets(session, 0.0, 10.0);
    expect(result.valid, isTrue);
    expect(result.method, brakingMethodInferred);
    expect(result.provenance, brakingProvenanceInferred);
    expect(result.channel, 'longacc');
    expect(result.threshold.unit, 'g');
    expect(result.candidates, hasLength(1));
    // -0.2 g at 6.05 s, -0.4 g at 6.10 s: the 0.3 g crossing is at 6.075 s.
    expect(result.candidates.first.telemetryTime, closeTo(6.075, 1e-3));
    expect(result.candidates.first.peakValue, closeTo(-0.8, 1e-3)); // braking is negative

    final disabled = detectBrakingOnsets(
      session,
      0.0,
      10.0,
      options: const BrakingOnsetOptions(allowInferred: false),
    );
    expect(disabled.unresolvedReason, brakingInferenceDisabled);
    expect(disabled.candidates, isEmpty);

    final empty = detectBrakingOnsets(_session({}), 0.0, 10.0);
    expect(empty.valid, isTrue);
    expect(empty.unresolvedReason, brakingNoChannel);
  });

  test('deceleration never stands in for missing brake data', () {
    final result = detectBrakingOnsets(
      _session({
        'brake': _channel('brake_pos', '%', (_) => double.nan),
        'longitudinalAcceleration': _channel('longacc', 'g', _decelerationProfile),
      }),
      0.0,
      10.0,
    );
    expect(result.method, brakingMethodMeasured);
    expect(result.unresolvedReason, brakingNoSamples);
    expect(result.candidates, isEmpty);
  });

  test('threshold units are enforced', () {
    final bar = _session({
      'brake': _channel('brake_pressure', 'bar', (k) => _brakeProfile(k) / 2.0),
    });
    expect(detectBrakingOnsets(bar, 0.0, 10.0).unresolvedReason, brakingUnitMismatch);
    final inBar = detectBrakingOnsets(
      bar,
      0.0,
      10.0,
      options: const BrakingOnsetOptions(measuredBrake: BrakingThreshold(5.0, 2.0, 'bar')),
    );
    expect(inBar.unresolvedReason, isEmpty);
    expect(inBar.candidates, hasLength(1));
    expect(inBar.candidates.first.telemetryTime, closeTo(5.025, 1e-3));

    final assumed = detectBrakingOnsets(
      _session({'brake': _channel('brake', '', _brakeProfile)}),
      0.0,
      10.0,
    );
    expect(assumed.candidates, hasLength(1));
    expect(assumed.channelUnit, isEmpty);
    expect(assumed.candidates.first.uncertaintyReasons, contains(brakingUnitUndeclared));
  });

  test('onsets are mapped to progress', () {
    ProgressSegment segment(double endTime, double endMeters) => ProgressSegment([
      const ProjectedSample(0.0, progressMeters: 0.0, valid: true),
      ProjectedSample(endTime, progressMeters: endMeters, valid: true),
    ]);
    final mapped = detectBrakingOnsets(_brake(), 0.0, 10.0, lapTrace: [segment(10.0, 500.0)]);
    expect(mapped.candidates, hasLength(1));
    expect(mapped.candidates.first.progressMeters, closeTo(5.025 * 50.0, 0.1));

    final unmapped = detectBrakingOnsets(_brake(), 0.0, 10.0, lapTrace: [segment(4.0, 200.0)]);
    expect(unmapped.candidates.first.progressMeters, isNull);
  });

  test('invalid inputs are rejected', () {
    final session = _brake();
    expect(detectBrakingOnsets(session, 5.0, 5.0).valid, isFalse);
    expect(detectBrakingOnsets(session, double.nan, 5.0).valid, isFalse);
    for (final options in const [
      BrakingOnsetOptions(measuredBrake: BrakingThreshold(5.0, 5.0, '%')),
      BrakingOnsetOptions(inferredDeceleration: BrakingThreshold(0.30, 0.15, ' ')),
      BrakingOnsetOptions(minimumDurationSeconds: 0.0),
    ]) {
      expect(detectBrakingOnsets(session, 0.0, 10.0, options: options).valid, isFalse);
    }
  });
}
