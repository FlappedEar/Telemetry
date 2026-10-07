// Property tests for lap detection (FET-216): on seeded random recordings
// (circle or rounded rectangle, 2–5 laps, 12–45 m/s, 4–25 Hz, GPS noise,
// dropouts, invalid fixes, timing jitter) the gate passes and timed laps keep
// their invariants, and on clean recordings they match the truth.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'generators.dart';

const _seed = 216001;
const _cases = 300;

void _checkInvariants(LapCase c, LapSession laps) {
  final reason = c.label;
  final duration = c.session.duration;
  final passes = laps.acceptedPasses;
  for (var index = 0; index < passes.length; ++index) {
    final time = passes[index].telemetryTime;
    expect(time.isFinite && time >= 0.0 && time <= duration, isTrue, reason: '$reason pass $index');
    if (index > 0) {
      // Strictly increasing pass (and so lap boundary) times.
      expect(time, greaterThan(passes[index - 1].telemetryTime), reason: '$reason pass $index');
    }
    // The first accepted direction locks.
    expect(passes[index].direction, passes.first.direction, reason: '$reason pass $index');
  }

  final timed = laps.timedLaps;
  // Each pair of consecutive passes is one lap: no pass is skipped.
  expect(timed.length, math.max(0, passes.length - 1), reason: reason);
  for (var index = 0; index < timed.length; ++index) {
    final lap = timed[index];
    expect(lap.number, index + 1, reason: '$reason lap $index');
    expect(lap.startTelemetryTime, passes[index].telemetryTime, reason: '$reason lap $index');
    expect(lap.endTelemetryTime, passes[index + 1].telemetryTime, reason: '$reason lap $index');
    expect(lap.durationSeconds, lap.endTelemetryTime - lap.startTelemetryTime, reason: reason);
    expect(lap.durationSeconds, greaterThan(0.0), reason: '$reason lap $index');
    final distance = lap.distanceMeters;
    if (distance != null) {
      expect(distance.isFinite && distance > 0.0, isTrue, reason: '$reason lap $index');
    }
    if (index > 0) {
      final before = timed[index - 1];
      // No self-overlap: a lap starts where the one before it ended.
      expect(lap.startTelemetryTime, greaterThanOrEqualTo(before.endTelemetryTime), reason: reason);
      expect(lap.startTelemetryTime, greaterThan(before.startTelemetryTime), reason: reason);
      expect(lap.endTelemetryTime, greaterThan(before.endTelemetryTime), reason: reason);
    }
  }

  // The fastest lap is the quickest reference-eligible one.
  final eligible = [
    for (var index = 0; index < timed.length; ++index)
      if (timed[index].referenceEligible) index,
  ];
  if (eligible.isEmpty) {
    expect(laps.fastestLapIndex, isNull, reason: reason);
  } else {
    final fastest = laps.fastestLapIndex!;
    expect(eligible, contains(fastest), reason: reason);
    for (final index in eligible) {
      expect(timed[fastest].durationSeconds, lessThanOrEqualTo(timed[index].durationSeconds));
    }
  }

  // Lap traces stay inside their laps, in time order.
  for (final trace in laps.lapTraces) {
    final lap = timed.firstWhere((lap) => lap.number == trace.lapNumber);
    expect(lap.referenceEligible, isTrue, reason: '$reason trace ${trace.lapNumber}');
    var previous = double.negativeInfinity;
    for (final point in trace.points) {
      expect(point.telemetryTime, greaterThanOrEqualTo(previous), reason: reason);
      expect(point.telemetryTime, inInclusiveRange(lap.startTelemetryTime, lap.endTelemetryTime));
      expect(point.eastMeters.isFinite && point.northMeters.isFinite, isTrue, reason: reason);
      previous = point.telemetryTime;
    }
  }
}

void main() {
  test('passes and laps keep their invariants on $_cases random recordings', () {
    final random = math.Random(_seed);
    var withLaps = 0;
    for (var index = 0; index < _cases; ++index) {
      final c = generateLapCase(random, 'seed $_seed case $index');
      final laps = deriveSourceLapSession(c.session);
      _checkInvariants(c, laps);
      if (laps.timedLaps.isNotEmpty) ++withLaps;
    }
    // The generator really exercises lap timing.
    expect(withLaps, greaterThan(_cases * 9 ~/ 10));
  });

  test('clean recordings give every lap at its true time', () {
    final random = math.Random(_seed + 1);
    var checkedTimes = 0;
    for (var index = 0; index < _cases; ++index) {
      final c = generateLapCase(random, 'seed ${_seed + 1} case $index', clean: true);
      final laps = deriveSourceLapSession(c.session);
      _checkInvariants(c, laps);
      expect(laps.status, LapSessionStatus.available, reason: c.label);
      // Only the first crossing may be lost, when the recording starts
      // inside the detector's outer corridor (see firstPassMayBeMissed).
      final missed = c.firstPassMayBeMissed && laps.acceptedPasses.length == c.laps ? 1 : 0;
      expect(laps.acceptedPasses, hasLength(c.laps + 1 - missed), reason: c.label);
      expect(laps.timedLaps, hasLength(c.laps - missed), reason: c.label);
      for (final lap in laps.timedLaps) {
        expect(lap.referenceEligible, isTrue, reason: '${c.label} lap ${lap.number}');
      }
      final expected = c.expectedLapSeconds;
      if (expected == null) continue;
      // The crossing moves by about the GPS error over the speed at each
      // gate, plus the 10 Hz base recording's step at a change of speed.
      final noiseTolerance = 0.03 + 6.0 * c.noiseMeters / c.slowestSpeed;
      for (var lap = 0; lap < c.laps - missed; ++lap) {
        expect(
          laps.timedLaps[lap].durationSeconds,
          closeTo(expected[lap + missed], noiseTolerance + c.stepErrorSeconds[lap + missed]),
          reason: '${c.label} lap ${lap + 1}',
        );
        ++checkedTimes;
      }
    }
    expect(checkedTimes, greaterThan(0));
  });

  test('dropping fixes never adds a pass or splits a lap', () {
    // Removing GPS can only lose passes: every pass found with dropouts is
    // one of the passes of the same recording without them.
    final random = math.Random(_seed + 2);
    for (var index = 0; index < _cases ~/ 2; ++index) {
      final label = 'seed ${_seed + 2} case $index';
      final c = generateLapCase(random, label, clean: true);
      final full = deriveSourceLapSession(c.session);
      final reduced = withDropouts(random, c.session);
      final partial = deriveSourceLapSession(reduced.session);
      _checkInvariants(
        LapCase(
          label: '$label ${reduced.description}',
          session: reduced.session,
          laps: c.laps,
          clean: false,
          expectedLapSeconds: null,
          noiseMeters: c.noiseMeters,
          slowestSpeed: c.slowestSpeed,
        ),
        partial,
      );
      for (final pass in partial.acceptedPasses) {
        final nearest = full.acceptedPasses
            .map((other) => (other.telemetryTime - pass.telemetryTime).abs())
            .reduce(math.min);
        expect(
          nearest,
          lessThan(1.0),
          reason: '$label ${reduced.description} pass ${pass.telemetryTime}',
        );
      }
    }
  });
}
