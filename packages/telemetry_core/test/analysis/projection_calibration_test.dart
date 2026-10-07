// Calibration of the projection constants of track_progress.dart on
// synthetic shapes that stress them (FET-215): a self-crossing figure-eight,
// parallel straights driven in opposite directions closer than the 20 m
// proximity, and tight hairpins. Each lap is driven with a known distance at
// every fix, so the projection is checked against the true path; the margin
// tests find how far each constant is from failing on these shapes. The
// figures are in docs/projection-constants.md.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/projection_probe.dart';
import '../support/projection_tracks.dart';
import '../support/synthetic_loop.dart';

/// GPS error of the driven laps: 0.3 m (standard deviation) in each
/// direction, correlated over a second as a receiver's is.
const _noise = 0.3;

/// A projected lap may differ from the true distance by this much: the axis
/// is 2 m chords and the fixes carry [_noise], up to about 1 m.
const _error = 2.0;

const _seeds = [1, 2, 3, 4, 5];

/// A line that wanders [amplitude] metres either side of the centre line.
double Function(double) _wander(double amplitude) =>
    (meters) => amplitude * math.sin(meters / 40.0);

/// Two straights of 300 m, [separation] metres apart centre to centre and
/// driven in opposite directions, joined by hairpins of half that radius.
SyntheticTrack _parallelStraights(double separation) =>
    SyntheticTrack.loop([straight(150), arc(180, separation / 2), straight(150)]);

/// [meters] lies on one of [_parallelStraights]' straights, 20 m clear of
/// the hairpins.
bool Function(double) _onStraights(SyntheticTrack track) => (meters) {
  final half = track.lengthMeters / 2;
  final along = meters % half;
  return along > 20.0 && along < 130.0;
};

/// A 600 m-straight oval: no other part of the track within 400 m.
final _oval = SyntheticTrack.loop([straight(300), arc(180, 200), straight(300)]);

/// Whether a first fix at [point], moving east, locks on to [axis].
bool _coldStart(ProgressAxis axis, MetricPoint point) =>
    projectSample(axis, point, 0.0, 40.0, (1.0, 0.0), ProjectionContext()).valid;

void _expectFollows(ProgressAxis axis, SyntheticTrack track, DrivenTrackLap lap) {
  final outcome = measureProjection(axis, track, lap);
  expect(outcome.tracks(_error), isTrue, reason: '$outcome');
  // Monotonic over the whole lap: one segment that never falls, from the
  // gate to the gate.
  expect(outcome.largestBackwardStep, 0.0);
  expect(outcome.firstProgress.abs(), lessThan(_error));
  expect(outcome.lastProgress, closeTo(axis.lengthMeters, 6.0));
}

void main() {
  group('figure-eight (self-crossing)', () {
    for (final angle in [90.0, 30.0, 10.0]) {
      test('a lap through a $angle° crossing follows the true path', () {
        final track = SyntheticTrack.figureEight(crossingDegrees: angle);
        final axis = track.axis();
        expect(axis.valid, isTrue);
        final lap = driveTrack(track, lateral: _wander(2.0), noise: _noise);
        _expectFollows(axis, track, lap);
        final probe = ProjectionProbe()..measure(axis, lap.times, lap.localPoints);
        print('Figure-eight $angle°: $probe');
        expect(probe.largestWindowedRatio, lessThan(0.7));
      });

      test('after a GPS gap 40 m before a $angle° crossing it finds the right branch', () {
        final track = SyntheticTrack.figureEight(crossingDegrees: angle);
        final axis = track.axis();
        final crossing = figureEightCrossing(crossingDegrees: angle);
        for (final seed in _seeds) {
          for (final side in [-1.0, 1.0]) {
            final lap = driveTrack(
              track,
              lateral: (_) => side * 2.0,
              noise: _noise,
              seed: seed,
              dropFix: (meters) => meters > crossing - 70.0 && meters < crossing - 40.0,
            );
            final outcome = measureProjection(axis, track, lap);
            expect(outcome.segments, 2, reason: '$outcome');
            expect(outcome.projected, outcome.fixes, reason: '$outcome');
            expect(outcome.maximumError, lessThan(_error), reason: '$outcome');
          }
        }
      });
    }
  });

  group('parallel straights in opposite directions', () {
    for (final separation in [40.0, 20.0, 15.0, 10.0]) {
      test('a lap with the straights $separation m apart follows the true path', () {
        final track = _parallelStraights(separation);
        final axis = track.axis();
        final lap = driveTrack(track, lateral: _wander(separation / 8), noise: _noise);
        _expectFollows(axis, track, lap);
        print(
          'Parallel straights $separation m apart: '
          '${ProjectionProbe()..measure(axis, lap.times, lap.localPoints)}',
        );
      });
    }

    test('locked, down to 2 m apart it never jumps across', () {
      for (final separation in [6.0, 4.0, 3.0, 2.0]) {
        final track = _parallelStraights(separation);
        final axis = track.axis();
        var dropped = 0, fixes = 0;
        for (final seed in _seeds) {
          final lap = driveTrack(
            track,
            lateral: _wander(separation / 8),
            noise: _noise,
            seed: seed,
          );
          final outcome = measureProjection(axis, track, lap);
          expect(outcome.maximumError, lessThan(_error), reason: '$separation m: $outcome');
          dropped += outcome.fixes - outcome.projected;
          fixes += outcome.fixes;
        }
        print('Parallel straights $separation m apart: $dropped of $fixes fixes dropped');
      }
    });

    test('a lap 7 m off its line toward the other straight stays on its own', () {
      for (final separation in [15.0, 20.0, 30.0]) {
        final track = _parallelStraights(separation);
        final onStraights = _onStraights(track);
        final lap = driveTrack(
          track,
          lateral: (meters) => onStraights(meters) ? 7.0 : 0.0,
          noise: _noise,
        );
        _expectFollows(track.axis(), track, lap);
      }
    });

    test('a cold start on a straight is ambiguous from 0.7 / 1.7 of the separation', () {
      // Best distance d to its own straight, runner-up separation − d to the
      // other: rejected when d > 0.7 (separation − d).
      for (final separation in [15.0, 20.0, 30.0]) {
        final track = _parallelStraights(separation);
        final axis = track.axis();
        final onset = 0.7 * separation / 1.7;
        bool coldStart(double offset) => _coldStart(axis, MetricPoint(75.0, offset));
        expect(coldStart(onset - 0.25), isTrue, reason: '$separation m, ${onset - 0.25} m off');
        expect(coldStart(onset + 0.25), isFalse, reason: '$separation m, ${onset + 0.25} m off');
      }
    });
  });

  group('tight hairpins', () {
    /// A lap [cut] metres inside the centre line through each hairpin of
    /// [track], blended in and out with the curvature.
    DrivenTrackLap cutting(
      SyntheticTrack track,
      double radius,
      double cut, {
      double noise = _noise,
      int seed = 1,
    }) => driveTrack(
      track,
      lateral: (meters) => cut * math.min(1.0, track.curvatureAt(meters).abs() * radius),
      noise: noise,
      seed: seed,
    );

    for (final radius in [7.5, 10.0, 15.0]) {
      test('a lap cutting the apex of a $radius m hairpin follows the true path', () {
        final track = _parallelStraights(2 * radius);
        final axis = track.axis();
        final cut = math.min(0.4 * radius, 3.0);
        for (final seed in _seeds) {
          final lap = cutting(track, radius, cut, seed: seed);
          _expectFollows(axis, track, lap);
          if (seed == 1) {
            final probe = ProjectionProbe()..measure(axis, lap.times, lap.localPoints);
            print('Hairpin of $radius m, apex cut ${cut.toStringAsFixed(1)} m: $probe');
            expect(probe.lowestHeadingCosine, greaterThan(0.5));
          }
        }
      });
    }

    test('below 7.5 m radius it may drop fixes at the apex but never jumps', () {
      for (final radius in [3.0, 5.0]) {
        final track = _parallelStraights(2 * radius);
        final axis = track.axis();
        var dropped = 0, fixes = 0;
        for (final seed in _seeds) {
          final outcome = measureProjection(
            axis,
            track,
            cutting(track, radius, 0.4 * radius, seed: seed),
          );
          expect(outcome.maximumError, lessThan(_error * 1.5), reason: '$outcome');
          dropped += outcome.fixes - outcome.projected;
          fixes += outcome.fixes;
        }
        print(
          'Hairpin of $radius m, apex cut ${(0.4 * radius).toStringAsFixed(1)} m: $dropped of $fixes fixes dropped',
        );
      }
    });

    test('without GPS error an apex cut of 4.5 m holds; 6 m holds in a 15 m hairpin and '
        'drops a fix in a 10 m one but never jumps', () {
      for (final radius in [7.5, 10.0, 15.0]) {
        final track = _parallelStraights(2 * radius);
        final axis = track.axis();
        _expectFollows(axis, track, cutting(track, radius, 4.5, noise: 0.0));
        if (radius > 7.5) {
          final outcome = measureProjection(axis, track, cutting(track, radius, 6.0, noise: 0.0));
          print('Hairpin of $radius m, apex cut 6 m: $outcome');
          // Before FET-257 both dropped fixes (18 and 2): the runner-up was
          // the same leg 10 m on.
          expect(outcome.tracks(_error), radius == 15.0, reason: '$outcome');
          expect(outcome.maximumError, lessThan(_error), reason: '$outcome');
        }
      }
    });
  });

  group('margins of the constants', () {
    final axis = _oval.axis();

    test('locked, a lap holds up to the 20 m proximity off the line', () {
      // Before FET-257 the 0.7 ratio, comparing the line with itself 10 m
      // on, dropped about a quarter of the fixes from 8.5 m off (finding 1).
      for (final side in [-1.0, 1.0]) {
        for (final offset in [7.0, 8.5, 12.0, 19.5]) {
          _expectFollows(axis, _oval, driveTrack(_oval, lateral: (_) => side * offset));
        }
        final outcome = measureProjection(
          axis,
          _oval,
          driveTrack(_oval, lateral: (_) => side * 20.5),
        );
        print('Oval, 20.5 m off the line: $outcome');
        expect(outcome.projected, 0, reason: '$outcome');
      }
    });

    test('a cold start accepts a fix up to the 20 m proximity', () {
      bool coldStart(double offset) => _coldStart(axis, MetricPoint(150.0, offset));
      expect(coldStart(19.9), isTrue);
      expect(coldStart(-19.9), isTrue);
      expect(coldStart(20.1), isFalse);
      expect(coldStart(-20.1), isFalse);
    });

    test('the forward window keeps the lock at 45 m/s with up to 3.3 s between fixes', () {
      // 3.3 s × 45 m/s = 148.5 m: inside the 150 m cap.
      for (final interval in [0.05, 0.1, 1.0, 2.0, 3.0, 3.3]) {
        final lap = driveTrack(_oval, interval: interval, speed: (_) => 45.0);
        final outcome = measureProjection(axis, _oval, lap);
        expect(outcome.tracks(_error), isTrue, reason: '$interval s: $outcome');
      }
    });

    test('a lock older than 5 s is not continued: the next fix is a cold start', () {
      // Locked 100 m along the first straight; the next fix is 200 m on,
      // beyond the 150 m forward window.
      ProjectionContext locked() {
        final context = ProjectionContext();
        expect(
          projectSample(axis, const MetricPoint(100.0, 0.0), 0.0, 40.0, (1.0, 0.0), context).valid,
          isTrue,
        );
        return context;
      }

      const ahead = MetricPoint(300.0, 0.0);
      expect(projectSample(axis, ahead, 4.9, 40.0, (1.0, 0.0), locked()).valid, isFalse);
      final cold = projectSample(axis, ahead, 5.1, 40.0, (1.0, 0.0), locked());
      expect(cold.valid, isTrue);
      expect(cold.progressMeters, closeTo(300.0 * axis.lengthMeters / _oval.lengthMeters, 1.0));
    });

    test('a fix without a heading may fall back 3 m and no more', () {
      for (final (back, accepted) in [(2.9, true), (3.1, false)]) {
        final context = ProjectionContext();
        projectSample(axis, const MetricPoint(100.0, 0.0), 0.0, 40.0, (1.0, 0.0), context);
        const still = (0.0, 0.0);
        final sample = projectSample(
          axis,
          MetricPoint(100.0 - back, 0.0),
          0.1,
          40.0,
          still,
          context,
        );
        expect(sample.valid, accepted, reason: '$back m back');
      }
      // With a heading, any step back on a straight moves against the axis:
      // the heading rule rejects it before the tolerance is reached.
      final context = ProjectionContext();
      projectSample(axis, const MetricPoint(100.0, 0.0), 0.0, 40.0, (1.0, 0.0), context);
      expect(
        projectSample(axis, const MetricPoint(99.0, 0.0), 0.1, 10.0, (-1.0, 0.0), context).valid,
        isFalse,
      );
    });
  });
}
