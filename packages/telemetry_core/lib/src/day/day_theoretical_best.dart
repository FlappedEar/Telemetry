// A day's theoretical best per compatibility group (FET-32), as Overlays'
// AnalysisControllerTheoreticalBest.cpp requests it and its
// TheoreticalBestDialog and TimeLossDialog show it: every eligible lap of the
// group timed against the approved segments on one shared axis, the fastest
// time of each segment, the time the best lap leaves (its own sector sum
// minus the theoretical best), and each lap's loss to the fastest time of
// every segment.
import 'dart:math' as math;

import '../analysis/automatic_segments.dart';
import '../analysis/outing_results.dart';
import '../analysis/outing_theoretical_best.dart';
import '../analysis/realistic_theoretical_best.dart';
import '../analysis/sector_timing.dart';
import '../analysis/time_loss.dart';
import '../analysis/track_progress.dart';
import '../analysis/track_segment_review.dart';
import '../intake/import_plan.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import 'day_analysis.dart';
import 'day_corners.dart';
import 'day_laps.dart';
import 'day_ranking.dart';

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
    List<DayCorner> corners = const [],
    this.segmentRunId = '',
    List<Map<String, Object?>> runSegments = const [],
    List<SegmentReviewItem> proposalReview = const [],
    Map<String, List<Map<String, Object?>>> remeasuredRuns = const {},
    this.realistic,
  }) : laps = List.unmodifiable(laps),
       corners = List.unmodifiable(corners),
       runSegments = List.unmodifiable(runSegments),
       proposalReview = List.unmodifiable(proposalReview),
       remeasuredRuns = Map.unmodifiable(remeasuredRuns);

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

  /// Each corner segment's speeds, braking and pickup on every lap, in
  /// approved order.
  final List<DayCorner> corners;

  /// The run whose approved segments were used: the one an edit changes.
  final String segmentRunId;

  /// That run's whole `trackSegments` (with [automaticSegments], the
  /// proposals approved now), which an edit starts from.
  final List<Map<String, Object?>> runSegments;

  /// The best lap's automatic proposals and their review state against the
  /// approved segments: all approved when the segments are the automatic
  /// ones, superseded where an edit replaced them.
  final List<SegmentReviewItem> proposalReview;

  /// When the segments were measured again on the best lap
  /// ([remeasureDaySegments]): each changed run's whole `trackSegments`,
  /// which the day keeps as approved. Empty otherwise.
  final Map<String, List<Map<String, Object?>>> remeasuredRuns;

  /// The fastest combination of segments that join at the speed the car had
  /// ([computeRealisticTheoreticalBest]); null without a result.
  final RealisticTheoreticalBest? realistic;

  /// This result with [runs] as its [remeasuredRuns].
  DayTheoreticalBest withRemeasuredRuns(Map<String, List<Map<String, Object?>>> runs) =>
      DayTheoreticalBest(
        groupId: groupId,
        state: state,
        message: message,
        computed: computed,
        summary: summary,
        laps: laps,
        bestLap: bestLap,
        automaticSegments: automaticSegments,
        corners: corners,
        segmentRunId: segmentRunId,
        runSegments: runSegments,
        proposalReview: proposalReview,
        remeasuredRuns: runs,
        realistic: realistic,
      );

  /// The length of the shared axis the segments are edited on.
  double get axisLengthMeters => computed?.axisLengthMeters ?? 0.0;

  /// Whether the approved segments are exactly the best lap's automatic
  /// proposals, names included.
  bool get segmentsAutomatic {
    if (automaticSegments) return true;
    final approved = computed?.approved.segments ?? const [];
    if (proposalReview.isEmpty || proposalReview.length != approved.length) return false;
    for (var i = 0; i < approved.length; ++i) {
      if (!segmentMatchesProposal(i)) return false;
    }
    return true;
  }

  /// Whether segment [index] of [segments] is one of the automatic proposals,
  /// unchanged (bounds, type and name).
  bool segmentMatchesProposal(int index) {
    if (automaticSegments) return true;
    final segment = approvedSegment(index);
    if (segment == null) return false;
    return proposalReview.any(
      (item) =>
          item.state == SegmentReviewState.approved &&
          item.approvedSegmentId == segment['id'] &&
          item.proposal.name == segment['name'],
    );
  }

  /// The approved segment [index] as stored (with its id).
  Map<String, Object?>? approvedSegment(int index) {
    final segments = computed?.approved.segments ?? const [];
    return index >= 0 && index < segments.length ? segments[index] : null;
  }

  /// Where [lap] is on the shared axis at [telemetryTime], or null outside
  /// its covered stretches.
  double? progressAt(DayLapRow lap, double telemetryTime) {
    final computed = this.computed;
    if (computed == null) return null;
    for (var i = 0; i < computed.population.length; ++i) {
      if (computed.population[i].times.lapReference != lap.reference) continue;
      return progressAtTime(computed.traces[i], telemetryTime);
    }
    return null;
  }

  /// When [lap] was at [progressMeters] on the shared axis, or null where
  /// its projection has no coverage there.
  double? timeAt(DayLapRow lap, double progressMeters) {
    final computed = this.computed;
    if (computed == null) return null;
    for (var i = 0; i < computed.population.length; ++i) {
      if (computed.population[i].times.lapReference != lap.reference) continue;
      return timeAtProgress(computed.traces[i], progressMeters);
    }
    return null;
  }

  /// The corner at segment [index] of [segments], or null for a straight or
  /// sector.
  DayCorner? cornerAt(int index) {
    for (final corner in corners) {
      if (corner.segmentIndex == index) return corner;
    }
    return null;
  }

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

  /// The largest losses as the time-loss list shows them (each run's best
  /// lap, or with [allLaps] every lap, against the group's best lap).
  TimeLossSummary publishedTimeLosses({bool allLaps = false}) {
    final computed = this.computed;
    if (computed == null || state != DayTheoreticalBestState.ready) {
      return TimeLossSummary(available: false, message: message);
    }
    return publishTimeLossRanking(computed, allLaps: allLaps);
  }

  /// [loss]'s lap and the group's best lap through its segment.
  TimeLossComparison? compareLoss(PublishedTimeLoss loss) {
    final computed = this.computed;
    return computed == null ? null : compareTimeLoss(computed, loss);
  }

  /// Each segment's median and spread per run, the runs in [order] (the
  /// progression's order).
  SectionProgression sectionProgression(List<ProgressionRunInfo> order) {
    final computed = this.computed;
    if (computed == null || state != DayTheoreticalBestState.ready) return SectionProgression();
    return publishSectorProgression(computed, order);
  }

  /// The approved segment (index in [segments]) at [progressMeters] on the
  /// shared axis, or null in a gap between segments. A lap's fixes just
  /// before the line or past the finish lie below 0 or above the axis length
  /// (FET-192); they are taken around the loop.
  int? segmentAt(double progressMeters) {
    final length = axisLengthMeters;
    if (length > 0 && (progressMeters < 0 || progressMeters > length)) {
      progressMeters %= length;
    }
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
    final progress = progressAt(lap, telemetryTime);
    return progress == null ? null : segmentAt(progress);
  }
}

/// Each run's recording and laps, by run id.
Map<String, OutingRun> outingRuns(List<NamedRun> runs) => {
  for (final named in runs) named.run.id: OutingRun(named.run.telemetry, named.run.laps),
};

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

/// The lap traces of [ranking]'s eligible laps other than [best], from
/// [runs] (each run's recording and laps): what the best lap's line is
/// checked against before its segments are adopted (FET-214). Excluded laps
/// and laps the ranking leaves out are not used. A run whose GPS longitude
/// convention differs from the best lap's run (a west-positive VBO against
/// an RCZ) has its traces mirrored east to west, so all are in the best
/// lap's frame.
List<LapTrace> otherEligibleLapTraces(
  DayRanking ranking,
  DayLapRow best,
  Map<String, (TelemetrySession, LapSession)> runs,
) {
  bool westPositive(String runId) =>
      runs[runId]?.$1.metadata['gpsLongitudeConvention'] == 'west-positive';
  final bestWestPositive = westPositive(best.runId);
  final traces = <LapTrace>[];
  for (final row in ranking.eligibleLaps) {
    if (row.runId == best.runId && row.lapNumber == best.lapNumber) continue;
    for (final trace in runs[row.runId]?.$2.lapTraces ?? const <LapTrace>[]) {
      if (trace.lapNumber != row.lapNumber) continue;
      traces.add(
        westPositive(row.runId) == bestWestPositive
            ? trace
            : LapTrace(
                lapNumber: trace.lapNumber,
                startTelemetryTime: trace.startTelemetryTime,
                durationSeconds: trace.durationSeconds,
                points: [
                  for (final point in trace.points)
                    LapTracePoint(point.telemetryTime, -point.eastMeters, point.northMeters),
                ],
              ),
      );
      break;
    }
  }
  return traces;
}

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
  var lineDisagrees = false;
  final best = ranking.bestOfDay;
  // The best lap's proposals: approved for the calculation when the group
  // has no segments yet, and otherwise compared with the approved ones.
  SegmentReview? review;
  if (best != null && runs[best.runId] != null) {
    final run = runs[best.runId]!;
    review = computeSegmentReview(
      run.session,
      run.laps,
      lapNumber: best.lapNumber,
      startTime: best.start,
      endTime: best.end,
      cancelled: cancelled,
    );
    if (group.id.startsWith('compatibility-v1:') &&
        !groupHasApprovedSegments(documentRuns, group.id)) {
      lineDisagrees = lineConsensus(
        review.axis,
        otherEligibleLapTraces(ranking, best, {
          for (final entry in runs.entries) entry.key: (entry.value.session, entry.value.laps),
        }),
        cancelled: cancelled,
      ).disagrees;
      final segments = lineDisagrees
          ? null
          : approveAllProposals(stored[best.runId], review, group.id, random: random);
      if (segments != null) {
        stored[best.runId] = segments;
        automatic = true;
      }
    }
  }
  final canonical = canonicalSegmentation(
    rows.map((row) => row.runId),
    (runId) => stored[runId],
    group.id,
  );
  if (canonical == null) {
    if (lineDisagrees) return unavailable(automaticSegmentsLineDisagreement);
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
  throwIfCancelled(cancelled);
  // Each timed lap's speed at each segment's start and end, for the
  // realistic best.
  final segmentIds = [for (final segment in computed.approved.segments) segment['id']];
  final realistic = computeRealisticTheoreticalBest(computed.approved, [
    for (var k = 0; k < computed.population.length; ++k)
      if (runs[computed.runIds[k]]?.session case final session?)
        () {
          SectorTime? sector(Object? id) {
            for (final candidate in computed.population[k].times.sectors) {
              if (candidate.segmentId == id) return candidate;
            }
            return null;
          }

          return RealisticLapInput(
            times: computed.population[k].times,
            entrySpeeds: [
              for (final id in segmentIds) speedMetresPerSecondAt(session, sector(id)?.startTime),
            ],
            exitSpeeds: [
              for (final id in segmentIds) speedMetresPerSecondAt(session, sector(id)?.endTime),
            ],
          );
        }(),
  ], cancelled: cancelled);
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
    corners: dayCorners(computed, rows, best),
    segmentRunId: canonical.runId,
    runSegments: [
      for (final value in (stored[canonical.runId] as List?) ?? const [])
        value as Map<String, Object?>,
    ],
    proposalReview: review == null || review.unavailable.isNotEmpty || review.error.isNotEmpty
        ? const []
        : reviewSegmentProposals(
            review.proposals.proposals,
            const {},
            const {},
            canonical.approved,
            review.axis.lengthMeters,
          ),
    realistic: realistic,
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
