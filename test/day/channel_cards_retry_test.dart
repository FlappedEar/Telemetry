import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/channel_cards.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';
import '../support/inline_runners.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('channels'));
  tearDown(() => deleteTemporaryDirectory(directory));

  testWidgets('the car and driver cards say why they failed, in the app\'s '
      'language, and calculate again', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final path = '${directory.path}/a.vbo';
    File(path).writeAsStringSync(
      rectangleVbo([
        rectangleLap(30, 50, 120, 20),
        rectangleLap(31, 300, 400, 25),
        rectangleLap(30.5, 550, 650, 22),
      ], car: true),
    );
    final outcome = runDayImport((paths: [path], includeSubfolders: false));
    var fail = true;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      channelSummariesRunner: asyncRunner((job) async {
        if (fail) throw const BackgroundTaskFailed('The work stopped.');
        return job();
      }),
    );
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: DayResultsPage.controller(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    final summary = find
        .descendant(
          of: find.byKey(const ValueKey('dayResultsSummary')),
          matching: find.byType(Scrollable),
        )
        .first;
    final again = find.descendant(
      of: find.byType(CarCard),
      matching: find.byKey(const ValueKey('calculateAgain')),
    );
    await tester.scrollUntilVisible(
      again,
      200,
      scrollable: summary,
      maxScrolls: 200,
    );
    expect(
      find.descendant(
        of: find.byType(CarCard),
        matching: find.text('Praca została przerwana.'),
      ),
      findsOneWidget,
    );
    expect(find.text('The work stopped.'), findsNothing);
    fail = false;
    await tester.ensureVisible(again);
    await tester.pumpAndSettle();
    await tester.tap(again);
    await tester.pumpAndSettle();
    expect(controller.channelSummaries!.error, isEmpty);
    expect(again, findsNothing);
    expect(find.byKey(const ValueKey('carChannel oil_temp')), findsOneWidget);
  });
}
