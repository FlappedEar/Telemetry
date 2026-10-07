// Measures, fix by fix, the quantities the projection constants of
// track_progress.dart bound (FET-215), from the axis geometry alone: how far
// a fix is from the axis, how close the runner-up is, how far progress steps
// back, how well the heading agrees and how far a fix advances. It never
// calls the projection, so it measures what the rules see, not what they let
// through.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';

double _distance(MetricPoint a, MetricPoint b) => math.sqrt(
  math.pow(a.eastMeters - b.eastMeters, 2) + math.pow(a.northMeters - b.northMeters, 2),
);

/// The nearest point of axis segment [index] (to `index + 1`, wrapping) to
/// [point]: its progress and distance.
(double, double) _onSegment(ProgressAxis axis, int index, MetricPoint point) {
  final n = axis.points.length;
  final a = axis.points[index], b = axis.points[(index + 1) % n];
  final abx = b.eastMeters - a.eastMeters, aby = b.northMeters - a.northMeters;
  final length2 = abx * abx + aby * aby;
  var t = 0.0;
  if (length2 > 1e-9) {
    t =
        (((point.eastMeters - a.eastMeters) * abx + (point.northMeters - a.northMeters) * aby) /
                length2)
            .clamp(0.0, 1.0);
  }
  final nearest = MetricPoint(a.eastMeters + abx * t, a.northMeters + aby * t);
  final next = (index + 1) % n;
  final segmentLength = next == 0
      ? axis.lengthMeters - axis.cumulative[index]
      : axis.cumulative[next] - axis.cumulative[index];
  return (axis.cumulative[index] + segmentLength * t, _distance(point, nearest));
}

/// The best segment for [point] among [count] segments from [start]
/// (wrapping), skipping those within [exclusion] points of [excluded]:
/// (index, progress, distance), index −1 when none.
(int, double, double) nearestSegment(
  ProgressAxis axis,
  MetricPoint point, {
  int start = 0,
  int? count,
  int? excluded,
  int exclusion = 0,
}) {
  final n = axis.points.length;
  var best = (-1, 0.0, double.infinity);
  for (var step = 0; step < math.min(count ?? n, n); ++step) {
    final index = ((start + step) % n + n) % n;
    if (excluded != null) {
      var separation = (index - excluded).abs();
      separation = math.min(separation, n - separation);
      if (separation < exclusion) continue;
    }
    final (progress, distance) = _onSegment(axis, index, point);
    if (distance < best.$3) best = (index, progress, distance);
  }
  return best;
}

/// The closest two points of [axis] get to each other while being more
/// than [alongMeters] apart along it: how near another part of the track
/// comes.
double nearestOtherPart(ProgressAxis axis, double alongMeters) {
  final n = axis.points.length;
  final exclusion = (alongMeters / axis.spacingMeters).ceil();
  var nearest = double.infinity;
  for (var i = 0; i < n; ++i) {
    for (var j = i + exclusion; j < n; ++j) {
      if (n - (j - i) < exclusion) break;
      nearest = math.min(nearest, _distance(axis.points[i], axis.points[j]));
    }
  }
  return nearest;
}

/// The worst values seen over many fixes; each is a quantity one constant
/// bounds. Step quantities (ratio while locked, backward step, heading,
/// advance) count only fixes within the 20 m lock proximity, as the
/// projection would.
final class ProjectionProbe {
  static const _proximity = 20.0;

  /// Fixes measured, and those farther than the 20 m proximity from the
  /// axis (off the reference line, for example off the track).
  int fixes = 0;
  int beyondProximity = 0;
  final _distances = <double>[];

  /// Fix distance to the axis (lock and cold-start proximity, 20 m).
  double get largestDistance => _distances.isEmpty ? 0.0 : _distances.reduce(math.max);

  /// The [share] quantile of the fix distance to the axis.
  double distanceQuantile(double share) {
    if (_distances.isEmpty) return 0.0;
    final sorted = [..._distances]..sort();
    return sorted[math.min(sorted.length - 1, (sorted.length * share).floor())];
  }

  /// Best distance over the runner-up's in the projection's own window,
  /// runner-ups within 10 m along the axis skipped (ambiguity ratio 0.7
  /// while locked), and the fixes it would reject.
  double largestWindowedRatio = 0.0;
  int windowedAmbiguous = 0;

  /// The same over the whole axis, runner-ups within 30 m skipped
  /// (ambiguity ratio 0.7 on a cold start), and the fixes it would reject.
  double largestColdStartRatio = 0.0;
  int coldStartAmbiguous = 0;

  /// Nearest runner-up more than 30 m along the axis from a fix's match.
  double nearestColdStartRunnerUp = double.infinity;

  /// Largest fall in progress from one fix to the next (backward tolerance,
  /// 3 m).
  double largestBackwardStep = 0.0;

  /// Lowest cosine between the movement and the axis direction at the
  /// match, over fixes that moved at least 0.5 m (heading rule, 0).
  double lowestHeadingCosine = 1.0;
  final _headingCosines = <double>[];

  /// The [share] quantile of that cosine.
  double headingCosineQuantile(double share) {
    if (_headingCosines.isEmpty) return 1.0;
    final sorted = [..._headingCosines]..sort();
    return sorted[math.min(sorted.length - 1, (sorted.length * share).floor())];
  }

  /// Longest time between consecutive fixes (gap, 5 s).
  double longestInterval = 0.0;

  /// Largest advance from one fix to the next, and the largest share of
  /// that step's forward window (forward window, 15–150 m) it took.
  double largestAdvance = 0.0;
  double largestWindowShare = 0.0;

  /// Measures the fixes [times] / [points] of one lap, in time order, and
  /// returns each fix's progress as followed here: the nearest point of the
  /// axis near the previous fix (the whole axis for the first).
  List<double> measure(ProgressAxis axis, List<double> times, List<MetricPoint> points) {
    final followed = <double>[];
    final n = axis.points.length;
    final spacing = axis.spacingMeters;
    final windowedExclusion = math.max(3, (10.0 / spacing).round());
    final coldExclusion = math.max(4, (30.0 / spacing).round());
    double? lastProgress;
    MetricPoint? lastPoint;
    double? lastTime;
    var lastWithin = false;
    for (var i = 0; i < times.length; ++i) {
      final point = points[i];
      ++fixes;
      final best = lastProgress == null
          ? nearestSegment(axis, point)
          : nearestSegment(
              axis,
              point,
              start: (lastProgress / spacing).round() - (40 / spacing).round(),
              count: (240 / spacing).round(),
            );
      final (index, progress, distance) = best;
      followed.add(progress);
      _distances.add(distance);
      final within = distance <= _proximity;
      if (!within) ++beyondProximity;

      if (within) {
        final cold = nearestSegment(axis, point, excluded: index, exclusion: coldExclusion);
        nearestColdStartRunnerUp = math.min(nearestColdStartRunnerUp, cold.$3);
        final coldRatio = distance / cold.$3;
        largestColdStartRatio = math.max(largestColdStartRatio, coldRatio);
        if (coldRatio > 0.7) ++coldStartAmbiguous;
      }

      if (lastProgress != null && lastPoint != null && lastTime != null) {
        longestInterval = math.max(longestInterval, times[i] - lastTime);
      }
      if (within && lastWithin && lastProgress != null && lastPoint != null) {
        final mx = point.eastMeters - lastPoint.eastMeters;
        final my = point.northMeters - lastPoint.northMeters;
        final moved = math.sqrt(mx * mx + my * my);
        // The window the projection searches for this fix: speed × dt is
        // the distance moved.
        final forward = (moved * 1.6).clamp(15.0, 150.0);
        final backward = math.min(15.0, forward * 0.3);
        final backwardCount = math.max(1, (backward / spacing).round());
        final forwardCount = math.max(1, (forward / spacing).round());
        final runnerUp = nearestSegment(
          axis,
          point,
          start: (lastProgress / spacing).round() - backwardCount,
          count: forwardCount + backwardCount + 1,
          excluded: index,
          exclusion: windowedExclusion,
        );
        if (runnerUp.$1 >= 0) {
          final ratio = distance / runnerUp.$3;
          largestWindowedRatio = math.max(largestWindowedRatio, ratio);
          if (ratio > 0.7) ++windowedAmbiguous;
        }
        var step = progress - lastProgress;
        if (step < -axis.lengthMeters / 2) step += axis.lengthMeters;
        if (step > axis.lengthMeters / 2) step -= axis.lengthMeters;
        largestBackwardStep = math.max(largestBackwardStep, -step);
        largestAdvance = math.max(largestAdvance, step);
        largestWindowShare = math.max(largestWindowShare, step / forward);
        if (moved >= 0.5) {
          final a = axis.points[index], b = axis.points[(index + 1) % n];
          final tx = b.eastMeters - a.eastMeters, ty = b.northMeters - a.northMeters;
          final tangent = math.sqrt(tx * tx + ty * ty);
          if (tangent > 1e-6) {
            final cosine = (mx * tx + my * ty) / (moved * tangent);
            _headingCosines.add(cosine);
            lowestHeadingCosine = math.min(lowestHeadingCosine, cosine);
          }
        }
      }
      lastProgress = progress;
      lastPoint = point;
      lastTime = times[i];
      lastWithin = within;
    }
    return followed;
  }

  @override
  String toString() =>
      '$fixes fixes ($beyondProximity beyond 20 m): distance to the axis '
      'p95 ${distanceQuantile(0.95).toStringAsFixed(2)} m, '
      'p99 ${distanceQuantile(0.99).toStringAsFixed(2)} m, '
      'max ${largestDistance.toStringAsFixed(2)} m; '
      'windowed ambiguity ratio ≤ ${largestWindowedRatio.toStringAsFixed(3)} '
      '($windowedAmbiguous fixes above 0.7); '
      'cold-start ratio ≤ ${largestColdStartRatio.toStringAsFixed(3)} '
      '($coldStartAmbiguous fixes above 0.7), nearest cold-start runner-up '
      '${nearestColdStartRunnerUp.toStringAsFixed(1)} m; '
      'backward step ≤ ${largestBackwardStep.toStringAsFixed(2)} m; '
      'heading cosine ≥ ${lowestHeadingCosine.toStringAsFixed(3)} '
      '(0.1% quantile ${headingCosineQuantile(0.001).toStringAsFixed(3)}); '
      'fix interval ≤ ${longestInterval.toStringAsFixed(3)} s; '
      'advance ≤ ${largestAdvance.toStringAsFixed(2)} m '
      '(${(largestWindowShare * 100).toStringAsFixed(0)}% of the forward window)';
}

/// The rule of [projectSample] or [projectLapTrace] that refused a fix.
enum Refusal {
  coldStartProximity('beyond 20 m on a cold start'),
  coldStartAmbiguity('ambiguous on a cold start'),
  coldStartOtherLeg('nearer the other leg on a cold start'),
  coldStartHeading('heading on a cold start'),
  lockedProximity('beyond 20 m while locked'),
  lockedAmbiguity('ambiguous while locked'),
  lockedHeading('heading while locked'),
  backward('more than 3 m back'),
  tooFarAhead('out of reach of the lap'),
  dropped('dropped with a run on another branch');

  const Refusal(this.label);

  final String label;
}

/// The nearest axis point to [progressMeters] by the axis's cumulative
/// distances, as the projection centres its window.
int _windowCentre(ProgressAxis axis, double progressMeters) {
  final n = axis.points.length;
  final length = axis.lengthMeters;
  final progress = progressMeters - (progressMeters / length).floorToDouble() * length;
  var low = 0;
  while (low + 1 < n && axis.cumulative[low + 1] <= progress) {
    ++low;
  }
  final next = low + 1 < n ? axis.cumulative[low + 1] : length;
  return progress - axis.cumulative[low] >= next - progress ? (low + 1) % n : low;
}

bool _headingAgrees(ProgressAxis axis, int index, (double, double) movement) {
  final (mx, my) = movement;
  final moved = math.sqrt(mx * mx + my * my);
  if (!(moved > 1e-6)) return true;
  final n = axis.points.length;
  final a = axis.points[index], b = axis.points[(index + 1) % n];
  final tx = b.eastMeters - a.eastMeters, ty = b.northMeters - a.northMeters;
  final tangent = math.sqrt(tx * tx + ty * ty);
  if (!(tangent > 1e-6)) return true;
  return (mx * tx + my * ty) / (moved * tangent) >= 0.0;
}

/// The unit direction of axis segment [index], (0, 0) when degenerate.
(double, double) _tangent(ProgressAxis axis, int index) {
  final n = axis.points.length;
  final a = axis.points[index], b = axis.points[(index + 1) % n];
  final tx = b.eastMeters - a.eastMeters, ty = b.northMeters - a.northMeters;
  final length = math.sqrt(tx * tx + ty * ty);
  return length > 1e-6 ? (tx / length, ty / length) : (0.0, 0.0);
}

/// Distance from [point] to the nearest segment within the cold-start
/// separation of [index] that runs the other way (a hairpin's other leg),
/// leaving out legs the [movement] fits worse than the match (FET-256).
double _otherLeg(ProgressAxis axis, MetricPoint point, int index, (double, double) movement) {
  final n = axis.points.length;
  final separation = math.max(4, (30.0 / axis.spacingMeters).round());
  final (tx, ty) = _tangent(axis, index);
  if (tx == 0 && ty == 0) return double.infinity;
  final (mx, my) = movement;
  final fit = mx * tx + my * ty;
  var nearest = double.infinity;
  for (var offset = 1 - separation; offset < separation; ++offset) {
    final other = ((index + offset) % n + n) % n;
    final (ox, oy) = _tangent(axis, other);
    if (ox * tx + oy * ty >= 0.0 || mx * ox + my * oy < fit) continue;
    nearest = math.min(nearest, _onSegment(axis, other, point).$2);
  }
  return nearest;
}

/// Counts, rule by rule, the fixes [projectLapTrace] refuses: it replays the
/// lap fix by fix through the real [projectSample], as [projectLapTrace]
/// does, and names the rule that refused each fix by applying the rules of
/// [projectSample] in its order, then the rules [projectLapTrace] adds
/// (FET-256): how far from the lap's last projected fix, or from the gate, a
/// segment may start, and dropping a run of segments on another branch. It
/// keeps the direction of travel as [projectLapTrace] does. [disagreements] counts fixes where that
/// reading and [projectSample] differ; it should stay 0, so the breakdown
/// cannot drift from the code silently.
final class RefusalTally {
  final counts = {for (final refusal in Refusal.values) refusal: 0};

  /// Fixes accepted, and fixes where the rules read here and [projectSample]
  /// disagree.
  int accepted = 0;
  int disagreements = 0;

  /// The progress of the best match of every fix refused for ambiguity
  /// while locked.
  final lockedAmbiguityProgress = <double>[];

  int get refused => counts.values.fold(0, (sum, count) => sum + count);

  /// Replays the fixes of [session] in [startTime]..[endTime] onto [axis].
  void replay(ProgressAxis axis, TelemetrySession session, double startTime, double endTime) {
    final length = axis.lengthMeters;
    final allowance = math.min(30.0, length / 4);
    double reach(double seconds) => seconds * 100.0 + 30.0;
    // The segments kept so far, as (time, progress) of each fix.
    final segments = <List<(double, double)>>[];
    var current = <(double, double)>[];
    var fastest = 0.0;
    // The projected fixes of the last second, (time, progress).
    final recentProgress = <(double, double)>[];
    void endSegment() {
      if (current.isNotEmpty) segments.add(current);
      current = [];
    }

    // The last fix before the lap within 5 s, for the first fix's movement.
    MetricPoint? previous;
    double? previousTime;
    final latitude = session.channel('latitude')!;
    final before = latitude.timestamps.lastIndexWhere((time) => time < startTime);
    if (before >= 0 && startTime - latitude.timestamps[before] <= 5.0) {
      final time = latitude.timestamps[before];
      final longitude = session.valueAt('longitude', time);
      final coordinate = GeoCoordinate(latitude.values[before], longitude ?? double.nan);
      if (longitude != null && isValidCoordinate(coordinate)) {
        previous = projectCoordinate(coordinate, axis.origin);
        previousTime = time;
      }
    }
    for (final segment in session.sampledSegments('latitude', startTime, endTime, 4000)) {
      var context = ProjectionContext();
      endSegment();
      // The movement is kept across a raw gap of up to 5 s.
      if (previousTime != null && segment.first.time - previousTime > 5.0) {
        previous = previousTime = null;
      }
      for (final sample in segment) {
        final longitude = session.valueAt('longitude', sample.time);
        final coordinate = GeoCoordinate(sample.value, longitude ?? double.nan);
        if (longitude == null || !isValidCoordinate(coordinate)) {
          context = ProjectionContext();
          endSegment();
          previous = previousTime = null;
          continue;
        }
        final local = projectCoordinate(coordinate, axis.origin);
        var speed = 0.0;
        var movement = (0.0, 0.0);
        if (previous != null && previousTime != null && sample.time > previousTime) {
          movement = (
            local.eastMeters - previous.eastMeters,
            local.northMeters - previous.northMeters,
          );
          final moved = math.sqrt(movement.$1 * movement.$1 + movement.$2 * movement.$2);
          speed = moved / (sample.time - previousTime);
          // A cold start takes no direction from less than 0.5 m while the
          // lap stands: its last projected fix at most 0.5 s old, and less
          // than 1 m/s of progress over at least 0.5 s before it.
          if (!context.hasLock && moved < 0.5 && recentProgress.isNotEmpty) {
            final (lastTime, lastProgress) = recentProgress.last;
            if (sample.time - lastTime <= 0.5) {
              for (final (at, progress) in recentProgress.reversed) {
                if (lastTime - at < 0.5) continue;
                if (lastProgress - progress < lastTime - at) movement = (0.0, 0.0);
                break;
              }
            }
          }
        }
        // A refused fix still keeps the direction of travel (FET-256).
        previous = local;
        previousTime = sample.time;
        final (refusal, progress) = _rule(axis, local, sample.time, speed, movement, context);
        final projected = projectSample(axis, local, sample.time, speed, movement, context);
        if (projected.valid != (refusal == null)) ++disagreements;
        if (!projected.valid) {
          if (refusal != null) {
            counts[refusal] = counts[refusal]! + 1;
            if (refusal == Refusal.lockedAmbiguity) lockedAmbiguityProgress.add(progress);
          }
          context = ProjectionContext();
          endSegment();
          continue;
        }
        // The unwrapping of projectLapTrace, and where the lap could be.
        final time = sample.time;
        var unwrapped = projected.progressMeters;
        final lastFix = current.isNotEmpty
            ? current.last
            : segments.isNotEmpty
            ? segments.last.last
            : null;
        var outOfReach = false;
        if (lastFix == null) {
          if (unwrapped > length / 2 && time - startTime <= 5.0) unwrapped -= length;
          outOfReach = unwrapped < -allowance || unwrapped > reach(time - startTime);
        } else if (current.isEmpty) {
          final (lastTime, last) = lastFix;
          unwrapped += ((last - allowance - unwrapped) / length).ceilToDouble() * length;
          final ownSpeed = (fastest * 1.5).clamp(40.0, 100.0);
          var dropped = false;
          if (unwrapped - last > (time - lastTime) * ownSpeed + 30.0) {
            // Behind a short run of the latest segments and within reach of
            // the lock before them: they are dropped.
            for (var k = segments.length - 1; k >= 0; --k) {
              final first = segments[k].first.$2;
              if (last - first >= length / 4) break;
              final (anchorTime, anchor) = k == 0 ? (startTime, 0.0) : segments[k - 1].last;
              final behind =
                  unwrapped + ((anchor - allowance - unwrapped) / length).ceilToDouble() * length;
              if (behind < first - allowance && behind - anchor <= reach(time - anchorTime)) {
                for (final run in segments.sublist(k)) {
                  counts[Refusal.dropped] = counts[Refusal.dropped]! + run.length;
                }
                segments.removeRange(k, segments.length);
                unwrapped = behind;
                dropped = true;
                break;
              }
            }
          }
          outOfReach = !dropped && unwrapped - last > reach(time - lastTime);
        } else {
          final last = lastFix.$2;
          unwrapped += ((last - 3.0 - unwrapped) / length).ceilToDouble() * length;
          unwrapped = math.max(unwrapped, last);
        }
        if (outOfReach) {
          counts[Refusal.tooFarAhead] = counts[Refusal.tooFarAhead]! + 1;
          context = ProjectionContext();
          continue;
        }
        current.add((time, unwrapped));
        recentProgress
          ..removeWhere((fix) => time - fix.$1 > 1.0)
          ..add((time, unwrapped));
        // The lap's own speed over at least a second of a segment.
        for (var j = current.length - 2; j >= 0; --j) {
          final span = time - current[j].$1;
          if (span >= 1.0) {
            fastest = math.max(fastest, (unwrapped - current[j].$2) / span);
            break;
          }
        }
      }
    }
    endSegment();
    accepted += segments.fold(0, (sum, segment) => sum + segment.length);
  }

  /// The rule that refuses [point], or null, and the progress of its best
  /// match; [context] is not changed.
  static (Refusal?, double) _rule(
    ProgressAxis axis,
    MetricPoint point,
    double time,
    double speed,
    (double, double) movement,
    ProjectionContext context,
  ) {
    final spacing = axis.spacingMeters;
    final dt = context.hasLock ? time - context.lastTelemetryTime : 0.0;
    if (!context.hasLock || !(dt > 0) || dt > 5.0) {
      final (index, progress, distance) = nearestSegment(axis, point);
      if (index < 0 || distance > 20.0) return (Refusal.coldStartProximity, progress);
      final second = nearestSegment(
        axis,
        point,
        excluded: index,
        exclusion: math.max(4, (30.0 / spacing).round()),
      );
      if (second.$1 >= 0 && distance > second.$3 * 0.7) {
        return (Refusal.coldStartAmbiguity, progress);
      }
      if (distance > _otherLeg(axis, point, index, movement) * 0.7) {
        return (Refusal.coldStartOtherLeg, progress);
      }
      if (!_headingAgrees(axis, index, movement)) return (Refusal.coldStartHeading, progress);
      return (null, progress);
    }
    final forward = (dt * math.max(0.0, speed) * 1.6).clamp(15.0, 150.0);
    final backward = math.min(15.0, forward * 0.3);
    final forwardCount = math.max(1, (forward / spacing).round());
    final backwardCount = math.max(1, (backward / spacing).round());
    final start = _windowCentre(axis, context.lastProgressMeters) - backwardCount;
    final count = forwardCount + backwardCount + 1;
    final (index, progress, distance) = nearestSegment(axis, point, start: start, count: count);
    if (index < 0 || distance > 20.0) return (Refusal.lockedProximity, progress);
    final second = nearestSegment(
      axis,
      point,
      start: start,
      count: count,
      excluded: index,
      exclusion: math.max(3, (10.0 / spacing).round()),
    );
    if (second.$1 >= 0 && distance > second.$3 * 0.7) return (Refusal.lockedAmbiguity, progress);
    if (!_headingAgrees(axis, index, movement)) return (Refusal.lockedHeading, progress);
    var delta = progress - context.lastProgressMeters;
    if (delta < -axis.lengthMeters / 2) {
      delta += axis.lengthMeters;
    } else if (delta > axis.lengthMeters / 2) {
      delta -= axis.lengthMeters;
    }
    if (delta < -3.0) return (Refusal.backward, progress);
    return (null, progress);
  }

  @override
  String toString() => [
    for (final refusal in Refusal.values)
      if (counts[refusal]! > 0) '${counts[refusal]} ${refusal.label}',
  ].join(', ');
}
