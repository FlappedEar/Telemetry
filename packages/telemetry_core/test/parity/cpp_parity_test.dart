// Compares the Dart parser and lap timing with FlappedEar Overlays' C++
// implementation, file by file, over the synthetic parity corpus.
//
// test/parity/cpp_reference.json is the output of tool/cpp_reference_dump run
// over test/parity/corpus/*.vbo and test/fixtures/*.vbo (see tool/README.md).
// Parsed values must match exactly. Values derived through trigonometry may
// differ in the last bits between C libraries, so they are compared to 1e-9
// relative.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'departures.dart';

void main() {
  final reference =
      jsonDecode(File('test/parity/cpp_reference.json').readAsStringSync()) as Map<String, dynamic>;
  final files = (reference['files'] as List).cast<Map<String, dynamic>>();

  test('the reference covers every corpus and fixture file', () {
    final onDisk = [
      ...Directory('test/parity/corpus').listSync(),
      ...Directory('test/fixtures').listSync(),
    ].whereType<File>().where((f) => f.path.endsWith('.vbo')).map((f) => f.uri.pathSegments.last);
    expect(files.map((f) => f['file']).toSet(), onDisk.toSet());
  });

  for (final entry in files) {
    final name = entry['file'] as String;
    test(name, () {
      final path = File('test/parity/corpus/$name').existsSync()
          ? 'test/parity/corpus/$name'
          : 'test/fixtures/$name';
      if (refusedByTelemetry(name)) {
        expect(() => parseVboFile(path), throwsA(isA<VboParseError>()));
        return;
      }
      final error = entry['error'] as Map<String, dynamic>?;
      if (error != null) {
        expect(
          () => parseVboFile(path),
          throwsA(
            predicate(
              (Object e) =>
                  e.runtimeType.toString() == error['type'] && e.toString() == error['message'],
            ),
          ),
        );
        return;
      }
      final session = parseVboFile(path);
      _expectSession(session, entry['session'] as Map<String, dynamic>);
      _expectLaps(deriveSourceLapSession(session), entry['laps'] as Map<String, dynamic>);
    });
  }

  test('formatLapTime', () {
    for (final row in (reference['formatLapTime'] as List).cast<List<dynamic>>()) {
      final seconds = (row[0] as num).toDouble();
      final decimals = row[1] as int;
      final text = row[2] as String;
      expect(
        formatLapTime(seconds, decimals),
        text.isEmpty ? isNull : text,
        reason: '$seconds s, $decimals decimals',
      );
    }
  });
}

void _expectSession(TelemetrySession session, Map<String, dynamic> expected) {
  expect(session.warnings, expected['warnings']);
  expect(session.sampleCount, expected['sampleCount']);
  expect(session.duration, (expected['duration'] as num).toDouble());
  expect(session.startTime, (expected['startTime'] as num).toDouble());
  expect(session.aliases, expected['aliases']);
  _expectMetadata(session.metadata, (expected['metadata'] as Map).cast<String, String>());

  final gates = (expected['timingGates'] as List).cast<Map<String, dynamic>>();
  expect(session.timingGates, hasLength(gates.length));
  for (var i = 0; i < gates.length; ++i) {
    final gate = session.timingGates[i];
    expect(gate.type.name, gates[i]['type']);
    expect(gate.sourceName, gates[i]['sourceName']);
    expect(gate.sourceDescription, gates[i]['sourceDescription']);
    _expectCoordinate(gate.endpointA, gates[i]['endpointA'] as Map<String, dynamic>);
    _expectCoordinate(gate.endpointB, gates[i]['endpointB'] as Map<String, dynamic>);
  }

  final channels = (expected['channels'] as List).cast<Map<String, dynamic>>();
  expect(session.channelNames(), channels.map((c) => c['name']).toList());
  final timestamps = _doubles(expected['timestamps'] as List);
  for (final channel in channels) {
    final actual = session.channels[channel['name']]!;
    expect(actual.unit, channel['unit']);
    expect(actual.sampleCount, channel['sampleCount']);
    expect(actual.timestamps, timestamps);
    expect(
      _nullable(actual.values),
      _doubles(channel['values'] as List),
      reason: 'values of ${channel['name']}',
    );
    expect(telemetryGapThreshold(actual), (channel['gapThreshold'] as num).toDouble());
  }
}

/// Metadata, including the `<section>.<n>` keys generated for lines without a
/// separator, matches exactly: both sides build it in file section order.
void _expectMetadata(Map<String, String> actual, Map<String, String> expected) {
  expect(actual, expected);
}

void _expectLaps(LapSession laps, Map<String, dynamic> expected) {
  expect(laps.status.name, expected['status']);
  final d = laps.diagnostics;
  expect({
    'usableGpsSegments': d.usableGpsSegments,
    'candidateClusters': d.candidateClusters,
    'discardedGapClusters': d.discardedGapClusters,
    'rejectedSlowClusters': d.rejectedSlowClusters,
    'rejectedParallelClusters': d.rejectedParallelClusters,
    'rejectedLongClusters': d.rejectedLongClusters,
    'rejectedOppositeDirectionClusters': d.rejectedOppositeDirectionClusters,
    'invalidLapDurations': d.invalidLapDurations,
  }, expected['diagnostics']);
  expect(laps.fastestLapIndex, expected['fastestLapIndex']);
  expect(laps.selectedStartGate == null, expected['selectedStartGate'] == null);

  final passes = (expected['acceptedPasses'] as List).cast<Map<String, dynamic>>();
  expect(laps.acceptedPasses, hasLength(passes.length));
  for (var i = 0; i < passes.length; ++i) {
    final pass = laps.acceptedPasses[i];
    expect(pass.direction, passes[i]['direction']);
    _close(pass.telemetryTime, passes[i]['telemetryTime']);
    _close(pass.closestDistanceMeters, passes[i]['closestDistanceMeters']);
    _close(pass.gateFraction, passes[i]['gateFraction']);
    _close(pass.groundSpeedMetersPerSecond, passes[i]['groundSpeedMetersPerSecond']);
    _close(pass.normalSpeedMetersPerSecond, passes[i]['normalSpeedMetersPerSecond']);
  }

  final timed = (expected['timedLaps'] as List).cast<Map<String, dynamic>>();
  expect(laps.timedLaps, hasLength(timed.length));
  for (var i = 0; i < timed.length; ++i) {
    final lap = laps.timedLaps[i];
    expect(lap.number, timed[i]['number']);
    expect(lap.referenceIssue.name, timed[i]['referenceIssue']);
    _close(lap.startTelemetryTime, timed[i]['startTelemetryTime']);
    _close(lap.endTelemetryTime, timed[i]['endTelemetryTime']);
    _close(lap.durationSeconds, timed[i]['durationSeconds']);
    _close(lap.deltaToBestSeconds, timed[i]['deltaToBestSeconds'], absolute: 1e-9);
  }

  final traces = (expected['lapTraces'] as List).cast<Map<String, dynamic>>();
  expect(laps.lapTraces, hasLength(traces.length));
  for (var i = 0; i < traces.length; ++i) {
    final trace = laps.lapTraces[i];
    expect(trace.lapNumber, traces[i]['lapNumber']);
    _close(trace.startTelemetryTime, traces[i]['startTelemetryTime']);
    _close(trace.durationSeconds, traces[i]['durationSeconds']);
    final points = (traces[i]['points'] as List).cast<List<dynamic>>();
    expect(trace.points, hasLength(points.length), reason: 'points of lap ${trace.lapNumber}');
    for (var p = 0; p < points.length; ++p) {
      _close(trace.points[p].telemetryTime, points[p][0]);
      _close(trace.points[p].eastMeters, points[p][1], absolute: 1e-7);
      _close(trace.points[p].northMeters, points[p][2], absolute: 1e-7);
    }
  }
}

void _expectCoordinate(GeoCoordinate actual, Map<String, dynamic> expected) {
  _close(actual.latitudeDegrees, expected['latitude']);
  _close(actual.longitudeDegrees, expected['longitude']);
}

void _close(double actual, Object? expected, {double absolute = 0.0}) {
  final value = (expected as num).toDouble();
  final tolerance = [absolute, 1e-9 * value.abs()].reduce((a, b) => a > b ? a : b);
  if (tolerance == 0.0) {
    expect(actual, value);
  } else {
    expect(actual, closeTo(value, tolerance));
  }
}

List<double?> _doubles(List<dynamic> values) => [
  for (final value in values) value == null ? null : (value as num).toDouble(),
];

List<double?> _nullable(List<double> values) => [
  for (final value in values) value.isFinite ? value : null,
];
