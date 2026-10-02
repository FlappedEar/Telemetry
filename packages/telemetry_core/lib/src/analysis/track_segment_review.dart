// Port of the approval part of FlappedEar Overlays
// native/src/telemetry/TrackSegmentReview.{h,cpp} (revision d4d1039, FET-31):
// the approved segments of one track configuration, and adding one approved
// segment to a run's stored `trackSegments`, and the stamp a segment result
// carries (`SegmentationResultStamp`).
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart'
    show maximumTrackSegments, trackSegmentSetRevision, validTrackSegment, validTrackSegments;

import 'track_segment_proposals.dart';

/// Heading and curvature smoothing radius used to build review proposals; each
/// proposal boundary's tolerance is this plus the axis spacing.
const double segmentReviewSmoothingMeters = 6.0;

/// Coverage holes in the reviewed lap's projected trace shorter than this are
/// sampling spacing at the lap ends, not GPS gaps.
const double segmentReviewMinimumGapMeters = 15.0;

// Bounds survive a JSON round trip exactly; this only absorbs arithmetic noise.
const double _boundaryMatchMeters = 1e-6;

/// The approved segments that apply to one track configuration, and the
/// revision that identifies them. An empty [revision] means nothing is
/// approved.
final class ApprovedSegmentation {
  ApprovedSegmentation({
    required this.trackConfigurationReference,
    List<Map<String, Object?>> segments = const [],
    this.revision = '',
    this.otherConfigurationSegments = 0,
    this.valid = false,
  }) : segments = List.unmodifiable(segments);

  final String trackConfigurationReference;
  final List<Map<String, Object?>> segments;
  final String revision;

  /// Stored segments approved for a different configuration (for example
  /// before a layout change). They never apply to this configuration.
  final int otherConfigurationSegments;

  /// False when the stored value itself is malformed.
  final bool valid;
}

/// The segments of [storedSegments] (a run's `trackSegments`) approved for
/// [trackConfigurationReference].
ApprovedSegmentation approvedSegmentation(
  Object? storedSegments,
  String trackConfigurationReference,
) {
  if (!validTrackSegments(storedSegments)) {
    return ApprovedSegmentation(trackConfigurationReference: trackConfigurationReference);
  }
  final segments = <Map<String, Object?>>[];
  var other = 0;
  for (final value in (storedSegments as List?) ?? const []) {
    final segment = value as Map<String, Object?>;
    if (segment['trackConfigurationReference'] == trackConfigurationReference) {
      segments.add(segment);
    } else {
      ++other;
    }
  }
  return ApprovedSegmentation(
    trackConfigurationReference: trackConfigurationReference,
    segments: segments,
    revision: segments.isEmpty ? '' : trackSegmentSetRevision(segments),
    otherConfigurationSegments: other,
    valid: true,
  );
}

/// Splits a wrapping range into its two pieces on [0, length].
List<(double, double)> _unwrap(ProgressRange range, double length) {
  if (range.endMeters >= range.startMeters) return [(range.startMeters, range.endMeters)];
  return [(range.startMeters, math.max(range.startMeters, length)), (0.0, range.endMeters)];
}

ProgressRange _rangeOf(Map<String, Object?> segment) => ProgressRange(
  (segment['startProgressMeters'] as num).toDouble(),
  (segment['endProgressMeters'] as num).toDouble(),
);

/// True when two progress intervals (end < start wraps the gate on a loop of
/// [lengthMeters]) share more than a boundary point.
bool progressRangesOverlap(ProgressRange a, ProgressRange b, double lengthMeters) {
  for (final (xStart, xEnd) in _unwrap(a, lengthMeters)) {
    for (final (yStart, yEnd) in _unwrap(b, lengthMeters)) {
      if (math.min(xEnd, yEnd) - math.max(xStart, yStart) > _boundaryMatchMeters) return true;
    }
  }
  return false;
}

/// The result of [withApprovedSegment]: the new `trackSegments`, or null and
/// why not.
typedef SegmentApproval = ({List<Map<String, Object?>>? segments, String error});

SegmentApproval _refused(String error) => (segments: null, error: error);

/// [storedSegments] with [segment] inserted in start order, or a reason when
/// approval would overlap an approved segment, mix track configurations,
/// exceed the bound or fail validation.
SegmentApproval withApprovedSegment(
  Object? storedSegments,
  Map<String, Object?> segment,
  double lengthMeters,
) {
  if (!validTrackSegments(storedSegments) || !validTrackSegment(segment)) {
    return _refused('The segment or the stored approved segments are invalid.');
  }
  final stored = [
    for (final value in (storedSegments as List?) ?? const []) value as Map<String, Object?>,
  ];
  final reference = segment['trackConfigurationReference'];
  for (final existing in stored) {
    if (existing['trackConfigurationReference'] != reference) {
      return _refused(
        'Segments approved for a different track configuration must be discarded first.',
      );
    }
    if (existing['id'] == segment['id']) return _refused('This segment is already approved.');
    if (progressRangesOverlap(_rangeOf(existing), _rangeOf(segment), lengthMeters)) {
      return _refused('Overlaps approved segment “${existing['name']}”.');
    }
  }
  if (stored.length >= maximumTrackSegments) {
    return _refused('At most $maximumTrackSegments segments can be approved.');
  }
  final result = <Map<String, Object?>>[];
  var inserted = false;
  final start = (segment['startProgressMeters'] as num).toDouble();
  for (final value in stored) {
    if (!inserted && start < (value['startProgressMeters'] as num).toDouble()) {
      result.add(segment);
      inserted = true;
    }
    result.add(value);
  }
  if (!inserted) result.add(segment);
  if (!validTrackSegments(result)) {
    return _refused('Only the last segment on the lap may cross the start/finish line.');
  }
  return (segments: result, error: '');
}

/// [storedSegments] without the approved segment [id] (revoking approval), or
/// null when the stored value is invalid or has no such segment.
List<Map<String, Object?>>? withoutApprovedSegment(Object? storedSegments, String id) {
  if (!validTrackSegments(storedSegments)) return null;
  final result = <Map<String, Object?>>[];
  var removed = false;
  for (final value in (storedSegments as List?) ?? const []) {
    final segment = value as Map<String, Object?>;
    if (segment['id'] == id) {
      removed = true;
    } else {
      result.add(segment);
    }
  }
  return removed ? result : null;
}

/// Which approved segments and which calculation a segment result comes from,
/// so a result is never shown against segments it was not computed for.
final class SegmentationResultStamp {
  const SegmentationResultStamp({
    this.trackConfigurationReference = '',
    this.revision = '',
    this.calculationAlgorithm = '',
  });

  final String trackConfigurationReference;
  final String revision;
  final String calculationAlgorithm;
}

/// The stamp of a result computed by [calculationAlgorithm] against [approved].
SegmentationResultStamp segmentationResultStamp(
  ApprovedSegmentation approved, [
  String calculationAlgorithm = '',
]) => SegmentationResultStamp(
  trackConfigurationReference: approved.trackConfigurationReference,
  revision: approved.revision,
  calculationAlgorithm: calculationAlgorithm,
);

/// Whether [stamp] is a result of [calculationAlgorithm] for the current
/// [approved] segments.
bool segmentationResultCurrent(
  SegmentationResultStamp stamp,
  ApprovedSegmentation approved, [
  String calculationAlgorithm = '',
]) =>
    approved.valid &&
    stamp.revision.isNotEmpty &&
    stamp.revision == approved.revision &&
    stamp.trackConfigurationReference == approved.trackConfigurationReference &&
    stamp.calculationAlgorithm == calculationAlgorithm;
