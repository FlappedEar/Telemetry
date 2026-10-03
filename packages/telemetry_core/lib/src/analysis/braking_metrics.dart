// Port of FlappedEar Overlays native/src/telemetry/BrakingMetrics.{h,cpp}
// (revision d4d1039, FET-33): braking metrics for one approved segment on one
// lap (KAN-53).
//
// Spatial reference: shared-axis progress. The search interval runs from
// `approachMeters` before the segment's start boundary (clipped at the gate
// and at the end of the previous approved corner) to its end boundary. The
// braking point is the first braking-onset candidate inside that interval;
// its time and distance run from the onset to the end of that braking
// episode. Deceleration is read only from the recorded longitudinal
// acceleration channel over the same episode. An interval bound on the gate
// takes the lap's timed start or end: a lap's projection never lands on the
// gate exactly.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart' show TrackSegmentType, trackSegmentTypeName;

import '../telemetry_session.dart';
import 'braking_onset.dart';
import 'corner_speeds.dart' show approvedSegmentById;
import 'track_progress.dart';
import 'track_segment_review.dart';

const String brakingMetricsAlgorithm = 'braking-metrics-v2';

const String brakingNoneDetected = 'noBrakingDetected';
const String brakingIncompleteCoverage = 'incompleteCoverage';
const String brakingSegmentCrossesGate = 'crossesGate';
const String brakingDecelerationChannelMissing = 'decelerationChannelMissing';
const String brakingApproachClipped = 'approachClippedAtGate';
const String brakingApproachClippedAtCorner = 'approachClippedAtPreviousCorner';
const String brakingMixedProvenance = 'mixedProvenance';

const double _gateEpsilon = 1e-6;

/// Options of [computeBrakingMetrics].
final class BrakingMetricsOptions {
  const BrakingMetricsOptions({
    this.approachMeters = 200.0,
    this.onset = const BrakingOnsetOptions(),
  });

  final double approachMeters;
  final BrakingOnsetOptions onset;
}

/// The braking of one segment on one lap.
final class BrakingMetrics {
  BrakingMetrics({this.segmentId = '', this.stamp = const SegmentationResultStamp()});

  final String segmentId;
  double intervalStartMeters = 0.0;
  double intervalEndMeters = 0.0;
  double entryMeters = 0.0;

  /// No braking point at all.
  String unavailableReason = '';

  /// Braking point, from the onset detector: `measuredBrake` or
  /// `inferredDeceleration`.
  String method = '';

  /// `measured` or `inferred`.
  String provenance = '';
  String channel = '';
  String thresholdUnit = '';
  double onThreshold = 0.0;
  double? brakingPointMeters;
  double? brakingPointTime;

  /// Entry minus braking point; negative inside the segment.
  double? distanceBeforeEntryMeters;
  double? brakingSeconds;

  /// Only with projected coverage to the episode end.
  double? brakingDistanceMeters;

  /// Onset uncertainty, clipped approach.
  final List<String> limitations = [];

  /// Deceleration over the braking episode (positive magnitudes, channel
  /// unit).
  String decelerationChannel = '';
  String decelerationUnit = '';
  double? peakDeceleration;
  double? meanDeceleration;
  String decelerationUnavailableReason = '';

  final SegmentationResultStamp stamp;
  bool valid = false;
}

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

/// The braking of [segmentId] on one lap from [lapStartTime] to [lapEndTime],
/// projected as [lapTrace] on an axis of [axisLengthMeters].
BrakingMetrics computeBrakingMetrics(
  double axisLengthMeters,
  ApprovedSegmentation approved,
  String segmentId,
  List<ProgressSegment> lapTrace,
  TelemetrySession session,
  double? lapStartTime,
  double? lapEndTime, [
  BrakingMetricsOptions options = const BrakingMetricsOptions(),
]) {
  if (!approved.valid ||
      !axisLengthMeters.isFinite ||
      axisLengthMeters <= 0.0 ||
      !options.approachMeters.isFinite ||
      options.approachMeters < 0.0) {
    return BrakingMetrics();
  }
  final segment = approvedSegmentById(approved, segmentId);
  if (segment == null || segment.isEmpty) return BrakingMetrics();
  final result = BrakingMetrics(
    segmentId: segmentId,
    stamp: segmentationResultStamp(approved, brakingMetricsAlgorithm),
  )..valid = true;

  final start = _number(segment['startProgressMeters']);
  final end = _number(segment['endProgressMeters']);
  result.entryMeters = start;
  if (end < start) {
    result.unavailableReason = brakingSegmentCrossesGate;
    return result;
  }
  // One gate-to-gate lap cannot see an approach that began before the gate.
  result.intervalStartMeters = math.max(0.0, start - options.approachMeters);
  result.intervalEndMeters = end;
  if (start - options.approachMeters < 0.0) result.limitations.add(brakingApproachClipped);
  // The approach never reaches back into the previous approved corner;
  // braking there belongs to that corner, not to this one.
  var clippedByCorner = false;
  for (final other in approved.segments) {
    if (other['id'] == segmentId ||
        other['type'] != trackSegmentTypeName(TrackSegmentType.corner)) {
      continue;
    }
    final otherEnd = _number(other['endProgressMeters']);
    if (otherEnd <= start + 1e-6 && otherEnd > result.intervalStartMeters) {
      result.intervalStartMeters = otherEnd;
      clippedByCorner = true;
    }
  }
  if (clippedByCorner) result.limitations.add(brakingApproachClippedAtCorner);

  // Without a brake or deceleration channel no coverage makes a braking point
  // possible.
  bool hasChannel(String alias) {
    final name = session.aliases[alias] ?? '';
    return name.isNotEmpty && session.channels.containsKey(name);
  }

  if (!hasChannel('brake') && !hasChannel('longitudinalAcceleration')) {
    result.unavailableReason = brakingNoChannel;
    return result;
  }

  final fromTime = result.intervalStartMeters <= _gateEpsilon && lapStartTime != null
      ? lapStartTime
      : timeAtProgress(lapTrace, result.intervalStartMeters);
  final toTime = result.intervalEndMeters >= axisLengthMeters - _gateEpsilon && lapEndTime != null
      ? lapEndTime
      : timeAtProgress(lapTrace, result.intervalEndMeters);
  if (fromTime == null || toTime == null || !(toTime > fromTime)) {
    result.unavailableReason = brakingIncompleteCoverage;
    return result;
  }
  final detection = detectBrakingOnsets(
    session,
    fromTime,
    toTime,
    options: options.onset,
    lapTrace: lapTrace,
  );
  result
    ..method = detection.method
    ..provenance = detection.provenance
    ..channel = detection.channel
    ..thresholdUnit = detection.threshold.unit
    ..onThreshold = detection.threshold.on;
  if (!detection.valid || detection.unresolvedReason.isNotEmpty) {
    result.unavailableReason = detection.valid
        ? detection.unresolvedReason
        : brakingIncompleteCoverage;
    return result;
  }
  BrakingOnsetCandidate? candidate;
  for (final onset in detection.candidates) {
    if (onset.progressMeters != null) {
      candidate = onset;
      break;
    }
  }
  if (candidate == null) {
    result.unavailableReason = brakingNoneDetected;
    return result;
  }
  final onsetProgress = candidate.progressMeters!;
  result
    ..brakingPointMeters = onsetProgress
    ..brakingPointTime = candidate.telemetryTime
    ..distanceBeforeEntryMeters = start - onsetProgress
    ..brakingSeconds = candidate.durationSeconds;
  result.limitations.addAll(candidate.uncertaintyReasons);
  final episodeEnd = candidate.telemetryTime + candidate.durationSeconds;
  final endProgress = progressAtTime(lapTrace, episodeEnd);
  // Only a continuous projection between onset and episode end yields a
  // distance.
  final continuous = lapTrace.any(
    (piece) =>
        piece.samples.isNotEmpty &&
        piece.samples.first.telemetryTime <= candidate!.telemetryTime &&
        piece.samples.last.telemetryTime >= episodeEnd,
  );
  if (endProgress != null && continuous && endProgress >= onsetProgress) {
    result.brakingDistanceMeters = endProgress - onsetProgress;
  }

  final decelerationName = session.aliases['longitudinalAcceleration'] ?? '';
  final deceleration = session.channels[decelerationName];
  if (decelerationName.isEmpty || deceleration == null) {
    result.decelerationUnavailableReason = brakingDecelerationChannelMissing;
    return result;
  }
  result
    ..decelerationChannel = decelerationName
    ..decelerationUnit = deceleration.unit;
  final times = deceleration.timestamps;
  final values = deceleration.values;
  if (times.length != values.length) {
    result.decelerationUnavailableReason = brakingIncompleteCoverage;
    return result;
  }
  final gapThreshold = telemetryGapThreshold(deceleration);
  final first = lowerBound(times, candidate.telemetryTime);
  final last = upperBound(times, episodeEnd);
  var peak = 0.0;
  var sum = 0.0;
  var samples = 0;
  double? previousTime;
  var gap = false;
  for (var index = first; index < last; ++index) {
    final double value = values[index];
    if (!value.isFinite ||
        (previousTime != null &&
            gapThreshold > 0.0 &&
            times[index] - previousTime > gapThreshold)) {
      gap = true;
      break;
    }
    previousTime = times[index];
    final magnitude = -value; // negative longitudinal G is braking
    peak = samples == 0 ? magnitude : math.max(peak, magnitude);
    sum += magnitude;
    ++samples;
  }
  // The episode must be covered from onset to end, not just somewhere inside.
  final reach = math.max(gapThreshold, 0.0);
  final reachesEnds =
      samples > 0 &&
      first != times.length &&
      times[first] - candidate.telemetryTime <= reach &&
      previousTime != null &&
      episodeEnd - previousTime <= reach;
  if (gap || samples < 2 || !reachesEnds) {
    result.decelerationUnavailableReason = brakingIncompleteCoverage;
    return result;
  }
  result
    ..peakDeceleration = peak
    ..meanDeceleration = sum / samples;
  return result;
}

/// A minus B for the same segment and approved revision. A braking-point
/// delta is positive when A starts braking further along the lap (later).
/// Values measured by different methods are never compared
/// (`mixedProvenance`).
final class BrakingComparison {
  const BrakingComparison({
    this.brakingPointDeltaMeters,
    this.brakingSecondsDelta,
    this.brakingDistanceDeltaMeters,
    this.peakDecelerationDelta,
    this.meanDecelerationDelta,
    this.unavailableReason = '',
    this.valid = false,
  });

  final double? brakingPointDeltaMeters;
  final double? brakingSecondsDelta;
  final double? brakingDistanceDeltaMeters;
  final double? peakDecelerationDelta;
  final double? meanDecelerationDelta;
  final String unavailableReason;
  final bool valid;
}

double? _delta(double? x, double? y) => x != null && y != null ? x - y : null;

/// [a] minus [b].
BrakingComparison compareBrakingMetrics(BrakingMetrics a, BrakingMetrics b) {
  if (!a.valid ||
      !b.valid ||
      a.segmentId != b.segmentId ||
      a.stamp.revision != b.stamp.revision ||
      a.stamp.trackConfigurationReference != b.stamp.trackConfigurationReference) {
    return const BrakingComparison(unavailableReason: 'differentSegmentOrRevision');
  }
  if (a.brakingPointMeters == null || b.brakingPointMeters == null) {
    return BrakingComparison(
      unavailableReason: a.unavailableReason.isNotEmpty ? a.unavailableReason : b.unavailableReason,
      valid: true,
    );
  }
  if (a.method != b.method || a.provenance != b.provenance || a.channel != b.channel) {
    return const BrakingComparison(unavailableReason: brakingMixedProvenance, valid: true);
  }
  final sameDeceleration =
      a.decelerationChannel == b.decelerationChannel && a.decelerationUnit == b.decelerationUnit;
  return BrakingComparison(
    brakingPointDeltaMeters: _delta(a.brakingPointMeters, b.brakingPointMeters),
    brakingSecondsDelta: _delta(a.brakingSeconds, b.brakingSeconds),
    brakingDistanceDeltaMeters: _delta(a.brakingDistanceMeters, b.brakingDistanceMeters),
    peakDecelerationDelta: sameDeceleration ? _delta(a.peakDeceleration, b.peakDeceleration) : null,
    meanDecelerationDelta: sameDeceleration ? _delta(a.meanDeceleration, b.meanDeceleration) : null,
    valid: true,
  );
}
