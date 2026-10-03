import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/corner_details.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/day/track_dialog.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';

import '../day/rectangle_vbo.dart';

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

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    group(name, () {
      testWidgets('the import page fits', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(const TelemetryApp(home: DayImportPage()));
        await tester.pumpAndSettle();
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the day page, a corner, a circuit and a lap fit', (
        tester,
      ) async {
        final outcome = importDay();
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
      });
    });
  }
}
