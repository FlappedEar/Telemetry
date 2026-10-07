// A reference lap from outside the day (FET-175): timed on today's line,
// refused on another track, compared with today's lap in each side's own
// units.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';
import '../support/fusion_pair.dart';

// A lap at [straight] m/s, slowed to [slow] m/s over [from, to] metres.
double Function(double) _lap(double straight, [double from = 0, double to = 0, double slow = 0]) =>
    (d) => to > from && d >= from && d <= to ? slow : straight;

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

/// [session] driven backwards: the same places, in the opposite order.
TelemetrySession _reversed(TelemetrySession session) {
  final end = session.duration;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: session.metadata,
    channels: {
      for (final MapEntry(:key, :value) in session.channels.entries)
        key: TelemetryChannel(
          name: value.name,
          unit: value.unit,
          timestamps: Float64List.fromList([
            for (final time in value.timestamps.reversed) end - time,
          ]),
          values: Float32List.fromList(value.values.reversed.toList()),
        ),
    },
    aliases: session.aliases,
    warnings: const [],
    timingGates: const [],
    sampleCount: session.sampleCount,
  );
}

void main() {
  final today = rectangleSession([_lap(30), _lap(29), _lap(30.5)]);
  final todayLaps = deriveSourceLapSession(today);
  final gate = todayLaps.selectedStartGate!;
  final perimeter = todayLaps.timedLaps.first.distanceMeters!;
  final line = referenceLineOf(today, todayLaps, todayLaps.timedLaps.first.number)!;

  test("times a reference without a line of its own on today's line", () {
    final reference = _as(rectangleSession([_lap(31), _lap(32, 100, 200, 20), _lap(30)]));
    expect(reference.timingGates, isEmpty);
    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'friend.vbo', session: reference),
    ], line);
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
    ], line);
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
    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'a.vbo', session: today),
    ], ReferenceLine(gate: away));
    expect(timing.refusal, ReferenceRefusal.noTimedLap);
    expect(timing.nearestGateDistanceMeters, closeTo(125, 5));

    final blind = timeReferenceLaps([
      ReferenceRecording(label: 'b.vbo', session: _as(today, gps: false)),
    ], line);
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
    ], line);
    expect(timing.refusal, ReferenceRefusal.none);
    // Session 2 is elsewhere: not timed and not kept, but the others are.
    expect(timing.statuses, [
      ReferenceRecordingStatus.timed,
      ReferenceRecordingStatus.tooFar,
      ReferenceRecordingStatus.timed,
    ]);
    expect(timing.recordings.map((recording) => recording.label), ['Session 1', 'Session 3']);
    expect(timing.laps, hasLength(2));
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

    // Two unlabelled speeds from two loggers may be in different units:
    // never on one axis unless a unit is assumed and stated.
    final neither = referenceChannelUnits(undeclared, undeclared, 'speed');
    expect(neither.today.unit, '');
    expect(neither.comparable, isFalse);
    final bothAssumed = referenceChannelUnits(undeclared, undeclared, 'speed', assumed: 'km/h');
    expect(bothAssumed.today.assumed && bothAssumed.reference.assumed, isTrue);
    expect(bothAssumed.comparable, isTrue);

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
    ], line);
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
    expect(compared.coverage, greaterThan(0.99));
    expect(delta.segments.last.last.y, closeTo(compared.lapDeltaSeconds!, 0.1));

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
      closeTo(compared.lapDeltaSeconds!, 0.1),
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

  test('mirrors an RCZ reference into a VBO day\'s longitudes', () {
    final directory = Directory.systemTemp.createTempSync('reference_rcz');
    addTearDown(() => directory.deleteSync(recursive: true));
    final (vbo, rcz) = writeFusionPair(directory.path);
    final plan = prepareTelemetryImport([vbo, rcz]);
    final vboRun = plan.runs.firstWhere((run) => run.format == RecordingFormat.vbo);
    final rczRun = plan.runs.firstWhere((run) => run.format == RecordingFormat.rcz);
    expect(longitudeWestPositive(vboRun.telemetry), isTrue);
    expect(longitudeWestPositive(rczRun.telemetry), isFalse);
    final ownBest = vboRun.laps.timedLaps.reduce(
      (x, y) => x.durationSeconds <= y.durationSeconds ? x : y,
    );
    final vboLine = referenceLineOf(vboRun.telemetry, vboRun.laps, ownBest.number)!;
    expect(vboLine.westPositive, isTrue);
    expect(vboLine.route, isNotNull);

    // The RCZ's longitudes are east-positive: as read, its GPS is on the
    // other side of the meridian, about 2,870 km from the VBO's line.
    final unmirrored = timeReferenceLaps([
      ReferenceRecording(label: 'drive.rcz', session: rczRun.telemetry),
    ], ReferenceLine(gate: vboLine.gate, route: vboLine.route));
    expect(unmirrored.refusal, ReferenceRefusal.wrongTrack);

    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'drive.rcz', session: rczRun.telemetry),
    ], vboLine);
    expect(timing.refusal, ReferenceRefusal.none);
    expect(timing.nearestGateDistanceMeters, lessThan(5));
    expect(longitudeWestPositive(timing.recordings.single.session), isTrue);
    // The same drive: the RCZ's laps on the VBO's line take as long as the
    // VBO's own.
    final own = {for (final lap in vboRun.laps.timedLaps) lap.number: lap.durationSeconds};
    expect(timing.candidates, isNotEmpty);
    for (final lap in timing.candidates) {
      expect(lap.durationSeconds, closeTo(own[lap.lapNumber]!, 0.15));
    }

    // And compared on the VBO's lap, the two are the same lap.
    final fastest = timing.fastest!;
    final compared = ReferenceLapComparison(
      today: ComparisonLap(
        session: vboRun.telemetry,
        laps: vboRun.laps,
        start: vboRun.laps.timedLaps
            .firstWhere((lap) => lap.number == fastest.lapNumber)
            .startTelemetryTime,
        end: vboRun.laps.timedLaps
            .firstWhere((lap) => lap.number == fastest.lapNumber)
            .endTelemetryTime,
        lapNumber: fastest.lapNumber,
      ),
      timing: timing,
      lap: fastest,
      referenceSession: timing.recordings[fastest.recordingIndex].session,
    );
    expect(compared.comparison.axis.valid, isTrue);
    expect(compared.coverage, greaterThan(referenceMinimumCoverage));
    expect(compared.lapDeltaSeconds, closeTo(0, 0.15));

    // An RCZ day takes a VBO reference the other way round.
    // (An RCZ day's line: the VBO's, east-positive.)
    GeoCoordinate east(GeoCoordinate point) =>
        GeoCoordinate(point.latitudeDegrees, -point.longitudeDegrees);
    final rczLaps = detectLaps(
      rczRun.telemetry,
      TimingGate(
        type: TimingGateType.start,
        sourceName: 'Start',
        endpointA: east(vboLine.gate.endpointA),
        endpointB: east(vboLine.gate.endpointB),
      ),
    );
    final rczLine = referenceLineOf(rczRun.telemetry, rczLaps, rczLaps.timedLaps[1].number)!;
    expect(rczLine.westPositive, isFalse);
    final back = timeReferenceLaps([
      ReferenceRecording(label: 'drive.vbo', session: vboRun.telemetry),
    ], rczLine);
    expect(back.refusal, ReferenceRefusal.none);
    expect(longitudeWestPositive(back.recordings.single.session), isFalse);
  });

  test("refuses today's route driven the other way round", () {
    final backwards = _reversed(rectangleSession([_lap(30), _lap(30), _lap(30)]));
    // Its laps do cross today's line...
    expect(detectLaps(backwards, gate).timedLaps.where((lap) => lap.referenceEligible), isNotEmpty);
    // ...but go round the other way.
    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'reverse.vbo', session: backwards),
    ], line);
    expect(timing.refusal, ReferenceRefusal.oppositeDirection);
    expect(timing.statuses, [ReferenceRecordingStatus.oppositeDirection]);
    expect(timing.candidates, isEmpty);
    expect(timing.recordings, isEmpty);

    // Without today's route the line alone cannot tell.
    final unchecked = timeReferenceLaps([
      ReferenceRecording(label: 'reverse.vbo', session: backwards),
    ], ReferenceLine(gate: gate));
    expect(unchecked.refusal, ReferenceRefusal.none);
    expect(unchecked.routeUnchecked, isTrue);
    expect(timing.routeUnchecked, isFalse);
  });

  test('refuses another layout through the same line', () {
    // The far side of the circuit 60 m further west: the same start/finish
    // line, a longer lap.
    double longer(double distance) =>
        distance < 200 || distance > 620 ? 0 : 60 * sin(pi * (distance - 200) / 420);
    final layout = rectangleSession(
      [_lap(30), _lap(30), _lap(30)],
      westShifts: [longer, longer, longer],
    );
    expect(detectLaps(layout, gate).timedLaps.where((lap) => lap.referenceEligible), isNotEmpty);
    final timing = timeReferenceLaps([
      ReferenceRecording(label: 'national.vbo', session: layout),
    ], line);
    expect(timing.refusal, ReferenceRefusal.differentLayout);
    expect(timing.statuses, [ReferenceRecordingStatus.differentLayout]);
    expect(timing.candidates, isEmpty);

    // Timed without today's route, its laps leave lap A's line for a third
    // of the lap: no lap Δ, as the two are not one lap of one track.
    final unchecked = timeReferenceLaps([
      ReferenceRecording(label: 'national.vbo', session: layout),
    ], ReferenceLine(gate: gate));
    final best = todayLaps.timedLaps.first;
    final compared = ReferenceLapComparison(
      today: ComparisonLap(
        session: today,
        laps: todayLaps,
        start: best.startTelemetryTime,
        end: best.endTelemetryTime,
        lapNumber: best.number,
      ),
      timing: unchecked,
      lap: unchecked.fastest!,
      referenceSession: unchecked.recordings.single.session,
    );
    expect(compared.comparison.axis.valid, isTrue);
    expect(compared.coverage, lessThan(referenceMinimumCoverage));
    expect(compared.lapDeltaSeconds, isNull);
  });

  test("marks an earlier day's excluded laps and never takes one as fastest", () {
    final day = _as(rectangleSession([_lap(29), _lap(32), _lap(31)]));
    final laps = detectLaps(day, gate).timedLaps;
    final quickest = laps.firstWhere((lap) => lap.number == 2);
    final timing = timeReferenceLaps([
      ReferenceRecording(
        label: 'Session 1',
        id: 'run-1',
        session: day,
        exclusions: [
          (
            // The day's own line can time the lap a little differently.
            start: quickest.startTelemetryTime + 0.3,
            end: quickest.endTelemetryTime - 0.2,
            reason: 'Cut the chicane',
          ),
        ],
      ),
    ], line);
    expect(timing.refusal, ReferenceRefusal.none);
    final excluded = timing.candidates.firstWhere((lap) => lap.lapNumber == 2);
    expect(excluded.excluded, isTrue);
    expect(excluded.excludedReason, 'Cut the chicane');
    expect(excluded.recordingId, 'run-1');
    expect(timing.candidates.where((lap) => lap.excluded), hasLength(1));
    // Lap 3 (31 m/s) is the fastest not excluded.
    expect(timing.fastest!.lapNumber, 3);

    final allExcluded = timeReferenceLaps([
      ReferenceRecording(
        label: 'Session 1',
        session: day,
        exclusions: [
          for (final lap in laps)
            (start: lap.startTelemetryTime, end: lap.endTelemetryTime, reason: ''),
        ],
      ),
    ], line);
    expect(allExcluded.refusal, ReferenceRefusal.onlyExcludedLaps);
    expect(allExcluded.usable, isFalse);
    expect(allExcluded.fastest, isNull);
    // Kept, all marked, so one can still be chosen on purpose.
    expect(allExcluded.candidates, hasLength(laps.length));
    expect(allExcluded.candidates.every((lap) => lap.excluded), isTrue);
  });

  test('keeps only recordings with laps, trimmed to them', () {
    // Ten minutes parked in the pits before the laps.
    final driven = rectangleSession([_lap(30), _lap(30)]);
    final parked = TelemetrySession(
      duration: driven.duration + 600,
      startTime: 0,
      metadata: const {},
      channels: {
        for (final MapEntry(:key, :value) in driven.channels.entries)
          key: TelemetryChannel(
            name: value.name,
            timestamps: Float64List.fromList([
              for (var t = 0.0; t < 600; t += 0.1) t,
              for (final time in value.timestamps) time + 600,
            ]),
            values: Float32List.fromList([
              for (var t = 0.0; t < 600; t += 0.1) key == 'velocity' ? 0 : value.values.first,
              ...value.values,
            ]),
          ),
      },
      aliases: driven.aliases,
      warnings: const [],
      timingGates: const [],
      sampleCount: driven.sampleCount + 6000,
    );
    final timing = timeReferenceLaps([
      ReferenceRecording(
        label: 'far.vbo',
        session: rectangleSession([_lap(30)], centre: const GeoCoordinate(50.0, 19.0)),
      ),
      ReferenceRecording(label: 'pits.vbo', session: parked),
    ], line);
    expect(timing.refusal, ReferenceRefusal.none);
    expect(timing.recordings.map((recording) => recording.label), ['pits.vbo']);
    expect(timing.candidates.every((lap) => lap.recordingIndex == 0), isTrue);
    final kept = timing.recordings.single.session.channel('speed')!;
    final first = timing.candidates.first.start, last = timing.candidates.last.end;
    expect(kept.timestamps.first, greaterThanOrEqualTo(first - referenceTrimMarginSeconds - 0.1));
    expect(kept.timestamps.last, lessThanOrEqualTo(last + referenceTrimMarginSeconds + 0.1));
    expect(kept.timestamps.length, lessThan(parked.channel('speed')!.timestamps.length / 3));
    // Its laps are where they were, on the recording's own clock.
    expect(first, greaterThan(600));
  });
}
