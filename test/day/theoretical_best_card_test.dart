import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/theoretical_best_card.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('theoretical'));
  tearDown(() => directory.deleteSync(recursive: true));

  // Each lap is slow somewhere else, so the theoretical best takes segments
  // from several laps.
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

  testWidgets(
    'the day results show the theoretical best, the loss map and the sector table on a phone',
    (tester) async {
      final outcome = importDay();
      final analysis = outcome.analysis!;
      final expected = dayTheoreticalBest(analysis, outingRuns(outcome.runs));
      expect(expected.state, DayTheoreticalBestState.ready);
      // A Pixel-sized window.
      await tester.binding.setSurfaceSize(const Size(412, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage(runs: outcome.runs, analysis: analysis),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Theoretical best'), findsWidgets);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('theoreticalBestTime')))
            .data,
        displayTime(expected.theoreticalBestSeconds!),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('bestLapTime'))).data,
        displayTime(analysis.ranking!.bestOfDay!.durationSeconds),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('availableTime'))).data,
        '${expected.availableSeconds!.toStringAsFixed(3)} s',
      );
      expect(find.byKey(const ValueKey('lossMap')), findsOneWidget);
      expect(find.byKey(const ValueKey('sectorTable')), findsOneWidget);
      for (final lap in expected.laps) {
        expect(
          find.byKey(ValueKey('sectorRow ${lap.lap.displayName}')),
          findsOneWidget,
        );
      }
      expect(find.text('Corner 1'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a lap chosen in the sector table colours the map by its losses',
    (tester) async {
      final outcome = importDay();
      final analysis = outcome.analysis!;
      final result = dayTheoreticalBest(analysis, outingRuns(outcome.runs));
      final best = analysis.ranking!.bestOfDay!;
      final session = outcome.runs
          .firstWhere((named) => named.run.id == best.runId)
          .run
          .telemetry;
      final path = lapPath(
        session,
        best.start,
        best.end,
        origin: mapOrigin(session),
      );
      await tester.binding.setSurfaceSize(const Size(412, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [TheoreticalBestCard(result: result, path: path)],
            ),
          ),
        ),
      );
      TrackMap map() =>
          tester.widget<TrackMap>(find.byKey(const ValueKey('lossMap')));
      expect(map().semanticLabel, contains(best.displayName));
      // The best lap leaves time only where another lap was faster.
      final bestLap = result.laps.singleWhere((lap) => lap.bestOfDay);
      final colours = {
        for (final segment in path.segments)
          for (final point in segment) map().pointColor!(point),
      };
      expect(colours.length, greaterThan(2));

      // The fastest time of every segment is highlighted once.
      final scheme = Theme.of(tester.element(find.byType(TheoreticalBestCard)))
          .colorScheme;
      final highlighted = find.descendant(
        of: find.byKey(const ValueKey('sectorTable')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.color == scheme.primaryContainer,
        ),
      );
      expect(highlighted, findsNWidgets(result.segments.length));

      final other = result.laps.firstWhere((lap) => !lap.bestOfDay);
      await tester.tap(
        find.byKey(ValueKey('sectorRow ${other.lap.displayName}')),
      );
      await tester.pump();
      expect(map().semanticLabel, contains(other.lap.displayName));
      // Its largest loss leads the list.
      final largest = other.lossSeconds.whereType<double>().reduce(
        (a, b) => a > b ? a : b,
      );
      expect(find.text('+${largest.toStringAsFixed(3)} s'), findsWidgets);
      expect(bestLap.totalLossSeconds, closeTo(result.availableSeconds!, 1e-9));
    },
  );

  testWidgets('says why there is no theoretical best', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TheoreticalBestCard(
                result: DayTheoreticalBest(
                  groupId: 'g',
                  state: DayTheoreticalBestState.unavailable,
                  message: 'No eligible laps in this group to calculate a theoretical best from.',
                ),
              ),
              const TheoreticalBestCard(result: null, loading: true),
            ],
          ),
        ),
      ),
    );
    expect(
      find.text(
        'No eligible laps in this group to calculate a theoretical best from.',
      ),
      findsOneWidget,
    );
    expect(find.text('Timing every lap on one track axis…'), findsOneWidget);
  });

  test('the controller drops a result for laps that changed', () async {
    final outcome = importDay();
    final jobs = <DayTheoreticalBest Function()>[];
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      theoreticalBestRunner: (job) async {
        jobs.add(job);
        return job();
      },
    );
    addTearDown(controller.dispose);
    final first = controller.requestTheoreticalBest();
    expect(controller.theoreticalBestLoading, isTrue);
    controller.exclude(outcome.analysis!.ranking!.bestOfDay!, 'Traffic');
    await first;
    expect(controller.theoreticalBest, isNull);
    await controller.requestTheoreticalBest();
    expect(controller.theoreticalBest!.state, DayTheoreticalBestState.ready);
    expect(
      controller.theoreticalBest!.bestLap!.reference,
      controller.ranking!.bestOfDay!.reference,
    );
    expect(jobs.length, 2);
  });

  test('short segment names', () {
    expect(shortSegmentName('Corner 1'), 'C1');
    expect(shortSegmentName('Straight 4'), 'S4');
    expect(shortSegmentName('Corners 1–2'), 'C1–2');
    expect(shortSegmentName('Pit'), 'Pit');
    expect(lossColor(0), isNot(lossColor(1)));
  });
}
