import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:telemetry/day/apple_map.dart';
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

import 'blank_tiles.dart';
import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('comparison');
    rememberedLapChannels.value = null;
  });
  tearDown(() => deleteTemporaryDirectory(directory));

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
    expect(textOf(tester, const ValueKey('chartCursor')), '0.0\u00a0s');

    // A drag moves the cursor, and the dot on the map with it.
    final map = tester.widget<TrackMap>(find.byType(TrackMap));
    final chart = find.byKey(const ValueKey('lapChart velocity'));
    await dragAcross(tester, chart, 0.05);
    expect(textOf(tester, const ValueKey('chartCursor')), isNot('0.0\u00a0s'));
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
      isNot('0.0\u00a0s – ${(row.end - row.start).toStringAsFixed(1)}\u00a0s'),
    );
    await tester.tap(find.byKey(const ValueKey('chartZoomReset')));
    await tester.pump();
    expect(
      textOf(tester, const ValueKey('chartRange')),
      '0.0\u00a0s – ${(row.end - row.start).toStringAsFixed(1)}\u00a0s',
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
    Widget chart(ChartSeries series) => TelemetryApp(
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

  testWidgets('a heading chart reads the recorded 0-360 at the cursor', (
    tester,
  ) async {
    final cursor = ValueNotifier(0.0);
    addTearDown(cursor.dispose);
    // Unwrapped across north: 350 then 370 (10 recorded) and -20 (340).
    await tester.pumpWidget(
      TelemetryApp(
        home: Scaffold(
          body: TelemetryChart(
            title: 'heading',
            lines: [
              ChartLine(
                'A',
                const ChartSeries(
                  segments: [
                    [(x: 0, y: 350), (x: 0.5, y: 370), (x: 1, y: -20)],
                  ],
                  minimum: -20,
                  maximum: 370,
                  angular: true,
                ),
                lapAColorForTest,
              ),
            ],
            start: 0,
            end: 1,
            cursor: cursor,
            onCursor: (value) => cursor.value = value,
            valueAxis: (-40, 390),
          ),
        ),
      ),
    );
    final value = find.byKey(const ValueKey('chartValue heading A'));
    expect(tester.widget<Text>(value).data, 'A 350');
    cursor.value = 0.5;
    await tester.pump();
    expect(tester.widget<Text>(value).data, 'A 10');
    cursor.value = 1;
    await tester.pump();
    expect(tester.widget<Text>(value).data, 'A 340');
    // A whole turn: a screen reader says 0 to 360.
    expect(find.bySemanticsLabel(RegExp('A: from 0 to 360')), findsOneWidget);
  });

  test('north reads 0, never 360, after rounding', () {
    expect(chartDegrees(719.6, 400), 0);
    expect(chartDegrees(-0.4, 400), 0);
    expect(chartDegrees(-1e-14, 400), 0);
    expect(chartDegrees(359.4, 400), 359);
    expect(chartDegrees(12.25, 50), 12.3);
  });

  testWidgets('a mouse moves the chart cursor without a click', (tester) async {
    final cursor = ValueNotifier(0.0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      TelemetryApp(
        home: Scaffold(
          body: TelemetryChart(
            title: 'speed',
            lines: [
              ChartLine(
                'A',
                const ChartSeries(
                  segments: [
                    [(x: 0, y: 45), (x: 1, y: 182)],
                  ],
                  minimum: 45,
                  maximum: 182,
                  unit: 'km/h',
                ),
                lapAColorForTest,
              ),
            ],
            start: 0,
            end: 100,
            cursor: cursor,
            onCursor: (value) => cursor.value = value,
            valueAxis: (40, 190),
          ),
        ),
      ),
    );
    final area = tester.getRect(find.byKey(const ValueKey('chartHover speed')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: area.centerLeft + const Offset(1, 0));
    await mouse.moveTo(area.center);
    await tester.pump();
    expect(cursor.value, closeTo(50, 0.5));
    await mouse.moveTo(area.centerLeft + Offset(area.width * 0.25, 0));
    await tester.pump();
    expect(cursor.value, closeTo(25, 0.5));
  });

  testWidgets('a screen reader hears each line\'s lowest and highest value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final cursor = ValueNotifier(0.0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      TelemetryApp(
        home: Scaffold(
          body: TelemetryChart(
            title: 'speed',
            lines: [
              ChartLine(
                'A',
                const ChartSeries(
                  segments: [
                    [(x: 0, y: 45), (x: 1, y: 182)],
                  ],
                  minimum: 45,
                  maximum: 182,
                  unit: 'km/h',
                ),
                lapAColorForTest,
              ),
            ],
            start: 0,
            end: 1,
            cursor: cursor,
            onCursor: (value) => cursor.value = value,
            valueAxis: (40, 190),
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^speed chart, A: from 45(\.0)?\u00a0km/h to 182(\.0)?\u00a0km/h$',
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('with very large text a lap header wraps, keeping the lap', (
    tester,
  ) async {
    final outcome = importDay();
    final analysis = outcome.analysis!;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: analysis,
    );
    final best = analysis.ranking!.bestOfDay!;
    final a = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    await tester.binding.setSurfaceSize(const Size(360, 740));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      TelemetryApp(
        home: ComparisonPage(controller: controller, a: a, b: best),
      ),
    );
    await tester.pumpAndSettle();
    for (final header in [
      find.textContaining('A · '),
      find.textContaining('B · '),
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(header.first);
      expect(paragraph.didExceedMaxLines, isFalse);
    }
    // Down to the last chart's Add a channel, nothing overflows.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('addChartChannel')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
    expect(textOf(tester, const ValueKey('chartCursor')), isNot('0.0\u00a0s'));
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
    expect(range, isNot(startsWith('0\u00a0m –')));
    expect(loss.window.endProgressMeters, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('chartZoomReset')));
    await tester.pump();
    expect(
      textOf(tester, const ValueKey('chartRange')),
      startsWith('0\u00a0m –'),
    );
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

  testWidgets('the comparison is saved with the day and opens as it was left', (
    tester,
  ) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final best = controller.ranking!.bestOfDay!;
    final a = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    expect(controller.savedComparisonPair, isNull);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ComparisonPage(controller: controller, a: a, b: best),
      ),
    );
    await tester.pumpAndSettle();
    // The pair, then a zoom once it settles, and the charts shown.
    expect(controller.savedComparison.slots, [a.reference, best.reference]);
    final whole = textOf(tester, const ValueKey('chartRange'));
    await tester.tap(find.byKey(const ValueKey('chartZoomIn')));
    await tester.pump(const Duration(milliseconds: 400));
    final zoomed = textOf(tester, const ValueKey('chartRange'));
    expect(zoomed, isNot(whole));
    final range = controller.savedComparison.range!;
    expect(range.$1, greaterThanOrEqualTo(0));
    expect(
      range.$2 - range.$1,
      lessThan(controller.comparison(a, best)!.axisLengthMeters),
    );
    controller.rememberComparisonChannels(const [deltaTimeChannel, 'velocity']);
    final path = '${directory.path}/Compared.fetproject';
    await tester.runAsync(() => controller.save(path));

    final opened = DayResultsController.opened(
      (await tester.runAsync(() async => openDay(path)))!,
    );
    final (savedA, savedB) = opened.savedComparisonPair!;
    expect((savedA.reference, savedB.reference), (a.reference, best.reference));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: opened)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lapsLastComparison')));
    await tester.pumpAndSettle();
    expect(find.byType(ComparisonPage), findsOneWidget);
    expect(
      textOf(tester, const ValueKey('comparisonLapDelta')),
      'Lap Δ ${displayDelta(a.durationSeconds - best.durationSeconds)}',
    );
    expect(textOf(tester, const ValueKey('chartRange')), zoomed);
    expect(
      find.byKey(const ValueKey('comparisonChart Δ time')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('comparisonChart velocity')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('comparisonChart throttle')),
      findsNothing,
    );
    // Opening the comparison left as saved changes nothing.
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened.dirty, isFalse);
  });

  testWidgets('a zoom left just before going back is saved', (tester) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final best = controller.ranking!.bestOfDay!;
    final a = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('openComparison'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ComparisonPage(controller: controller, a: a, b: best),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('openComparison')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chartZoomIn')));
    await tester.pump();
    expect(controller.savedComparison.range, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final length = controller.comparison(a, best)!.axisLengthMeters;
    final range = controller.savedComparison.range!;
    expect(range.$2 - range.$1, closeTo(length / 2, 1e-6));
    expect(tester.takeException(), isNull);
  });

  test('picking the group already shown saves it', () async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    Object? saved() =>
        ((readDayDocument(path)['event'] as Map)['analysisDecisions']
            as Map?)?['comparisonGroupId'];
    expect(saved(), isNull);
    expect(controller.dirty, isFalse);
    controller.chooseGroup(controller.analysis.chosenGroupId!);
    expect(controller.dirty, isTrue);
    await controller.save(path);
    expect(saved(), controller.analysis.chosenGroupId);
    // Picking it again changes nothing.
    controller.chooseGroup(controller.analysis.chosenGroupId!);
    expect(controller.dirty, isFalse);
  });

  testWidgets('the comparison map draws both laps over map tiles', (
    tester,
  ) async {
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
    mapBackground.value = MapBackground.streets;
    debugTileProvider = BlankTiles.new;
    addTearDown(() {
      mapBackground.value = MapBackground.none;
      debugTileProvider = null;
    });
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ComparisonPage(controller: controller, a: a, b: best),
      ),
    );
    await tester.pumpAndSettle();
    final map = find.byKey(const ValueKey('comparisonMap'));
    Finder inMap(Finder finder) => find.descendant(of: map, matching: finder);
    expect(inMap(find.byType(FlutterMap)), findsOneWidget);
    expect(inMap(find.byType(TileLayer)), findsOneWidget);
    expect(inMap(find.text('© OpenStreetMap contributors')), findsOneWidget);
    expect(inMap(find.byTooltip('Map background')), findsOneWidget);

    // Both laps, in their colours, where the recordings were driven (the
    // synthetic track's start line is at 52° N, 21° E).
    List<Polyline<Object>> lines() => [
      for (final layer in tester.widgetList<PolylineLayer>(
        inMap(find.byType(PolylineLayer)),
      ))
        if (layer.key != const ValueKey('comparisonMapRange'))
          ...layer.polylines,
    ];
    final colors = {for (final line in lines()) line.color};
    expect(colors, containsAll([lapAColorForTest, lapBColorForTest]));
    for (final line in lines()) {
      for (final point in line.points) {
        expect(point.latitude, closeTo(52.0, 0.01));
        expect(point.longitude, closeTo(21.0, 0.01));
      }
    }

    // Only the markers follow the cursor.
    List<LatLng> markers() => [
      for (final circle
          in tester
              .widget<CircleLayer>(
                find.byKey(const ValueKey('comparisonMapMarkers')),
              )
              .circles)
        circle.point,
    ];
    final delta = find.byKey(const ValueKey('comparisonChart Δ time'));
    await dragAcross(tester, delta, 0.1);
    final before = markers();
    expect(before, hasLength(2));
    await dragAcross(tester, delta, 0.5);
    final after = markers();
    expect(after, hasLength(2));
    expect(after.first, isNot(before.first));

    // The zoom window is highlighted on lap B.
    PolylineLayer range() => tester.widget<PolylineLayer>(
      find.byKey(const ValueKey('comparisonMapRange')),
    );
    expect(range().polylines, isEmpty);
    await tester.tap(find.byKey(const ValueKey('chartZoomIn')).first);
    await tester.pump();
    expect(range().polylines, isNotEmpty);

    // A channel layer colours lap B over the tiles and dims both lines.
    await tester.tap(find.byKey(const ValueKey('comparisonMapLayerPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speed').last);
    await tester.pumpAndSettle();
    expect(lines().length, greaterThan(colors.length));
    expect(lines().where((line) => line.color == lapAColorForTest), isEmpty);
  });

  // On iPhone, iPad and Mac the same layers are drawn over Apple Maps.
  for (final platform in const [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('the comparison map draws both laps over Apple Maps on '
        '${platform.name}', (tester) async {
      final outcome = importDay();
      final analysis = outcome.analysis!;
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: analysis,
      );
      final best = analysis.ranking!.bestOfDay!;
      final a = controller
          .comparisonCandidates(best)
          .firstWhere(
            (row) => row.durationSeconds > best.durationSeconds + 0.5,
          );
      debugDefaultTargetPlatformOverride = platform;
      mapBackground.value = MapBackground.apple;
      debugAppleMapBuilder = (context, region) =>
          const ColoredBox(key: ValueKey('stubAppleMap'), color: Colors.grey);
      addTearDown(() {
        mapBackground.value = MapBackground.none;
        debugAppleMapBuilder = null;
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: ComparisonPage(controller: controller, a: a, b: best),
        ),
      );
      await tester.pumpAndSettle();
      final map = find.byKey(const ValueKey('comparisonMap'));
      Finder inMap(Finder finder) => find.descendant(of: map, matching: finder);
      final apple = inMap(find.byKey(const ValueKey('stubAppleMap')));
      expect(apple, findsOneWidget);
      expect(inMap(find.byType(TileLayer)), findsNothing);
      expect(inMap(find.text('Apple Maps')), findsNothing);
      expect(
        inMap(find.byKey(const ValueKey('appleMapLegal'))),
        findsOneWidget,
      );

      // Drawn after the map, so above it.
      int order(Finder finder) =>
          tester.allElements.toList().indexOf(tester.element(finder));
      final markers = find.byKey(const ValueKey('comparisonMapMarkers'));
      final range = find.byKey(const ValueKey('comparisonMapRange'));
      expect(order(markers), greaterThan(order(apple)));
      expect(order(range), greaterThan(order(apple)));

      List<Polyline<Object>> lines() => [
        for (final layer in tester.widgetList<PolylineLayer>(
          inMap(find.byType(PolylineLayer)),
        ))
          if (layer.key != const ValueKey('comparisonMapRange'))
            ...layer.polylines,
      ];
      expect({
        for (final line in lines()) line.color,
      }, containsAll([lapAColorForTest, lapBColorForTest]));
      expect(tester.widget<CircleLayer>(markers).circles, isNotEmpty);

      // The zoom window and a channel layer, as over tiles.
      await tester.tap(find.byKey(const ValueKey('chartZoomIn')).first);
      await tester.pump();
      expect(tester.widget<PolylineLayer>(range).polylines, isNotEmpty);
      final plain = lines().length;
      await tester.tap(find.byKey(const ValueKey('comparisonMapLayerPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speed').last);
      await tester.pumpAndSettle();
      expect(lines().length, greaterThan(plain));
      expect(lines().where((line) => line.color == lapAColorForTest), isEmpty);

      // With lap A picked for the colouring, the B button is not amber.
      final slot = find.byKey(const ValueKey('comparisonMapLayerSlot'));
      Color? slotColor(String label) => tester
          .widget<RichText>(
            find.descendant(
              of: find.descendant(of: slot, matching: find.text(label)),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;
      await tester.tap(find.descendant(of: slot, matching: find.text('A')));
      await tester.pumpAndSettle();
      expect(slotColor('B'), isNot(anyOf(lapAColorForTest, lapBColorForTest)));
      await tester.tap(find.descendant(of: slot, matching: find.text('B')));
      await tester.pumpAndSettle();
      expect(slotColor('A'), isNot(anyOf(lapAColorForTest, lapBColorForTest)));
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('a lap page on a wide but short window is at most 840 wide', (
    tester,
  ) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final row = controller
        .comparisonCandidates(outcome.analysis!.ranking!.bestOfDay!)
        .first;
    await tester.binding.setSurfaceSize(const Size(1400, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();
    final map = tester.getRect(find.byType(TrackMap));
    expect(map.width, lessThanOrEqualTo(840));
    // Centred.
    expect(map.center.dx, closeTo(700, 1));
  });

  testWidgets('a lap page shows the best of the day in blue and compares '
      'with it', (tester) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final best = outcome.analysis!.ranking!.bestOfDay!;
    final row = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();

    Color barColor(String key) => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;
    expect(barColor('lapTimeBar'), lapAColorForTest);
    expect(barColor('lapBestBar'), lapBColorForTest);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lapTimeBar')),
        matching: find.text(displayTime(row.durationSeconds)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lapBestBar')),
        matching: find.text(displayTime(best.durationSeconds)),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '${displayDelta(row.durationSeconds - best.durationSeconds)} '
        'to the best of the day',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('lapBestBar')));
    await tester.pumpAndSettle();
    final page = tester.widget<ComparisonPage>(find.byType(ComparisonPage));
    expect(page.a.reference, row.reference);
    expect(page.b.reference, best.reference);
  });

  testWidgets('an excluded lap\'s best bar does not compare, and an out '
      'lap has none', (tester) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final best = outcome.analysis!.ranking!.bestOfDay!;
    final row = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    controller.exclude(row, 'Traffic');
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(const ValueKey('lapBestBar')),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
    );

    final out = controller.analysis.rows.firstWhere(
      (row) => row.type != LapSectionType.lap,
    );
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: out),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lapTimeBar')), findsOneWidget);
    expect(find.byKey(const ValueKey('lapBestBar')), findsNothing);
    expect(find.byKey(const ValueKey('lapGapToBest')), findsNothing);
  });

  testWidgets('the best lap of the day has no second bar', (tester) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final best = outcome.analysis!.ranking!.bestOfDay!;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: best),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lapTimeBar')),
        matching: find.text('Best lap of the day'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('lapBestBar')), findsNothing);
    expect(find.byKey(const ValueKey('lapGapToBest')), findsNothing);
  });

  testWidgets('a lap page speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final best = outcome.analysis!.ranking!.bestOfDay!;
    final row = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kanały'), findsOneWidget);
    expect(find.text('Channels'), findsNothing);
    expect(find.text('Prędkość'), findsOneWidget);
    expect(find.text('Porównaj z…'), findsOneWidget);
    expect(find.text('Wyklucz z rankingu…'), findsOneWidget);
    expect(
      find.textContaining('Różnica względem najlepszego okrążenia dnia'),
      findsOneWidget,
    );
    expect(find.textContaining('OKR.'), findsWidgets);
    expect(find.textContaining('Session'), findsNothing);
    expect(find.byTooltip('Pomniejsz'), findsOneWidget);
    expect(find.text('Dodaj kanał'), findsOneWidget);

    await tester.tap(find.text('Wyklucz z rankingu…'));
    await tester.pumpAndSettle();
    expect(find.text('Wyklucz to okrążenie'), findsOneWidget);
    expect(find.text('Powód'), findsOneWidget);
    expect(find.text('Anuluj'), findsOneWidget);
  });

  testWidgets('a comparison speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    final analysis = outcome.analysis!;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: analysis,
    );
    final best = analysis.ranking!.bestOfDay!;
    final a = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: ComparisonPage(controller: controller, a: a, b: best),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Porównanie okrążeń'), findsOneWidget);
    expect(find.text('Compare laps'), findsNothing);
    expect(
      textOf(tester, const ValueKey('comparisonLapDelta')),
      'Różnica czasu okrążenia: ${displayDelta(a.durationSeconds - best.durationSeconds)}',
    );
    expect(find.text('Zamień A i B'), findsOneWidget);
    expect(find.text('B: najlepsze okrążenie dnia'), findsOneWidget);
    expect(find.text('Kanały według pozycji na torze'), findsOneWidget);
    expect(find.text('Tor jazdy: A / B'), findsOneWidget);
    expect(find.text('Otwórz okrążenie A w tym miejscu'), findsOneWidget);
    expect(find.textContaining('Session'), findsNothing);
  });

  testWidgets('a chart speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final cursor = ValueNotifier(0.0);
    addTearDown(cursor.dispose);
    Widget chart(ChartSeries series) => TelemetryApp(
      locale: const Locale('pl'),
      home: Scaffold(
        body: TelemetryChart(
          title: 'speed',
          lines: [ChartLine('A', series, lapAColorForTest)],
          start: 0,
          end: 1,
          cursor: cursor,
          onCursor: (value) => cursor.value = value,
          valueAxis: (0, 1),
          onRemove: () {},
        ),
      ),
    );
    await tester.pumpWidget(chart(ChartSeries.empty));
    expect(find.text('Brak danych w tym zakresie'), findsOneWidget);
    expect(find.text('No data in this range'), findsNothing);
    expect(find.byTooltip('Usuń speed'), findsOneWidget);
    await tester.pumpWidget(
      chart(const ChartSeries.failed(chartReasonChannelMissing)),
    );
    expect(find.text('Niedostępne · A: nie zapisano'), findsOneWidget);
  });

  test('the Δ time map runs from lap A\'s colour to lap B\'s', () {
    const layer = ComparisonMapLayer(
      id: 'delta',
      scale: 'diverging',
      trace: MapLayerTrace(minimum: -1, maximum: 1),
    );
    // Δ is A − B: negative where A is ahead, positive where B is.
    expect(mapLayerColor(layer, -1), lapAColorForTest);
    expect(mapLayerColor(layer, 1), lapBColorForTest);
    // The single Δ line is neither lap's colour.
    expect(deltaLineColor, isNot(anyOf(lapAColorForTest, lapBColorForTest)));
  });

  test('the other map layers use neither lap\'s colour', () {
    for (final layer in const [
      ComparisonMapLayer(
        id: 'lateralG',
        scale: 'diverging',
        trace: MapLayerTrace(minimum: -1, maximum: 1),
      ),
      ComparisonMapLayer(
        id: 'speed',
        scale: 'sequential',
        trace: MapLayerTrace(minimum: 0, maximum: 1),
      ),
    ]) {
      for (final value in [-1.0, 0.0, 0.5, 1.0]) {
        expect(
          mapLayerColor(layer, value),
          isNot(anyOf(lapAColorForTest, lapBColorForTest)),
          reason: '${layer.id} at $value',
        );
      }
    }
  });
}

const lapAColorForTest = Color(0xFFFCB203);
const lapBColorForTest = Color(0xFF3D8BFF);
