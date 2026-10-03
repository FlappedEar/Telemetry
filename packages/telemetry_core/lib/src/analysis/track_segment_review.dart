// Port of FlappedEar Overlays native/src/telemetry/TrackSegmentReview.{h,cpp}
// (revision d4d1039; approval FET-31, review states and decisions FET-34): the
// approved segments of one track configuration, adding or removing one
// approved segment in a run's stored `trackSegments`, the stamp a segment
// result carries (`SegmentationResultStamp`), each proposal's review state
// against the approved set, and the rejections a run stores in
// `trackSegmentReview`.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart'
    show
        TrackSegmentType,
        maximumTrackSegments,
        qtTrimmed,
        trackSegmentSetRevision,
        trackSegmentTypeName,
        validTrackSegment,
        validTrackSegments;

import 'track_segment_proposals.dart';

/// The review's algorithm tag, stored as the `version` of a run's
/// `trackSegmentReview`.
const trackSegmentReviewAlgorithm = 'track-segment-review-v1';

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

/// Persisted form of [stamp], for results saved in a project or report.
Map<String, Object?> segmentationResultStampToJson(SegmentationResultStamp stamp) => {
  'trackConfigurationReference': stamp.trackConfigurationReference,
  'revision': stamp.revision,
  'calculationAlgorithm': stamp.calculationAlgorithm,
};

// Overlays matches these with PCRE2, where `$` also matches before a final
// newline.
final _configurationReferencePattern = RegExp(r'^compatibility-v1:[0-9a-f]{64}\n?$');
final _revisionPattern = RegExp(r'^track-segments-v1:[0-9a-f]{64}\n?$');
const int _maximumAlgorithmTagCharacters = 64;

// Matches TrackSegments' progress bound for imported or edited documents.
const double _maximumDecisionProgressMeters = 1000000.0;

/// The stamp stored in [value], or null when it is not exactly a valid
/// stamp object.
SegmentationResultStamp? segmentationResultStampFromJson(Object? value) {
  if (value is! Map<String, Object?> || value.length != 3) return null;
  final reference = value['trackConfigurationReference'];
  final revision = value['revision'];
  final algorithm = value['calculationAlgorithm'];
  if (reference is! String ||
      !_configurationReferencePattern.hasMatch(reference) ||
      revision is! String ||
      !_revisionPattern.hasMatch(revision) ||
      algorithm is! String ||
      algorithm.length > _maximumAlgorithmTagCharacters ||
      algorithm.contains('\u0000')) {
    return null;
  }
  return SegmentationResultStamp(
    trackConfigurationReference: reference,
    revision: revision,
    calculationAlgorithm: algorithm,
  );
}

/// Where a proposal stands against the approved segments.
enum SegmentReviewState {
  /// Awaiting a decision.
  proposed('proposed'),

  /// An approved segment has exactly these bounds and type.
  approved('approved'),

  /// Dismissed by the reviewer.
  rejected('rejected'),

  /// Overlaps an approved segment that came from elsewhere (an edit, another
  /// proposal).
  superseded('superseded');

  const SegmentReviewState(this.label);

  /// Overlays' `segmentReviewStateName`.
  final String label;
}

/// One proposal and its review state.
final class SegmentReviewItem {
  const SegmentReviewItem({
    required this.proposal,
    this.state = SegmentReviewState.proposed,
    this.approvedSegmentId = '',
    this.edited = false,
  });

  /// The reviewer's edited copy when [edited].
  final TrackSegmentProposal proposal;
  final SegmentReviewState state;

  /// Set when [state] is approved.
  final String approvedSegmentId;
  final bool edited;
}

bool _sameBounds(Map<String, Object?> segment, TrackSegmentProposal proposal) =>
    segment['type'] == trackSegmentTypeName(proposal.type) &&
    ((segment['startProgressMeters'] as num).toDouble() - proposal.start.progressMeters).abs() <=
        _boundaryMatchMeters &&
    ((segment['endProgressMeters'] as num).toDouble() - proposal.end.progressMeters).abs() <=
        _boundaryMatchMeters;

ProgressRange _proposalRange(TrackSegmentProposal proposal) =>
    ProgressRange(proposal.start.progressMeters, proposal.end.progressMeters);

/// Each proposal's state against [approved]. [proposals] may carry reviewer
/// edits (their indexes in [edited]); [rejected] holds proposal indexes.
List<SegmentReviewItem> reviewSegmentProposals(
  List<TrackSegmentProposal> proposals,
  Set<int> edited,
  Set<int> rejected,
  ApprovedSegmentation approved,
  double lengthMeters,
) {
  final items = <SegmentReviewItem>[];
  for (var index = 0; index < proposals.length; ++index) {
    final proposal = proposals[index];
    var approvedId = '';
    var overlapsApproved = false;
    for (final segment in approved.segments) {
      if (approvedId.isEmpty && _sameBounds(segment, proposal)) {
        approvedId = segment['id'] as String;
        continue;
      }
      overlapsApproved |= progressRangesOverlap(
        _rangeOf(segment),
        _proposalRange(proposal),
        lengthMeters,
      );
    }
    items.add(
      SegmentReviewItem(
        proposal: proposal,
        edited: edited.contains(index),
        approvedSegmentId: approvedId,
        state: approvedId.isNotEmpty
            ? SegmentReviewState.approved
            : overlapsApproved
            ? SegmentReviewState.superseded
            : rejected.contains(index)
            ? SegmentReviewState.rejected
            : SegmentReviewState.proposed,
      ),
    );
  }
  return items;
}

/// Why a reviewer's edit of a segment's name and bounds is refused, or an
/// empty string when it is valid: bounds lie in [0, [lengthMeters]] and
/// differ (end < start wraps the gate). Overlap is checked elsewhere.
String proposalEditError(String name, double startMeters, double endMeters, double lengthMeters) {
  if (!lengthMeters.isFinite || lengthMeters <= 0.0) return 'The track axis is unavailable.';
  final trimmed = qtTrimmed(name);
  if (trimmed.isEmpty || trimmed.length > 160 || trimmed.contains('\u0000')) {
    return 'Enter a name of 1–160 characters.';
  }
  if (!startMeters.isFinite ||
      !endMeters.isFinite ||
      startMeters < 0.0 ||
      endMeters < 0.0 ||
      startMeters > lengthMeters ||
      endMeters > lengthMeters) {
    return 'Bounds must lie between 0 and ${lengthMeters.toStringAsFixed(1)} m.';
  }
  if ((startMeters - endMeters).abs() <= _boundaryMatchMeters) return 'A segment cannot be empty.';
  return '';
}

/// Whether [proposalEditError] accepts the edit (Overlays'
/// `validProposalEdit`).
bool validProposalEdit(String name, double startMeters, double endMeters, double lengthMeters) =>
    proposalEditError(name, startMeters, endMeters, lengthMeters).isEmpty;

/// Most rejections a run's `trackSegmentReview` stores.
const int maximumSegmentReviewDecisions = 64;

bool _validDecisionBound(Object? value) =>
    value is num &&
    value.toDouble().isFinite &&
    value >= 0.0 &&
    value <= _maximumDecisionProgressMeters;

/// Whether [value] is a valid `trackSegmentReview`: absent, or exactly
/// `version`, `trackConfigurationReference`, `proposalAlgorithm` and at most
/// [maximumSegmentReviewDecisions] `rejected` decisions (type and bounds).
bool validTrackSegmentReview(Object? value) {
  if (value == null) return true;
  if (value is! Map<String, Object?>) return false;
  if (value.length != 4 || value['version'] != trackSegmentReviewAlgorithm) return false;
  final reference = value['trackConfigurationReference'];
  final algorithm = value['proposalAlgorithm'];
  if (reference is! String ||
      !_configurationReferencePattern.hasMatch(reference) ||
      algorithm is! String ||
      qtTrimmed(algorithm).isEmpty ||
      algorithm.length > _maximumAlgorithmTagCharacters ||
      algorithm.contains('\u0000')) {
    return false;
  }
  final rejected = value['rejected'];
  if (rejected is! List || rejected.length > maximumSegmentReviewDecisions) return false;
  for (final item in rejected) {
    if (item is! Map<String, Object?> || item.length != 3) return false;
    if (!const ['sector', 'corner', 'straight'].contains(item['type'])) return false;
    final start = item['startProgressMeters'];
    final end = item['endProgressMeters'];
    if (!_validDecisionBound(start) || !_validDecisionBound(end)) return false;
    if ((start as num).toDouble() == (end as num).toDouble()) return false;
  }
  return true;
}

/// The `trackSegmentReview` that stores [rejected] (at most
/// [maximumSegmentReviewDecisions]) for [trackConfigurationReference]; empty
/// when it would not validate.
Map<String, Object?> makeTrackSegmentReview(
  String trackConfigurationReference,
  List<TrackSegmentProposal> rejected,
) {
  final review = <String, Object?>{
    'version': trackSegmentReviewAlgorithm,
    'trackConfigurationReference': trackConfigurationReference,
    'proposalAlgorithm': trackSegmentProposalAlgorithm,
    'rejected': [
      for (final proposal in rejected.take(maximumSegmentReviewDecisions))
        {
          'type': trackSegmentTypeName(proposal.type),
          'startProgressMeters': proposal.start.progressMeters,
          'endProgressMeters': proposal.end.progressMeters,
        },
    ],
  };
  return validTrackSegmentReview(review) ? review : <String, Object?>{};
}

/// The indexes of [proposals] that [storedReview] rejects. Decisions apply
/// only to the same configuration and proposal algorithm, matched by type and
/// exact bounds.
Set<int> rejectedProposalIndexes(
  Object? storedReview,
  String trackConfigurationReference,
  List<TrackSegmentProposal> proposals,
) {
  final indexes = <int>{};
  if (storedReview is! Map<String, Object?> || !validTrackSegmentReview(storedReview)) {
    return indexes;
  }
  if (storedReview['trackConfigurationReference'] != trackConfigurationReference ||
      storedReview['proposalAlgorithm'] != trackSegmentProposalAlgorithm) {
    return indexes;
  }
  for (final item in storedReview['rejected'] as List) {
    final decision = item as Map<String, Object?>;
    for (var index = 0; index < proposals.length; ++index) {
      final proposal = proposals[index];
      if (decision['type'] == trackSegmentTypeName(proposal.type) &&
          ((decision['startProgressMeters'] as num).toDouble() - proposal.start.progressMeters)
                  .abs() <=
              _boundaryMatchMeters &&
          ((decision['endProgressMeters'] as num).toDouble() - proposal.end.progressMeters).abs() <=
              _boundaryMatchMeters) {
        indexes.add(index);
      }
    }
  }
  return indexes;
}

/// [storedSegments] without the segments approved for any configuration other
/// than [trackConfigurationReference]; only on the user's explicit request.
List<Map<String, Object?>> withoutOtherConfigurations(
  Object? storedSegments,
  String trackConfigurationReference,
) => [
  if (storedSegments is List)
    for (final value in storedSegments)
      if (value is Map<String, Object?> &&
          value['trackConfigurationReference'] == trackConfigurationReference)
        value,
];

/// The stored type named [name], or null.
TrackSegmentType? trackSegmentTypeFromName(String name) {
  for (final type in TrackSegmentType.values) {
    if (type.jsonName == name) return type;
  }
  return null;
}
