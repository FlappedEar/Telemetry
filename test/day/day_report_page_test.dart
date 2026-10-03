import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/channel_cards.dart';
import 'package:telemetry/day/day_report_page.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/focus_areas_card.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('day_report'));
  tearDown(() => directory.deleteSync(recursive: true));

  // Two sessions on the rectangle, with an oil temperature and heart rate:
  // each lap slows somewhere else, so sectors differ between laps.
  DayImportOutcome importDay({bool car = true}) {
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
      File(path).writeAsStringSync(rectangleVbo(laps, car: car));
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  Finder summary() => find
      .descendant(
        of: find.byKey(const ValueKey('dayResultsSummary')),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<DayResultsController> open(
    WidgetTester tester,
    DayImportOutcome outcome,
  ) async {
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 200, scrollable: summary());
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('the car and driver cards summarize every session', (
    tester,
  ) async {
    final controller = await open(tester, importDay());
    final channels = controller.channelSummaries!;
    expect(channels.error, isEmpty);
    expect(channels.temperatureChannels, ['oil_temp']);
    expect(channels.hasHeartRate, isTrue);
    final oil = find.byKey(const ValueKey('carChannel oil_temp'));
    await reveal(tester, oil);
    expect(
      find.descendant(of: oil, matching: find.textContaining('Oil · oil_temp')),
      findsOneWidget,
    );
    for (final run in channels.runs) {
      final whole = run.channel('oil_temp')!.run;
      expect(
        find.descendant(
          of: oil,
          matching: find.textContaining(
            '${run.runName}: mean ${whole.mean!.toStringAsFixed(0)}',
          ),
        ),
        findsOneWidget,
      );
    }
    // Two sessions with two and three laps: too few for an association,
    // said as such and never as a number.
    expect(
      find.byKey(const ValueKey('carAssociation oil_temp')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('carAssociation oil_temp')))
          .data,
      contains('at least $minimumAssociationSamples are needed'),
    );
    await tester.tap(oil);
    await tester.pumpAndSettle();
    expect(find.byType(ChannelPage), findsOneWidget);
    expect(find.textContaining('Cooling: −'), findsWidgets);
    expect(find.text('With lap performance'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final heart = find.byKey(
      ValueKey('heartRate ${channels.runs.first.runId}'),
    );
    await reveal(tester, heart);
    expect(tester.widget<Text>(heart).data, startsWith('mean 1'));
    final lapChip = find.byType(ActionChip).first;
    await tester.ensureVisible(lapChip);
    await tester.pumpAndSettle();
    await tester.tap(lapChip);
    await tester.pumpAndSettle();
    expect(find.byType(LapPage), findsOneWidget);
  });

  testWidgets('the car and driver cards speak Polish', (tester) async {
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
    final oil = find.byKey(const ValueKey('carChannel oil_temp'));
    await reveal(tester, oil);
    expect(find.text('Samochód'), findsOneWidget);
    expect(find.text('Car'), findsNothing);
    expect(
      find.descendant(
        of: oil,
        matching: find.textContaining('Olej · oil_temp'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: oil,
        matching: find.textContaining('Sesja 1: średnio '),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('carAssociation oil_temp')))
          .data,
      startsWith('Czas okrążenia: '),
    );
    final heart = find.byKey(
      ValueKey('heartRate ${controller.channelSummaries!.runs.first.runId}'),
    );
    await reveal(tester, heart);
    expect(find.text('Kierowca'), findsOneWidget);
    expect(find.text('Driver'), findsNothing);
    expect(find.textContaining('OKR. '), findsWidgets);

    await tester.scrollUntilVisible(oil, -200, scrollable: summary());
    await tester.ensureVisible(oil);
    await tester.pumpAndSettle();
    await tester.tap(oil);
    await tester.pumpAndSettle();
    expect(find.text('Związek z osiągami na okrążeniu'), findsOneWidget);
    expect(find.textContaining('Chłodzenie: '), findsWidgets);
    expect(find.text('With lap performance'), findsNothing);
  });

  testWidgets('without channels the cards say so', (tester) async {
    await open(tester, importDay(car: false));
    final none = find.byKey(const ValueKey('carNoChannels'));
    await reveal(tester, none);
    expect(none, findsOneWidget);
    expect(find.byKey(const ValueKey('driverNoHeartRate')), findsOneWidget);
  });

  testWidgets('a focus area shows the observation apart from the hypothesis '
      'and compares its two laps', (tester) async {
    final controller = await open(tester, importDay());
    final areas = controller.focusAreas;
    expect(areas, isNotEmpty);
    expect(areas.length, lessThanOrEqualTo(3));
    final first = find.byKey(const ValueKey('focusArea 0'));
    await reveal(tester, first);
    expect(
      find.descendant(
        of: first,
        matching: find.text('Observed: ${areas.first.observation}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: first,
        matching: find.text('Hypothesis: ${areas.first.hypothesis}'),
      ),
      findsOneWidget,
    );
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.byType(FocusAreaPage), findsOneWidget);
    expect(find.byKey(const ValueKey('focusLapA')), findsOneWidget);
    expect(find.byKey(const ValueKey('focusLapB')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('focusLapA'))).data,
      isNot(contains('not timed')),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('focusOpenLapB')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focusOpenLapB')));
    await tester.pumpAndSettle();
    expect(find.byType(LapPage), findsOneWidget);
  });

  testWidgets('the day report presents what was calculated', (tester) async {
    final controller = await open(tester, importDay());
    final report = controller.dayReportDocument;
    expect(validateDayReport(report), '');
    final statuses = {
      for (final result in (report['results'] as List).cast<Map>())
        result['id']: result['status'],
    };
    expect(statuses['bestLap'], 'available');
    expect(statuses['theoreticalBest'], 'available');
    expect(statuses['focusAreas'], 'available');
    expect(statuses['temperatures'], 'available');
    expect(statuses['heartRate'], 'available');
    await tester.tap(find.byKey(const ValueKey('openDayReport')));
    await tester.pumpAndSettle();
    expect(find.byType(DayReportPage), findsOneWidget);
    final best = controller.ranking!.bestOfDay!;
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('dayReportBestTime'))).data,
      displayTime(best.durationSeconds),
    );
    expect(
      find.byKey(const ValueKey('dayReportFocusObservation0')),
      findsOneWidget,
    );
    final list = find.byType(Scrollable).first;
    for (final key in [
      'dayReportLosses',
      'dayReportSessions',
      'dayReportConsistency',
      'dayReportTemperature0',
      'dayReportHeartRate0',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        200,
        scrollable: list,
      );
    }
    expect(find.textContaining('Oil · peak'), findsOneWidget);
    expect(find.textContaining('recorded cooling interval'), findsOneWidget);
    // Evidence leads to its lap.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dayReportSession0')),
      -200,
      scrollable: list,
    );
    await tester.tap(find.byKey(const ValueKey('dayReportSession0')));
    await tester.pumpAndSettle();
    expect(find.byType(LapPage), findsOneWidget);
  });

  testWidgets('a report result not calculated yet says why, never zero', (
    tester,
  ) async {
    final outcome = importDay();
    final report = dayReport(
      analysis: outcome.analysis!,
      eventId: 'event',
      runs: const [],
      channelsLoading: true,
    );
    await tester.pumpWidget(TelemetryApp(home: DayReportPage(report: report)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('dayReportTheoreticalTime')))
          .data,
      '—',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('dayReportTheoreticalNote')))
          .data,
      'Not calculated yet.',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dayReportCar')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dayReportCar')),
        matching: find.text('Calculating…'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining(' 0 s'), findsNothing);
  });

  testWidgets('the day report speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final controller = await open(tester, importDay());
    final report = controller.dayReportDocument;
    await tester.binding.setSurfaceSize(const Size(412, 6000));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: DayReportPage(report: report),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Raport dnia'), findsOneWidget);
    expect(find.text('Day report'), findsNothing);
    expect(find.textContaining('Grupa 1 · '), findsOneWidget);
    expect(find.text('Najlepsze okrążenie i co zostało'), findsOneWidget);
    expect(find.text('Best lap and what is left'), findsNothing);
    expect(find.textContaining('· OKR. '), findsWidgets);
    expect(find.textContaining('Zmierzono: '), findsWidgets);
    expect(find.textContaining('Observed: '), findsNothing);
    expect(find.textContaining('Your best lap'), findsNothing);
    expect(find.text('Największe straty czasu'), findsOneWidget);
    expect(find.textContaining('Względem Sesja '), findsOneWidget);
    expect(find.text('Sesje'), findsOneWidget);
    expect(find.textContaining('kwalifikuje się'), findsWidgets);
    expect(find.text('Powtarzalność'), findsOneWidget);
    expect(find.textContaining('Typowe okrążenie '), findsOneWidget);
    expect(find.textContaining('Olej · maksimum'), findsOneWidget);
    expect(find.text('Tętno'), findsOneWidget);
    expect(find.textContaining('ud./min'), findsWidgets);
    expect(find.textContaining('laps'), findsNothing);

    // A result not calculated yet says why in Polish.
    final outcome = importDay();
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: DayReportPage(
          report: dayReport(
            analysis: outcome.analysis!,
            eventId: 'event',
            runs: const [],
            channelsLoading: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('dayReportTheoreticalNote')))
          .data,
      'Jeszcze nie obliczono.',
    );
    expect(find.text('Obliczanie…'), findsWidgets);
    expect(find.text('Calculating…'), findsNothing);
  });
}
