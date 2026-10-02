import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

final _group = 'compatibility-v1:${'ab' * 32}';
final _otherGroup = 'compatibility-v1:${'cd' * 32}';

/// An axis of [curvatures].length points 2 m apart and its features, with
/// the given curvature at each point (the geometry itself is not used).
(ProgressAxis, TrackFeatures) _axis(List<double> curvatures, {double smoothing = 6.0}) {
  final n = curvatures.length;
  final axis = ProgressAxis(
    points: [for (var i = 0; i < n; ++i) MetricPoint(i * 2.0, 0.0)],
    cumulative: [for (var i = 0; i < n; ++i) i * 2.0],
    lengthMeters: n * 2.0,
    spacingMeters: 2.0,
    valid: true,
  );
  final features = TrackFeatures(
    samples: [for (var i = 0; i < n; ++i) TrackFeatureSample(i * 2.0, 0.0, curvatures[i])],
    smoothingMeters: smoothing,
    valid: true,
  );
  return (axis, features);
}

/// Curvature runs: (count, curvature) pairs, in order.
List<double> _runs(List<(int, double)> runs) => [
  for (final (count, curvature) in runs) ...List.filled(count, curvature),
];

Map<String, Object?> _segment(
  String id,
  double start,
  double end, {
  String type = 'corner',
  String? group,
}) => {
  'id': id,
  'type': type,
  'name': 'Segment $id',
  'startProgressMeters': start,
  'endProgressMeters': end,
  'trackConfigurationReference': group ?? _group,
};

void main() {
  group('proposeTrackSegments', () {
    test('alternates straights and corners and closes the loop', () {
      // 100 m straight, 40 m left corner (turn 0.8), 100 m straight, 40 m right corner.
      final (axis, features) = _axis(_runs([(50, 0), (20, 0.02), (50, 0), (20, -0.02)]));
      final result = proposeTrackSegments(axis, features);
      expect(result.valid, isTrue);
      expect(result.unresolvedReason, isEmpty);
      expect(
        [for (final p in result.proposals) p.name],
        ['Straight 1', 'Corner 1', 'Straight 2', 'Corner 2'],
      );
      expect(result.proposals.first.start.progressMeters, 0.0);
      // The last proposal ends at the full length, not at 0.
      expect(result.proposals.last.end.progressMeters, 280.0);
      expect(result.proposals[1].type, fet.TrackSegmentType.corner);
      expect(result.proposals[1].turnRadians, closeTo(0.8, 1e-12));
      expect(result.proposals[3].turnRadians, closeTo(-0.8, 1e-12));
      expect(result.proposals[3].peakCurvaturePerMeter, -0.02);
      expect(result.proposals[1].lengthMeters, 40.0);
      expect(result.proposals[1].chainedCorners, 1);
      expect(result.proposals[0].chainedCorners, 0);
      expect(result.proposals[1].start.toleranceMeters, 8.0);
      expect(result.proposals.every((p) => p.start.certain && p.end.certain), isTrue);
    });

    test('a proposal crossing the gate is the last one', () {
      final (axis, features) = _axis(_runs([(10, 0.02), (50, 0), (20, 0.02), (50, 0), (10, 0.02)]));
      final result = proposeTrackSegments(axis, features);
      expect(
        [for (final p in result.proposals) p.name],
        ['Straight 1', 'Corner 1', 'Straight 2', 'Corner 2'],
      );
      final last = result.proposals.last;
      expect(last.start.progressMeters, 260.0);
      expect(last.end.progressMeters, 20.0);
      expect(last.lengthMeters, 40.0);
    });

    test('kinks stay in the straight', () {
      // 0.01 × 2 m × 10 = 0.2 rad, under the 0.35 rad of a corner.
      final (axis, features) = _axis(_runs([(40, 0), (10, 0.01), (40, 0), (20, 0.03), (40, 0)]));
      final result = proposeTrackSegments(axis, features);
      expect([for (final p in result.proposals) p.name], ['Corner 1', 'Straight 1']);
    });

    test('corners without a straight between them form a chain', () {
      // S-bend, then two corners joined by a 10 m straight.
      final (axis, features) = _axis(
        _runs([(50, 0), (15, 0.03), (15, -0.03), (50, 0), (15, 0.03), (5, 0), (15, 0.03), (50, 0)]),
      );
      final result = proposeTrackSegments(axis, features);
      expect(
        [for (final p in result.proposals) p.name],
        ['Corners 1–2', 'Straight 1', 'Corners 3–4', 'Straight 2'],
      );
      expect(result.proposals[0].chainedCorners, 2);
      expect(result.proposals[0].turnRadians, closeTo(0.0, 1e-12));
      expect(result.proposals[2].chainedCorners, 2);
      expect(result.proposals[2].lengthMeters, 70.0);
      expect(result.proposals[2].turnRadians, closeTo(1.8, 1e-12));
      // The last straight crosses the gate.
      expect(result.proposals[3].end.progressMeters, 100.0);
    });

    test('a short straight makes both of its boundaries uncertain', () {
      // A 30 m straight: proposed, but under the 40 m of a certain one.
      final (axis, features) = _axis(_runs([(60, 0), (20, 0.03), (15, 0), (20, 0.03)]));
      final result = proposeTrackSegments(axis, features);
      final straight = result.proposals.firstWhere((p) => p.lengthMeters == 30.0);
      expect(straight.start.uncertaintyReasons, [proposalUncertainShortStraight]);
      expect(straight.end.uncertaintyReasons, [proposalUncertainShortStraight]);
      expect(result.proposals.first.start.certain, isTrue);
    });

    test('a boundary near a GPS gap is uncertain', () {
      final (axis, features) = _axis(_runs([(50, 0), (20, 0.02), (50, 0), (20, -0.02)]));
      final result = proposeTrackSegments(axis, features, const [ProgressRange(130, 135)]);
      final reasons = [for (final p in result.proposals) p.start.uncertaintyReasons];
      // Boundaries at 0, 100, 140 and 240; 140 is within 8 m of the gap.
      expect(reasons, [
        <String>[],
        <String>[],
        [proposalUncertainGpsGap],
        <String>[],
      ]);
      // A wrapping gap covers the gate.
      final wrapped = proposeTrackSegments(axis, features, const [ProgressRange(270, 5)]);
      expect(wrapped.proposals.first.start.uncertaintyReasons, [proposalUncertainGpsGap]);
    });

    test('geometry that cannot be split is unresolved', () {
      final (straight, straightFeatures) = _axis(List.filled(100, 0.0));
      expect(proposeTrackSegments(straight, straightFeatures).unresolvedReason, 'noCorners');
      final (circle, circleFeatures) = _axis(List.filled(100, 0.03));
      final continuous = proposeTrackSegments(circle, circleFeatures);
      expect(continuous.valid, isTrue);
      expect(continuous.unresolvedReason, 'continuousCorner');
      expect(continuous.proposals, isEmpty);
      // No straight of 20 m anywhere.
      final (bends, bendFeatures) = _axis(_runs([(30, 0.03), (5, 0), (30, -0.03), (5, 0)]));
      expect(proposeTrackSegments(bends, bendFeatures).unresolvedReason, 'continuousCorner');
      // More than 64 segments.
      final (many, manyFeatures) = _axis(
        _runs([
          for (var i = 0; i < 40; ++i) ...[(15, 0.0), (15, 0.03)],
        ]),
      );
      expect(proposeTrackSegments(many, manyFeatures).unresolvedReason, 'tooManySegments');
    });

    test('invalid inputs give an invalid result', () {
      final (axis, features) = _axis(_runs([(50, 0), (20, 0.02), (50, 0), (20, -0.02)]));
      expect(proposeTrackSegments(const ProgressAxis(), features).valid, isFalse);
      expect(proposeTrackSegments(axis, const TrackFeatures()).valid, isFalse);
      expect(proposeTrackSegments(axis, features, const [ProgressRange(-1, 5)]).valid, isFalse);
      expect(proposeTrackSegments(axis, features, const [ProgressRange(0, 281)]).valid, isFalse);
      expect(
        proposeTrackSegments(
          axis,
          features,
          const [],
          const SegmentProposalOptions(connectedStraightMeters: 50.0),
        ).valid,
        isFalse,
      );
      final (nan, nanFeatures) = _axis([...List.filled(50, 0.0), double.nan]);
      expect(proposeTrackSegments(nan, nanFeatures).valid, isFalse);
    });

    test('proposalsToTrackSegments makes ordinary segments', () {
      final (axis, features) = _axis(_runs([(50, 0), (20, 0.02), (50, 0), (20, -0.02)]));
      final segments = proposalsToTrackSegments(proposeTrackSegments(axis, features), _group);
      expect(segments.length, 4);
      expect(fet.validTrackSegments(segments), isTrue);
      expect(segments[1]['type'], 'corner');
      expect(segments[1]['name'], 'Corner 1');
      expect(segments.last['endProgressMeters'], 280.0);
      expect(proposalsToTrackSegments(TrackSegmentProposals(), _group), isEmpty);
      expect(proposalsToTrackSegments(proposeTrackSegments(axis, features), 'unknown'), isEmpty);
    });
  });

  group('approved segments', () {
    test('progressRangesOverlap', () {
      expect(
        progressRangesOverlap(const ProgressRange(10, 50), const ProgressRange(50, 90), 1000),
        isFalse,
      );
      expect(
        progressRangesOverlap(const ProgressRange(10, 50), const ProgressRange(40, 90), 1000),
        isTrue,
      );
      expect(
        progressRangesOverlap(const ProgressRange(900, 20), const ProgressRange(10, 30), 1000),
        isTrue,
      );
      expect(
        progressRangesOverlap(const ProgressRange(900, 20), const ProgressRange(20, 900), 1000),
        isFalse,
      );
      expect(
        progressRangesOverlap(const ProgressRange(900, 20), const ProgressRange(950, 960), 1000),
        isTrue,
      );
    });

    test('withApprovedSegment inserts in start order', () {
      var stored = withApprovedSegment(null, _segment('b', 300, 400), 1000).segments!;
      stored = withApprovedSegment(stored, _segment('a', 100, 200), 1000).segments!;
      stored = withApprovedSegment(stored, _segment('w', 900, 20), 1000).segments!;
      expect([for (final s in stored) s['id']], ['a', 'b', 'w']);
      expect(fet.validTrackSegments(stored), isTrue);
    });

    test('withApprovedSegment refuses overlaps, other groups and a second wrap', () {
      final stored = [_segment('a', 100, 200), _segment('w', 900, 20)];
      expect(
        withApprovedSegment(stored, _segment('c', 150, 250), 1000).error,
        'Overlaps approved segment “Segment a”.',
      );
      expect(
        withApprovedSegment(stored, _segment('a', 300, 400), 1000).error,
        'This segment is already approved.',
      );
      expect(
        withApprovedSegment(stored, _segment('c', 300, 400, group: _otherGroup), 1000).error,
        startsWith('Segments approved for a different track configuration'),
      );
      expect(withApprovedSegment(stored, _segment('c', 950, 990), 1000).segments, isNull);
      expect(
        withApprovedSegment([_segment('w', 900, 20)], _segment('v', 600, 30), 1000).error,
        isNotEmpty,
      );
      expect(withApprovedSegment(stored, {'id': 'x'}, 1000).error, contains('invalid'));
      final full = [for (var i = 0; i < 64; ++i) _segment('s$i', i * 10.0, i * 10.0 + 5)];
      expect(
        withApprovedSegment(full, _segment('c', 900, 910), 1000).error,
        'At most 64 segments can be approved.',
      );
    });

    test('withoutApprovedSegment', () {
      final stored = [_segment('a', 100, 200), _segment('b', 300, 400)];
      expect([for (final s in withoutApprovedSegment(stored, 'a')!) s['id']], ['b']);
      expect(withoutApprovedSegment(stored, 'x'), isNull);
    });

    test('approvedSegmentation applies only to its configuration', () {
      final stored = [_segment('a', 100, 200), _segment('o', 250, 260, group: _otherGroup)];
      final approved = approvedSegmentation(stored, _group);
      expect(approved.valid, isTrue);
      expect([for (final s in approved.segments) s['id']], ['a']);
      expect(approved.otherConfigurationSegments, 1);
      expect(approved.revision, fet.trackSegmentsV1Revision([stored.first]));
      expect(approvedSegmentation(null, _group).revision, isEmpty);
      expect(approvedSegmentation(null, _group).valid, isTrue);
      expect(approvedSegmentation('x', _group).valid, isFalse);
    });
  });

  group('automatic segments', () {
    ProgressSegment covered(double from, double to) => ProgressSegment([
      ProjectedSample(0, progressMeters: from, valid: true),
      ProjectedSample(1, progressMeters: to, valid: true),
    ]);

    test('coverageGaps', () {
      expect(coverageGaps([covered(0, 500)], 500), isEmpty);
      expect(coverageGaps([covered(10, 490)], 500), isEmpty); // under 15 m
      expect(coverageGaps([covered(300, 480), covered(20, 200)], 500), const [
        ProgressRange(0, 20),
        ProgressRange(200, 300),
        ProgressRange(480, 500),
      ]);
      expect(coverageGaps([], 500), const [ProgressRange(0, 500)]);
    });

    test('the best lap of a corpus track is approved whole, once', () {
      final session = parseVboFile('test/parity/corpus/segments_rectangle.vbo');
      final laps = deriveSourceLapSession(session);
      final lap = laps.timedLaps[1];
      List<Map<String, Object?>>? run(Iterable<Object?> runs, Object? stored) =>
          automaticTrackSegments(
            documentRuns: runs,
            groupId: _group,
            storedSegments: stored,
            session: session,
            laps: laps,
            lapNumber: lap.number,
            startTime: lap.startTelemetryTime,
            endTime: lap.endTelemetryTime,
            random: Random(7),
          );
      final segments = run(const [], null)!;
      expect(
        [for (final s in segments) s['name']],
        [
          'Corner 1',
          'Straight 1',
          'Corner 2',
          'Straight 2',
          'Corner 3',
          'Straight 3',
          'Corner 4',
          'Straight 4',
        ],
      );
      expect(fet.validTrackSegments(segments), isTrue);
      expect(segments.every((s) => s['trackConfigurationReference'] == _group), isTrue);
      expect(segments.map((s) => s['id']).toSet().length, 8);
      // Approved segments in any run of the group stop it.
      expect(
        run([
          {'trackSegments': segments},
        ], null),
        isNull,
      );
      // Segments of another configuration in the run block approval, as in Overlays.
      expect(run(const [], [_segment('o', 1, 2, group: _otherGroup)]), isNull);
      expect(
        automaticTrackSegments(
          documentRuns: const [],
          groupId: 'unresolved:run',
          storedSegments: null,
          session: session,
          laps: laps,
          lapNumber: lap.number,
          startTime: lap.startTelemetryTime,
          endTime: lap.endTelemetryTime,
        ),
        isNull,
      );
    });

    test('a saved day gets the best lap\'s segments, kept on later saves', () {
      final directory = Directory.systemTemp.createTempSync('automatic_segments');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = p.join(directory.path, 'rectangle.vbo');
      File('test/parity/corpus/segments_rectangle.vbo').copySync(path);
      final plan = prepareTelemetryImport([path]);
      final runs = nameRunsInRecordingOrder(plan.runs);
      final analysis = analyzeDay([
        for (final named in runs)
          DayRunInput(
            runId: named.run.id,
            name: named.name,
            contentSha256: named.run.contentSha256,
            session: named.run.telemetry,
            laps: named.run.laps,
          ),
      ]);
      expect(analysis.chosenGroup?.resolved, isTrue);
      final projectPath = p.join(directory.path, 'day.fetproject');
      Map<String, Object?> save({Map<String, Object?>? previous, bool automatic = true}) =>
          dayDocument(
            eventId: 'event',
            name: 'Day',
            runs: runs,
            analysis: analysis,
            projectPath: projectPath,
            previous: previous,
            previousPath: projectPath,
            automaticSegments: automatic,
          );
      List<Object?>? segmentsOf(Map<String, Object?> document) =>
          ((((document['event'] as Map)['runs'] as List).single as Map)['trackSegments']) as List?;

      final first = save();
      expect(fet.validateFetproject(first), isNull);
      final segments = segmentsOf(first)!;
      expect(segments.length, 8);
      expect((segments.first as Map)['trackConfigurationReference'], analysis.chosenGroupId);
      final second = save(previous: first);
      expect(segmentsOf(second), segments);
      expect(segmentsOf(save(automatic: false)), isNull);
    });
  });
}
