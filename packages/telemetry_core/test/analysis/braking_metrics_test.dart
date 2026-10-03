// Braking point, distance and deceleration (braking_metrics.dart), ported
// from Overlays' BrakingMetricsTests.cpp: an explicit spatial interval,
// measured and inferred kept apart, and no distances or peaks from missing
// coverage.
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _dt = 0.05; // 20 Hz
const _sampleCount = 1001; // t = 0 .. 50 s
const _lapLength = 1000.0; // progress = 20 m/s * t

final _configuration = 'compatibility-v1:${'d' * 64}';

TelemetryChannel _channel(String name, String unit, double Function(int) value) => TelemetryChannel(
  name: name,
  unit: unit,
  timestamps: Float64List.fromList([for (var k = 0; k < _sampleCount; ++k) k * _dt]),
  values: Float32List.fromList([for (var k = 0; k < _sampleCount; ++k) value(k)]),
);

// A short application at 5 s (outside the interval) and the real one from
// k = onset: 0 -> 80 % over 4 samples, held 2 s, released over 4 samples.
double Function(int) _brakeFrom(int onset) => (k) {
  if (k >= 100 && k < 110) return 60.0;
  if (k <= onset) return 0.0;
  if (k < onset + 4) return (k - onset) * 20.0;
  if (k <= onset + 40) return 80.0;
  if (k < onset + 44) return 80.0 - (k - onset - 40) * 20.0;
  return 0.0;
};

// -0.9 g from k = 440 to 484 with one -1.1 g sample at k = 460.
double _deceleration(int k) => k == 460 ? -1.1 : (k >= 440 && k <= 484 ? -0.9 : 0.0);

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

TelemetrySession _brake(int onset, [double Function(int)? deceleration]) => _session({
  'brake': _channel('brake_pos', '%', _brakeFrom(onset)),
  if (deceleration != null) 'longitudinalAcceleration': _channel('longacc', 'g', deceleration),
});

final _idle = _session({
  'brake': _channel('brake_pos', '%', (k) => k >= 100 && k < 110 ? 60.0 : 0.0),
});

List<ProgressSegment> _projectedLap([double holeFrom = -1.0, double holeTo = -1.0]) {
  final lap = <List<ProjectedSample>>[[]];
  for (var k = 0; k < _sampleCount; ++k) {
    final time = k * _dt;
    if (time > holeFrom && time < holeTo) {
      if (lap.last.isNotEmpty) lap.add([]);
      continue;
    }
    lap.last.add(ProjectedSample(time, progressMeters: 20.0 * time, valid: true));
  }
  return [
    for (final samples in lap)
      if (samples.isNotEmpty) ProgressSegment(samples),
  ];
}

ApprovedSegmentation _cornerAt(double start, double end) => approvedSegmentation([
  makeTrackSegment(TrackSegmentType.corner, 'T1', start, end, _configuration),
], _configuration);

BrakingMetrics _braking(
  ApprovedSegmentation approved,
  TelemetrySession session, {
  List<ProgressSegment>? lap,
  String? id,
  double? lapStart,
  double? lapEnd,
  BrakingMetricsOptions options = const BrakingMetricsOptions(),
}) => computeBrakingMetrics(
  _lapLength,
  approved,
  id ?? approved.segments.first['id']! as String,
  lap ?? _projectedLap(),
  session,
  lapStart,
  lapEnd,
  options,
);

void main() {
  test('the braking point, distance and deceleration are measured', () {
    final approved = _cornerAt(500.0, 600.0);
    final metrics = _braking(approved, _brake(440, _deceleration));
    expect(metrics.valid, isTrue);
    expect(metrics.unavailableReason, isEmpty);
    expect(metrics.intervalStartMeters, 300.0);
    expect(metrics.intervalEndMeters, 600.0);
    expect(metrics.method, brakingMethodMeasured);
    expect(metrics.provenance, brakingProvenanceMeasured);
    expect(metrics.thresholdUnit, '%');
    // 10 % is crossed half-way between 22.00 s (0 %) and 22.05 s (20 %).
    expect(metrics.brakingPointTime, closeTo(22.025, 1e-3));
    expect(metrics.brakingPointMeters, closeTo(440.5, 0.05));
    expect(metrics.distanceBeforeEntryMeters, closeTo(59.5, 0.05));
    // Released below 5 % at 24.2 s (484 m).
    expect(metrics.brakingSeconds, closeTo(2.175, 1e-3));
    expect(metrics.brakingDistanceMeters, closeTo(43.5, 0.05));
    expect(metrics.limitations, isEmpty);
    expect(metrics.decelerationChannel, 'longacc');
    expect(metrics.decelerationUnit, 'g');
    expect(metrics.peakDeceleration, closeTo(1.1, 1e-3));
    expect(metrics.meanDeceleration, closeTo(0.9045, 0.001));
    expect(metrics.stamp.calculationAlgorithm, brakingMetricsAlgorithm);
    expect(segmentationResultCurrent(metrics.stamp, approved, brakingMetricsAlgorithm), isTrue);
  });

  test('deceleration-based braking is labelled inferred', () {
    final approved = _cornerAt(500.0, 600.0);
    final metrics = _braking(
      approved,
      _session({'longitudinalAcceleration': _channel('longacc', 'g', _deceleration)}),
    );
    expect(metrics.method, brakingMethodInferred);
    expect(metrics.provenance, brakingProvenanceInferred);
    expect(metrics.thresholdUnit, 'g');
    expect(metrics.brakingPointMeters, inExclusiveRange(438.0, 441.0));
    expect(metrics.peakDeceleration, closeTo(1.1, 1e-3));

    // A measured brake without an acceleration channel has no deceleration.
    final noDeceleration = _braking(approved, _brake(440));
    expect(noDeceleration.brakingPointMeters, isNotNull);
    expect(noDeceleration.peakDeceleration, isNull);
    expect(noDeceleration.meanDeceleration, isNull);
    expect(noDeceleration.decelerationUnavailableReason, brakingDecelerationChannelMissing);
  });

  test('missing coverage creates no distance or peak', () {
    final approved = _cornerAt(500.0, 600.0);
    final session = _brake(440, _deceleration);

    // A projection hole inside the episode: the point stays, the distance does not.
    final holed = _braking(approved, session, lap: _projectedLap(23.0, 23.5));
    expect(holed.brakingPointMeters, isNotNull);
    expect(holed.brakingSeconds, isNotNull);
    expect(holed.brakingDistanceMeters, isNull);

    // A hole at the interval start: nothing is measured at all.
    final noStart = _braking(approved, session, lap: _projectedLap(14.5, 15.5));
    expect(noStart.unavailableReason, brakingIncompleteCoverage);
    expect(noStart.brakingPointMeters, isNull);

    // A missing acceleration sample inside the episode: no peak or mean.
    final noPeak = _braking(approved, _brake(440, (k) => k == 470 ? double.nan : _deceleration(k)));
    expect(noPeak.brakingPointMeters, isNotNull);
    expect(noPeak.peakDeceleration, isNull);
    expect(noPeak.meanDeceleration, isNull);
    expect(noPeak.decelerationUnavailableReason, brakingIncompleteCoverage);
  });

  test('why no braking point exists is reported', () {
    final approved = _cornerAt(500.0, 600.0);
    // The 5 s application lies outside the interval.
    expect(_braking(approved, _idle).unavailableReason, brakingNoneDetected);
    expect(_braking(approved, _session({})).unavailableReason, brakingNoChannel);
    expect(_braking(_cornerAt(900.0, 100.0), _idle).unavailableReason, brakingSegmentCrossesGate);

    // An approach that would start before the gate is clipped and says so.
    final early = _cornerAt(100.0, 200.0);
    final clipped = _braking(early, _idle);
    expect(clipped.intervalStartMeters, 0.0);
    expect(clipped.limitations, contains(brakingApproachClipped));

    // A real lap's projection never lands on the gate exactly: without the
    // lap's timed start or end a gate-bounded interval has no coverage.
    final offGate = _projectedLap(-1.0, 0.3); // first projected sample at 6 m
    final shortEnd = _projectedLap(49.7, 51.0); // last projected sample at 994 m
    expect(_braking(early, _idle, lap: offGate).unavailableReason, brakingIncompleteCoverage);
    final gateStart = _braking(early, _idle, lap: offGate, lapStart: 0.0, lapEnd: 50.0);
    expect(gateStart.unavailableReason, isEmpty);
    expect(gateStart.brakingPointMeters, isNotNull); // the 5 s application at 100 m
    final last = _cornerAt(900.0, 1000.0);
    expect(_braking(last, _idle, lap: shortEnd).unavailableReason, brakingIncompleteCoverage);
    expect(
      _braking(last, _idle, lap: shortEnd, lapStart: 0.0, lapEnd: 50.0).unavailableReason,
      brakingNoneDetected,
    );
    // The missing channel is reported ahead of coverage.
    expect(_braking(early, _session({}), lap: offGate).unavailableReason, brakingNoChannel);

    expect(_braking(approved, _idle, id: 'missing').valid, isFalse);
    expect(
      _braking(approved, _idle, options: const BrakingMetricsOptions(approachMeters: -1.0)).valid,
      isFalse,
    );
  });

  test('only like is compared with like', () {
    final approved = _cornerAt(500.0, 600.0);
    final measuredA = _braking(approved, _brake(440, _deceleration));
    final measuredB = _braking(approved, _brake(460, _deceleration));
    final comparison = compareBrakingMetrics(measuredA, measuredB);
    expect(comparison.valid, isTrue);
    expect(comparison.unavailableReason, isEmpty);
    // B brakes 1 s (20 m) later, so A minus B is -20 m: A brakes earlier.
    expect(comparison.brakingPointDeltaMeters, closeTo(-20.0, 0.05));
    expect(comparison.brakingSecondsDelta, isNotNull);

    final inferredB = _braking(
      approved,
      _session({'longitudinalAcceleration': _channel('longacc', 'g', _deceleration)}),
    );
    final mixed = compareBrakingMetrics(measuredA, inferredB);
    expect(mixed.valid, isTrue);
    expect(mixed.unavailableReason, brakingMixedProvenance);
    expect(mixed.brakingPointDeltaMeters, isNull);

    expect(
      compareBrakingMetrics(measuredA, _braking(_cornerAt(500.0, 610.0), _brake(440))).valid,
      isFalse,
    );
  });

  test('the approach stops at the previous corner', () {
    // A corner ending at 450 m precedes T2 (500-600 m). Braking that starts
    // at 440 m is that corner's; the 200 m approach stops at 450 m.
    final segments = [
      makeTrackSegment(TrackSegmentType.corner, 'T1', 300.0, 450.0, _configuration),
      makeTrackSegment(TrackSegmentType.corner, 'T2', 500.0, 600.0, _configuration),
    ];
    final approved = approvedSegmentation(segments, _configuration);
    final id = segments[1]['id']! as String;
    var metrics = _braking(approved, _brake(440), id: id);
    expect(metrics.valid, isTrue);
    expect(metrics.intervalStartMeters, 450.0);
    expect(metrics.limitations, contains(brakingApproachClippedAtCorner));
    expect(metrics.brakingPointMeters == null || metrics.brakingPointMeters! >= 450.0, isTrue);
    // Braking that starts after the previous corner is still found.
    metrics = _braking(approved, _brake(470), id: id);
    expect(metrics.brakingPointMeters, closeTo(470.5, 0.05));
    // A straight in between does not clip the approach.
    final withStraight = [
      makeTrackSegment(TrackSegmentType.straight, 'S', 300.0, 500.0, _configuration),
      makeTrackSegment(TrackSegmentType.corner, 'T2', 500.0, 600.0, _configuration),
    ];
    metrics = _braking(
      approvedSegmentation(withStraight, _configuration),
      _brake(440),
      id: withStraight[1]['id']! as String,
    );
    expect(metrics.intervalStartMeters, 300.0);
    expect(metrics.limitations, isNot(contains(brakingApproachClippedAtCorner)));
  });
}
