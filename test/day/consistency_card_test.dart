import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/consistency_card.dart';
import 'package:telemetry/day/segment_spread_map.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('consistency'));
  tearDown(() => directory.deleteSync(recursive: true));

  // Session 1 drives four laps, session 2 two (four with [longerLatest]).
  DayImportOutcome importDay({bool longerLatest = false}) {
    final files = {
      'a.vbo': [
        rectangleLap(30, 50, 120, 20),
        rectangleLap(31, 300, 400, 25),
        rectangleLap(30, 550, 650, 22),
        rectangleLap(30.5, 100, 160, 24),
      ],
      'b.vbo': [
        rectangleLap(29),
        rectangleLap(30.5, 700, 780, 20),
        if (longerLatest) ...[
          rectangleLap(29.5, 200, 260, 22),
          rectangleLap(30, 400, 480, 18),
        ],
      ],
    };
    final paths = <String>[];
    files.forEach((name, laps) {
      final path = '${directory.path}/$name';
      File(path).writeAsStringSync(rectangleVbo(laps));
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  testWidgets('the consistency card speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay();
    final analysis = outcome.analysis!;
    final result = dayTheoreticalBest(analysis, outingRuns(outcome.runs));
    expect(result.state, DayTheoreticalBestState.ready);
    await tester.binding.setSurfaceSize(const Size(412, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: Scaffold(
          body: ListView(
            children: [
              ConsistencyCard(
                laps: dayLapConsistency(analysis),
                result: result,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Powtarzalność'), findsOneWidget);
    expect(find.text('Wszystkie sesje'), findsOneWidget);
    expect(find.text('Sesja 1'), findsOneWidget);
    expect(find.text('Zakręt 1'), findsOneWidget);
    expect(find.textContaining('rozrzut'), findsWidgets);
    expect(find.text('Potrzeba co najmniej 3 okrążeń'), findsOneWidget);
    expect(find.text('2 okrążenia'), findsOneWidget);
    expect(find.text('Consistency'), findsNothing);
    expect(find.textContaining('spread'), findsNothing);
  });

  testWidgets('a session waiting for the theoretical best speaks Polish', (
    tester,
  ) async {
    addTearDown(() => Intl.defaultLocale = null);
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: Scaffold(
          body: ConsistencyCard(
            laps: LapConsistency(),
            result: null,
            loading: true,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('lapConsistency day')))
          .data,
      'Potrzeba co najmniej 3 okrążeń',
    );
    expect(find.text('0 okrążeń'), findsOneWidget);
    expect(
      find.text(
        'Obliczanie powtarzalności wraz z teoretycznym czasem okrążenia…',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a one-session day has one lap-time row, named after it', (
    tester,
  ) async {
    const summary = ConsistencySummary(
      count: 4,
      median: 90.5,
      interquartileRange: 0.25,
      available: true,
    );
    await tester.pumpWidget(
      TelemetryApp(
        home: Scaffold(
          body: ConsistencyCard(
            laps: LapConsistency(
              day: summary,
              runs: const [
                RunLapConsistency(
                  runId: 'r1',
                  runName: 'Session 1',
                  laps: summary,
                ),
              ],
            ),
            result: null,
            loading: true,
          ),
        ),
      ),
    );
    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text('All sessions'), findsNothing);
    expect(find.byKey(const ValueKey('lapConsistency r1')), findsNothing);
    expect(find.textContaining('· spread'), findsOneWidget);
  });

  testWidgets('a one-session day names its row in Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: Scaffold(
          body: ConsistencyCard(
            laps: LapConsistency(
              runs: const [
                RunLapConsistency(
                  runId: 'r1',
                  runName: 'Session 1',
                  laps: ConsistencySummary(),
                ),
              ],
            ),
            result: null,
            loading: true,
          ),
        ),
      ),
    );
    expect(find.text('Sesja 1'), findsOneWidget);
    expect(find.text('Wszystkie sesje'), findsNothing);
  });

  group('where the laps vary', () {
    // The best lap's trace at 10 Hz; where it is drawn does not matter.
    LapPath pathOf(DayTheoreticalBest result) {
      final best = result.bestLap!;
      return LapPath(
        origin: const GeoCoordinate(0, 0),
        segments: [
          [
            for (var t = best.start; t <= best.end; t += 0.1)
              PathPoint(t, t, 0, null),
          ],
        ],
      );
    }

    Future<
      ({DayTheoreticalBest result, SectionProgression sections, LapPath path})
    >
    show(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      bool longerLatest = false,
    }) async {
      final outcome = importDay(longerLatest: longerLatest);
      final analysis = outcome.analysis!;
      final result = dayTheoreticalBest(analysis, outingRuns(outcome.runs));
      expect(result.state, DayTheoreticalBestState.ready);
      final sections = result.sectionProgression([
        for (final named in outcome.runs)
          ProgressionRunInfo(id: named.run.id, name: named.name),
      ]);
      final path = pathOf(result);
      await tester.binding.setSurfaceSize(const Size(412, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? chosen;
      await tester.pumpWidget(
        TelemetryApp(
          locale: locale,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ListView(
                children: [
                  ConsistencyCard(
                    laps: dayLapConsistency(analysis),
                    result: result,
                    sections: sections,
                    path: path,
                    spreadRunId: chosen,
                    onSpreadRun: (id) => setState(() => chosen = id),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (result: result, sections: sections, path: path);
    }

    String textOf(WidgetTester tester, Finder finder) => tester
        .widgetList<Text>(
          find.descendant(of: finder, matching: find.byType(Text)),
        )
        .map((text) => text.data)
        .join(' | ');

    // Each segment's spread in [runId], by segment id; null below 3 laps.
    Map<String, double?> spreadsIn(SectionProgression sections, String runId) =>
        {
          for (final row in sections.segments)
            row.segmentId: row.cells
                .firstWhere((cell) => cell.runId == runId)
                .summary
                .interquartileRange,
        };

    // The map colours each fix by its segment's band in the session shown,
    // grey below 3 laps, and its own colour outside every segment; the list
    // gives every value, most varied first.
    Future<void> expectSession(
      WidgetTester tester,
      DayTheoreticalBest result,
      SectionProgression sections,
      LapPath path,
      String runId,
    ) async {
      final spreads = spreadsIn(sections, runId);
      final context = tester.element(
        find.byKey(const ValueKey('segmentSpread')),
      );
      final colors = segmentSpreadColors(context);
      final grey = Theme.of(context).colorScheme.outline;
      final map = tester.widget<TrackMap>(
        find.byKey(const ValueKey('segmentSpreadMap')),
      );
      final seen = <String>{};
      for (final point in path.segments.single) {
        final index = result.segmentAtTime(
          result.bestLap!,
          point.telemetryTime,
        );
        final expected = switch (index) {
          null => segmentSpreadOutsideColor,
          final i => switch (spreads[result.segments[i].segmentId]) {
            null => grey,
            final spread => colors[segmentSpreadBand(spread)],
          },
        };
        expect(map.pointColor!(point), expected, reason: '$index');
        if (index != null) seen.add(result.segments[index].segmentId);
      }
      expect(seen, hasLength(result.segments.length));
      final order = [...spreads.entries]
        ..sort((a, b) => (b.value ?? -1).compareTo(a.value ?? -1));
      final tops = <double>[];
      for (final MapEntry(key: id, value: spread) in order) {
        final row = find.byKey(ValueKey('segmentSpread $id'));
        expect(
          textOf(tester, row),
          spread == null
              ? contains('Needs at least 3 laps')
              : contains('spread ${spread.toStringAsFixed(3)} s'),
        );
        tops.add(tester.getTopLeft(row).dy);
      }
      expect(tops, orderedEquals([...tops]..sort()));
    }

    testWidgets('shows the latest session first, coloured by its spreads', (
      tester,
    ) async {
      final (:result, :sections, :path) = await show(
        tester,
        longerLatest: true,
      );
      expect(find.text('Where the laps vary'), findsOneWidget);
      final latest = sections.sessions.last;
      expect(latest.run.name, 'Session 2');
      expect(spreadsIn(sections, latest.runId).values, everyElement(isNotNull));
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('segmentSpreadSession')),
            )
            .value,
        latest.runId,
      );
      await expectSession(tester, result, sections, path, latest.runId);
      // Two sessions with different spreads: the colours are not one band.
      final first = spreadsIn(sections, sections.sessions.first.runId);
      expect(first, isNot(spreadsIn(sections, latest.runId)));
    });

    testWidgets('another session shows its own spreads', (tester) async {
      final (:result, :sections, :path) = await show(
        tester,
        longerLatest: true,
      );
      await tester.tap(find.byKey(const ValueKey('segmentSpreadSession')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Session 1').last);
      await tester.pumpAndSettle();
      final first = sections.sessions.first.runId;
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('segmentSpreadSession')),
            )
            .value,
        first,
      );
      await expectSession(tester, result, sections, path, first);
    });

    testWidgets('a session with two laps is grey and says why', (tester) async {
      final (:result, :sections, :path) = await show(tester);
      final latest = sections.sessions.last.runId;
      expect(spreadsIn(sections, latest).values, everyElement(isNull));
      await expectSession(tester, result, sections, path, latest);
      final legend = textOf(
        tester,
        find.byKey(const ValueKey('segmentSpreadLegend')),
      );
      for (final band in [
        'Up to 0.10 s',
        '0.10–0.25 s',
        '0.25–0.50 s',
        '0.50–1.00 s',
        'Over 1.00 s',
        'Needs at least 3 laps',
      ]) {
        expect(legend, contains(band));
      }
    });

    testWidgets('speaks Polish', (tester) async {
      addTearDown(() => Intl.defaultLocale = null);
      await show(tester, locale: const Locale('pl'));
      expect(find.text('Gdzie okrążenia się różnią'), findsOneWidget);
      expect(find.text('Do 0.10 s'), findsOneWidget);
      expect(find.text('Ponad 1.00 s'), findsOneWidget);
      expect(find.text('Where the laps vary'), findsNothing);
    });
  });
}
