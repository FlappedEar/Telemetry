import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

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
  DayCoach coachOf(DayResultsController controller) {
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
      previousRunId: previous,
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
  }) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final outcome = importDay();
    late DayResultsController controller;
    controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      coachRunner: testCoachRunner((job) async => coachOf(controller)),
    );
    await tester.pumpWidget(
      TelemetryApp(
        locale: locale,
        home: DayResultsPage.controller(
          controller: controller,
          coach: ValueNotifier(true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
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

    final kept = (await store.load())!;
    final restored = DayResultsController.recovered(
      openRecoveredDay(kept),
      kept,
      recovery: store,
    );
    addTearDown(restored.dispose);
    expect(restored.runMetadata(first).goals!.goals, [goal]);
  });

  testWidgets('in Polish', (tester) async {
    await show(tester, locale: const Locale('pl'));
    await reveal(tester, find.byKey(const ValueKey('ownGoalsAdd')));
    expect(find.text('Twoje cele na następną sesję'), findsOneWidget);
    expect(find.text('Dodaj cel'), findsOneWidget);
  });
}
