// Throttle pickup and downstream exit effects (exit_metrics.dart), ported
// from Overlays' ExitMetricsTests.cpp: measured throttle first, inferred
// acceleration labelled, an explicit following-straight interval, and
// comparisons without assigned causes.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _dt = 0.05; // 20 Hz
const _sampleCount = 1001; // t = 0 .. 50 s
const _lapLength = 1000.0; // progress = 20 m/s * t

final _configuration = 'compatibility-v1:${'e' * 64}';

TelemetryChannel _channel(String name, String unit, double Function(int) value) => TelemetryChannel(
  name: name,
  unit: unit,
  timestamps: Float64List.fromList([for (var k = 0; k < _sampleCount; ++k) k * _dt]),
  values: Float32List.fromList([for (var k = 0; k < _sampleCount; ++k) value(k)]),
);

// Lifted (0 %, then 5 %) in the corner, back on from k = rise: 25 % per
// sample to 100 %.
double Function(int) _throttleFrom(int rise) => (k) {
  if (k < 505) return 0.0;
  if (k < rise) return 5.0;
  return math.min(100.0, (k - rise + 1) * 25.0);
};

double _speed(int k) => 50.0 + k * 0.05; // km/h: 80 at 600 m, 90 at 800 m

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

TelemetrySession _measured([int rise = 540, double Function(int) speed = _speed]) => _session({
  'throttle': _channel('throttle_pos', '%', _throttleFrom(rise)),
  'speed': _channel('velocity', 'km/h', speed),
});

TelemetrySession _throttle(double Function(int) value, [String unit = '%']) =>
    _session({'throttle': _channel('throttle_pos', unit, value)});

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

ApprovedSegmentation _approvedOf(List<(TrackSegmentType, double, double)> segments) {
  var number = 1;
  return approvedSegmentation([
    for (final (type, start, end) in segments)
      makeTrackSegment(type, 'S${number++}', start, end, _configuration),
  ], _configuration);
}

String _firstId(ApprovedSegmentation approved) => approved.segments.first['id']! as String;

ApprovedSegmentation _cornerAndStraight() => _approvedOf([
  (TrackSegmentType.corner, 500.0, 600.0),
  (TrackSegmentType.straight, 600.0, 800.0),
]);

ExitMetrics _exit(
  ApprovedSegmentation approved,
  TelemetrySession session, {
  List<ProgressSegment>? lap,
  double? lapEnd,
  String? id,
  ExitMetricsOptions options = const ExitMetricsOptions(),
}) => computeExitMetrics(
  _lapLength,
  approved,
  id ?? _firstId(approved),
  lap ?? _projectedLap(),
  session,
  lapEnd,
  options,
);

void main() {
  test('the pickup and the following straight are measured', () {
    final metrics = _exit(_cornerAndStraight(), _measured(), lapEnd: 50.0);
    expect(metrics.valid, isTrue);
    expect(metrics.pickup.method, pickupMethodMeasured);
    expect(metrics.pickup.provenance, 'measured');
    expect(metrics.pickup.unit, '%');
    // 20 % is crossed between 5 % at 26.95 s and 25 % at 27.00 s: 26.9875 s, 539.75 m.
    expect(metrics.pickup.telemetryTime, isNotNull, reason: metrics.pickup.unavailableReason);
    expect(metrics.pickup.telemetryTime, closeTo(26.9875, 1e-3));
    expect(metrics.pickup.progressMeters, closeTo(539.75, 0.05));
    expect(metrics.pickup.limitations, isEmpty);

    expect(metrics.intervalSource, intervalFollowingStraight);
    expect(metrics.intervalStartMeters, 600.0);
    expect(metrics.intervalEndMeters, 800.0);
    expect(metrics.speedUnit, 'km/h');
    expect(metrics.exitSpeed, closeTo(80.0, 1e-3));
    expect(metrics.intervalEndSpeed, closeTo(90.0, 1e-3));
    expect(metrics.elapsedSeconds, closeTo(10.0, 1e-9));
    expect(metrics.downstreamUnavailableReason, isEmpty);
    expect(metrics.stamp.calculationAlgorithm, exitMetricsAlgorithm);
  });

  test('an acceleration-based pickup is labelled inferred', () {
    final approved = _cornerAndStraight();
    final metrics = _exit(
      approved,
      _session({
        'longitudinalAcceleration': _channel(
          'longacc',
          'g',
          (k) => k < 540 ? -0.5 : (k < 545 ? 0.0 : 0.3),
        ),
      }),
      lapEnd: 50.0,
    );
    expect(metrics.pickup.method, pickupMethodInferred);
    expect(metrics.pickup.provenance, 'inferred');
    expect(metrics.pickup.progressMeters, closeTo(544.33, 0.1));
    // No speed channel: elapsed time is still measured, speeds are not invented.
    expect(metrics.elapsedSeconds, isNotNull);
    expect(metrics.exitSpeed, isNull);
    expect(metrics.intervalEndSpeed, isNull);
    expect(metrics.downstreamUnavailableReason, exitSpeedChannelMissing);

    expect(_exit(approved, _session({}), lapEnd: 50.0).pickup.unavailableReason, exitNoChannel);
  });

  test('lifts, spikes, gaps and units are handled', () {
    final approved = _cornerAndStraight();
    expect(_exit(approved, _throttle((_) => 100.0)).pickup.unavailableReason, exitNoLift);
    expect(
      _exit(approved, _throttle((k) => k < 505 ? 0.0 : 5.0)).pickup.unavailableReason,
      exitNoPickup,
    );

    // A one-sample blip is not a pickup; the real one follows.
    final afterSpike = _exit(approved, _throttle((k) => k == 520 ? 50.0 : _throttleFrom(540)(k)));
    expect(afterSpike.pickup.progressMeters, closeTo(539.75, 0.05));

    // Missing throttle samples around the rise: reported where data resumes, flagged.
    final afterGap = _exit(
      approved,
      _throttle((k) => k >= 538 && k <= 541 ? double.nan : _throttleFrom(540)(k)),
    );
    expect(afterGap.pickup.progressMeters, closeTo(542.0, 0.05));
    expect(afterGap.pickup.limitations, contains(exitFollowsGap));

    expect(
      _exit(approved, _throttle(_throttleFrom(540), 'raw')).pickup.unavailableReason,
      exitUnitMismatch,
    );
    expect(
      _exit(approved, _throttle(_throttleFrom(540), '')).pickup.limitations,
      contains(exitUnitUndeclared),
    );
  });

  test('the downstream interval is defined explicitly', () {
    final session = _measured();
    final fixed = _exit(
      _approvedOf([(TrackSegmentType.corner, 500.0, 600.0)]),
      session,
      lapEnd: 50.0,
    );
    expect(fixed.intervalSource, intervalFixedDistance);
    expect(fixed.intervalEndMeters, 800.0);
    expect(fixed.elapsedSeconds, closeTo(10.0, 1e-9));

    // A straight ending at the gate ends at the lap's timed end.
    final toGate = _approvedOf([
      (TrackSegmentType.corner, 500.0, 600.0),
      (TrackSegmentType.straight, 600.0, _lapLength),
    ]);
    final atGate = _exit(toGate, session, lapEnd: 50.0);
    expect(atGate.intervalEndMeters, _lapLength);
    expect(atGate.elapsedSeconds, closeTo(20.0, 1e-9));
    expect(_exit(toGate, session).downstreamUnavailableReason, exitIncompleteCoverage);

    // A corner ending at the gate searches for pickup up to the lap's timed
    // end, even though the projection stops short of the gate.
    final lastCorner = _approvedOf([(TrackSegmentType.corner, 900.0, _lapLength)]);
    final shortEnd = _projectedLap(49.7, 51.0);
    expect(
      _exit(lastCorner, _measured(960), lap: shortEnd).pickup.unavailableReason,
      exitIncompleteCoverage,
    );
    final lastPickup = _exit(lastCorner, _measured(960), lap: shortEnd, lapEnd: 50.0);
    expect(lastPickup.pickup.unavailableReason, isEmpty);
    expect(lastPickup.pickup.progressMeters, inExclusiveRange(950.0, 965.0));

    final late = _approvedOf([(TrackSegmentType.corner, 900.0, 950.0)]);
    expect(_exit(late, session, lapEnd: 50.0).downstreamUnavailableReason, exitCrossesGate);

    // A projection hole inside the interval: no elapsed time, the exit speed stays.
    final approved = _cornerAndStraight();
    final holed = _exit(approved, session, lap: _projectedLap(35.0, 36.0), lapEnd: 50.0);
    expect(holed.elapsedSeconds, isNull);
    expect(holed.downstreamUnavailableReason, exitIncompleteCoverage);
    expect(holed.exitSpeed, isNotNull);

    final wrapped = _exit(
      _approvedOf([(TrackSegmentType.corner, 950.0, 50.0)]),
      session,
      lapEnd: 50.0,
    );
    expect(wrapped.pickup.unavailableReason, exitCrossesGate);
    expect(wrapped.downstreamUnavailableReason, exitCrossesGate);

    expect(_exit(approved, session, id: 'missing').valid, isFalse);
    expect(
      _exit(
        approved,
        session,
        lapEnd: 50.0,
        options: const ExitMetricsOptions(followMeters: 0.0),
      ).valid,
      isFalse,
    );
  });

  test('two laps are compared without assigning a cause', () {
    final approved = _cornerAndStraight();
    final a = _exit(approved, _measured(540), lapEnd: 50.0);
    final b = _exit(approved, _measured(560, (k) => _speed(k) - 5.0), lapEnd: 50.0);
    final comparison = compareExitMetrics(a, b);
    expect(comparison.valid, isTrue);
    expect(comparison.pickupDeltaMeters, closeTo(-20.0, 0.05)); // A picks up 20 m earlier
    expect(comparison.exitSpeedDelta, closeTo(5.0, 1e-3));
    expect(comparison.intervalEndSpeedDelta, closeTo(5.0, 1e-3));
    expect(comparison.elapsedSecondsDelta, closeTo(0.0, 1e-9));

    final inferred = _exit(
      approved,
      _session({
        'longitudinalAcceleration': _channel('longacc', 'g', (k) => k < 545 ? 0.0 : 0.3),
        'speed': _channel('velocity', 'km/h', _speed),
      }),
      lapEnd: 50.0,
    );
    final mixed = compareExitMetrics(a, inferred);
    expect(mixed.valid, isTrue);
    expect(mixed.pickupUnavailableReason, exitMixedProvenance);
    expect(mixed.pickupDeltaMeters, isNull);
    expect(mixed.exitSpeedDelta, isNotNull); // same recorded channel and unit

    final other = _approvedOf([(TrackSegmentType.corner, 500.0, 610.0)]);
    expect(compareExitMetrics(a, _exit(other, _measured(), lapEnd: 50.0)).valid, isFalse);
  });
}
