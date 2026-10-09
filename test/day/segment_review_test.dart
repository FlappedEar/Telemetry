import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/segment_editor_page.dart';
import 'package:telemetry/day/segment_review_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'recovery_test.dart' show FileRecoveryStore;
import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('review'));
  tearDown(() => deleteTemporaryDirectory(directory));

  DayImportOutcome importDay() {
    final files = {
      'a.vbo': [
        rectangleLap(30, 50, 120, 20),
        rectangleLap(31, 300, 400, 25),
        rectangleLap(30, 550, 650, 22),
      ],
      'b.vbo': [rectangleLap(29), rectangleLap(30.5, 700, 780, 20)],
    };
    final paths = <String>[];
    files.forEach((name, laps) {
      final path = '${directory.path}/$name';
      File(path).writeAsStringSync(rectangleVbo(laps));
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  Future<void> tapKey(WidgetTester tester, Finder finder) async {
    // The review's buttons scroll with its proposals: back to the top.
    final list = find.byKey(const ValueKey('proposalList'));
    if (finder.evaluate().isEmpty && list.evaluate().isNotEmpty) {
      await tester.drag(list, const Offset(0, 3000));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // From the day's results to the segment editor, then the review.
  Future<void> openReview(
    WidgetTester tester,
    DayResultsController controller,
  ) async {
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('editSegments')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('dayResultsSummary')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tapKey(tester, find.byKey(const ValueKey('editSegments')));
    expect(find.byType(SegmentEditorPage), findsOneWidget);
    await tapKey(tester, find.byKey(const ValueKey('reviewProposals')));
    expect(find.byType(SegmentReviewPage), findsOneWidget);
  }

  Finder inCard(int index, String key) => find.descendant(
    of: find.byKey(ValueKey('proposal $index')),
    matching: find.byKey(ValueKey(key)),
  );

  List<SegmentReviewState> states(DayResultsController controller) => [
    for (final item in controller.segmentReviewItems) item.state,
  ];

  testWidgets(
    'the review shows each proposal, all approved, without asking for anything',
    (tester) async {
      final outcome = importDay();
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
      );
      await openReview(tester, controller);
      expect(find.byKey(const ValueKey('reviewUnusedKept')), findsNothing);

      final result = controller.theoreticalBest!;
      final review = controller.segmentReview!;
      final count = result.segments.length;
      expect(review.lap!.reference, result.bestLap!.reference);
      expect(
        find.text('$count proposals from ${result.bestLap!.displayName}'),
        findsOneWidget,
      );
      expect(
        states(controller),
        List.filled(count, SegmentReviewState.approved),
      );
      // Automatic segments need no decision: nothing to approve or reject.
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('approveAllProposals')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('rejectProposal')), findsNothing);
      expect(controller.dirty, isTrue); // a new day, never saved

      // A corner: its state, turn, bounds with tolerance, and apex.
      final corner = review.proposals.indexWhere(
        (proposal) => proposal.type.name == 'corner',
      );
      final proposal = review.proposals[corner];
      final card = find.byKey(ValueKey('proposal $corner'));
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('proposalList')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      Finder text(String data) =>
          find.descendant(of: card, matching: find.text(data));
      expect(text('Approved'), findsOneWidget);
      expect(text(proposal.name), findsOneWidget);
      final degrees = (proposal.turnRadians * 180 / 3.141592653589793)
          .abs()
          .toStringAsFixed(0);
      expect(
        text(
          'Corner · $degrees° ${proposal.turnRadians > 0 ? 'left' : 'right'}',
        ),
        findsOneWidget,
      );
      expect(
        text(
          '${proposal.start.progressMeters.toStringAsFixed(1)}\u00a0m '
          '±${proposal.start.toleranceMeters.toStringAsFixed(0)} → '
          '${proposal.end.progressMeters.toStringAsFixed(1)}\u00a0m '
          '±${proposal.end.toleranceMeters.toStringAsFixed(0)} '
          '(${proposal.lengthMeters.toStringAsFixed(1)}\u00a0m)',
        ),
        findsOneWidget,
      );
      final apex = review.phases[corner]!.apex;
      expect(apex.resolved, isTrue);
      expect(
        text(
          'Geometric apex ${apex.progressMeters.toStringAsFixed(1)}\u00a0m '
          '±${apex.toleranceMeters.toStringAsFixed(0)}\u00a0m',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reject, undo, redo, approve all and recompute', (tester) async {
    final outcome = importDay();
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    // Two segments removed in the editor: their proposals are open again.
    await controller.requestTheoreticalBest();
    var result = controller.theoreticalBest!;
    final count = result.segments.length;
    expect(
      controller.removeSegment(result.approvedSegment(0)!['id']! as String),
      isEmpty,
    );
    await controller.requestTheoreticalBest();
    result = controller.theoreticalBest!;
    expect(
      controller.removeSegment(result.approvedSegment(0)!['id']! as String),
      isEmpty,
    );
    await openReview(tester, controller);
    expect(controller.theoreticalBest!.segments, hasLength(count - 2));
    expect(states(controller).take(3), [
      SegmentReviewState.proposed,
      SegmentReviewState.proposed,
      SegmentReviewState.approved,
    ]);
    expect(find.byKey(const ValueKey('rejectProposal')), findsNWidgets(2));

    // Reject the second: shown as rejected, nothing is timed again.
    final timed = controller.theoreticalBest;
    await tapKey(tester, inCard(1, 'rejectProposal'));
    expect(states(controller)[1], SegmentReviewState.rejected);
    expect(inCard(1, 'restoreProposal'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('proposal 1')),
        matching: find.text('Rejected'),
      ),
      findsOneWidget,
    );
    expect(identical(controller.theoreticalBest, timed), isTrue);
    expect(controller.dirty, isTrue);

    // Undone and redone with the rest of the segment history.
    await tapKey(tester, find.byKey(const ValueKey('undoReview')));
    expect(states(controller)[1], SegmentReviewState.proposed);
    await tapKey(tester, find.byKey(const ValueKey('redoReview')));
    expect(states(controller)[1], SegmentReviewState.rejected);

    // Approve all approves the open proposal, not the rejected one.
    await tapKey(tester, find.byKey(const ValueKey('approveAllProposals')));
    expect(find.text('1 proposal approved'), findsOneWidget);
    expect(controller.theoreticalBest!.segments, hasLength(count - 1));
    expect(states(controller).take(2), [
      SegmentReviewState.approved,
      SegmentReviewState.rejected,
    ]);
    await tapKey(tester, find.byKey(const ValueKey('undoReview')));
    expect(controller.theoreticalBest!.segments, hasLength(count - 2));
    expect(states(controller)[0], SegmentReviewState.proposed);
    await tapKey(tester, find.byKey(const ValueKey('redoReview')));
    expect(controller.theoreticalBest!.segments, hasLength(count - 1));

    // Recompute: the same proposals again, decisions kept.
    final before = controller.segmentReview!;
    await tapKey(tester, find.byKey(const ValueKey('recomputeProposals')));
    final after = controller.segmentReview!;
    expect(identical(after, before), isFalse);
    expect(after.proposals, hasLength(before.proposals.length));
    expect(states(controller).take(2), [
      SegmentReviewState.approved,
      SegmentReviewState.rejected,
    ]);

    // Restore the rejected one, then approve all: every proposal approved,
    // the segments are the automatic ones again.
    await tapKey(tester, inCard(1, 'restoreProposal'));
    expect(states(controller)[1], SegmentReviewState.proposed);
    await tapKey(tester, find.byKey(const ValueKey('approveAllProposals')));
    expect(controller.theoreticalBest!.segments, hasLength(count));
    expect(controller.theoreticalBest!.segmentsAutomatic, isTrue);
    expect(states(controller), List.filled(count, SegmentReviewState.approved));

    // Back in the editor, its undo goes through the same history.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, find.byKey(const ValueKey('undoSegmentEdit')));
    expect(controller.theoreticalBest!.segments, hasLength(count - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejection is saved as Overlays stores it and opens again', (
    tester,
  ) async {
    final outcome = importDay();
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = '${directory.path}/day.fetproject';
    final saved = <Map<String, Object?>>[];
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async {
        saved.add(document);
        await saveDayDocument(path, document);
      },
    );
    await controller.requestTheoreticalBest();
    final result = controller.theoreticalBest!;
    expect(
      controller.removeSegment(result.approvedSegment(0)!['id']! as String),
      isEmpty,
    );
    await openReview(tester, controller);
    await tapKey(tester, inCard(0, 'rejectProposal'));
    final review = controller.segmentReview!;
    final rejected = review.proposals[0];

    await tester.runAsync(() => controller.save(path));
    await tester.pumpAndSettle();
    expect(controller.dirty, isFalse);
    Map<String, Object?> runOf(Map<String, Object?> document) =>
        ((document['event'] as Map<String, Object?>)['runs'] as List)
            .cast<Map<String, Object?>>()
            .firstWhere((run) => run['id'] == review.runId);
    final stored = runOf(saved.last)['trackSegmentReview'];
    expect(stored, {
      'version': 'track-segment-review-v1',
      'trackConfigurationReference': review.groupId,
      'proposalAlgorithm': 'track-segment-proposal-v2',
      'rejected': [
        {
          'type': rejected.type.name,
          'startProgressMeters': rejected.start.progressMeters,
          'endProgressMeters': rejected.end.progressMeters,
        },
      ],
    });
    expect(validTrackSegmentReview(stored), isTrue);
    // The segments saved are the ones approved now, without the removed one.
    expect(
      runOf(saved.last)['trackSegments'],
      hasLength(result.segments.length - 1),
    );

    // Opened again: the proposal is still rejected; a later save keeps it.
    // The first day's pages close (and dispose of its controller).
    await tester.pumpWidget(const SizedBox());
    final opened = (await tester.runAsync(() async => openDay(path)))!;
    final reopened = DayResultsController.opened(
      opened,
      writer: (path, document) async => saved.add(document),
    );
    await reopened.requestTheoreticalBest();
    await tester.pumpWidget(
      TelemetryApp(home: SegmentReviewPage(controller: reopened)),
    );
    await tester.pumpAndSettle();
    expect(reopened.segmentReviewItems[0].state, SegmentReviewState.rejected);
    expect(inCard(0, 'restoreProposal'), findsOneWidget);
    await tester.runAsync(() => reopened.save(path));
    expect(runOf(saved.last)['trackSegmentReview'], stored);

    // Restored, saved: the key goes, as Overlays removes an empty review.
    await tapKey(tester, inCard(0, 'restoreProposal'));
    await tester.runAsync(() => reopened.save(path));
    expect(runOf(saved.last).containsKey('trackSegmentReview'), isFalse);
    expect(
      runOf(saved.last)['trackSegments'],
      hasLength(result.segments.length - 1),
    );
    reopened.dispose();
    expect(tester.takeException(), isNull);
  });

  test('a recovery snapshot keeps the rejections', () async {
    final outcome = importDay();
    final store = FileRecoveryStore(
      '${directory.path}/support/day-recovery.json',
    );
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      recovery: store,
    );
    await controller.requestTheoreticalBest();
    final result = controller.theoreticalBest!;
    expect(
      controller.removeSegment(result.approvedSegment(0)!['id']! as String),
      isEmpty,
    );
    await controller.requestTheoreticalBest();
    await controller.requestSegmentReview();
    expect(controller.rejectSegmentProposal(0), isNull);
    final runId = controller.segmentReview!.runId;
    await controller.flushRecovery();

    final kept = (await store.load())!;
    final run =
        ((kept.document['event'] as Map<String, Object?>)['runs'] as List)
            .cast<Map<String, Object?>>()
            .firstWhere((run) => run['id'] == runId);
    final stored = run['trackSegmentReview'];
    expect(validTrackSegmentReview(stored), isTrue);
    expect((stored! as Map<String, Object?>)['rejected'], hasLength(1));

    // The recovered day shows the proposal rejected.
    final recovered = DayResultsController.recovered(
      openRecoveredDay(kept),
      kept,
    );
    expect(recovered.dirty, isTrue);
    await recovered.requestTheoreticalBest();
    await recovered.requestSegmentReview();
    expect(recovered.segmentReviewItems[0].state, SegmentReviewState.rejected);
    controller.dispose();
    recovered.dispose();
  });

  testWidgets('segments saved under another route group are reported', (
    tester,
  ) async {
    final outcome = importDay();
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = FileRecoveryStore(
      '${directory.path}/support/day-recovery.json',
    );
    late DayResultsController first;
    late DayResultsController recovered;
    late int moved;
    await tester.runAsync(() async {
      first = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        recovery: store,
      );
      await first.requestTheoreticalBest();
      expect(
        first.removeSegment(
          first.theoreticalBest!.approvedSegment(0)!['id']! as String,
        ),
        isEmpty,
      );
      expect(first.unusedStoredSegments, 0);
      await first.flushRecovery();
      final kept = (await store.load())!;

      // The group the segments were saved under no longer exists: they are
      // in the document, but no run uses them (FET-267).
      final old = 'compatibility-v1:${'a' * 64}';
      moved = 0;
      for (final run
          in ((kept.document['event'] as Map<String, Object?>)['runs'] as List)
              .cast<Map<String, Object?>>()) {
        for (final segment
            in ((run['trackSegments'] as List?) ?? const [])
                .cast<Map<String, Object?>>()) {
          segment['trackConfigurationReference'] = old;
          ++moved;
        }
      }
      expect(moved, greaterThan(0));
      recovered = DayResultsController.recovered(openRecoveredDay(kept), kept);
      expect(recovered.unusedStoredSegments, moved);
    });
    await tester.pumpWidget(
      TelemetryApp(home: SegmentReviewPage(controller: recovered)),
    );
    await tester.runAsync(() async {
      await recovered.requestTheoreticalBest();
      await recovered.requestSegmentReview();
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reviewUnusedKept')), findsOneWidget);
    first.dispose();
    recovered.dispose();
  });

  test(
    'every reason a change was not made has its own text in both languages',
    () {
      for (final locale in supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        final texts = {
          for (final issue in SegmentChangeIssue.values)
            segmentChangeIssueText(l10n, issue),
        };
        expect(texts, hasLength(SegmentChangeIssue.values.length));
        expect(texts.every((text) => text.isNotEmpty), isTrue);
      }
      expect(
        segmentChangeIssueText(
          lookupAppLocalizations(const Locale('pl')),
          SegmentChangeIssue.historyCleared,
        ),
        isNot(SegmentChangeIssue.historyCleared.message),
      );
    },
  );
}
