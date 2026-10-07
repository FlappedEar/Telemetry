// The braking technique in a corner's details and the day's summary
// (FET-219), in English and Polish, on a wide screen and on a small phone
// with large text. Synthetic recordings only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/corner_details.dart';
import 'package:telemetry/day/theoretical_best_card.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

/// A lap that braked from the G channel: hit, peak, trail, release and
/// brake-to-throttle known; the brake pedal an OBD one at [brakeRate] Hz.
BrakingTechniqueLap _lap(double hit, {double brakeRate = 2.1}) =>
    BrakingTechniqueLap()
      ..source = brakingTechniqueFromG
      ..channel = 'longacc-calc'
      ..declaredUnit = 'g'
      ..rateHz = 10
      ..onsetTime = 10
      ..peakTime = 10.5
      ..endTime = 12
      ..peakG = 0.54
      ..zoneSeconds = 2
      ..zoneMeters = 74
      ..peakAfterOnsetMeters = 18
      ..peakFraction = 0.25
      ..hitGPerSecond = hit
      ..releaseGPerSecond = 0.32
      ..trailSeconds = 1.5
      ..trailMeters = 24
      ..lateralChannel = 'latacc-calc'
      ..lateralRateHz = 10
      ..lateralUnitAssumed = true
      ..brakeToThrottleSeconds = 0.84
      ..throttleChannel = 'accelerator_pos-obd'
      ..throttleRateHz = 2.1
      ..brakeChannel = 'brake_pos-obd'
      ..brakeRateHz = brakeRate
      ..pedalReason = brakingTechniqueBrakeTooSlow;

const _a = DayLapReference(
  runId: 'run1',
  sourceRevision: 'r',
  type: LapSectionType.lap,
  startTime: 0,
  endTime: 100,
);
const _b = DayLapReference(
  runId: 'run1',
  sourceRevision: 'r',
  type: LapSectionType.lap,
  startTime: 100,
  endTime: 200,
);
const _c = DayLapReference(
  runId: 'run1',
  sourceRevision: 'r',
  type: LapSectionType.lap,
  startTime: 200,
  endTime: 300,
);

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('braking'));
  tearDown(() => deleteTemporaryDirectory(directory));

  // Three laps braking hard into the second corner. The VBO has a brake and a
  // throttle at 10 Hz but no G channel: the deceleration comes from speed.
  DayTheoreticalBest day() {
    final path = '${directory.path}/pedals.vbo';
    File(path).writeAsStringSync(
      rectangleVbo([
        rectangleBrakingLap(250, 12),
        rectangleBrakingLap(260, 12.5),
        rectangleBrakingLap(240, 11.5),
      ], pedals: true),
    );
    final outcome = runDayImport((paths: [path], includeSubfolders: false));
    return dayTheoreticalBest(outcome.analysis!, outingRuns(outcome.runs));
  }

  String rowText(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
          matchRoot: true,
        ),
      )
      .map((text) => text.data)
      .join(' | ');

  // The app keeps one navigator (appNavigatorKey), so its first page would
  // outlive a new app; clear it before showing another.
  Future<void> show(WidgetTester tester, Locale locale, Widget home) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(TelemetryApp(locale: locale, home: home));
    await tester.pumpAndSettle();
  }

  Future<void> showCard(
    WidgetTester tester,
    DayTheoreticalBest result,
    Locale locale, {
    double textScale = 1,
  }) async {
    await show(
      tester,
      locale,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: ListView(children: [TheoreticalBestCard(result: result)]),
          ),
        ),
      ),
    );
  }

  // Opens Corner 2's details from its row of the losses; the tap must land
  // on the row, not beside it.
  Future<void> openCorner(WidgetTester tester) async {
    final row = find.byKey(const ValueKey('lossRow Corner 2'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(row.hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(CornerDetails), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('brakingTechniqueNote')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a corner shows its braking technique from speed, in English and Polish',
    (tester) async {
      final result = day();
      final corner = result.corners.firstWhere((c) => c.name == 'Corner 2');
      final technique = corner.brakingTechnique;
      expect(technique.source, brakingTechniqueFromSpeed);
      // The synthetic VBO's speed column declares no unit: read as km/h.
      expect(technique.unitAssumed, isTrue);
      expect(technique.unavailableReason, isEmpty);
      expect(technique.hit.median, isNotNull);
      expect(technique.brakeToThrottle.median, isNotNull);
      // A hit from speed as quick as its smoothing shows is a lower bound.
      String bound(String text, bool lower, String word) =>
          lower ? '$word $text' : text;
      final hitValue = '${fixed(technique.hit.median!, 2)}\u00a0g/s';
      final hit = bound(hitValue, technique.hit.atLeast, 'at least');
      final hitPl = bound(hitValue, technique.hit.atLeast, 'co najmniej');
      final peak = '${fixed(technique.peak.median!, 2)}\u00a0g';
      final release = bound(
        '${fixed(technique.release.median!, 2)}\u00a0g/s',
        technique.release.atLeast,
        'at least',
      );
      final throttle = '${fixed(technique.brakeToThrottle.median!, 2)}\u00a0s';

      await tester.binding.setSurfaceSize(const Size(412, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await showCard(tester, result, const Locale('en'));
      // The day's summary, over the corners braked into.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('brakingTechniqueDay')))
            .data,
        allOf(
          startsWith(
            'Typical over 1 corner, from speed (no unit recorded: read as '
            'km/h): initial hit $hit',
          ),
          contains('release $release'),
          contains('brake to throttle $throttle'),
          isNot(contains('trail')),
        ),
      );
      await openCorner(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('brakingTechniqueTitle')))
            .data,
        'Braking technique',
      );
      expect(
        rowText(tester, 'brakingTechniqueSource'),
        'From speed (10.0 Hz, no unit recorded: read as km/h), its change '
        'smoothed over a 0.5 s window, on this day\'s ranked laps: no '
        'longitudinal G channel. Not comparable with figures from a G '
        'channel. Brakes on 3 of 3 laps.',
      );
      expect(
        rowText(tester, 'brakingTechniqueHit'),
        allOf(
          startsWith('Initial hit | This lap: '),
          endsWith('typical $hit (3 laps)'),
        ),
      );
      expect(
        rowText(tester, 'brakingTechniquePeak'),
        allOf(
          contains('typical $peak (3 laps)'),
          contains(' s of braking. Typically in the '),
          contains(' third of the braking, by time.'),
        ),
      );
      expect(
        rowText(tester, 'brakingTechniqueTrail'),
        'Trail braking · inferred | This lap: not known, no lateral G channel '
        '· typical: not known, no lateral G channel | Braking while the '
        'lateral G is at least 0.3 g. Inferred: there is no steering channel.',
      );
      expect(
        rowText(tester, 'brakingTechniqueRelease'),
        contains('typical $release (3 laps)'),
      );
      expect(
        rowText(tester, 'brakingTechniqueThrottle'),
        allOf(
          contains('typical $throttle (3 laps)'),
          contains(
            'From the end of braking to the throttle pickup, looked for '
            'until braking starts again and at most 4 s. The throttle is '
            'recorded at 10.0 Hz, so the pickup is placed to about 0.1 s.',
          ),
        ),
      );
      // The synthetic pedal is a 10 Hz one: its own ramps are read.
      expect(
        rowText(tester, 'brakingTechniquePedal'),
        contains('%/s (3 laps)'),
      );
      expect(find.textContaining('too slow'), findsNothing);
      expect(tester.takeException(), isNull);

      // In Polish.
      await showCard(tester, result, const Locale('pl'));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('brakingTechniqueDay')))
            .data,
        startsWith(
          'Typowo w 1 zakręcie, z prędkości (bez zapisanej jednostki: '
          'odczytane jako km/h): narastanie $hitPl',
        ),
      );
      await openCorner(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('brakingTechniqueTitle')))
            .data,
        'Technika hamowania',
      );
      expect(
        rowText(tester, 'brakingTechniqueHit'),
        allOf(
          startsWith('Narastanie hamowania | To okrążenie: '),
          endsWith('typowo $hitPl (3 okrążenia)'),
        ),
      );
      expect(
        rowText(tester, 'brakingTechniqueTrail'),
        contains('To okrążenie: nieznane, brak kanału przeciążenia bocznego'),
      );
      expect(
        rowText(tester, 'brakingTechniqueSource'),
        contains('jej zmiana wygładzona w oknie 0.5 s'),
      );
      expect(find.text('Braking technique'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an OBD brake pedal says it is too slow, with its rate, and a '
      'slow throttle is shown to 0.1 s', (tester) async {
    final technique = summarizeBrakingTechnique([
      (_a, _lap(0.7)),
      (_b, _lap(0.8)),
      (_c, _lap(0.6)),
    ]);
    for (final (locale, source, pedal, hit, throttle, trail, peak) in [
      (
        'en',
        'From the longitudinal G channel (10.0 Hz) on this day\'s ranked '
            'laps. Brakes on 3 of 3 laps.',
        'Brake pedal: application and release | Not known: brake channel too '
            'slow (2.1 Hz). It shows when braking happens, not how the pedal '
            'moves, so the hit and release above come from the deceleration.',
        'Initial hit | This lap: 0.80\u00a0g/s · typical 0.70\u00a0g/s (3 laps)',
        'Brake to throttle | This lap: about 0.8\u00a0s · typical about '
            '0.8\u00a0s (3 laps)',
        'The lateral G has no unit recorded: read as g.',
        'Peak 0.5 s into 2.0 s of braking. Typically in the first third of '
            'the braking, by time.',
      ),
      (
        'pl',
        'Z kanału przyspieszenia wzdłużnego (10.0 Hz), na sklasyfikowanych '
            'okrążeniach tego dnia. Hamowanie na 3 z 3 okrążeń.',
        'Pedał hamulca: wciskanie i puszczanie | Nieznane: kanał hamulca jest '
            'zbyt wolny (2.1 Hz). Pokazuje, kiedy trwa hamowanie, ale nie jak '
            'porusza się pedał, dlatego narastanie i odpuszczanie powyżej '
            'pochodzą z opóźnienia.',
        'Narastanie hamowania | To okrążenie: 0.80\u00a0g/s · typowo '
            '0.70\u00a0g/s (3 okrążenia)',
        'Od hamulca do gazu | To okrążenie: około 0.8\u00a0s · typowo około '
            '0.8\u00a0s (3 okrążenia)',
        'Przeciążenie boczne nie ma zapisanej jednostki: odczytane jako g.',
        'Szczyt 0.5 s od początku hamowania trwającego 2.0 s. Zwykle na '
            'początku (1/3) hamowania, wg czasu.',
      ),
    ]) {
      await show(
        tester,
        Locale(locale),
        Scaffold(
          body: SingleChildScrollView(
            child: BrakingTechniqueSection(technique: technique, lap: _b),
          ),
        ),
      );
      expect(rowText(tester, 'brakingTechniqueSource'), source);
      expect(rowText(tester, 'brakingTechniquePedal'), pedal);
      expect(rowText(tester, 'brakingTechniqueHit'), hit);
      expect(rowText(tester, 'brakingTechniqueThrottle'), startsWith(throttle));
      expect(rowText(tester, 'brakingTechniqueTrail'), endsWith(trail));
      expect(rowText(tester, 'brakingTechniquePeak'), endsWith(peak));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('an OBD brake column is never read for its ramps', (
    tester,
  ) async {
    // Written at 10 Hz in a VBO, but resampled from a rate the file does
    // not tell.
    BrakingTechniqueLap resampled(double hit) => _lap(hit, brakeRate: 10)
      ..brakeChannel = 'brake_pos-obd'
      ..pedalReason = brakingTechniqueBrakeResampled;
    final technique = summarizeBrakingTechnique([
      (_a, resampled(0.7)),
      (_b, resampled(0.8)),
      (_c, resampled(0.6)),
    ]);
    for (final (locale, expected) in [
      (
        'en',
        'This lap: not known, the brake is an OBD channel resampled to the '
            'recording\'s rows, its own rate not known',
      ),
      (
        'pl',
        'To okrążenie: nieznane, hamulec to kanał OBD przepróbkowany do '
            'wierszy zapisu, jego własna częstotliwość nie jest znana',
      ),
    ]) {
      await show(
        tester,
        Locale(locale),
        Scaffold(
          body: SingleChildScrollView(
            child: BrakingTechniqueSection(technique: technique, lap: _b),
          ),
        ),
      );
      expect(rowText(tester, 'brakingTechniquePedal'), contains(expected));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a corner without braking says why, and so does a lap', (
    tester,
  ) async {
    final none = BrakingTechniqueLap()
      ..source = brakingTechniqueFromG
      ..rateHz = 10
      ..unavailableReason = brakingTechniqueNoBraking;
    final slow = BrakingTechniqueLap()
      ..source = brakingTechniqueFromG
      ..rateHz = 4.0
      ..unavailableReason = brakingTechniqueDecelerationTooSlow;
    final cases = [
      (
        summarizeBrakingTechnique([(_a, none), (_b, none), (_c, none)]),
        'Not known: no braking here',
        'Nieznane: brak hamowania w tym miejscu',
      ),
      (
        summarizeBrakingTechnique([(_a, slow), (_b, slow), (_c, slow)]),
        'Not known: channel too slow (4.0 Hz)',
        'Nieznane: kanał zbyt wolny (4.0 Hz)',
      ),
    ];
    for (final (technique, english, polish) in cases) {
      for (final (locale, expected) in [('en', english), ('pl', polish)]) {
        await show(
          tester,
          Locale(locale),
          Scaffold(
            body: BrakingTechniqueSection(technique: technique, lap: _a),
          ),
        );
        expect(rowText(tester, 'brakingTechniqueReason'), expected);
        expect(find.byKey(const ValueKey('brakingTechniqueHit')), findsNothing);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the braking technique fits a small phone with large text, in Polish',
    (tester) async {
      final result = day();
      // A small phone, text twice the size.
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await showCard(tester, result, const Locale('pl'), textScale: 2);
      await openCorner(tester);
      for (final key in [
        'brakingTechniqueHit',
        'brakingTechniquePeak',
        'brakingTechniqueTrail',
        'brakingTechniqueRelease',
        'brakingTechniqueThrottle',
        'brakingTechniquePedal',
        'brakingTechniqueNote',
      ]) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      // The sheet closes from the strip of page above it.
      await tester.tapAt(const Offset(160, 4));
      await tester.pumpAndSettle();
      expect(find.byType(CornerDetails), findsNothing);
    },
  );
}
