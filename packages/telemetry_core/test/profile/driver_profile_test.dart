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
          contentSha256: _revision.replaceFirst('a', '${index + 1}'),
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
  );
}

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
