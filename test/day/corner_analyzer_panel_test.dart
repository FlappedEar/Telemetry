import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/comparison_page.dart';
import 'package:telemetry/day/corner_analyzer_panel.dart';
import 'package:telemetry/day/corner_details.dart' show cornerReasonText;
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/day/time_losses_card.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

final english = lookupAppLocalizations(const Locale('en'));

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('analyzer'));
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

  Future<DayResultsController> openDay(
    WidgetTester tester, {
    Locale? locale,
  }) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: locale,
        home: DayResultsPage.controller(controller: controller),
      ),
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
    // The note is information, so it is grey, not an accent colour.
    final note = find.byKey(const ValueKey('cornerAnalyzerNote'));
    expect(
      tester.widget<Text>(note).style?.color,
      Theme.of(tester.element(note)).colorScheme.onSurfaceVariant,
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
      startsWith('${segment.startMeters.round()}\u00a0m'),
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
      startsWith('${next.startMeters.round()}\u00a0m'),
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
    // The braking point reads as metres before the corner's entry.
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
          textOf(tester, const ValueKey('cornerAnalyzer brakingPoint note')),
          contains(
            cornerReasonText(english, value.unavailableReason).substring(1),
          ),
        );
      } else {
        expect(shown, '${(corner.startMeters - value.value!).round()}\u00a0m');
      }
    }

    // Grouped as a driver reads a corner, with the summary on top and the
    // speed chart drawn on the segment and a lead-in.
    for (final group in ['Time', 'Braking', 'Corner', 'Exit']) {
      expect(
        find.byKey(ValueKey('cornerAnalyzerGroup $group')),
        findsOneWidget,
        reason: group,
      );
    }
    expect(
      textOf(tester, const ValueKey('cornerAnalyzerSummary')),
      cornerAnalyzerSummary(english, analysis),
    );
    final chart = tester.widget<SegmentSpeedChart>(
      find.byKey(const ValueKey('cornerAnalyzerChart')),
    );
    final (chartStart, chartEnd) = chart.range;
    expect(chartStart, lessThan(corner.startMeters));
    expect(chartEnd, greaterThan(corner.endMeters));
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('cornerAnalyzerChartPlot')),
                )
                .painter!
            as SegmentSpeedPainter;
    // Both laps' lines cover the corner: a speed at its middle on each.
    final middle = (corner.startMeters + corner.endMeters) / 2;
    for (final slot in const [0, 1]) {
      final speed = painter.speedAt(slot, middle);
      expect(speed, isNotNull, reason: 'lap $slot');
      expect(
        speed,
        closeTo(
          view.analyzer
              .lap(slot)
              .session
              .valueAt(
                'speed',
                timeAtProgress(view.analyzer.lap(slot).trace, middle)!,
              )!,
          1.0,
        ),
      );
    }
    expect(
      textOf(tester, const ValueKey('cornerAnalyzerChartAxis')),
      startsWith('Distance from the corner entry (m) · shaded: the corner'),
    );
    expect(
      find.byKey(const ValueKey('cornerAnalyzerLegend A')),
      findsOneWidget,
    );

    // Moving the cursor repaints its own layer only, not the chart.
    final cursorPainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('cornerAnalyzerChartCursorLayer')),
                )
                .painter!
            as SegmentSpeedCursorPainter;
    expect(cursorPainter.chart, same(painter));
    RenderObject plot(String key) =>
        tester.renderObject(find.byKey(ValueKey(key)));
    (cursorPainter.cursor as ValueNotifier<double>).value = corner.startMeters;
    expect(plot('cornerAnalyzerChartCursorLayer').debugNeedsPaint, isTrue);
    expect(plot('cornerAnalyzerChartPlot').debugNeedsPaint, isFalse);
    await tester.pump();
    expect(plot('cornerAnalyzerChartCursorLayer').debugNeedsPaint, isFalse);

    // Lap A opens at the segment's start.
    await tapKey(tester, const ValueKey('cornerAnalyzerOpenLapA'));
    expect(find.byType(LapPage), findsOneWidget);
    expect(textOf(tester, const ValueKey('chartCursor')), isNot('0.0\u00a0s'));
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
      textOf(tester, const ValueKey('cornerAnalyzer brakingPoint note')),
      contains('B: No brake or deceleration channel'),
    );
    expect(
      textOf(tester, const ValueKey('cornerAnalyzer pickup note')),
      contains('B: No throttle or acceleration channel'),
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

  testWidgets('the Corner Analyzer speaks Polish', (tester) async {
    final controller = await openDay(tester, locale: const Locale('pl'));
    await tester.tap(find.byKey(const ValueKey('timeLoss 0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lossCompare')));
    await tester.pumpAndSettle();
    final page = tester.widget<ComparisonPage>(find.byType(ComparisonPage));
    expect(find.text('Analizator zakrętów'), findsOneWidget);
    expect(find.text('Corner Analyzer'), findsNothing);
    final note = textOf(tester, const ValueKey('cornerAnalyzerNote'));
    expect(note, startsWith('Odcinki zaproponowano na podstawie: Sesja '));
    expect(note, contains(' · OKR. '));
    expect(find.byKey(const ValueKey('cornerAnalyzerGroup Time')), findsOne);
    expect(find.text('CZAS'), findsOneWidget);

    final view = controller.cornerAnalyzer(
      page.a,
      page.b,
      fromTheoreticalBest: true,
    )!;
    final corner = view.analyzer.segments.firstWhere((s) => s.corner);
    await pickSegment(tester, corner.name);
    expect(find.text('HAMOWANIE'), findsOneWidget);
    expect(find.text('Prędkość na wejściu'), findsOneWidget);
    expect(find.text('Przybliż odcinek'), findsOneWidget);
    expect(
      textOf(tester, const ValueKey('cornerAnalyzerChartTitle')),
      startsWith('Prędkość · Zakręt '),
    );
    expect(find.textContaining('Entry speed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the notes on whose segments are used are translated', () {
    final source = File('lib/day/day_results_controller.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'''['"]\s*\n\s*['"]'''), '');
    final polish = lookupAppLocalizations(const Locale('pl'));
    for (final (literal, note) in [
      (
        "'Segments proposed from \${best.displayName}, as used by the sector "
            "theoretical best; saving the day approves them. Boundaries are "
            "distances along that lap\\'s axis, so they can shift by a few "
            "metres on these laps.'",
        "Segments proposed from Session 2 · LAP 4, as used by the sector "
            "theoretical best; saving the day approves them. Boundaries are "
            "distances along that lap's axis, so they can shift by a few "
            'metres on these laps.',
      ),
      (
        "'Segments approved on \${_runName(result.segmentRunId)}, as used by "
            "the sector theoretical best. Boundaries are distances along that "
            "run\\'s axis, so they can shift by a few metres on these laps.'",
        "Segments approved on Session 2, as used by the sector theoretical "
            "best. Boundaries are distances along that run's axis, so they can "
            'shift by a few metres on these laps.',
      ),
    ]) {
      expect(source, contains(literal));
      expect(cornerAnalyzerNoteText(english, note, const []), note);
      expect(cornerAnalyzerNoteText(polish, note, const []), isNot(note));
    }
    expect(
      cornerAnalyzerNoteText(
        polish,
        'Segments approved on Session 2, as used by the sector theoretical '
        "best. Boundaries are distances along that run's axis, so they can "
        'shift by a few metres on these laps.',
        const [],
      ),
      startsWith('Odcinki zatwierdzono dla: Sesja 2.'),
    );
  });

  test('the segment picker does not repeat the type', () {
    ComparisonSegment segment(String name, String type) => ComparisonSegment(
      id: name,
      name: name,
      type: type,
      startMeters: 100,
      endMeters: 270,
    );
    expect(
      segmentPickerLabel(english, segment('Corner 1', 'corner'), 2000),
      'Corner 1 · 170\u00a0m',
    );
    expect(
      segmentPickerLabel(english, segment('Corners 2–3', 'corner'), 2000),
      'Corners 2–3 · 170\u00a0m',
    );
    expect(
      segmentPickerLabel(english, segment('S1', 'sector'), 2000),
      'S1 · sector · 170\u00a0m',
    );
    final polish = lookupAppLocalizations(const Locale('pl'));
    expect(
      segmentPickerLabel(polish, segment('Corner 1', 'corner'), 2000),
      'Zakręt 1 · 170\u00a0m',
    );
    expect(
      segmentPickerLabel(polish, segment('S1', 'sector'), 2000),
      'S1 · sektor · 170\u00a0m',
    );
  });

  test('every reason the corner analyses give reads as words', () {
    const reasons = [
      '',
      analyzerIncompleteCoverage,
      brakingNoneDetected,
      brakingIncompleteCoverage,
      brakingSegmentCrossesGate,
      brakingDecelerationChannelMissing,
      brakingApproachClipped,
      brakingApproachClippedAtCorner,
      brakingMixedProvenance,
      brakingNoChannel,
      brakingInferenceDisabled,
      brakingUnitMismatch,
      brakingNoSamples,
      brakingFollowsGap,
      brakingAlreadyActive,
      brakingInterruptedByGap,
      brakingTruncatedAtWindowEnd,
      brakingUnitUndeclared,
      brakingBrakeChannelNotUsed,
      exitNoLift,
      exitNoPickup,
      exitNoChannel,
      exitUnitMismatch,
      exitIncompleteCoverage,
      exitCrossesGate,
      exitSpeedChannelMissing,
      exitFollowsGap,
      exitTruncated,
      exitUnitUndeclared,
      exitScaleUnknown,
      exitScaleInferred,
      exitMixedProvenance,
      cornerPhaseMultipleApexes,
      cornerPhaseSpeedChannelMissing,
      cornerPhaseIncompleteCoverage,
      cornerPhaseFlatSpeed,
      cornerPhaseCrossesGate,
      cornerPhaseInsufficientGeometry,
      cornerPhaseInvalidInput,
      cornerPhaseBroadPeak,
      cornerPhaseAtCornerBoundary,
      cornerSpeedNotACorner,
      cornerSpeedSparseSamples,
      cornerSpeedMixedProvenance,
      cornerSpeedDifferentSegmentOrRevision,
      sectorCrossesGate,
      sectorIncompleteCoverage,
      sectorTimeDifferentSegmentOrRevision,
      sectorTimeSegmentNotFound,
      channelSummaryMissing,
      channelSummaryNoSamples,
      timeLossUntimed,
      timeLossDifferentSegmentOrRevision,
      timeLossNoReference,
      theoreticalBestNoApprovedSegmentation,
      theoreticalBestIncompleteCoverage,
      drivingIncompleteCoverage,
      drivingStateUnknownReason,
      'somethingNew',
    ];
    final identifier = RegExp(r'[a-z][A-Z]');
    for (final reason in reasons) {
      final text = cornerReasonText(english, reason);
      expect(text, isNotEmpty, reason: reason);
      expect(text, isNot(reason), reason: reason);
      expect(identifier.hasMatch(text), isFalse, reason: '$reason: $text');
    }
    // A reason is never shown as its identifier, and none falls back to
    // the generic phrase except an unknown one.
    for (final reason in reasons.take(reasons.length - 1)) {
      expect(
        cornerReasonText(english, reason),
        isNot('not available'),
        reason: reason,
      );
    }
    expect(
      cornerReasonText(english, cornerPhaseMultipleApexes),
      contains('apex'),
    );
  });
}
