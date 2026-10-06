// Removing a session from a day, and Undo (FET-241). Synthetic recordings
// only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_page_test.dart' show FakeDocuments, circuitVbo;

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('remove'));
  tearDown(() => directory.deleteSync(recursive: true));

  DayImportOutcome importDay(Map<String, List<double>> recordings) =>
      runDayImport((
        paths: [
          for (final MapEntry(:key, :value) in recordings.entries)
            (File(
              '${directory.path}/$key',
            )..writeAsStringSync(circuitVbo(value))).path,
        ],
        includeSubfolders: false,
      ));

  List<String> savedRunIds(String path) =>
      dayDocumentRunIds(readDayDocument(path));

  /// Pumps, letting file writes finish, until [done].
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var tries = 0; tries < 100 && !done(); tries++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('removes a session from its details, then puts it back', (
    tester,
  ) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32, 33],
    });
    final path = '${directory.path}/Day.fetproject';
    final opened = (await tester.runAsync(() async {
      await saveDayDocument(
        path,
        dayDocument(
          eventId: newEventId(),
          name: 'Track day',
          runs: outcome.runs,
          analysis: outcome.analysis!,
          projectPath: path,
        ),
      );
      return openDay(path);
    }))!;
    final kept = opened.runs.first.run.id;
    final removed = opened.runs.last.run.id;
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          // Written at once: the test's clock is not the file system's.
          controller: DayResultsController.opened(
            opened,
            writer: (path, document) async =>
                File(path).writeAsStringSync(jsonEncode(document)),
          ),
          documents: FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final removedTile = find.byKey(ValueKey('sessionDetails $removed'));
    await tester.tap(removedTile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sessionDetailsRemove')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Session 2?'), findsOneWidget);

    // Cancelled: the day stays as it is.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removedTile, findsOneWidget);
    expect(savedRunIds(path), [kept, removed]);

    await tester.tap(removedTile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sessionDetailsRemove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('removeSessionConfirm')));
    await settleUntil(tester, () => removedTile.evaluate().isEmpty);

    expect(removedTile, findsNothing);
    expect(find.byKey(ValueKey('sessionDetails $kept')), findsOneWidget);
    expect(savedRunIds(path), [kept]);
    expect(find.text('Session 2 removed from the day.'), findsOneWidget);
    // The day's laps are those of the session left.
    expect(find.textContaining('Session 2 · LAP'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sessionRemovedUndo')));
    await settleUntil(tester, () => removedTile.evaluate().isNotEmpty);
    expect(removedTile, findsOneWidget);
    expect(savedRunIds(path), [kept, removed]);
    expect(find.text('Session 2 is back in the day.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removes a session whose recording is missing from the menu', (
    tester,
  ) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32, 33],
    });
    final path = '${directory.path}/Day.fetproject';
    final opened = (await tester.runAsync(() async {
      await saveDayDocument(
        path,
        dayDocument(
          eventId: newEventId(),
          name: 'Track day',
          runs: outcome.runs,
          analysis: outcome.analysis!,
          projectPath: path,
        ),
      );
      File('${directory.path}/b.vbo').deleteSync();
      return openDay(path);
    }))!;
    final missing = opened.missing.single.runId;
    await tester.binding.setSurfaceSize(const Size(1200, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: DayResultsController.opened(
            opened,
            writer: (path, document) async =>
                File(path).writeAsStringSync(jsonEncode(document)),
          ),
          documents: FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 session could not be opened'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('moreMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove a session…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('removeSessionChoice $missing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('removeSessionConfirm')));
    final card = find.text('1 session could not be opened');
    await settleUntil(tester, () => card.evaluate().isEmpty);
    expect(card, findsNothing);
    expect(savedRunIds(path), [opened.runs.single.run.id]);
  });

  testWidgets('a day keeps its only session', (tester) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
    });
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async {},
    );
    await tester.binding.setSurfaceSize(const Size(1200, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('moreMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove a session…'));
    await tester.pumpAndSettle();
    expect(find.text('Remove which session?'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('removeSessionChoice ${outcome.runs.single.run.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A day keeps at least one session. To remove the whole day, '
        'delete it in the Library.',
      ),
      findsOneWidget,
    );
    expect(controller.runs, hasLength(1));
  });
}
