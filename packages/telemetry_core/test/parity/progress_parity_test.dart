// Compares the Dart track-progress port (TelemetrySession.sampledSegments and
// analysis/track_progress.dart) with FlappedEar Overlays' C++ implementation
// over the synthetic parity corpus.
//
// test/parity/progress_reference.json is the output of tool/cpp_progress_dump
// run over test/parity/corpus/*.vbo and test/fixtures/*.vbo (see
// tool/README.md); it holds every file with lap traces. Counts and indices
// must match exactly. Values derived through trigonometry may differ in the
// last bits between C libraries, so doubles are compared to 1e-9 relative
// (1e-9 absolute near zero).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

// Must match tool/cpp_progress_dump/main.cpp.
const _axisStride = 50;
const _featureStride = 50;
const _projectionStride = 25;
const _deltaStride = 50;
const _sampledStride = 10;

void main() {
  final reference = jsonDecode(
    File('test/parity/progress_reference.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final files = (reference['files'] as List).cast<Map<String, dynamic>>();

  test('the reference covers every corpus and fixture file with lap traces', () {
    final withTraces = <String>{};
    for (final file in [
      ...Directory('test/parity/corpus').listSync(),
      ...Directory('test/fixtures').listSync(),
    ].whereType<File>().where((f) => f.path.endsWith('.vbo'))) {
      final LapSession laps;
      try {
        laps = deriveSourceLapSession(parseVboFile(file.path));
      } on Exception {
        continue;
      }
      if (laps.lapTraces.isNotEmpty && laps.selectedStartGate != null) {
        withTraces.add(file.uri.pathSegments.last);
      }
    }
    expect(files.map((f) => f['file']).toSet(), withTraces);
  });

  for (final entry in files) {
    final name = entry['file'] as String;
    test(name, () {
      final path = File('test/parity/corpus/$name').existsSync()
          ? 'test/parity/corpus/$name'
          : 'test/fixtures/$name';
      final session = parseVboFile(path);
      final laps = deriveSourceLapSession(session);
      final gate = laps.selectedStartGate!;
      final origin = GeoCoordinate(
        (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
        (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
      );
      final eligible = {
        for (final lap in laps.timedLaps)
          if (lap.referenceEligible) lap.number,
      };
      final referenceTrace = laps.lapTraces.firstWhere(
        (trace) => eligible.contains(trace.lapNumber),
      );
      expect(referenceTrace.lapNumber, entry['referenceLap']);

      final sampled = (entry['sampled'] as List).cast<Map<String, dynamic>>();
      for (final expected in sampled) {
        _expectSampled(
          session.sampledSegments(
            expected['channel'] as String,
            _double(expected['start']),
            _double(expected['end']),
            expected['maximumPoints'] as int,
          ),
          expected,
        );
      }

      final axis = buildProgressAxis(referenceTrace, origin, gate);
      _expectAxis(axis, entry['axis'] as Map<String, dynamic>);
      _expectFeatures(computeTrackFeatures(axis, 15.0), entry['features'] as Map<String, dynamic>);

      final projections = (entry['projections'] as List).cast<Map<String, dynamic>>();
      expect(laps.timedLaps, hasLength(projections.length));
      final projected = <List<ProgressSegment>>[];
      for (var i = 0; i < laps.timedLaps.length; ++i) {
        final lap = laps.timedLaps[i];
        final segments = projectLapTrace(
          axis,
          session,
          lap.startTelemetryTime,
          lap.endTelemetryTime,
        );
        projected.add(segments);
        _expectProjection(lap, segments, projections[i]);
      }

      final delta = entry['delta'] as Map<String, dynamic>?;
      expect(laps.fastestLapIndex, entry['fastestLapIndex']);
      if (delta != null) {
        _expectDelta(
          computeDeltaSeries(projected.first, projected[laps.fastestLapIndex!], 5.0),
          delta,
        );
        final first = laps.timedLaps.first, fastest = laps.timedLaps[laps.fastestLapIndex!];
        _expectDelta(
          computeTimedDeltaSeries(
            projected.first,
            projected[laps.fastestLapIndex!],
            5.0,
            DeltaTiming(
              lapStartA: first.startTelemetryTime,
              lapEndA: first.endTelemetryTime,
              lapStartB: fastest.startTelemetryTime,
              lapEndB: fastest.endTelemetryTime,
              lengthMeters: axis.lengthMeters,
            ),
          ),
          entry['timedDelta'] as Map<String, dynamic>,
        );
      }
    });
  }
}

void _expectSampled(List<List<SamplePoint>> actual, Map<String, dynamic> expected) {
  final what = '${expected['channel']} ${expected['start']}..${expected['end']}';
  expect(actual.map((s) => s.length).toList(), expected['segmentSizes'], reason: what);
  final points = (expected['points'] as List).cast<List<dynamic>>();
  var ordinal = 0;
  var p = 0;
  for (var s = 0; s < actual.length; ++s) {
    for (var i = 0; i < actual[s].length; ++i, ++ordinal) {
      if (ordinal % _sampledStride != 0) continue;
      expect([s, i], [points[p][0], points[p][1]], reason: what);
      // Samples are copied, not computed: they match exactly.
      expect(actual[s][i].time, _double(points[p][2]), reason: what);
      expect(actual[s][i].value, _double(points[p][3]), reason: what);
      ++p;
    }
  }
  expect(p, points.length, reason: what);
}

void _expectAxis(ProgressAxis axis, Map<String, dynamic> expected) {
  expect(axis.valid, expected['valid']);
  expect(axis.points, hasLength(expected['pointCount'] as int));
  _close(axis.lengthMeters, expected['lengthMeters'], absolute: 1e-9);
  _close(axis.spacingMeters, expected['spacingMeters'], absolute: 1e-9);
  final points = (expected['points'] as List).cast<List<dynamic>>();
  var p = 0;
  for (var i = 0; i < axis.points.length; i += _axisStride, ++p) {
    expect(i, points[p][0]);
    _close(axis.points[i].eastMeters, points[p][1], absolute: 1e-9);
    _close(axis.points[i].northMeters, points[p][2], absolute: 1e-9);
    _close(axis.cumulative[i], points[p][3], absolute: 1e-9);
  }
  expect(p, points.length);
}

void _expectFeatures(TrackFeatures features, Map<String, dynamic> expected) {
  expect(features.valid, expected['valid']);
  expect(features.samples, hasLength(expected['sampleCount'] as int));
  _close(features.smoothingMeters, expected['smoothingMeters'], absolute: 1e-9);
  final samples = (expected['samples'] as List).cast<List<dynamic>>();
  var p = 0;
  for (var i = 0; i < features.samples.length; i += _featureStride, ++p) {
    final sample = features.samples[i];
    expect(i, samples[p][0]);
    _close(sample.progressMeters, samples[p][1], absolute: 1e-9);
    _close(sample.headingRadians, samples[p][2], absolute: 1e-9);
    _close(sample.curvaturePerMeter, samples[p][3], absolute: 1e-9);
  }
  expect(p, samples.length);
}

void _expectProjection(
  TimedLap lap,
  List<ProgressSegment> segments,
  Map<String, dynamic> expected,
) {
  final what = 'lap ${lap.number}';
  expect(lap.number, expected['lapNumber']);
  final expectedSegments = (expected['segments'] as List).cast<Map<String, dynamic>>();
  expect(
    segments.map((s) => s.samples.length).toList(),
    expectedSegments.map((s) => s['sampleCount']).toList(),
    reason: what,
  );
  for (var s = 0; s < segments.length; ++s) {
    final samples = segments[s].samples;
    final want = expectedSegments[s];
    void expectSample(ProjectedSample sample, List<dynamic> values) {
      expect(sample.valid, isTrue);
      _close(sample.telemetryTime, values[0], absolute: 1e-9);
      _close(sample.progressMeters, values[1], absolute: 1e-9);
    }

    expectSample(samples.first, want['first'] as List<dynamic>);
    expectSample(samples.last, want['last'] as List<dynamic>);
    final every = (want['samples'] as List).cast<List<dynamic>>();
    var p = 0;
    for (var i = 0; i < samples.length; i += _projectionStride, ++p) {
      expect(i, every[p][0], reason: what);
      expectSample(samples[i], every[p].sublist(1));
    }
    expect(p, every.length, reason: what);
  }
  for (final row in (expected['timeAtProgress'] as List).cast<List<dynamic>>()) {
    _closeOrNull(timeAtProgress(segments, _double(row[0])), row[1], '$what time at ${row[0]}');
  }
  for (final row in (expected['progressAtTime'] as List).cast<List<dynamic>>()) {
    _closeOrNull(progressAtTime(segments, _double(row[0])), row[1], '$what progress at ${row[0]}');
  }
}

void _expectDelta(List<List<DeltaPoint>> series, Map<String, dynamic> expected) {
  final expectedSeries = (expected['series'] as List).cast<Map<String, dynamic>>();
  expect(series.map((s) => s.length).toList(), expectedSeries.map((s) => s['pointCount']).toList());
  for (var s = 0; s < series.length; ++s) {
    final points = series[s];
    final want = expectedSeries[s];
    void expectPoint(DeltaPoint point, List<dynamic> values) {
      _close(point.progressMeters, values[0], absolute: 1e-9);
      _close(point.deltaSeconds, values[1], absolute: 1e-9);
    }

    expectPoint(points.first, want['first'] as List<dynamic>);
    expectPoint(points.last, want['last'] as List<dynamic>);
    final every = (want['points'] as List).cast<List<dynamic>>();
    var p = 0;
    for (var i = 0; i < points.length; i += _deltaStride, ++p) {
      expect(i, every[p][0]);
      expectPoint(points[i], every[p].sublist(1));
    }
    expect(p, every.length);
  }
}

double _double(Object? value) => (value as num).toDouble();

void _closeOrNull(double? actual, Object? expected, String reason) {
  if (expected == null) {
    expect(actual, isNull, reason: reason);
  } else {
    expect(actual, isNotNull, reason: reason);
    _close(actual!, expected, absolute: 1e-9);
  }
}

void _close(double actual, Object? expected, {double absolute = 0.0}) {
  final value = _double(expected);
  final tolerance = [absolute, 1e-9 * value.abs()].reduce((a, b) => a > b ? a : b);
  if (tolerance == 0.0) {
    expect(actual, value);
  } else {
    expect(actual, closeTo(value, tolerance));
  }
}
