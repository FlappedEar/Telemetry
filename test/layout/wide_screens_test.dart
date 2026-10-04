import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/time_losses_card.dart';
import 'package:telemetry/import/import_review_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../day/rectangle_vbo.dart';
import '../support/temp_directory.dart';

/// On a large desktop window, text and cards stay at most 840 wide.
void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('wide'));
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
      File(path).writeAsStringSync(rectangleVbo(laps, car: true));
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  Future<void> desktop(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('the day page, a time loss and the lap picker on 1920', (
    tester,
  ) async {
    await desktop(tester);
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    final summary = find.byKey(const ValueKey('dayResultsSummary'));
    final cards = find.descendant(of: summary, matching: find.byType(Card));
    expect(cards, findsWidgets);
    for (final card in cards.evaluate()) {
      expect(
        tester.getSize(find.byWidget(card.widget)).width,
        lessThanOrEqualTo(840),
      );
    }

    // A time loss's page.
    final loss = find.byKey(const ValueKey('timeLoss 0'));
    await tester.scrollUntilVisible(
      loss,
      300,
      scrollable: find
          .descendant(of: summary, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(loss);
    await tester.pumpAndSettle();
    final page = find.byType(TimeLossPage);
    expect(page, findsOneWidget);
    final texts = find.descendant(of: page, matching: find.byType(Text));
    for (final text in texts.evaluate()) {
      expect(
        tester.getSize(find.byWidget(text.widget)).width,
        lessThanOrEqualTo(840),
      );
    }
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The lap picker: a lap's time near its name.
    await tester.tap(find.byKey(const ValueKey('lapsCompare')));
    await tester.pumpAndSettle();
    final dialog = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first;
    expect(tester.getSize(dialog).width, lessThanOrEqualTo(440));
  });

  testWidgets('the import review on 1920, its failures in Polish', (
    tester,
  ) async {
    await desktop(tester);
    addTearDown(() => Intl.defaultLocale = null);
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: ImportReviewPage(
          plan: TelemetryImportPlan(
            runs: [],
            files: const [
              TelemetryImportFileResult(
                requestedPath: '/day/b.vbo',
                status: TelemetryImportFileStatus.error,
                message: 'Telemetry file is empty or exceeds the per-file import limit.',
              ),
            ],
            possibleSameRuns: [],
          ),
          automatic: const {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('importReviewList'));
    for (final card
        in find.descendant(of: list, matching: find.byType(Card)).evaluate()) {
      expect(
        tester.getSize(find.byWidget(card.widget)).width,
        lessThanOrEqualTo(840),
      );
    }
    final summary = tester.getRect(find.byKey(const ValueKey('reviewSummary')));
    final confirm = tester.getRect(find.byKey(const ValueKey('confirmReview')));
    expect(confirm.right - summary.left, lessThanOrEqualTo(840));
    expect(find.textContaining('Nie zaimportowano: '), findsOneWidget);
    expect(find.textContaining('Telemetry file'), findsNothing);
  });
}
