// Port of FlappedEar Overlays' segment proposals for a lap and their
// automatic approval (revision d4d1039, FET-31): `computeSegmentReview` and
// `coverageGaps` in native/src/app/AnalysisControllerSegmentReview.cpp, and
// the decision in native/src/app/AnalysisControllerAutomaticSegments.cpp
// (KAN-136). When no run of a track configuration has approved segments, every
// proposal of the day's best lap is approved into that lap's run, so segment
// results work straight after import. They are ordinary approved segments.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart' show makeTrackSegment;

import '../geometry.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import 'track_progress.dart';
import 'track_segment_proposals.dart';
import 'track_segment_review.dart';

/// Progress ranges [trace] (one lap projected onto an axis of [length]) does
/// not cover, at least [segmentReviewMinimumGapMeters] long, from progress 0
/// to [length].
List<ProgressRange> coverageGaps(List<ProgressSegment> trace, double length) {
  final covered = [
    for (final segment in trace)
      if (segment.samples.isNotEmpty)
        ProgressRange(segment.samples.first.progressMeters, segment.samples.last.progressMeters),
  ]..sort((a, b) => a.startMeters.compareTo(b.startMeters));
  final gaps = <ProgressRange>[];
  var reached = 0.0;
  void addGap(double start, double end) {
    if (end - start >= segmentReviewMinimumGapMeters && gaps.length < maximumProposalGpsGaps) {
      gaps.add(ProgressRange(start, end));
    }
  }

  for (final range in covered) {
    addGap(reached, range.startMeters);
    reached = math.max(reached, range.endMeters);
  }
  addGap(reached, length);
  return gaps;
}

/// The segment proposals of one lap, or why there are none.
final class SegmentReview {
  SegmentReview({
    this.axis = const ProgressAxis(),
    this.features = const TrackFeatures(),
    List<ProgressSegment> lapTrace = const [],
    List<ProgressRange> gaps = const [],
    TrackSegmentProposals? proposals,
    this.unavailable = '',
    this.error = '',
  }) : lapTrace = List.unmodifiable(lapTrace),
       gaps = List.unmodifiable(gaps),
       proposals = proposals ?? TrackSegmentProposals();

  /// Built from the lap's own trace around the start gate's midpoint.
  final ProgressAxis axis;

  /// Smoothed over [segmentReviewSmoothingMeters].
  final TrackFeatures features;

  /// The lap projected onto [axis].
  final List<ProgressSegment> lapTrace;

  /// [coverageGaps] of [lapTrace].
  final List<ProgressRange> gaps;
  final TrackSegmentProposals proposals;

  /// Why the lap has no proposals (no trace, no axis, unsplittable geometry).
  final String unavailable;

  /// Set when the proposals could not be computed.
  final String error;
}

String _unresolvedProposalText(String reason) => switch (reason) {
  'continuousCorner' =>
    'No automatic proposal: this lap turns continuously, with no straight between corners.',
  'noCorners' => 'No automatic proposal: no corner was detected on this lap.',
  'tooManySegments' => 'No automatic proposal: the lap would split into more than 64 segments.',
  _ => 'No automatic proposal could be made for this lap.',
};

/// Segment proposals for timed lap [lapNumber] of [session] ([startTime] to
/// [endTime]), with [laps] derived from [session] by
/// `deriveSourceLapSession`: the progress axis is built from the lap's own
/// trace around the start gate's midpoint, features use
/// [segmentReviewSmoothingMeters], and the lap's coverage gaps mark uncertain
/// boundaries.
SegmentReview computeSegmentReview(
  TelemetrySession session,
  LapSession laps, {
  required int lapNumber,
  required double startTime,
  required double endTime,
  CancellationCheck? cancelled,
}) {
  final gate = laps.selectedStartGate;
  LapTrace? trace;
  for (final candidate in laps.lapTraces) {
    if (candidate.lapNumber == lapNumber) {
      trace = candidate;
      break;
    }
  }
  if (gate == null || trace == null) {
    return SegmentReview(
      unavailable: 'This lap has no gate-anchored GPS trace to build a track axis from.',
    );
  }
  final origin = GeoCoordinate(
    (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
    (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
  );
  final axis = buildProgressAxis(trace, origin, gate, cancelled: cancelled);
  final features = axis.valid
      ? computeTrackFeatures(axis, segmentReviewSmoothingMeters)
      : const TrackFeatures();
  if (!features.valid) {
    return SegmentReview(
      axis: axis,
      unavailable: 'The track axis could not be built from this lap\'s GPS trace.',
    );
  }
  throwIfCancelled(cancelled);
  final lapTrace = projectLapTrace(axis, session, startTime, endTime, cancelled: cancelled);
  final gaps = coverageGaps(lapTrace, axis.lengthMeters);
  final proposals = proposeTrackSegments(axis, features, gaps);
  if (!proposals.valid) {
    return SegmentReview(
      axis: axis,
      features: features,
      lapTrace: lapTrace,
      gaps: gaps,
      proposals: proposals,
      error: 'Segment proposals could not be computed for this lap.',
    );
  }
  return SegmentReview(
    axis: axis,
    features: features,
    lapTrace: lapTrace,
    gaps: gaps,
    proposals: proposals,
    unavailable: proposals.unresolvedReason.isEmpty
        ? ''
        : _unresolvedProposalText(proposals.unresolvedReason),
  );
}

/// Whether any of [runs] (a document's `event.runs`) has segments approved
/// for [groupId].
bool groupHasApprovedSegments(Iterable<Object?> runs, String groupId) {
  for (final value in runs) {
    final run = value is Map<String, Object?> ? value : const <String, Object?>{};
    final approved = approvedSegmentation(run['trackSegments'], groupId);
    if (approved.valid && approved.segments.isNotEmpty) return true;
  }
  return false;
}

/// [storedSegments] (the best lap's run's `trackSegments`) with every
/// proposal of [review] approved for [groupId] in order, skipping any that
/// [withApprovedSegment] refuses. Null when the review has no proposals or
/// none could be approved (for example when the run still stores segments of
/// another configuration).
List<Map<String, Object?>>? approveAllProposals(
  Object? storedSegments,
  SegmentReview review,
  String groupId, {
  math.Random? random,
}) {
  if (review.error.isNotEmpty ||
      review.unavailable.isNotEmpty ||
      review.proposals.proposals.isEmpty) {
    return null;
  }
  var stored = storedSegments;
  var approved = 0;
  for (final proposal in review.proposals.proposals) {
    final segment = makeTrackSegment(
      proposal.type,
      proposal.name,
      proposal.start.progressMeters,
      proposal.end.progressMeters,
      groupId,
      random: random,
    );
    if (segment.isEmpty) continue;
    final next = withApprovedSegment(stored, segment, review.axis.lengthMeters).segments;
    if (next == null) continue;
    stored = next;
    ++approved;
  }
  return approved == 0 ? null : stored as List<Map<String, Object?>>;
}

/// The automatic segments of a track configuration: null when [groupId] is
/// not a resolved `compatibility-v1` group or any of [documentRuns] already
/// has segments approved for it; otherwise the best lap's proposals approved
/// into [storedSegments], its run's current `trackSegments` (null when none
/// could be approved).
List<Map<String, Object?>>? automaticTrackSegments({
  required Iterable<Object?> documentRuns,
  required String groupId,
  required Object? storedSegments,
  required TelemetrySession session,
  required LapSession laps,
  required int lapNumber,
  required double startTime,
  required double endTime,
  math.Random? random,
  CancellationCheck? cancelled,
}) {
  if (!groupId.startsWith('compatibility-v1:') || groupHasApprovedSegments(documentRuns, groupId)) {
    return null;
  }
  final review = computeSegmentReview(
    session,
    laps,
    lapNumber: lapNumber,
    startTime: startTime,
    endTime: endTime,
    cancelled: cancelled,
  );
  return approveAllProposals(storedSegments, review, groupId, random: random);
}
