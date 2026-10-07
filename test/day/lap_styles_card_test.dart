import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/lap_styles_card.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

DayLapRow _row(int number) => DayLapRow(
  runId: 'run1',
  runName: 'Session 1',
  type: LapSectionType.lap,
  lapNumber: number,
  start: number * 200.0,
  end: number * 200.0 + 100.0 + number,
  sourceRevision: 'a' * 64,
);

const _brake = 'inferredDeceleration|longacc';

LapStyleInput _lap(
  int number, {
  required double brake,
  required double pickup,
  double speed = 80,
  String unit = 'km/h',
}) => LapStyleInput(
  lap: _row(number),
  seconds: 100.0 + number,
  corners: [
    for (var i = 0; i < 4; ++i)
      LapCornerSample(
        cornerId: 'c$i',
        brakeBeforeEntryMeters: brake,
        brakeSource: _brake,
        pickupAfterEntryMeters: pickup,
        pickupSource: 'measuredThrottle|throttle',
        minimumSpeed: speed,
        exitSpeed: speed + 20,
        speedUnit: unit,
        speedSource: 'velocity',
      ),
  ],
);

// Laps 1 to 3 plain (50 m, 30 m), laps 4 to 6 braking 10 m later, lap 7
// braking 12 m earlier and the throttle 15 m later.
DayLapStyles _styles({
  String unit = 'km/h',
  int timed = 9,
  bool unitMissing = false,
  int brakeFigures = 28,
}) {
  final inputs = [
    for (var n = 1; n <= 3; ++n) _lap(n, brake: 50, pickup: 30, unit: unit),
    for (var n = 4; n <= 6; ++n)
      _lap(n, brake: 40, pickup: 30, speed: 86, unit: unit),
    _lap(7, brake: 62, pickup: 45, speed: 74, unit: unit),
  ];
  return DayLapStyles(
    styles: computeLapStyles(inputs),
    inputs: inputs,
    timedLapCount: timed,
    brakeCornerFigures: brakeFigures,
    throttleCornerFigures: 28,
    brakeUnitAssumed: true,
    speedUnitMissing: unitMissing,
  );
}

DayTheoreticalBest _result(DayLapStyles? styles) => DayTheoreticalBest(
  groupId: 'g',
  state: DayTheoreticalBestState.ready,
  lapStyles: styles,
);

Future<void> _pump(
  WidgetTester tester,
  Widget card, {
  Locale? locale,
  bool open = true,
}) async {
  // Tall enough for the card opened in full: the groups, the rules and the
  // notes make it longer than a phone screen.
  await tester.binding.setSurfaceSize(const Size(412, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    TelemetryApp(
      locale: locale,
      home: Scaffold(body: ListView(children: [card])),
    ),
  );
  await tester.pumpAndSettle();
  if (open) {
    await tester.tap(find.byKey(const ValueKey('lapStylesToggle')));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('closed at first: one line, opened with Show', (tester) async {
    await _pump(tester, LapStylesCard(result: _result(_styles())), open: false);
    expect(find.text('Lap styles'), findsOneWidget);
    expect(find.text('Inferred'), findsOneWidget);
    expect(
      find.text(
        'Ranked laps grouped by how they were braked and driven on the '
        'throttle, and the best lap of each group.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('lapStylesBasis')), findsNothing);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lapStylesBasis')), findsOneWidget);
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lapStylesBasis')), findsNothing);
  });

  testWidgets(
    'says how many laps rest on it and which group the best lap is in',
    (tester) async {
      await _pump(tester, LapStylesCard(result: _result(_styles())));
      expect(
        find.text(
          'Laps grouped: 7 of 9 timed (out laps, in laps, excluded laps and '
          'laps with issues are left out). Corners compared: 4.',
        ),
        findsOneWidget,
      );
      // Lap 1 (1:41.000) is the day's best, and plain.
      expect(
        find.text(
          'The day\'s best lap, Session 1 · LAP 1 (1:41.000), is in the '
          '“Typical” group.',
        ),
        findsOneWidget,
      );
      expect(find.text('Typical · 3 laps'), findsOneWidget);
      expect(find.text('Late braking · 3 laps'), findsOneWidget);
      expect(find.text('Conservative · 1 lap'), findsOneWidget);
      expect(find.textContaining('observations'), findsNothing);
      expect(
        find.textContaining(
          'nothing here shows that a style made a lap faster',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Few laps rest on each group'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a group shows its best lap, its gap, and how it sat against the '
      'typical', (tester) async {
    await _pump(tester, LapStylesCard(result: _result(_styles())));
    final late = find.byKey(const ValueKey('lapStylesGroup lateBraking'));
    expect(
      find.descendant(
        of: late,
        matching: find.text(
          'Best: Session 1 · LAP 4 · 1:44.000 · +3.000\u00a0s against the day\'s best '
          'lap',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(late);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Session 1 · LAP 4 against the day\'s typical lap (the median of 7 '
        'grouped laps)',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Braking point: earlier at 0, later at 4 of 4 corners; median 10 m later',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Throttle pickup: earlier at 0, later at 0 of 4 corners; median about '
        'typical',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Minimum speed: faster at 4, slower at 0 of 4 corners; median 6.0\u00a0km/h '
        'faster',
      ),
      findsOneWidget,
    );
    // Three laps: a typical time; the lone conservative lap has none.
    expect(
      find.byKey(const ValueKey('lapStylesGroupFigures lateBraking')),
      findsOneWidget,
    );
    expect(
      find.text(
        'typical lap 1:45.000 · 3 of 3 in the quicker half of the day\'s laps',
      ),
      findsNothing,
      reason: 'laps 4 to 6 are slower than the first three',
    );
  });

  testWidgets('a lap opens from its group', (tester) async {
    final opened = <DayLapRow>[];
    await _pump(
      tester,
      LapStylesCard(result: _result(_styles()), onOpenLap: opened.add),
    );
    await tester.tap(find.byKey(const ValueKey('lapStylesGroup lateBraking')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('lapStylesLap Session 1 · LAP 5')),
    );
    expect(opened.single.lapNumber, 5);
  });

  testWidgets('a declared unit is shown as declared, never converted', (
    tester,
  ) async {
    await _pump(tester, LapStylesCard(result: _result(_styles(unit: 'mph'))));
    await tester.tap(find.byKey(const ValueKey('lapStylesGroup lateBraking')));
    await tester.pumpAndSettle();
    expect(find.textContaining('median 6.0\u00a0mph faster'), findsNWidgets(2));
    expect(find.textContaining('\u00a0km/h'), findsNothing);
  });

  testWidgets(
    'says when braking, units or a speed unit are assumed or missing',
    (tester) async {
      await _pump(
        tester,
        LapStylesCard(result: _result(_styles(unitMissing: true))),
      );
      expect(
        find.textContaining('read from the longitudinal acceleration'),
        findsOneWidget,
      );
      expect(find.textContaining('never from the brake pedal'), findsOneWidget);
      expect(
        find.text(
          'The acceleration or speed used for the braking points declares no unit and is read as g or km/h.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'A speed in this day declares no unit, so its speeds are shown '
          'without one.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Earlier or later means more than 5 m'),
        findsOneWidget,
      );
    },
  );

  testWidgets('without a braking point the card says why', (tester) async {
    await _pump(
      tester,
      LapStylesCard(result: _result(_styles(brakeFigures: 0))),
    );
    expect(
      find.textContaining('No braking point could be read'),
      findsOneWidget,
    );
  });

  testWidgets('too few laps or corners are not grouped, and the card says so', (
    tester,
  ) async {
    final inputs = [
      for (var n = 1; n <= 2; ++n) _lap(n, brake: 50, pickup: 30),
    ];
    await _pump(
      tester,
      LapStylesCard(
        result: _result(
          DayLapStyles(
            styles: computeLapStyles(inputs),
            inputs: inputs,
            timedLapCount: 3,
          ),
        ),
      ),
    );
    expect(
      find.text('Lap styles need at least 3 ranked laps.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('lapStylesBestLine')), findsNothing);
    final plain = [
      for (var n = 1; n <= 4; ++n)
        LapStyleInput(
          lap: _row(n),
          seconds: 100.0 + n,
          corners: const [
            LapCornerSample(
              cornerId: 'c0',
              brakeBeforeEntryMeters: 50,
              brakeSource: _brake,
            ),
          ],
        ),
    ];
    await _pump(
      tester,
      LapStylesCard(
        key: const ValueKey('few corners'),
        result: _result(
          DayLapStyles(styles: computeLapStyles(plain), inputs: plain),
        ),
      ),
    );
    expect(
      find.textContaining('Fewer than 3 corners have a braking or throttle'),
      findsOneWidget,
    );
  });

  testWidgets('while it is worked out, and without a result', (tester) async {
    await _pump(tester, const LapStylesCard(result: null, loading: true));
    expect(find.byKey(const ValueKey('lapStylesWorking')), findsOneWidget);
    await _pump(
      tester,
      LapStylesCard(
        key: const ValueKey('unavailable'),
        result: DayTheoreticalBest(
          groupId: 'g',
          state: DayTheoreticalBestState.unavailable,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('lapStylesUnavailable')), findsOneWidget);
  });

  testWidgets('speaks Polish', (tester) async {
    await _pump(
      tester,
      LapStylesCard(result: _result(_styles())),
      locale: const Locale('pl'),
    );
    expect(find.text('Style okrążeń'), findsOneWidget);
    expect(find.text('Wnioskowane'), findsOneWidget);
    expect(find.text('Ukryj'), findsOneWidget);
    expect(
      find.textContaining('Pogrupowane okrążenia: 7 z 9 mierzonych'),
      findsOneWidget,
    );
    expect(
      find.textContaining('okrążenia wyjazdowe, zjazdowe, wykluczone'),
      findsOneWidget,
    );
    expect(find.textContaining('Najlepsze okrążenie dnia'), findsOneWidget);
    expect(
      find.textContaining('należy do grupy „Jazda typowa”'),
      findsOneWidget,
    );
    expect(find.text('Późne hamowanie · 3 okrążenia'), findsOneWidget);
    expect(find.text('Ostrożna jazda · 1 okrążenie'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lapStylesGroup lateBraking')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Punkt hamowania: wcześniej w 0, później w 4 z 4 zakrętów; mediana: 10 m później',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('km/h szybciej'), findsNWidgets(2));
    expect(find.textContaining('nigdy z pedału hamulca'), findsOneWidget);
    // Decimal point, not comma.
    expect(find.textContaining('6.0\u00a0km/h'), findsNWidgets(2));
    expect(find.textContaining('6,0'), findsNothing);
  });
}
