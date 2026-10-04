import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/corner_details.dart' show lapAColor, lapBColor;
import 'package:telemetry/day/next_session_card.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/l10n/app_localizations.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('coach');
    speedUnitSetting.value = SpeedUnitSetting.automatic;
  });
  tearDown(() {
    deleteTemporaryDirectory(directory);
    speedUnitSetting.value = SpeedUnitSetting.automatic;
  });

  /// [header] is a VBO header line such as `velocity mph`.
  /// [mixed], when set, is the second recording's header line instead.
  DayImportOutcome importDay({String header = '', String mixed = ''}) {
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
      final vbo = rectangleVbo(laps);
      final line = name == 'b.vbo' && mixed.isNotEmpty ? mixed : header;
      File(path).writeAsStringSync(
        line.isEmpty
            ? vbo
            : vbo.replaceFirst(
                '[header]\n',
                '[header]\ntime\nlatitude\nlongitude\n$line\n',
              ),
      );
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  // A plan with one change and one improvement, on the day's own laps and
  // first corner, as the coach would give it.
  DayCoach plan(
    DayTheoreticalBest result,
    String runId, {
    CoachGoalOutcome goal = CoachGoalOutcome.better,
    String? measuredName,
    bool lift = false,
    bool braking = false,
  }) {
    final laps = [for (final sectors in result.laps) sectors.lap];
    final segment = result.segments.firstWhere(
      (s) => s.type == 'corner',
      orElse: () => result.segments.first,
    );
    final earlier = laps.where((lap) => lap.runId != runId).toList();
    final latest = laps.lastWhere((lap) => lap.runId == runId);
    CoachFinding finding(
      CoachKind kind,
      CoachMetric key,
      String unit,
      List<DayLapRow> references,
    ) => CoachFinding(
      kind: kind,
      segmentId: segment.segmentId,
      segmentName: segment.name,
      confidence: 0.78,
      // A change also seen on laps of an earlier session.
      affectedLaps: kind.corrective
          ? [...earlier.take(2), latest]
          : laps.take(3).toList(),
      sessionLaps: kind.corrective ? [latest] : null,
      evidence: [
        CoachEvidence(
          key: key,
          metric: 'Minimum speed',
          observed: 46.94,
          reference: 53.71,
          unit: unit,
          referenceLaps: references,
          detail: '',
        ),
        CoachEvidence(
          key: CoachMetric.segmentTime,
          metric: 'Segment time',
          observed: 4.21,
          reference: 3.95,
          unit: 's',
          referenceLaps: references,
          detail: '',
        ),
      ],
    );
    // With [lift], a lift point 46.94 m along the lap against 53.71 m.
    final change = braking
        ? finding(
            CoachKind.inconsistentBraking,
            CoachMetric.brakingStart,
            'm',
            [laps.last],
          )
        : lift
        ? finding(CoachKind.earlyLift, CoachMetric.liftPoint, 'm', [laps.last])
        : finding(CoachKind.lowMinimumSpeed, CoachMetric.minimumSpeed, 'km/h', [
            laps.last,
          ]);
    final keep = lift
        ? finding(CoachKind.improving, CoachMetric.throttleReturn, 'm', [
            laps.first,
          ])
        : finding(CoachKind.improving, CoachMetric.minimumSpeed, 'km/h', [
            laps.first,
          ]);
    return DayCoach(
      runId: runId,
      findings: [change, keep],
      // The change first: the main focus.
      plan: [CoachItem(change), CoachItem(keep)],
      reason: CoachReason.ready,
      slowLaps: [laps.last],
      // The session before's focus, checked again.
      goal: CoachGoalCheck(
        runId: earlier.first.runId,
        runName: earlier.first.runName,
        finding: change,
        outcome: goal,
        measuredName: measuredName ?? segment.name,
        before: goal == CoachGoalOutcome.notMeasured ? null : 44.04,
        now: goal == CoachGoalOutcome.notMeasured ? null : 46.94,
      ),
    );
  }

  Future<DayResultsController> show(
    WidgetTester tester, {
    Locale? locale,
    bool withPlan = true,
    Size size = const Size(412, 915),
    double textScale = 1.0,
    String header = 'velocity kmh',
    String mixed = '',
    List<NamedRun> Function(List<NamedRun> runs)? editRuns,
    CoachRunner? coachRunner,
    TheoreticalBestRunner? theoreticalBestRunner,
    CoachGoalOutcome goal = CoachGoalOutcome.better,
    String? measuredName,
    bool lift = false,
    bool braking = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final outcome = importDay(header: header, mixed: mixed);
    late DayResultsController controller;
    controller = DayResultsController(
      runs: editRuns == null ? outcome.runs : editRuns(outcome.runs),
      analysis: outcome.analysis!,
      theoreticalBestRunner: theoreticalBestRunner,
      coachRunner:
          coachRunner ??
          (job) async => withPlan
              ? plan(
                  controller.theoreticalBest!,
                  controller.latestRunId,
                  goal: goal,
                  measuredName: measuredName,
                  lift: lift,
                  braking: braking,
                )
              : job(),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: TelemetryApp(
          locale: locale,
          home: DayResultsPage.controller(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Finder summary() => find
      .descendant(
        of: find.byKey(const ValueKey('dayResultsSummary')),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 200, scrollable: summary());
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('the coach coaches the session recorded last', (tester) async {
    final controller = await show(tester, withPlan: false);
    expect(controller.latestRunName, 'Session 2');
    expect(controller.coach, isNotNull);
    expect(controller.coach!.runId, controller.latestRunId);
    // The synthetic day has no pedals and no plan, and says why.
    expect(controller.coach!.plan, isEmpty);
    expect(find.byKey(const ValueKey('nextSessionCard')), findsOneWidget);
    expect(find.text('Next session'), findsOneWidget);
    expect(
      find.text("Coaching Session 2 against the day's faster laps"),
      findsOneWidget,
    );
    final reason = tester.widget<Text>(
      find.byKey(const ValueKey('coachReason')),
    );
    expect(reason.data, isNotEmpty);
    expect(reason.data, isNot(startsWith('Work on the main focus first.')));
  });

  testWidgets(
    'each item is a labelled suggestion: measured apart from what to try',
    (tester) async {
      await show(tester);
      // The first item is the main focus, the other for once it feels settled.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('coachLabel 0'))).data,
        'Main focus',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('coachLabel 1'))).data,
        'Once that feels settled',
      );
      final measured = tester.widget<Text>(
        find.byKey(const ValueKey('coachMeasured 0')),
      );
      expect(
        measured.textSpan!.toPlainText(),
        'Measured: Minimum speed: 46.9\u00a0km/h on this session\'s laps, 53.7\u00a0km/h on your faster lap.',
      );
      final action = tester.widget<Text>(
        find.byKey(const ValueKey('coachAction 0')),
      );
      expect(
        action.textSpan!.toPlainText(),
        startsWith('Try: Repeat the line'),
      );
      final keep = tester.widget<Text>(
        find.byKey(const ValueKey('coachAction 1')),
      );
      expect(
        keep.textSpan!.toPlainText(),
        startsWith('Keep: Keep the approach'),
      );
      expect(
        find.textContaining('suggest an opportunity, not a promised gain'),
        findsOneWidget,
      );
      final slow = tester.widget<Text>(
        find.byKey(const ValueKey('coachSlowLaps')),
      );
      expect(
        slow.data,
        startsWith("Left out as much slower than their session's typical lap"),
      );
      expect(slow.data, contains('Session 2'));
      // The observations follow it, labelled as such.
      await reveal(tester, find.text('Where to look next'));
      expect(find.text('Where to look next'), findsOneWidget);
    },
  );

  testWidgets('Why? shows the measured values and the corner on the map', (
    tester,
  ) async {
    await show(tester);
    await reveal(tester, find.byKey(const ValueKey('coachWhy 0')));
    await tester.tap(find.byKey(const ValueKey('coachWhy 0')));
    await tester.pumpAndSettle();
    expect(find.byType(CoachItemPage), findsOneWidget);
    expect(find.text('46.9\u00a0km/h against 53.7\u00a0km/h'), findsOneWidget);
    expect(find.text('4.2\u00a0s against 4.0\u00a0s'), findsOneWidget);
    expect(find.text("This session's laps"), findsOneWidget);
    expect(find.text('Earlier laps showing it today'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachMap')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('not a probability'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('not a probability'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the session before\'s main focus is checked again', (
    tester,
  ) async {
    await show(tester);
    final goal = find.byKey(const ValueKey('coachGoal'));
    expect(goal, findsOneWidget);
    expect(
      find.descendant(
        of: goal,
        matching: find.text('Main focus from Session 1'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coachGoalResult'))).data,
      'Minimum speed: 44.0\u00a0km/h then, 46.9\u00a0km/h in this session. '
      'Better.',
    );
    // Measured at the same corner: nothing more to say.
    expect(find.byKey(const ValueKey('coachGoalMeasuredAt')), findsNothing);
    // Above the plan.
    expect(
      tester.getTopLeft(goal).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('coachItem 0'))).dy),
    );
  });

  testWidgets('a focus measured at a corner drawn differently today says '
      'where', (tester) async {
    await show(tester, measuredName: 'Corners 5–8');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('coachGoalMeasuredAt')))
          .data,
      "Measured at Corners 5–8, as today's corners divide the track.",
    );
  });

  testWidgets('a focus no corner of today\'s matches says so', (tester) async {
    await show(tester, goal: CoachGoalOutcome.notMeasured, measuredName: '');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coachGoalResult'))).data,
      "Not measured: today's corners no longer include it.",
    );
  });

  testWidgets('a focus not measured again says so, without values', (
    tester,
  ) async {
    await show(tester, goal: CoachGoalOutcome.notMeasured);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coachGoalResult'))).data,
      'Not measured in this session.',
    );
  });

  testWidgets('Why? marks this session\'s point and the faster laps\' on '
      'the map', (tester) async {
    await show(tester, lift: true);
    await reveal(tester, find.byKey(const ValueKey('coachWhy 0')));
    await tester.tap(find.byKey(const ValueKey('coachWhy 0')));
    await tester.pumpAndSettle();
    final map = tester.widget<TrackMap>(find.byKey(const ValueKey('coachMap')));
    expect(map.marks.map((mark) => mark.color), [lapBColor, lapAColor]);
    // On the best lap's line, where it was 54 m and 47 m along the lap.
    final page = tester.widget<CoachItemPage>(find.byType(CoachItemPage));
    final best = page.result.bestLap!;
    for (final (mark, progress) in [
      (map.marks[0], 53.71),
      (map.marks[1], 46.94),
    ]) {
      final at = lapPathPointAt(
        page.path!,
        page.result.timeAt(best, progress)!,
      )!;
      expect(mark.east, closeTo(at.east, 1e-9));
      expect(mark.north, closeTo(at.north, 1e-9));
    }
    final [faster, own] = map.marks;
    final apart = sqrt(
      pow(faster.east - own.east, 2) + pow(faster.north - own.north, 2),
    );
    expect(apart, inInclusiveRange(4, 8));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coachMapThis'))).data,
      "Lift point: this session's laps",
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coachMapFaster'))).data,
      'Lift point: your faster laps',
    );
  });

  testWidgets('Why? for the braking marker compares with the three fastest '
      'laps', (tester) async {
    await show(tester, braking: true);
    await reveal(tester, find.byKey(const ValueKey('coachWhy 0')));
    await tester.tap(find.byKey(const ValueKey('coachWhy 0')));
    await tester.pumpAndSettle();
    final map = tester.widget<TrackMap>(find.byKey(const ValueKey('coachMap')));
    expect(map.marks, hasLength(2));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coachMapFaster')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coachMapFaster'))).data,
      'Braking start: your three fastest laps today',
    );
  });

  testWidgets('Why? for an improvement to keep has no points on the map', (
    tester,
  ) async {
    await show(tester, lift: true);
    await reveal(tester, find.byKey(const ValueKey('coachWhy 1')));
    await tester.tap(find.byKey(const ValueKey('coachWhy 1')));
    await tester.pumpAndSettle();
    final map = tester.widget<TrackMap>(find.byKey(const ValueKey('coachMap')));
    expect(map.marks, isEmpty);
  });

  testWidgets('Why? for a speed item has no points on the map', (tester) async {
    await show(tester);
    await reveal(tester, find.byKey(const ValueKey('coachWhy 0')));
    await tester.tap(find.byKey(const ValueKey('coachWhy 0')));
    await tester.pumpAndSettle();
    final map = tester.widget<TrackMap>(find.byKey(const ValueKey('coachMap')));
    expect(map.marks, isEmpty);
    expect(find.byKey(const ValueKey('coachMapThis')), findsNothing);
  });

  testWidgets('in Polish', (tester) async {
    await show(tester, locale: const Locale('pl'));
    expect(find.text('Główny cel po sesji: Sesja 1'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coachGoalResult'))).data,
      'Prędkość minimalna: w poprzedniej sesji 44.0\u00a0km/h, w tej 46.9\u00a0km/h. '
      'Lepiej.',
    );
    expect(find.text('Następna sesja'), findsOneWidget);
    expect(find.text('Główny cel'), findsOneWidget);
    expect(find.text('Gdy to już wychodzi'), findsOneWidget);
    final measured = tester.widget<Text>(
      find.byKey(const ValueKey('coachMeasured 0')),
    );
    expect(
      measured.textSpan!.toPlainText(),
      startsWith('Zmierzono: Prędkość minimalna: 46.9\u00a0km/h'),
    );
  });

  testWidgets('fits a small phone with large text, one-handed', (tester) async {
    await show(tester, size: const Size(360, 640), textScale: 1.3);
    final why = find.byKey(const ValueKey('coachWhy 0'));
    await reveal(tester, why);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(why).height, greaterThanOrEqualTo(48));
    await tester.tap(why);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  String measured(WidgetTester tester, int index) => tester
      .widget<Text>(find.byKey(ValueKey('coachMeasured $index')))
      .textSpan!
      .toPlainText();

  testWidgets('speeds keep the unit the recordings declare: mph', (
    tester,
  ) async {
    await show(tester, header: 'velocity mph');
    expect(
      measured(tester, 0),
      'Measured: Minimum speed: 46.9\u00a0mph on this session\'s laps, 53.7\u00a0mph on your faster lap.',
    );
    expect(find.textContaining('km/h'), findsNothing);
  });

  testWidgets('speeds of recordings declaring no unit stay unlabelled', (
    tester,
  ) async {
    await show(tester, header: '');
    expect(
      measured(tester, 0),
      'Measured: Minimum speed: 46.9 on this session\'s laps, 53.7 on your faster lap.',
    );
    expect(find.byKey(const ValueKey('coachSpeedHidden')), findsNothing);
  });

  testWidgets('speeds of recordings declaring km/h say km/h', (tester) async {
    speedUnitSetting.value = SpeedUnitSetting.milesPerHour;
    await show(tester, header: 'velocity kmh');
    expect(measured(tester, 0), contains('46.9\u00a0km/h'));
  });

  testWidgets('converted speeds are not shown, and the card says why', (
    tester,
  ) async {
    // A speed channel declaring mph, as an RCZ recording can: the coach
    // converts its speeds to km/h, which are never shown converted.
    NamedRun inMph(NamedRun named) {
      final t = named.run.telemetry;
      final speed = t.aliases['speed'] ?? 'velocity';
      final channel = t.channels[speed]!;
      final r = named.run;
      return (
        run: TelemetryRunProposal(
          id: r.id,
          sourceId: r.sourceId,
          sourcePath: r.sourcePath,
          format: r.format,
          contentSha256: r.contentSha256,
          laps: r.laps,
          telemetry: TelemetrySession(
            duration: t.duration,
            startTime: t.startTime,
            metadata: t.metadata,
            channels: {
              ...t.channels,
              speed: TelemetryChannel(
                name: channel.name,
                unit: 'mph',
                timestamps: channel.timestamps,
                values: channel.values,
              ),
            },
            aliases: t.aliases,
            warnings: t.warnings,
            timingGates: t.timingGates,
            sampleCount: t.sampleCount,
          ),
        ),
        name: named.name,
      );
    }

    final controller = await show(
      tester,
      editRuns: (runs) => [inMph(runs.first), ...runs.skip(1)],
    );
    expect(controller.coachSpeedsConverted, isTrue);
    expect(
      measured(tester, 0),
      'Measured: Minimum speed: — on this session\'s laps, — on your faster lap.',
    );
    expect(find.byKey(const ValueKey('coachSpeedHidden')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('coachWhy 0')));
    await tester.tap(find.byKey(const ValueKey('coachWhy 0')));
    await tester.pumpAndSettle();
    expect(find.text('— against —'), findsOneWidget);
    expect(find.text('4.2\u00a0s against 4.0\u00a0s'), findsOneWidget);
    expect(find.textContaining('Speeds are not shown'), findsOneWidget);
  });

  testWidgets('a coach that fails says so instead of loading for ever', (
    tester,
  ) async {
    final controller = await show(
      tester,
      coachRunner: (job) async => throw StateError('broken'),
    );
    expect(controller.coachLoading, isFalse);
    expect(controller.coachError, contains('broken'));
    expect(
      find.text('The coach could not run: Bad state: broken'),
      findsOneWidget,
    );
  });

  testWidgets('a coach that failed runs again from Calculate again, '
      'its failure in the app\'s language', (tester) async {
    var fail = true;
    final release = Completer<void>();
    late DayResultsController controller;
    controller = await show(
      tester,
      locale: const Locale('pl'),
      coachRunner: (job) async {
        if (fail) throw const BackgroundTaskFailed('The work stopped.');
        await release.future;
        return plan(controller.theoreticalBest!, controller.latestRunId);
      },
    );
    addTearDown(() => Intl.defaultLocale = null);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coachReason'))).data,
      contains('Praca została przerwana.'),
    );
    fail = false;
    final again = find.descendant(
      of: find.byType(NextSessionCard),
      matching: find.byKey(const ValueKey('calculateAgain')),
    );
    await reveal(tester, again);
    await tester.tap(again);
    await tester.pump();
    // While it runs again, the card no longer shows the old failure.
    expect(controller.coachLoading, isTrue);
    expect(controller.coachError, isEmpty);
    expect(find.byKey(const ValueKey('coachReason')), findsNothing);
    release.complete();
    await tester.pumpAndSettle();
    expect(controller.coachError, isEmpty);
    expect(controller.coach, isNotNull);
    expect(again, findsNothing);
  });

  testWidgets('without a theoretical best the coach says why', (tester) async {
    var coached = false;
    final controller = await show(
      tester,
      theoreticalBestRunner: (job) async => DayTheoreticalBest(
        groupId: '',
        state: DayTheoreticalBestState.error,
        message: 'failed',
      ),
      coachRunner: (job) async {
        coached = true;
        return job();
      },
    );
    expect(coached, isFalse);
    expect(controller.coachLoading, isFalse);
    expect(
      find.text(
        'The coach needs the theoretical best, which could not be computed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('speeds of a day in mph and km/h are not shown', (tester) async {
    await show(tester, header: 'velocity kmh', mixed: 'velocity mph');
    expect(measured(tester, 0), contains('— on this session'));
    expect(find.byKey(const ValueKey('coachSpeedHidden')), findsOneWidget);
  });

  testWidgets('the label follows the unit setting while the day is open', (
    tester,
  ) async {
    await show(tester, header: '');
    expect(measured(tester, 0), contains('46.9 on this session'));
    speedUnitSetting.value = SpeedUnitSetting.milesPerHour;
    await tester.pumpAndSettle();
    expect(measured(tester, 0), contains('46.9\u00a0mph on this session'));
    await reveal(tester, find.byKey(const ValueKey('coachWhy 0')));
    await tester.tap(find.byKey(const ValueKey('coachWhy 0')));
    await tester.pumpAndSettle();
    expect(find.text('46.9\u00a0mph against 53.7\u00a0mph'), findsOneWidget);
    speedUnitSetting.value = SpeedUnitSetting.kilometresPerHour;
    await tester.pumpAndSettle();
    expect(find.text('46.9\u00a0km/h against 53.7\u00a0km/h'), findsOneWidget);
  });

  test('an early throttle item: picked up once, against the faster laps', () {
    final finding = CoachFinding(
      kind: CoachKind.earlyThrottle,
      segmentId: 's',
      segmentName: 'Corners 2–3',
      confidence: 0.83,
      affectedLaps: const [],
      evidence: [
        CoachEvidence(
          key: CoachMetric.firstThrottle,
          metric: 'First throttle pickup',
          observed: 475.2,
          reference: 541.4,
          unit: 'm',
          referenceLaps: const [],
          detail: '',
        ),
      ],
    );
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.coachKind(CoachKind.earlyThrottle), 'Pick up the throttle once');
    expect(
      en.coachMeasured(finding, 'km/h'),
      'First throttle pickup: 475\u00a0m on this session\'s laps, 541\u00a0m on your faster laps.',
    );
    expect(
      en.coachAction(CoachKind.earlyThrottle),
      startsWith('Wait to pick up'),
    );
    final pl = lookupAppLocalizations(const Locale('pl'));
    expect(pl.coachKind(CoachKind.earlyThrottle), 'Dodaj gaz raz');
    expect(
      pl.coachMeasured(finding, 'km/h'),
      startsWith('Pierwsze dodanie gazu: 475\u00a0m'),
    );
    // Checked next session by the share of laps picking up early.
    final goal = CoachGoalCheck(
      runId: 'run1',
      runName: 'Session 1',
      finding: finding,
      outcome: CoachGoalOutcome.better,
      before: 200 / 3,
      now: 0,
    );
    expect(en.coachMetric(goal.metric), 'Laps picking up the throttle early');
    expect(coachValue(goal.before!, goal.unit, 'km/h'), '67%');
    expect(coachValue(goal.now!, goal.unit, 'km/h'), '0%');
    expect(
      pl.coachMetric(goal.metric),
      'Okrążenia z przedwczesnym dodaniem gazu',
    );
  });

  test('mean combined G with two decimals', () {
    expect(coachValue(0.4867, 'g', 'km/h'), '0.49\u00a0g');
    expect(coachValue(double.nan, 'g', 'km/h'), '—');
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.coachMetric(CoachMetric.combinedG), 'Mean combined G');
    final pl = lookupAppLocalizations(const Locale('pl'));
    expect(
      pl.coachMetric(CoachMetric.combinedG),
      'Średnie łączne przeciążenie',
    );
    expect(
      en.coachMetric(CoachMetric.highestCombinedG),
      'Highest here: this session against today',
    );
  });

  test('a braking item compares with the three fastest laps of the day', () {
    CoachFinding braking() => CoachFinding(
      kind: CoachKind.inconsistentBraking,
      segmentId: 's',
      segmentName: 'Corner 7',
      confidence: 0.74,
      affectedLaps: const [],
      evidence: [
        CoachEvidence(
          key: CoachMetric.brakingSpread,
          metric: 'Braking point range',
          observed: 39.3,
          reference: 4.7,
          unit: 'm',
          referenceLaps: const [],
          detail: '',
        ),
      ],
    );
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      en.coachMeasured(braking(), 'km/h'),
      'Braking point range: 39\u00a0m on this session\'s laps, 5\u00a0m on your three fastest laps today.',
    );
    expect(
      en.coachKind(CoachKind.inconsistentBraking),
      'Brake at the same point every lap',
    );
    final pl = lookupAppLocalizations(const Locale('pl'));
    expect(
      pl.coachMeasured(braking(), 'km/h'),
      contains('trzech najszybszych okrążeniach dnia'),
    );
  });

  test('earlier laps are never the session coached\'s own', () {
    DayLapRow lap(String run, int number) => DayLapRow(
      runId: run,
      runName: run,
      type: LapSectionType.lap,
      lapNumber: number,
      start: number * 100.0,
      end: number * 100.0 + 90,
      sourceRevision: '',
    );
    // A braking item reads every lap of the session and lists those off the
    // usual point as the session's.
    final finding = CoachFinding(
      kind: CoachKind.inconsistentBraking,
      segmentId: 's',
      segmentName: 'Corner 7',
      confidence: 0.74,
      affectedLaps: [
        lap('run1', 4),
        lap('run2', 1),
        lap('run2', 2),
        lap('run2', 3),
      ],
      sessionLaps: [lap('run2', 1), lap('run2', 3)],
      evidence: const [],
    );
    expect(coachEarlierLaps(finding).map((l) => (l.runId, l.lapNumber)), [
      ('run1', 4),
    ]);
  });
}
