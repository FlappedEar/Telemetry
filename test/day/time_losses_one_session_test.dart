import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('one-session'));
  tearDown(() => deleteTemporaryDirectory(directory));

  for (final locale in const [Locale('en'), Locale('pl')]) {
    testWidgets('a one-session day says why nothing is compared, '
        'not that nothing was lost ($locale)', (tester) async {
      addTearDown(() => Intl.defaultLocale = null);
      final path = '${directory.path}/a.vbo';
      File(path).writeAsStringSync(
        rectangleVbo([
          rectangleLap(30, 50, 120, 20),
          rectangleLap(31, 300, 400, 25),
          rectangleLap(30.5, 550, 650, 22),
        ]),
      );
      final outcome = runDayImport((paths: [path], includeSubfolders: false));
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
      );
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          locale: locale,
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
      final nothing = find.byKey(const ValueKey('timeLossNothingCompared'));
      await tester.scrollUntilVisible(nothing, 200, scrollable: summary);
      final english = locale.languageCode == 'en';
      expect(
        tester.widget<Text>(nothing).data,
        startsWith(english ? 'With one session' : 'Przy jednej sesji'),
      );
      expect(find.byKey(const ValueKey('timeLossSummary')), findsNothing);
      expect(
        find.text(
          english
              ? 'No lap lost time to the best lap in any timed segment.'
              : 'Żadne okrążenie nie straciło czasu do najlepszego okrążenia '
                    'w żadnym zmierzonym segmencie.',
        ),
        findsNothing,
      );
      // Every lap compares the other two.
      final everyLap = find.text(english ? 'Every lap' : 'Każde okrążenie');
      await tester.ensureVisible(everyLap);
      await tester.pumpAndSettle();
      await tester.tap(everyLap);
      await tester.pumpAndSettle();
      expect(nothing, findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('timeLossSummary'))).data,
        contains(english ? '2 laps compared' : '2 okrążenia porównane'),
      );
    });
  }
}
