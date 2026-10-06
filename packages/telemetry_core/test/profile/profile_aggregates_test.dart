import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

/// [session] with its speed declared in [unit] (the test circuits record
/// km/h without a unit).
TelemetrySession _labelled(TelemetrySession session, String unit, {double scale = 1}) {
  final speed = session.channels['velocity']!;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: session.metadata,
    channels: {
      ...session.channels,
      'velocity': TelemetryChannel(
        name: 'velocity',
        unit: unit,
        timestamps: speed.timestamps,
        values: Float32List.fromList([
          for (final v in speed.values) v * scale / (unit == 'm/s' ? 3.6 : 1),
        ]),
      ),
    },
    aliases: session.aliases,
    warnings: session.warnings,
    timingGates: session.timingGates,
    sampleCount: session.sampleCount,
  );
}

/// [session] with its channel [name] changed by [change].
TelemetrySession _changed(
  TelemetrySession session,
  String name,
  TelemetryChannel Function(TelemetryChannel channel) change,
) => TelemetrySession(
  duration: session.duration,
  startTime: session.startTime,
  metadata: session.metadata,
  channels: {...session.channels, name: change(session.channels[name]!)},
  aliases: session.aliases,
  warnings: session.warnings,
  timingGates: session.timingGates,
  sampleCount: session.sampleCount,
);

/// [channel] [seconds] earlier.
TelemetryChannel _earlier(TelemetryChannel channel, double seconds) => TelemetryChannel(
  name: channel.name,
  unit: channel.unit,
  timestamps: Float64List.fromList([for (final t in channel.timestamps) t - seconds]),
  values: channel.values,
);

/// [channel] in [unit], its values times [scale].
TelemetryChannel _inUnit(TelemetryChannel channel, String unit, {double scale = 1}) =>
    TelemetryChannel(
      name: channel.name,
      unit: unit,
      timestamps: channel.timestamps,
      values: Float32List.fromList([for (final v in channel.values) v * scale]),
    );

/// [session] with a GPS accuracy of [metres] throughout.
TelemetrySession _withAccuracy(TelemetrySession session, double metres) {
  final latitude = session.channels['latitude']!;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: session.metadata,
    channels: {
      ...session.channels,
      'accuracy': TelemetryChannel(
        name: 'accuracy',
        unit: 'm',
        timestamps: latitude.timestamps,
        values: Float32List.fromList(List.filled(latitude.sampleCount, metres)),
      ),
    },
    aliases: {...session.aliases, 'accuracy': 'accuracy'},
    warnings: session.warnings,
    timingGates: session.timingGates,
    sampleCount: session.sampleCount,
  );
}

// A lap at 30 m/s that brakes from [brake] m to [slow] m/s at 326 m, holds it
// to 360 m and is back at 30 m/s 60 m later.
double Function(double) _lap(double brake, double slow) => (d) {
  if (d < brake) return 30;
  if (d < 326) return 30 + (slow - 30) * (d - brake) / (326 - brake);
  if (d < 360) return slow;
  if (d < 420) return slow + (30 - slow) * (d - 360) / 60;
  return 30;
};

final _laps = [_lap(250, 18), _lap(270, 20), _lap(240, 17), _lap(255, 19)];

// As [_lap], on full throttle gaining 2 m/s over the 60 m before braking,
// and still slowing by 0.5 m/s off the brake to 360 m.
double Function(double) _pushed(double brake, double slow) => (d) {
  if (d >= brake - 60 && d < brake) return 28 + 2 * (d - brake + 60) / 60;
  if (d < brake) return 28;
  if (d >= 326 && d < 360) return slow - 0.5 * (d - 326) / 34;
  if (d >= 360 && d < 420) return slow - 0.5 + (30.5 - slow) * (d - 360) / 60;
  return _lap(brake, slow)(d);
};

final _pushedLaps = [
  for (final (brake, slow) in [(250.0, 18.0), (270.0, 20.0), (240.0, 17.0), (255.0, 19.0)])
    _pushed(brake, slow),
];

/// A rectangle day of one session, analysed as the app does, with its
/// recordings and theoretical best when [measured].
({DayAnalysis analysis, Map<String, TelemetrySession?> recordings, DayTheoreticalBest best})
_rectangle({
  String unit = 'm/s',
  int start = 1756454400000,
  double scale = 1,
  List<double Function(double)>? laps,
  bool pedals = true,
  double? accuracy,
  TelemetrySession Function(TelemetrySession session)? edit,
}) {
  var session = rectangleSession(laps ?? _laps, firstTimestampMilliseconds: start, pedals: pedals);
  if (unit.isNotEmpty) session = _labelled(session, unit, scale: scale);
  if (accuracy != null) session = _withAccuracy(session, accuracy);
  if (edit != null) session = edit(session);
  final run = DayRunInput(
    runId: 'run1',
    name: 'Session 1',
    contentSha256: 'b' * 64,
    session: session,
    laps: deriveSourceLapSession(session),
  );
  final analysis = analyzeDay([run]);
  final best = dayTheoreticalBest(analysis, {
    'run1': OutingRun(run.session, run.laps),
  }, random: Random(1));
  return (analysis: analysis, recordings: {'run1': session}, best: best);
}

ProfileDayInput _input(
  String eventId, {
  String unit = 'm/s',
  bool recordings = true,
  bool theoreticalBest = true,
  int start = 1756454400000,
}) {
  final day = _rectangle(unit: unit, start: start);
  return ProfileDayInput.fromAnalysis(
    eventId: eventId,
    file: 'Days/$eventId.fetproject',
    name: eventId,
    analysis: day.analysis,
    recordings: recordings ? day.recordings : null,
    theoreticalBest: theoreticalBest ? day.best : null,
  );
}

DriverProfile _add(DriverProfile profile, ProfileDayInput day) => addDayToProfile(
  profile,
  day,
  defaultCarName: 'My car',
  defaultTrackName: 'Track',
  random: Random(day.eventId.hashCode),
);

DriverProfile _roundTrip(DriverProfile profile) =>
    decodeDriverProfile(encodeDriverProfile(profile));

// ---------------------------------------------------------------------------
// Synthetic profiles: built directly, so every number is known.

final _route = () {
  final session = circuitSession(radius: 100, speeds: [30, 30, 30]);
  return analyzeDay([
    DayRunInput(
      runId: 'r',
      name: 'S',
      contentSha256: 'c' * 64,
      session: session,
      laps: deriveSourceLapSession(session),
    ),
  ]).inferences['r']!.route!;
}();

ProfileTrack _track(String id, [List<TrackCorner> corners = const []]) =>
    ProfileTrack(id: id, name: id, route: _route, corners: corners);

ProfileSession _session(
  String runId, {
  double? best,
  int laps = 6,
  double? median,
  double? spread,
  double distance = 20000,
  List<CornerStats> corners = const [],
}) => ProfileSession(
  runId: runId,
  name: runId,
  lapCount: laps + 2,
  bestLapSeconds: best,
  stats: SessionStats(
    distanceMeters: distance,
    drivingSeconds: distance / 25,
    rankedLaps: laps,
    medianLapSeconds: median,
    lapSpreadSeconds: spread,
    corners: corners,
  ),
);

const _day0 = 1735689600000; // 2025-01-01 00:00 UTC
const _dayMs = 86400000;

ProfileDay _visit(
  String id,
  int dayNumber, {
  required String track,
  String car = 'car1',
  List<ProfileSession> sessions = const [],
  double? theoretical,
  double? dayBest,
}) {
  final best =
      dayBest ??
      [
        for (final s in sessions)
          if (s.bestLapSeconds != null) s.bestLapSeconds!,
      ].fold<double?>(null, (a, b) => a == null || b < a ? b : a);
  return ProfileDay(
    eventId: id,
    file: 'Days/$id.fetproject',
    name: id,
    carId: car,
    trackId: track,
    startMilliseconds: _day0 + dayNumber * _dayMs,
    sessions: sessions,
    bestLapSeconds: best,
    theoreticalBestSeconds: theoretical,
  );
}

DriverProfile _profile(List<ProfileDay> days, {List<ProfileTrack>? tracks}) => DriverProfile(
  driverId: 'driver',
  cars: [
    ProfileCar(id: 'car1', name: 'Clio'),
    ProfileCar(id: 'car2', name: 'Golf'),
    ProfileCar(id: 'car3', name: 'Unused'),
  ],
  tracks: tracks ?? [_track('jastrzab'), _track('poznan'), _track('torun')],
  days: days,
);

void main() {
  group('measuring a day', () {
    final day = _rectangle();
    final stats = measureSessions(day.analysis, day.recordings, best: day.best)['run1']!;

    test('distance, driving time and lap statistics', () {
      expect(day.best.state, DayTheoreticalBestState.ready);
      final laps = day.analysis.ranking!.eligibleLaps;
      expect(stats.rankedLaps, laps.length);
      expect(stats.rankedLaps, greaterThanOrEqualTo(3));
      final durations = [for (final lap in laps) lap.durationSeconds]..sort();
      expect(stats.medianLapSeconds, greaterThanOrEqualTo(durations.first));
      expect(stats.medianLapSeconds, lessThanOrEqualTo(durations.last));
      expect(stats.lapSpreadSeconds, isNotNull);
      // Every sample is above 2 m/s: driving time is the whole recording.
      final session = day.recordings['run1']!;
      expect(stats.drivingSeconds, closeTo(session.duration, 0.2));
      // The speed integrated and the GPS path agree.
      final gps = measureSessions(day.analysis, {
        'run1': _labelled(rectangleSession(_laps, pedals: true), ''),
      })['run1']!;
      expect(stats.distanceMeters, closeTo(gps.distanceMeters!, gps.distanceMeters! * 0.02));
    });

    test('a session theoretical best is no slower than its best lap', () {
      expect(stats.theoreticalBestSeconds, isNotNull);
      expect(
        stats.theoreticalBestSeconds,
        lessThanOrEqualTo(day.analysis.ranking!.bestOfDay!.durationSeconds + 1e-6),
      );
    });

    test('corners: speeds in m/s, braking spread and loss', () {
      expect(stats.corners, isNotEmpty);
      final slow = stats.corners.reduce(
        (a, b) => (a.minimumSpeed ?? 99) < (b.minimumSpeed ?? 99) ? a : b,
      );
      // The slow corner's laps hold 18, 20, 17 and 19 m/s.
      expect(slow.minimumSpeed, closeTo(18.5, 0.01));
      expect(slow.bestMinimumSpeed, closeTo(20, 0.01));
      expect(slow.laps, stats.rankedLaps);
      for (final corner in stats.corners) {
        expect(corner.lossSeconds, anyOf(isNull, greaterThanOrEqualTo(0)));
      }
    });

    // The corner whose laps brake: the one with a minimum speed.
    CornerStats slowCorner(
      ({DayAnalysis analysis, Map<String, TelemetrySession?> recordings, DayTheoreticalBest best})
      day,
    ) => measureSessions(
      day.analysis,
      day.recordings,
      best: day.best,
    )['run1']!.corners.firstWhere((c) => c.minimumSpeed != null);

    test('corners: pedals, deceleration, entry, line and what follows', () {
      final pushed = _rectangle(laps: _pushedLaps, accuracy: 0.1);
      final slow = slowCorner(pushed);
      expect(slow.laps, 4);
      // Off the throttle straight onto the brake.
      expect(slow.liftSeconds, closeTo(0, 0.15));
      // The braking always ends at the same place, 326 m.
      expect(slow.releaseSpreadMeters, lessThan(2));
      // Braking from 30 to 17–20 m/s over 56–86 m: 0.3–0.5 g.
      expect(slow.decelerationG, inInclusiveRange(0.3, 0.5));
      expect(slow.bestDecelerationG, greaterThan(slow.decelerationG!));
      expect(slow.entrySpeedSpread, greaterThan(0));
      // Still slowing off the brake, the throttle known and never picked
      // up and released.
      expect(slow.throttleKnownLaps, 4);
      expect(slow.releasedPickups, 0);
      // One line, GPS stated at 0.1 m.
      expect(slow.lineSpreadMeters, lessThan(0.25));
      // The plain laps pick the throttle up at much the same place.
      expect(slowCorner(_rectangle()).pickupSpreadMeters, lessThan(2));
      // Read back the same.
      final read = _roundTrip(
        _add(
          DriverProfile.empty(Random(1)),
          ProfileDayInput.fromAnalysis(
            eventId: 'p',
            file: 'Days/p.fetproject',
            name: 'p',
            analysis: pushed.analysis,
            recordings: pushed.recordings,
            theoreticalBest: pushed.best,
          ),
        ),
      ).day('p')!.sessions.single.stats!.corners.firstWhere((c) => c.minimumSpeed != null);
      expect(read.liftSeconds, slow.liftSeconds);
      expect(read.releaseSpreadMeters, slow.releaseSpreadMeters);
      expect(read.decelerationG, slow.decelerationG);
      expect(read.bestDecelerationG, slow.bestDecelerationG);
      expect(read.entrySpeedSpread, slow.entrySpeedSpread);
      expect(read.lineSpreadMeters, slow.lineSpreadMeters);
      expect(read.throttleKnownLaps, 4);
      expect(read.releasedPickups, 0);
      expect(read.sequenceLossSeconds, slow.sequenceLossSeconds);
    });

    test('released pickups that do not add up are left out when read', () {
      final profile = _profile([
        _visit(
          'v',
          1,
          track: 'jastrzab',
          sessions: [
            _session(
              's1',
              corners: [
                CornerStats(cornerId: 'k1', laps: 3, throttleKnownLaps: 3, releasedPickups: 1),
              ],
            ),
          ],
        ),
      ]);
      final text = encodeDriverProfile(profile);
      expect(text, contains('"releasedPickups":1'));
      final corner = decodeDriverProfile(
        text.replaceFirst('"releasedPickups":1', '"releasedPickups":5'),
      ).day('v')!.sessions.single.stats!.corners.single;
      expect(corner.throttleKnownLaps, isNull);
      expect(corner.releasedPickups, isNull);
      expect(corner.laps, 3);
    });

    test('lift timing: a lift before braking, and coasting the whole approach', () {
      // The throttle half a second ahead of the brake.
      final early = slowCorner(
        _rectangle(
          laps: _pushedLaps,
          edit: (s) => _changed(s, 'throttle', (c) => _earlier(c, 0.5)),
        ),
      );
      expect(early.liftSeconds, closeTo(0.5, 0.1));
      // Off the throttle on every lap, pressed only once the last lap is
      // over: lifted before the approach (150 m before the corner), so at
      // least the approach long.
      TelemetryChannel pressedLast(TelemetryChannel channel) => TelemetryChannel(
        name: channel.name,
        unit: '%',
        timestamps: channel.timestamps,
        values: Float32List.fromList([
          for (var i = 0; i < channel.sampleCount; i++) i == channel.sampleCount - 1 ? 100 : 0,
        ]),
      );
      final coasting = slowCorner(
        _rectangle(laps: _pushedLaps, edit: (s) => _changed(s, 'throttle', pressedLast)),
      );
      expect(coasting.liftSeconds, greaterThan(2));
      // A throttle never pressed (unplugged, logging zeros) shows nothing.
      final dead = slowCorner(
        _rectangle(
          laps: _pushedLaps,
          edit: (s) => _changed(s, 'throttle', (c) => _inUnit(c, '%', scale: 0)),
        ),
      );
      expect(dead.liftSeconds, isNull);
    });

    test('deceleration in m/s² is stored in g; in another unit it is not stored', () {
      final g = slowCorner(_rectangle(laps: _pushedLaps));
      final metric = slowCorner(
        _rectangle(
          laps: _pushedLaps,
          edit: (s) => _changed(s, 'longacc', (c) => _inUnit(c, 'm/s²', scale: standardGravity)),
        ),
      );
      expect(metric.decelerationG, closeTo(g.decelerationG!, 0.002));
      expect(metric.bestDecelerationG, closeTo(g.bestDecelerationG!, 0.002));
      final unknown = slowCorner(
        _rectangle(
          laps: _pushedLaps,
          edit: (s) => _changed(s, 'longacc', (c) => _inUnit(c, 'ft/s2')),
        ),
      );
      expect(unknown.decelerationG, isNull);
      expect(unknown.bestDecelerationG, isNull);
    });

    test('a corner whose faster laps lose time right after gives it back', () {
      // A faster corner (higher minimum speed) leads onto a slower straight.
      double Function(double) traded(double slow) => (d) {
        final straight = 30 - (slow - 17);
        if (d >= 420 && d < 560) return straight;
        if (d >= 360 && d < 420) return slow + (straight - slow) * (d - 360) / 60;
        if (d >= 560 && d < 600) return straight + (30 - straight) * (d - 560) / 40;
        return _lap(250, slow)(d);
      };
      final speeds = [18.0, 20.0, 17.0, 19.0];
      expect(
        slowCorner(_rectangle(laps: [for (final v in speeds) traded(v)])).sequenceLossSeconds,
        greaterThan(0.1),
      );
      expect(
        slowCorner(_rectangle(laps: [for (final v in speeds) _lap(250, v)])).sequenceLossSeconds,
        closeTo(0, 0.01),
      );
    });

    test('the coach passages come from the recordings given', () {
      final day = _rectangle(laps: _pushedLaps);
      final first = coachCornerPassages(day.best, day.recordings);
      expect(first.values.expand((p) => p).where((p) => p.liftSeconds != null), isNotEmpty);
      // The same result with recordings that have no pedals.
      final bare = rectangleSession(_pushedLaps, firstTimestampMilliseconds: 1756454400000);
      final other = coachCornerPassages(day.best, {'run1': _labelled(bare, 'm/s')});
      expect(other.values.expand((p) => p).where((p) => p.liftSeconds != null), isEmpty);
      expect(coachCornerPassages(day.best, const {}).values.expand((p) => p), isEmpty);
    });

    test('without pedals, G or a stated GPS accuracy those are not measured', () {
      final bare = _rectangle(pedals: false);
      final corners = measureSessions(
        bare.analysis,
        bare.recordings,
        best: bare.best,
      )['run1']!.corners;
      expect(corners, isNotEmpty);
      for (final corner in corners) {
        expect(corner.liftSeconds, isNull);
        expect(corner.releaseSpreadMeters, isNull);
        expect(corner.decelerationG, isNull);
        expect(corner.pickupSpreadMeters, isNull);
        expect(corner.throttleKnownLaps, isNull);
        expect(corner.releasedPickups, isNull);
        expect(corner.lineSpreadMeters, isNull);
      }
      // Timing and speed need no more than GPS and speed.
      expect(corners.where((c) => c.entrySpeedSpread != null), isNotEmpty);
      expect(corners.where((c) => c.sequenceLossSeconds != null), isNotEmpty);
      // A GPS accuracy worse than 0.25 m cannot tell lines apart.
      final rough = _rectangle(accuracy: 0.3);
      for (final corner in measureSessions(
        rough.analysis,
        rough.recordings,
        best: rough.best,
      )['run1']!.corners) {
        expect(corner.lineSpreadMeters, isNull);
      }
    });

    test('speeds in km/h are stored in m/s', () {
      final kmh = _rectangle(unit: 'km/h');
      final other = measureSessions(kmh.analysis, kmh.recordings, best: kmh.best)['run1']!;
      expect(other.distanceMeters, closeTo(stats.distanceMeters!, 1));
      for (final (index, corner) in other.corners.indexed) {
        final same = stats.corners[index];
        expect(corner.cornerId, same.cornerId);
        expect(corner.exitSpeed, closeTo(same.exitSpeed!, 0.01));
        if (same.minimumSpeed == null) continue;
        expect(corner.minimumSpeed, closeTo(same.minimumSpeed!, 0.01));
      }
      expect(stats.corners.where((c) => c.minimumSpeed != null), isNotEmpty);
    });

    test('a speed without a unit is not stored; distance comes from GPS', () {
      final unlabelled = _rectangle(unit: '');
      final other = measureSessions(
        unlabelled.analysis,
        unlabelled.recordings,
        best: unlabelled.best,
      )['run1']!;
      expect(other.distanceMeters, closeTo(stats.distanceMeters!, stats.distanceMeters! * 0.02));
      expect(other.corners, isNotEmpty);
      for (final corner in other.corners) {
        expect(corner.minimumSpeed, isNull);
        expect(corner.exitSpeed, isNull);
      }
    });

    test('a session on another layout that day is marked so', () {
      DayRunInput run(String id, double radius) {
        final session = circuitSession(radius: radius, speeds: [30, 29, 31, 30]);
        return DayRunInput(
          runId: id,
          name: id,
          contentSha256: id.padLeft(64, '0'),
          session: session,
          laps: deriveSourceLapSession(session),
        );
      }

      final runs = [run('1', 100), run('2', 100), run('3', 250)];
      final analysis = analyzeDay(runs);
      expect(analysis.groups.length, 2);
      final stats = measureSessions(analysis, {for (final r in runs) r.runId: r.session});
      final chosen = analysis.chosenGroup!.runIds.toSet();
      for (final r in runs) {
        expect(stats[r.runId]!.otherLayout, !chosen.contains(r.runId));
        expect(stats[r.runId]!.distanceMeters, greaterThan(0));
      }
      expect(stats.values.where((s) => s.otherLayout), hasLength(1));
    });

    test('a speed beyond any car is left out, and the day still adds', () {
      // km/h figures declared as m/s, twice over: 30 m/s reads 389 m/s.
      final wrong = _rectangle(scale: 3.6 * 3.6);
      final input = ProfileDayInput.fromAnalysis(
        eventId: 'w',
        file: 'Days/w.fetproject',
        name: 'w',
        analysis: wrong.analysis,
        recordings: wrong.recordings,
        theoreticalBest: wrong.best,
      );
      final stats = input.sessions.single.stats!;
      expect(stats.distanceMeters, greaterThan(0));
      for (final corner in stats.corners) {
        expect(corner.exitSpeed, isNull);
        expect(corner.bestExitSpeed, isNull);
      }
      final profile = _add(DriverProfile.empty(Random(1)), input);
      expect(profile.day('w')!.sessions.single.stats!.corners, isNotEmpty);
      expect(_roundTrip(profile).days, hasLength(1));
    });

    test('jitter while parked is not driving when distance comes from GPS', () {
      final times = <double>[], lat = <double>[], lon = <double>[];
      final random = Random(3);
      for (var i = 0; i < 600; i++) {
        times.add(i / 10);
        // About half a metre of noise around one spot.
        lat.add(52.0 + (random.nextDouble() - 0.5) * 9e-6);
        lon.add(21.0 + (random.nextDouble() - 0.5) * 1.5e-5);
      }
      TelemetryChannel channel(String name, List<double> values) => TelemetryChannel(
        name: name,
        timestamps: Float64List.fromList(times),
        values: Float32List.fromList(values),
      );
      final parked = TelemetrySession(
        duration: 60,
        startTime: 0,
        metadata: const {},
        channels: {'latitude': channel('latitude', lat), 'longitude': channel('longitude', lon)},
        aliases: const {'latitude': 'latitude', 'longitude': 'longitude'},
        warnings: const [],
        timingGates: const [],
        sampleCount: times.length,
      );
      final day = _rectangle();
      final stats = measureSessions(day.analysis, {'run1': parked})['run1']!;
      expect(stats.drivingSeconds, isNull);
      expect(stats.distanceMeters, isNull);
    });

    test('without recordings or a theoretical best: laps only', () {
      final other = measureSessions(day.analysis, const {})['run1']!;
      expect(other.distanceMeters, isNull);
      expect(other.drivingSeconds, isNull);
      expect(other.rankedLaps, stats.rankedLaps);
      expect(other.theoreticalBestSeconds, isNull);
      expect(other.corners, isEmpty);
    });
  });

  group('adding measured days', () {
    test('corners keep their ids on every visit and read back the same', () {
      var profile = _add(DriverProfile.empty(Random(1)), _input('a'));
      final track = profile.tracks.single;
      expect(track.corners, isNotEmpty);
      final first = profile.day('a')!;
      expect(first.theoreticalBestSeconds, isNotNull);
      final ids = {for (final c in first.sessions.single.stats!.corners) c.cornerId};
      expect(ids, {for (final c in track.corners) c.id});

      profile = _roundTrip(profile);
      profile = _add(profile, _input('b', start: 1756454400000 + 7 * 86400000));
      expect(profile.tracks.single.corners.length, track.corners.length);
      final again = {for (final c in profile.day('b')!.sessions.single.stats!.corners) c.cornerId};
      expect(again, ids);

      final read = _roundTrip(profile);
      expect(encodeDriverProfile(read), encodeDriverProfile(profile));
      final stats = read.day('a')!.sessions.single.stats!;
      final original = first.sessions.single.stats!;
      expect(stats.distanceMeters, original.distanceMeters);
      expect(stats.corners.length, original.corners.length);
      expect(stats.corners.first.minimumSpeed, original.corners.first.minimumSpeed);
      for (final corner in read.tracks.single.corners) {
        expect(corner.start, inInclusiveRange(0, 1));
        expect(corner.span, lessThan(0.5));
      }
    });

    test('a theoretical best that failed keeps the corners measured before', () {
      var profile = _add(DriverProfile.empty(Random(1)), _input('a'));
      final before = profile.day('a')!;
      final day = _rectangle();
      final failed = ProfileDayInput.fromAnalysis(
        eventId: 'a',
        file: 'Days/a.fetproject',
        name: 'a',
        analysis: day.analysis,
        recordings: day.recordings,
        theoreticalBest: DayTheoreticalBest(
          groupId: day.analysis.chosenGroupId!,
          state: DayTheoreticalBestState.error,
        ),
      );
      profile = _add(profile, failed);
      final after = profile.day('a')!;
      expect(after.theoreticalBestSeconds, before.theoreticalBestSeconds);
      expect(
        after.sessions.single.stats!.corners.length,
        before.sessions.single.stats!.corners.length,
      );
    });

    test('adding a day again before its theoretical best keeps its corners', () {
      var profile = _add(DriverProfile.empty(Random(1)), _input('a'));
      final before = profile.day('a')!;
      profile = _add(profile, _input('a', theoreticalBest: false));
      final after = profile.day('a')!;
      expect(after.theoreticalBestSeconds, before.theoreticalBestSeconds);
      final stats = after.sessions.single.stats!;
      expect(stats.corners.length, before.sessions.single.stats!.corners.length);
      expect(stats.theoreticalBestSeconds, before.sessions.single.stats!.theoreticalBestSeconds);
      expect(stats.distanceMeters, isNotNull);
      // Without recordings either, everything measured before is kept.
      profile = _add(profile, _input('a', recordings: false, theoreticalBest: false));
      expect(profile.day('a')!.sessions.single.stats!.distanceMeters, stats.distanceMeters);
    });

    test('a day moved to another track drops what was measured on the old one', () {
      final profile = _add(DriverProfile.empty(Random(1)), _input('a'));
      final day = profile.day('a')!;
      final moved = DriverProfile(
        driverId: profile.driverId,
        cars: profile.cars,
        tracks: [...profile.tracks, _track('other')],
        days: [
          ProfileDay(
            eventId: 'a',
            file: day.file,
            name: day.name,
            carId: day.carId,
            trackId: 'other',
            sessions: day.sessions,
            theoreticalBestSeconds: day.theoreticalBestSeconds,
          ),
        ],
      );
      // The day's route matches the rectangle again, not "other".
      final readded = _add(moved, _input('a', recordings: false, theoreticalBest: false));
      final again = readded.day('a')!;
      expect(again.trackId, isNot('other'));
      expect(again.theoreticalBestSeconds, isNull);
      expect(again.sessions.single.stats, isNull);
    });

    test('spans are placed by overlap, across the start line too', () {
      GeoCoordinate at(double fraction) {
        final point = _route.points[(fraction * _route.points.length).round() % 256];
        return unprojectCoordinate(point.eastMeters, point.northMeters, _route.origin);
      }

      ProfileDayInput day(String id, List<(String, double, double)> spans) => ProfileDayInput(
        eventId: id,
        file: 'Days/$id.fetproject',
        name: id,
        route: _route,
        measuredCorners: true,
        cornerSpans: [
          for (final (segment, start, end) in spans)
            DayCornerSpan(segmentId: segment, name: segment, start: at(start), end: at(end)),
        ],
        sessions: [
          ProfileSession(
            runId: 'r',
            name: 'S',
            stats: SessionStats(
              rankedLaps: 3,
              corners: [
                for (final (segment, _, _) in spans) CornerStats(cornerId: segment, laps: 3),
              ],
            ),
          ),
        ],
      );
      var profile = _add(
        DriverProfile.empty(Random(1)),
        day('a', [('s1', 0.95, 0.05), ('s2', 0.30, 0.36), ('far', 0.1, 0.8)]),
      );
      final corners = profile.tracks.single.corners;
      // Over half a lap is not a corner.
      expect(corners, hasLength(2));
      expect(corners.first.start, greaterThan(corners.first.end));
      final b = day('b', [
        ('x', 0.97, 0.04),
        ('y', 0.31, 0.34),
        ('z', 0.6, 0.65),
        ('w', 0.36, 0.40),
      ]);
      // Matching only reads the track's corners: new places have none.
      expect(matchTrackCorners(profile.tracks.single, b.cornerSpans), {
        'x': corners[0].id,
        'y': corners[1].id,
      });
      expect(profile.tracks.single.corners, hasLength(2));
      profile = _add(profile, b);
      final ids = [for (final c in profile.day('b')!.sessions.single.stats!.corners) c.cornerId];
      expect(ids[0], corners[0].id);
      expect(ids[1], corners[1].id);
      expect(profile.tracks.single.corners, hasLength(4));
      expect(ids.toSet(), hasLength(4));
      // Matched again, a day's spans get the ids adding it gave them.
      expect(matchTrackCorners(profile.tracks.single, b.cornerSpans), {
        'x': ids[0],
        'y': ids[1],
        'z': ids[2],
        'w': ids[3],
      });
      expect(
        matchTrackCorners(profile.tracks.single, day('a', [('far', 0.1, 0.8)]).cornerSpans),
        isEmpty,
      );
      // A corner off the route (more than 50 m) is dropped from the stats.
      final off = ProfileDayInput(
        eventId: 'c',
        file: 'Days/c.fetproject',
        name: 'c',
        route: _route,
        measuredCorners: true,
        cornerSpans: [
          DayCornerSpan(
            segmentId: 'off',
            name: 'off',
            start: const GeoCoordinate(0, 0),
            end: const GeoCoordinate(0, 0.001),
          ),
        ],
        sessions: [
          ProfileSession(
            runId: 'r',
            name: 'S',
            stats: SessionStats(corners: [CornerStats(cornerId: 'off', laps: 3)]),
          ),
        ],
      );
      // Two of a day's corners inside one known corner: one takes it, the
      // other becomes a corner of its own, so no session counts it twice.
      final split = _add(profile, day('d', [('p', 0.30, 0.33), ('q', 0.33, 0.36)]));
      final splitIds = [for (final c in split.day('d')!.sessions.single.stats!.corners) c.cornerId];
      expect(splitIds, hasLength(2));
      expect(splitIds.toSet(), hasLength(2));
      expect(splitIds, contains(corners[1].id));
      expect(matchTrackCorners(profile.tracks.single, off.cornerSpans), isEmpty);
      final withOff = _add(profile, off);
      expect(withOff.day('c')!.sessions.single.stats!.corners, isEmpty);
      expect(withOff.tracks.single.corners, hasLength(4));
    });

    group('matching a day again after later days added corners', () {
      GeoCoordinate at(double fraction) {
        final point = _route.points[(fraction * _route.points.length).round() % 256];
        return unprojectCoordinate(point.eastMeters, point.northMeters, _route.origin);
      }

      ProfileDayInput day(String id, List<(String, double, double)> spans) => ProfileDayInput(
        eventId: id,
        file: 'Days/$id.fetproject',
        name: id,
        route: _route,
        measuredCorners: true,
        cornerSpans: [
          for (final (segment, start, end) in spans)
            DayCornerSpan(segmentId: segment, name: segment, start: at(start), end: at(end)),
        ],
        sessions: [
          ProfileSession(
            runId: 'r',
            name: 'S',
            stats: SessionStats(
              rankedLaps: 3,
              corners: [
                for (final (segment, _, _) in spans) CornerStats(cornerId: segment, laps: 3),
              ],
            ),
          ),
        ],
      );

      // The track corner id adding [eventId] stored for each of its spans.
      Map<String, String> stored(DriverProfile profile, ProfileDayInput input) => {
        for (final (i, span) in input.cornerSpans.indexed)
          span.segmentId: profile.day(input.eventId)!.sessions.single.stats!.corners[i].cornerId,
      };

      test('a day that made its corners keeps them', () {
        final a = day('a', [('s', 0.30, 0.36)]);
        var profile = _add(DriverProfile.empty(Random(1)), a);
        final ids = stored(profile, a);
        // Day b takes a's corner with one span and adds an overlapping one.
        profile = _add(profile, day('b', [('p', 0.30, 0.36), ('q', 0.31, 0.40)]));
        expect(profile.tracks.single.corners, hasLength(2));
        expect(dayCornerIds(profile.day('a')!), ids);
        expect(matchTrackCorners(profile.tracks.single, a.cornerSpans), ids);
      });

      // a's span took z's corner by a share under one; b's corner covers
      // the span whole, so matching a again finds b's (FET-184). The
      // segments kept when a was added still give z's corner.
      test('a day matched to an older corner keeps it', () {
        var profile = _add(DriverProfile.empty(Random(1)), day('z', [('k', 0.30, 0.36)]));
        final a = day('a', [('s', 0.31, 0.40)]);
        profile = _add(profile, a);
        final ids = stored(profile, a);
        expect(ids, {'s': profile.tracks.single.corners.single.id});
        // Day b adds a corner exactly where a's span is.
        profile = _add(profile, day('b', [('p', 0.30, 0.36), ('q', 0.31, 0.40)]));
        expect(dayCornerIds(_roundTrip(profile).day('a')!), ids);
        // Matching again, the fallback for profiles written before, does not.
        expect(matchTrackCorners(profile.tracks.single, a.cornerSpans), isNot(ids));
      });

      test('a day added again keeps the segments it measured', () {
        final a = day('a', [('s', 0.31, 0.40)]);
        var profile = _add(DriverProfile.empty(Random(1)), day('z', [('k', 0.30, 0.36)]));
        profile = _add(profile, a);
        final ids = stored(profile, a);
        // Added again without measuring corners: what was placed stays.
        profile = _add(
          profile,
          ProfileDayInput(
            eventId: 'a',
            file: a.file,
            name: 'a',
            route: _route,
            sessions: a.sessions,
          ),
        );
        expect(dayCornerIds(profile.day('a')!), ids);
      });

      test('a profile written before keeps no segments and matches again', () {
        final a = day('a', [('s', 0.30, 0.36)]);
        final profile = _add(DriverProfile.empty(Random(1)), a);
        final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
        final corner =
            (((((json['days'] as List).single as Map)['sessions'] as List).single as Map)['stats']
                        as Map)['corners']
                    .single
                as Map<String, Object?>;
        expect(corner['segmentId'], 's');
        corner.remove('segmentId');
        final old = decodeDriverProfile(jsonEncode(json));
        expect(old.day('a')!.sessions.single.stats!.corners.single.segmentId, isNull);
        expect(dayCornerIds(old.day('a')!), isNull);
        expect(matchTrackCorners(old.tracks.single, a.cornerSpans), stored(old, a));
      });
    });

    test('a profile without stats (written before) still reads and adds up', () {
      final old = _profile([
        _visit(
          'a',
          0,
          track: 'jastrzab',
          sessions: [ProfileSession(runId: 'r', name: 'S')],
        ),
      ]);
      final read = _roundTrip(old);
      expect(read.day('a')!.sessions.single.stats, isNull);
      final totals = driverTotals(read);
      expect(totals.sessions, 1);
      expect(totals.measuredSessions, 0);
      expect(totals.distanceMeters, 0);
      for (final skill in skillLevels(read)) {
        expect(skill.level, isNull);
        expect(skill.confidence, isNull);
      }
      expect(trackProgress(read, 'jastrzab').single.typicalLapSeconds, isNull);
    });
  });

  group('reading stats', () {
    late Map<String, Object?> valid;
    Map<String, Object?> stats() =>
        (((valid['days'] as List).first as Map)['sessions'] as List).first['stats']
            as Map<String, Object?>;
    Map<String, Object?> corner() => (stats()['corners'] as List).first as Map<String, Object?>;
    Map<String, Object?> trackCorner() =>
        ((valid['tracks'] as List).first as Map)['corners'].first as Map<String, Object?>;
    void rejected(String reason) => expect(
      () => decodeDriverProfile(jsonEncode(valid)),
      throwsA(isA<ProfileFormatError>().having((e) => e.message, 'message', contains(reason))),
    );

    setUp(() {
      final profile = _profile(
        [
          _visit(
            'a',
            0,
            track: 'jastrzab',
            theoretical: 70,
            sessions: [
              _session('r', corners: [CornerStats(cornerId: 'c1', laps: 3, minimumSpeed: 20)]),
            ],
          ),
        ],
        tracks: [
          _track('jastrzab', [TrackCorner(id: 'c1', name: 'Corner 1', start: 0.9, end: 0.1)]),
        ],
      );
      valid = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
    });

    test("a corner's segment is read, written back and optional", () {
      corner()['segmentId'] = 'segment-3';
      final read = decodeDriverProfile(jsonEncode(valid));
      final kept = read.day('a')!.sessions.single.stats!.corners.single;
      expect(kept.segmentId, 'segment-3');
      expect(kept.unknown, isEmpty);
      expect(dayCornerIds(read.day('a')!), {'segment-3': 'c1'});
      valid = jsonDecode(encodeDriverProfile(read)) as Map<String, Object?>;
      expect(corner()['segmentId'], 'segment-3');
      // Written before it existed: no key, no segment.
      corner().remove('segmentId');
      final old = decodeDriverProfile(jsonEncode(valid));
      expect(old.day('a')!.sessions.single.stats!.corners.single.segmentId, isNull);
      expect(dayCornerIds(old.day('a')!), isNull);
      valid = jsonDecode(encodeDriverProfile(old)) as Map<String, Object?>;
      expect(corner().containsKey('segmentId'), isFalse);
      for (final invalid in ['', 7, '\u0000']) {
        corner()['segmentId'] = invalid;
        rejected('corner segment id');
      }
    });
    test('unknown keys inside stats and corners are kept', () {
      stats()['future'] = 1;
      corner()['future'] = [2];
      trackCorner()['future'] = 'x';
      final read = decodeDriverProfile(jsonEncode(valid));
      final again = jsonDecode(encodeDriverProfile(read)) as Map<String, Object?>;
      valid = again;
      expect(stats()['future'], 1);
      expect(corner()['future'], [2]);
      expect(trackCorner()['future'], 'x');
    });
    test('impossible speeds, distances and fractions', () {
      corner()['minimumSpeed'] = 500;
      rejected('minimum speed');
      corner()['minimumSpeed'] = -1;
      rejected('minimum speed');
      corner()['minimumSpeed'] = 20;
      stats()['distanceMeters'] = 'far';
      rejected('session distance');
      stats()['distanceMeters'] = 1;
      stats()['rankedLaps'] = 1.5;
      rejected('ranked laps');
      stats()['rankedLaps'] = 1;
      trackCorner()['start'] = 1;
      rejected('track corner start');
    });
    test('too many corners or the same corner twice', () {
      stats()['corners'] = [
        for (var i = 0; i <= maximumProfileCorners; i++) {'cornerId': 'c$i', 'laps': 1},
      ];
      rejected('too many');
      stats()['corners'] = [];
      final track = (valid['tracks'] as List).first as Map<String, Object?>;
      track['corners'] = [trackCorner(), trackCorner()];
      rejected('same track corner twice');
    });
    test('a day theoretical best of zero', () {
      ((valid['days'] as List).first as Map)['theoreticalBestSeconds'] = 0;
      rejected('day theoretical best');
    });
  });

  group('aggregates over many days, tracks and cars', () {
    // Jastrząb: car1 on days 0, 10, 20, 30 getting faster; car2 on day 15.
    // Poznań: car1 on day 5, car2 on day 25. Toruń: never.
    // Day 40: Jastrząb in car1, undated, added last.
    final corner = [
      TrackCorner(id: 'k1', name: 'Corner 1', start: 0.1, end: 0.15),
      TrackCorner(id: 'k2', name: 'Corner 2', start: 0.4, end: 0.45),
      TrackCorner(id: 'k3', name: 'Corner 3', start: 0.7, end: 0.75),
      TrackCorner(id: 'k4', name: 'Corner 4', start: 0.9, end: 0.95),
    ];
    // Per visit, the loss at each corner: k1 always costly, k2 costly early
    // then fixed, k3 costly once.
    List<CornerStats> corners(double k1, double k2, double k3, {double spread = 5}) => [
      CornerStats(
        cornerId: 'k1',
        laps: 6,
        lossSeconds: k1,
        minimumSpeed: 20,
        bestMinimumSpeed: 21,
        exitSpeed: 25,
        bestExitSpeed: 25.5,
        brakingSpreadMeters: spread,
      ),
      CornerStats(cornerId: 'k2', laps: 6, lossSeconds: k2, brakingSpreadMeters: spread),
      CornerStats(cornerId: 'k3', laps: 6, lossSeconds: k3),
      CornerStats(cornerId: 'k4', laps: 6, lossSeconds: 0.05),
    ];
    final days = [
      _visit(
        'j0',
        0,
        track: 'jastrzab',
        theoretical: 69,
        sessions: [
          _session(
            's1',
            best: 72,
            median: 74,
            spread: 6,
            corners: corners(0.5, 0.4, 0.01, spread: 12),
          ),
          _session(
            's2',
            best: 71,
            median: 73,
            spread: 5,
            corners: corners(0.6, 0.3, 0.01, spread: 12),
          ),
        ],
      ),
      _visit(
        'p5',
        5,
        track: 'poznan',
        theoretical: 99,
        sessions: [_session('s1', best: 101, median: 103, spread: 3)],
      ),
      _visit(
        'j10',
        10,
        track: 'jastrzab',
        theoretical: 68.5,
        sessions: [
          _session('s1', best: 70.5, median: 72, spread: 4, corners: corners(0.4, 0.3, 0.3)),
        ],
      ),
      _visit(
        'j15',
        15,
        track: 'jastrzab',
        car: 'car2',
        theoretical: 66,
        sessions: [_session('s1', best: 67, median: 68, spread: 2)],
      ),
      _visit(
        'j20',
        20,
        track: 'jastrzab',
        theoretical: 68,
        sessions: [
          _session(
            's1',
            best: 70,
            median: 71,
            spread: 2,
            corners: corners(0.4, 0.01, 0.02, spread: 3),
          ),
        ],
      ),
      _visit(
        'p25',
        25,
        track: 'poznan',
        car: 'car2',
        sessions: [_session('s1', best: 98, laps: 2, distance: 5000)],
      ),
      _visit(
        'j30',
        30,
        track: 'jastrzab',
        theoretical: 67.5,
        sessions: [
          _session(
            's1',
            best: 69.5,
            median: 70.5,
            spread: 0.8,
            corners: corners(0.3, 0.02, 0.01, spread: 3),
          ),
        ],
      ),
      ProfileDay(
        eventId: 'undated',
        file: 'Days/undated.fetproject',
        name: 'undated',
        carId: 'car1',
        trackId: 'jastrzab',
        sessions: [_session('s1', best: 75, median: 76)],
        bestLapSeconds: 75,
      ),
    ];
    final profile = _profile(
      days,
      tracks: [_track('jastrzab', corner), _track('poznan'), _track('torun')],
    );

    test('totals mix everything; per car and per track they split it', () {
      final totals = driverTotals(profile);
      expect(totals.days, 8);
      expect(totals.sessions, 9);
      expect(totals.measuredSessions, 9);
      expect(totals.distanceMeters, 8 * 20000 + 5000);
      expect(totals.rankedLaps, 8 * 6 + 2);
      expect(totals.laps, 8 * 8 + 4);
      expect(totals.tracks, 2);
      expect(totals.cars, 2);
      expect(totals.firstMilliseconds, _day0);
      expect(totals.lastMilliseconds, _day0 + 30 * _dayMs);

      final cars = carTotals(profile);
      expect(cars.keys, ['car1', 'car2', 'car3']);
      expect(cars['car3']!.days, 0);
      expect(cars['car1']!.distanceMeters + cars['car2']!.distanceMeters, totals.distanceMeters);
      expect(cars['car2']!.tracks, 2);

      final tracks = trackTotals(profile);
      expect(tracks.keys, ['jastrzab', 'poznan']);
      expect(tracks['jastrzab']!.days, 6);
      expect(trackTotals(profile, carId: 'car2')['jastrzab']!.days, 1);
    });

    test('records never mix tracks and can be per car', () {
      final records = trackRecords(profile);
      expect(records.keys, ['jastrzab', 'poznan']);
      final jastrzab = records['jastrzab']!;
      expect(jastrzab.visits, 6);
      expect(jastrzab.bestLap!.seconds, 67);
      expect(jastrzab.bestLap!.day.eventId, 'j15');
      expect(jastrzab.theoreticalBest!.seconds, 66);
      expect(jastrzab.bestTypicalLap!.seconds, 68);
      expect(records['poznan']!.bestLap!.seconds, 98);

      final car1 = trackRecords(profile, carId: 'car1')['jastrzab']!;
      expect(car1.bestLap!.seconds, 69.5);
      expect(car1.bestLap!.day.eventId, 'j30');
      expect(car1.theoreticalBest!.seconds, 67.5);
      expect(car1.bestTypicalLap!.runId, 's1');
      expect(trackRecords(profile, carId: 'car1').keys, ['jastrzab', 'poznan']);
    });

    test('progress per visit, oldest first, undated last', () {
      final visits = trackProgress(profile, 'jastrzab', carId: 'car1');
      expect([for (final v in visits) v.day.eventId], ['j0', 'j10', 'j20', 'j30', 'undated']);
      expect(visits.first.previous, isNull);
      expect(visits.first.typicalLapSeconds, 73.5);
      expect(visits.first.lapSpreadSeconds, 5.5);
      expect(visits.first.rankedLaps, 12);
      expect(visits[1].bestLapGain, 0.5);
      expect(visits[1].typicalLapGain, 1.5);
      expect(visits[1].theoreticalBestGain, 0.5);
      expect(visits.last.theoreticalBestGain, isNull);
    });

    test('last time here before a day in another car is still before it', () {
      expect(
        lastTimeHere(profile, 'jastrzab', carId: 'car1', beforeEventId: 'j15')!.day.eventId,
        'j10',
      );
      expect(
        lastTimeHere(profile, 'jastrzab', carId: 'car1', beforeEventId: 'p5')!.day.eventId,
        'j0',
      );
      expect(lastTimeHere(profile, 'poznan', beforeEventId: 'j0'), isNull);
    });

    test('last time here prefers the same car', () {
      expect(
        lastTimeHere(profile, 'jastrzab', carId: 'car1', beforeEventId: 'j30')!.day.eventId,
        'j20',
      );
      expect(lastTimeHere(profile, 'jastrzab', beforeEventId: 'j20')!.day.eventId, 'j15');
      expect(lastTimeHere(profile, 'jastrzab', carId: 'car1', beforeEventId: 'j0'), isNull);
      // car2 never drove Toruń; nobody did.
      expect(lastTimeHere(profile, 'torun', carId: 'car2'), isNull);
      // car2's first Poznań visit: car1's is used.
      expect(
        lastTimeHere(profile, 'poznan', carId: 'car2', beforeEventId: 'p25')!.day.eventId,
        'p5',
      );
      // Before an undated day: every dated one.
      expect(
        lastTimeHere(profile, 'jastrzab', carId: 'car1', beforeEventId: 'undated')!.day.eventId,
        'j30',
      );
      expect(lastTimeHere(profile, 'jastrzab', carId: 'car1')!.day.eventId, 'undated');
    });

    test('last time here per corner: measured on both days, in track order', () {
      final then = profile.days.firstWhere((d) => d.eventId == 'j20');
      final today = profile.days.firstWhere((d) => d.eventId == 'j30');
      final corners = lastTimeHereCorners(profile, 'jastrzab', then, today);
      expect([for (final c in corners) c.corner.id], ['k1', 'k2', 'k3', 'k4']);
      expect(corners.first.corner.name, 'Corner 1');
      expect(corners.first.then, closeTo(0.4, 1e-9));
      expect(corners.first.today, closeTo(0.3, 1e-9));
      expect(corners[1].then, closeTo(0.01, 1e-9));
      expect(corners[1].today, closeTo(0.02, 1e-9));
      // Days averaged by laps, as their history.
      final first = profile.days.firstWhere((d) => d.eventId == 'j0');
      expect(
        lastTimeHereCorners(profile, 'jastrzab', first, today).first.then,
        closeTo(0.55, 1e-9),
      );
      // A day without corners measured, or another track: none.
      final car2 = profile.days.firstWhere((d) => d.eventId == 'j15');
      expect(lastTimeHereCorners(profile, 'jastrzab', car2, today), isEmpty);
      expect(lastTimeHereCorners(profile, 'torun', then, today), isEmpty);
      expect(lastTimeHereCorners(profile, 'nowhere', then, today), isEmpty);
    });

    test("a corner's history averages its sessions by laps", () {
      final history = cornerHistory(profile, 'jastrzab', 'k1');
      expect([for (final v in history) v.day.eventId], ['j0', 'j10', 'j20', 'j30']);
      expect(history.first.laps, 12);
      expect(history.first.lossSeconds, closeTo(0.55, 1e-9));
      expect(history.first.bestMinimumSpeed, 21);
      expect(cornerHistory(profile, 'jastrzab', 'k1', carId: 'car2'), isEmpty);
      expect(cornerHistory(profile, 'poznan', 'k1'), isEmpty);
    });

    test('repeated losses: active, fixed, and once is not repeated', () {
      final losses = repeatedLosses(profile, trackId: 'jastrzab');
      expect([for (final l in losses) l.cornerId], ['k1', 'k2']);
      final k1 = losses.first;
      expect(k1.visits, 4);
      expect(k1.state, RepeatedLossState.active);
      expect(k1.meanLossSeconds, closeTo((0.55 + 0.4 + 0.4 + 0.3) / 4, 1e-9));
      final k2 = losses[1];
      expect(k2.visits, 2);
      expect(k2.state, RepeatedLossState.fixed);
      expect(k2.lastLost.eventId, 'j10');
      expect(repeatedLosses(profile, trackId: 'poznan'), isEmpty);
      expect(repeatedLosses(profile, carId: 'car2'), isEmpty);
    });

    test('a loss not measured on two later visits fades', () {
      final fading = _profile(
        [
          days[0],
          days[2],
          _visit('later1', 40, track: 'jastrzab', sessions: [_session('s1', best: 70)]),
          _visit('later2', 41, track: 'jastrzab', sessions: [_session('s1', best: 70)]),
        ],
        tracks: [_track('jastrzab', corner)],
      );
      final k1 = repeatedLosses(fading).firstWhere((l) => l.cornerId == 'k1');
      expect(k1.state, RepeatedLossState.fading);
    });

    test('a corner before a day: earlier visits in its car only', () {
      ProfileDay day(String id) => profile.day(id)!;
      // Before j30: j0, j10 and j20 (j15 is in car2); k2 lost on j0 and j10.
      final k2 = cornerBefore(profile, day('j30'), 'k2')!;
      expect(k2.corner.name, 'Corner 2');
      expect((k2.visits, k2.measured, k2.lost), (3, 3, 2));
      expect(k2.lastLost!.eventId, 'j10');
      expect(k2.notOnLastTwo, isFalse);
      // Before the undated day: every dated one, and j20 and j30 measured
      // k2 without a loss.
      final undated = cornerBefore(profile, day('undated'), 'k2')!;
      expect((undated.visits, undated.measured, undated.lost), (4, 4, 2));
      expect(undated.notOnLastTwo, isTrue);
      // Later days are left out.
      final j20 = cornerBefore(profile, day('j20'), 'k1')!;
      expect((j20.visits, j20.measured, j20.lost), (2, 2, 2));
      expect(j20.lastLost!.eventId, 'j10');
      expect(cornerBefore(profile, day('undated'), 'k3')!.lost, 1);
      // Measured, never among the costliest (under 0.1 s).
      final k4 = cornerBefore(profile, day('undated'), 'k4')!;
      expect((k4.measured, k4.lost, k4.lastLost, k4.notOnLastTwo), (4, 0, null, false));
      // A first visit, and the first in another car.
      final first = cornerBefore(profile, day('j0'), 'k1')!;
      expect((first.visits, first.measured, first.lost), (0, 0, 0));
      expect(cornerBefore(profile, day('j15'), 'k1')!.visits, 0);
      // Earlier visits that did not measure the corner.
      final unmeasured = _profile(
        [_visit('a', 0, track: 'jastrzab'), days[2]],
        tracks: [_track('jastrzab', corner)],
      );
      final none = cornerBefore(unmeasured, days[2], 'k1')!;
      expect((none.visits, none.measured), (1, 0));
      // Not a corner of the track, or a track without it.
      expect(cornerBefore(profile, day('j30'), 'nowhere'), isNull);
      expect(cornerBefore(profile, day('p25'), 'k1'), isNull);
    });

    test('skill levels over the last three days, with confidence and trend', () {
      final skills = {for (final s in skillLevels(profile, carId: 'car1')) s.skill.id: s};
      expect(skills.keys, [for (final s in skillCatalogue) s.id]);
      expect(skills.length, 12);
      // The fixture's corners carry no pedal, G, line or sequence figures.
      for (final id in [
        'liftTiming',
        'brakeReleaseTiming',
        'brakingEffectiveness',
        'turnInConsistency',
        'lineConsistency',
        'throttleReapplication',
        'throttleCommitment',
        'cornerSequenceManagement',
      ]) {
        expect(skills[id]!.level, isNull, reason: id);
        expect(skills[id]!.confidence, isNull);
      }
      // Lap spread over the undated day (no spread), j30, j20, j10: 0.8, 2, 4.
      final consistency = skills['paceConsistency']!;
      expect(consistency.days, 3);
      expect(consistency.value, closeTo((0.8 + 2 + 4) / 3, 1e-9));
      expect(consistency.level, 4);
      expect(consistency.rankedLaps, 18);
      expect(consistency.confidence, SkillConfidence.high);
      expect(consistency.lastDay!.eventId, 'j30');
      // Before: j0 alone, spread 5.5 → level 2.
      expect(consistency.trend, SkillTrend.improving);

      // Braking spread: j30 3, j20 3, j10 5 → 3.67 m, level 5; before 12 → 2.
      final brake = skills['brakePointConsistency']!;
      expect(brake.value, closeTo(11 / 3, 1e-9));
      expect(brake.level, 5);
      expect(brake.trend, SkillTrend.improving);

      // Minimum and exit speed: 1 m/s and 0.5 m/s below the day's best.
      expect(skills['minimumSpeedControl']!.value, closeTo(3.6, 1e-9));
      expect(skills['minimumSpeedControl']!.level, 4);
      expect(skills['exitSpeedExecution']!.value, closeTo(1.8, 1e-9));
      expect(skills['exitSpeedExecution']!.level, 4);
      expect(skills['exitSpeedExecution']!.trend, SkillTrend.steady);
    });

    test('the pedal, G, line and sequence skills from each corner', () {
      CornerStats corner(String id, double scale, double deceleration) => CornerStats(
        cornerId: id,
        laps: 6,
        liftSeconds: 0.3 * scale,
        releaseSpreadMeters: 10 * scale,
        decelerationG: deceleration,
        bestDecelerationG: deceleration,
        entrySpeedSpread: 1 * scale,
        lineSpreadMeters: 0.8 * scale,
        pickupSpreadMeters: 5 * scale,
        throttleKnownLaps: 10,
        releasedPickups: scale.round(),
        sequenceLossSeconds: 0.04 * scale,
      );
      final measured = _profile([
        _visit(
          'm',
          1,
          track: 'jastrzab',
          sessions: [
            // k1 brakes at 0.8 g at best, k2 at 0.5 g.
            _session('s1', corners: [corner('k1', 1, 0.8), corner('k2', 1, 0.5)]),
            _session('s2', corners: [corner('k1', 2, 0.6), corner('k2', 2, 0.45)]),
          ],
        ),
      ]);
      final skills = {for (final s in skillLevels(measured)) s.skill.id: s};
      // Sessions weigh alike (6 laps each): the mean of 1x and 2x.
      expect(skills['liftTiming']!.value, closeTo(0.45, 1e-9));
      expect(skills['liftTiming']!.level, 3);
      expect(skills['brakeReleaseTiming']!.value, closeTo(15, 1e-9));
      expect(skills['brakeReleaseTiming']!.level, 2);
      // s1 at the day's best, s2 0.2 g and 0.05 g short: median 0.125, / 2.
      expect(skills['brakingEffectiveness']!.value, closeTo(0.0625, 1e-9));
      expect(skills['brakingEffectiveness']!.level, 3);
      expect(skills['turnInConsistency']!.value, closeTo(1.5 * 3.6, 1e-9));
      expect(skills['turnInConsistency']!.level, 3);
      expect(skills['lineConsistency']!.value, closeTo(1.2, 1e-9));
      expect(skills['lineConsistency']!.level, 3);
      expect(skills['throttleReapplication']!.value, closeTo(7.5, 1e-9));
      expect(skills['throttleReapplication']!.level, 3);
      // Pooled over each session's passes: 2 of 20 (10 %), 4 of 20 (20 %).
      expect(skills['throttleCommitment']!.value, closeTo(15, 1e-9));
      expect(skills['throttleCommitment']!.level, 4);
      expect(skills['cornerSequenceManagement']!.value, closeTo(0.06, 1e-9));
      expect(skills['cornerSequenceManagement']!.level, 3);

      // A session without the pedals measures none of their skills.
      final bare = _profile([
        _visit(
          'b',
          1,
          track: 'jastrzab',
          sessions: [
            _session('s1', corners: [CornerStats(cornerId: 'k1', laps: 6)]),
          ],
        ),
      ]);
      for (final skill in skillLevels(bare)) {
        expect(skill.level, isNull, reason: skill.skill.id);
      }
    });

    test('a session on another layout counts in totals only', () {
      ProfileSession other(String id) => ProfileSession(
        runId: id,
        name: id,
        lapCount: 5,
        bestLapSeconds: 40,
        stats: SessionStats(
          distanceMeters: 1000,
          rankedLaps: 5,
          medianLapSeconds: 41,
          lapSpreadSeconds: 9,
          otherLayout: true,
          corners: [CornerStats(cornerId: 'k1', laps: 5, lossSeconds: 3)],
        ),
      );
      final mixed = _profile(
        [
          _visit(
            'a',
            0,
            track: 'jastrzab',
            sessions: [_session('s1', best: 70, median: 71, spread: 1), other('o')],
            dayBest: 70,
          ),
        ],
        tracks: [_track('jastrzab', corner)],
      );
      final read = _roundTrip(mixed);
      expect(read.day('a')!.sessions.last.stats!.otherLayout, isTrue);
      expect(driverTotals(read).distanceMeters, 21000);
      expect(trackRecords(read)['jastrzab']!.bestLap!.seconds, 70);
      expect(trackRecords(read)['jastrzab']!.bestLap!.runId, 's1');
      // Written before stats: only the day's best lap is the track's.
      final old = _profile([
        _visit(
          'b',
          0,
          track: 'jastrzab',
          dayBest: 70,
          sessions: [
            ProfileSession(runId: 's1', name: 's1', bestLapSeconds: 70),
            ProfileSession(runId: 'o', name: 'o', bestLapSeconds: 40),
          ],
        ),
      ]);
      expect(trackRecords(old)['jastrzab']!.bestLap!.seconds, 70);
      expect(trackRecords(old)['jastrzab']!.bestLap!.runId, isNull);
      expect(trackRecords(read)['jastrzab']!.bestTypicalLap!.seconds, 71);
      expect(trackProgress(read, 'jastrzab').single.lapSpreadSeconds, 1);
      expect(cornerHistory(read, 'jastrzab', 'k1'), isEmpty);
      expect(skillLevels(read).last.value, 1);
    });

    test('confidence follows the ranked laps behind a level', () {
      final few = _profile([
        _visit('a', 0, track: 'poznan', sessions: [_session('s', laps: 4, spread: 1)]),
      ]);
      expect(skillLevels(few).last.confidence, SkillConfidence.low);
      final some = _profile([
        _visit('a', 0, track: 'poznan', sessions: [_session('s', laps: 14, spread: 1)]),
      ]);
      expect(skillLevels(some).last.confidence, SkillConfidence.medium);
      expect(skillLevels(some).last.trend, isNull);
    });

    test('levels step down at each band', () {
      final consistency = skillCatalogue.last;
      expect(consistency.levelOf(0), 5);
      expect(consistency.levelOf(1), 5);
      expect(consistency.levelOf(1.01), 4);
      expect(consistency.levelOf(2.6), 3);
      expect(consistency.levelOf(5.1), 2);
      expect(consistency.levelOf(8.1), 1);
      expect(consistency.levelOf(1000), 1);
    });

    test('the most days a profile holds fit, corners up to their budget', () {
      // Worst case: every day 5 sessions; the first days carry 15 corners
      // each until the budget is spent.
      final ids = [for (var i = 0; i < 15; i++) 'c${i.toString().padLeft(31, '0')}'];
      final busy = [
        for (var i = 0; i < 15; i++)
          CornerStats(
            cornerId: ids[i],
            laps: 12,
            minimumSpeed: 18.123,
            bestMinimumSpeed: 19.456,
            exitSpeed: 23.789,
            bestExitSpeed: 24.012,
            brakingSpreadMeters: 6.345,
            lossSeconds: 0.312,
            liftSeconds: 0.345,
            releaseSpreadMeters: 7.123,
            decelerationG: 0.845,
            bestDecelerationG: 0.987,
            entrySpeedSpread: 1.234,
            lineSpreadMeters: 0.678,
            pickupSpreadMeters: 8.901,
            throttleKnownLaps: 12,
            releasedPickups: 3,
            sequenceLossSeconds: 0.456,
          ),
      ];
      ProfileSession full(String id, List<CornerStats> corners) => ProfileSession(
        runId: id.padLeft(32, '0'),
        name: 'Session $id',
        startMilliseconds: _day0,
        lapCount: 14,
        bestLapSeconds: 109.898,
        stats: SessionStats(
          distanceMeters: 31234.567,
          drivingSeconds: 1612.345,
          rankedLaps: 12,
          medianLapSeconds: 111.234,
          lapSpreadSeconds: 1.234,
          theoreticalBestSeconds: 108.765,
          corners: corners,
        ),
      );
      var corners = maximumProfileCornerStats;
      final days = <ProfileDay>[];
      for (var d = 0; d < maximumProfileDays; d++) {
        days.add(
          ProfileDay(
            eventId: 'e${d.toString().padLeft(31, '0')}',
            file: 'Days/e${d.toString().padLeft(31, '0')}.fetproject',
            name: 'Day 2026-08-29',
            carId: 'car1',
            trackId: 'jastrzab',
            startMilliseconds: _day0 + d * _dayMs,
            bestLapSeconds: 109.898,
            theoreticalBestSeconds: 108.765,
            sessions:
                [
                  for (var s = 0; s < 5; s++)
                    full('$s', corners >= 15 ? busy : const <CornerStats>[]),
                ].map((session) {
                  corners -= session.stats!.corners.length;
                  return session;
                }).toList(),
          ),
        );
      }
      final big = _profile(days.sublist(1), tracks: [_track('jastrzab', corner)]);
      final text = encodeDriverProfile(big);
      expect(text.length, lessThan(maximumProfileCharacters));
      // Over the budget, a day is added without its corners.
      final crowded = _profile(days.sublist(0, 4000), tracks: [_track('jastrzab', corner)]);
      final input = ProfileDayInput(
        eventId: 'new',
        file: 'Days/new.fetproject',
        name: 'new',
        measuredCorners: true,
        sessions: [full('n', busy)],
      );
      final added = _add(crowded, input).day('new')!;
      expect(added.sessions.single.stats!.corners, isEmpty);
      expect(added.sessions.single.stats!.distanceMeters, 31234.567);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a day already in a profile past the budget keeps its corners', () {
      final first = _add(DriverProfile.empty(Random(1)), _input('old'));
      final old = first.day('old')!;
      final kept = old.sessions.single.stats!.corners;
      expect(kept, isNotEmpty);
      // Another day with more corners than the budget, as a profile written
      // under an older, larger one may hold.
      final crowded = DriverProfile(
        driverId: first.driverId,
        cars: first.cars,
        tracks: first.tracks,
        lastCarId: first.lastCarId,
        days: [
          old,
          ProfileDay(
            eventId: 'full',
            file: 'Days/full.fetproject',
            name: 'full',
            carId: old.carId,
            trackId: old.trackId,
            sessions: [
              for (var i = 0; i <= maximumProfileCornerStats ~/ kept.length; i++)
                ProfileSession(
                  runId: 'r$i',
                  name: 'r$i',
                  stats: SessionStats(rankedLaps: 4, corners: kept),
                ),
            ],
          ),
        ],
      );
      final again = _add(crowded, _input('old')).day('old')!;
      expect(again.sessions.single.stats!.corners, hasLength(kept.length));
      expect(again.sessions.single.stats!.corners.first.cornerId, kept.first.cornerId);
      // A new day gets none.
      final added = _add(crowded, _input('new', start: 1756454400000 + 86400000)).day('new')!;
      expect(added.sessions.single.stats!.corners, isEmpty);
    });

    test('many days stay quick', () {
      final many = _profile(
        [
          for (var i = 0; i < 2000; i++)
            _visit(
              'd$i',
              i,
              track: ['jastrzab', 'poznan', 'torun'][i % 3],
              car: i.isEven ? 'car1' : 'car2',
              theoretical: 70,
              sessions: [
                for (var s = 0; s < 4; s++)
                  _session(
                    's$s',
                    best: 70.0 + s,
                    median: 72,
                    spread: 1,
                    corners: corners(0.2, 0.1, 0.3),
                  ),
              ],
            ),
        ],
        tracks: [_track('jastrzab', corner), _track('poznan', corner), _track('torun', corner)],
      );
      final watch = Stopwatch()..start();
      driverTotals(many);
      carTotals(many);
      trackRecords(many);
      trackProgress(many, 'jastrzab');
      repeatedLosses(many);
      skillLevels(many);
      expect(watch.elapsedMilliseconds, lessThan(5000));
      final text = encodeDriverProfile(many);
      expect(text.length, lessThan(maximumProfileCharacters));
      expect(driverTotals(decodeDriverProfile(text)).sessions, 8000);
    });
  });
}
