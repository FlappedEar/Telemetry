// Choosing the two laps of an A/B comparison on a day (FET-37), as Overlays'
// AnalysisControllerComparison.cpp does: A and B are eligible laps of one
// compatible group; B can be set to the best lap of A's session or of the
// group, and the two can be swapped.
import '../analysis/lap_comparison.dart';
import '../intake/import_plan.dart';
import 'day_analysis.dart';
import 'day_laps.dart';
import 'day_progression.dart';

/// [row]'s lap for a comparison, from its run in [runs]; null for a section
/// that is not a timed lap or a run that is not there.
ComparisonLap? dayComparisonLap(List<NamedRun> runs, DayLapRow row) {
  if (row.type != LapSectionType.lap) return null;
  for (final named in runs) {
    if (named.run.id != row.runId) continue;
    return ComparisonLap(
      session: named.run.telemetry,
      laps: named.run.laps,
      start: row.start,
      end: row.end,
      lapNumber: row.lapNumber,
    );
  }
  return null;
}

/// The compatibility group of [row], or null when its circuit is not
/// resolved.
String? dayLapGroupId(DayAnalysis analysis, DayLapRow row) {
  final id = analysis.configurations[row.runId]?.compatibilityGroupId;
  for (final group in analysis.groups) {
    if (group.id == id && group.resolved) return id;
  }
  return null;
}

/// The laps that can be compared with [row]: the eligible laps of its group,
/// in recording order (the group shown when [row] is null).
List<DayLapRow> dayComparisonCandidates(DayAnalysis analysis, [DayLapRow? row]) {
  final groupId = row == null ? analysis.chosenGroupId : dayLapGroupId(analysis, row);
  if (groupId == null) return const [];
  return dayEligibleLaps(analysis, groupId: groupId);
}

/// Whether [a] and [b] can be compared: two different eligible laps of one
/// group.
bool dayLapsComparable(DayAnalysis analysis, DayLapRow a, DayLapRow b) {
  if (a.reference == b.reference) return false;
  final candidates = dayComparisonCandidates(analysis, a);
  return candidates.any((row) => row.reference == a.reference) &&
      candidates.any((row) => row.reference == b.reference);
}

/// The best lap of [row]'s group, or with [sameRun] of its session; null
/// when there is none.
DayLapRow? dayBestComparisonLap(DayAnalysis analysis, DayLapRow row, {bool sameRun = false}) {
  final groupId = dayLapGroupId(analysis, row);
  for (final group in analysis.groups) {
    if (group.id != groupId) continue;
    final ranking = group.ranking;
    if (ranking == null) return null;
    if (!sameRun) return ranking.bestOfDay;
    for (final run in ranking.runs) {
      if (run.runId == row.runId) return run.bestLap;
    }
  }
  return null;
}
