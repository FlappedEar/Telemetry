import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/focus_areas_card.dart';
import 'package:telemetry/day/time_losses_card.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

void main() {
  final english = lookupAppLocalizations(const Locale('en'));
  final polish = lookupAppLocalizations(const Locale('pl'));

  // One area of every kind, each on its own segment.
  List<FocusArea> everyKind({String speedUnit = 'km/h'}) {
    CornerLapObservation corner(int lap, double braking, double speed) =>
        CornerLapObservation(lapReference: 'lap $lap')
          ..brakingPointMeters = braking
          ..brakingProvenance = 'measured'
          ..minimumSpeed = speed;
    return selectFocusAreas(
      FocusInputs(
        referenceLap: 'lap 0',
        referenceLabel: 'Session 1 · LAP 2',
        comparedLapCount: 5,
        speedUnit: speedUnit,
        gaps: [
          const FocusSectorGap(
            segmentId: 's1',
            name: 'Straight 1',
            gapSeconds: 0.2,
            bestLap: 'lap 0',
            bestLapLabel: 'Session 1 · LAP 2',
            sourceLap: 'lap 3',
            sourceLapLabel: 'Session 2 · LAP 1',
          ),
        ],
        losses: [
          for (var lap = 1; lap <= 4; ++lap)
            FocusLoss(
              segmentId: 's2',
              name: 'Corner 1',
              lossSeconds: 0.1 * lap,
              lap: 'lap $lap',
            ),
        ],
        corners: [
          FocusCorner(
            segmentId: 's3',
            name: 'Corners 2–3',
            observations: [
              for (var lap = 1; lap <= 5; ++lap) corner(lap, 40.0 * lap, 60),
            ],
          ),
          FocusCorner(
            segmentId: 's4',
            name: 'Hairpin',
            observations: [
              for (var lap = 1; lap <= 5; ++lap)
                corner(lap, 100, 40.0 + lap * 5),
            ],
          ),
        ],
      ),
      maximum: 4,
    );
  }

  test('focus areas keep their English and speak Polish', () {
    for (final unit in ['km/h', '']) {
      final areas = everyKind(speedUnit: unit);
      expect(areas.map((area) => area.kind).toSet(), FocusAreaKind.values);
      for (final area in areas) {
        // The same text, with a no-break space before each unit.
        expect(
          english.focusAreaObservation(area).replaceAll('\u00a0', ' '),
          area.observation,
        );
        expect(
          english.focusAreaHypothesis(area).replaceAll('\u00a0', ' '),
          area.hypothesis,
        );
        expect(polish.focusAreaObservation(area), isNot(area.observation));
        expect(polish.focusAreaHypothesis(area), isNot(area.hypothesis));
      }
      final byKind = {for (final area in areas) area.kind: area};
      expect(
        polish.focusAreaObservation(byKind[FocusAreaKind.sectorGap]!),
        'Twoje najlepsze okrążenie (Sesja 1 · OKR. 2) było o 0.200\u00a0s '
        'wolniejsze w segmencie Prosta 1 niż Sesja 2 · OKR. 1, najszybsze '
        'zarejestrowane tam.',
      );
      expect(
        polish.focusAreaHypothesis(byKind[FocusAreaKind.repeatedLoss]!),
        contains('z Sesja 1 · OKR. 2 w segmencie Zakręt 1'),
      );
      expect(
        polish.focusAreaObservation(byKind[FocusAreaKind.brakingSpread]!),
        startsWith('Punkt hamowania w segmencie Zakręty 2–3 zmienia się o'),
      );
      final speed = polish.focusAreaObservation(
        byKind[FocusAreaKind.minimumSpeedSpread]!,
      );
      expect(speed, startsWith('Prędkość minimalna w segmencie Hairpin'));
      expect(speed.contains('km/h'), unit.isNotEmpty);
      expect(
        speed.endsWith('Prędkości są w jednostkach z nagrania.'),
        unit.isEmpty,
      );
    }
  });

  test('an unknown text is shown as written', () {
    const area = FocusArea(
      kind: FocusAreaKind.brakingSpread,
      segmentId: 's',
      name: 'Corner 1',
      observation: 'Something new.',
      hypothesis: 'Something else.',
      metric: '',
      value: 0,
      unit: 'm',
      sampleCount: 3,
      lap: null,
      against: null,
      score: 0,
    );
    expect(polish.focusAreaObservation(area), 'Something new.');
    expect(polish.focusAreaHypothesis(area), 'Something else.');
    expect(polish.timeLossSegment('Corner 4'), 'Zakręt 4');
    expect(polish.timeLossSegment('Straight 2'), 'Prosta 2');
    expect(polish.timeLossSegment('Hairpin'), 'Hairpin');
    expect(polish.timeLossLapLabel('Session 3 · LAP 2'), 'Sesja 3 · OKR. 2');
  });

  group('in Polish', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('l10n_tl'));
    tearDown(() => directory.deleteSync(recursive: true));

    // Session 1 drives four laps, session 2 two, each slow somewhere else.
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

    Finder summary() => find
        .descendant(
          of: find.byKey(const ValueKey('dayResultsSummary')),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<DayResultsController> open(WidgetTester tester) async {
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
      return controller;
    }

    Future<void> reveal(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(target, 200, scrollable: summary());
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    testWidgets('the time-loss card speaks Polish', (tester) async {
      await open(tester);
      final summaryText = find.byKey(const ValueKey('timeLossSummary'));
      await reveal(tester, summaryText);
      expect(find.text('Straty czasu'), findsOneWidget);
      expect(find.text('Time losses'), findsNothing);
      expect(find.text('Najlepsze każdej sesji'), findsOneWidget);
      final text = tester.widget<Text>(summaryText).data!;
      expect(text, startsWith('Względem: Sesja '));
      expect(text, contains('OKR. '));
      expect(text, contains('1 okrążenie porównane'));
      await tester.tap(find.byKey(const ValueKey('timeLoss 0')));
      await tester.pumpAndSettle();
      expect(find.byType(TimeLossPage), findsOneWidget);
      expect(find.text('To okrążenie'), findsOneWidget);
      expect(find.text('Najlepsze okrążenie'), findsOneWidget);
      expect(find.text('Różnica'), findsOneWidget);
      expect(find.textContaining('względem najlepszego okrążenia'), findsOne);
      expect(find.textContaining('against the best lap'), findsNothing);
    });

    testWidgets('the focus-area card speaks Polish', (tester) async {
      final controller = await open(tester);
      expect(controller.focusAreas, isNotEmpty);
      final first = find.byKey(const ValueKey('focusArea 0'));
      await reveal(tester, first);
      expect(find.text('Co sprawdzić dalej'), findsOneWidget);
      expect(find.text('Where to look next'), findsNothing);
      final area = controller.focusAreas.first;
      expect(
        find.descendant(
          of: first,
          matching: find.text(
            'Zmierzono: ${polish.focusAreaObservation(area)}',
          ),
        ),
        findsOneWidget,
      );
      expect(polish.focusAreaObservation(area), isNot(area.observation));
      expect(find.textContaining('Hipoteza: '), findsWidgets);
      expect(find.textContaining('Observed: '), findsNothing);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.byType(FocusAreaPage), findsOneWidget);
      expect(
        find.textContaining('Zmierzone tylko na tych okrążeniach'),
        findsOneWidget,
      );
      expect(find.textContaining('A · Sesja '), findsOneWidget);
    });
  });
}
