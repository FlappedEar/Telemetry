import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/segment_editor_page.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'recovery_test.dart' show FileRecoveryStore;
import 'rectangle_vbo.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('segments'));
  tearDown(() => directory.deleteSync(recursive: true));

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

  List<Map<String, Object?>> runsOf(Map<String, Object?> document) =>
      ((document['event'] as Map<String, Object?>)['runs'] as List)
          .cast<Map<String, Object?>>();

  test('an edit marks the day unsaved, is kept for recovery and saved as approved segments', () async {
    final outcome = importDay();
    final store = FileRecoveryStore(
      '${directory.path}/support/day-recovery.json',
    );
    final saved = <Map<String, Object?>>[];
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      recovery: store,
      writer: (path, document) async => saved.add(document),
    );
    final path = '${directory.path}/day.fetproject';
    await controller.save(path);
    expect(controller.dirty, isFalse);

    await controller.requestTheoreticalBest();
    var result = controller.theoreticalBest!;
    expect(result.segmentsAutomatic, isTrue);
    final id = result.approvedSegment(0)!['id']! as String;
    final segment = result.segments[0];
    expect(
      controller.editSegment(
        id,
        name: 'Hairpin',
        type: 'sector',
        startMeters: segment.startProgressMeters,
        endMeters: segment.endProgressMeters + 10,
      ),
      isEmpty,
    );
    expect(controller.dirty, isTrue);
    expect(controller.theoreticalBest, isNull);
    expect(controller.canUndoSegmentEdit, isTrue);
    await controller.requestTheoreticalBest();
    result = controller.theoreticalBest!;
    expect(result.segments[0].name, 'Hairpin');
    expect(result.segments[0].type, 'sector');
    expect(
      result.segments[1].startProgressMeters,
      closeTo(segment.endProgressMeters + 10, 1e-9),
    );
    expect(result.segmentsAutomatic, isFalse);

    // Recovery keeps the edit; the recovered day shows it.
    await controller.flushRecovery();
    final kept = (await store.load())!;
    final recovered = openRecoveredDay(kept);
    final reopened = dayTheoreticalBest(
      recovered.analysis!,
      outingRuns(recovered.runs),
      documentRuns: runsOf(kept.document),
    );
    expect(reopened.segments[0].name, 'Hairpin');
    expect(reopened.automaticSegments, isFalse);

    // Saving writes the edited segments; the next save keeps them.
    await controller.save(path);
    final edited = runsOf(saved.last)
        .firstWhere((run) => run['id'] == result.segmentRunId)['trackSegments'];
    expect(
      (edited! as List).cast<Map<String, Object?>>().first['name'],
      'Hairpin',
    );
    expect(controller.dirty, isFalse);
    final other = controller.analysis.rows.firstWhere(
      (row) =>
          row.type == LapSectionType.lap &&
          row.reference != controller.ranking!.bestOfDay!.reference,
    );
    expect(controller.exclude(other, 'Test'), isTrue);
    await controller.save(path);
    expect(
      runsOf(
        saved.last,
      ).firstWhere((run) => run['id'] == result.segmentRunId)['trackSegments'],
      edited,
    );
    await controller.flushRecovery();
    controller.dispose();
  });

  testWidgets(
    'the segment editor renames, moves, splits, merges, removes and restores on a phone',
    (tester) async {
      final outcome = importDay();
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
      );
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
      await tester.ensureVisible(find.byKey(const ValueKey('editSegments')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editSegments')));
      await tester.pumpAndSettle();

      Future<void> tapKey(String key) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      expect(find.byType(SegmentEditorPage), findsOneWidget);
      expect(find.byKey(const ValueKey('segmentMap')), findsOneWidget);
      expect(find.text('Automatic segments'), findsOneWidget);
      final count = controller.theoreticalBest!.segments.length;
      final before = controller.theoreticalBest!;
      final id0 = before.approvedSegment(0)!['id']! as String;
      final boundaries = tester
          .widget<TrackMap>(find.byKey(const ValueKey('segmentMap')))
          .marks;
      expect(boundaries, hasLength(count));

      // Rename and retype.
      await tester.tap(find.byKey(ValueKey('segment $id0')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TrackMap>(find.byKey(const ValueKey('segmentMap'))).marks,
        hasLength(count + 1),
      );
      await tester.enterText(
        find.byKey(const ValueKey('segmentName')),
        'Hairpin',
      );
      await tester.tap(find.text('Sector'));
      await tester.pump();
      await tapKey('applySegment');
      var result = controller.theoreticalBest!;
      expect(result.segments[0].name, 'Hairpin');
      expect(result.segments[0].type, 'sector');
      expect(find.text('Edited segments'), findsOneWidget);
      expect(controller.dirty, isTrue);

      // Move the end 11 m on, with the next segment's start.
      await tapKey('segmentEnd +10');
      await tapKey('segmentEnd +1');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('segmentEnd value')))
            .data,
        '${(before.segments[0].endProgressMeters + 11).toStringAsFixed(1)} m',
      );
      await tapKey('applySegment');
      result = controller.theoreticalBest!;
      expect(
        result.segments[0].endProgressMeters,
        closeTo(before.segments[0].endProgressMeters + 11, 1e-3),
      );
      expect(
        result.segments[1].startProgressMeters,
        result.segments[0].endProgressMeters,
      );
      expect(
        result.segments[0].seconds,
        greaterThan(before.segments[0].seconds!),
      );

      // Split in the middle, then merge back.
      await tapKey('splitSegment');
      expect(controller.theoreticalBest!.segments, hasLength(count + 1));
      expect(controller.theoreticalBest!.segments[1].name, 'Hairpin (2)');
      await tapKey('mergeSegment');
      expect(controller.theoreticalBest!.segments, hasLength(count));

      // Remove, then undo.
      await tapKey('removeSegment');
      expect(controller.theoreticalBest!.segments, hasLength(count - 1));
      await tester.tap(find.byKey(const ValueKey('undoSegmentEdit')));
      await tester.pumpAndSettle();
      expect(controller.theoreticalBest!.segments, hasLength(count));
      expect(controller.theoreticalBest!.segments[0].name, 'Hairpin');

      // Restore the automatic segments.
      await tester.tap(find.byKey(const ValueKey('restoreAutomatic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmRestore')));
      await tester.pumpAndSettle();
      result = controller.theoreticalBest!;
      expect(result.segmentsAutomatic, isTrue);
      expect(
        result.segments.map((s) => s.name),
        before.segments.map((s) => s.name),
      );
      expect(
        result.theoreticalBestSeconds,
        closeTo(before.theoreticalBestSeconds!, 1e-9),
      );
      expect(find.text('Automatic segments'), findsOneWidget);

      // Back on the results, the card shows the recalculated result.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('theoreticalBestTime')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
