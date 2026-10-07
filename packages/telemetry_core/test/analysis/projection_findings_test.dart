// The figures docs/projection-constants.md quotes for finding 2 and
// finding 3 (FET-215), pinned at their current values on synthetic shapes.
// These tests document current behaviour, limits included: they do not say
// the behaviour is right. Finding 2 is fixed (FET-256): its figures are what
// is left after the fix, the before-the-fix figures are the truth tests'
// (cold_start_branch_test.dart), which fail without it. A change to the
// projection that moves a figure fails here; update the constant below and
// the page together. Each figure the page quotes has one constant.
import 'dart:math' as math;

import 'package:test/test.dart';

import '../support/projection_probe.dart';
import '../support/projection_tracks.dart';
import '../support/synthetic_loop.dart';

// Finding 2, figure-eight: of 915 trials per crossing angle (lines −1, 0
// and +1 m off the centre line, five seeds, GPS back after a 30 m gap whose
// end is every metre from 30 m before to 30 m after the crossing), none is
// on the other diagonal; the fixes refused in all instead, and the worst
// error of a projected fix.
const _figureEightTrials = 915;
final _figureEightRefused = <double, int>{90.0: 60, 30.0: 82, 10.0: 357};
final _figureEightWorstError = <double, double>{90.0: 1.19, 30.0: 1.16, 10.0: 1.26};

// Finding 2, parallel straights driven in opposite directions: a lap 0.5 m
// beyond separation / 1.7 off its line toward the other straight, by
// separation: the fixes projected (of all) and the worst error.
final _parallelProjected = <double, (int, int)>{
  15.0: (137, 186),
  20.0: (144, 193),
  30.0: (156, 205),
};
final _parallelWorstError = <double, double>{15.0: 0.73, 20.0: 0.77, 30.0: 0.75};

// Finding 2, hairpins cut by 40% with 1 m of GPS error, five seeds: the
// worst error by radius, and how far behind the last fix a segment
// re-acquires.
final _hairpinWorstError = <double, double>{3.0: 5.67, 5.0: 6.2};
final _hairpinReacquiredBehind = <double, double>{3.0: 0.59, 5.0: 1.02};

// Finding 3: at 45 m/s with 3.4 s between fixes (153 m, beyond the 150 m
// window) the lap stays one segment, with this worst error.
const _beyondWindowWorstError = 15.4;

// The minimumHeadingCosine row: GPS error of ±0.5 m uncorrelated from fix to
// fix, on the oval at a steady speed (m/s), five seeds: fixes dropped, all
// by the heading rule. (Below 10 m/s a lap of this oval has more than 4,000
// fixes and the fix budget thins it as well, so slower speeds are left out.)
final _whiteNoiseDropped = <double, int>{10.0: 45, 12.0: 2, 15.0: 0, 20.0: 0};

/// Two straights of 300 m, [separation] metres apart centre to centre and
/// driven in opposite directions, joined by hairpins of half that radius.
SyntheticTrack _parallelStraights(double separation) =>
    SyntheticTrack.loop([straight(150), arc(180, separation / 2), straight(150)]);

/// A 600 m-straight oval: no other part of the track within 400 m.
final _oval = SyntheticTrack.loop([straight(300), arc(180, 200), straight(300)]);

const _seeds = [1, 2, 3, 4, 5];

void main() {
  group('finding 2 (fixed by FET-256): a cold start no longer locks on to the wrong branch', () {
    for (final angle in _figureEightRefused.keys) {
      test('figure-eight with a $angle° crossing', () {
        final track = SyntheticTrack.figureEight(crossingDegrees: angle);
        final axis = track.axis();
        final crossing = figureEightCrossing(crossingDegrees: angle);
        var trials = 0, wrong = 0, refused = 0;
        var worst = 0.0;
        for (final line in [-1.0, 0.0, 1.0]) {
          for (final seed in _seeds) {
            for (var at = -30; at <= 30; ++at) {
              final end = crossing + at;
              final lap = driveTrack(
                track,
                lateral: (_) => line,
                noise: 0.3,
                seed: seed,
                dropFix: (meters) => meters > end - 30.0 && meters < end,
              );
              final outcome = measureProjection(axis, track, lap);
              ++trials;
              if (outcome.maximumError > 4.0) ++wrong;
              refused += outcome.fixes - outcome.projected;
              worst = math.max(worst, outcome.maximumError);
            }
          }
        }
        print(
          'Figure-eight $angle° (${track.lengthMeters.toStringAsFixed(0)} m): '
          '$wrong of $trials trials on the other diagonal, $refused fixes refused, '
          'worst error ${worst.toStringAsFixed(2)} m',
        );
        expect(trials, _figureEightTrials);
        expect(wrong, 0);
        expect(refused, _figureEightRefused[angle]);
        expect(worst, closeTo(_figureEightWorstError[angle]!, 0.05));
      });
    }

    test('parallel straights, a lap beyond separation / 1.7 off its line', () {
      for (final separation in _parallelWorstError.keys) {
        final track = _parallelStraights(separation);
        final half = track.lengthMeters / 2;
        final offset = separation / 1.7 + 0.5;
        final lap = driveTrack(
          track,
          noise: 0.3,
          lateral: (meters) {
            final along = meters % half;
            return along > 20.0 && along < 130.0 ? offset : 0.0;
          },
        );
        final outcome = measureProjection(track.axis(), track, lap);
        print(
          'Parallel straights $separation m apart, ${offset.toStringAsFixed(1)} m off '
          '(lap ${track.lengthMeters.toStringAsFixed(0)} m): $outcome',
        );
        expect((outcome.projected, outcome.fixes), _parallelProjected[separation]);
        expect(outcome.maximumError, closeTo(_parallelWorstError[separation]!, 0.05));
      }
    });

    test('hairpins cut by 40% with 1 m of GPS error', () {
      for (final radius in _hairpinWorstError.keys) {
        final track = _parallelStraights(2 * radius);
        final axis = track.axis();
        var worst = 0.0, behind = 0.0;
        for (final seed in _seeds) {
          final lap = driveTrack(
            track,
            noise: 1.0,
            seed: seed,
            lateral: (meters) =>
                0.4 * radius * math.min(1.0, track.curvatureAt(meters).abs() * radius),
          );
          final outcome = measureProjection(axis, track, lap);
          worst = math.max(worst, outcome.maximumError);
          behind = math.max(behind, outcome.largestBackwardStep);
        }
        print(
          'Hairpin of $radius m: worst error ${worst.toStringAsFixed(2)} m, '
          're-acquired up to ${behind.toStringAsFixed(2)} m behind',
        );
        expect(worst, closeTo(_hairpinWorstError[radius]!, 0.05));
        expect(behind, closeTo(_hairpinReacquiredBehind[radius]!, 0.05));
      }
    });
  });

  test('finding 3: a fix just beyond the 150 m forward window is placed at its end', () {
    final lap = driveTrack(_oval, interval: 3.4, speed: (_) => 45.0);
    final outcome = measureProjection(_oval.axis(), _oval, lap);
    print('45 m/s, 3.4 s between fixes: $outcome');
    expect(outcome.segments, 1);
    expect(outcome.projected, outcome.fixes);
    expect(outcome.maximumError, closeTo(_beyondWindowWorstError, 0.05));
  });

  test('uncorrelated GPS error trips the heading rule at low speed', () {
    final axis = _oval.axis();
    for (final speed in _whiteNoiseDropped.keys) {
      var dropped = 0;
      final refusals = RefusalTally();
      for (final seed in _seeds) {
        final lap = driveTrack(_oval, speed: (_) => speed, noise: 0.5, noiseSeconds: 0, seed: seed);
        final outcome = measureProjection(axis, _oval, lap);
        dropped += outcome.fixes - outcome.projected;
        refusals.replay(axis, lap.session, 0.0, lap.endTime);
      }
      print(
        '±0.5 m uncorrelated at ${speed.toStringAsFixed(0)} m/s: $dropped fixes dropped '
        '($refusals)',
      );
      expect(dropped, _whiteNoiseDropped[speed]);
      expect(refusals.disagreements, 0);
      expect(refusals.counts[Refusal.lockedHeading], dropped);
    }
  });
}
