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
    this.notebooks = const [],
    this.notebookCut = false,
    this.referencesNotKept = const [],
  });

  /// This profile with the new days.
  final DriverProfile profile;

  /// Event ids of the days added, in [from]'s order.
  final List<String> added;

  /// Days this profile already had: left as they are.
  final List<String> alreadyHere;

  /// Days past this profile's limits of days, cars or tracks.
  final List<String> notAdded;

  /// Ids of this profile's tracks whose notebook took something of [from]'s.
  final List<String> notebooks;

  /// Whether some of [from]'s notebook text or things to try were left
  /// out, past the profile's limits.
  final bool notebookCut;

  /// Days added without their reference lap (FET-276): it would have passed
  /// the profile's limits of reference recordings ([maximumReferenceFiles],
  /// [maximumReferenceBytes]). The day itself came along.
  final List<String> referencesNotKept;
}

/// [into] with the days of [from] it does not have yet ([only] of them,
/// when given), each file `Days/<eventId>.fetproject`.
///
/// A car of [from] is this profile's car with the same id or, failing
/// that, the same name; a track is the one with the same id or, failing
/// that, the same route ([routesMatch]), its corners placed on this
/// track's as a day's are. Anything else is added. Corners past the
/// profile's budget are left out, as when a day is added; which car new
/// days take is unchanged. The notebook of every track both have takes
/// what [from]'s adds, whichever days are added. A day brings its reference
/// lap (FET-276): a recording copy the profile keeps already (same hash) is
/// shared, and one that would pass the limits of reference recordings is
/// left out ([ProfileMerge.referencesNotKept]).
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
  // The reference recordings the profile keeps, by file name.
  final referenceFiles = profileReferenceFiles(into);
  final referencesNotKept = <String>[];

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
      mine = theirs;
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
    if (days.length >= maximumProfileDays) {
      notAdded.add(day.eventId);
      continue;
    }
    // A day that cannot be added leaves no car or track of its own behind.
    final before = (
      cars: [...cars],
      tracks: [...tracks],
      carIds: {...carIds},
      trackIds: {...trackIds},
      cornerIds: {...cornerIds},
    );
    final trackId = day.trackId == null ? null : track(day.trackId!);
    final carId = car(day.carId);
    if (carId == null || (day.trackId != null && trackId == null)) {
      cars
        ..clear()
        ..addAll(before.cars);
      tracks
        ..clear()
        ..addAll(before.tracks);
      carIds
        ..clear()
        ..addAll(before.carIds);
      trackIds
        ..clear()
        ..addAll(before.trackIds);
      cornerIds
        ..clear()
        ..addAll(before.cornerIds);
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
    // Its reference lap comes along; a recording the profile keeps already
    // is shared, a new one counts against the limits.
    var reference = day.reference;
    if (reference is ProfileReferenceFile && !referenceFiles.containsKey(reference.fileName)) {
      if (referenceFiles.length >= maximumReferenceFiles ||
          referenceFiles.values.fold(0, (sum, bytes) => sum + bytes) + reference.bytes >
              maximumReferenceBytes) {
        reference = null;
        referencesNotKept.add(day.eventId);
      } else {
        referenceFiles[reference.fileName] = reference.bytes;
      }
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
        reference: reference,
        unknown: day.unknown,
      ),
    );
    known.add(day.eventId);
    added.add(day.eventId);
  }
  // Their notebooks join mine on every track both profiles have, whether
  // or not a day was added to it: two devices with the same days still
  // share what was written on either.
  final notebooks = <String>[];
  var notebookCut = false;
  for (final theirs in from.tracks) {
    if (theirs.notebook.isEmpty) continue;
    var index = -1;
    if (trackIds[theirs.id] case final mapped?) {
      index = tracks.indexWhere((track) => track.id == mapped);
    } else {
      index = tracks.indexWhere((track) => track.id == theirs.id);
      if (index < 0) {
        index = tracks.indexWhere((track) => routesMatch(track.route, theirs.route));
      }
    }
    // Their track came along whole, notebook and all; or it is not here.
    if (index < 0 || identical(tracks[index], theirs)) continue;
    final mine = tracks[index];
    final (notebook, cut) = _mergeNotebook(
      mine.notebook,
      theirs.notebook,
      ids: matchTrackCorners(mine, _cornerSpans(theirs)),
      names: {for (final corner in theirs.corners) corner.id: corner.name},
    );
    notebookCut |= cut;
    if (jsonEncode(_encodeNotebook(notebook)) == jsonEncode(_encodeNotebook(mine.notebook))) {
      continue;
    }
    tracks[index] = _verified(_encodeTrack(mine.copyWith(notebook: notebook)), _track);
    if (!notebooks.contains(mine.id)) notebooks.add(mine.id);
  }
  final merged = into._copy(cars: cars, tracks: tracks, days: days);
  // Read back as it will be written: a merge never leaves a profile that
  // cannot be opened.
  return ProfileMerge(
    profile: decodeDriverProfile(encodeDriverProfile(merged)),
    added: added,
    alreadyHere: alreadyHere,
    notAdded: notAdded,
    notebooks: notebooks,
    notebookCut: notebookCut,
    referencesNotKept: referencesNotKept,
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
