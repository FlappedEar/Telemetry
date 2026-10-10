import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/evolution_view.dart';
import 'package:telemetry/day/progression_card.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry_core/telemetry_core.dart';

const _gates =
    'gates-v2:0000000000000000000000000000000000000000000000000000000000000000';
const _revision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _track = TrackConfiguration(
  layoutId: 'Test circuit',
  direction: TrackDirection.clockwise,
  gateRevision: _gates,
);

DayLapRow _section(
  String run,
  LapSectionType type,
  int number,
  double start,
  double duration,
) => DayLapRow(
  runId: run,
  runName: run,
  type: type,
  lapNumber: number,
  start: start,
  end: start + duration,
  sourceRevision: _revision,
  referenceEligible: true,
);

List<DayLapRow> _session(String run, List<double> laps) {
  final rows = [_section(run, LapSectionType.outLap, 0, 0, 600)];
  var time = 600.0;
  for (var i = 0; i < laps.length; ++i) {
    rows.add(_section(run, LapSectionType.lap, i + 1, time, laps[i]));
    time += laps[i];
  }
  return rows;
}

void main() {
  final rows = [
    ..._session('1', [100, 95, 92, 91, 93]),
    ..._session('2', [98, 94, 90, 91, 92]),
    ..._session('3', [96, 97]),
  ];
  final configurations = {'1': _track, '2': _track, '3': _track};
  final excluded = rows.firstWhere(
    (row) =>
        row.runId == '2' &&
        row.type == LapSectionType.lap &&
        row.lapNumber == 1,
  );
  final ranking = rankDayLaps(
    rows,
    _track.compatibilityGroupId,
    configurations,
    exclusions: {excluded.reference: 'Yellow flag'},
  );
  final progression = summarizeDayProgression(rows, ranking, [
    for (final id in ['1', '2', '3'])
      ProgressionRunInfo(id: id, name: 'Session $id'),
  ], configurations);
  final evolution = summarizeDayEvolution(rows, ranking, progression);
  final weather = SessionWeather(
    sourceRevision: _revision,
    latitude: 51,
    longitude: 21,
    startMilliseconds: DateTime.utc(2026, 8, 29, 10, 15).millisecondsSinceEpoch,
    endMilliseconds: DateTime.utc(2026, 8, 29, 10, 45).millisecondsSinceEpoch,
    fetchedMilliseconds: 0,
    hours: [
      WeatherHour(
        time: DateTime.utc(2026, 8, 29, 10).millisecondsSinceEpoch,
        temperatureC: 21,
      ),
      WeatherHour(
        time: DateTime.utc(2026, 8, 29, 11).millisecondsSinceEpoch,
        temperatureC: 21.2,
      ),
    ],
  );

  Future<List<DayLapRow>> pump(WidgetTester tester, String language) async {
    final opened = <DayLapRow>[];
    await tester.binding.setSurfaceSize(const Size(412, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              ProgressionCard(
                progression: progression,
                evolution: evolution,
                result: null,
                onOpenLap: opened.add,
                weatherOf: (runId) => runId == '1' ? weather : null,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  test('the time since the first lap reads m:ss', () {
    expect(displayClock(0), '0:00');
    expect(displayClock(151.4), '2:31');
    expect(displayClock(59.6), '1:00');
    expect(displayClock(double.nan), '—');
  });

  testWidgets('shows every lap of each session by lap number', (tester) async {
    final opened = await pump(tester, 'en');
    await tester.tap(find.text('By lap'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('evolutionChart')), findsOneWidget);
    expect(find.byKey(const ValueKey('evolutionTable')), findsOneWidget);
    expect(find.text('LAP 5'), findsWidgets);
    // A measured lap: its time and when it began after the first lap.
    final cell = find.byKey(const ValueKey('evolutionCell 1 2'));
    expect(
      find.descendant(of: cell, matching: find.text(displayTime(95))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell, matching: find.text('+1:40')),
      findsOneWidget,
    );
    // A lap the ranking leaves out is listed but not measured.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('evolutionCell 2 1')),
        matching: find.text('not ranked'),
      ),
      findsOneWidget,
    );
    // With its reason below the table, as the lap list says it.
    expect(
      textOf(tester, 'evolutionNotRanked 2 1'),
      'LAP 1 · Excluded: Yellow flag',
    );
    expect(
      textOf(tester, 'evolutionPace 1'),
      "First lap in the session's middle half or quicker: LAP 2, after 1 lap",
    );
    // Session 1's quickest lap came after lap 2: lap 4 (91 s) is 4 s
    // quicker, more than the session's spread (95 - 92 s).
    expect(
      textOf(tester, 'evolutionQuickerLater 1'),
      'Its quickest lap came later: LAP 4, 4.000\u00a0s quicker than LAP 2.',
    );
    expect(find.byKey(const ValueKey('evolutionQuickerLater 2')), findsNothing);
    expect(
      textOf(tester, 'evolutionPace 2'),
      "First lap in the session's middle half or quicker: LAP 3, after 2 laps",
    );
    expect(
      find.text(
        '1 lap before it is not ranked, so whether it was slower is not known',
      ),
      findsOneWidget,
    );
    expect(
      textOf(tester, 'evolutionPace 3'),
      "The session's middle half needs at least 3 ranked laps",
    );
    expect(
      textOf(tester, 'evolutionSameLaps 2'),
      'Against Session 1 at the same laps: −1.000 s typical difference over 4 laps',
    );
    expect(
      textOf(tester, 'evolutionSameLaps 3'),
      'Against Session 2 at the same laps: 1 of the 3 laps needed',
    );
    expect(find.byKey(const ValueKey('evolutionSameLaps 1')), findsNothing);
    // The air temperature where the weather is kept, with its source.
    expect(textOf(tester, 'evolutionAir 1'), 'Air (modelled): 21 °C');
    expect(find.byKey(const ValueKey('evolutionAir 2')), findsNothing);
    expect(
      find.byKey(const ValueKey('evolutionWeatherCredit')),
      findsOneWidget,
    );
    expect(
      textOf(tester, 'evolutionCaveat'),
      contains('The track temperature is not recorded.'),
    );

    await tester.tap(cell);
    expect(opened.single.lapNumber, 2);
    expect(opened.single.runId, '1');
  });

  testWidgets('the By lap view speaks Polish', (tester) async {
    await pump(tester, 'pl');
    await tester.tap(find.text('Według okrążeń'));
    await tester.pumpAndSettle();
    expect(find.text('OKR. 5'), findsWidgets);
    expect(
      textOf(tester, 'evolutionPace 1'),
      'Pierwsze okrążenie w środkowej połowie sesji lub szybsze: OKR. 2, po 1 okrążeniu',
    );
    expect(
      textOf(tester, 'evolutionSameLaps 2'),
      'Względem Sesja 1 na tych samych okrążeniach: typowa różnica −1.000 s z 4 okrążeń',
    );
    expect(textOf(tester, 'evolutionAir 1'), 'Powietrze (model): 21 °C');
    expect(
      textOf(tester, 'evolutionQuickerLater 1'),
      'Najszybsze okrążenie przyszło później: OKR. 4, o 4.000\u00a0s szybsze '
      'niż OKR. 2.',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('evolutionCell 2 1')),
        matching: find.text('niesklasyfikowane'),
      ),
      findsOneWidget,
    );
    expect(
      textOf(tester, 'evolutionNotRanked 2 1'),
      'OKR. 1 · Wykluczone: Yellow flag',
    );
    expect(
      textOf(tester, 'evolutionCaveat'),
      contains('Temperatura nawierzchni toru nie jest rejestrowana.'),
    );
  });

  testWidgets('says so when no session has timed laps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EvolutionView(evolution: DayEvolution(groupId: null)),
        ),
      ),
    );
    expect(find.text('No session has timed laps.'), findsOneWidget);
  });

  testWidgets('hides the chart when no lap is ranked, keeping the table', (
    tester,
  ) async {
    final rows = _session('9', [90, 91, 92]);
    final configurations = {'9': _track};
    final ranking = rankDayLaps(
      rows,
      _track.compatibilityGroupId,
      configurations,
      exclusions: {
        for (final row in rows)
          if (row.type == LapSectionType.lap) row.reference: 'Wet',
      },
    );
    final progression = summarizeDayProgression(rows, ranking, [
      const ProgressionRunInfo(id: '9', name: 'Session 9'),
    ], configurations);
    final evolution = summarizeDayEvolution(rows, ranking, progression);
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: [EvolutionView(evolution: evolution)]),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('evolutionChart')), findsNothing);
    expect(find.byKey(const ValueKey('evolutionTable')), findsOneWidget);
    expect(find.text('not ranked'), findsNWidgets(3));
    expect(
      textOf(tester, 'evolutionPace 9'),
      "The session's middle half needs at least 3 ranked laps",
    );
    expect(textOf(tester, 'evolutionNotRanked 9 3'), 'LAP 3 · Excluded: Wet');
  });

  test('places session names clear of each other and inside the chart', () {
    // Six names wanted at the same spot near the bottom of the plot.
    final placed = <Rect>[];
    for (var i = 0; i < 6; ++i) {
      placed.add(
        placeEvolutionLabel(
          const Rect.fromLTWH(200, 170, 60, 14),
          placed,
          top: 0,
          bottom: 180,
        ),
      );
    }
    for (final (i, rect) in placed.indexed) {
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(180));
      for (final other in placed.skip(i + 1)) {
        expect(rect.overlaps(other), isFalse);
      }
    }
    // The first stays where it fits; the next goes up, not off the chart.
    expect(placed[0].top, 166);
    expect(placed[1].bottom, lessThan(placed[0].top));
    // With room below, a name moves down past the one it would cover.
    final below = placeEvolutionLabel(
      const Rect.fromLTWH(0, 10, 60, 14),
      [const Rect.fromLTWH(0, 8, 60, 14)],
      top: 0,
      bottom: 180,
    );
    expect(below.top, 23);
  });

  testWidgets('six sessions ending together fit a 320 px wide phone', (
    tester,
  ) async {
    final rows = [
      for (var s = 1; s <= 6; ++s)
        ..._session('$s', [100.0 - s, 96, 95.0 + s / 100]),
    ];
    final configurations = {for (var s = 1; s <= 6; ++s) '$s': _track};
    final ranking = rankDayLaps(
      rows,
      _track.compatibilityGroupId,
      configurations,
    );
    final progression = summarizeDayProgression(rows, ranking, [
      for (var s = 1; s <= 6; ++s)
        ProgressionRunInfo(id: '$s', name: 'Session $s'),
    ], configurations);
    final evolution = summarizeDayEvolution(rows, ranking, progression);
    await tester.binding.setSurfaceSize(const Size(320, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: [EvolutionView(evolution: evolution)]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('evolutionChart')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('evolutionChart'))).width,
      lessThanOrEqualTo(320),
    );
    expect(find.byKey(const ValueKey('evolutionTable')), findsOneWidget);
  });
}
