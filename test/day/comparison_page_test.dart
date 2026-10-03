import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/comparison_page.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/day/telemetry_chart.dart';
import 'package:telemetry/day/time_losses_card.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('comparison');
    rememberedLapChannels.value = null;
  });
  tearDown(() => directory.deleteSync(recursive: true));

  // Two sessions with pedals, slow in different places, and one without.
  DayImportOutcome importDay() {
    final files = {
      'a.vbo': (
        [
          rectangleLap(30, 50, 120, 20),
          rectangleLap(31, 300, 400, 25),
          rectangleLap(30, 550, 650, 22),
        ],
        true,
      ),
      'b.vbo': ([rectangleLap(29), rectangleLap(30.5, 700, 780, 20)], true),
      'c.vbo': ([rectangleLap(28), rectangleLap(28.5)], false),
    };
    final paths = <String>[];
    files.forEach((name, entry) {
      final path = '${directory.path}/$name';
      File(path).writeAsStringSync(rectangleVbo(entry.$1, pedals: entry.$2));
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  String textOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  Future<void> dragAcross(
    WidgetTester tester,
    Finder chart,
    double from,
  ) async {
    final box = tester.getRect(
      find.descendant(
        of: chart,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is GestureDetector &&
              widget.onHorizontalDragUpdate != null,
        ),
      ),
    );
    final start = Offset(box.left + box.width * from, box.center.dy);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(Offset(box.width * 0.2, 0));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a lap shows its channels on a time axis with a cursor', (
    tester,
  ) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final row = outcome.analysis!.rows.firstWhere(
      (row) => row.runId == outcome.runs.first.run.id && row.lapNumber == 1,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();
    final session = controller.session(row.runId)!;
    final expected = lapChartChannels(session);
    expect(expected, contains('velocity'));
    expect(expected, contains('throttle'));
    for (final channel in expected) {
      expect(find.byKey(ValueKey('lapChart $channel')), findsOneWidget);
    }
    expect(textOf(tester, const ValueKey('chartCursor')), '0.0 s');

    // A drag moves the cursor, and the dot on the map with it.
    final map = tester.widget<TrackMap>(find.byType(TrackMap));
    final chart = find.byKey(const ValueKey('lapChart velocity'));
    await dragAcross(tester, chart, 0.05);
    expect(textOf(tester, const ValueKey('chartCursor')), isNot('0.0 s'));
    final before = map.movingMarks!.value.single;
    await dragAcross(tester, chart, 0.4);
    final after = map.movingMarks!.value.single;
    expect(
      (after.east - before.east).abs() + (after.north - before.north).abs(),
      greaterThan(10),
    );
    expect(
      textOf(tester, const ValueKey('chartValue velocity ')),
      // The recording declares no unit, so none is shown.
      matches(RegExp(r'^\d+$')),
    );

    // Zoom in around the cursor, then back to the whole lap.
    await tester.tap(find.byKey(const ValueKey('chartZoomIn')));
    await tester.pump();
    expect(
      textOf(tester, const ValueKey('chartRange')),
      isNot('0.0 s – ${(row.end - row.start).toStringAsFixed(1)} s'),
    );
    await tester.tap(find.byKey(const ValueKey('chartZoomReset')));
    await tester.pump();
    expect(
      textOf(tester, const ValueKey('chartRange')),
      '0.0 s – ${(row.end - row.start).toStringAsFixed(1)} s',
    );

    // Removing a chart is remembered for the next lap.
    await tester.tap(find.byTooltip('Remove throttle'));
    await tester.pump();
    expect(find.byKey(const ValueKey('lapChart throttle')), findsNothing);
    expect(rememberedLapChannels.value, isNot(contains('throttle')));
    await tester.tap(find.byKey(const ValueKey('addChartChannel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('brake').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lapChart brake')), findsOneWidget);
  });

  testWidgets('a chart tells no data apart from a failure', (tester) async {
    final cursor = ValueNotifier(0.0);
    addTearDown(cursor.dispose);
    Widget chart(ChartSeries series) => MaterialApp(
      home: Scaffold(
        body: TelemetryChart(
          title: 'speed',
          lines: [ChartLine('A', series, lapAColorForTest)],
          start: 0,
          end: 1,
          cursor: cursor,
          onCursor: (value) => cursor.value = value,
          valueAxis: (0, 1),
        ),
      ),
    );
    await tester.pumpWidget(chart(ChartSeries.empty));
    expect(find.text('No data in this range'), findsOneWidget);
    await tester.pumpWidget(
      chart(const ChartSeries.failed(chartReasonChannelMissing)),
    );
    expect(find.text('Not available · A: not recorded'), findsOneWidget);
  });

  testWidgets('compares two laps by track position, A − B', (tester) async {
    final outcome = importDay();
    final analysis = outcome.analysis!;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: analysis,
    );
    final best = analysis.ranking!.bestOfDay!;
    final a = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.durationSeconds > best.durationSeconds + 0.5);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ComparisonPage(controller: controller, a: a, b: best),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      textOf(tester, const ValueKey('comparisonLapDelta')),
      'Lap Δ ${displayDelta(a.durationSeconds - best.durationSeconds)}',
    );
    expect(
      textOf(tester, const ValueKey('comparisonLapDelta')),
      startsWith('Lap Δ +'),
    );
    final comparison = controller.comparison(a, best)!;
    for (final channel in comparison.defaultChartChannels) {
      expect(find.byKey(ValueKey('comparisonChart $channel')), findsOneWidget);
    }
    expect(comparison.defaultChartChannels.first, deltaTimeChannel);
    expect(find.text('+ = A behind'), findsOneWidget);

    // Lap A is slower, so it is behind at the end of the lap.
    final delta = find.byKey(const ValueKey('comparisonChart Δ time'));
    await dragAcross(tester, delta, 0.9);
    final shown = textOf(tester, const ValueKey('chartValue Δ time (A − B) '));
    expect(shown, startsWith('+'));
    expect(
      textOf(tester, const ValueKey('chartValue velocity A')),
      matches(RegExp(r'^A \d+$')),
    );
    expect(
      textOf(tester, const ValueKey('chartValue velocity B')),
      matches(RegExp(r'^B \d+$')),
    );

    // The map layer: speed of lap B, then a channel lap C did not record.
    await tester.tap(find.byKey(const ValueKey('comparisonMapLayerPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speed').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('comparisonMapLegend')), findsOneWidget);
    expect(
      textOf(tester, const ValueKey('comparisonMapLegendSource')),
      startsWith('Speed · lap B'),
    );

    // Swapping flips the sign.
    await tester.tap(find.byKey(const ValueKey('comparisonSwap')));
    await tester.pumpAndSettle();
    expect(
      textOf(tester, const ValueKey('comparisonLapDelta')),
      'Lap Δ ${displayDelta(best.durationSeconds - a.durationSeconds)}',
    );

    // Lap B from the session without pedals: no brake, never invented.
    final other = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.runId == outcome.runs.last.run.id);
    await tester.tap(find.byKey(const ValueKey('comparisonLapB')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('pickLap ${other.displayName}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('comparisonChart brake')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('comparisonMapLayerPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brake (measured)').last);
    await tester.pumpAndSettle();
    expect(
      textOf(tester, const ValueKey('comparisonMapLayerUnavailable')),
      'Not recorded on lap B.',
    );

    // Opens lap A where the cursor is.
    await dragAcross(tester, delta, 0.3);
    await tester.ensureVisible(
      find.byKey(const ValueKey('comparisonOpenLapA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comparisonOpenLapA')));
    await tester.pumpAndSettle();
    expect(find.byType(LapPage), findsOneWidget);
    expect(textOf(tester, const ValueKey('chartCursor')), isNot('0.0 s'));
  });

  testWidgets('a time loss and the lap list open a comparison', (tester) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    final loss = controller.theoreticalBest!.publishedTimeLosses().losses.first;
    await tester.tap(find.byKey(const ValueKey('timeLoss 0')));
    await tester.pumpAndSettle();
    expect(find.byType(TimeLossPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lossCompare')));
    await tester.pumpAndSettle();
    expect(find.byType(ComparisonPage), findsOneWidget);
    // The loss's segment is shown first, not the whole lap.
    final range = textOf(tester, const ValueKey('chartRange'));
    expect(range, isNot(startsWith('0 m –')));
    expect(loss.window.endProgressMeters, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('chartZoomReset')));
    await tester.pump();
    expect(textOf(tester, const ValueKey('chartRange')), startsWith('0 m –'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    final best = controller.ranking!.bestOfDay!;
    final candidates = controller.comparisonCandidates();
    final a = candidates.firstWhere((row) => row.reference != best.reference);
    await tester.tap(find.byKey(const ValueKey('lapsCompare')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('pickLap ${a.displayName}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('suggestedLap ${best.displayName}')));
    await tester.pumpAndSettle();
    expect(find.byType(ComparisonPage), findsOneWidget);
    expect(
      textOf(tester, const ValueKey('comparisonLapDelta')),
      'Lap Δ ${displayDelta(a.durationSeconds - best.durationSeconds)}',
    );
  });
}

const lapAColorForTest = Color(0xFF55E6A5);
