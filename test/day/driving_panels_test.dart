import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/comparison_page.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/driving_panels.dart';
import 'package:telemetry/day/lap_coasting_panel.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'driving_vbo.dart';
import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('driving');
    rememberedLapChannels.value = null;
  });
  tearDown(() => deleteTemporaryDirectory(directory));

  /// Two sessions braking into the second corner, with accelerations; with
  /// [pedals] they also record the brake and throttle (lifting off at a
  /// steady speed), without them braking and accelerating are inferred.
  /// [accelerations] false leaves the G channels out.
  DayImportOutcome importDay({bool pedals = true, bool accelerations = true}) {
    final files = {
      'a.vbo': [rectangleBrakingLap(250, 15), rectangleBrakingLap(240, 16)],
      'b.vbo': [rectangleBrakingLap(260, 14), rectangleBrakingLap(255, 15)],
    };
    final paths = <String>[];
    files.forEach((name, laps) {
      final path = '${directory.path}/$name';
      final vbo = rectangleVbo(laps, pedals: pedals);
      File(path).writeAsStringSync(
        accelerations ? withAcceleration(vbo, liftOff: true) : vbo,
      );
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  String textOf(WidgetTester tester, Key key) {
    final widget = tester.widget(find.byKey(key));
    return widget is Text
        ? widget.data ?? widget.textSpan!.toPlainText()
        : (widget as RichText).text.toPlainText();
  }

  Future<DayResultsController> openComparison(
    WidgetTester tester,
    DayImportOutcome outcome,
  ) async {
    final analysis = outcome.analysis!;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: analysis,
    );
    final best = analysis.ranking!.bestOfDay!;
    final other = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    await tester.binding.setSurfaceSize(const Size(1200, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ComparisonPage(controller: controller, a: other, b: best),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('the comparison shows G-G, driving states and coasting', (
    tester,
  ) async {
    await openComparison(tester, importDay());
    for (final key in const [
      'ggPanel',
      'drivingStatesPanel',
      'comparisonCoastingPanel',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.text('Whole lap'), findsNWidgets(3));
    for (final lap in const ['A', 'B']) {
      // Peaks from every pair, in g, and how many pairs there are.
      expect(textOf(tester, ValueKey('ggBraking $lap')), endsWith('\u00a0g'));
      expect(textOf(tester, ValueKey('ggCombined $lap')), endsWith('\u00a0g'));
      expect(
        int.parse(textOf(tester, ValueKey('ggSamples $lap'))),
        greaterThan(100),
      );
      // The pedals are recorded, so the states are measured, and labelled.
      expect(
        textOf(tester, ValueKey('drivingSource braking $lap')),
        'measured',
      );
      expect(
        textOf(tester, ValueKey('drivingSource coasting $lap')),
        'measured',
      );
      expect(
        textOf(tester, ValueKey('drivingState braking $lap')),
        // The units are joined to their numbers by no-break spaces.
        matches(RegExp(r'^\d+\.\d\u00a0s · \d+\u00a0%$')),
      );
      expect(
        textOf(tester, ValueKey('coastingSummary $lap')),
        contains('of the lap'),
      );
      expect(
        textOf(tester, ValueKey('coastingSource $lap')),
        startsWith('Measured'),
      );
    }
    // Nothing is inferred when the pedals are recorded.
    expect(find.text('inferred'), findsNothing);
    expect(find.byKey(const ValueKey('ggPlot')), findsOneWidget);

    // An episode moves the shared cursor to where it starts.
    final cursor = textOf(tester, const ValueKey('chartCursor'));
    final episode = find.byKey(const ValueKey('coastingEpisode A 1'));
    await tester.ensureVisible(episode);
    await tester.pumpAndSettle();
    await tester.tap(episode);
    await tester.pumpAndSettle();
    expect(textOf(tester, const ValueKey('chartCursor')), isNot(cursor));
  });

  testWidgets('without pedals the states are inferred and marked so', (
    tester,
  ) async {
    await openComparison(tester, importDay(pedals: false));
    for (final lap in const ['A', 'B']) {
      expect(
        textOf(tester, ValueKey('drivingSource braking $lap')),
        'inferred',
      );
      expect(
        textOf(tester, ValueKey('drivingSource accelerating $lap')),
        'inferred',
      );
      expect(
        textOf(tester, ValueKey('drivingSource cornering $lap')),
        'measured',
      );
      expect(
        textOf(tester, ValueKey('coastingSource $lap')),
        startsWith('Inferred from longitudinal G'),
      );
      expect(
        textOf(tester, ValueKey('drivingSources $lap')),
        contains('Braking inferred from deceleration'),
      );
    }
  });

  testWidgets('without G channels the G-G says why, never zero', (
    tester,
  ) async {
    await openComparison(tester, importDay(accelerations: false));
    // The reason in place of empty axes.
    expect(find.byKey(const ValueKey('ggPlot')), findsNothing);
    expect(
      textOf(tester, const ValueKey('ggEmpty')),
      'A: No longitudinal G recorded · B: No longitudinal G recorded',
    );
    for (final lap in const ['A', 'B']) {
      expect(textOf(tester, ValueKey('ggCombined $lap')), '—');
      expect(
        textOf(tester, ValueKey('ggSamples $lap')),
        'No longitudinal G recorded',
      );
      // The pedals still tell braking and coasting; cornering is unknown.
      expect(
        textOf(tester, ValueKey('drivingSource braking $lap')),
        'measured',
      );
      expect(textOf(tester, ValueKey('drivingState cornering $lap')), '—');
      expect(
        textOf(tester, ValueKey('drivingSource cornering $lap')),
        'not recorded',
      );
    }
  });

  testWidgets('a zoomed stretch narrows every panel', (tester) async {
    await openComparison(tester, importDay());
    final whole = int.parse(textOf(tester, const ValueKey('ggSamples A')));
    await tester.tap(find.byKey(const ValueKey('chartZoomIn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected stretch · '), findsNWidgets(3));
    expect(
      int.parse(textOf(tester, const ValueKey('ggSamples A'))),
      lessThan(whole),
    );
    expect(
      textOf(tester, const ValueKey('coastingSummary A')),
      contains('of the stretch'),
    );
  });

  testWidgets('a lap shows its coasting by segment and episode', (
    tester,
  ) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      theoreticalBestRunner: (job) async => job(),
    );
    final row = outcome.analysis!.ranking!.bestOfDay!;
    await tester.binding.setSurfaceSize(const Size(1200, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LapCoastingPanel), findsOneWidget);
    expect(
      textOf(tester, const ValueKey('lapCoastingSummary')),
      contains('of the lap'),
    );
    expect(
      textOf(tester, const ValueKey('lapCoastingProvenance')),
      startsWith('Measured'),
    );
    expect(find.byKey(const ValueKey('lapCoastingNoSegments')), findsOneWidget);

    // Once the day's segments are calculated, coasting is shown by segment.
    await controller.requestTheoreticalBest();
    await tester.pumpAndSettle();
    final result = controller.theoreticalBest!;
    expect(result.state, DayTheoreticalBestState.ready);
    expect(find.byKey(const ValueKey('lapCoastingNoSegments')), findsNothing);
    for (final segment in result.computed!.approved.segments) {
      expect(
        find.byKey(ValueKey('lapCoastingSegment ${segment['id']}')),
        findsOneWidget,
      );
    }

    // An episode moves the lap's cursor to its start.
    final episode = find.byKey(const ValueKey('lapCoastingEpisode 1'));
    await tester.ensureVisible(episode);
    await tester.pumpAndSettle();
    await tester.tap(episode);
    await tester.pumpAndSettle();
    expect(textOf(tester, const ValueKey('chartCursor')), isNot('0.0\u00a0s'));
  });

  testWidgets('the driving panels speak Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    final analysis = outcome.analysis!;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: analysis,
    );
    final best = analysis.ranking!.bestOfDay!;
    final other = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    await tester.binding.setSurfaceSize(const Size(1200, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: ComparisonPage(controller: controller, a: other, b: best),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Całe okrążenie'), findsNWidgets(3));
    expect(find.text('Whole lap'), findsNothing);
    expect(find.text('Stany jazdy'), findsOneWidget);
    expect(find.text('Driving states'), findsNothing);
    expect(find.text('Hamowanie w zakręcie'), findsOneWidget);
    expect(find.text('Maks. łączne'), findsOneWidget);
    expect(find.text('Okrążenie A'), findsOneWidget);
    for (final lap in const ['A', 'B']) {
      expect(
        textOf(tester, ValueKey('drivingSource braking $lap')),
        'zmierzone',
      );
      expect(
        textOf(tester, ValueKey('coastingSummary $lap')),
        contains('% okrążenia)'),
      );
      expect(
        textOf(tester, ValueKey('coastingSource $lap')),
        startsWith('Zmierzone'),
      );
      expect(
        textOf(tester, ValueKey('drivingSources $lap')),
        startsWith('$lap: Zapisano pedał hamulca; zapisano pedał gazu;'),
      );
    }
  });

  testWidgets('the coasting of a lap speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      theoreticalBestRunner: (job) async => job(),
    );
    final row = outcome.analysis!.ranking!.bestOfDay!;
    await tester.binding.setSurfaceSize(const Size(1200, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Toczenie bez gazu i hamulca'), findsOneWidget);
    expect(find.text('Coasting'), findsNothing);
    expect(
      textOf(tester, const ValueKey('lapCoastingSummary')),
      contains('% okrążenia)'),
    );
    expect(
      textOf(tester, const ValueKey('lapCoastingNoSegments')),
      'Toczenie według segmentów wymaga segmentów w grupie tego okrążenia.',
    );
    expect(
      find.text('Epizody · wybierz jeden, aby go zobaczyć'),
      findsOneWidget,
    );

    await controller.requestTheoreticalBest();
    await tester.pumpAndSettle();
    expect(find.text('Według segmentów'), findsOneWidget);
    expect(find.textContaining('Zakręt'), findsWidgets);
    expect(find.textContaining('Corner'), findsNothing);
  });

  test('the G-G scale grows past 1\u00a0g in half steps', () {
    expect(ggScale([null, 0.4]), 1.5);
    expect(ggScale([1.2]), 1.5);
    expect(ggScale([0.9, 1.4]), 1.5);
    expect(ggScale([1.45]), 2.0);
    expect(ggScale(const []), 1.5);
  });

  test('strip parts are fractions of the stretch, ending at the seam', () {
    final trace = [
      ProgressSegment([
        const ProjectedSample(0, progressMeters: 0, valid: true),
        const ProjectedSample(10, progressMeters: 100, valid: true),
        const ProjectedSample(11, progressMeters: 0, valid: true),
      ]),
    ];
    expect(
      stripFractions(
        const [DrivingStateInterval(2, 5), DrivingStateInterval(9, 11)],
        trace,
        0,
        100,
      ),
      [(from: 0.2, to: 0.5), (from: 0.9, to: 1.0)],
    );
  });
}
