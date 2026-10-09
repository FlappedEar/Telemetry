// Truth tests for pedal channels with no unit within 0..1 (FET-205): read
// as a fraction only when the longitudinal G shows the pedal working at
// that scale, otherwise reported as an unknown scale, never guessed.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

/// A 60 s session at 10 Hz: six 1.5 s brakings at 0.8 g from 5 s every
/// 10 s, each followed by a 2 s acceleration at 0.3 g from 7 s.
bool _braking(double t) => t % 10.0 >= 5.0 && t % 10.0 < 6.5;
bool _accelerating(double t) => t % 10.0 >= 7.0 && t % 10.0 < 9.0;
double _longitudinal(double t) => _braking(t) ? -0.8 : (_accelerating(t) ? 0.3 : 0.0);

TelemetrySession _session({
  double Function(double t)? brake,
  String brakeUnit = '',
  double Function(double t)? throttle,
  bool g = true,
}) {
  TelemetryChannel channel(String name, String unit, double Function(double) value) {
    final times = [for (var i = 0; i <= 600; ++i) i / 10.0];
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
      if (brake != null) 'brake': channel('brake', brakeUnit, brake),
      if (throttle != null) 'throttle': channel('throttle', '', throttle),
      if (g) 'longacc': channel('longacc', 'g', _longitudinal),
    },
    aliases: {
      if (brake != null) 'brake': 'brake',
      if (throttle != null) 'throttle': 'throttle',
      if (g) 'longitudinalAcceleration': 'longacc',
    },
    warnings: const [],
    timingGates: const [],
    sampleCount: 601,
  );
}

double _fractionBrake(double t) => _braking(t) ? 0.6 : 0.0;

void main() {
  test('a 0..1 brake that the hard brakings show is read as a fraction', () {
    final session = _session(brake: _fractionBrake);
    final quality = brakingSourceQuality(session);
    expect(quality.brakeScale, PedalScale.fraction);
    expect(quality.brakeUsable, isTrue);
    expect(quality.hardBrakingsWithBrake, 6);
    final onsets = detectBrakingOnsets(session, 0, 60);
    expect(onsets.method, brakingMethodMeasured);
    expect(onsets.threshold.on, closeTo(0.10, 1e-12));
    expect(onsets.candidates, hasLength(6));
    expect(onsets.candidates.first.telemetryTime, closeTo(5.0, 0.11));
    for (final candidate in onsets.candidates) {
      expect(candidate.uncertaintyReasons, contains(brakingScaleInferred));
    }
    final states = classifyDrivingStates(session, 0, 60);
    expect(states.braking.provenance, drivingStateMeasured);
    expect(states.braking.scale, PedalScale.fraction);
    expect(states.braking.active, hasLength(6));
  });

  test('a 0..1 brake with nothing to show its scale is reported, not guessed', () {
    final session = _session(brake: _fractionBrake, g: false);
    expect(brakingSourceQuality(session).brakeScale, PedalScale.unknown);
    final onsets = detectBrakingOnsets(session, 0, 60);
    expect(onsets.method, brakingMethodMeasured);
    expect(onsets.unresolvedReason, brakingScaleUnknown);
    expect(onsets.candidates, isEmpty);
    final states = classifyDrivingStates(session, 0, 60);
    expect(states.braking.provenance, drivingStateUnknown);
    expect(states.braking.unresolvedReason, 'scaleUnknown');
  });

  test('sensor noise under 1 on a % brake is never turned into braking', () {
    // Never pressed, noise up to 0.8 % at random times: the hard brakings
    // do not show it, so its scale is unknown and the deceleration is used.
    final random = math.Random(205);
    final noise = [for (var i = 0; i <= 600; ++i) random.nextDouble() * 0.8];
    final session = _session(brake: (t) => noise[(t * 10).round()]);
    final quality = brakingSourceQuality(session);
    expect(quality.brakeScale, PedalScale.unknown);
    expect(quality.brakeRejected, isTrue);
    final onsets = detectBrakingOnsets(session, 0, 60);
    expect(onsets.method, brakingMethodInferred);
    expect(onsets.candidates, hasLength(6));
    // The reason carried to the panels is the scale, not "does not show the
    // braking" (FET-244).
    expect(classifyDrivingStates(session, 0, 60).braking.inferredBecause, brakingScaleUnknown);
  });

  test('a declared unit is never rescaled, and values beyond 1 stay %', () {
    final declared = _session(brake: _fractionBrake, brakeUnit: '%');
    expect(brakingSourceQuality(declared).brakeScale, PedalScale.percent);
    expect(brakingSourceQuality(declared).brakeRejected, isTrue);
    final percent = _session(brake: (t) => _braking(t) ? 60.0 : 0.0);
    expect(brakingSourceQuality(percent).brakeScale, PedalScale.percent);
    expect(detectBrakingOnsets(percent, 0, 60).threshold.on, 10.0);
    // A brake that never moves is not a scale question.
    expect(brakingSourceQuality(_session(brake: (_) => 0.0)).brakeScale, PedalScale.percent);
  });

  test('the brake must be pressed at the fraction scale in half the hard brakings', () {
    TelemetrySession pressedIn(int n) =>
        _session(brake: (t) => t < n * 10.0 && _braking(t) ? 0.6 : 0.0);
    expect(brakingSourceQuality(pressedIn(3)).brakeScale, PedalScale.fraction);
    expect(brakingSourceQuality(pressedIn(2)).brakeScale, PedalScale.unknown);
  });

  test('a 0..1 throttle is read as a fraction when the accelerations show it', () {
    final session = _session(throttle: (t) => _accelerating(t) ? 0.9 : 0.0);
    expect(throttleScale(session), PedalScale.fraction);
    final states = classifyDrivingStates(session, 0, 60);
    expect(states.accelerating.provenance, drivingStateMeasured);
    expect(states.accelerating.scale, PedalScale.fraction);
    expect(states.accelerating.active, hasLength(6));

    final alone = _session(throttle: (t) => _accelerating(t) ? 0.9 : 0.0, g: false);
    expect(throttleScale(alone), PedalScale.unknown);
    expect(classifyDrivingStates(alone, 0, 60).accelerating.unresolvedReason, 'scaleUnknown');
  });

  test('a pedal pressed in the brakings but also in the accelerations is not a fraction', () {
    final session = _session(brake: (t) => _braking(t) || _accelerating(t) ? 0.6 : 0.0);
    expect(brakingSourceQuality(session).brakeScale, PedalScale.unknown);
    final onsets = detectBrakingOnsets(session, 0, 60);
    expect(onsets.method, brakingMethodInferred);
    for (final candidate in onsets.candidates) {
      expect(candidate.uncertaintyReasons, contains(brakingScaleUnknown));
      expect(candidate.uncertaintyReasons, isNot(contains(brakingBrakeChannelNotUsed)));
    }
  });

  test('peaks up to 1.5 are ambiguous, beyond are %', () {
    expect(
      brakingSourceQuality(_session(brake: (t) => _braking(t) ? 1.4 : 0.0)).brakeScale,
      PedalScale.fraction,
    );
    expect(
      brakingSourceQuality(_session(brake: (t) => _braking(t) ? 1.6 : 0.0)).brakeScale,
      PedalScale.percent,
    );
  });

  test('fewer than 3 runs of either kind leave the scale unknown', () {
    // Accelerations only in the first 20 s: two.
    final twoAccelerations = _session(
      throttle: (t) => t < 20 && _accelerating(t) ? 0.9 : 0.0,
      brake: _fractionBrake,
    );
    expect(brakingSourceQuality(twoAccelerations).brakeScale, PedalScale.fraction);
    expect(throttleScale(twoAccelerations), PedalScale.unknown);
    final session = _session(brake: _fractionBrake, g: false);
    expect(brakingSourceQuality(session).brakeScale, PedalScale.unknown);
  });

  test('the pedal may lead the G by half a second', () {
    TelemetrySession pressedFrom(double from, double to) =>
        _session(brake: (t) => t % 10.0 >= from && t % 10.0 < to ? 0.6 : 0.0);
    expect(brakingSourceQuality(pressedFrom(4.6, 4.9)).brakeScale, PedalScale.fraction);
    expect(brakingSourceQuality(pressedFrom(4.0, 4.4)).brakeScale, PedalScale.unknown);
  });

  test('a throttle needs 20 finite samples to be judged', () {
    final sparse = _session(throttle: (t) => t < 1.9 ? (t * 10).round() % 2 * 0.9 : double.nan);
    expect(throttleScale(sparse), PedalScale.percent);
    final twenty = _session(throttle: (t) => t < 1.95 ? (t * 10).round() % 2 * 0.9 : double.nan);
    expect(throttleScale(twenty), PedalScale.unknown);
  });
}
