// Port of FlappedEar Overlays native/src/telemetry/TrackProgress.{h,cpp}
// (revision d4d1039, FET-30; gate anchoring, unwrapping and the timed delta
// from Overlays KAN-152, FET-192): a gate-anchored distance axis for one
// track, laps projected onto it, and the time delta between two laps by
// distance.
import 'dart:math' as math;

import '../geometry.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import '../timing_gate.dart';

/// Projection of a gate-to-gate lap starts and ends a few samples inside the
/// gate; coverage within this distance of either gate counts as reaching it.
const double gateCoverageToleranceMeters = 15.0;

/// A dense (~2 m spacing), gate-anchored loop built once per compatible track
/// group from one representative lap. Progress 0 sits where the lap's path
/// crosses the timing gate, or at the point nearest the gate midpoint when the
/// path never crosses the gate's segment. Points are local east/north metres around [origin], the same
/// convention lap traces use (no west-positive display flip: that only matters
/// for map presentation, not for this distance math).
final class ProgressAxis {
  const ProgressAxis({
    this.points = const [],
    this.cumulative = const [],
    this.lengthMeters = 0.0,
    this.spacingMeters = 0.0,
    this.origin = const GeoCoordinate(0.0, 0.0),
    this.valid = false,
  });

  final List<MetricPoint> points;

  /// Arc length from `points[0]` to `points[i]`.
  final List<double> cumulative;

  /// Length of the closed reference loop: the RAW path's length, as Overlays
  /// has it, not the resampled points' (FET-251). `cumulative.last` plus the
  /// closing line back to `points[0]` is shorter, by about 4 m on the VBO
  /// axes of the real day and 19 m on its RCZ axes, and `_progressAtSegment`
  /// puts the whole difference into the last axis segment (about 21 m of
  /// progress on a ~2 m stretch at the gate). Using the chord length breaks
  /// the Overlays parity fixtures (191 of 497 fail in test/parity, in every
  /// progress-dependent suite), so it is a departure to agree with the owner,
  /// not made here. Convert progress to a point with [nearestAxisIndex], never
  /// by dividing by [spacingMeters].
  final double lengthMeters;

  /// [lengthMeters] / point count. The points are evenly spaced along the raw
  /// path, not along [cumulative], which is shorter (FET-249).
  final double spacingMeters;
  final GeoCoordinate origin;
  final bool valid;
}

/// Heading and curvature of the axis at one of its points.
final class TrackFeatureSample {
  const TrackFeatureSample(this.progressMeters, this.headingRadians, this.curvaturePerMeter);

  final double progressMeters;

  /// Smoothed direction of travel, `atan2(north, east)`.
  final double headingRadians;

  /// Signed rate of heading change per metre; positive turns left.
  final double curvaturePerMeter;
}

/// Heading and curvature computed from the axis's own geometry, never from a
/// per-lap projection. A pure function of the axis: it never changes the axis
/// or any telemetry.
final class TrackFeatures {
  const TrackFeatures({this.samples = const [], this.smoothingMeters = 0.0, this.valid = false});

  /// One entry per axis point, in the same order.
  final List<TrackFeatureSample> samples;
  final double smoothingMeters;
  final bool valid;
}

/// Rolling state carried between successive [projectSample] calls for one
/// lap. Re-create it after a real gap so the next sample is a cold start.
final class ProjectionContext {
  bool hasLock = false;
  double lastProgressMeters = 0.0;
  double lastTelemetryTime = 0.0;
}

/// One fix projected onto the axis.
final class ProjectedSample {
  const ProjectedSample(this.telemetryTime, {this.progressMeters = 0.0, this.valid = false});

  final double telemetryTime;
  final double progressMeters;
  final bool valid;
}

/// A run of locked samples (time increasing, progress never falling) with no
/// gap in between.
final class ProgressSegment {
  ProgressSegment([List<ProjectedSample>? samples]) : samples = samples ?? [];

  final List<ProjectedSample> samples;
}

/// The time difference between two laps at one progress value.
final class DeltaPoint {
  const DeltaPoint(this.progressMeters, this.deltaSeconds);

  final double progressMeters;

  /// A minus B; positive means A is behind at this point.
  final double deltaSeconds;
}

double _distance(MetricPoint a, MetricPoint b) =>
    hypot(a.eastMeters - b.eastMeters, a.northMeters - b.northMeters);

/// A projection may step back this far before it is distrusted.
const _backwardToleranceMeters = 3.0;

/// A lock older than this is not continued: the next fix is a cold start.
const _maximumGapSeconds = 5.0;

/// How far behind the last progress the first fix of a segment after a gap
/// may project and still be on the same lap (FET-249, KAN-237). Overlays allows only
/// [_backwardToleranceMeters], so a fix found again 4 m behind moved the rest
/// of the lap one whole lap on.
/// Capped at a quarter of the axis, so a short loop never reads a jump forward
/// as one backward.
const _segmentStartBackwardMeters = 30.0;

/// Faster than any car on a track day (360 km/h). A segment that starts after
/// a gap in a lap may lie at most this speed times the time since the lap's
/// last projected fix, plus [_segmentStartBackwardMeters], ahead of that fix
/// (FET-256): a cold start that matched another branch of the track (the
/// other diagonal of a crossing, the other leg of a hairpin, a parallel
/// straight) lands a long way off along the axis, and the lap could not have
/// driven there in the time.
const _maximumPlausibleSpeedMetersPerSecond = 100.0;

/// When a segment's first fix lies further ahead of the lap's last projected
/// fix than the lap's own speed (its fastest progress over a second) times
/// this margin, at least [_ownSpeedFloorMetersPerSecond], could have taken it,
/// it is read as lying behind the latest segments instead, which are dropped
/// if the fix fits the lock before them (FET-256).
const _ownSpeedMargin = 1.5;
const _ownSpeedFloorMetersPerSecond = 40.0;

/// A cold start takes no direction of travel from a movement shorter than
/// this while the lap stands: its projected progress advanced less than
/// [_standingMetersPerSecond] over the [_standingSeconds] before its last
/// projected fix, and that fix is at most [_standingSeconds] old. It is GPS
/// jitter (FET-256); a car crawling through a hairpin keeps its heading.
const _minimumHeadingMovementMeters = 0.5;
const _standingSeconds = 0.5;
const _standingMetersPerSecond = 1.0;

/// While locked, a part of the match's own branch at least the windowed
/// separation along the axis from the match, and nearly as near the fix as
/// the match (within this ratio of its distance), is still compared as a
/// runner-up (FET-257). The fix's distance from the axis then barely grows
/// along it: the fix is near the centre of a corner, about as near the whole
/// corner, and where it lies along it is not known. Off a straight, 10 m
/// along is never closer than 0.93 of the way within the 20 m proximity.
const _flatBranchRatio = 0.95;

/// A fix kept off the line by that comparison must not lie on the inside of
/// a bend by more than this share of the bend's radius (FET-257): further in,
/// the car may be anywhere around the bend, or past its centre on another
/// part of the track, and the nearest point of the axis no longer says
/// where (a hairpin driven 8 m inside at 1 Hz, a tight ess cut).
const _insideBendShare = 0.5;

/// The match's own branch, for that comparison, runs within 90° of the
/// match's direction; a part turned further, such as a hairpin's other leg,
/// is compared as a runner-up however near (FET-257).
const _sameBranchCosine = 0.0;

double _cross(double ax, double ay, double bx, double by) => ax * by - ay * bx;

/// Where a closed path (last point == first) crosses the gate segment
/// [a]–[b], as the index of the path's edge from `closed[edge]` to
/// `closed[edge + 1]` and the crossing point: the crossing nearest the gate
/// midpoint when there are several, or null.
(int, MetricPoint)? _gateCrossing(List<MetricPoint> closed, MetricPoint a, MetricPoint b) {
  final gateX = b.eastMeters - a.eastMeters, gateY = b.northMeters - a.northMeters;
  final midpoint = MetricPoint(
    (a.eastMeters + b.eastMeters) / 2.0,
    (a.northMeters + b.northMeters) / 2.0,
  );
  (int, MetricPoint)? result;
  var bestDistance = double.infinity;
  for (var i = 0; i + 1 < closed.length; ++i) {
    final edgeX = closed[i + 1].eastMeters - closed[i].eastMeters;
    final edgeY = closed[i + 1].northMeters - closed[i].northMeters;
    final denominator = _cross(edgeX, edgeY, gateX, gateY);
    if (!(denominator.abs() > 1e-12)) continue; // parallel: no single crossing
    final offsetX = a.eastMeters - closed[i].eastMeters;
    final offsetY = a.northMeters - closed[i].northMeters;
    final alongEdge = _cross(offsetX, offsetY, gateX, gateY) / denominator;
    final alongGate = _cross(offsetX, offsetY, edgeX, edgeY) / denominator;
    if (alongEdge < 0.0 || alongEdge >= 1.0 || alongGate < 0.0 || alongGate > 1.0) continue;
    final point = MetricPoint(
      closed[i].eastMeters + edgeX * alongEdge,
      closed[i].northMeters + edgeY * alongEdge,
    );
    final distance = _distance(point, midpoint);
    if (distance < bestDistance) {
      bestDistance = distance;
      result = (i, point);
    }
  }
  return result;
}

/// `std::lround` for the finite values used here (half away from zero).
int _lround(double value) => value.round();

/// Resamples [points] into [count] points evenly spaced by arc length,
/// `points[0]` included; callers close the loop first when they want one.
List<MetricPoint> _resampleByArcLength(List<MetricPoint> points, int count) {
  if (points.length < 2 || count < 1) return const [];
  final cumulative = <double>[0.0];
  for (var i = 1; i < points.length; ++i) {
    cumulative.add(cumulative.last + _distance(points[i - 1], points[i]));
  }
  final length = cumulative.last;
  if (!(length > 0)) return const [];
  final result = <MetricPoint>[];
  var segment = 1;
  for (var i = 0; i < count; ++i) {
    final target = length * i / count;
    while (segment + 1 < cumulative.length && cumulative[segment] < target) {
      ++segment;
    }
    final span = cumulative[segment] - cumulative[segment - 1];
    if (!(span > 0)) return const [];
    final a = points[segment - 1], b = points[segment];
    final ratio = (target - cumulative[segment - 1]) / span;
    result.add(
      MetricPoint(
        a.eastMeters + (b.eastMeters - a.eastMeters) * ratio,
        a.northMeters + (b.northMeters - a.northMeters) * ratio,
      ),
    );
  }
  return result;
}

/// (fraction along a→b, distance) of the closest point of segment a→b.
(double, double) _projectOntoSegment(MetricPoint point, MetricPoint a, MetricPoint b) {
  final abx = b.eastMeters - a.eastMeters, aby = b.northMeters - a.northMeters;
  final lengthSquared = abx * abx + aby * aby;
  if (!(lengthSquared > 1e-9)) return (0.0, _distance(point, a));
  final apx = point.eastMeters - a.eastMeters, apy = point.northMeters - a.northMeters;
  final t = ((apx * abx + apy * aby) / lengthSquared).clamp(0.0, 1.0);
  return (t, _distance(point, MetricPoint(a.eastMeters + abx * t, a.northMeters + aby * t)));
}

double _progressAtSegment(ProgressAxis axis, int segmentIndex, double fraction) {
  final n = axis.points.length;
  final next = (segmentIndex + 1) % n;
  final segmentLength = next == 0
      ? axis.lengthMeters - axis.cumulative[segmentIndex]
      : axis.cumulative[next] - axis.cumulative[segmentIndex];
  return axis.cumulative[segmentIndex] + segmentLength * fraction;
}

final class _Candidate {
  int index = -1;
  double progressMeters = 0.0;
  double distance = double.infinity;

  /// Where along segment [index] the match lies, 0 at its start and 1 at
  /// its end.
  double fraction = 0.0;
}

/// Best match within [count] axis segments from [startIndex], wrapping around
/// the loop; with [excludeIndex], anything within [minimumSeparation] points
/// of it is skipped, so the result is a genuinely different crossing rather
/// than a neighbouring segment of the same one.
_Candidate _bestCandidateInRange(
  ProgressAxis axis,
  MetricPoint point,
  int startIndex,
  int count, {
  int? excludeIndex,
  int minimumSeparation = 0,
}) {
  final best = _Candidate();
  final n = axis.points.length;
  final bounded = math.min(count, n);
  for (var step = 0; step < bounded; ++step) {
    final index = ((startIndex + step) % n + n) % n;
    if (excludeIndex != null) {
      var separation = (index - excludeIndex).abs();
      separation = math.min(separation, n - separation);
      if (separation < minimumSeparation) continue;
    }
    final (fraction, distance) = _projectOntoSegment(
      point,
      axis.points[index],
      axis.points[(index + 1) % n],
    );
    if (distance < best.distance) {
      best.index = index;
      best.distance = distance;
      best.fraction = fraction;
      best.progressMeters = _progressAtSegment(axis, index, fraction);
    }
  }
  return best;
}

/// The runner-up of a fix kept a few metres off the line while locked: the
/// best match anywhere on the axis that lies on another part of the track
/// than [best] (FET-257). The run of the axis around [best] that would itself
/// make the fix ambiguous (within [ambiguityRatio] of its distance) and runs
/// within 90° of its direction ([_sameBranchCosine]), unbroken along the axis,
/// is the same branch: a fix a few metres off a straight is nearly as close
/// to the line 10 m further on, and comparing the line with itself refused it
/// (finding 1). Every other part of the axis is another branch, however far
/// along it lies: a hairpin's other leg, a parallel straight, the other pass
/// of a crossing. A part of the branch that is nearly as near the fix as
/// [best] ([_flatBranchRatio]) still counts: the fix is near the centre of a
/// corner. As in the window, nothing within [minimumSeparation] points of
/// [best] counts.
_Candidate _runnerUpOnAnotherPart(
  ProgressAxis axis,
  MetricPoint point,
  _Candidate best,
  int minimumSeparation,
  double ambiguityRatio,
) {
  final n = axis.points.length;
  int indexAt(int offset) => ((best.index + offset) % n + n) % n;
  final distances = List<double>.filled(n, double.infinity);
  final fractions = List<double>.filled(n, 0.0);
  for (var index = 0; index < n; ++index) {
    final (fraction, distance) = _projectOntoSegment(
      point,
      axis.points[index],
      axis.points[(index + 1) % n],
    );
    distances[index] = distance;
    fractions[index] = fraction;
  }
  final (bx, by) = _axisTangent(axis, best.index);
  // Whether the segment at [index] belongs to the same branch as [best]:
  // near enough to make the fix ambiguous, and running the same way.
  bool sameBranch(int index) {
    if (!(best.distance > distances[index] * ambiguityRatio)) return false;
    final (tx, ty) = _axisTangent(axis, index);
    return tx * bx + ty * by >= _sameBranchCosine;
  }

  // The branch of [best], as offsets along the axis either side of it.
  var behind = 0, ahead = 0;
  while (behind + ahead + 1 < n && sameBranch(indexAt(-behind - 1))) {
    ++behind;
  }
  while (behind + ahead + 1 < n && sameBranch(indexAt(ahead + 1))) {
    ++ahead;
  }
  final runnerUp = _Candidate();
  for (var offset = -(n ~/ 2); offset < n - n ~/ 2; ++offset) {
    final index = indexAt(offset);
    final onBranch = offset >= -behind && offset <= ahead;
    if (onBranch && !(best.distance > distances[index] * _flatBranchRatio)) continue;
    if (offset.abs() < minimumSeparation) continue;
    if (distances[index] < runnerUp.distance) {
      runnerUp.index = index;
      runnerUp.distance = distances[index];
      runnerUp.fraction = fractions[index];
      runnerUp.progressMeters = _progressAtSegment(axis, index, fractions[index]);
    }
  }
  return runnerUp;
}

/// Whether [point] lies on the inside of a bend of the match's own branch
/// further from the axis than [_insideBendShare] of the bend's radius
/// (FET-257). The branch is the run of the axis next to [best] near enough
/// to make the fix ambiguous ([ambiguityRatio]); each point's radius comes
/// from the turn over 2 points either side. There the nearest point of the
/// axis stops following where the car is: near or past the centre of a
/// hairpin, or off the inside of an ess by more than its radius.
bool _insideBend(ProgressAxis axis, MetricPoint point, _Candidate best, double ambiguityRatio) {
  final n = axis.points.length;
  int wrap(int index) => (index % n + n) % n;
  final (tx, ty) = _axisTangent(axis, best.index);
  final a = axis.points[best.index], b = axis.points[wrap(best.index + 1)];
  final footX = a.eastMeters + (b.eastMeters - a.eastMeters) * best.fraction;
  final footY = a.northMeters + (b.northMeters - a.northMeters) * best.fraction;
  final side = _cross(tx, ty, point.eastMeters - footX, point.northMeters - footY);
  if (side == 0) return false;
  bool near(int index) {
    final (_, distance) = _projectOntoSegment(
      point,
      axis.points[wrap(index)],
      axis.points[wrap(index + 1)],
    );
    return best.distance > distance * ambiguityRatio;
  }

  bool tooTight(int index) {
    final (ax, ay) = _axisTangent(axis, wrap(index - 2));
    final (bx, by) = _axisTangent(axis, wrap(index + 2));
    final turn = math.atan2(_cross(ax, ay, bx, by), ax * bx + ay * by);
    // Turning toward the fix: the fix is on the inside of the bend.
    if (!(turn * side > 0)) return false;
    final radius = 4 * axis.spacingMeters / turn.abs();
    return best.distance > _insideBendShare * radius;
  }

  if (tooTight(best.index)) return true;
  for (final direction in [-1, 1]) {
    for (var step = 1; step < n ~/ 2 && near(best.index + direction * step); ++step) {
      if (tooTight(best.index + direction * step)) return true;
    }
  }
  return false;
}

/// Distance from [point] to the nearest axis segment within [separation]
/// points of [index] (either way) whose direction is more than 90° from the
/// direction at [index]: the other leg of a tight hairpin (FET-256). When the
/// car's [movementDirection] fits the direction at [index] better than a
/// leg's, that leg is no alternative. Infinity when there is none.
double _nearestOtherLeg(
  ProgressAxis axis,
  MetricPoint point,
  int index,
  int separation,
  (double, double) movementDirection,
) {
  final n = axis.points.length;
  final (tx, ty) = _axisTangent(axis, index);
  var nearest = double.infinity;
  if (tx == 0 && ty == 0) return nearest;
  final (mx, my) = movementDirection;
  final fit = mx * tx + my * ty; // 0 without a movement: every leg counts
  for (var offset = -separation + 1; offset < separation; ++offset) {
    final other = ((index + offset) % n + n) % n;
    final (ox, oy) = _axisTangent(axis, other);
    if (ox * tx + oy * ty >= 0.0) continue;
    if (mx * ox + my * oy < fit) continue;
    final (_, distance) = _projectOntoSegment(
      point,
      axis.points[other],
      axis.points[(other + 1) % n],
    );
    nearest = math.min(nearest, distance);
  }
  return nearest;
}

/// The axis point nearest [progressMeters] along the axis (taken modulo its
/// length), by the axis's own cumulative distances (FET-249, KAN-237; used for
/// the profile's corner positions and the corner phases too, FET-251). Overlays
/// divides by [ProgressAxis.spacingMeters] instead, which is the raw path's
/// length over the point count, while [ProgressAxis.cumulative] adds up the
/// straight lines between the resampled points: shorter, by about 4 m on a
/// VBO lap and 19 m on a 25 Hz RaceChrono RCZ lap. On the RCZ lap that
/// centre ended up 8 points (16 m) behind the car after 1.7 km, until the
/// search window no longer reached it. Projection measures progress by
/// [ProgressAxis.cumulative], so the centre does too; the two indices differ
/// by up to 2 points on a VBO lap.
///
/// An axis without points has no index: the result is 0.
int nearestAxisIndex(ProgressAxis axis, double progressMeters) {
  final n = axis.points.length;
  if (n == 0) return 0;
  final cumulative = axis.cumulative;
  final length = axis.lengthMeters;
  if (cumulative.length != n || !(length > 0.0) || !progressMeters.isFinite) {
    return ((_lround(progressMeters / axis.spacingMeters) % n) + n) % n;
  }
  final progress = progressMeters - (progressMeters / length).floorToDouble() * length;
  // The last point at or before [progress].
  var low = 0, high = n - 1;
  while (low < high) {
    final middle = (low + high + 1) >> 1;
    if (cumulative[middle] <= progress) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  final next = low + 1 < n ? cumulative[low + 1] : length;
  // Half way rounds forward, as lround does.
  return progress - cumulative[low] >= next - progress ? (low + 1) % n : low;
}

/// Unit tangent of the axis at [index], toward index + 1 (the direction of
/// travel). Zero for a degenerate segment: no heading opinion.
(double, double) _axisTangent(ProgressAxis axis, int index) {
  final n = axis.points.length;
  final a = axis.points[index], b = axis.points[(index + 1) % n];
  final ex = b.eastMeters - a.eastMeters, ey = b.northMeters - a.northMeters;
  final length = hypot(ex, ey);
  return length > 1e-6 ? (ex / length, ey / length) : (0.0, 0.0);
}

/// False when the car's direction of travel disagrees with the axis there:
/// distance alone cannot tell the right branch from a nearby parallel section
/// running the opposite way, or a hairpin's other side.
bool _headingAgrees(
  ProgressAxis axis,
  int index,
  (double, double) movementDirection,
  double minimumCosine,
) {
  final (mx, my) = movementDirection;
  final movementLength = hypot(mx, my);
  if (!(movementLength > 1e-6)) return true; // no heading evidence: don't reject on it
  final (tx, ty) = _axisTangent(axis, index);
  if (tx == 0 && ty == 0) return true; // degenerate axis segment: no opinion
  final cosine = (mx * tx + my * ty) / movementLength;
  return cosine >= minimumCosine;
}

/// Signed shortest angle from [from] to [to], in (−π, π]; never a naive
/// subtraction, which breaks across the ±π wrap.
double _angularDifference(double to, double from) =>
    math.atan2(math.sin(to - from), math.cos(to - from));

/// The progress axis of [referenceTrace] (a reference-eligible, gap-free lap)
/// around [origin], with index 0 where the lap's path crosses [gate] (else the
/// point closest to its midpoint).
/// Invalid for fewer than 12 distinct points or a loop outside 50 m–30 km.
ProgressAxis buildProgressAxis(
  LapTrace referenceTrace,
  GeoCoordinate origin,
  TimingGate gate, {
  CancellationCheck? cancelled,
}) {
  throwIfCancelled(cancelled);
  const invalid = ProgressAxis();
  if (referenceTrace.points.length < 12) return invalid;

  final points = <MetricPoint>[];
  for (final sample in referenceTrace.points) {
    final point = MetricPoint(sample.eastMeters, sample.northMeters);
    if (!point.eastMeters.isFinite || !point.northMeters.isFinite) return invalid;
    // Drop sub-0.5 m GPS jitter: fine enough for ~2 m spacing, coarse enough
    // that duplicate fixes don't make a zero-length resampling segment.
    if (points.isEmpty || _distance(points.last, point) >= 0.5) points.add(point);
  }
  if (points.length < 12) return invalid;
  points.add(points.first); // close the loop

  var length = 0.0;
  for (var i = 1; i < points.length; ++i) {
    length += _distance(points[i - 1], points[i]);
  }
  if (!(length >= 50 && length <= 30000)) return invalid;

  final pointCount = _lround(length / 2.0).clamp(32, 15000);

  // Progress 0 is where the path crosses the timing gate (KAN-152): the closed
  // path is restarted at that crossing before it is resampled. The point
  // nearest the gate midpoint is not enough: an oblique gate whose midpoint
  // lies off the racing line puts it metres after the crossing, and each lap's
  // first fix would project just before progress 0.
  final crossing = _gateCrossing(
    points,
    projectCoordinate(gate.endpointA, origin),
    projectCoordinate(gate.endpointB, origin),
  );
  final List<MetricPoint> rotated;
  if (crossing != null) {
    final (edge, point) = crossing;
    final open = points.length - 1; // points.last repeats points.first
    final restarted = <MetricPoint>[point];
    for (var step = 1; step <= open; ++step) {
      final next = points[(edge + step) % open];
      if (_distance(next, restarted.last) > 1e-9) restarted.add(next);
    }
    if (_distance(point, restarted.last) > 1e-9) restarted.add(point);
    rotated = _resampleByArcLength(restarted, pointCount);
    if (rotated.length != pointCount) return invalid;
  } else {
    // The path never crosses the gate's segment: rotate so index 0 is the
    // resampled point nearest the gate midpoint.
    final resampled = _resampleByArcLength(points, pointCount);
    if (resampled.length != pointCount) return invalid;
    final gateMidpoint = geoMidpoint(gate.endpointA, gate.endpointB);
    final gateLocal = projectCoordinate(gateMidpoint, origin);
    var gateIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < resampled.length; ++i) {
      final d = _distance(resampled[i], gateLocal);
      if (d < bestDistance) {
        bestDistance = d;
        gateIndex = i;
      }
    }
    rotated = [
      for (var i = 0; i < resampled.length; ++i) resampled[(gateIndex + i) % resampled.length],
    ];
  }
  final cumulative = <double>[0.0];
  for (var i = 1; i < rotated.length; ++i) {
    cumulative.add(cumulative.last + _distance(rotated[i - 1], rotated[i]));
  }
  return ProgressAxis(
    points: List.unmodifiable(rotated),
    cumulative: List.unmodifiable(cumulative),
    lengthMeters: length,
    spacingMeters: length / rotated.length,
    origin: origin,
    valid: true,
  );
}

/// Heading at each axis point as the circular mean (mean of unit tangents,
/// never of raw angles, which breaks across ±π) of the direction of travel
/// within [smoothingMeters] on each side, wrapping around the loop; curvature
/// as the signed change to the next point's heading over the point spacing.
/// Needs a positive, finite [smoothingMeters] and a valid axis of 4+ points.
TrackFeatures computeTrackFeatures(ProgressAxis axis, double smoothingMeters) {
  if (!axis.valid ||
      axis.points.length < 4 ||
      !(axis.spacingMeters > 0.0) ||
      !smoothingMeters.isFinite ||
      smoothingMeters <= 0.0) {
    return const TrackFeatures();
  }
  final n = axis.points.length;
  final radius = _lround(smoothingMeters / axis.spacingMeters).clamp(1, n ~/ 2 - 1);

  final heading = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; ++i) {
    var sumEast = 0.0, sumNorth = 0.0;
    for (var offset = -radius; offset <= radius; ++offset) {
      final index = ((i + offset) % n + n) % n;
      final (tx, ty) = _axisTangent(axis, index);
      sumEast += tx;
      sumNorth += ty;
    }
    heading[i] = math.atan2(sumNorth, sumEast);
  }

  final samples = <TrackFeatureSample>[
    for (var i = 0; i < n; ++i)
      TrackFeatureSample(
        axis.cumulative[i],
        heading[i],
        _angularDifference(heading[(i + 1) % n], heading[i]) / axis.spacingMeters,
      ),
  ];
  return TrackFeatures(
    samples: List.unmodifiable(samples),
    smoothingMeters: smoothingMeters,
    valid: true,
  );
}

/// Projects one GPS fix ([localPoint], metres around the axis origin) onto
/// [axis] with a bounded local search: the previous lock plus dt × speed sizes
/// a forward-biased window instead of searching the whole track, and the car's
/// [movementDirection] (raw displacement since the previous fix) must roughly
/// agree with the axis direction at the match. Window, heading and a runner-up
/// ambiguity gap together tell a hairpin apex or an opposite-running parallel
/// straight from the right branch.
///
/// Returns an invalid sample, never a guess, when no candidate is unambiguous,
/// continuous, heading-consistent and close enough. [context] changes only on
/// success. A zero [movementDirection] (e.g. the first fix) skips the heading
/// check for that sample.
ProjectedSample projectSample(
  ProgressAxis axis,
  MetricPoint localPoint,
  double telemetryTime,
  double speedMetersPerSecond,
  (double, double) movementDirection,
  ProjectionContext context,
) {
  final invalid = ProjectedSample(telemetryTime);
  if (!axis.valid || axis.points.length < 8 || !(axis.spacingMeters > 0)) return invalid;
  if (!localPoint.eastMeters.isFinite ||
      !localPoint.northMeters.isFinite ||
      !telemetryTime.isFinite) {
    return invalid;
  }

  const coldStartProximityMeters = 20.0;
  const lockProximityMeters = 20.0;
  const ambiguityRatio = 0.7; // reject when the runner-up is within 70% of the best distance
  const coldStartSeparationMeters = 30.0;
  const windowedSeparationMeters = 10.0;
  // Direction must not disagree outright (> 90° off): this rejects a nearby
  // parallel section running the opposite way. Cornering can dip well below a
  // "mostly agrees" bar, so this stays loose.
  const minimumHeadingCosine = 0.0;

  final dt = context.hasLock ? telemetryTime - context.lastTelemetryTime : 0.0;
  final coldStart = !context.hasLock || !(dt > 0) || dt > _maximumGapSeconds;
  final n = axis.points.length;

  ProjectedSample lock(double progress) {
    context.hasLock = true;
    context.lastProgressMeters = progress;
    context.lastTelemetryTime = telemetryTime;
    return ProjectedSample(telemetryTime, progressMeters: progress, valid: true);
  }

  if (coldStart) {
    // No usable window (or too long since the last lock): require an
    // unambiguous global match before locking on.
    final best = _bestCandidateInRange(axis, localPoint, 0, n);
    if (best.index < 0 || best.distance > coldStartProximityMeters) return invalid;
    final minimumSeparation = math.max(4, _lround(coldStartSeparationMeters / axis.spacingMeters));
    final second = _bestCandidateInRange(
      axis,
      localPoint,
      0,
      n,
      excludeIndex: best.index,
      minimumSeparation: minimumSeparation,
    );
    if (second.index >= 0 && best.distance > second.distance * ambiguityRatio) return invalid;
    // The separation keeps the same branch out of the comparison, but in a
    // hairpin tighter than about 10 m radius the other leg is nearer than
    // that along the axis, so it was never compared and a fix midway between
    // the legs locked on to either (FET-256). A part of the axis running the
    // other way from the match is another branch, however near, unless the
    // direction of travel rules it out.
    final otherLeg = _nearestOtherLeg(
      axis,
      localPoint,
      best.index,
      minimumSeparation,
      movementDirection,
    );
    if (best.distance > otherLeg * ambiguityRatio) return invalid;
    if (!_headingAgrees(axis, best.index, movementDirection, minimumHeadingCosine)) {
      return invalid;
    }
    return lock(best.progressMeters);
  }

  // Adaptive, forward-biased local window around the previous lock: a fix
  // matches only near where the lap was. That alone does not keep another
  // branch out (it can lie inside the window, or beyond it); the runner-up
  // checks below do.
  final expectedTravel = dt * math.max(0.0, speedMetersPerSecond);
  final forwardWindow = (expectedTravel * 1.6).clamp(15.0, 150.0);
  final backwardWindow = math.min(15.0, forwardWindow * 0.3);
  final forwardCount = math.max(1, _lround(forwardWindow / axis.spacingMeters));
  final backwardCount = math.max(1, _lround(backwardWindow / axis.spacingMeters));
  final centerIndex = nearestAxisIndex(axis, context.lastProgressMeters);
  final startIndex = centerIndex - backwardCount;
  final count = forwardCount + backwardCount + 1;

  final best = _bestCandidateInRange(axis, localPoint, startIndex, count);
  // Lost lock; the caller ends the segment.
  if (best.index < 0 || best.distance > lockProximityMeters) return invalid;
  // A fix whose nearest point lies beyond the window's forward end matched
  // only the end of the window, not where it is (FET-257, finding 3): it is
  // refused, and the next fix is a cold start on the whole axis.
  if (count < n && best.index == ((startIndex + count - 1) % n + n) % n && best.fraction >= 1.0) {
    return invalid;
  }
  final minimumSeparation = math.max(3, _lround(windowedSeparationMeters / axis.spacingMeters));
  // Overlays' runner-up: the best match in the window at least the windowed
  // separation from [best]. On a straight it is the same line 10 m on, so a
  // fix about 8 m off the line is refused by it (finding 1).
  final windowed = _bestCandidateInRange(
    axis,
    localPoint,
    startIndex,
    count,
    excludeIndex: best.index,
    minimumSeparation: minimumSeparation,
  );
  if (windowed.index >= 0 && best.distance > windowed.distance * ambiguityRatio) {
    // Such a fix is kept only when every other branch of the track is
    // ruled out (FET-257). The window alone does not show that: another
    // branch can lie beyond it (a hairpin's exit leg at 1 Hz, a parallel
    // straight). So no part of the whole axis beyond the match's own branch
    // may be nearly as near, and the fix must not lie well inside a bend.
    final second = _runnerUpOnAnotherPart(
      axis,
      localPoint,
      best,
      minimumSeparation,
      ambiguityRatio,
    );
    if (second.index >= 0 && best.distance > second.distance * ambiguityRatio) return invalid;
    if (_insideBend(axis, localPoint, best, ambiguityRatio)) return invalid;
  }
  if (!_headingAgrees(axis, best.index, movementDirection, minimumHeadingCosine)) return invalid;

  var delta = best.progressMeters - context.lastProgressMeters;
  if (delta < -axis.lengthMeters / 2) {
    delta += axis.lengthMeters; // wrapped past the start/finish line
  } else if (delta > axis.lengthMeters / 2) {
    delta -= axis.lengthMeters;
  }
  if (delta < -_backwardToleranceMeters) return invalid; // backward jump: not trustworthy
  return lock(best.progressMeters);
}

/// Projects every valid latitude/longitude sample of [session] in
/// [startTime]..[endTime] onto [axis], in time order. Like
/// [TelemetrySession.sampledSegments], an actual GPS gap or a stretch
/// [projectSample] cannot lock onto ends the current segment instead of
/// bridging it.
///
/// Progress is unwrapped within the lap (KAN-152): a fix taken just after the
/// lap's timed start that projects just before progress 0 is stored as a small
/// negative value, and fixes past the finish continue beyond the axis length.
/// A fix projecting slightly behind the previous one in its segment is held at
/// the previous progress, so progress never falls within a segment.
///
/// A segment after a gap must start where the lap could have driven since its
/// last projected fix (FET-256); a fix that does not matched another branch of
/// the track and is refused. When a fix instead fits the lap's earlier lock
/// (the gate at [startTime] before the first segment) and lies behind where a
/// short run of the latest segments started, or out of the run's reach where
/// the earlier lock could have driven at the lap's own speed, those segments
/// matched another branch and are dropped, rather than the rest of the lap
/// being moved on by a lap or refused.
List<ProgressSegment> projectLapTrace(
  ProgressAxis axis,
  TelemetrySession session,
  double startTime,
  double endTime, {
  CancellationCheck? cancelled,
}) {
  final result = <ProgressSegment>[];
  if (!axis.valid) return result;
  final latitudeSegments = session.sampledSegments('latitude', startTime, endTime, 4000);
  final length = axis.lengthMeters;
  // How far behind the last progress a segment's first fix may lie and still
  // be on the same lap (FET-249).
  final allowance = math.min(_segmentStartBackwardMeters, length / 4);

  var current = ProgressSegment();
  var context = ProjectionContext();
  // The last fix, projected or not, for the direction of travel; seeded with
  // the last fix before the lap, so the lap's first fix has one too.
  var (previousLocal, previousTime) = _fixBefore(session, startTime, axis.origin);
  // The lap's projected fixes of the last second, (time, progress), to tell
  // whether it stands.
  final recentProgress = <(double, double)>[];
  double? lastProgress; // unwrapped; kept across segments of this lap
  double? lastProgressTime; // when the fix at [lastProgress] was taken
  // The lap's own speed: its fastest progress over a second within a
  // segment, and where in [current] that second starts.
  var fastest = 0.0;
  var secondAgo = 0;

  // Ends the current segment; the next fix is a cold start. Unless the lap
  // has to forget it, the next fix's movement is still measured from the
  // last fix, so the cold start has a direction of travel to check
  // (FET-256): after a fix the projection refused, and across a raw GPS gap
  // of up to [_maximumGapSeconds]. Overlays forgets it, so a cold start could
  // lock on to a hairpin's other leg or a parallel straight driven the other
  // way.
  void flush({bool keepMovement = false}) {
    if (current.samples.isNotEmpty) {
      result.add(current);
      current = ProgressSegment();
    }
    context = ProjectionContext();
    secondAgo = 0;
    if (!keepMovement) {
      previousLocal = null;
      previousTime = null;
    }
  }

  // How far ahead of a fix [seconds] earlier the lap could be: at
  // [_maximumPlausibleSpeedMetersPerSecond], or at its own speed with a margin.
  double reach(double seconds) =>
      seconds * _maximumPlausibleSpeedMetersPerSecond + _segmentStartBackwardMeters;
  double ownReach(double seconds) =>
      seconds *
          (fastest * _ownSpeedMargin).clamp(
            _ownSpeedFloorMetersPerSecond,
            _maximumPlausibleSpeedMetersPerSecond,
          ) +
      _segmentStartBackwardMeters;

  // The latest segments a segment's first fix at [progress] (any lap of it)
  // and [time] shows to be on another branch: the index in [result] of the
  // first of them and the fix's progress from the lock before it, or null.
  // The run must cover less than a quarter of the axis (a long run is more
  // likely right than one fix), and the fix must either lie behind where
  // the run started and within reach of the lock before it ([behind]), or,
  // out of the run's reach, be where the lock before it could have driven at
  // the lap's own speed (otherwise).
  (int, double)? conflictingRun(double progress, double time, {required bool behind}) {
    final last = lastProgress!;
    for (var k = result.length - 1; k >= 0; --k) {
      final first = result[k].samples.first.progressMeters;
      if (last - first >= length / 4) return null;
      // The lap's last progress and its time when segment k began: the
      // gate at [startTime] for the first. A lap timed from another line
      // than the axis gate makes this lock off by that line's distance from
      // the gate, which matters only for dropping the lap's first segment.
      final (anchor, anchorTime) = k == 0
          ? (0.0, startTime)
          : (result[k - 1].samples.last.progressMeters, result[k - 1].samples.last.telemetryTime);
      final from = progress + ((anchor - allowance - progress) / length).ceilToDouble() * length;
      if (behind
          ? from < first - allowance && from - anchor <= reach(time - anchorTime)
          : from - anchor <= ownReach(time - anchorTime)) {
        return (k, from);
      }
    }
    return null;
  }

  for (final segment in latitudeSegments) {
    // A raw GPS gap between sampled segments is never bridged, but up to
    // [_maximumGapSeconds] the movement across it still gives the direction
    // of travel.
    final since = previousTime;
    flush(keepMovement: since != null && segment.first.time - since <= _maximumGapSeconds);
    for (final sample in segment) {
      throwIfCancelled(cancelled);
      final time = sample.time;
      final latitude = sample.value;
      final longitude = session.valueAt('longitude', time, InterpolationMode.longitude);
      if (longitude == null || !isValidCoordinate(GeoCoordinate(latitude, longitude))) {
        flush();
        continue;
      }
      final local = projectCoordinate(GeoCoordinate(latitude, longitude), axis.origin);
      var speed = 0.0;
      var movement = (0.0, 0.0);
      final lastLocal = previousLocal, lastTime = previousTime;
      if (lastLocal != null && lastTime != null && time > lastTime) {
        movement = (
          local.eastMeters - lastLocal.eastMeters,
          local.northMeters - lastLocal.northMeters,
        );
        final moved = hypot(movement.$1, movement.$2);
        speed = moved / (time - lastTime);
        // A cold start takes no direction from the GPS jitter of a standing
        // car.
        if (!context.hasLock &&
            moved < _minimumHeadingMovementMeters &&
            _standing(recentProgress, time)) {
          movement = (0.0, 0.0);
        }
      }
      previousLocal = local;
      previousTime = time;

      final projected = projectSample(axis, local, time, speed, movement, context);
      if (!projected.valid) {
        flush(keepMovement: true);
        continue;
      }

      // Unwrap at the gate (KAN-152). The lap's first fix, taken just after
      // its timed start, may project onto the end of the axis: it is just
      // before progress 0. Later fixes continue forward from the last one by
      // whole laps of the axis, so fixes past the finish run beyond the axis
      // length.
      var progress = projected.progressMeters;
      final last = lastProgress;
      if (last == null) {
        if (progress > length / 2 && time - startTime <= _maximumGapSeconds) {
          progress -= length;
        }
        // No bound here: the lap may be timed from another line than the
        // axis gate, so where it starts on the axis is not known. A first
        // segment on another branch is dropped by the later fixes instead.
      } else if (current.samples.isEmpty) {
        // A segment after a gap continues from the last progress too, but its
        // first fix, found again from scratch, may be a little more behind
        // than the jitter tolerance (FET-249): up to the allowance is the
        // same lap, not one lap on.
        progress += ((last - allowance - progress) / length).ceilToDouble() * length;
        // A segment's first fix is a cold start, found on the whole axis
        // (FET-256). Further ahead than the lap could have driven since, at
        // its own speed, it may instead lie behind the latest segments: if
        // it fits the lock before them, they matched another branch, and
        // they are dropped rather than this fix and every later one moved on
        // by a lap. Otherwise, further ahead than any car could have driven,
        // it matched another branch itself and is refused, leaving a gap.
        final ahead = progress - last, since = time - lastProgressTime!;
        var run = ahead > ownReach(since) ? conflictingRun(progress, time, behind: true) : null;
        // The mirror case: a cold start after a long gap matched another
        // branch behind the car but within reach, and the right fixes after
        // it are out of its reach. When the lock before that run could have
        // reached this fix at the lap's own speed, the run is dropped.
        if (run == null && ahead > reach(since)) {
          run = conflictingRun(progress, time, behind: false);
        }
        if (run != null) {
          final (k, behind) = run;
          result.removeRange(k, result.length);
          progress = behind;
        } else if (ahead > reach(since)) {
          flush(keepMovement: true);
          continue;
        }
      } else {
        progress += ((last - _backwardToleranceMeters - progress) / length).ceilToDouble() * length;
        // A fix projecting up to the backward tolerance behind the last one
        // in this segment (GPS jitter, often while stopped) is held at the
        // last progress, so progress never falls within a segment and the
        // segment still covers the fix's time.
        progress = math.max(progress, last);
      }
      lastProgress = progress;
      lastProgressTime = time;
      current.samples.add(
        ProjectedSample(projected.telemetryTime, progressMeters: progress, valid: true),
      );
      recentProgress
        ..removeWhere((fix) => time - fix.$1 > 1.0)
        ..add((time, progress));
      // The lap's own speed, over at least a second of this segment.
      final samples = current.samples;
      while (secondAgo + 1 < samples.length && time - samples[secondAgo + 1].telemetryTime >= 1.0) {
        ++secondAgo;
      }
      final span = time - samples[secondAgo].telemetryTime;
      if (span >= 1.0) {
        fastest = math.max(fastest, (progress - samples[secondAgo].progressMeters) / span);
      }
    }
  }
  if (current.samples.isNotEmpty) result.add(current);
  return result;
}

/// Whether the lap stands at [time]: its last projected fix, from
/// [recentProgress] ((time, progress), in time order), is at most
/// [_standingSeconds] old, and its progress advanced less than
/// [_standingMetersPerSecond] over at least [_standingSeconds] before it.
bool _standing(List<(double, double)> recentProgress, double time) {
  if (recentProgress.isEmpty) return false;
  final (lastTime, lastProgress) = recentProgress.last;
  if (time - lastTime > _standingSeconds) return false;
  for (final (at, progress) in recentProgress.reversed) {
    final span = lastTime - at;
    if (span >= _standingSeconds) return lastProgress - progress < span * _standingMetersPerSecond;
  }
  return false;
}

/// The last fix of [session] before [time], in metres around [origin], and its
/// time; (null, null) when it is more than [_maximumGapSeconds] before [time]
/// or has no valid coordinate, as the lap would forget the movement then.
(MetricPoint?, double?) _fixBefore(TelemetrySession session, double time, GeoCoordinate origin) {
  final latitude = session.channel('latitude');
  if (latitude == null || latitude.timestamps.length != latitude.values.length) {
    return (null, null);
  }
  final timestamps = latitude.timestamps;
  var low = 0, high = timestamps.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (timestamps[middle] < time) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low == 0 || !(time - timestamps[low - 1] <= _maximumGapSeconds)) return (null, null);
  final before = timestamps[low - 1];
  final longitude = session.valueAt('longitude', before);
  final coordinate = GeoCoordinate(latitude.values[low - 1], longitude ?? double.nan);
  if (longitude == null || !isValidCoordinate(coordinate)) return (null, null);
  return (projectCoordinate(coordinate, origin), before);
}

/// Index of the first sample whose [key] is not less than [value].
int _lowerBound(List<ProjectedSample> samples, double value, double Function(ProjectedSample) key) {
  var low = 0;
  var high = samples.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (key(samples[middle]) < value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

double? _timeAtProgressInSegment(ProgressSegment segment, double progress) {
  final samples = segment.samples;
  if (samples.isEmpty ||
      progress < samples.first.progressMeters ||
      progress > samples.last.progressMeters) {
    return null;
  }
  final next = _lowerBound(samples, progress, (sample) => sample.progressMeters);
  if (next == 0) return samples[next].telemetryTime;
  if (next == samples.length) return samples[next - 1].telemetryTime;
  final previous = samples[next - 1];
  final span = samples[next].progressMeters - previous.progressMeters;
  if (!(span > 0)) return previous.telemetryTime;
  final ratio = (progress - previous.progressMeters) / span;
  return previous.telemetryTime + (samples[next].telemetryTime - previous.telemetryTime) * ratio;
}

/// Reference lap start: the exact progress-0 crossing when covered, else the
/// earliest projected sample as the closest available approximation.
double _referenceTime(List<ProgressSegment> lap) {
  final time = timeAtProgress(lap, 0.0);
  if (time != null) return time;
  for (final segment in lap) {
    if (segment.samples.isNotEmpty) return segment.samples.first.telemetryTime;
  }
  return 0.0;
}

/// Interpolated telemetry time at [progressMeters], from the first segment
/// whose locked coverage reaches it; null otherwise (never bridged).
double? timeAtProgress(List<ProgressSegment> lap, double progressMeters) {
  for (final segment in lap) {
    final time = _timeAtProgressInSegment(segment, progressMeters);
    if (time != null) return time;
  }
  return null;
}

/// Interpolated progress at [telemetryTime], or null when no segment's locked
/// coverage spans that time (never bridged).
double? progressAtTime(List<ProgressSegment> lap, double telemetryTime) {
  for (final segment in lap) {
    final samples = segment.samples;
    if (samples.isEmpty ||
        telemetryTime < samples.first.telemetryTime ||
        telemetryTime > samples.last.telemetryTime) {
      continue;
    }
    final next = _lowerBound(samples, telemetryTime, (sample) => sample.telemetryTime);
    if (next == 0) return samples[next].progressMeters;
    final previous = samples[next - 1];
    final span = samples[next].telemetryTime - previous.telemetryTime;
    if (!(span > 0.0)) return previous.progressMeters;
    return previous.progressMeters +
        (samples[next].progressMeters - previous.progressMeters) *
            (telemetryTime - previous.telemetryTime) /
            span;
  }
  return null;
}

/// Each lap's timed start (its gate crossing) and end, and the axis length,
/// for [computeDeltaSeries].
final class DeltaTiming {
  const DeltaTiming({
    required this.lapStartA,
    required this.lapEndA,
    required this.lapStartB,
    required this.lapEndB,
    required this.lengthMeters,
  });

  final double lapStartA;
  final double lapEndA;
  final double lapStartB;
  final double lapEndB;
  final double lengthMeters;
}

/// [lap] at its timed start at progress 0 and its timed end at [length], when
/// its projection stops within the gate tolerance of them.
List<ProgressSegment> _anchoredAtGate(
  List<ProgressSegment> lap,
  double start,
  double end,
  double length,
) {
  if (lap.isEmpty || lap.first.samples.isEmpty || lap.last.samples.isEmpty) return lap;
  final segments = [
    for (final segment in lap) ProgressSegment([...segment.samples]),
  ];
  final first = segments.first.samples;
  if (first.first.progressMeters > 0.0 &&
      first.first.progressMeters <= gateCoverageToleranceMeters &&
      start < first.first.telemetryTime) {
    first.insert(0, ProjectedSample(start, valid: true));
  }
  final last = segments.last.samples;
  if (last.last.progressMeters < length &&
      last.last.progressMeters >= length - gateCoverageToleranceMeters &&
      end > last.last.telemetryTime) {
    last.add(ProjectedSample(end, progressMeters: length, valid: true));
  }
  return segments;
}

/// Lap A's time from its timed start minus lap B's, every [progressStepMeters]
/// from 0 to the axis length, which is always the last step (KAN-152). Like
/// sector timing, a lap whose projection reaches within
/// [gateCoverageToleranceMeters] of the gate is at progress 0 at its timed
/// start and at the axis length at its timed end, so the delta is 0 at the
/// start and the lap-time difference at the finish. Only where both laps have
/// locked coverage of the same progress; each uncovered stretch starts a new
/// series.
List<List<DeltaPoint>> computeTimedDeltaSeries(
  List<ProgressSegment> lapA,
  List<ProgressSegment> lapB,
  double progressStepMeters,
  DeltaTiming timing, {
  CancellationCheck? cancelled,
}) {
  final result = <List<DeltaPoint>>[];
  final length = timing.lengthMeters;
  if (lapA.isEmpty ||
      lapB.isEmpty ||
      !(progressStepMeters > 0) ||
      !length.isFinite ||
      !(length > 0)) {
    return result;
  }
  final anchoredA = _anchoredAtGate(lapA, timing.lapStartA, timing.lapEndA, length);
  final anchoredB = _anchoredAtGate(lapB, timing.lapStartB, timing.lapEndB, length);

  final steps = (length / progressStepMeters).ceil();
  var current = <DeltaPoint>[];
  for (var i = 0; i <= steps; ++i) {
    throwIfCancelled(cancelled);
    final progress = math.min(length, i * progressStepMeters);
    final timeA = timeAtProgress(anchoredA, progress);
    final timeB = timeAtProgress(anchoredB, progress);
    if (timeA == null || timeB == null) {
      if (current.isNotEmpty) {
        result.add(current);
        current = [];
      }
      continue;
    }
    current.add(DeltaPoint(progress, (timeA - timing.lapStartA) - (timeB - timing.lapStartB)));
  }
  if (current.isNotEmpty) result.add(current);
  return result;
}

/// Lap A's time minus lap B's (each relative to its own start) every
/// [progressStepMeters], only where both laps have locked coverage of the same
/// progress: never across a gap in either lap, never invented between their
/// differing valid ranges. Each uncovered stretch starts a new series.
List<List<DeltaPoint>> computeDeltaSeries(
  List<ProgressSegment> lapA,
  List<ProgressSegment> lapB,
  double progressStepMeters, {
  CancellationCheck? cancelled,
}) {
  final result = <List<DeltaPoint>>[];
  if (lapA.isEmpty || lapB.isEmpty || !(progressStepMeters > 0)) return result;

  var maxProgress = 0.0;
  var haveCoverage = false;
  for (final segment in [...lapA, ...lapB]) {
    if (segment.samples.isNotEmpty) {
      maxProgress = math.max(maxProgress, segment.samples.last.progressMeters);
      haveCoverage = true;
    }
  }
  if (!haveCoverage || !(maxProgress > 0)) return result;

  final referenceA = _referenceTime(lapA);
  final referenceB = _referenceTime(lapB);
  final steps = (maxProgress / progressStepMeters).floor();

  var current = <DeltaPoint>[];
  for (var i = 0; i <= steps; ++i) {
    throwIfCancelled(cancelled);
    final progress = math.min(maxProgress, i * progressStepMeters);
    final timeA = timeAtProgress(lapA, progress);
    final timeB = timeAtProgress(lapB, progress);
    if (timeA == null || timeB == null) {
      if (current.isNotEmpty) {
        result.add(current);
        current = [];
      }
      continue;
    }
    current.add(DeltaPoint(progress, (timeA - referenceA) - (timeB - referenceB)));
  }
  if (current.isNotEmpty) result.add(current);
  return result;
}
