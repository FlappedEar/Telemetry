// Port of Overlays native/tests/ChannelFusionTests.cpp (d4d1039): every
// output sample keeps its source, clock and rule; conflicts need a rule;
// units are never rescaled; gaps stay gaps; nothing is resampled.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

TelemetryChannel _channel(
  String name,
  String unit,
  double start,
  double end,
  double rate,
  double Function(double) value, [
  bool Function(double)? present,
]) {
  final times = <double>[], values = <double>[];
  for (var time = start; time <= end + 1e-9; time += 1.0 / rate) {
    if (present != null && !present(time)) continue;
    times.add(time);
    values.add(value(time));
  }
  return TelemetryChannel(
    name: name,
    unit: unit,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
}

TelemetrySession _session(List<(TelemetryChannel, String?)> channels) => TelemetrySession(
  duration: 0.0,
  startTime: 0.0,
  metadata: const {},
  channels: {for (final (channel, _) in channels) channel.name: channel},
  aliases: {for (final (channel, alias) in channels) ?alias: channel.name},
  warnings: const [],
  timingGates: const [],
  sampleCount: 0,
);

double _speedAt(double t) => 100.0 + 20.0 * math.sin(0.1 * t);

// The primary (a VBO): GPS speed, missing from 40 to 50 s.
TelemetrySession _primary({String speedUnit = 'km/h'}) => _session([
  (
    _channel('velocity', speedUnit, 0.0, 100.0, 10.0, _speedAt, (t) => t < 40.0 || t > 50.0),
    'speed',
  ),
  (_channel('latacc-calc', 'g', 0.0, 100.0, 10.0, math.sin), 'lateralAcceleration'),
]);

// The alternative (an RCZ) runs 5 s behind: primaryTime = altTime + 5.
TelemetrySession _alternative({double speedBias = 0.0, String speedUnit = 'km/h'}) => _session([
  (_channel('velocity', speedUnit, 0.0, 90.0, 5.0, (c) => _speedAt(c + 5.0) + speedBias), 'speed'),
  (_channel('coolant_temp-obd', 'C', 0.0, 95.0, 1.0, (c) => 90.0 + 0.01 * c), null),
  (
    _channel(
      'rpm-obd',
      'rpm',
      0.0,
      95.0,
      5.0,
      (c) => 4000.0 + 1000.0 * math.sin(0.3 * c),
      (c) => c < 60.0 || c > 70.0,
    ),
    'rpm',
  ),
]);

List<FusionSource> _rcz(
  TelemetrySession? session, {
  SourceClock clock = const SourceClock(offsetSeconds: 5.0),
  String status = 'aligned',
}) => [FusionSource(sourceId: 'rcz', session: session, clock: clock, alignmentStatus: status)];

FusedChannel? _find(ChannelFusionResult result, String key) {
  for (final channel in result.channels) {
    if (channel.key == key) return channel;
  }
  return null;
}

bool _strictlyIncreasing(List<double> times) {
  for (var index = 1; index < times.length; ++index) {
    if (!(times[index] > times[index - 1])) return false;
  }
  return true;
}

FusionPolicy _rule(String key, String source, FusionRule rule) =>
    FusionPolicy(rules: {key: (sourceId: source, rule: rule)});

void main() {
  test('adds alternative-only channels on the primary clock', () {
    final primary = _primary();
    final alternative = _alternative();
    final result = fuseChannels(primary, 'vbo', _rcz(alternative));
    final coolant = _find(result, 'coolant_temp-obd')!;
    expect(coolant.rule, 'added');
    expect(coolant.unit, 'C');
    expect(coolant.channel.timestamps.first, 5.0); // alternative 0 s is primary 5 s
    expect(
      coolant.channel.timestamps.length,
      alternative.channels['coolant_temp-obd']!.timestamps.length,
    ); // not resampled
    expect(coolant.segments, hasLength(1));
    expect(coolant.segments.first.sourceId, 'rcz');
    expect(coolant.segments.first.clock.offsetSeconds, 5.0);
    expect(coolant.segments.first.sampleIntervalSeconds, 1.0); // its own resolution
    // A gap in the alternative stays a gap: two segments.
    final rpm = _find(result, 'rpm')!;
    expect(rpm.rule, 'added');
    expect(rpm.segments, hasLength(2));
    expect(rpm.segments[0].end, lessThan(65.0 + 1e-9));
    expect(rpm.segments[1].start, greaterThan(75.0 - 1e-9));
    // The primary's own channels are untouched.
    final lateral = _find(result, 'lateralAcceleration')!;
    expect(lateral.rule, 'primary');
    expect(lateral.segments.first.sourceId, 'vbo');
    expect(result.unresolved, isEmpty);
    expect(result.refusedSources, isEmpty);
  });

  test('keeps the primary when measurements agree', () {
    final primary = _primary();
    final result = fuseChannels(primary, 'vbo', _rcz(_alternative(speedBias: 0.5)));
    final speed = _find(result, 'speed')!;
    expect(speed.rule, 'primary');
    expect(speed.comparedSourceId, 'rcz');
    expect(speed.comparedSamples, greaterThan(100));
    expect((speed.medianDifference - 0.5).abs(), lessThan(0.1));
    expect(speed.conflicting, isFalse);
    // Not overwritten: the primary's samples and its gap are exactly as recorded.
    expect(speed.channel.timestamps, primary.channels['velocity']!.timestamps);
    expect(speed.segments, hasLength(2));
    expect(result.unresolved, isEmpty);
  });

  test('reports conflicts without a rule', () {
    final primary = _primary();
    final alternative = _alternative(speedBias: 8.0); // the RCZ reads 8 km/h high
    final result = fuseChannels(primary, 'vbo', _rcz(alternative));
    final speed = _find(result, 'speed')!;
    expect(speed.conflicting, isTrue);
    expect(speed.rule, 'unresolvedConflict');
    expect(result.unresolved, ['speed']);
    expect(speed.channel.timestamps, primary.channels['velocity']!.timestamps);
    // Choosing the primary explicitly resolves it.
    final chosen = fuseChannels(
      primary,
      'vbo',
      _rcz(alternative),
      policy: _rule('speed', 'rcz', FusionRule.primaryOnly),
    );
    expect(_find(chosen, 'speed')!.rule, 'primary');
    expect(_find(chosen, 'speed')!.conflicting, isTrue); // still reported
    expect(chosen.unresolved, isEmpty);
    // A rule for another source does not apply to this one.
    final other = fuseChannels(
      primary,
      'vbo',
      _rcz(alternative),
      policy: _rule('speed', 'another', FusionRule.fillGaps),
    );
    expect(other.unresolved, ['speed']);
  });

  test('fills primary gaps only when chosen', () {
    final primary = _primary();
    final result = fuseChannels(
      primary,
      'vbo',
      _rcz(_alternative()),
      policy: _rule('speed', 'rcz', FusionRule.fillGaps),
    );
    final speed = _find(result, 'speed')!;
    expect(speed.rule, 'fillGaps');
    expect(_strictlyIncreasing(speed.channel.timestamps), isTrue);
    // The primary everywhere it recorded; the alternative only inside its
    // gap (40-50 s).
    var fromAlternative = 0;
    for (final segment in speed.segments) {
      if (segment.sourceId == 'rcz') {
        ++fromAlternative;
        expect(segment.start, greaterThan(39.9));
        expect(segment.end, lessThan(50.1));
        expect(segment.sampleIntervalSeconds, closeTo(0.2, 1e-12)); // QCOMPARE is fuzzy
      } else {
        expect(segment.sourceId, 'vbo');
      }
    }
    expect(fromAlternative, 1);
    for (var index = 0; index < speed.channel.timestamps.length; ++index) {
      final t = speed.channel.timestamps[index];
      expect((speed.channel.values[index] - _speedAt(t)).abs(), lessThan(0.01));
    }
    // Gaps neither source covers stay gaps: the alternative starts at 5 s.
    expect(speed.channel.timestamps.first, 0.0);
  });

  test('prefers the alternative only when chosen', () {
    final result = fuseChannels(
      _primary(),
      'vbo',
      _rcz(_alternative()),
      policy: _rule('speed', 'rcz', FusionRule.preferAlternative),
    );
    final speed = _find(result, 'speed')!;
    expect(speed.rule, 'preferAlternative');
    expect(_strictlyIncreasing(speed.channel.timestamps), isTrue);
    // The alternative covers 5-95 s; the primary only outside it.
    for (final segment in speed.segments) {
      if (segment.sourceId == 'vbo') {
        expect(segment.end < 5.0 || segment.start > 95.0, isTrue);
      } else {
        expect(segment.start, greaterThanOrEqualTo(5.0 - 1e-9));
      }
    }
  });

  test('applies clock drift', () {
    // 1000 ppm: alternative 90 s is primary 90 + 5 + 0.09 s.
    final result = fuseChannels(
      _primary(),
      'vbo',
      _rcz(_alternative(), clock: const SourceClock(offsetSeconds: 5.0, driftPpm: 1000.0)),
    );
    final coolant = _find(result, 'coolant_temp-obd')!;
    expect((coolant.channel.timestamps[90] - 95.09).abs(), lessThan(1e-9));
    expect(_strictlyIncreasing(coolant.channel.timestamps), isTrue);
    expect(coolant.segments.first.clock.driftPpm, 1000.0);
  });

  test('refuses unaligned sources and unit mismatches', () {
    final primary = _primary();
    final alternative = _alternative();
    for (final status in ['ambiguous', 'conflicting', 'insufficient', '']) {
      final result = fuseChannels(primary, 'vbo', _rcz(alternative, status: status));
      expect(result.refusedSources, ['rcz']);
      expect(_find(result, 'coolant_temp-obd'), isNull);
    }
    expect(
      fuseChannels(
        primary,
        'vbo',
        _rcz(alternative, clock: const SourceClock(offsetSeconds: double.nan)),
      ).refusedSources,
      ['rcz'],
    );
    expect(
      fuseChannels(
        primary,
        'vbo',
        _rcz(alternative, clock: const SourceClock(offsetSeconds: 5.0, driftPpm: -2e6)),
      ).refusedSources,
      ['rcz'],
    );
    expect(fuseChannels(primary, 'vbo', _rcz(null)).refusedSources, ['rcz']);
    // Speed in m/s against km/h: not compared, not fused, never rescaled.
    final mismatch = fuseChannels(
      primary,
      'vbo',
      _rcz(_alternative(speedUnit: 'm/s')),
      policy: _rule('speed', 'rcz', FusionRule.fillGaps),
    );
    expect(mismatch.unitMismatches, ['speed: rcz']);
    expect(_find(mismatch, 'speed')!.rule, 'primary');
    expect(_find(mismatch, 'speed')!.channel.timestamps, primary.channels['velocity']!.timestamps);
    // Tolerances by unit.
    expect(fusionConflictTolerance('km/h', 50.0), 2.0);
    expect(fusionConflictTolerance('g', 2.0), 0.05);
    expect(fusionConflictTolerance('bar', 2.0), 0.1);
    expect(fusionConflictTolerance('\u00b0C', 50.0), 2.0); // KAN-184
    expect(fusionConflictTolerance(' degC ', 50.0), 2.0);
  });

  test('compares a channel with an undeclared unit (KAN-184)', () {
    // VBO channels declare no unit, RCZ channels do.
    final primary = _primary(speedUnit: '');
    // Agreeing values: the same unit, compared with km/h's tolerance and fusable.
    final agreeing = _alternative(speedBias: 1.5);
    var result = fuseChannels(primary, 'vbo', _rcz(agreeing));
    expect(result.unitMismatches, isEmpty);
    expect(_find(result, 'speed')!.comparedSourceId, 'rcz');
    expect(_find(result, 'speed')!.conflicting, isFalse);
    final policy = _rule('speed', 'rcz', FusionRule.fillGaps);
    result = fuseChannels(primary, 'vbo', _rcz(agreeing), policy: policy);
    expect(_find(result, 'speed')!.rule, 'fillGaps');
    expect(_find(result, 'speed')!.unit, ''); // the primary's unit is kept
    // Disagreeing values may be another scale: a mismatch, never fused, even with a rule.
    result = fuseChannels(primary, 'vbo', _rcz(_alternative(speedBias: 8.0)), policy: policy);
    expect(result.unitMismatches, ['speed: rcz']);
    expect(_find(result, 'speed')!.rule, 'primary');
    expect(_find(result, 'speed')!.comparedSourceId, '');
    expect(_find(result, 'speed')!.channel.timestamps, primary.channels['velocity']!.timestamps);
    // Fewer than 10 overlapping samples cannot show the units agree.
    final brief = fuseChannels(
      primary,
      'vbo',
      _rcz(agreeing, clock: const SourceClock(offsetSeconds: 98.5)),
      policy: policy,
    );
    expect(brief.unitMismatches, ['speed: rcz']);
    // The undeclared side may be the alternative.
    result = fuseChannels(_primary(), 'vbo', _rcz(_alternative(speedBias: 1.5, speedUnit: '')));
    expect(result.unitMismatches, isEmpty);
    expect(_find(result, 'speed')!.comparedSourceId, 'rcz');
  });

  test(
    'an added VBO acceleration and temperature keep the units their header declares (FET-288)',
    () {
      final vbo = TelemetrySession(
        duration: 0.0,
        startTime: 0.0,
        metadata: const {'header.3': 'longacc-calc m/s2', 'header.4': 'oil-obd deg F'},
        channels: {
          'longacc-calc': _channel('longacc-calc', '', 0.0, 90.0, 5.0, (c) => 1.0),
          'oil-obd': _channel('oil-obd', '', 0.0, 90.0, 5.0, (c) => 194.0),
        },
        aliases: const {},
        warnings: const [],
        timingGates: const [],
        sampleCount: 0,
      );
      final result = fuseChannels(_primary(), 'rcz', _rcz(vbo));
      expect(_find(result, 'longacc-calc')!.channel.unit, 'm/s2');
      expect(_find(result, 'oil-obd')!.channel.unit, 'deg F');
      expect(_find(result, 'oil-obd')!.channel.values, vbo.channels['oil-obd']!.values);
    },
  );

  test('an added VBO speed keeps the unit its header declares (FET-112)', () {
    // The primary (an RCZ) has no second speed; the VBO's `velocity-calc`
    // declares mph only on its `[header]` line.
    final vbo = TelemetrySession(
      duration: 0.0,
      startTime: 0.0,
      metadata: const {'header.3': 'velocity-calc mph', 'header.4': 'velocity kmh'},
      channels: {
        'velocity-calc': _channel('velocity-calc', '', 0.0, 90.0, 5.0, _speedAt),
        'rpm-obd': _channel('rpm-obd', '', 0.0, 90.0, 5.0, (c) => 4000.0),
      },
      aliases: const {},
      warnings: const [],
      timingGates: const [],
      sampleCount: 0,
    );
    final result = fuseChannels(_primary(), 'rcz', _rcz(vbo));
    final speed = _find(result, 'velocity-calc')!;
    expect(speed.rule, 'added');
    expect(speed.unit, 'mph');
    expect(speed.channel.unit, 'mph');
    // The values are never rescaled.
    expect(speed.channel.values, vbo.channels['velocity-calc']!.values);
    // Analysis of the fused session reads it in mph, whatever is assumed.
    final fused = withEffectiveSpeedUnits(fusedSession(_primary(), result), assumed: 'km/h');
    expect(fused.channels['velocity-calc']!.unit, 'mph');
    // A speed found only through its `speed` alias, declared `kmh`.
    final aliased = TelemetrySession(
      duration: 0.0,
      startTime: 0.0,
      metadata: const {'header.2': 'gps_speed kmh'},
      channels: {'gps_speed': _channel('gps_speed', '', 0.0, 90.0, 5.0, _speedAt)},
      aliases: const {'speed': 'gps_speed'},
      warnings: const [],
      timingGates: const [],
      sampleCount: 0,
    );
    final rczWithoutSpeed = _session([
      (_channel('latacc-calc', 'g', 0.0, 100.0, 10.0, math.sin), 'lateralAcceleration'),
    ]);
    final byAlias = fuseChannels(rczWithoutSpeed, 'rcz', _rcz(aliased));
    expect(_find(byAlias, 'speed')!.rule, 'added');
    expect(_find(byAlias, 'speed')!.unit, 'km/h');
    // A channel that is not a speed keeps its own (missing) unit.
    expect(_find(result, 'rpm-obd')!.unit, '');
    // A speed with no unit declared anywhere stays without one.
    final bare = fuseChannels(
      _primary(),
      'rcz',
      _rcz(
        TelemetrySession(
          duration: 0.0,
          startTime: 0.0,
          metadata: const {},
          channels: {'velocity-calc': _channel('velocity-calc', '', 0.0, 90.0, 5.0, _speedAt)},
          aliases: const {},
          warnings: const [],
          timingGates: const [],
          sampleCount: 0,
        ),
      ),
    );
    expect(_find(bare, 'velocity-calc')!.unit, '');
  });

  test('the fused session carries the merged and added channels', () {
    final primary = _primary();
    final result = fuseChannels(
      primary,
      'vbo',
      _rcz(_alternative()),
      policy: _rule('speed', 'rcz', FusionRule.fillGaps),
    );
    final session = fusedSession(primary, result);
    expect(session.metadata['fusedChannels'], 'coolant_temp-obd,rpm-obd,velocity');
    expect(session.aliases['rpm'], 'rpm-obd');
    expect(
      session.channel('speed')!.timestamps.length,
      greaterThan(primary.channel('speed')!.timestamps.length),
    );
    expect(session.channels['latacc-calc'], same(primary.channels['latacc-calc']));
  });

  test('cancels', () {
    expect(
      () => fuseChannels(_primary(), 'vbo', _rcz(_alternative()), cancelled: () => true),
      throwsA(isA<OperationCancelled>()),
    );
  });
}
