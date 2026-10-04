import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'day_weather.dart';

/// Open-Meteo's credit, required next to its data (CC BY 4.0).
String weatherCredit(AppLocalizations l10n) => l10n.weatherCredit;

/// [condition] in words: "light rain" style, lower case.
String weatherConditionText(
  AppLocalizations l10n,
  WeatherCondition condition,
) => switch (condition) {
  WeatherCondition.clear => l10n.weatherClear,
  WeatherCondition.partlyCloudy => l10n.weatherPartlyCloudy,
  WeatherCondition.overcast => l10n.weatherOvercast,
  WeatherCondition.fog => l10n.weatherFog,
  WeatherCondition.drizzle => l10n.weatherDrizzle,
  WeatherCondition.rain => l10n.weatherRain,
  WeatherCondition.snow => l10n.weatherSnow,
  WeatherCondition.showers => l10n.weatherShowers,
  WeatherCondition.thunderstorm => l10n.weatherThunderstorm,
};

/// The 8-point compass name of a direction the wind comes from: "SW".
String compassPoint(double degrees) {
  const points = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return points[((degrees % 360) / 45).round() % 8];
}

String _whole(double value) => fixed(value, 0);

/// The air temperature: "21 °C", or "19–22 °C" when it changed by a degree
/// or more during the session.
String? weatherTemperatureText(AppLocalizations l10n, WeatherSummary summary) {
  final low = summary.temperatureMinC, high = summary.temperatureMaxC;
  if (low != null && high != null && high.round() - low.round() >= 1) {
    return l10n.weatherTemperatureRange(_whole(low), _whole(high));
  }
  final middle = summary.temperatureC ?? low;
  return middle == null ? null : l10n.weatherTemperature(_whole(middle));
}

/// The rain: "0.4 mm of rain", or "no rain" below 0.1 mm.
String? weatherPrecipitationText(
  AppLocalizations l10n,
  WeatherSummary summary,
) {
  final amount = summary.precipitationMm;
  if (amount == null) return null;
  return amount < 0.05
      ? l10n.weatherNoPrecipitation
      : l10n.weatherPrecipitation(fixed(amount, 1));
}

/// The wind: "wind SW 12 km/h".
String? weatherWindText(AppLocalizations l10n, WeatherSummary summary) {
  final speed = summary.windSpeedKmh;
  if (speed == null) return null;
  final direction = summary.windDirectionDegrees;
  return direction == null
      ? l10n.weatherWindNoDirection(_whole(speed))
      : l10n.weatherWind(compassPoint(direction), _whole(speed));
}

/// One short line of a session's weather: "21 °C, overcast, no rain, wind
/// SW 12 km/h", or null when the model had nothing.
String? weatherShortText(AppLocalizations l10n, SessionWeather weather) {
  final summary = weather.summary;
  final parts = [
    ?weatherTemperatureText(l10n, summary),
    if (summary.condition case final condition?)
      weatherConditionText(l10n, condition),
    ?weatherPrecipitationText(l10n, summary),
    ?weatherWindText(l10n, summary),
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

/// Every value of a session's weather, one per line.
List<String> weatherDetailLines(AppLocalizations l10n, SessionWeather weather) {
  final summary = weather.summary;
  return [
    if (weatherTemperatureText(l10n, summary) case final text?)
      l10n.weatherAirTemperature(text),
    if (summary.condition case final condition?)
      l10n.weatherSky(weatherConditionText(l10n, condition)),
    ?weatherPrecipitationText(l10n, summary),
    ?weatherWindText(l10n, summary),
    if (summary.windGustsKmh case final gusts?)
      l10n.weatherGusts(_whole(gusts)),
    if (summary.relativeHumidityPercent case final humidity?)
      l10n.weatherHumidity(_whole(humidity)),
    if (summary.cloudCoverPercent case final cloud?)
      l10n.weatherCloudCover(_whole(cloud)),
    if (summary.surfacePressureHpa case final pressure?)
      l10n.weatherPressure(_whole(pressure)),
  ];
}

/// A session's weather in its details: every value, where it comes from,
/// or why there is none.
class SessionWeatherSection extends StatelessWidget {
  const SessionWeatherSection({
    super.key,
    required this.weather,
    required this.runId,
  });

  final DayWeather weather;
  final String runId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: weather,
      builder: (context, _) {
        final shown = weather.of(runId);
        final state = weather.stateOf(runId);
        final small = theme.textTheme.bodySmall;
        return Column(
          key: const ValueKey('sessionWeather'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sessionDetailsWeather, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (shown != null) ...[
              for (final line in weatherDetailLines(l10n, shown))
                Text(line, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(l10n.weatherModelled, style: small),
              Text(weatherCredit(l10n), style: small),
            ] else
              Text(switch (state) {
                SessionWeatherState.fetching => l10n.weatherFetching,
                SessionWeatherState.off => l10n.weatherOff,
                SessionWeatherState.unavailable => l10n.weatherUnavailable,
                SessionWeatherState.kept => l10n.weatherKept,
                _ => l10n.weatherNone,
              }, style: small),
            if (shown == null && state == SessionWeatherState.unavailable)
              TextButton(
                key: const ValueKey('sessionWeatherRetry'),
                onPressed: () => weather.retry(runId),
                child: Text(l10n.weatherRetry),
              ),
          ],
        );
      },
    );
  }
}
