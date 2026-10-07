// Truth tests for FET-256: a cold start in the middle of a lap (after a GPS
// gap, or after a fix the projection refused) must never lock on to another
// branch of the track, and one wrong fix must never shift the rest of the lap
// by whole laps. Each synthetic lap is driven with a known distance at every
// fix; the shapes are those of the calibration (FET-215,
// docs/projection-constants.md, finding 2): a figure-eight whose GPS comes
// back next to the crossing, parallel straights driven in opposite directions
// with a lap off its line toward the other straight, and hairpins cut with
// 1 m of GPS error. A fix may be refused (a gap), never misplaced.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/projection_tracks.dart';
import '../support/synthetic_loop.dart';

/// A projected fix may be this far from its true distance: 2 m axis chords
/// plus GPS error. A wrong branch is tens to thousands of metres out.
const _error = 5.0;

const _seeds = [1, 2, 3, 4, 5];

/// Whether no fix is misplaced and no segment is shifted: every projected
/// fix within [_error] of its true distance, progress never falling by more
/// than that from one segment to the next, and the lap still reaching the
/// finish.
bool _onTheRightBranch(ProgressAxis axis, ProjectionOutcome outcome) =>
    outcome.maximumError <= _error &&
    outcome.largestBackwardStep <= _error &&
    (outcome.lastProgress - axis.lengthMeters).abs() <= 10.0;

void main() {
  group('figure-eight: GPS back next to the crossing', () {
    for (final angle in [90.0, 30.0, 10.0]) {
      test('a $angle° crossing never locks on to the other diagonal', () {
        final track = SyntheticTrack.figureEight(crossingDegrees: angle);
        final axis = track.axis();
        final crossing = figureEightCrossing(crossingDegrees: angle);
        var trials = 0, refusedFixes = 0;
        final wrong = <String>[];
        // A 30 m gap whose end is anywhere from 30 m before to 30 m after
        // the crossing, on lines 1 m either side of the centre line.
        for (var end = -30.0; end <= 30.0; end += 1.0) {
          for (final side in [-1.0, 0.0, 1.0]) {
            for (final seed in _seeds) {
              final gapEnd = crossing + end;
              final lap = driveTrack(
                track,
                lateral: (_) => side,
                noise: 0.3,
                seed: seed,
                dropFix: (meters) => meters > gapEnd - 30.0 && meters < gapEnd,
              );
              final outcome = measureProjection(axis, track, lap);
              if (!_onTheRightBranch(axis, outcome)) {
                wrong.add('gap ends $end m from the crossing, $side m off, seed $seed: $outcome');
              }
              ++trials;
              refusedFixes += outcome.fixes - outcome.projected;
            }
          }
        }
        print('Figure-eight $angle°: $trials trials, $refusedFixes fixes refused in all');
        expect(wrong, isEmpty, reason: '${wrong.length} of $trials trials on the wrong branch');
      });
    }
  });

  group('parallel straights in opposite directions', () {
    for (final separation in [15.0, 20.0, 30.0]) {
      test('a lap off its line toward the other straight, $separation m apart, '
          'never jumps across', () {
        final track = SyntheticTrack.loop([straight(150), arc(180, separation / 2), straight(150)]);
        final axis = track.axis();
        final wrong = <String>[];
        // Beyond separation / 1.7 toward the other straight, which is then
        // nearer than its own (and within 20 m of the fix).
        for (final share in [0.55, 0.6, 0.65]) {
          final offset = share * separation;
          for (final seed in _seeds) {
            final lap = driveTrack(
              track,
              lateral: (meters) {
                final along = meters % (track.lengthMeters / 2);
                return along > 20.0 && along < 130.0 ? offset : 0.0;
              },
              noise: 0.3,
              seed: seed,
            );
            final outcome = measureProjection(axis, track, lap);
            if (!_onTheRightBranch(axis, outcome)) wrong.add('$offset m off, seed $seed: $outcome');
          }
        }
        expect(wrong, isEmpty, reason: '${wrong.length} of 15 laps on the wrong branch');
      });
    }
  });

  group('hairpins cut with 1 m of GPS error', () {
    // With 1 m of GPS error a fix in a hairpin of 3 or 5 m radius can sit
    // 4 m from where the car is, which moves the nearest point of the
    // centre line by as much along the lap. So here a fix is misplaced when
    // it lands further from its true distance than 2 m (the axis chords)
    // plus its own distance from the car's place on the centre line; one
    // locked on to the other leg is out by the length of the hairpin.
    for (final radius in [3.0, 5.0]) {
      test('a $radius m hairpin cut by 40% never re-locks on the other leg', () {
        final track = SyntheticTrack.loop([straight(150), arc(180, radius), straight(150)]);
        final axis = track.axis();
        final scale = axis.lengthMeters / track.lengthMeters;
        final wrong = <String>[];
        final seeds = [for (var seed = 1; seed <= 20; ++seed) seed];
        for (final seed in seeds) {
          final lap = driveTrack(
            track,
            lateral: (meters) =>
                0.4 * radius * math.min(1.0, track.curvatureAt(meters).abs() * radius),
            noise: 1.0,
            seed: seed,
          );
          final points = lap.localPoints;
          final index = {for (var i = 0; i < lap.times.length; ++i) lap.times[i]: i};
          for (final segment in projectLapTrace(axis, lap.session, 0.0, lap.endTime)) {
            for (final sample in segment.samples) {
              final i = index[sample.telemetryTime]!;
              final ((x, y), _) = track.at(lap.truth[i]);
              final offTrue = math.sqrt(
                math.pow(points[i].eastMeters - x, 2) + math.pow(points[i].northMeters - y, 2),
              );
              final error = (sample.progressMeters - lap.truth[i] * scale).abs();
              if (error > 2.0 + offTrue) {
                wrong.add(
                  'seed $seed, ${lap.truth[i].toStringAsFixed(1)} m: '
                  '${error.toStringAsFixed(1)} m out, the fix ${offTrue.toStringAsFixed(1)} m '
                  'from the car',
                );
              }
            }
          }
          final outcome = measureProjection(axis, track, lap);
          expect(
            outcome.largestBackwardStep,
            lessThanOrEqualTo(_error),
            reason: 'seed $seed: $outcome',
          );
          expect(
            outcome.lastProgress,
            closeTo(axis.lengthMeters, 10.0),
            reason: 'seed $seed: $outcome',
          );
        }
        expect(wrong, isEmpty, reason: '${wrong.length} fixes misplaced');
      });
    }
  });
}
