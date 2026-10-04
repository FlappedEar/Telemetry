// Corner variability on the theoretical best card, and the retry actions
// Overlays offers on analysis status notices (FET-54). Synthetic
// recordings only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/theoretical_best_card.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_page_test.dart' show FakeDocuments, circuitVbo;
import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('status'));
  tearDown(() => deleteTemporaryDirectory(directory));

  DayImportOutcome rectangleDay() {
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

  Finder summaryList() => find
      .descendant(
        of: find.byKey(const ValueKey('dayResultsSummary')),
        matching: find.byType(Scrollable),
      )
      .first;

  group('variabilityLines', () {
    ConsistencySummary summary(int count, double median, double spread) =>
        ConsistencySummary(
          count: count,
          median: median,
          interquartileRange: spread,
          available: count >= 3,
          unavailableReason: count >= 3 ? '' : 'too few',
        );

    test('labels measured and inferred, and says when laps are too few', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final lines = variabilityLines(
        l10n,
        CornerVariability(
          name: 'Corner 1',
          brakingPointMeasured: summary(5, 120, 4.24),
          brakingPointInferred: summary(2, 118, 1),
          minimumSpeed: summary(5, 72.44, 1.81),
          pickupInferred: summary(4, 40, 3),
          lineOffset: summary(5, 0, 1.4),
          typicalGpsAccuracyMeters: 0.8,
          lineSpreadResolvable: true,
        ),
        'km/h',
      );
      expect(lines, [
        'Braking point: spread 4.2\u00a0m · 5 laps · measured',
        'Braking point: too few laps (2 laps · inferred)',
        'Minimum speed: typical 72.4\u00a0km/h · spread 1.8\u00a0km/h · 5 laps',
        'Throttle pickup: spread 3.0\u00a0m · 4 laps · inferred',
        'Line: spread 1.4\u00a0m · GPS accuracy about 0.80\u00a0m',
      ]);
      expect(
        variabilityLines(
          l10n,
          CornerVariability(lineOffset: summary(4, 0, 0.5)),
          '',
        ),
        [
          'Line: spread 0.5\u00a0m · GPS accuracy not recorded'
              ' · not distinguishable from GPS error',
        ],
      );
      expect(variabilityLines(l10n, const CornerVariability(), ''), isEmpty);
    });

    test('in Polish', () {
      final l10n = lookupAppLocalizations(const Locale('pl'));
      expect(
        variabilityLines(
          l10n,
          CornerVariability(
            exitSpeed: summary(3, 90, 2),
            apexSpeed: summary(2, 80, 1),
          ),
          'km/h',
        ),
        [
          'Prędkość na wierzchołku: za mało okrążeń (2 okrążenia)',
          'Prędkość na wyjściu: typowa 90.0\u00a0km/h · rozrzut 2.0\u00a0km/h · '
              '3 okrążenia',
        ],
      );
    });
  });

  testWidgets('the theoretical best card lists each corner lap to lap on a '
      'phone', (tester) async {
    final outcome = rectangleDay();
    final expected = dayTheoreticalBest(
      outcome.analysis!,
      outingRuns(outcome.runs),
    );
    final corners = [
      for (final row in expected.segments)
        if (row.variability != null) row,
    ];
    expect(corners, isNotEmpty);
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(ValueKey('variability ${corners.first.name}'));
    await tester.scrollUntilVisible(tile, 300, scrollable: summaryList());
    await tester.pumpAndSettle();
    expect(find.text('Lap to lap in each corner'), findsOneWidget);
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
    final l10n = lookupAppLocalizations(const Locale('en'));
    final lines = variabilityLines(
      l10n,
      corners.first.variability!,
      speedUnitLabel(),
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    for (final line in lines.isEmpty ? [l10n.variabilityNotMeasured] : lines) {
      expect(find.text(line), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed theoretical best is calculated again', (tester) async {
    final outcome = rectangleDay();
    var calls = 0;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      theoreticalBestRunner: (job) async {
        if (++calls == 1) throw StateError('Out of memory');
        return job();
      },
    );
    await tester.binding.setSurfaceSize(const Size(412, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(controller.theoreticalBest!.state, DayTheoreticalBestState.error);
    // The error and its retry once, on the theoretical best card; the cards
    // built on it say only that it is not available.
    expect(find.byKey(const ValueKey('calculateAgain')), findsOneWidget);
    expect(find.textContaining('Out of memory'), findsOneWidget);
    expect(
      find.text('Not available: the theoretical best could not be calculated.'),
      findsWidgets,
    );
    await tester.tap(find.byKey(const ValueKey('calculateAgain')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(controller.theoreticalBest!.state, DayTheoreticalBestState.ready);
    expect(find.byKey(const ValueKey('calculateAgain')), findsNothing);
    // A ready result is not calculated again.
    expect(controller.retryTheoreticalBest(), isFalse);
  });

  test('only an unavailable or failed result offers calculating again', () {
    DayTheoreticalBest of(DayTheoreticalBestState state) =>
        DayTheoreticalBest(groupId: 'g', state: state, message: '');
    expect(
      offersCalculateAgain(of(DayTheoreticalBestState.unavailable)),
      isTrue,
    );
    expect(offersCalculateAgain(of(DayTheoreticalBestState.error)), isTrue);
    expect(offersCalculateAgain(of(DayTheoreticalBestState.ready)), isFalse);
  });

  test('a result requested before calculating again is dropped', () async {
    final outcome = rectangleDay();
    var calls = 0;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      theoreticalBestRunner: (job) async {
        ++calls;
        if (calls == 1) {
          return DayTheoreticalBest(
            groupId: 'g',
            state: DayTheoreticalBestState.error,
            message: 'Failed.',
          );
        }
        return job();
      },
    );
    addTearDown(controller.dispose);
    await controller.requestTheoreticalBest();
    expect(controller.theoreticalBest!.state, DayTheoreticalBestState.error);
    expect(controller.retryTheoreticalBest(), isTrue);
    expect(controller.theoreticalBestLoading, isTrue);
    // Asked again while it runs: nothing new starts.
    expect(controller.retryTheoreticalBest(), isFalse);
    await pumpEventQueue();
    expect(controller.theoreticalBest!.state, DayTheoreticalBestState.ready);
    expect(calls, 2);
  });

  testWidgets('retries the recordings where the day says they are', (
    tester,
  ) async {
    final outcome = runDayImport((
      paths: [
        for (final (name, speeds) in [
          ('a.vbo', <double>[30, 28, 31]),
          ('b.vbo', <double>[29, 32]),
        ])
          (File(
            '${directory.path}/$name',
          )..writeAsStringSync(circuitVbo(speeds))).path,
      ],
      includeSubfolders: false,
    ));
    final path = '${directory.path}/Day.fetproject';
    final away = '${directory.path}/away.vbo';
    final opened = (await tester.runAsync(() async {
      await saveDayDocument(
        path,
        dayDocument(
          eventId: newEventId(),
          name: 'Track day',
          runs: outcome.runs,
          analysis: outcome.analysis!,
          projectPath: path,
        ),
      );
      File('${directory.path}/b.vbo').renameSync(away);
      return openDay(path);
    }))!;
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.opened(day: opened, documents: FakeDocuments()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 session could not be opened'), findsOneWidget);
    final retry = find.byKey(const ValueKey('retryRecordings'));
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

    // Still away: said, and the day stays as it is.
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(
      find.text('The recordings are still not where the day says.'),
      findsOneWidget,
    );
    expect(find.text('1 session could not be opened'), findsOneWidget);

    // A document that cannot be read any more: said, the day stays.
    final saved = File(path).readAsBytesSync();
    File(path).writeAsStringSync('{not json');
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The day could not be opened again: '),
      findsOneWidget,
    );
    expect(find.text('1 session could not be opened'), findsOneWidget);
    File(path).writeAsBytesSync(saved);
    ScaffoldMessenger.of(tester.element(retry)).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    // Back where the day says: the day opens again with both sessions.
    File(away).renameSync('${directory.path}/b.vbo');
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('1 session could not be opened'), findsNothing);
    expect(find.byKey(const ValueKey('retryRecordings')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retrying the recordings runs in its own isolate', (
    tester,
  ) async {
    debugRunInIsolate = true;
    addTearDown(() => debugRunInIsolate = false);
    final outcome = runDayImport((
      paths: [
        for (final (name, speeds) in [
          ('a.vbo', <double>[30, 28, 31]),
          ('b.vbo', <double>[29, 32]),
        ])
          (File(
            '${directory.path}/$name',
          )..writeAsStringSync(circuitVbo(speeds))).path,
      ],
      includeSubfolders: false,
    ));
    final path = '${directory.path}/Day.fetproject';
    final away = '${directory.path}/away.vbo';
    final opened = (await tester.runAsync(() async {
      await saveDayDocument(
        path,
        dayDocument(
          eventId: newEventId(),
          name: 'Track day',
          runs: outcome.runs,
          analysis: outcome.analysis!,
          projectPath: path,
        ),
      );
      File('${directory.path}/b.vbo').renameSync(away);
      return openDay(path);
    }))!;
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.opened(day: opened, documents: FakeDocuments()),
      ),
    );
    await tester.pumpAndSettle();
    File(away).renameSync('${directory.path}/b.vbo');
    await tester.tap(find.byKey(const ValueKey('retryRecordings')));
    await tester.pump();
    final missingCard = find.text('1 session could not be opened');
    for (
      var tries = 0;
      tries < 100 && missingCard.evaluate().isNotEmpty;
      tries++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(missingCard, findsNothing);
    expect(find.textContaining('could not be opened again'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
