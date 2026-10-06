// Editing a session's name, conditions, setup changes and notes, and
// renaming the day (FET-52); a session's structured setup (FET-188).
// Synthetic recordings only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/session_details_dialog.dart';
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
      find.text('No conditions, setup, setup changes or notes'),
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
      'Dry, 18\u00a0°C',
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
        'Conditions: Dry, 18\u00a0°C\nSetup changes: Tyres +0.1 bar\n'
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
    expect(run['conditions'], 'Dry, 18\u00a0°C');
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
    expect(cleared['conditions'], 'Dry, 18\u00a0°C');

    // Saving with nothing changed leaves the day clean.
    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();
  });

  Finder setupField(String row, String wheel) =>
      find.byKey(ValueKey('sessionSetup $row $wheel'));

  String fieldText(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!.text;

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('sessionDetailsSave')),
          )
          .onPressed !=
      null;

  test('a comma becomes a decimal point; other characters are refused', () {
    final formatter = SetupNumberFormatter();
    TextEditingValue type(String before, String after) =>
        formatter.formatEditUpdate(
          TextEditingValue(text: before),
          TextEditingValue(text: after),
        );
    expect(type('2', '2,').text, '2.');
    expect(type('2', '2,1').text, '2.1');
    expect(type('2.1', '2.15').text, '2.15');
    expect(type('2.15', '2.155').text, '2.15');
    expect(type('30', '300').text, '30');
    expect(type('', 'a').text, '');
    expect(type('', '-').text, '');
    // Pasted with spaces.
    expect(type('', ' 2.1').text, '2.1');
    expect(type('', '2.1 ').text, '2.1');
    expect(type('', '2, 1').text, '2.1');
    expect(
      type('', '2, 1').selection,
      const TextSelection.collapsed(offset: 3),
    );
    expect(
      SetupNumberFormatter(integerDigits: 3)
          .formatEditUpdate(
            const TextEditingValue(text: '12'),
            const TextEditingValue(text: '120,5'),
          )
          .text,
      '120.5',
    );
  });

  test('the previous session is the one recorded before', () {
    final outcome = importDay();
    final [first, second] = [for (final named in outcome.runs) named.run.id];
    expect(previousRunInRecordingOrder(outcome.runs, first), isNull);
    expect(previousRunInRecordingOrder(outcome.runs, second), first);
    expect(previousRunInRecordingOrder(outcome.runs, 'nope'), isNull);
  });

  testWidgets('enters a setup in Polish on a 320 phone: a decimal point, the '
      'unit never converted, ranges per field, the previous session copied', (
    tester,
  ) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async {},
    );
    final [first, second] = [for (final named in outcome.runs) named.run.id];
    const previous = RunSetup(
      pressureUnit: PressureUnit.psi,
      cold: WheelPressures(fl: 30, fr: 30, rl: 28.5, rr: 28.5),
      hot: WheelPressures(fl: 34),
      tyre: 'Pirelli SC2',
      fuelStartLitres: 20,
    );
    expect(
      controller.updateRunMetadata(
        first,
        const RunMetadata(name: 'Session 1', setup: previous),
      ),
      isNull,
    );
    await tester.binding.setSurfaceSize(const Size(320, 900));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    SessionDetailsDialog(controller: controller, runId: second),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Ustawienia'), findsOneWidget);
    // The unit is the previous session's.
    final unit = tester.widget<SegmentedButton<PressureUnit>>(
      find.byKey(const ValueKey('sessionSetupUnit')),
    );
    expect(unit.selected, {PressureUnit.psi});

    // A comma typed in Polish is a decimal point.
    await tester.enterText(setupField('cold', 'fl'), '2,1');
    await tester.pump();
    expect(fieldText(tester, setupField('cold', 'fl')), '2.1');
    // 2.1 psi is out of range: said under the table, Save off.
    expect(
      find.byKey(const ValueKey('sessionSetupPressureError')),
      findsOneWidget,
    );
    expect(find.textContaining('od 7 do 90'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);

    // Switching to bar keeps the number and checks it again.
    await tester.ensureVisible(find.text('bar'));
    await tester.tap(find.text('bar'));
    await tester.pump();
    expect(fieldText(tester, setupField('cold', 'fl')), '2.1');
    expect(
      find.byKey(const ValueKey('sessionSetupPressureError')),
      findsNothing,
    );
    expect(saveEnabled(tester), isTrue);
    await tester.enterText(setupField('hot', 'rr'), '7');
    await tester.pump();
    expect(find.textContaining('od 0.5 do 6'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    await tester.enterText(setupField('hot', 'rr'), '');
    await tester.enterText(
      find.byKey(const ValueKey('sessionSetupFuel')),
      '250',
    );
    await tester.pump();
    expect(find.text('0–200 l, najwyżej dwie cyfry po kropce'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    await tester.enterText(find.byKey(const ValueKey('sessionSetupFuel')), '');
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Same as Session 1 fills the fields, unit included; nothing saved yet.
    final sameAs = find.byKey(const ValueKey('sessionSetupSameAs'));
    expect(find.text('Skopiuj z: Sesja 1'), findsOneWidget);
    await tester.ensureVisible(sameAs);
    await tester.pumpAndSettle();
    // The fields hold values: asked first, and Cancel keeps them.
    await tester.tap(sameAs);
    await tester.pumpAndSettle();
    expect(find.text('Zastąpić ustawienia?'), findsOneWidget);
    await tester.tap(find.text('Anuluj').last);
    await tester.pumpAndSettle();
    expect(fieldText(tester, setupField('cold', 'fl')), '2.1');
    await tester.ensureVisible(sameAs);
    await tester.pumpAndSettle();
    await tester.tap(sameAs);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sessionSetupReplace')));
    await tester.pumpAndSettle();
    expect(fieldText(tester, setupField('cold', 'fl')), '30');
    expect(fieldText(tester, setupField('cold', 'rl')), '28.5');
    expect(fieldText(tester, setupField('hot', 'fl')), '34');
    expect(fieldText(tester, setupField('hot', 'fr')), '');
    expect(
      fieldText(tester, find.byKey(const ValueKey('sessionSetupTyre'))),
      'Pirelli SC2',
    );
    expect(
      tester
          .widget<SegmentedButton<PressureUnit>>(
            find.byKey(const ValueKey('sessionSetupUnit')),
          )
          .selected,
      {PressureUnit.psi},
    );
    expect(controller.runMetadata(second).setup, const RunSetup());
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Zapisz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(controller.runMetadata(second).setup, previous);
  });

  testWidgets('a setup is saved with the day as entered and shown on the '
      'day and in the progression', (tester) async {
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
    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    expect(find.text('Setup'), findsOneWidget);
    // The first session has no previous one to copy.
    expect(find.byKey(const ValueKey('sessionSetupSameAs')), findsNothing);
    // Bar by default.
    expect(
      tester
          .widget<SegmentedButton<PressureUnit>>(
            find.byKey(const ValueKey('sessionSetupUnit')),
          )
          .selected,
      {PressureUnit.bar},
    );
    for (final (wheel, value) in [('fl', '2.1'), ('fr', '2.10'), ('rl', '2')]) {
      await tester.enterText(setupField('cold', wheel), value);
    }
    await tester.enterText(setupField('hot', 'fl'), '2.45');
    await tester.enterText(
      find.byKey(const ValueKey('sessionSetupTyre')),
      ' Pirelli SC2 ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sessionSetupFuel')),
      '8,5',
    );
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();
    expect(controller.dirty, isTrue);
    const line =
        'Setup: Cold 2.1 / 2.1 / 2 / — bar · Hot 2.45 / — / — / — bar'
        ' · Tyres Pirelli SC2 · Fuel 8.5 l';
    // In the session list and in the progression.
    expect(find.text(line), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(ValueKey('progressionRun $first')),
        matching: find.text(line),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    final run = documentRun(saved.single, first);
    expect(run['setup'], {
      'version': 'session-setup-v1',
      'pressureUnit': 'bar',
      'coldPressure': {'fl': 2.1, 'fr': 2.1, 'rl': 2.0},
      'hotPressure': {'fl': 2.45},
      'tyre': 'Pirelli SC2',
      'fuelStartLitres': 8.5,
    });
    expect(
      documentRun(saved.single, outcome.runs.last.run.id).containsKey('setup'),
      isFalse,
    );
    expect(controller.dirty, isFalse);

    // Opened again and saved unchanged: the day stays clean.
    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    expect(fieldText(tester, setupField('cold', 'fr')), '2.1');
    expect(fieldText(tester, setupField('hot', 'fl')), '2.45');
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();
    expect(controller.dirty, isFalse);

    // Every field cleared: the file keeps no setup at all.
    await tester.tap(detailsTile(first));
    await tester.pumpAndSettle();
    for (final row in ['cold', 'hot']) {
      for (final wheel in setupWheels) {
        await tester.enterText(setupField(row, wheel), '');
      }
    }
    await tester.enterText(find.byKey(const ValueKey('sessionSetupTyre')), '');
    await tester.enterText(find.byKey(const ValueKey('sessionSetupFuel')), '');
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();
    expect(controller.dirty, isTrue);
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(documentRun(saved.last, first).containsKey('setup'), isFalse);
    expect(find.text(line), findsNothing);
  });

  testWidgets('on a 320×640 phone with text twice as large every setup '
      'control fits, reads and can be tapped', (tester) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async {},
    );
    final [first, second] = [for (final named in outcome.runs) named.run.id];
    const previous = RunSetup(
      pressureUnit: PressureUnit.psi,
      cold: WheelPressures(fl: 28.25, fr: 28.25, rl: 26.5, rr: 26.5),
      tyre: 'Pirelli SC2',
    );
    controller.updateRunMetadata(
      first,
      const RunMetadata(name: 'Session 1', setup: previous),
    );
    await tester.binding.setSurfaceSize(const Size(320, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      TelemetryApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    SessionDetailsDialog(controller: controller, runId: second),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The copy button is reached by scrolling and works.
    final sameAs = find.byKey(const ValueKey('sessionSetupSameAs'));
    await tester.ensureVisible(sameAs);
    await tester.pumpAndSettle();
    await tester.tap(sameAs);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(fieldText(tester, setupField('cold', 'fl')), '28.25');

    // Each pressure field is wide enough for "28.25" at this text size.
    for (final row in ['cold', 'hot']) {
      for (final wheel in setupWheels) {
        final field = setupField(row, wheel);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        final text = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final editable = tester.widget<EditableText>(text);
        final painter = TextPainter(
          text: TextSpan(text: '28.25', style: editable.style),
          textScaler:
              editable.textScaler ??
              MediaQuery.textScalerOf(tester.element(text)),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(
          tester.getSize(text).width,
          greaterThanOrEqualTo(painter.width),
          reason: '$row $wheel',
        );
        painter.dispose();
        // On screen, inside the dialog.
        final rect = tester.getRect(field);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
    }

    // Every control can be reached: the fuel and Save at the end.
    final fuel = find.byKey(const ValueKey('sessionSetupFuel'));
    await tester.ensureVisible(fuel);
    await tester.pumpAndSettle();
    await tester.enterText(fuel, '12.5');
    final save = find.byKey(const ValueKey('sessionDetailsSave'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.runMetadata(second).setup.fuelStartLitres, 12.5);
    expect(controller.runMetadata(second).setup.cold, previous.cold);
  });

  testWidgets('on a Polish desktop the pressure fields fit "28.25"', (
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
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    SessionDetailsDialog(controller: controller, runId: first),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('psi'));
    await tester.pump();
    for (final row in ['cold', 'hot']) {
      for (final wheel in setupWheels) {
        final field = setupField(row, wheel);
        await tester.enterText(field, '28.25');
        await tester.pump();
        final text = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final editable = tester.widget<EditableText>(text);
        final painter = TextPainter(
          text: TextSpan(text: '28.25', style: editable.style),
          textScaler:
              editable.textScaler ??
              MediaQuery.textScalerOf(tester.element(text)),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(
          tester.getSize(text).width,
          greaterThanOrEqualTo(painter.width),
          reason: '$row $wheel',
        );
        painter.dispose();
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a setup of a newer version is shown and passed back as it is', (
    tester,
  ) async {
    final outcome = importDay();
    final saved = <Map<String, Object?>>[];
    final first = outcome.runs.first.run.id;
    const stored = {
      'version': 'session-setup-v2',
      'pressureUnit': 'bar',
      'coldPressure': {'fl': 2.1},
      'futureField': 1,
    };
    final unsaved = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async => saved.add(document),
    );
    await unsaved.save('${directory.path}/d.fetproject');
    unsaved.dispose();
    final document = saved.single;
    documentRun(document, first)['setup'] = stored;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      openedFrom: '${directory.path}/d.fetproject',
      openedDocument: document,
      writer: (path, document) async => saved.add(document),
    );
    // Not rewritten from the controller either.
    expect(
      controller.updateRunMetadata(
        first,
        const RunMetadata(
          name: 'Session 1',
          setup: RunSetup(tyre: 'Slick'),
        ),
      ),
      isNull,
    );
    expect(controller.dirty, isFalse);
    await tester.pumpWidget(
      TelemetryApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    SessionDetailsDialog(controller: controller, runId: first),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sessionSetupReadOnly')), findsOneWidget);
    expect(find.byKey(const ValueKey('sessionSetupUnit')), findsNothing);
    expect(find.text('Cold 2.1 / — / — / — bar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sessionDetailsSave')));
    await tester.pumpAndSettle();
    expect(
      controller.runMetadata(first).setup.unknownVersion,
      'session-setup-v2',
    );
    expect(controller.dirty, isFalse);
    expect(identical(documentRun(document, first)['setup'], stored), isTrue);
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
