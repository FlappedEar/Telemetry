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

/// A deceleration drawn with straight lines through [points] (seconds after
/// [start], g), 0 before the first and after the last.
double Function(double) _pieces(List<(double, double)> points, {double start = 10.0}) => (t) {
  final x = t - start;
  if (x <= points.first.$1 || x >= points.last.$1) return 0.0;
  for (var i = 1; i < points.length; ++i) {
    final (x0, y0) = points[i - 1];
    final (x1, y1) = points[i];
    if (x <= x1) return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
  }
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
  String lateralUnit = 'g',
  String throttleUnit = '%',
  TelemetryChannel? brake,
  Map<String, String> metadata = const {},
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
    if (lateral != null)
      'latacc': _channel('latacc', lateral, unit: lateralUnit, step: lateralStep),
    if (throttle != null) 'throttle': _channel('throttle', throttle, unit: throttleUnit),
  };
  if (brake != null) channels[brake.name] = brake;
  return TelemetrySession(
    duration: 30,
    startTime: 0,
    metadata: metadata,
    channels: channels,
    aliases: {
      'longitudinalAcceleration': 'longacc',
      if (speed) 'speed': 'velocity',
      if (lateral != null) 'lateralAcceleration': 'latacc',
      if (throttle != null) 'throttle': 'throttle',
      if (brake != null) 'brake': brake.name,
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
  String name = 'brake',
}) {
  double value(double t) {
    final k = ((t - phase) / period).floor();
    final t0 = phase + k * period, t1 = t0 + period;
    if (held) return pedal(t0);
    return pedal(t0) + (pedal(t1) - pedal(t0)) * (t - t0) / period;
  }

  return _channel(name, value, unit: '%', step: step);
}

/// [signal] updated every [period] s from [phase] and drawn with straight
/// lines at 10 Hz, written with three decimals (as a VBO writes it).
TelemetryChannel _lines(double Function(double) signal, double period, double phase) {
  double value(double t) {
    final k = ((t - phase) / period).floor();
    final t0 = phase + k * period, t1 = t0 + period;
    final y = signal(t0) + (signal(t1) - signal(t0)) * (t - t0) / period;
    return (y * 1000).roundToDouble() / 1000;
  }

  return _channel('x', value, to: 120);
}

// A G-like signal that never holds still.
double _gLike(double t) => 0.6 * math.sin(t * 0.9) + 0.3 * math.sin(t * 2.3);

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
      // By time, always.
      expect(
        lap.peakFraction,
        closeTo((lap.peakTime! - lap.onsetTime!) / (lap.endTime! - lap.onsetTime!), 1e-9),
      );
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

    test('a coast or light lift before braking is not part of the hit', () {
      // Lifting off to [lift] g for a second, then a 0.3 s rise to 1 g (and
      // back down the same way): the hit and release start from a quarter
      // of the peak, so a lift below it does not slow them.
      double Function(double) braking(double lift) => (t) {
        if (t < 9) return 0;
        if (t < 10) return lift;
        final x = t - 10;
        if (x < 0.3) return lift + (1 - lift) * x / 0.3;
        if (x < 1.3) return 1;
        if (x < 1.6) return 1 - (1 - lift) * (x - 1.3) / 0.3;
        if (x < 2.6) return lift;
        return 0;
      };
      for (final lift in [0.0, 0.16, 0.2, 0.24]) {
        final lap = _measure(_session(deceleration: braking(lift), gStep: 0.01));
        final slope = (1 - lift) / 0.3;
        expect(lap.hitGPerSecond, closeTo(slope, slope * 0.02), reason: 'lift $lift');
        expect(lap.releaseGPerSecond, closeTo(slope, slope * 0.02), reason: 'lift $lift');
      }
      // A lift above a quarter of the peak but below 0.30 g is part of the
      // ramp: the hit starts where the lift does.
      final above = _measure(_session(deceleration: braking(0.26), gStep: 0.01));
      expect(above.hitGPerSecond, lessThan(1.0));
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

  group('brake to throttle', () {
    // Two brakings in one segment: at 10 s and again at 14 s.
    double twice(double t) => _braking()(t) + _braking(start: 14)(t);

    test('stops at the next braking when the throttle comes after it', () {
      final lap = _measure(
        _session(deceleration: twice, throttle: (t) => t < 17.0 ? 0.0 : 50.0),
        to: 18,
      );
      expect(lap.brakeToThrottleSeconds, isNull);
      expect(lap.brakeToThrottleReason, brakingTechniqueBrakingAgain);
    });

    test('a pickup between the two brakings is timed', () {
      final lap = _measure(
        _session(deceleration: twice, throttle: (t) => t < 13.0 || t > 13.8 ? 0.0 : 50.0),
        to: 18,
      );
      expect(lap.brakeToThrottleSeconds, closeTo(13.0 - lap.endTime!, 0.11));
    });

    test('a throttle without a declared unit is read as % and says so', () {
      final lap = _measure(_session(throttle: (t) => t < 13.0 ? 0.0 : 50.0, throttleUnit: ''));
      expect(lap.brakeToThrottleSeconds, isNotNull);
      expect(lap.throttleUnitAssumed, isTrue);
      expect(lap.throttleCoarse, isFalse);
    });
  });

  group('a lift between two pushes on the pedal', () {
    // A first push to 0.45 g, a lift to 0.28 g (above the ramp floor of a
    // quarter of the peak), then the real hit to 0.65 g in 0.4 s.
    final lift = _pieces([(0, 0), (1, 0.45), (1.4, 0.28), (1.8, 0.65), (2.8, 0.65), (3.8, 0.0)]);
    final liftedFall = _pieces([
      (0, 0),
      (0.4, 0.65),
      (1.4, 0.65),
      (1.8, 0.28),
      (2.4, 0.45),
      (3.4, 0.0),
    ]);

    test('the hit starts at the lift, not before the first push', () {
      final lap = _measure(_session(deceleration: lift, gStep: 0.02));
      // (0.85 x 0.65 - 0.28) over the time from the dip: about 0.925 g/s.
      expect(lap.hitGPerSecond, closeTo(0.925, 0.1));
    });

    test('the release ends at the lift after the fall', () {
      final lap = _measure(_session(deceleration: liftedFall, gStep: 0.02));
      // From 0.85 x 0.65 down to the dip at 0.28 g over about 0.3 s.
      expect(lap.releaseGPerSecond, closeTo(0.925, 0.12));
    });

    test('a shallow wobble in the rise does not cut the hit short', () {
      final wobble = _pieces([(0, 0), (0.5, 0.25), (0.6, 0.23), (1.0, 0.65), (2.0, 0.65), (3, 0)]);
      final plain = _pieces([(0, 0), (0.5, 0.25), (1.0, 0.65), (2.0, 0.65), (3, 0)]);
      final a = _measure(_session(deceleration: wobble, gStep: 0.02));
      final b = _measure(_session(deceleration: plain, gStep: 0.02));
      expect(a.hitGPerSecond, closeTo(b.hitGPerSecond!, 0.15 * b.hitGPerSecond!));
    });
  });

  group('the speed unit', () {
    // The same driving in km/h as a speed channel with the unit written
    // elsewhere: a VBO header line, or nothing at all.
    TelemetrySession speedIn(String unit, {Map<String, String> metadata = const {}}) {
      final kmh = _speed(_braking());
      final factor = unit == 'mph' ? 1.609344 : 1.0;
      return TelemetrySession(
        duration: 30,
        startTime: 0,
        metadata: metadata,
        channels: {
          'velocity': TelemetryChannel(
            name: 'velocity',
            unit: '',
            timestamps: kmh.timestamps,
            values: Float32List.fromList([for (final v in kmh.values) v / factor]),
          ),
        },
        aliases: const {'speed': 'velocity'},
        warnings: const [],
        timingGates: const [],
        sampleCount: 751,
      );
    }

    final reference = _measure(_speedOnly(_braking()));

    test('a header-only "velocity mph" gives the label and the scale together', () {
      final lap = _measure(speedIn('mph', metadata: const {'header.0': 'velocity mph'}));
      expect(lap.declaredUnit, 'mph');
      expect(lap.unitAssumed, isFalse);
      expect(lap.peakG, closeTo(reference.peakG!, 0.01));
      expect(lap.zoneMeters, closeTo(reference.zoneMeters!, 0.5));
    });

    test('an undeclared speed is assumed in the unit the user set, whatever it is', () {
      final undeclared = speedIn('mph');
      final mph = _measure(withEffectiveSpeedUnits(undeclared, assumed: 'mph'));
      expect(mph.unitAssumed, isTrue);
      expect(mph.declaredUnit, isEmpty);
      expect(mph.assumedUnit, 'mph');
      expect(mph.peakG, closeTo(reference.peakG!, 0.01));
      expect(mph.zoneMeters, closeTo(reference.zoneMeters!, 0.5));
      final none = _measure(speedIn('km/h'));
      expect(none.unitAssumed, isTrue);
      expect(none.assumedUnit, 'km/h');
      expect(none.peakG, closeTo(reference.peakG!, 0.01));
    });

    test('a declared unit is never overridden by the setting', () {
      final declared = speedIn('mph', metadata: const {'header.0': 'velocity mph'});
      final lap = _measure(withEffectiveSpeedUnits(declared, assumed: 'km/h'));
      expect(lap.declaredUnit, 'mph');
      expect(lap.unitAssumed, isFalse);
      expect(lap.assumedUnit, isEmpty);
      expect(lap.peakG, closeTo(reference.peakG!, 0.01));
      // An RCZ speed carries its own unit: the setting does not touch it.
      final rcz = _measure(withEffectiveSpeedUnits(_speedOnly(_braking()), assumed: 'mph'));
      expect(rcz.declaredUnit, 'km/h');
      expect(rcz.unitAssumed, isFalse);
    });
  });

  group('hit and release from speed', () {
    // The speed's slope is smoothed over ±0.25 s: a ramp quicker than that
    // reads as fast as the smoothing allows, so it is only a lower bound.
    test('a quick ramp from speed reads "at least"', () {
      final quick = _measure(_speedOnly(_braking(rise: 0.15, fall: 0.3)));
      expect(quick.hitAtLeast, isTrue);
      expect(quick.releaseAtLeast, isTrue);
      final slow = _measure(_speedOnly(_braking(rise: 1.0, fall: 1.5)));
      expect(slow.hitAtLeast, isFalse);
      expect(slow.releaseAtLeast, isFalse);
      // From G, never.
      final g = _measure(_session(deceleration: _braking(rise: 0.15, fall: 0.3), gStep: 0.01));
      expect(g.hitAtLeast, isFalse);
      final typical = summarizeBrakingTechnique([
        ('a', quick),
        ('b', _measure(_speedOnly(_braking(rise: 1.0, fall: 1.5)))),
        ('c', slow),
      ]);
      expect(typical.hit.atLeast, isTrue);
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

    test('an OBD column of a VBO is never read for a ramp, whatever its rate', () {
      final lap = _measure(_session(brake: _channel('brake_pos-obd', _smoothPedal, unit: '%')));
      expect(lap.brakeRateHz, closeTo(10, 0.01));
      expect(lap.pedalReason, brakingTechniqueBrakeResampled);
      expect(lap.pedalApplicationPerSecond, isNull);
    });

    test('a pedal without a declared unit is read as % and says so', () {
      final lap = _measure(_session(brake: _channel('brake', _smoothPedal)));
      expect(lap.pedalApplicationPerSecond, isNotNull);
      expect(lap.brakeUnitAssumed, isTrue);
    });

    test('a 10 Hz pedal gives its application and release', () {
      final lap = _measure(_session(brake: _channel('brake', _smoothPedal, unit: '%')));
      expect(lap.brakeRateHz, closeTo(10, 0.01));
      expect(lap.pedalReason, isEmpty);
      // From a quarter of the peak (20 %) to 85 % of 80 %, on
      // 80 sin²(πx/3): symmetric, so the same rate both ways.
      double at(double level) => 3 / math.pi * math.asin(math.sqrt(level / 80));
      final expected = (0.85 * 80 - 20) / (at(0.85 * 80) - at(20));
      expect(lap.pedalApplicationPerSecond, isNotNull);
      expect(lap.pedalApplicationPerSecond, closeTo(expected, expected * 0.03));
      expect(lap.pedalReleasePerSecond, closeTo(expected, expected * 0.03));
    });
  });

  group('channel update rates', () {
    test('lines drawn between updates every 0.15 to 0.35 s are slow, whatever their phase', () {
      for (final period in [0.15, 0.2, 0.25, 0.3, 0.35]) {
        for (final phase in [0.0, 0.03, 0.05, 0.13]) {
          final rate = channelUpdateRateHz(_lines(_smoothPedal, period, phase))!;
          expect(rate, lessThan(brakingTechniqueMinimumRateHz), reason: '$period s at $phase s');
          expect(rate, closeTo(1 / period, 0.25 / period), reason: '$period s at $phase s');
        }
      }
    });

    test('a smooth G updated twice a second and drawn with lines is 2 Hz', () {
      for (final phase in [0.0, 0.03, 0.05, 0.13]) {
        expect(channelUpdateRateHz(_lines(_gLike, 0.5, phase)), closeTo(2, 0.15));
      }
    });

    test('a 2 Hz pedal with noise added at 10 Hz is still 2 Hz', () {
      final random = math.Random(4);
      final noisy = _lines(_smoothPedal, 0.48, 0.13);
      final values = Float32List.fromList([
        for (final v in noisy.values) v + (random.nextDouble() - 0.5) * 0.2,
      ]);
      final channel = TelemetryChannel(name: 'x', timestamps: noisy.timestamps, values: values);
      expect(channelUpdateRateHz(channel), closeTo(2.08, 0.15));
    });

    test('a smooth G recorded at 10 Hz is 10 Hz', () {
      final random = math.Random(5);
      final g = _channel(
        'g',
        (t) => ((_gLike(t) + (random.nextDouble() - 0.5) * 0.004) * 1000).roundToDouble() / 1000,
        to: 120,
      );
      expect(channelUpdateRateHz(g), closeTo(10, 0.01));
    });

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

    test('a 10 Hz pedal pressed and let off over a few samples is 10 Hz', () {
      // Each edge bends at three or four samples in a row (as a pedal that
      // follows the deceleration does): corners a sample apart are the
      // pedal's own rate, not lines between slower updates.
      const press = [5.2, 52.8, 92.7];
      const off = [29.7, 9.3];
      final values = <double>[];
      for (var brake = 0; brake < 8; ++brake) {
        values.addAll(List.filled(20, 0.0));
        values.addAll(press);
        for (var level = 90.2; level > 41.4; level *= 0.973) {
          values.add((level * 10).roundToDouble() / 10);
        }
        values.addAll(off);
      }
      values.addAll(List.filled(20, 0.0));
      final channel = _channel(
        'brake',
        (t) => values[(t * 10).round()],
        unit: '%',
        to: (values.length - 1) / 10,
      );
      expect(channelUpdateRateHz(channel), closeTo(10, 0.01));
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

    test('a unit declared in the VBO header counts as declared', () {
      final lap = _measure(
        _session(
          gUnit: '',
          lateral: (t) => t < 11.0 ? 0.0 : 0.5,
          lateralUnit: '',
          metadata: const {'header.3': 'longacc g', 'header.4': 'latacc g'},
        ),
      );
      expect(lap.declaredUnit, 'g');
      expect(lap.unitAssumed, isFalse);
      expect(lap.lateralUnitAssumed, isFalse);
      final undeclared = _measure(
        _session(gUnit: '', lateral: (t) => t < 11.0 ? 0.0 : 0.5, lateralUnit: ''),
      );
      expect(undeclared.unitAssumed, isTrue);
      expect(undeclared.lateralUnitAssumed, isTrue);
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

    test('a typical resting on a few braking laps says so, and why', () {
      // Two brakings in one segment: the first one's throttle never comes
      // before the second braking.
      double twice(double t) => _braking()(t) + _braking(start: 14)(t);
      BrakingTechniqueLap kept() => _measure(_session(throttle: (t) => t < 13.0 ? 0.0 : 50.0));
      BrakingTechniqueLap dropped() =>
          _measure(_session(deceleration: twice, throttle: (t) => t < 17.0 ? 0.0 : 50.0), to: 18);
      final few = summarizeBrakingTechnique([
        for (var i = 0; i < 5; ++i) (i, kept()),
        for (var i = 5; i < 16; ++i) (i, dropped()),
      ]);
      expect(few.lapsBraking, 16);
      expect(few.brakeToThrottle.median, isNotNull);
      expect(few.brakeToThrottle.laps, 5);
      expect(few.brakeToThrottle.brakingLaps, 16);
      expect(few.brakeToThrottle.droppedReason, brakingTechniqueBrakingAgain);
      expect(few.brakeToThrottle.partial, isTrue);
      expect(few.brakeToThrottle.minority, isTrue);
      // The figures every braking lap has are whole.
      expect(few.peak.laps, 16);
      expect(few.peak.partial, isFalse);
      expect(few.peak.droppedReason, isEmpty);

      // Three quarters of the laps are still shown with the count, not as a minority.
      final most = summarizeBrakingTechnique([
        for (var i = 0; i < 9; ++i) (i, kept()),
        for (var i = 9; i < 16; ++i) (i, dropped()),
      ]);
      expect(most.brakeToThrottle.partial, isTrue);
      expect(most.brakeToThrottle.minority, isFalse);
      final nearly = summarizeBrakingTechnique([
        for (var i = 0; i < 13; ++i) (i, kept()),
        for (var i = 13; i < 16; ++i) (i, dropped()),
      ]);
      expect(nearly.brakeToThrottle.partial, isFalse);

      // The day leaves a corner resting on a minority out, and counts it.
      final whole = summarizeBrakingTechnique([for (var i = 0; i < 5; ++i) (i, kept())]);
      final day = summarizeBrakingTechniqueDay([whole, whole, few]);
      expect(day.brakeToThrottleCorners, 2);
      expect(day.minorityCorners, 1);
      expect(day.brakeToThrottle, closeTo(whole.brakeToThrottle.median!, 1e-9));
      // Its other figures, kept on every lap, still count.
      expect(day.hitCorners, 3);
    });

    test('the day pools corners of one source', () {
      final corner = summarizeBrakingTechnique([
        for (final key in ['a', 'b', 'c']) (key, lap(0.5)),
      ]);
      final fromSpeed = summarizeBrakingTechnique([
        for (final key in ['a', 'b', 'c']) (key, _measure(_speedOnly(_braking()))),
      ]);
      expect(fromSpeed.unavailableReason, isEmpty);
      expect(fromSpeed.source, brakingTechniqueFromSpeed);
      final day = summarizeBrakingTechniqueDay([
        corner,
        corner,
        fromSpeed,
        const BrakingTechnique(),
      ]);
      expect(day.corners, 4);
      expect(day.cornersBraked, 2);
      expect(day.source, brakingTechniqueFromG);
      // The corner from speed is left out, and counted.
      expect(day.otherSourceCorners, 1);
      expect(day.hit, closeTo(2.0, 1e-3));
      expect(day.hitCorners, 2);
      expect(day.available, isTrue);
      expect(day.unitAssumed, isFalse);
      expect(summarizeBrakingTechniqueDay(const []).available, isFalse);
    });
  });
}
