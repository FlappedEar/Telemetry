// Editing a day's track segments (day/day_segments.dart): each edit changes
// the theoretical best, edits are saved as the run's approved segments and
// are not replaced by automatic ones on later saves, and restoring brings the
// automatic segments back.
import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';
import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';

double Function(double) _lap(double straight, [double from = 0, double to = 0, double slow = 0]) =>
    (d) => d >= from && d <= to ? slow : straight;

DayRunInput _run(String id, TelemetrySession session) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
  session: session,
  laps: deriveSourceLapSession(session),
);

void main() {
  final runs = [
    _run(
      'run1',
      rectangleSession([_lap(30, 50, 120, 20), _lap(31, 300, 400, 25), _lap(30, 550, 650, 22)]),
    ),
    _run('run2', rectangleSession([_lap(29, 0, 0, 0), _lap(30.5, 700, 780, 20)])),
  ];
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  final analysis = analyzeDay(runs);
  final best = analysis.ranking!.bestOfDay!;

  DayTheoreticalBest calculate(DaySegmentEdits edits) => dayTheoreticalBest(
    analysis,
    outing,
    documentRuns: edits.applyTo(const []),
    random: Random(1),
  );

  test('automatic segments are reported as automatic, on the best lap\'s run', () {
    final result = calculate(DaySegmentEdits());
    expect(result.automaticSegments, isTrue);
    expect(result.segmentsAutomatic, isTrue);
    expect(result.segmentRunId, best.runId);
    expect(result.runSegments, hasLength(result.segments.length));
    expect(result.proposalReview, hasLength(result.segments.length));
    expect(result.axisLengthMeters, greaterThan(0));
  });

  test('automatic segments can be kept as approved, once, without history', () {
    final edits = DaySegmentEdits();
    final result = calculate(edits);
    expect(edits.keepAutomatic(result), isTrue);
    expect(edits.keepAutomatic(result), isFalse);
    expect(edits.canUndo, isFalse);
    final kept = calculate(edits);
    expect(kept.automaticSegments, isFalse);
    expect(kept.segmentRunId, result.segmentRunId);
    expect(
      [for (final s in kept.runSegments) s['id']],
      [for (final s in result.runSegments) s['id']],
    );
    // Approved segments are not automatic, so there is nothing more to keep.
    expect(DaySegmentEdits().keepAutomatic(kept), isFalse);
  });

  test('a rename keeps the automatic bounds but is an edit', () {
    final edits = DaySegmentEdits();
    var result = calculate(edits);
    final id = result.approvedSegment(0)!['id']! as String;
    final segment = result.segments[0];
    expect(
      edits.edit(
        result,
        id,
        name: 'Hairpin',
        type: segment.type,
        startMeters: segment.startProgressMeters,
        endMeters: segment.endProgressMeters,
      ),
      isEmpty,
    );
    expect(edits.runs.keys, [best.runId]);
    result = calculate(edits);
    expect(result.automaticSegments, isFalse);
    expect(result.segments[0].name, 'Hairpin');
    expect(result.approvedSegment(0)!['id'], id);
    expect(result.segmentsAutomatic, isFalse);
    expect(result.segmentMatchesProposal(0), isFalse);
    expect(result.segmentMatchesProposal(1), isTrue);
    expect(
      result.proposalReview.every((item) => item.state == SegmentReviewState.approved),
      isTrue,
    );
  });

  test('moving a boundary moves the time between the two segments', () {
    final edits = DaySegmentEdits();
    final before = calculate(edits);
    final first = before.segments[0], second = before.segments[1];
    final id = before.approvedSegment(0)!['id']! as String;
    expect(
      edits.edit(
        before,
        id,
        name: first.name,
        type: first.type,
        startMeters: first.startProgressMeters,
        endMeters: first.endProgressMeters + 20,
      ),
      isEmpty,
    );
    final after = calculate(edits);
    expect(after.segments[0].endProgressMeters, closeTo(first.endProgressMeters + 20, 1e-9));
    expect(after.segments[1].startProgressMeters, closeTo(second.startProgressMeters + 20, 1e-9));
    expect(after.segments[0].seconds!, greaterThan(first.seconds!));
    expect(after.segments[1].seconds!, lessThan(second.seconds!));
    expect(
      after.proposalReview.where((item) => item.state == SegmentReviewState.superseded),
      hasLength(2),
    );
    // The best lap still adds up to its lap time.
    expect(after.bestLapSeconds, before.bestLapSeconds);
  });

  test('split, merge, remove, undo and redo', () {
    final edits = DaySegmentEdits(random: Random(3));
    var result = calculate(edits);
    final count = result.segments.length;
    final id0 = result.approvedSegment(0)!['id']! as String;
    final id1 = result.approvedSegment(1)!['id']! as String;
    final first = result.segments[0];
    final middle = (first.startProgressMeters + first.endProgressMeters) / 2;

    expect(edits.split(result, id0, middle), isEmpty);
    result = calculate(edits);
    expect(result.segments, hasLength(count + 1));
    expect(result.segments[1].name, '${first.name} (2)');
    expect(result.segments[1].startProgressMeters, closeTo(middle, 1e-9));

    expect(edits.merge(result, id0, result.approvedSegment(1)!['id']! as String), isEmpty);
    result = calculate(edits);
    expect(result.segments, hasLength(count));
    expect(result.segments[0].endProgressMeters, closeTo(first.endProgressMeters, 1e-9));

    expect(edits.remove(result, id1), isEmpty);
    result = calculate(edits);
    expect(result.segments, hasLength(count - 1));
    expect(result.summary!.actualBest!.coversWholeLap, isFalse);

    expect(edits.split(result, id0, -5), contains('Split inside'));
    expect(edits.canUndo, isTrue);
    expect(edits.undo(const []), isEmpty);
    expect(calculate(edits).segments, hasLength(count));
    expect(edits.redo(const []), isEmpty);
    expect(calculate(edits).segments, hasLength(count - 1));
    expect(edits.undo(const []), isEmpty);
    expect(edits.undo(const []), isEmpty);
    expect(edits.undo(const []), isEmpty);
    expect(calculate(edits).segmentsAutomatic, isTrue);
    expect(edits.undo(const []), 'Nothing to undo.');
  });

  test('the last segment cannot be removed', () {
    final edits = DaySegmentEdits();
    var result = calculate(edits);
    while (result.segments.length > 1) {
      final last = result.approvedSegment(result.segments.length - 1)!['id']! as String;
      expect(edits.remove(result, last), isEmpty);
      result = calculate(edits);
    }
    expect(
      edits.remove(result, result.approvedSegment(0)!['id']! as String),
      contains('at least one'),
    );
  });

  test('restore removes the group\'s segments so the proposals come back', () {
    final edits = DaySegmentEdits();
    final result = calculate(edits);
    final segment = result.segments[0];
    edits.edit(
      result,
      result.approvedSegment(0)!['id']! as String,
      name: 'Hairpin',
      type: segment.type,
      startMeters: segment.startProgressMeters,
      endMeters: segment.endProgressMeters,
    );
    final otherSegment = {
      ...result.runSegments.first,
      'id': 'other',
      'trackConfigurationReference': 'compatibility-v1:${'f' * 64}',
    };
    final documentRuns = [
      {
        'id': 'run2',
        'trackSegments': [otherSegment],
      },
    ];
    expect(edits.restoreAutomatic(documentRuns, analysis.chosenGroupId!), isTrue);
    expect(edits.runs[best.runId], isEmpty);
    expect(edits.canUndo, isFalse);
    expect(edits.restoreAutomatic(documentRuns, analysis.chosenGroupId!), isFalse);
    final restored = dayTheoreticalBest(
      analysis,
      outing,
      documentRuns: edits.applyTo(documentRuns),
      random: Random(1),
    );
    expect(restored.automaticSegments, isTrue);
    expect(restored.segments[0].name, isNot('Hairpin'));
    expect(edits.applyTo(documentRuns).first, documentRuns.first);
  });

  group('saved', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('day_segments'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('edits are saved as approved segments and kept on later saves', () {
      final root = directory.resolveSymbolicLinksSync();
      final paths = [
        for (final (name, speeds) in [
          ('a.vbo', <double>[30, 28, 31]),
          ('b.vbo', <double>[29, 32, 27]),
        ])
          (File(p.join(root, name))..writeAsStringSync(circuitVbo(speeds))).path,
      ];
      final named = nameRunsInRecordingOrder(prepareTelemetryImport(paths).runs);
      final day = analyzeDay([
        for (final run in named)
          DayRunInput(
            runId: run.run.id,
            name: run.name,
            contentSha256: run.run.contentSha256,
            session: run.run.telemetry,
            laps: run.run.laps,
          ),
      ]);
      final path = p.join(root, 'day.fetproject');
      final eventId = newEventId();
      final edits = DaySegmentEdits();
      final result = dayTheoreticalBest(day, outingRuns(named), random: Random(1));
      expect(result.state, DayTheoreticalBestState.ready, reason: result.message);
      final segment = result.segments.last;
      expect(
        edits.edit(
          result,
          result.approvedSegment(result.segments.length - 1)!['id']! as String,
          name: 'Last bit',
          type: 'sector',
          startMeters: segment.startProgressMeters,
          endMeters: segment.endProgressMeters,
        ),
        isEmpty,
      );
      final document = dayDocument(
        eventId: eventId,
        name: 'Day',
        runs: named,
        analysis: day,
        projectPath: path,
        trackSegments: edits.runs,
      );
      List<Object?> runsOf(Map<String, Object?> document) =>
          (document['event'] as Map<String, Object?>)['runs'] as List<Object?>;
      Object? segmentsOf(Map<String, Object?> document) =>
          runsOf(document)
              .cast<Map<String, Object?>>()
              .firstWhere((run) => run['id'] == result.segmentRunId)['trackSegments'];
      expect(segmentsOf(document), edits.runs[result.segmentRunId]);
      expect(fet.validateFetproject(document), isNull);

      // A later save without edits keeps them.
      final again = dayDocument(
        eventId: eventId,
        name: 'Day',
        runs: named,
        analysis: day,
        projectPath: path,
        previous: document,
        previousPath: path,
      );
      expect(segmentsOf(again), segmentsOf(document));
      final reopened = dayTheoreticalBest(day, outingRuns(named), documentRuns: runsOf(again));
      expect(reopened.automaticSegments, isFalse);
      expect(reopened.segments.last.name, 'Last bit');
      expect(reopened.segmentsAutomatic, isFalse);

      // Restoring writes the automatic proposals again.
      final restore = DaySegmentEdits();
      expect(restore.restoreAutomatic(runsOf(again), day.chosenGroupId!), isTrue);
      final restored = dayDocument(
        eventId: eventId,
        name: 'Day',
        runs: named,
        analysis: day,
        projectPath: path,
        previous: again,
        previousPath: path,
        trackSegments: restore.runs,
        random: Random(5),
      );
      final automatic = dayTheoreticalBest(day, outingRuns(named), documentRuns: runsOf(restored));
      expect(automatic.automaticSegments, isFalse);
      expect(automatic.segmentsAutomatic, isTrue);
      expect(automatic.segments.length, result.segments.length);
    });
  });
}
