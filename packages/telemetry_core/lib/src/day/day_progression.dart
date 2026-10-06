// Port of summarizeOutingProgression in FlappedEar Overlays
// native/src/telemetry/OutingLaps.cpp and of the lap consistency of
// AnalysisController::outingLapConsistency (revision d4d1039, FET-35): each
// run's best lap and lap-time quartiles in recording order, and how
// repeatable the group's lap times are, over the same eligible laps as the
// ranking. Overlays' OutingProgressionDialog.qml shows them.
import '../analysis/consistency.dart';
import '../analysis/outing_results.dart';
import '../intake/import_plan.dart';
import '../operation.dart';
import 'compatibility.dart';
import 'day_analysis.dart';
import 'day_laps.dart';
import 'day_ranking.dart';
import 'run_setup.dart';

/// Whether a run of the progression has a result.
enum ProgressionRunState {
  available,

  /// It has laps in the group, but none is eligible.
  noEligibleLaps,

  /// It belongs to the group but has no lap section (no recording).
  noRecordedLaps,
}

/// One run in the progression.
final class ProgressionRun {
  ProgressionRun({
    required this.run,
    required this.state,
    this.lapCount = 0,
    this.eligibleLapCount = 0,
    this.tieCount = 0,
    this.bestLap,
    this.distribution,
    List<ExcludedLap> excludedLaps = const [],
    this.firstSectionUtcMilliseconds,
    this.bestDeltaPreviousListedSeconds,
    this.previousListedRunName,
  }) : excludedLaps = List.unmodifiable(excludedLaps);

  final ProgressionRunInfo run;
  final ProgressionRunState state;

  /// Timed laps of the run.
  final int lapCount;
  final int eligibleLapCount;
  final int tieCount;
  final DayLapRow? bestLap;

  /// Lap-time quartiles of its eligible laps.
  final LapDistribution? distribution;

  /// Its laps the ranking leaves out, with why.
  final List<ExcludedLap> excludedLaps;

  /// The recording clock of its first section (UTC), when known.
  final int? firstSectionUtcMilliseconds;

  /// Its best lap minus the best lap of the run listed before it, when both
  /// have one. A run without an eligible lap breaks the comparison.
  final double? bestDeltaPreviousListedSeconds;
  final String? previousListedRunName;

  String get runId => run.id;
  String get runName => run.name;
  bool get chronologyKnown => firstSectionUtcMilliseconds != null;
}

/// The runs of one group in recording order (Overlays' run progression).
final class DayProgression {
  DayProgression({
    required this.groupId,
    required this.state,
    List<ProgressionRun> runs = const [],
    this.lapCount = 0,
    this.eligibleLapCount = 0,
    this.minimumSeconds,
    this.maximumSeconds,
  }) : runs = List.unmodifiable(runs);

  final String? groupId;
  final DayRankingState state;

  /// Runs with a recording clock first, by clock; the others after them in
  /// the day's order.
  final List<ProgressionRun> runs;
  final int lapCount;
  final int eligibleLapCount;

  /// The quickest and slowest eligible lap of any run: a shared time scale.
  final double? minimumSeconds, maximumSeconds;
}

/// The progression of [ranking]'s group over the day's [rows] (any group:
/// a run's clock is its earliest section). [runs] are the day's runs in
/// order with their context; those whose [configurations] put them in the
/// group are listed.
DayProgression summarizeDayProgression(
  List<DayLapRow> rows,
  DayRanking ranking,
  List<ProgressionRunInfo> runs,
  Map<String, TrackConfiguration> configurations,
) {
  if (rows.length > maximumDayLapRows || runs.length > 64) {
    throw const ResourceLimitError('Too many runs or lap sections for progression.');
  }
  final group = ranking.groupId;
  DayProgression empty() => DayProgression(
    groupId: group,
    state: ranking.state,
    lapCount: ranking.lapCount,
    eligibleLapCount: ranking.eligibleLapCount,
  );
  if (group == null || group.isEmpty || ranking.state == DayRankingState.selectionRequired) {
    return empty();
  }
  final ranked = {for (final run in ranking.runs) run.runId: run};
  final excluded = <String, List<ExcludedLap>>{};
  for (final lap in ranking.excludedLaps) {
    (excluded[lap.row.runId] ??= []).add(lap);
  }
  final clocks = <String, int>{};
  for (final row in rows) {
    final clock = row.timestampMilliseconds;
    if (clock == null) continue;
    final current = clocks[row.runId];
    if (current == null || clock < current) clocks[row.runId] = clock;
  }
  double? minimum, maximum;
  final listed = <(ProgressionRun, int)>[];
  for (var i = 0; i < runs.length; ++i) {
    final info = runs[i];
    if (configurations[info.id]?.compatibilityGroupId != group) continue;
    final run = ranked[info.id];
    final distribution = run?.distribution;
    if (distribution != null) {
      if (minimum == null || distribution.minimum < minimum) minimum = distribution.minimum;
      if (maximum == null || distribution.maximum > maximum) maximum = distribution.maximum;
    }
    listed.add((
      ProgressionRun(
        run: info,
        state: run == null
            ? ProgressionRunState.noRecordedLaps
            : run.available
            ? ProgressionRunState.available
            : ProgressionRunState.noEligibleLaps,
        lapCount: run?.lapCount ?? 0,
        eligibleLapCount: run?.eligibleLapCount ?? 0,
        tieCount: run?.tieCount ?? 0,
        bestLap: run?.bestLap,
        distribution: distribution,
        excludedLaps: excluded[info.id] ?? const [],
        firstSectionUtcMilliseconds: clocks[info.id],
      ),
      i,
    ));
  }
  listed.sort((a, b) {
    final clockA = a.$1.firstSectionUtcMilliseconds, clockB = b.$1.firstSectionUtcMilliseconds;
    if ((clockA == null) != (clockB == null)) return clockA != null ? -1 : 1;
    if (clockA != null && clockA != clockB) return clockA.compareTo(clockB!);
    return a.$2.compareTo(b.$2);
  });
  final published = <ProgressionRun>[];
  ProgressionRun? previous;
  for (final (run, _) in listed) {
    final best = run.bestLap, previousBest = previous?.bestLap;
    final item = ProgressionRun(
      run: run.run,
      state: run.state,
      lapCount: run.lapCount,
      eligibleLapCount: run.eligibleLapCount,
      tieCount: run.tieCount,
      bestLap: run.bestLap,
      distribution: run.distribution,
      excludedLaps: run.excludedLaps,
      firstSectionUtcMilliseconds: run.firstSectionUtcMilliseconds,
      bestDeltaPreviousListedSeconds: best != null && previousBest != null
          ? best.durationSeconds - previousBest.durationSeconds
          : null,
      previousListedRunName: previous?.runName,
    );
    published.add(item);
    previous = item;
  }
  return DayProgression(
    groupId: group,
    state: ranking.state,
    runs: published,
    lapCount: ranking.lapCount,
    eligibleLapCount: ranking.eligibleLapCount,
    minimumSeconds: minimum,
    maximumSeconds: maximum,
  );
}

/// One run's lap-time consistency.
final class RunLapConsistency {
  const RunLapConsistency({required this.runId, required this.runName, required this.laps});

  final String runId;
  final String runName;
  final ConsistencySummary laps;
}

/// How repeatable a group's lap times are: over the day and per run.
final class LapConsistency {
  LapConsistency({
    this.day = const ConsistencySummary(unavailableReason: consistencyTooFewSamples),
    List<RunLapConsistency> runs = const [],
  }) : runs = List.unmodifiable(runs);

  final ConsistencySummary day;

  /// In the order their first eligible lap was recorded.
  final List<RunLapConsistency> runs;
}

/// The lap-time median and interquartile range of [eligible] (eligible laps
/// in recording order), over the day and per run; unavailable below three
/// laps.
LapConsistency summarizeLapConsistency(List<DayLapRow> eligible) {
  final byRun = <String, List<double>>{};
  final names = <String, String>{};
  for (final row in eligible) {
    (byRun[row.runId] ??= []).add(row.durationSeconds);
    names[row.runId] = row.runName;
  }
  return LapConsistency(
    day: summarizeConsistency([for (final row in eligible) row.durationSeconds]),
    runs: [
      for (final entry in byRun.entries)
        RunLapConsistency(
          runId: entry.key,
          runName: names[entry.key]!,
          laps: summarizeConsistency(entry.value),
        ),
    ],
  );
}

/// The day's runs with their names, and the notes, conditions, setup
/// changes and structured setup a day document (`event.runs`) records for
/// them.
List<ProgressionRunInfo> progressionRunInfo(
  List<NamedRun> runs, {
  Iterable<Object?> documentRuns = const [],
}) {
  final stored = <String, Map<String, Object?>>{
    for (final value in documentRuns)
      if (value case final Map<String, Object?> run when run['id'] is String)
        run['id'] as String: run,
  };
  String? text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
  return [
    for (final named in runs)
      ProgressionRunInfo(
        id: named.run.id,
        name: named.name,
        notes: text(stored[named.run.id]?['notes']),
        conditions: text(stored[named.run.id]?['conditions']),
        setupChanges: text(stored[named.run.id]?['setupChanges']),
        setup: switch (RunSetup.fromJson(stored[named.run.id]?[runSetupKey])) {
          final setup when setup.isEmpty => null,
          final setup => setup,
        },
      ),
  ];
}

/// The eligible laps of [groupId] (by default the group shown) in
/// recording order.
List<DayLapRow> dayEligibleLaps(DayAnalysis analysis, {String? groupId}) {
  final ranking = _group(analysis, groupId)?.ranking;
  if (ranking == null) return const [];
  final eligible = {for (final lap in ranking.eligibleLaps) lap.reference};
  return [
    for (final row in analysis.rows)
      if (eligible.contains(row.reference)) row,
  ];
}

DayGroup? _group(DayAnalysis analysis, String? groupId) {
  final id = groupId ?? analysis.chosenGroupId;
  for (final group in analysis.groups) {
    if (group.id == id && group.resolved) return group;
  }
  return null;
}

/// The progression of [groupId] (by default the group shown) in [analysis];
/// [runs] are the day's runs in order ([progressionRunInfo]).
DayProgression dayProgression(
  DayAnalysis analysis,
  List<ProgressionRunInfo> runs, {
  String? groupId,
}) {
  final ranking = _group(analysis, groupId)?.ranking;
  if (ranking == null) {
    return DayProgression(groupId: null, state: DayRankingState.selectionRequired);
  }
  return summarizeDayProgression(analysis.rows, ranking, runs, analysis.configurations);
}

/// The lap consistency of [groupId] (by default the group shown).
LapConsistency dayLapConsistency(DayAnalysis analysis, {String? groupId}) =>
    summarizeLapConsistency(dayEligibleLaps(analysis, groupId: groupId));

/// [dayProgression] of every resolved group, by group id.
Map<String, DayProgression> dayProgressions(DayAnalysis analysis, List<ProgressionRunInfo> runs) =>
    {
      for (final group in analysis.groups)
        if (group.resolved) group.id: dayProgression(analysis, runs, groupId: group.id),
    };

/// [dayLapConsistency] of every resolved group, by group id.
Map<String, LapConsistency> dayLapConsistencies(DayAnalysis analysis) => {
  for (final group in analysis.groups)
    if (group.resolved) group.id: dayLapConsistency(analysis, groupId: group.id),
};
