import 'dart:io';
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

final _start = DateTime.utc(2026, 8, 29, 10, 20).millisecondsSinceEpoch;
const _hour = 3600 * 1000;

/// A dated session of [seconds] at the fixes given (synthetic, no real
/// recording).
TelemetrySession _session({
  List<(double, double)> fixes = const [(51.98321, 17.83467)],
  double seconds = 1500,
  int? start,
  bool westPositive = false,
}) {
  final steps = fixes.length > 1 ? fixes.length - 1 : 1;
  final times = [for (var i = 0; i < fixes.length; ++i) i * seconds / steps];
  TelemetryChannel channel(String name, List<double> values) => TelemetryChannel(
    name: name,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
  return TelemetrySession(
    duration: seconds,
    startTime: 0,
    metadata: {
      'firstTimestampMilliseconds': '${start ?? _start}',
      if (westPositive) 'gpsLongitudeConvention': 'west-positive',
    },
    channels: {
      'latitude': channel('latitude', [for (final fix in fixes) fix.$1]),
      'longitude': channel('longitude', [for (final fix in fixes) fix.$2]),
    },
    aliases: const {'latitude': 'latitude', 'longitude': 'longitude'},
    warnings: const [],
    timingGates: const [],
    sampleCount: fixes.length,
  );
}

/// Open-Meteo's answer for one day, hour by hour (made up).
Map<String, Object?> _answer({int hours = 24, Map<String, List<Object?>> overrides = const {}}) {
  final day = DateTime.utc(2026, 8, 29);
  List<Object?> series(double Function(int) value) => [for (var h = 0; h < hours; ++h) value(h)];
  return {
    'latitude': 51.98,
    'longitude': 17.83,
    'hourly': {
      'time': [
        for (var h = 0; h < hours; ++h)
          day.add(Duration(hours: h)).toIso8601String().substring(0, 16),
      ],
      'temperature_2m': series((h) => 10.0 + h),
      'relative_humidity_2m': series((h) => 50.0 + h),
      'precipitation': series((h) => h == 11 ? 0.4 : (h == 12 ? 0.2 : 0)),
      'weather_code': series((h) => h == 11 ? 61 : 3),
      'cloud_cover': series((h) => 4.0 * h),
      'surface_pressure': series((h) => 1000.0 + h),
      'wind_speed_10m': series((h) => 2.0 * h),
      'wind_direction_10m': series((h) => 10.0 * h),
      'wind_gusts_10m': series((h) => h == 12 ? 40 : 3.0 * h),
      ...overrides,
    },
  };
}

void main() {
  group('weatherRequest', () {
    test('asks for the first fix rounded to about 1 km and the session hours', () {
      final request = weatherRequest(
        _session(fixes: [(0, 0), (51.98321, 17.83467), (51.99, 17.9)]),
      )!;
      expect(request.latitude, 51.98);
      expect(request.longitude, 17.83);
      expect(request.startMilliseconds, _start);
      expect(request.endMilliseconds, _start + 1500 * 1000);
      expect(request.firstHour, DateTime.utc(2026, 8, 29, 10).millisecondsSinceEpoch);
      expect(request.lastHour, DateTime.utc(2026, 8, 29, 11).millisecondsSinceEpoch);
      final uri = request.openMeteoUri;
      expect(uri.host, 'archive-api.open-meteo.com');
      expect(uri.queryParameters['latitude'], '51.98');
      expect(uri.queryParameters['longitude'], '17.83');
      expect(uri.queryParameters['start_date'], '2026-08-29');
      expect(uri.queryParameters['end_date'], '2026-08-29');
      expect(uri.queryParameters['timezone'], 'GMT');
      // Nothing of the recording but the rounded position and the date.
      expect(uri.toString(), isNot(contains('51.983')));
    });

    test('turns a west-positive longitude east-positive', () {
      expect(weatherRequest(_session(fixes: [(51.5, 1.25)], westPositive: true))!.longitude, -1.25);
    });

    test('asks for the next day too when the session runs past midnight', () {
      final late = DateTime.utc(2026, 8, 29, 23, 40).millisecondsSinceEpoch;
      final uri = weatherRequest(_session(start: late))!.openMeteoUri;
      expect(uri.queryParameters['start_date'], '2026-08-29');
      expect(uri.queryParameters['end_date'], '2026-08-30');
    });

    test('nothing without a time, a fix, or for a recording over two days', () {
      final undated = TelemetrySession(
        duration: 10,
        startTime: 0,
        metadata: const {},
        channels: _session().channels,
        aliases: _session().aliases,
        warnings: const [],
        timingGates: const [],
        sampleCount: 1,
      );
      expect(weatherRequest(undated), isNull);
      expect(weatherRequest(_session(fixes: [(0, 0), (0, 0)])), isNull);
      expect(weatherRequest(_session(fixes: [(91, 0), (0, 0)])), isNull);
      expect(weatherRequest(_session(seconds: 48 * 3600)), isNull);
    });
  });

  group('sessionWeatherFromOpenMeteo', () {
    final request = weatherRequest(_session())!;

    test('keeps the hours around the session', () {
      final weather = sessionWeatherFromOpenMeteo(
        _answer(),
        request,
        sourceRevision: 'a' * 64,
        fetchedMilliseconds: _start + 5 * _hour,
      );
      expect(
        [for (final hour in weather.hours) hour.time],
        [request.firstHour, request.firstHour + _hour],
      );
      expect(weather.hours.first.temperatureC, 20);
      expect(weather.hours.last.weatherCode, 61);
      expect(weather.latitude, 51.98);
    });

    test('a value out of range or missing is no data', () {
      final weather = sessionWeatherFromOpenMeteo(
        _answer(
          overrides: {
            'temperature_2m': [for (var h = 0; h < 24; ++h) h == 10 ? 400 : null],
            'weather_code': [for (var h = 0; h < 24; ++h) h == 10 ? 2.5 : 3],
          },
        ),
        request,
        sourceRevision: 'a' * 64,
        fetchedMilliseconds: 0,
      );
      expect(weather.hours.first.temperatureC, isNull);
      expect(weather.hours.last.temperatureC, isNull);
      expect(weather.hours.first.weatherCode, isNull);
    });

    test('refuses an error, a short column or times out of order', () {
      Object? attempt(Object? json) {
        try {
          return sessionWeatherFromOpenMeteo(
            json,
            request,
            sourceRevision: 'a' * 64,
            fetchedMilliseconds: 0,
          );
        } on FormatException catch (error) {
          return error;
        }
      }

      expect(attempt({'error': true, 'reason': 'Too many requests'}), isA<FormatException>());
      expect(attempt([]), isA<FormatException>());
      expect(attempt({'hourly': <String, Object?>{}}), isA<FormatException>());
      expect(
        attempt(
          _answer(
            overrides: {
              'precipitation': [0],
            },
          ),
        ),
        isA<FormatException>(),
      );
      final reversed = _answer();
      final hourly = reversed['hourly']! as Map<String, Object?>;
      hourly['time'] = (hourly['time']! as List).reversed.toList();
      expect(attempt(reversed), isA<FormatException>());
    });
  });

  group('SessionWeather', () {
    final request = weatherRequest(_session())!;
    final weather = sessionWeatherFromOpenMeteo(
      _answer(),
      request,
      sourceRevision: 'b' * 64,
      fetchedMilliseconds: DateTime.utc(2026, 10, 4, 13).millisecondsSinceEpoch,
    );

    test('reads back what it stores', () {
      final json = fet.qtJsonDecode(fet.qtCompactJson(weather.toJson()));
      final read = SessionWeather.fromJson(json)!;
      expect(read.toJson(), weather.toJson());
      expect((json! as Map)['version'], sessionWeatherVersion);
    });

    test('ignores another version or a malformed entry', () {
      final json = weather.toJson();
      expect(SessionWeather.fromJson({...json, 'version': 'session-weather-v2'}), isNull);
      expect(SessionWeather.fromJson({...json, 'latitude': 'x'}), isNull);
      expect(SessionWeather.fromJson({...json, 'start': '2026-08-29T10:20:00'}), isNull);
      expect(SessionWeather.fromJson({...json, 'hours': 'x'}), isNull);
      expect(
        SessionWeather.fromJson({
          ...json,
          'hours': [for (var i = 0; i < maximumWeatherHours + 1; ++i) <String, Object?>{}],
        }),
        isNull,
      );
      final hours = (json['hours']! as List).reversed.toList();
      expect(SessionWeather.fromJson({...json, 'hours': hours}), isNull);
      expect(SessionWeather.fromJson(null), isNull);
    });

    test('summarises the session', () {
      // 10:20 to 10:45: the middle is 10:32:30.
      final summary = weather.summary;
      expect(summary.temperatureC, closeTo(20 + 32.5 / 60, 1e-9));
      expect(summary.temperatureMinC, closeTo(20 + 20 / 60, 1e-9));
      expect(summary.temperatureMaxC, closeTo(20 + 45 / 60, 1e-9));
      expect(summary.relativeHumidityPercent, closeTo(60 + 32.5 / 60, 1e-9));
      // Rain and gusts of the hour to 11:00, the hour the session ran in.
      expect(summary.precipitationMm, closeTo(0.4, 1e-9));
      expect(summary.windGustsKmh, 33);
      expect(summary.condition, WeatherCondition.rain);
      // The wind's direction of the hour nearest the middle, 11:00.
      expect(summary.windDirectionDegrees, 110);
      expect(summary.isEmpty, isFalse);
    });

    test('a session across hours takes rain and gusts of each', () {
      final long = weatherRequest(_session(seconds: 3600))!;
      final summary = sessionWeatherFromOpenMeteo(
        _answer(),
        long,
        sourceRevision: 'b' * 64,
        fetchedMilliseconds: 0,
      ).summary;
      expect(summary.precipitationMm, closeTo(0.6, 1e-9));
      expect(summary.windGustsKmh, 40);
      expect(summary.temperatureMinC, closeTo(20 + 20 / 60, 1e-9));
      expect(summary.temperatureMaxC, closeTo(21 + 20 / 60, 1e-9));
    });

    test('no data reads as empty', () {
      final empty = SessionWeather(
        sourceRevision: 'c' * 64,
        latitude: 1,
        longitude: 2,
        startMilliseconds: _start,
        endMilliseconds: _start + 60000,
        fetchedMilliseconds: _start,
        hours: [WeatherHour(time: _start - _start % _hour)],
      ).summary;
      expect(empty.isEmpty, isTrue);
    });
  });

  test('WMO codes read as conditions', () {
    expect(WeatherCondition.ofCode(0), WeatherCondition.clear);
    expect(WeatherCondition.ofCode(2), WeatherCondition.partlyCloudy);
    expect(WeatherCondition.ofCode(3), WeatherCondition.overcast);
    expect(WeatherCondition.ofCode(48), WeatherCondition.fog);
    expect(WeatherCondition.ofCode(53), WeatherCondition.drizzle);
    expect(WeatherCondition.ofCode(65), WeatherCondition.rain);
    expect(WeatherCondition.ofCode(75), WeatherCondition.snow);
    expect(WeatherCondition.ofCode(86), WeatherCondition.snow);
    expect(WeatherCondition.ofCode(81), WeatherCondition.showers);
    expect(WeatherCondition.ofCode(99), WeatherCondition.thunderstorm);
    expect(WeatherCondition.ofCode(4), isNull);
  });

  group('a day', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('session_weather'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('saves each run\'s weather, keeps it on a later save and opens it again', () async {
      final root = directory.resolveSymbolicLinksSync();
      final a = p.join(root, 'a.vbo');
      final b = p.join(root, 'b.vbo');
      File(a).writeAsStringSync(circuitVbo([30, 28, 31]));
      File(b).writeAsStringSync(circuitVbo([29, 32]));
      final runs = nameRunsInRecordingOrder(prepareTelemetryImport([a, b]).runs);
      final analysis = analyzeDay([
        for (final named in runs)
          DayRunInput(
            runId: named.run.id,
            name: named.name,
            contentSha256: named.run.contentSha256,
            session: named.run.telemetry,
            laps: named.run.laps,
          ),
      ]);
      final first = runs.first.run.id;
      final weather = sessionWeatherFromOpenMeteo(
        _answer(),
        weatherRequest(_session())!,
        sourceRevision: runs.first.run.contentSha256,
        fetchedMilliseconds: 0,
      );
      final path = p.join(root, 'day.fetproject');
      final document = dayDocument(
        eventId: newEventId(),
        name: 'Day',
        runs: runs,
        analysis: analysis,
        projectPath: path,
        weather: {first: weather},
      );
      expect(fet.validateFetproject(document), isNull);
      await saveDayDocument(path, document);
      Map<String, Object?> run(Map<String, Object?> document, bool firstRun) =>
          ((document['event']! as Map)['runs']! as List).firstWhere(
            (run) => ((run as Map)['id'] == first) == firstRun,
          ) as Map<String, Object?>;
      final opened = openDay(path);
      expect(
        SessionWeather.fromJson(run(opened.document, true)[sessionWeatherKey])?.toJson(),
        weather.toJson(),
      );
      expect(run(opened.document, false).containsKey(sessionWeatherKey), isFalse);
      // Saved again without new weather, the stored one stays.
      final again = dayDocument(
        eventId: opened.eventId,
        name: opened.name,
        runs: opened.runs,
        analysis: opened.analysis!,
        projectPath: path,
        previous: opened.document,
        previousPath: path,
      );
      expect(
        SessionWeather.fromJson(run(again, true)[sessionWeatherKey])?.toJson(),
        weather.toJson(),
      );
    });
  });
}
