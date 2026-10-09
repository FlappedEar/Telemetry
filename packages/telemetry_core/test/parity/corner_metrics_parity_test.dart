// Compares the Dart Corner Analyzer port (analysis/corner_phases.dart,
// corner_speeds.dart, braking_onset.dart, braking_metrics.dart,
// exit_metrics.dart, driving_variability.dart and the corner metrics of
// outing_theoretical_best.dart) with FlappedEar Overlays' C++ implementation
// over the synthetic parity corpus, hand-made sessions and fixed cases.
//
// test/parity/corner_metrics_reference.json is the output of
// tool/cpp_corner_metrics_dump run over test/parity/corpus/*.vbo and
// test/fixtures/*.vbo (see tool/README.md). Counts, ids, reasons, limitations
// and orders must match exactly; doubles to 1e-9 relative (1e-9 absolute near
// zero), as in the other parity tests.
//
// FET_CORNER_REFERENCE and FET_CORNER_DIRS (colon-separated) run the same
// checks against another reference and its recordings, for local runs only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'departures.dart';

var _maximumDifference = 0.0;

void main() {
  final referencePath =
      Platform.environment['FET_CORNER_REFERENCE'] ?? 'test/parity/corner_metrics_reference.json';
  final directories =
      (Platform.environment['FET_CORNER_DIRS'] ?? 'test/parity/corpus:test/fixtures').split(':');
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final files = (reference['files'] as List? ?? const []).cast<Map<String, Object?>>();
  final cases = reference['cases'] as Map<String, Object?>?;

  tearDownAll(() {
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      stdout.writeln('largest difference: $_maximumDifference');
    }
  });

  String pathOf(String name) => directories
      .map((directory) => '$directory/$name')
      .firstWhere((path) => File(path).existsSync());

  test(
    'the reference covers measured, inferred and missing channels',
    skip: Platform.environment.containsKey('FET_CORNER_REFERENCE') ? 'another reference' : false,
    () {
      expect(files.length, greaterThanOrEqualTo(10));
      final corners = [
        for (final file in files)
          for (final variant in (file['variants'] as List).cast<Map<String, Object?>>())
            ...((variant['corners'] as List?) ?? const []).cast<Map<String, Object?>>(),
      ];
      final methods = {for (final corner in corners) (corner['braking'] as Map)['method']};
      expect(methods, containsAll(['measuredBrake', 'inferredDeceleration', '']));
      final pickups = {
        for (final corner in corners) ((corner['exit'] as Map)['pickup'] as Map)['method'],
      };
      expect(pickups, containsAll(['measuredThrottle', 'inferredAcceleration', '']));
      expect(
        corners.where((corner) => (corner['braking'] as Map)['point'] != null).length,
        greaterThan(30),
      );
    },
  );

  for (final entry in files) {
    final name = entry['file'] as String;
    test(name, () {
      final session = parseVboFile(pathOf(name));
      final laps = deriveSourceLapSession(session);
      final runs = {'run-a': OutingRun(session, laps), 'run-b': OutingRun(session, laps)};
      final byNumber = {for (final lap in laps.timedLaps) lap.number: lap};
      final population = [
        for (final row in (entry['population'] as List).cast<Map<String, Object?>>())
          () {
            final lap = byNumber[row['lapNumber']]!;
            return OutingLap(
              runId: row['runId'] as String,
              lapNumber: lap.number,
              start: lap.startTelemetryTime,
              end: lap.endTelemetryTime,
              reference: '${row['runId']}#${lap.number}',
            );
          }(),
      ];
      for (final variant in (entry['variants'] as List).cast<Map<String, Object?>>()) {
        expectCornerDay(
          population,
          runs,
          variant['segments'] as Map<String, Object?>,
          entry['actualBest'] as String,
          variant,
          '$name ${variant['name']}',
          cppAxis: cppAxis(entry['axis']),
        );
      }
    });
  }

  if (cases != null) _cases(cases);
}

/// Checks one day of [want] (a `dayJson` of the dump) against the Dart port.
void expectCornerDay(
  List<OutingLap> population,
  Map<String, OutingRun> runs,
  Map<String, Object?> segments,
  String actualBest,
  Map<String, Object?> want,
  String what, {
  String configuration = _configuration,
  ProgressAxis? cppAxis,
}) {
  final canonical = canonicalSegmentation(
    population.map((lap) => lap.runId),
    (runId) => segments[runId],
    configuration,
  );
  expect(canonical?.runId ?? '', want['canonicalRunId'], reason: what);
  if (canonical == null) return;
  expect(canonical.approved.revision, want['revision'], reason: what);
  final computed = calculateOutingTheoreticalBest(
    population,
    runs,
    canonical.approved,
    canonical.runId,
    actualBest,
  );
  expect(computed.error, want['error'], reason: what);
  if (computed.error.isNotEmpty) return;
  final axis = want['axis'] as Map<String, Object?>;
  expect(computed.axis.points.length, axis['pointCount'], reason: what);
  _close(computed.axisLengthMeters, axis['lengthMeters']);

  // The metrics run on Overlays' own axis when the reference has it: the
  // automatic segment bounds are axis samples there, and an axis built in
  // Dart can differ from it in the last bits (see track_progress.dart), which
  // decides whether a bound sample is inside a segment.
  final axisUsed = cppAxis ?? computed.axis;
  final features = computeTrackFeatures(axisUsed, segmentReviewSmoothingMeters);
  final phases = (want['phases'] as List).cast<Map<String, Object?>>();
  expect(phases.length, canonical.approved.segments.length, reason: what);
  for (var i = 0; i < phases.length; ++i) {
    final segment = canonical.approved.segments[i];
    final corner = cornerFromSegment(axisUsed, features, segment);
    final geometry = proposeCornerGeometryPhases(axisUsed, features, corner);
    final other = phases[i];
    expect(segment['id'], other['segmentId'], reason: what);
    expect(corner.type.jsonName, other['cornerType'], reason: what);
    _close(corner.turnRadians, other['turn'], absolute: 1e-9);
    _close(corner.peakCurvaturePerMeter, other['peak'], absolute: 1e-9);
    _close(corner.lengthMeters, other['lengthMeters'], absolute: 1e-9);
    expect(geometry.valid, other['valid'], reason: what);
    _expectPhase(geometry.entry, other['entry'], '$what ${segment['id']} entry');
    _expectPhase(geometry.apex, other['apex'], '$what ${segment['id']} apex');
    _expectPhase(geometry.exit, other['exit'], '$what ${segment['id']} exit');
    _expectNumbers(geometry.apexCandidatesMeters, other['candidates']);
  }

  // Lap by lap, corner by corner, as the C++ loop appends them.
  final byLap = <String, Map<String, CornerLapMetrics>>{};
  var total = 0;
  for (final entry in computed.cornerMetrics.entries) {
    for (final lap in entry.value) {
      (byLap[lap.lapReference as String] ??= {})[entry.key] = lap;
      ++total;
    }
  }
  if (cppAxis != null) {
    final measured = <String, Map<String, CornerLapMetrics>>{};
    for (final lap in population) {
      final session = runs[lap.runId]!.session;
      final trace = projectLapTrace(cppAxis, session, lap.start, lap.end);
      for (final segment in canonical.approved.segments) {
        if (segment['type'] != 'corner') continue;
        final id = segment['id'] as String;
        (measured[lap.reference as String] ??= {})[id] = measureCornerLap(
          cppAxis,
          features,
          canonical.approved,
          id,
          (segment['startProgressMeters'] as num).toDouble(),
          (segment['endProgressMeters'] as num).toDouble(),
          trace,
          session,
          lap.start,
          lap.end,
          lap.reference,
        );
      }
    }
    // The Dart calculation on its own axis agrees except where a bound
    // sample decides the geometry (apex and the line taken there).
    for (final MapEntry(key: lap, value: corners) in byLap.entries) {
      for (final MapEntry(key: id, value: own) in corners.entries) {
        final other = measured[lap]![id]!;
        _closeOrNull(own.speeds.minimum.value, other.speeds.minimum.value?.toDouble(), 1e-6);
        _closeOrNull(own.speeds.entry.value, other.speeds.entry.value, 1e-6);
        _closeOrNull(own.speeds.exit.value, other.speeds.exit.value, 1e-6);
        _closeOrNull(own.braking.brakingPointMeters, other.braking.brakingPointMeters, 1e-6);
        _closeOrNull(own.braking.brakingSeconds, other.braking.brakingSeconds, 1e-6);
        _closeOrNull(own.braking.peakDeceleration, other.braking.peakDeceleration, 1e-6);
        _closeOrNull(own.exit.pickup.progressMeters, other.exit.pickup.progressMeters, 1e-6);
        expect(own.braking.unavailableReason, other.braking.unavailableReason, reason: what);
        expect(own.exit.pickup.unavailableReason, other.exit.pickup.unavailableReason);
      }
    }
    byLap
      ..clear()
      ..addAll(measured);
  }
  final corners = (want['corners'] as List).cast<Map<String, Object?>>();
  expect(total, corners.length, reason: what);
  for (final corner in corners) {
    final lap = corner['lap'] as String, id = corner['segmentId'] as String;
    final metrics = byLap[lap]![id]!;
    final label = '$what $lap $id';
    expectSpeeds(metrics.speeds, corner['speeds'], label);
    expectBraking(metrics.braking, corner['braking'], label);
    expectExit(metrics.exit, corner['exit'], label);
  }
  for (final comparison in (want['comparisons'] as List).cast<Map<String, Object?>>()) {
    final lap = comparison['lap'] as String, id = comparison['segmentId'] as String;
    final a = byLap[lap]![id]!, b = byLap[actualBest]![id]!;
    final speeds = compareCornerSpeeds(a.speeds, b.speeds);
    final wantSpeeds = comparison['speeds'] as Map<String, Object?>;
    expect([speeds.valid, speeds.unavailableReason], [wantSpeeds['valid'], wantSpeeds['reason']]);
    _closeOrNull(speeds.entryDelta, wantSpeeds['entry']);
    _closeOrNull(speeds.apexDelta, wantSpeeds['apex']);
    _closeOrNull(speeds.minimumDelta, wantSpeeds['minimum']);
    _closeOrNull(speeds.exitDelta, wantSpeeds['exit']);
    final braking = compareBrakingMetrics(a.braking, b.braking);
    final wantBraking = comparison['braking'] as Map<String, Object?>;
    expect(
      [braking.valid, braking.unavailableReason],
      [wantBraking['valid'], wantBraking['reason']],
    );
    _closeOrNull(braking.brakingPointDeltaMeters, wantBraking['point']);
    _closeOrNull(braking.brakingSecondsDelta, wantBraking['seconds']);
    _closeOrNull(braking.brakingDistanceDeltaMeters, wantBraking['distance']);
    _closeOrNull(braking.peakDecelerationDelta, wantBraking['peak']);
    _closeOrNull(braking.meanDecelerationDelta, wantBraking['mean']);
    final exit = compareExitMetrics(a.exit, b.exit);
    final wantExit = comparison['exit'] as Map<String, Object?>;
    expect(
      [exit.valid, exit.pickupUnavailableReason],
      [wantExit['valid'], wantExit['pickupReason']],
    );
    _closeOrNull(exit.pickupDeltaMeters, wantExit['pickup']);
    _closeOrNull(exit.exitSpeedDelta, wantExit['exitSpeed']);
    _closeOrNull(exit.intervalEndSpeedDelta, wantExit['endSpeed']);
    _closeOrNull(exit.elapsedSecondsDelta, wantExit['elapsed']);
  }
  for (final observation in (want['observations'] as List).cast<Map<String, Object?>>()) {
    final metrics = byLap[observation['lap'] as String]![observation['segmentId'] as String]!;
    _expectObservation(metrics.observation, observation);
  }

  final variability = {
    for (final row in (want['variability'] as List).cast<Map<String, Object?>>())
      row['segmentId'] as String: row,
  };
  final summary = publishTheoreticalBest(computed);
  for (final row in summary.sectors) {
    expect(row.variability != null, variability.containsKey(row.segmentId), reason: what);
    if (row.variability == null) continue;
    final observations = [
      for (final lap in population)
        if (byLap[lap.reference as String]?[row.segmentId] case final metrics?) metrics.observation,
    ];
    _expectVariability(
      cppAxis == null
          ? row.variability!
          : summarizeCornerVariability(row.segmentId, row.name, observations),
      variability[row.segmentId],
    );
  }
  expect(drivingVariabilityAlgorithm, want['variabilityAlgorithm']);
}

const _configuration =
    'compatibility-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void _cases(Map<String, Object?> cases) {
  final configuration = cases['configuration'] as String;
  final sessions = {
    for (final spec in (cases['sessions'] as List).cast<Map<String, Object?>>())
      spec['name'] as String: _session(spec),
  };
  final traces = {
    for (final entry in (cases['traces'] as Map<String, Object?>).entries)
      entry.key: _trace(entry.value),
  };
  final segments = cases['segments'] as Map<String, Object?>;
  final lap = traces['full']!;

  test('braking onsets in hand-made sessions', () {
    for (final item in (cases['onsets'] as List).cast<Map<String, Object?>>()) {
      final options = item['options'] as Map<String, Object?>;
      final detection = detectBrakingOnsets(
        sessions[item['session']]!,
        _double(item['start']),
        _double(item['end']),
        options: BrakingOnsetOptions(
          measuredBrake: BrakingThreshold(
            _double(options['measuredOn']),
            _double(options['measuredOff']),
            '%',
          ),
          inferredDeceleration: BrakingThreshold(
            _double(options['inferredOn']),
            _double(options['inferredOff']),
            'g',
          ),
          minimumDurationSeconds: _double(options['minimumDuration']),
          allowInferred: options['allowInferred'] as bool,
        ),
        lapTrace: item['trace'] == true ? lap : null,
      );
      _expectDetection(detection, item['result'], '${item['session']} ${item['start']}');
    }
  });

  test('braking and exit metrics on hand-made projections', () {
    for (final item in (cases['metrics'] as List).cast<Map<String, Object?>>()) {
      final session = sessions[item['session']]!;
      final approved = approvedSegmentation(segments[item['segments']], configuration);
      final trace = traces[item['trace']]!;
      final id = item['segmentId'] as String;
      final what =
          '${item['session']} ${item['segments']} ${item['trace']} $id ${item['approach']}';
      expectBraking(
        computeBrakingMetrics(
          2000.0,
          approved,
          id,
          trace,
          session,
          0.0,
          20.0,
          BrakingMetricsOptions(approachMeters: _double(item['approach'])),
        ),
        item['braking'],
        what,
      );
      final options = ExitMetricsOptions(followMeters: _double(item['follow']));
      expectExit(
        computeExitMetrics(2000.0, approved, id, trace, session, 20.0, options),
        item['exit'],
        what,
      );
      expectExit(
        computeExitMetrics(2000.0, approved, id, trace, session, null, options),
        item['exitNoEnd'],
        '$what without an end',
      );
    }
  });

  test('lateral offsets and variability of fixed inputs', () {
    const axis = ProgressAxis(
      points: [
        MetricPoint(0, 0),
        MetricPoint(10, 0),
        MetricPoint(10, 10),
        MetricPoint(0, 10),
        MetricPoint(0, 0),
      ],
      cumulative: [0, 10, 20, 30, 40],
      lengthMeters: 40,
      spacingMeters: 10,
      valid: true,
    );
    for (final item in (cases['offsets'] as List).cast<Map<String, Object?>>()) {
      _closeOrNull(
        lateralOffsetMeters(
          axis,
          _double(item['progress']),
          MetricPoint(_double(item['east']), _double(item['north'])),
        ),
        item['offset'],
      );
    }
    final observations = [
      for (final item in (cases['observations'] as List).cast<Map<String, Object?>>())
        CornerLapObservation(lapReference: item['lap'])
          ..brakingPointMeters = _optional(item['braking'])
          ..brakingProvenance = item['brakingProvenance'] as String
          ..apexSpeed = _optional(item['apex'])
          ..minimumSpeed = _optional(item['minimum'])
          ..exitSpeed = _optional(item['exit'])
          ..pickupMeters = _optional(item['pickup'])
          ..pickupProvenance = item['pickupProvenance'] as String
          ..lineOffsetMeters = _optional(item['line'])
          ..gpsAccuracyMeters = _optional(item['accuracy']),
    ];
    _expectVariability(
      summarizeCornerVariability('c1', 'C1', observations),
      cases['variability'],
      names: true,
    );
    _expectVariability(
      summarizeCornerVariability('c1', 'C1', observations, minimumSamples: 2),
      cases['variabilityTwo'],
      names: true,
    );
  });
}

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
    sampleCount: 0,
  );
}

void _expectPhase(CornerPhasePoint point, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(
    [point.method, point.uncertaintyReasons, point.unresolvedReason],
    [want['method'], want['uncertainty'], want['reason']],
    reason: what,
  );
  _close(point.progressMeters, want['progress'], absolute: 1e-9);
  _close(point.toleranceMeters, want['tolerance'], absolute: 1e-9);
  _expectJson(point.evidence, want['evidence'], what);
}

void _expectJson(Object? actual, Object? expected, String what) {
  if (expected is num) {
    expect(actual, isA<num>(), reason: what);
    _close((actual! as num).toDouble(), expected, absolute: 1e-9);
  } else if (expected is List) {
    expect(actual, isA<List<Object?>>(), reason: what);
    final list = actual! as List<Object?>;
    expect(list.length, expected.length, reason: what);
    for (var i = 0; i < list.length; ++i) {
      _expectJson(list[i], expected[i], what);
    }
  } else if (expected is Map) {
    expect(actual, isA<Map<String, Object?>>(), reason: what);
    final map = actual! as Map<String, Object?>;
    expect(map.keys.toSet(), expected.keys.toSet(), reason: what);
    for (final key in map.keys) {
      _expectJson(map[key], expected[key], '$what.$key');
    }
  } else {
    expect(actual, expected, reason: what);
  }
}

void _expectSpeed(CornerSpeedValue value, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  _closeOrNull(value.value, want['value']);
  _close(value.progressMeters, want['progress'], absolute: 1e-9);
  _closeOrNull(value.telemetryTime, want['time']);
  expect(
    [value.unavailableReason, value.limitations],
    [want['reason'], want['limitations']],
    reason: what,
  );
}

/// Checks [speeds] against a `speedsJson` of the dump.
void expectSpeeds(CornerSpeeds speeds, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(
    [
      speeds.valid,
      speeds.segmentId,
      speeds.name,
      speeds.type,
      speeds.channel,
      speeds.unit,
      speeds.provenance,
      speeds.stamp.revision,
      speeds.stamp.calculationAlgorithm,
    ],
    [
      want['valid'],
      want['segmentId'],
      want['name'],
      want['type'],
      want['channel'],
      unitAsTelemetryReadsIt(want['unit'], speeds.unit),
      want['provenance'],
      want['revision'],
      want['algorithm'],
    ],
    reason: what,
  );
  _expectSpeed(speeds.entry, want['entry'], '$what entry');
  _expectSpeed(speeds.apex, want['apex'], '$what apex');
  _expectSpeed(speeds.minimum, want['minimum'], '$what minimum');
  _expectSpeed(speeds.exit, want['exit'], '$what exit');
  _close(speeds.lengthMeters, want['lengthMeters'], absolute: 1e-9);
  _close(speeds.coveredMeters, want['coveredMeters'], absolute: 1e-9);
  _close(speeds.meanSampleSpacingMeters, want['spacing'], absolute: 1e-9);
}

/// Checks [braking] against a `brakingJson` of the dump.
void expectBraking(BrakingMetrics braking, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(
    [
      braking.valid,
      braking.segmentId,
      braking.unavailableReason,
      braking.method,
      braking.provenance,
      braking.channel,
      braking.thresholdUnit,
      braking.limitations,
      braking.decelerationChannel,
      braking.decelerationUnit,
      braking.decelerationUnavailableReason,
      braking.stamp.revision,
      braking.stamp.calculationAlgorithm,
    ],
    [
      want['valid'],
      want['segmentId'],
      want['reason'],
      want['method'],
      want['provenance'],
      want['channel'],
      want['thresholdUnit'],
      want['limitations'],
      want['decelerationChannel'],
      want['decelerationUnit'],
      want['decelerationReason'],
      want['revision'],
      want['algorithm'],
    ],
    reason: what,
  );
  _close(braking.intervalStartMeters, want['intervalStart'], absolute: 1e-9);
  _close(braking.intervalEndMeters, want['intervalEnd'], absolute: 1e-9);
  _close(braking.entryMeters, want['entry'], absolute: 1e-9);
  _close(braking.onThreshold, want['onThreshold'], absolute: 1e-9);
  _closeOrNull(braking.brakingPointMeters, want['point']);
  _closeOrNull(braking.brakingPointTime, want['pointTime']);
  _closeOrNull(braking.distanceBeforeEntryMeters, want['beforeEntry']);
  _closeOrNull(braking.brakingSeconds, want['seconds']);
  _closeOrNull(braking.brakingDistanceMeters, want['distance']);
  _closeOrNull(braking.peakDeceleration, want['peak']);
  _closeOrNull(braking.meanDeceleration, want['mean']);
}

/// Checks [exit] against an `exitJson` of the dump.
void expectExit(ExitMetrics exit, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  final pickup = want['pickup'] as Map<String, Object?>;
  expect(
    [
      exit.valid,
      exit.segmentId,
      exit.pickup.method,
      exit.pickup.provenance,
      exit.pickup.channel,
      exit.pickup.unit,
      exit.pickup.threshold.unit,
      exit.pickup.unavailableReason,
      exit.pickup.limitations,
      exit.intervalSource,
      exit.speedChannel,
      exit.speedUnit,
      exit.downstreamUnavailableReason,
      exit.stamp.revision,
      exit.stamp.calculationAlgorithm,
    ],
    [
      want['valid'],
      want['segmentId'],
      pickup['method'],
      pickup['provenance'],
      pickup['channel'],
      pickup['unit'],
      pickup['thresholdUnit'],
      pickup['reason'],
      pickup['limitations'],
      want['source'],
      want['speedChannel'],
      unitAsTelemetryReadsIt(want['speedUnit'], exit.speedUnit),
      want['reason'],
      want['revision'],
      want['algorithm'],
    ],
    reason: what,
  );
  _close(exit.pickup.threshold.on, pickup['on'], absolute: 1e-9);
  _close(exit.pickup.threshold.off, pickup['off'], absolute: 1e-9);
  _closeOrNull(exit.pickup.progressMeters, pickup['progress']);
  _closeOrNull(exit.pickup.telemetryTime, pickup['time']);
  _close(exit.intervalStartMeters, want['intervalStart'], absolute: 1e-9);
  _close(exit.intervalEndMeters, want['intervalEnd'], absolute: 1e-9);
  _closeOrNull(exit.exitSpeed, want['exitSpeed']);
  _closeOrNull(exit.intervalEndSpeed, want['endSpeed']);
  _closeOrNull(exit.elapsedSeconds, want['elapsed']);
}

void _expectDetection(BrakingOnsetDetection detection, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(
    [
      detection.valid,
      detection.method,
      detection.provenance,
      detection.channel,
      detection.channelUnit,
      detection.threshold.unit,
      detection.rejectedSpikes,
      detection.gaps,
      detection.unresolvedReason,
    ],
    [
      want['valid'],
      want['method'],
      want['provenance'],
      want['channel'],
      // The unit as the recording declares it, without the spaces round it
      // (Overlays echoes the channel's unit as written).
      (want['channelUnit'] as String).trim(),
      want['thresholdUnit'],
      want['rejectedSpikes'],
      want['gaps'],
      want['reason'],
    ],
    reason: what,
  );
  _close(detection.threshold.on, want['on'], absolute: 1e-9);
  _close(detection.threshold.off, want['off'], absolute: 1e-9);
  _close(detection.minimumDurationSeconds, want['minimumDuration'], absolute: 1e-9);
  final candidates = (want['candidates'] as List).cast<Map<String, Object?>>();
  expect(detection.candidates.length, candidates.length, reason: what);
  for (var i = 0; i < candidates.length; ++i) {
    final candidate = detection.candidates[i], other = candidates[i];
    _close(candidate.telemetryTime, other['time'], absolute: 1e-9);
    _close(candidate.toleranceSeconds, other['tolerance'], absolute: 1e-9);
    _close(candidate.durationSeconds, other['duration'], absolute: 1e-9);
    _close(candidate.peakValue, other['peak'], absolute: 1e-9);
    _closeOrNull(candidate.progressMeters, other['progress']);
    expect(candidate.uncertaintyReasons, other['uncertainty'], reason: what);
  }
}

void _expectObservation(CornerLapObservation observation, Map<String, Object?> want) {
  _closeOrNull(observation.brakingPointMeters, want['braking']);
  expect(observation.brakingProvenance, want['brakingProvenance']);
  _closeOrNull(observation.apexSpeed, want['apex']);
  _closeOrNull(observation.minimumSpeed, want['minimum']);
  _closeOrNull(observation.exitSpeed, want['exit']);
  _closeOrNull(observation.pickupMeters, want['pickup']);
  expect(observation.pickupProvenance, want['pickupProvenance']);
  _closeOrNull(observation.lineOffsetMeters, want['line']);
  _closeOrNull(observation.gpsAccuracyMeters, want['accuracy']);
}

void _expectSummary(ConsistencySummary summary, Object? expected) {
  final want = expected as Map<String, Object?>;
  expect(summary.count, want['count']);
  expect(summary.available, want['available']);
  if (!summary.available) {
    expect(summary.unavailableReason, want['unavailableReason']);
    return;
  }
  _closeOrNull(summary.minimum, want['minimum']);
  _closeOrNull(summary.q1, want['q1']);
  _closeOrNull(summary.median, want['median']);
  _closeOrNull(summary.q3, want['q3']);
  _closeOrNull(summary.maximum, want['maximum']);
  _closeOrNull(summary.interquartileRange, want['interquartileRange']);
}

void _expectVariability(CornerVariability variability, Object? expected, {bool names = false}) {
  final want = expected as Map<String, Object?>;
  if (names) {
    expect([variability.segmentId, variability.name], [want['segmentId'], want['name']]);
  }
  _expectSummary(variability.brakingPointMeasured, want['brakingPointMeasured']);
  _expectSummary(variability.brakingPointInferred, want['brakingPointInferred']);
  _expectSummary(variability.apexSpeed, want['apexSpeed']);
  _expectSummary(variability.minimumSpeed, want['minimumSpeed']);
  _expectSummary(variability.exitSpeed, want['exitSpeed']);
  _expectSummary(variability.pickupMeasured, want['pickupMeasured']);
  _expectSummary(variability.pickupInferred, want['pickupInferred']);
  _expectSummary(variability.lineOffset, want['lineOffset']);
  _closeOrNull(variability.typicalGpsAccuracyMeters, want['typicalGpsAccuracyMeters']);
  expect(variability.lineSpreadResolvable, want['lineSpreadResolvable']);
}

List<ProgressSegment> _trace(Object? value) => [
  for (final segment in (value as List).cast<List<Object?>>())
    ProgressSegment([
      for (final sample in segment.cast<List<Object?>>())
        ProjectedSample(_double(sample[0]), progressMeters: _double(sample[1]), valid: true),
    ]),
];

double _double(Object? value) => (value as num).toDouble();
double? _optional(Object? value) => (value as num?)?.toDouble();

void _expectNumbers(List<double> actual, Object? expected) {
  final want = (expected as List).cast<num?>();
  expect(actual.length, want.length);
  for (var i = 0; i < want.length; ++i) {
    _close(actual[i], want[i], absolute: 1e-9);
  }
}

void _closeOrNull(double? actual, Object? expected, [double absolute = 1e-9]) {
  if (expected == null) {
    expect(actual, isNull);
    return;
  }
  expect(actual, isNotNull);
  _close(actual!, expected, absolute: absolute);
}

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

void _close(double actual, Object? expected, {double absolute = 0.0}) {
  final value = _double(expected);
  final difference = (actual - value).abs();
  if (difference > _maximumDifference) _maximumDifference = difference;
  final tolerance = max(absolute, 1e-9 * value.abs());
  if (tolerance == 0.0) {
    expect(actual, value);
  } else {
    expect(actual, closeTo(value, tolerance));
  }
}
