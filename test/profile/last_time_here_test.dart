import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/last_time_here_card.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry_core/telemetry_core.dart';

final _route = RouteShape(
  origin: const GeoCoordinate(50.0, 19.0),
  // A circle of 256 points, as the profile keeps a route.
  points: [
    for (var i = 0; i < 256; ++i)
      MetricPoint(
        100 * math.cos(i * math.pi / 128),
        100 * math.sin(i * math.pi / 128),
      ),
  ],
  lengthMeters: 628,
  direction: TrackDirection.clockwise,
);

const _dayMs = 24 * 3600 * 1000;
const _day0 = 1756454400000; // 2025-08-29

ProfileDay _day(
  String id, {
  required int dayNumber,
  String car = 'clio',
  String? track = 'jastrzab',
  double? best,
  double? theoretical,
  Map<String, double> losses = const {},
  List<ProfileSession> sessions = const [],
}) => ProfileDay(
  eventId: id,
  file: 'Days/$id.fetproject',
  name: 'Day $id',
  carId: car,
  trackId: track,
  startMilliseconds: _day0 + dayNumber * _dayMs,
  bestLapSeconds: best,
  theoreticalBestSeconds: theoretical,
  sessions: [
    ...sessions,
    if (losses.isNotEmpty)
      ProfileSession(
        runId: 's1',
        name: 'Session 1',
        lapCount: 6,
        bestLapSeconds: best,
        stats: SessionStats(
          rankedLaps: 4,
          corners: [
            for (final MapEntry(:key, :value) in losses.entries)
              CornerStats(cornerId: key, laps: 4, lossSeconds: value),
          ],
        ),
      ),
  ],
);

ProfileSession _session(String id, double best, [ProfileWeather? weather]) =>
    ProfileSession(
      runId: id,
      name: 'Session ${id.substring(1)}',
      lapCount: 5,
      bestLapSeconds: best,
      weather: weather,
    );

final _warm = ProfileWeather(
  temperatureC: 21.4,
  condition: WeatherCondition.overcast,
  precipitationMm: 0,
  windSpeedKmh: 12.3,
  windDirectionDegrees: 225,
);
final _wet = ProfileWeather(
  temperatureC: 14.6,
  temperatureMinC: 13.8,
  temperatureMaxC: 15.2,
  condition: WeatherCondition.rain,
  precipitationMm: 1.24,
  windSpeedKmh: 20,
);

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('last_time'));
  tearDown(() => folder.deleteSync(recursive: true));

  Future<ProfileLibrary> library(List<ProfileDay> days) async {
    final profile = DriverProfile(
      driverId: 'driver',
      cars: [
        ProfileCar(id: 'clio', name: 'Clio'),
        ProfileCar(id: 'golf', name: 'Golf'),
      ],
      tracks: [
        ProfileTrack(
          id: 'jastrzab',
          name: 'Jastrząb',
          route: _route,
          corners: [
            TrackCorner(id: 'k1', name: 'Turn 1', start: 0.1, end: 0.15),
            TrackCorner(id: 'k2', name: 'Turn 2', start: 0.4, end: 0.45),
            TrackCorner(id: 'k3', name: 'Turn 3', start: 0.7, end: 0.75),
          ],
        ),
      ],
      days: days,
    );
    File('${folder.path}/$profileFileName')
        .writeAsStringSync(encodeDriverProfile(profile));
    final shelf = ProfileLibrary(
      store: FolderProfileStore(folder.path),
      defaultCarName: 'My car',
      defaultTrackName: (number) => 'Track $number',
      background: <R>(FutureOr<R> Function() computation) async =>
          computation(),
    );
    await shelf.load();
    return shelf;
  }

  Future<void> show(WidgetTester tester, ProfileLibrary shelf, String id) =>
      tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(
            body: LastTimeHereCard(library: shelf, eventId: id),
          ),
        ),
      );

  testWidgets('shows the last visit next to today, faster in green', (
    tester,
  ) async {
    final shelf = await tester.runAsync(
      () => library([
        _day('a', dayNumber: 0, best: 112.0, theoretical: 110.0),
        _day('b', dayNumber: 30, best: 111.204, theoretical: 109.5),
        _day('today', dayNumber: 60, best: 109.898, theoretical: 109.9),
      ]),
    );
    await show(tester, shelf!, 'today');
    expect(find.byKey(const ValueKey('lastTimeHere')), findsOneWidget);
    // The visit just before today, not the first.
    expect(
      find.textContaining('Day b'),
      findsOneWidget,
      reason: 'the last visit before today',
    );
    expect(find.text('1:51.204 then · 1:49.898 today'), findsOneWidget);
    expect(find.text('−1.306 s'), findsOneWidget);
    // Theoretical best slower today: a positive difference.
    expect(find.text('1:49.500 then · 1:49.900 today'), findsOneWidget);
    expect(find.text('+0.400 s'), findsOneWidget);
  });

  testWidgets('each corner measured on both days, with the time lost there', (
    tester,
  ) async {
    final shelf = await tester.runAsync(
      () => library([
        _day('a', dayNumber: 0, best: 112.0, losses: {'k1': 0.6, 'k2': 0.2}),
        _day(
          'today',
          dayNumber: 30,
          best: 110.0,
          losses: {'k1': 0.25, 'k3': 0.1},
        ),
      ]),
    );
    await show(tester, shelf!, 'today');
    expect(find.byKey(const ValueKey('lastTimeHereCorners')), findsOneWidget);
    final turn1 = find.byKey(const ValueKey('lastTimeHereCorner k1'));
    expect(
      find.descendant(of: turn1, matching: find.text('Turn 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: turn1,
        matching: find.text('0.600\u00a0s then · 0.250\u00a0s today'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: turn1, matching: find.text('−0.350\u00a0s')),
      findsOneWidget,
    );
    // Turn 2 only last time, Turn 3 only today: neither is listed.
    expect(find.byKey(const ValueKey('lastTimeHereCorner k2')), findsNothing);
    expect(find.byKey(const ValueKey('lastTimeHereCorner k3')), findsNothing);
    expect(find.textContaining('not a faster corner'), findsOneWidget);

    // No corner on both days: no corner rows.
    final none = await tester.runAsync(
      () => library([
        _day('a', dayNumber: 0, best: 112.0, losses: {'k2': 0.2}),
        _day('today', dayNumber: 30, best: 110.0, losses: {'k1': 0.25}),
      ]),
    );
    await show(tester, none!, 'today');
    expect(find.byKey(const ValueKey('lastTimeHere')), findsOneWidget);
    expect(find.byKey(const ValueKey('lastTimeHereCorners')), findsNothing);
    expect(
      find.text('Time lost per corner: no corner was measured on both days.'),
      findsOneWidget,
    );

    // Today not measured yet (no stats): said too.
    final unmeasured = await tester.runAsync(
      () => library([
        _day('a', dayNumber: 0, best: 112.0, losses: {'k1': 0.6}),
        _day('today', dayNumber: 30, best: 110.0),
      ]),
    );
    await show(tester, unmeasured!, 'today');
    expect(
      find.byKey(const ValueKey('lastTimeHereCornersNone')),
      findsOneWidget,
    );
  });

  testWidgets('the visit before by date, whatever order days were added', (
    tester,
  ) async {
    final shelf = await tester.runAsync(
      () => library([
        _day('later', dayNumber: 60, best: 108.0),
        _day('opened', dayNumber: 30, best: 110.0),
        _day('first', dayNumber: 0, best: 112.0),
      ]),
    );
    // An older day opened after a later visit: compared with the one
    // before it.
    await show(tester, shelf!, 'opened');
    expect(find.textContaining('Day first'), findsOneWidget);
    await show(tester, shelf, 'later');
    expect(find.textContaining('Day opened'), findsOneWidget);
    await show(tester, shelf, 'first');
    expect(find.byKey(const ValueKey('lastTimeHere')), findsNothing);
  });

  testWidgets('an undated day compares with the latest dated visit', (
    tester,
  ) async {
    final shelf = await tester.runAsync(
      () => library([
        _day('a', dayNumber: 0, best: 112.0),
        _day('b', dayNumber: 30, best: 111.0),
        ProfileDay(
          eventId: 'undated',
          file: 'Days/undated.fetproject',
          name: 'Day undated',
          carId: 'clio',
          trackId: 'jastrzab',
          bestLapSeconds: 110.0,
        ),
      ]),
    );
    await show(tester, shelf!, 'undated');
    expect(find.textContaining('Day b'), findsOneWidget);
  });

  testWidgets('prefers the same car and names another car', (tester) async {
    final shelf = await tester.runAsync(
      () => library([
        _day('clio1', dayNumber: 0, best: 115.0),
        _day('golf1', dayNumber: 10, car: 'golf', best: 108.0),
        _day('today', dayNumber: 20, best: 110.0),
      ]),
    );
    await show(tester, shelf!, 'today');
    expect(find.textContaining('Day clio1'), findsOneWidget);
    expect(find.textContaining('Golf'), findsNothing);

    final golfOnly = await tester.runAsync(
      () => library([
        _day('golf1', dayNumber: 10, car: 'golf', best: 108.0),
        _day('today', dayNumber: 20, best: 110.0),
      ]),
    );
    await show(tester, golfOnly!, 'today');
    expect(find.textContaining('Day golf1'), findsOneWidget);
    expect(find.textContaining('· Golf'), findsOneWidget);
    expect(find.textContaining('not driven here before'), findsOneWidget);
  });

  testWidgets('nothing on a first visit, an unknown track or another day', (
    tester,
  ) async {
    final shelf = await tester.runAsync(
      () => library([
        _day('first', dayNumber: 0, best: 115.0),
        _day('nowhere', dayNumber: 5, track: null, best: 99.0),
      ]),
    );
    for (final id in ['first', 'nowhere', 'not-in-profile']) {
      await show(tester, shelf!, id);
      expect(find.byKey(const ValueKey('lastTimeHere')), findsNothing);
    }
  });

  testWidgets('a missing time reads as a dash, with no difference', (
    tester,
  ) async {
    final shelf = await tester.runAsync(
      () => library([
        _day('a', dayNumber: 0, best: 112.0),
        _day('today', dayNumber: 30),
      ]),
    );
    await show(tester, shelf!, 'today');
    expect(find.text('1:52.000 then · — today'), findsOneWidget);
    expect(find.byKey(const ValueKey('lastTimeHereMissing')), findsOneWidget);
    expect(find.textContaining('−'), findsNothing);
    expect(find.textContaining('+'), findsNothing);
  });

  group('weather', () {
    const credit =
        "Modelled for the area around the track at the session's time, not "
        'measured at the track. Weather data by Open-Meteo.com';
    const reason =
        'No weather for that session: weather lookup off, no time or '
        'position, or the day was added before the library kept weather.';

    testWidgets('of the best lap session on both visits, with the credit', (
      tester,
    ) async {
      final shelf = await tester.runAsync(
        () => library([
          _day(
            'a',
            dayNumber: 0,
            best: 111.2,
            sessions: [
              _session('s1', 113.0, _warm),
              _session('s2', 111.2, _wet),
            ],
          ),
          _day(
            'today',
            dayNumber: 30,
            best: 109.9,
            sessions: [
              _session('s1', 109.9, _warm),
              _session('s2', 110.4, _wet),
            ],
          ),
        ]),
      );
      await show(tester, shelf!, 'today');
      expect(find.byKey(const ValueKey('lastTimeHereWeather')), findsOneWidget);
      expect(
        find.text(
          'Then (Session 2): 14–15 °C, rain, 1.2 mm of rain, wind 20 km/h',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Today (Session 1): 21 °C, overcast, no rain, wind SW 12 km/h',
        ),
        findsOneWidget,
      );
      expect(find.text(credit), findsOneWidget);
      expect(
        find.byKey(const ValueKey('lastTimeHereWeatherMissing')),
        findsNothing,
      );
    });

    testWidgets('a best lap session without weather: the first with it', (
      tester,
    ) async {
      final shelf = await tester.runAsync(
        () => library([
          _day(
            'a',
            dayNumber: 0,
            best: 111.2,
            sessions: [
              _session('s1', 111.2),
              _session('s2', 112.0, _wet),
              _session('s3', 113.0, _warm),
            ],
          ),
          _day(
            'today',
            dayNumber: 30,
            best: 109.9,
            sessions: [_session('s1', 109.9, _warm)],
          ),
        ]),
      );
      await show(tester, shelf!, 'today');
      expect(find.textContaining('Then (Session 2): 14–15 °C'), findsOneWidget);
    });

    testWidgets('one side missing reads as a dash with the reason', (
      tester,
    ) async {
      final shelf = await tester.runAsync(
        () => library([
          _day(
            'a',
            dayNumber: 0,
            best: 111.2,
            sessions: [_session('s1', 111.2)],
          ),
          _day(
            'today',
            dayNumber: 30,
            best: 109.9,
            sessions: [_session('s1', 109.9, _warm)],
          ),
        ]),
      );
      await show(tester, shelf!, 'today');
      expect(find.text('Then: —'), findsOneWidget);
      expect(find.textContaining('Today (Session 1): 21 °C'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(find.text(credit), findsOneWidget);
    });

    testWidgets('no weather on either visit: only the reason', (tester) async {
      final shelf = await tester.runAsync(
        () => library([
          _day('a', dayNumber: 0, best: 112.0),
          _day(
            'today',
            dayNumber: 30,
            best: 110.0,
            sessions: [_session('s1', 110.0)],
          ),
        ]),
      );
      await show(tester, shelf!, 'today');
      expect(find.byKey(const ValueKey('lastTimeHereWeather')), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(
        find.byKey(const ValueKey('lastTimeHereWeatherThen')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('lastTimeHereWeatherToday')),
        findsNothing,
      );
      expect(find.text(credit), findsNothing);
    });
  });
}
