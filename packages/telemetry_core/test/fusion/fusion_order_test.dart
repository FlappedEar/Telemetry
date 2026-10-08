// FET-208: fusing several alternatives gives the same result whatever order
// they are listed in; only a policy rule gives one source priority.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

TelemetryChannel _channel(
  String name,
  String unit,
  double end,
  double rate,
  double Function(double) value, [
  bool Function(double)? present,
]) {
  final times = <double>[], values = <double>[];
  for (var time = 0.0; time <= end + 1e-9; time += 1.0 / rate) {
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
double _rpmAt(double t) => 4000.0 + 1000.0 * math.sin(0.3 * t);

final _primary = _session([
  (_channel('velocity', 'km/h', 100.0, 10.0, _speedAt, (t) => t < 40.0 || t > 50.0), 'speed'),
]);

FusionSource _source(
  String id,
  TelemetrySession session, {
  String status = 'aligned',
  SourceClock clock = const SourceClock(),
}) => FusionSource(sourceId: id, session: session, clock: clock, alignmentStatus: status);

// a: speed 30 km/h off (conflicts); b: speed that agrees; c: rpm over the
// whole run, 2 s behind the primary; d: rpm for the first 20 s only, with
// gaps (NaN); e: speed in mph (a unit mismatch); x: not aligned.
final _sources = [
  _source(
    'a',
    _session([(_channel('velocity', 'km/h', 90.0, 5.0, (t) => _speedAt(t) + 30.0), 'speed')]),
  ),
  _source('b', _session([(_channel('velocity', 'km/h', 90.0, 5.0, _speedAt), 'speed')])),
  _source(
    'c',
    _session([(_channel('rpm-obd', 'rpm', 95.0, 5.0, _rpmAt), 'rpm')]),
    clock: const SourceClock(offsetSeconds: 2.0, driftPpm: 50.0),
  ),
  _source(
    'd',
    _session([
      (
        _channel(
          'rpm',
          'rpm',
          95.0,
          5.0,
          (t) => t % 5.0 < 1.0 ? double.nan : _rpmAt(t),
          (t) => t < 20.0,
        ),
        'rpm',
      ),
    ]),
  ),
  _source(
    'e',
    _session([(_channel('velocity', 'mph', 90.0, 5.0, (t) => _speedAt(t) / 1.609), 'speed')]),
  ),
  _source('x', _session([(_channel('rpm', 'rpm', 95.0, 5.0, _rpmAt), 'rpm')]), status: 'ambiguous'),
];

/// Everything the result says, as text.
String _fingerprint(ChannelFusionResult result) => [
  for (final channel in result.channels)
    [
      channel.key,
      channel.name,
      channel.unit,
      channel.rule,
      channel.comparedSourceId,
      channel.comparedSamples,
      channel.medianDifference,
      channel.highDifference,
      channel.fractionOverTolerance,
      channel.activeFractionOverTolerance,
      channel.conflicting,
      channel.channel.timestamps.join(','),
      channel.channel.values.join(','),
      channel.channel.name,
      channel.channel.unit,
      [
        for (final segment in channel.segments)
          '${segment.sourceId}@${segment.start}-${segment.end}'
              ' clock ${segment.clock.offsetSeconds}/${segment.clock.driftPpm}'
              ' every ${segment.sampleIntervalSeconds}',
      ],
    ].join('|'),
  'unresolved ${result.unresolved}',
  'mismatches ${result.unitMismatches}',
  'refused ${result.refusedSources}',
].join('\n');

Iterable<List<T>> _permutations<T>(List<T> items) sync* {
  if (items.length <= 1) {
    yield items;
    return;
  }
  for (var index = 0; index < items.length; ++index) {
    final rest = [...items]..removeAt(index);
    for (final tail in _permutations(rest)) {
      yield [items[index], ...tail];
    }
  }
}

FusedChannel _find(ChannelFusionResult result, String key) =>
    result.channels.singleWhere((channel) => channel.key == key);

void main() {
  final policies = {
    'no rules': const FusionPolicy(),
    'speed from b': const FusionPolicy(
      rules: {'speed': (sourceId: 'b', rule: FusionRule.preferAlternative)},
    ),
    'rpm from d': const FusionPolicy(rules: {'rpm': (sourceId: 'd', rule: FusionRule.fillGaps)}),
  };
  for (final MapEntry(key: name, value: policy) in policies.entries) {
    test('permuted alternatives give the same result: $name', () {
      final expected = _fingerprint(fuseChannels(_primary, 'vbo', _sources, policy: policy));
      for (final order in _permutations(_sources)) {
        expect(
          _fingerprint(fuseChannels(_primary, 'vbo', order, policy: policy)),
          expected,
          reason: 'order ${[for (final source in order) source.sourceId]}',
        );
      }
    });
  }

  test('without rules a conflict from any source is unresolved', () {
    for (final order in _permutations(_sources.sublist(0, 2))) {
      final result = fuseChannels(_primary, 'vbo', order);
      expect(result.unresolved, ['speed']);
      final speed = _find(result, 'speed');
      expect(speed.rule, 'unresolvedConflict');
      expect(speed.comparedSourceId, 'a');
      expect(speed.conflicting, isTrue);
    }
  });

  test('a rule naming a source decides even after another conflicts', () {
    final result = fuseChannels(_primary, 'vbo', _sources, policy: policies['speed from b']!);
    expect(result.unresolved, isEmpty);
    final speed = _find(result, 'speed');
    expect(speed.rule, 'preferAlternative');
    // The other source's disagreement is still shown.
    expect(speed.comparedSourceId, 'a');
    expect(speed.conflicting, isTrue);
    expect({for (final segment in speed.segments) segment.sourceId}, {'vbo', 'b'});
  });

  test('a rule that cannot apply leaves the others to decide', () {
    // The rule names the mph recording, whose unit does not match.
    final result = fuseChannels(
      _primary,
      'vbo',
      _sources,
      policy: const FusionPolicy(rules: {'speed': (sourceId: 'e', rule: FusionRule.fillGaps)}),
    );
    expect(result.unitMismatches, ['speed: e']);
    expect(result.unresolved, ['speed']);
    expect(_find(result, 'speed').comparedSourceId, 'a');
  });

  test('a channel only alternatives have comes from the one covering most', () {
    for (final order in _permutations(_sources.sublist(2))) {
      final rpm = _find(fuseChannels(_primary, 'vbo', order), 'rpm');
      expect(rpm.rule, 'added');
      expect(rpm.segments.map((segment) => segment.sourceId).toSet(), {'c'});
      // A rule gives the shorter one priority.
      final ruled = _find(
        fuseChannels(_primary, 'vbo', order, policy: policies['rpm from d']!),
        'rpm',
      );
      expect(ruled.segments.map((segment) => segment.sourceId).toSet(), {'d'});
    }
  });

  test('a repeated source ID is refused, whatever the order', () {
    final long = _source('a', _session([(_channel('rpm', 'rpm', 90.0, 5.0, _rpmAt), 'rpm')]));
    final short = _source('a', _session([(_channel('rpm', 'rpm', 20.0, 5.0, _rpmAt), 'rpm')]));
    for (final order in [
      [long, short],
      [short, long],
    ]) {
      final result = fuseChannels(_primary, 'vbo', [...order, _sources[2]]);
      expect(result.refusedSources, ['a', 'a']);
      expect(_find(result, 'rpm').segments.map((segment) => segment.sourceId).toSet(), {'c'});
    }
  });

  test('unit mismatches are reported in source ID order', () {
    final result = fuseChannels(_primary, 'vbo', _sources.reversed.toList());
    expect(result.unitMismatches, ['speed: e']);
  });

  test('refused sources are listed in source ID order', () {
    final refused = [
      _source('z', _primary, status: 'ambiguous'),
      _source('m', _primary, status: 'ambiguous'),
    ];
    expect(fuseChannels(_primary, 'vbo', refused).refusedSources, ['m', 'z']);
  });
}
