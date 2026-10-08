// Port of rankOutingLaps and eligibleOutingLaps in VBOOverlay
// native/src/telemetry/OutingLaps.cpp (FET-21): the best laps of a day within
// one compatibility group.
import '../operation.dart';
import 'compatibility.dart';
import 'day_laps.dart';

/// Whether a ranking has a result.
enum DayRankingState {
  /// No compatibility group is chosen.
  selectionRequired,

  /// The group has laps but none is eligible.
  noEligibleLaps,
  available,
}

/// Lap-time quartiles of one run, interpolated linearly.
final class LapDistribution {
  const LapDistribution({
    required this.minimum,
    required this.q1,
    required this.median,
    required this.q3,
    required this.maximum,
  });

  final double minimum;
  final double q1;
  final double median;
  final double q3;
  final double maximum;
}

/// A lap of the group that is not ranked, and why.
final class ExcludedLap {
  const ExcludedLap({required this.row, required this.issues, this.userReason = ''});

  final DayLapRow row;
  final List<LapIssue> issues;

  /// The reason the user gave when they excluded the lap.
  final String userReason;
}

/// One run's result within the group.
final class RunRanking {
  const RunRanking({
    required this.runId,
    required this.runName,
    required this.lapCount,
    required this.eligibleLapCount,
    required this.tieCount,
    this.bestLap,
    this.distribution,
  });

  final String runId;
  final String runName;

  /// Timed laps of the run.
  final int lapCount;
  final int eligibleLapCount;

  /// Eligible laps exactly as fast as [bestLap], itself included.
  final int tieCount;
  final DayLapRow? bestLap;
  final LapDistribution? distribution;

  bool get available => bestLap != null;
}

/// The ranking of one compatibility group.
final class DayRanking {
  DayRanking({
    required this.groupId,
    required this.state,
    this.bestOfDay,
    List<RunRanking> runs = const [],
    List<ExcludedLap> excludedLaps = const [],
    List<DayLapRow> eligibleLaps = const [],
    this.lapCount = 0,
    this.tieCount = 0,
  }) : runs = List.unmodifiable(runs),
       excludedLaps = List.unmodifiable(excludedLaps),
       eligibleLaps = List.unmodifiable(eligibleLaps);

  final String? groupId;
  final DayRankingState state;
  final DayLapRow? bestOfDay;

  /// Runs with an eligible lap first, fastest first; then the others.
  final List<RunRanking> runs;
  final List<ExcludedLap> excludedLaps;

  /// Eligible laps, fastest first.
  final List<DayLapRow> eligibleLaps;
  final int lapCount;
  final int tieCount;

  int get eligibleLapCount => eligibleLaps.length;
}

/// Orders laps by duration, then clock (unknown last), run, start and end.
/// Source order, names and lap numbers never break a tie.
int compareRankedLaps(DayLapRow a, DayLapRow b) {
  final durationA = a.durationSeconds, durationB = b.durationSeconds;
  if (durationA != durationB) return durationA < durationB ? -1 : 1;
  final clockA = a.timestampMilliseconds, clockB = b.timestampMilliseconds;
  if (clockA != clockB) {
    if (clockA == null) return 1;
    if (clockB == null) return -1;
    return clockA.compareTo(clockB);
  }
  if (a.runId != b.runId) return a.runId.compareTo(b.runId);
  if (a.start != b.start) return a.start.compareTo(b.start);
  return a.end.compareTo(b.end);
}

/// Why [row], a timed lap of a run with [configuration], is not eligible;
/// empty when it is. The one eligibility rule behind the ranking and every
/// later consumer of the eligible laps.
List<LapIssue> dayLapIssues(
  DayLapRow row,
  TrackConfiguration configuration, {
  String userExclusionReason = '',
  bool staleSource = false,
}) {
  final issues = lapCompatibilityIssues(
    configuration,
    issue: row.referenceIssue,
    userExcluded: userExclusionReason.isNotEmpty,
  );
  if (row.offRoute) issues.add(LapIssue.differentRecordedRoute);
  if (row.shortForGroup && !issues.contains(LapIssue.implausibleLap)) {
    issues.add(LapIssue.implausibleLap);
  }
  if (staleSource) issues.add(LapIssue.staleSource);
  if (row.type != LapSectionType.lap) {
    issues.add(LapIssue.notTimedLap);
  } else if (!row.referenceEligible && issues.isEmpty) {
    issues.add(LapIssue.ineligibleLap);
  }
  return issues;
}

void _checkLimits(List<DayLapRow> rows, Map<DayLapReference, String> exclusions) {
  if (rows.length > maximumDayLapRows || exclusions.length > maximumDayLapRows) {
    throw const ResourceLimitError('Too many laps or exclusions to rank this day.');
  }
}

/// The timed laps of [groupId] that may be ranked and compared, in row order.
/// Empty without a group.
List<DayLapRow> eligibleDayLaps(
  List<DayLapRow> rows,
  String? groupId,
  Map<String, TrackConfiguration> configurations, {
  Map<DayLapReference, String> exclusions = const {},
  Set<String> staleRunIds = const {},
}) {
  if (groupId == null || groupId.isEmpty) return const [];
  _checkLimits(rows, exclusions);
  final groups = <String, String?>{};
  return [
    for (final row in rows)
      if (row.type == LapSectionType.lap &&
          groups.putIfAbsent(row.runId, () => configurations[row.runId]?.compatibilityGroupId) ==
              groupId &&
          dayLapIssues(
            row,
            configurations[row.runId]!,
            userExclusionReason: exclusions[row.reference] ?? '',
            staleSource: staleRunIds.contains(row.runId),
          ).isEmpty)
        row,
  ];
}

/// Ranks the timed laps of [groupId]: the best of the day, each run's best
/// and quartiles, and every lap left out with its reasons.
DayRanking rankDayLaps(
  List<DayLapRow> rows,
  String? groupId,
  Map<String, TrackConfiguration> configurations, {
  Map<DayLapReference, String> exclusions = const {},
  Set<String> staleRunIds = const {},
}) {
  if (groupId == null || groupId.isEmpty) {
    return DayRanking(groupId: null, state: DayRankingState.selectionRequired);
  }
  _checkLimits(rows, exclusions);
  final groups = <String, String?>{};
  final runNames = <String, String>{};
  final runLapCounts = <String, int>{};
  final runEligible = <String, List<DayLapRow>>{};
  final eligible = <DayLapRow>[];
  final excluded = <ExcludedLap>[];
  for (final row in rows) {
    final group = groups.putIfAbsent(
      row.runId,
      () => configurations[row.runId]?.compatibilityGroupId,
    );
    if (group != groupId) continue;
    runNames.putIfAbsent(row.runId, () => row.runName);
    runEligible.putIfAbsent(row.runId, () => []);
    if (row.type != LapSectionType.lap) continue;
    runLapCounts[row.runId] = (runLapCounts[row.runId] ?? 0) + 1;
    final userReason = exclusions[row.reference] ?? '';
    final issues = dayLapIssues(
      row,
      configurations[row.runId]!,
      userExclusionReason: userReason,
      staleSource: staleRunIds.contains(row.runId),
    );
    if (issues.isEmpty) {
      eligible.add(row);
      runEligible[row.runId]!.add(row);
    } else {
      excluded.add(ExcludedLap(row: row, issues: issues, userReason: userReason));
    }
  }
  eligible.sort(compareRankedLaps);
  for (final laps in runEligible.values) {
    laps.sort(compareRankedLaps);
  }
  final runOrder = runEligible.keys.toList()
    ..sort((a, b) {
      final left = runEligible[a]!, right = runEligible[b]!;
      if (left.isEmpty != right.isEmpty) return left.isEmpty ? 1 : -1;
      if (left.isEmpty) return a.compareTo(b);
      return compareRankedLaps(left.first, right.first);
    });

  int ties(List<DayLapRow> laps) {
    if (laps.isEmpty) return 0;
    final best = laps.first.durationSeconds;
    return laps.where((lap) => lap.durationSeconds == best).length;
  }

  var lapCount = 0;
  final runs = <RunRanking>[];
  for (final id in runOrder) {
    final laps = runEligible[id]!;
    final count = runLapCounts[id] ?? 0;
    lapCount += count;
    runs.add(
      RunRanking(
        runId: id,
        runName: runNames[id]!,
        lapCount: count,
        eligibleLapCount: laps.length,
        tieCount: ties(laps),
        bestLap: laps.isEmpty ? null : laps.first,
        distribution: laps.isEmpty ? null : _distribution(laps),
      ),
    );
  }
  return DayRanking(
    groupId: groupId,
    state: eligible.isEmpty ? DayRankingState.noEligibleLaps : DayRankingState.available,
    bestOfDay: eligible.isEmpty ? null : eligible.first,
    runs: runs,
    excludedLaps: excluded,
    eligibleLaps: eligible,
    lapCount: lapCount,
    tieCount: ties(eligible),
  );
}

LapDistribution _distribution(List<DayLapRow> sorted) {
  double quantile(double fraction) {
    final position = fraction * (sorted.length - 1);
    final lower = position.floor(), upper = position.ceil();
    final a = sorted[lower].durationSeconds, b = sorted[upper].durationSeconds;
    return a + (b - a) * (position - lower);
  }

  return LapDistribution(
    minimum: quantile(0.0),
    q1: quantile(0.25),
    median: quantile(0.5),
    q3: quantile(0.75),
    maximum: quantile(1.0),
  );
}
