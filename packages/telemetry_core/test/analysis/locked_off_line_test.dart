// Truth tests for FET-257 (docs/projection-constants.md, findings 1 and 3).
//
// Finding 1: while locked, the runner-up of a fix only had to be 10 m along
// the axis, and on a straight that is the same line 10 m further on: a fix
// about 8 m off it was as near to that as to its own match, so the 0.7
// ambiguity ratio refused it, long before the 20 m proximity. Such a fix is
// now kept when no other part of the whole axis is nearly as near and it
// does not lie well inside a bend; true ambiguity (a hairpin's legs, the
// other straight of a pair, a crossing) is still refused. The review of the
// first version (which looked only in the search window) adds 1–2 Hz laps,
// where another branch can lie beyond the window.
//
// Finding 3: a fix whose nearest point lay beyond the forward end of the
// search window was placed at the window's end. It is refused now.
//
// Each synthetic lap is driven with a known distance at every fix. A fix may
// be refused (a gap), never misplaced.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/projection_tracks.dart';
import '../support/synthetic_loop.dart';

/// A projected fix may be this far from its true distance: 2 m axis chords
/// plus GPS error.
const _error = 2.0;

const _seeds = [1, 2, 3, 4, 5];

/// A 600 m-straight oval: no other part of the track within 400 m.
final _oval = SyntheticTrack.loop([straight(300), arc(180, 200), straight(300)]);

/// Two straights of 300 m, [separation] metres apart centre to centre and
/// driven in opposite directions (east along y = 0, west along
/// y = [separation]), joined by hairpins of half that radius centred on
/// x = ±150 m.
SyntheticTrack _parallelStraights(double separation) =>
    SyntheticTrack.loop([straight(150), arc(180, separation / 2), straight(150)]);

/// A lock at [from] (moving east) and then the fix [to] [seconds] later at
/// [speed]: whether [to] is projected, and where.
ProjectedSample _lockedThen(
  ProgressAxis axis,
  MetricPoint from,
  MetricPoint to, {
  double seconds = 1.0,
  double speed = 40.0,
}) {
  final context = ProjectionContext();
  expect(projectSample(axis, from, 0.0, speed, (1.0, 0.0), context).valid, isTrue);
  final movement = (to.eastMeters - from.eastMeters, to.northMeters - from.northMeters);
  return projectSample(axis, to, seconds, speed, movement, context);
}

/// The largest distance of a projected fix of [lap] from where the car
/// truly is, either way round the loop (a fix at the gate may be read at the
/// end of the lap or at its start).
double _worstError(ProgressAxis axis, SyntheticTrack track, DrivenTrackLap lap) {
  final scale = axis.lengthMeters / track.lengthMeters;
  final truthAt = {for (var i = 0; i < lap.times.length; ++i) lap.times[i]: lap.truth[i] * scale};
  var worst = 0.0;
  for (final segment in projectLapTrace(axis, lap.session, 0.0, lap.endTime)) {
    for (final sample in segment.samples) {
      final error = (sample.progressMeters - truthAt[sample.telemetryTime]!).abs();
      worst = math.max(worst, math.min(error, (axis.lengthMeters - error).abs()));
    }
  }
  return worst;
}

void main() {
  group('finding 1: a lap off the reference line keeps its fixes while locked', () {
    final axis = _oval.axis();

    for (final offset in [8.5, 10.0, 15.0]) {
      test('a lap $offset m off the line on the oval stays in one segment', () {
        for (final side in [-1.0, 1.0]) {
          for (final seed in _seeds) {
            final lap = driveTrack(_oval, lateral: (_) => side * offset, noise: 0.3, seed: seed);
            final outcome = measureProjection(axis, _oval, lap);
            expect(
              outcome.tracks(_error),
              isTrue,
              reason: '${side * offset} m, seed $seed: $outcome',
            );
            expect(outcome.largestBackwardStep, 0.0, reason: '$outcome');
          }
        }
      });
    }

    test('a lap beyond separation / 1.7 off its line toward the other straight is refused '
        'there, never placed on either straight', () {
      // Nearer the other straight than 0.7 of the way, a fix could be on
      // either: the other straight lies beyond the window, but only the
      // whole axis can show that it is not the car's (FET-257 review).
      for (final separation in [15.0, 20.0, 30.0]) {
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
        expect(outcome.maximumError, lessThan(_error), reason: '$separation m apart: $outcome');
        expect(outcome.projected, lessThan(outcome.fixes), reason: '$separation m apart: $outcome');
      }
    });

    test('a lap through a figure-eight\'s crossing 8.5 m off its line is never misplaced', () {
      // The 10° figure-eight's lobes have a radius of 13 m: 8.5 m inside
      // one, the GPS error moves the nearest point of the axis about three
      // times as far, up to 3.9 m (as before FET-257). The other branch is
      // hundreds of metres out.
      for (final angle in [90.0, 30.0, 10.0]) {
        final track = SyntheticTrack.figureEight(crossingDegrees: angle);
        for (final side in [-1.0, 1.0]) {
          for (final seed in _seeds) {
            final lap = driveTrack(track, lateral: (_) => side * 8.5, noise: 0.3, seed: seed);
            final outcome = measureProjection(track.axis(), track, lap);
            expect(outcome.maximumError, lessThan(5.0), reason: '$angle°: $outcome');
            expect(outcome.largestBackwardStep, 0.0, reason: '$angle°: $outcome');
          }
        }
      }
    });

    test('a loop shorter than the search window keeps a lap 5 m off its line', () {
      // 103 m round: the window covers the whole loop and wraps.
      final track = SyntheticTrack.loop([straight(20), arc(180, 10), straight(20)]);
      final axis = track.axis();
      for (final side in [-1.0, 1.0]) {
        final lap = driveTrack(track, lateral: (_) => side * 5.0, speed: (_) => 10.0);
        final outcome = measureProjection(axis, track, lap);
        expect(outcome.tracks(_error), isTrue, reason: '${side * 5.0} m: $outcome');
      }
    });
  });

  group('finding 1: true ambiguity while locked is still refused', () {
    for (final radius in [3.0, 7.5, 15.0]) {
      test('a fix midway between the legs of a $radius m hairpin', () {
        final track = _parallelStraights(2 * radius);
        final axis = track.axis();
        // Locked on the eastbound leg 10 m before the hairpin; the next fix
        // is 2 m before the hairpin's centre, as near the westbound leg as
        // the eastbound one, and the window reaches both.
        final midway = _lockedThen(axis, const MetricPoint(140.0, 0.0), MetricPoint(148.0, radius));
        expect(midway.valid, isFalse);
        // Nearer the eastbound leg it is placed there.
        final near = _lockedThen(
          axis,
          const MetricPoint(140.0, 0.0),
          MetricPoint(148.0, radius * 0.4),
        );
        expect(near.valid, isTrue);
        expect(near.progressMeters, closeTo(148.0 * axis.lengthMeters / track.lengthMeters, 1.0));
      });
    }

    for (final radius in [3.0, 7.5, 15.0]) {
      test('a fix at the centre of a $radius m hairpin, as near every part of it', () {
        final track = _parallelStraights(2 * radius);
        final axis = track.axis();
        final centre = _lockedThen(axis, const MetricPoint(140.0, 0.0), MetricPoint(150.0, radius));
        expect(centre.valid, isFalse);
      });
    }

    for (final radius in [10.0, 15.0, 19.0]) {
      test('a fix at the centre of a 90° corner of $radius m, as near all of it', () {
        // A rounded rectangle: the first corner turns north at x = 150 m,
        // its centre at (150, radius).
        final track = SyntheticTrack.loop([
          straight(150),
          arc(90, radius),
          straight(100),
          arc(90, radius),
          straight(150),
        ]);
        final axis = track.axis();
        final centre = _lockedThen(axis, const MetricPoint(130.0, 0.0), MetricPoint(150.0, radius));
        expect(centre.valid, isFalse);
      });
    }

    test('a fix midway between two straights 15 m apart, both in the window', () {
      final track = _parallelStraights(15.0);
      final axis = track.axis();
      // 1.0 s at 40 m/s: a 64 m window from x = 120 m reaches round the
      // hairpin onto the westbound straight.
      final midway = _lockedThen(
        axis,
        const MetricPoint(120.0, 0.0),
        const MetricPoint(145.0, 7.5),
      );
      expect(midway.valid, isFalse);
    });
  });

  group('review: at 1–2 Hz an off-line fix is kept only when no other branch is near', () {
    for (final radius in [5.0, 6.0, 7.5, 8.0]) {
      test('a fix on the other leg of a $radius m hairpin, beyond the window, is not placed on '
          'this leg', () {
        // Locked 15 m before the hairpin, eastbound; a second later (1 Hz)
        // the car is on the westbound leg, 10 m past the hairpin, exactly
        // on the line. The window, sized by the 5–17 m the GPS moved, ends
        // before the hairpin; the eastbound leg 2 × radius away was the
        // nearest point in it, and was taken (FET-257 review).
        final track = _parallelStraights(2 * radius);
        final axis = track.axis();
        final scale = axis.lengthMeters / track.lengthMeters;
        final to = MetricPoint(140.0, 2 * radius);
        final moved = MetricPoint(5.0, 2 * radius);
        final speed = math.sqrt(
          moved.eastMeters * moved.eastMeters + moved.northMeters * moved.northMeters,
        );
        final fix = _lockedThen(axis, const MetricPoint(135.0, 0.0), to, speed: speed);
        final truth = (150.0 + math.pi * radius + 10.0) * scale;
        expect(
          !fix.valid || (fix.progressMeters - truth).abs() < _error,
          isTrue,
          reason:
              'placed at ${fix.progressMeters.toStringAsFixed(1)} m, truly at '
              '${truth.toStringAsFixed(1)} m',
        );
      });
    }

    // Hairpins of 6–8 m (parallel straights 12–16 m apart) and a 20°
    // figure-eight with 80 m diagonals, driven at 1 Hz and 2 Hz on the line
    // and 3 m either side of it, at four top speeds, without and with 1 m
    // of GPS error: no projected fix is more than 10 m from where the car
    // is. Before the review's fix, a fix a few metres off one leg with the
    // other leg beyond the window was placed on the wrong one.
    final shapes = <String, (SyntheticTrack, double)>{
      for (final radius in [6.0, 7.5, 8.0])
        'a $radius m hairpin': (_parallelStraights(2 * radius), 3.0),
      'a 20° figure-eight with 80 m diagonals': (
        SyntheticTrack.figureEight(diagonalMeters: 80.0, crossingDegrees: 20.0),
        4.0,
      ),
    };
    for (final MapEntry(key: name, value: (track, off)) in shapes.entries) {
      test('laps of $name at 1–2 Hz are never misplaced', () {
        final axis = track.axis();
        for (final interval in [1.0, 0.5]) {
          for (final offset in [0.0, off, -off]) {
            for (final top in [36.0, 40.0, 44.0, 48.0]) {
              for (final seed in [1, 2, 3]) {
                final lap = driveTrack(
                  track,
                  interval: interval,
                  noise: seed == 1 ? 0.0 : 1.0,
                  seed: seed,
                  lateral: (_) => offset,
                  speed: (meters) => track.cornerSpeed(meters, topSpeed: top),
                );
                expect(
                  _worstError(axis, track, lap),
                  lessThan(10.0),
                  reason: '$interval s, $offset m, $top m/s, seed $seed',
                );
              }
            }
          }
        }
      });
    }
  });

  group('finding 3: a fix beyond the forward window', () {
    test('is refused rather than placed at the window\'s end', () {
      final axis = _oval.axis();
      // 45 m/s with 3.4–3.8 s between fixes: 153–171 m, beyond the 150 m
      // cap of the window; the fix is within the 20 m proximity of its end.
      for (final interval in [3.4, 3.5, 3.6, 3.8]) {
        final lap = driveTrack(_oval, interval: interval, speed: (_) => 45.0);
        final outcome = measureProjection(axis, _oval, lap);
        expect(outcome.maximumError, lessThan(_error), reason: '$interval s: $outcome');
        expect(outcome.projected, greaterThan(0), reason: '$interval s: $outcome');
      }
      // A single step: locked at 100 m, the next fix 160 m on.
      final beyond = _lockedThen(
        axis,
        const MetricPoint(100.0, 0.0),
        const MetricPoint(260.0, 0.0),
        seconds: 3.0,
        speed: 30.0,
      );
      expect(beyond.valid, isFalse);
      // Inside the window it is placed where it is.
      final inside = _lockedThen(
        axis,
        const MetricPoint(100.0, 0.0),
        const MetricPoint(240.0, 0.0),
        seconds: 3.0,
        speed: 30.0,
      );
      expect(inside.valid, isTrue);
      expect(inside.progressMeters, closeTo(240.0 * axis.lengthMeters / _oval.lengthMeters, 1.0));
    });
  });
}
