// The review of a day's automatic segment proposals (FET-56), as Overlays'
// segment review shows it (AnalysisControllerSegmentReview.cpp,
// SegmentReviewPanel.qml at revision d4d1039; KAN-48, KAN-50, KAN-136): the
// proposals of the lap the day's segments are measured on, each with its
// state against the approved segments, turn, boundary tolerance and
// uncertainty, and its corner's geometric apex. Segments stay automatic: the
// review is optional, and nothing waits for it.
//
// The lap reviewed is the one the shared axis is built from: the fastest
// eligible lap of the run whose approved segments are used
// ([DayTheoreticalBest.segmentRunId]), so the proposals and the approved
// segments share one axis. With automatic segments that is the day's best
// lap. Approvals go into that run's `trackSegments` and rejections into its
// `trackSegmentReview`, as Overlays stores them (see [DaySegmentEdits]).
import 'package:fetproject/fetproject.dart' show TrackSegmentType, maximumTrackSegments;

import '../analysis/automatic_segments.dart';
import '../analysis/corner_phases.dart';
import '../analysis/outing_theoretical_best.dart';
import '../analysis/track_segment_proposals.dart';
import '../analysis/track_segment_review.dart';
import '../operation.dart';
import 'day_laps.dart';
import 'day_theoretical_best.dart';

/// The most segments a proposal may split a lap into (`tooManySegments`).
const segmentReviewMaximumSegments = maximumTrackSegments;

/// [DayProposalReview.reason] when the lap or its recording is missing.
const segmentReviewNoLap = 'noLap';

/// [DayProposalReview.reason] when the lap has no GPS trace a track axis can
/// be built from.
const segmentReviewNoAxis = 'noAxis';

/// [DayProposalReview.reason] when the proposals could not be computed.
const segmentReviewFailed = 'failed';

/// The lap whose proposals [result] is reviewed with: the fastest eligible
/// lap of [DayTheoreticalBest.segmentRunId] (the first of equal ones), as
/// the shared axis is built from it. Null when there is none.
DayLapRow? segmentReviewLap(DayTheoreticalBest result) {
  DayLapRow? lap;
  for (final timed in result.laps) {
    final row = timed.lap;
    if (row.runId != result.segmentRunId) continue;
    if (lap == null || row.end - row.start < lap.end - lap.start) lap = row;
  }
  return lap;
}

/// The proposals of one lap for the review, with each corner's geometry.
final class DayProposalReview {
  DayProposalReview({
    required this.groupId,
    required this.runId,
    this.lap,
    SegmentReview? review,
    List<CornerGeometryPhases?> phases = const [],
    this.message = '',
    this.reason = '',
    this.failed = false,
  }) : review = review ?? SegmentReview(),
       phases = List.unmodifiable(phases);

  /// The track configuration the decisions are stored for.
  final String groupId;

  /// The run approvals and rejections are stored in.
  final String runId;

  /// The lap the proposals come from.
  final DayLapRow? lap;
  final SegmentReview review;

  /// Each proposal's geometric phases (null for a straight or sector).
  final List<CornerGeometryPhases?> phases;

  /// Why there are no proposals; empty when [ready].
  final String message;

  /// [message] as a code, for the app's own text: [segmentReviewNoLap],
  /// the proposals' `unresolvedReason` (`continuousCorner`, `noCorners`,
  /// `tooManySegments`), [segmentReviewNoAxis] or [segmentReviewFailed].
  final String reason;

  /// The proposals could not be computed (as opposed to "none to make").
  final bool failed;

  bool get ready => message.isEmpty && !failed;

  List<TrackSegmentProposal> get proposals => ready ? review.proposals.proposals : const [];

  double get axisLengthMeters => review.axis.lengthMeters;

  /// Whether this review is of the lap [result] is reviewed with.
  bool matches(DayTheoreticalBest result) {
    // A result with no lap to review matches the review that says so, so
    // the app never computes it again and again.
    final current = segmentReviewLap(result);
    return lap?.reference == current?.reference &&
        runId == result.segmentRunId &&
        groupId == result.groupId;
  }

  /// The proposals [storedReview] (a run's `trackSegmentReview`) rejects.
  Set<int> rejected(Object? storedReview) =>
      rejectedProposalIndexes(storedReview, groupId, proposals);

  /// Each proposal's state against [storedSegments] (the run's
  /// `trackSegments`) and [storedReview].
  List<SegmentReviewItem> items(Object? storedSegments, Object? storedReview) =>
      reviewSegmentProposals(
        proposals,
        const {},
        rejected(storedReview),
        approvedSegmentation(storedSegments, groupId),
        axisLengthMeters,
      );
}

/// The lap [lap]'s proposals, from [run]'s recording, for [result]'s group
/// and run. A missing recording or lap is a [DayProposalReview.message].
DayProposalReview dayProposalReview(
  DayTheoreticalBest result,
  DayLapRow? lap,
  OutingRun? run, {
  CancellationCheck? cancelled,
}) {
  DayProposalReview without(String message, String reason) => DayProposalReview(
    groupId: result.groupId,
    runId: result.segmentRunId,
    lap: lap,
    message: message,
    reason: reason,
    failed: reason == segmentReviewFailed,
  );
  if (lap == null || run == null) {
    return without('The lap the segments are measured on is not available.', segmentReviewNoLap);
  }
  final SegmentReview review;
  try {
    review = computeSegmentReview(
      run.session,
      run.laps,
      lapNumber: lap.lapNumber,
      startTime: lap.start,
      endTime: lap.end,
      cancelled: cancelled,
    );
  } on OperationCancelled {
    return without('Segment review was cancelled.', segmentReviewFailed);
  }
  if (review.error.isNotEmpty) return without(review.error, segmentReviewFailed);
  if (review.unavailable.isNotEmpty) {
    final unresolved = review.proposals.unresolvedReason;
    return without(review.unavailable, unresolved.isNotEmpty ? unresolved : segmentReviewNoAxis);
  }
  return DayProposalReview(
    groupId: result.groupId,
    runId: result.segmentRunId,
    lap: lap,
    review: review,
    phases: [
      for (final proposal in review.proposals.proposals)
        proposal.type == TrackSegmentType.corner
            ? proposeCornerGeometryPhases(review.axis, review.features, proposal)
            : null,
    ],
  );
}
