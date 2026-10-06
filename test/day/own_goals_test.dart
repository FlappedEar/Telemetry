import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/briefing_card.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/l10n/app_localizations.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_page_test.dart' show circuitVbo;
import 'rectangle_vbo.dart';
import 'recovery_test.dart' show FileRecoveryStore;
import '../support/coach_runner.dart';
import '../support/temp_directory.dart';

// The driver's own goals for the next session (FET-218): set on the Next
// session card, stored with the session they were set after, and checked
// in the session summary once the next session is added.
void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('goals');
    speedUnitSetting.value = SpeedUnitSetting.automatic;
  });
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
      File(path).writeAsStringSync(
        rectangleVbo(laps).replaceFirst(
          '[header]\n',
          '[header]\ntime\nlatitude\nlongitude\nvelocity kmh\n',
        ),
      );
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  // The coach of the latest session, its main focus coasting at the first
  // corner, with that corner's measures in both sessions.
  DayCoach coachOf(DayResultsController controller, {String? previousRunId}) {
    final result = controller.theoreticalBest!;
    final runId = controller.latestRunId;
    final laps = [for (final sectors in result.laps) sectors.lap];
    final previous = laps.firstWhere((lap) => lap.runId != runId).runId;
    final corner = result.corners.first;
    final latest = laps.lastWhere((lap) => lap.runId == runId);
    final focus = CoachFinding(
      kind: CoachKind.excessiveCoasting,
      segmentId: corner.segmentId,
      segmentName: corner.name,
      confidence: 0.7,
      affectedLaps: [latest],
      evidence: [
        CoachEvidence(
          key: CoachMetric.longestCoast,
          metric: 'Longest coast',
          observed: 1.2,
          reference: 0.6,
          unit: 's',
          referenceLaps: [laps.first],
          detail: '',
        ),
      ],
    );
    return DayCoach(
      runId: runId,
      findings: [focus],
      plan: [CoachItem(focus)],
      reason: CoachReason.ready,
      previousRunId: previousRunId ?? previous,
      goalValues: [
        for (final c in result.corners)
          CoachCornerGoalValues(
            segmentId: c.segmentId,
            name: c.name,
            startProgressMeters: c.startProgressMeters,
            endProgressMeters: c.endProgressMeters,
            before: {CoachKind.excessiveCoasting: (value: 1.8, laps: 3)},
            now: {CoachKind.excessiveCoasting: (value: 1.2, laps: 2)},
          ),
      ],
    );
  }

  Future<DayResultsController> show(
    WidgetTester tester, {
    Locale? locale,
    String? previousRunId,
    bool coachFails = false,
    Size size = const Size(412, 915),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final outcome = importDay();
    late DayResultsController controller;
    controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      coachRunner: testCoachRunner(
        (job) async => coachFails
            ? throw StateError('coach failed')
            : coachOf(controller, previousRunId: previousRunId),
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: TelemetryApp(
          locale: locale,
          home: DayResultsPage.controller(
            controller: controller,
            coach: ValueNotifier(true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder target, {
    bool up = false,
  }) async {
    // Built already (above or below): bring it in.
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
      return;
    }
    await tester.scrollUntilVisible(
      target,
      up ? -200 : 200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('dayResultsCoach')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a goal is added from the coach\'s focus, stored, and removed', (
    tester,
  ) async {
    final controller = await show(tester);
    final corner = controller.theoreticalBest!.corners.first;
    await reveal(tester, find.byKey(const ValueKey('ownGoalsAdd')));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('ownGoalsIntro'))).data,
      'Set up to 3 changes to work on, each at one corner. The next session '
      'is checked against this one.',
    );

    await tester.tap(find.byKey(const ValueKey('ownGoalsAdd')));
    await tester.pumpAndSettle();
    // The coach's main focus is picked to start with.
    expect(find.text('Reduce coasting'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('ownGoalSave')));
    await tester.pumpAndSettle();

    final goals = controller.runMetadata(controller.latestRunId).goals!;
    expect(goals.goals, [
      SessionGoal(
        kind: CoachKind.excessiveCoasting,
        segmentName: corner.name,
        startProgressMeters: corner.startProgressMeters,
        endProgressMeters: corner.endProgressMeters,
      ),
    ]);
    expect(find.byKey(const ValueKey('ownGoal0')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('ownGoalsIntro'))).data,
      'Checked against this session once the next one is added.',
    );
    // The details of the session keep the goal when edited without it.
    final metadata = controller.runMetadata(controller.latestRunId);
    expect(
      controller.updateRunMetadata(
        controller.latestRunId,
        RunMetadata(name: metadata.name, notes: 'Dry'),
      ),
      isNull,
    );
    expect(controller.runMetadata(controller.latestRunId).goals, goals);

    // The same goal again cannot be added.
    await tester.tap(find.byKey(const ValueKey('ownGoalsAdd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ownGoalTaken')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('ownGoalSave')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ownGoalRemove0')));
    await tester.pumpAndSettle();
    expect(
      controller.runMetadata(controller.latestRunId).goals!.isEmpty,
      isTrue,
    );
    expect(find.byKey(const ValueKey('ownGoal0')), findsNothing);
  });

  testWidgets('goals set after the session before are checked in the summary', (
    tester,
  ) async {
    final controller = await show(tester);
    final coach = controller.coach!;
    final corner = controller.theoreticalBest!.corners.first;
    final previous = controller.runMetadata(coach.previousRunId);
    controller.updateRunMetadata(
      coach.previousRunId,
      previous.withGoals(
        RunGoals(
          goals: [
            SessionGoal(
              kind: CoachKind.excessiveCoasting,
              segmentName: corner.name,
              startProgressMeters: corner.startProgressMeters,
              endProgressMeters: corner.endProgressMeters,
            ),
            SessionGoal(
              kind: CoachKind.earlyLift,
              segmentName: corner.name,
              startProgressMeters: corner.startProgressMeters,
              endProgressMeters: corner.endProgressMeters,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    String value(int i) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(ValueKey('sessionSummaryOwnGoal$i')),
                matching: find.byType(Text),
              )
              .last,
        )
        .data!;
    await reveal(tester, find.byKey(const ValueKey('sessionSummaryOwnGoal1')));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sessionSummaryOwnGoal0')),
        matching: find.text('Your goal: ${corner.name} · Reduce coasting'),
      ),
      findsOneWidget,
    );
    expect(
      value(0),
      'Longest coast: 1.8 s then, 1.2 s in this session. Better.',
    );
    // No lift measured: it says so.
    expect(value(1), 'Not measured in this session.');
  });

  test('goals are saved with the day and kept for recovery', () async {
    final outcome = importDay();
    final saved = <Map<String, Object?>>[];
    final store = FileRecoveryStore('${directory.path}/support/recovery.json');
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      recovery: store,
      writer: (path, document) async => saved.add(document),
    );
    final first = outcome.runs.first.run.id;
    const goal = SessionGoal(
      kind: CoachKind.lateThrottle,
      segmentName: 'Corner 2',
      startProgressMeters: 120,
      endProgressMeters: 180,
    );
    expect(
      controller.updateRunMetadata(
        first,
        controller.runMetadata(first).withGoals(RunGoals(goals: [goal])),
      ),
      isNull,
    );
    await controller.flushRecovery();
    final kept = (await store.load())!;
    await controller.save('${directory.path}/d.fetproject');
    controller.dispose();
    final runs =
        (saved.single['event']! as Map<String, Object?>)['runs']! as List;
    final run = runs.cast<Map<String, Object?>>().firstWhere(
      (r) => r['id'] == first,
    );
    expect(run[runGoalsKey], {
      'version': runGoalsVersion,
      'goals': [goal.toJson()],
    });
    final other = runs.cast<Map<String, Object?>>().firstWhere(
      (r) => r['id'] != first,
    );
    expect(other.containsKey(runGoalsKey), isFalse);

    final restored = DayResultsController.recovered(
      openRecoveredDay(kept),
      kept,
      recovery: store,
    );
    addTearDown(restored.dispose);
    expect(restored.runMetadata(first).goals!.goals, [goal]);
  });

  testWidgets('goals of a session without laps compared say why they are not '
      'measured', (tester) async {
    // The coach compared the latest session with another one than the
    // session the goals were set after.
    final controller = await show(tester, previousRunId: 'another');
    final before = controller.coach!;
    expect(before.previousRunId, 'another');
    final first = controller.runs.first.run.id;
    final corner = controller.theoreticalBest!.corners.first;
    controller.updateRunMetadata(
      first,
      controller
          .runMetadata(first)
          .withGoals(
            RunGoals(
              goals: [
                SessionGoal(
                  kind: CoachKind.excessiveCoasting,
                  segmentName: corner.name,
                  startProgressMeters: corner.startProgressMeters,
                  endProgressMeters: corner.endProgressMeters,
                ),
              ],
            ),
          ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('sessionSummaryOwnGoal0'));
    await reveal(tester, row);
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          'Not measured: needs laps of Session 1 and this session among the '
          'compared laps',
        ),
      ),
      findsOneWidget,
    );
  });

  test('goals set on the latest session are checked once the next one is '
      'added, with the coach\'s own measures', () async {
    // Synthetic circuit laps (no real data), as the addition tests use.
    String write(String name, List<double> speeds) {
      final path = '${directory.path}/$name';
      File(path).writeAsStringSync(circuitVbo(speeds));
      return path;
    }

    final files = [
      write('a.vbo', [30, 28, 31]),
      write('b.vbo', [33, 29, 34]),
    ];
    final first = runDayImport((
      paths: [files.first],
      includeSubfolders: false,
    ));
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      coachRunner: testCoachRunner((job) async => job()),
    );
    addTearDown(controller.dispose);
    Future<void> coached() async {
      await controller.requestTheoreticalBest();
      while (controller.coachLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    await coached();
    final setAfter = controller.latestRunId;
    final corners = controller.theoreticalBest!.corners;
    expect(corners, isNotEmpty);
    final goals = [
      for (final corner in corners.take(2))
        SessionGoal(
          kind: CoachKind.lowMinimumSpeed,
          segmentName: corner.name,
          startProgressMeters: corner.startProgressMeters,
          endProgressMeters: corner.endProgressMeters,
        ),
    ];
    expect(
      controller.updateRunMetadata(
        setAfter,
        controller.runMetadata(setAfter).withGoals(RunGoals(goals: goals)),
      ),
      isNull,
    );

    final addition = await controller.addRecordings([files.last]);
    expect(addition.error, isEmpty);
    await coached();
    final coach = controller.coach!;
    expect(controller.latestRunId, isNot(setAfter));
    expect(coach.runId, controller.latestRunId);
    // Checked against the session the goals were set after.
    expect(coach.previousRunId, setAfter);
    final checks = checkSessionGoals(
      controller.runMetadata(setAfter).goals!,
      coach,
      groupId: controller.theoreticalBest!.groupId,
    );
    expect(checks, hasLength(2));
    final measured = checks
        .where((c) => c.outcome != CoachGoalOutcome.notMeasured)
        .toList();
    expect(measured, isNotEmpty);
    for (final check in measured) {
      expect(check.before!.laps, greaterThanOrEqualTo(2));
      expect(check.now!.laps, greaterThanOrEqualTo(2));
      expect(check.before!.value.isFinite && check.now!.value.isFinite, isTrue);
    }
  });

  testWidgets('goals checked by a coach that failed say so', (tester) async {
    final controller = await show(tester, coachFails: true);
    expect(controller.coachError, isNotEmpty);
    final first = controller.runs.first.run.id;
    final corner = controller.theoreticalBest!.corners.first;
    controller.updateRunMetadata(
      first,
      controller
          .runMetadata(first)
          .withGoals(
            RunGoals(
              goals: [
                SessionGoal(
                  kind: CoachKind.excessiveCoasting,
                  segmentName: corner.name,
                  startProgressMeters: corner.startProgressMeters,
                  endProgressMeters: corner.endProgressMeters,
                ),
              ],
            ),
          ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('sessionSummaryOwnGoal0'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('The coach could not run')),
      findsOneWidget,
    );
  });

  testWidgets('goals set on other compared laps get no new goal', (
    tester,
  ) async {
    final controller = await show(tester);
    final latest = controller.latestRunId;
    final corner = controller.theoreticalBest!.corners.first;
    controller.updateRunMetadata(
      latest,
      controller
          .runMetadata(latest)
          .withGoals(
            RunGoals(
              groupId: 'another group',
              goals: [
                SessionGoal(
                  kind: CoachKind.excessiveCoasting,
                  segmentName: corner.name,
                  startProgressMeters: corner.startProgressMeters,
                  endProgressMeters: corner.endProgressMeters,
                ),
              ],
            ),
          ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('ownGoalsOtherGroup')));
    expect(find.byKey(const ValueKey('ownGoalsAdd')), findsNothing);
    // Removing them keeps the group until none is left.
    await tester.tap(find.byKey(const ValueKey('ownGoalRemove0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ownGoalsAdd')), findsOneWidget);
  });

  Future<void> openBriefing(WidgetTester tester) async {
    await reveal(
      tester,
      find.byKey(const ValueKey('sessionSummaryBriefing')),
      up: true,
    );
    await tester.tap(find.byKey(const ValueKey('sessionSummaryBriefing')));
    await tester.pumpAndSettle();
  }

  String line(WidgetTester tester, String key) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    ))
      text.data,
  ].join(' | ');

  testWidgets('the briefing gathers the focus, the goals and the biggest '
      'chance before the next session', (tester) async {
    final controller = await show(tester);
    final corner = controller.theoreticalBest!.corners.first;
    await openBriefing(tester);
    expect(find.byKey(const ValueKey('briefingPage')), findsOneWidget);
    expect(find.text('From Session 2'), findsOneWidget);
    expect(
      line(tester, 'briefingFocus'),
      'Main focus | ${corner.name} · Reduce coasting | Measured: Longest coast: '
      '1.2\u00a0s on this session\'s laps, 0.6\u00a0s on your faster lap.',
    );
    expect(
      line(tester, 'briefingGoals'),
      'Your goals | None set: add them under Your goals for the next session',
    );
    // The summary's Biggest gap left, word for word.
    await tester.pageBack();
    await tester.pumpAndSettle();
    final gap = line(tester, 'sessionSummaryGap').split(' | ').last;
    await openBriefing(tester);
    expect(line(tester, 'briefingChance'), 'Biggest chance | $gap');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A goal set on the Next session card shows in the briefing.
    await reveal(tester, find.byKey(const ValueKey('ownGoalsAdd')));
    await tester.tap(find.byKey(const ValueKey('ownGoalsAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ownGoalSave')));
    await tester.pumpAndSettle();
    await openBriefing(tester);
    expect(
      line(tester, 'briefingGoals'),
      'Your goals | ${corner.name} · Reduce coasting',
    );
  });

  group('each briefing line says why when it cannot be filled', () {
    late DayResultsController controller;

    Future<void> card(
      WidgetTester tester, {
      String? runId,
      DayTheoreticalBestState? sectionsState = DayTheoreticalBestState.ready,
      bool coachLoading = false,
      String coachError = '',
      DayCoach? coach,
      bool keepCoach = true,
      bool speedsConverted = false,
      RunGoals? goals,
      DayChannelSummaries? channels,
      DayLapRow? lastLap,
      DayLapRow? bestLap,
    }) async {
      final best = controller.theoreticalBest!;
      await tester.pumpWidget(
        // Not TelemetryApp: its navigator would keep the Day results page.
        MaterialApp(
          key: UniqueKey(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                BriefingCard(
                  runId: runId ?? controller.latestRunId,
                  session: controller.latestRunName,
                  progression: controller.progression,
                  sectionsState: sectionsState,
                  sections: best.sectionProgression([
                    for (final run in controller.progression.runs) run.run,
                  ]),
                  coach: keepCoach ? (coach ?? controller.coach) : null,
                  coachLoading: coachLoading,
                  coachError: coachError,
                  speedsConverted: speedsConverted,
                  goals: goals ?? RunGoals(),
                  channels: channels,
                  lastLap: lastLap,
                  bestLap: bestLap,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String value(WidgetTester tester, String key) =>
        line(tester, key).split(' | ')[1];

    testWidgets('while working, and without a theoretical best', (
      tester,
    ) async {
      controller = await show(tester);
      await card(tester, sectionsState: null);
      expect(value(tester, 'briefingFocus'), 'Working…');
      expect(value(tester, 'briefingChance'), 'Working…');
      await card(tester, coachLoading: true);
      expect(value(tester, 'briefingFocus'), 'Working…');
      await card(tester, sectionsState: DayTheoreticalBestState.unavailable);
      expect(
        value(tester, 'briefingFocus'),
        isNot(anyOf('Working…', contains('Reduce coasting'))),
      );
      expect(value(tester, 'briefingChance'), value(tester, 'briefingFocus'));
    });

    testWidgets('a coach for an older session is not shown', (tester) async {
      controller = await show(tester);
      final older = controller.progression.runs.first.run.id;
      expect(older, isNot(controller.latestRunId));
      await card(tester, runId: older);
      expect(value(tester, 'briefingFocus'), 'Working…');
    });

    testWidgets('a session without laps on the circuit shown', (tester) async {
      controller = await show(tester);
      await card(tester, runId: 'no such session', keepCoach: false);
      expect(
        value(tester, 'briefingChance'),
        '${controller.latestRunName} has no timed laps on the circuit shown.',
      );
    });

    testWidgets('goals stored in another form are kept, and say so', (
      tester,
    ) async {
      controller = await show(tester);
      await card(tester, goals: RunGoals(unknownVersion: 'session-goals-v2'));
      expect(
        value(tester, 'briefingGoals'),
        'Stored in a form this version of the app does not edit, so they '
        'are not changed here.',
      );
    });

    testWidgets('a speed that cannot be shown says why', (tester) async {
      controller = await show(tester);
      final coach = controller.coach!;
      final finding = coach.plan.first.finding;
      final speed = CoachFinding(
        kind: CoachKind.lowMinimumSpeed,
        segmentId: finding.segmentId,
        segmentName: finding.segmentName,
        confidence: 0.7,
        affectedLaps: finding.affectedLaps,
        evidence: [
          CoachEvidence(
            key: CoachMetric.minimumSpeed,
            metric: 'Minimum speed',
            observed: 45.8,
            reference: 52.5,
            unit: 'km/h',
            referenceLaps: finding.evidence.first.referenceLaps,
            detail: '',
          ),
        ],
      );
      await card(
        tester,
        coach: DayCoach(
          runId: coach.runId,
          findings: [speed],
          plan: [CoachItem(speed)],
          reason: CoachReason.ready,
          speedsConverted: true,
        ),
        speedsConverted: true,
      );
      final focus = line(tester, 'briefingFocus');
      expect(focus, contains('Measured: '));
      expect(focus, contains('—'));
      expect(focus, isNot(contains('45.8')));
      expect(focus, contains('Speeds are not shown'));
    });

    testWidgets('trackside: the last lap, the best of the day and the gap '
        'in large digits, or why not', (tester) async {
      controller = await show(tester);
      final laps = controller.comparisonCandidates();
      final last = laps.lastWhere((row) => row.runId == controller.latestRunId);
      final best = laps.reduce(
        (a, b) => a.durationSeconds <= b.durationSeconds ? a : b,
      );
      await card(tester, lastLap: last, bestLap: best);
      String tile(String key) => line(tester, key);
      expect(
        tile('briefingLastLap'),
        'Last lap | ${displayTime(last.durationSeconds)} | '
        '${last.runName} · LAP ${last.lapNumber}',
      );
      expect(
        tile('briefingBestLap'),
        'Best of the day | ${displayTime(best.durationSeconds)} | '
        '${best.runName} · LAP ${best.lapNumber}',
      );
      expect(
        tile('briefingDelta'),
        'To the best | '
        '${displayDelta(last.durationSeconds - best.durationSeconds)}',
      );
      await card(tester);
      expect(
        line(tester, 'briefingLaps'),
        '${controller.latestRunName} has no timed laps on the circuit shown.',
      );
    });

    testWidgets('trackside: the car, hottest and over the last laps', (
      tester,
    ) async {
      controller = await show(tester);
      await card(tester);
      expect(value(tester, 'briefingCar'), 'Working…');
      await card(
        tester,
        channels: DayChannelSummaries(
          error: 'Channel summaries were cancelled.',
        ),
      );
      expect(find.byKey(const ValueKey('briefingCar')), findsOneWidget);
      // Nothing recorded on the day: no car line.
      await card(tester, channels: DayChannelSummaries());
      expect(find.byKey(const ValueKey('briefingCar')), findsNothing);
      final rows = [
        for (final row in controller.analysis.rows)
          if (row.runId == controller.latestRunId) row,
      ];
      await card(
        tester,
        channels: DayChannelSummaries(
          runs: [
            RunChannelSummaries(
              runId: controller.latestRunId,
              runName: controller.latestRunName,
              channels: [
                RunChannel(
                  channel: 'engine_oil_temp-obd',
                  unit: 'C',
                  run: const ChannelSummary(maximum: 128, valid: true),
                  sections: [
                    for (final row in rows)
                      ChannelSection(
                        row: row,
                        summary: ChannelSummary(
                          maximum: 100.0 + 10 * row.lapNumber,
                          valid: true,
                        ),
                      ),
                  ],
                ),
              ],
              laps: [
                for (final row in rows)
                  SectionAcceleration(
                    row: row,
                    acceleration: const LapAcceleration(),
                  ),
              ],
            ),
          ],
        ),
      );
      // The synthetic session has too few ranked laps to read a rise, and
      // says so as the summary does.
      expect(
        line(tester, 'briefingCar'),
        'Car | Oil 128\u00a0°C | Temperatures: needs 3 ranked laps',
      );
    });
  });

  testWidgets('the briefing follows the day while it is open', (tester) async {
    final controller = await show(tester);
    final corner = controller.theoreticalBest!.corners.first;
    await openBriefing(tester);
    final latest = controller.latestRunId;
    controller.updateRunMetadata(
      latest,
      controller
          .runMetadata(latest)
          .withGoals(
            RunGoals(
              goals: [
                SessionGoal(
                  kind: CoachKind.lateThrottle,
                  segmentName: corner.name,
                  startProgressMeters: corner.startProgressMeters,
                  endProgressMeters: corner.endProgressMeters,
                ),
              ],
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(
      line(tester, 'briefingGoals'),
      'Your goals | ${corner.name} · Return to throttle sooner',
    );
  });

  testWidgets('the briefing says why while the coach failed', (tester) async {
    await show(tester, coachFails: true);
    await openBriefing(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('briefingFocus')),
        matching: find.text('The coach could not run'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the briefing fits a small phone with large text', (
    tester,
  ) async {
    await show(tester, size: const Size(320, 640), textScale: 2);
    await openBriefing(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('briefingChance')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('briefingPage')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Polish', (tester) async {
    await show(tester, locale: const Locale('pl'));
    await reveal(tester, find.byKey(const ValueKey('ownGoalsAdd')));
    expect(find.text('Twoje cele na następną sesję'), findsOneWidget);
    expect(find.text('Dodaj cel'), findsOneWidget);
    await openBriefing(tester);
    expect(find.text('Przed wyjazdem'), findsOneWidget);
  });
}
