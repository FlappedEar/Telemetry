import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('semantics'));
  tearDown(() => deleteTemporaryDirectory(directory));

  testWidgets('the day page\'s tappable rows are buttons to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
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
      File(path).writeAsStringSync(rectangleVbo(laps, car: true));
      paths.add(path);
    });
    final outcome = runDayImport((paths: paths, includeSubfolders: false));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    final summary = find
        .descendant(
          of: find.byKey(const ValueKey('dayResultsSummary')),
          matching: find.byType(Scrollable),
        )
        .first;
    final firstRun = outcome.runs.first.run.id;
    for (final key in [
      'lossRow Corner 1',
      'focusArea 0',
      'timeLoss 0',
      'progressionRun $firstRun',
      'carChannel oil_temp',
    ]) {
      final row = find.byKey(ValueKey(key));
      // From the top each time: the rows' order is the page's to choose.
      tester.state<ScrollableState>(summary).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: summary,
        maxScrolls: 200,
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(row),
        isSemantics(isButton: true, hasTapAction: true),
        reason: key,
      );
    }
    handle.dispose();
  });
}
