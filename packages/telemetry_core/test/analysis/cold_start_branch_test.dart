// Truth tests for FET-256: a cold start in the middle of a lap (after a GPS
// gap, or after a fix the projection refused) must never lock on to another
// branch of the track, and one wrong fix must never shift the rest of the lap
// by whole laps. Each synthetic lap is driven with a known distance at every
// fix; the shapes are those of the calibration (FET-215,
// docs/projection-constants.md, finding 2): a figure-eight whose GPS comes
// back next to the crossing, parallel straights driven in opposite directions
// with a lap off its line toward the other straight, and hairpins cut with
// 1 m of GPS error. A fix may be refused (a gap), never misplaced.
//
// The review of the first fix added the later groups: gaps longer than a
// second on short loops, raw GPS gaps on parallel straights, a gap at the
// lap's start, and guards that real cars keep their fixes (fast cars and long
// tunnels) and that a standing car keeps most of its fixes.
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
    // The 3 m hairpin fails without the other-leg check of the cold start;
    // the 5 m one already passed before FET-256 and is a guard. With 1 m of
    // GPS error a fix in a hairpin of 3 or 5 m radius can sit
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

  group('short loops: gaps longer than a second', () {
    // On a short figure-eight a wrong cold start within reach of the time
    // since the last fix was accepted, and the right fixes after it were
    // moved on by a lap seconds later (the review of FET-256): 31 of 279
    // trials at 10° with a 200 m gap, 10 at 30° with a 400 m gap.
    for (final angle in [90.0, 30.0, 10.0]) {
      for (final gap in [100.0, 200.0, 400.0]) {
        test('a $angle° crossing, GPS back after $gap m', () {
          final track = SyntheticTrack.figureEight(crossingDegrees: angle);
          final axis = track.axis();
          final crossing = figureEightCrossing(crossingDegrees: angle);
          var trials = 0;
          final wrong = <String>[];
          for (var end = -30.0; end <= 30.0; end += 2.0) {
            for (final side in [-1.0, 0.0, 1.0]) {
              for (final seed in [1, 2, 3]) {
                final gapEnd = crossing + end;
                final lap = driveTrack(
                  track,
                  lateral: (_) => side,
                  noise: 0.3,
                  seed: seed,
                  dropFix: (meters) => meters > gapEnd - gap && meters < gapEnd,
                );
                final outcome = measureProjection(axis, track, lap);
                ++trials;
                if (!_onTheRightBranch(axis, outcome)) {
                  wrong.add('gap ends $end m from the crossing, $side m off, seed $seed: $outcome');
                }
              }
            }
          }
          expect(trials, 279);
          expect(wrong, isEmpty, reason: '${wrong.length} of $trials trials on the wrong branch');
        });
      }
    }
  });

  group('parallel straights with a raw GPS gap', () {
    // A raw gap of 5–40 m on the straight (three fixes at 25 Hz are one)
    // used to forget the direction of travel, so the fix after it could
    // lock on to the other straight: 92, 80 and 74 of 594 trials at 15, 20
    // and 30 m apart (the review of FET-256).
    for (final separation in [15.0, 20.0, 30.0]) {
      test('$separation m apart', () {
        final track = SyntheticTrack.loop([straight(150), arc(180, separation / 2), straight(150)]);
        final axis = track.axis();
        var trials = 0;
        final wrong = <String>[];
        for (final share in [0.55, 0.6, 0.65]) {
          final offset = share * separation;
          for (var gapEnd = 25.0; gapEnd <= 130.0; gapEnd += 5.0) {
            for (final gap in [5.0, 20.0, 40.0]) {
              for (final seed in [1, 2, 3]) {
                final lap = driveTrack(
                  track,
                  lateral: (meters) {
                    final along = meters % (track.lengthMeters / 2);
                    return along > 20.0 && along < 130.0 ? offset : 0.0;
                  },
                  noise: 0.3,
                  seed: seed,
                  dropFix: (meters) => meters > gapEnd - gap && meters < gapEnd,
                );
                final outcome = measureProjection(axis, track, lap);
                ++trials;
                if (!_onTheRightBranch(axis, outcome)) {
                  wrong.add('$offset m off, gap $gap m to $gapEnd m, seed $seed: $outcome');
                }
              }
            }
          }
        }
        expect(trials, 594);
        expect(wrong, isEmpty, reason: '${wrong.length} of $trials trials on the wrong branch');
      });
    }
  });

  group('parallel straights with a gap at the lap start', () {
    // The lap's first fix had no direction of travel and no bound on where
    // it could be: before FET-256 89, 85 and 78 of 117 laps were moved on by
    // whole laps; after its first fix 18 of 117 still had fixes on the other
    // straight, up to 140 m out.
    for (final separation in [15.0, 20.0, 30.0]) {
      test('$separation m apart', () {
        final track = SyntheticTrack.loop([straight(150), arc(180, separation / 2), straight(150)]);
        final axis = track.axis();
        var trials = 0;
        final wrong = <String>[];
        for (final share in [0.55, 0.6, 0.65]) {
          final offset = share * separation;
          for (var gapEnd = 10.0; gapEnd <= 130.0; gapEnd += 10.0) {
            for (final seed in [1, 2, 3]) {
              final lap = driveTrack(
                track,
                lateral: (meters) {
                  final along = meters % (track.lengthMeters / 2);
                  return along > 5.0 && along < 130.0 ? offset : 0.0;
                },
                noise: 0.3,
                seed: seed,
                dropFix: (meters) => meters > 0.5 && meters < gapEnd,
              );
              final outcome = measureProjection(axis, track, lap);
              ++trials;
              if (!_onTheRightBranch(axis, outcome)) {
                wrong.add('$offset m off, gap to $gapEnd m, seed $seed: $outcome');
              }
            }
          }
        }
        expect(trials, 117);
        expect(wrong, isEmpty, reason: '${wrong.length} of $trials laps on the wrong branch');
      });
    }
  });

  group('real cars keep their fixes', () {
    // Guards, which pass before and after: a lap with no other part of the
    // track nearby must keep every fix after a gap however fast the car or
    // long the gap.
    final track = SyntheticTrack.loop([
      straight(600),
      arc(90, 60),
      straight(200),
      arc(90, 25),
      straight(300),
    ]);
    final axis = track.axis();
    for (final (speed, gaps) in [
      (95.0, [50.0, 200.0, 500.0, 1000.0]),
      (40.0, [10.0, 30.0, 100.0, 300.0, 900.0]),
    ]) {
      test('at $speed m/s with gaps of ${gaps.join(', ')} m', () {
        for (final gap in gaps) {
          final lap = driveTrack(
            track,
            noise: 0.3,
            speed: (_) => speed,
            dropFix: (meters) => meters > 100.0 && meters < 100.0 + gap,
          );
          final outcome = measureProjection(axis, track, lap);
          expect(outcome.projected, outcome.fixes, reason: 'gap $gap m: $outcome');
          expect(_onTheRightBranch(axis, outcome), isTrue, reason: 'gap $gap m: $outcome');
        }
      });
    }

    test('a car standing for a minute keeps most of its fixes', () {
      // GPS jitter while standing trips the heading rule while locked (as in
      // Overlays); the cold start after it takes no heading from less than
      // 0.2 m. 6,215 of 7,115 fixes are projected before FET-256, 5,880 with
      // the first fix, which took the jitter as a heading.
      var projected = 0, fixes = 0;
      for (var seed = 1; seed <= 5; ++seed) {
        final lap = driveTrack(
          track,
          noise: 0.5,
          seed: seed,
          schedule: (i) {
            final t = i * 0.1;
            if (t < 500 / 30) return t * 30;
            if (t < 500 / 30 + 60) return 500.0;
            final meters = 500 + (t - 500 / 30 - 60) * 30;
            return meters > track.lengthMeters ? null : meters;
          },
        );
        final outcome = measureProjection(axis, track, lap);
        expect(_onTheRightBranch(axis, outcome), isTrue, reason: 'seed $seed: $outcome');
        projected += outcome.projected;
        fixes += outcome.fixes;
      }
      print('Standing a minute: $projected of $fixes fixes projected');
      expect(fixes, 7115);
      expect(projected, greaterThanOrEqualTo(6100));
    });
  });

  test("the lap's first fix has the direction of travel of the fix before the lap", () {
    // The last fix before the lap's start gives its first fix a movement:
    // a first fix 4.5 m behind it moved backwards and is refused, as any
    // later fix would be. Before, the first fix had no heading.
    final track = SyntheticTrack.loop([straight(300), arc(180, 200), straight(300)]);
    final axis = track.axis();
    final lap = driveTrack(
      track,
      schedule: (i) => switch (i) {
        0 => track.lengthMeters - 4.5, // before the lap
        1 => track.lengthMeters - 9.0, // its first fix, 4.5 m back
        _ when i < 40 => (i - 2) * 4.5,
        _ => null,
      },
    );
    final trace = projectLapTrace(axis, lap.session, 0.05, lap.endTime);
    expect(trace, isNotEmpty);
    expect(trace.first.samples.first.telemetryTime, closeTo(0.2, 1e-9));
  });
}
