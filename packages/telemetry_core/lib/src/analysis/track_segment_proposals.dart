// Port of FlappedEar Overlays native/src/telemetry/TrackSegmentProposals.{h,cpp}
// (revision d4d1039, FET-31): corners and straights proposed from a progress
// axis's smoothed curvature.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart'
    show TrackSegmentType, makeTrackSegment, maximumTrackSegments, validTrackSegments;

import 'track_progress.dart';

/// Corners with no proposed straight between them form one corner chain.
/// Stored review decisions are keyed by this tag (and match proposals by exact
/// bounds, so dividing chains, [SegmentProposalOptions.splitCornerChains],
/// needs no new tag).
const trackSegmentProposalAlgorithm = 'track-segment-proposal-v2';

/// Uncertainty reasons of a proposal boundary. A boundary with no reason is
/// geometrically well separated; it still carries a finite tolerance.
const proposalUncertainConnectedCorners = 'connectedCorners';
const proposalUncertainShortStraight = 'shortStraight';
const proposalUncertainGpsGap = 'gpsGap';

/// Most GPS gaps [proposeTrackSegments] accepts.
const int maximumProposalGpsGaps = 4096;

/// A progress interval on an axis; [endMeters] < [startMeters] wraps across
/// the gate.
final class ProgressRange {
  const ProgressRange(this.startMeters, this.endMeters);

  final double startMeters;
  final double endMeters;

  @override
  bool operator ==(Object other) =>
      other is ProgressRange && other.startMeters == startMeters && other.endMeters == endMeters;

  @override
  int get hashCode => Object.hash(startMeters, endMeters);

  @override
  String toString() => '[$startMeters, $endMeters]';
}

/// Thresholds of [proposeTrackSegments].
final class SegmentProposalOptions {
  const SegmentProposalOptions({
    this.cornerCurvaturePerMeter = defaultCornerCurvaturePerMeter,
    this.minimumCornerTurnRadians = 0.35,
    this.connectedStraightMeters = 20.0,
    this.certainStraightMeters = 40.0,
    this.splitCornerChains = false,
  });

  /// |curvature| at or above this is turning.
  final double cornerCurvaturePerMeter;

  /// [cornerCurvaturePerMeter] by default (also the turning part of the
  /// corner classes, FET-220).
  static const double defaultCornerCurvaturePerMeter = 1.0 / 250.0;

  /// Smaller turning runs are kinks, kept in the straight.
  final double minimumCornerTurnRadians;

  /// Shorter straights are not proposed; the corners around them join.
  final double connectedStraightMeters;

  /// Shorter straights get uncertain boundaries.
  final double certainStraightMeters;

  /// Whether a chain of corners with no proposed straight between them is
  /// divided into its single corners, one per turning run (FET-115). The
  /// stretch between two runs joins the corner before it, and the boundary
  /// between them is uncertain ([proposalUncertainConnectedCorners]). Off,
  /// the chain is one proposal, as in FlappedEar Overlays.
  final bool splitCornerChains;
}

/// One end of a proposal.
final class SegmentProposalBoundary {
  SegmentProposalBoundary(this.progressMeters, this.toleranceMeters, [List<String>? reasons])
    : uncertaintyReasons = reasons ?? [];

  double progressMeters;

  /// Smoothing radius plus axis spacing.
  final double toleranceMeters;
  final List<String> uncertaintyReasons;

  bool get certain => uncertaintyReasons.isEmpty;

  SegmentProposalBoundary _copy() =>
      SegmentProposalBoundary(progressMeters, toleranceMeters, [...uncertaintyReasons]);
}

/// A proposed corner or straight. Proposals carry no ids or approval state.
final class TrackSegmentProposal {
  TrackSegmentProposal({
    required this.type,
    required this.name,
    required this.start,
    required this.end,
    this.lengthMeters = 0.0,
    this.turnRadians = 0.0,
    this.peakCurvaturePerMeter = 0.0,
    this.chainedCorners = 0,
  });

  final TrackSegmentType type;
  final String name;
  final SegmentProposalBoundary start;

  /// `end.progressMeters < start.progressMeters` wraps across the gate.
  final SegmentProposalBoundary end;
  final double lengthMeters;

  /// Signed total heading change; positive turns left.
  final double turnRadians;

  /// Signed curvature with the largest magnitude.
  final double peakCurvaturePerMeter;

  /// Corners joined into this proposal (0 for a straight).
  final int chainedCorners;
}

/// The result of [proposeTrackSegments].
final class TrackSegmentProposals {
  TrackSegmentProposals({
    List<TrackSegmentProposal> proposals = const [],
    this.unresolvedReason = '',
    this.options = const SegmentProposalOptions(),
    this.valid = false,
  }) : proposals = List.unmodifiable(proposals);

  /// Non-decreasing start progress; only the last proposal may wrap.
  final List<TrackSegmentProposal> proposals;

  /// Set (with no proposals) when the geometry cannot be split without
  /// inventing boundaries: `continuousCorner`, `noCorners`, `tooManySegments`.
  final String unresolvedReason;
  final SegmentProposalOptions options;
  final bool valid;
}

/// A maximal circular run of samples sharing one label: 0 straight, +1 left
/// corner, -1 right corner.
final class _Run {
  _Run(this.label, this.first, this.count);

  final int label;
  final int first;
  int count;
}

/// Empty when every sample has the same label (no boundary exists).
List<_Run> _circularRuns(List<int> labels) {
  final n = labels.length;
  var startIndex = -1;
  for (var i = 0; i < n; ++i) {
    if (labels[i] != labels[(i - 1 + n) % n]) {
      startIndex = i;
      break;
    }
  }
  final runs = <_Run>[];
  if (startIndex < 0) return runs;
  var index = startIndex;
  var walked = 0;
  while (walked < n) {
    final run = _Run(labels[index], index, 0);
    while (walked < n && labels[index] == run.label) {
      ++run.count;
      index = (index + 1) % n;
      ++walked;
    }
    runs.add(run);
  }
  return runs;
}

double _circularDistance(double a, double b, double length) {
  final direct = (a - b).abs();
  return math.min(direct, length - direct);
}

bool _nearRange(double progress, ProgressRange range, double tolerance, double length) {
  final inside = range.startMeters <= range.endMeters
      ? progress >= range.startMeters && progress <= range.endMeters
      : progress >= range.startMeters || progress <= range.endMeters;
  return inside ||
      _circularDistance(progress, range.startMeters, length) <= tolerance ||
      _circularDistance(progress, range.endMeters, length) <= tolerance;
}

bool _validOptions(SegmentProposalOptions options) {
  bool positive(double value) => value.isFinite && value > 0.0;
  return positive(options.cornerCurvaturePerMeter) &&
      positive(options.minimumCornerTurnRadians) &&
      positive(options.connectedStraightMeters) &&
      positive(options.certainStraightMeters) &&
      options.certainStraightMeters >= options.connectedStraightMeters;
}

void _addReason(List<String> reasons, String reason) {
  if (!reasons.contains(reason)) reasons.add(reason);
}

TrackSegmentProposals _unresolved(SegmentProposalOptions options, String reason) =>
    TrackSegmentProposals(options: options, unresolvedReason: reason, valid: true);

final class _Piece {
  _Piece(this.run, this.start);

  _Run run;
  final SegmentProposalBoundary start;
}

/// Classifies [axis]'s smoothed curvature into alternating corner and straight
/// proposals. [features] must come from `computeTrackFeatures(axis, ...)`.
/// [gpsGaps] are progress ranges where the analysed lap lacks GPS coverage;
/// boundaries within tolerance of a gap are marked uncertain.
///
/// Returns `valid == false` for invalid inputs. Proposals carry no ids or
/// approval state.
TrackSegmentProposals proposeTrackSegments(
  ProgressAxis axis,
  TrackFeatures features, [
  List<ProgressRange> gpsGaps = const [],
  SegmentProposalOptions options = const SegmentProposalOptions(),
]) {
  final invalid = TrackSegmentProposals(options: options);
  if (!axis.valid ||
      !features.valid ||
      axis.points.length < 4 ||
      features.samples.length != axis.points.length ||
      !(axis.spacingMeters > 0.0) ||
      !axis.lengthMeters.isFinite ||
      axis.lengthMeters <= 0.0 ||
      !_validOptions(options) ||
      gpsGaps.length > maximumProposalGpsGaps) {
    return invalid;
  }
  final length = axis.lengthMeters;
  for (final gap in gpsGaps) {
    if (!gap.startMeters.isFinite ||
        !gap.endMeters.isFinite ||
        gap.startMeters < 0.0 ||
        gap.endMeters < 0.0 ||
        gap.startMeters > length ||
        gap.endMeters > length) {
      return invalid;
    }
  }

  final samples = features.samples;
  final n = samples.length;
  final spacing = axis.spacingMeters;
  final labels = List<int>.filled(n, 0);
  for (var i = 0; i < n; ++i) {
    final curvature = samples[i].curvaturePerMeter;
    if (!curvature.isFinite) return invalid;
    if (curvature.abs() >= options.cornerCurvaturePerMeter) labels[i] = curvature > 0.0 ? 1 : -1;
  }
  double turnOf(_Run run) {
    var turn = 0.0;
    for (var k = 0; k < run.count; ++k) {
      turn += samples[(run.first + k) % n].curvaturePerMeter * spacing;
    }
    return turn;
  }

  TrackSegmentProposals unsplittable(List<int> current) =>
      _unresolved(options, current.first == 0 ? 'noCorners' : 'continuousCorner');

  var runs = _circularRuns(labels);
  if (runs.isEmpty) return unsplittable(labels);
  // A turning run too small to be a corner is a kink: fold it into the straight.
  for (final run in runs) {
    if (run.label != 0 && turnOf(run).abs() < options.minimumCornerTurnRadians) {
      for (var k = 0; k < run.count; ++k) {
        labels[(run.first + k) % n] = 0;
      }
    }
  }
  runs = _circularRuns(labels);
  if (runs.isEmpty) return unsplittable(labels);

  final tolerance = features.smoothingMeters + spacing;
  final pieces = [
    for (final run in runs)
      _Piece(
        _Run(run.label, run.first, run.count),
        SegmentProposalBoundary(samples[run.first].progressMeters, tolerance),
      ),
  ];
  final m = pieces.length;
  for (var k = 0; k < m; ++k) {
    final run = pieces[k].run;
    final straightLength = run.count * spacing;
    if (run.label == 0 &&
        straightLength >= options.connectedStraightMeters &&
        straightLength < options.certainStraightMeters) {
      _addReason(pieces[k].start.uncertaintyReasons, proposalUncertainShortStraight);
      _addReason(pieces[(k + 1) % m].start.uncertaintyReasons, proposalUncertainShortStraight);
    }
  }

  // A straight too short to stand on its own is not proposed. Corners with no
  // proposed straight between them (an S-bend, or a straight shorter than
  // connectedStraightMeters) form one corner chain.
  var anchor = -1;
  for (var k = 0; k < m && anchor < 0; ++k) {
    final run = pieces[k].run;
    if (run.label == 0 && run.count * spacing >= options.connectedStraightMeters) anchor = k;
  }
  if (anchor < 0) return _unresolved(options, 'continuousCorner');
  final kept = <_Piece>[];
  final chained = <int>[];
  for (var step = 0; step < m; ++step) {
    final piece = pieces[(anchor + step) % m];
    final straightPiece = piece.run.label == 0;
    final proposedStraight =
        straightPiece && piece.run.count * spacing >= options.connectedStraightMeters;
    if (proposedStraight || kept.isEmpty || kept.last.run.label == 0) {
      // A copy: the chain below extends the kept run, never the piece's own.
      kept.add(
        _Piece(_Run(piece.run.label, piece.run.first, piece.run.count), piece.start._copy()),
      );
      chained.add(straightPiece ? 0 : 1);
      continue;
    }
    if (options.splitCornerChains && !straightPiece) {
      // The next corner of the chain stands on its own; the stretch before
      // it stays with the corner it follows.
      final start = piece.start._copy();
      _addReason(start.uncertaintyReasons, proposalUncertainConnectedCorners);
      kept.add(_Piece(_Run(piece.run.label, piece.run.first, piece.run.count), start));
      chained.add(1);
      continue;
    }
    // Extend the current chain (its label stays non-zero: it is a corner).
    kept.last.run.count += piece.run.count;
    if (!straightPiece) ++chained[chained.length - 1];
  }
  if (kept.length < 2) return _unresolved(options, 'continuousCorner');
  if (kept.length > maximumTrackSegments) return _unresolved(options, 'tooManySegments');

  for (final piece in kept) {
    for (final gap in gpsGaps) {
      if (_nearRange(piece.start.progressMeters, gap, tolerance, length)) {
        _addReason(piece.start.uncertaintyReasons, proposalUncertainGpsGap);
        break;
      }
    }
  }

  // Order by start progress so only the final proposal can wrap the gate
  // (the first smallest start, as std::min_element picks it).
  var rotation = 0;
  for (var k = 1; k < kept.length; ++k) {
    if (kept[k].start.progressMeters < kept[rotation].start.progressMeters) rotation = k;
  }
  final ordered = [...kept.sublist(rotation), ...kept.sublist(0, rotation)];
  final orderedChained = [...chained.sublist(rotation), ...chained.sublist(0, rotation)];

  final proposals = <TrackSegmentProposal>[];
  final count = ordered.length;
  var cornerNumber = 0;
  var straightNumber = 0;
  for (var k = 0; k < count; ++k) {
    final piece = ordered[k];
    final start = piece.start._copy();
    final end = ordered[(k + 1) % count].start._copy();
    // The loop closes at progress 0 only when the first boundary sits exactly on the gate.
    if (k == count - 1 && end.progressMeters == 0.0) end.progressMeters = length;
    final span = end.progressMeters - start.progressMeters;
    final lengthMeters = span > 0.0 ? span : span + length;
    if (piece.run.label == 0) {
      proposals.add(
        TrackSegmentProposal(
          type: TrackSegmentType.straight,
          name: 'Straight ${++straightNumber}',
          start: start,
          end: end,
          lengthMeters: lengthMeters,
        ),
      );
      continue;
    }
    final links = orderedChained[k];
    final firstCorner = cornerNumber + 1;
    cornerNumber += links;
    var peak = 0.0;
    for (var j = 0; j < piece.run.count; ++j) {
      final curvature = samples[(piece.run.first + j) % n].curvaturePerMeter;
      if (curvature.abs() > peak.abs()) peak = curvature;
    }
    proposals.add(
      TrackSegmentProposal(
        type: TrackSegmentType.corner,
        name: links > 1 ? 'Corners $firstCorner–$cornerNumber' : 'Corner $firstCorner',
        start: start,
        end: end,
        lengthMeters: lengthMeters,
        turnRadians: turnOf(piece.run),
        peakCurvaturePerMeter: peak,
        chainedCorners: links,
      ),
    );
  }
  return TrackSegmentProposals(proposals: proposals, options: options, valid: true);
}

/// [proposals] as ordinary editable track segments with fresh ids, for the
/// configuration [trackConfigurationReference]. Uncertainty is not stored.
/// Empty for invalid or unresolved proposals, or when the result would not
/// validate.
List<Map<String, Object?>> proposalsToTrackSegments(
  TrackSegmentProposals proposals,
  String trackConfigurationReference, {
  math.Random? random,
}) {
  if (!proposals.valid || proposals.proposals.isEmpty) return [];
  final segments = <Map<String, Object?>>[];
  for (final proposal in proposals.proposals) {
    final segment = makeTrackSegment(
      proposal.type,
      proposal.name,
      proposal.start.progressMeters,
      proposal.end.progressMeters,
      trackConfigurationReference,
      random: random,
    );
    if (segment.isEmpty) return [];
    segments.add(segment);
  }
  return validTrackSegments(segments) ? segments : [];
}
