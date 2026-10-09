// The Corner Analyzer of two laps of a day (FET-38), as Overlays'
// AnalysisControllerCornerAnalyzer.cpp resolves its segments
// (comparisonApprovedSegmentation, comparisonSharedSegmentation) and
// AnalysisControllerTheoreticalBest.cpp opens it from a theoretical-best
// sector (openTheoreticalBestSector): each lap's run's approved segments for
// its track configuration, used only when both are the same revision, or,
// when opened from the theoretical best, the segments that result used.
import '../analysis/corner_analyzer.dart';
import '../analysis/track_segment_review.dart';
import 'day_analysis.dart';
import 'day_comparison.dart';
import 'day_laps.dart';
import 'day_theoretical_best.dart';

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

/// [row]'s run's approved segments for its track configuration, from the
/// day document's `event.runs` ([documentRuns]).
ApprovedSegmentation dayRunApprovedSegmentation(
  DayAnalysis analysis,
  Iterable<Object?> documentRuns,
  DayLapRow row,
) {
  final configuration = analysis.configurations[row.runId]?.compatibilityGroupId ?? '';
  for (final value in documentRuns) {
    final run = _object(value);
    if (run != null && run['id'] == row.runId) {
      return approvedSegmentation(run['trackSegments'], configuration);
    }
  }
  return ApprovedSegmentation(trackConfigurationReference: configuration);
}

/// How many stored segments the day keeps that no run uses: each is saved
/// under a route group the run no longer belongs to (FET-267). A group that
/// merged into another, or split, gets a new id, and the corners kept under
/// the old one are left in the document, unused, until the driver sets the
/// corners again.
int dayUnusedStoredSegments(DayAnalysis analysis, Iterable<Object?> documentRuns) {
  var unused = 0;
  for (final value in documentRuns) {
    final run = _object(value);
    final id = run?['id'];
    if (run == null || id is! String) continue;
    final configuration = analysis.configurations[id]?.compatibilityGroupId;
    if (configuration == null) continue;
    unused += approvedSegmentation(run['trackSegments'], configuration).otherConfigurationSegments;
  }
  return unused;
}

/// The segments laps [a] and [b] are compared on. With [theoreticalBest]
/// (the comparison was opened from it) and both laps in its group, its
/// segments are used when the laps' own differ.
ComparisonSegmentation dayComparisonSegmentation(
  DayAnalysis analysis,
  DayLapRow a,
  DayLapRow b, {
  Iterable<Object?> documentRuns = const [],
  DayTheoreticalBest? theoreticalBest,
}) {
  final computed = theoreticalBest?.computed;
  final ready =
      theoreticalBest != null &&
      theoreticalBest.state == DayTheoreticalBestState.ready &&
      computed != null &&
      computed.error.isEmpty;
  final groupA = dayLapGroupId(analysis, a) ?? '';
  return comparisonSharedSegmentation(
    dayRunApprovedSegmentation(analysis, documentRuns, a),
    dayRunApprovedSegmentation(analysis, documentRuns, b),
    canonical: ready && theoreticalBest.groupId == groupA ? computed.approved : null,
    groupA: groupA,
    groupB: dayLapGroupId(analysis, b) ?? '',
  );
}

/// The two laps to compare through segment [segmentId] of [result]: [lap]
/// against the group's best lap; for the best lap itself (or without
/// [lap]), as Overlays opens a theoretical-best sector, the lap that set the
/// segment's fastest time against the best lap, or, when that is the best
/// lap, the best lap against the next fastest through the segment. Null
/// when there is no such pair.
(DayLapRow, DayLapRow)? dayTheoreticalBestSectorPair(
  DayTheoreticalBest result,
  String segmentId, {
  DayLapRow? lap,
}) {
  final best = result.bestLap;
  if (result.state != DayTheoreticalBestState.ready || best == null) return null;
  DayLapRow? row(Object? reference) {
    for (final timed in result.laps) {
      if (timed.lap.reference == reference) return timed.lap;
    }
    return null;
  }

  if (lap != null && lap.reference != best.reference && row(lap.reference) != null) {
    return (lap, best);
  }
  final sector = result.segments.where((sector) => sector.segmentId == segmentId).firstOrNull;
  if (sector == null || sector.seconds == null) return null;
  final donor = row(sector.sourceLapReference);
  if (donor == null) return null;
  if (donor.reference != best.reference) return (donor, best);
  DayLapRow? next;
  double? nextSeconds;
  for (final timed in result.laps) {
    if (timed.lap.reference == best.reference) continue;
    final seconds = timed.times.sector(segmentId)?.seconds;
    if (seconds == null) continue;
    if (nextSeconds == null || seconds < nextSeconds) {
      nextSeconds = seconds;
      next = timed.lap;
    }
  }
  return next == null ? null : (best, next);
}
