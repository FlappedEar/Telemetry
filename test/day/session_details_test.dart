// Editing a session's name, conditions, setup changes and notes, and
// renaming the day (FET-52). Synthetic recordings only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_page_test.dart' show FakeDocuments, circuitVbo;
import 'recovery_test.dart' show FileRecoveryStore;

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('details'));
  tearDown(() => directory.deleteSync(recursive: true));

  DayImportOutcome importDay() {
    final paths = <String>[];
    for (final (name, speeds) in [
      ('a.vbo', <double>[30, 28, 31]),
      ('b.vbo', <double>[29, 32]),
    ]) {
      final path = '${directory.path}/$name';
      File(path).writeAsStringSync(circuitVbo(speeds));
      paths.add(path);
    }
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  Map<String, Object?> documentRun(Map<String, Object?> document, String id) =>
      ((document['event']! as Map)['runs']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((run) => run['id'] == id);

  Finder detailsTile(String runId) =>
      find.byKey(ValueKey('sessionDetails $runId'));

  testWidgets('edits a session\'s details and saves them with the day', (
    tester,
  ) async {
    final outcome = importDay();
    final saved = <Map<String, Object?>>[];
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async => saved.add(document),
    );
    final first = outcome.runs.first.run.id;
    final documents = FakeDocuments(location: '${directory.path}/d.fetproject');
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: documents,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Session details'), findsOneWidget);
    expect(
      find.text('No conditions, setup changes or notes'),
      findsNWidgets(2),
    );

    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    expect(find.text('Details of Session 1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sessionDetailsName')),
      '',
    );
    await tester.pump();
    expect(find.text('A session needs a name.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('sessionDetailsSave')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('sessionDetailsName')),
      '  Warm-up ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Conditions'),
      'Dry, 18 °C',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Setup changes'),
      'Tyres +0.1 bar',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'Brake earlier into T1',
    );
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();

    expect(controller.dirty, isTrue);
    expect(
      find.text(
        'Conditions: Dry, 18 °C\nSetup changes: Tyres +0.1 bar\n'
        'Notes: Brake earlier into T1',
      ),
      findsOneWidget,
    );
    // The laps and results name the session as renamed.
    expect(find.text('Warm-up · LAP 1'), findsWidgets);
    expect(
      {
        for (final row in controller.analysis.rows)
          if (row.runId == first) row.runName,
      },
      {'Warm-up'},
    );
    expect(
      controller.progressionRuns.firstWhere((run) => run.id == first).notes,
      'Brake earlier into T1',
    );

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    final run = documentRun(saved.single, first);
    expect(run['name'], 'Warm-up');
    expect(run['conditions'], 'Dry, 18 °C');
    expect(run['setupChanges'], 'Tyres +0.1 bar');
    expect(run['notes'], 'Brake earlier into T1');
    final other = documentRun(saved.single, outcome.runs.last.run.id);
    for (final key in runMetadataTextKeys) {
      expect(other.containsKey(key), isFalse, reason: key);
    }

    // Cleared afterwards: null in the file, as Overlays writes it.
    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    expect(find.text('Details of Warm-up'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Notes'), '');
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();
    expect(controller.dirty, isTrue);
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    final cleared = documentRun(saved.last, first);
    expect(cleared.containsKey('notes'), isTrue);
    expect(cleared['notes'], isNull);
    expect(cleared['conditions'], 'Dry, 18 °C');

    // Saving with nothing changed leaves the day clean.
    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();
  });

  testWidgets('a text too long as the file counts it is refused under all '
      'the fields', (tester) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async {},
    );
    final first = outcome.runs.first.run.id;
    final documents = FakeDocuments(location: '${directory.path}/d.fetproject');
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: documents,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    // 3000 emoji fit the field's limit but are 6000 UTF-16 units.
    final notes = find.widgetWithText(TextField, 'Notes');
    await tester.enterText(notes, '\u{1F3CE}' * 3000);
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sessionDetailsInvalid')), findsOneWidget);
    expect(find.text('Details of Session 1'), findsOneWidget);
  });

  testWidgets('renames the day from the menu', (tester) async {
    final outcome = importDay();
    final saved = <Map<String, Object?>>[];
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async => saved.add(document),
    );
    final documents = FakeDocuments(location: '${directory.path}/d.fetproject');
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: documents,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename day…'));
    await tester.pumpAndSettle();
    expect(find.text('Rename day'), findsOneWidget);
    final field = find.byKey(const ValueKey('renameDayName'));
    expect(tester.widget<TextField>(field).controller!.text, 'Day');
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(find.text('A day needs a name.'), findsOneWidget);
    await tester.enterText(field, ' Łódź, morning ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('renameDaySave')));
    await tester.pumpAndSettle();
    expect(controller.name, 'Łódź, morning');

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    // The save offers the new name, and the title shows it.
    expect(documents.names, ['Łódź, morning']);
    expect((saved.single['event']! as Map)['name'], 'Łódź, morning');
    expect(find.text('Łódź, morning'), findsOneWidget);
  });

  test('refuses names and texts Overlays would refuse', () {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async {},
    );
    addTearDown(controller.dispose);
    final first = outcome.runs.first.run.id;
    expect(controller.renameDay(' '), isNotNull);
    expect(controller.renameDay('x' * 161), isNotNull);
    expect(controller.renameDay('a\u0000'), isNotNull);
    expect(
      controller.updateRunMetadata(first, const RunMetadata(name: ' ')),
      isNotNull,
    );
    expect(
      controller.updateRunMetadata(
        first,
        RunMetadata(name: 'A', notes: 'n' * 4097),
      ),
      isNotNull,
    );
    expect(
      controller.updateRunMetadata('nope', const RunMetadata(name: 'A')),
      isNotNull,
    );
    expect(controller.name, 'Day');
    expect(controller.runMetadata(first), const RunMetadata(name: 'Session 1'));
  });

  test('keeps unsaved details for recovery', () async {
    final outcome = importDay();
    final store = FileRecoveryStore('${directory.path}/support/recovery.json');
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      recovery: store,
      writer: (path, document) async {},
    );
    final first = outcome.runs.first.run.id;
    expect(
      controller.updateRunMetadata(
        first,
        const RunMetadata(name: 'Warm-up', conditions: 'Wet'),
      ),
      isNull,
    );
    expect(controller.renameDay('Rainy day'), isNull);
    await controller.flushRecovery();
    controller.dispose();

    final kept = (await store.load())!;
    final restored = DayResultsController.recovered(
      openRecoveredDay(kept),
      kept,
      recovery: store,
    );
    addTearDown(restored.dispose);
    expect(restored.dirty, isTrue);
    expect(restored.name, 'Rainy day');
    expect(
      restored.runMetadata(first),
      const RunMetadata(name: 'Warm-up', conditions: 'Wet'),
    );
    expect(
      restored.analysis.rows.where((row) => row.runId == first).first.runName,
      'Warm-up',
    );
  });

  testWidgets('the details dialog speaks Polish on a phone with large text', (
    tester,
  ) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async {},
    );
    final first = outcome.runs.first.run.id;
    await tester.binding.setSurfaceSize(const Size(360, 740));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: DayResultsPage.controller(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      detailsTile(first),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('dayResultsSummary')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: detailsTile(first), matching: find.text('Sesja 1')),
      findsOneWidget,
    );
    expect(
      tester.getSize(detailsTile(first)).height,
      greaterThanOrEqualTo(kMinInteractiveDimension),
    );
    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    expect(find.text('Szczegóły: Sesja 1'), findsOneWidget);
    final name = find.byKey(const ValueKey('sessionDetailsName'));
    expect(tester.widget<TextField>(name).controller!.text, 'Sesja 1');
    expect(find.text('Warunki'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Warunki'), 'Mokro');
    await tester.ensureVisible(find.text('Zapisz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The name shown in Polish stays the one in the file.
    expect(
      controller.runMetadata(first),
      const RunMetadata(name: 'Session 1', conditions: 'Mokro'),
    );
    expect(controller.runs.first.name, 'Session 1');
  });
}
