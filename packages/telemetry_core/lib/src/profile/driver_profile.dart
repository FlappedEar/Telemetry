// The driver profile (`.feprofile`): the driver, their cars, the tracks they
// drove and every day kept on this device, so analysis can look across days.
// The day files stay authoritative for sessions and laps; a day's summary
// here is rebuilt from its analysis whenever the day is added again.
import 'dart:convert';
import 'dart:math';

import '../analysis/consistency.dart';
import '../analysis/gg_pairs.dart' show standardGravity;
import '../day/compatibility.dart';
import '../day/day_coach.dart' show CoachCornerPassage, coachCornerPassages;
import '../day/day_analysis.dart';
import '../day/day_document.dart';
import '../day/day_laps.dart';
import '../day/day_ranking.dart';
import '../day/day_theoretical_best.dart';
import '../day/track_inference.dart';
import '../geometry.dart';
import '../speed_units.dart';
import '../telemetry_session.dart';

part 'session_stats.dart';

/// The `format` of a driver profile.
const driverProfileFormat = 'flappedear-driver-profile';

/// The version this code writes and the newest it reads.
const driverProfileVersion = 1;

/// The largest profile read, in UTF-16 code units of its text.
const maximumProfileCharacters = 32 * 1024 * 1024;

/// The most cars, tracks and days a profile holds.
const maximumProfileCars = 64;
const maximumProfileTracks = 1024;
const maximumProfileDays = 10000;

/// The longest name or note in a profile, in UTF-16 code units.
const maximumProfileTextCharacters = 4096;

/// Why a profile cannot be read.
final class ProfileFormatError implements Exception {
  const ProfileFormatError(this.message, {this.newerVersion = false});

  final String message;

  /// Whether the profile was written by a newer version of the app: whole,
  /// and never to be replaced by this version.
  final bool newerVersion;

  @override
  String toString() => 'ProfileFormatError: $message';
}

/// A car the driver drives.
final class ProfileCar {
  ProfileCar({
    required this.id,
    required this.name,
    this.notes = '',
    Map<String, Object?> unknown = const {},
  }) : unknown = Map.unmodifiable(unknown);

  final String id;
  final String name;
  final String notes;

  /// Keys this version does not know, kept as read.
  final Map<String, Object?> unknown;

  ProfileCar copyWith({String? name, String? notes}) =>
      ProfileCar(id: id, name: name ?? this.name, notes: notes ?? this.notes, unknown: unknown);
}

/// A circuit the driver drove, recognised on later days by its route.
final class ProfileTrack {
  ProfileTrack({
    required this.id,
    required this.name,
    required this.route,
    List<TrackCorner> corners = const [],
    Map<String, Object?> unknown = const {},
    Map<String, Object?> unknownRoute = const {},
  }) : corners = List.unmodifiable(corners),
       unknown = Map.unmodifiable(unknown),
       unknownRoute = Map.unmodifiable(unknownRoute);

  final String id;
  final String name;

  /// The route of the day that first added the track.
  final RouteShape route;

  /// Its corners, the same on every visit, in the order first found.
  final List<TrackCorner> corners;
  final Map<String, Object?> unknown;

  /// `route` keys this version does not know.
  final Map<String, Object?> unknownRoute;

  ProfileTrack copyWith({String? name, List<TrackCorner>? corners}) => ProfileTrack(
    id: id,
    name: name ?? this.name,
    route: route,
    corners: corners ?? this.corners,
    unknown: unknown,
    unknownRoute: unknownRoute,
  );
}

/// One session of a day, as its last analysis found it.
final class ProfileSession {
  ProfileSession({
    required this.runId,
    required this.name,
    this.startMilliseconds,
    this.lapCount = 0,
    this.bestLapSeconds,
    this.stats,
    Map<String, Object?> unknown = const {},
  }) : unknown = Map.unmodifiable(unknown);

  final String runId;

  /// "Session N" or the user's name.
  final String name;

  /// The recording's start in Unix milliseconds; null when undated.
  final int? startMilliseconds;

  /// Timed laps.
  final int lapCount;

  /// The fastest eligible lap; null when none is eligible.
  final double? bestLapSeconds;

  /// What it measured; null until measured.
  final SessionStats? stats;
  final Map<String, Object?> unknown;

  ProfileSession _withStats(SessionStats? stats) => ProfileSession(
    runId: runId,
    name: name,
    startMilliseconds: startMilliseconds,
    lapCount: lapCount,
    bestLapSeconds: bestLapSeconds,
    stats: stats,
    unknown: unknown,
  );
}

/// A day kept in the profile.
final class ProfileDay {
  ProfileDay({
    required this.eventId,
    required this.file,
    required this.name,
    required this.carId,
    this.trackId,
    this.startMilliseconds,
    List<ProfileSession> sessions = const [],
    this.bestLapSeconds,
    this.theoreticalBestSeconds,
    Map<String, Object?> unknown = const {},
  }) : sessions = List.unmodifiable(sessions),
       unknown = Map.unmodifiable(unknown);

  /// The day document's `event.id`.
  final String eventId;

  /// The day document, relative to the profile's folder.
  final String file;
  final String name;
  final String carId;

  /// Null when no route was recognised (the chosen group had no run with
  /// enough complete laps on one line).
  final String? trackId;

  /// The first session's start in Unix milliseconds; null when undated.
  final int? startMilliseconds;
  final List<ProfileSession> sessions;

  /// The day's fastest eligible lap; null when none.
  final double? bestLapSeconds;

  /// The theoretical best of the day's track: its best segments added up.
  final double? theoreticalBestSeconds;
  final Map<String, Object?> unknown;

  ProfileDay copyWith({String? carId}) => ProfileDay(
    eventId: eventId,
    file: file,
    name: name,
    carId: carId ?? this.carId,
    trackId: trackId,
    startMilliseconds: startMilliseconds,
    sessions: sessions,
    bestLapSeconds: bestLapSeconds,
    theoreticalBestSeconds: theoreticalBestSeconds,
    unknown: unknown,
  );
}

/// The driver and everything they drove on this device.
final class DriverProfile {
  DriverProfile({
    required this.driverId,
    this.driverName = '',
    List<ProfileCar> cars = const [],
    List<ProfileTrack> tracks = const [],
    List<ProfileDay> days = const [],
    this.lastCarId,
    Map<String, Object?> unknown = const {},
    Map<String, Object?> unknownDriver = const {},
  }) : cars = List.unmodifiable(cars),
       tracks = List.unmodifiable(tracks),
       days = List.unmodifiable(days),
       unknown = Map.unmodifiable(unknown),
       unknownDriver = Map.unmodifiable(unknownDriver);

  /// A profile with a new driver id and nothing in it.
  factory DriverProfile.empty([Random? random]) => DriverProfile(driverId: newEventId(random));

  final String driverId;
  final String driverName;
  final List<ProfileCar> cars;
  final List<ProfileTrack> tracks;

  /// In the order added.
  final List<ProfileDay> days;

  /// The car of the day added or changed last; new days take it.
  final String? lastCarId;

  /// Top-level and `driver` keys this version does not know.
  final Map<String, Object?> unknown;
  final Map<String, Object?> unknownDriver;

  ProfileCar? car(String id) => _find(cars, (car) => car.id == id);
  ProfileTrack? track(String id) => _find(tracks, (track) => track.id == id);
  ProfileDay? day(String eventId) => _find(days, (day) => day.eventId == eventId);

  DriverProfile _copy({
    String? driverName,
    List<ProfileCar>? cars,
    List<ProfileTrack>? tracks,
    List<ProfileDay>? days,
    String? lastCarId,
  }) => DriverProfile(
    driverId: driverId,
    driverName: driverName ?? this.driverName,
    cars: cars ?? this.cars,
    tracks: tracks ?? this.tracks,
    days: days ?? this.days,
    lastCarId: lastCarId ?? this.lastCarId,
    unknown: unknown,
    unknownDriver: unknownDriver,
  );
}

T? _find<T>(List<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Adding days

/// What the profile keeps of a day: its document and its last analysis.
final class ProfileDayInput {
  ProfileDayInput({
    required this.eventId,
    required this.file,
    required this.name,
    List<ProfileSession> sessions = const [],
    this.startMilliseconds,
    this.bestLapSeconds,
    this.route,
    this.trackName,
    this.theoreticalBestSeconds,
    List<DayCornerSpan> cornerSpans = const [],
    this.measuredCorners = false,
  }) : sessions = List.unmodifiable(sessions),
       cornerSpans = List.unmodifiable(cornerSpans);

  /// [eventId] and [file] of a day with [name], from its [analysis]: each
  /// session's laps and best lap, the day's best lap and the route of its
  /// chosen group. [trackName] names a track the profile does not know yet.
  ///
  /// With [recordings] (by run id, as analysis reads them: speeds in their
  /// effective unit), each session's distance and driving time; with the
  /// chosen group's [theoreticalBest], its total, each session's own
  /// theoretical best and its corners. Without them, adding the day keeps
  /// what the profile measured before.
  factory ProfileDayInput.fromAnalysis({
    required String eventId,
    required String file,
    required String name,
    required DayAnalysis analysis,
    String? trackName,
    Map<String, TelemetrySession?>? recordings,
    DayTheoreticalBest? theoreticalBest,
  }) {
    // Only the chosen group's: the day's route and track are its.
    if (theoreticalBest != null && theoreticalBest.groupId != analysis.chosenGroupId) {
      theoreticalBest = null;
    }
    final measured = recordings == null && theoreticalBest == null
        ? const <String, SessionStats>{}
        : measureSessions(analysis, recordings ?? const {}, best: theoreticalBest);
    final ready = theoreticalBest?.state == DayTheoreticalBestState.ready ? theoreticalBest : null;
    final canonical = recordings?[ready?.computed?.canonicalRunId ?? ''];
    final ranking = analysis.ranking;
    // Each run's best lap from the ranking of its own group, so a session
    // on another layout that day keeps its best lap too.
    final best = <String, double?>{
      for (final group in analysis.groups)
        for (final run in group.ranking?.runs ?? const <RunRanking>[])
          run.runId: run.bestLap?.durationSeconds,
    };
    final order = <String>[];
    final names = <String, String>{};
    final starts = <String, int>{};
    final laps = <String, int>{};
    for (final row in analysis.rows) {
      if (!names.containsKey(row.runId)) order.add(row.runId);
      names[row.runId] = row.runName;
      // A time a profile cannot keep (a hostile recording clock) is undated.
      final time = _keptMilliseconds(row.timestampMilliseconds);
      if (time != null && (starts[row.runId] == null || time < starts[row.runId]!)) {
        starts[row.runId] = time;
      }
      laps[row.runId] = (laps[row.runId] ?? 0) + (row.type == LapSectionType.lap ? 1 : 0);
    }
    final sessions = [
      for (final runId in order)
        ProfileSession(
          runId: runId,
          name: names[runId]!,
          startMilliseconds: starts[runId],
          lapCount: laps[runId]!,
          bestLapSeconds: _finite(best[runId]),
          stats: measured[runId],
        ),
    ];
    RouteShape? route;
    for (final runId in analysis.chosenGroup?.runIds ?? const <String>[]) {
      route = analysis.inferences[runId]?.route;
      if (route != null) break;
    }
    int? start;
    for (final time in starts.values) {
      if (start == null || time < start) start = time;
    }
    return ProfileDayInput(
      eventId: eventId,
      file: file,
      name: name,
      sessions: sessions,
      startMilliseconds: start,
      bestLapSeconds: _finite(ranking?.bestOfDay?.durationSeconds),
      route: route,
      trackName: trackName,
      theoreticalBestSeconds: ready?.computed?.best.valid == true
          ? _finite(ready!.computed!.best.totalSeconds)
          : null,
      cornerSpans: canonical == null
          ? const []
          : measureCornerSpans(
              ready,
              longitudeIsWestPositive:
                  canonical.metadata['gpsLongitudeConvention'] == 'west-positive',
            ),
      // Corners are placed from the recording the axis came from; without
      // it, what was measured before is kept.
      // A calculation that failed measured nothing: what was measured
      // before is kept.
      measuredCorners:
          theoreticalBest != null &&
          theoreticalBest.state != DayTheoreticalBestState.error &&
          (ready == null || canonical != null),
    );
  }

  final String eventId;
  final String file;
  final String name;
  final List<ProfileSession> sessions;
  final int? startMilliseconds;
  final double? bestLapSeconds;

  /// The day's route; null when none was recognised.
  final RouteShape? route;

  /// The name of a new track; else [addDayToProfile]'s default.
  final String? trackName;

  /// The theoretical best of the day's route; null when not known.
  final double? theoreticalBestSeconds;

  /// Where the corners of the sessions' [SessionStats] lie, by segment id;
  /// placed on the day's track when it is added.
  final List<DayCornerSpan> cornerSpans;

  /// Whether the theoretical best was worked out: false keeps the day's and
  /// each session's theoretical best and corners measured before.
  final bool measuredCorners;
}

double? _finite(double? value) => value != null && value.isFinite && value > 0 ? value : null;

/// The track of [profile] that [route] drives, or null: the first whose
/// route [routesMatch] (same direction, length within 5 %, every point
/// within 25 m and RMS at most 10 m).
ProfileTrack? matchProfileTrack(DriverProfile profile, RouteShape route) =>
    _find(profile.tracks, (track) => routesMatch(track.route, route));

/// [profile] with [day] added, or updated when its event is already there.
///
/// A new day is driven in the car of the day added or moved to another car
/// last ([DriverProfile.lastCarId]), else
/// the first car, else a new car named [defaultCarName]: adding a day never
/// asks. An updated day keeps its car. Its track is the profile track its
/// route matches; a route no track matches adds a track named
/// [ProfileDayInput.trackName] or [defaultTrackName]. An updated day whose
/// route still matches its track, or that has no route, keeps it. Throws
/// [ProfileFormatError] for text or times [decodeDriverProfile] would refuse.
DriverProfile addDayToProfile(
  DriverProfile profile,
  ProfileDayInput day, {
  required String defaultCarName,
  required String defaultTrackName,
  Random? random,
}) {
  final cars = [...profile.cars];
  final tracks = [...profile.tracks];
  final existing = profile.day(day.eventId);

  var carId = existing?.carId;
  if (carId == null || profile.car(carId) == null) {
    carId = profile.lastCarId != null && profile.car(profile.lastCarId!) != null
        ? profile.lastCarId
        : cars.isEmpty
        ? null
        : cars.first.id;
    if (carId == null) {
      if (cars.length >= maximumProfileCars) {
        throw const ProfileFormatError('The profile has too many cars.');
      }
      final car = ProfileCar(id: newEventId(random), name: _text(defaultCarName, 'Car'));
      cars.add(car);
      carId = car.id;
    }
  }

  // Without a route (recordings missing, every lap left out) the day keeps
  // the track it had: the profile is authoritative for it.
  var trackId = existing?.trackId;
  final route = day.route;
  if (route != null) {
    final kept = existing?.trackId == null ? null : profile.track(existing!.trackId!);
    if (kept != null && routesMatch(kept.route, route)) {
      trackId = kept.id;
    } else {
      trackId = matchProfileTrack(profile, route)?.id;
      if (trackId == null) {
        if (tracks.length >= maximumProfileTracks) {
          throw const ProfileFormatError('The profile has too many tracks.');
        }
        final track = ProfileTrack(
          id: newEventId(random),
          name: _text(day.trackName ?? '', _text(defaultTrackName, 'Track')),
          route: route,
        );
        _verified(_encodeTrack(track), _track);
        tracks.add(track);
        trackId = track.id;
      }
    }
  }

  // Corners measured this time are placed on the track; a session not
  // measured this time keeps what was measured before, while it is on the
  // same track.
  var ids = const <String, String>{};
  final trackIndex = trackId == null ? -1 : tracks.indexWhere((track) => track.id == trackId);
  if (trackIndex >= 0 && day.cornerSpans.isNotEmpty) {
    final (corners, placed) = _placeCorners(tracks[trackIndex], day.cornerSpans, random);
    if (corners.length != tracks[trackIndex].corners.length) {
      tracks[trackIndex] = _verified(
        _encodeTrack(tracks[trackIndex].copyWith(corners: corners)),
        _track,
      );
    }
    ids = placed;
  }
  final sameTrack = existing != null && existing.trackId == trackId;
  // Past the profile's budget of corners, the day keeps none.
  var budget = maximumProfileCornerStats;
  for (final other in profile.days) {
    if (other.eventId == day.eventId) continue;
    for (final session in other.sessions) {
      budget -= session.stats?.corners.length ?? 0;
    }
  }
  final before = {
    if (sameTrack)
      for (final session in existing.sessions)
        if (session.stats != null) session.runId: session.stats!,
  };
  var sessions = [
    for (final session in day.sessions)
      switch (session.stats) {
        final stats? when day.measuredCorners => session._withStats(
          stats.withCorners([
            for (final corner in stats.corners)
              if (ids[corner.cornerId] case final id?) corner.withCorner(id),
          ], theoreticalBestSeconds: stats.theoreticalBestSeconds),
        ),
        final stats? => session._withStats(
          stats.withCorners(
            before[session.runId]?.corners ?? const [],
            theoreticalBestSeconds: before[session.runId]?.theoreticalBestSeconds,
          ),
        ),
        null => session._withStats(before[session.runId]),
      },
  ];
  if (sessions.fold(0, (sum, s) => sum + (s.stats?.corners.length ?? 0)) > budget) {
    sessions = [
      for (final session in sessions)
        session._withStats(
          session.stats?.withCorners(
            const [],
            theoreticalBestSeconds: session.stats!.theoreticalBestSeconds,
          ),
        ),
    ];
  }
  final entry = ProfileDay(
    eventId: day.eventId,
    file: day.file,
    name: day.name,
    carId: carId,
    trackId: trackId,
    startMilliseconds: day.startMilliseconds,
    sessions: sessions,
    bestLapSeconds: day.bestLapSeconds,
    theoreticalBestSeconds: day.measuredCorners
        ? day.theoreticalBestSeconds
        : day.theoreticalBestSeconds ?? (sameTrack ? existing.theoreticalBestSeconds : null),
    unknown: existing?.unknown ?? const {},
  );
  // What reading would refuse is refused here, so a profile is never
  // written that cannot be read back.
  _verified(_encodeDay(entry), _day);
  final days = [for (final other in profile.days) other.eventId == day.eventId ? entry : other];
  if (existing == null) {
    if (days.length >= maximumProfileDays) {
      throw const ProfileFormatError('The profile has too many days.');
    }
    days.add(entry);
  }
  // Only a new day sets the car new days take: adding a day again, such
  // as when it is opened, never changes it.
  return profile._copy(
    cars: cars,
    tracks: tracks,
    days: days,
    lastCarId: existing == null ? carId : profile.lastCarId,
  );
}

/// [profile] with a new car named [name]; the car is the last element of
/// the result's [DriverProfile.cars].
DriverProfile addProfileCar(DriverProfile profile, String name, {Random? random}) {
  if (profile.cars.length >= maximumProfileCars) {
    throw const ProfileFormatError('The profile has too many cars.');
  }
  return profile._copy(
    cars: [
      ...profile.cars,
      ProfileCar(id: newEventId(random), name: _text(name, 'Car')),
    ],
  );
}

/// [profile] with car [carId] renamed to [name] (blank keeps the name).
DriverProfile renameProfileCar(DriverProfile profile, String carId, String name) => profile._copy(
  cars: [
    for (final car in profile.cars)
      car.id == carId ? car.copyWith(name: _text(name, car.name)) : car,
  ],
);

/// [profile] with track [trackId] renamed to [name] (blank keeps the name).
DriverProfile renameProfileTrack(DriverProfile profile, String trackId, String name) =>
    profile._copy(
      tracks: [
        for (final track in profile.tracks)
          track.id == trackId ? track.copyWith(name: _text(name, track.name)) : track,
      ],
    );

/// [profile] with day [eventId] driven in car [carId], which new days then
/// take. Unchanged when either is not in the profile.
DriverProfile setProfileDayCar(DriverProfile profile, String eventId, String carId) {
  if (profile.car(carId) == null || profile.day(eventId) == null) return profile;
  return profile._copy(
    days: [
      for (final day in profile.days) day.eventId == eventId ? day.copyWith(carId: carId) : day,
    ],
    lastCarId: carId,
  );
}

/// [profile]'s other days at [trackId], most recent first; undated days last.
List<ProfileDay> earlierVisits(DriverProfile profile, String trackId, {String? exceptEventId}) {
  final visits = [
    for (final day in profile.days)
      if (day.trackId == trackId && day.eventId != exceptEventId) day,
  ];
  visits.sort((a, b) {
    final x = a.startMilliseconds, y = b.startMilliseconds;
    if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
    return y.compareTo(x);
  });
  return visits;
}

/// [value] trimmed and cut to [maximumProfileTextCharacters], or [fallback]
/// when blank.
String _text(String value, String fallback) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed.length > maximumProfileTextCharacters
      ? trimmed.substring(0, maximumProfileTextCharacters)
      : trimmed;
}

// ---------------------------------------------------------------------------
// Reading and writing

/// [profile] as the text of a `.feprofile` file. Throws
/// [ProfileFormatError] rather than write what [decodeDriverProfile] would
/// refuse.
String encodeDriverProfile(DriverProfile profile) {
  final json = <String, Object?>{
    ...profile.unknown,
    'format': driverProfileFormat,
    'version': driverProfileVersion,
    'driver': {...profile.unknownDriver, 'id': profile.driverId, 'name': profile.driverName},
    'cars': [
      for (final car in profile.cars)
        {...car.unknown, 'id': car.id, 'name': car.name, 'notes': car.notes},
    ],
    'tracks': [for (final track in profile.tracks) _encodeTrack(track)],
    'days': [for (final day in profile.days) _encodeDay(day)],
    'lastCarId': profile.lastCarId,
  };
  final String text;
  try {
    text = jsonEncode(json);
  } on JsonUnsupportedObjectError {
    throw const ProfileFormatError('The profile holds a value that cannot be written.');
  }
  decodeDriverProfile(text);
  return text;
}

/// [json] read back with [read] as it would be from a file.
T _verified<T>(Map<String, Object?> json, T Function(Object?) read) {
  try {
    return read(jsonDecode(jsonEncode(json)));
  } on JsonUnsupportedObjectError {
    throw const ProfileFormatError('The profile holds a value that cannot be written.');
  }
}

Map<String, Object?> _encodeTrack(ProfileTrack track) => {
  ...track.unknown,
  'id': track.id,
  'name': track.name,
  'route': {...track.unknownRoute, ..._encodeRoute(track.route)},
  if (track.corners.isNotEmpty)
    'corners': [for (final corner in track.corners) _encodeTrackCorner(corner)],
};

Map<String, Object?> _encodeDay(ProfileDay day) => {
  ...day.unknown,
  'eventId': day.eventId,
  'file': day.file,
  'name': day.name,
  'carId': day.carId,
  'trackId': day.trackId,
  'startMilliseconds': day.startMilliseconds,
  'bestLapSeconds': day.bestLapSeconds,
  if (day.theoreticalBestSeconds != null) 'theoreticalBestSeconds': day.theoreticalBestSeconds,
  'sessions': [
    for (final session in day.sessions)
      {
        ...session.unknown,
        'runId': session.runId,
        'name': session.name,
        'startMilliseconds': session.startMilliseconds,
        'lapCount': session.lapCount,
        'bestLapSeconds': session.bestLapSeconds,
        if (session.stats case final stats?) 'stats': _encodeStats(stats),
      },
  ],
};

double _round(double value) => (value * 10).roundToDouble() / 10;

Map<String, Object?> _encodeRoute(RouteShape route) => {
  'origin': [route.origin.latitudeDegrees, route.origin.longitudeDegrees],
  'lengthMeters': route.lengthMeters,
  'direction': route.direction.name,
  // A tenth of a metre is well inside the 10 m RMS a match allows.
  'points': [
    for (final point in route.points) [_round(point.eastMeters), _round(point.northMeters)],
  ],
};

/// The profile in [text], a `.feprofile` file's content. Throws
/// [ProfileFormatError] when it is not one this version reads; unknown keys
/// are kept for the next [encodeDriverProfile].
DriverProfile decodeDriverProfile(String text) {
  if (text.length > maximumProfileCharacters) {
    throw const ProfileFormatError('The profile is too large.');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text.startsWith('\uFEFF') ? text.substring(1) : text);
  } on FormatException catch (error) {
    throw ProfileFormatError('The profile is not valid JSON: ${error.message}');
  }
  final json = _map(decoded, 'profile');
  if (json['format'] != driverProfileFormat) {
    throw const ProfileFormatError('This is not a FlappedEar driver profile.');
  }
  final version = json['version'];
  if (version is! int || version < 1) {
    throw const ProfileFormatError('The profile has no valid version.');
  }
  if (version > driverProfileVersion) {
    throw const ProfileFormatError(
      'The profile was written by a newer version of the app.',
      newerVersion: true,
    );
  }
  final driver = _map(json['driver'], 'driver');
  final cars = _list(json['cars'], 'cars', maximumProfileCars, _car);
  final tracks = _list(json['tracks'], 'tracks', maximumProfileTracks, _track);
  final days = _list(json['days'], 'days', maximumProfileDays, _day);
  _unique([for (final car in cars) car.id], 'car');
  _unique([for (final track in tracks) track.id], 'track');
  _unique([for (final day in days) day.eventId], 'day');
  final carIds = {for (final car in cars) car.id};
  final trackIds = {for (final track in tracks) track.id};
  for (final day in days) {
    if (!carIds.contains(day.carId)) {
      throw ProfileFormatError('Day ${day.eventId} names a car the profile does not have.');
    }
    if (day.trackId != null && !trackIds.contains(day.trackId)) {
      throw ProfileFormatError('Day ${day.eventId} names a track the profile does not have.');
    }
  }
  final lastCarId = _optionalString(json['lastCarId'], 'lastCarId');
  return DriverProfile(
    driverId: _string(driver['id'], 'driver id', allowEmpty: false),
    driverName: _string(driver['name'] ?? '', 'driver name'),
    cars: cars,
    tracks: tracks,
    days: days,
    lastCarId: carIds.contains(lastCarId) ? lastCarId : null,
    unknown: _without(json, const [
      'format',
      'version',
      'driver',
      'cars',
      'tracks',
      'days',
      'lastCarId',
    ]),
    unknownDriver: _without(driver, const ['id', 'name']),
  );
}

ProfileCar _car(Object? value) {
  final json = _map(value, 'car');
  return ProfileCar(
    id: _string(json['id'], 'car id', allowEmpty: false),
    name: _string(json['name'], 'car name', allowEmpty: false),
    notes: _string(json['notes'] ?? '', 'car notes'),
    unknown: _without(json, const ['id', 'name', 'notes']),
  );
}

ProfileTrack _track(Object? value) {
  final json = _map(value, 'track');
  final corners = _list(json['corners'], 'track corners', maximumProfileCorners, _trackCorner);
  _unique([for (final corner in corners) corner.id], 'track corner');
  return ProfileTrack(
    id: _string(json['id'], 'track id', allowEmpty: false),
    name: _string(json['name'], 'track name', allowEmpty: false),
    route: _route(json['route']),
    corners: corners,
    unknown: _without(json, const ['id', 'name', 'route', 'corners']),
    unknownRoute: _without(_map(json['route'], 'route'), const [
      'origin',
      'lengthMeters',
      'direction',
      'points',
    ]),
  );
}

RouteShape _route(Object? value) {
  final json = _map(value, 'route');
  final origin = json['origin'];
  if (origin is! List || origin.length != 2) {
    throw const ProfileFormatError('A track route has no valid origin.');
  }
  final latitude = _double(origin[0], 'route origin');
  final longitude = _double(origin[1], 'route origin');
  final coordinate = GeoCoordinate(latitude, longitude);
  if (!isValidCoordinate(coordinate)) {
    throw const ProfileFormatError('A track route has no valid origin.');
  }
  final length = _double(json['lengthMeters'], 'route length');
  if (length < 100 || length > 30000) {
    throw const ProfileFormatError('A track route has an impossible length.');
  }
  final direction = switch (json['direction']) {
    'clockwise' => TrackDirection.clockwise,
    'counterclockwise' => TrackDirection.counterclockwise,
    _ => throw const ProfileFormatError('A track route has no valid direction.'),
  };
  final points = json['points'];
  if (points is! List || points.length != routeShapePointCount) {
    throw const ProfileFormatError('A track route does not have $routeShapePointCount points.');
  }
  return RouteShape(
    origin: coordinate,
    lengthMeters: length,
    direction: direction,
    points: List.unmodifiable([
      for (final point in points)
        if (point is List && point.length == 2)
          MetricPoint(_coordinate(point[0]), _coordinate(point[1]))
        else
          throw const ProfileFormatError('A track route has an invalid point.'),
    ]),
  );
}

ProfileDay _day(Object? value) {
  final json = _map(value, 'day');
  final sessions = _list(json['sessions'], 'sessions', maximumDayRuns, _session);
  if ({for (final session in sessions) session.runId}.length != sessions.length) {
    throw const ProfileFormatError('A day has the same session twice.');
  }
  return ProfileDay(
    eventId: _string(json['eventId'], 'day event id', allowEmpty: false),
    file: _checkFile(_string(json['file'], 'day file', allowEmpty: false)),
    name: _string(json['name'], 'day name'),
    carId: _string(json['carId'], 'day car', allowEmpty: false),
    trackId: _optionalString(json['trackId'], 'day track'),
    startMilliseconds: _optionalInt(json['startMilliseconds'], 'day start'),
    bestLapSeconds: _optionalSeconds(json['bestLapSeconds'], 'day best lap'),
    theoreticalBestSeconds: _optionalSeconds(
      json['theoreticalBestSeconds'],
      'day theoretical best',
    ),
    sessions: sessions,
    unknown: _without(json, const [
      'eventId',
      'file',
      'name',
      'carId',
      'trackId',
      'startMilliseconds',
      'bestLapSeconds',
      'theoreticalBestSeconds',
      'sessions',
    ]),
  );
}

ProfileSession _session(Object? value) {
  final json = _map(value, 'session');
  final laps = json['lapCount'] ?? 0;
  if (laps is! int || laps < 0) {
    throw const ProfileFormatError('A session has an invalid lap count.');
  }
  return ProfileSession(
    runId: _string(json['runId'], 'session run id', allowEmpty: false),
    name: _string(json['name'], 'session name'),
    startMilliseconds: _optionalInt(json['startMilliseconds'], 'session start'),
    lapCount: laps,
    bestLapSeconds: _optionalSeconds(json['bestLapSeconds'], 'session best lap'),
    stats: json['stats'] == null ? null : _stats(json['stats']),
    unknown: _without(json, const [
      'runId',
      'name',
      'startMilliseconds',
      'lapCount',
      'bestLapSeconds',
      'stats',
    ]),
  );
}

Map<String, Object?> _map(Object? value, String what) {
  if (value is Map<String, Object?>) return value;
  throw ProfileFormatError('The $what is not an object.');
}

List<T> _list<T>(Object? value, String what, int maximum, T Function(Object?) read) {
  if (value == null) return const [];
  if (value is! List) throw ProfileFormatError('The $what are not a list.');
  if (value.length > maximum) throw ProfileFormatError('The profile has too many $what.');
  return [for (final item in value) read(item)];
}

String _string(Object? value, String what, {bool allowEmpty = true}) {
  if (value is! String ||
      (!allowEmpty && value.trim().isEmpty) ||
      value.length > maximumProfileTextCharacters ||
      value.contains('\u0000')) {
    throw ProfileFormatError('The $what is not valid text.');
  }
  return value;
}

String? _optionalString(Object? value, String what) =>
    value == null ? null : _string(value, what, allowEmpty: false);

int? _optionalInt(Object? value, String what) {
  if (value == null) return null;
  if (value is! int) throw ProfileFormatError('The $what is not a whole number.');
  return _checkMilliseconds(value, what);
}

/// The furthest time kept, in milliseconds either side of 1970: what a
/// [DateTime] holds less two days, so its local date can still be built in
/// any time zone.
const _maximumMilliseconds = 8640000000000000 - 2 * 86400000;

int? _keptMilliseconds(int? value) =>
    value != null && value.abs() <= _maximumMilliseconds ? value : null;

int? _checkMilliseconds(int? value, String what) {
  if (value != null && value.abs() > _maximumMilliseconds) {
    throw ProfileFormatError('The $what is out of range.');
  }
  return value;
}

void _checkText(String value, String what, {bool allowEmpty = true}) =>
    _string(value, what, allowEmpty: allowEmpty);

/// [file] when it is a relative path inside the profile's folder.
String _checkFile(String file) {
  _checkText(file, 'day file', allowEmpty: false);
  final parts = file.split(RegExp(r'[\\/]'));
  // A leading or doubled separator leaves an empty part; ':' is a drive or
  // an NTFS stream; Windows drops trailing dots and spaces from a name.
  if (file.contains(':') ||
      parts.any(
        (part) =>
            part.isEmpty ||
            RegExp(r'^[. ]+$').hasMatch(part) ||
            part.endsWith('.') ||
            part.endsWith(' '),
      )) {
    throw const ProfileFormatError('A day file is not inside the profile.');
  }
  return file;
}

/// A route point's coordinate: at most 50 km from the origin, as a route is
/// at most 30 km long.
double _coordinate(Object? value) {
  final metres = _double(value, 'route point');
  if (metres.abs() > 50000) throw const ProfileFormatError('A track route point is too far.');
  return metres;
}

/// The deepest nesting of a value kept from a newer version.
const _maximumUnknownDepth = 64;

/// [value] when it nests at most [_maximumUnknownDepth] deep, checked
/// without recursion, so writing it back cannot overflow the stack.
Object? _bounded(Object? value) {
  final pending = <(Object?, int)>[(value, 1)];
  while (pending.isNotEmpty) {
    final (item, depth) = pending.removeLast();
    if (item is double && !item.isFinite) {
      throw const ProfileFormatError('The profile holds a number too large to keep.');
    }
    if (item is! Map && item is! List) continue;
    if (depth > _maximumUnknownDepth) {
      throw const ProfileFormatError('The profile nests too deeply.');
    }
    final children = item is Map ? item.values : item as List;
    for (final child in children) {
      pending.add((child, depth + 1));
    }
  }
  return value;
}

double _double(Object? value, String what) {
  if (value is! num || !value.isFinite) throw ProfileFormatError('The $what is not a number.');
  return value.toDouble();
}

double? _optionalSeconds(Object? value, String what) {
  if (value == null) return null;
  final seconds = _double(value, what);
  if (seconds <= 0) throw ProfileFormatError('The $what is not a positive time.');
  return seconds;
}

void _unique(List<String> ids, String what) {
  if (ids.toSet().length != ids.length) {
    throw ProfileFormatError('The profile has the same $what twice.');
  }
}

Map<String, Object?> _without(Map<String, Object?> json, List<String> known) => {
  for (final MapEntry(:key, :value) in json.entries)
    if (!known.contains(key)) key: _bounded(value),
};
