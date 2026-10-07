// Seeded generators of synthetic recordings for the property tests
// (FET-216). Every case comes from a dart:math Random with a fixed seed, so a
// failure names the seed and case that reproduce it. No real data: the
// circuits are the test helpers' circle and rounded rectangle.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';

import '../support/circuits.dart';

/// A normally distributed value (Box-Muller) with mean 0 and [sigma].
double gaussian(math.Random random, double sigma) {
  if (sigma == 0.0) return 0.0;
  final u = 1.0 - random.nextDouble();
  final v = random.nextDouble();
  return sigma * math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v);
}

double uniform(math.Random random, double low, double high) =>
    low + (high - low) * random.nextDouble();

/// One generated lap recording and what is known to be true about it.
final class LapCase {
  LapCase({
    required this.label,
    required this.session,
    required this.laps,
    required this.clean,
    required this.expectedLapSeconds,
    this.stepErrorSeconds = const [],
    required this.noiseMeters,
    required this.slowestSpeed,
    this.firstPassMayBeMissed = false,
  });

  /// Seed, case and the knobs that made it, for failure messages.
  final String label;
  final TelemetrySession session;

  /// Laps timed gate to gate.
  final int laps;

  /// No dropout, invalid fix or timing jitter: every pass is recorded.
  final bool clean;

  /// The true lap times, when the circuit gives them exactly (constant
  /// speed per lap on the circle); null otherwise.
  final List<double>? expectedLapSeconds;

  /// How far each true lap time can be from the recording itself: the
  /// circle helper drives its 10 Hz step that crosses into a new lap at the
  /// old lap's speed, which moves the position by up to 0.1 s at the old
  /// speed.
  final List<double> stepErrorSeconds;
  final double noiseMeters;
  final double slowestSpeed;

  /// The recording starts so close to the gate that its first segment may
  /// already be inside the detector's outer corridor (10 m): a pass is only
  /// armed once the path has been outside it, so the first crossing may not
  /// count.
  final bool firstPassMayBeMissed;

  @override
  String toString() => label;
}

const double _metersPerDegree = 6371000.0 * math.pi / 180.0;

/// A lap recording: the circle or the rounded rectangle of
/// `support/circuits.dart`, two to five laps driven at 12–45 m/s (constant or
/// varying within the lap), resampled at 4–25 Hz, with GPS error up to
/// 1.5 m and, unless [clean], timing jitter, dropouts and invalid fixes.
/// Half the recordings that are not clean also stop or crawl (at 1–6% of
/// the speed, about 0.1–2.7 m/s) one to three times for 3–30 s, while the
/// GPS error keeps wandering: the fixes of a car standing still.
LapCase generateLapCase(math.Random random, String label, {bool? clean}) {
  final isClean = clean ?? random.nextDouble() < 0.4;
  final driven = 2 + random.nextInt(4);
  final circle = random.nextBool();
  final speeds = [for (var lap = 0; lap < driven; ++lap) uniform(random, 12.0, 45.0)];
  final TelemetrySession base;
  List<double>? expected;
  var stepError = <double>[];
  var laps = driven;
  var describe = '';
  // How far before the gate the recording starts.
  var leadMeters = 20.0;
  if (circle) {
    final radius = uniform(random, 60.0, 180.0);
    final clockwise = random.nextBool();
    base = circuitSession(radius: radius, speeds: speeds, clockwise: clockwise);
    double arc(double angle, int lap) => angle * radius / speeds[math.min(lap, driven - 1)];
    leadMeters = clockwise ? double.infinity : 0.25 * radius;
    if (clockwise) {
      // Clockwise, the circle starts 0.25 rad past the gate, so the first
      // pass ends the first lap's 2π − 0.25 rad: one lap fewer is timed,
      // each driven 0.25 rad at one lap's speed and the rest at the next's.
      laps = driven - 1;
      expected = [
        for (var lap = 0; lap < laps; ++lap) arc(0.25, lap) + arc(2 * math.pi - 0.25, lap + 1),
      ];
    } else {
      // Counter-clockwise it starts 0.25 rad before the gate; each lap's
      // last 0.25 rad is driven at the next lap's speed (the last lap keeps
      // its own).
      expected = [
        for (var lap = 0; lap < laps; ++lap) arc(2 * math.pi - 0.25, lap) + arc(0.25, lap + 1),
      ];
    }
    // Either way timed lap k contains the step into driven lap k + 1.
    stepError = [for (var lap = 0; lap < laps; ++lap) _stepError(speeds, lap + 1)];
    describe = 'circle r=${radius.toStringAsFixed(1)} cw=$clockwise';
  } else {
    final amplitudes = [for (var lap = 0; lap < driven; ++lap) uniform(random, 0.0, 0.3)];
    final phases = [for (var lap = 0; lap < driven; ++lap) uniform(random, 0.0, 2 * math.pi)];
    base = rectangleSession([
      for (var lap = 0; lap < driven; ++lap)
        (double distance) =>
            speeds[lap] * (1.0 + amplitudes[lap] * math.sin(distance / 60.0 + phases[lap])),
    ]);
    describe = 'rectangle';
  }
  final rate = const [4.0, 5.0, 10.0, 20.0, 25.0][random.nextInt(5)];
  final noise = random.nextDouble() < 0.3 ? 0.0 : uniform(random, 0.0, 1.5);
  // Independent noise per fix only on the rough recordings: at 25 Hz even
  // 5 cm per fix is a velocity error of 2 m/s.
  final white = isClean ? 0.0 : uniform(random, 0.0, 0.05);
  final jitter = isClean ? 0.0 : uniform(random, 0.0, 0.2);
  final dropouts = isClean ? 0 : random.nextInt(4);
  final invalidFixes = isClean ? 0 : random.nextInt(6);
  final baseEnd = base.channel('latitude')!.timestamps.last;
  final stops = isClean || random.nextBool()
      ? const <(double, double, double)>[]
      : [
          for (var stop = 0, count = 1 + random.nextInt(3); stop < count; ++stop)
            (
              uniform(random, 0.0, baseEnd),
              uniform(random, 3.0, 30.0),
              random.nextBool() ? 0.0 : uniform(random, 0.01, 0.06),
            ),
        ];
  final session = resampleGps(
    random,
    base,
    rate: rate,
    noiseMeters: noise,
    whiteMeters: white,
    jitterFraction: jitter,
    dropouts: dropouts,
    invalidFixes: invalidFixes,
    stops: stops,
  );
  final slowest = circle
      ? speeds.reduce(math.min)
      : speeds.reduce(math.min) * (1.0 - 0.3); // the largest amplitude
  return LapCase(
    label:
        '$label: $describe laps=$laps speeds=${[for (final s in speeds) s.toStringAsFixed(1)]} '
        'rate=$rate noise=${noise.toStringAsFixed(2)} white=${white.toStringAsFixed(2)} jitter=${jitter.toStringAsFixed(2)} '
        'dropouts=$dropouts invalid=$invalidFixes'
        '${stops.isEmpty ? '' : ' stops=${[for (final (at, seconds, share) in stops) '${at.toStringAsFixed(1)}+${seconds.toStringAsFixed(1)}s@${share.toStringAsFixed(2)}']}'}',
    session: session,
    laps: laps,
    clean: isClean,
    expectedLapSeconds: isClean ? expected : null,
    stepErrorSeconds: stepError,
    noiseMeters: noise + white,
    slowestSpeed: slowest,
    firstPassMayBeMissed:
        leadMeters - 1.3 * speeds.first / rate < 10.0 + 3.0 * (noise + white) + 1.0,
  );
}

/// The time the circle helper's step into lap [next] can move the lap
/// containing that step by: the part of the step past the boundary is
/// driven at the old speed instead of the new one.
double _stepError(List<double> speeds, int next) {
  if (next <= 0 || next >= speeds.length) return 0.0;
  return 0.1 * (speeds[next - 1] / speeds[next] - 1.0).abs();
}

/// [base] (a 10 Hz recording) read at [rate] Hz by straight-line
/// interpolation between its fixes, each time moved by up to
/// [jitterFraction] of the interval, with GPS error per axis: a smoothly
/// drifting offset of [noiseMeters] RMS plus [whiteMeters] of independent
/// noise per fix, [dropouts] stretches of 0.5–8 s with no fix and
/// [invalidFixes] single fixes whose latitude is NaN. Each of [stops]
/// (base time, seconds, share of the speed) holds the car at [base]'s
/// position from that time for that many seconds, moving on at that share
/// of its speed (0: standing still); the recording is that much longer, and
/// the GPS error goes on drifting meanwhile. The speed channel is read at
/// the same times, scaled during a stop. Gates and aliases are kept.
TelemetrySession resampleGps(
  math.Random random,
  TelemetrySession base, {
  required double rate,
  double noiseMeters = 0.0,
  double whiteMeters = 0.0,
  double jitterFraction = 0.0,
  int dropouts = 0,
  int invalidFixes = 0,
  List<(double, double, double)> stops = const [],
}) {
  final latitude = base.channel('latitude')!;
  final longitude = base.channel('longitude')!;
  final speed = base.channel('speed');
  final baseTimes = latitude.timestamps;
  // The stops in base time order, each starting after the last one ends,
  // with the recording time each starts at.
  final held = <(double, double, double, double)>[];
  var delay = 0.0;
  for (final (at, seconds, share) in [...stops]..sort((a, b) => a.$1.compareTo(b.$1))) {
    if (held.isNotEmpty && at <= held.last.$1 + held.last.$2 * held.last.$3) continue;
    held.add((at, seconds, share, at + delay));
    delay += seconds * (1.0 - share);
  }
  // The base time shown at recording time [time], and the share of the
  // base speed then.
  (double, double) baseAt(double time) {
    var offset = 0.0;
    for (final (at, seconds, share, starts) in held) {
      if (time < starts) break;
      if (time < starts + seconds) return (at + share * (time - starts), share);
      offset += seconds * (1.0 - share);
    }
    return (time - offset, 1.0);
  }

  final end = baseTimes.last + delay;
  final step = 1.0 / rate;
  final holes = [
    for (var index = 0; index < dropouts; ++index)
      () {
        final start = uniform(random, 0.0, end);
        return (start, start + uniform(random, 0.5, 8.0));
      }(),
  ];
  final times = <double>[];
  for (var index = 0; index * step <= end; ++index) {
    final time = math.min(end, index * step + jitterFraction * step * (random.nextDouble() - 0.5));
    if (times.isNotEmpty && time <= times.last) continue;
    if (holes.any((hole) => time > hole.$1 && time < hole.$2)) continue;
    times.add(time);
  }
  double interpolate(TelemetryChannel channel, double time) {
    final value = telemetryValueAt(channel, time);
    if (value != null) return value;
    // The last sample, or between two samples on a turn of the clock.
    return telemetryValueAt(channel, time, InterpolationMode.nearest) ?? double.nan;
  }

  final cosLatitude = math.cos(latitude.values.first * math.pi / 180.0);
  final latitudes = Float32List(times.length);
  final longitudes = Float32List(times.length);
  final speeds = Float32List(times.length);
  final latitudeValues = Float64List(times.length);
  final longitudeValues = Float64List(times.length);
  // Each axis's slow error: three sine waves with periods of 8–60 s and
  // random phases, scaled to [noiseMeters] RMS. A receiver's position error
  // drifts smoothly like this; its velocity error stays under 1 m/s.
  List<(double, double, double)> waves() => [
    for (var wave = 0; wave < 3; ++wave)
      (
        noiseMeters * math.sqrt(2.0 / 3.0),
        2.0 * math.pi / uniform(random, 8.0, 60.0),
        uniform(random, 0.0, 2.0 * math.pi),
      ),
  ];
  double drift(List<(double, double, double)> waves, double time) {
    var sum = 0.0;
    for (final (amplitude, frequency, phase) in waves) {
      sum += amplitude * math.sin(frequency * time + phase);
    }
    return sum;
  }

  final northWaves = waves(), eastWaves = waves();
  for (var index = 0; index < times.length; ++index) {
    final time = times[index];
    final north = drift(northWaves, time), east = drift(eastWaves, time);
    final (baseTime, share) = baseAt(time);
    latitudeValues[index] =
        interpolate(latitude, baseTime) +
        (north + gaussian(random, whiteMeters)) / _metersPerDegree;
    longitudeValues[index] =
        interpolate(longitude, baseTime) +
        (east + gaussian(random, whiteMeters)) / (_metersPerDegree * cosLatitude);
    speeds[index] = speed == null ? double.nan : share * interpolate(speed, baseTime);
  }
  for (var count = 0; count < invalidFixes && times.isNotEmpty; ++count) {
    latitudeValues[random.nextInt(times.length)] = double.nan;
  }
  // Float32 keeps about 0.5 m at these coordinates; the parser stores
  // coordinates the same way, so the generated noise floor is realistic.
  for (var index = 0; index < times.length; ++index) {
    latitudes[index] = latitudeValues[index];
    longitudes[index] = longitudeValues[index];
  }
  final timestamps = Float64List.fromList(times);
  TelemetryChannel channel(String name, String unit, Float32List values) =>
      TelemetryChannel(name: name, unit: unit, timestamps: timestamps, values: values);
  return TelemetrySession(
    duration: times.last,
    startTime: 0,
    metadata: base.metadata,
    channels: {
      'latitude': channel('latitude', '', latitudes),
      'longitude': channel('longitude', '', longitudes),
      if (speed != null) 'velocity': channel('velocity', speed.unit, speeds),
    },
    aliases: {
      'latitude': 'latitude',
      'longitude': 'longitude',
      if (speed != null) 'speed': 'velocity',
    },
    warnings: const [],
    timingGates: base.timingGates,
    sampleCount: times.length,
  );
}

/// [session] without its samples in one to four random stretches of
/// 0.3–6 s, and a description of them.
({TelemetrySession session, String description}) withDropouts(
  math.Random random,
  TelemetrySession session,
) {
  final end = session.duration;
  final holes = [
    for (var index = 0, count = 1 + random.nextInt(4); index < count; ++index)
      () {
        final start = uniform(random, 0.0, end);
        return (start, start + uniform(random, 0.3, 6.0));
      }(),
  ];
  bool kept(double time) => !holes.any((hole) => time > hole.$1 && time < hole.$2);
  final channels = <String, TelemetryChannel>{};
  for (final entry in session.channels.entries) {
    final channel = entry.value;
    final times = <double>[], values = <double>[];
    for (var index = 0; index < channel.sampleCount; ++index) {
      if (!kept(channel.timestamps[index])) continue;
      times.add(channel.timestamps[index]);
      values.add(channel.values[index]);
    }
    channels[entry.key] = TelemetryChannel(
      name: channel.name,
      unit: channel.unit,
      timestamps: Float64List.fromList(times),
      values: Float32List.fromList(values),
    );
  }
  return (
    session: TelemetrySession(
      duration: session.duration,
      startTime: session.startTime,
      metadata: session.metadata,
      channels: channels,
      aliases: session.aliases,
      warnings: session.warnings,
      timingGates: session.timingGates,
      sampleCount: channels.values.first.sampleCount,
    ),
    description:
        'dropouts ${[for (final h in holes) '${h.$1.toStringAsFixed(2)}-${h.$2.toStringAsFixed(2)}']}',
  );
}
