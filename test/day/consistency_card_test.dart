import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/consistency_card.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('consistency'));
  tearDown(() => directory.deleteSync(recursive: true));

  // Session 1 drives four laps, session 2 two.
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
}
