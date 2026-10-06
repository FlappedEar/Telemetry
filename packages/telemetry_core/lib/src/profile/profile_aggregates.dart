// What a driver profile says across days: totals, records per track,
// progress visit by visit, a corner's history, repeated losses and skill
// levels. Worked out when read from the measurements each session keeps
// (session_stats.dart), so a better rule re-scores all history and nothing
// here is stored.
//
// Lap times are compared only on the same track, which is also the same
// direction (a track's route has one), and per car where a car is given.
// Totals mix everything.
import 'dart:math';

import 'driver_profile.dart';

/// Days in date order: dated days by start, then undated ones as added.
List<ProfileDay> _ordered(Iterable<ProfileDay> days) {
  final list = [...days];
  final order = {for (var i = 0; i < list.length; i++) list[i].eventId: i};
  list.sort((a, b) {
    final x = a.startMilliseconds, y = b.startMilliseconds;
    if (x != null && y != null && x != y) return x.compareTo(y);
    if (x == null && y != null) return 1;
    if (x != null && y == null) return -1;
    return order[a.eventId]!.compareTo(order[b.eventId]!);
  });
  return list;
}

/// [day]'s sessions on its track: not those measured on another layout.
Iterable<ProfileSession> _onTrack(ProfileDay day) =>
    day.sessions.where((session) => session.stats?.otherLayout != true);

Iterable<ProfileDay> _visits(DriverProfile profile, String trackId, String? carId) => _ordered(
  profile.days.where((day) => day.trackId == trackId && (carId == null || day.carId == carId)),
);

/// The mean of [values] weighted by [weights]; null when no weight.
double? _weighted(Iterable<(double?, int)> values) {
  var sum = 0.0, weight = 0;
  for (final (value, count) in values) {
    if (value == null || count <= 0) continue;
    sum += value * count;
    weight += count;
  }
  return weight == 0 ? null : sum / weight;
}

// ---------------------------------------------------------------------------
// Totals

/// How much was driven.
final class ProfileTotals {
  const ProfileTotals({
    this.days = 0,
    this.sessions = 0,
    this.laps = 0,
    this.rankedLaps = 0,
    this.distanceMeters = 0,
    this.drivingSeconds = 0,
    this.measuredSessions = 0,
    this.tracks = 0,
    this.cars = 0,
    this.firstMilliseconds,
    this.lastMilliseconds,
  });

  final int days;
  final int sessions;

  /// Timed laps, and of them the ranked ones.
  final int laps;
  final int rankedLaps;

  /// Distance and driving time of the [measuredSessions]: sessions not yet
  /// measured (added before this version, or without speed and GPS) count
  /// in [sessions] only.
  final double distanceMeters;
  final double drivingSeconds;
  final int measuredSessions;

  /// Different tracks and cars.
  final int tracks;
  final int cars;

  /// The first and last dated day's start, Unix milliseconds.
  final int? firstMilliseconds;
  final int? lastMilliseconds;
}

ProfileTotals _totals(Iterable<ProfileDay> days) {
  var count = 0, sessions = 0, laps = 0, ranked = 0, measured = 0;
  var distance = 0.0, driving = 0.0;
  final tracks = <String>{}, cars = <String>{};
  int? first, last;
  for (final day in days) {
    count++;
    if (day.trackId != null) tracks.add(day.trackId!);
    cars.add(day.carId);
    final start = day.startMilliseconds;
    if (start != null) {
      if (first == null || start < first) first = start;
      if (last == null || start > last) last = start;
    }
    for (final session in day.sessions) {
      sessions++;
      laps += session.lapCount;
      final stats = session.stats;
      if (stats == null) continue;
      ranked += stats.rankedLaps;
      if (stats.distanceMeters != null || stats.drivingSeconds != null) {
        measured++;
        distance += stats.distanceMeters ?? 0;
        driving += stats.drivingSeconds ?? 0;
      }
    }
  }
  return ProfileTotals(
    days: count,
    sessions: sessions,
    laps: laps,
    rankedLaps: ranked,
    distanceMeters: distance,
    drivingSeconds: driving,
    measuredSessions: measured,
    tracks: tracks.length,
    cars: cars.length,
    firstMilliseconds: first,
    lastMilliseconds: last,
  );
}

/// Everything the driver drove.
ProfileTotals driverTotals(DriverProfile profile) => _totals(profile.days);

/// Per car of [profile] (every car, driven or not): what it drove.
Map<String, ProfileTotals> carTotals(DriverProfile profile) => {
  for (final car in profile.cars) car.id: _totals(profile.days.where((d) => d.carId == car.id)),
};

/// Per track driven (in [carId] when given): what was driven there.
Map<String, ProfileTotals> trackTotals(DriverProfile profile, {String? carId}) {
  final result = <String, ProfileTotals>{};
  for (final track in profile.tracks) {
    final days = _visits(profile, track.id, carId).toList();
    if (days.isNotEmpty) result[track.id] = _totals(days);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Records and progress per track

/// A time set on one day, in one session when [runId] is set.
final class ProfileTime {
  const ProfileTime(this.seconds, this.day, [this.runId]);

  final double seconds;
  final ProfileDay day;
  final String? runId;
}

/// One track's personal records.
final class TrackRecord {
  const TrackRecord({
    required this.trackId,
    required this.visits,
    this.bestLap,
    this.theoreticalBest,
    this.bestTypicalLap,
  });

  final String trackId;

  /// Days driven there.
  final int visits;

  /// The fastest ranked lap.
  final ProfileTime? bestLap;

  /// The lowest theoretical best of a day.
  final ProfileTime? theoreticalBest;

  /// The lowest median lap of a session: the best typical pace.
  final ProfileTime? bestTypicalLap;
}

/// Per track driven (in [carId] when given), its records, by track id.
Map<String, TrackRecord> trackRecords(DriverProfile profile, {String? carId}) {
  final result = <String, TrackRecord>{};
  for (final track in profile.tracks) {
    final visits = _visits(profile, track.id, carId).toList();
    if (visits.isEmpty) continue;
    ProfileTime? best, theoretical, typical;
    for (final day in visits) {
      // A session's best lap is its own layout's: only one measured on the
      // day's track counts. The day's best lap is always the track's.
      for (final session in day.sessions) {
        final lap = session.bestLapSeconds;
        final stats = session.stats;
        if (stats == null || stats.otherLayout || lap == null) continue;
        if (best == null || lap < best.seconds) best = ProfileTime(lap, day, session.runId);
      }
      final dayBest = day.bestLapSeconds;
      if (dayBest != null && (best == null || dayBest < best.seconds)) {
        best = ProfileTime(dayBest, day);
      }
      for (final session in _onTrack(day)) {
        final median = session.stats?.medianLapSeconds;
        if (median != null && (typical == null || median < typical.seconds)) {
          typical = ProfileTime(median, day, session.runId);
        }
      }
      final total = day.theoreticalBestSeconds;
      if (total != null && (theoretical == null || total < theoretical.seconds)) {
        theoretical = ProfileTime(total, day);
      }
    }
    result[track.id] = TrackRecord(
      trackId: track.id,
      visits: visits.length,
      bestLap: best,
      theoreticalBest: theoretical,
      bestTypicalLap: typical,
    );
  }
  return result;
}

/// One day at a track.
final class TrackVisit {
  const TrackVisit({
    required this.day,
    required this.rankedLaps,
    this.bestLapSeconds,
    this.theoreticalBestSeconds,
    this.typicalLapSeconds,
    this.lapSpreadSeconds,
    this.previous,
  });

  final ProfileDay day;
  final int rankedLaps;
  final double? bestLapSeconds;
  final double? theoreticalBestSeconds;

  /// The sessions' median laps averaged by their ranked laps.
  final double? typicalLapSeconds;

  /// The sessions' lap spreads averaged by their ranked laps.
  final double? lapSpreadSeconds;

  /// The visit before, to compare with; null on the first.
  final TrackVisit? previous;

  /// Seconds faster than [previous] (positive is better); null when either
  /// has no time.
  double? get bestLapGain => _gain(previous?.bestLapSeconds, bestLapSeconds);
  double? get typicalLapGain => _gain(previous?.typicalLapSeconds, typicalLapSeconds);
  double? get theoreticalBestGain =>
      _gain(previous?.theoreticalBestSeconds, theoreticalBestSeconds);
}

double? _gain(double? before, double? now) => before == null || now == null ? null : before - now;

TrackVisit _visit(ProfileDay day, TrackVisit? previous) {
  final measured = [for (final session in _onTrack(day)) ?session.stats];
  return TrackVisit(
    day: day,
    rankedLaps: measured.fold(0, (sum, stats) => sum + stats.rankedLaps),
    bestLapSeconds: day.bestLapSeconds,
    theoreticalBestSeconds: day.theoreticalBestSeconds,
    typicalLapSeconds: _weighted([for (final s in measured) (s.medianLapSeconds, s.rankedLaps)]),
    lapSpreadSeconds: _weighted([for (final s in measured) (s.lapSpreadSeconds, s.rankedLaps)]),
    previous: previous,
  );
}

/// Every visit to [trackId] (in [carId] when given), oldest first, each with
/// the one before it.
List<TrackVisit> trackProgress(DriverProfile profile, String trackId, {String? carId}) {
  final result = <TrackVisit>[];
  for (final day in _visits(profile, trackId, carId)) {
    result.add(_visit(day, result.isEmpty ? null : result.last));
  }
  return result;
}

/// The last visit to [trackId] before [beforeEventId] (else the last of
/// all): in [carId] when it drove there, else in any car. Null on a first
/// visit.
TrackVisit? lastTimeHere(
  DriverProfile profile,
  String trackId, {
  String? carId,
  String? beforeEventId,
}) {
  // Each day's place among all days, so a day in another car or on
  // another track still says which visits came before it. An undated day
  // sorts last, so before it is every dated day.
  final order = {for (final (i, day) in _ordered(profile.days).indexed) day.eventId: i};
  final limit = beforeEventId == null ? null : order[beforeEventId];
  TrackVisit? find(String? car) {
    final earlier = [
      for (final visit in trackProgress(profile, trackId, carId: car))
        if (limit == null || order[visit.day.eventId]! < limit) visit,
    ];
    return earlier.isEmpty ? null : earlier.last;
  }

  return (carId == null ? null : find(carId)) ?? find(null);
}

// ---------------------------------------------------------------------------
// Corners across visits

/// One corner on one visit: its sessions' figures averaged by their laps.
final class CornerVisit {
  const CornerVisit({
    required this.day,
    required this.laps,
    this.minimumSpeed,
    this.bestMinimumSpeed,
    this.exitSpeed,
    this.bestExitSpeed,
    this.brakingSpreadMeters,
    this.lossSeconds,
  });

  final ProfileDay day;
  final int laps;

  /// m/s.
  final double? minimumSpeed;
  final double? bestMinimumSpeed;
  final double? exitSpeed;
  final double? bestExitSpeed;
  final double? brakingSpreadMeters;
  final double? lossSeconds;
}

/// Every corner [day] measured, by corner id.
Map<String, CornerVisit> _cornerVisits(ProfileDay day) {
  final byCorner = <String, List<CornerStats>>{};
  for (final session in _onTrack(day)) {
    for (final corner in session.stats?.corners ?? const <CornerStats>[]) {
      byCorner.putIfAbsent(corner.cornerId, () => []).add(corner);
    }
  }
  return {for (final MapEntry(:key, :value) in byCorner.entries) key: _cornerVisit(day, value)};
}

CornerVisit _cornerVisit(ProfileDay day, List<CornerStats> corners) {
  double? highest(Iterable<double?> values) =>
      values.whereType<double>().fold<double?>(null, (a, b) => a == null || b > a ? b : a);
  return CornerVisit(
    day: day,
    laps: corners.fold(0, (sum, corner) => sum + corner.laps),
    minimumSpeed: _weighted([for (final c in corners) (c.minimumSpeed, c.laps)]),
    bestMinimumSpeed: highest(corners.map((c) => c.bestMinimumSpeed)),
    exitSpeed: _weighted([for (final c in corners) (c.exitSpeed, c.laps)]),
    bestExitSpeed: highest(corners.map((c) => c.bestExitSpeed)),
    brakingSpreadMeters: _weighted([for (final c in corners) (c.brakingSpreadMeters, c.laps)]),
    lossSeconds: _weighted([for (final c in corners) (c.lossSeconds, c.laps)]),
  );
}

/// Corner [cornerId] of [trackId] on every visit that measured it (in
/// [carId] when given), oldest first.
List<CornerVisit> cornerHistory(
  DriverProfile profile,
  String trackId,
  String cornerId, {
  String? carId,
}) => [for (final day in _visits(profile, trackId, carId)) ?_cornerVisits(day)[cornerId]];

/// One corner of a track on the last visit and on the day open now.
final class CornerThenToday {
  const CornerThenToday({required this.corner, required this.then, required this.today});

  final TrackCorner corner;

  /// The time lost here against that day's fastest time through the corner,
  /// each session's median averaged by its laps ([CornerVisit.lossSeconds]),
  /// seconds: how far that day's laps were from its best here, not a time
  /// through the corner.
  final double then;
  final double today;
}

/// [today]'s corners next to [then]'s, in the track's order: every corner
/// of [trackId] whose time lost was measured on both days. Empty when the
/// track has no corners or no corner was measured on both. Corners are the
/// track's own, matched on each day by where they are on the track, so the
/// days' segments need not end at the same place; each loss is against its
/// own day's fastest, so it compares consistency, not speed.
List<CornerThenToday> lastTimeHereCorners(
  DriverProfile profile,
  String trackId,
  ProfileDay then,
  ProfileDay today,
) {
  final track = profile.track(trackId);
  if (track == null) return const [];
  final before = _cornerVisits(then), now = _cornerVisits(today);
  return [
    for (final corner in track.corners)
      if ((before[corner.id]?.lossSeconds, now[corner.id]?.lossSeconds) case (final a?, final b?))
        CornerThenToday(corner: corner, then: a, today: b),
  ];
}

// ---------------------------------------------------------------------------
// Corners that keep costing time

/// Where a repeated loss stands.
enum RepeatedLossState {
  /// Lost time on one of the last two visits that measured it.
  active,

  /// Not measured on the last two visits since it last lost time.
  fading,

  /// Measured without losing time on the last two visits.
  fixed,
}

/// A corner that cost time on more than one visit.
final class RepeatedLoss {
  const RepeatedLoss({
    required this.trackId,
    required this.cornerId,
    required this.visits,
    required this.meanLossSeconds,
    required this.state,
    required this.lastLost,
  });

  final String trackId;
  final String cornerId;

  /// Visits on which it was among the day's costliest corners.
  final int visits;

  /// Its loss averaged over those visits.
  final double meanLossSeconds;
  final RepeatedLossState state;
  final ProfileDay lastLost;

  /// What ranks it: time lost times how often.
  double get weight => meanLossSeconds * visits;
}

/// A corner loses time on a visit when it is among the visit's
/// [_lossCorners] costliest and loses at least [_lossSeconds].
const _lossCorners = 3;
const _lossSeconds = 0.1;

/// Corners that cost time on at least two visits, per track ([trackId]
/// when given, in [carId] when given), costliest first.
List<RepeatedLoss> repeatedLosses(DriverProfile profile, {String? trackId, String? carId}) {
  final result = <RepeatedLoss>[];
  for (final track in profile.tracks) {
    if (trackId != null && track.id != trackId) continue;
    // Per corner, per visit: null when not measured, else whether it lost.
    final history = <String, List<(ProfileDay, double?, bool)?>>{};
    final visits = _visits(profile, track.id, carId).toList();
    for (var v = 0; v < visits.length; v++) {
      final day = visits[v];
      final measured = _cornerVisits(day);
      final costly =
          (measured.entries.where((e) => (e.value.lossSeconds ?? 0) >= _lossSeconds).toList()
                ..sort((a, b) => b.value.lossSeconds!.compareTo(a.value.lossSeconds!)))
              .take(_lossCorners)
              .map((e) => e.key)
              .toSet();
      for (final corner in track.corners) {
        final list = history.putIfAbsent(corner.id, () => List.filled(visits.length, null));
        final visit = measured[corner.id];
        if (visit != null) list[v] = (day, visit.lossSeconds, costly.contains(corner.id));
      }
    }
    for (final MapEntry(key: cornerId, value: list) in history.entries) {
      final lost = [
        for (final entry in list)
          if (entry != null && entry.$3) entry,
      ];
      if (lost.length < 2) continue;
      final last = list.lastIndexWhere((entry) => entry != null && entry.$3);
      final after = list.sublist(last + 1);
      final measuredAfter = after.whereType<(ProfileDay, double?, bool)>().length;
      final state = measuredAfter >= 2
          ? RepeatedLossState.fixed
          : after.length >= 2
          ? RepeatedLossState.fading
          : RepeatedLossState.active;
      result.add(
        RepeatedLoss(
          trackId: track.id,
          cornerId: cornerId,
          visits: lost.length,
          meanLossSeconds: lost.fold(0.0, (sum, entry) => sum + entry.$2!) / lost.length,
          state: state,
          lastLost: lost.last.$1,
        ),
      );
    }
  }
  result.sort((a, b) => b.weight.compareTo(a.weight));
  return result;
}

// ---------------------------------------------------------------------------
// Skills

/// The four parts of a lap a skill belongs to.
enum SkillGroup { braking, corner, exit, lap }

/// How sure a level is, from the ranked laps behind it.
enum SkillConfidence { low, medium, high }

/// A level against the window before.
enum SkillTrend { improving, steady, declining }

/// One skill of the 12-skill model: how a session measures it (lower is
/// better) and the [bands] its level steps down at.
final class SkillDefinition {
  const SkillDefinition(this.id, this.group, {this.unit = '', this.bands = const []});

  final String id;
  final SkillGroup group;

  /// The unit of the measure and [bands]: "s", "m", "km/h", "g" or "%" (a
  /// share of passes).
  final String unit;

  /// Four rising thresholds; level = 5 − bands exceeded. Empty while the
  /// skill has no measure.
  final List<double> bands;

  bool get measured => bands.isNotEmpty;

  /// The level of [value]: 5 at or below the first band, 1 above the last.
  int levelOf(double value) => 5 - bands.where((band) => value > band).length;
}

/// The skills, in the order shown. Bands from the Profile screen's draft
/// (thread "Welcome screen and app navigation"); tune them here, stored
/// data never changes.
const skillCatalogue = [
  SkillDefinition('liftTiming', SkillGroup.braking, unit: 's', bands: [0.2, 0.4, 0.7, 1]),
  SkillDefinition('brakePointConsistency', SkillGroup.braking, unit: 'm', bands: [4, 6, 9, 14]),
  SkillDefinition('brakeReleaseTiming', SkillGroup.braking, unit: 'm', bands: [6, 9, 14, 21]),
  SkillDefinition(
    'brakingEffectiveness',
    SkillGroup.braking,
    unit: 'g',
    bands: [0.03, 0.06, 0.1, 0.15],
  ),
  SkillDefinition('turnInConsistency', SkillGroup.corner, unit: 'km/h', bands: [2, 4, 6, 9]),
  SkillDefinition('minimumSpeedControl', SkillGroup.corner, unit: 'km/h', bands: [2, 4, 6, 9]),
  SkillDefinition('lineConsistency', SkillGroup.corner, unit: 'm', bands: [0.5, 1, 1.5, 2.5]),
  SkillDefinition('throttleReapplication', SkillGroup.exit, unit: 'm', bands: [4, 6, 9, 14]),
  SkillDefinition('throttleCommitment', SkillGroup.exit, unit: '%', bands: [5, 15, 30, 50]),
  SkillDefinition('exitSpeedExecution', SkillGroup.exit, unit: 'km/h', bands: [1, 3, 6, 9]),
  SkillDefinition(
    'cornerSequenceManagement',
    SkillGroup.lap,
    unit: 's',
    bands: [0.02, 0.05, 0.1, 0.2],
  ),
  SkillDefinition('paceConsistency', SkillGroup.lap, unit: 's', bands: [1, 2.5, 5, 8]),
];

/// A skill's level over its window.
final class SkillLevel {
  const SkillLevel({
    required this.skill,
    this.level,
    this.value,
    this.rankedLaps = 0,
    this.days = 0,
    this.trend,
    this.lastDay,
  });

  final SkillDefinition skill;

  /// 1–5; null with no measurement ("Needs more evidence").
  final int? level;

  /// The measure over the window, in [SkillDefinition.unit].
  final double? value;

  /// Ranked laps and days behind it.
  final int rankedLaps;
  final int days;

  /// Against the window before; null without one.
  final SkillTrend? trend;

  /// The newest day that measured it.
  final ProfileDay? lastDay;

  /// Low below 5 ranked laps, medium below 15, high from 15.
  SkillConfidence? get confidence => level == null
      ? null
      : rankedLaps < 5
      ? SkillConfidence.low
      : rankedLaps < 15
      ? SkillConfidence.medium
      : SkillConfidence.high;
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// The day's best per corner, from all its sessions on the track: minimum
/// and exit speed, m/s, and mean deceleration while braking, g.
typedef _CornerBest = ({double? minimum, double? exit, double? deceleration});

/// One session's measure of [skill] and its ranked laps; null when not
/// measured. [dayBest] is the day's best per corner.
(double, int)? _skillMeasure(String skill, SessionStats stats, Map<String, _CornerBest> dayBest) {
  (double, int)? median(double? Function(CornerStats corner) value, {double scale = 1}) {
    final values = [
      for (final corner in stats.corners)
        if (value(corner) case final v?) v * scale,
    ];
    final result = _median(values);
    return result == null ? null : (result, stats.rankedLaps);
  }

  switch (skill) {
    case 'paceConsistency':
      final spread = stats.lapSpreadSeconds;
      return spread == null ? null : (spread, stats.rankedLaps);
    case 'brakePointConsistency':
      return median((corner) => corner.brakingSpreadMeters);
    case 'liftTiming':
      return median((corner) => corner.liftSeconds);
    case 'brakeReleaseTiming':
      return median((corner) => corner.releaseSpreadMeters);
    case 'turnInConsistency':
      return median((corner) => corner.entrySpeedSpread, scale: 3.6);
    case 'lineConsistency':
      return median((corner) => corner.lineSpreadMeters);
    case 'throttleReapplication':
      return median((corner) => corner.pickupSpreadMeters);
    case 'cornerSequenceManagement':
      return median((corner) => corner.sequenceLossSeconds);
    case 'throttleCommitment':
      // A share of all the session's passes, from 3 of them on 3 laps.
      var known = 0, released = 0;
      for (final corner in stats.corners) {
        known += corner.throttleKnownLaps ?? 0;
        released += corner.releasedPickups ?? 0;
      }
      return known < 3 || stats.rankedLaps < 3 ? null : (released / known * 100, stats.rankedLaps);
    case 'brakingEffectiveness':
      return median((corner) {
        final best = dayBest[corner.cornerId]?.deceleration, typical = corner.decelerationG;
        return best == null || typical == null ? null : max(0, best - typical);
      });
    case 'minimumSpeedControl' || 'exitSpeedExecution':
      final minimum = skill == 'minimumSpeedControl';
      return median((corner) {
        final best = minimum ? dayBest[corner.cornerId]?.minimum : dayBest[corner.cornerId]?.exit;
        final typical = minimum ? corner.minimumSpeed : corner.exitSpeed;
        return best == null || typical == null ? null : max(0, best - typical);
      }, scale: 3.6);
  }
  return null;
}

/// Each skill of [skillCatalogue]: its level over the last [window] days
/// that measured it (on [trackId] and in [carId] when given), and its trend
/// against the [window] days before those.
List<SkillLevel> skillLevels(
  DriverProfile profile, {
  int window = 3,
  String? trackId,
  String? carId,
}) {
  final days = _ordered(
    profile.days.where(
      (day) => (trackId == null || day.trackId == trackId) && (carId == null || day.carId == carId),
    ),
  );
  return [
    for (final skill in skillCatalogue)
      if (!skill.measured) SkillLevel(skill: skill) else _skillLevel(skill, days, max(1, window)),
  ];
}

SkillLevel _skillLevel(SkillDefinition skill, List<ProfileDay> days, int window) {
  // Per day that measured it, newest first: its sessions' measures.
  final measured = <(ProfileDay, List<(double, int)>)>[];
  for (final day in days.reversed) {
    final dayBest = <String, _CornerBest>{};
    for (final session in _onTrack(day)) {
      for (final corner in session.stats?.corners ?? const <CornerStats>[]) {
        final best = dayBest[corner.cornerId];
        dayBest[corner.cornerId] = (
          minimum: _higher(best?.minimum, corner.bestMinimumSpeed),
          exit: _higher(best?.exit, corner.bestExitSpeed),
          deceleration: _higher(best?.deceleration, corner.bestDecelerationG),
        );
      }
    }
    final values = [
      for (final session in _onTrack(day))
        if (session.stats case final stats?) ?_skillMeasure(skill.id, stats, dayBest),
    ];
    if (values.isNotEmpty) measured.add((day, values));
    if (measured.length >= window * 2) break;
  }
  (double, int, int)? over(Iterable<(ProfileDay, List<(double, int)>)> part) {
    final all = [for (final (_, values) in part) ...values];
    if (all.isEmpty) return null;
    // Each session counts by its laps; one with none still counts once.
    final value = _weighted([for (final (v, laps) in all) (v, max(1, laps))])!;
    return (value, all.fold(0, (sum, m) => sum + m.$2), part.length);
  }

  final now = over(measured.take(window));
  if (now == null) return SkillLevel(skill: skill);
  final before = over(measured.skip(window));
  final level = skill.levelOf(now.$1);
  final earlier = before == null ? null : skill.levelOf(before.$1);
  return SkillLevel(
    skill: skill,
    level: level,
    value: now.$1,
    rankedLaps: now.$2,
    days: now.$3,
    lastDay: measured.first.$1,
    trend: earlier == null
        ? null
        : level > earlier
        ? SkillTrend.improving
        : level < earlier
        ? SkillTrend.declining
        : SkillTrend.steady,
  );
}

double? _higher(double? a, double? b) => a == null ? b : (b == null || a >= b ? a : b);
