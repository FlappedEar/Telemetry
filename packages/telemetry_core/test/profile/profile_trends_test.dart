// Day by day across a profile (FET-235): synthetic profiles only.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

final _route = RouteShape(
  origin: const GeoCoordinate(52, 17),
  points: [
    for (var i = 0; i < 256; ++i)
      MetricPoint(100 * math.cos(i * math.pi / 128), 100 * math.sin(i * math.pi / 128)),
  ],
  lengthMeters: 628,
  direction: TrackDirection.clockwise,
);

const _day0 = 1735689600000; // 2025-01-01 00:00 UTC
const _dayMs = 86400000;

CornerStats _corner(
  String id, {
  int laps = 6,
  double? minimum,
  double? bestMinimum,
  double? braking,
  double? lift,
}) => CornerStats(
  cornerId: id,
  laps: laps,
  minimumSpeed: minimum,
  bestMinimumSpeed: bestMinimum,
  brakingSpreadMeters: braking,
  liftSeconds: lift,
);

ProfileSession _session(
  String runId, {
  double? best,
  int laps = 6,
  double? median,
  double? spread,
  bool otherLayout = false,
  List<CornerStats> corners = const [],
  ProfileWeather? weather,
  bool measured = true,
}) => ProfileSession(
  runId: runId,
  name: runId,
  lapCount: laps + 2,
  bestLapSeconds: best,
  stats: measured
      ? SessionStats(
          rankedLaps: laps,
          medianLapSeconds: median,
          lapSpreadSeconds: spread,
          otherLayout: otherLayout,
          corners: corners,
        )
      : null,
  weather: weather,
);

ProfileDay _day(
  String id,
  int? dayNumber, {
  String track = 'jastrzab',
  String car = 'car1',
  List<ProfileSession> sessions = const [],
  double? best,
}) => ProfileDay(
  eventId: id,
  file: 'Days/$id.fetproject',
  name: id,
  carId: car,
  trackId: track,
  startMilliseconds: dayNumber == null ? null : _day0 + dayNumber * _dayMs,
  sessions: sessions,
  bestLapSeconds: best,
);

DriverProfile _profile(List<ProfileDay> days) => DriverProfile(
  driverId: 'driver',
  cars: [
    ProfileCar(id: 'car1', name: 'Clio'),
    ProfileCar(id: 'car2', name: 'Golf'),
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
    ProfileTrack(id: 'poznan', name: 'Poznań', route: _route),
  ],
  days: days,
);

void main() {
  test('an empty profile has no trends', () {
    expect(profileTrends(_profile(const [])), isEmpty);
  });

  test('one day is shown, but too few for a trend', () {
    final trends = profileTrends(
      _profile([
        _day(
          'd1',
          0,
          best: 92,
          sessions: [
            _session(
              's1',
              best: 92,
              median: 93,
              spread: 1.2,
              corners: [
                _corner('c1', minimum: 15, bestMinimum: 15.5, braking: 5, lift: 0.3),
                _corner('c2', minimum: 20, bestMinimum: 21, braking: 7, lift: 0.5),
              ],
            ),
          ],
        ),
      ]),
    );
    expect(trends, hasLength(1));
    final trend = trends.single;
    expect(trend.track.id, 'jastrzab');
    expect(trend.carId, 'car1');
    expect(trend.enoughDays, isFalse);
    expect(trend.changes, isEmpty);
    final day = trend.days.single;
    // The first day is the only best, not a new one.
    expect(day.personalBest, isFalse);
    expect(day.visit.bestLapSeconds, 92);
    expect(day.visit.typicalLapSeconds, 93);
    // Medians over the corners, as the skills measure them.
    expect(day.measures['brakePointConsistency'], 6);
    expect(day.measures['liftTiming'], closeTo(0.4, 1e-9));
    expect(day.measures['paceConsistency'], 1.2);
    // Each corner below its own best ever, in km/h: 0.5 and 1 m/s.
    expect(day.measures['minimumSpeedControl'], closeTo(0.75 * 3.6, 1e-9));
    expect(day.weather.sessions, 0);
    expect(day.weather.conditions, isEmpty);
  });

  test('three days give each measure from its first day to its last', () {
    ProfileDay day(String id, int number, double best, double braking, double? lift) => _day(
      id,
      number,
      best: best,
      sessions: [
        _session(
          's1',
          best: best,
          median: best + 1,
          spread: 1,
          corners: [_corner('c1', minimum: 15, bestMinimum: 16, braking: braking, lift: lift)],
        ),
      ],
    );
    final trend = profileTrends(
      _profile([
        // Added out of date order: days run by date.
        day('d3', 14, 90.5, 4, 0.2),
        day('d1', 0, 92, 8, 0.4),
        day('d2', 7, 92.5, 6, null),
      ]),
    ).single;
    expect([for (final d in trend.days) d.day.eventId], ['d1', 'd2', 'd3']);
    expect(trend.enoughDays, isTrue);
    expect([for (final d in trend.days) d.personalBest], [false, false, true]);
    // Lift was not measured on d2: absent, never 0.
    expect(trend.days[1].measures.containsKey('liftTiming'), isFalse);
    final changes = {for (final change in trend.changes) change.measure: change};
    expect(changes['bestLap']!.first, 92);
    expect(changes['bestLap']!.last, 90.5);
    expect(changes['bestLap']!.change, -1.5);
    expect(changes['typicalLap']!.days, 3);
    expect(changes['brakePointConsistency']!.first, 8);
    expect(changes['brakePointConsistency']!.last, 4);
    expect(changes['paceConsistency']!.change, 0);
    // Measured on two days only: no trend for it.
    expect(changes.containsKey('liftTiming'), isFalse);
    // The best ever at c1 is 16 m/s on every day, the figure 1 m/s below.
    expect(changes['minimumSpeedControl']!.last, closeTo(3.6, 1e-9));
  });

  test('days compare only at the same track in the same car', () {
    final trends = profileTrends(
      _profile([
        _day('a1', 0, best: 92, sessions: [_session('s1', best: 92)]),
        _day('a2', 1, car: 'car2', best: 80, sessions: [_session('s1', best: 80)]),
        _day('a3', 2, best: 91, sessions: [_session('s1', best: 91)]),
        _day('p1', 3, track: 'poznan', best: 120, sessions: [_session('s1', best: 120)]),
      ]),
    );
    expect(
      [for (final t in trends) '${t.track.id} ${t.carId} ${t.days.length}'],
      ['poznan car1 1', 'jastrzab car1 2', 'jastrzab car2 1'],
    );
    final clio = trends[1];
    // The Golf's faster lap is not the Clio's best.
    expect(clio.days.last.personalBest, isTrue);
    expect(trends[2].days.single.personalBest, isFalse);
  });

  test('the minimum-speed reference is the best ever in that car', () {
    final trend = profileTrends(
      _profile([
        _day(
          'd1',
          0,
          sessions: [
            _session('s1', corners: [_corner('c1', minimum: 15, bestMinimum: 15.5)]),
          ],
        ),
        _day(
          'd2',
          1,
          sessions: [
            _session('s1', corners: [_corner('c1', minimum: 17, bestMinimum: 18)]),
          ],
        ),
        // Another car's faster corner is not this car's reference.
        _day(
          'g1',
          2,
          car: 'car2',
          sessions: [
            _session('s1', corners: [_corner('c1', minimum: 25, bestMinimum: 26)]),
          ],
        ),
      ]),
    ).firstWhere((trend) => trend.carId == 'car1');
    // Against 18 m/s, the later day's best: 3 and 1 m/s below.
    expect(trend.days[0].measures['minimumSpeedControl'], closeTo(3 * 3.6, 1e-9));
    expect(trend.days[1].measures['minimumSpeedControl'], closeTo(1 * 3.6, 1e-9));
  });

  test('sessions weigh by ranked laps; another layout and unmeasured ones do not count', () {
    final trend = profileTrends(
      _profile([
        _day(
          'd1',
          0,
          best: 92,
          sessions: [
            _session('s1', laps: 2, corners: [_corner('c1', braking: 10)]),
            _session('s2', laps: 6, corners: [_corner('c1', braking: 2)]),
            _session('s3', otherLayout: true, corners: [_corner('c1', braking: 50)]),
            _session('s4', measured: false),
          ],
        ),
      ]),
    ).single;
    expect(trend.days.single.measures['brakePointConsistency'], (10 * 2 + 2 * 6) / 8);
    expect(trend.days.single.visit.rankedLaps, 8);
  });

  test('weather: the model conditions kept, each once, and the most rain', () {
    final trend = profileTrends(
      _profile([
        _day(
          'd1',
          0,
          sessions: [
            _session(
              's1',
              weather: ProfileWeather(condition: WeatherCondition.overcast, precipitationMm: 0),
            ),
            _session(
              's2',
              weather: ProfileWeather(condition: WeatherCondition.rain, precipitationMm: 1.4),
            ),
            _session(
              's3',
              weather: ProfileWeather(condition: WeatherCondition.rain, precipitationMm: 0.6),
            ),
            // Weather with no condition this version knows still counts.
            _session('s4', weather: ProfileWeather(temperatureC: 12)),
            _session('s5'),
          ],
        ),
      ]),
    ).single;
    final weather = trend.days.single.weather;
    expect(weather.sessions, 4);
    expect(weather.conditions, [WeatherCondition.overcast, WeatherCondition.rain]);
    expect(weather.precipitationMm, 1.4);
  });

  test('undated days come last and do not set the order of tracks', () {
    final trends = profileTrends(
      _profile([
        _day('j1', 5, best: 90, sessions: [_session('s1', best: 90)]),
        _day('j2', null, best: 89, sessions: [_session('s1', best: 89)]),
        _day('p1', 3, track: 'poznan', best: 120, sessions: [_session('s1', best: 120)]),
      ]),
    );
    expect([for (final t in trends) t.track.id], ['jastrzab', 'poznan']);
    expect([for (final d in trends.first.days) d.day.eventId], ['j1', 'j2']);
    expect(trends.first.days.last.personalBest, isTrue);
  });
}
