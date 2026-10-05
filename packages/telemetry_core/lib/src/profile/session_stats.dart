part of 'driver_profile.dart';

// What each session measured, kept in the profile so analysis across days
// never re-opens old days. Measurements only, in SI units, each with the
// laps it came from; levels, trends and focus areas are worked out when
// read (profile_aggregates.dart), so a better rule re-scores all history.

/// The most corners a track or a session keeps.
const maximumProfileCorners = 128;

/// The most session corners a whole profile keeps, so it stays well inside
/// [maximumProfileCharacters] at [maximumProfileDays]: past it, a day is
/// still added, without its corners.
const maximumProfileCornerStats = 60000;

/// Moving faster than this counts as driving.
const drivingSpeedMetresPerSecond = 2.0;

/// A corner of a track, the same place on every visit: its span as
/// fractions (0–1) of the track's stored route, in driving direction. A span
/// may wrap past the start line ([start] > [end]).
final class TrackCorner {
  TrackCorner({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    Map<String, Object?> unknown = const {},
  }) : unknown = Map.unmodifiable(unknown);

  final String id;
  final String name;
  final double start;
  final double end;
  final Map<String, Object?> unknown;

  /// Its length as a fraction of the lap.
  double get span => _arc(start, end);
}

/// A corner as one day's analysis found it: its segment and where it starts
/// and ends on the ground, placed on the track's route when the day is added.
final class DayCornerSpan {
  const DayCornerSpan({
    required this.segmentId,
    required this.name,
    required this.start,
    required this.end,
  });

  final String segmentId;
  final String name;
  final GeoCoordinate start;
  final GeoCoordinate end;
}

/// One corner in one session: medians over the session's ranked laps.
final class CornerStats {
  CornerStats({
    required this.cornerId,
    required this.laps,
    this.minimumSpeed,
    this.bestMinimumSpeed,
    this.exitSpeed,
    this.bestExitSpeed,
    this.brakingSpreadMeters,
    this.lossSeconds,
    Map<String, Object?> unknown = const {},
  }) : unknown = Map.unmodifiable(unknown);

  /// The track's corner ([TrackCorner.id]); while a day is measured, its
  /// segment id.
  final String cornerId;

  /// Ranked laps measured here.
  final int laps;

  /// Median and highest minimum speed, m/s; null without a speed in a known
  /// unit.
  final double? minimumSpeed;
  final double? bestMinimumSpeed;

  /// Median and highest exit speed, m/s.
  final double? exitSpeed;
  final double? bestExitSpeed;

  /// Interquartile range of the braking point, metres; null below 3 laps.
  final double? brakingSpreadMeters;

  /// Median time lost here against the group's fastest time, seconds.
  final double? lossSeconds;
  final Map<String, Object?> unknown;

  CornerStats withCorner(String id) => CornerStats(
    cornerId: id,
    laps: laps,
    minimumSpeed: minimumSpeed,
    bestMinimumSpeed: bestMinimumSpeed,
    exitSpeed: exitSpeed,
    bestExitSpeed: bestExitSpeed,
    brakingSpreadMeters: brakingSpreadMeters,
    lossSeconds: lossSeconds,
    unknown: unknown,
  );
}

/// What a session measured, for analysis across days.
final class SessionStats {
  SessionStats({
    this.distanceMeters,
    this.drivingSeconds,
    this.rankedLaps = 0,
    this.medianLapSeconds,
    this.lapSpreadSeconds,
    this.theoreticalBestSeconds,
    this.otherLayout = false,
    List<CornerStats> corners = const [],
    Map<String, Object?> unknown = const {},
  }) : corners = List.unmodifiable(corners),
       unknown = Map.unmodifiable(unknown);

  /// Driven on another layout than the day's track: its laps and times are
  /// not the track's, so only totals count it.
  final bool otherLayout;

  /// Distance driven, out and in laps included; null without speed or GPS.
  final double? distanceMeters;

  /// Time moving faster than [drivingSpeedMetresPerSecond].
  final double? drivingSeconds;

  /// Eligible laps of the session's track.
  final int rankedLaps;

  /// Median of the ranked laps; null without one.
  final double? medianLapSeconds;

  /// Interquartile range of the ranked laps; null below 3 laps.
  final double? lapSpreadSeconds;

  /// The session's own best segments added up; null unless every segment
  /// was timed on a ranked lap.
  final double? theoreticalBestSeconds;
  final List<CornerStats> corners;
  final Map<String, Object?> unknown;

  SessionStats withCorners(List<CornerStats> corners, {double? theoreticalBestSeconds}) =>
      SessionStats(
        distanceMeters: distanceMeters,
        drivingSeconds: drivingSeconds,
        rankedLaps: rankedLaps,
        medianLapSeconds: medianLapSeconds,
        lapSpreadSeconds: lapSpreadSeconds,
        theoreticalBestSeconds: theoreticalBestSeconds,
        otherLayout: otherLayout,
        corners: corners,
        unknown: unknown,
      );
}

/// The arc from [start] to [end] along a lap, as a fraction (0–1).
double _arc(double start, double end) => end >= start ? end - start : 1 - start + end;

/// How much of the arc [aStart]–[aEnd] the arc [bStart]–[bEnd] covers.
double _overlap(double aStart, double aEnd, double bStart, double bEnd) {
  // Each arc unrolled to one interval; b is tried a lap earlier and later
  // too, so a span across the start line still meets its neighbours.
  final aUntil = aStart + _arc(aStart, aEnd), bUntil = bStart + _arc(bStart, bEnd);
  var total = 0.0;
  for (final shift in const [-1.0, 0.0, 1.0]) {
    final low = max(aStart, bStart + shift), high = min(aUntil, bUntil + shift);
    if (high > low) total += high - low;
  }
  return total;
}

// ---------------------------------------------------------------------------
// Measuring a day

/// Per session of [analysis]: what it measured, from its recordings
/// [sessions] (by run id) and, when ready, the day's theoretical best
/// [best] (corners, segment times). A session missing from [sessions] has
/// no distance; without [best] there are no corners.
Map<String, SessionStats> measureSessions(
  DayAnalysis analysis,
  Map<String, TelemetrySession?> sessions, {
  DayTheoreticalBest? best,
}) {
  final ranked = <String, List<double>>{};
  final rankedRows = <String, Set<DayLapReference>>{};
  for (final group in analysis.groups) {
    for (final row in group.ranking?.eligibleLaps ?? const <DayLapRow>[]) {
      ranked.putIfAbsent(row.runId, () => []).add(row.durationSeconds);
      rankedRows.putIfAbsent(row.runId, () => {}).add(row.reference);
    }
  }
  final ready = best != null && best.state == DayTheoreticalBestState.ready ? best : null;
  final dayTrack = {...?analysis.chosenGroup?.runIds};
  final result = <String, SessionStats>{};
  for (final runId in {for (final row in analysis.rows) row.runId}) {
    final laps = ranked[runId] ?? const <double>[];
    final summary = summarizeConsistency(laps);
    final (distance, driving) = _travel(sessions[runId]);
    result[runId] = SessionStats(
      distanceMeters: _positive(distance, _maximumDistance),
      drivingSeconds: _positive(driving, _maximumDuration),
      rankedLaps: laps.length,
      otherLayout: !dayTrack.contains(runId),
      medianLapSeconds: _positive(laps.isEmpty ? null : _median(laps), _maximumSeconds),
      lapSpreadSeconds: summary.available && laps.length >= 3
          ? _nonNegative(summary.interquartileRange, _maximumSeconds)
          : null,
      theoreticalBestSeconds: ready == null
          ? null
          : _sessionTheoreticalBest(ready, rankedRows[runId] ?? const {}),
      corners: ready == null
          ? const []
          : _cornerStats(ready, rankedRows[runId] ?? const {}, sessions[runId]),
    );
  }
  return result;
}

/// Where each corner of [best] starts and ends on the ground. Its axis is
/// in the recordings' own longitudes: [longitudeIsWestPositive] when they
/// count west as positive (`gpsLongitudeConvention`), as a profile's
/// routes never do.
List<DayCornerSpan> measureCornerSpans(
  DayTheoreticalBest? best, {
  bool longitudeIsWestPositive = false,
}) {
  final axis = best?.computed?.axis;
  if (best == null || best.state != DayTheoreticalBestState.ready || axis == null) {
    return const [];
  }
  if (!axis.valid || axis.points.isEmpty || axis.spacingMeters <= 0) return const [];
  GeoCoordinate at(double progress) {
    final count = axis.points.length;
    final index = ((progress / axis.spacingMeters).round() % count + count) % count;
    final point = axis.points[index];
    final raw = unprojectCoordinate(point.eastMeters, point.northMeters, axis.origin);
    return longitudeIsWestPositive
        ? GeoCoordinate(raw.latitudeDegrees, -raw.longitudeDegrees)
        : raw;
  }

  return [
    for (final corner in best.corners.take(maximumProfileCorners))
      DayCornerSpan(
        segmentId: corner.segmentId,
        name: corner.name,
        start: at(corner.startProgressMeters),
        end: at(corner.endProgressMeters),
      ),
  ];
}

/// Distance and time moving in [session]: from its speed in a known unit,
/// else from its GPS positions. Gaps are not counted.
(double?, double?) _travel(TelemetrySession? session) {
  if (session == null) return (null, null);
  // A day is measured again after every save; its samples rarely change.
  // They are shared, never copied, by the sessions analysis builds, so
  // they key the result.
  final key = (session.channel('speed') ?? session.channel('latitude'))?.values;
  if (key == null) return (null, null);
  final unit = effectiveChannelUnit(session, session.aliases['speed'] ?? 'speed');
  final cached = _travelled[key]?[unit];
  if (cached != null) return cached;
  final result = _measureTravel(session);
  (_travelled[key] ??= {})[unit] = result;
  return result;
}

final _travelled = Expando<Map<String, (double?, double?)>>('travel');

(double?, double?) _measureTravel(TelemetrySession session) {
  const maximumStep = 1.0;
  final speed = session.channel('speed');
  final factor = speed == null
      ? null
      : _speedFactor(effectiveChannelUnit(session, session.aliases['speed'] ?? 'speed'));
  if (speed != null && factor != null && speed.sampleCount > 1) {
    var distance = 0.0, driving = 0.0;
    for (var i = 1; i < speed.sampleCount; i++) {
      final dt = speed.timestamps[i] - speed.timestamps[i - 1];
      if (!(dt > 0) || dt > maximumStep) continue;
      final a = speed.values[i - 1] * factor, b = speed.values[i] * factor;
      if (!a.isFinite || !b.isFinite || a < 0 || b < 0) continue;
      distance += (a + b) / 2 * dt;
      if ((a + b) / 2 > drivingSpeedMetresPerSecond) driving += dt;
    }
    return (distance, driving);
  }
  // From GPS: positions a second or more apart, so jitter while parked
  // (a metre or so) never reads as driving; steps over 3 s are gaps.
  final latitude = session.channel('latitude'), longitude = session.channel('longitude');
  if (latitude == null || longitude == null) return (null, null);
  final count = min(latitude.sampleCount, longitude.sampleCount);
  var distance = 0.0, driving = 0.0;
  GeoCoordinate? previous;
  var previousTime = 0.0;
  for (var i = 0; i < count; i++) {
    final point = GeoCoordinate(latitude.values[i].toDouble(), longitude.values[i].toDouble());
    final time = latitude.timestamps[i];
    if (!isValidCoordinate(point) || !time.isFinite) continue;
    if (previous != null) {
      final dt = time - previousTime;
      if (dt < 1 && dt > 0) continue;
      if (dt > 0 && dt <= 3) {
        final step = projectCoordinate(point, previous);
        final metres = sqrt(
          step.eastMeters * step.eastMeters + step.northMeters * step.northMeters,
        );
        // A jump faster than 100 m/s is a GPS glitch, not driving.
        if (metres / dt <= 100 && metres / dt > drivingSpeedMetresPerSecond) {
          distance += metres;
          driving += dt;
        }
      }
    }
    previous = point;
    previousTime = time;
  }
  return (distance, driving);
}

/// Metres per second in one [unit]; null when the unit is not declared
/// (an unlabelled speed may be km/h or mph) or not known.
double? _speedFactor(String unit) => unit.trim().isEmpty ? null : metresPerSecondPerSpeedUnit(unit);

double? _sessionTheoreticalBest(DayTheoreticalBest best, Set<DayLapReference> ranked) {
  List<double?>? fastest;
  for (final lap in best.laps) {
    if (!ranked.contains(lap.lap.reference) || !lap.times.completePartition) continue;
    final count = lap.times.sectors.length;
    fastest ??= List<double?>.filled(count, null);
    if (fastest.length != count) return null;
    for (var i = 0; i < count; i++) {
      final seconds = lap.seconds(i);
      if (seconds != null && seconds > 0 && (fastest[i] == null || seconds < fastest[i]!)) {
        fastest[i] = seconds;
      }
    }
  }
  if (fastest == null || fastest.isEmpty || fastest.any((s) => s == null)) return null;
  return _positive(fastest.fold<double>(0, (sum, s) => sum + s!), _maximumSeconds);
}

List<CornerStats> _cornerStats(
  DayTheoreticalBest best,
  Set<DayLapReference> ranked,
  TelemetrySession? session,
) {
  final losses = <DayLapReference, List<double?>>{
    for (final lap in best.laps)
      if (ranked.contains(lap.lap.reference)) lap.lap.reference: lap.lossSeconds,
  };
  final result = <CornerStats>[];
  for (final corner in best.corners.take(maximumProfileCorners)) {
    final minimum = <double>[], exit = <double>[], braking = <double>[], loss = <double>[];
    var laps = 0;
    for (final (row, metrics) in corner.laps) {
      if (!ranked.contains(row.reference)) continue;
      laps++;
      final factor = _speedFactor(metrics.speeds.unit);
      final low = metrics.speeds.minimum.value, out = metrics.speeds.exit.value;
      if (factor != null && low != null && low.isFinite) minimum.add(low * factor);
      if (factor != null && out != null && out.isFinite) exit.add(out * factor);
      final point = metrics.braking.brakingPointMeters;
      if (point != null && point.isFinite) braking.add(point);
      final lapLoss = losses[row.reference];
      if (lapLoss != null && corner.segmentIndex < lapLoss.length) {
        final value = lapLoss[corner.segmentIndex];
        if (value != null && value.isFinite) loss.add(value);
      }
    }
    if (laps == 0) continue;
    final spread = summarizeConsistency(braking);
    result.add(
      CornerStats(
        cornerId: corner.segmentId,
        laps: laps,
        minimumSpeed: _positive(minimum.isEmpty ? null : _median(minimum), _maximumSpeed),
        bestMinimumSpeed: _positive(minimum.isEmpty ? null : minimum.reduce(max), _maximumSpeed),
        exitSpeed: _positive(exit.isEmpty ? null : _median(exit), _maximumSpeed),
        bestExitSpeed: _positive(exit.isEmpty ? null : exit.reduce(max), _maximumSpeed),
        brakingSpreadMeters: braking.length >= 3 && spread.available
            ? _nonNegative(spread.interquartileRange, _maximumSeconds)
            : null,
        lossSeconds: _nonNegative(loss.isEmpty ? null : _median(loss), _maximumSeconds),
      ),
    );
  }
  return result;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

// What a profile keeps of a measurement. Beyond them a value is a fault (a
// GPS spike, a speed in another unit than declared): it is left out, never
// a reason to refuse the day.
const _maximumSpeed = 200.0; // m/s, 720 km/h
const _maximumDistance = 1e7; // m
const _maximumDuration = 1e6; // s
const _maximumSeconds = 1e5; // s, also metres of braking spread

double? _positive(double? value, double maximum) =>
    value != null && value.isFinite && value > 0 && value <= maximum ? _rounded(value) : null;

double? _nonNegative(double? value, double maximum) =>
    value != null && value.isFinite && value >= 0 && value <= maximum ? _rounded(value) : null;

/// [value] to a thousandth: a millisecond, a millimetre, a mm/s; keeps the
/// profile small.
double _rounded(double value) => (value * 1000).roundToDouble() / 1000;

// ---------------------------------------------------------------------------
// Placing a day's corners on its track

/// Where [point] lies along [route], as a fraction of the lap; null when it
/// is more than 50 m from the route.
double? _routeFraction(RouteShape route, GeoCoordinate point) {
  final local = projectCoordinate(point, route.origin);
  var best = -1;
  var bestDistance = double.infinity;
  for (var i = 0; i < route.points.length; i++) {
    final p = route.points[i];
    final east = p.eastMeters - local.eastMeters, north = p.northMeters - local.northMeters;
    final d = sqrt(east * east + north * north);
    if (d < bestDistance) (best, bestDistance) = (i, d);
  }
  if (best < 0 || bestDistance > 50) return null;
  return best / route.points.length;
}

/// [track]'s corners with [spans] placed on its route, and each span's
/// track corner id (by segment id). A span covering at least half of a
/// known corner not taken yet, or half of which one covers, is that corner;
/// otherwise it is a new corner.
(List<TrackCorner>, Map<String, String>) _placeCorners(
  ProfileTrack track,
  List<DayCornerSpan> spans,
  Random? random,
) {
  final corners = [...track.corners];
  final ids = <String, String>{};
  // Each track corner takes one of the day's corners at most, so a session
  // never counts the same corner twice.
  final taken = <String>{};
  for (final span in spans) {
    final start = _routeFraction(track.route, span.start);
    final end = _routeFraction(track.route, span.end);
    if (start == null || end == null || start == end) continue;
    final length = _arc(start, end);
    // A span over half the lap is not one corner.
    if (length > 0.5) continue;
    TrackCorner? match;
    var matched = 0.0;
    for (final corner in corners) {
      if (taken.contains(corner.id)) continue;
      final shared = _overlap(start, end, corner.start, corner.end);
      final share = max(shared / length, corner.span > 0 ? shared / corner.span : 0.0);
      if (share >= 0.5 && share > matched) (match, matched) = (corner, share);
    }
    if (match == null) {
      if (corners.length >= maximumProfileCorners) continue;
      // The day's own name for it; renamed in the Library.
      match = TrackCorner(
        id: newEventId(random),
        name: span.name,
        start: (start * 10000).roundToDouble() / 10000,
        end: (end * 10000).roundToDouble() / 10000,
      );
      corners.add(match);
    }
    ids[span.segmentId] = match.id;
    taken.add(match.id);
  }
  return (corners, ids);
}

// ---------------------------------------------------------------------------
// Reading and writing

Map<String, Object?> _encodeTrackCorner(TrackCorner corner) => {
  ...corner.unknown,
  'id': corner.id,
  'name': corner.name,
  'start': corner.start,
  'end': corner.end,
};

TrackCorner _trackCorner(Object? value) {
  final json = _map(value, 'track corner');
  return TrackCorner(
    id: _string(json['id'], 'track corner id', allowEmpty: false),
    name: _string(json['name'], 'track corner name'),
    start: _fraction(json['start'], 'track corner start'),
    end: _fraction(json['end'], 'track corner end'),
    unknown: _without(json, const ['id', 'name', 'start', 'end']),
  );
}

// Absent values are left out, so a profile of many days stays small.
Map<String, Object?> _encodeStats(SessionStats stats) => {
  ...stats.unknown,
  'distanceMeters': ?stats.distanceMeters,
  'drivingSeconds': ?stats.drivingSeconds,
  'rankedLaps': stats.rankedLaps,
  'medianLapSeconds': ?stats.medianLapSeconds,
  'lapSpreadSeconds': ?stats.lapSpreadSeconds,
  'theoreticalBestSeconds': ?stats.theoreticalBestSeconds,
  if (stats.otherLayout) 'otherLayout': true,
  if (stats.corners.isNotEmpty)
    'corners': [
      for (final corner in stats.corners)
        {
          ...corner.unknown,
          'cornerId': corner.cornerId,
          'laps': corner.laps,
          'minimumSpeed': ?corner.minimumSpeed,
          'bestMinimumSpeed': ?corner.bestMinimumSpeed,
          'exitSpeed': ?corner.exitSpeed,
          'bestExitSpeed': ?corner.bestExitSpeed,
          'brakingSpreadMeters': ?corner.brakingSpreadMeters,
          'lossSeconds': ?corner.lossSeconds,
        },
    ],
};

SessionStats _stats(Object? value) {
  final json = _map(value, 'session stats');
  final corners = _list(json['corners'], 'session corners', maximumProfileCorners, _cornerStatsOf);
  _unique([for (final corner in corners) corner.cornerId], 'session corner');
  return SessionStats(
    distanceMeters: _optionalMeasure(json['distanceMeters'], 'session distance', 1e7),
    drivingSeconds: _optionalMeasure(json['drivingSeconds'], 'session driving time', 1e6),
    rankedLaps: _count(json['rankedLaps'], 'ranked laps'),
    medianLapSeconds: _optionalMeasure(json['medianLapSeconds'], 'median lap', 1e5),
    lapSpreadSeconds: _optionalMeasure(json['lapSpreadSeconds'], 'lap spread', 1e5),
    theoreticalBestSeconds: _optionalMeasure(
      json['theoreticalBestSeconds'],
      'session theoretical best',
      1e5,
    ),
    otherLayout: switch (json['otherLayout']) {
      null || false => false,
      true => true,
      _ => throw const ProfileFormatError('The session layout is not valid.'),
    },
    corners: corners,
    unknown: _without(json, const [
      'otherLayout',
      'distanceMeters',
      'drivingSeconds',
      'rankedLaps',
      'medianLapSeconds',
      'lapSpreadSeconds',
      'theoreticalBestSeconds',
      'corners',
    ]),
  );
}

CornerStats _cornerStatsOf(Object? value) {
  final json = _map(value, 'corner stats');
  // 200 m/s (720 km/h) bounds every speed.
  return CornerStats(
    cornerId: _string(json['cornerId'], 'corner id', allowEmpty: false),
    laps: _count(json['laps'], 'corner laps'),
    minimumSpeed: _optionalMeasure(json['minimumSpeed'], 'minimum speed', 200),
    bestMinimumSpeed: _optionalMeasure(json['bestMinimumSpeed'], 'best minimum speed', 200),
    exitSpeed: _optionalMeasure(json['exitSpeed'], 'exit speed', 200),
    bestExitSpeed: _optionalMeasure(json['bestExitSpeed'], 'best exit speed', 200),
    brakingSpreadMeters: _optionalMeasure(json['brakingSpreadMeters'], 'braking spread', 1e5),
    lossSeconds: _optionalMeasure(json['lossSeconds'], 'corner loss', 1e5),
    unknown: _without(json, const [
      'cornerId',
      'laps',
      'minimumSpeed',
      'bestMinimumSpeed',
      'exitSpeed',
      'bestExitSpeed',
      'brakingSpreadMeters',
      'lossSeconds',
    ]),
  );
}

double _fraction(Object? value, String what) {
  final fraction = _double(value, what);
  if (fraction < 0 || fraction >= 1) throw ProfileFormatError('The $what is out of range.');
  return fraction;
}

int _count(Object? value, String what) {
  final count = value ?? 0;
  if (count is! int || count < 0 || count > 1000000) {
    throw ProfileFormatError('The $what is not a valid count.');
  }
  return count;
}

/// A measurement from 0 to [maximum], or null.
double? _optionalMeasure(Object? value, String what, double maximum) {
  if (value == null) return null;
  final measure = _double(value, what);
  if (measure < 0 || measure > maximum) throw ProfileFormatError('The $what is out of range.');
  return measure;
}
