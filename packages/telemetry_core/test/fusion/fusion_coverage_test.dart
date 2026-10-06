// Truth tests for fusion coverage (FET-200): a source covers a time only
// where it has a finite value, whatever its timestamps say.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

double _speed(double t) => 100.0 + 30.0 * math.sin(t / 7.0);

/// A session with one "speed" channel in km/h sampled every [step] seconds
/// from [start] to [end]; [missing] times have a NaN value.
TelemetrySession _speedSession(
  double start,
  double end,
  double step, {
  bool Function(double time, int index) missing = _none,
  double bias = 0.0,
}) {
  final times = <double>[];
  final values = <double>[];
  for (var index = 0; start + index * step <= end + 1e-9; ++index) {
    final time = start + index * step;
    times.add(time);
    values.add(missing(time, index) ? double.nan : _speed(time) + bias);
  }
  return TelemetrySession(
    duration: end - start,
    startTime: 0,
    metadata: const {},
    channels: {
      'velocity': TelemetryChannel(
        name: 'velocity',
        unit: 'km/h',
        timestamps: Float64List.fromList(times),
        values: Float32List.fromList(values),
      ),
    },
    aliases: const {'speed': 'velocity'},
    warnings: const [],
    timingGates: const [],
    sampleCount: times.length,
  );
}

bool _none(double time, int index) => false;

/// A "speed" session from explicit [times] and [values], as an RCZ with
/// gap markers (NaN just inside a loss of signal) arrives.
TelemetrySession _rawSession(List<double> times, List<double> values) => TelemetrySession(
  duration: times.last - times.first,
  startTime: 0,
  metadata: const {},
  channels: {
    'velocity': TelemetryChannel(
      name: 'velocity',
      unit: 'km/h',
      timestamps: Float64List.fromList(times),
      values: Float32List.fromList(values),
    ),
  },
  aliases: const {'speed': 'velocity'},
  warnings: const [],
  timingGates: const [],
  sampleCount: times.length,
);

/// A 10 Hz recording from [start] to [end] with no samples between
/// [lossStart] and [lossEnd] and RCZ gap markers just inside the loss.
TelemetrySession _withLoss(double start, double end, double lossStart, double lossEnd) {
  final times = <double>[], values = <double>[];
  for (var index = 0; start + index * 0.1 <= end + 1e-9; ++index) {
    final time = start + index * 0.1;
    if (time > lossStart + 1e-9 && time < lossEnd - 1e-9) continue;
    times.add(time);
    values.add(_speed(time) + 0.5);
    if ((time - lossStart).abs() < 1e-9) {
      times.add(time + 1e-6);
      values.add(double.nan);
      times.add(lossEnd - 1e-6);
      values.add(double.nan);
    }
  }
  return _rawSession(times, values);
}

/// Whether a reading of [fused] interpolates between two samples of one
/// source across that source's own missing value: two neighbouring output
/// samples that are both [source]'s finite samples with a NaN of [source]
/// between them.
bool _bridgesMissing(TelemetryChannel fused, TelemetryChannel source) {
  final finite = <double>{
    for (var index = 0; index < source.timestamps.length; ++index)
      if (source.values[index].isFinite) source.timestamps[index],
  };
  final missing = [
    for (var index = 0; index < source.timestamps.length; ++index)
      if (!source.values[index].isFinite) source.timestamps[index],
  ];
  for (var index = 1; index < fused.timestamps.length; ++index) {
    final before = fused.timestamps[index - 1], after = fused.timestamps[index];
    if (!fused.values[index - 1].isFinite || !fused.values[index].isFinite) continue;
    if (!finite.contains(before) || !finite.contains(after)) continue;
    if (missing.any((time) => time > before && time < after)) return true;
  }
  return false;
}

FusionPolicy _rule(FusionRule rule) =>
    FusionPolicy(rules: {'speed': (sourceId: 'rcz', rule: rule)});

TelemetryChannel _fuse(TelemetrySession primary, TelemetrySession alternative, FusionRule rule) {
  final result = fuseChannels(primary, 'vbo', [
    FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
  ], policy: _rule(rule));
  final speed = result.channels.firstWhere((channel) => channel.key == 'speed');
  expect(speed.rule, rule == FusionRule.fillGaps ? 'fillGaps' : 'preferAlternative');
  return speed.channel;
}

double? _valueAt(TelemetryChannel channel, double time) => telemetryValueAt(channel, time);

/// The invariants every fused channel keeps: strictly increasing times, and
/// with fillGaps every finite primary sample unchanged.
void _checkInvariants(TelemetryChannel fused, TelemetrySession primary, {required bool fill}) {
  final times = fused.timestamps;
  for (var index = 1; index < times.length; ++index) {
    expect(times[index], greaterThan(times[index - 1]), reason: 'time $index');
  }
  if (!fill) return;
  final source = primary.channels['velocity']!;
  final output = <double, double>{
    for (var index = 0; index < times.length; ++index) times[index]: fused.values[index],
  };
  for (var index = 0; index < source.timestamps.length; ++index) {
    final value = source.values[index];
    if (!value.isFinite) continue;
    expect(output[source.timestamps[index]], value, reason: 'primary sample $index kept');
  }
}

void main() {
  test('fillGaps fills where the primary has timestamps but NaN values', () {
    final primary = _speedSession(0, 100, 0.1, missing: (t, _) => t > 40.0 && t < 50.0);
    final alternative = _speedSession(0, 100, 0.2, bias: 0.5);
    final fused = _fuse(primary, alternative, FusionRule.fillGaps);
    _checkInvariants(fused, primary, fill: true);
    for (final time in [40.5, 42.3, 45.0, 49.5]) {
      final value = _valueAt(fused, time);
      expect(value, isNotNull, reason: 'value at $time');
      expect(value!, closeTo(_speed(time) + 0.5, 0.2));
    }
    // Outside the hole the primary's own values are read.
    expect(_valueAt(fused, 30.0), closeTo(_speed(30.0), 0.01));
  });

  test('fillGaps fills a primary with a NaN every third sample', () {
    final primary = _speedSession(0, 60, 0.1, missing: (_, index) => index % 3 == 2);
    final alternative = _speedSession(0, 60, 0.05, bias: 0.25);
    final fused = _fuse(primary, alternative, FusionRule.fillGaps);
    _checkInvariants(fused, primary, fill: true);
    final source = primary.channels['velocity']!;
    for (var index = 2; index < source.timestamps.length - 1; index += 3) {
      final time = source.timestamps[index];
      expect(_valueAt(fused, time), isNotNull, reason: 'value at $time');
    }
  });

  test('preferAlternative takes the primary where the alternative has NaN values', () {
    final primary = _speedSession(0, 100, 0.1);
    final alternative = _speedSession(
      0,
      100,
      0.2,
      missing: (t, _) => t > 30.0 && t < 33.0,
      bias: 0.5,
    );
    final fused = _fuse(primary, alternative, FusionRule.preferAlternative);
    _checkInvariants(fused, primary, fill: false);
    expect(_valueAt(fused, 31.5), closeTo(_speed(31.5), 0.05));
    expect(_valueAt(fused, 20.0), closeTo(_speed(20.0) + 0.5, 0.2));
  });

  test('where neither source has a value, there is still no value', () {
    final primary = _speedSession(0, 100, 0.1, missing: (t, _) => t > 40.0 && t < 50.0);
    final alternative = _speedSession(0, 100, 0.2, missing: (t, _) => t > 44.0 && t < 47.0);
    final fused = _fuse(primary, alternative, FusionRule.fillGaps);
    _checkInvariants(fused, primary, fill: true);
    expect(_valueAt(fused, 42.0), isNotNull);
    expect(_valueAt(fused, 45.5), isNull);
    expect(_valueAt(fused, 48.5), isNotNull);
  });

  test('invariant: fillGaps never removes a finite primary sample', () {
    final random = math.Random(200);
    for (var trial = 0; trial < 40; ++trial) {
      final primaryStep = [0.04, 0.1, 0.2, 1.0][random.nextInt(4)];
      final alternativeStep = [0.04, 0.1, 0.2, 1.0][random.nextInt(4)];
      final holes = [
        for (var hole = 0; hole < 4; ++hole)
          (random.nextDouble() * 80.0, 0.1 + random.nextDouble() * 8.0),
      ];
      bool inHole(double t, List<(double, double)> list) =>
          list.any((hole) => t >= hole.$1 && t < hole.$1 + hole.$2);
      final dropRate = random.nextDouble() * 0.3;
      final primary = _speedSession(
        0,
        90,
        primaryStep,
        missing: (t, _) => inHole(t, holes) || random.nextDouble() < dropRate,
      );
      final alternative = _speedSession(
        random.nextDouble() * 5.0,
        85,
        alternativeStep,
        missing: (t, _) => random.nextDouble() < dropRate,
        bias: 0.3,
      );
      final fused = _fuse(primary, alternative, FusionRule.fillGaps);
      _checkInvariants(fused, primary, fill: true);
    }
  });

  test('a coarser alternative with no sample in a short hole leaves the hole missing', () {
    // NaN at 10.1 s and 10.2 s; the 1 Hz alternative has nothing between
    // 10.0 s and 10.3 s, so nothing may read the primary across the hole.
    final primary = _speedSession(
      0,
      60,
      0.1,
      missing: (t, _) => (t - 10.1).abs() < 1e-6 || (t - 10.2).abs() < 1e-6,
    );
    final alternative = _speedSession(0, 60, 1.0, bias: 5.0);
    final fused = _fuse(primary, alternative, FusionRule.fillGaps);
    _checkInvariants(fused, primary, fill: true);
    expect(_valueAt(fused, 10.15), isNull);
    expect(_bridgesMissing(fused, primary.channels['velocity']!), isFalse);
  });

  test('an alternative spanning beyond both ends of the primary', () {
    final primary = _speedSession(10, 50, 0.1, missing: (t, _) => t > 20.0 && t < 25.0);
    final alternative = _speedSession(0, 60, 0.2, bias: 0.5);
    for (final rule in [FusionRule.fillGaps, FusionRule.preferAlternative]) {
      final fused = _fuse(primary, alternative, rule);
      _checkInvariants(fused, primary, fill: rule == FusionRule.fillGaps);
      expect(fused.timestamps.first, 0.0);
      expect(fused.timestamps.last, closeTo(60.0, 1e-9));
      expect(_valueAt(fused, 5.0), closeTo(_speed(5.0) + 0.5, 0.2));
      expect(_valueAt(fused, 22.0), closeTo(_speed(22.0) + 0.5, 0.2));
      expect(_valueAt(fused, 55.0), closeTo(_speed(55.0) + 0.5, 0.2));
    }
  });

  test('RCZ gap markers on the preferred side are dropped only where the other fills', () {
    // The alternative (preferred) loses signal from 20 s to 30 s.
    final alternative = _withLoss(0, 60, 20, 30);
    // A primary covering the loss fills it; markers go, values are read.
    final full = _fuse(_speedSession(0, 60, 0.1), alternative, FusionRule.preferAlternative);
    _checkInvariants(full, alternative, fill: false);
    expect(full.values.where((value) => value.isNaN), isEmpty);
    expect(_valueAt(full, 25.0), closeTo(_speed(25.0), 0.01));
    expect(_valueAt(full, 15.0), closeTo(_speed(15.0) + 0.5, 0.01));
    // A primary that loses signal from 18 s to 32 s too fills nothing: the
    // markers stay and the loss reads as missing.
    final lost = _fuse(
      _speedSession(0, 60, 0.1, missing: (t, _) => t > 18.0 && t < 32.0),
      alternative,
      FusionRule.preferAlternative,
    );
    _checkInvariants(lost, alternative, fill: false);
    for (final time in [20.5, 25.0, 29.5]) {
      expect(_valueAt(lost, time), isNull, reason: 'value at $time');
    }
    expect(_valueAt(lost, 15.0), closeTo(_speed(15.0) + 0.5, 0.01));
  });

  test('RCZ gap markers partly filled keep the uncovered part missing', () {
    final alternative = _withLoss(0, 60, 20, 30);
    final primary = _speedSession(0, 60, 0.1, missing: (t, _) => t > 24.0);
    final result = fuseChannels(primary, 'vbo', [
      FusionSource(sourceId: 'rcz', session: alternative, alignmentStatus: 'aligned'),
    ], policy: _rule(FusionRule.preferAlternative));
    final speed = result.channels.firstWhere((channel) => channel.key == 'speed');
    expect(_valueAt(speed.channel, 22.0), closeTo(_speed(22.0), 0.01));
    expect(_valueAt(speed.channel, 27.0), isNull);
    expect(_valueAt(speed.channel, 35.0), closeTo(_speed(35.0) + 0.5, 0.01));
    // Provenance: the primary's segment lies inside the loss.
    final fromPrimary = speed.segments.where((segment) => segment.sourceId == 'vbo').toList();
    expect(fromPrimary, isNotEmpty);
    for (final segment in fromPrimary) {
      expect(segment.start, greaterThanOrEqualTo(20.0 - 1e-6));
      expect(segment.end, lessThanOrEqualTo(30.0 + 1e-6));
    }
  });

  test('invariant: fusion never reads a source across its own missing value', () {
    final random = math.Random(2000);
    for (var trial = 0; trial < 60; ++trial) {
      final primaryStep = [0.04, 0.1, 0.2, 1.0][random.nextInt(4)];
      final alternativeStep = [0.05, 0.1, 0.3, 1.0][random.nextInt(4)];
      final dropRate = random.nextDouble() * 0.3;
      final primary = _speedSession(
        0,
        90,
        primaryStep,
        missing: (t, _) => random.nextDouble() < dropRate,
      );
      final alternative = _speedSession(
        random.nextDouble() * 10.0 - 5.0,
        80 + random.nextDouble() * 20.0,
        alternativeStep,
        missing: (t, _) => random.nextDouble() < dropRate,
        bias: 0.3,
      );
      for (final rule in [FusionRule.fillGaps, FusionRule.preferAlternative]) {
        final fused = _fuse(primary, alternative, rule);
        final fill = rule == FusionRule.fillGaps;
        _checkInvariants(fused, primary, fill: fill);
        final preferred = (fill ? primary : alternative).channels['velocity']!;
        expect(_bridgesMissing(fused, preferred), isFalse, reason: 'trial $trial $rule');
      }
    }
  });
}
