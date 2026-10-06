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
import 'package:telemetry/day/next_session_card.dart';
import 'package:telemetry/day/report_share.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  group('share', _shareTests);
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('day_report'));
  tearDown(() => deleteTemporaryDirectory(directory));

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
        matching: find.textContaining('Temperatura oleju · oil_temp'),
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
    expect(find.text('Związek z wynikami przejazdu okrążeń'), findsOneWidget);
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
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.replaceAll('\u00a0', ' ') ==
                  'Observed: ${areas.first.observation}',
        ),
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

  testWidgets('on a large screen the report stays 840 wide, centred', (
    tester,
  ) async {
    final controller = await open(tester, importDay());
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayReportPage(report: controller.dayReportDocument)),
    );
    await tester.pumpAndSettle();
    final group = tester.getRect(find.byKey(const ValueKey('dayReportGroup')));
    expect(group.left, 540);
    expect(group.right, lessThanOrEqualTo(1380));
  });

  testWidgets('a wide screen has the report as a tab beside Compare', (
    tester,
  ) async {
    await open(tester, importDay());
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    await tester.pumpAndSettle();
    final tabs = find.byKey(const ValueKey('daySections'));
    for (final label in ['Overview', 'Compare', 'Report']) {
      expect(
        find.descendant(of: tabs, matching: find.text(label)),
        findsOneWidget,
      );
    }
    // The laps are beside the overview, not a tab; the report is no longer
    // a toolbar button.
    expect(
      find.descendant(of: tabs, matching: find.text('Laps')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('openDayReport')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('daySection-report')));
    await tester.pumpAndSettle();
    // At most 840 wide, centred in the page.
    final group = tester.getRect(find.byKey(const ValueKey('dayReportGroup')));
    expect(group.left, 540);
    expect(group.right, lessThanOrEqualTo(1380));
    final list = find
        .descendant(
          of: find.byKey(const ValueKey('dayReport')),
          matching: find.byType(Scrollable),
        )
        .first;
    final session = find.byKey(const ValueKey('dayReportSession0'));
    await tester.scrollUntilVisible(session, 200, scrollable: list);
    await tester.ensureVisible(session);
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(list).position.pixels;
    expect(offset, greaterThan(0));
    // Evidence opens its lap; back on the day, the report is where it was.
    await tester.tap(session);
    await tester.pumpAndSettle();
    expect(find.byType(LapPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dayReportGroup')).hitTestable(),
      findsNothing,
    );
    expect(tester.state<ScrollableState>(list).position.pixels, offset);
    // Overview and back keeps the place too.
    await tester.tap(find.byKey(const ValueKey('daySection-overview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daySection-report')));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(list).position.pixels, offset);
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
    expect(find.byKey(const ValueKey('openDayReport')), findsNothing);
    // The day page's Report tab.
    await tester.tap(find.byKey(const ValueKey('daySection-report')));
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
    // The focus kind is a label, so it is grey, not an accent colour.
    final kind = find.byKey(const ValueKey('dayReportFocusKind0'));
    expect(
      tester.widget<Text>(kind).style?.color,
      Theme.of(tester.element(kind)).colorScheme.onSurfaceVariant,
    );
    final list = find
        .descendant(
          of: find.byKey(const ValueKey('dayReport')),
          matching: find.byType(Scrollable),
        )
        .first;
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
    expect(find.textContaining(' 0\u00a0s'), findsNothing);
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
    expect(
      find.text('Najlepsze okrążenie i różnica do czasu teoretycznego'),
      findsOneWidget,
    );
    expect(find.text('Best lap and what is left'), findsNothing);
    expect(find.textContaining('· OKR. '), findsWidgets);
    expect(find.textContaining('Zaobserwowano: '), findsWidgets);
    expect(find.textContaining('Observed: '), findsNothing);
    expect(find.textContaining('Your best lap'), findsNothing);
    expect(find.text('Największe straty czasu'), findsOneWidget);
    expect(find.textContaining('Względem Sesja '), findsOneWidget);
    expect(find.text('Sesje'), findsOneWidget);
    expect(find.textContaining('kwalifikuj'), findsWidgets);
    expect(find.text('Powtarzalność'), findsOneWidget);
    expect(find.textContaining('Typowy czas okrążenia '), findsOneWidget);
    expect(find.textContaining('Temperatura oleju · maksimum'), findsOneWidget);
    expect(find.text('Tętno'), findsOneWidget);
    expect(find.textContaining('\u00a0bpm'), findsWidgets);
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

/// The report image's path instead of the share sheet or save dialog.
final class _FakeSharer implements ReportSharer {
  _FakeSharer(this.folder, {this.shares = true, this.chosen, this.work});

  final Directory folder;
  @override
  final bool shares;

  /// What the save dialog answers; null is cancelled.
  final String? chosen;
  final shared = <String>[];
  final asked = <String>[];

  /// Where the image is written before sharing; in [folder] when null.
  final String? work;

  @override
  Future<String?> saveLocation(String fileName) async {
    asked.add(fileName);
    return chosen;
  }

  @override
  Future<String> workFile(String fileName) async =>
      work ?? '${folder.path}/$fileName';

  @override
  Future<bool> share(String path, Rect origin) async {
    shared.add(path);
    return true;
  }
}

/// The width and height a PNG's header says.
(int, int) _pngSize(List<int> bytes) {
  int word(int at) =>
      bytes[at] << 24 |
      bytes[at + 1] << 16 |
      bytes[at + 2] << 8 |
      bytes[at + 3];
  expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
  return (word(16), word(20));
}

void _shareTests() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('report_share'));
  tearDown(() => deleteTemporaryDirectory(directory));

  DayImportOutcome importDay() {
    final path = '${directory.path}/a.vbo';
    File(path).writeAsStringSync(
      rectangleVbo([
        rectangleLap(30, 50, 120, 20),
        rectangleLap(31, 300, 400, 25),
        rectangleLap(30, 550, 650, 22),
      ], car: true),
    );
    return runDayImport((paths: [path], includeSubfolders: false));
  }

  Future<void> openReport(WidgetTester tester, ReportSharer sharer) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          reportSharer: sharer,
          disposesController: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daySection-report')));
    await tester.pumpAndSettle();
  }

  Future<void> tapShare(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('dayReportShare')));
      for (var wait = 0; wait < 1500 && !done(); ++wait) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
  }

  // Real time passes until [finder] shows: the write after the image is
  // asynchronous, so a file that exists may not be finished yet.
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var wait = 0; wait < 500 && finder.evaluate().isEmpty; ++wait) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('on a phone the report goes to the share sheet as one image', (
    tester,
  ) async {
    final sharer = _FakeSharer(directory);
    await openReport(tester, sharer);
    await tapShare(tester, () => sharer.shared.isNotEmpty);
    expect(sharer.shared, hasLength(1));
    expect(sharer.shared.single, endsWith('.png'));
    final (width, height) = _pngSize(
      File(sharer.shared.single).readAsBytesSync(),
    );
    // 600 wide drawn at twice that; tall enough for every card.
    expect(width, 1200);
    expect(height, greaterThan(1200));
    expect(sharer.asked, isEmpty);
  });

  testWidgets('on desktop the image is saved where the driver chooses', (
    tester,
  ) async {
    final target = '${directory.path}/chosen.png';
    final sharer = _FakeSharer(directory, shares: false, chosen: target);
    await openReport(tester, sharer);
    await tapShare(tester, () => File(target).existsSync());
    await settleUntil(tester, find.text('Report saved as an image.'));
    expect(sharer.asked.single, endsWith('.png'));
    expect(_pngSize(File(target).readAsBytesSync()).$1, 1200);
    expect(find.text('Report saved as an image.'), findsOneWidget);
  });

  testWidgets('a cancelled save writes nothing and says nothing', (
    tester,
  ) async {
    final cancelled = _FakeSharer(directory, shares: false);
    await openReport(tester, cancelled);
    await tapShare(tester, () => cancelled.asked.isNotEmpty);
    expect(cancelled.asked, hasLength(1));
    expect(find.text('Report saved as an image.'), findsNothing);
  });

  testWidgets('the image has the cards under the day name, without buttons', (
    tester,
  ) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(600, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: SingleChildScrollView(
          child: DayReportPage(
            report: controller.dayReportDocument,
            printable: true,
            heading: 'Jastrząb 29 Aug',
            onOpenLap: (_) {},
            onShare: (_) async {},
          ),
        ),
      ),
    );
    expect(find.text('Jastrząb 29 Aug'), findsOneWidget);
    expect(find.byKey(const ValueKey('dayReportBest')), findsOneWidget);
    expect(find.byKey(const ValueKey('dayReportShare')), findsNothing);
    expect(find.byKey(const ValueKey('dayReportOpenBestLap')), findsNothing);
    expect(find.text('FlappedEar Telemetry'), findsOneWidget);
  });

  testWidgets('a report image that cannot be written says why', (tester) async {
    final sharer = _FakeSharer(
      directory,
      work: '${directory.path}/missing/folder/report.png',
    );
    await openReport(tester, sharer);
    // Nothing to wait on but the message.
    await tapShare(tester, () => true);
    await settleUntil(tester, find.textContaining('could not be made'));
    expect(
      find.textContaining('The report image could not be made: '),
      findsOneWidget,
    );
    expect(sharer.shared, isEmpty);
  });

  testWidgets('the coach goes into the image without its buttons', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: SingleChildScrollView(
          child: DayReportPage(
            report: const {'groupLabel': 'Unresolved · 1', 'results': []},
            printable: true,
            heading: 'Day',
            extra: [
              NextSessionCard(
                coach: null,
                result: null,
                session: '2',
                lapLabel: (_) => '',
                error: 'Out of memory',
                onRetry: () {},
                printable: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('nextSessionCard')), findsOneWidget);
    expect(find.byKey(const ValueKey('coachReason')), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a report too tall for one image is refused, never cut', (
    tester,
  ) async {
    Object? error;
    await tester.runAsync(() async {
      try {
        await renderWidgetImage(
          tester.view,
          const SizedBox(width: 600, height: 20000),
          width: 600,
        );
      } on Object catch (caught) {
        error = caught;
      }
    });
    expect(error, isA<ReportImageTooLong>());
    final l10n = lookupAppLocalizations(const Locale('pl'));
    expect(
      reportShareError(l10n, error!),
      'Raport jest za długi na jeden obraz.',
    );
    expect(
      reportShareError(
        l10n,
        const FileSystemException('x', 'p', OSError('Brak miejsca', 28)),
      ),
      'Brak miejsca',
    );
  });

  test('the file is named after the day', () {
    expect(
      reportFileName('Jastrząb 29/08: day', 'Day report'),
      'Jastrząb 29 08 day.png',
    );
    expect(reportFileName('  ', 'Day report'), 'Day report.png');
    expect(reportFileName('con', 'Day report'), 'Day report.png');
    expect(reportFileName('Day 1.', 'Day report'), 'Day 1.png');
    expect(reportFileName('x' * 300, 'Day report').length, 104);
  });
}
