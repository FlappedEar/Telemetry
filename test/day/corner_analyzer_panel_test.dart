import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/comparison_page.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/day/time_losses_card.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('analyzer'));
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

  Future<DayResultsController> openDay(WidgetTester tester) async {
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
    return controller;
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> pickSegment(WidgetTester tester, String name) async {
    await tapKey(tester, const ValueKey('cornerAnalyzerSegmentPicker'));
    await tester.tap(find.byKey(ValueKey('cornerAnalyzerSegment $name')).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a time loss opens the Corner Analyzer on its segment', (
    tester,
  ) async {
    final controller = await openDay(tester);
    final loss = controller.theoreticalBest!.publishedTimeLosses().losses.first;
    await tester.tap(find.byKey(const ValueKey('timeLoss 0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lossCompare')));
    await tester.pumpAndSettle();
    final page = tester.widget<ComparisonPage>(find.byType(ComparisonPage));
    expect(page.segmentId, loss.window.segmentId);
    expect(page.fromTheoreticalBest, isTrue);

    // The day has no approved segments yet: the theoretical best's automatic
    // ones are used, and the panel says so.
    expect(find.byKey(const ValueKey('cornerAnalyzer')), findsOneWidget);
    expect(
      textOf(tester, const ValueKey('cornerAnalyzerNote')),
      startsWith('Segments proposed from '),
    );
    final view = controller.cornerAnalyzer(
      page.a,
      page.b,
      fromTheoreticalBest: true,
    )!;
    final segment = view.analyzer.segment(loss.window.segmentId)!;
    final picker = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('cornerAnalyzerSegmentPicker')),
    );
    expect(picker.value, segment.id);

    // A, B and Δ = A − B of the sector time, as the analyzer measures them.
    final sector = view.analyzer.analyze(segment.id)!.sectorTime!;
    expect(
      textOf(tester, const ValueKey('cornerAnalyzer sectorTime A')),
      displayTime(sector.a.value!),
    );
    expect(
      textOf(tester, const ValueKey('cornerAnalyzer sectorTime B')),
      displayTime(sector.b.value!),
    );
    expect(
      textOf(tester, const ValueKey('cornerAnalyzer sectorTime Δ')),
      displayDelta(sector.a.value! - sector.b.value!),
    );
    expect(find.byKey(const ValueKey('cornerAnalyzerChart')), findsOneWidget);

    // The charts show the segment, with the cursor in its middle.
    expect(
      textOf(tester, const ValueKey('chartRange')),
      startsWith('${segment.startMeters.round()} m'),
    );

    // The next segment: the charts follow it.
    await tapKey(tester, const ValueKey('cornerAnalyzerNext'));
    final next =
        view.analyzer.segments[view.analyzer.segments.indexOf(segment) + 1];
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('cornerAnalyzerSegmentPicker')),
          )
          .value,
      next.id,
    );
    expect(
      textOf(tester, const ValueKey('chartRange')),
      startsWith('${next.startMeters.round()} m'),
    );

    // A corner: speeds, braking point and pickup rows, each missing value
    // with its reason.
    final corner = view.analyzer.segments.firstWhere((s) => s.corner);
    await pickSegment(tester, corner.name);
    final analysis = view.analyzer.analyze(corner.id)!;
    for (final row in ['entry', 'apex', 'minimum', 'exit', 'brakingPoint']) {
      expect(
        find.byKey(ValueKey('cornerAnalyzer $row A')),
        findsOneWidget,
        reason: row,
      );
    }
    for (final (slot, side) in [(0, 'A'), (1, 'B')]) {
      final metric = analysis.braking!.point;
      final value = slot == 0 ? metric.a : metric.b;
      final shown = textOf(
        tester,
        ValueKey('cornerAnalyzer brakingPoint $side'),
      );
      if (value.value == null) {
        expect(shown, '—');
        expect(
          find.byKey(ValueKey('cornerAnalyzer brakingPoint $side note')),
          findsOneWidget,
        );
      } else {
        expect(shown, '${value.value!.toStringAsFixed(1)} m');
      }
    }

    // Lap A opens at the segment's start.
    await tapKey(tester, const ValueKey('cornerAnalyzerOpenLapA'));
    expect(find.byType(LapPage), findsOneWidget);
    expect(textOf(tester, const ValueKey('chartCursor')), isNot('0.0 s'));
  });

  testWidgets('laps without shared segments can use the theoretical best\'s', (
    tester,
  ) async {
    final controller = await openDay(tester);
    final best = controller.ranking!.bestOfDay!;
    final other = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.runId != best.runId);
    await tester.tap(find.byKey(const ValueKey('lapsCompare')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('pickLap ${other.displayName}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('suggestedLap ${best.displayName}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cornerAnalyzerEmpty')), findsOneWidget);
    expect(find.byKey(const ValueKey('cornerAnalyzerTable')), findsNothing);
    await tapKey(tester, const ValueKey('cornerAnalyzerUseTheoreticalBest'));
    expect(find.byKey(const ValueKey('cornerAnalyzerEmpty')), findsNothing);
    expect(find.byKey(const ValueKey('cornerAnalyzerNote')), findsOneWidget);
    expect(find.byKey(const ValueKey('cornerAnalyzerTable')), findsOneWidget);

    // Lap B without pedals: its braking point is missing, and says why.
    final noPedals = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.runId == controller.runs.last.run.id);
    await tapKey(tester, const ValueKey('comparisonLapB'));
    await tester.tap(find.byKey(ValueKey('pickLap ${noPedals.displayName}')));
    await tester.pumpAndSettle();
    final page = tester.state(find.byType(ComparisonPage));
    expect(page, isNotNull);
    final view = controller.cornerAnalyzer(
      other,
      noPedals,
      fromTheoreticalBest: true,
    )!;
    final corner = view.analyzer.segments.firstWhere((s) => s.corner);
    await pickSegment(tester, corner.name);
    expect(
      textOf(tester, const ValueKey('cornerAnalyzer brakingPoint B')),
      '—',
    );
    expect(
      textOf(tester, const ValueKey('cornerAnalyzer brakingPoint B note')),
      'no brake or deceleration channel',
    );
    expect(
      textOf(tester, const ValueKey('cornerAnalyzer pickup B note')),
      'no throttle or acceleration channel',
    );
  });

  testWidgets('a theoretical-best row and a corner open the Corner Analyzer', (
    tester,
  ) async {
    final controller = await openDay(tester);
    final result = controller.theoreticalBest!;
    final corner = result.segments.firstWhere((s) => s.type == 'corner');
    await tapKey(tester, ValueKey('lossAnalyze ${corner.name}'));
    final page = tester.widget<ComparisonPage>(find.byType(ComparisonPage));
    expect(page.segmentId, corner.segmentId);
    final (a, b) = dayTheoreticalBestSectorPair(
      result,
      corner.segmentId,
      lap: result.bestLap,
    )!;
    expect([page.a.reference, page.b.reference], [a.reference, b.reference]);
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('cornerAnalyzerSegmentPicker')),
          )
          .value,
      corner.segmentId,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The corner's sheet leads there too.
    await tapKey(tester, ValueKey('lossRow ${corner.name}'));
    await tapKey(tester, const ValueKey('cornerOpenAnalyzer'));
    expect(find.byType(ComparisonPage), findsOneWidget);
    expect(
      tester.widget<ComparisonPage>(find.byType(ComparisonPage)).segmentId,
      corner.segmentId,
    );
  });

  testWidgets('a focus area opens the Corner Analyzer on its segment', (
    tester,
  ) async {
    final controller = await openDay(tester);
    final area = controller.focusAreas.firstWhere(
      (area) => area.segmentId.isNotEmpty,
    );
    final index = controller.focusAreas.indexOf(area);
    await tapKey(tester, ValueKey('focusArea $index'));
    await tapKey(tester, const ValueKey('focusCompare'));
    final page = tester.widget<ComparisonPage>(find.byType(ComparisonPage));
    expect(page.segmentId, area.segmentId);
    expect(page.fromTheoreticalBest, isTrue);
    expect(find.byKey(const ValueKey('cornerAnalyzerTable')), findsOneWidget);
    expect(find.byType(TimeLossPage), findsNothing);
  });
}
