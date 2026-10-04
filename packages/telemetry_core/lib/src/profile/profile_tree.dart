// The driver profile as the library shows it: Driver > Car > Year > Track >
// Date > Sessions. A view over the profile's days; nothing here is stored.
import 'driver_profile.dart';

/// One date's days at a track. Usually one day.
final class ProfileDateNode {
  ProfileDateNode(this.date, List<ProfileDay> days) : days = List.unmodifiable(days);

  /// The local date at midnight; null for undated days.
  final DateTime? date;

  /// Earliest first.
  final List<ProfileDay> days;
}

/// A track's dates within one year.
final class ProfileTrackNode {
  ProfileTrackNode(this.track, List<ProfileDateNode> dates) : dates = List.unmodifiable(dates);

  /// Null for days whose track was not recognised.
  final ProfileTrack? track;

  /// Most recent first; undated last.
  final List<ProfileDateNode> dates;
}

/// A car's tracks within one year.
final class ProfileYearNode {
  ProfileYearNode(this.year, List<ProfileTrackNode> tracks) : tracks = List.unmodifiable(tracks);

  /// Null for undated days.
  final int? year;

  /// By name; the unrecognised track last.
  final List<ProfileTrackNode> tracks;
}

/// A car's years.
final class ProfileCarNode {
  ProfileCarNode(this.car, List<ProfileYearNode> years) : years = List.unmodifiable(years);

  final ProfileCar car;

  /// Most recent first; undated last.
  final List<ProfileYearNode> years;
}

/// [profile]'s days by car, year, track and date. Cars are in the profile's
/// order, with no node for a car without days. [localTime] turns a Unix
/// millisecond time into the date the driver saw (the device's time zone
/// by default).
List<ProfileCarNode> profileTree(
  DriverProfile profile, {
  DateTime Function(int milliseconds)? localTime,
}) {
  final toLocal =
      localTime ?? (int milliseconds) => DateTime.fromMillisecondsSinceEpoch(milliseconds);
  DateTime? dateOf(ProfileDay day) {
    final start = day.startMilliseconds;
    if (start == null) return null;
    final time = toLocal(start);
    return DateTime(time.year, time.month, time.day);
  }

  int byStart(ProfileDay a, ProfileDay b) =>
      (a.startMilliseconds ?? 0).compareTo(b.startMilliseconds ?? 0);
  int newestFirst<T extends Comparable<Object>>(T? a, T? b) =>
      a == null ? (b == null ? 0 : 1) : (b == null ? -1 : b.compareTo(a));

  final nodes = <ProfileCarNode>[];
  for (final car in profile.cars) {
    final days = [
      for (final day in profile.days)
        if (day.carId == car.id) day,
    ];
    if (days.isEmpty) continue;
    final byYear = <int?, List<ProfileDay>>{};
    for (final day in days) {
      byYear.putIfAbsent(dateOf(day)?.year, () => []).add(day);
    }
    final years = byYear.keys.toList()..sort(newestFirst);
    nodes.add(
      ProfileCarNode(car, [
        for (final year in years)
          ProfileYearNode(year, () {
            final byTrack = <String?, List<ProfileDay>>{};
            for (final day in byYear[year]!) {
              byTrack.putIfAbsent(day.trackId, () => []).add(day);
            }
            final tracks = [
              for (final MapEntry(:key, :value) in byTrack.entries)
                (track: key == null ? null : profile.track(key), days: value),
            ];
            tracks.sort((a, b) {
              if (a.track == null || b.track == null) {
                return a.track == null ? (b.track == null ? 0 : 1) : -1;
              }
              final byName = a.track!.name.toLowerCase().compareTo(b.track!.name.toLowerCase());
              return byName != 0 ? byName : a.track!.id.compareTo(b.track!.id);
            });
            return [
              for (final (:track, :days) in tracks)
                ProfileTrackNode(track, () {
                  final byDate = <DateTime?, List<ProfileDay>>{};
                  for (final day in days) {
                    byDate.putIfAbsent(dateOf(day), () => []).add(day);
                  }
                  final dates = byDate.keys.toList()..sort(newestFirst);
                  return [
                    for (final date in dates) ProfileDateNode(date, byDate[date]!..sort(byStart)),
                  ];
                }()),
            ];
          }()),
      ]),
    );
  }
  return nodes;
}
