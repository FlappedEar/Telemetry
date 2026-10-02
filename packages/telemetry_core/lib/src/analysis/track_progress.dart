// Port of FlappedEar Overlays native/src/telemetry/TrackProgress.{h,cpp}
// (revision d4d1039, FET-30): a gate-anchored distance axis for one track,
// laps projected onto it, and the time delta between two laps by distance.
import 'dart:math' as math;

import '../geometry.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import '../timing_gate.dart';

/// A dense (~2 m spacing), gate-anchored loop built once per compatible track
/// group from one representative lap. Progress 0 sits at the timing-gate
/// crossing. Points are local east/north metres around [origin], the same
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

  /// Length of the closed reference loop.
  final double lengthMeters;

  /// [lengthMeters] / point count; the points are evenly arc-spaced.
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

/// A run of locked samples (time increasing) with no gap in between.
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
      best.progressMeters = _progressAtSegment(axis, index, fraction);
    }
  }
  return best;
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
/// around [origin], with index 0 at the point closest to [gate]'s midpoint.
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
  final resampled = _resampleByArcLength(points, pointCount);
  if (resampled.length != pointCount) return invalid;

  // Rotate so index 0 sits at the timing-gate crossing.
  final gateMidpoint = GeoCoordinate(
    (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2,
    (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2,
  );
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
  final rotated = [
    for (var i = 0; i < resampled.length; ++i) resampled[(gateIndex + i) % resampled.length],
  ];
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
  const backwardToleranceMeters = 3.0;
  const maximumGapSeconds = 5.0;
  const coldStartSeparationMeters = 30.0;
  const windowedSeparationMeters = 10.0;
  // Direction must not disagree outright (> 90° off): this rejects a nearby
  // parallel section running the opposite way. Cornering can dip well below a
  // "mostly agrees" bar, so this stays loose.
  const minimumHeadingCosine = 0.0;

  final dt = context.hasLock ? telemetryTime - context.lastTelemetryTime : 0.0;
  final coldStart = !context.hasLock || !(dt > 0) || dt > maximumGapSeconds;
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
    if (!_headingAgrees(axis, best.index, movementDirection, minimumHeadingCosine)) {
      return invalid;
    }
    return lock(best.progressMeters);
  }

  // Adaptive, forward-biased local window: the rest of the track is never
  // considered, which keeps a hairpin apex or a parallel straight out.
  final expectedTravel = dt * math.max(0.0, speedMetersPerSecond);
  final forwardWindow = (expectedTravel * 1.6).clamp(15.0, 150.0);
  final backwardWindow = math.min(15.0, forwardWindow * 0.3);
  final forwardCount = math.max(1, _lround(forwardWindow / axis.spacingMeters));
  final backwardCount = math.max(1, _lround(backwardWindow / axis.spacingMeters));
  final centerIndex = ((_lround(context.lastProgressMeters / axis.spacingMeters) % n) + n) % n;
  final startIndex = centerIndex - backwardCount;
  final count = forwardCount + backwardCount + 1;

  final best = _bestCandidateInRange(axis, localPoint, startIndex, count);
  // Lost lock; the caller ends the segment.
  if (best.index < 0 || best.distance > lockProximityMeters) return invalid;
  final minimumSeparation = math.max(3, _lround(windowedSeparationMeters / axis.spacingMeters));
  final second = _bestCandidateInRange(
    axis,
    localPoint,
    startIndex,
    count,
    excludeIndex: best.index,
    minimumSeparation: minimumSeparation,
  );
  if (second.index >= 0 && best.distance > second.distance * ambiguityRatio) return invalid;
  if (!_headingAgrees(axis, best.index, movementDirection, minimumHeadingCosine)) return invalid;

  var delta = best.progressMeters - context.lastProgressMeters;
  if (delta < -axis.lengthMeters / 2) {
    delta += axis.lengthMeters; // wrapped past the start/finish line
  } else if (delta > axis.lengthMeters / 2) {
    delta -= axis.lengthMeters;
  }
  if (delta < -backwardToleranceMeters) return invalid; // backward jump: not trustworthy
  return lock(best.progressMeters);
}

/// Projects every valid latitude/longitude sample of [session] in
/// [startTime]..[endTime] onto [axis], in time order. Like
/// [TelemetrySession.sampledSegments], an actual GPS gap or a stretch
/// [projectSample] cannot lock onto ends the current segment instead of
/// bridging it.
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

  var current = ProgressSegment();
  var context = ProjectionContext();
  MetricPoint? previousLocal;
  double? previousTime;
  void flush() {
    if (current.samples.isNotEmpty) {
      result.add(current);
      current = ProgressSegment();
    }
    context = ProjectionContext();
    previousLocal = null;
    previousTime = null;
  }

  for (final segment in latitudeSegments) {
    flush(); // a raw GPS gap between sampled segments is never bridged
    for (final sample in segment) {
      throwIfCancelled(cancelled);
      final time = sample.time;
      final latitude = sample.value;
      final longitude = session.valueAt('longitude', time);
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
        speed = hypot(movement.$1, movement.$2) / (time - lastTime);
      }
      previousLocal = local;
      previousTime = time;

      final projected = projectSample(axis, local, time, speed, movement, context);
      if (!projected.valid) {
        flush();
        continue;
      }
      current.samples.add(projected);
    }
  }
  if (current.samples.isNotEmpty) result.add(current);
  return result;
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
