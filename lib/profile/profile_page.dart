import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../day/theoretical_best_card.dart' show TheoreticalBestText;
import '../format.dart';
import '../l10n.dart';
import '../ui/readable_list.dart';
import 'profile_library.dart';
import 'profile_trends_card.dart';
import 'skill_levels_card.dart';

/// A distance in kilometres: "71.8 km".
String profileDistance(double meters) =>
    '${fixed(meters / 1000, 1)}${unitSpace}km';

/// A time on track in hours and minutes: "2 h 12 min".
String profileDuration(double seconds) {
  final minutes = (seconds / 60).round();
  final hours = minutes ~/ 60;
  return hours == 0
      ? '$minutes${unitSpace}min'
      : '$hours${unitSpace}h ${minutes % 60}${unitSpace}min';
}

/// The driver across every day: totals, skills, each car's mileage, each
/// track's records and progress, each track's days one by one, and the
/// corners that keep costing time.
/// Everything is worked out by the profile (`telemetry_core`); this page
/// only shows it.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.library});

  final ProfileLibrary library;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.navProfile)),
    body: ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final profile = library.profile;
        if (!library.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        if (profile == null) {
          // As the library says: the profile is not read or kept now.
          return ReadableListView(
            children: [
              Text(
                context.l10n.libraryUnavailable,
                key: const ValueKey('profileUnavailable'),
              ),
            ],
          );
        }
        if (profile.days.isEmpty) {
          return ReadableListView(
            children: [
              Text(
                context.l10n.profileEmpty,
                key: const ValueKey('profileEmpty'),
              ),
            ],
          );
        }
        return ReadableListView(
          key: const ValueKey('profile'),
          children: [
            _Totals(profile: profile),
            const SizedBox(height: 12),
            ProfileSkillLevels(library: library),
            const SizedBox(height: 12),
            _Cars(profile: profile),
            const SizedBox(height: 12),
            _Tracks(profile: profile),
            const SizedBox(height: 12),
            ProfileTrendsCard(profile: profile),
            const SizedBox(height: 12),
            _Repeated(profile: profile),
          ],
        );
      },
    ),
  );
}

/// A date, or "Undated".
String profileDayDate(BuildContext context, ProfileDay day) {
  final start = day.startMilliseconds;
  return start == null
      ? context.l10n.profileUndated
      : DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(start));
}

/// When a record was set: its date, and its session when known.
String _when(BuildContext context, ProfileTime time) {
  final date = profileDayDate(context, time.day);
  final session = time.day.sessions
      .where((session) => session.runId == time.runId)
      .firstOrNull;
  return session == null
      ? date
      : '$date · ${context.l10n.session(session.name)}';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          ...children,
        ],
      ),
    ),
  );
}

class _Totals extends StatelessWidget {
  const _Totals({required this.profile});

  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final totals = driverTotals(profile);
    final figures = [
      (l10n.profileDays, '${totals.days}'),
      (l10n.profileSessions, '${totals.sessions}'),
      (l10n.profileLaps, '${totals.laps}'),
      // Not measured is no figure, not zero; the line below says why.
      (
        l10n.profileDistance,
        totals.measuredSessions == 0
            ? '—'
            : profileDistance(totals.distanceMeters),
      ),
      (
        l10n.profileDrivingTime,
        totals.measuredSessions == 0
            ? '—'
            : profileDuration(totals.drivingSeconds),
      ),
      (l10n.profileTracks, '${totals.tracks}'),
      (l10n.profileCars, '${totals.cars}'),
    ];
    return _Section(
      key: const ValueKey('profileTotals'),
      title: l10n.profileTotals,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            for (final (label, value) in figures)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  Text(
                    value,
                    key: ValueKey('profileTotal $label'),
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
          ],
        ),
        if (totals.measuredSessions < totals.sessions) ...[
          const SizedBox(height: 8),
          Text(
            l10n.profileMeasured(totals.measuredSessions, totals.sessions),
            key: const ValueKey('profileMeasured'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _Cars extends StatelessWidget {
  const _Cars({required this.profile});

  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final totals = carTotals(profile);
    return _Section(
      key: const ValueKey('profileCars'),
      title: l10n.profileCars,
      children: [
        for (final car in profile.cars)
          if (totals[car.id] case final total? when total.days > 0)
            ListTile(
              key: ValueKey('profileCar ${car.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(car.name),
              subtitle: Text(
                total.measuredSessions == 0
                    ? l10n.profileDrivenOnUnmeasured(total.days)
                    : l10n.profileDrivenOn(
                        total.days,
                        profileDistance(total.distanceMeters),
                        profileDuration(total.drivingSeconds),
                      ),
              ),
            ),
      ],
    );
  }
}

class _Tracks extends StatelessWidget {
  const _Tracks({required this.profile});

  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final records = trackRecords(profile);
    return _Section(
      key: const ValueKey('profileTracksSection'),
      title: l10n.profileTracks,
      children: [
        if (!profile.tracks.any((track) => records[track.id] != null))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.profileTracksNone,
              key: const ValueKey('profileTracksNone'),
            ),
          ),
        for (final track in profile.tracks)
          if (records[track.id] case final record?)
            _TrackRecordTile(profile: profile, track: track, record: record),
      ],
    );
  }
}

class _TrackRecordTile extends StatelessWidget {
  const _TrackRecordTile({
    required this.profile,
    required this.track,
    required this.record,
  });

  final DriverProfile profile;
  final ProfileTrack track;
  final TrackRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final last = trackProgress(profile, track.id).lastOrNull;
    final gain = last?.bestLapGain;
    final lines = [
      if (record.bestLap case final best?)
        l10n.profileBestLap(displayTime(best.seconds), _when(context, best)),
      if (record.theoreticalBest case final best?)
        l10n.profileTheoreticalBest(
          displayTime(best.seconds),
          _when(context, best),
        ),
      if (record.bestTypicalLap case final best?)
        l10n.profileTypicalLap(displayTime(best.seconds), _when(context, best)),
      // A gain that shows as 0.000 s is no change.
      if (gain != null && gain.abs() >= 0.0005)
        gain > 0
            ? l10n.profileFaster(displayTime(gain))
            : l10n.profileSlower(displayTime(-gain)),
    ];
    return Padding(
      key: ValueKey('profileTrack ${track.id}'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${track.name} · ${l10n.direction(track.route.direction)} · '
            '${l10n.profileVisits(record.visits)}',
            style: theme.textTheme.bodyLarge,
          ),
          for (final line in lines)
            Text(line, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Repeated extends StatelessWidget {
  const _Repeated({required this.profile});

  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final losses = repeatedLosses(profile);
    return _Section(
      key: const ValueKey('profileRepeated'),
      title: l10n.profileRepeated,
      children: [
        if (losses.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.profileRepeatedNone),
          ),
        for (final (i, loss) in losses.indexed)
          ListTile(
            key: ValueKey('profileRepeated $i'),
            contentPadding: EdgeInsets.zero,
            title: Text(_cornerName(context, loss)),
            subtitle: Text(
              '${l10n.profileRepeatedLoss(displayTime(loss.meanLossSeconds), loss.visits)}'
              ' · ${l10n.profileRepeatedState(loss.state.name)}',
            ),
          ),
      ],
    );
  }

  String _cornerName(BuildContext context, RepeatedLoss loss) {
    final track = profile.track(loss.trackId);
    final corner = track?.corners
        .where((corner) => corner.id == loss.cornerId)
        .firstOrNull;
    final name = corner == null
        ? loss.cornerId
        : context.l10n.tbSegmentName(corner.name);
    return track == null ? name : '${track.name} · $name';
  }
}
