// The weather at the track during a session: a weather model's hourly
// history for the session's place and time, fetched once and kept with the
// day as the session's `weather` (an open run object, which FlappedEar
// Overlays keeps as it is). It is modelled for a grid cell around the track,
// not measured there: no track temperature, and no claim that the track was
// wet.
import 'dart:math' as math;

import '../geometry.dart';
import '../intake/import_plan.dart' show recordingTimestamp;
import '../telemetry_session.dart';

/// The version of a session's stored weather.
const sessionWeatherVersion = 'session-weather-v1';

/// The run key the weather is stored under.
const sessionWeatherKey = 'weather';

/// The weather service, Open-Meteo's historical weather API (CC BY 4.0).
const openMeteoProvider = 'open-meteo-archive';

/// The most hours a session's weather holds; a longer recording gets none.
const maximumWeatherHours = 48;

/// Decimal places the position is rounded to before it leaves the device:
/// 0.01° is about 1 km, finer than the weather model's grid.
const weatherPositionDecimals = 2;

const _hour = 3600 * 1000;

/// Open-Meteo's hourly variables, in the order they are asked for.
const _openMeteoHourly = [
  'temperature_2m',
  'relative_humidity_2m',
  'precipitation',
  'weather_code',
  'cloud_cover',
  'surface_pressure',
  'wind_speed_10m',
  'wind_direction_10m',
  'wind_gusts_10m',
];

/// Where and when a session's weather is asked for.
final class WeatherRequest {
  const WeatherRequest({
    required this.latitude,
    required this.longitude,
    required this.startMilliseconds,
    required this.endMilliseconds,
  });

  /// The session's first GPS fix, rounded to [weatherPositionDecimals].
  final double latitude, longitude;

  /// The session's start and end, UTC milliseconds since the epoch.
  final int startMilliseconds, endMilliseconds;

  /// The first hour kept: the one at or before the start.
  int get firstHour => startMilliseconds - startMilliseconds % _hour;

  /// The last hour kept: the one after the end, whose rain fell during the
  /// hour the session ended in.
  int get lastHour => endMilliseconds - endMilliseconds % _hour + _hour;

  /// The Open-Meteo request: only the rounded position and the dates.
  Uri get openMeteoUri {
    String date(int milliseconds) => DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).toIso8601String().substring(0, 10);
    return Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': latitude.toStringAsFixed(weatherPositionDecimals),
      'longitude': longitude.toStringAsFixed(weatherPositionDecimals),
      'start_date': date(firstHour),
      'end_date': date(lastHour),
      'hourly': _openMeteoHourly.join(','),
      'timezone': 'GMT',
    });
  }
}

double _round(double value) {
  final scale = math.pow(10, weatherPositionDecimals);
  return (value * scale).round() / scale;
}

/// What to ask for [session]'s weather, or null when it has no recording
/// time or no GPS fix, or is longer than [maximumWeatherHours].
WeatherRequest? weatherRequest(TelemetrySession session) {
  final start = recordingTimestamp(session);
  if (start == null || !session.duration.isFinite || session.duration < 0) return null;
  final end = start + (session.duration * 1000).round();
  final latitude = session.channel('latitude');
  final longitude = session.channel('longitude');
  if (latitude == null || longitude == null) return null;
  final westPositive = session.metadata['gpsLongitudeConvention'] == 'west-positive';
  GeoCoordinate? fix;
  for (var index = 0; index < latitude.values.length; ++index) {
    final time = latitude.timestamps[index];
    final lon = session.valueAt('longitude', time);
    if (lon == null) continue;
    final candidate = GeoCoordinate(latitude.values[index].toDouble(), westPositive ? -lon : lon);
    // A receiver without a fix reports 0, 0.
    if (isValidCoordinate(candidate) &&
        (candidate.latitudeDegrees != 0 || candidate.longitudeDegrees != 0)) {
      fix = candidate;
      break;
    }
  }
  if (fix == null) return null;
  final request = WeatherRequest(
    latitude: _round(fix.latitudeDegrees),
    longitude: _round(fix.longitudeDegrees),
    startMilliseconds: start,
    endMilliseconds: end,
  );
  if ((request.lastHour - request.firstHour) ~/ _hour + 1 > maximumWeatherHours) return null;
  return request;
}

/// One hour of the weather model: the instant values at [time], and the
/// rain, the strongest gust and the weather of the hour before it. Null is
/// "no data".
final class WeatherHour {
  const WeatherHour({
    required this.time,
    this.temperatureC,
    this.relativeHumidityPercent,
    this.precipitationMm,
    this.weatherCode,
    this.cloudCoverPercent,
    this.surfacePressureHpa,
    this.windSpeedKmh,
    this.windDirectionDegrees,
    this.windGustsKmh,
  });

  /// UTC milliseconds since the epoch, on the hour.
  final int time;
  final double? temperatureC;
  final double? relativeHumidityPercent;
  final double? precipitationMm;

  /// The WMO weather code (0 clear … 99 thunderstorm with hail).
  final int? weatherCode;
  final double? cloudCoverPercent;
  final double? surfacePressureHpa;
  final double? windSpeedKmh;

  /// Where the wind comes from, degrees clockwise from north.
  final double? windDirectionDegrees;
  final double? windGustsKmh;
}

// The stored keys with the range a value must be in, else it is no data.
const _ranges = <String, (double, double)>{
  'temperatureC': (-90, 60),
  'relativeHumidityPercent': (0, 100),
  'precipitationMm': (0, 500),
  'cloudCoverPercent': (0, 100),
  'surfacePressureHpa': (300, 1100),
  'windSpeedKmh': (0, 500),
  'windDirectionDegrees': (0, 360),
  'windGustsKmh': (0, 500),
};

double? _value(Object? value, String key) {
  if (value is! num) return null;
  final number = value.toDouble();
  final (low, high) = _ranges[key]!;
  return number.isFinite && number >= low && number <= high ? number : null;
}

int? _code(Object? value) {
  if (value is! num || !value.isFinite || value != value.roundToDouble()) return null;
  final code = value.toInt();
  return code >= 0 && code <= 99 ? code : null;
}

int? _time(Object? value) {
  if (value is! String || value.length > 40) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) return null;
  final milliseconds = parsed.millisecondsSinceEpoch;
  return milliseconds % _hour == 0 ? milliseconds : null;
}

String _timeText(int milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true).toIso8601String();

/// A session's weather as kept with the day.
final class SessionWeather {
  SessionWeather({
    required this.sourceRevision,
    required this.latitude,
    required this.longitude,
    required this.startMilliseconds,
    required this.endMilliseconds,
    required this.fetchedMilliseconds,
    required List<WeatherHour> hours,
    this.provider = openMeteoProvider,
  }) : hours = List.unmodifiable(hours);

  /// The SHA-256 of the recording it was fetched for: a session whose
  /// recording is replaced has its weather fetched again.
  final String sourceRevision;
  final String provider;
  final double latitude, longitude;
  final int startMilliseconds, endMilliseconds;
  final int fetchedMilliseconds;

  /// In time order, one per hour.
  final List<WeatherHour> hours;

  /// The stored form (`event.runs[].weather`).
  Map<String, Object?> toJson() => {
    'version': sessionWeatherVersion,
    'provider': provider,
    'sourceRevision': sourceRevision,
    'latitude': latitude,
    'longitude': longitude,
    'start': _timeText(startMilliseconds),
    'end': _timeText(endMilliseconds),
    'fetchedAt': _timeText(fetchedMilliseconds),
    'hours': [
      for (final hour in hours)
        {
          'time': _timeText(hour.time),
          'temperatureC': hour.temperatureC,
          'relativeHumidityPercent': hour.relativeHumidityPercent,
          'precipitationMm': hour.precipitationMm,
          'weatherCode': hour.weatherCode,
          'cloudCoverPercent': hour.cloudCoverPercent,
          'surfacePressureHpa': hour.surfacePressureHpa,
          'windSpeedKmh': hour.windSpeedKmh,
          'windDirectionDegrees': hour.windDirectionDegrees,
          'windGustsKmh': hour.windGustsKmh,
        },
    ],
  };

  /// The weather stored in a run, or null when there is none or it is not
  /// one this app reads (another version, or malformed). A value out of its
  /// range reads as no data.
  static SessionWeather? fromJson(Object? value) {
    if (value is! Map<String, Object?> || value['version'] != sessionWeatherVersion) return null;
    final revision = value['sourceRevision'];
    final provider = value['provider'];
    final latitude = value['latitude'], longitude = value['longitude'];
    final start = _parse(value['start']);
    final end = _parse(value['end']);
    final fetched = _parse(value['fetchedAt']);
    final list = value['hours'];
    if (revision is! String ||
        revision.length > 128 ||
        provider is! String ||
        provider.length > 128 ||
        latitude is! num ||
        longitude is! num ||
        !isValidCoordinate(GeoCoordinate(latitude.toDouble(), longitude.toDouble())) ||
        start == null ||
        end == null ||
        end < start ||
        fetched == null ||
        list is! List ||
        list.length > maximumWeatherHours) {
      return null;
    }
    final hours = <WeatherHour>[];
    for (final entry in list) {
      if (entry is! Map<String, Object?>) return null;
      final time = _time(entry['time']);
      if (time == null || (hours.isNotEmpty && time <= hours.last.time)) return null;
      hours.add(
        WeatherHour(
          time: time,
          temperatureC: _value(entry['temperatureC'], 'temperatureC'),
          relativeHumidityPercent: _value(
            entry['relativeHumidityPercent'],
            'relativeHumidityPercent',
          ),
          precipitationMm: _value(entry['precipitationMm'], 'precipitationMm'),
          weatherCode: _code(entry['weatherCode']),
          cloudCoverPercent: _value(entry['cloudCoverPercent'], 'cloudCoverPercent'),
          surfacePressureHpa: _value(entry['surfacePressureHpa'], 'surfacePressureHpa'),
          windSpeedKmh: _value(entry['windSpeedKmh'], 'windSpeedKmh'),
          windDirectionDegrees: _value(entry['windDirectionDegrees'], 'windDirectionDegrees'),
          windGustsKmh: _value(entry['windGustsKmh'], 'windGustsKmh'),
        ),
      );
    }
    return SessionWeather(
      sourceRevision: revision,
      provider: provider,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      startMilliseconds: start,
      endMilliseconds: end,
      fetchedMilliseconds: fetched,
      hours: hours,
    );
  }

  /// The weather during the session.
  WeatherSummary get summary => WeatherSummary._of(this);
}

int? _parse(Object? value) {
  if (value is! String || value.length > 40) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null || !parsed.isUtc ? null : parsed.millisecondsSinceEpoch;
}

/// What the WMO weather code says, coarsely.
enum WeatherCondition {
  clear,
  partlyCloudy,
  overcast,
  fog,
  drizzle,
  rain,
  snow,
  showers,
  thunderstorm;

  /// [code]'s condition, or null for a code the WMO table does not use for
  /// weather models.
  static WeatherCondition? ofCode(int code) => switch (code) {
    0 => clear,
    1 || 2 => partlyCloudy,
    3 => overcast,
    45 || 48 => fog,
    >= 51 && <= 57 => drizzle,
    >= 61 && <= 67 => rain,
    >= 71 && <= 77 || 85 || 86 => snow,
    >= 80 && <= 82 => showers,
    >= 95 && <= 99 => thunderstorm,
    _ => null,
  };
}

/// The weather during a session: instant values at its middle, the air
/// temperature's range from start to end, and the rain, strongest gust and
/// worst weather of the hours it ran in. Null is "no data".
final class WeatherSummary {
  const WeatherSummary({
    this.temperatureC,
    this.temperatureMinC,
    this.temperatureMaxC,
    this.relativeHumidityPercent,
    this.precipitationMm,
    this.condition,
    this.cloudCoverPercent,
    this.surfacePressureHpa,
    this.windSpeedKmh,
    this.windDirectionDegrees,
    this.windGustsKmh,
  });

  factory WeatherSummary._of(SessionWeather weather) {
    final hours = weather.hours;
    final start = weather.startMilliseconds, end = weather.endMilliseconds;
    final middle = start + (end - start) ~/ 2;

    // [read] at [time], linear between the hours either side, or the hour
    // itself; no data when a neighbour has none.
    double? at(int time, double? Function(WeatherHour) read) {
      for (var index = 0; index < hours.length; ++index) {
        final hour = hours[index];
        if (hour.time == time) return read(hour);
        if (hour.time > time) {
          if (index == 0) return null;
          final before = hours[index - 1];
          final a = read(before), b = read(hour);
          if (a == null || b == null || hour.time - before.time != _hour) return null;
          return a + (b - a) * (time - before.time) / _hour;
        }
      }
      return null;
    }

    // The hours whose hour before overlaps the session.
    final during = [
      for (final hour in hours)
        if (hour.time > start && hour.time - _hour < (end > start ? end : start + 1)) hour,
    ];
    double? total(double? Function(WeatherHour) read) {
      final values = [for (final hour in during) ?read(hour)];
      return values.isEmpty ? null : values.fold<double>(0, (sum, value) => sum + value);
    }

    double? maximum(double? Function(WeatherHour) read) {
      final values = [for (final hour in during) ?read(hour)];
      return values.isEmpty ? null : values.reduce(math.max);
    }

    final temperatures = [
      ?at(start, (hour) => hour.temperatureC),
      ?at(end, (hour) => hour.temperatureC),
      for (final hour in hours)
        if (hour.time > start && hour.time < end) ?hour.temperatureC,
    ];
    final codes = [for (final hour in during) ?hour.weatherCode];
    // The worst weather: higher WMO codes are heavier weather.
    WeatherCondition? condition;
    if (codes.isNotEmpty) condition = WeatherCondition.ofCode(codes.reduce(math.max));
    WeatherHour? nearest;
    for (final hour in hours) {
      if (nearest == null || (hour.time - middle).abs() < (nearest.time - middle).abs()) {
        nearest = hour;
      }
    }
    return WeatherSummary(
      temperatureC: at(middle, (hour) => hour.temperatureC),
      temperatureMinC: temperatures.isEmpty ? null : temperatures.reduce(math.min),
      temperatureMaxC: temperatures.isEmpty ? null : temperatures.reduce(math.max),
      relativeHumidityPercent: at(middle, (hour) => hour.relativeHumidityPercent),
      precipitationMm: total((hour) => hour.precipitationMm),
      condition: condition,
      cloudCoverPercent: at(middle, (hour) => hour.cloudCoverPercent),
      surfacePressureHpa: at(middle, (hour) => hour.surfacePressureHpa),
      windSpeedKmh: at(middle, (hour) => hour.windSpeedKmh),
      // Directions are not interpolated (359° and 1° would average to 180°).
      windDirectionDegrees: nearest != null && (nearest.time - middle).abs() <= _hour ~/ 2
          ? nearest.windDirectionDegrees
          : null,
      windGustsKmh: maximum((hour) => hour.windGustsKmh),
    );
  }

  final double? temperatureC, temperatureMinC, temperatureMaxC;
  final double? relativeHumidityPercent;

  /// Rain (and melted snow) over the hours the session ran in, in mm.
  final double? precipitationMm;
  final WeatherCondition? condition;
  final double? cloudCoverPercent;
  final double? surfacePressureHpa;
  final double? windSpeedKmh;
  final double? windDirectionDegrees;

  /// The strongest gust in the hours the session ran in.
  final double? windGustsKmh;

  /// True when the model had nothing for the session.
  bool get isEmpty =>
      temperatureC == null &&
      temperatureMinC == null &&
      relativeHumidityPercent == null &&
      precipitationMm == null &&
      condition == null &&
      cloudCoverPercent == null &&
      surfacePressureHpa == null &&
      windSpeedKmh == null &&
      windGustsKmh == null;
}

/// The longest Open-Meteo answer read, in characters.
const maximumOpenMeteoCharacters = 256 * 1024;

/// [request]'s weather from Open-Meteo's answer [json] (decoded), for the
/// recording [sourceRevision], fetched at [fetchedMilliseconds]: the hours
/// from [WeatherRequest.firstHour] to [WeatherRequest.lastHour]. Throws a
/// [FormatException] for an answer that is not Open-Meteo's hourly table.
SessionWeather sessionWeatherFromOpenMeteo(
  Object? json,
  WeatherRequest request, {
  required String sourceRevision,
  required int fetchedMilliseconds,
}) {
  if (json is! Map<String, Object?>) throw const FormatException('Not a JSON object.');
  if (json['error'] == true) {
    final reason = json['reason'];
    throw FormatException('The weather service refused: ${reason is String ? reason : ''}');
  }
  final hourly = json['hourly'];
  if (hourly is! Map<String, Object?>) throw const FormatException('No hourly weather.');
  final times = hourly['time'];
  if (times is! List || times.length > 24 * 4) {
    throw const FormatException('The hourly times are missing or too many.');
  }
  List<Object?> column(String name) {
    final values = hourly[name];
    if (values is! List || values.length != times.length) {
      throw FormatException('The hourly $name is missing or has the wrong length.');
    }
    return values;
  }

  final columns = {for (final name in _openMeteoHourly) name: column(name)};
  final hours = <WeatherHour>[];
  for (var index = 0; index < times.length; ++index) {
    final text = times[index];
    // GMT times without a zone ("2026-08-29T10:00").
    final time = text is String && text.length <= 20 ? _time('${text}Z') : null;
    if (time == null || (hours.isNotEmpty && time <= hours.last.time)) {
      throw const FormatException('The hourly times are malformed or out of order.');
    }
    if (time < request.firstHour || time > request.lastHour) continue;
    Object? cell(String name) => columns[name]![index];
    hours.add(
      WeatherHour(
        time: time,
        temperatureC: _value(cell('temperature_2m'), 'temperatureC'),
        relativeHumidityPercent: _value(cell('relative_humidity_2m'), 'relativeHumidityPercent'),
        precipitationMm: _value(cell('precipitation'), 'precipitationMm'),
        weatherCode: _code(cell('weather_code')),
        cloudCoverPercent: _value(cell('cloud_cover'), 'cloudCoverPercent'),
        surfacePressureHpa: _value(cell('surface_pressure'), 'surfacePressureHpa'),
        windSpeedKmh: _value(cell('wind_speed_10m'), 'windSpeedKmh'),
        windDirectionDegrees: _value(cell('wind_direction_10m'), 'windDirectionDegrees'),
        windGustsKmh: _value(cell('wind_gusts_10m'), 'windGustsKmh'),
      ),
    );
  }
  return SessionWeather(
    sourceRevision: sourceRevision,
    latitude: request.latitude,
    longitude: request.longitude,
    startMilliseconds: request.startMilliseconds,
    endMilliseconds: request.endMilliseconds,
    fetchedMilliseconds: fetchedMilliseconds,
    hours: hours,
  );
}
