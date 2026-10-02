import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

// 10 Hz from 0 to 10 s; each channel's value at a time.
TelemetrySession _session(Map<String, (String, double Function(double))> channels) {
  final times = Float64List.fromList([for (var i = 0; i <= 100; ++i) i / 10]);
  return TelemetrySession(
    duration: 10,
    startTime: 0,
    metadata: const {},
    channels: {
      for (final MapEntry(key: name, value: (unit, value)) in channels.entries)
        name: TelemetryChannel(
          name: name,
          unit: unit,
          timestamps: times,
          values: Float32List.fromList([for (final t in times) value(t)]),
        ),
    },
    aliases: {
      if (channels.containsKey('brake')) 'brake': 'brake',
      if (channels.containsKey('longacc')) 'longitudinalAcceleration': 'longacc',
    },
    warnings: const [],
    timingGates: const [],
    sampleCount: times.length,
  );
}

// Braking from 2 s to 4 s, a 0.1 s spike at 6 s.
double _brake(double t) => (t >= 2 && t < 4) ? 60 : ((t - 6).abs() < 0.01 ? 40 : 0);
double _deceleration(double t) => (t >= 2 && t < 4) ? -0.8 : 0;

void main() {
  group('braking onsets', () {
    test('use the brake channel and reject spikes', () {
      final detection = detectBrakingOnsets(
        _session({'brake': ('%', _brake), 'longacc': ('g', _deceleration)}),
        0,
        10,
      );
      expect(detection.method, brakingMethodMeasured);
      expect(detection.provenance, brakingProvenanceMeasured);
      expect(detection.candidates.length, 1);
      expect(detection.candidates.single.telemetryTime, closeTo(1.9 + 0.1 * 10 / 60, 1e-9));
      expect(detection.candidates.single.durationSeconds, closeTo(4.0 - 1.9 - 0.1 / 6, 1e-6));
      expect(detection.candidates.single.peakValue, 60);
      expect(detection.rejectedSpikes, 1);
    });

    test('fall back to deceleration only without a brake channel', () {
      final detection = detectBrakingOnsets(_session({'longacc': ('g', _deceleration)}), 0, 10);
      expect(detection.method, brakingMethodInferred);
      expect(detection.provenance, brakingProvenanceInferred);
      expect(detection.candidates.single.peakValue, closeTo(-0.8, 1e-6));
      final disabled = detectBrakingOnsets(
        _session({'longacc': ('g', _deceleration)}),
        0,
        10,
        options: const BrakingOnsetOptions(allowInferred: false),
      );
      expect(disabled.unresolvedReason, brakingInferenceDisabled);
      expect(disabled.candidates, isEmpty);
    });

    test('report a missing channel, a unit mismatch and an episode cut by the window', () {
      expect(detectBrakingOnsets(_session({}), 0, 10).unresolvedReason, brakingNoChannel);
      expect(
        detectBrakingOnsets(_session({'brake': ('bar', _brake)}), 0, 10).unresolvedReason,
        brakingUnitMismatch,
      );
      final cut = detectBrakingOnsets(_session({'brake': ('', _brake)}), 3, 10);
      expect(cut.candidates.first.uncertaintyReasons, [
        brakingAlreadyActive,
        brakingUnitUndeclared,
      ]);
    });
  });

  test('corner variability keeps measured and inferred braking points apart', () {
    CornerLapObservation lap(double braking, String provenance, double minimum) =>
        CornerLapObservation()
          ..brakingPointMeters = braking
          ..brakingProvenance = provenance
          ..minimumSpeed = minimum;
    final variability = summarizeCornerVariability('c1', 'Corner 1', [
      lap(100, 'measured', 60),
      lap(104, 'measured', 62),
      lap(110, 'measured', 61),
      lap(90, 'inferred', 59),
    ]);
    expect(variability.brakingPointMeasured.count, 3);
    expect(variability.brakingPointMeasured.available, isTrue);
    expect(variability.brakingPointMeasured.median, 104);
    expect(variability.brakingPointInferred.count, 1);
    expect(variability.brakingPointInferred.available, isFalse);
    expect(variability.minimumSpeed.count, 4);
    expect(variability.lineOffset.count, 0);
  });

  test('corner speeds are never compared across channels', () {
    final stamp = const SegmentationResultStamp(revision: 'r');
    CornerSpeeds speeds(String channel, double minimum) => CornerSpeeds(
      segmentId: 'c1',
      channel: channel,
      unit: 'km/h',
      provenance: 'measured',
      minimum: CornerSpeedValue(value: minimum),
      stamp: stamp,
      valid: true,
    );
    final same = compareCornerSpeeds(speeds('velocity', 70), speeds('velocity', 72.5));
    expect(same.valid, isTrue);
    expect(same.minimumDelta, -2.5);
    final mixed = compareCornerSpeeds(speeds('velocity', 70), speeds('gps_speed', 72.5));
    expect(mixed.valid, isFalse);
    expect(mixed.unavailableReason, cornerSpeedMixedProvenance);
  });
}
