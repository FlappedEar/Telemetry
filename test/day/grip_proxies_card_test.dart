import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/grip_proxies_card.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

DayLapRow _lap(String runId, String runName, int number) => DayLapRow(
  runId: runId,
  runName: runName,
  type: LapSectionType.lap,
  lapNumber: number,
  start: number * 100.0,
  end: number * 100.0 + 90,
  sourceRevision: 'a' * 64,
);

const _g = GripSource(channel: 'latacc-calc', unit: 'g');
const _assumed = GripSource(channel: 'longacc', unit: 'g', unitAssumed: true);
const _fromSpeed = GripSource(channel: 'velocity', unit: 'g', fromSpeed: true);

GripFigure _figure(
  double typical,
  double peak, {
  GripSource source = _g,
  DayLapRow? lap,
  int laps = 4,
  int leftOut = 0,
}) => GripFigure(
  typical: typical,
  peak: peak,
  peakLap: lap,
  lapCount: laps,
  leftOut: leftOut,
  source: source,
);

DayTheoreticalBest _result(DayGripProxies grip) => DayTheoreticalBest(
  groupId: 'g',
  state: DayTheoreticalBestState.ready,
  grip: grip,
);

DayGripProxies _grip() => DayGripProxies(
  sessions: [
    GripSession(
      runId: 'run1',
      runName: 'Session 1',
      lapCount: 2,
      bands: [
        GripBand(
          lower: null,
          upper: 80,
          // The speed declares no unit: km/h's edges, assumed.
          speedUnit: '',
          speedUnitAssumed: true,
          lateral: const GripFigure(
            peak: 0.71,
            lapCount: 2,
            source: _g,
            typicalReason: gripTooFewLaps,
          ),
          braking: const GripFigure(
            peak: 0.58,
            lapCount: 2,
            source: _fromSpeed,
            typicalReason: gripTooFewLaps,
          ),
          accelerating: const GripFigure(
            peak: 0.29,
            lapCount: 2,
            source: _fromSpeed,
            typicalReason: gripTooFewLaps,
          ),
        ),
      ],
      balance: const GripFigure(reason: gripDeviceAxesOnly),
    ),
    GripSession(
      runId: 'run2',
      runName: 'Session 2',
      lapCount: 4,
      bands: [
        GripBand(
          lower: null,
          upper: 80,
          speedUnit: 'km/h',
          lateral: _figure(0.99, 1.03),
          braking: _figure(0.83, 0.87, source: _assumed),
          accelerating: _figure(0.30, 0.39, source: _assumed),
        ),
        GripBand(
          lower: 80,
          upper: 120,
          speedUnit: 'km/h',
          lateral: _figure(0.88, 0.97),
          braking: _figure(0.83, 0.87, source: _assumed),
          accelerating: _figure(0.27, 0.30, source: _assumed),
        ),
        const GripBand(
          lower: 120,
          upper: null,
          speedUnit: 'km/h',
          lateral: GripFigure(reason: gripTooFewSamples),
          braking: GripFigure(reason: gripTooFewSamples),
          accelerating: GripFigure(reason: gripTooFewSamples),
        ),
      ],
      balance: const GripFigure(reason: gripDeviceAxesOnly),
    ),
  ],
  corners: [
    GripCorner(
      segmentIndex: 0,
      segmentId: 'c1',
      name: 'Corner 1',
      lateral: _figure(
        0.72,
        1.03,
        lap: _lap('run2', 'Session 2', 2),
        laps: 6,
        leftOut: 1,
      ),
      braking: _figure(
        0.55,
        0.71,
        source: _assumed,
        lap: _lap('run2', 'Session 2', 3),
      ),
      traction: _figure(
        -0.04,
        0.17,
        source: _assumed,
        lap: _lap('run1', 'Session 1', 1),
      ),
      balance: const GripFigure(
        peak: 1.1,
        typical: 0.97,
        lapCount: 5,
        source: GripSource(channel: 'yaw_rate', unit: 'deg/s'),
      ),
    ),
    const GripCorner(
      segmentIndex: 2,
      segmentId: 'c2',
      name: 'Corner 2',
      lateral: GripFigure(reason: gripNotTimed),
      braking: GripFigure(reason: gripNotTimed),
      traction: GripFigure(reason: gripNotTimed),
      balance: GripFigure(reason: gripNoYawChannel),
    ),
    GripCorner(
      segmentIndex: 4,
      segmentId: 'c3',
      name: 'Corner 3',
      lateral: GripFigure(
        peak: 0.61,
        peakLap: _lap('run1', 'Session 1', 2),
        lapCount: 2,
        unmeasured: 3,
        source: _g,
        typicalReason: gripTooFewLaps,
      ),
      braking: _figure(
        0.52,
        0.6,
        source: const GripSource(
          channel: 'velocity',
          unit: 'g',
          fromSpeed: true,
          unitAssumed: true,
        ),
        lap: _lap('run1', 'Session 1', 1),
      ),
      traction: const GripFigure(reason: gripAllZero),
      balance: const GripFigure(
        peak: 1.2,
        typical: 1.05,
        lapCount: 4,
        unmeasured: 1,
        source: GripSource(
          channel: 'yaw_rate',
          unit: 'deg/s',
          unitAssumed: true,
        ),
      ),
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget card, {
  Locale? locale,
  bool open = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(412, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    TelemetryApp(
      locale: locale,
      home: Scaffold(body: ListView(children: [card])),
    ),
  );
  await tester.pumpAndSettle();
  if (open) {
    await tester.tap(find.byKey(const ValueKey('gripToggle')));
    await tester.pumpAndSettle();
  }
}

String _text(WidgetTester tester, Finder finder) => [
  for (final widget in tester.widgetList<Text>(
    find.descendant(of: finder, matching: find.byType(Text)),
  ))
    widget.data ?? '',
].join('|');

void main() {
  testWidgets('closed at first: one line, opened with Show', (tester) async {
    await _pump(tester, GripProxiesCard(result: _result(_grip())), open: false);
    expect(find.text('Grip and balance'), findsOneWidget);
    expect(find.text('Inferred'), findsOneWidget);
    expect(
      find.text(
        'How hard the car was worked cornering, braking and accelerating, per '
        'session and per corner.',
      ),
      findsOneWidget,
    );
    expect(find.text('By session, at comparable speed'), findsNothing);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('By session, at comparable speed'), findsOneWidget);
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text('By session, at comparable speed'), findsNothing);
  });

  testWidgets('while it is worked out, and without a result', (tester) async {
    await _pump(tester, const GripProxiesCard(result: null, loading: true));
    expect(find.text('Grip and balance'), findsOneWidget);
    expect(find.text('Inferred'), findsOneWidget);
    expect(find.byKey(const ValueKey('gripWorking')), findsOneWidget);
    await _pump(
      tester,
      GripProxiesCard(
        // A new card: the first one's state is not kept.
        key: const ValueKey('unavailable'),
        result: DayTheoreticalBest(
          groupId: 'g',
          state: DayTheoreticalBestState.unavailable,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('gripUnavailable')), findsOneWidget);
    expect(find.textContaining('Not known until'), findsOneWidget);
  });

  testWidgets(
    'a session\'s speed bands: typical and peak, units and what is not known',
    (tester) async {
      await _pump(tester, GripProxiesCard(result: _result(_grip())));
      // The latest session first.
      expect(find.text('Session 2 · 4 ranked laps'), findsOneWidget);
      expect(find.text('below 80\u00a0km/h'), findsOneWidget);
      expect(find.text('80–120\u00a0km/h'), findsOneWidget);
      expect(find.text('120\u00a0km/h and above'), findsOneWidget);
      expect(
        _text(tester, find.byKey(const ValueKey('gripLateral 0'))),
        '0.99|peak 1.03',
      );
      expect(
        _text(tester, find.byKey(const ValueKey('gripBraking 1'))),
        '0.83|peak 0.87',
      );
      expect(
        _text(tester, find.byKey(const ValueKey('gripLateral 2'))),
        '—',
        reason: 'never zero',
      );
      // A declared g is g; an undeclared one is said to be assumed.
      expect(find.text('Cornering: in g.'), findsOneWidget);
      expect(
        find.text(
          'Braking and accelerating: the recording does not declare a unit; g is assumed.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Cornering, Braking, Accelerating · 120\u00a0km/h and above: not known: '
          'not enough samples on any lap.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Balance: not known: the recording\'s gyro measures the logger\'s own axes, '
          'not the car\'s yaw.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Typical values need'), findsNothing);

      // Session 1: two laps, so peaks only; braking from speed.
      await tester.tap(find.byKey(const ValueKey('gripSession')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Session 1 · 2 ranked laps').last);
      await tester.pumpAndSettle();
      expect(
        _text(tester, find.byKey(const ValueKey('gripLateral 0'))),
        '—|peak 0.71',
      );
      expect(find.text('below 80 (km/h assumed)'), findsOneWidget);
      expect(
        find.text(
          'Braking and accelerating: from the change in speed (no longitudinal acceleration '
          'recorded), in g.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Typical values need at least 3 laps measured the same way; where there are fewer '
          'only the peak is shown.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('each corner: a summary, and its figures when opened', (
    tester,
  ) async {
    await _pump(tester, GripProxiesCard(result: _result(_grip())));
    final corner = find.byKey(const ValueKey('gripCorner Corner 1'));
    expect(
      find.descendant(
        of: corner,
        matching: find.text(
          'Cornering 0.72\u00a0g · Braking 0.55\u00a0g (g assumed) · '
          'Exit acceleration −0.04\u00a0g (g assumed)',
        ),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(corner);
    await tester.tap(corner);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Cornering: typical 0.72\u00a0g · peak 1.03\u00a0g (Session 2 · LAP 2) · from 6 laps · '
        '1 lap measured differently is left out.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Braking: typical 0.55\u00a0g (g assumed) · peak 0.71\u00a0g (g assumed) '
        '(Session 2 · LAP 3) · from 4 laps',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Balance: typical 0.97 (yaw rate ÷ what the cornering needs) · from 5 laps',
      ),
      findsOneWidget,
    );
    final other = find.byKey(const ValueKey('gripCorner Corner 2'));
    expect(
      find.descendant(of: other, matching: find.text('')),
      findsOneWidget,
      reason: 'no summary',
    );
    await tester.ensureVisible(other);
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Cornering: not known: the laps are not timed through this corner.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Balance: not known: the recording has no yaw-rate channel.'),
      findsOneWidget,
    );
    // What each number means.
    expect(
      find.textContaining('Balance: the car\'s yaw rate divided by'),
      findsOneWidget,
    );
    expect(find.textContaining('from 0.3 g and 10 m/s'), findsOneWidget);
    expect(
      find.textContaining('about 1 whether the car understeers or oversteers'),
      findsOneWidget,
    );
    expect(find.textContaining('-like'), findsNothing);

    // Too few laps for a typical value: the summary says peak; a value from
    // the speed's change says so, and that km/h was assumed.
    final third = find.byKey(const ValueKey('gripCorner Corner 3'));
    expect(
      find.descendant(
        of: third,
        matching: find.text(
          'Cornering peak 0.61\u00a0g · Braking 0.52\u00a0g from speed (km/h assumed)',
        ),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(third);
    await tester.tap(
      find.descendant(of: third, matching: find.text('Corner 3')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Cornering: peak 0.61\u00a0g (Session 1 · LAP 2); typical needs 3 laps · '
        'from 2 laps · 3 ranked laps have no value',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Exit acceleration: not known: the channel holds only zeros (a placeholder, '
        'not a measurement).',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Balance: typical 1.05 (yaw rate ÷ what the cornering needs); units assumed · '
        'from 4 laps · 1 ranked lap has no value',
      ),
      findsOneWidget,
    );
  });

  testWidgets('fits a small phone with text ×2, open and with a corner open', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: Scaffold(
              body: ListView(
                children: [GripProxiesCard(result: _result(_grip()))],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final toggle = find.byKey(const ValueKey('gripToggle'));
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    // A tap that misses fails here rather than warning.
    Future<void> tapOn(Finder target) async {
      await tester.scrollUntilVisible(
        target,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tapOn(toggle);
    expect(tester.takeException(), isNull);
    expect(find.text('By corner'), findsOneWidget);
    await tapOn(
      find.descendant(
        of: find.byKey(const ValueKey('gripCorner Corner 1')),
        matching: find.text('Corner 1'),
      ),
    );
    expect(tester.takeException(), isNull);
    final opened = find.text(
      'Cornering: typical 0.72 g · peak 1.03 g (Session 2 · LAP 2) · from 6 laps · '
      '1 lap measured differently is left out.',
    );
    await tester.scrollUntilVisible(
      opened,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    // Opened, and its start on the screen (at ×2 it is taller than half of
    // it, so its middle may be below).
    expect(opened, findsOneWidget);
    expect(tester.getRect(opened).top, lessThan(640));
    expect(tester.getRect(opened).width, lessThanOrEqualTo(320));
  });

  testWidgets('the card speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    await _pump(
      tester,
      GripProxiesCard(result: _result(_grip())),
      locale: const Locale('pl'),
    );
    expect(find.text('Przyczepność i balans'), findsOneWidget);
    expect(find.text('Wnioskowane'), findsOneWidget);
    expect(find.text('Sesja 2 · 4 okrążenia w rankingu'), findsOneWidget);
    expect(find.text('poniżej 80\u00a0km/h'), findsOneWidget);
    expect(find.textContaining('Grip'), findsNothing);
  });

  testWidgets('from a recording without lateral acceleration', (tester) async {
    final directory = Directory.systemTemp.createTempSync('grip');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/a.vbo';
    File(path).writeAsStringSync(
      rectangleVbo([
        rectangleBrakingLap(250, 18),
        rectangleBrakingLap(270, 20),
        rectangleBrakingLap(240, 17),
      ]),
    );
    final outcome = runDayImport((paths: [path], includeSubfolders: false));
    final result = dayTheoreticalBest(
      outcome.analysis!,
      outingRuns(outcome.runs),
    );
    expect(result.state, DayTheoreticalBestState.ready);
    await _pump(tester, GripProxiesCard(result: result));
    expect(
      find.textContaining('the recording has no lateral acceleration'),
      findsWidgets,
    );
    // The speed has no unit: braking from speed says km/h is assumed.
    expect(
      find.text(
        'Braking and accelerating: from the change in speed, in g; the speed has no declared '
        'unit, so km/h is assumed.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gripCorner Corner 2')), findsOneWidget);
  });
}
