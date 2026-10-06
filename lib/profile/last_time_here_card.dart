import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import 'profile_library.dart';

/// "Last time here": the previous visit to the open day's track, from the
/// driver profile, with its best lap and theoretical best next to today's.
/// The same car first, else any car. Nothing is shown on a first visit, for
/// a day outside the library, or before the day is in the profile.
class LastTimeHereCard extends StatelessWidget {
  const LastTimeHereCard({
    super.key,
    required this.library,
    required this.eventId,
  });

  final ProfileLibrary library;

  /// The open day's `event.id`.
  final String eventId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
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
            ..._corners(context, profile, today, then),
          ],
        ),
      ),
    );
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
