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
            lowestHeadingCosine = math.min(
              lowestHeadingCosine,
              (mx * tx + my * ty) / (moved * tangent),
            );
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
      'heading cosine ≥ ${lowestHeadingCosine.toStringAsFixed(3)}; '
      'fix interval ≤ ${longestInterval.toStringAsFixed(3)} s; '
      'advance ≤ ${largestAdvance.toStringAsFixed(2)} m '
      '(${(largestWindowShare * 100).toStringAsFixed(0)}% of the forward window)';
}
