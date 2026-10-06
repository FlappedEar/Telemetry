import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../day/day_weather.dart';
import '../day/setup_text.dart';
import '../day/weather_text.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import 'profile_library.dart';

/// "Last time here": the previous visit to the open day's track, from the
/// driver profile, with its best lap, theoretical best, weather and setup
/// next to today's.
/// The same car first, else any car. Nothing is shown on a first visit, for
/// a day outside the library, or before the day is in the profile.
class LastTimeHereCard extends StatelessWidget {
  const LastTimeHereCard({
    super.key,
    required this.library,
    required this.eventId,
    this.weatherStateOf,
    this.weatherChanges,
    this.setupUnsavedOf,
  });

  final ProfileLibrary library;

  /// The open day's `event.id`.
  final String eventId;

  /// Where the open day's weather of a session is ([DayWeather.stateOf]),
  /// to say why today has none in the library yet; nothing is looked up
  /// here. [weatherChanges] tells when it changes.
  final SessionWeatherState Function(String runId)? weatherStateOf;
  final Listenable? weatherChanges;

  /// Whether the open day's setup of a session was edited and not saved
  /// yet, so it is in the day document but not in the library, which has
  /// the setups as the day was saved.
  final bool Function(String runId)? setupUnsavedOf;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([library, ?weatherChanges]),
    builder: (context, _) {
      final profile = library.profile;
      final today = profile?.days
          .where((day) => day.eventId == eventId)
          .firstOrNull;
      final trackId = today?.trackId;
      if (profile == null || today == null || trackId == null) {
        return const SizedBox.shrink();
      }
      final last = lastTimeHere(
        profile,
        trackId,
        carId: today.carId,
        beforeEventId: eventId,
      );
      if (last == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _card(context, profile, today, last.day),
      );
    },
  );

  Widget _card(
    BuildContext context,
    DriverProfile profile,
    ProfileDay today,
    ProfileDay then,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final start = then.startMilliseconds;
    final date = start == null
        ? l10n.profileUndated
        : DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(start));
    final car = then.carId == today.carId
        ? null
        : profile.car(then.carId)?.name;
    return Card(
      key: const ValueKey('lastTimeHere'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.lastTimeHereTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              [date, then.name, ?car].join(' · '),
              key: const ValueKey('lastTimeHereVisit'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _row(
              context,
              const ValueKey('lastTimeHereBest'),
              l10n.lastTimeHereBestLap,
              then.bestLapSeconds,
              today.bestLapSeconds,
            ),
            _row(
              context,
              const ValueKey('lastTimeHereTheoretical'),
              l10n.lastTimeHereTheoreticalBest,
              then.theoreticalBestSeconds,
              today.theoreticalBestSeconds,
            ),
            const SizedBox(height: 4),
            if ([
              then.bestLapSeconds,
              today.bestLapSeconds,
              then.theoreticalBestSeconds,
              today.theoreticalBestSeconds,
            ].contains(null))
              Text(
                l10n.lastTimeHereMissing,
                key: const ValueKey('lastTimeHereMissing'),
                style: theme.textTheme.bodySmall,
              ),
            Text(l10n.lastTimeHereNote, style: theme.textTheme.bodySmall),
            if (car != null)
              Text(l10n.lastTimeHereOtherCar, style: theme.textTheme.bodySmall),
            ..._weather(context, today, then),
            ..._setup(context, today, then),
            ..._corners(context, profile, today, then),
          ],
        ),
      ),
    );
  }

  /// The weather of each visit, kept in the profile with its sessions:
  /// nothing is looked up here. Today without weather in the library says
  /// why from the page's weather.
  List<Widget> _weather(
    BuildContext context,
    ProfileDay today,
    ProfileDay then,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final thenWeather = _weatherOf(l10n, then);
    final todayWeather = _weatherOf(l10n, today);
    final small = theme.textTheme.bodySmall;
    return [
      const SizedBox(height: 8),
      Text(
        l10n.lastTimeHereWeather,
        key: const ValueKey('lastTimeHereWeather'),
        style: theme.textTheme.labelLarge,
      ),
      Text(
        thenWeather == null
            ? l10n.lastTimeHereWeatherThenNone
            : l10n.lastTimeHereWeatherThen(thenWeather.$1, thenWeather.$2),
        key: const ValueKey('lastTimeHereWeatherThen'),
        style: thenWeather == null ? small : theme.textTheme.bodyMedium,
      ),
      Text(
        todayWeather == null
            ? _todayMissing(l10n, today)
            : l10n.lastTimeHereWeatherToday(todayWeather.$1, todayWeather.$2),
        key: const ValueKey('lastTimeHereWeatherToday'),
        style: todayWeather == null ? small : theme.textTheme.bodyMedium,
      ),
      if (thenWeather != null || todayWeather != null) ...[
        const SizedBox(height: 4),
        Text(l10n.lastTimeHereWeatherNote, style: small),
        Text(
          '${l10n.weatherModelled} ${weatherCredit(l10n)}',
          key: const ValueKey('lastTimeHereWeatherCredit'),
          style: small,
        ),
      ],
    ];
  }

  /// The session that set [day]'s best lap, if any matches.
  static ProfileSession? _bestLapSession(ProfileDay day) {
    final best = day.bestLapSeconds;
    return best == null
        ? null
        : day.sessions
              .where((session) => session.bestLapSeconds == best)
              .firstOrNull;
  }

  /// The weather in words, or null when there is none to say.
  static String? _weatherText(AppLocalizations l10n, ProfileWeather weather) {
    final parts = [
      ?weatherSummaryShortText(l10n, weather.summary),
      if (weather.hasUnknownCondition) l10n.lastTimeHereWeatherUnknownCondition,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// The session standing for [day] with what [value] finds of it, and
  /// its label: the session that set its best lap when [value] finds
  /// something there, else its first session where it does, labelled as
  /// which ([bestHadNone] or [firstSession]); null when none has.
  static (String, ProfileSession, T)? _standingSession<T extends Object>(
    AppLocalizations l10n,
    ProfileDay day,
    T? Function(ProfileSession session) value, {
    required String Function(String session) bestHadNone,
    required String Function(String session) firstSession,
  }) {
    final setter = _bestLapSession(day);
    if (setter != null) {
      if (value(setter) case final shown?) {
        return (
          l10n.lastTimeHereWeatherBestLapSession(setter.name),
          setter,
          shown,
        );
      }
    }
    for (final session in day.sessions) {
      if (value(session) case final shown?) {
        return (
          setter == null
              ? firstSession(session.name)
              : bestHadNone(session.name),
          session,
          shown,
        );
      }
    }
    return null;
  }

  /// The session label and weather line standing for [day]: the session
  /// that set its best lap when it has weather, else its first session with
  /// weather, labelled as which; null when none has.
  static (String, String)? _weatherOf(AppLocalizations l10n, ProfileDay day) {
    final standing = _standingSession(
      l10n,
      day,
      (session) => switch (session.weather) {
        final weather? => _weatherText(l10n, weather),
        null => null,
      },
      bestHadNone: l10n.lastTimeHereWeatherBestHadNone,
      firstSession: l10n.lastTimeHereWeatherFirstSession,
    );
    return standing == null ? null : (standing.$1, standing.$3);
  }

  /// The session label and setup standing for [day], chosen as its weather
  /// is ([_standingSession]); null when no session has a setup entered.
  static (String, RunSetup)? _setupOf(AppLocalizations l10n, ProfileDay day) {
    final standing = _standingSession(
      l10n,
      day,
      (session) => switch (session.setup?.setup) {
        final setup? when setupText(l10n, setup) != null => setup,
        _ => null,
      },
      bestHadNone: l10n.lastTimeHereSetupBestHadNone,
      firstSession: l10n.lastTimeHereSetupFirstSession,
    );
    return standing == null ? null : (standing.$1, standing.$3);
  }

  /// The setup of each visit as entered, kept in the profile with its
  /// sessions as the day was saved, and, when both visits entered
  /// pressures in the same unit, today's minus then's. Pressures in
  /// different units are never converted or compared.
  List<Widget> _setup(BuildContext context, ProfileDay today, ProfileDay then) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final small = theme.textTheme.bodySmall;
    final thenSetup = _setupOf(l10n, then);
    final todaySetup = _setupOf(l10n, today);
    final difference = thenSetup == null || todaySetup == null
        ? null
        : _setupDifference(l10n, thenSetup.$2, todaySetup.$2);
    return [
      const SizedBox(height: 8),
      Text(
        l10n.lastTimeHereSetup,
        key: const ValueKey('lastTimeHereSetup'),
        style: theme.textTheme.labelLarge,
      ),
      Text(
        thenSetup == null
            ? _thenSetupMissing(l10n, then)
            : l10n.lastTimeHereSetupThen(
                thenSetup.$1,
                setupText(l10n, thenSetup.$2)!,
              ),
        key: const ValueKey('lastTimeHereSetupThen'),
        style: thenSetup == null ? small : theme.textTheme.bodyMedium,
      ),
      Text(
        todaySetup == null
            ? _todaySetupMissing(l10n, today)
            : l10n.lastTimeHereSetupToday(
                todaySetup.$1,
                setupText(l10n, todaySetup.$2)!,
              ),
        key: const ValueKey('lastTimeHereSetupToday'),
        style: todaySetup == null ? small : theme.textTheme.bodyMedium,
      ),
      if (difference case (final line?, _))
        Text(
          l10n.lastTimeHereSetupDifference(line),
          key: const ValueKey('lastTimeHereSetupDifference'),
          style: theme.textTheme.bodyMedium,
        ),
      if (difference case (_, true))
        Text(
          l10n.lastTimeHereSetupUnits,
          key: const ValueKey('lastTimeHereSetupUnits'),
          style: small,
        ),
      if (thenSetup != null || todaySetup != null) ...[
        const SizedBox(height: 4),
        Text(l10n.lastTimeHereSetupNote, style: small),
      ],
    ];
  }

  /// Why [setup] cannot be shown, when it holds something this version
  /// does not show: stored by a newer version, or only values it cannot
  /// read. Null when it shows, or when nothing but its version (and a
  /// unit) is stored: nothing was entered.
  static String? _unreadable(AppLocalizations l10n, ProfileSetup? setup) {
    if (setup == null || setupText(l10n, setup.setup) != null) return null;
    if (setup.setup.readOnly) return l10n.lastTimeHereSetupReasonNewer;
    final stored = setup.json.keys.any(
      (key) => key != 'version' && key != 'pressureUnit',
    );
    return stored ? l10n.lastTimeHereSetupReasonUnreadable : null;
  }

  /// The session standing for [day] whose setup cannot be shown, labelled
  /// as a shown setup would be, with why; null when none has such a setup.
  static (String, String)? _unreadableOf(
    AppLocalizations l10n,
    ProfileDay day,
  ) {
    final standing = _standingSession(
      l10n,
      day,
      (session) => _unreadable(l10n, session.setup),
      bestHadNone: l10n.lastTimeHereSetupBestHadNone,
      firstSession: l10n.lastTimeHereSetupFirstSession,
    );
    return standing == null ? null : (standing.$1, standing.$3);
  }

  /// The previous visit without a setup to show: why for a session whose
  /// setup this version cannot show, else that the day has none.
  static String _thenSetupMissing(AppLocalizations l10n, ProfileDay then) =>
      switch (_unreadableOf(l10n, then)) {
        (final label, final reason) => l10n.lastTimeHereSetupThenMissing(
          label,
          reason,
        ),
        null => l10n.lastTimeHereSetupThenNone,
      };

  /// Today without a setup to show in the library: why, for a session
  /// whose setup this version cannot show, else for the session that set
  /// the best lap (else the first session): entered on the page and not
  /// saved yet, saved and not in the library yet, or not entered.
  String _todaySetupMissing(AppLocalizations l10n, ProfileDay today) {
    if (_unreadableOf(l10n, today) case (final label, final reason)) {
      return l10n.lastTimeHereSetupTodayMissing(label, reason);
    }
    final setter = _bestLapSession(today);
    final session = setter ?? today.sessions.firstOrNull;
    if (session == null) return l10n.lastTimeHereSetupTodayNoSessions;
    final label = setter == null
        ? session.name
        : l10n.lastTimeHereWeatherBestLapSession(session.name);
    final given = library.givenSetups(eventId)?[session.runId];
    final reason = setupUnsavedOf?.call(session.runId) ?? false
        ? l10n.lastTimeHereSetupReasonUnsaved
        : given != null && setupText(l10n, given.setup) != null
        ? l10n.lastTimeHereSetupReasonPending
        : l10n.lastTimeHereSetupReasonNone;
    return l10n.lastTimeHereSetupTodayMissing(label, reason);
  }

  /// Today's pressures minus then's ("Cold +0.1 / 0 / −0.1 / — bar · Hot
  /// …") when both were entered in one unit, for the wheels entered on
  /// both; null when there is none. The second value is whether the units
  /// differ, so nothing was compared.
  static (String?, bool) _setupDifference(
    AppLocalizations l10n,
    RunSetup then,
    RunSetup today,
  ) {
    final unit = then.pressureUnit;
    if (unit == null ||
        today.pressureUnit == null ||
        !then.hasPressures ||
        !today.hasPressures) {
      return (null, false);
    }
    if (unit != today.pressureUnit) return (null, true);
    String? wheels(
      WheelPressures before,
      WheelPressures now,
      String Function(String pressures, String unit) line,
    ) {
      final values = [
        for (final (index, value) in now.values.indexed)
          switch ((before.values[index], value)) {
            (final a?, final b?) => _signed(b - a),
            _ => null,
          },
      ];
      if (values.every((value) => value == null)) return null;
      return line(
        [for (final value in values) value ?? '—'].join(' / '),
        pressureUnitText(l10n, unit),
      );
    }

    final parts = [
      ?wheels(then.cold, today.cold, l10n.setupCold),
      ?wheels(then.hot, today.hot, l10n.setupHot),
    ];
    return (parts.isEmpty ? null : parts.join(' · '), false);
  }

  /// A difference of setup numbers with its sign, as a time difference
  /// shows it: "+0.1", "−0.15", "0" for none.
  static String _signed(double value) {
    final hundredths = (value * 100).round();
    if (hundredths == 0) return '0';
    return '${hundredths > 0 ? '+' : '−'}'
        '${setupNumberText(hundredths.abs() / 100)}';
  }

  /// Why today has no weather in the library: from the page's weather of
  /// the session that set the best lap (else the first session).
  String _todayMissing(AppLocalizations l10n, ProfileDay today) {
    final setter = _bestLapSession(today);
    final session = setter ?? today.sessions.firstOrNull;
    final stateOf = weatherStateOf;
    if (session == null || stateOf == null) {
      return l10n.lastTimeHereWeatherTodayNone;
    }
    final label = setter == null
        ? session.name
        : l10n.lastTimeHereWeatherBestLapSession(session.name);
    return switch (stateOf(session.runId)) {
      SessionWeatherState.fetching => l10n.lastTimeHereWeatherTodayFetching(
        label,
      ),
      SessionWeatherState.off => l10n.lastTimeHereWeatherTodayOff(label),
      SessionWeatherState.unavailable =>
        l10n.lastTimeHereWeatherTodayUnavailable(label),
      SessionWeatherState.none => l10n.lastTimeHereWeatherTodayNoPosition(
        label,
      ),
      SessionWeatherState.ready => l10n.lastTimeHereWeatherTodayPending(label),
      SessionWeatherState.kept => l10n.lastTimeHereWeatherTodayKept(label),
    };
  }

  /// Each corner measured on both days: the time lost there against that
  /// day's fastest through it, then and today.
  List<Widget> _corners(
    BuildContext context,
    DriverProfile profile,
    ProfileDay today,
    ProfileDay then,
  ) {
    final trackId = today.trackId;
    if (trackId == null) return const [];
    final corners = lastTimeHereCorners(profile, trackId, then, today);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    if (corners.isEmpty) {
      // A track with corners, not measured on one of the days (an older
      // day, or today's still being analysed).
      if (profile.track(trackId)?.corners.isEmpty ?? true) return const [];
      return [
        const SizedBox(height: 8),
        Text(
          l10n.lastTimeHereCornersNone,
          key: const ValueKey('lastTimeHereCornersNone'),
          style: theme.textTheme.bodySmall,
        ),
      ];
    }
    return [
      const SizedBox(height: 8),
      Text(
        l10n.lastTimeHereCorners,
        key: const ValueKey('lastTimeHereCorners'),
        style: theme.textTheme.labelLarge,
      ),
      for (final corner in corners)
        _row(
          context,
          ValueKey('lastTimeHereCorner ${corner.corner.id}'),
          corner.corner.name,
          corner.then,
          corner.today,
        ),
      Text(l10n.lastTimeHereCornersNote, style: theme.textTheme.bodySmall),
    ];
  }

  /// "Best lap  1:51.204 then · 1:49.898 today  −1.306 s": today − then,
  /// so a negative difference is faster today.
  Widget _row(
    BuildContext context,
    Key key,
    String label,
    double? then,
    double? today,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = FetColors.of(context);
    final delta = then == null || today == null ? null : today - then;
    // A difference that shows as 0.000 s is no change.
    final rounded = delta == null ? 0 : (delta * 1000).round();
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          Text(
            l10n.lastTimeHereThenToday(
              then == null ? '—' : displayTime(then),
              today == null ? '—' : displayTime(today),
            ),
            style: theme.textTheme.bodyMedium,
          ),
          if (delta != null)
            Text(
              displayDelta(delta),
              style: theme.textTheme.titleSmall?.copyWith(
                color: rounded < 0
                    ? colors.gain
                    : rounded > 0
                    ? colors.loss
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
