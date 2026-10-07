// Property tests for source fusion (FET-216): on seeded random pairs of
// recordings (different rates, clock offsets and drift, losses with and
// without RCZ gap markers, missing values) fused channels keep strictly
// increasing timestamps, fillGaps keeps every finite primary sample,
// preferAlternative every finite alternative sample, the other source's
// samples appear only outside the preferred source's coverage, every fused
// value is a real recorded sample, nothing reads across a declared gap, and
// the order of alternatives whose channel keys are disjoint, and of the
// channels, does not change the result. With two alternatives that share a
// ruled key the result does depend on their order; FET-208 fixes that and is
// not merged here, so that case is not asserted.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/src/telemetry_session.dart' show lowerBound, upperBound;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'generators.dart';

const _seed = 216201;
const _cases = 160;

double _signal(double time, double phase) =>
    100.0 + 30.0 * math.sin(time / 7.0) + 10.0 * math.sin(time / 1.3 + phase);

/// One channel's samples on its own recording's clock.
typedef _Track = ({List<double> times, List<double> values});

/// Samples of [signal] every 1/[rate] s from [start] to [end] (primary
/// time [toPrimary] of the recording's clock), with losses (no samples,
/// sometimes RCZ gap markers just inside) and runs of missing values.
_Track _track(
  math.Random random, {
  required double start,
  required double end,
  required double rate,
  required double Function(double primaryTime) signal,
  required double Function(double ownTime) toPrimary,
}) {
  final step = 1.0 / rate;
  final losses = [
    for (var index = 0, count = random.nextInt(4); index < count; ++index)
      () {
        final from = uniform(random, start, end);
        return (from, from + uniform(random, 0.2, 12.0));
      }(),
  ];
  final missing = [
    for (var index = 0, count = random.nextInt(4); index < count; ++index)
      () {
        final from = uniform(random, start, end);
        return (from, from + uniform(random, 0.0, 3.0));
      }(),
  ];
  final markers = random.nextBool();
  final jitter = random.nextDouble() < 0.3 ? 0.2 * step : 0.0;
  final times = <double>[], values = <double>[];
  void add(double time, double value) {
    if (times.isNotEmpty && time <= times.last) return;
    times.add(time);
    values.add(value);
  }

  for (var index = 0; start + index * step <= end; ++index) {
    final time = start + index * step + jitter * (random.nextDouble() - 0.5);
    final lost = losses.where((loss) => time > loss.$1 && time < loss.$2);
    if (lost.isNotEmpty) continue;
    final value = missing.any((gap) => time >= gap.$1 && time <= gap.$2)
        ? double.nan
        : signal(toPrimary(time));
    add(time, value);
    // An RCZ recording marks a loss with a NaN just inside each end.
    final next = time + step;
    if (markers && losses.any((loss) => time <= loss.$1 && next > loss.$1)) {
      final loss = losses.firstWhere((loss) => time <= loss.$1 && next > loss.$1);
      if (loss.$2 - time > 3.0 * step) {
        add(time + 1e-6, double.nan);
        add(loss.$2 - 1e-6, double.nan);
      }
    }
  }
  return (times: times, values: values);
}

TelemetryChannel _channel(String name, String unit, _Track track) => TelemetryChannel(
  name: name,
  unit: unit,
  timestamps: Float64List.fromList(track.times),
  values: Float32List.fromList(track.values),
);

TelemetrySession _session(Map<String, TelemetryChannel> channels, Map<String, String> aliases) {
  var last = 0.0;
  for (final channel in channels.values) {
    if (channel.sampleCount > 0) last = math.max(last, channel.timestamps.last);
  }
  return TelemetrySession(
    duration: last,
    startTime: 0,
    metadata: const {},
    channels: channels,
    aliases: aliases,
    warnings: const [],
    timingGates: const [],
    sampleCount: channels.values.first.sampleCount,
  );
}

/// [channels] in a random order: fusion must not depend on map order.
Map<String, TelemetryChannel> _shuffled(
  math.Random random,
  Map<String, TelemetryChannel> channels,
) {
  final keys = channels.keys.toList()..shuffle(random);
  return {for (final key in keys) key: channels[key]!};
}

const _rates = [1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0];

/// A random fusion case: a primary with "velocity" (alias speed, km/h) and
/// "brake"; an alternative with "velocity" on its own clock and "rpm".
final class _FusionCase {
  _FusionCase(math.Random random, this.label) {
    final duration = uniform(random, 40.0, 120.0);
    final phase = uniform(random, 0.0, 2 * math.pi);
    // A quarter of the clocks are whole seconds apart without drift, so the
    // two recordings sample at the same instants and tie.
    final tied = random.nextDouble() < 0.25;
    clock = tied
        ? SourceClock(offsetSeconds: (random.nextInt(41) - 20).toDouble())
        : SourceClock(
            offsetSeconds: uniform(random, -30.0, 30.0),
            driftPpm: random.nextDouble() < 0.3 ? 0.0 : uniform(random, -300.0, 300.0),
          );
    final scale = 1.0 + clock.driftPpm * 1e-6;
    double alternativeToPrimary(double time) =>
        time + clock.offsetSeconds + clock.driftPpm * 1e-6 * time;
    double primaryToAlternative(double time) => (time - clock.offsetSeconds) / scale;
    final bias = random.nextDouble() < 0.7
        ? uniform(random, -0.5, 0.5)
        : uniform(random, -20.0, 20.0);
    primaryRate = _rates[random.nextInt(_rates.length)];
    alternativeRate = _rates[random.nextInt(_rates.length)];
    primarySpeed = _track(
      random,
      start: 0.0,
      end: duration,
      rate: primaryRate,
      signal: (time) => _signal(time, phase),
      toPrimary: (time) => time,
    );
    final from = tied
        ? random.nextInt(duration ~/ 2 + 20) - 20.0
        : uniform(random, -20.0, duration / 2);
    final to = uniform(random, duration / 2, duration + 20.0);
    alternativeSpeed = _track(
      random,
      start: primaryToAlternative(from),
      end: primaryToAlternative(to),
      rate: alternativeRate,
      signal: (time) => _signal(time, phase) + bias,
      toPrimary: alternativeToPrimary,
    );
    final brake = _track(
      random,
      start: 0.0,
      end: duration,
      rate: primaryRate,
      signal: (time) => math.max(0.0, 50.0 * math.sin(time / 3.0)),
      toPrimary: (time) => time,
    );
    final rpm = _track(
      random,
      start: primaryToAlternative(from),
      end: primaryToAlternative(to),
      rate: alternativeRate,
      signal: (time) => 4000.0 + 1500.0 * math.sin(time / 5.0),
      toPrimary: alternativeToPrimary,
    );
    primary = _session(
      _shuffled(random, {
        'velocity': _channel('velocity', 'km/h', primarySpeed),
        'brake': _channel('brake', '%', brake),
      }),
      const {'speed': 'velocity', 'brake': 'brake'},
    );
    alternative = _session(
      _shuffled(random, {
        'velocity': _channel('velocity', 'km/h', alternativeSpeed),
        'rpm-obd': _channel('rpm-obd', 'rpm', rpm),
      }),
      const {'speed': 'velocity'},
    );
    rule = const [
      null,
      FusionRule.fillGaps,
      FusionRule.preferAlternative,
      FusionRule.primaryOnly,
    ][random.nextInt(4)];
    description =
        '$label: rates $primaryRate/$alternativeRate Hz, offset '
        '${clock.offsetSeconds.toStringAsFixed(2)} s, drift ${clock.driftPpm.toStringAsFixed(1)} ppm, '
        'bias ${bias.toStringAsFixed(2)}, rule $rule';
  }

  final String label;
  late final String description;
  late final SourceClock clock;
  late final double primaryRate, alternativeRate;
  late final _Track primarySpeed, alternativeSpeed;
  late final TelemetrySession primary, alternative;
  late final FusionRule? rule;

  FusionPolicy get policy =>
      FusionPolicy(rules: {if (rule != null) 'speed': (sourceId: 'alt', rule: rule!)});

  /// The alternative's speed samples on the primary clock, as fusion maps
  /// them.
  List<double> get alternativeTimes => [
    for (final time in alternativeSpeed.times)
      time + clock.offsetSeconds + clock.driftPpm * 1e-6 * time,
  ];

  ChannelFusionResult fuse() => fuseChannels(primary, 'primary', [
    FusionSource(sourceId: 'alt', session: alternative, clock: clock, alignmentStatus: 'aligned'),
  ], policy: policy);
}

void _expectStrictlyIncreasing(TelemetryChannel channel, String reason) {
  expect(channel.timestamps.length, channel.values.length, reason: reason);
  for (var index = 0; index < channel.sampleCount; ++index) {
    final time = channel.timestamps[index];
    expect(time.isFinite, isTrue, reason: '$reason sample $index');
    if (index > 0) {
      expect(time, greaterThan(channel.timestamps[index - 1]), reason: '$reason sample $index');
    }
  }
}

/// Whether [time] is inside data of the source with [times], [values]: on a
/// finite sample, or between two consecutive finite samples no more than
/// [gap] apart (fusion's coverage, `_finiteSpans`).
bool _covered(List<double> times, List<double> values, double gap, double time) {
  final next = lowerBound(times, time);
  if (next < times.length && times[next] == time) return values[next].isFinite;
  if (next == 0 || next == times.length) return false;
  final before = next - 1;
  return values[before].isFinite && values[next].isFinite && times[next] - times[before] <= gap;
}

void main() {
  test('fused timestamps strictly increase and fused values are recorded samples', () {
    final random = math.Random(_seed);
    final rules = <String, int>{};
    for (var index = 0; index < _cases; ++index) {
      final c = _FusionCase(random, 'seed $_seed case $index');
      final result = c.fuse();
      for (final fused in result.channels) {
        _expectStrictlyIncreasing(fused.channel, '${c.description} ${fused.name}');
        for (var i = 1; i < fused.segments.length; ++i) {
          expect(fused.segments[i].start, greaterThanOrEqualTo(fused.segments[i - 1].start));
        }
        for (final segment in fused.segments) {
          expect(segment.end, greaterThanOrEqualTo(segment.start), reason: c.description);
        }
      }
      final session = fusedSession(c.primary, result);
      for (final channel in session.channels.values) {
        _expectStrictlyIncreasing(channel, '${c.description} session ${channel.name}');
      }
      final speed = result.channels.firstWhere((fused) => fused.key == 'speed');
      rules.update(speed.rule, (count) => count + 1, ifAbsent: () => 1);
      // Every finite fused value is a sample one of the recordings made, at
      // its own time on the primary clock: nothing is resampled or invented.
      final recorded = <double, Set<double>>{};
      void record(List<double> times, List<double> values) {
        for (var i = 0; i < times.length; ++i) {
          if (values[i].isFinite) {
            recorded.putIfAbsent(times[i], () => {}).add(Float32List.fromList([values[i]])[0]);
          }
        }
      }

      record(c.primarySpeed.times, c.primarySpeed.values);
      record(c.alternativeTimes, c.alternativeSpeed.values);
      final channel = speed.channel;
      for (var i = 0; i < channel.sampleCount; ++i) {
        final double value = channel.values[i];
        if (!value.isFinite) continue;
        expect(
          recorded[channel.timestamps[i]]?.contains(value),
          isTrue,
          reason: '${c.description} fused sample $i at ${channel.timestamps[i]}',
        );
      }
    }
    // Every merge rule was exercised.
    expect(rules.keys, containsAll(['fillGaps', 'preferAlternative', 'primary']));
  });

  test('fillGaps never removes a finite primary sample, preferAlternative an alternative one', () {
    final random = math.Random(_seed + 1);
    var merged = 0;
    for (var index = 0; index < _cases; ++index) {
      final c = _FusionCase(random, 'seed ${_seed + 1} case $index');
      final speed = c.fuse().channels.firstWhere((fused) => fused.key == 'speed');
      if (speed.rule != 'fillGaps' && speed.rule != 'preferAlternative') continue;
      ++merged;
      final preferredTimes = speed.rule == 'fillGaps' ? c.primarySpeed.times : c.alternativeTimes;
      final preferredValues = speed.rule == 'fillGaps'
          ? c.primarySpeed.values
          : c.alternativeSpeed.values;
      final channel = speed.channel;
      for (var i = 0; i < preferredTimes.length; ++i) {
        final value = Float32List.fromList([preferredValues[i]])[0];
        if (!value.isFinite) continue;
        final at = lowerBound(channel.timestamps, preferredTimes[i]);
        expect(
          at < channel.sampleCount && channel.timestamps[at] == preferredTimes[i],
          isTrue,
          reason: '${c.description}: preferred sample $i at ${preferredTimes[i]} is gone',
        );
        expect(channel.values[at], value, reason: '${c.description}: sample $i changed');
      }
    }
    expect(merged, greaterThan(_cases ~/ 4));
  });

  test('fillGaps and preferAlternative add the other source only outside the preferred '
      'source\'s coverage', () {
    final random = math.Random(_seed + 4);
    var merged = 0, added = 0;
    for (var index = 0; index < _cases; ++index) {
      final c = _FusionCase(random, 'seed ${_seed + 4} case $index');
      final speed = c.fuse().channels.firstWhere((fused) => fused.key == 'speed');
      if (speed.rule != 'fillGaps' && speed.rule != 'preferAlternative') continue;
      ++merged;
      final fillGaps = speed.rule == 'fillGaps';
      final preferredTimes = fillGaps ? c.primarySpeed.times : c.alternativeTimes;
      final preferredValues = fillGaps ? c.primarySpeed.values : c.alternativeSpeed.values;
      // The preferred source's coverage: its runs of finite samples, a step
      // longer than its gap threshold ending a run (`_finiteSpans`).
      final preferredGap = fillGaps
          ? telemetryGapThreshold(c.primary.channel('speed')!)
          : telemetryGapThreshold(c.alternative.channel('speed')!) *
                (1.0 + c.clock.driftPpm * 1e-6);
      final preferredAt = preferredTimes.toSet();
      final channel = speed.channel;
      for (var i = 0; i < channel.sampleCount; ++i) {
        final time = channel.timestamps[i];
        if (!channel.values[i].isFinite || preferredAt.contains(time)) continue;
        // A sample the preferred source did not record: the other source's.
        expect(
          _covered(preferredTimes, preferredValues, preferredGap, time),
          isFalse,
          reason:
              '${c.description}: the other source\'s sample at $time is inside the '
              'preferred source\'s coverage',
        );
        ++added;
      }
    }
    expect(merged, greaterThan(_cases ~/ 4));
    expect(added, greaterThan(100));
  });

  test('no fused reading bridges a declared gap', () {
    final random = math.Random(_seed + 2);
    var checkedPairs = 0, readings = 0;
    for (var index = 0; index < _cases; ++index) {
      final c = _FusionCase(random, 'seed ${_seed + 2} case $index');
      final speed = c.fuse().channels.firstWhere((fused) => fused.key == 'speed');
      if (speed.rule != 'fillGaps' && speed.rule != 'preferAlternative') continue;
      final primaryChannel = c.primary.channel('speed')!;
      final alternativeChannel = c.alternative.channel('speed')!;
      final primaryGap = telemetryGapThreshold(primaryChannel);
      final alternativeGap =
          telemetryGapThreshold(alternativeChannel) * (1.0 + c.clock.driftPpm * 1e-6);
      final widest = math.max(primaryGap, alternativeGap);
      final primaryTimes = c.primarySpeed.times, primaryValues = c.primarySpeed.values;
      final alternativeTimes = c.alternativeTimes, alternativeValues = c.alternativeSpeed.values;
      final channel = speed.channel;
      final times = channel.timestamps, values = channel.values;
      // Two neighbouring finite samples are what any reading joins or holds
      // across. They are never farther apart than the wider gap threshold,
      // and no missing value either recording declared lies between them
      // unless the other recording has data there.
      for (var i = 1; i < channel.sampleCount; ++i) {
        if (!values[i - 1].isFinite || !values[i].isFinite) continue;
        final from = times[i - 1], to = times[i];
        final reason = '${c.description}: fused samples at $from and $to';
        expect(to - from, lessThanOrEqualTo(widest * (1 + 1e-12)), reason: reason);
        void checkMissing(
          List<double> ownTimes,
          List<double> ownValues,
          List<double> otherTimes,
          List<double> otherValues,
          double otherGap,
          String own,
        ) {
          for (var k = upperBound(ownTimes, from); k < ownTimes.length && ownTimes[k] < to; ++k) {
            if (ownValues[k].isFinite) continue;
            expect(
              _covered(otherTimes, otherValues, otherGap, ownTimes[k]),
              isTrue,
              reason: '$reason bridge the $own recording\'s missing value at ${ownTimes[k]}',
            );
          }
        }

        checkMissing(
          primaryTimes,
          primaryValues,
          alternativeTimes,
          alternativeValues,
          alternativeGap,
          'primary',
        );
        checkMissing(
          alternativeTimes,
          alternativeValues,
          primaryTimes,
          primaryValues,
          primaryGap,
          'alternative',
        );
        ++checkedPairs;
      }
      // Readings: where neither recording has a finite sample within the
      // wider gap threshold on both sides, a linear reading has no value;
      // a held (previous) or nearest reading only ever returns a sample
      // recorded within that threshold of the time read.
      final finite = <double>[
        for (var i = 0; i < primaryTimes.length; ++i)
          if (primaryValues[i].isFinite) primaryTimes[i],
        for (var i = 0; i < alternativeTimes.length; ++i)
          if (alternativeValues[i].isFinite) alternativeTimes[i],
      ]..sort();
      for (var probe = 0; probe < 400; ++probe) {
        final time = uniform(random, times.first - 1.0, times.last + 1.0);
        final next = lowerBound(finite, time);
        final before = next > 0 ? finite[next - 1] : double.negativeInfinity;
        final after = next < finite.length ? finite[next] : double.infinity;
        if (before == time || after == time) continue;
        final reason = '${c.description}: reading at $time between data at $before and $after';
        if (after - before > widest) {
          expect(telemetryValueAt(channel, time), isNull, reason: 'linear $reason');
          ++readings;
        }
        if (telemetryValueAt(channel, time, InterpolationMode.previous) != null) {
          expect(time - before, lessThanOrEqualTo(widest), reason: 'previous $reason');
          ++readings;
        }
        if (telemetryValueAt(channel, time, InterpolationMode.nearest) != null) {
          expect(
            math.min(time - before, after - time),
            lessThanOrEqualTo(widest),
            reason: 'nearest $reason',
          );
          ++readings;
        }
      }
    }
    expect(checkedPairs, greaterThan(10000));
    expect(readings, greaterThan(1000));
  });

  // Only alternatives with disjoint channel keys: for two that share a ruled
  // key fuseChannels depends on their order, which FET-208 fixes (not merged
  // here). Then the property holds by construction, so it guards the
  // channel and alias bookkeeping rather than the merge.
  test('the order of alternatives with disjoint channel keys, and of channels, does not '
      'change the fusion', () {
    final random = math.Random(_seed + 3);
    for (var index = 0; index < _cases ~/ 3; ++index) {
      final c = _FusionCase(random, 'seed ${_seed + 3} case $index');
      // A second alternative with channels of its own, on another clock.
      final secondClock = SourceClock(offsetSeconds: uniform(random, -5.0, 5.0));
      final heart = _track(
        random,
        start: 0.0,
        end: c.primary.duration,
        rate: 1.0,
        signal: (time) => 120.0 + 20.0 * math.sin(time / 30.0),
        toPrimary: (time) => time + secondClock.offsetSeconds,
      );
      final temperature = _track(
        random,
        start: 0.0,
        end: c.primary.duration,
        rate: 0.5,
        signal: (time) => 80.0 + time / 100.0,
        toPrimary: (time) => time + secondClock.offsetSeconds,
      );
      TelemetrySession second() => _session(
        _shuffled(random, {
          'hr': _channel('hr', 'bpm', heart),
          'oil': _channel('oil', 'C', temperature),
        }),
        const {'heartRate': 'hr'},
      );
      FusionSource first() => FusionSource(
        sourceId: 'alt',
        session: _session(_shuffled(random, {...c.alternative.channels}), c.alternative.aliases),
        clock: c.clock,
        alignmentStatus: 'aligned',
      );
      FusionSource other() => FusionSource(
        sourceId: 'second',
        session: second(),
        clock: secondClock,
        alignmentStatus: 'aligned',
      );
      final primaryAgain = _session(_shuffled(random, {...c.primary.channels}), c.primary.aliases);
      final forward = fuseChannels(c.primary, 'primary', [first(), other()], policy: c.policy);
      final backward = fuseChannels(primaryAgain, 'primary', [other(), first()], policy: c.policy);
      final a = fusedSession(c.primary, forward), b = fusedSession(primaryAgain, backward);
      expect(a.channels.keys.toSet(), b.channels.keys.toSet(), reason: c.description);
      expect(a.aliases, b.aliases, reason: c.description);
      expect(a.metadata, b.metadata, reason: c.description);
      for (final name in a.channels.keys) {
        final left = a.channels[name]!, right = b.channels[name]!;
        expect(left.unit, right.unit, reason: '${c.description} $name');
        expect(left.timestamps, right.timestamps, reason: '${c.description} $name');
        expect(
          [for (final v in left.values) v.isNaN ? 'NaN' : v],
          [for (final v in right.values) v.isNaN ? 'NaN' : v],
          reason: '${c.description} $name',
        );
      }
      String describe(FusedChannel fused) =>
          '${fused.key} ${fused.rule} ${fused.comparedSourceId} ${fused.conflicting} '
          '${[for (final s in fused.segments) '${s.sourceId} ${s.start} ${s.end}']}';
      expect(
        {for (final fused in forward.channels) describe(fused)},
        {for (final fused in backward.channels) describe(fused)},
        reason: c.description,
      );
      expect(forward.unresolved.toSet(), backward.unresolved.toSet(), reason: c.description);
      expect(forward.unitMismatches.toSet(), backward.unitMismatches.toSet());
    }
  });
}
