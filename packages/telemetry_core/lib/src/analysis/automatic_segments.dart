// Port of FlappedEar Overlays' segment proposals for a lap and their
// automatic approval (revision d4d1039, FET-31): `computeSegmentReview` and
// `coverageGaps` in native/src/app/AnalysisControllerSegmentReview.cpp, and
// the decision in native/src/app/AnalysisControllerAutomaticSegments.cpp
// (KAN-136). When no run of a track configuration has approved segments, every
// proposal of the day's best lap is approved into that lap's run, so segment
// results work straight after import. They are ordinary approved segments.
//
// Departure (FET-214, KAN-236): the best lap's proposals are adopted only
// when its GPS line agrees with the run's other eligible laps
// ([lineConsensus]); Overlays adopts them unchecked.
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

/// How far, in metres, a lap's line may be from most of the other eligible
/// laps anywhere along it for its proposals to be adopted without review
/// (FET-214). On the real Jastrząb and Silesia days (38 ranked laps, each
/// checked against 8 others) every lap is within 13.5 m, the days' best laps
/// within 5.2 m and 3.9 m; a check takes at most 50 ms. A line off by more
/// than 30 m, about two track widths, draws corners that are not there.
const double segmentConsensusMaximumMeters = 30.0;

/// At least this many other eligible laps check a lap's line; with fewer the
/// proposals are adopted unchecked, as Overlays does.
const int segmentConsensusMinimumLaps = 2;

/// At most this many other laps, spread over the day, are compared.
const int segmentConsensusMaximumLaps = 8;

/// The lap's line is checked every this many metres along its axis.
const double segmentConsensusStepMeters = 5.0;

/// Why no segments were adopted: the best lap's GPS line and the other
/// eligible laps' lines are far apart somewhere (FET-214).
const String automaticSegmentsLineDisagreement =
    "The best lap's GPS line is far from most of the other laps somewhere, so no "
    'segments were made automatically. Exclude the laps whose line is wrong from the ranking.';

/// How well a lap's line agrees with the other eligible laps.
final class LineConsensus {
  const LineConsensus({
    this.checkedLaps = 0,
    this.worstDistanceMeters = 0.0,
    this.worstProgressMeters = 0.0,
  });

  /// Other laps compared; none when there were too few to check.
  final int checkedLaps;

  /// The largest, along the lap, of the distance within which at least half
  /// of the other laps' lines pass: the middle distance with an odd number
  /// of laps, the smaller middle one with an even number.
  final double worstDistanceMeters;

  /// Where along the lap's axis [worstDistanceMeters] is.
  final double worstProgressMeters;

  /// Whether enough laps were compared to judge.
  bool get checked => checkedLaps >= segmentConsensusMinimumLaps;

  /// Whether, somewhere along the lap, more than half of the other laps are
  /// farther than [segmentConsensusMaximumMeters] from it.
  bool get disagrees => checked && !(worstDistanceMeters <= segmentConsensusMaximumMeters);
}

// One lap's line cut into runs of up to 32 segments, each with its bounding
// box, so most runs are passed over without measuring their segments.
final class _Line {
  _Line(List<LapTracePoint> points) : points = points {
    for (var first = 0; first + 1 < points.length; first += 32) {
      final last = math.min(first + 32, points.length - 1);
      var minEast = double.infinity, maxEast = -double.infinity;
      var minNorth = double.infinity, maxNorth = -double.infinity;
      for (var i = first; i <= last; ++i) {
        minEast = math.min(minEast, points[i].eastMeters);
        maxEast = math.max(maxEast, points[i].eastMeters);
        minNorth = math.min(minNorth, points[i].northMeters);
        maxNorth = math.max(maxNorth, points[i].northMeters);
      }
      runs.add((first, last, minEast, maxEast, minNorth, maxNorth));
    }
  }

  final List<LapTracePoint> points;
  final runs = <(int, int, double, double, double, double)>[];

  double distanceTo(MetricPoint point) {
    final px = point.eastMeters, py = point.northMeters;
    if (points.length == 1) {
      return hypot(px - points.first.eastMeters, py - points.first.northMeters);
    }
    var best = double.infinity;
    for (final (first, last, minEast, maxEast, minNorth, maxNorth) in runs) {
      final dx = px < minEast ? minEast - px : (px > maxEast ? px - maxEast : 0.0);
      final dy = py < minNorth ? minNorth - py : (py > maxNorth ? py - maxNorth : 0.0);
      if (hypot(dx, dy) >= best) continue;
      for (var i = first; i < last; ++i) {
        final a = points[i], b = points[i + 1];
        final abx = b.eastMeters - a.eastMeters, aby = b.northMeters - a.northMeters;
        final apx = px - a.eastMeters, apy = py - a.northMeters;
        final length2 = abx * abx + aby * aby;
        final t = length2 > 0.0 ? ((apx * abx + apy * aby) / length2).clamp(0.0, 1.0) : 0.0;
        final distance = hypot(apx - t * abx, apy - t * aby);
        if (distance < best) best = distance;
      }
    }
    return best;
  }
}

/// How well [axis] agrees with [others], the other eligible laps' traces in
/// metres around the same origin (laps of one track configuration share
/// their start gate, so their origin): every [segmentConsensusStepMeters]
/// along the axis, the distance within which at least half of them pass
/// (FET-214). Up to [segmentConsensusMaximumLaps] of [others], spread over
/// them; unchecked with fewer than [segmentConsensusMinimumLaps].
LineConsensus lineConsensus(
  ProgressAxis axis,
  List<LapTrace> others, {
  CancellationCheck? cancelled,
}) {
  final usable = [
    for (final trace in others)
      if (trace.points.isNotEmpty) trace,
  ];
  if (!axis.valid || usable.length < segmentConsensusMinimumLaps) return const LineConsensus();
  final chosen = usable.length <= segmentConsensusMaximumLaps
      ? usable
      : [
          for (var i = 0; i < segmentConsensusMaximumLaps; ++i)
            usable[(i * (usable.length - 1)) ~/ (segmentConsensusMaximumLaps - 1)],
        ];
  final lines = [for (final trace in chosen) _Line(trace.points)];
  final spacing = axis.spacingMeters > 0.0 ? axis.spacingMeters : segmentConsensusStepMeters;
  final stride = math.max(1, (segmentConsensusStepMeters / spacing).round());
  var worst = 0.0, worstAt = 0.0;
  final distances = List<double>.filled(lines.length, 0.0);
  for (var index = 0; index < axis.points.length; index += stride) {
    throwIfCancelled(cancelled);
    final point = axis.points[index];
    for (var lap = 0; lap < lines.length; ++lap) {
      distances[lap] = lines[lap].distanceTo(point);
    }
    distances.sort();
    // At least half of the laps pass within this distance, so it is over
    // the limit only when more than half are farther.
    final majority = distances[(distances.length - 1) ~/ 2];
    if (!(majority <= worst)) {
      worst = majority;
      worstAt = index < axis.cumulative.length ? axis.cumulative[index] : 0.0;
    }
  }
  return LineConsensus(
    checkedLaps: lines.length,
    worstDistanceMeters: worst,
    worstProgressMeters: worstAt,
  );
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
  final origin = geoMidpoint(gate.endpointA, gate.endpointB);
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
/// could be approved, or when the lap's line disagrees with [otherLaps], the
/// group's other eligible laps: [lineConsensus], FET-214).
List<Map<String, Object?>>? automaticTrackSegments({
  required Iterable<Object?> documentRuns,
  required String groupId,
  required Object? storedSegments,
  required TelemetrySession session,
  required LapSession laps,
  required int lapNumber,
  required double startTime,
  required double endTime,
  List<LapTrace> otherLaps = const [],
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
  if (lineConsensus(review.axis, otherLaps, cancelled: cancelled).disagrees) return null;
  return approveAllProposals(storedSegments, review, groupId, random: random);
}
