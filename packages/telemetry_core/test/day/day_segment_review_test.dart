// The optional review of a day's automatic segment proposals (FET-56,
// day/day_segment_review.dart and DaySegmentEdits): each proposal's state,
// rejections stored as Overlays stores them, approve all, undo and redo, and
// the saved document.
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

  DayProposalReview reviewOf(DayTheoreticalBest result) =>
      dayProposalReview(result, segmentReviewLap(result), outing[result.segmentRunId]);

  Map<String, Object?>? storedReview(DaySegmentEdits edits, String runId) {
    for (final run in edits.applyTo(const []).cast<Map<String, Object?>>()) {
      if (run['id'] == runId) return run['trackSegmentReview'] as Map<String, Object?>?;
    }
    return null;
  }

  List<SegmentReviewState> states(DaySegmentEdits edits, DayTheoreticalBest result) {
    final review = reviewOf(result);
    return [
      for (final item in review.items(result.runSegments, storedReview(edits, review.runId)))
        item.state,
    ];
  }

  test('automatic segments are the best lap\'s proposals, all approved', () {
    final result = calculate(DaySegmentEdits());
    expect(segmentReviewLap(result)!.reference, best.reference);
    final review = reviewOf(result);
    expect(review.ready, isTrue, reason: review.message);
    expect(review.runId, best.runId);
    expect(review.matches(result), isTrue);
    expect(review.proposals, hasLength(result.segments.length));
    final items = review.items(result.runSegments, null);
    expect(items.every((item) => item.state == SegmentReviewState.approved), isTrue);
    // Corners carry their turn and geometric apex; straights neither.
    for (var i = 0; i < items.length; ++i) {
      final proposal = items[i].proposal;
      expect(proposal.start.toleranceMeters, greaterThan(0));
      if (proposal.type == fet.TrackSegmentType.corner) {
        expect(proposal.turnRadians.abs(), greaterThan(1.0));
        expect(review.phases[i]!.valid, isTrue);
      } else {
        expect(review.phases[i], isNull);
      }
    }
    // Without the lap's recording there are no proposals, and it says why.
    final missing = dayProposalReview(result, segmentReviewLap(result), null);
    expect(missing.ready, isFalse);
    expect(missing.reason, segmentReviewNoLap);
    expect(missing.items(result.runSegments, null), isEmpty);
    // Nothing waits for a review: approve all has nothing left to do.
    expect(
      DaySegmentEdits().approveAll(result, review, const []).error,
      'No proposal could be approved.',
    );
  });

  test('reject, restore, approve all, undo and redo', () {
    final edits = DaySegmentEdits(random: Random(4));
    var result = calculate(edits);
    final count = result.segments.length;
    // Revoke two approved segments: their proposals are open again.
    expect(edits.remove(result, result.approvedSegment(0)!['id']! as String), isEmpty);
    result = calculate(edits);
    expect(edits.remove(result, result.approvedSegment(0)!['id']! as String), isEmpty);
    result = calculate(edits);
    expect(states(edits, result).take(3), [
      SegmentReviewState.proposed,
      SegmentReviewState.proposed,
      SegmentReviewState.approved,
    ]);

    // A rejection is stored in the run's trackSegmentReview, as Overlays
    // writes it, without changing the segments.
    final review = reviewOf(result);
    expect(edits.setRejected(result, review, const [], 1), isEmpty);
    expect(edits.undoChangesSegments, isFalse);
    final stored = storedReview(edits, best.runId)!;
    expect(validTrackSegmentReview(stored), isTrue);
    expect(stored, {
      'version': trackSegmentReviewAlgorithm,
      'trackConfigurationReference': analysis.chosenGroupId,
      'proposalAlgorithm': trackSegmentProposalAlgorithm,
      'rejected': [
        {
          'type': fet.trackSegmentTypeName(review.proposals[1].type),
          'startProgressMeters': review.proposals[1].start.progressMeters,
          'endProgressMeters': review.proposals[1].end.progressMeters,
        },
      ],
    });
    expect(edits.runs[best.runId], hasLength(count - 2));
    expect(states(edits, result)[1], SegmentReviewState.rejected);
    // Approved proposals cannot be rejected.
    expect(edits.setRejected(result, review, const [], 2), contains('Only open'));

    // Undo and redo the rejection.
    expect(edits.undo(const []), isEmpty);
    expect(storedReview(edits, best.runId), isNull);
    expect(states(edits, result)[1], SegmentReviewState.proposed);
    expect(edits.redo(const []), isEmpty);
    expect(states(edits, result)[1], SegmentReviewState.rejected);

    // Approve all approves the open proposal, not the rejected one.
    final approval = edits.approveAll(result, review, const []);
    expect(approval, (approved: 1, error: ''));
    expect(edits.undoChangesSegments, isTrue);
    result = calculate(edits);
    expect(result.segments, hasLength(count - 1));
    expect(states(edits, result).take(2), [
      SegmentReviewState.approved,
      SegmentReviewState.rejected,
    ]);

    // Restoring the rejected proposal and approving all brings every one back.
    expect(edits.setRejected(result, reviewOf(result), const [], 1, rejected: false), isEmpty);
    expect(storedReview(edits, best.runId), isNull);
    expect(edits.approveAll(result, reviewOf(result), const []).approved, 1);
    result = calculate(edits);
    expect(result.segments, hasLength(count));
    expect(result.segmentsAutomatic, isTrue);

    // Every step undoes in order.
    expect(edits.undo(const []), isEmpty);
    expect(edits.undo(const []), isEmpty);
    expect(storedReview(edits, best.runId), isNotNull);
    expect(edits.undo(const []), isEmpty);
    expect(calculate(edits).segments, hasLength(count - 2));
    expect(storedReview(edits, best.runId), isNotNull);
  });

  group('saved', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('day_segment_review'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('rejections are saved as Overlays stores them and kept on later saves', () {
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
      final dayRuns = outingRuns(named);
      var result = dayTheoreticalBest(day, dayRuns, random: Random(1));
      expect(result.state, DayTheoreticalBestState.ready, reason: result.message);
      expect(edits.remove(result, result.approvedSegment(0)!['id']! as String), isEmpty);
      result = dayTheoreticalBest(
        day,
        dayRuns,
        documentRuns: edits.applyTo(const []),
        random: Random(1),
      );
      var review = dayProposalReview(
        result,
        segmentReviewLap(result),
        dayRuns[result.segmentRunId],
      );
      expect(review.ready, isTrue, reason: review.message);
      expect(edits.setRejected(result, review, const [], 0), isEmpty);
      final document = dayDocument(
        eventId: eventId,
        name: 'Day',
        runs: named,
        analysis: day,
        projectPath: path,
        trackSegments: edits.runs,
        trackSegmentReviews: edits.reviews,
      );
      expect(fet.validateFetproject(document), isNull);
      List<Map<String, Object?>> runsOf(Map<String, Object?> document) =>
          ((document['event'] as Map<String, Object?>)['runs'] as List<Object?>)
              .cast<Map<String, Object?>>();
      Map<String, Object?> runOf(Map<String, Object?> document) =>
          runsOf(document).firstWhere((run) => run['id'] == result.segmentRunId);
      expect(runOf(document)['trackSegmentReview'], edits.reviews[result.segmentRunId]);

      // A later save without edits keeps it, and the reopened day reads it.
      final again = dayDocument(
        eventId: eventId,
        name: 'Day',
        runs: named,
        analysis: day,
        projectPath: path,
        previous: document,
        previousPath: path,
      );
      expect(runOf(again)['trackSegmentReview'], runOf(document)['trackSegmentReview']);
      final reopened = dayTheoreticalBest(day, dayRuns, documentRuns: runsOf(again));
      review = dayProposalReview(
        reopened,
        segmentReviewLap(reopened),
        dayRuns[reopened.segmentRunId],
      );
      expect(
        review.items(reopened.runSegments, runOf(again)['trackSegmentReview'])[0].state,
        SegmentReviewState.rejected,
      );

      // Taking the last rejection back removes the key.
      final restore = DaySegmentEdits();
      expect(restore.setRejected(reopened, review, runsOf(again), 0, rejected: false), isEmpty);
      final cleared = dayDocument(
        eventId: eventId,
        name: 'Day',
        runs: named,
        analysis: day,
        projectPath: path,
        previous: again,
        previousPath: path,
        trackSegments: restore.runs,
        trackSegmentReviews: restore.reviews,
      );
      expect(runOf(cleared).containsKey('trackSegmentReview'), isFalse);
      expect(runOf(cleared)['trackSegments'], runOf(again)['trackSegments']);
      expect(fet.validateFetproject(cleared), isNull);
    });
  });
}
