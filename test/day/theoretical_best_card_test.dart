import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/ui/theme.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/corner_details.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/theoretical_best_card.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

final english = lookupAppLocalizations(const Locale('en'));

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('theoretical'));
  tearDown(() => deleteTemporaryDirectory(directory));

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
        '${expected.availableSeconds!.toStringAsFixed(3)}\u00a0s',
      );
      // The three ways to add it up (FET-222).
      String valueOf(String key) =>
          tester.widget<Text>(find.byKey(ValueKey('$key value'))).data!;
      expect(valueOf('rawBest'), displayTime(expected.theoreticalBestSeconds!));
      final realistic = expected.realistic!;
      expect(realistic.valid, isTrue);
      expect(valueOf('realisticBest'), displayTime(realistic.totalSeconds!));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('realisticBest')),
          matching: find.textContaining(
            'at most 2\u00a0km/h wherever two laps meet',
          ),
        ),
        findsOneWidget,
      );
      final repeatable = repeatableTheoreticalBest(
        expected.sectionProgression([
          for (final named in outcome.runs)
            ProgressionRunInfo(id: named.run.id, name: named.name),
        ]),
      );
      expect(repeatable, isNotNull);
      expect(valueOf('repeatableBest'), displayTime(repeatable!));
      // Quickest each segment, then joined, then as a rule.
      expect(
        realistic.totalSeconds,
        greaterThanOrEqualTo(expected.theoreticalBestSeconds! - 1e-9),
      );
      expect(
        repeatable,
        greaterThanOrEqualTo(expected.theoreticalBestSeconds!),
      );
      // Blue as the Theoretical best bar; what is available as a gain.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('theoreticalBestTime')))
            .style
            ?.color,
        FetColors.dark.reference,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('availableTime')))
            .style
            ?.color,
        FetColors.dark.gain,
      );
      expect(find.byKey(const ValueKey('lossMap')), findsOneWidget);
      expect(find.byKey(const ValueKey('sectorTable')), findsOneWidget);
      final semantics = tester.ensureSemantics();
      var picked = 0;
      for (final lap in expected.laps) {
        final row = find.byKey(ValueKey('sectorRow ${lap.lap.displayName}'));
        expect(row, findsOneWidget);
        // One button per row, which names every column with its time.
        final node = tester.getSemantics(row);
        expect(node, isSemantics(isButton: true, hasTapAction: true));
        expect(node.label, startsWith(english.lap(lap.lap)));
        expect(
          node.label,
          contains('Time: ${displayTime(lap.lap.durationSeconds)}'),
        );
        expect(node.label, contains('Corner 1: '));
        if (node.flagsCollection.isSelected.toBoolOrNull() ?? false) ++picked;
      }
      // The lap shown on the map, and no other.
      expect(picked, 1);
      // The footer adds up to the theoretical best, and is not a button.
      final footer = find.bySemanticsLabel(RegExp('^Fastest; Time: '));
      expect(footer, findsOneWidget);
      expect(tester.getSemantics(footer), isNot(isSemantics(isButton: true)));
      final fastest = expected.segments.first;
      final source = expected.laps.firstWhere(
        (lap) => lap.lap.reference == fastest.sourceLapReference,
      );
      expect(
        tester
            .getSemantics(
              find.byKey(ValueKey('sectorRow ${source.lap.displayName}')),
            )
            .label,
        contains(
          '${english.tbSegmentName(fastest.name)}: '
          '${fastest.seconds!.toStringAsFixed(3)}, the fastest',
        ),
      );
      semantics.dispose();
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
        TelemetryApp(
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
      expect(find.text('+${largest.toStringAsFixed(3)}\u00a0s'), findsWidgets);
      expect(bestLap.totalLossSeconds, closeTo(result.availableSeconds!, 1e-9));
    },
  );

  testWidgets(
    'a corner shows its speeds, braking and pickup against the best lap on a phone',
    (tester) async {
      final path = '${directory.path}/pedals.vbo';
      File(path).writeAsStringSync(
        rectangleVbo([
          rectangleBrakingLap(250, 18),
          rectangleBrakingLap(270, 20),
          rectangleBrakingLap(240, 17, hold: 350),
        ], pedals: true),
      );
      final outcome = runDayImport((paths: [path], includeSubfolders: false));
      final result = dayTheoreticalBest(
        outcome.analysis!,
        outingRuns(outcome.runs),
      );
      expect(result.state, DayTheoreticalBestState.ready);
      final corner = result.corners.firstWhere((c) => c.name == 'Corner 2');
      final best = result.bestLap!;
      expect(best.lapNumber, 2);
      final first = result.laps.firstWhere((lap) => lap.lap.lapNumber == 1);
      final comparison = corner.compare(first.lap.reference)!;
      final firstMinimum = comparison.metrics.speeds.minimum.value!;
      final bestMinimum = comparison.bestLapMetrics!.speeds.minimum.value!;

      // A Pixel 7 screen.
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(
            body: ListView(children: [TheoreticalBestCard(result: result)]),
          ),
        ),
      );
      final page = find.byType(Scrollable).first;
      // The best lap is chosen first; choose lap 1 in the sector table.
      final row = find.byKey(ValueKey('sectorRow ${first.lap.displayName}'));
      await tester.scrollUntilVisible(row, 200, scrollable: page);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();

      final summary = find.byKey(const ValueKey('cornerSummary Corner 2'));
      await tester.scrollUntilVisible(summary, -200, scrollable: page);
      final line = tester.widget<Text>(summary).data!;
      expect(line, contains('Min ${firstMinimum.toStringAsFixed(1)}'));
      expect(line, contains('best lap ${bestMinimum.toStringAsFixed(1)}'));
      expect(line, contains('m earlier'));
      // Straights have no corner details.
      expect(find.byKey(const ValueKey('lossRow Straight 1')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('lossRow Corner 2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lossRow Corner 2')));
      await tester.pumpAndSettle();
      final details = find.byType(CornerDetails);
      expect(details, findsOneWidget);
      String rowText(String key) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .join(' | ');
      expect(
        rowText('cornerMinimumSpeed'),
        contains(
          '${firstMinimum.toStringAsFixed(1)} | ${bestMinimum.toStringAsFixed(1)} | −'
          '${(bestMinimum - firstMinimum).toStringAsFixed(1)}',
        ),
      );
      final before = comparison.metrics.braking.distanceBeforeEntryMeters!;
      final delta = comparison.braking.brakingPointDeltaMeters!;
      expect(
        rowText('cornerBrakingPoint'),
        allOf(
          contains('${before.round()}\u00a0m'),
          contains('${delta.abs().round()}\u00a0m earlier'),
          contains('From the brake channel'),
        ),
      );
      // Lap 1 never lifts below 10 % in the corner; the best lap does.
      final bestPickup =
          comparison.bestLapMetrics!.exit.pickup.progressMeters! -
          corner.startProgressMeters;
      expect(
        rowText('cornerPickup'),
        allOf(
          contains('— | ${bestPickup.round()}\u00a0m | —'),
          contains('no lift before the pickup'),
        ),
      );
      expect(
        rowText('cornerBest Earliest throttle pickup'),
        contains(comparison.earliestPickup!.lap.displayName),
      );
      expect(
        rowText('cornerBest Highest minimum speed'),
        contains(best.displayName),
      );
      expect(
        rowText('cornerBest Latest braking point'),
        contains(best.displayName),
      );
      // The rectangle's corner turns in steps: it is not split, and says
      // why.
      expect(
        rowText('cornerPhasesReason'),
        'Not split: more than one tight part',
      );
      expect(tester.takeException(), isNull);

      // A corner that is split: each part against the best lap. (Not
      // TelemetryApp: its navigator would keep the sheet open.)
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                CornerDetails(
                  corner: corner,
                  comparison: DayCornerComparison(
                    lap: comparison.lap,
                    metrics: comparison.metrics,
                    bestLap: comparison.bestLap,
                    bestLapMetrics: comparison.bestLapMetrics,
                    phases: const CornerPhaseTimes.timed(
                      entry: 1.25,
                      mid: 0.9,
                      exit: 1.5,
                    ),
                    bestLapPhases: const CornerPhaseTimes.timed(
                      entry: 1.1,
                      mid: 0.95,
                      exit: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        rowText('cornerPhaseEntry'),
        'Entry | 1.25\u00a0s | 1.10\u00a0s | +0.15\u00a0s',
      );
      expect(
        rowText('cornerPhaseMiddle'),
        'Middle | 0.90\u00a0s | 0.95\u00a0s | −0.05\u00a0s',
      );
      expect(
        rowText('cornerPhaseExit'),
        'Exit | 1.50\u00a0s | 1.50\u00a0s | ±0.00\u00a0s',
      );
      expect(find.byKey(const ValueKey('cornerPhasesNote')), findsOneWidget);
      expect(find.byKey(const ValueKey('cornerPhasesReason')), findsNothing);
      expect(
        find.byKey(const ValueKey('cornerPhasesBestReason')),
        findsNothing,
      );

      // The best lap not timed through the parts says why.
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                CornerDetails(
                  corner: corner,
                  comparison: DayCornerComparison(
                    lap: comparison.lap,
                    metrics: comparison.metrics,
                    bestLap: comparison.bestLap,
                    bestLapMetrics: comparison.bestLapMetrics,
                    phases: const CornerPhaseTimes.timed(
                      entry: 1.25,
                      mid: 0.9,
                      exit: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(rowText('cornerPhaseEntry'), 'Entry | 1.25\u00a0s | — | —');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('cornerPhasesBestReason')))
            .data,
        'Best lap not timed through the parts: lap not fully covered here',
      );
    },
  );

  testWidgets('a corner of the best lap and a corner without pedals', (
    tester,
  ) async {
    final outcome = importDay();
    final result = dayTheoreticalBest(
      outcome.analysis!,
      outingRuns(outcome.runs),
    );
    final corner = result.corners.first;
    final best = corner.compare(result.bestLap!.reference)!;
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CornerDetails(corner: corner, comparison: best),
          ),
        ),
      ),
    );
    expect(find.textContaining('the best lap'), findsWidgets);
    expect(find.text('This lap'), findsNothing);
    // The braking point's reason, and the corner type's (FET-220).
    expect(
      find.textContaining('no brake or deceleration channel'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('no throttle or acceleration channel'),
      findsOneWidget,
    );
    expect(
      cornerReasonText(english, 'noBrakingDetected'),
      'no braking detected',
    );
    expect(cornerReasonText(english, 'somethingNew'), 'not available');
    expect(tester.takeException(), isNull);

    // In Polish.
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CornerDetails(corner: corner, comparison: best),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('najlepsze okrążenie'), findsWidgets);
    expect(find.textContaining('Sesja '), findsWidgets);
    expect(find.textContaining('the best lap'), findsNothing);
    expect(
      find.textContaining('brak kanału hamulca i przeciążenia wzdłużnego'),
      findsNWidgets(2),
    );
    expect(
      find.text('Punkt rozpoczęcia hamowania (przed zakrętem)'),
      findsOneWidget,
    );
    expect(
      find.text('Najlepsze z ${corner.laps.length} okrążeń'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a corner says what kind of corner it is, in English and Polish (FET-220)',
    (tester) async {
      final path = '${directory.path}/pedals.vbo';
      File(path).writeAsStringSync(
        rectangleVbo([
          rectangleBrakingLap(250, 18),
          rectangleBrakingLap(270, 20),
          rectangleBrakingLap(240, 17, hold: 350),
        ], pedals: true),
      );
      final outcome = runDayImport((paths: [path], includeSubfolders: false));
      final result = dayTheoreticalBest(
        outcome.analysis!,
        outingRuns(outcome.runs),
      );
      final corner = result.corners.firstWhere((c) => c.name == 'Corner 2');
      final driving = corner.classification.driving;
      // The VBO has a brake but no longitudinal G: braking, not split into
      // heavy or not.
      expect(driving.approach, CornerApproach.braking);
      expect(driving.typicalSpeedShedMetresPerSecond, isNull);
      expect(driving.speedBand, CornerSpeedBand.slow);
      expect(corner.classification.shape.shape, CornerShape.doubleApex);
      final flat = result.corners.firstWhere((c) => c.name == 'Corner 1');
      expect(flat.classification.driving.approach, CornerApproach.flat);

      await tester.binding.setSurfaceSize(const Size(412, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> showCard(Locale locale) async {
        await tester.pumpWidget(
          TelemetryApp(
            key: UniqueKey(),
            locale: locale,
            home: Scaffold(
              body: ListView(children: [TheoreticalBestCard(result: result)]),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      String text(String key) =>
          tester.widget<Text>(find.byKey(ValueKey(key))).data!;
      String rowText(String key) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .join(' | ');

      // On each corner's row of the losses.
      await showCard(const Locale('en'));
      expect(
        text('cornerClassSummary Corner 2'),
        'Braking · Slow corner · Double apex',
      );
      expect(
        text('cornerClassSummary Corner 1'),
        'Flat · Medium-speed corner · Single apex',
      );
      expect(
        find.byKey(const ValueKey('cornerClassSummary Straight 1')),
        findsNothing,
      );

      // In the corner's details, with what each comes from.
      await tester.ensureVisible(
        find.byKey(const ValueKey('lossRow Corner 2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lossRow Corner 2')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('cornerClass')));
      await tester.pumpAndSettle();
      expect(text('cornerClassTitle'), 'Corner type');
      expect(
        rowText('cornerClassApproach'),
        'Braking · from this day\'s laps | Braking | Brakes on 3 of 3 laps '
        '(brake pedal). The speed braking takes off is not measured on three '
        'laps, so it is not split into heavy or not.',
      );
      // No unit is recorded or assumed: the speed is shown without one.
      final minimum = driving
          .inSpeedUnit(driving.typicalMinimumSpeedMetresPerSecond)!
          .toStringAsFixed(0);
      expect(
        rowText('cornerClassSpeed'),
        'Speed · from this day\'s laps | Slow corner | Typical minimum speed '
        '$minimum over 3 laps.',
      );
      expect(
        rowText('cornerClassShape'),
        'Shape · from the track | Double apex | Two separate tight parts, '
        'measured as one corner.',
      );
      expect(
        find.textContaining('not split into single corners'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // In Polish (the app's navigator would keep the sheet open).
      Navigator.of(tester.element(find.byType(CornerDetails))).pop();
      await tester.pumpAndSettle();
      await showCard(const Locale('pl'));
      expect(
        text('cornerClassSummary Corner 2'),
        'Hamowanie · Wolny zakręt · Podwójny wierzchołek',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('lossRow Corner 2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lossRow Corner 2')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('cornerClass')));
      await tester.pumpAndSettle();
      expect(text('cornerClassTitle'), 'Rodzaj zakrętu');
      expect(
        rowText('cornerClassApproach'),
        allOf(
          contains('Hamowanie na 3 z 3 okrążeń (pedał hamulca).'),
          contains('nie wiadomo, czy hamowanie jest mocne'),
        ),
      );
      expect(rowText('cornerClassShape'), contains('Podwójny wierzchołek'));
      expect(find.text('Corner type'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a corner class that is not known says why', (tester) async {
    final outcome = importDay();
    final result = dayTheoreticalBest(
      outcome.analysis!,
      outingRuns(outcome.runs),
    );
    final corner = result.corners.first;
    final best = corner.compare(result.bestLap!.reference)!;
    await tester.binding.setSurfaceSize(const Size(412, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (locale, expected) in [
      ('en', 'Not known: no brake or deceleration channel'),
      ('pl', 'Nieznane: brak kanału hamulca i przeciążenia wzdłużnego'),
    ]) {
      await tester.pumpWidget(
        TelemetryApp(
          key: UniqueKey(),
          locale: Locale(locale),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CornerDetails(corner: corner, comparison: best),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final approach = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('cornerClassApproach')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .toList();
      expect(approach.last, expected);
      expect(approach.length, 2, reason: 'no class, only the reason');
    }
    expect(
      cornerReasonText(english, cornerClassTooFewLaps),
      'fewer than three laps measured here',
    );
    expect(
      cornerReasonText(english, cornerClassSpeedUnitUnknown),
      'speed unit not known',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('says why there is no theoretical best', (tester) async {
    await tester.pumpWidget(
      TelemetryApp(
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

  testWidgets('says when the best lap is off the other laps\' line (FET-214)', (
    tester,
  ) async {
    final result = DayTheoreticalBest(
      groupId: 'g',
      state: DayTheoreticalBestState.unavailable,
      message: automaticSegmentsLineDisagreement,
    );
    await tester.pumpWidget(
      TelemetryApp(
        home: Scaffold(body: TheoreticalBestCard(result: result)),
      ),
    );
    expect(find.text(english.tbBestLapOffLine), findsOneWidget);
    final polish = lookupAppLocalizations(const Locale('pl'));
    expect(
      polish.tbMessage(automaticSegmentsLineDisagreement),
      polish.tbBestLapOffLine,
    );
    expect(polish.tbBestLapOffLine, contains('Wyklucz'));
  });

  testWidgets('the theoretical best speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
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
    await tester.binding.setSurfaceSize(const Size(412, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: Scaffold(
          body: ListView(
            children: [TheoreticalBestCard(result: result, path: path)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Teoretyczny czas okrążenia'), findsWidgets);
    expect(find.text('Gdzie ucieka czas'), findsOneWidget);
    expect(find.text('Czasy odcinków'), findsOneWidget);
    expect(find.text('Zakręt 1'), findsWidgets);
    expect(find.text('Najlepsze czasy'), findsOneWidget);
    expect(find.text('Trzy sposoby liczenia'), findsOneWidget);
    expect(find.text('Odcinki, które się łączą'), findsOneWidget);
    expect(find.text('Najlepszy typowy czas'), findsOneWidget);
    expect(find.textContaining('Złożony z '), findsOneWidget);
    // Without the sessions' segment times the best typical waits for them.
    expect(
      find.text(
        'Obliczanie powtarzalności wraz z teoretycznym czasem okrążenia…',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('OKR. '), findsWidgets);
    expect(find.textContaining('najlepsze'), findsWidgets);
    expect(
      tester
          .widget<TrackMap>(find.byKey(const ValueKey('lossMap')))
          .semanticLabel,
      contains('Sesja '),
    );
    expect(find.text('Theoretical best'), findsNothing);
    expect(find.text('Sector times'), findsNothing);
    expect(find.text('Corner 1'), findsNothing);
    expect(tester.takeException(), isNull);
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
    // The largest loss is the app's loss red, never lap A's amber.
    expect(lossColor(1), FetColors.dark.loss);
  });
}
