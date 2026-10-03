// Compares the Dart Corner Analyzer of two compared laps
// (analysis/corner_analyzer.dart) with FlappedEar Overlays' C++
// implementation over the synthetic parity corpus and hand-made cases.
//
// test/parity/corner_analyzer_reference.json is the output of
// tool/cpp_corner_analyzer_dump run over test/parity/corpus/*.vbo and
// test/fixtures/*.vbo (see tool/README.md). Every value the Corner Analyzer
// shows (Overlays' comparisonSegmentMetrics, comparisonApprovedSegments,
// comparisonHeartRate and comparisonTimeLossObservations) and the per-lap
// figures it reads (segment speeds, the corner's geometric phases, corner
// speeds, braking and exit) are compared: keys, counts, names, reasons and
// provenance exactly, doubles to 1e-9 relative (1e-9 absolute near zero), as
// in the other parity tests. The figures are measured on Overlays' own
// shared axis, written in full by the tool: an axis built in Dart can differ
// from it in the last bits, which decides whether a segment bound sample is
// inside a segment (see corner_metrics_parity_test.dart).
//
// FET_ANALYZER_REFERENCE and FET_ANALYZER_DIRS (colon-separated) run the
// same checks against another reference (a --day output) and its
// recordings, for local runs only; FET_PARITY_REPORT=1 prints how many
// values were compared, how many differed and the largest difference.
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
      Platform.environment['FET_ANALYZER_REFERENCE'] ??
      'test/parity/corner_analyzer_reference.json';
  final directories =
      (Platform.environment['FET_ANALYZER_DIRS'] ?? 'test/parity/corpus:test/fixtures').split(':');
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final configuration = reference['configuration'] as String;
  final pairs = (reference['pairs'] as List).cast<Map<String, Object?>>();
  final axes = reference['axes'] as Map<String, Object?>;
  final files = (reference['files'] as Map<String, Object?>?) ?? const {};
  final cases = reference['cases'] as Map<String, Object?>?;

  tearDownAll(() {
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      stdout.writeln(
        'values compared: $_compared, mismatches: $_mismatched, '
        'largest difference: $_maximumDifference',
      );
    }
  });

  String pathOf(String run) {
    final name = (files[run] as String?) ?? run;
    return directories
        .map((directory) => '$directory/$name')
        .firstWhere((path) => File(path).existsSync());
  }

  final recordings = <String, (TelemetrySession, LapSession)>{};
  (TelemetrySession, LapSession) recording(String run) => recordings.putIfAbsent(run, () {
    final session = parseVboFile(pathOf(run));
    return (session, deriveSourceLapSession(session));
  });

  test(
    'the reference covers corners, methods, gate crossings, pairs across files and cases',
    skip: Platform.environment.containsKey('FET_ANALYZER_REFERENCE') ? 'another reference' : false,
    () {
      expect(pairs.length, greaterThanOrEqualTo(30));
      expect(
        pairs.where((pair) => (pair['a'] as Map)['run'] != (pair['b'] as Map)['run']),
        isNotEmpty,
      );
      final segments = [
        for (final pair in pairs)
          for (final variant in (pair['variants'] as List).cast<Map<String, Object?>>())
            ...(variant['segments'] as List).cast<Map<String, Object?>>(),
      ];
      final braking = {
        for (final segment in segments)
          for (final lap in (segment['braking'] as List? ?? const []).cast<Map<String, Object?>>())
            lap['method'],
      };
      expect(braking, containsAll(['measuredBrake', 'inferredDeceleration', '']));
      final pickups = {
        for (final segment in segments)
          for (final lap in (segment['exit'] as List? ?? const []).cast<Map<String, Object?>>())
            (lap['pickup'] as Map)['method'],
      };
      expect(pickups, containsAll(['measuredThrottle', 'inferredAcceleration', '']));
      final reasons = {
        for (final segment in segments)
          for (final lap
              in (segment['segmentSpeeds'] as List? ?? const []).cast<Map<String, Object?>>())
            lap['reason'],
      };
      expect(reasons, containsAll(['', 'crossesGate']));
      expect(segments.where((segment) => segment['phases'] != null).length, greaterThan(100));
      final shared = ((cases!['shared'] as Map)['cases'] as List).cast<Map<String, Object?>>();
      expect(shared.where((item) => item['note'] == true), isNotEmpty);
      expect(shared.where((item) => item['shared'] == null), isNotEmpty);
    },
  );

  for (final pair in pairs) {
    final a = pair['a'] as Map<String, Object?>, b = pair['b'] as Map<String, Object?>;
    final what = '${a['run']} ${a['lap']} / ${b['run']} ${b['lap']}';
    test(what, () {
      final check = _Check(what);
      final (sessionA, lapsA) = recording(a['run'] as String);
      final (sessionB, lapsB) = recording(b['run'] as String);
      ComparisonLap lap(TelemetrySession session, LapSession laps, Object? number) {
        final timed = laps.timedLaps.firstWhere((timed) => timed.number == number);
        return ComparisonLap(
          session: session,
          laps: laps,
          start: timed.startTelemetryTime,
          end: timed.endTelemetryTime,
          lapNumber: timed.number,
        );
      }

      final lapA = lap(sessionA, lapsA, a['lap']), lapB = lap(sessionB, lapsB, b['lap']);
      final comparison = LapComparison(lapA, lapB);
      check.same('axisValid', comparison.axis.valid, pair['axisValid']);
      check.number('axisLength', comparison.axisLengthMeters, pair['axisLength']);
      final axis = cppAxis(axes[pair['axis']]) ?? comparison.axis;
      CornerAnalyzerLap analyzerLap(ComparisonLap lap, int slot) => CornerAnalyzerLap(
        session: lap.session,
        trace: axis.valid ? projectLapTrace(axis, lap.session, lap.start, lap.end) : const [],
        start: lap.start,
        end: lap.end,
        reference: slot,
      );
      final laps = (analyzerLap(lapA, 0), analyzerLap(lapB, 1));
      for (final variant in (pair['variants'] as List).cast<Map<String, Object?>>()) {
        final approved = approvedSegmentation(variant['stored'], configuration);
        _expectAnalyzer(
          check.at(variant['name'] as String),
          CornerAnalyzer(
            axis: axis,
            a: laps.$1,
            b: laps.$2,
            segmentation: ComparisonSegmentation(shared: approved),
          ),
          variant,
        );
      }
      check.done();
    });
  }

  if (cases != null) _cases(cases);
}

void _cases(Map<String, Object?> cases) {
  final shared = cases['shared'] as Map<String, Object?>;
  test('the segments two laps share, and when they are borrowed', () {
    final stored = shared['stored'] as Map<String, Object?>;
    const configuration =
        'compatibility-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    for (final item in (shared['cases'] as List).cast<Map<String, Object?>>()) {
      final what =
          '${item['a']} ${item['b']} ${item['canonical']} ${item['groupA']}/${item['groupB']}';
      final check = _Check(what);
      final canonical = item['canonical'] as String;
      final result = comparisonSharedSegmentation(
        approvedSegmentation(stored[item['a']], configuration),
        approvedSegmentation(stored[item['b']], item['referenceB'] as String),
        canonical: canonical.isEmpty
            ? null
            : approvedSegmentation(stored[canonical], configuration),
        groupA: item['groupA'] as String,
        groupB: item['groupB'] as String,
      );
      check.same('shared', result.shared?.revision, item['shared']);
      check.same('note', result.borrowed, item['note']);
      check.compare('segments', [
        for (final segment in comparisonApprovedSegments(result.shared)) _rowMap(segment),
      ], item['segments']);
      check.done();
    }
  });

  final handMade = cases['handMade'] as Map<String, Object?>;
  final sessions = {
    for (final spec in (handMade['sessions'] as List).cast<Map<String, Object?>>())
      spec['name'] as String: _session(spec),
  };
  final traces = {
    for (final entry in (handMade['traces'] as Map<String, Object?>).entries)
      entry.key: _trace(entry.value),
  };
  final segments = handMade['segments'] as Map<String, Object?>;
  final axis = cppAxis(handMade['axis'])!;
  final configuration = handMade['configuration'] as String;
  for (final item in (handMade['pairs'] as List).cast<Map<String, Object?>>()) {
    final what =
        'hand-made ${item['a']} ${item['traceA']} / ${item['b']} ${item['traceB']} ${item['segmentSet']}';
    test(what, () {
      final check = _Check(what);
      final analyzer = CornerAnalyzer(
        axis: axis,
        a: CornerAnalyzerLap(
          session: sessions[item['a']]!,
          trace: traces[item['traceA']]!,
          start: 0.0,
          end: 19.95,
          reference: 0,
        ),
        b: CornerAnalyzerLap(
          session: sessions[item['b']]!,
          trace: traces[item['traceB']]!,
          start: 0.0,
          end: 19.95,
          reference: 1,
        ),
        segmentation: ComparisonSegmentation(
          shared: approvedSegmentation(segments[item['segmentSet']], configuration),
        ),
      );
      _expectAnalyzer(check, analyzer, item);
      for (final range in (item['ranges'] as List).cast<Map<String, Object?>>()) {
        check.compare(
          'heart rate ${range['start']}..${range['end']}',
          _heartRateMap(analyzer.heartRate(_double(range['start']), _double(range['end']))),
          range['result'],
        );
      }
      check.done();
    });
  }
}

/// Checks everything [analyzer] shows against one segment set of the dump.
void _expectAnalyzer(_Check check, CornerAnalyzer analyzer, Map<String, Object?> want) {
  final segments = (want['segments'] as List).cast<Map<String, Object?>>();
  check.same('segment count', analyzer.segments.length, segments.length);
  if (analyzer.segments.length != segments.length) return;
  check.same('revision', analyzer.segmentation.shared?.revision, want['revision']);
  for (var i = 0; i < segments.length; ++i) {
    final expected = segments[i];
    final segment = analyzer.segments[i];
    final where = 'segment ${segment.id}';
    check.compare('$where row', _rowMap(segment), expected['row']);
    final analysis = analyzer.analyze(segment.id);
    check.compare('$where metrics', _metricsMap(analysis), expected['metrics']);
    check.compare(
      '$where heart rate',
      _heartRateMap(analyzer.heartRate(segment.startMeters, segment.endMeters)),
      expected['heartRate'],
    );
    if (analysis == null) {
      check.same('$where detail', expected['segmentSpeeds'], null);
      continue;
    }
    check.compare('$where segment speeds', [
      for (final speeds in analysis.segmentSpeeds) _segmentSpeedsMap(speeds),
    ], expected['segmentSpeeds']);
    check.same('$where corner', analysis.phases != null, expected['phases'] != null);
    if (analysis.phases == null || expected['phases'] == null) continue;
    check.compare('$where phases', _phasesMap(analysis.phases!), expected['phases']);
    check.compare('$where corner speeds', [
      for (final speeds in analysis.cornerSpeeds!) _cornerSpeedsMap(speeds),
    ], expected['cornerSpeeds']);
    check.compare('$where braking', [
      for (final braking in analysis.brakingMetrics!) _brakingMap(braking),
    ], expected['braking']);
    check.compare('$where exit', [
      for (final exit in analysis.exitMetrics!) _exitMap(exit),
    ], expected['exit']);
  }
  check.compare('unknown segment', _metricsMap(analyzer.analyze('not-a-real-id')), want['unknown']);
  check.compare('time loss', _timeLossMap(analyzer.timeLosses()), want['timeLoss']);
}

// --- The Dart results in the shape the C++ tool writes ----------------------

Map<String, Object?> _rowMap(ComparisonSegment segment) => {
  'id': segment.id,
  'name': segment.name,
  'type': segment.type,
  'startMeters': segment.startMeters,
  'endMeters': segment.endMeters,
};

Map<String, Object?> _valueMap(AnalyzerValue value) => {
  'provenance': value.provenance,
  if (value.value != null)
    'value': value.value
  else if (value.unavailableReason.isNotEmpty)
    'unavailableReason': value.unavailableReason,
};

Map<String, Object?> _deltaMap(AnalyzerDelta delta) => {
  if (delta.value != null)
    'value': delta.value
  else if (delta.unavailableReason.isNotEmpty)
    'unavailableReason': delta.unavailableReason,
};

Map<String, Object?> _metricMap(AnalyzerMetric metric) => {
  'a': _valueMap(metric.a),
  'b': _valueMap(metric.b),
  'delta': _deltaMap(metric.delta),
};

Map<String, Object?> _metricsMap(SegmentAnalysis? analysis) {
  if (analysis == null) return const {};
  final speeds = analysis.speeds;
  final corner = analysis.corner, braking = analysis.braking, exit = analysis.exitEffects;
  return {
    'segmentId': analysis.segmentId,
    'type': analysis.type,
    if (analysis.sectorTime != null) 'sectorTime': _metricMap(analysis.sectorTime!),
    'speeds': {
      'unit': speeds.unit,
      'entry': _metricMap(speeds.entry),
      'maximum': _metricMap(speeds.maximum),
      'minimum': _metricMap(speeds.minimum),
      'exit': _metricMap(speeds.exit),
    },
    if (corner != null)
      'corner': {
        'channel': corner.channel,
        'unit': corner.unit,
        'entry': _metricMap(corner.entry),
        'apex': _metricMap(corner.apex),
        'minimum': _metricMap(corner.minimum),
        'exit': _metricMap(corner.exit),
      },
    if (braking != null)
      'braking': {
        'point': _metricMap(braking.point),
        'seconds': _metricMap(braking.seconds),
        'peakDeceleration': _metricMap(braking.peakDeceleration),
      },
    if (exit != null)
      'exitEffects': {'pickup': _metricMap(exit.pickup), 'exitSpeed': _metricMap(exit.exitSpeed)},
  };
}

Map<String, Object?> _summaryMap(ChannelSummary summary) => {
  'valid': summary.valid,
  'sampleCount': summary.sampleCount,
  'excludedArtifacts': summary.excludedArtifacts,
  'coverage': summary.coverage,
  'coveredSeconds': summary.coveredSeconds,
  'startTime': summary.startTime,
  'endTime': summary.endTime,
  if (!summary.valid) 'unavailableReason': summary.unavailableReason,
  if (summary.valid) ...{
    'minimum': summary.minimum,
    'maximum': summary.maximum,
    'mean': summary.mean,
    'minimumTime': summary.minimumTime,
    'maximumTime': summary.maximumTime,
  },
};

Map<String, Object?> _heartRateMap(ComparisonHeartRate heartRate) {
  if (!heartRate.valid) return const {'valid': false};
  return {
    'valid': true,
    'algorithm': heartRate.algorithm,
    'laps': [
      for (final lap in heartRate.laps)
        lap.summary.unavailableReason == analyzerIncompleteCoverage
            ? {'valid': false, 'unavailableReason': analyzerIncompleteCoverage}
            : {..._summaryMap(lap.summary), 'channel': lap.channel},
    ],
    'startMeters': heartRate.startMeters,
    'endMeters': heartRate.endMeters,
    'crossesStartFinish': heartRate.crossesStartFinish,
  };
}

Map<String, Object?> _timeLossMap(ComparisonTimeLosses losses) {
  final observations = losses.observations;
  if (observations == null) return const {'valid': false};
  if (!observations.valid) {
    return {'valid': false, 'unavailableReason': observations.unavailableReason};
  }
  return {
    'valid': true,
    'algorithm': timeLossAlgorithm,
    'revision': observations.stamp.revision,
    'windows': [
      for (final window in observations.windows)
        {
          'segmentId': window.segmentId,
          'name': window.name,
          'type': window.type,
          'role': window.role,
          'startMeters': window.startProgressMeters,
          'endMeters': window.endProgressMeters,
          if (window.cornerSegmentId.isNotEmpty) 'cornerSegmentId': window.cornerSegmentId,
          if (window.incrementSeconds != null)
            'incrementSeconds': window.incrementSeconds
          else
            'unavailableReason': window.unavailableReason,
          if (window.cumulativeAtStartSeconds != null)
            'cumulativeAtStartSeconds': window.cumulativeAtStartSeconds,
          if (window.cumulativeAtEndSeconds != null)
            'cumulativeAtEndSeconds': window.cumulativeAtEndSeconds,
        },
    ],
    'allWindowsTimed': observations.allWindowsTimed,
    'timedIncrementSumSeconds': observations.timedIncrementSumSeconds,
    'lapDeltaSeconds': losses.lapDeltaSeconds,
  };
}

Map<String, Object?> _segmentSpeedsMap(SegmentSpeeds speeds) => {
  'entry': speeds.entry,
  'exit': speeds.exit,
  'maximum': speeds.maximum,
  'minimum': speeds.minimum,
  'reason': speeds.unavailableReason,
};

Map<String, Object?> _phaseMap(CornerPhasePoint point) => {
  'method': point.method,
  'progress': point.progressMeters,
  'tolerance': point.toleranceMeters,
  'uncertainty': point.uncertaintyReasons,
  'reason': point.unresolvedReason,
};

Map<String, Object?> _phasesMap(CornerGeometryPhases phases) => {
  'valid': phases.valid,
  'entry': _phaseMap(phases.entry),
  'apex': _phaseMap(phases.apex),
  'exit': _phaseMap(phases.exit),
  'candidates': phases.apexCandidatesMeters,
};

Map<String, Object?> _speedMap(CornerSpeedValue value) => {
  'value': value.value,
  'progress': value.progressMeters,
  'time': value.telemetryTime,
  'reason': value.unavailableReason,
  'limitations': value.limitations,
};

Map<String, Object?> _cornerSpeedsMap(CornerSpeeds speeds) => {
  'valid': speeds.valid,
  'channel': speeds.channel,
  'unit': speeds.unit,
  'provenance': speeds.provenance,
  'entry': _speedMap(speeds.entry),
  'apex': _speedMap(speeds.apex),
  'minimum': _speedMap(speeds.minimum),
  'exit': _speedMap(speeds.exit),
  'lengthMeters': speeds.lengthMeters,
  'coveredMeters': speeds.coveredMeters,
  'spacing': speeds.meanSampleSpacingMeters,
};

Map<String, Object?> _brakingMap(BrakingMetrics braking) => {
  'valid': braking.valid,
  'intervalStart': braking.intervalStartMeters,
  'intervalEnd': braking.intervalEndMeters,
  'entry': braking.entryMeters,
  'reason': braking.unavailableReason,
  'method': braking.method,
  'provenance': braking.provenance,
  'channel': braking.channel,
  'point': braking.brakingPointMeters,
  'pointTime': braking.brakingPointTime,
  'beforeEntry': braking.distanceBeforeEntryMeters,
  'seconds': braking.brakingSeconds,
  'distance': braking.brakingDistanceMeters,
  'limitations': braking.limitations,
  'decelerationUnit': braking.decelerationUnit,
  'peak': braking.peakDeceleration,
  'mean': braking.meanDeceleration,
  'decelerationReason': braking.decelerationUnavailableReason,
};

Map<String, Object?> _exitMap(ExitMetrics exit) => {
  'valid': exit.valid,
  'pickup': {
    'method': exit.pickup.method,
    'provenance': exit.pickup.provenance,
    'channel': exit.pickup.channel,
    'progress': exit.pickup.progressMeters,
    'time': exit.pickup.telemetryTime,
    'reason': exit.pickup.unavailableReason,
    'limitations': exit.pickup.limitations,
  },
  'source': exit.intervalSource,
  'intervalStart': exit.intervalStartMeters,
  'intervalEnd': exit.intervalEndMeters,
  'exitSpeed': exit.exitSpeed,
  'endSpeed': exit.intervalEndSpeed,
  'elapsed': exit.elapsedSeconds,
  'reason': exit.downstreamUnavailableReason,
};

// --- Inputs ------------------------------------------------------------------

TelemetrySession _session(Map<String, Object?> spec) {
  final channels = <String, TelemetryChannel>{};
  for (final channel in (spec['channels'] as List).cast<Map<String, Object?>>()) {
    final times = (channel['times'] as List).cast<num>();
    final values = (channel['values'] as List).cast<num?>();
    channels[channel['name'] as String] = TelemetryChannel(
      name: channel['name'] as String,
      unit: channel['unit'] as String,
      timestamps: Float64List.fromList([for (final time in times) time.toDouble()]),
      values: Float32List.fromList([for (final value in values) value?.toDouble() ?? double.nan]),
    );
  }
  return TelemetrySession(
    duration: 19.95,
    startTime: 0,
    metadata: const {},
    channels: channels,
    aliases: (spec['aliases'] as Map<String, Object?>).cast<String, String>(),
    warnings: const [],
    timingGates: const [],
    sampleCount: 400,
  );
}

List<ProgressSegment> _trace(Object? value) => [
  for (final segment in (value as List).cast<List<Object?>>())
    ProgressSegment([
      for (final sample in segment.cast<List<Object?>>())
        ProjectedSample(_double(sample[0]), progressMeters: _double(sample[1]), valid: true),
    ]),
];

double _double(Object? value) => (value as num).toDouble();

/// The axis written by the dump, or null.
ProgressAxis? cppAxis(Object? value) {
  if (value is! Map<String, Object?>) return null;
  return ProgressAxis(
    points: [
      for (final point in (value['points'] as List).cast<List<Object?>>())
        MetricPoint(_double(point[0]), _double(point[1])),
    ],
    cumulative: [for (final item in (value['cumulative'] as List)) _double(item)],
    lengthMeters: _double(value['lengthMeters']),
    spacingMeters: _double(value['spacingMeters']),
    origin: GeoCoordinate(_double(value['originLatitude']), _double(value['originLongitude'])),
    valid: value['valid'] != false,
  );
}

/// Collects every difference of one test, then fails once with all of them.
final class _Check {
  _Check(this.what, [List<String>? failures]) : failures = failures ?? [];

  final String what;
  final List<String> failures;

  _Check at(String where) => _Check('$what $where', failures);

  void _fail(String message) {
    ++_mismatched;
    if (failures.length < 40) failures.add('$what $message');
  }

  void same(String where, Object? actual, Object? expected) {
    ++_compared;
    if (actual != expected) _fail('$where: $actual, expected $expected');
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
    if (!(difference <= max(1e-9, 1e-9 * value.abs()))) _fail('$where: $actual, expected $value');
  }

  /// [actual] (maps, lists, numbers, strings, booleans and nulls) against
  /// [expected] as the tool wrote it.
  void compare(String where, Object? actual, Object? expected) {
    if (expected is Map) {
      if (actual is! Map) return _fail('$where: $actual, expected $expected');
      final keys = {...actual.keys.cast<String>()}, wanted = {...expected.keys.cast<String>()};
      if (keys.length != wanted.length || !keys.containsAll(wanted)) {
        return _fail('$where: keys $keys, expected $wanted');
      }
      for (final key in wanted) {
        compare('$where.$key', actual[key], expected[key]);
      }
      return;
    }
    if (expected is List) {
      if (actual is! List || actual.length != expected.length) {
        return _fail('$where: $actual, expected $expected');
      }
      for (var i = 0; i < expected.length; ++i) {
        compare('$where[$i]', actual[i], expected[i]);
      }
      return;
    }
    if (expected is num && actual is num) return number(where, actual.toDouble(), expected);
    if (expected == null && actual is double && !actual.isFinite) return same(where, null, null);
    same(where, actual, expected);
  }

  void done() {
    if (failures.isNotEmpty) fail(failures.join('\n'));
  }
}
