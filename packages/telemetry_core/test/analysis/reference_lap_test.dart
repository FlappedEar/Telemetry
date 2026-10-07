// A reference lap from outside the day (FET-175): timed on today's line,
// refused on another track, compared with today's lap in each side's own
// units.
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

// A lap at [straight] m/s, slowed to [slow] m/s over [from, to] metres.
double Function(double) _lap(double straight, [double from = 0, double to = 0, double slow = 0]) =>
    (d) => d >= from && d <= to ? slow : straight;

/// [session] without its own start line and with [header] lines (as a VBO
/// `[header]` keeps them), or without GPS.
TelemetrySession _as(TelemetrySession session, {List<String> header = const [], bool gps = true}) =>
    TelemetrySession(
      duration: session.duration,
      startTime: session.startTime,
      metadata: {
        ...session.metadata,
        for (var i = 0; i < header.length; ++i) 'header.$i': header[i],
      },
      channels: {
        for (final MapEntry(:key, :value) in session.channels.entries)
          if (gps || (key != 'latitude' && key != 'longitude')) key: value,
      },
      aliases: {
        for (final MapEntry(:key, :value) in session.aliases.entries)
          if (gps || (key != 'latitude' && key != 'longitude')) key: value,
      },
      warnings: const [],
      timingGates: const [],
      sampleCount: session.sampleCount,
    );

void main() {
  final today = rectangleSession([_lap(30), _lap(29), _lap(30.5)]);
  final todayLaps = deriveSourceLapSession(today);
  final gate = todayLaps.selectedStartGate!;
  final perimeter = todayLaps.timedLaps.first.distanceMeters!;

  test("times a reference without a line of its own on today's line", () {
    final reference = _as(rectangleSession([_lap(31), _lap(32, 100, 200, 20), _lap(30)]));
    expect(reference.timingGates, isEmpty);
    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'friend.vbo', session: reference),
    ], gate);
    expect(timing.refusal, ReferenceRefusal.none);
    expect(timing.usable, isTrue);
    expect(timing.nearestGateDistanceMeters, lessThan(1.0));
    expect(timing.candidates.map((lap) => lap.lapNumber), [1, 2, 3]);
    // The fastest is the first lap, at 31 m/s all the way round.
    final fastest = timing.fastest!;
    expect(fastest.lapNumber, 1);
    expect(fastest.recordingLabel, 'friend.vbo');
    expect(fastest.durationSeconds, closeTo(perimeter / 31, 0.3));
    // The same laps as the day's own lap detection finds on that line.
    final detected = detectLaps(reference, gate);
    expect(
      timing.candidates.map((lap) => lap.durationSeconds),
      detected.timedLaps.map((lap) => lap.durationSeconds),
    );
  });

  test('refuses a reference from another track', () {
    final elsewhere = rectangleSession([
      _lap(30),
      _lap(30),
    ], centre: const GeoCoordinate(50.0, 19.0));
    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'other.vbo', session: elsewhere),
    ], gate);
    expect(timing.refusal, ReferenceRefusal.wrongTrack);
    expect(timing.usable, isFalse);
    expect(timing.candidates, isEmpty);
    expect(timing.fastest, isNull);
    expect(timing.nearestGateDistanceMeters, greaterThan(100000));
  });

  test('refuses a recording near the line that never laps it, or without GPS', () {
    // A line 200 m north of the start, outside the rectangle (75 m north
    // at most): the GPS comes within 125 m but never crosses it.
    final north = 200 / (6371000.0 * pi / 180.0);
    final away = TimingGate(
      type: TimingGateType.start,
      sourceName: 'Start',
      endpointA: GeoCoordinate(
        gate.endpointA.latitudeDegrees + north,
        gate.endpointA.longitudeDegrees,
      ),
      endpointB: GeoCoordinate(
        gate.endpointB.latitudeDegrees + north,
        gate.endpointB.longitudeDegrees,
      ),
    );
    final timing = timeReferenceLaps([ReferenceRecording(label: 'a.vbo', session: today)], away);
    expect(timing.refusal, ReferenceRefusal.noTimedLap);
    expect(timing.nearestGateDistanceMeters, closeTo(125, 5));

    final blind = timeReferenceLaps([
      ReferenceRecording(label: 'b.vbo', session: _as(today, gps: false)),
    ], gate);
    expect(blind.refusal, ReferenceRefusal.noGps);
  });

  test('takes the fastest lap across the sessions of an earlier day', () {
    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'Session 1', session: _as(rectangleSession([_lap(29), _lap(30)]))),
      ReferenceRecording(
        label: 'Session 2',
        session: rectangleSession([_lap(30)], centre: const GeoCoordinate(50.0, 19.0)),
      ),
      ReferenceRecording(label: 'Session 3', session: _as(rectangleSession([_lap(32), _lap(31)]))),
    ], gate);
    expect(timing.refusal, ReferenceRefusal.none);
    // Session 2 is elsewhere: not timed, but the others are.
    expect(timing.laps[1].timedLaps, isEmpty);
    expect(timing.fastest!.recordingLabel, 'Session 3');
    expect(timing.fastest!.lapNumber, 1);
  });

  test('never pools or relabels units; an undeclared one is assumed', () {
    final declaredKmh = _as(today, header: ['velocity kmh']);
    final declaredMph = _as(today, header: ['velocity mph']);
    final undeclared = _as(today);

    final same = referenceChannelUnits(declaredKmh, _as(today, header: ['velocity km/h']), 'speed');
    expect(same.today.unit, 'km/h');
    expect(same.reference.unit, 'km/h');
    expect(same.today.assumed || same.reference.assumed, isFalse);
    expect(same.comparable, isTrue);

    final mixed = referenceChannelUnits(declaredKmh, declaredMph, 'speed', assumed: 'km/h');
    expect(mixed.today.unit, 'km/h');
    // Declared mph stays mph whatever is assumed for unlabelled speeds.
    expect(mixed.reference.unit, 'mph');
    expect(mixed.reference.assumed, isFalse);
    expect(mixed.comparable, isFalse);

    final unlabelled = referenceChannelUnits(declaredKmh, undeclared, 'speed');
    expect(unlabelled.reference.unit, '');
    expect(unlabelled.comparable, isFalse);

    final assumed = referenceChannelUnits(declaredKmh, undeclared, 'speed', assumed: 'km/h');
    expect(assumed.reference.unit, 'km/h');
    expect(assumed.reference.assumed, isTrue);
    expect(assumed.today.assumed, isFalse);
    expect(assumed.comparable, isTrue);

    final against = referenceChannelUnits(declaredMph, undeclared, 'speed', assumed: 'km/h');
    expect(against.comparable, isFalse);

    final missing = referenceChannelUnits(declaredKmh, undeclared, 'throttle');
    expect(missing.today.recorded, isFalse);
    expect(missing.comparable, isFalse);
  });

  test("compares today's lap with the reference on today's segments", () {
    final reference = _as(rectangleSession([_lap(30), _lap(30, 100, 200, 20)]));
    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'friend.vbo', session: reference),
    ], gate);
    final slow = timing.candidates.firstWhere((lap) => lap.lapNumber == 2);
    final best = todayLaps.timedLaps.first;
    final todayLap = ComparisonLap(
      session: today,
      laps: todayLaps,
      start: best.startTelemetryTime,
      end: best.endTelemetryTime,
      lapNumber: best.number,
    );
    final analysis = analyzeDay([
      DayRunInput(
        runId: 'run1',
        name: 'Session 1',
        contentSha256: 'a' * 64,
        session: today,
        laps: todayLaps,
      ),
    ]);
    final groupId = analysis.chosenGroup!.id;
    final segments = automaticTrackSegments(
      documentRuns: const [],
      groupId: groupId,
      storedSegments: null,
      session: today,
      laps: todayLaps,
      lapNumber: best.number,
      startTime: best.startTelemetryTime,
      endTime: best.endTelemetryTime,
      random: Random(5),
    )!;
    final segmentation = ComparisonSegmentation(shared: approvedSegmentation(segments, groupId));
    expect(segmentation.shared!.valid, isTrue);
    final compared = ReferenceLapComparison(
      today: todayLap,
      timing: timing,
      lap: slow,
      referenceSession: reference,
      segmentation: segmentation,
    );
    // Today − reference: today is quicker, so negative.
    expect(compared.lapDeltaSeconds, lessThan(-1.0));
    expect(compared.comparison.axis.valid, isTrue);
    final delta = compared.comparison.deltaSeries(0, compared.comparison.axisLengthMeters, 400);
    expect(delta.segments.last.last.y, closeTo(compared.lapDeltaSeconds, 0.1));

    final times = compared.segmentTimes();
    expect(times, hasLength(segmentation.shared!.segments.length));
    for (final time in times) {
      expect(time.deltaSeconds, isNotNull, reason: time.unavailableReason);
      expect(time.deltaSeconds, closeTo(time.todaySeconds! - time.referenceSeconds!, 1e-9));
    }
    // The reference's slow stretch (100 to 200 m) is where today gains.
    final gained = times.reduce((x, y) => x.deltaSeconds! < y.deltaSeconds! ? x : y);
    expect(gained.segment.startMeters, lessThan(200));
    expect(gained.deltaSeconds, lessThan(-1.0));
    expect(
      times.fold<double>(0, (sum, time) => sum + time.deltaSeconds!),
      closeTo(compared.lapDeltaSeconds, 0.1),
    );

    // Without segments there is nothing to time, and no row says otherwise.
    final plain = ReferenceLapComparison(
      today: todayLap,
      timing: timing,
      lap: slow,
      referenceSession: reference,
    );
    expect(plain.segmentTimes(), isEmpty);
  });
}
