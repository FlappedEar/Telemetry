// The Profile place: what the profile works out across days, shown.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry/profile/profile_page.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../support/temp_directory.dart';

/// No profile folder, as when the profile cannot be used.
final class _NoFolder implements ProfileStore {
  const _NoFolder();

  @override
  Future<String?> folder() async => null;
}

Future<R> _inPlace<R>(FutureOr<R> Function() computation) async =>
    computation();

final _route = RouteShape(
  origin: const GeoCoordinate(52, 17),
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

const _day0 = 1735689600000; // 2025-01-01
const _dayMs = 86400000;

ProfileSession _session(
  String runId, {
  required double best,
  required double median,
  required double spread,
  double distance = 20000,
  List<CornerStats> corners = const [],
}) => ProfileSession(
  runId: runId,
  name: 'Session ${runId.substring(1)}',
  lapCount: 10,
  bestLapSeconds: best,
  stats: SessionStats(
    distanceMeters: distance,
    drivingSeconds: distance / 25,
    rankedLaps: 8,
    medianLapSeconds: median,
    lapSpreadSeconds: spread,
    corners: corners,
  ),
);

CornerStats _corner(String id, double loss) => CornerStats(
  cornerId: id,
  laps: 8,
  minimumSpeed: 15,
  bestMinimumSpeed: 15.5,
  exitSpeed: 20,
  bestExitSpeed: 20.3,
  brakingSpreadMeters: 5,
  lossSeconds: loss,
  liftSeconds: 0.3,
  decelerationG: 0.8,
  bestDecelerationG: 0.9,
);

ProfileDay _visit(String id, int number, double best) => ProfileDay(
  eventId: id,
  file: 'Days/$id.fetproject',
  name: id,
  carId: 'car1',
  trackId: 'jastrzab',
  startMilliseconds: _day0 + number * _dayMs,
  sessions: [
    _session(
      's1',
      best: best,
      median: best + 1,
      spread: 1.5,
      corners: [_corner('c1', 0.4), _corner('c2', 0.05)],
    ),
  ],
  bestLapSeconds: best,
  theoreticalBestSeconds: best - 1,
);

DriverProfile _profile(List<ProfileDay> days) => DriverProfile(
  driverId: 'driver',
  cars: [
    ProfileCar(id: 'car1', name: 'Clio'),
    ProfileCar(id: 'car2', name: 'Unused'),
  ],
  tracks: [
    ProfileTrack(
      id: 'jastrzab',
      name: 'Jastrząb',
      route: _route,
      corners: [
        TrackCorner(id: 'c1', name: 'Corner 1', start: 0.1, end: 0.2),
        TrackCorner(id: 'c2', name: 'Corner 2', start: 0.5, end: 0.6),
      ],
    ),
  ],
  days: days,
);

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('profile'));
  tearDown(() => deleteTemporaryDirectory(directory));

  Future<void> show(
    WidgetTester tester,
    DriverProfile profile, {
    String? locale,
  }) async {
    final folder = p.join(directory.path, 'Profile');
    Directory(p.join(folder, profileDaysFolder)).createSync(recursive: true);
    File(p.join(folder, profileFileName))
        .writeAsStringSync(encodeDriverProfile(profile));
    final library = ProfileLibrary(
      store: FolderProfileStore(folder),
      defaultCarName: 'My car',
      defaultTrackName: (number) => 'Track $number',
      background: _inPlace,
    );
    await tester.runAsync(library.load);
    await tester.binding.setSurfaceSize(const Size(412, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: locale == null ? null : Locale(locale),
        home: ProfilePage(library: library),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a profile with no day says what will appear', (tester) async {
    await show(tester, _profile(const []));
    expect(find.byKey(const ValueKey('profileEmpty')), findsOneWidget);
  });

  testWidgets('totals, skills, cars, records and repeated losses', (
    tester,
  ) async {
    await show(tester, _profile([_visit('d1', 0, 92), _visit('d2', 7, 91.5)]));
    String total(String label) =>
        tester.widget<Text>(find.byKey(ValueKey('profileTotal $label'))).data!;
    expect(total('Days'), '2');
    expect(total('Sessions'), '2');
    expect(total('Distance'), '40.0 km');
    expect(total('Time on track'), '27\u00a0min');
    expect(find.byKey(const ValueKey('profileMeasured')), findsNothing);

    // Every skill of the model, measured or not, says where it stands.
    for (final skill in skillCatalogue) {
      expect(find.byKey(ValueKey('skill ${skill.id}')), findsOneWidget);
    }
    final pace = tester
        .widget<Text>(
          find.byKey(const ValueKey('skillDetails paceConsistency')),
        )
        .data!;
    expect(pace, startsWith('Level 3 of 5'));
    expect(pace, contains('High confidence'));
    expect(pace, contains('16 ranked laps over 2 days'));
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('skillValue paceConsistency')),
          )
          .data,
      'Lap time spread: 1.50 s',
    );
    String value(String id) =>
        tester.widget<Text>(find.byKey(ValueKey('skillValue $id'))).data!;
    expect(value('liftTiming'), 'Off the throttle to braking: 0.30\u00a0s');
    // 0.8 g against the best ever there, 0.9 g.
    expect(
      value('brakingEffectiveness'),
      'Braking below your best: 0.10\u00a0g',
    );
    // No throttle figures in this profile.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('skillDetails throttleCommitment')),
          )
          .data,
      'Needs more evidence',
    );

    // Only cars that drove.
    expect(find.byKey(const ValueKey('profileCar car1')), findsOneWidget);
    expect(find.byKey(const ValueKey('profileCar car2')), findsNothing);

    // The track's records, with the progress since the visit before.
    final track = find.byKey(const ValueKey('profileTrack jastrzab'));
    expect(
      find.descendant(of: track, matching: find.textContaining('1:31.500')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: track,
        matching: find.text(
          'Last visit: best lap 0.500 s faster than the visit before',
        ),
      ),
      findsOneWidget,
    );

    // Below the day-by-day figures.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profileRepeated')),
      300,
    );
    // Corner 1 lost time on both visits; Corner 2 too little to count.
    expect(find.byKey(const ValueKey('profileRepeated 0')), findsOneWidget);
    expect(find.text('Jastrząb · Corner 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('profileRepeated 1')), findsNothing);
  });

  testWidgets('in Polish', (tester) async {
    await show(
      tester,
      _profile([_visit('d1', 0, 92), _visit('d2', 7, 91.5)]),
      locale: 'pl',
    );
    expect(find.text('Wszystkie dni'), findsOneWidget);
    expect(find.text('Powtarzalność tempa'), findsOneWidget);
    expect(find.text('Potrzeba więcej danych'), findsWidgets);
    expect(
      find.text('Od odjęcia gazu do hamowania: 0.30\u00a0s'),
      findsOneWidget,
    );
    expect(find.textContaining('2 wizyty'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('skillDetails paceConsistency')),
          )
          .data,
      contains('16 sklasyfikowanych okrążeń z 2 dni'),
    );
  });

  testWidgets('day by day: one day is too few for a trend', (tester) async {
    await show(tester, _profile([_visit('d1', 0, 92)]));
    final card = find.byKey(const ValueKey('profileTrends'));
    await tester.scrollUntilVisible(card, 300);
    expect(card, findsOneWidget);
    expect(find.text('Jastrząb · Clockwise · Clio'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('profileTrendTooFew jastrzab car1')),
          )
          .data,
      '1 dated day here in this car: a trend needs at least 3 days.',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendTimes d1')))
          .data,
      'Best lap 1:32.000 · Typical lap 1:33.000',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendMeasures d1')))
          .data,
      'Braking-point spread: 5.0\u00a0m · '
      'Minimum speed below your best: 1.8\u00a0km/h · '
      'Off the throttle to braking: 0.30\u00a0s · '
      'Lap time spread: 1.50\u00a0s',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendWeather d1')))
          .data,
      'No weather kept for this day.',
    );
    expect(find.byKey(const ValueKey('profileTrendsWetDry')), findsOneWidget);
    expect(find.textContaining('First day to last'), findsNothing);
  });

  testWidgets('day by day: three days show first to last', (tester) async {
    final rainy = _visit('d3', 14, 91);
    await show(
      tester,
      _profile([
        _visit('d1', 0, 92),
        _visit('d2', 7, 92.5),
        ProfileDay(
          eventId: rainy.eventId,
          file: rainy.file,
          name: rainy.name,
          carId: rainy.carId,
          trackId: rainy.trackId,
          startMilliseconds: rainy.startMilliseconds,
          bestLapSeconds: rainy.bestLapSeconds,
          sessions: [
            for (final session in rainy.sessions)
              ProfileSession(
                runId: session.runId,
                name: session.name,
                lapCount: session.lapCount,
                bestLapSeconds: session.bestLapSeconds,
                stats: session.stats,
                weather: ProfileWeather(
                  condition: WeatherCondition.rain,
                  precipitationMm: 1.4,
                ),
              ),
          ],
        ),
      ]),
    );
    final change = find.byKey(
      const ValueKey('profileTrendChange jastrzab car1 bestLap'),
    );
    await tester.scrollUntilVisible(change, 300);
    expect(
      find.byKey(const ValueKey('profileTrendTooFew jastrzab car1')),
      findsNothing,
    );
    expect(
      tester.widget<Text>(change).data,
      'Best lap: 1:32.000 (Jan 1, 2025) → 1:31.000 (Jan 15, 2025), '
      'across 3 measured days',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey(
                'profileTrendChange jastrzab car1 brakePointConsistency',
              ),
            ),
          )
          .data,
      'Braking-point spread: 5.0\u00a0m (Jan 1, 2025) → 5.0\u00a0m (Jan 15, 2025), '
      'across 3 measured days',
    );
    // Only the day that beat every earlier one is a new best.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendTimes d3')))
          .data,
      'Best lap 1:31.000 · new best here in this car · Typical lap 1:32.000',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendTimes d2')))
          .data,
      isNot(contains('new best')),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendWeather d3')))
          .data,
      'Weather model: rain, up to 1.4\u00a0mm of rain in a session',
    );
  });

  testWidgets('day by day: a figure on too few days says why', (tester) async {
    // Three days; lap times on all, corner figures on two of them only.
    final bare = _visit('d2', 7, 92.5);
    await show(
      tester,
      _profile([
        _visit('d1', 0, 92),
        ProfileDay(
          eventId: bare.eventId,
          file: bare.file,
          name: bare.name,
          carId: bare.carId,
          trackId: bare.trackId,
          startMilliseconds: bare.startMilliseconds,
          bestLapSeconds: bare.bestLapSeconds,
          sessions: [
            _session('s1', best: 92.5, median: 93.5, spread: 1.5),
            ProfileSession(
              runId: 's2',
              name: 'Session 2',
              lapCount: 3,
              weather: ProfileWeather(condition: WeatherCondition.clear),
            ),
          ],
        ),
        _visit('d3', 14, 91),
      ]),
    );
    final reason = find.byKey(
      const ValueKey('profileTrendTooFew jastrzab car1 brakePointConsistency'),
    );
    await tester.scrollUntilVisible(reason, 300);
    expect(
      tester.widget<Text>(reason).data,
      'Braking-point spread: measured on 2 dated days; '
      'a trend needs a figure on at least 3 days.',
    );
    // Lap time spread is on every day: a change, no reason.
    expect(
      find.byKey(
        const ValueKey('profileTrendChange jastrzab car1 paceConsistency'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('profileTrendTooFew jastrzab car1 paceConsistency'),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendWeather d2')))
          .data,
      'Weather model: clear (1 of 2 sessions)',
    );
  });

  testWidgets('day by day: the last 10 days listed, the change over all', (
    tester,
  ) async {
    await show(
      tester,
      _profile([for (var i = 0; i < 12; i++) _visit('d$i', i, 100.0 - i)]),
    );
    final change = find.byKey(
      const ValueKey('profileTrendChange jastrzab car1 bestLap'),
    );
    await tester.scrollUntilVisible(change, 300);
    expect(
      tester.widget<Text>(change).data,
      'Best lap: 1:40.000 (Jan 1, 2025) → 1:29.000 (Jan 12, 2025), '
      'across 12 measured days',
    );
    expect(find.text('The last 10 of 12 days here.'), findsOneWidget);
    expect(find.byKey(const ValueKey('profileTrendDay d0')), findsNothing);
    expect(find.byKey(const ValueKey('profileTrendDay d1')), findsNothing);
    // The card is built whole, so a day it leaves out is not just off screen.
    expect(find.byKey(const ValueKey('profileTrendDay d2')), findsOneWidget);
    expect(find.byKey(const ValueKey('profileTrendDay d11')), findsOneWidget);
  });

  testWidgets('day by day in Polish', (tester) async {
    await show(tester, _profile([_visit('d1', 0, 92)]), locale: 'pl');
    final card = find.byKey(const ValueKey('profileTrends'));
    await tester.scrollUntilVisible(card, 300);
    expect(find.text('Dzień po dniu'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('profileTrendTooFew jastrzab car1')),
          )
          .data,
      '1 dzień z datą na tym torze w tym samochodzie: '
      'trend wymaga co najmniej 3 dni.',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendTimes d1')))
          .data,
      'Najlepsze okrążenie 1:32.000 · Typowe okrążenie 1:33.000',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendMeasures d1')))
          .data,
      startsWith('Rozrzut punktu hamowania: 5.0\u00a0m · '),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendWeather d1')))
          .data,
      'Brak zapisanej pogody dla tego dnia.',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profileTrendsWetDry')))
          .data,
      startsWith('Nie zapisuje się, czy tor był mokry, czy suchy.'),
    );
  });

  testWidgets('a slower last visit says so', (tester) async {
    await show(tester, _profile([_visit('d1', 0, 91.5), _visit('d2', 7, 92)]));
    expect(
      find.text(
        'Last visit: best lap 0.500\u00a0s slower than the visit before',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a best lap equal to the shown precision is no change', (
    tester,
  ) async {
    await show(
      tester,
      _profile([_visit('d1', 0, 92), _visit('d2', 7, 91.9998)]),
    );
    expect(find.textContaining('Last visit:'), findsNothing);
  });

  testWidgets('days with nothing measured show no zeros', (tester) async {
    final day = _visit('d1', 0, 92);
    await show(
      tester,
      _profile([
        ProfileDay(
          eventId: day.eventId,
          file: day.file,
          name: day.name,
          carId: 'car1',
          sessions: [
            ProfileSession(runId: 's1', name: 'Session 1', lapCount: 10),
          ],
        ),
      ]),
    );
    String total(String label) =>
        tester.widget<Text>(find.byKey(ValueKey('profileTotal $label'))).data!;
    expect(total('Distance'), '—');
    expect(total('Time on track'), '—');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('profileMeasured'))).data,
      startsWith('Distance and time cover 0 of 1 session:'),
    );
    expect(
      find.text('1 day · distance and time not measured yet'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profileTracksNone')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('skillDetails paceConsistency')),
          )
          .data,
      'Needs more evidence',
    );
  });

  testWidgets('a profile that cannot be used says so, not "no days"', (
    tester,
  ) async {
    final library = ProfileLibrary(
      store: const _NoFolder(),
      defaultCarName: 'My car',
      defaultTrackName: (number) => 'Track $number',
      background: _inPlace,
    );
    await tester.pumpWidget(TelemetryApp(home: ProfilePage(library: library)));
    // Still loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('profileEmpty')), findsNothing);
    await tester.runAsync(library.load);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profileUnavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('profileEmpty')), findsNothing);
  });
}
