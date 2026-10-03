import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/consistency_card.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/progression_card.dart';
import 'package:telemetry/day/time_losses_card.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('explained'));
  tearDown(() => deleteTemporaryDirectory(directory));

  // Session 1 drives four laps, session 2 two, each slow somewhere else.
  DayImportOutcome importDay() {
    final files = {
      'a.vbo': [
        rectangleLap(30, 50, 120, 20),
        rectangleLap(31, 300, 400, 25),
        rectangleLap(30, 550, 650, 22),
        rectangleLap(30.5, 100, 160, 24),
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

  String textOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  testWidgets(
    'ranks the time losses on a phone and opens one as a comparison',
    (tester) async {
      final outcome = importDay();
      final analysis = outcome.analysis!;
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: analysis,
      );

      // A Pixel 7 screen.
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(home: DayResultsPage.controller(controller: controller)),
      );
      await tester.pumpAndSettle();
      final expected = controller.theoreticalBest!;
      final losses = expected.publishedTimeLosses();
      final every = expected.publishedTimeLosses(allLaps: true);
      expect(losses.losses, isNotEmpty);
      expect(every.losses.length, greaterThan(losses.losses.length));
      final page = find
          .descendant(
            of: find.byKey(const ValueKey('dayResultsSummary')),
            matching: find.byType(Scrollable),
          )
          .first;
      final summary = find.byKey(const ValueKey('timeLossSummary'));
      await tester.scrollUntilVisible(summary, 300, scrollable: page);
      expect(
        textOf(tester, const ValueKey('timeLossSummary')),
        contains('1 lap compared'),
      );
      // Largest first, as calculated.
      for (var i = 0; i < losses.losses.length; ++i) {
        final row = find.byKey(ValueKey('timeLoss $i'));
        expect(row, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.text(displayDelta(losses.losses[i].lossSeconds)),
          ),
          findsOneWidget,
        );
      }

      // Every lap.
      await tester.ensureVisible(find.text('Every lap'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every lap'));
      await tester.pumpAndSettle();
      expect(
        textOf(tester, const ValueKey('timeLossSummary')),
        contains('${every.comparedLapCount} laps compared'),
      );
      if (every.losses.length > 8) {
        expect(find.byKey(const ValueKey('timeLoss 8')), findsNothing);
        final showAll = find.byKey(const ValueKey('timeLossShowAll'));
        await tester.scrollUntilVisible(showAll, 200, scrollable: page);
        await tester.ensureVisible(showAll);
        await tester.pumpAndSettle();
        await tester.tap(showAll);
        await tester.pumpAndSettle();
      }
      final last = find.byKey(ValueKey('timeLoss ${every.losses.length - 1}'));
      await tester.scrollUntilVisible(last, 200, scrollable: page);
      expect(last, findsOneWidget);

      // The largest loss opens with the two laps' times through its segment.
      final first = find.byKey(const ValueKey('timeLoss 0'));
      await tester.scrollUntilVisible(first, -200, scrollable: page);
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      final loss = every.losses.first;
      final comparison = expected.compareLoss(loss)!;
      expect(find.byType(TimeLossPage), findsOneWidget);
      expect(find.text(timeLossWindowName(loss)), findsOneWidget);
      expect(
        textOf(tester, const ValueKey('lossLapTime')),
        displayTime(comparison.lapSeconds!),
      );
      expect(
        textOf(tester, const ValueKey('lossReferenceTime')),
        displayTime(comparison.referenceSeconds!),
      );
      expect(
        textOf(tester, const ValueKey('lossDifference')),
        displayDelta(loss.lossSeconds),
      );
      expect(find.byKey(const ValueKey('timeLossMap')), findsOneWidget);
      expect(find.textContaining('not a guaranteed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lossOpenLap')));
      await tester.pumpAndSettle();
      expect(find.byType(TimeLossPage), findsNothing);
    },
  );

  testWidgets(
    'shows lap and segment consistency, never a missing value as zero',
    (tester) async {
      final outcome = importDay();
      final analysis = outcome.analysis!;
      final consistency = dayLapConsistency(analysis);
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: analysis,
      );
      expect(consistency.day.available, isTrue);
      final short = consistency.runs.firstWhere((run) => !run.laps.available);
      final long = consistency.runs.firstWhere((run) => run.laps.available);

      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(home: DayResultsPage.controller(controller: controller)),
      );
      await tester.pumpAndSettle();
      final expected = controller.theoreticalBest!;
      final page = find
          .descendant(
            of: find.byKey(const ValueKey('dayResultsSummary')),
            matching: find.byType(Scrollable),
          )
          .first;
      final day = find.byKey(const ValueKey('lapConsistency day'));
      await tester.scrollUntilVisible(day, 300, scrollable: page);
      expect(
        textOf(tester, const ValueKey('lapConsistency day')),
        '${displayTime(consistency.day.median!)} · spread '
        '${consistency.day.interquartileRange!.toStringAsFixed(3)} s',
      );
      expect(
        textOf(tester, ValueKey('lapConsistency ${long.runId}')),
        startsWith(displayTime(long.laps.median!)),
      );
      expect(
        textOf(tester, ValueKey('lapConsistency ${short.runId}')),
        'Needs at least 3 laps',
      );
      expect(find.text('2 laps'), findsWidgets);
      for (final segment in expected.segments) {
        final key = ValueKey('sectorConsistency ${segment.segmentId}');
        await tester.scrollUntilVisible(find.byKey(key), 100, scrollable: page);
        expect(
          textOf(tester, key),
          startsWith('${displayTime(segment.consistency.median!)} · spread'),
        );
      }
    },
  );

  testWidgets('shows the progression by session and by segment', (
    tester,
  ) async {
    final outcome = importDay();
    final analysis = outcome.analysis!;
    final runs = [
      for (final run in outcome.runs)
        ProgressionRunInfo(id: run.run.id, name: run.name),
    ];
    final progression = dayProgression(analysis, runs);
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: analysis,
    );

    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    final expected = controller.theoreticalBest!;
    final sections = expected.sectionProgression([
      for (final run in progression.runs) run.run,
    ]);
    final page = find
        .descendant(
          of: find.byKey(const ValueKey('dayResultsSummary')),
          matching: find.byType(Scrollable),
        )
        .first;
    final view = find.byKey(const ValueKey('progressionView'));
    await tester.scrollUntilVisible(view, 300, scrollable: page);
    for (final run in progression.runs) {
      final best = find.byKey(ValueKey('progressionBest ${run.runId}'));
      await tester.scrollUntilVisible(best, 100, scrollable: page);
      expect(
        textOf(tester, ValueKey('progressionBest ${run.runId}')),
        displayTime(run.bestLap!.durationSeconds),
      );
    }
    // Undated recordings say so; the second session compares with the first.
    expect(
      find.text('Recording time unavailable'),
      findsNWidgets(progression.runs.length),
    );
    final second = progression.runs[1];
    expect(
      find.text(
        'Best ${displayDelta(second.bestDeltaPreviousListedSeconds!)} against ${progression.runs[0].runName}',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Typical lap needs at least 3 ranked laps'),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey(
          'progressionBar ${progression.runs.firstWhere((run) => run.eligibleLapCount >= 3).runId}',
        ),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(view, -100, scrollable: page);
    await tester.ensureVisible(find.text('By segment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('By segment'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sectionTable')), findsOneWidget);
    final row = sections.segments.first;
    final long = row.cells.firstWhere((cell) => cell.summary.available);
    final short = row.cells.firstWhere((cell) => !cell.summary.available);
    final cell = find.byKey(
      ValueKey('sectionCell ${row.segmentId} ${long.runId}'),
    );
    await tester.scrollUntilVisible(cell, 100, scrollable: page);
    expect(
      find.descendant(
        of: cell,
        matching: find.text(displayTime(long.summary.median!)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('sectionCell ${row.segmentId} ${short.runId}')),
        matching: find.text('${short.summary.count} laps'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('sectionCellLaps'));
    expect(sheet, findsOneWidget);
    for (final lap in long.laps) {
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(displayTime(lap.seconds)),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('the progression card speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: DayResultsPage.controller(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    final page = find
        .descendant(
          of: find.byKey(const ValueKey('dayResultsSummary')),
          matching: find.byType(Scrollable),
        )
        .first;
    final view = find.byKey(const ValueKey('progressionView'));
    await tester.scrollUntilVisible(view, 300, scrollable: page);
    await tester.pumpAndSettle();
    expect(find.text('Postęp'), findsOneWidget);
    expect(find.text('Progression'), findsNothing);
    expect(find.text('Według sesji'), findsOneWidget);
    expect(find.text('1. Sesja 1'), findsOneWidget);
    expect(find.text('Brak czasu nagrania'), findsWidgets);
    expect(
      find.text(
        'Typowe okrążenie wymaga co najmniej 3 sklasyfikowanych okrążeń',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Według segmentów'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Według segmentów'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sectionTable')), findsOneWidget);
    expect(find.textContaining('rozrzut '), findsWidgets);
    expect(find.textContaining('spread '), findsNothing);
  });

  testWidgets('cards say what is missing', (tester) async {
    await tester.pumpWidget(
      TelemetryApp(
        home: Scaffold(
          body: ListView(
            children: [
              ConsistencyCard(
                laps: LapConsistency(),
                result: null,
                loading: true,
              ),
              TimeLossesCard(
                result: DayTheoreticalBest(
                  groupId: '',
                  state: DayTheoreticalBestState.unavailable,
                  message: 'No eligible laps in this group to calculate a theoretical best from.',
                ),
              ),
              ProgressionCard(
                progression: DayProgression(
                  groupId: null,
                  state: DayRankingState.selectionRequired,
                ),
                result: null,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('lapConsistency day')))
          .data,
      'Needs at least 3 laps',
    );
    expect(find.textContaining('0.000'), findsNothing);
    expect(find.text('Measured with the theoretical best…'), findsOneWidget);
    expect(
      find.text(
        'No eligible laps in this group to calculate a theoretical best from.',
      ),
      findsOneWidget,
    );
    expect(find.text('No session to compare.'), findsOneWidget);
    expect(
      timeLossReasonText(timeLossNoReference),
      'The best lap could not be timed against the segments.',
    );
  });
}
