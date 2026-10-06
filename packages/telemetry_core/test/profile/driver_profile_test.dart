import 'dart:convert';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// A day of [sessions] laps of a circle of [radius] m starting at [start]
/// (Unix ms), analysed as the app does.
ProfileDayInput _day(
  String eventId, {
  double radius = 100,
  bool clockwise = false,
  int start = 1756454400000, // 2025-08-29 08:00 UTC
  int sessions = 2,
  String? trackName,
  Map<String, WeatherSummary?>? weather,
  Map<String, String> recordings = const {},
  Map<String, ProfileSetup?>? setups,
}) {
  final runs = [
    for (var index = 0; index < sessions; ++index)
      () {
        final session = circuitSession(
          radius: radius,
          clockwise: clockwise,
          speeds: [30, 29 + index.toDouble(), 31, 30],
          firstTimestampMilliseconds: start + index * 3600000,
        );
        return DayRunInput(
          runId: 'run${index + 1}',
          name: 'Session ${index + 1}',
          contentSha256: recordings['run${index + 1}'] ?? _runRevision(index + 1),
          session: session,
          laps: deriveSourceLapSession(session),
        );
      }(),
  ];
  return ProfileDayInput.fromAnalysis(
    eventId: eventId,
    file: 'Days/$eventId.fetproject',
    name: 'Day $eventId',
    analysis: analyzeDay(runs),
    trackName: trackName,
    weather: weather?.map(
      (runId, summary) => MapEntry(
        runId,
        ProfileWeather.of(
          summary,
          sourceRevision: recordings[runId] ?? _runRevision(int.parse(runId.substring(3))),
        ),
      ),
    ),
    setups: setups,
  );
}

String _runRevision(int number) => _revision.replaceFirst('a', '$number');

DriverProfile _add(DriverProfile profile, ProfileDayInput day) => addDayToProfile(
  profile,
  day,
  defaultCarName: 'My car',
  defaultTrackName: 'Track',
  random: Random(day.eventId.hashCode),
);

void main() {
  group('ProfileDayInput.fromAnalysis', () {
    test('keeps each session, the best laps and the route', () {
      final day = _day('a', sessions: 3);
      expect(
        [for (final session in day.sessions) session.name],
        ['Session 1', 'Session 2', 'Session 3'],
      );
      expect(day.sessions.first.startMilliseconds, 1756454400000);
      expect(day.startMilliseconds, 1756454400000);
      for (final session in day.sessions) {
        expect(session.lapCount, greaterThanOrEqualTo(3));
        expect(session.bestLapSeconds, isNotNull);
      }
      final fastest = day.sessions.map((s) => s.bestLapSeconds!).reduce(min);
      expect(day.bestLapSeconds, fastest);
      expect(day.route, isNotNull);
      expect(day.route!.lengthMeters, closeTo(2 * pi * 100, 10));
    });
  });

  group('addDayToProfile', () {
    test('a first day gets a new car and a new track without asking', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a', trackName: 'Jastrząb'));
      expect(profile.cars.single.name, 'My car');
      expect(profile.tracks.single.name, 'Jastrząb');
      final day = profile.days.single;
      expect(day.carId, profile.cars.single.id);
      expect(day.trackId, profile.tracks.single.id);
      expect(profile.lastCarId, day.carId);
    });

    test('a later day on the same circuit is the same track and the last car', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a', trackName: 'Jastrząb'));
      profile = addProfileCar(profile, 'Civic', random: Random(2));
      final civic = profile.cars.last.id;
      profile = setProfileDayCar(profile, 'a', civic);
      profile = _add(profile, _day('b', start: 1759132800000, trackName: 'Elsewhere'));
      expect(profile.tracks, hasLength(1));
      expect(profile.day('b')!.trackId, profile.day('a')!.trackId);
      expect(profile.day('b')!.carId, civic);
      expect(
        earlierVisits(profile, profile.tracks.single.id, exceptEventId: 'b').single.eventId,
        'a',
      );
    });

    test('another circuit or the other direction is another track', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      profile = _add(profile, _day('b', radius: 150));
      profile = _add(profile, _day('c', clockwise: true));
      expect(profile.tracks, hasLength(3));
      expect({for (final day in profile.days) day.trackId}, hasLength(3));
      expect(profile.tracks.map((t) => t.name), everyElement('Track'));
    });

    test('adding a day again updates it and keeps its car and track', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final first = profile.cars.first.id;
      profile = addProfileCar(profile, 'Civic', random: Random(2));
      final civic = profile.cars.last.id;
      profile = _add(profile, _day('b', start: 1759132800000));
      profile = setProfileDayCar(profile, 'b', civic);
      expect(profile.lastCarId, civic);
      profile = _add(profile, _day('a', sessions: 3));
      expect(profile.days, hasLength(2));
      expect(profile.day('a')!.sessions, hasLength(3));
      expect(profile.day('a')!.carId, first);
      expect(profile.tracks, hasLength(1));
      // Adding an older day again does not change the car new days take.
      expect(profile.lastCarId, civic);
      profile = _add(profile, _day('c', start: 1759219200000));
      expect(profile.day('c')!.carId, civic);
    });

    test('a day added again without a route keeps its track', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final track = profile.day('a')!.trackId;
      expect(track, isNotNull);
      profile = _add(
        profile,
        ProfileDayInput(eventId: 'a', file: 'Days/a.fetproject', name: 'Day a'),
      );
      expect(profile.day('a')!.trackId, track);
      expect(earlierVisits(profile, track!), hasLength(1));
    });

    test('refuses values that could not be written or read back', () {
      final profile = DriverProfile.empty(Random(1));
      void refused(ProfileDayInput day) =>
          expect(() => _add(profile, day), throwsA(isA<ProfileFormatError>()));
      final good = _day('a');
      ProfileDayInput like({double? best, List<ProfileSession>? sessions, RouteShape? route}) =>
          ProfileDayInput(
            eventId: 'a',
            file: 'Days/a.fetproject',
            name: 'Day',
            bestLapSeconds: best,
            sessions: sessions ?? const [],
            route: route,
          );
      refused(like(best: double.nan));
      refused(like(best: -1));
      refused(
        like(
          sessions: [ProfileSession(runId: 'r', name: 'S', lapCount: -1)],
        ),
      );
      refused(
        like(
          sessions: [ProfileSession(runId: 'r', name: 'S', bestLapSeconds: 0)],
        ),
      );
      refused(
        like(
          sessions: [
            ProfileSession(runId: 'r', name: 'S'),
            ProfileSession(runId: 'r', name: 'T'),
          ],
        ),
      );
      final route = good.route!;
      RouteShape changed({double? length, List<MetricPoint>? points, GeoCoordinate? origin}) =>
          RouteShape(
            origin: origin ?? route.origin,
            points: points ?? route.points,
            lengthMeters: length ?? route.lengthMeters,
            direction: route.direction,
          );
      refused(like(route: changed(length: 50000)));
      refused(like(route: changed(points: route.points.skip(1).toList())));
      refused(like(route: changed(points: [const MetricPoint(1e308, 0), ...route.points.skip(1)])));
      refused(like(route: changed(origin: const GeoCoordinate(91, 0))));
      expect(_add(profile, good).days, hasLength(1));
    });

    test('a session on another layout that day keeps its best lap', () {
      DayRunInput run(String id, double radius, int start) {
        final session = circuitSession(
          radius: radius,
          speeds: [30, 29, 31, 30],
          firstTimestampMilliseconds: start,
        );
        return DayRunInput(
          runId: id,
          name: 'Session $id',
          contentSha256: _revision.replaceFirst('a', id),
          session: session,
          laps: deriveSourceLapSession(session),
        );
      }

      final analysis = analyzeDay([
        run('1', 100, 1756454400000),
        run('2', 100, 1756458000000),
        run('3', 150, 1756461600000),
      ]);
      expect(analysis.groups.where((group) => group.resolved), hasLength(2));
      final day = ProfileDayInput.fromAnalysis(
        eventId: 'a',
        file: 'Days/a.fetproject',
        name: 'Day',
        analysis: analysis,
      );
      expect(day.sessions, hasLength(3));
      for (final session in day.sessions) {
        expect(session.bestLapSeconds, isNotNull, reason: session.name);
      }
    });

    test('refuses a day the profile could not read back', () {
      final profile = DriverProfile.empty(Random(1));
      void refused(ProfileDayInput day) =>
          expect(() => _add(profile, day), throwsA(isA<ProfileFormatError>()));
      refused(ProfileDayInput(eventId: ' ', file: 'Days/a.fetproject', name: 'Day'));
      refused(ProfileDayInput(eventId: 'a', file: 'Days/a.fetproject', name: 'a\u0000b'));
      refused(ProfileDayInput(eventId: 'a', file: '../a.fetproject', name: 'Day'));
      refused(ProfileDayInput(eventId: 'a', file: '/tmp/a.fetproject', name: 'Day'));
      refused(ProfileDayInput(eventId: 'a', file: r'C:\a.fetproject', name: 'Day'));
      refused(
        ProfileDayInput(
          eventId: 'a',
          file: 'Days/a.fetproject',
          name: 'Day',
          startMilliseconds: 9007199254740991,
        ),
      );
      refused(
        ProfileDayInput(
          eventId: 'a',
          file: 'Days/a.fetproject',
          name: 'Day',
          sessions: [
            for (var i = 0; i <= maximumDayRuns; ++i) ProfileSession(runId: 'r$i', name: 'S'),
          ],
        ),
      );
    });

    test('a day without complete laps has no track', () {
      final profile = _add(
        DriverProfile.empty(Random(1)),
        ProfileDayInput(eventId: 'x', file: 'Days/x.fetproject', name: 'Day'),
      );
      expect(profile.days.single.trackId, isNull);
      expect(profile.tracks, isEmpty);
    });

    test('blank names fall back', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a', trackName: '  '));
      expect(profile.tracks.single.name, 'Track');
      profile = renameProfileTrack(profile, profile.tracks.single.id, ' Tor Poznań ');
      expect(profile.tracks.single.name, 'Tor Poznań');
      profile = renameProfileCar(profile, profile.cars.single.id, '');
      expect(profile.cars.single.name, 'My car');
    });

    test('setProfileDayCar ignores a car or day the profile does not have', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      expect(setProfileDayCar(profile, 'a', 'nope'), same(profile));
      expect(setProfileDayCar(profile, 'nope', profile.cars.single.id), same(profile));
    });
  });

  group('encode and decode', () {
    test('a profile reads back the same, and its tracks still match', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a', trackName: 'Jastrząb'));
      profile = _add(profile, _day('b', radius: 150));
      final read = decodeDriverProfile(encodeDriverProfile(profile));
      expect(read.driverId, profile.driverId);
      expect(read.lastCarId, profile.lastCarId);
      expect([for (final car in read.cars) car.name], ['My car']);
      expect([for (final track in read.tracks) track.name], ['Jastrząb', 'Track']);
      for (final (index, day) in read.days.indexed) {
        final original = profile.days[index];
        expect(day.eventId, original.eventId);
        expect(day.file, original.file);
        expect(day.carId, original.carId);
        expect(day.trackId, original.trackId);
        expect(day.startMilliseconds, original.startMilliseconds);
        expect(day.bestLapSeconds, original.bestLapSeconds);
        expect(
          [for (final s in day.sessions) (s.runId, s.lapCount, s.bestLapSeconds)],
          [for (final s in original.sessions) (s.runId, s.lapCount, s.bestLapSeconds)],
        );
      }
      for (final (index, track) in read.tracks.indexed) {
        expect(track.route.direction, profile.tracks[index].route.direction);
        expect(track.route.points, hasLength(routeShapePointCount));
        expect(routesMatch(track.route, profile.tracks[index].route), isTrue);
      }
      // A later day on the first circuit matches the track read back.
      final again = _add(read, _day('c'));
      expect(again.tracks, hasLength(2));
      expect(again.day('c')!.trackId, read.day('a')!.trackId);
      expect(
        encodeDriverProfile(decodeDriverProfile(encodeDriverProfile(read))),
        encodeDriverProfile(read),
      );
    });

    test('keys this version does not know are kept', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      json['future'] = {'x': 1};
      (json['driver'] as Map<String, Object?>)['photo'] = 'p.png';
      ((json['cars'] as List).single as Map<String, Object?>)['setup'] = [1, 2];
      ((json['tracks'] as List).single as Map<String, Object?>)['country'] = 'PL';
      (((json['tracks'] as List).single as Map<String, Object?>)['route']
              as Map<String, Object?>)['width'] =
          12;
      final day = (json['days'] as List).single as Map<String, Object?>;
      day['weather'] = 'dry';
      ((day['sessions'] as List).first as Map<String, Object?>)['tyres'] = 'new';
      final written = jsonDecode(encodeDriverProfile(decodeDriverProfile(jsonEncode(json))));
      expect(written, json);
    });

    test('a byte order mark is ignored', () {
      final profile = DriverProfile.empty(Random(1));
      expect(
        decodeDriverProfile('\uFEFF${encodeDriverProfile(profile)}').driverId,
        profile.driverId,
      );
    });

    test('an empty profile reads back', () {
      final profile = DriverProfile.empty(Random(1));
      final read = decodeDriverProfile(encodeDriverProfile(profile));
      expect(read.driverId, profile.driverId);
      expect(read.cars, isEmpty);
      expect(read.days, isEmpty);
      expect(read.lastCarId, isNull);
    });

    group('rejects', () {
      late Map<String, Object?> valid;
      setUp(() {
        final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
        valid = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      });
      Map<String, Object?> day() => (valid['days'] as List).single as Map<String, Object?>;
      Map<String, Object?> route() =>
          ((valid['tracks'] as List).single as Map<String, Object?>)['route']
              as Map<String, Object?>;
      void rejected(String text, [String reason = '']) => expect(
        () => decodeDriverProfile(text),
        throwsA(isA<ProfileFormatError>().having((e) => e.message, 'message', contains(reason))),
      );

      test('text that is not JSON or not a profile', () {
        rejected('{', 'not valid JSON');
        rejected('[]', 'not an object');
        rejected('{"format":"other","version":1}', 'not a FlappedEar driver profile');
      });
      test('a newer or missing version', () {
        valid['version'] = 2;
        rejected(jsonEncode(valid), 'newer version');
        expect(
          () => decodeDriverProfile(jsonEncode(valid)),
          throwsA(isA<ProfileFormatError>().having((e) => e.newerVersion, 'newerVersion', isTrue)),
        );
        valid['version'] = '1';
        rejected(jsonEncode(valid), 'no valid version');
      });
      test('a day naming a car or track that is not there', () {
        day()['carId'] = 'gone';
        rejected(jsonEncode(valid), 'names a car');
      });
      test('a day naming a missing track', () {
        day()['trackId'] = 'gone';
        rejected(jsonEncode(valid), 'names a track');
      });
      test('the same day twice', () {
        (valid['days'] as List).add(day());
        rejected(jsonEncode(valid), 'same day twice');
      });
      test('a route with the wrong number of points', () {
        (route()['points'] as List).removeLast();
        rejected(jsonEncode(valid), 'points');
      });
      test('a route with an impossible origin, length or direction', () {
        route()['origin'] = [91, 0];
        rejected(jsonEncode(valid), 'origin');
        route()['origin'] = [52, 21];
        route()['lengthMeters'] = 50;
        rejected(jsonEncode(valid), 'length');
        route()['lengthMeters'] = 600;
        route()['direction'] = 'sideways';
        rejected(jsonEncode(valid), 'direction');
      });
      test('wrong types and values', () {
        day()['startMilliseconds'] = 1.5;
        rejected(jsonEncode(valid), 'whole number');
        day()['startMilliseconds'] = null;
        day()['bestLapSeconds'] = -1;
        rejected(jsonEncode(valid), 'positive time');
        day()['bestLapSeconds'] = null;
        day()['name'] = 'a\u0000b';
        rejected(jsonEncode(valid), 'not valid text');
        day()['name'] = 'x';
        ((day()['sessions'] as List).first as Map<String, Object?>)['lapCount'] = -1;
        rejected(jsonEncode(valid), 'lap count');
      });
      test('too much', () {
        rejected(' ' * (maximumProfileCharacters + 1), 'too large');
        valid['cars'] = [
          for (var i = 0; i <= maximumProfileCars; ++i) {'id': 'c$i', 'name': 'Car'},
        ];
        rejected(jsonEncode(valid), 'too many cars');
      });
      test('unknown values nested too deeply', () {
        // Written by hand: encoding it here would overflow the stack too.
        final deep = '${'[' * 10000}${']' * 10000}';
        rejected(jsonEncode(valid).replaceFirst('{', '{"future":$deep,'), 'nests too deeply');
      });
      test('route points too far to write back', () {
        (route()['points'] as List)[0] = [1e308, 0];
        rejected(jsonEncode(valid), 'too far');
      });
      test('times a date cannot hold', () {
        day()['startMilliseconds'] = 9007199254740991;
        rejected(jsonEncode(valid), 'out of range');
      });
      test('a day file outside the profile', () {
        for (final file in [
          '../../x.fetproject',
          '/x.fetproject',
          r'\\server\x.fetproject',
          r'C:\x.fetproject',
          'C:x.fetproject',
          'Days//x.fetproject',
          'Days/./x.fetproject',
          'Days/.. /x.fetproject',
          'Days/x.fetproject.',
          'Days/x.fetproject ',
          '...',
          'x.fetproject:stream',
        ]) {
          day()['file'] = file;
          rejected(jsonEncode(valid), 'not inside the profile');
        }
        day()['file'] = r'Days\x.fetproject';
        expect(decodeDriverProfile(jsonEncode(valid)).days.single.file, r'Days\x.fetproject');
      });
      test('numbers too large to keep', () {
        final text = jsonEncode(valid).replaceFirst('{', '{"future":1e400,');
        rejected(text, 'too large to keep');
      });
      test('times a local date cannot be built for', () {
        day()['startMilliseconds'] = 8640000000000000;
        rejected(jsonEncode(valid), 'out of range');
        day()['startMilliseconds'] = -8640000000000000;
        rejected(jsonEncode(valid), 'out of range');
      });
      test('the same session twice', () {
        final sessions = day()['sessions'] as List;
        sessions.add(sessions.first);
        rejected(jsonEncode(valid), 'same session twice');
      });
    });
  });

  group('session weather', () {
    const warm = WeatherSummary(
      temperatureC: 21.4,
      temperatureMinC: 19.2,
      temperatureMaxC: 22.6,
      relativeHumidityPercent: 60,
      precipitationMm: 0.4,
      condition: WeatherCondition.rain,
      windSpeedKmh: 12.5,
      windDirectionDegrees: 225,
      windGustsKmh: 30,
    );
    Map<String, Object?> session(Map<String, Object?> json, [int index = 0]) =>
        ((((json['days'] as List).single as Map<String, Object?>)['sessions'] as List)[index])
            as Map<String, Object?>;

    test('is kept as stored, in °C, mm and km/h, and reads back', () {
      final profile = _add(
        DriverProfile.empty(Random(1)),
        _day('a', weather: {'run1': warm, 'run2': null}),
      );
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      expect(session(json)['weather'], {
        'sourceRevision': _runRevision(1),
        'temperatureC': 21.4,
        'temperatureMinC': 19.2,
        'temperatureMaxC': 22.6,
        'condition': WeatherCondition.rain.name,
        'precipitationMm': 0.4,
        'windSpeedKmh': 12.5,
        'windDirectionDegrees': 225.0,
      });
      expect(session(json, 1).containsKey('weather'), isFalse);
      final read = decodeDriverProfile(encodeDriverProfile(profile));
      final weather = read.day('a')!.sessions.first.weather!;
      expect(weather.temperatureC, 21.4);
      expect(weather.temperatureMinC, 19.2);
      expect(weather.temperatureMaxC, 22.6);
      expect(weather.condition, WeatherCondition.rain);
      expect(weather.precipitationMm, 0.4);
      expect(weather.windSpeedKmh, 12.5);
      expect(weather.windDirectionDegrees, 225);
      expect(read.day('a')!.sessions[1].weather, isNull);
      expect(encodeDriverProfile(read), encodeDriverProfile(profile));
    });

    test('a summary with none of the kept values is no weather', () {
      final day = _day('a', weather: {'run1': const WeatherSummary(relativeHumidityPercent: 50)});
      expect(day.sessions.first.weather, isNull);
    });

    test('out-of-range values are dropped, not refused', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      session(json)['weather'] = {
        'temperatureC': 61,
        'temperatureMinC': -91,
        'temperatureMaxC': 'warm',
        'condition': 'clear',
        'precipitationMm': -1,
        'windSpeedKmh': 501,
        'windDirectionDegrees': 360,
      };
      session(json, 1)['weather'] = {'temperatureC': 70, 'windSpeedKmh': -3};
      final read = decodeDriverProfile(jsonEncode(json));
      final weather = read.day('a')!.sessions.first.weather!;
      expect(weather.windDirectionDegrees, 360);
      expect(weather.condition, WeatherCondition.clear);
      expect([
        weather.temperatureC,
        weather.temperatureMinC,
        weather.temperatureMaxC,
        weather.precipitationMm,
        weather.windSpeedKmh,
      ], everyElement(isNull));
      // Nothing left: no weather.
      expect(read.day('a')!.sessions[1].weather, isNull);
      expect(
        session(jsonDecode(encodeDriverProfile(read)) as Map<String, Object?>, 1),
        isNot(contains('weather')),
      );
    });

    test('weather that is not an object is refused', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      session(json)['weather'] = 'dry';
      expect(() => decodeDriverProfile(jsonEncode(json)), throwsA(isA<ProfileFormatError>()));
    });

    test('a profile written before weather was kept reads without it', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      expect(session(json).containsKey('weather'), isFalse);
      expect(json['version'], 1);
      final read = decodeDriverProfile(jsonEncode(json));
      expect([for (final s in read.day('a')!.sessions) s.weather], [null, null]);
    });

    test('a session added again without weather keeps its weather', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a', weather: {'run1': warm}));
      profile = _add(profile, _day('a'));
      expect(profile.day('a')!.sessions.first.weather!.temperatureC, 21.4);
      expect(profile.day('a')!.sessions[1].weather, isNull);
      // New weather replaces it.
      profile = _add(profile, _day('a', weather: {'run1': const WeatherSummary(temperatureC: 15)}));
      expect(profile.day('a')!.sessions.first.weather!.temperatureC, 15);
      expect(profile.day('a')!.sessions.first.weather!.condition, isNull);
    });

    test('keys this version does not know are kept, also on re-adding', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a', weather: {'run1': warm}));
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      (session(json)['weather'] as Map<String, Object?>)['trackTemperatureC'] = 38;
      session(json, 1)['weather'] = {'visibilityKm': 10};
      final read = decodeDriverProfile(jsonEncode(json));
      expect(jsonDecode(encodeDriverProfile(read)), json);
      final again = _add(read, _day('a'));
      expect(jsonDecode(encodeDriverProfile(again)), json);
    });
  });

  group('session setup', () {
    const bar = {
      'version': runSetupVersion,
      'pressureUnit': 'bar',
      'coldPressure': {'fl': 2.1, 'fr': 2.1, 'rl': 2, 'rr': 2},
      'hotPressure': {'fl': 2.45, 'rr': 2.3},
      'tyre': 'Pirelli SC2',
      'fuelStartLitres': 8.5,
    };
    Map<String, Object?> session(Map<String, Object?> json, [int index = 0]) =>
        ((((json['days'] as List).single as Map<String, Object?>)['sessions'] as List)[index])
            as Map<String, Object?>;

    test('is kept as the run stores it and reads back', () {
      final profile = _add(
        DriverProfile.empty(Random(1)),
        _day('a', setups: {'run1': ProfileSetup.of(bar), 'run2': null}),
      );
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      expect(session(json)['setup'], bar);
      expect(session(json, 1).containsKey('setup'), isFalse);
      expect(json['version'], 1);
      final read = decodeDriverProfile(encodeDriverProfile(profile));
      final setup = read.day('a')!.sessions.first.setup!.setup;
      expect(setup.pressureUnit, PressureUnit.bar);
      expect(setup.cold, const WheelPressures(fl: 2.1, fr: 2.1, rl: 2, rr: 2));
      expect(setup.hot, const WheelPressures(fl: 2.45, rr: 2.3));
      expect(setup.tyre, 'Pirelli SC2');
      expect(setup.fuelStartLitres, 8.5);
      expect(read.day('a')!.sessions[1].setup, isNull);
      expect(encodeDriverProfile(read), encodeDriverProfile(profile));
    });

    test('a RunSetup is stored as the day stores it', () {
      final setup = RunSetup.fromJson(bar);
      expect(ProfileSetup.ofSetup(setup)!.json, bar);
      expect(ProfileSetup.ofSetup(setup)!.setup, setup);
      expect(ProfileSetup.ofSetup(const RunSetup()), isNull);
      expect(ProfileSetup.of({'version': runSetupVersion}), isNull);
      expect(ProfileSetup.of('bar'), isNull);
    });

    test('invalid values read as not entered and are not refused', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      session(json)['setup'] = {
        'version': runSetupVersion,
        'pressureUnit': 'bar',
        'coldPressure': {'fl': 9, 'fr': 'high', 'rl': 2.123, 'rr': 2},
        'hotPressure': 'warm',
        'tyre': 7,
        'fuelStartLitres': -1,
      };
      session(json, 1)['setup'] = 'slicks';
      final read = decodeDriverProfile(jsonEncode(json));
      final setup = read.day('a')!.sessions.first.setup!.setup;
      expect(setup.cold, const WheelPressures(rr: 2));
      expect(setup.hot.isEmpty, isTrue);
      expect(setup.tyre, '');
      expect(setup.fuelStartLitres, isNull);
      // Not an object: no setup, kept as it was.
      expect(read.day('a')!.sessions[1].setup, isNull);
      expect(jsonDecode(encodeDriverProfile(read)), json);
    });

    test('pressures without a unit are not entered', () {
      final setup = ProfileSetup.of({
        'coldPressure': {'fl': 2.1},
      })!;
      expect(setup.setup.cold.isEmpty, isTrue);
      expect(setup.setup.pressureUnit, isNull);
    });

    test('keys this version does not know are kept, also on re-adding', () {
      final profile = _add(
        DriverProfile.empty(Random(1)),
        _day('a', setups: {'run1': ProfileSetup.of(bar)}),
      );
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      final stored = session(json)['setup'] as Map<String, Object?>;
      stored['camber'] = {'fl': -2.5};
      (stored['coldPressure'] as Map<String, Object?>)['spare'] = 2.0;
      session(json, 1)['setup'] = {'version': 'session-setup-v9', 'wing': 3};
      final read = decodeDriverProfile(jsonEncode(json));
      expect(jsonDecode(encodeDriverProfile(read)), json);
      expect(read.day('a')!.sessions[1].setup!.setup.readOnly, isTrue);
      // Added again without setups (a day found in the days folder): kept.
      final again = _add(read, _day('a'));
      expect(jsonDecode(encodeDriverProfile(again)), json);
    });

    test('given setups replace the profile\'s, null clears, none given keeps', () {
      var profile = _add(
        DriverProfile.empty(Random(1)),
        _day('a', setups: {'run1': ProfileSetup.of(bar), 'run2': ProfileSetup.of(bar)}),
      );
      // Not given: kept.
      profile = _add(profile, _day('a'));
      expect([for (final s in profile.day('a')!.sessions) s.setup?.json], [bar, bar]);
      // Given: replaces; null and missing clear.
      const psi = {
        'version': runSetupVersion,
        'pressureUnit': 'psi',
        'coldPressure': {'fl': 30},
      };
      profile = _add(profile, _day('a', setups: {'run1': ProfileSetup.of(psi)}));
      expect(profile.day('a')!.sessions.first.setup!.json, psi);
      expect(profile.day('a')!.sessions[1].setup, isNull);
      profile = _add(profile, _day('a', setups: {'run1': null}));
      expect(profile.day('a')!.sessions.first.setup, isNull);
    });

    test('new weather, a replaced recording and new weather alone keep it', () {
      var profile = _add(
        DriverProfile.empty(Random(1)),
        _day('a', setups: {'run1': ProfileSetup.of(bar)}),
      );
      profile = _add(profile, _day('a', recordings: {'run1': _runRevision(9)}));
      expect(profile.day('a')!.sessions.first.setup!.json, bar);
      profile = setProfileSessionWeather(profile, 'a', {'run1': ProfileWeather(temperatureC: 12)});
      expect(profile.day('a')!.sessions.first.weather!.temperatureC, 12);
      expect(profile.day('a')!.sessions.first.setup!.json, bar);
      final withWeather = _day(
        'a',
        setups: {'run1': ProfileSetup.of(bar)},
      ).withWeather({'run1': ProfileWeather(temperatureC: 14)});
      expect(withWeather.setupsGiven, isTrue);
      expect(withWeather.sessions.first.setup!.json, bar);
    });

    test('merging another profile brings the setup along', () {
      final there = _add(
        DriverProfile.empty(Random(1)),
        _day('a', setups: {'run1': ProfileSetup.of(bar)}),
      );
      final merged = mergeDriverProfile(DriverProfile.empty(Random(2)), there);
      expect(merged.added, ['a']);
      expect(merged.profile.day('a')!.sessions.first.setup!.json, bar);
      expect(merged.profile.day('a')!.sessions[1].setup, isNull);
    });
  });

  group('session weather, kept per recording', () {
    const warm = WeatherSummary(temperatureC: 21.4, condition: WeatherCondition.overcast);
    Map<String, Object?> session(Map<String, Object?> json, [int index = 0]) =>
        ((((json['days'] as List).single as Map<String, Object?>)['sessions'] as List)[index])
            as Map<String, Object?>;

    test('a replaced recording drops the weather kept for the old one', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a', weather: {'run1': warm}));
      profile = _add(profile, _day('a', recordings: {'run1': _runRevision(9)}));
      expect(profile.day('a')!.sessions.first.weather, isNull);
    });

    test('weather without a recording kept is kept on re-adding', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      session(json)['weather'] = {'temperatureC': 12};
      final read = decodeDriverProfile(jsonEncode(json));
      final again = _add(read, _day('a', recordings: {'run1': _runRevision(9)}));
      expect(again.day('a')!.sessions.first.weather!.temperatureC, 12);
    });

    test('a condition of a newer version survives a re-save, read as unknown', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      session(json)['weather'] = {'temperatureC': 12, 'condition': 'sandstorm'};
      final read = decodeDriverProfile(jsonEncode(json));
      final weather = read.day('a')!.sessions.first.weather!;
      expect(weather.condition, isNull);
      expect(weather.hasUnknownCondition, isTrue);
      expect(jsonDecode(encodeDriverProfile(read)), json);
      // Only an unknown condition: still weather, still kept.
      session(json)['weather'] = {'condition': 'sandstorm'};
      expect(jsonDecode(encodeDriverProfile(decodeDriverProfile(jsonEncode(json)))), json);
    });

    test('setProfileSessionWeather swaps only the weather of known sessions', () {
      final profile = _add(DriverProfile.empty(Random(1)), _day('a'));
      final weather = ProfileWeather.of(warm, sourceRevision: _runRevision(1))!;
      final next = setProfileSessionWeather(profile, 'a', {'run1': weather, 'other': weather});
      final day = next.day('a')!;
      expect(day.sessions.first.weather!.temperatureC, 21.4);
      expect(day.sessions[1].weather, isNull);
      expect(
        [for (final s in day.sessions) (s.runId, s.lapCount, s.bestLapSeconds)],
        [for (final s in profile.day('a')!.sessions) (s.runId, s.lapCount, s.bestLapSeconds)],
      );
      // Nothing new, or a day not in the profile: the same profile.
      expect(identical(setProfileSessionWeather(next, 'a', {'run1': weather}), next), isTrue);
      expect(identical(setProfileSessionWeather(next, 'b', {'run1': weather}), next), isTrue);
      expect(
        decodeDriverProfile(encodeDriverProfile(next))
            .day('a')!
            .sessions
            .first
            .weather!
            .sourceRevision,
        _runRevision(1),
      );
    });
  });

  group('profileTree', () {
    DateTime utc(int milliseconds) =>
        DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

    test('groups days by car, year, track and date', () {
      var profile = _add(DriverProfile.empty(Random(1)), _day('a', trackName: 'Jastrząb'));
      profile = _add(profile, _day('b', start: 1756540800000)); // 2025-08-30, same circuit
      profile = _add(profile, _day('c', radius: 150, trackName: 'Poznań'));
      profile = _add(profile, _day('d', start: 1788076800000)); // 2026-08-30
      profile = addProfileCar(profile, 'Civic', random: Random(2));
      profile = setProfileDayCar(profile, 'd', profile.cars.last.id);
      profile = _add(
        profile,
        ProfileDayInput(eventId: 'e', file: 'Days/e.fetproject', name: 'Undated'),
      );

      final tree = profileTree(profile, localTime: utc);
      expect([for (final node in tree) node.car.name], ['My car', 'Civic']);
      final mine = tree.first;
      expect([for (final year in mine.years) year.year], [2025]);
      final tracks = mine.years.single.tracks;
      expect([for (final track in tracks) track.track?.name], ['Jastrząb', 'Poznań']);
      expect(
        [for (final date in tracks.first.dates) date.date],
        [DateTime(2025, 8, 30), DateTime(2025, 8, 29)],
      );
      expect(tracks.last.dates.single.days.single.eventId, 'c');
      final civic = tree.last;
      expect([for (final year in civic.years) year.year], [2026, null]);
      expect(civic.years.first.tracks.single.track?.name, 'Jastrząb');
      final undated = civic.years.last.tracks.single;
      expect(undated.track, isNull);
      expect(undated.dates.single.date, isNull);
      expect(undated.dates.single.days.single.eventId, 'e');
    });

    test('the earliest and latest times kept have a date in any time zone', () {
      final valid = jsonDecode(
        encodeDriverProfile(_add(DriverProfile.empty(Random(1)), _day('a'))),
      ) as Map<String, Object?>;
      final day = (valid['days'] as List).single as Map<String, Object?>;
      for (final time in [-8639999827200000, 8639999827200000]) {
        day['startMilliseconds'] = time;
        final profile = decodeDriverProfile(jsonEncode(valid));
        for (final hours in [-14, 14]) {
          final tree = profileTree(
            profile,
            localTime: (ms) =>
                DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(Duration(hours: hours)),
          );
          expect(tree.single.years.single.year, isNotNull);
        }
        expect(profileTree(profile).single.years.single.year, isNotNull);
      }
    });

    test('a car without days has no node', () {
      final profile = addProfileCar(DriverProfile.empty(Random(1)), 'Civic');
      expect(profileTree(profile), isEmpty);
    });
  });
}
