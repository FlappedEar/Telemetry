part of 'driver_profile.dart';

// Bringing the days of another device's profile into this one (FET-133):
// a day already here stays as it is; a new day joins this profile's car
// and track when it has them, so its history continues on this device.

/// What [mergeDriverProfile] did.
final class ProfileMerge {
  const ProfileMerge({
    required this.profile,
    this.added = const [],
    this.alreadyHere = const [],
    this.notAdded = const [],
  });

  /// This profile with the new days.
  final DriverProfile profile;

  /// Event ids of the days added, in [from]'s order.
  final List<String> added;

  /// Days this profile already had: left as they are.
  final List<String> alreadyHere;

  /// Days past this profile's limits of days, cars or tracks.
  final List<String> notAdded;
}

/// [into] with the days of [from] it does not have yet ([only] of them,
/// when given), each file `Days/<eventId>.fetproject`.
///
/// A car of [from] is this profile's car with the same id or, failing
/// that, the same name; a track is the one with the same id or, failing
/// that, the same route ([routesMatch]), its corners placed on this
/// track's as a day's are. Anything else is added. Corners past the
/// profile's budget are left out, as when a day is added; which car new
/// days take is unchanged.
ProfileMerge mergeDriverProfile(
  DriverProfile into,
  DriverProfile from, {
  Set<String>? only,
  Random? random,
}) {
  final cars = [...into.cars];
  final tracks = [...into.tracks];
  final days = [...into.days];
  final known = {for (final day in days) day.eventId};
  final carIds = <String, String>{};
  final trackIds = <String, String>{};
  // Per track of [from]: its corner ids on this profile's track.
  final cornerIds = <String, Map<String, String>>{};
  var corners = 0;
  for (final day in days) {
    for (final session in day.sessions) {
      corners += session.stats?.corners.length ?? 0;
    }
  }

  String? car(String id) {
    if (carIds[id] case final mapped?) return mapped;
    final theirs = from.car(id);
    if (theirs == null) return null;
    final name = theirs.name.trim().toLowerCase();
    var mine =
        _find(cars, (car) => car.id == id) ??
        _find(cars, (car) => car.name.trim().toLowerCase() == name);
    if (mine == null) {
      if (cars.length >= maximumProfileCars) return null;
      mine = cars.any((car) => car.id == id)
          ? ProfileCar(
              id: newEventId(random),
              name: theirs.name,
              notes: theirs.notes,
              unknown: theirs.unknown,
            )
          : theirs;
      cars.add(mine);
    }
    return carIds[id] = mine.id;
  }

  // Null when the track could not be added.
  String? track(String id) {
    if (trackIds[id] case final mapped?) return mapped;
    final theirs = from.track(id);
    if (theirs == null) return null;
    var index = tracks.indexWhere((track) => track.id == id);
    if (index < 0) index = tracks.indexWhere((track) => routesMatch(track.route, theirs.route));
    if (index < 0) {
      if (tracks.length >= maximumProfileTracks) return null;
      tracks.add(theirs);
      cornerIds[id] = {for (final corner in theirs.corners) corner.id: corner.id};
      return trackIds[id] = theirs.id;
    }
    final mine = tracks[index];
    final (placed, ids) = _placeCorners(mine, _cornerSpans(theirs), random);
    if (placed.length != mine.corners.length) {
      tracks[index] = _verified(_encodeTrack(mine.copyWith(corners: placed)), _track);
    }
    cornerIds[id] = ids;
    return trackIds[id] = mine.id;
  }

  final added = <String>[], alreadyHere = <String>[], notAdded = <String>[];
  for (final day in from.days) {
    if (only != null && !only.contains(day.eventId)) continue;
    if (known.contains(day.eventId)) {
      alreadyHere.add(day.eventId);
      continue;
    }
    final carId = days.length >= maximumProfileDays ? null : car(day.carId);
    final trackId = day.trackId == null ? null : track(day.trackId!);
    if (carId == null || (day.trackId != null && trackId == null)) {
      notAdded.add(day.eventId);
      continue;
    }
    final ids = day.trackId == null ? const <String, String>{} : cornerIds[day.trackId!]!;
    var sessions = [
      for (final session in day.sessions)
        session._withStats(
          session.stats?.withCorners([
            for (final corner in session.stats!.corners)
              if (ids[corner.cornerId] case final id?) corner.withCorner(id),
          ], theoreticalBestSeconds: session.stats!.theoreticalBestSeconds),
        ),
    ];
    final count = sessions.fold(0, (sum, s) => sum + (s.stats?.corners.length ?? 0));
    if (corners + count > maximumProfileCornerStats) {
      sessions = [
        for (final session in sessions)
          session._withStats(
            session.stats?.withCorners(
              const [],
              theoreticalBestSeconds: session.stats!.theoreticalBestSeconds,
            ),
          ),
      ];
    } else {
      corners += count;
    }
    days.add(
      ProfileDay(
        eventId: day.eventId,
        file: 'Days/${day.eventId}.fetproject',
        name: day.name,
        carId: carId,
        trackId: trackId,
        startMilliseconds: day.startMilliseconds,
        sessions: sessions,
        bestLapSeconds: day.bestLapSeconds,
        theoreticalBestSeconds: day.theoreticalBestSeconds,
        unknown: day.unknown,
      ),
    );
    known.add(day.eventId);
    added.add(day.eventId);
  }
  final merged = into._copy(cars: cars, tracks: tracks, days: days);
  // Read back as it will be written: a merge never leaves a profile that
  // cannot be opened.
  return ProfileMerge(
    profile: decodeDriverProfile(encodeDriverProfile(merged)),
    added: added,
    alreadyHere: alreadyHere,
    notAdded: notAdded,
  );
}

/// [track]'s corners on the ground, as a day's analysis gives them.
List<DayCornerSpan> _cornerSpans(ProfileTrack track) {
  final points = track.route.points;
  if (points.isEmpty) return const [];
  GeoCoordinate at(double fraction) {
    final index = (fraction * points.length).round() % points.length;
    final point = points[index];
    return unprojectCoordinate(point.eastMeters, point.northMeters, track.route.origin);
  }

  return [
    for (final corner in track.corners)
      DayCornerSpan(
        segmentId: corner.id,
        name: corner.name,
        start: at(corner.start),
        end: at(corner.end),
      ),
  ];
}
