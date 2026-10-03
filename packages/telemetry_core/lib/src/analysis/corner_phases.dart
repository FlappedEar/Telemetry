// Port of FlappedEar Overlays native/src/telemetry/CornerPhases.{h,cpp}
// (revision d4d1039, FET-33): a corner's geometric entry, apex and exit on a
// progress axis, and one lap's minimum-speed location inside it.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart' show TrackSegmentType, validTrackSegment;

import '../telemetry_session.dart';
import 'track_progress.dart';
import 'track_segment_proposals.dart';

const String cornerPhaseAlgorithm = 'corner-phase-v1';

/// Phase methods. Entry, apex and exit are track geometry, shared by every lap
/// on the axis. The minimum-speed location is a per-lap driving measurement
/// and is never used as, or derived from, the apex.
const String cornerPhaseCurvatureOnset = 'curvatureOnset';
const String cornerPhasePeakCurvature = 'peakCurvatureRegion';
const String cornerPhaseCurvatureRelease = 'curvatureRelease';
const String cornerPhaseMinimumSpeed = 'minimumSpeed';

/// Unresolved reasons: the phase has no location.
const String cornerPhaseMultipleApexes = 'multipleApexes';
const String cornerPhaseSpeedChannelMissing = 'speedChannelMissing';
const String cornerPhaseIncompleteCoverage = 'incompleteCoverage';
const String cornerPhaseFlatSpeed = 'flatSpeed';
const String cornerPhaseCrossesGate = 'crossesGate';
const String cornerPhaseInsufficientGeometry = 'insufficientGeometry';
const String cornerPhaseInvalidInput = 'invalidInput';

/// Uncertainty reasons: located, but not a sharp single point.
const String cornerPhaseBroadPeak = 'broadPeak';
const String cornerPhaseAtCornerBoundary = 'atCornerBoundary';

/// Most samples [locateMinimumSpeed] takes across one corner.
const int maximumMinimumSpeedSamples = 100000;

/// One phase of a corner.
final class CornerPhasePoint {
  CornerPhasePoint({
    this.method = '',
    this.progressMeters = 0.0,
    this.toleranceMeters = 0.0,
    List<String>? uncertaintyReasons,
    this.unresolvedReason = '',
    Map<String, Object?>? evidence,
  }) : uncertaintyReasons = uncertaintyReasons ?? [],
       evidence = evidence ?? {};

  String method;
  double progressMeters;
  double toleranceMeters;
  final List<String> uncertaintyReasons;

  /// Non-empty: no location is proposed.
  String unresolvedReason;

  /// Method inputs and measured values, for review.
  final Map<String, Object?> evidence;

  bool get resolved => unresolvedReason.isEmpty;
}

/// A corner's geometric phases.
final class CornerGeometryPhases {
  CornerGeometryPhases({
    CornerPhasePoint? entry,
    CornerPhasePoint? apex,
    CornerPhasePoint? exit,
    List<double>? apexCandidatesMeters,
    this.valid = false,
  }) : entry = entry ?? CornerPhasePoint(),
       apex = apex ?? CornerPhasePoint(),
       exit = exit ?? CornerPhasePoint(),
       apexCandidatesMeters = apexCandidatesMeters ?? [];

  final CornerPhasePoint entry;
  final CornerPhasePoint apex;
  final CornerPhasePoint exit;

  /// Progress of every separate high-curvature region, in travel order. More
  /// than one leaves the apex unresolved for review.
  final List<double> apexCandidatesMeters;
  final bool valid;
}

/// Thresholds of [proposeCornerGeometryPhases] and [locateMinimumSpeed].
final class CornerPhaseOptions {
  const CornerPhaseOptions({
    this.apexRegionRatio = 0.8,
    this.apexSeparationRatio = 0.6,
    this.flatSpeedFraction = 0.02,
  });

  /// Curvature at or above this fraction of the corner peak starts a region.
  final double apexRegionRatio;

  /// A region ends only once curvature falls below this fraction.
  final double apexSeparationRatio;

  /// Speeds within this fraction of the corner's speed range count as the
  /// minimum.
  final double flatSpeedFraction;
}

bool _inProgressRange(double progress, double start, double end) =>
    start <= end ? progress >= start && progress < end : progress >= start || progress < end;

// Axis sample indices inside the corner, in travel order (handles a corner
// that wraps across the gate).
List<int> _cornerIndices(TrackFeatures features, TrackSegmentProposal corner) {
  final n = features.samples.length;
  final start = corner.start.progressMeters;
  final end = corner.end.progressMeters;
  var first = 0;
  for (var i = 0; i < n; ++i) {
    if (features.samples[i].progressMeters >= start) {
      first = i;
      break;
    }
  }
  final indices = <int>[];
  for (var walked = 0, index = first; walked < n; ++walked, index = (index + 1) % n) {
    if (!_inProgressRange(features.samples[index].progressMeters, start, end)) break;
    indices.add(index);
  }
  return indices;
}

bool _validCorner(TrackSegmentProposal corner, double length) {
  bool inAxis(double value) => value.isFinite && value >= 0.0 && value <= length;
  return corner.type == TrackSegmentType.corner &&
      inAxis(corner.start.progressMeters) &&
      inAxis(corner.end.progressMeters) &&
      corner.start.progressMeters != corner.end.progressMeters;
}

bool _validOptions(CornerPhaseOptions options) =>
    options.apexRegionRatio.isFinite &&
    options.apexSeparationRatio.isFinite &&
    options.flatSpeedFraction.isFinite &&
    options.apexSeparationRatio > 0.0 &&
    options.apexSeparationRatio < options.apexRegionRatio &&
    options.apexRegionRatio <= 1.0 &&
    options.flatSpeedFraction > 0.0 &&
    options.flatSpeedFraction < 1.0;

CornerPhasePoint _boundaryPhase(String method, SegmentProposalBoundary boundary) =>
    CornerPhasePoint(
      method: method,
      progressMeters: boundary.progressMeters,
      toleranceMeters: boundary.toleranceMeters,
      uncertaintyReasons: [...boundary.uncertaintyReasons],
      evidence: {'source': trackSegmentProposalAlgorithm},
    );

/// Entry and exit reuse the corner proposal's boundaries (and their
/// uncertainty); the apex is the midpoint of the corner's high-curvature
/// region. [corner] must be a corner proposal on this axis.
CornerGeometryPhases proposeCornerGeometryPhases(
  ProgressAxis axis,
  TrackFeatures features,
  TrackSegmentProposal corner, [
  CornerPhaseOptions options = const CornerPhaseOptions(),
]) {
  if (!axis.valid ||
      !features.valid ||
      features.samples.length != axis.points.length ||
      axis.points.length < 4 ||
      !(axis.spacingMeters > 0.0) ||
      !_validCorner(corner, axis.lengthMeters) ||
      !_validOptions(options)) {
    return CornerGeometryPhases();
  }
  final apex = CornerPhasePoint(method: cornerPhasePeakCurvature);
  final result = CornerGeometryPhases(
    entry: _boundaryPhase(cornerPhaseCurvatureOnset, corner.start),
    apex: apex,
    exit: _boundaryPhase(cornerPhaseCurvatureRelease, corner.end),
    valid: true,
  );

  final indices = _cornerIndices(features, corner);
  final direction = corner.turnRadians != 0.0 ? corner.turnRadians : corner.peakCurvaturePerMeter;
  final sign = direction >= 0.0 ? 1.0 : -1.0;
  final turning = <double>[];
  var peak = 0.0;
  for (final index in indices) {
    final value = sign * features.samples[index].curvaturePerMeter;
    turning.add(value);
    peak = math.max(peak, value);
  }
  if (indices.length < 3 || !(peak > 0.0) || direction == 0.0) {
    apex.unresolvedReason = cornerPhaseInsufficientGeometry;
    return result;
  }

  // Hysteresis keeps small curvature ripple on a constant-radius arc from
  // splitting one region into several false apexes.
  final regions = <List<int>>[]; // [first, last]
  var open = false;
  for (var j = 0; j < turning.length; ++j) {
    if (!open && turning[j] >= options.apexRegionRatio * peak) {
      regions.add([j, j]);
      open = true;
    } else if (open && turning[j] < options.apexSeparationRatio * peak) {
      open = false;
    } else if (open && turning[j] >= options.apexRegionRatio * peak) {
      regions.last[1] = j;
    }
  }

  final spacing = axis.spacingMeters;
  final length = axis.lengthMeters;
  final baseTolerance = features.smoothingMeters + spacing;
  double regionStart(List<int> region) => features.samples[indices[region[0]]].progressMeters;
  double regionMidpoint(List<int> region) =>
      (regionStart(region) + (region[1] - region[0]) * spacing / 2.0).remainder(length);
  final candidates = <double>[];
  for (final region in regions) {
    result.apexCandidatesMeters.add(regionMidpoint(region));
    candidates.add(regionMidpoint(region));
  }
  apex.evidence.addAll({
    'peakCurvaturePerMeter': sign * peak,
    'regionRatio': options.apexRegionRatio,
    'separationRatio': options.apexSeparationRatio,
    'smoothingMeters': features.smoothingMeters,
    'candidatesMeters': candidates,
  });
  if (regions.length != 1) {
    apex.unresolvedReason = cornerPhaseMultipleApexes;
    return result;
  }

  final region = regions.first;
  final halfWidth = (region[1] - region[0]) * spacing / 2.0;
  apex.progressMeters = regionMidpoint(region);
  apex.toleranceMeters = math.max(baseTolerance, halfWidth + spacing);
  apex.evidence['regionStartMeters'] = regionStart(region);
  apex.evidence['regionEndMeters'] = features.samples[indices[region[1]]].progressMeters;
  if (halfWidth > baseTolerance) apex.uncertaintyReasons.add(cornerPhaseBroadPeak);
  return result;
}

/// Samples one lap's `speed` channel every [stepMeters] across the corner,
/// using that lap's projected trace ([projectLapTrace] on the same axis). Any
/// sample without projected coverage or a speed value leaves the result
/// unresolved rather than searching around the hole.
CornerPhasePoint locateMinimumSpeed(
  ProgressAxis axis,
  TrackSegmentProposal corner,
  List<ProgressSegment> lapTrace,
  TelemetrySession session,
  double stepMeters, [
  CornerPhaseOptions options = const CornerPhaseOptions(),
]) {
  final point = CornerPhasePoint(method: cornerPhaseMinimumSpeed);
  if (!axis.valid ||
      !_validCorner(corner, axis.lengthMeters) ||
      !_validOptions(options) ||
      !stepMeters.isFinite ||
      stepMeters <= 0.0) {
    point.unresolvedReason = cornerPhaseInvalidInput;
    return point;
  }
  point.evidence['stepMeters'] = stepMeters;

  final channelName = session.aliases['speed'] ?? '';
  final channel = session.channels[channelName];
  if (channelName.isEmpty || channel == null) {
    point.unresolvedReason = cornerPhaseSpeedChannelMissing;
    return point;
  }
  point.evidence['channel'] = channelName;
  point.evidence['unit'] = channel.unit;
  // One lap is timed gate to gate, so the two halves of a gate-crossing
  // corner lie at opposite ends of the lap and are not one continuous pass.
  if (corner.end.progressMeters < corner.start.progressMeters) {
    point.unresolvedReason = cornerPhaseCrossesGate;
    return point;
  }

  final start = corner.start.progressMeters;
  final span = corner.end.progressMeters - start;
  final sampleCountExact = (span / stepMeters).ceilToDouble() + 1.0;
  if (!(sampleCountExact <= maximumMinimumSpeedSamples)) {
    point.unresolvedReason = cornerPhaseInvalidInput;
    return point;
  }
  final count = sampleCountExact.toInt();
  final progress = List<double>.filled(count, 0.0);
  final values = List<double>.filled(count, 0.0);
  final times = List<double>.filled(count, 0.0);
  var missing = 0;
  for (var k = 0; k < count; ++k) {
    progress[k] = math.min(start + k * stepMeters, corner.end.progressMeters);
    final time = timeAtProgress(lapTrace, progress[k]);
    final value = time == null ? null : session.valueAt(channelName, time);
    if (value == null) {
      ++missing;
      continue;
    }
    times[k] = time!;
    values[k] = value;
  }
  point.evidence['samples'] = count;
  if (missing > 0) {
    point.evidence['missingSamples'] = missing;
    point.unresolvedReason = cornerPhaseIncompleteCoverage;
    return point;
  }

  // The first smallest value, as std::minmax_element finds it.
  var lowest = 0;
  var maximum = values[0];
  for (var k = 1; k < count; ++k) {
    if (values[k] < values[lowest]) lowest = k;
    if (values[k] >= maximum) maximum = values[k];
  }
  final minimum = values[lowest];
  if (!(maximum - minimum > 1e-9 * math.max(1.0, maximum.abs()))) {
    point.unresolvedReason = cornerPhaseFlatSpeed;
    return point;
  }
  final nearMinimum = minimum + options.flatSpeedFraction * (maximum - minimum);
  var left = lowest;
  var right = lowest;
  while (left > 0 && values[left - 1] <= nearMinimum) {
    --left;
  }
  while (right + 1 < count && values[right + 1] <= nearMinimum) {
    ++right;
  }

  point.progressMeters = progress[lowest];
  point.toleranceMeters =
      stepMeters + math.max(progress[lowest] - progress[left], progress[right] - progress[lowest]);
  if (left == 0 || right == count - 1) point.uncertaintyReasons.add(cornerPhaseAtCornerBoundary);
  point.evidence.addAll({
    'minimumValue': minimum,
    'maximumValue': maximum,
    'telemetryTime': times[lowest],
    'flatSpeedFraction': options.flatSpeedFraction,
  });
  return point;
}

/// The geometric view of an approved segment on an axis: a corner proposal
/// with the segment's exact bounds (no automatic uncertainty) and its turn and
/// peak curvature measured from [features], for use with the phase functions
/// above. A straight-type proposal on bad input.
TrackSegmentProposal cornerFromSegment(
  ProgressAxis axis,
  TrackFeatures features,
  Map<String, Object?> segment,
) {
  TrackSegmentProposal invalid() => TrackSegmentProposal(
    type: TrackSegmentType.straight,
    name: '',
    start: SegmentProposalBoundary(0.0, 0.0),
    end: SegmentProposalBoundary(0.0, 0.0),
  );
  if (!axis.valid ||
      !features.valid ||
      features.samples.length != axis.points.length ||
      !validTrackSegment(segment)) {
    return invalid();
  }
  final length = axis.lengthMeters;
  final start = (segment['startProgressMeters'] as num).toDouble();
  final end = (segment['endProgressMeters'] as num).toDouble();
  if (start > length || end > length) return invalid();
  final bounds = TrackSegmentProposal(
    type: TrackSegmentType.corner,
    name: segment['name'] as String,
    start: SegmentProposalBoundary(start, 0.0),
    end: SegmentProposalBoundary(end, 0.0),
  );
  var turn = 0.0;
  var peak = 0.0;
  for (final index in _cornerIndices(features, bounds)) {
    final curvature = features.samples[index].curvaturePerMeter;
    turn += curvature * axis.spacingMeters;
    if (curvature.abs() > peak.abs()) peak = curvature;
  }
  return TrackSegmentProposal(
    type: TrackSegmentType.corner,
    name: bounds.name,
    start: bounds.start,
    end: bounds.end,
    lengthMeters: end >= start ? end - start : end + length - start,
    turnRadians: turn,
    peakCurvaturePerMeter: peak,
  );
}
