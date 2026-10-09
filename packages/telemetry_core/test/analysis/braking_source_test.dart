// Truth tests for the braking source (FET-204): the brake channel is used
// when its data can be trusted, not merely because it exists.
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

/// A 60 s session: six 1.5 s brakings at 0.8 g, from 5 s every 10 s.
bool _braking(double t) => t % 10.0 >= 5.0 && t % 10.0 < 6.5;
double _deceleration(double t) => _braking(t) ? -0.8 : 0.05;
double _goodBrake(double t) => _braking(t) ? 60.0 : 0.0;

TelemetrySession _session({
  double Function(double t)? brake,
  double brakeStep = 0.1,
  String brakeUnit = '%',
  double Function(double t)? deceleration,
  String decelerationUnit = 'g',
  bool Function(double t)? decelerationRecorded,
}) {
  TelemetryChannel channel(
    String name,
    String unit,
    double step,
    double Function(double) value, [
    bool Function(double t)? recorded,
  ]) {
    final times = [
      for (var i = 0; i * step <= 60.0 + 1e-9; ++i)
        if (recorded?.call(i * step) ?? true) i * step,
    ];
    return TelemetryChannel(
      name: name,
      unit: unit,
      timestamps: Float64List.fromList(times),
      values: Float32List.fromList([for (final t in times) value(t)]),
    );
  }

  return TelemetrySession(
    duration: 60,
    startTime: 0,
    metadata: const {},
    channels: {
      if (brake != null) 'brake': channel('brake', brakeUnit, brakeStep, brake),
      if (deceleration != null)
        'longacc': channel('longacc', decelerationUnit, 0.1, deceleration, decelerationRecorded),
    },
    aliases: {
      if (brake != null) 'brake': 'brake',
      if (deceleration != null) 'longitudinalAcceleration': 'longacc',
    },
    warnings: const [],
    timingGates: const [],
    sampleCount: 601,
  );
}

void main() {
  test('a brake pressed in every hard braking is used', () {
    final session = _session(brake: _goodBrake, deceleration: _deceleration);
    final quality = brakingSourceQuality(session);
    expect(quality.hardBrakings, 6);
    expect(quality.hardBrakingsWithBrake, 6);
    expect(quality.brakeUsable, isTrue);
    final detection = detectBrakingOnsets(session, 0, 60);
    expect(detection.method, brakingMethodMeasured);
    expect(detection.candidates, hasLength(6));
  });

  test('a brake that is never pressed gives way to the deceleration', () {
    final session = _session(brake: (_) => 0.0, deceleration: _deceleration);
    expect(brakingSourceQuality(session).brakeRejected, isTrue);
    final detection = detectBrakingOnsets(session, 0, 60);
    expect(detection.method, brakingMethodInferred);
    expect(detection.channel, 'longacc');
    expect(detection.candidates, hasLength(6));
    final states = classifyDrivingStates(session, 0, 60);
    expect(states.braking.provenance, drivingStateInferred);
    expect(states.braking.channel, 'longacc');
  });

  test('a brake pressed in only one of six hard brakings gives way to the deceleration', () {
    final session = _session(
      brake: (t) => t >= 5.0 && t < 6.5 ? 60.0 : 0.0,
      deceleration: _deceleration,
    );
    final quality = brakingSourceQuality(session);
    expect(quality.hardBrakingsWithBrake, 1);
    expect(quality.brakeRejected, isTrue);
    expect(detectBrakingOnsets(session, 0, 60).method, brakingMethodInferred);
  });

  test('a brake with no data gives way to the deceleration', () {
    final session = _session(brake: (_) => double.nan, deceleration: _deceleration);
    expect(brakingSourceQuality(session).brakeRejected, isTrue);
    expect(detectBrakingOnsets(session, 0, 60).method, brakingMethodInferred);
  });

  test('with inference disabled, a doubtful brake is still the only source', () {
    final session = _session(brake: (_) => 0.0, deceleration: _deceleration);
    const options = BrakingOnsetOptions(allowInferred: false);
    expect(detectBrakingOnsets(session, 0, 60, options: options).method, brakingMethodMeasured);
    final states = classifyDrivingStates(
      session,
      0,
      60,
      const DrivingStateOptions(allowInferred: false),
    );
    expect(states.braking.provenance, drivingStateMeasured);
  });

  test('without a usable deceleration the brake is kept, as there is nothing to judge it by', () {
    // Never pressed, but no deceleration (a short pit-lane run looks the
    // same), one in a unit that cannot be read as g, or one that never shows
    // braking.
    for (final session in [
      _session(brake: (_) => 0.0),
      _session(
        brake: (_) => 0.0,
        deceleration: (t) => _deceleration(t) * 9.81,
        decelerationUnit: 'furlongs/fortnight2',
      ),
      _session(brake: (_) => 0.0, deceleration: (_) => 0.0),
    ]) {
      expect(brakingSourceQuality(session).brakeRejected, isFalse);
      expect(detectBrakingOnsets(session, 0, 60).method, brakingMethodMeasured);
    }
  });

  test('a slow brake at 2 Hz that agrees with the deceleration is used', () {
    final session = _session(brake: _goodBrake, brakeStep: 0.5, deceleration: _deceleration);
    expect(brakingSourceQuality(session).brakeUsable, isTrue);
    expect(detectBrakingOnsets(session, 0, 60).method, brakingMethodMeasured);
  });

  test('with too few hard brakings to judge, the brake is kept', () {
    final session = _session(
      brake: (_) => 0.0,
      deceleration: (t) => t < 20.0 ? _deceleration(t) : 0.05,
    );
    final quality = brakingSourceQuality(session);
    expect(quality.hardBrakings, 2);
    expect(quality.brakeUsable, isTrue);
    expect(detectBrakingOnsets(session, 0, 60).method, brakingMethodMeasured);
  });

  test('without a brake the deceleration is used as before', () {
    final session = _session(deceleration: _deceleration);
    expect(detectBrakingOnsets(session, 0, 60).method, brakingMethodInferred);
    expect(detectBrakingOnsets(_session(), 0, 60).unresolvedReason, brakingNoChannel);
  });

  test('every window of a session uses the same source', () {
    final session = _session(brake: (_) => 0.0, deceleration: _deceleration);
    for (var start = 0.0; start < 60.0; start += 10.0) {
      expect(detectBrakingOnsets(session, start, start + 10.0).channel, 'longacc');
    }
  });

  test('a rejected brake is named on every inferred braking, a used one never', () {
    final rejected = detectBrakingOnsets(
      _session(brake: (_) => 0.0, deceleration: _deceleration),
      0,
      60,
    );
    expect(rejected.candidates, hasLength(6));
    for (final candidate in rejected.candidates) {
      expect(candidate.uncertaintyReasons, contains(brakingBrakeChannelNotUsed));
    }
    for (final session in [
      _session(brake: _goodBrake, deceleration: _deceleration),
      _session(deceleration: _deceleration),
    ]) {
      for (final candidate in detectBrakingOnsets(session, 0, 60).candidates) {
        expect(candidate.uncertaintyReasons, isNot(contains(brakingBrakeChannelNotUsed)));
      }
    }
  });

  test('a brake with too few samples gives way even when the hard brakings cannot judge it', () {
    // Two hard brakings: too few to judge agreement, so only the data rule
    // decides. 19 finite samples reject the brake, 20 keep it.
    double twoBrakings(double t) => t < 20.0 ? _deceleration(t) : 0.05;
    TelemetrySession withSamples(int count) => _session(
      brake: (t) => t < count * 0.1 - 0.05 ? 0.0 : double.nan,
      deceleration: twoBrakings,
    );
    expect(brakingSourceQuality(withSamples(19)).brakeRejected, isTrue);
    expect(brakingSourceQuality(withSamples(20)).brakeRejected, isFalse);
    expect(brakingSourceQuality(withSamples(19)).hardBrakings, 0);
  });

  test('the brake must be pressed in at least half of the hard brakings', () {
    // Pressed in the first [n] of the six brakings.
    TelemetrySession pressedIn(int n) => _session(
      brake: (t) => t < n * 10.0 && _braking(t) ? 60.0 : 0.0,
      deceleration: _deceleration,
    );
    expect(brakingSourceQuality(pressedIn(3)).hardBrakingsWithBrake, 3);
    expect(brakingSourceQuality(pressedIn(3)).brakeRejected, isFalse);
    expect(brakingSourceQuality(pressedIn(2)).hardBrakingsWithBrake, 2);
    expect(brakingSourceQuality(pressedIn(2)).brakeRejected, isTrue);
  });

  test('a hard braking reaches 0.45 g and stays beyond 0.30 g for half a second', () {
    int hardBrakings(double Function(double t) shape) => brakingSourceQuality(
      _session(brake: (_) => 0.0, deceleration: (t) => _braking(t) ? shape(t % 10.0) : 0.05),
    ).hardBrakings;
    expect(hardBrakings((_) => -0.46), 6);
    expect(hardBrakings((_) => -0.44), 0);
    // Peak for 0.2 s, then held at 0.35 g: one braking; at 0.25 g: too short.
    expect(hardBrakings((t) => t < 5.2 ? -0.5 : -0.35), 6);
    expect(hardBrakings((t) => t < 5.2 ? -0.5 : -0.25), 0);
    // 0.7 s is long enough, 0.3 s is not.
    expect(hardBrakings((t) => t < 5.7 ? -0.8 : 0.05), 6);
    expect(hardBrakings((t) => t < 5.3 ? -0.8 : 0.05), 0);
  });

  test('a hard braking never spans a gap in the deceleration', () {
    // Each braking is recorded as two 0.4 s halves around a 0.6 s dropout.
    final session = _session(
      brake: (_) => 0.0,
      deceleration: _deceleration,
      decelerationRecorded: (t) => !(t % 10.0 > 5.45 && t % 10.0 < 6.05),
    );
    expect(brakingSourceQuality(session).hardBrakings, 0);
    expect(brakingSourceQuality(session).brakeRejected, isFalse);
  });

  test('the brake may be pressed up to half a second before the deceleration builds', () {
    TelemetrySession pressedFrom(double from, double to) => _session(
      brake: (t) => t % 10.0 >= from && t % 10.0 < to ? 60.0 : 0.0,
      deceleration: _deceleration,
    );
    expect(brakingSourceQuality(pressedFrom(4.6, 4.9)).brakeRejected, isFalse);
    expect(brakingSourceQuality(pressedFrom(4.0, 4.4)).brakeRejected, isTrue);
  });

  test('a deceleration with no declared unit judges the brake', () {
    final session = _session(brake: (_) => 0.0, deceleration: _deceleration, decelerationUnit: '');
    expect(brakingSourceQuality(session).brakeRejected, isTrue);
  });

  test('a brake in another unit is kept to report its unit, unless it has no data', () {
    // Pressure in bar is never compared with 10 %: no fallback to
    // deceleration, the analyses report the unit.
    final bar = _session(
      brake: (t) => _braking(t) ? 6.0 : 0.0,
      brakeUnit: 'bar',
      deceleration: _deceleration,
    );
    expect(brakingSourceQuality(bar).brakeRejected, isFalse);
    expect(detectBrakingOnsets(bar, 0, 60).unresolvedReason, brakingUnitMismatch);
    expect(classifyDrivingStates(bar, 0, 60).braking.unresolvedReason, 'unitMismatch');
    final empty = _session(brake: (_) => double.nan, brakeUnit: 'bar', deceleration: _deceleration);
    expect(brakingSourceQuality(empty).brakeRejected, isTrue);
  });

  test('corner braking and driving states always use the same source', () {
    // A short peak then a light braking (the shape the two analyses'
    // different thresholds would judge differently), a dead brake, and a
    // good one.
    for (final session in [
      _session(
        brake: (_) => 0.0,
        deceleration: (t) => _braking(t) ? (t % 10.0 < 5.2 ? -0.5 : -0.2) : 0.05,
      ),
      _session(brake: (_) => 0.0, deceleration: _deceleration),
      _session(brake: _goodBrake, deceleration: _deceleration),
    ]) {
      final onset = detectBrakingOnsets(session, 0, 60);
      final states = classifyDrivingStates(session, 0, 60);
      expect(states.braking.channel, onset.channel);
      expect(
        states.braking.provenance == drivingStateInferred,
        onset.method == brakingMethodInferred,
      );
    }
  });

  test('a deceleration threshold beyond the hard braking still finishes', () {
    final session = _session(brake: (_) => 0.0, deceleration: (t) => _braking(t) ? -0.48 : 0.05);
    final detection = detectBrakingOnsets(
      session,
      0,
      60,
      options: const BrakingOnsetOptions(inferredDeceleration: BrakingThreshold(0.5, 0.25, 'g')),
    );
    expect(detection.valid, isTrue);
  });
}
