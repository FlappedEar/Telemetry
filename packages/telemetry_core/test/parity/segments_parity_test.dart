// Compares the Dart track-segment port (fetproject's track_segments.dart and
// analysis/track_segment_proposals.dart, track_segment_review.dart and
// automatic_segments.dart) with FlappedEar Overlays' C++ implementation over
// the synthetic parity corpus and fixed cases.
//
// test/parity/segments_reference.json is the output of tool/cpp_segments_dump
// run over test/parity/corpus/*.vbo and test/fixtures/*.vbo (see
// tool/README.md); it holds every file with lap traces and a start gate.
// Counts, indices, names, types and reasons must match exactly; doubles to
// 1e-9 relative (1e-9 absolute near zero), as in progress_parity_test.dart.
//
// FET_SEGMENTS_REFERENCE and FET_SEGMENTS_DIRS (colon-separated) run the same
// checks against another reference and its recordings, for local runs only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

// Must match tool/cpp_segments_dump/main.cpp.
const _featureStride = 50;

var _maximumDifference = 0.0;

void main() {
  final referencePath =
      Platform.environment['FET_SEGMENTS_REFERENCE'] ?? 'test/parity/segments_reference.json';
  final directories =
      (Platform.environment['FET_SEGMENTS_DIRS'] ?? 'test/parity/corpus:test/fixtures').split(':');
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final files = (reference['files'] as List).cast<Map<String, Object?>>();
  final cases = reference['cases'] as Map<String, Object?>;
  final configuration = cases['configuration'] as String;

  tearDownAll(() {
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      stdout.writeln('largest difference: $_maximumDifference');
    }
  });

  String pathOf(String name) => directories
      .map((directory) => '$directory/$name')
      .firstWhere((path) => File(path).existsSync());

  test('the reference covers every file with lap traces and a start gate', () {
    final withTraces = <String>{};
    for (final file in [
      for (final directory in directories) ...Directory(directory).listSync(),
    ].whereType<File>().where((f) => f.path.toLowerCase().endsWith('.vbo'))) {
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
      final session = parseVboFile(pathOf(name));
      final laps = deriveSourceLapSession(session);
      final expectedLaps = (entry['laps'] as List).cast<Map<String, Object?>>();
      expect(laps.timedLaps.map((lap) => lap.number).toList(), [
        for (final lap in expectedLaps) lap['lapNumber'],
      ]);
      for (var index = 0; index < laps.timedLaps.length; ++index) {
        final lap = laps.timedLaps[index];
        _expectReview(
          session,
          laps,
          lap,
          expectedLaps[index],
          configuration,
          '$name lap ${lap.number}',
        );
      }

      if (!entry.containsKey('referenceLap')) return;
      final gate = laps.selectedStartGate!;
      final eligible = {
        for (final lap in laps.timedLaps)
          if (lap.referenceEligible) lap.number,
      };
      final trace = laps.lapTraces.firstWhere((trace) => eligible.contains(trace.lapNumber));
      expect(trace.lapNumber, entry['referenceLap']);
      final axis = buildProgressAxis(trace, _midpoint(gate), gate);
      final features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
      final cross = (entry['crossLaps'] as List).cast<Map<String, Object?>>();
      expect(cross.length, laps.timedLaps.length);
      for (var index = 0; index < cross.length; ++index) {
        final lap = laps.timedLaps[index];
        expect(lap.number, cross[index]['lapNumber']);
        final gaps = coverageGaps(
          projectLapTrace(axis, session, lap.startTelemetryTime, lap.endTelemetryTime),
          axis.lengthMeters,
        );
        _expectRanges(gaps, cross[index]['gaps']);
        _expectProposals(
          proposeTrackSegments(axis, features, gaps),
          cross[index]['proposals'],
          '$name cross lap ${lap.number}',
        );
      }
      for (final variant in (entry['variants'] as List).cast<Map<String, Object?>>()) {
        final values = [for (final value in variant['options'] as List) _double(value)];
        final options = SegmentProposalOptions(
          cornerCurvaturePerMeter: values[0],
          minimumCornerTurnRadians: values[1],
          connectedStraightMeters: values[2],
          certainStraightMeters: values[3],
        );
        final gaps = [
          for (final range in (variant['gaps'] as List).cast<List<Object?>>())
            ProgressRange(_double(range[0]), _double(range[1])),
        ];
        _expectProposals(
          proposeTrackSegments(axis, features, gaps, options),
          variant['proposals'],
          '$name options $values gaps $gaps',
        );
      }
    });
  }

  test('validTrackSegments', () {
    for (final item in (cases['validTrackSegments'] as List).cast<Map<String, Object?>>()) {
      expect(validTrackSegments(item['value']), item['valid'], reason: '${item['value']}');
    }
  });

  test('progressRangesOverlap', () {
    for (final item in (cases['progressRangesOverlap'] as List).cast<Map<String, Object?>>()) {
      final a = item['a'] as List, b = item['b'] as List;
      expect(
        progressRangesOverlap(
          ProgressRange(_double(a[0]), _double(a[1])),
          ProgressRange(_double(b[0]), _double(b[1])),
          _double(item['lengthMeters']),
        ),
        item['overlap'],
        reason: '$a $b',
      );
    }
  });

  test('withApprovedSegment', () {
    for (final item in (cases['withApprovedSegment'] as List).cast<Map<String, Object?>>()) {
      final approval = withApprovedSegment(
        item['stored'],
        item['segment'] as Map<String, Object?>,
        _double(item['lengthMeters']),
      );
      expect(approval.error, item['error'], reason: '${item['segment']}');
      expect(approval.segments, item['result'], reason: '${item['segment']}');
    }
  });

  test('approvedSegmentation', () {
    for (final item in (cases['approvedSegmentation'] as List).cast<Map<String, Object?>>()) {
      final approved = approvedSegmentation(item['stored'], item['reference'] as String);
      final reason = '${item['stored']} ${item['reference']}';
      expect(approved.valid, item['valid'], reason: reason);
      expect(approved.segments, item['segments'], reason: reason);
      expect(approved.revision, item['revision'], reason: reason);
      expect(
        approved.otherConfigurationSegments,
        item['otherConfigurationSegments'],
        reason: reason,
      );
    }
  });
}

GeoCoordinate _midpoint(TimingGate gate) => GeoCoordinate(
  (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
  (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
);

void _expectReview(
  TelemetrySession session,
  LapSession laps,
  TimedLap lap,
  Map<String, Object?> expected,
  String configuration,
  String what,
) {
  _close(lap.startTelemetryTime, expected['start']);
  _close(lap.endTelemetryTime, expected['end']);
  final review = computeSegmentReview(
    session,
    laps,
    lapNumber: lap.number,
    startTime: lap.startTelemetryTime,
    endTime: lap.endTelemetryTime,
    splitCornerChains: false, // Overlays' proposals, chains kept
  );
  final unavailable = expected['unavailable'];
  if (unavailable == 'noTrace') {
    expect(review.unavailable, contains('no gate-anchored GPS trace'), reason: what);
    return;
  }
  final axis = expected['axis'] as Map<String, Object?>;
  expect(review.axis.valid, axis['valid'], reason: what);
  expect(review.axis.points.length, axis['pointCount'], reason: what);
  _close(review.axis.lengthMeters, axis['lengthMeters']);
  _close(review.axis.spacingMeters, axis['spacingMeters']);
  if (unavailable == 'noAxis') {
    expect(review.unavailable, contains('could not be built'), reason: what);
    return;
  }
  expect(unavailable, isNull);
  final features = expected['features'] as Map<String, Object?>;
  expect(review.features.samples.length, features['sampleCount'], reason: what);
  final samples = (features['samples'] as List).cast<List<Object?>>();
  var s = 0;
  for (var i = 0; i < review.features.samples.length; i += _featureStride, ++s) {
    expect(i, samples[s][0]);
    _close(review.features.samples[i].progressMeters, samples[s][1], absolute: 1e-9);
    _close(review.features.samples[i].curvaturePerMeter, samples[s][2], absolute: 1e-9);
  }
  expect(s, samples.length);
  expect(review.lapTrace.map((segment) => segment.samples.length).toList(), expected['traceSizes']);
  _expectRanges(review.gaps, expected['gaps']);
  _expectProposals(review.proposals, expected['proposals'], what);

  final automatic = expected['automatic'] as Map<String, Object?>?;
  final approved = approveAllProposals(null, review, configuration, random: Random(1));
  if (automatic == null) {
    expect(approved, isNull, reason: what);
    expect(review.proposals.proposals.isEmpty || review.unavailable.isNotEmpty, isTrue);
    return;
  }
  expect(approved?.length ?? 0, automatic['approved'], reason: what);
  _expectSegments(approved, automatic['stored']);
  final again = approveAllProposals(approved, review, configuration, random: Random(2));
  expect(again?.length ?? 0, automatic['approvedAgain'], reason: what);
  _expectSegments(
    proposalsToTrackSegments(review.proposals, configuration, random: Random(3)),
    expected['proposalsToTrackSegments'],
  );
}

void _expectSegments(List<Map<String, Object?>>? actual, Object? expected) {
  final want = expected as Map<String, Object?>;
  final segments = actual ?? const [];
  expect(validTrackSegments(actual), want['valid']);
  expect(segments.map((segment) => segment['id']).toSet().length, want['distinctIds']);
  final expectedSegments = (want['segments'] as List).cast<Map<String, Object?>>();
  expect(segments.length, expectedSegments.length);
  for (var i = 0; i < segments.length; ++i) {
    final segment = segments[i], other = expectedSegments[i];
    expect(segment.keys.toSet(), {...other.keys, 'id'});
    for (final key in ['type', 'name', 'trackConfigurationReference']) {
      expect(segment[key], other[key]);
    }
    for (final key in ['startProgressMeters', 'endProgressMeters']) {
      _close(_double(segment[key]), other[key], absolute: 1e-9);
    }
  }
}

void _expectRanges(List<ProgressRange> actual, Object? expected) {
  final want = (expected as List).cast<List<Object?>>();
  expect(actual.length, want.length);
  for (var i = 0; i < actual.length; ++i) {
    _close(actual[i].startMeters, want[i][0], absolute: 1e-9);
    _close(actual[i].endMeters, want[i][1], absolute: 1e-9);
  }
}

void _expectProposals(TrackSegmentProposals actual, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(actual.valid, want['valid'], reason: what);
  expect(actual.unresolvedReason, want['unresolvedReason'], reason: what);
  final proposals = (want['proposals'] as List).cast<Map<String, Object?>>();
  expect(actual.proposals.map((p) => '${p.type.jsonName} ${p.name}').toList(), [
    for (final p in proposals) '${p['type']} ${p['name']}',
  ], reason: what);
  for (var i = 0; i < proposals.length; ++i) {
    final proposal = actual.proposals[i], other = proposals[i];
    void boundary(SegmentProposalBoundary actual, Object? expected) {
      final values = expected as List;
      _close(actual.progressMeters, values[0], absolute: 1e-9);
      _close(actual.toleranceMeters, values[1], absolute: 1e-9);
      expect(actual.uncertaintyReasons, values[2], reason: '$what ${proposal.name}');
    }

    boundary(proposal.start, other['start']);
    boundary(proposal.end, other['end']);
    _close(proposal.lengthMeters, other['lengthMeters'], absolute: 1e-9);
    _close(proposal.turnRadians, other['turnRadians'], absolute: 1e-9);
    _close(proposal.peakCurvaturePerMeter, other['peakCurvaturePerMeter'], absolute: 1e-9);
    expect(proposal.chainedCorners, other['chainedCorners']);
  }
}

double _double(Object? value) => (value as num).toDouble();

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
