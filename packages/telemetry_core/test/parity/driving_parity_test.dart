// Compares the Dart G-G, driving-state and coasting port
// (analysis/gg_pairs.dart, analysis/driving_states.dart,
// analysis/coasting_analysis.dart and analysis/comparison_driving.dart) with
// FlappedEar Overlays' C++ implementation over the synthetic driving corpus,
// a few files of the main corpus and fixed cases.
//
// test/parity/driving_reference.json is the output of tool/cpp_driving_dump
// run over test/parity/driving/*.vbo and the files tool/README.md lists.
// Counts, names, reasons and provenances must match exactly; doubles to
// 1e-9 relative (1e-9 absolute near zero), as in the other parity tests.
//
// FET_DRIVING_REFERENCE and FET_DRIVING_DIRS (colon-separated) run the same
// checks against another reference (a --day output) and its recordings, for
// local runs only; FET_PARITY_REPORT=1 prints how many values were
// compared, how many differed and the largest difference.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

var _compared = 0;
var _mismatched = 0;
var _maximumDifference = 0.0;

void main() {
  final referencePath =
      Platform.environment['FET_DRIVING_REFERENCE'] ?? 'test/parity/driving_reference.json';
  final directories =
      (Platform.environment['FET_DRIVING_DIRS'] ??
              'test/parity/driving:test/parity/corpus:test/fixtures')
          .split(':');
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final stride = (reference['strides'] as Map<String, Object?>)['points'] as int;
  final recordingsJson = (reference['recordings'] as List).cast<Map<String, Object?>>();
  final pairs = (reference['pairs'] as List).cast<Map<String, Object?>>();
  final cases = reference['cases'] as Map<String, Object?>;
  final otherReference = Platform.environment.containsKey('FET_DRIVING_REFERENCE');

  tearDownAll(() {
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      stdout.writeln(
        'values compared: $_compared, mismatches: $_mismatched, '
        'largest difference: $_maximumDifference',
      );
    }
  });

  String pathOf(String name) => directories
      .map((directory) => '$directory/$name')
      .firstWhere((path) => File(path).existsSync());

  final loaded = <String, (TelemetrySession, LapSession)>{};
  (TelemetrySession, LapSession) recording(String name) => loaded.putIfAbsent(name, () {
    final session = parseVboFile(pathOf(name));
    return (session, deriveSourceLapSession(session));
  });

  ComparisonLap? lapOf(String file, Object? number) {
    final (session, laps) = recording(file);
    for (final timed in laps.timedLaps) {
      if (timed.number != number) continue;
      return ComparisonLap(
        session: session,
        laps: laps,
        start: timed.startTelemetryTime,
        end: timed.endTelemetryTime,
        lapNumber: timed.number,
      );
    }
    return null;
  }

  test('the reference covers every driving file, pairs and cases', skip: otherReference, () {
    final files = {for (final entry in recordingsJson) entry['file']};
    for (final file in Directory('test/parity/driving').listSync()) {
      expect(files, contains(file.uri.pathSegments.last));
    }
    expect(pairs.where((pair) => pair['fileA'] != pair['fileB']), isNotEmpty);
    final provenances = {
      for (final entry in recordingsJson)
        for (final lap in (entry['laps'] as List).cast<Map<String, Object?>>())
          for (final state in const ['braking', 'cornering', 'coasting'])
            ((lap['states'] as Map)[state] as Map)['provenance'],
    };
    expect(provenances, containsAll(['measured', 'inferred', 'calculated', 'unknown']));
    expect((cases['driving'] as List).length, greaterThanOrEqualTo(60));
  });

  for (final entry in recordingsJson) {
    final file = entry['file'] as String;
    for (final expected in (entry['laps'] as List).cast<Map<String, Object?>>()) {
      final what = '$file lap ${expected['lapNumber']}';
      test(what, () {
        final check = _Check(what);
        final (session, _) = recording(file);
        final start = _double(expected['start']), end = _double(expected['end']);
        final lapNumber = expected['lapNumber'] as int;
        if (lapNumber > 0) {
          final lap = lapOf(file, lapNumber)!;
          check.number('start', lap.start, start);
          check.number('end', lap.end, end);
        } else {
          check.number('duration', session.duration, end);
        }
        check.gg('gg', buildGgPairs(session, start, end), expected['gg'], stride);
        final states = classifyDrivingStates(session, start, end);
        check.states('states', states, expected['states']);
        check.states(
          'strict',
          classifyDrivingStates(
            session,
            start,
            end,
            const DrivingStateOptions(allowInferred: false),
          ),
          expected['strict'],
        );
        final overlap = overlapOf(states.braking.active, states.cornering.active);
        check.intervals('overlap', overlap, expected['overlap']);
        check.number('overlapMeters', travelledMeters(session, overlap), expected['overlapMeters']);
        check.coasting(
          'coastingBare',
          summarizeCoasting(session, start, end),
          expected['coastingBare'],
        );
        if (lapNumber > 0 && expected.containsKey('axisValid')) {
          final own = LapComparison(lapOf(file, lapNumber)!, lapOf(file, lapNumber)!);
          check.same('axisValid', own.axis.valid, expected['axisValid']);
          if (own.axis.valid && expected['axisValid'] == true) {
            check.number('axisLength', own.axisLengthMeters, expected['axisLength']);
            check.coasting(
              'coasting',
              summarizeCoasting(
                session,
                start,
                end,
                lapTrace: own.trace(0),
                approved: _fixedSegments(own.axisLengthMeters),
              ),
              expected['coasting'],
            );
          }
        }
        check.done();
      });
    }
  }

  for (final pair in pairs) {
    final what = '${pair['fileA']} ${pair['lapA']} / ${pair['fileB']} ${pair['lapB']}';
    test(what, () {
      final check = _Check(what);
      final a = lapOf(pair['fileA'] as String, pair['lapA']);
      final b = lapOf(pair['fileB'] as String, pair['lapB']);
      check.same('missing', a == null || b == null, pair['missing']);
      if (a == null || b == null) return check.done();
      final comparison = LapComparison(a, b);
      check.same('axisValid', comparison.axis.valid, pair['axisValid']);
      check.number('axisLength', comparison.axisLengthMeters, pair['axisLength']);
      for (final expected in (pair['gg'] as List).cast<Map<String, Object?>>()) {
        final from = _double(expected['requestedStart']), to = _double(expected['requestedEnd']);
        final points = expected['maximumPoints'] as int;
        check.scatter(
          'gg $from..$to/$points',
          comparisonGgScatter(comparison, from, to, points),
          expected,
          stride,
        );
      }
      for (final expected in (pair['trailBraking'] as List).cast<Map<String, Object?>>()) {
        final from = _double(expected['requestedStart']), to = _double(expected['requestedEnd']);
        check.trail('trail $from..$to', comparisonTrailBraking(comparison, from, to), expected);
      }
      for (final expected in (pair['drivingStates'] as List).cast<Map<String, Object?>>()) {
        final from = _double(expected['requestedStart']), to = _double(expected['requestedEnd']);
        final where = 'driving $from..$to';
        final laps = comparisonDrivingStates(comparison, from, to);
        check.same('$where valid', comparison.axis.valid, expected['valid']);
        if (expected['valid'] != true) continue;
        final wanted = (expected['laps'] as List).cast<Map<String, Object?>>();
        for (final slot in const [0, 1]) {
          final lap = laps[slot], want = wanted[slot];
          check.same('$where $slot valid', lap.valid, want['valid']);
          if (want['valid'] != true) {
            check.same('$where $slot reason', lap.unavailableReason, want['reason']);
            continue;
          }
          check.number('$where $slot start', lap.startTime, want['start']);
          check.number('$where $slot end', lap.endTime, want['end']);
          check.states('$where $slot states', lap.states, want['states']);
          check.coasting('$where $slot coasting', lap.coasting, want['coasting']);
          check.intervals('$where $slot overlap', lap.overlap, want['overlap']);
          check.number('$where $slot overlapMeters', lap.overlapMeters, want['overlapMeters']);
        }
      }
      check.done();
    });
  }

  for (final expected in (cases['gg'] as List).cast<Map<String, Object?>>()) {
    test('G-G case ${expected['name']}', () {
      final check = _Check('${expected['name']}');
      final session = _ggSessions()[expected['name']]!;
      check.gg(
        'gg',
        buildGgPairs(session, _double(expected['start']), _double(expected['end'])),
        expected,
        stride,
      );
      check.done();
    });
  }

  test('G-G peaks and thinning', () {
    final check = _Check('peaks');
    final expected = cases['peaks'] as Map<String, Object?>;
    final points = [
      for (var i = 0; i < 5000; ++i) GgPoint(i * 0.01, 0.3 * cos(i * 0.01), 0.3 * sin(i * 0.01)),
    ];
    points[1234] = GgPoint(points[1234].time, -1.1, points[1234].lateralG);
    points[3777] = GgPoint(points[3777].time, points[3777].longitudinalG, -1.05);
    final peaks = computeGgPeaks(points);
    check.peaks('peaks', peaks, expected['peaks']);
    for (final row in (expected['decimated'] as List).cast<Map<String, Object?>>()) {
      final shown = decimateGgPoints(points, peaks, row['maximumPoints'] as int);
      check.points('decimated ${row['maximumPoints']}', shown, row['count'], row['points'], 7);
    }
    check.peaks('empty', computeGgPeaks(const []), expected['emptyPeaks']);
    check.done();
  });

  final drivingSessions = _drivingSessions();
  for (final expected in (cases['driving'] as List).cast<Map<String, Object?>>()) {
    final what = 'driving case ${expected['session']} ${expected['options']}';
    test(what, () {
      final check = _Check(what);
      final session = drivingSessions[expected['session']]!;
      final options = _options[expected['options']]!;
      final start = _double(expected['start']), end = _double(expected['end']);
      final states = classifyDrivingStates(session, start, end, options);
      check.states('states', states, expected['states']);
      final overlap = overlapOf(states.braking.active, states.cornering.active);
      check.intervals('overlap', overlap, expected['overlap']);
      check.number('overlapMeters', travelledMeters(session, overlap), expected['overlapMeters']);
      check.number(
        'brakingMeters',
        travelledMeters(session, states.braking.active),
        expected['brakingMeters'],
      );
      check.coasting(
        'coasting',
        summarizeCoasting(
          session,
          start,
          end,
          lapTrace: _coastingTrace(),
          approved: _coastingSegments(),
          options: options,
        ),
        expected['coasting'],
      );
      check.coasting(
        'coastingBare',
        summarizeCoasting(session, start, end, options: options),
        expected['coastingBare'],
      );
      check.done();
    });
  }
}

ApprovedSegmentation _fixedSegments(double length) => ApprovedSegmentation(
  trackConfigurationReference: 'fixed',
  valid: true,
  segments: [
    for (final (id, name, type, from, to) in const [
      ('s1', 'Turn 1', 'corner', 0.10, 0.40),
      ('s2', 'Back straight', 'straight', 0.40, 0.70),
      ('s3', 'Turn 2', 'corner', 0.70, 0.95),
      ('s4', 'Start/finish', 'straight', 0.95, 0.10),
    ])
      {
        'id': id,
        'name': name,
        'type': type,
        'startProgressMeters': from * length,
        'endProgressMeters': to * length,
      },
  ],
);

TelemetryChannel _timedChannel(
  String name,
  String unit,
  List<double> times,
  double Function(double) value,
) => TelemetryChannel(
  name: name,
  unit: unit,
  timestamps: Float64List.fromList(times),
  values: Float32List.fromList([for (final time in times) value(time)]),
);

List<double> _clock(double start, double end, double step) {
  final times = <double>[];
  for (var time = start; time <= end + 1e-9; time += step) {
    times.add(time);
  }
  return times;
}

TelemetrySession _session(Map<String, TelemetryChannel> aliased) => TelemetrySession(
  duration: 10,
  startTime: 0,
  metadata: const {},
  channels: {for (final channel in aliased.values) channel.name: channel},
  aliases: {for (final entry in aliased.entries) entry.key: entry.value.name},
  warnings: const [],
  timingGates: const [],
  sampleCount: 0,
);

TelemetrySession _ggSession(TelemetryChannel longitudinal, TelemetryChannel lateral) =>
    _session({'longitudinalAcceleration': longitudinal, 'lateralAcceleration': lateral});

// The sessions of cpp_driving_dump's ggCases (GgPairsTests.cpp's).
Map<String, TelemetrySession> _ggSessions() {
  final shared = _clock(0.0, 1.0, 0.1);
  final sharedSession = _ggSession(
    _timedChannel('longacc', 'g', shared, (t) => t < 0.5 ? -0.8 : 0.3),
    _timedChannel('latacc', 'g', shared, (t) => t < 0.5 ? 0.6 : -0.4),
  );
  final lateralTimes = <double>[];
  for (var time = 0.025; time <= 1.525; time += 0.05) {
    if (time < 0.4 || time > 0.9) lateralTimes.add(time);
  }
  final short = _clock(0.0, 0.5, 0.1);
  final outlierTimes = _clock(0.0, 0.9, 0.1);
  final outliers = _ggSession(
    _timedChannel(
      'longacc',
      'g',
      outlierTimes,
      (t) => (t - 0.3).abs() < 1e-6
          ? 12.0
          : (t - 0.5).abs() < 1e-6
          ? double.nan
          : -0.4,
    ),
    _timedChannel('latacc', 'g', outlierTimes, (t) => (t - 0.7).abs() < 1e-6 ? double.nan : 0.7),
  );
  return {
    'shared': sharedSession,
    'sharedPart': sharedSession,
    'interpolated': _ggSession(
      _timedChannel('longacc', 'g', _clock(0.0, 1.5, 0.1), (_) => -0.5),
      _timedChannel('latacc', 'g', lateralTimes, (t) => t),
    ),
    'metric': _ggSession(
      _timedChannel('longacc', 'm/s^2', short, (_) => -9.80665),
      _timedChannel('latacc', 'm/s²', short, (_) => 4.903325),
    ),
    'metricSpaced': _ggSession(
      _timedChannel('longacc', ' M/S2 ', short, (_) => 3.0),
      _timedChannel('latacc', 'm / s ^ 2', short, (_) => -2.0),
    ),
    'undeclared': _ggSession(
      _timedChannel('longacc', '', short, (_) => 0.2),
      _timedChannel('latacc', '', short, (_) => 0.1),
    ),
    'unsupported': _ggSession(
      _timedChannel('longacc', 'km/h', short, (_) => 1.0),
      _timedChannel('latacc', 'g', short, (_) => 0.1),
    ),
    'outliers': outliers,
    'inverted': outliers,
    'outside': outliers,
    'missingLateral': _session({
      'longitudinalAcceleration': _timedChannel('longacc', 'g', outlierTimes, (_) => 0.1),
    }),
    'empty': _session(const {}),
  };
}

const double _dt = 0.05;
const int _sampleCount = 201;

TelemetryChannel _channel(
  String name,
  String unit,
  double Function(double) value, [
  bool Function(double)? present,
]) {
  final times = <double>[];
  for (var k = 0; k < _sampleCount; ++k) {
    final t = k * _dt;
    if (present == null || present(t)) times.add(t);
  }
  return _timedChannel(name, unit, times, value);
}

double _brake(double t) => t > 5.0 && t < 7.0 ? 60.0 : 0.0;
double _throttle(double t) => t < 4.0 || t > 8.0 ? 90.0 : 0.0;
double _lateral(double t) => t > 4.5 && t < 7.5 ? -0.9 : 0.05;
double _longitudinal(double t) => t < 4.0 || t > 8.0
    ? 0.25
    : t > 5.0 && t < 7.0
    ? -0.7
    : 0.0;
double _speed(double _) => 110.0;

// The sessions of cpp_driving_dump's drivingSessions (DrivingStatesTests.cpp's
// and a few more).
Map<String, TelemetrySession> _drivingSessions() => {
  'measured': _session({
    'brake': _channel('brake_pos-obd', '%', _brake),
    'throttle': _channel('accelerator_pos-obd', '%', _throttle),
    'lateralAcceleration': _channel('latacc-calc', 'g', _lateral),
    'longitudinalAcceleration': _channel('longacc-calc', 'g', _longitudinal),
    'speed': _channel('velocity', 'km/h', _speed),
  }),
  'inferred': _session({
    'lateralAcceleration': _channel('latacc', 'g', _lateral),
    'longitudinalAcceleration': _channel('longacc', 'g', _longitudinal),
    'speed': _channel('velocity', 'km/h', _speed),
  }),
  'gapped': _session({
    'brake': _channel('brake_pos-obd', '%', _brake, (t) => t < 2.0 || t > 3.0),
    'throttle': _channel('accelerator_pos-obd', '%', (t) => t > 1.0 && t < 4.0 ? 0.0 : 90.0),
    'speed': _channel('velocity', 'km/h', _speed),
  }),
  'bar': _session({
    'brake': _channel('brake_pressure', 'bar', _brake),
    'throttle': _channel('accelerator_pos-obd', '%', _throttle),
    'longitudinalAcceleration': _channel('longacc', 'g', _longitudinal),
    'speed': _channel('velocity', 'km/h', _speed),
  }),
  'slow': _session({
    'brake': _channel('brake_pos-obd', '%', (_) => 0.0),
    'throttle': _channel('accelerator_pos-obd', '%', (_) => 0.0),
    'speed': _channel('velocity', 'km/h', (t) => t < 5.0 ? 5.0 : 60.0),
  }),
  'leftFoot': _session({
    'brake': _channel('brake_pos-obd', '%', (t) => t > 5.0 && t < 6.0 ? 30.0 : 0.0),
    'throttle': _channel('accelerator_pos-obd', '%', (t) => t > 4.0 && t < 7.0 ? 50.0 : 0.0),
    'speed': _channel('velocity', 'km/h', _speed),
  }),
  'blip': _session({
    'brake': _channel('brake_pos-obd', '%', (t) => (t - 3.0).abs() < 0.01 ? 50.0 : 0.0),
    'throttle': _channel('accelerator_pos-obd', '%', (_) => 0.0),
    'speed': _channel('velocity', 'km/h', _speed),
  }),
  'coasting': _session({
    'brake': _channel('brake_pos-obd', '%', _brake),
    'throttle': _channel('accelerator_pos-obd', '%', _throttle),
    'speed': _channel('velocity', 'km/h', (_) => 36.0),
  }),
  'speedOnly': _session({'speed': _channel('velocity', 'km/h', _speed)}),
  'mph': _session({
    'brake': _channel('brake_pos-obd', '%', _brake),
    'throttle': _channel('accelerator_pos-obd', '%', _throttle),
    'lateralAcceleration': _channel('latacc', 'm/s2', _lateral),
    'speed': _channel('velocity', 'mph', _speed),
  }),
  'noSpeed': _session({
    'brake': _channel('brake_pos-obd', 'PCT', _brake),
    'throttle': _channel('accelerator_pos-obd', '', _throttle),
  }),
  'missingSamples': _session({
    'brake': _channel(
      'brake_pos-obd',
      '%',
      (t) => (t - 2.5).abs() < 0.01 || (t - 2.55).abs() < 0.01 ? double.nan : _brake(t + 1.0),
    ),
    'throttle': _channel('accelerator_pos-obd', '%', _throttle),
    'lateralAcceleration': _channel('latacc', 'g', _lateral),
    'speed': _channel('velocity', 'km/h', (t) => t < 9.0 ? 110.0 : double.nan),
  }),
};

const Map<String, DrivingStateOptions> _options = {
  'default': DrivingStateOptions(),
  'strict': DrivingStateOptions(allowInferred: false),
  'invalid': DrivingStateOptions(cornering: BrakingThreshold(0.2, 0.3, 'g')),
  'tuned': DrivingStateOptions(
    minimumSpeedKmh: 1.0,
    minimumDurationSeconds: 0.5,
    cornering: BrakingThreshold(0.5, 0.4, 'G'),
  ),
  'window': DrivingStateOptions(),
  'empty': DrivingStateOptions(),
};

List<ProgressSegment> _coastingTrace() => [
  ProgressSegment([
    for (var k = 0; k < _sampleCount; ++k) ProjectedSample(k * _dt, progressMeters: k * _dt * 10.0),
  ]),
];

ApprovedSegmentation _coastingSegments() => ApprovedSegmentation(
  trackConfigurationReference: '',
  valid: true,
  segments: [
    for (final (id, start, end) in const [
      ('approach', 0.0, 50.0),
      ('corner', 50.0, 70.0),
      ('exit', 70.0, 100.0),
    ])
      {
        'id': id,
        'name': id.toUpperCase(),
        'type': 'sector',
        'startProgressMeters': start,
        'endProgressMeters': end,
      },
  ],
);

double _double(Object? value) => value == null ? double.nan : (value as num).toDouble();

/// Collects every difference of one test, so a local run can count them.
final class _Check {
  _Check(this.what);

  final String what;
  final List<String> failures = [];

  void _fail(String message) {
    ++_mismatched;
    if (failures.length < 20) failures.add(message);
  }

  void same(String where, Object? actual, Object? expected) {
    ++_compared;
    if (!_equal(actual, expected)) _fail('$where: $actual, expected $expected');
  }

  static bool _equal(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; ++i) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is num && b is num) return a == b;
    return a == b;
  }

  void number(String where, double actual, Object? expected) {
    ++_compared;
    if (expected == null) {
      if (actual.isFinite) _fail('$where: $actual, expected no value');
      return;
    }
    final value = _double(expected);
    final difference = (actual - value).abs();
    if (difference > _maximumDifference) _maximumDifference = difference;
    if (!(difference <= max(1e-9, 1e-9 * value.abs()))) {
      _fail('$where: $actual, expected $value');
    }
  }

  void optional(String where, double? actual, Object? expected) {
    if (actual == null || expected == null) {
      same('$where present', actual != null, expected != null);
      return;
    }
    number(where, actual, expected);
  }

  void point(String where, GgPoint actual, List<Object?> expected) {
    number('$where time', actual.time, expected[1]);
    number('$where longitudinal', actual.longitudinalG, expected[2]);
    number('$where lateral', actual.lateralG, expected[3]);
  }

  void points(String where, List<GgPoint> actual, Object? count, Object? expected, int stride) {
    same('$where count', actual.length, count);
    final rows = (expected as List).cast<List<Object?>>();
    var p = 0;
    for (var i = 0; i < actual.length; ++i) {
      if (i % stride != 0 && i != actual.length - 1) continue;
      if (p >= rows.length) {
        _fail('$where: more points than expected');
        return;
      }
      same('$where index', i, rows[p][0]);
      point('$where $i', actual[i], rows[p]);
      ++p;
    }
    same('$where point count', p, rows.length);
  }

  void peak(String where, GgPeak? actual, Object? expected) {
    if (actual == null || expected == null) {
      same('$where present', actual != null, expected != null);
      return;
    }
    final row = expected as List;
    number('$where value', actual.value, row[0]);
    point(where, actual.point, [null, ...row.skip(1)]);
  }

  void peaks(String where, GgPeaks actual, Object? expected) {
    final want = expected as Map<String, Object?>;
    peak('$where lateral', actual.lateral, want['lateral']);
    peak('$where braking', actual.braking, want['braking']);
    peak('$where acceleration', actual.acceleration, want['acceleration']);
    peak('$where combined', actual.combined, want['combined']);
    same('$where sampleCount', actual.sampleCount, want['sampleCount']);
  }

  void gg(String where, GgPairs actual, Object? expected, int stride) {
    final want = expected as Map<String, Object?>;
    same(
      '$where fields',
      [
        actual.valid,
        actual.unavailableReason,
        actual.longitudinalChannel,
        actual.lateralChannel,
        actual.longitudinalUnit,
        actual.lateralUnit,
        actual.unitsDeclared,
        actual.sharedClock,
        actual.candidateCount,
        actual.skippedForGap,
        actual.excludedOutliers,
      ],
      [
        want['valid'],
        want['reason'],
        want['longitudinalChannel'],
        want['lateralChannel'],
        want['longitudinalUnit'],
        want['lateralUnit'],
        want['unitsDeclared'],
        want['sharedClock'],
        want['candidateCount'],
        want['skippedForGap'],
        want['excludedOutliers'],
      ],
    );
    number('$where offset', actual.maximumPairingOffsetSeconds, want['maximumPairingOffset']);
    points('$where points', actual.points, want['count'], want['points'], stride);
    final peaksOf = computeGgPeaks(actual.points);
    peaks('$where peaks', peaksOf, want['peaks']);
    points(
      '$where decimated',
      decimateGgPoints(actual.points, peaksOf, 300),
      want['decimatedCount'],
      want['decimated'],
      16,
    );
  }

  void scatter(
    String where,
    ComparisonGgScatter actual,
    Map<String, Object?> expected,
    int stride,
  ) {
    same('$where valid', actual.valid, expected['valid']);
    if (expected['valid'] != true || !actual.valid) return;
    number('$where start', actual.startMeters, expected['startMeters']);
    number('$where end', actual.endMeters, expected['endMeters']);
    final laps = (expected['laps'] as List).cast<Map<String, Object?>>();
    for (final slot in const [0, 1]) {
      final lap = actual.laps[slot], want = laps[slot];
      same('$where $slot valid', lap.valid, want['valid']);
      if (want['valid'] != true || !lap.valid) {
        same('$where $slot reason', lap.unavailableReason, want['reason']);
        continue;
      }
      final pairs = lap.pairs!;
      same(
        '$where $slot fields',
        [
          pairs.candidateCount,
          pairs.skippedForGap,
          pairs.excludedOutliers,
          pairs.sharedClock,
          pairs.unitsDeclared,
          pairs.longitudinalChannel,
          pairs.lateralChannel,
        ],
        [
          want['candidateCount'],
          want['skippedForGap'],
          want['excludedOutliers'],
          want['sharedClock'],
          want['unitsDeclared'],
          want['longitudinalChannel'],
          want['lateralChannel'],
        ],
      );
      peaks('$where $slot peaks', lap.peaks, want['peaks']);
      points('$where $slot points', lap.points, want['pointCount'], want['points'], stride);
    }
  }

  void strip(String where, List<RangeFraction> actual, Object? expected) {
    final rows = (expected as List).cast<List<Object?>>();
    same('$where size', actual.length, rows.length);
    for (var i = 0; i < min(actual.length, rows.length); ++i) {
      number('$where $i from', actual[i].from, rows[i][0]);
      number('$where $i to', actual[i].to, rows[i][1]);
    }
  }

  void trail(String where, ComparisonTrailBraking actual, Map<String, Object?> expected) {
    same('$where valid', actual.valid, expected['valid']);
    if (expected['valid'] != true || !actual.valid) return;
    number('$where start', actual.startMeters, expected['startMeters']);
    number('$where end', actual.endMeters, expected['endMeters']);
    same('$where crosses', actual.crossesStartFinish, expected['crossesStartFinish']);
    final laps = (expected['laps'] as List).cast<Map<String, Object?>>();
    for (final slot in const [0, 1]) {
      final lap = actual.laps[slot], want = laps[slot];
      same('$where $slot valid', lap.valid, want['valid']);
      same('$where $slot reason', lap.unavailableReason, want['unavailableReason'] ?? '');
      if (want.containsKey('brakingProvenance')) {
        same(
          '$where $slot provenance',
          [lap.brakingProvenance, lap.corneringProvenance],
          [want['brakingProvenance'], want['corneringProvenance']],
        );
      }
      if (want['valid'] != true || !lap.valid) continue;
      same(
        '$where $slot channels',
        [lap.brakeChannel, lap.lateralChannel],
        [want['brakeChannel'], want['lateralChannel']],
      );
      number('$where $slot overlapSeconds', lap.overlapSeconds, want['overlapSeconds']);
      number('$where $slot overlapMeters', lap.overlapMeters, want['overlapMeters']);
      number('$where $slot brakingSeconds', lap.brakingSeconds, want['brakingSeconds']);
      number('$where $slot corneringSeconds', lap.corneringSeconds, want['corneringSeconds']);
      final strips = want['strips'] as Map<String, Object?>;
      strip('$where $slot braking strip', lap.brakingStrip, strips['braking']);
      strip('$where $slot cornering strip', lap.corneringStrip, strips['cornering']);
      strip('$where $slot overlap strip', lap.overlapStrip, strips['overlap']);
    }
  }

  void intervals(String where, List<DrivingStateInterval> actual, Object? expected) {
    final rows = (expected as List).cast<List<Object?>>();
    same('$where size', actual.length, rows.length);
    for (var i = 0; i < min(actual.length, rows.length); ++i) {
      number('$where $i start', actual[i].start, rows[i][0]);
      number('$where $i end', actual[i].end, rows[i][1]);
    }
  }

  void track(String where, DrivingStateTrack actual, Object? expected) {
    final want = expected as Map<String, Object?>;
    final threshold = want['threshold'] as List;
    same(
      '$where fields',
      [
        actual.provenance,
        actual.channel,
        actual.unit,
        actual.unresolvedReason,
        actual.rejectedSpikes,
        actual.threshold.unit,
      ],
      [
        want['provenance'],
        want['channel'],
        want['unit'],
        want['reason'],
        want['spikes'],
        threshold[2],
      ],
    );
    number('$where on', actual.threshold.on, threshold[0]);
    number('$where off', actual.threshold.off, threshold[1]);
    intervals('$where active', actual.active, want['active']);
    intervals('$where known', actual.known, want['known']);
  }

  void states(String where, DrivingStateClassification actual, Object? expected) {
    final want = expected as Map<String, Object?>;
    same('$where valid', [actual.valid, actual.algorithm], [want['valid'], want['algorithm']]);
    number('$where start', actual.start, want['start']);
    number('$where end', actual.end, want['end']);
    track('$where braking', actual.braking, want['braking']);
    track('$where accelerating', actual.accelerating, want['accelerating']);
    track('$where cornering', actual.cornering, want['cornering']);
    track('$where coasting', actual.coasting, want['coasting']);
  }

  void coasting(String where, CoastingSummary actual, Object? expected) {
    final want = expected as Map<String, Object?>;
    same(
      '$where fields',
      [actual.valid, actual.algorithm, actual.provenance, actual.unresolvedReason],
      [want['valid'], want['algorithm'], want['provenance'], want['reason']],
    );
    number('$where lapSeconds', actual.lapSeconds, want['lapSeconds']);
    number('$where knownSeconds', actual.knownSeconds, want['knownSeconds']);
    number('$where coastingSeconds', actual.coastingSeconds, want['coastingSeconds']);
    number('$where coastingMeters', actual.coastingMeters, want['coastingMeters']);
    final episodes = (want['episodes'] as List).cast<List<Object?>>();
    same('$where episodes', actual.episodes.length, episodes.length);
    for (var i = 0; i < min(actual.episodes.length, episodes.length); ++i) {
      final episode = actual.episodes[i], row = episodes[i];
      number('$where $i start', episode.startTime, row[0]);
      number('$where $i end', episode.endTime, row[1]);
      number('$where $i seconds', episode.seconds, row[2]);
      number('$where $i meters', episode.meters, row[3]);
      optional('$where $i startProgress', episode.startProgressMeters, row[4]);
      optional('$where $i endProgress', episode.endProgressMeters, row[5]);
      same('$where $i segment', episode.segmentId, row[6]);
    }
    final segments = (want['segments'] as List).cast<List<Object?>>();
    same('$where segments', actual.segments.length, segments.length);
    for (var i = 0; i < min(actual.segments.length, segments.length); ++i) {
      final segment = actual.segments[i], row = segments[i];
      same(
        '$where segment $i',
        [segment.segmentId, segment.name, segment.type, segment.episodes],
        [row[0], row[1], row[2], row[5]],
      );
      number('$where segment $i seconds', segment.seconds, row[3]);
      number('$where segment $i meters', segment.meters, row[4]);
    }
  }

  void done() => expect(failures, isEmpty, reason: what);
}
