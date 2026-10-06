// Compares the Dart recording alignment and channel fusion port
// (fusion/telemetry_sync_engine.dart, fusion/recording_alignment.dart and
// fusion/channel_fusion.dart) with FlappedEar Overlays' C++ implementation
// (TelemetrySyncEngine, RecordingAlignment and ChannelFusion, d4d1039).
//
// test/parity/fusion_reference.json is the output of tool/cpp_fusion_dump.
// The synthetic recordings below are built exactly as the tool builds them
// (the same `wave`, made of + - * / and floor only, so no C library is
// involved); their digests are checked first. Every number, string, count
// and sample must then be equal: no tolerance.
//
// FET_PARITY_REPORT=1 prints how many values were compared and how many
// differed.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_json.dart';

/// Cases where Telemetry deliberately differs from Overlays, and why. Each
/// has truth tests of its own; the Overlays ticket ports the change.
const _fusionDepartures = {
  // The preferred source's missing values (NaN) no longer count as coverage,
  // so the other source fills them (FET-200, KAN-223;
  // test/fusion/fusion_coverage_test.dart).
  'missingValues': 'FET-200',
  // The preferred source's RCZ gap markers go where the other source fills
  // the loss (truth tests "RCZ gap markers ..." in the same file).
  'gapMarkersPreferred': 'FET-200',
  // FET-201 (KAN-224) adds conflict rules beyond Overlays' median: far-off
  // shares, compared at the slower recording's rate, and an undeclared unit
  // that only disagrees in use is a conflict, not a unit mismatch. No corpus
  // case reaches them, so none is skipped; the truth tests are in
  // test/fusion/fusion_conflict_test.dart.
};

var _compared = 0;
var _mismatched = 0;

void main() {
  final reference = qtJsonDecode(
    File('test/parity/fusion_reference.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final inputs = reference['inputs'] as Map<String, Object?>;

  tearDownAll(() {
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      stdout.writeln('values compared: $_compared, mismatches: $_mismatched');
    }
  });

  void run(String what, void Function(FusionCheck check) body) {
    final check = FusionCheck(what);
    body(check);
    _compared += check.compared;
    _mismatched += check.mismatched;
    expect(check.failures, isEmpty);
  }

  test('algorithm names', () {
    expect(reference['alignmentAlgorithm'], recordingAlignmentAlgorithm);
    expect(reference['fusionAlgorithm'], channelFusionAlgorithm);
  });

  test('the reference covers every case', () {
    expect((reference['alignment'] as Map).keys, unorderedEquals(_alignmentCases.keys));
    expect((reference['fusion'] as Map).keys, unorderedEquals(_fusionCases().keys));
    final statuses = {
      for (final value in (reference['alignment'] as Map).values) (value as Map)['status'],
    };
    expect(statuses, containsAll(['aligned', 'ambiguous', 'conflicting', 'insufficient']));
    final rules = {
      for (final value in (reference['fusion'] as Map).values)
        for (final channel in (value as Map)['channels'] as List) (channel as Map)['rule'],
    };
    expect(
      rules,
      containsAll(['primary', 'added', 'fillGaps', 'preferAlternative', 'unresolvedConflict']),
    );
  });

  group('sync engine', () {
    final sync = reference['sync'] as Map<String, Object?>;
    final cases = sync['cases'] as Map<String, Object?>;
    final primary = _recording(0.0, 900.0, 10.0, _uniqueSpeed);
    final candidate = _recording(0.0, 700.0, 5.0, (c) => _uniqueSpeed(c + 55.5));
    final pairs = <String, (TelemetrySession, TelemetrySession)>{
      'clean': (candidate, primary),
      'cleanReversed': (primary, candidate),
      'lapAway': (_candidateOf(123.4, 0.0), _primaryDay()),
      'drift': (_candidateOf(40.0, 400.0), _primaryDay()),
    };
    for (final MapEntry(:key, :value) in pairs.entries) {
      test(key, () {
        run('sync $key', (check) {
          check.sync(
            key,
            synchronizeTelemetry(value.$1, value.$2),
            cases[key] as Map<String, Object?>,
          );
        });
      });
    }
    test('confidence levels', () {
      run('levels', (check) {
        for (final row in (sync['levels'] as List).cast<List<Object?>>()) {
          final value = row[0] == null ? double.nan : (row[0] as num).toDouble();
          check.same('level $value', syncConfidenceLevel(value).name, row[1]);
          check.same(
            'autoApply $value',
            shouldAutoApplySyncCandidate(SyncCandidate(confidence: value)),
            row[2],
          );
        }
      });
    });
  });

  group('alignment', () {
    final cases = reference['alignment'] as Map<String, Object?>;
    for (final MapEntry(:key, :value) in _alignmentCases.entries) {
      test(key, () {
        final (primary, candidate, options) = value();
        run('alignment $key', (check) {
          final input = inputs['alignment/$key'] as Map<String, Object?>;
          check.session('$key primary input', primary, input['primary'] as Map<String, Object?>);
          check.session(
            '$key candidate input',
            candidate,
            input['candidate'] as Map<String, Object?>,
          );
          check.alignment(
            key,
            alignRecordings(primary, candidate, options: options),
            cases[key] as Map<String, Object?>,
          );
        });
      });
    }
  });

  group('fusion', () {
    final cases = reference['fusion'] as Map<String, Object?>;
    for (final MapEntry(:key, :value) in _fusionCases().entries) {
      test(key, () {
        final (primary, alternatives, policy) = value;
        run('fusion $key', (check) {
          final input = inputs['fusion/$key'] as Map<String, Object?>;
          check.session('$key primary input', primary, input['primary'] as Map<String, Object?>);
          for (final alternative in alternatives) {
            if (alternative.session == null) continue;
            check.session(
              '$key ${alternative.sourceId} input',
              alternative.session!,
              input[alternative.sourceId] as Map<String, Object?>,
            );
          }
          // A deliberate departure from Overlays: the inputs still match, the
          // result is checked by truth tests instead.
          if (_fusionDepartures.containsKey(key)) return;
          final expected = cases[key] as Map<String, Object?>;
          final result = fuseChannels(primary, 'vbo', alternatives, policy: policy);
          check.fusion(key, result, expected);
          check.session(
            '$key session',
            fusedSession(primary, result),
            expected['session'] as Map<String, Object?>,
          );
        });
      });
    }
  });

  test('conflict tolerances', () {
    run('tolerances', (check) {
      for (final row in (reference['tolerances'] as List).cast<List<Object?>>()) {
        final unit = row[0] as String;
        final range = (row[1] as num).toDouble();
        check.number('$unit $range', fusionConflictTolerance(unit, range), row[2]);
      }
    });
  });
}

// --- The synthetic recordings of tool/cpp_fusion_dump ------------------------

const double _pi = 3.141592653589793;

// sin(x) to about 2e-8, from + - * / and floor only.
double _wave(double x) {
  const twoPi = 2.0 * _pi;
  final r = x - (x / twoPi + 0.5).floorToDouble() * twoPi;
  final r2 = r * r;
  return r *
      (1.0 +
          r2 *
              (-1.0 / 6.0 +
                  r2 *
                      (1.0 / 120.0 +
                          r2 *
                              (-1.0 / 5040.0 +
                                  r2 *
                                      (1.0 / 362880.0 +
                                          r2 *
                                              (-1.0 / 39916800.0 +
                                                  r2 *
                                                      (1.0 / 6227020800.0 +
                                                          r2 *
                                                              (-1.0 / 1307674368000.0 +
                                                                  r2 *
                                                                      (1.0 /
                                                                          355687428096000.0)))))))));
}

double _daySpeed(double t) {
  final lap = 2.0 * _pi * t / 110.0;
  final racing =
      90.0 +
      35.0 * _wave(lap) +
      15.0 * _wave(3.0 * lap + 0.4) +
      10.0 * _wave(0.013 * t) +
      6.0 * _wave(0.0071 * t + 1.0) +
      2.0 * _wave(1.7 * t) * _wave(0.031 * t);
  if (t < 120.0) return racing < 60.0 ? racing : 60.0;
  if (t > 800.0 && t < 910.0) return racing * 0.6;
  if (t > 1650.0) return racing * 0.7;
  return racing;
}

double _uniqueSpeed(double t) => 80.0 + 30.0 * _wave(0.002 * t * t / 10.0) + 10.0 * _wave(0.05 * t);

double _periodicSpeed(double t) => 80.0 + 30.0 * _wave(2.0 * _pi * t / 20.0);

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

TelemetrySession _session(
  List<(TelemetryChannel, String?)> channels, {
  double duration = 0.0,
  int sampleCount = 0,
  Map<String, String> metadata = const {},
}) => TelemetrySession(
  duration: duration,
  startTime: 0.0,
  metadata: metadata,
  channels: {for (final (channel, _) in channels) channel.name: channel},
  aliases: {for (final (channel, alias) in channels) ?alias: channel.name},
  warnings: const [],
  timingGates: const [],
  sampleCount: sampleCount,
);

TelemetrySession _recording(
  double start,
  double end,
  double rate,
  double Function(double) speedAt, [
  int? startMilliseconds,
]) {
  final speed = _channel('velocity', 'km/h', start, end, rate, speedAt);
  return _session(
    [(speed, 'speed')],
    duration: end - start,
    sampleCount: speed.values.length,
    metadata: {if (startMilliseconds != null) 'firstTimestampMilliseconds': '$startMilliseconds'},
  );
}

TelemetrySession _candidateOf(
  double offset,
  double driftPpm, [
  double length = 1500.0,
  int? startMilliseconds,
]) => _recording(
  0.0,
  length,
  5.0,
  (c) => _daySpeed(c + offset + driftPpm * 1e-6 * c),
  startMilliseconds,
);

TelemetrySession _primaryDay([int? startMilliseconds]) =>
    _recording(0.0, 1800.0, 5.0, _daySpeed, startMilliseconds);

const _dayStart = 1756450000000;

typedef _AlignmentCase = (TelemetrySession, TelemetrySession, RecordingAlignmentOptions);

final Map<String, _AlignmentCase Function()> _alignmentCases = {
  'cleanOffset': () => (
    _recording(0.0, 900.0, 10.0, _uniqueSpeed),
    _recording(0.0, 700.0, 5.0, (c) => _uniqueSpeed(c + 55.5)),
    const RecordingAlignmentOptions(),
  ),
  'cleanOffsetDeclared': () => (
    _recording(0.0, 900.0, 10.0, _uniqueSpeed, _dayStart),
    _recording(0.0, 700.0, 5.0, (c) => _uniqueSpeed(c + 55.5), _dayStart + 55000),
    const RecordingAlignmentOptions(),
  ),
  'negativeOffset': () => (
    _recording(0.0, 900.0, 10.0, _uniqueSpeed),
    _recording(0.0, 950.0, 5.0, (c) => _uniqueSpeed(c - 30.25)),
    const RecordingAlignmentOptions(),
  ),
  'lapAwayMeasuredOnly': () =>
      (_primaryDay(), _candidateOf(123.4, 0.0), const RecordingAlignmentOptions()),
  'lapAwayDeclared': () => (
    _primaryDay(_dayStart),
    _candidateOf(123.4, 0.0, 1500.0, _dayStart + 123900),
    const RecordingAlignmentOptions(),
  ),
  'agreeingDeclared': () => (
    _primaryDay(_dayStart),
    _candidateOf(123.4, 0.0, 1500.0, _dayStart + 123400),
    const RecordingAlignmentOptions(),
  ),
  'conflictingDeclared': () => (
    _primaryDay(_dayStart),
    _candidateOf(123.4, 0.0, 1500.0, _dayStart + 183400),
    const RecordingAlignmentOptions(),
  ),
  'drift': () => (
    _primaryDay(_dayStart),
    _candidateOf(40.0, 400.0, 1500.0, _dayStart + 40000),
    const RecordingAlignmentOptions(),
  ),
  'driftNegative': () => (
    _primaryDay(_dayStart),
    _candidateOf(40.0, -600.0, 1500.0, _dayStart + 40000),
    const RecordingAlignmentOptions(),
  ),
  'implausibleDrift': () => (
    _primaryDay(_dayStart),
    _candidateOf(40.0, 400.0, 1500.0, _dayStart + 40000),
    const RecordingAlignmentOptions(maximumPlausibleDriftPpm: 100.0),
  ),
  'threeWindows': () => (
    _primaryDay(_dayStart),
    _candidateOf(40.0, 400.0, 1500.0, _dayStart + 40000),
    const RecordingAlignmentOptions(maximumWindows: 3, minimumWindowSeconds: 200.0),
  ),
  'clockStep': () => (
    _primaryDay(_dayStart),
    _recording(
      0.0,
      1500.0,
      5.0,
      (c) => _daySpeed(c + 40.0 + (c > 750.0 ? 1.5 : 0.0)),
      _dayStart + 40000,
    ),
    const RecordingAlignmentOptions(),
  ),
  'periodic': () => (
    _recording(0.0, 600.0, 10.0, _periodicSpeed),
    _recording(0.0, 500.0, 5.0, (c) => _periodicSpeed(c + 37.0)),
    const RecordingAlignmentOptions(),
  ),
  'flat': () => (
    _recording(0.0, 600.0, 10.0, (_) => 100.0),
    _recording(0.0, 500.0, 5.0, (_) => 100.0),
    const RecordingAlignmentOptions(),
  ),
  'unrelated': () => (
    _primaryDay(_dayStart),
    _recording(0.0, 700.0, 5.0, _uniqueSpeed, _dayStart + 10000),
    const RecordingAlignmentOptions(),
  ),
  'noSpeed': () => (_primaryDay(), _session([]), const RecordingAlignmentOptions()),
  'insufficientOverlap': () => (
    _primaryDay(_dayStart),
    _candidateOf(200.0, 0.0, 15.0, _dayStart + 200000),
    const RecordingAlignmentOptions(),
  ),
  'tooFewSamples': () =>
      (_primaryDay(), _recording(0.0, 1.0, 5.0, _daySpeed), const RecordingAlignmentOptions()),
};

// std::nan(""): the positive quiet NaN (Dart's double.nan may carry the
// sign bit, which a float digest sees).
final double _quietNan = (ByteData(8)..setUint64(0, 0x7ff8000000000000)).getFloat64(0);

double _fusionSpeed(double t) => 100.0 + 20.0 * _wave(0.1 * t);

// The positive [value]'s neighbouring double towards [toward].
double _nextAfter(double value, double toward) {
  final bits = ByteData(8)..setFloat64(0, value);
  bits.setInt64(0, bits.getInt64(0) + (toward > value ? 1 : -1));
  return bits.getFloat64(0);
}

// A channel with the gap markers the RCZ parser writes, as the tool's
// withGapMarkers.
TelemetryChannel _withGapMarkers(TelemetryChannel channel, double gap) {
  final times = <double>[], values = <double>[];
  for (var index = 0; index < channel.timestamps.length; ++index) {
    if (index > 0 && channel.timestamps[index] - channel.timestamps[index - 1] > gap) {
      final before = channel.timestamps[index - 1], after = channel.timestamps[index];
      times
        ..add(_nextAfter(before, after))
        ..add(_nextAfter(after, before));
      values
        ..add(_quietNan)
        ..add(_quietNan);
    }
    times.add(channel.timestamps[index]);
    values.add(channel.values[index]);
  }
  return TelemetryChannel(
    name: channel.name,
    unit: channel.unit,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
}

TelemetrySession _fusionPrimary([List<(TelemetryChannel, String?)> extra = const []]) => _session(
  [
    (
      _channel('velocity', 'km/h', 0.0, 100.0, 10.0, _fusionSpeed, (t) => t < 40.0 || t > 50.0),
      'speed',
    ),
    (_channel('latacc-calc', 'g', 0.0, 100.0, 10.0, _wave), 'lateralAcceleration'),
    ...extra,
  ],
  duration: 100.0,
  sampleCount: 1001,
  metadata: const {'source': 'primary'},
);

TelemetrySession _fusionAlternative({
  double speedBias = 0.0,
  String speedUnit = 'km/h',
  List<(TelemetryChannel, String?)> extra = const [],
}) => _session([
  (
    _channel('velocity', speedUnit, 0.0, 90.0, 5.0, (c) => _fusionSpeed(c + 5.0) + speedBias),
    'speed',
  ),
  (_channel('coolant_temp-obd', 'C', 0.0, 95.0, 1.0, (c) => 90.0 + 0.01 * c), null),
  (
    _channel(
      'rpm-obd',
      'rpm',
      0.0,
      95.0,
      5.0,
      (c) => 4000.0 + 1000.0 * _wave(0.3 * c),
      (c) => c < 60.0 || c > 70.0,
    ),
    'rpm',
  ),
  ...extra,
]);

typedef _FusionCase = (TelemetrySession, List<FusionSource>, FusionPolicy);

FusionPolicy _rule(String key, String source, FusionRule rule) =>
    FusionPolicy(rules: {key: (sourceId: source, rule: rule)});

Map<String, _FusionCase> _fusionCases() {
  final primary = _fusionPrimary();
  const five = SourceClock(offsetSeconds: 5.0);
  const none = FusionPolicy();
  FusionSource rcz(
    TelemetrySession? session, [
    SourceClock clock = five,
    String status = 'aligned',
    String id = 'rcz',
  ]) => FusionSource(sourceId: id, session: session, clock: clock, alignmentStatus: status);
  final second = _fusionAlternative(
    speedBias: 8.0,
    extra: [
      (_channel('throttle', '%', 0.0, 95.0, 10.0, (c) => 50.0 + 50.0 * _wave(0.2 * c)), 'throttle'),
    ],
  );
  // Overlays KAN-188: RCZ gap markers through a 3000 s offset.
  final markedRpm = _session([
    (
      _withGapMarkers(
        _channel(
          'rpm-obd',
          'rpm',
          1000.0,
          1010.0,
          10.0,
          (c) => 3000.0 + c,
          (c) => c < 1004.0 || c > 1006.0,
        ),
        1.0,
      ),
      'rpm',
    ),
  ]);
  const offset3000 = SourceClock(offsetSeconds: 3000.0);
  final laterSpeed = (_channel('velocity', 'km/h', 3990.0, 4020.0, 10.0, _fusionSpeed), 'speed');
  final later = _session([laterSpeed]);
  final laterWithRpm = _session([
    laterSpeed,
    (_channel('rpm-obd', 'rpm', 3990.0, 4020.0, 10.0, (t) => t + 0.5), 'rpm'),
  ]);
  return {
    'added': (primary, [rcz(_fusionAlternative())], none),
    'agree': (primary, [rcz(_fusionAlternative(speedBias: 0.5))], none),
    'unresolvedConflict': (primary, [rcz(_fusionAlternative(speedBias: 8.0))], none),
    'conflictPrimaryOnly': (
      primary,
      [rcz(_fusionAlternative(speedBias: 8.0))],
      _rule('speed', 'rcz', FusionRule.primaryOnly),
    ),
    'conflictRuleForAnotherSource': (
      primary,
      [rcz(_fusionAlternative(speedBias: 8.0))],
      _rule('speed', 'another', FusionRule.fillGaps),
    ),
    'fillGaps': (primary, [rcz(_fusionAlternative())], _rule('speed', 'rcz', FusionRule.fillGaps)),
    'fillGapsConflicting': (
      primary,
      [rcz(_fusionAlternative(speedBias: 8.0))],
      _rule('speed', 'rcz', FusionRule.fillGaps),
    ),
    'preferAlternative': (
      primary,
      [rcz(_fusionAlternative())],
      _rule('speed', 'rcz', FusionRule.preferAlternative),
    ),
    'preferAlternativeDrift': (
      primary,
      [rcz(_fusionAlternative(), const SourceClock(offsetSeconds: 5.0, driftPpm: 1000.0))],
      _rule('speed', 'rcz', FusionRule.preferAlternative),
    ),
    'fillGapsNegativeDrift': (
      primary,
      [rcz(_fusionAlternative(), const SourceClock(offsetSeconds: 5.0, driftPpm: -500.0))],
      _rule('speed', 'rcz', FusionRule.fillGaps),
    ),
    'drift': (
      primary,
      [rcz(_fusionAlternative(), const SourceClock(offsetSeconds: 5.0, driftPpm: 1000.0))],
      none,
    ),
    'fractionalOffset': (
      primary,
      [rcz(_fusionAlternative(), const SourceClock(offsetSeconds: 5.03))],
      _rule('speed', 'rcz', FusionRule.fillGaps),
    ),
    for (final status in ['ambiguous', 'conflicting', 'insufficient', ''])
      'refused-$status': (primary, [rcz(_fusionAlternative(), five, status)], none),
    'refusedNanClock': (
      primary,
      [rcz(_fusionAlternative(), const SourceClock(offsetSeconds: double.nan))],
      none,
    ),
    'refusedDrift': (
      primary,
      [rcz(_fusionAlternative(), const SourceClock(offsetSeconds: 5.0, driftPpm: -2e6))],
      none,
    ),
    'refusedNull': (primary, [rcz(null)], none),
    'unitMismatch': (
      primary,
      [rcz(_fusionAlternative(speedUnit: 'm/s'))],
      _rule('speed', 'rcz', FusionRule.fillGaps),
    ),
    'unitCase': (
      primary,
      [rcz(_fusionAlternative(speedUnit: ' KM/H '))],
      _rule('speed', 'rcz', FusionRule.fillGaps),
    ),
    'unitUndeclaredAgree': (
      primary,
      [rcz(_fusionAlternative(speedBias: 0.5, speedUnit: ''))],
      _rule('speed', 'rcz', FusionRule.fillGaps),
    ),
    'unitUndeclaredConflict': (
      primary,
      [rcz(_fusionAlternative(speedBias: 8.0, speedUnit: ''))],
      _rule('speed', 'rcz', FusionRule.fillGaps),
    ),
    'twoAlternatives': (
      primary,
      [
        rcz(_fusionAlternative(speedBias: 0.3)),
        rcz(second, const SourceClock(offsetSeconds: 5.2), 'aligned', 'rcz2'),
      ],
      _rule('speed', 'rcz2', FusionRule.preferAlternative),
    ),
    'twoAlternativesRefusedFirst': (
      primary,
      [
        rcz(_fusionAlternative(), five, 'ambiguous'),
        rcz(second, const SourceClock(offsetSeconds: 5.2), 'aligned', 'rcz2'),
      ],
      none,
    ),
    'keysAndNames': (
      primary,
      [
        rcz(
          _session([
            (_channel('velocity', 'km/h', 0.0, 90.0, 5.0, (c) => _fusionSpeed(c + 5.0)), null),
            (
              _channel('latacc', 'G', 0.0, 90.0, 25.0, (c) => _wave(c + 5.0) + 0.2),
              'lateralAcceleration',
            ),
            (_channel('speed', 'km/h', 0.0, 90.0, 5.0, (c) => _fusionSpeed(c + 5.0)), null),
          ]),
        ),
      ],
      _rule('lateralAcceleration', 'rcz', FusionRule.fillGaps),
    ),
    'temperatures': (
      _fusionPrimary([
        (_channel('oil', 'C', 0.0, 100.0, 1.0, (t) => 100.0 + 0.5 * t), null),
        (_channel('water', '°C', 0.0, 100.0, 1.0, (t) => 80.0 + 0.5 * t), null),
      ]),
      [
        rcz(
          _session([
            (_channel('oil', 'c', 0.0, 95.0, 1.0, (c) => 100.0 + 0.5 * (c + 5.0) + 2.5), null),
            (_channel('water', '°C', 0.0, 95.0, 1.0, (c) => 80.0 + 0.5 * (c + 5.0) + 2.2), null),
          ]),
        ),
      ],
      none,
    ),
    'missingValues': (
      primary,
      [
        rcz(
          _session([
            (
              _channel(
                'velocity',
                'km/h',
                0.0,
                90.0,
                5.0,
                (c) => c > 30.0 && c < 33.0 ? _quietNan : _fusionSpeed(c + 5.0),
              ),
              'speed',
            ),
          ]),
        ),
      ],
      _rule('speed', 'rcz', FusionRule.preferAlternative),
    ),
    'gapMarkersAdded': (later, [rcz(markedRpm, offset3000)], none),
    'gapMarkersPreferred': (
      laterWithRpm,
      [rcz(markedRpm, offset3000)],
      _rule('rpm', 'rcz', FusionRule.preferAlternative),
    ),
    'mergedGapMarkers': (
      _session([
        (
          _channel(
            'velocity',
            'km/h',
            0.0,
            400.0,
            1.0,
            _fusionSpeed,
            (t) => t < 100.0 || t > 120.0,
          ),
          'speed',
        ),
      ]),
      [
        rcz(
          _session([
            (
              _channel(
                'velocity',
                'km/h',
                0.0,
                30.0,
                10.0,
                (c) => _fusionSpeed(c + 95.0),
                (c) => c < 13.0 || c > 15.0,
              ),
              'speed',
            ),
          ]),
          const SourceClock(offsetSeconds: 95.0),
        ),
      ],
      _rule('speed', 'rcz', FusionRule.fillGaps),
    ),
  };
}
