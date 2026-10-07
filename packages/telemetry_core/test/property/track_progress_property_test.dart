// Property tests for track progress (FET-216): on seeded random recordings
// the progress a lap is projected to never falls within a locked stretch,
// and fix by fix around the whole recording it only moves forward, apart
// from the jitter allowance and the wrap at the start/finish line.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';
import 'generators.dart';

const _seed = 216101;
const _cases = 200;

/// How far a projection may step back before it is distrusted
/// (`_backwardToleranceMeters` in track_progress.dart).
const _backwardTolerance = 3.0;

/// The fastest speed the generator drives (45 m/s, up to 30 % more within
/// a rectangle lap).
const _fastest = 45.0 * 1.3;

/// The widest forward search window of [projectSample], plus a margin.
const _maximumStep = 155.0;

/// The progress axis of [laps]'s first reference-eligible lap, or null.
ProgressAxis? _axisOf(LapSession laps) {
  final gate = laps.selectedStartGate;
  if (gate == null || laps.lapTraces.isEmpty) return null;
  final origin = GeoCoordinate(
    (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
    (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
  );
  final axis = buildProgressAxis(laps.lapTraces.first, origin, gate);
  return axis.valid ? axis : null;
}

void main() {
  test('a projected lap never moves backwards within a segment', () {
    final random = math.Random(_seed);
    var checkedLaps = 0, cleanLaps = 0;
    for (var index = 0; index < _cases; ++index) {
      final c = generateLapCase(random, 'seed $_seed case $index');
      final laps = deriveSourceLapSession(c.session);
      final axis = _axisOf(laps);
      if (axis == null) continue;
      final length = axis.lengthMeters;
      for (final lap in laps.timedLaps) {
        final reason = '${c.label} lap ${lap.number}';
        final segments = projectLapTrace(
          axis,
          c.session,
          lap.startTelemetryTime,
          lap.endTelemetryTime,
        );
        ++checkedLaps;
        double? lastTime, lastProgress;
        final jump = (length - axis.cumulative.last) + 5.0 + 3.0 * c.noiseMeters;
        for (final segment in segments) {
          expect(segment.samples, isNotEmpty, reason: reason);
          for (var i = 0; i < segment.samples.length; ++i) {
            final sample = segment.samples[i];
            expect(sample.valid, isTrue, reason: reason);
            expect(sample.progressMeters.isFinite, isTrue, reason: reason);
            expect(
              sample.telemetryTime,
              inInclusiveRange(lap.startTelemetryTime, lap.endTelemetryTime),
              reason: reason,
            );
            if (lastTime != null && lastProgress != null) {
              // Time strictly increases, across segments too.
              expect(sample.telemetryTime, greaterThan(lastTime), reason: reason);
              // Progress never runs ahead of the car: at most the fastest
              // generated speed for the time since the last fix, plus the
              // axis's closing segment and a margin for GPS error.
              expect(
                sample.progressMeters - lastProgress,
                lessThanOrEqualTo(_fastest * (sample.telemetryTime - lastTime) + jump),
                reason: '$reason t=${sample.telemetryTime}',
              );
            }
            if (i > 0) {
              // Within a segment progress never falls.
              expect(
                sample.progressMeters,
                greaterThanOrEqualTo(segment.samples[i - 1].progressMeters),
                reason: '$reason t=${sample.telemetryTime}',
              );
            } else if (lastProgress != null) {
              // A segment after a gap starts at most the jitter allowance
              // behind: progress is unwrapped within the lap.
              expect(
                sample.progressMeters,
                greaterThanOrEqualTo(lastProgress - _backwardTolerance),
                reason: '$reason t=${sample.telemetryTime}',
              );
            }
            lastTime = sample.telemetryTime;
            lastProgress = sample.progressMeters;
          }
        }
        // Unwrapped, a lap starts at about 0, not before the axis's middle.
        if (segments.isNotEmpty) {
          expect(segments.first.samples.first.progressMeters, greaterThan(-length / 2));
        }
        if (c.clean && lap.referenceEligible) {
          // A clean lap is covered gate to gate. Lock may drop for a moment
          // (the reference lap's ends, recorded with different GPS error,
          // meet in a kink at the gate), but never for long.
          final step = _fastest / 4.0; // the longest step between two fixes
          final slack = step + 10.0 + 3.0 * c.noiseMeters;
          expect(segments, isNotEmpty, reason: reason);
          expect(segments.first.samples.first.progressMeters, lessThan(slack), reason: reason);
          expect(lastProgress, greaterThan(length - slack), reason: reason);
          var unlocked = 0.0;
          for (var i = 1; i < segments.length; ++i) {
            unlocked +=
                segments[i].samples.first.telemetryTime -
                segments[i - 1].samples.last.telemetryTime;
          }
          expect(unlocked, lessThan(1.0), reason: reason);
          ++cleanLaps;
        }
      }
    }
    expect(checkedLaps, greaterThan(_cases));
    expect(cleanLaps, greaterThan(_cases ~/ 4));
  });

  test('progress around the whole recording only falls at the start/finish wrap', () {
    final random = math.Random(_seed + 1);
    var wrapsSeen = 0;
    for (var index = 0; index < _cases; ++index) {
      final c = generateLapCase(random, 'seed ${_seed + 1} case $index');
      final laps = deriveSourceLapSession(c.session);
      final axis = _axisOf(laps);
      if (axis == null) continue;
      final length = axis.lengthMeters;
      final latitude = c.session.channel('latitude')!;
      final longitude = c.session.channel('longitude')!;
      var context = ProjectionContext();
      MetricPoint? previousPoint;
      double? previousTime;
      var wraps = 0;
      for (var i = 0; i < latitude.sampleCount; ++i) {
        final time = latitude.timestamps[i];
        final coordinate = GeoCoordinate(latitude.values[i], longitude.values[i]);
        if (!isValidCoordinate(coordinate)) {
          context = ProjectionContext();
          previousPoint = null;
          continue;
        }
        final point = projectCoordinate(coordinate, axis.origin);
        var movement = (0.0, 0.0), speed = 0.0;
        final before = previousPoint, beforeTime = previousTime;
        if (before != null && beforeTime != null) {
          movement = (point.eastMeters - before.eastMeters, point.northMeters - before.northMeters);
          speed =
              math.sqrt(movement.$1 * movement.$1 + movement.$2 * movement.$2) /
              (time - beforeTime);
        }
        previousPoint = point;
        previousTime = time;
        // A fix within 5 s of the last lock is searched for near it; any
        // other is a cold start, free to lock anywhere unambiguous.
        final windowed =
            context.hasLock &&
            time > context.lastTelemetryTime &&
            time - context.lastTelemetryTime <= 5.0;
        final last = context.lastProgressMeters;
        final sample = projectSample(axis, point, time, speed, movement, context);
        if (!sample.valid) continue;
        final progress = sample.progressMeters;
        final reason = '${c.label} t=$time';
        expect(progress, inInclusiveRange(0.0, length), reason: reason);
        if (!windowed) continue;
        final delta = progress - last;
        if (delta < -length / 2) {
          // The start/finish wrap: from the end of the axis to its start.
          expect((length - last) + progress, lessThanOrEqualTo(_maximumStep), reason: reason);
          ++wraps;
        } else {
          expect(delta, greaterThanOrEqualTo(-_backwardTolerance), reason: reason);
          expect(delta, lessThanOrEqualTo(_maximumStep), reason: reason);
        }
      }
      wrapsSeen += wraps;
      if (c.clean) {
        // Every gate crossing is one wrap, the first included even where the
        // detector could not count it (firstPassMayBeMissed).
        expect(wraps, c.laps + 1, reason: c.label);
      }
    }
    expect(wrapsSeen, greaterThan(_cases));
  });

  test('a lap is followed to the finish on a jagged reference path (pinned)', () {
    // The counterexample this suite found (FET-216): a 100 m circle driven
    // at 12 m/s and recorded at 25 Hz, without noise. Latitude stored as a
    // float (0.42 m steps at 52°) makes the reference path a staircase,
    // 644.9 m long against 627.7 m of chords between its resampled points.
    // The projection window was centred on progress over spacing, which
    // fell 8 points behind by the end of the lap: each lap broke into four
    // segments and stopped at 628 m, more than the 15 m gate tolerance short
    // of the finish.
    final session = resampleGps(
      math.Random(1),
      circuitSession(radius: 100.0, speeds: const [12.0, 12.0, 12.0]),
      rate: 25.0,
    );
    final laps = deriveSourceLapSession(session);
    final axis = _axisOf(laps)!;
    expect(axis.lengthMeters - axis.cumulative.last, greaterThan(15.0));
    expect(laps.timedLaps, hasLength(3));
    for (final lap in laps.timedLaps) {
      final segments = projectLapTrace(axis, session, lap.startTelemetryTime, lap.endTelemetryTime);
      expect(segments, hasLength(1), reason: 'lap ${lap.number}');
      expect(
        segments.single.samples.last.progressMeters,
        greaterThan(axis.lengthMeters - gateCoverageToleranceMeters),
        reason: 'lap ${lap.number}',
      );
    }
  });
}
