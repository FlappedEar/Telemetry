import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/next_session_card.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('coach'));
  tearDown(() => directory.deleteSync(recursive: true));

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

  // A plan with one change and one improvement, on the day's own laps and
  // first corner, as the coach would give it.
  DayCoach plan(DayTheoreticalBest result, String runId) {
    final laps = [for (final sectors in result.laps) sectors.lap];
    final segment = result.segments.firstWhere(
      (s) => s.type == 'corner',
      orElse: () => result.segments.first,
    );
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
      affectedLaps: laps.take(3).toList(),
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
    final change = finding(
      CoachKind.lowMinimumSpeed,
      CoachMetric.minimumSpeed,
      'km/h',
      [laps.last],
    );
    final keep = finding(
      CoachKind.improving,
      CoachMetric.minimumSpeed,
      'km/h',
      [laps.first],
    );
    return DayCoach(
      runId: runId,
      findings: [change, keep],
      plan: [CoachItem(keep), CoachItem(change)],
      reason: CoachReason.ready,
    );
  }

  Future<DayResultsController> show(
    WidgetTester tester, {
    Locale? locale,
    bool withPlan = true,
    Size size = const Size(412, 915),
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final outcome = importDay();
    late DayResultsController controller;
    controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      coachRunner: (job) async => withPlan
          ? plan(controller.theoreticalBest!, controller.latestRunId)
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
    expect(reason.data, isNot('Choose one focus at a time for your next run.'));
  });

  testWidgets(
    'each item is a labelled suggestion: measured apart from what to try',
    (tester) async {
      await show(tester);
      expect(find.text('Coach suggestion'), findsNWidgets(2));
      final measured = tester.widget<Text>(
        find.byKey(const ValueKey('coachMeasured 1')),
      );
      expect(
        measured.textSpan!.toPlainText(),
        'Measured: Minimum speed: 46.9 km/h on this session\'s laps, 53.7 km/h on your faster lap.',
      );
      final action = tester.widget<Text>(
        find.byKey(const ValueKey('coachAction 1')),
      );
      expect(
        action.textSpan!.toPlainText(),
        startsWith('Try: Repeat the line'),
      );
      final keep = tester.widget<Text>(
        find.byKey(const ValueKey('coachAction 0')),
      );
      expect(
        keep.textSpan!.toPlainText(),
        startsWith('Keep: Keep the approach'),
      );
      expect(
        find.textContaining('suggest an opportunity, not a promised gain'),
        findsOneWidget,
      );
      // The observations follow it, labelled as such.
      await reveal(tester, find.text('Where to look next'));
      expect(find.text('Where to look next'), findsOneWidget);
    },
  );

  testWidgets('Why? shows the measured values and the corner on the map', (
    tester,
  ) async {
    await show(tester);
    await reveal(tester, find.byKey(const ValueKey('coachWhy 1')));
    await tester.tap(find.byKey(const ValueKey('coachWhy 1')));
    await tester.pumpAndSettle();
    expect(find.byType(CoachItemPage), findsOneWidget);
    expect(find.text('46.9 km/h against 53.7 km/h'), findsOneWidget);
    expect(find.text('4.2 s against 4.0 s'), findsOneWidget);
    expect(find.byKey(const ValueKey('coachMap')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('not a probability'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('not a probability'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Polish', (tester) async {
    await show(tester, locale: const Locale('pl'));
    expect(find.text('Następna sesja'), findsOneWidget);
    expect(find.text('Sugestia trenera'), findsNWidgets(2));
    final measured = tester.widget<Text>(
      find.byKey(const ValueKey('coachMeasured 1')),
    );
    expect(
      measured.textSpan!.toPlainText(),
      startsWith('Zmierzono: Najmniejsza prędkość: 46.9 km/h'),
    );
  });

  testWidgets('fits a small phone with large text, one-handed', (tester) async {
    await show(tester, size: const Size(360, 640), textScale: 1.3);
    final why = find.byKey(const ValueKey('coachWhy 1'));
    await reveal(tester, why);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(why).height, greaterThanOrEqualTo(48));
    await tester.tap(why);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
