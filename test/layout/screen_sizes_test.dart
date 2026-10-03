import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/channel_cards.dart';
import 'package:telemetry/day/comparison_page.dart';
import 'package:telemetry/day/corner_details.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_report_page.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/focus_areas_card.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/day/telemetry_chart.dart';
import 'package:telemetry/day/track_dialog.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';

import '../day/driving_vbo.dart';
import '../day/rectangle_vbo.dart';
import '../support/temp_directory.dart';

/// Logical sizes of the devices the app is tested on.
const sizes = {
  'small phone portrait': Size(360, 740),
  'Pixel portrait': Size(412, 915),
  'small phone landscape': Size(740, 360),
  'Pixel landscape': Size(915, 412),
  'tablet portrait': Size(820, 1180),
  'tablet landscape': Size(1180, 820),
};

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('layout'));
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

  /// Scrolls every vertical scrollable on screen to its end, so lazily built
  /// rows are laid out too.
  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollables = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    final count = scrollables.hitTestable().evaluate().length;
    for (var i = 0; i < count; i++) {
      for (var step = 0; step < 30; step++) {
        await tester.drag(
          scrollables.hitTestable().at(i),
          const Offset(0, -300),
          warnIfMissed: false,
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }
  }

  /// Shows the app at [size] with text [scale] times the normal size.
  Future<void> fit(WidgetTester tester, Size size, double scale) async {
    await tester.binding.setSurfaceSize(size);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      return tester.binding.setSurfaceSize(null);
    });
  }

  // Every size at the normal text size and at 1.3 times it, a common
  // larger-text setting on phones.
  for (final scale in const [1.0, 1.3]) {
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      group(scale == 1 ? name : '$name, text ×$scale', () {
        testWidgets('the import page fits', (tester) async {
          await fit(tester, size, scale);
          await tester.pumpWidget(const TelemetryApp(home: DayImportPage()));
          await tester.pumpAndSettle();
          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });

        testWidgets('the day page, a corner, a circuit and a lap fit', (
          tester,
        ) async {
          final outcome = importDay();
          await fit(tester, size, scale);
          await tester.pumpWidget(
            TelemetryApp(
              home: DayResultsPage(
                runs: outcome.runs,
                analysis: outcome.analysis!,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'day page');
          final narrow = size.width < 900;
          // A phone shows the laps as a tab, not below the analysis.
          expect(
            find.widgetWithText(Tab, 'Laps'),
            narrow ? findsOneWidget : findsNothing,
          );
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'day page scrolled');

          Finder list(String key) => find
              .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(Scrollable),
              )
              .first;
          final summary = list('dayResultsSummary');

          final corner = find.byKey(const ValueKey('lossRow Corner 1'));
          await tester.scrollUntilVisible(corner, -200, scrollable: summary);
          await tester.ensureVisible(corner);
          await tester.pumpAndSettle();
          await tester.tap(corner);
          await tester.pumpAndSettle();
          expect(find.byType(CornerDetails), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'corner');
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'corner scrolled');
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
          expect(find.byType(CornerDetails), findsNothing);

          await tester.scrollUntilVisible(
            find.text('Circuits'),
            200,
            scrollable: summary,
            // Larger text makes a long way down.
            maxScrolls: 150,
          );
          // A drag can land on a map or a table, which takes it instead of
          // the page, so bring the circuits into view directly.
          await tester.ensureVisible(find.text('Circuits'));
          await tester.pumpAndSettle();
          // Larger text pushes the circuit list below the heading.
          await tester.scrollUntilVisible(
            find.byIcon(Icons.edit_outlined).first,
            100,
            scrollable: summary,
          );
          final circuit = find.byIcon(Icons.edit_outlined).first;
          await tester.ensureVisible(circuit);
          await tester.pumpAndSettle();
          await tester.tap(circuit);
          await tester.pumpAndSettle();
          expect(find.byType(TrackDialog), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'circuit');
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          if (narrow) {
            // The laps are one tap away on a phone, not below the analysis.
            await tester.tap(find.widgetWithText(Tab, 'Laps'));
            await tester.pumpAndSettle();
            await scrollThrough(tester);
            expect(tester.takeException(), isNull, reason: 'laps scrolled');
          }
          final best = outcome.analysis!.ranking!.bestOfDay!;
          final lap = find.descendant(
            of: find.byKey(const ValueKey('dayResultsLaps')),
            matching: find.text(best.displayName),
          );
          await tester.scrollUntilVisible(
            lap,
            -200,
            scrollable: list('dayResultsLaps'),
          );
          await tester.ensureVisible(lap);
          await tester.pumpAndSettle();
          await tester.tap(lap);
          await tester.pumpAndSettle();
          expect(find.byType(LapPage), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'lap');
          // The trace stays large enough to read, scrolling if it has to.
          expect(
            tester.getSize(find.byType(TrackMap)).height,
            greaterThanOrEqualTo(200),
          );
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'lap scrolled');
          // The lap's charts are there, under the map.
          expect(find.byType(TelemetryChart), findsWidgets);

          // The lap against the next fastest, from the lap page.
          final compare = find.byKey(const ValueKey('lapCompare'));
          await tester.dragUntilVisible(
            compare,
            find.byType(Scrollable).hitTestable().first,
            const Offset(0, 300),
          );
          await tester.pumpAndSettle();
          await tester.tap(compare);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'lap picker');
          final partner = find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'suggestedLap ',
                ),
          );
          await tester.tap(partner);
          await tester.pumpAndSettle();
          expect(find.byType(ComparisonPage), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'comparison');
          final overlay = find.byKey(const ValueKey('comparisonMap'));
          await tester.dragUntilVisible(
            overlay,
            find.byKey(const ValueKey('comparisonSummary')),
            const Offset(0, -200),
          );
          await tester.pumpAndSettle();
          expect(tester.getSize(overlay).height, greaterThanOrEqualTo(180));
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'comparison scrolled');
        });

        testWidgets('the Corner Analyzer fits', (tester) async {
          final outcome = importDay();
          await fit(tester, size, scale);
          await tester.pumpWidget(
            TelemetryApp(
              home: DayResultsPage(
                runs: outcome.runs,
                analysis: outcome.analysis!,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final summary = find
              .descendant(
                of: find.byKey(const ValueKey('dayResultsSummary')),
                matching: find.byType(Scrollable),
              )
              .first;
          // A corner of the theoretical best, from its row's sheet.
          final corner = find.byKey(const ValueKey('lossRow Corner 1'));
          await tester.scrollUntilVisible(corner, 200, scrollable: summary);
          await tester.ensureVisible(corner);
          await tester.pumpAndSettle();
          await tester.tap(corner);
          await tester.pumpAndSettle();
          final open = find.byKey(const ValueKey('cornerOpenAnalyzer'));
          await tester.ensureVisible(open);
          await tester.pumpAndSettle();
          await tester.tap(open);
          await tester.pumpAndSettle();
          expect(find.byType(ComparisonPage), findsOneWidget);
          expect(find.byKey(const ValueKey('cornerAnalyzer')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'analyzer');
          // Opened on its segment, in view, with the table.
          final table = find.byKey(const ValueKey('cornerAnalyzerTable'));
          expect(table, findsOneWidget);
          expect(
            find.byKey(const ValueKey('cornerAnalyzer brakingPoint A')),
            findsOneWidget,
          );
          // Every segment in turn.
          final next = find.byKey(const ValueKey('cornerAnalyzerNext'));
          for (var step = 0; step < 12; step++) {
            await tester.ensureVisible(next);
            await tester.pumpAndSettle();
            if (tester.widget<IconButton>(next).onPressed == null) break;
            await tester.tap(next);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'segment $step');
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('cornerAnalyzerSegmentPicker')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('cornerAnalyzerSegmentPicker')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'segment list');
          final item = find
              .byKey(const ValueKey('cornerAnalyzerSegment Corner 2'))
              .last;
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('cornerAnalyzerChart')),
            findsOneWidget,
          );
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'analyzer scrolled');
        });

        testWidgets('the day report, a focus area and a channel fit', (
          tester,
        ) async {
          final outcome = importDay();
          await fit(tester, size, scale);
          await tester.pumpWidget(
            TelemetryApp(
              home: DayResultsPage(
                runs: outcome.runs,
                analysis: outcome.analysis!,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final summary = find
              .descendant(
                of: find.byKey(const ValueKey('dayResultsSummary')),
                matching: find.byType(Scrollable),
              )
              .first;
          Future<void> open(Finder target) async {
            await tester.scrollUntilVisible(
              target,
              200,
              scrollable: summary,
              maxScrolls: 200,
            );
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          await open(find.byKey(const ValueKey('focusArea 0')));
          expect(find.byType(FocusAreaPage), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'focus area');
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'focus scrolled');
          // Its two laps compared, through its segment.
          final compare = find.byKey(const ValueKey('focusCompare'));
          await tester.dragUntilVisible(
            compare,
            find.byType(Scrollable).hitTestable().first,
            const Offset(0, -200),
          );
          await tester.pumpAndSettle();
          await tester.tap(compare);
          await tester.pumpAndSettle();
          expect(find.byType(ComparisonPage), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'focus comparison');
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          await open(find.byKey(const ValueKey('carChannel oil_temp')));
          expect(find.byType(ChannelPage), findsOneWidget);
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'channel scrolled');
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('openDayReport')));
          await tester.pumpAndSettle();
          expect(find.byType(DayReportPage), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'day report');
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'report scrolled');
        });

        testWidgets('the G-G, driving-state and coasting panels fit', (
          tester,
        ) async {
          final paths = <String>[];
          for (final name in const ['a.vbo', 'b.vbo']) {
            final path = '${directory.path}/$name';
            final laps = [
              rectangleBrakingLap(250, 15),
              rectangleBrakingLap(260, 14),
            ];
            File(path).writeAsStringSync(
              withAcceleration(rectangleVbo(laps, pedals: true), liftOff: true),
            );
            paths.add(path);
          }
          final outcome = runDayImport((
            paths: paths,
            includeSubfolders: false,
          ));
          final controller = DayResultsController(
            runs: outcome.runs,
            analysis: outcome.analysis!,
            theoreticalBestRunner: (job) async => job(),
          );
          await controller.requestTheoreticalBest();
          final best = outcome.analysis!.ranking!.bestOfDay!;
          await fit(tester, size, scale);
          await tester.pumpWidget(
            TelemetryApp(
              home: LapPage(controller: controller, row: best),
            ),
          );
          await tester.pumpAndSettle();
          await scrollThrough(tester);
          expect(
            find.byKey(const ValueKey('lapCoastingPanel')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: 'lap coasting');
          final other = controller
              .comparisonCandidates(best)
              .firstWhere((row) => row.reference != best.reference);
          await tester.pumpWidget(
            TelemetryApp(
              home: ComparisonPage(controller: controller, a: other, b: best),
            ),
          );
          await tester.pumpAndSettle();
          final charts = find
              .descendant(
                of: find.byKey(
                  ValueKey(
                    size.width >= 900
                        ? 'comparisonCharts'
                        : 'comparisonSummary',
                  ),
                ),
                matching: find.byType(Scrollable),
              )
              .first;
          for (final key in const [
            'ggPanel',
            'drivingStatesPanel',
            'comparisonCoastingPanel',
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(ValueKey(key)),
              200,
              scrollable: charts,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: key);
          }
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: 'driving panels');
        });
      });
    }
  }
}
