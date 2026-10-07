import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../day/weather_text.dart' show weatherConditionText;
import '../format.dart';
import '../l10n.dart';
import 'profile_page.dart' show profileDayDate;
import 'skill_levels_card.dart' show skillMeasureText;

/// The most days listed per track and car; the first-to-last figures still
/// cover every day.
const profileTrendDaysShown = 10;

/// [id]'s value as text: a time for `bestLap` and `typicalLap`, else the
/// skill's measure with its unit.
String _measureText(String id, double value) {
  if (id == 'bestLap' || id == 'typicalLap') return displayTime(value);
  final unit = skillCatalogue.firstWhere((skill) => skill.id == id).unit;
  return skillMeasureText(value, unit);
}

/// Each track in each car, day by day: lap times, the measures the profile
/// keeps per session, the weather kept, and each measure from its first day
/// to its last once there are enough days. Everything comes from
/// `profileTrends` (`telemetry_core`); this card only shows it.
class ProfileTrendsCard extends StatelessWidget {
  const ProfileTrendsCard({super.key, required this.profile});

  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final trends = profileTrends(profile);
    return Card(
      key: const ValueKey('profileTrends'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.profileTrends, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.profileTrendsIntro, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              l10n.profileTrendsWetDry,
              key: const ValueKey('profileTrendsWetDry'),
              style: theme.textTheme.bodySmall,
            ),
            if (trends.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.profileTracksNone),
              ),
            for (final trend in trends)
              _TrendGroup(profile: profile, trend: trend),
          ],
        ),
      ),
    );
  }
}

class _TrendGroup extends StatelessWidget {
  const _TrendGroup({required this.profile, required this.trend});

  final DriverProfile profile;
  final TrackTrend trend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final car =
        profile.cars.where((car) => car.id == trend.carId).firstOrNull?.name ??
        trend.carId;
    final key = '${trend.track.id} ${trend.carId}';
    final days = trend.days;
    final shown = days.length > profileTrendDaysShown
        ? days.sublist(days.length - profileTrendDaysShown)
        : days;
    final changes = trend.changes;
    return Padding(
      key: ValueKey('profileTrend $key'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profileTrendsGroup(
              trend.track.name,
              l10n.direction(trend.track.route.direction),
              car,
            ),
            style: theme.textTheme.bodyLarge,
          ),
          if (!trend.enoughDays)
            Text(
              l10n.profileTrendsTooFew(days.length, trendMinimumDays),
              key: ValueKey('profileTrendTooFew $key'),
              style: muted,
            ),
          if (shown.length < days.length)
            Text(
              l10n.profileTrendsShowingLast(shown.length, days.length),
              style: muted,
            ),
          for (final day in shown) _TrendDayTile(day: day),
          if (changes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.profileTrendsChanges,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final change in changes)
              Text(
                l10n.profileTrendsChange(
                  l10n.profileTrendsMeasure(change.measure),
                  _measureText(change.measure, change.first),
                  _measureText(change.measure, change.last),
                  change.days,
                ),
                key: ValueKey('profileTrendChange $key ${change.measure}'),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}

class _TrendDayTile extends StatelessWidget {
  const _TrendDayTile({required this.day});

  final TrendDay day;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final visit = day.visit;
    final times = [
      if (visit.bestLapSeconds case final best?)
        l10n.profileTrendsBestLap(displayTime(best)),
      if (day.personalBest) l10n.profileTrendsPersonalBest,
      if (visit.typicalLapSeconds case final typical?)
        l10n.profileTrendsTypicalLap(displayTime(typical)),
    ];
    final measures = [
      for (final id in trendMeasures)
        if (day.measures[id] case final value?)
          l10n.skillMeasured(id, _measureText(id, value)),
    ];
    final eventId = day.day.eventId;
    return Padding(
      key: ValueKey('profileTrendDay $eventId'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profileDayDate(context, day.day),
            style: theme.textTheme.labelLarge,
          ),
          Text(
            times.isEmpty ? l10n.profileTrendsNoLapTimes : times.join(' · '),
            key: ValueKey('profileTrendTimes $eventId'),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            measures.isEmpty
                ? l10n.profileTrendsNotMeasured
                : measures.join(' · '),
            key: ValueKey('profileTrendMeasures $eventId'),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            _weather(l10n, day.weather),
            key: ValueKey('profileTrendWeather $eventId'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// The model's conditions and the most rain of a session, or why none.
  static String _weather(AppLocalizations l10n, TrendWeather weather) {
    final rain = weather.precipitationMm;
    final parts = [
      for (final condition in weather.conditions)
        weatherConditionText(l10n, condition),
      if (rain != null)
        rain < 0.05
            ? l10n.weatherNoPrecipitation
            : l10n.profileTrendsRain(fixed(rain, 1)),
    ];
    return parts.isEmpty
        ? l10n.profileTrendsNoWeather
        : l10n.profileTrendsWeather(parts.join(', '));
  }
}
