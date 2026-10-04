import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/next_session_card.dart';
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
      // A change also seen on earlier laps of the day.
      sessionLaps: kind.corrective ? laps.skip(2).take(1).toList() : null,
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
      // The change first: the main focus.
      plan: [CoachItem(change), CoachItem(keep)],
      reason: CoachReason.ready,
      slowLaps: [laps.last],
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

  testWidgets('in Polish', (tester) async {
    await show(tester, locale: const Locale('pl'));
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
}
