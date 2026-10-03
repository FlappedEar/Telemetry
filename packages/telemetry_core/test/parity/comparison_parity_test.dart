// Compares the Dart A/B comparison, map layers and lap-chart port
// (analysis/lap_comparison.dart, analysis/map_layers.dart and
// analysis/lap_charts.dart) with FlappedEar Overlays' C++ implementation
// over the synthetic parity corpus and fixed cases.
//
// test/parity/comparison_reference.json is the output of
// tool/cpp_comparison_dump run over test/parity/corpus/*.vbo and
// test/fixtures/*.vbo (see tool/README.md). Counts, names, reasons, states
// and indices must match exactly; doubles to 1e-9 relative (1e-9 absolute
// near zero), as in the other parity tests.
//
// FET_COMPARISON_REFERENCE and FET_COMPARISON_DIRS (colon-separated) run the
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
      Platform.environment['FET_COMPARISON_REFERENCE'] ?? 'test/parity/comparison_reference.json';
  final directories =
      (Platform.environment['FET_COMPARISON_DIRS'] ?? 'test/parity/corpus:test/fixtures').split(
        ':',
      );
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final strides = reference['strides'] as Map<String, Object?>;
  final seriesStride = strides['series'] as int;
  final mapStride = strides['map'] as int;
  final pairs = (reference['pairs'] as List).cast<Map<String, Object?>>();
  final cases = reference['cases'] as Map<String, Object?>;

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

  final recordings = <String, (TelemetrySession, LapSession)>{};
  (TelemetrySession, LapSession) recording(String name) => recordings.putIfAbsent(name, () {
    final session = parseVboFile(pathOf(name));
    return (session, deriveSourceLapSession(session));
  });

  test(
    'the reference covers pairs in files and across files, layers and cases',
    skip: Platform.environment.containsKey('FET_COMPARISON_REFERENCE')
        ? 'another reference'
        : false,
    () {
      expect(pairs.length, greaterThanOrEqualTo(30));
      expect(pairs.where((pair) => pair['fileA'] != pair['fileB']), isNotEmpty);
      expect(pairs.where((pair) => pair['axisValid'] == false), isNotEmpty);
      final reasons = {
        for (final pair in pairs)
          for (final layer in (pair['mapLayers'] as List? ?? const []).cast<Map<String, Object?>>())
            layer['reason'],
      };
      expect(reasons, containsAll(['', 'channelMissing', 'unknownLayer', 'pairNotReady']));
      expect((cases['runs'] as List).length, 3);
    },
  );

  for (final pair in pairs) {
    final what = '${pair['fileA']} ${pair['lapA']} / ${pair['fileB']} ${pair['lapB']}';
    test(what, () {
      final check = _Check(what);
      final (sessionA, lapsA) = recording(pair['fileA'] as String);
      final (sessionB, lapsB) = recording(pair['fileB'] as String);
      ComparisonLap? lap(TelemetrySession session, LapSession laps, Object? number) {
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

      final a = lap(sessionA, lapsA, pair['lapA']), b = lap(sessionB, lapsB, pair['lapB']);
      check.same('missing', a == null || b == null, pair['missing']);
      if (a == null || b == null) return;
      final comparison = LapComparison(a, b);
      check.number('startA', a.start, pair['startA']);
      check.number('endB', b.end, pair['endB']);
      check.same('axisValid', comparison.axis.valid, pair['axisValid']);
      check.number('axisLength', comparison.axisLengthMeters, pair['axisLength']);
      check.same('traceSizes', [
        comparison.trace(0).length,
        comparison.trace(1).length,
      ], pair['traceSizes']);
      check.same('availableChannels', comparison.availableChannels, pair['availableChannels']);
      check.same('preferredChannels', comparison.preferredChannels, pair['preferredChannels']);
      check.geometry('geometry', comparison.geometry, pair['geometry']);
      final overlay = (pair['overlay'] as List).cast<Map<String, Object?>>();
      for (final slot in [0, 1]) {
        check.track('overlay $slot', comparison.overlayTrack(slot), overlay[slot], mapStride);
      }

      for (final expected in (pair['delta'] as List).cast<Map<String, Object?>>()) {
        check.series(
          'delta ${expected['start']}..${expected['end']}/${expected['maximumPoints']}',
          comparison.deltaSeries(
            _double(expected['start']),
            _double(expected['end']),
            expected['maximumPoints'] as int,
          ),
          expected,
          seriesStride,
        );
      }
      for (final expected in (pair['channelSeries'] as List).cast<Map<String, Object?>>()) {
        check.series(
          'channel ${expected['channel']} ${expected['slot']} ${expected['start']}..${expected['end']}',
          comparison.channelSeries(
            expected['slot'] as int,
            expected['channel'] as String,
            _double(expected['start']),
            _double(expected['end']),
            expected['maximumPoints'] as int,
          ),
          expected,
          seriesStride,
        );
      }
      for (final row in (pair['positions'] as List).cast<List<Object?>>()) {
        final progress = _double(row[0]);
        for (final slot in [0, 1]) {
          final where = 'position $slot at $progress';
          check.point(where, comparison.positionAt(slot, progress), row[1 + slot * 2]);
          check.optional('$where time', comparison.timeAt(slot, progress), row[2 + slot * 2]);
        }
      }

      final options = comparison.mapLayerOptions;
      final expectedOptions = (pair['mapLayerOptions'] as List).cast<Map<String, Object?>>();
      check.same(
        'option ids',
        [for (final option in options) option.id],
        [for (final option in expectedOptions) option['id']],
      );
      for (var i = 0; i < min(options.length, expectedOptions.length); ++i) {
        check.same(
          'option ${options[i].id}',
          [options[i].label, options[i].available, options[i].temperature],
          [
            expectedOptions[i]['label'],
            expectedOptions[i]['available'],
            expectedOptions[i]['temperature'],
          ],
        );
      }
      for (final expected in (pair['mapLayers'] as List).cast<Map<String, Object?>>()) {
        final id = expected['requestedId'] as String, slot = expected['requestedSlot'] as int;
        check.layer('layer $id $slot', comparison.mapLayer(id, slot), expected, mapStride);
      }

      final lapPage = pair['lap'] as Map<String, Object?>;
      check.same(
        'lap channels',
        lapChartChannels(sessionA, includePedals: false),
        lapPage['channels'],
      );
      for (final expected in (lapPage['series'] as List).cast<Map<String, Object?>>()) {
        check.series(
          'lap ${expected['channel']} ${expected['start']}..${expected['end']}',
          timeSeries(
            sessionA,
            expected['channel'] as String,
            _double(expected['start']),
            _double(expected['end']),
            expected['maximumPoints'] as int,
          ),
          expected,
          seriesStride,
        );
      }
      final lapGeometry = lapMapGeometry(sessionA, a.start, a.end);
      check.geometry('lap geometry', lapGeometry, lapPage['geometry']);
      check.track(
        'lap track',
        mapTrace(sessionA, a.start, a.end, lapGeometry),
        lapPage['track'],
        mapStride,
      );
      final cursorChannels = (lapPage['cursorChannels'] as List).cast<String>();
      for (final row in (lapPage['cursor'] as List).cast<List<Object?>>()) {
        final time = _double(row[0]);
        for (var i = 0; i < cursorChannels.length; ++i) {
          check.optional(
            'cursor ${cursorChannels[i]} $time',
            sessionA.valueAt(cursorChannels[i], time),
            row[1 + i],
          );
        }
        check.point('cursor point $time', mapPointAt(sessionA, time, lapGeometry), row.last);
      }
      check.done();
    });
  }

  for (final run in (cases['runs'] as List).cast<Map<String, Object?>>()) {
    test('map layers of a hand-made ${run['name']} run', () {
      final check = _Check('${run['name']}');
      final gpsGap = run['gpsGap'] as bool, westPositive = run['westPositive'] as bool;
      bool present(double t) => !gpsGap || t < 3.0 || t > 5.0;
      final session = _straightRun(present, westPositive);
      final trace = _straightTrace(present);
      final geometry = sessionMapGeometry(session);
      check.geometry('geometry', geometry, run['geometry']);
      for (final along in (run['along'] as List).cast<Map<String, Object?>>()) {
        final where = 'along ${along['channel']} ${along['length']} ${along['points']}';
        final values = channelAlongProgress(
          session,
          along['channel'] as String,
          trace,
          along['length'] == null ? double.nan : _double(along['length']),
          along['points'] as int,
          along['temperature'] == true ? temperatureSummaryPolicy : const ChannelSummaryPolicy(),
        );
        final expected = (along['values'] as List).cast<List<Object?>>();
        check.same('$where runs', values.length, expected.length);
        for (var s = 0; s < min(values.length, expected.length); ++s) {
          final points = expected[s].cast<List<Object?>>();
          check.same('$where run $s size', values[s].length, points.length);
          for (var i = 0; i < min(values[s].length, points.length); ++i) {
            check.number('$where $s/$i progress', values[s][i].progress, points[i][0]);
            check.number('$where $s/$i value', values[s][i].value, points[i][1]);
          }
        }
        check.trace('$where layer', placeOnMap(session, trace, geometry, values), along['layer']);
      }
      final handMade = [
        <ProgressValue>[
          (progress: 0.0, value: 1.0),
          (progress: 50.0, value: 2.0),
          (progress: 100.0, value: double.nan),
          (progress: 150.0, value: 3.0),
          (progress: 190.0, value: 4.0),
          (progress: 400.0, value: 5.0),
        ],
        <ProgressValue>[(progress: 10.0, value: 7.0)],
        <ProgressValue>[(progress: 20.0, value: -1.0), (progress: 30.0, value: -2.0)],
      ];
      check.trace('hand-made', placeOnMap(session, trace, geometry, handMade), run['handMade']);
      final oil = session.channels['oil_temp']!, speed = session.channels['velocity']!;
      for (final row in (run['plausible'] as List).cast<List<Object?>>()) {
        final time = _double(row[0]);
        if (row[1] == 'speed') {
          check.optional(
            'speed at $time',
            plausibleChannelValue(speed, time, const ChannelSummaryPolicy(), false),
            row[2],
          );
          continue;
        }
        final policy = row[1] == true ? temperatureSummaryPolicy : const ChannelSummaryPolicy();
        check.optional(
          'oil at $time ${row[1]}',
          plausibleChannelValue(oil, time, policy, zeroIsPlaceholder(oil, policy)),
          row[2],
        );
      }
      for (final row in (run['trackPoints'] as List).cast<List<Object?>>()) {
        check.point('point ${row[0]}', mapPointAt(session, _double(row[0]), geometry), row[1]);
      }
      check.track('track', mapTrace(session, 0, 10, geometry), run['track'], mapStride);
      check.geometry('shared', sharedMapGeometry(session, 0, 5, session, 5, 10), run['shared']);
      check.done();
    });
  }
}

// MapLayersTests.cpp's straight run east at 20 m/s, as the tool writes it.
TelemetrySession _straightRun(bool Function(double) gpsPresent, bool westPositive) {
  TelemetryChannel channel(
    String name,
    String unit,
    double Function(double) value, [
    bool Function(double)? present,
  ]) {
    final times = <double>[], values = <double>[];
    for (var k = 0; k < 101; ++k) {
      final t = k * 0.1;
      if (present != null && !present(t)) continue;
      times.add(t);
      values.add(value(t));
    }
    return TelemetryChannel(
      name: name,
      unit: unit,
      timestamps: Float64List.fromList(times),
      values: Float32List.fromList(values),
    );
  }

  double temperature(double t) {
    if ((t - 3.0).abs() < 1e-6) return 0.0;
    if ((t - 7.0).abs() < 1e-6) return 900.0;
    return 90.0;
  }

  final sign = westPositive ? -1.0 : 1.0;
  return TelemetrySession(
    duration: 10,
    startTime: 0,
    metadata: {if (westPositive) 'gpsLongitudeConvention': 'west-positive'},
    channels: {
      'lat': channel('lat', 'deg', (t) => 50.0, gpsPresent),
      'lon': channel('lon', 'deg', (t) => 19.0 + sign * t * 20.0 / 71500.0, gpsPresent),
      'velocity': channel('velocity', 'km/h', (t) => 60.0 + t, (t) => t < 4.0 || t > 6.0),
      'oil_temp': channel('oil_temp', 'C', temperature),
    },
    aliases: const {'latitude': 'lat', 'longitude': 'lon', 'speed': 'velocity'},
    warnings: const [],
    timingGates: const [],
    sampleCount: 101,
  );
}

List<ProgressSegment> _straightTrace(bool Function(double) present) {
  final trace = [ProgressSegment()];
  for (var k = 0; k < 101; ++k) {
    final t = k * 0.1;
    if (!present(t)) {
      if (trace.last.samples.isNotEmpty) trace.add(ProgressSegment());
      continue;
    }
    trace.last.samples.add(ProjectedSample(t, progressMeters: t * 20.0, valid: true));
  }
  if (trace.last.samples.isEmpty) trace.removeLast();
  return trace;
}

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

  void point(String where, MapPoint? actual, Object? expected) {
    if (actual == null || expected == null) {
      same('$where present', actual != null, expected != null);
      return;
    }
    final values = expected as List;
    number('$where x', actual.x, values[0]);
    number('$where y', actual.y, values[1]);
  }

  void geometry(String where, MapGeometry actual, Object? expected) {
    final want = expected as Map<String, Object?>;
    same('$where valid', actual.valid, want['valid']);
    same('$where westPositive', actual.longitudeIsWestPositive, want['westPositive']);
    if (!actual.valid) return;
    same('$where points', actual.pointCount, want['pointCount']);
    number('$where minimumX', actual.minimumX, want['minimumX']);
    number('$where minimumY', actual.minimumY, want['minimumY']);
    number('$where width', actual.width, want['width']);
    number('$where height', actual.height, want['height']);
    number('$where centerX', actual.centerX, want['centerX']);
    number('$where centerY', actual.centerY, want['centerY']);
    number('$where scale', actual.normalizationScale, want['scale']);
    number('$where originLatitude', actual.originLatitude, want['originLatitude']);
    number('$where originLongitude', actual.originLongitude, want['originLongitude']);
  }

  void track(String where, List<List<MapPoint>> actual, Object? expected, int stride) {
    final want = expected as Map<String, Object?>;
    same('$where sizes', [for (final run in actual) run.length], want['segmentSizes']);
    final points = (want['points'] as List).cast<List<Object?>>();
    var p = 0;
    for (var s = 0; s < actual.length; ++s) {
      for (var i = 0; i < actual[s].length; ++i) {
        if (i % stride != 0 && i != actual[s].length - 1) continue;
        if (p >= points.length) {
          _fail('$where: more points than expected');
          return;
        }
        same('$where index', [s, i], [points[p][0], points[p][1]]);
        number('$where $s/$i x', actual[s][i].x, points[p][2]);
        number('$where $s/$i y', actual[s][i].y, points[p][3]);
        ++p;
      }
    }
    same('$where point count', p, points.length);
  }

  void series(String where, ChartSeries actual, Map<String, Object?> expected, int stride) {
    same('$where reason', actual.reason, expected['reason']);
    same('$where empty', !actual.hasData, expected['empty']);
    if (expected['empty'] == true || !actual.hasData) return;
    same('$where sizes', [
      for (final segment in actual.segments) segment.length,
    ], expected['segmentSizes']);
    number('$where minimum', actual.minimum, expected['minimum']);
    number('$where maximum', actual.maximum, expected['maximum']);
    same('$where unit', actual.unit, expected['unit']);
    same('$where brakingUp', actual.brakingUp, expected['brakingUp']);
    final points = (expected['points'] as List).cast<List<Object?>>();
    var p = 0;
    for (var s = 0; s < actual.segments.length; ++s) {
      final segment = actual.segments[s];
      for (var i = 0; i < segment.length; ++i) {
        if (i % stride != 0 && i != segment.length - 1) continue;
        if (p >= points.length) {
          _fail('$where: more points than expected');
          return;
        }
        same('$where index', [s, i], [points[p][0], points[p][1]]);
        number('$where $s/$i x', segment[i].x, points[p][2]);
        number('$where $s/$i y', segment[i].y, points[p][3]);
        ++p;
      }
    }
    same('$where point count', p, points.length);
  }

  void layer(String where, ComparisonMapLayer actual, Map<String, Object?> expected, int stride) {
    same('$where valid', actual.valid, expected['valid']);
    same('$where reason', actual.reason, expected['reason']);
    final known = expected['reason'] != 'unknownLayer' && expected['reason'] != 'pairNotReady';
    if (known) {
      same(
        '$where fields',
        [
          actual.id,
          actual.label,
          actual.scale,
          actual.negativeLabel,
          actual.positiveLabel,
          actual.algorithm,
          actual.slot,
        ],
        [
          expected['id'],
          expected['label'],
          expected['scale'],
          expected['negativeLabel'],
          expected['positiveLabel'],
          expected['algorithm'],
          expected['slot'],
        ],
      );
    }
    if (expected['reason'] == '' || expected['reason'] == 'noSamples') {
      same(
        '$where source',
        [actual.channel, actual.unit, actual.provenance],
        [expected['channel'], expected['unit'], expected['provenance']],
      );
    }
    if (expected['valid'] != true || !actual.valid) return;
    number('$where minimum', actual.trace.minimum!, expected['minimum']);
    number('$where maximum', actual.trace.maximum!, expected['maximum']);
    final polylines = actual.trace.polylines;
    same('$where sizes', [for (final line in polylines) line.length], expected['polylineSizes']);
    final points = (expected['points'] as List).cast<List<Object?>>();
    var p = 0;
    for (var l = 0; l < polylines.length; ++l) {
      for (var i = 0; i < polylines[l].length; ++i) {
        if (i % stride != 0 && i != polylines[l].length - 1) continue;
        if (p >= points.length) {
          _fail('$where: more points than expected');
          return;
        }
        final point = polylines[l][i];
        same('$where index', [l, i], [points[p][0], points[p][1]]);
        number('$where $l/$i x', point.x, points[p][2]);
        number('$where $l/$i y', point.y, points[p][3]);
        number('$where $l/$i value', point.value, points[p][4]);
        ++p;
      }
    }
    same('$where point count', p, points.length);
  }

  void trace(String where, MapLayerTrace actual, Object? expected) {
    final want = expected as Map<String, Object?>;
    optional('$where minimum', actual.minimum, want['minimum']);
    optional('$where maximum', actual.maximum, want['maximum']);
    final polylines = (want['polylines'] as List).cast<List<Object?>>();
    same('$where polylines', actual.polylines.length, polylines.length);
    for (var l = 0; l < min(actual.polylines.length, polylines.length); ++l) {
      final points = polylines[l].cast<List<Object?>>();
      same('$where $l size', actual.polylines[l].length, points.length);
      for (var i = 0; i < min(actual.polylines[l].length, points.length); ++i) {
        final point = actual.polylines[l][i];
        number('$where $l/$i x', point.x, points[i][0]);
        number('$where $l/$i y', point.y, points[i][1]);
        number('$where $l/$i value', point.value, points[i][2]);
      }
    }
  }

  void done() => expect(failures, isEmpty, reason: what);
}
