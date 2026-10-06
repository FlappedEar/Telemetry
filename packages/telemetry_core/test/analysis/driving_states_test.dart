// Ports DrivingStatesTests.cpp of FlappedEar Overlays (revision d4d1039):
// braking, accelerating, cornering and coasting from measured pedals or,
// labelled inferred, from longitudinal G; hysteresis, gaps and units
// handled; coasting by segment and lap; braking while cornering. Then the
// comparison functions on a synthetic recording.
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const double _dt = 0.05; // 20 Hz
const int _sampleCount = 201; // t = 0 .. 10 s

TelemetryChannel _channel(
  String name,
  String unit,
  double Function(double) value, [
  bool Function(double)? present,
]) {
  final times = <double>[], values = <double>[];
  for (var k = 0; k < _sampleCount; ++k) {
    final t = k * _dt;
    if (present != null && !present(t)) continue;
    times.add(t);
    values.add(value(t));
  }
  return TelemetryChannel(
    name: name,
    unit: unit,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
}

TelemetrySession _session(Map<String, TelemetryChannel> aliased) => TelemetrySession(
  duration: 10,
  startTime: 0,
  metadata: const {},
  channels: {for (final channel in aliased.values) channel.name: channel},
  aliases: {for (final entry in aliased.entries) entry.key: entry.value.name},
  warnings: const [],
  timingGates: const [],
  sampleCount: _sampleCount,
);

// A lap slice: throttle to 4 s, brake 5-7 s, throttle again from 8 s,
// cornering 4.5-7.5 s (trail braking), coasting 4-5 s and 7-8 s.
double _brake(double t) => t > 5.0 && t < 7.0 ? 60.0 : 0.0;
double _throttle(double t) => t < 4.0 || t > 8.0 ? 90.0 : 0.0;
double _lateral(double t) => t > 4.5 && t < 7.5 ? -0.9 : 0.05;
double _longitudinal(double t) => t < 4.0 || t > 8.0
    ? 0.25
    : t > 5.0 && t < 7.0
    ? -0.7
    : 0.0;
double _speed(double _) => 110.0;

bool _covers(List<DrivingStateInterval> intervals, double from, double to) =>
    intervals.any((i) => i.start <= from + 1e-6 && i.end >= to - 1e-6);

bool _touches(List<DrivingStateInterval> intervals, double from, double to) =>
    intervals.any((i) => i.end > from && i.start < to);

void main() {
  test('classifies measured pedals with trail braking', () {
    final session = _session({
      'brake': _channel('brake_pos-obd', '%', _brake),
      'throttle': _channel('accelerator_pos-obd', '%', _throttle),
      'lateralAcceleration': _channel('latacc-calc', 'g', _lateral),
      'longitudinalAcceleration': _channel('longacc-calc', 'g', _longitudinal),
      'speed': _channel('velocity', 'km/h', _speed),
    });
    final states = classifyDrivingStates(session, 0.0, 10.0);
    expect(states.valid, isTrue);
    expect(states.algorithm, 'driving-states-v1');
    expect(states.braking.provenance, 'measured');
    expect(states.braking.channel, 'brake_pos-obd');
    expect(states.accelerating.provenance, 'measured');
    // RaceChrono's GPS-derived lateral G is calculated, not a sensor reading.
    expect(states.cornering.provenance, 'calculated');
    expect(states.coasting.provenance, 'measured');

    expect(states.braking.active, hasLength(1));
    expect(_covers(states.braking.active, 5.1, 6.9), isTrue);
    expect(states.accelerating.active, hasLength(2));
    expect(_covers(states.cornering.active, 4.6, 7.4), isTrue);
    expect(_touches(states.cornering.active, 5.1, 6.9), isTrue);
    expect(_touches(states.braking.active, 5.1, 6.9), isTrue);
    // Coasting between throttle and brake, and between brake and throttle.
    expect(_covers(states.coasting.active, 4.1, 4.9), isTrue);
    expect(_covers(states.coasting.active, 7.1, 7.9), isTrue);
    expect(_touches(states.coasting.active, 5.1, 6.9), isFalse, reason: 'never while braking');
    expect(_covers(states.braking.known, 0.0, 10.0), isTrue);
  });

  test('infers pedals from acceleration without claiming measurement', () {
    final session = _session({
      'lateralAcceleration': _channel('latacc', 'g', _lateral),
      'longitudinalAcceleration': _channel('longacc', 'g', _longitudinal),
      'speed': _channel('velocity', 'km/h', _speed),
    });
    final states = classifyDrivingStates(session, 0.0, 10.0);
    expect(states.braking.provenance, 'inferred');
    expect(states.accelerating.provenance, 'inferred');
    expect(states.coasting.provenance, 'inferred');
    expect(states.cornering.provenance, 'measured', reason: 'a sensor channel, not "-calc"');
    expect(_covers(states.braking.active, 5.1, 6.9), isTrue);
    expect(_covers(states.accelerating.active, 0.0, 3.9), isTrue);
    // One acceleration channel cannot show braking and accelerating together.
    for (final braking in states.braking.active) {
      expect(_touches(states.accelerating.active, braking.start, braking.end), isFalse);
    }
    expect(_covers(states.coasting.active, 4.1, 4.9), isTrue);

    final strict = classifyDrivingStates(
      session,
      0.0,
      10.0,
      const DrivingStateOptions(allowInferred: false),
    );
    expect(strict.braking.provenance, 'unknown');
    expect(strict.braking.unresolvedReason, 'inferenceDisabled');
    expect(strict.braking.active, isEmpty);
    expect(strict.coasting.unresolvedReason, 'pedalStateUnknown');
  });

  test('leaves gaps and unusable channels unknown', () {
    // Brake samples missing 2-3 s: unknown there, and no coasting either.
    final gapped = _session({
      'brake': _channel('brake_pos-obd', '%', _brake, (t) => t < 2.0 || t > 3.0),
      'throttle': _channel('accelerator_pos-obd', '%', (t) => t > 1.0 && t < 4.0 ? 0.0 : 90.0),
      'speed': _channel('velocity', 'km/h', _speed),
    });
    final states = classifyDrivingStates(gapped, 0.0, 10.0);
    expect(states.braking.known, hasLength(2));
    expect(_touches(states.braking.known, 2.05, 2.95), isFalse);
    expect(_covers(states.coasting.active, 1.1, 1.9), isTrue);
    expect(_touches(states.coasting.active, 2.05, 2.95), isFalse);
    expect(_covers(states.coasting.active, 3.1, 3.9), isTrue);
    expect(states.cornering.provenance, 'unknown');
    expect(states.cornering.unresolvedReason, 'noLateralAccelerationChannel');

    // A brake recorded in bar is not a percentage: unknown, never rescaled.
    final bar = _session({
      'brake': _channel('brake_pressure', 'bar', _brake),
      'throttle': _channel('accelerator_pos-obd', '%', _throttle),
      'longitudinalAcceleration': _channel('longacc', 'g', _longitudinal),
      'speed': _channel('velocity', 'km/h', _speed),
    });
    final mismatched = classifyDrivingStates(bar, 0.0, 10.0);
    expect(mismatched.braking.provenance, 'unknown');
    expect(mismatched.braking.unresolvedReason, 'unitMismatch');
    expect(mismatched.braking.active, isEmpty, reason: 'no fallback to deceleration');
    expect(mismatched.coasting.unresolvedReason, 'pedalStateUnknown');

    // Slow: never coasting in the pit lane.
    final slow = _session({
      'brake': _channel('brake_pos-obd', '%', (_) => 0.0),
      'throttle': _channel('accelerator_pos-obd', '%', (_) => 0.0),
      'speed': _channel('velocity', 'km/h', (t) => t < 5.0 ? 5.0 : 60.0),
    });
    final pit = classifyDrivingStates(slow, 0.0, 10.0);
    expect(_touches(pit.coasting.active, 0.0, 4.9), isFalse);
    expect(_covers(pit.coasting.active, 5.1, 9.9), isTrue);

    expect(classifyDrivingStates(slow, 5.0, 5.0).valid, isFalse);
  });

  test('separates overlaps and spikes', () {
    // Left-foot braking on the throttle: both measured, both shown.
    final overlap = _session({
      'brake': _channel('brake_pos-obd', '%', (t) => t > 5.0 && t < 6.0 ? 30.0 : 0.0),
      'throttle': _channel('accelerator_pos-obd', '%', (t) => t > 4.0 && t < 7.0 ? 50.0 : 0.0),
      'speed': _channel('velocity', 'km/h', _speed),
    });
    final states = classifyDrivingStates(overlap, 0.0, 10.0);
    expect(_covers(states.braking.active, 5.1, 5.9), isTrue);
    expect(_covers(states.accelerating.active, 5.1, 5.9), isTrue);
    expect(_touches(states.coasting.active, 4.05, 6.95), isFalse);

    // A one-sample brake blip is a spike, not a braking episode.
    final blip = _session({
      'brake': _channel('brake_pos-obd', '%', (t) => (t - 3.0).abs() < 0.01 ? 50.0 : 0.0),
      'throttle': _channel('accelerator_pos-obd', '%', (_) => 0.0),
      'speed': _channel('velocity', 'km/h', _speed),
    });
    final spiked = classifyDrivingStates(blip, 0.0, 10.0);
    expect(spiked.braking.active, isEmpty);
    expect(spiked.braking.rejectedSpikes, 1);
  });

  test('summarizes coasting by segment and lap', () {
    // At 36 km/h (10 m/s) the lap coasts 4-5 s and 7-8 s. Progress is 10 m
    // per second, so those are 40-50 m and 70-80 m, which fall in the
    // "Approach" and "Exit" segments.
    final session = _session({
      'brake': _channel('brake_pos-obd', '%', _brake),
      'throttle': _channel('accelerator_pos-obd', '%', _throttle),
      'speed': _channel('velocity', 'km/h', (_) => 36.0),
    });
    final trace = [
      ProgressSegment([
        for (var k = 0; k < _sampleCount; ++k)
          ProjectedSample(k * _dt, progressMeters: k * _dt * 10.0),
      ]),
    ];
    final approved = ApprovedSegmentation(
      trackConfigurationReference: '',
      valid: true,
      segments: [
        for (final (id, start, end) in const [
          ('approach', 0.0, 50.0),
          ('corner', 50.0, 70.0),
          ('exit', 70.0, 100.0),
        ])
          {
            'id': id,
            'name': id.toUpperCase(),
            'type': 'sector',
            'startProgressMeters': start,
            'endProgressMeters': end,
          },
      ],
    );
    final summary = summarizeCoasting(session, 0.0, 10.0, lapTrace: trace, approved: approved);
    expect(summary.valid, isTrue);
    expect(summary.algorithm, 'coasting-v1');
    expect(summary.provenance, 'measured');
    expect(summary.episodes, hasLength(2));
    expect(summary.coastingSeconds, closeTo(2.0, 0.15));
    expect(summary.coastingMeters, closeTo(20.0, 1.5));
    expect(summary.episodes[0].segmentId, 'approach');
    expect(summary.episodes[1].segmentId, 'exit');
    expect(summary.episodes[0].startProgressMeters, closeTo(40.0, 1.0));
    expect(summary.segments, hasLength(3), reason: 'every segment listed, zero rows kept');
    expect(summary.segments[1].segmentId, 'corner');
    expect(summary.segments[1].episodes, 0);
    expect(summary.segments[1].seconds, lessThan(0.1));
    expect(summary.segments[0].meters, closeTo(10.0, 1.5));
    expect(summary.segments[2].meters, closeTo(10.0, 1.5));
    expect(summary.knownSeconds, closeTo(10.0, 0.1));

    // Without progress or segments the lap totals remain.
    final bare = summarizeCoasting(session, 0.0, 10.0);
    expect(bare.episodes, hasLength(2));
    expect(bare.segments, isEmpty);
    expect(bare.episodes[0].startProgressMeters, isNull);

    // Without pedals and acceleration it cannot be told: unknown, not zero.
    final unknown = summarizeCoasting(
      _session({'speed': _channel('velocity', 'km/h', _speed)}),
      0.0,
      10.0,
    );
    expect(unknown.provenance, 'unknown');
    expect(unknown.unresolvedReason, 'pedalStateUnknown');
    expect(unknown.episodes, isEmpty);
  });

  test('measures braking while cornering', () {
    // Braking 5-7 s and cornering 4.5-7.5 s overlap for 2 s; at 110 km/h
    // that is 61.1 m.
    final session = _session({
      'brake': _channel('brake_pos-obd', '%', _brake),
      'throttle': _channel('accelerator_pos-obd', '%', _throttle),
      'lateralAcceleration': _channel('latacc-calc', 'g', _lateral),
      'speed': _channel('velocity', 'km/h', _speed),
    });
    final states = classifyDrivingStates(session, 0.0, 10.0);
    final overlap = overlapOf(states.braking.active, states.cornering.active);
    expect(overlap, hasLength(1));
    expect(overlap[0].end - overlap[0].start, closeTo(2.0, 0.15));
    expect(travelledMeters(session, overlap), closeTo(110.0 / 3.6 * 2.0, 4.0));
    expect(overlapOf(states.braking.active, const []), isEmpty);
    expect(travelledMeters(_session(const {}), overlap), 0.0, reason: 'no speed: none invented');
  });

  test('counts no distance across a speed gap longer than the gap threshold', () {
    // Steps of 0.25 s put the threshold at 3 x 0.25 = 0.75 s: the 0.75 s step
    // from 1 s is counted, the 1 s step from 2.25 s is not. 36 km/h is 10 m/s.
    const times = [0.0, 0.25, 0.5, 0.75, 1.0, 1.75, 2.0, 2.25, 3.25, 3.5, 3.75];
    final session = _session({
      'speed': TelemetryChannel(
        name: 'velocity',
        unit: 'km/h',
        timestamps: Float64List.fromList(times),
        values: Float32List.fromList([for (final _ in times) 36.0]),
      ),
    });
    expect(travelledMeters(session, const [DrivingStateInterval(0.0, 3.75)]), closeTo(27.5, 1e-9));
  });

  group('on a comparison', () {
    final session = parseVboFile('test/parity/driving/driving_measured.vbo');
    final laps = deriveSourceLapSession(session);
    ComparisonLap lap(int index) => ComparisonLap(
      session: session,
      laps: laps,
      start: laps.timedLaps[index].startTelemetryTime,
      end: laps.timedLaps[index].endTelemetryTime,
      lapNumber: laps.timedLaps[index].number,
    );
    final comparison = LapComparison(lap(0), lap(1));
    final length = comparison.axisLengthMeters;

    test('the whole axis is each lap from start to end', () {
      expect(comparison.axis.valid, isTrue);
      expect(comparisonTimeRange(comparison, 1, 0, length), (lap(1).start, lap(1).end));
      expect(comparisonTimeRange(comparison, 0, 10, 10), isNull);
    });

    test('G-G of both laps with peaks from every pair', () {
      final scatter = comparisonGgScatter(comparison, 0, length, 200);
      expect(scatter.valid, isTrue);
      for (final lap in scatter.laps) {
        expect(lap.valid, isTrue);
        expect(lap.points.length, lessThanOrEqualTo(204));
        expect(lap.peaks.sampleCount, lap.pairs!.points.length);
        expect(lap.peaks.combined!.value, greaterThan(0.5));
      }
      final part = comparisonGgScatter(comparison, length * 0.2, length * 0.4, 200);
      expect(part.laps[0].peaks.sampleCount, lessThan(scatter.laps[0].peaks.sampleCount));
    });

    test('trail braking across start/finish lays both ends side by side', () {
      final trail = comparisonTrailBraking(comparison, length * 0.8, length * 0.2);
      expect(trail.valid, isTrue);
      expect(trail.crossesStartFinish, isTrue);
      for (final lap in trail.laps) {
        expect(lap.valid, isTrue);
        expect(lap.brakingProvenance, 'measured');
        for (final part in [...lap.brakingStrip, ...lap.corneringStrip, ...lap.overlapStrip]) {
          expect(part.from, inInclusiveRange(-1e-9, 1 + 1e-9));
          expect(part.to, greaterThanOrEqualTo(part.from));
        }
      }
    });

    test('driving states and coasting over a range', () {
      final laps = comparisonDrivingStates(comparison, 0, length);
      expect(laps, hasLength(2));
      for (final lap in laps) {
        expect(lap.valid, isTrue);
        expect(lap.states.coasting.provenance, 'measured');
        expect(lap.coasting.episodes, isNotEmpty);
        for (final episode in lap.coasting.episodes) {
          expect(episode.startProgressMeters, isNotNull);
        }
        expect(intervalSeconds(lap.overlap), greaterThan(0));
      }
    });
  });
}
