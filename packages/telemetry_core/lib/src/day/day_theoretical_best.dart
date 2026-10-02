// A day's theoretical best per compatibility group (FET-32), as Overlays'
// AnalysisControllerTheoreticalBest.cpp requests it and its
// TheoreticalBestDialog and TimeLossDialog show it: every eligible lap of the
// group timed against the approved segments on one shared axis, the fastest
// time of each segment, the time the best lap leaves (its own sector sum
// minus the theoretical best), and each lap's loss to the fastest time of
// every segment.
import 'dart:math' as math;

import '../analysis/automatic_segments.dart';
import '../analysis/outing_theoretical_best.dart';
import '../analysis/sector_timing.dart';
import '../analysis/time_loss.dart';
import '../analysis/track_progress.dart';
import '../intake/import_plan.dart';
import '../operation.dart';
import 'day_analysis.dart';
import 'day_laps.dart';

/// Whether a group's theoretical best was calculated.
enum DayTheoreticalBestState {
  /// Calculated; [DayTheoreticalBest.message] says when the total is
  /// withheld.
  ready,

  /// Nothing to calculate from: no group, no eligible lap, no segments.
  unavailable,

  /// The calculation failed.
  error,
}

/// One eligible lap of the group in the sector table.
final class DayLapSectors {
  DayLapSectors({
    required this.lap,
    required this.times,
    required List<double?> lossSeconds,
    this.bestOfDay = false,
  }) : lossSeconds = List.unmodifiable(lossSeconds);

  final DayLapRow lap;

  /// Its time through every approved segment, in approved order.
  final LapSectorTimes times;

  /// Its time minus the fastest time, per segment in approved order: the
  /// loss map. Null where either is untimed.
  final List<double?> lossSeconds;

  /// The group's best lap.
  final bool bestOfDay;

  /// Its time through segment [index], or null.
  double? seconds(int index) => times.sectors[index].seconds;

  /// The sum of [lossSeconds] when every segment is timed.
  double? get totalLossSeconds {
    var total = 0.0;
    for (final loss in lossSeconds) {
      if (loss == null) return null;
      total += loss;
    }
    return total;
  }
}

/// A group's theoretical best, or why there is none.
final class DayTheoreticalBest {
  DayTheoreticalBest({
    required this.groupId,
    required this.state,
    this.message = '',
    this.computed,
    this.summary,
    List<DayLapSectors> laps = const [],
    this.bestLap,
    this.automaticSegments = false,
  }) : laps = List.unmodifiable(laps);

  final String groupId;
  final DayTheoreticalBestState state;

  /// Why there is no result, or why its total is withheld.
  final String message;
  final OutingTheoreticalBest? computed;

  /// What Overlays' theoretical-best dialog shows.
  final TheoreticalBestSummary? summary;

  /// Every lap timed, in recording order.
  final List<DayLapSectors> laps;

  /// The group's best lap.
  final DayLapRow? bestLap;

  /// The segments were proposed from the best lap now because the day has
  /// none for this group yet; saving the day approves the same proposals.
  final bool automaticSegments;

  /// The approved segments, in approved order, with their fastest times.
  List<TheoreticalBestRow> get segments => summary?.sectors ?? const [];

  /// The theoretical best lap time, when every segment is timed.
  double? get theoreticalBestSeconds => summary?.totalSeconds;

  /// What the best lap shows: its lap time, or its sector sum when the
  /// segments do not cover the whole lap.
  double? get bestLapSeconds => summary?.actualBest?.shownSeconds;

  /// The time available: the best lap's sector sum minus the theoretical best.
  double? get availableSeconds => summary?.differenceSeconds;

  /// The largest losses of each session's best lap against the best lap
  /// (Overlays' "Largest time losses", or every lap with [allLaps]).
  TimeLossRanking timeLosses({bool allLaps = false}) => computed == null
      ? TimeLossRanking(unavailableReason: timeLossNoReference)
      : rankOutingTimeLosses(computed!, allLaps: allLaps);

  /// The approved segment (index in [segments]) at [progressMeters] on the
  /// shared axis, or null in a gap between segments.
  int? segmentAt(double progressMeters) {
    final rows = segments;
    for (var i = 0; i < rows.length; ++i) {
      final start = rows[i].startProgressMeters, end = rows[i].endProgressMeters;
      final inside = end >= start
          ? progressMeters >= start && progressMeters <= end
          : progressMeters >= start || progressMeters <= end;
      if (inside) return i;
    }
    return null;
  }

  /// The approved segment [lap] is in at [telemetryTime], from its projection
  /// onto the shared axis; null outside its covered stretches.
  int? segmentAtTime(DayLapRow lap, double telemetryTime) {
    final computed = this.computed;
    if (computed == null) return null;
    for (var i = 0; i < computed.population.length; ++i) {
      if (computed.population[i].times.lapReference != lap.reference) continue;
      final progress = progressAtTime(computed.traces[i], telemetryTime);
      return progress == null ? null : segmentAt(progress);
    }
    return null;
  }
}

/// Each run's recording and laps, by run id.
Map<String, OutingRun> outingRuns(List<NamedRun> runs) => {
  for (final named in runs) named.run.id: OutingRun(named.run.telemetry, named.run.laps),
};

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

/// The theoretical best of [groupId] (by default the group shown) in
/// [analysis], with [runs]' recordings. [documentRuns] are the day
/// document's `event.runs`, whose `trackSegments` hold the approved segments.
/// When none of them has segments for the group, the proposals of the group's
/// best lap are approved for the calculation, as saving the day does
/// ([automaticTrackSegments]); [random] mints their ids. The segments are
/// those of the first run, by id, that has any for the group.
DayTheoreticalBest dayTheoreticalBest(
  DayAnalysis analysis,
  Map<String, OutingRun> runs, {
  Iterable<Object?> documentRuns = const [],
  String? groupId,
  math.Random? random,
  CancellationCheck? cancelled,
}) {
  final id = groupId ?? analysis.chosenGroupId ?? '';
  DayTheoreticalBest unavailable(String message) =>
      DayTheoreticalBest(groupId: id, state: DayTheoreticalBestState.unavailable, message: message);
  DayGroup? group;
  for (final candidate in analysis.groups) {
    if (candidate.id == id && candidate.resolved) group = candidate;
  }
  final ranking = group?.ranking;
  if (group == null || ranking == null) {
    return unavailable(
      'Confirm a compatible track configuration before calculating a theoretical best.',
    );
  }
  final eligible = {for (final lap in ranking.eligibleLaps) lap.reference};
  final rows = [
    for (final row in analysis.rows)
      if (eligible.contains(row.reference)) row,
  ];
  if (rows.isEmpty) {
    return unavailable('No eligible laps in this group to calculate a theoretical best from.');
  }
  final stored = <String, Object?>{
    for (final value in documentRuns)
      if (_object(value) case final run? when run['id'] is String)
        run['id'] as String: run['trackSegments'],
  };
  var automatic = false;
  final best = ranking.bestOfDay;
  if (best != null &&
      runs[best.runId] != null &&
      !groupHasApprovedSegments(documentRuns, group.id)) {
    final run = runs[best.runId]!;
    final segments = automaticTrackSegments(
      documentRuns: documentRuns,
      groupId: group.id,
      storedSegments: stored[best.runId],
      session: run.session,
      laps: run.laps,
      lapNumber: best.lapNumber,
      startTime: best.start,
      endTime: best.end,
      random: random,
      cancelled: cancelled,
    );
    if (segments != null) {
      stored[best.runId] = segments;
      automatic = true;
    }
  }
  final canonical = canonicalSegmentation(
    rows.map((row) => row.runId),
    (runId) => stored[runId],
    group.id,
  );
  if (canonical == null) {
    return unavailable(
      'No run in this group has an approved segment review yet. '
      'Approve segments for at least one run first.',
    );
  }
  final computed = calculateOutingTheoreticalBest(
    [
      for (final row in rows)
        OutingLap(
          runId: row.runId,
          lapNumber: row.lapNumber,
          start: row.start,
          end: row.end,
          reference: row.reference,
        ),
    ],
    runs,
    canonical.approved,
    canonical.runId,
    best?.reference,
    cancelled: cancelled,
  );
  if (computed.error.isNotEmpty) {
    return DayTheoreticalBest(
      groupId: id,
      state: DayTheoreticalBestState.error,
      message: computed.error,
      automaticSegments: automatic,
    );
  }
  if (!computed.best.valid) {
    return DayTheoreticalBest(
      groupId: id,
      state: DayTheoreticalBestState.unavailable,
      message: theoreticalBestReasonText(computed.best.unavailableReason),
      automaticSegments: automatic,
    );
  }
  final summary = publishTheoreticalBest(computed);
  final byReference = {for (final row in rows) row.reference: row};
  final fastest = [for (final sector in computed.best.sectors) sector.seconds];
  final timed = <DayLapReference, DayLapSectors>{};
  for (final lap in computed.population) {
    final reference = lap.times.lapReference as DayLapReference;
    timed[reference] = DayLapSectors(
      lap: byReference[reference]!,
      times: lap.times,
      lossSeconds: [
        for (var i = 0; i < lap.times.sectors.length; ++i)
          lap.times.sectors[i].seconds == null || fastest[i] == null
              ? null
              : lap.times.sectors[i].seconds! - fastest[i]!,
      ],
      bestOfDay: reference == best?.reference,
    );
  }
  return DayTheoreticalBest(
    groupId: id,
    state: DayTheoreticalBestState.ready,
    message: computed.best.totalSeconds == null
        ? theoreticalBestReasonText(computed.best.unavailableReason)
        : '',
    computed: computed,
    summary: summary,
    laps: [for (final row in rows) ?timed[row.reference]],
    bestLap: best,
    automaticSegments: automatic,
  );
}

/// [dayTheoreticalBest] of every resolved group of [analysis], by group id.
Map<String, DayTheoreticalBest> dayTheoreticalBests(
  DayAnalysis analysis,
  Map<String, OutingRun> runs, {
  Iterable<Object?> documentRuns = const [],
  math.Random? random,
  CancellationCheck? cancelled,
}) => {
  for (final group in analysis.groups)
    if (group.resolved)
      group.id: dayTheoreticalBest(
        analysis,
        runs,
        documentRuns: documentRuns,
        groupId: group.id,
        random: random,
        cancelled: cancelled,
      ),
};
