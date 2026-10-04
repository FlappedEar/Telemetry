import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/segment_editor_page.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'recovery_test.dart' show FileRecoveryStore;
import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('segments'));
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
        '${(before.segments[0].endProgressMeters + 11).toStringAsFixed(1)}\u00a0m',
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
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('theoreticalBestTime')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('theoreticalBestTime')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the segment editor speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: SegmentEditorPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edytuj segmenty'), findsOneWidget);
    expect(find.text('Segmenty automatyczne'), findsOneWidget);
    expect(find.textContaining('Teoretycznie najlepsze '), findsOneWidget);
    expect(find.textContaining('Zaproponowane na podstawie: '), findsOneWidget);
    expect(find.textContaining('OKR.'), findsOneWidget);
    // Automatic segment names and types.
    expect(find.textContaining(RegExp(r'^(Zakręty?|Prosta) \d')), findsWidgets);
    expect(find.textContaining(RegExp(r'^(Zakręt|Prosta) · ')), findsWidgets);
    expect(find.text('Edit segments'), findsNothing);
    expect(find.text('Automatic segments'), findsNothing);

    final id0 =
        controller.theoreticalBest!.approvedSegment(0)!['id']! as String;
    await tester.tap(find.byKey(ValueKey('segment $id0')));
    await tester.pumpAndSettle();
    expect(find.text('Nazwa'), findsOneWidget);
    expect(find.text('Sektor'), findsOneWidget);
    expect(find.text('Początek'), findsOneWidget);
    expect(find.text('Przesuń też sąsiedni segment'), findsOneWidget);
    expect(find.text('Zastosuj'), findsOneWidget);
    expect(find.text('Podziel tutaj'), findsOneWidget);
    expect(find.textContaining('Połącz z '), findsOneWidget);
    expect(find.text('Usuń'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);

    // A refused edit is explained in Polish.
    await tester.enterText(find.byKey(const ValueKey('segmentName')), ' ');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('applySegment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('applySegment')));
    await tester.pump();
    expect(find.text('Wpisz nazwę (1–160 znaków).'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Polish, applying without renaming keeps the stored name', (
    tester,
  ) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: SegmentEditorPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    // Short badges in Polish: "Z1" for "Zakręt 1", "P2" for "Prosta 2".
    expect(find.textContaining(RegExp(r'^Z\d')), findsWidgets);

    final before = controller.theoreticalBest!.approvedSegment(0)!;
    final id0 = before['id']! as String;
    final stored = before['name']! as String;
    await tester.tap(find.byKey(ValueKey('segment $id0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('segmentName')))
          .controller!
          .text,
      isNot(stored),
    );
    await tester.tap(find.text('Sektor'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('applySegment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('applySegment')));
    for (var i = 0; i < 20 && controller.theoreticalBestLoading; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final after = controller.theoreticalBest!.approvedSegment(0)!;
    expect(after['name'], stored);
    expect(after['type'], 'sector');
  });

  testWidgets('a boundary is picked on the map by touch, applied and undone', (
    tester,
  ) async {
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

    final before = controller.theoreticalBest!;
    final best = before.bestLap!;
    final id1 = before.approvedSegment(1)!['id']! as String;
    final segment = before.segments[1];
    await tester.tap(find.byKey(ValueKey('segment $id1')));
    await tester.pumpAndSettle();

    // The fix of the best lap three quarters into the segment.
    final mapFinder = find.byKey(const ValueKey('segmentMap'));
    final path = tester.widget<TrackMap>(mapFinder).path;
    final target =
        segment.startProgressMeters +
        0.75 * (segment.endProgressMeters - segment.startProgressMeters);
    PathPoint? chosen;
    double? chosenProgress;
    for (final part in path.segments) {
      for (final point in part) {
        final at = before.progressAt(best, point.telemetryTime);
        if (at != null &&
            (chosenProgress == null ||
                (at - target).abs() < (chosenProgress - target).abs())) {
          chosen = point;
          chosenProgress = at;
        }
      }
    }
    // Where the plain map draws it (track_map.dart's fit, 16 px padding).
    final box = tester.getRect(mapFinder);
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final part in path.segments) {
      for (final point in part) {
        if (point.eastMeters < minX) minX = point.eastMeters;
        if (point.eastMeters > maxX) maxX = point.eastMeters;
        if (point.northMeters < minY) minY = point.northMeters;
        if (point.northMeters > maxY) maxY = point.northMeters;
      }
    }
    final spanX = maxX - minX, spanY = maxY - minY;
    final scale = [
      (box.width - 32) / spanX,
      (box.height - 32) / spanY,
    ].reduce((a, b) => a < b ? a : b);
    final at = Offset(
      box.left +
          (box.width - spanX * scale) / 2 +
          (chosen!.eastMeters - minX) * scale,
      box.bottom -
          (box.height - spanY * scale) / 2 -
          (chosen.northMeters - minY) * scale,
    );

    Future<void> tapKey(String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    // Started and cancelled.
    await tapKey('pick end');
    expect(find.text('Tap the track line to place the end'), findsOneWidget);
    await tapKey('pick end');
    expect(find.byKey(const ValueKey('segmentPickBanner')), findsNothing);

    // Off the track: said, and still waiting.
    await tapKey('pick end');
    await tester.tapAt(Offset(box.left + 4, box.bottom - 4));
    await tester.pumpAndSettle();
    expect(find.text('Tap on the lap\'s track line.'), findsOneWidget);
    expect(find.byKey(const ValueKey('segmentPickBanner')), findsOneWidget);

    // On the track: the end moves there, to 0.1 m, shown before it applies.
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('segmentPickBanner')), findsNothing);
    final picked = double.parse(chosenProgress!.toStringAsFixed(1));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('segmentEnd value'))).data,
      '${picked.toStringAsFixed(1)}\u00a0m',
    );
    expect(
      controller.theoreticalBest!.segments[1].endProgressMeters,
      segment.endProgressMeters,
    );
    await tapKey('applySegment');
    expect(
      controller.theoreticalBest!.segments[1].endProgressMeters,
      closeTo(picked, 1e-9),
    );
    expect(controller.dirty, isTrue);

    // Undone like any edit.
    await tester.tap(find.byKey(const ValueKey('undoSegmentEdit')));
    await tester.pumpAndSettle();
    expect(
      controller.theoreticalBest!.segments[1].endProgressMeters,
      segment.endProgressMeters,
    );
    await tester.tap(find.byKey(const ValueKey('redoSegmentEdit')));
    await tester.pumpAndSettle();
    expect(
      controller.theoreticalBest!.segments[1].endProgressMeters,
      closeTo(picked, 1e-9),
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'a phone with text ×2 keeps the segments in view, under the map',
    (tester) async {
      addTearDown(() => Intl.defaultLocale = null);
      final outcome = importDay();
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
      );
      addTearDown(controller.dispose);
      final best = controller.ranking!.bestOfDay!;
      final session = controller.session(best.runId)!;
      final origin = mapOrigin(session);
      final path = lapPath(session, best.start, best.end, origin: origin);
      for (final locale in const [Locale('en'), Locale('pl')]) {
        await tester.pumpWidget(
          TelemetryApp(
            locale: locale,
            home: SegmentEditorPage(controller: controller, path: path),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale');
        expect(find.byType(TrackMap), findsOneWidget);
        // The list, header included, scrolls: its first segment is reached.
        final id0 =
            controller.theoreticalBest!.approvedSegment(0)!['id']! as String;
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('segment $id0')),
          100,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('segmentList')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.takeException(), isNull, reason: '$locale scrolled');
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('a desktop window keeps the segments 760 wide', (tester) async {
    final outcome = importDay();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      TelemetryApp(home: SegmentEditorPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('segmentList'))).width,
      lessThanOrEqualTo(760),
    );
    final id0 =
        controller.theoreticalBest!.approvedSegment(0)!['id']! as String;
    await tester.tap(find.byKey(ValueKey('segment $id0')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('applySegment'))).width,
      lessThan(760),
    );
  });
}
