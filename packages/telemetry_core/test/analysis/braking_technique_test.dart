// Braking technique (FET-219): hit, peak, trail braking, release and
// brake-to-throttle time from the longitudinal deceleration, with every
// threshold tested on both sides. Synthetic recordings only.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

/// A braking from [start] s: deceleration (g) rises linearly to [peak] over
/// [rise] s, holds for [hold] s and falls linearly to 0 over [fall] s.
/// With [kink], the rise is steeper above [kink] × [peak] (twice as steep).
double Function(double) _braking({
  double start = 10.0,
  double peak = 1.0,
  double rise = 0.5,
  double hold = 1.0,
  double fall = 1.0,
  double? kink,
}) => (t) {
  final x = t - start;
  if (x <= 0) return 0.0;
  if (kink != null) {
    // Slope s up to kink × peak, then 2 s to the peak.
    final slope = peak / rise;
    final kinkTime = kink * peak / slope;
    final topTime = kinkTime + (1 - kink) * peak / (2 * slope);
    if (x < kinkTime) return slope * x;
    if (x < topTime) return kink * peak + 2 * slope * (x - kinkTime);
    if (x < topTime + hold) return peak;
    if (x < topTime + hold + fall) return peak * (1 - (x - topTime - hold) / fall);
    return 0.0;
  }
  if (x < rise) return peak * x / rise;
  if (x < rise + hold) return peak;
  if (x < rise + hold + fall) return peak * (1 - (x - rise - hold) / fall);
  return 0.0;
};

TelemetryChannel _channel(
  String name,
  double Function(double) value, {
  String unit = '',
  double step = 0.1,
  double from = 0.0,
  double to = 30.0,
  bool Function(double t)? recorded,
}) {
  final times = <double>[];
  for (var i = 0; from + i * step <= to + 1e-9; ++i) {
    final t = from + i * step;
    if (recorded?.call(t) ?? true) times.add(t);
  }
  return TelemetryChannel(
    name: name,
    unit: unit,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList([for (final t in times) value(t)]),
  );
}

/// The speed (km/h, 25 Hz) of a car at [initial] m/s slowing by
/// [deceleration], with ±0.02 km/h of GPS noise.
TelemetryChannel _speed(double Function(double) deceleration, {double initial = 40.0}) {
  const step = 0.04, fine = 0.001;
  final random = math.Random(7);
  final times = <double>[], values = <double>[];
  var v = initial, t = 0.0, next = 0.0;
  while (t <= 30.0 + 1e-9) {
    if (t >= next - 1e-9) {
      times.add(next);
      values.add(v * 3.6 + (random.nextDouble() - 0.5) * 0.04);
      next = times.length * step;
    }
    v -= deceleration(t + fine / 2) * standardGravity * fine;
    t += fine;
  }
  return TelemetryChannel(
    name: 'velocity',
    unit: 'km/h',
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
}

TelemetrySession _session({
  double Function(double)? deceleration,
  String gUnit = 'g',
  double gStep = 0.1,
  double gScale = 1.0,
  bool Function(double t)? gRecorded,
  bool speed = true,
  double Function(double)? lateral,
  double lateralStep = 0.1,
  double Function(double)? throttle,
  TelemetryChannel? brake,
}) {
  final decel = deceleration ?? _braking();
  final channels = <String, TelemetryChannel>{
    'longacc': _channel(
      'longacc',
      (t) => -decel(t) * gScale,
      unit: gUnit,
      step: gStep,
      recorded: gRecorded,
    ),
    if (speed) 'velocity': _speed(decel),
    if (lateral != null) 'latacc': _channel('latacc', lateral, unit: 'g', step: lateralStep),
    if (throttle != null) 'throttle': _channel('throttle', throttle, unit: '%'),
    'brake': ?brake,
  };
  return TelemetrySession(
    duration: 30,
    startTime: 0,
    metadata: const {},
    channels: channels,
    aliases: {
      'longitudinalAcceleration': 'longacc',
      if (speed) 'speed': 'velocity',
      if (lateral != null) 'lateralAcceleration': 'latacc',
      if (throttle != null) 'throttle': 'throttle',
      if (brake != null) 'brake': 'brake',
    },
    warnings: const [],
    timingGates: const [],
    sampleCount: 301,
  );
}

TelemetrySession _speedOnly(double Function(double) deceleration, {TelemetryChannel? g}) =>
    TelemetrySession(
      duration: 30,
      startTime: 0,
      metadata: const {},
      channels: {'velocity': _speed(deceleration), 'longacc': ?g},
      aliases: {'speed': 'velocity', if (g != null) 'longitudinalAcceleration': 'longacc'},
      warnings: const [],
      timingGates: const [],
      sampleCount: 751,
    );

/// A 2 Hz OBD pedal (one update every [period] s, from [phase]) written at
/// 10 Hz the way RaceChrono's VBO export writes it: straight lines between
/// the updates, or the last update held.
TelemetryChannel _obdBrake(
  double Function(double) pedal, {
  double period = 0.48,
  double phase = 0.13,
  bool held = false,
  double step = 0.1,
}) {
  double value(double t) {
    final k = ((t - phase) / period).floor();
    final t0 = phase + k * period, t1 = t0 + period;
    if (held) return pedal(t0);
    return pedal(t0) + (pedal(t1) - pedal(t0)) * (t - t0) / period;
  }

  return _channel('brake', value, unit: '%', step: step);
}

// A pedal pressed with the deceleration's shape, 0 to 80 %, every 6 s (at
// 4, 10, 16, 22 and 28 s), so its rate can be told.
double _pedal(double t) => 80.0 * _braking(start: 0)((t - 4) % 6);

// The same presses, smooth as a real foot: an OBD channel drawn with
// straight lines then bends at every update.
double _smoothPedal(double t) {
  final x = (t - 4) % 6;
  return x < 3 ? 80.0 * math.pow(math.sin(math.pi * x / 3), 2) : 0.0;
}

BrakingTechniqueLap _measure(TelemetrySession session, {double from = 5.0, double to = 16.0}) =>
    measureBrakingTechnique(session, from, to);

void main() {
  group('a braking from the G channel', () {
    final lap = _measure(
      _session(
        lateral: (t) => t < 11.0 ? 0.0 : math.min(0.8, 0.8 * (t - 11.0)),
        throttle: (t) => t < 13.0 ? 0.0 : 50.0,
      ),
    );

    test('finds the zone from the 0.15 g crossings', () {
      expect(lap.unavailableReason, isEmpty);
      expect(lap.source, brakingTechniqueFromG);
      expect(lap.channel, 'longacc');
      expect(lap.declaredUnit, 'g');
      expect(lap.unitAssumed, isFalse);
      expect(lap.rateHz, closeTo(10, 0.01));
      // 0.15 g on a 2 g/s rise from 10 s, and on a 1 g/s fall from 11.5 s.
      expect(lap.onsetTime, closeTo(10.075, 1e-6));
      expect(lap.endTime, closeTo(12.35, 1e-6));
      expect(lap.zoneSeconds, closeTo(2.275, 1e-6));
    });

    test('measures the peak and where it falls', () {
      expect(lap.peakG, closeTo(1.0, 1e-6));
      // The first sample at the peak, 10.5 s.
      expect(lap.peakTime, closeTo(10.5, 1e-6));
      expect(lap.zoneMeters, greaterThan(0));
      expect(lap.peakAfterOnsetMeters, lessThan(lap.zoneMeters!));
      expect(lap.peakFraction, closeTo(lap.peakAfterOnsetMeters! / lap.zoneMeters!, 1e-9));
      // Distance from the recorded speed: onset at about 40 m/s.
      expect(lap.zoneMeters, closeTo(70, 10));
    });

    test('reads the hit and the release as the rise and fall rates', () {
      expect(lap.hitGPerSecond, closeTo(2.0, 1e-3));
      expect(lap.releaseGPerSecond, closeTo(1.0, 1e-3));
    });

    test('times trail braking while the lateral G is at least 0.3 g (inferred)', () {
      // Lateral G reaches 0.3 g at 11.375 s; braking ends at 12.35 s. Read on
      // the 10 Hz samples, so to within one sample interval.
      expect(lap.trailSeconds, closeTo(0.975, 0.06));
      expect(lap.trailMeters, greaterThan(0));
      expect(lap.trailReason, isEmpty);
      expect(lap.lateralRateHz, closeTo(10, 0.01));
    });

    test('times braking to the throttle pickup', () {
      // The throttle passes 20 % between 12.9 s (0) and 13.0 s (50 %).
      expect(lap.brakeToThrottleSeconds, closeTo(12.94 - 12.35, 1e-3));
      expect(lap.throttleChannel, 'throttle');
    });

    test('says there is no brake pedal', () {
      expect(lap.pedalReason, brakingTechniqueNoBrake);
      expect(lap.pedalApplicationPerSecond, isNull);
    });
  });

  group('thresholds, each on both sides', () {
    test('braking starts from 0.30 g', () {
      final at = _measure(_session(deceleration: _braking(peak: 0.30)));
      final below = _measure(_session(deceleration: _braking(peak: 0.29)));
      expect(at.measured, isTrue);
      expect(below.measured, isFalse);
      expect(below.unavailableReason, brakingTechniqueNoBraking);
    });

    test('braking ends below 0.15 g', () {
      // Falling to 0.16 g and holding there: braking never ends in the
      // recording read.
      final holding = _measure(_session(deceleration: (t) => t < 12.0 ? _braking()(t) : 0.16));
      final ending = _measure(
        _session(deceleration: (t) => t < 12.0 ? _braking()(t) : (t < 12.5 ? 0.14 : 0.0)),
      );
      expect(holding.unavailableReason, brakingTechniqueTruncated);
      expect(ending.measured, isTrue);
      expect(ending.endTime, lessThan(12.1));
    });

    test('a braking shorter than 0.3 s is a bump', () {
      // Above 0.15 g for (1 - 0.15 / 0.6) × (rise + fall) seconds, at 100 Hz.
      TelemetrySession bump(double seconds) {
        final both = seconds / 0.75;
        return _session(
          deceleration: _braking(peak: 0.6, rise: both / 2, hold: 0, fall: both / 2),
          gStep: 0.01,
        );
      }

      expect(_measure(bump(0.31)).measured, isTrue);
      expect(_measure(bump(0.29)).unavailableReason, brakingTechniqueNoBraking);
    });

    test('hit and release need a peak of at least 0.40 g', () {
      final at = _measure(_session(deceleration: _braking(peak: 0.40)));
      final below = _measure(_session(deceleration: _braking(peak: 0.39)));
      expect(at.hitGPerSecond, closeTo(0.8, 1e-3));
      expect(at.releaseGPerSecond, closeTo(0.4, 1e-3));
      expect(below.measured, isTrue);
      expect(below.peakG, closeTo(0.39, 1e-6));
      expect(below.hitGPerSecond, isNull);
      expect(below.hitReason, brakingTechniqueTooLight);
      expect(below.releaseReason, brakingTechniqueTooLight);
    });

    test('the hit runs to 85 % of the peak', () {
      // Twice as steep above the kink: a kink at 85 % leaves the hit at the
      // first slope, a kink at 80 % does not.
      final at = _measure(_session(deceleration: _braking(rise: 0.5, kink: 0.85), gStep: 0.01));
      final below = _measure(_session(deceleration: _braking(rise: 0.5, kink: 0.80), gStep: 0.01));
      expect(at.hitGPerSecond, closeTo(2.0, 0.02));
      expect(below.hitGPerSecond, greaterThan(2.05));
    });

    test('a hit or release needs a sample between its ends', () {
      // Peak reached in one sample interval (0.1 s): too quick for 10 Hz.
      final quick = _measure(_session(deceleration: _braking(rise: 0.1, fall: 0.1)));
      final resolved = _measure(_session(deceleration: _braking(rise: 0.2, fall: 0.2)));
      expect(quick.measured, isTrue);
      expect(quick.hitReason, brakingTechniqueTooQuick);
      expect(quick.releaseReason, brakingTechniqueTooQuick);
      expect(resolved.hitGPerSecond, closeTo(5.0, 1e-3));
      expect(resolved.releaseGPerSecond, closeTo(5.0, 1e-3));
    });

    test('trail braking counts lateral G from 0.30 g', () {
      final at = _measure(_session(lateral: (t) => t < 1 ? 0.0 : 0.30));
      final below = _measure(_session(lateral: (t) => t < 1 ? 0.0 : -0.29));
      final left = _measure(_session(lateral: (t) => t < 1 ? 0.0 : -0.30));
      expect(at.trailSeconds, closeTo(at.zoneSeconds!, 1e-6));
      expect(left.trailSeconds, closeTo(left.zoneSeconds!, 1e-6));
      expect(below.trailSeconds, 0.0);
      expect(below.trailReason, isEmpty);
    });

    test('channels slower than 9.5 Hz give no ramp', () {
      final fast = _measure(_session(gStep: 1 / 9.6));
      final slow = _measure(_session(gStep: 1 / 9.4));
      expect(fast.measured, isTrue);
      expect(slow.unavailableReason, brakingTechniqueDecelerationTooSlow);
      expect(slow.rateHz, closeTo(9.4, 0.01));
      final slowLateral = _measure(
        _session(lateral: (t) => t < 1 ? 0.0 : 0.5, lateralStep: 1 / 9.4),
      );
      expect(slowLateral.trailReason, brakingTechniqueLateralTooSlow);
      expect(slowLateral.trailSeconds, isNull);
    });

    test('looks for braking up to 200 m before the corner', () {
      final segments = [
        {'id': 'a', 'type': 'corner', 'startProgressMeters': 300.0, 'endProgressMeters': 400.0},
      ];
      // One metre per second from the lap's start at 0 s.
      final trace = [
        ProgressSegment([
          for (var t = 0.0; t <= 1000.0; t += 1.0)
            ProjectedSample(t, progressMeters: t, valid: true),
        ]),
      ];
      final window = brakingTechniqueWindow(1000, segments, segments.first, trace, 0, 1000)!;
      expect(window.start, closeTo(100, 1e-6));
      expect(window.end, closeTo(400, 1e-6));
      expect(window.beyondLap, isFalse);
      // A previous corner ending 150 m before stops the approach there.
      final clipped = [
        ...segments,
        {'id': 'b', 'type': 'corner', 'startProgressMeters': 50.0, 'endProgressMeters': 150.0},
      ];
      expect(
        brakingTechniqueWindow(1000, clipped, clipped.first, trace, 0, 1000)!.start,
        closeTo(150, 1e-6),
      );
      // A straight there does not.
      final straight = [
        ...segments,
        {'id': 'c', 'type': 'straight', 'startProgressMeters': 50.0, 'endProgressMeters': 250.0},
      ];
      expect(
        brakingTechniqueWindow(1000, straight, straight.first, trace, 0, 1000)!.start,
        closeTo(100, 1e-6),
      );
    });
  });

  group('the brake pedal', () {
    test('a 2 Hz OBD pedal drawn with lines at 10 Hz is refused for ramps', () {
      final lap = _measure(_session(brake: _obdBrake(_smoothPedal)));
      expect(lap.measured, isTrue);
      expect(lap.brakeChannel, 'brake');
      expect(lap.brakeRateHz, closeTo(1 / 0.48, 0.3));
      expect(lap.pedalReason, brakingTechniqueBrakeTooSlow);
      expect(lap.pedalApplicationPerSecond, isNull);
      expect(lap.pedalReleasePerSecond, isNull);
      // The deceleration still gives the hit and release.
      expect(lap.hitGPerSecond, closeTo(2.0, 1e-3));
    });

    test('lines whose corners land on the samples are read the same', () {
      // 0.97 × the pedal, so the updates are not whole numbers.
      final lap = _measure(
        _session(brake: _obdBrake((t) => 0.97 * _smoothPedal(t), period: 0.5, phase: 0.0)),
      );
      // A corner at the top of a press, where the pedal turns, does not
      // move between its neighbours and is not counted: read a little slow.
      expect(lap.brakeRateHz, inInclusiveRange(1.0, 3.0));
      expect(lap.pedalReason, brakingTechniqueBrakeTooSlow);
    });

    test('a held 2 Hz pedal and a pedal sampled at 2 Hz are refused', () {
      final held = _measure(_session(brake: _obdBrake(_smoothPedal, held: true)));
      final sampled = _measure(_session(brake: _channel('brake', _pedal, unit: '%', step: 0.5)));
      expect(held.brakeRateHz, closeTo(1 / 0.48, 0.3));
      expect(held.pedalReason, brakingTechniqueBrakeTooSlow);
      expect(sampled.brakeRateHz, closeTo(2.0, 1e-6));
      expect(sampled.pedalReason, brakingTechniqueBrakeTooSlow);
    });

    test('a 10 Hz pedal gives its application and release', () {
      final lap = _measure(_session(brake: _channel('brake', _smoothPedal, unit: '%')));
      expect(lap.brakeRateHz, closeTo(10, 0.01));
      expect(lap.pedalReason, isEmpty);
      // From 5 % (pressed from 10 %, let off below 5 %) to 85 % of 80 %, on
      // 80 sin²(πx/3): symmetric, so the same rate both ways.
      double at(double level) => 3 / math.pi * math.asin(math.sqrt(level / 80));
      final expected = (0.85 * 80 - 5) / (at(0.85 * 80) - at(5));
      expect(lap.pedalApplicationPerSecond, closeTo(expected, expected * 0.03));
      expect(lap.pedalReleasePerSecond, closeTo(expected, expected * 0.03));
    });
  });

  group('channel update rates', () {
    test('a varying 10 Hz channel is 10 Hz', () {
      final random = math.Random(3);
      final noisy = _channel('g', (t) => math.sin(t * 3) + random.nextDouble() * 0.01);
      expect(channelUpdateRateHz(noisy), closeTo(10, 0.01));
    });

    test('a smooth 10 Hz channel is 10 Hz', () {
      // Smooth: no straight lines between samples.
      expect(channelUpdateRateHz(_channel('g', (t) => -_smoothPedal(t) / 80)), closeTo(10, 0.01));
    });

    test('a smooth 10 Hz channel written with one decimal is 10 Hz', () {
      // Coarse values look straight between rounding steps, but those
      // corners are neither sharp nor regular.
      double pedal(double t) {
        final x = (t - 4) % 6;
        return x < 3 ? ((85 * math.exp(-x / 2)) * 10).roundToDouble() / 10 : 0.0;
      }

      expect(channelUpdateRateHz(_channel('brake', pedal, unit: '%')), closeTo(10, 0.01));
    });

    test('a channel with no samples has no rate', () {
      final empty = TelemetryChannel(name: 'x', timestamps: Float64List(0), values: Float32List(0));
      expect(channelUpdateRateHz(empty), isNull);
    });
  });

  group('where the deceleration comes from', () {
    test('without a G channel, from the speed', () {
      final lap = _measure(_speedOnly(_braking()));
      expect(lap.source, brakingTechniqueFromSpeed);
      expect(lap.gChannelReason, brakingTechniqueGMissing);
      expect(lap.declaredUnit, 'km/h');
      expect(lap.rateHz, closeTo(25, 0.01));
      // The speed's slope is smoothed over half a second: the peak holds,
      // the ramps read slower than the G channel's.
      expect(lap.peakG, closeTo(1.0, 0.02));
      expect(lap.hitGPerSecond, inInclusiveRange(1.2, 2.0));
      expect(lap.releaseGPerSecond, inInclusiveRange(0.7, 1.0));
    });

    test('a G channel of zero placeholders is not used: from the speed', () {
      final lap = _measure(_speedOnly(_braking(), g: _channel('longacc', (_) => 0.0, unit: 'g')));
      expect(lap.source, brakingTechniqueFromSpeed);
      expect(lap.gChannelReason, brakingTechniqueGPlaceholder);
      expect(lap.measured, isTrue);
    });

    test('a G channel in m/s² is converted; an undeclared one is assumed g', () {
      final metric = _measure(_session(gUnit: 'm/s²', gScale: standardGravity));
      final undeclared = _measure(_session(gUnit: ''));
      expect(metric.declaredUnit, 'm/s²');
      expect(metric.peakG, closeTo(1.0, 1e-5));
      expect(metric.unitAssumed, isFalse);
      expect(undeclared.unitAssumed, isTrue);
      expect(undeclared.peakG, closeTo(1.0, 1e-6));
    });

    test('a G channel in another unit is not read', () {
      final lap = _measure(_session(gUnit: 'ft/s2'));
      expect(lap.unavailableReason, brakingTechniqueUnitNotSupported);
      expect(lap.declaredUnit, 'ft/s2');
    });

    test('a lateral channel of placeholders gives no trail braking', () {
      final lap = _measure(_session(lateral: (_) => 0.0));
      expect(lap.trailReason, brakingTechniqueLateralPlaceholder);
      expect(lap.trailSeconds, isNull);
      expect(_measure(_session()).trailReason, brakingTechniqueNoLateral);
    });

    test('without a throttle, or with a throttle of placeholders, no brake-to-throttle', () {
      expect(_measure(_session()).brakeToThrottleReason, brakingTechniqueNoThrottle);
      final flat = _measure(_session(throttle: (_) => 0.0));
      expect(flat.brakeToThrottleReason, brakingTechniqueNoThrottle);
      expect(flat.brakeToThrottleSeconds, isNull);
    });
  });

  group('not known, and why', () {
    test('braking already under way where the window starts', () {
      final lap = measureBrakingTechnique(_session(), 10.6, 16);
      expect(lap.unavailableReason, brakingTechniqueAlreadyBraking);
      expect(lap.hitGPerSecond, isNull);
    });

    test('a gap in the deceleration', () {
      final lap = _measure(_session(gRecorded: (t) => t < 10.8 || t > 11.4));
      expect(lap.unavailableReason, brakingTechniqueGap);
    });

    test('no braking in the window', () {
      expect(_measure(_session(), from: 15, to: 25).unavailableReason, brakingTechniqueNoBraking);
    });

    test('a window with no time', () {
      expect(
        measureBrakingTechnique(_session(), 5, 5).unavailableReason,
        brakingTechniqueNotCovered,
      );
    });
  });

  group('a corner across start/finish', () {
    // Laps of 100 s at 10 m/s on a 1000 m axis; the lap ends at 100 s.
    // The corner runs from 900 m to 50 m across the line; braking starts at
    // 98 s (980 m) and ends after the line.
    final segments = [
      {'id': 'x', 'type': 'corner', 'startProgressMeters': 900.0, 'endProgressMeters': 50.0},
    ];
    final trace = [
      ProgressSegment([
        for (var t = 0.0; t <= 100.0; t += 1.0)
          ProjectedSample(t, progressMeters: t * 10, valid: true),
      ]),
    ];

    test('reads the recording past the lap end', () {
      final window = brakingTechniqueWindow(1000, segments, segments.first, trace, 0, 100)!;
      expect(window.start, closeTo(70, 1e-6)); // 700 m
      expect(window.end, closeTo(105, 1e-6)); // 50 m into the next lap
      expect(window.beyondLap, isTrue);
      final session = TelemetrySession(
        duration: 120,
        startTime: 0,
        metadata: const {},
        channels: {
          'longacc': _channel('longacc', (t) => -_braking(start: 98.0)(t), unit: 'g', to: 120),
        },
        aliases: const {'longitudinalAcceleration': 'longacc'},
        warnings: const [],
        timingGates: const [],
        sampleCount: 1201,
      );
      final lap = measureBrakingTechnique(
        session,
        window.start,
        window.end,
        beyondLap: window.beyondLap,
      );
      expect(lap.unavailableReason, isEmpty);
      expect(lap.beyondLap, isTrue);
      expect(lap.onsetTime, closeTo(98.075, 1e-6));
      expect(lap.endTime, closeTo(100.35, 1e-6), reason: 'past the lap end at 100 s');
      expect(lap.hitGPerSecond, closeTo(2.0, 1e-3));
      expect(lap.releaseGPerSecond, closeTo(1.0, 1e-3));
      // Without a speed, the peak's place is by time.
      expect(lap.zoneMeters, isNull);
      expect(lap.peakFraction, closeTo((98.5 - 98.075) / 2.275, 1e-6));
    });

    test('an approach reaching before the gate starts before the lap', () {
      final first = [
        {'id': 'y', 'type': 'corner', 'startProgressMeters': 100.0, 'endProgressMeters': 200.0},
      ];
      final window = brakingTechniqueWindow(1000, first, first.first, trace, 0, 100)!;
      expect(window.start, closeTo(-10, 1e-6));
      expect(window.beyondLap, isTrue);
    });
  });

  group('typical values over the laps', () {
    BrakingTechniqueLap lap(double rise, {String unit = 'g'}) => _measure(
      _session(
        deceleration: _braking(rise: rise),
        gUnit: unit,
      ),
    );

    test('need three laps', () {
      final three = summarizeBrakingTechnique([('a', lap(0.5)), ('b', lap(0.4)), ('c', lap(0.25))]);
      expect(three.unavailableReason, isEmpty);
      expect(three.source, brakingTechniqueFromG);
      expect(three.lapsBraking, 3);
      expect(three.hit.median, closeTo(2.5, 1e-3));
      expect(three.hit.laps, 3);
      expect(three.peak.median, closeTo(1.0, 1e-6));
      final two = summarizeBrakingTechnique([('a', lap(0.5)), ('b', lap(0.4))]);
      expect(two.hit.median, isNull);
      expect(two.hit.reason, brakingTechniqueTooFewLaps);
      expect(two.unavailableReason, brakingTechniqueTooFewLaps);
    });

    test('never pool a G channel with speed, or g with m/s²', () {
      final speed = _measure(_speedOnly(_braking()));
      final mixed = summarizeBrakingTechnique([
        ('a', lap(0.5)),
        ('b', lap(0.5, unit: 'm/s²')),
        ('c', lap(0.5)),
        ('d', speed),
        ('e', lap(0.5)),
      ]);
      expect(mixed.source, brakingTechniqueFromG);
      expect(mixed.declaredUnit, 'g');
      expect(mixed.otherSourceLaps, 2);
      expect(mixed.hit.laps, 3);
    });

    test('no braking on most laps says so', () {
      final none = _measure(_session(deceleration: _braking(peak: 0.2)));
      final result = summarizeBrakingTechnique([
        ('a', none),
        ('b', none),
        ('c', none),
        ('d', lap(0.5)),
      ]);
      expect(result.unavailableReason, brakingTechniqueNoBraking);
      expect(result.lapsMeasured, 4);
      expect(result.lapsBraking, 1);
    });

    test('a missing value says why from the braking laps', () {
      final result = summarizeBrakingTechnique([
        for (final key in ['a', 'b', 'c']) (key, lap(0.5)),
      ]);
      expect(result.trailSeconds.median, isNull);
      expect(result.trailSeconds.reason, brakingTechniqueNoLateral);
      expect(result.lap('b'), isNotNull);
      expect(result.lap('z'), isNull);
    });

    test('the day pools corners of one source', () {
      final corner = summarizeBrakingTechnique([
        for (final key in ['a', 'b', 'c']) (key, lap(0.5)),
      ]);
      final day = summarizeBrakingTechniqueDay([corner, corner, const BrakingTechnique()]);
      expect(day.corners, 3);
      expect(day.cornersBraked, 2);
      expect(day.hit, closeTo(2.0, 1e-3));
      expect(day.hitCorners, 2);
      expect(day.available, isTrue);
      expect(summarizeBrakingTechniqueDay(const []).available, isFalse);
    });
  });
}
