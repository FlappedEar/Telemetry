// Port of FlappedEar Overlays native/src/telemetry/OutingDayReport.{h,cpp}
// and of AnalysisController::computeOutingDayReport
// (native/src/app/AnalysisControllerDayReport.cpp, revision d4d1039,
// FET-36): the day report assembled from results computed elsewhere
// (KAN-71), with the areas to inspect next (KAN-73). Nothing is recalculated
// here; a result that has not been computed is reported as such.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fetproject/fetproject.dart' show lapReferenceAlgorithm;

import '../analysis/channel_summary.dart';
import '../analysis/consistency.dart';
import '../analysis/day_report.dart';
import '../analysis/focus_areas.dart';
import '../analysis/outing_results.dart';
import '../analysis/outing_theoretical_best.dart';
import '../analysis/theoretical_best.dart';
import '../analysis/time_loss.dart';
import 'day_analysis.dart';
import 'day_channel_summaries.dart';
import 'day_laps.dart';
import 'day_progression.dart';
import 'day_ranking.dart';
import 'day_theoretical_best.dart';

/// Overlays' lap-ranking algorithm tag, which the best lap and the
/// progression carry.
const String lapRankingAlgorithm = 'outing-ranking-v1';

/// Everything the day report presents, as computed elsewhere.
final class DayReportSources {
  DayReportSources({
    this.eventId = '',
    this.groupId = '',
    this.groupLabel = '',
    this.decisionsKey = const [],
    this.theoreticalKey = const [],
    this.lapsLoading = false,
    this.ranking,
    this.progression,
    this.consistency,
    List<DayLapRow> eligibleLaps = const [],
    this.theoreticalStatus = DayResultStatus.notComputed,
    this.theoreticalMessage = '',
    this.theoretical,
    this.timeLosses,
    this.sectionProgression,
    this.focus,
    this.channelStatus = DayResultStatus.notComputed,
    this.channelMessage = '',
    this.channels,
    required this.lapLabel,
    required this.referenceJson,
  }) : eligibleLaps = List.unmodifiable(eligibleLaps);

  final String eventId;
  final String groupId;
  final String groupLabel;

  /// The current analysis decisions.
  final List<int> decisionsKey;

  /// The decisions the theoretical-best family was computed under.
  final List<int> theoreticalKey;

  /// The day's laps are being derived again.
  final bool lapsLoading;

  /// The compared group's ranking; null without a group.
  final DayRanking? ranking;
  final DayProgression? progression;

  /// The group's lap-time consistency; null without a group.
  final LapConsistency? consistency;

  /// The group's eligible laps in recording order: the consistency's
  /// evidence.
  final List<DayLapRow> eligibleLaps;

  /// The theoretical best's status: available when calculated, unavailable
  /// with [theoreticalMessage] when there is none, computing or not
  /// computed.
  final DayResultStatus theoreticalStatus;
  final String theoreticalMessage;

  /// The theoretical best, its time losses (the list shown: each session's
  /// best or every lap) and the section progression, when available.
  final TheoreticalBestSummary? theoretical;
  final TimeLossSummary? timeLosses;
  final SectionProgression? sectionProgression;

  /// Focus-area inputs; null when the group's best lap was not timed on the
  /// shared axis (the focus areas are then unavailable, with a reason).
  final FocusInputs? focus;

  /// The channel summaries' status and result.
  final DayResultStatus channelStatus;
  final String channelMessage;
  final DayChannelSummaries? channels;

  /// "Session 3 · LAP 2" for a lap reference.
  final String Function(Object? reference) lapLabel;

  /// A lap reference as the report writes it.
  final Object? Function(Object? reference) referenceJson;
}

Map<String, Object?> _lapEvidence(DayReportSources sources, Object? reference, String label) => {
  'kind': 'lap',
  'reference': sources.referenceJson(reference),
  'label': label,
};

String _reasonFor(String message, String fallback) => message.isEmpty ? fallback : message;

/// A [ConsistencySummary] as the report writes it.
Map<String, Object?> consistencySummaryMap(ConsistencySummary summary) => {
  'count': summary.count,
  'available': summary.available,
  if (!summary.available)
    'unavailableReason': summary.unavailableReason
  else ...{
    'minimum': summary.minimum,
    'q1': summary.q1,
    'median': summary.median,
    'q3': summary.q3,
    'maximum': summary.maximum,
    'interquartileRange': summary.interquartileRange,
  },
};

/// The day report document of [sources] (see [buildDayReport]).
Map<String, Object?> buildOutingDayReport(DayReportSources sources) {
  final results = <DayReportResult>[];
  final groupId = sources.groupId;
  Map<String, Object?> dayRange() => {'scope': 'day', 'groupId': groupId};
  final ranking = sources.ranking;

  // Best lap of the day (KAN-23), from the eligibility-filtered ranking.
  {
    final best = ranking?.bestOfDay;
    final result = DayReportResult(
      id: 'bestLap',
      algorithm: lapRankingAlgorithm,
      revision: lapReferenceAlgorithm,
      decisionsKey: sources.decisionsKey,
      range: {
        ...dayRange(),
        'lapCount': sources.lapsLoading ? 0 : ranking?.lapCount ?? 0,
        'eligibleLapCount': sources.lapsLoading ? 0 : ranking?.eligibleLapCount ?? 0,
      },
    );
    if (sources.lapsLoading) {
      result.status = DayResultStatus.computing;
    } else if (ranking?.state == DayRankingState.available && best != null) {
      final label = '${best.runName} · LAP ${best.lapNumber}';
      result.status = DayResultStatus.available;
      result.value.addAll({
        'seconds': best.durationSeconds,
        'label': label,
        'runId': best.runId,
        'lapNumber': best.lapNumber,
      });
      result.evidence.add(_lapEvidence(sources, best.reference, label));
    } else {
      result.status = DayResultStatus.unavailable;
      result.reason = ranking == null || ranking.state == DayRankingState.selectionRequired
          ? 'Choose a compatibility group.'
          : 'No eligible lap in this group.';
    }
    results.add(result);
  }

  // Per-session best and spread (KAN-25), from the same ranking.
  {
    final runs = sources.lapsLoading
        ? const <ProgressionRun>[]
        : sources.progression?.runs ?? const <ProgressionRun>[];
    final result = DayReportResult(
      id: 'progression',
      algorithm: lapRankingAlgorithm,
      decisionsKey: sources.decisionsKey,
      range: {...dayRange(), 'runCount': runs.length},
    );
    if (sources.lapsLoading) {
      result.status = DayResultStatus.computing;
    } else if (runs.isEmpty) {
      result.status = DayResultStatus.unavailable;
      result.reason = 'No session in this group.';
    } else {
      final rows = <Map<String, Object?>>[];
      for (final run in runs) {
        final row = <String, Object?>{
          'runId': run.runId,
          'runName': run.runName,
          'lapCount': run.lapCount,
          'eligibleLapCount': run.eligibleLapCount,
        };
        final best = run.bestLap;
        if (best != null) {
          row['bestSeconds'] = best.durationSeconds;
          row['evidenceIndex'] = result.evidence.length;
          result.evidence.add(
            _lapEvidence(sources, best.reference, '${run.runName} · LAP ${best.lapNumber}'),
          );
        }
        final distribution = run.distribution;
        if (distribution != null) {
          row['distribution'] = {
            'minimum': distribution.minimum,
            'q1': distribution.q1,
            'median': distribution.median,
            'q3': distribution.q3,
            'maximum': distribution.maximum,
          };
        }
        final delta = run.bestDeltaPreviousListedSeconds;
        if (delta != null) row['bestDeltaPreviousSeconds'] = delta;
        rows.add(row);
      }
      result.status = DayResultStatus.available;
      result.value['runs'] = rows;
    }
    results.add(result);
  }

  // Lap-time consistency (KAN-62): day and per session, over the eligible
  // laps.
  {
    final consistency = sources.lapsLoading ? null : sources.consistency;
    final result = DayReportResult(
      id: 'consistency',
      algorithm: consistencyAlgorithm,
      decisionsKey: sources.decisionsKey,
      range: {...dayRange(), 'minimumSamples': minimumConsistencySamples},
    );
    if (consistency == null) {
      result.status = sources.lapsLoading ? DayResultStatus.computing : DayResultStatus.unavailable;
      if (!sources.lapsLoading) result.reason = 'No eligible laps to summarize.';
    } else {
      result.status = DayResultStatus.available;
      result.value.addAll({
        'day': consistencySummaryMap(consistency.day),
        'runs': [
          for (final run in consistency.runs)
            {'runId': run.runId, 'runName': run.runName, 'laps': consistencySummaryMap(run.laps)},
        ],
      });
      for (final row in sources.eligibleLaps) {
        result.evidence.add(
          _lapEvidence(sources, row.reference, '${row.runName} · LAP ${row.lapNumber}'),
        );
      }
    }
    results.add(result);
  }

  // Theoretical best (KAN-56): each sector with the lap it came from.
  final theoreticalStatus = sources.theoreticalStatus;
  final theoretical = sources.theoretical;
  final available = theoreticalStatus == DayResultStatus.available && theoretical != null;
  String notAvailableReason() => _reasonFor(
    sources.theoreticalMessage,
    theoreticalStatus == DayResultStatus.notComputed ? 'Not calculated yet.' : '',
  );
  {
    final result = DayReportResult(
      id: 'theoreticalBest',
      algorithm: theoreticalBestAlgorithm,
      decisionsKey: sources.theoreticalKey,
      range: dayRange(),
      status: available ? DayResultStatus.available : _notAvailable(theoreticalStatus),
    );
    if (available) {
      final sectors = <Map<String, Object?>>[];
      for (final sector in theoretical.sectors) {
        final row = <String, Object?>{
          'segmentId': sector.segmentId,
          'name': sector.name,
          'type': sector.type,
        };
        final seconds = sector.seconds;
        if (seconds != null) {
          final label = sources.lapLabel(sector.sourceLapReference);
          row['seconds'] = seconds;
          row['sourceLapLabel'] = label;
          result.evidence.add({
            'kind': 'segment',
            'segmentId': sector.segmentId,
            'reference': sources.referenceJson(sector.sourceLapReference),
            'label': label,
          });
        } else {
          row['unavailableReason'] = sector.unavailableReason;
        }
        if (sector.lossSeconds != null) row['lossSeconds'] = sector.lossSeconds;
        sectors.add(row);
      }
      result.value['sectors'] = sectors;
      result.range['sectorCount'] = sectors.length;
      if (theoretical.totalSeconds != null) result.value['totalSeconds'] = theoretical.totalSeconds;
      if (theoretical.differenceSeconds != null) {
        result.value['differenceSeconds'] = theoretical.differenceSeconds;
      }
      final actual = theoretical.actualBest;
      if (actual != null) {
        final label = sources.lapLabel(actual.reference);
        result.value['actualBest'] = {'label': label, 'seconds': actual.lapSeconds};
        result.evidence.add(_lapEvidence(sources, actual.reference, label));
      }
    } else {
      result.reason = notAvailableReason();
    }
    results.add(result);
  }

  // Largest time losses (KAN-60) against the group's best lap.
  {
    final losses = sources.timeLosses;
    final ready = available && losses != null && losses.available;
    final result = DayReportResult(
      id: 'timeLosses',
      algorithm: timeLossAlgorithm,
      revision: ready ? losses.revision : '',
      decisionsKey: sources.theoreticalKey,
      range: dayRange(),
      status: ready
          ? DayResultStatus.available
          : available
          ? DayResultStatus.unavailable
          : _notAvailable(theoreticalStatus),
    );
    if (ready) {
      result.range.addAll({
        'scope': losses.allLaps ? 'allLaps' : 'runBests',
        'groupId': groupId,
        'comparedLapCount': losses.comparedLapCount,
        'observationCount': losses.observationCount,
      });
      final against = sources.referenceJson(losses.referenceLap);
      final rows = <Map<String, Object?>>[];
      for (final loss in losses.losses.take(10)) {
        final label = sources.lapLabel(loss.lapReference);
        rows.add({
          'name': loss.window.name,
          'role': loss.window.role,
          'segmentId': loss.window.segmentId,
          'lossSeconds': loss.lossSeconds,
          'lapLabel': label,
          if (loss.window.cornerSegmentId.isNotEmpty && loss.cornerName.isNotEmpty)
            'cornerName': loss.cornerName,
        });
        result.evidence.add({
          'kind': 'segment',
          'segmentId': loss.window.segmentId,
          'reference': sources.referenceJson(loss.lapReference),
          'against': against,
          'startMeters': loss.window.startProgressMeters,
          'endMeters': loss.window.endProgressMeters,
          'label': label,
        });
      }
      result.value.addAll({
        'referenceLabel': sources.lapLabel(losses.referenceLap),
        'losses': rows,
      });
    } else if (available) {
      result.reason = losses?.message ?? '';
    } else {
      result.reason = notAvailableReason();
    }
    results.add(result);
  }

  // Areas to inspect next (KAN-73), selected from the computed losses of
  // each session's fastest lap, the best lap's sector gaps and the corner
  // variability. Observations and hypotheses are kept apart.
  {
    final focus = sources.focus;
    final result = DayReportResult(
      id: 'focusAreas',
      algorithm: focusAreasAlgorithm,
      decisionsKey: sources.theoreticalKey,
      range: dayRange(),
      status: available ? DayResultStatus.available : _notAvailable(theoreticalStatus),
    );
    if (available && focus == null) {
      result.status = DayResultStatus.unavailable;
      result.reason = timeLossBestLapUntimedMessage;
    } else if (available) {
      final areas = <Map<String, Object?>>[];
      for (final area in selectFocusAreas(focus!)) {
        areas.add({
          'kind': area.kind.code,
          'segmentId': area.segmentId,
          'name': area.name,
          'observation': area.observation,
          'hypothesis': area.hypothesis,
          'metric': area.metric,
          'value': area.value,
          'unit': area.unit,
          'sampleCount': area.sampleCount,
          'evidenceIndex': result.evidence.length,
        });
        result.evidence.add({
          'kind': 'segment',
          'segmentId': area.segmentId,
          'reference': sources.referenceJson(area.lap),
          'label': sources.lapLabel(area.lap),
          'against': sources.referenceJson(area.against),
          'againstLabel': sources.lapLabel(area.against),
        });
      }
      result.range['comparedLapCount'] = focus.comparedLapCount;
      if (areas.isEmpty) {
        result.status = DayResultStatus.unavailable;
        result.reason = 'No loss, sector gap or spread is large enough to single out.';
      } else {
        result.value.addAll({'areas': areas, 'referenceLabel': focus.referenceLabel});
      }
    } else {
      result.reason = notAvailableReason();
    }
    results.add(result);
  }

  // Sections by session (KAN-64): typical time and spread per segment.
  {
    final sections = sources.sectionProgression;
    final ready = available && sections != null;
    final result = DayReportResult(
      id: 'sectionProgression',
      algorithm: consistencyAlgorithm,
      decisionsKey: sources.theoreticalKey,
      range: dayRange(),
      status: ready ? DayResultStatus.available : _notAvailable(theoreticalStatus),
    );
    if (ready) {
      final rows = <Map<String, Object?>>[];
      for (final segment in sections.segments) {
        final cells = <Map<String, Object?>>[];
        for (final cell in segment.cells) {
          cells.add({'runId': cell.runId, 'summary': consistencySummaryMap(cell.summary)});
          result.evidence.add({
            'kind': 'segment',
            'segmentId': segment.segmentId,
            'runId': cell.runId,
            'lapCount': cell.laps.length,
          });
        }
        rows.add({
          'segmentId': segment.segmentId,
          'name': segment.name,
          'type': segment.type,
          'cells': cells,
          if (segment.fastestTypical != null) 'fastestTypicalSeconds': segment.fastestTypical,
        });
      }
      result.value.addAll({
        'sessions': [
          for (final session in sections.sessions)
            {'runId': session.runId, 'runName': session.run.name},
        ],
        'segments': rows,
      });
    } else {
      result.reason = notAvailableReason();
    }
    results.add(result);
  }

  // Recorded temperatures (KAN-67/68) and heart rate (KAN-69/70), per
  // session. They do not depend on the analysis decisions; they are
  // invalidated with the run set.
  final channels = sources.channels;
  final channelsReady = sources.channelStatus == DayResultStatus.available && channels != null;
  final channelRuns = channels?.runs ?? const <RunChannelSummaries>[];
  for (final heart in [false, true]) {
    final result = DayReportResult(
      id: heart ? 'heartRate' : 'temperatures',
      algorithm: channelSummaryAlgorithm,
      range: {'scope': 'day', 'runCount': channelsReady ? channelRuns.length : 0},
      status: channelsReady ? DayResultStatus.available : _notAvailable(sources.channelStatus),
    );
    if (channelsReady) {
      final runs = <Map<String, Object?>>[];
      for (final run in channelRuns) {
        final row = <String, Object?>{'runId': run.runId, 'runName': run.runName};
        final entries = heart ? [?run.heartRate] : run.channels;
        final written = <Map<String, Object?>>[];
        for (final entry in entries) {
          final channel = <String, Object?>{
            'channel': entry.channel,
            'unit': entry.unit,
            'run': channelSummaryMap(entry.run),
          };
          if (!heart) {
            var largestDrop = 0.0;
            for (final cooling in entry.cooling) {
              if (cooling.interval.drop > largestDrop) largestDrop = cooling.interval.drop;
            }
            channel['coolingCount'] = entry.cooling.length;
            if (entry.cooling.isNotEmpty) channel['largestCoolingDrop'] = largestDrop;
          }
          written.add(channel);
          result.evidence.add({'kind': 'channel', 'runId': run.runId, 'channel': entry.channel});
        }
        if (heart) {
          if (written.isNotEmpty) row['heartRate'] = written.first;
        } else {
          row['channels'] = written;
        }
        if (run.unavailableReason.isNotEmpty) row['unavailableReason'] = run.unavailableReason;
        runs.add(row);
      }
      if (result.evidence.isEmpty) {
        result.status = DayResultStatus.unavailable;
        result.reason = heart ? 'No heart rate recorded.' : 'No temperature recorded.';
      } else {
        result.value['runs'] = runs;
      }
    } else {
      result.reason = _reasonFor(
        sources.channelMessage,
        sources.channelStatus == DayResultStatus.notComputed ? 'Not calculated yet.' : '',
      );
    }
    results.add(result);
  }

  return buildDayReport(
    DayReportInput(
      eventId: sources.eventId,
      groupId: groupId,
      groupLabel: sources.groupLabel,
      decisionsKey: sources.decisionsKey,
      results: results,
    ),
  );
}

// A status that is not "available": an available status without its result
// is reported as unavailable.
DayResultStatus _notAvailable(DayResultStatus status) =>
    status == DayResultStatus.available ? DayResultStatus.unavailable : status;

/// The focus-area inputs of a ready theoretical best (Overlays'
/// `computeOutingDayReport`): the best lap's gap to the fastest time of each
/// sector, the losses of each session's fastest lap against it (every one,
/// not only the list's 50) and each corner's observations, corners by
/// segment id. Null without a timed best lap.
FocusInputs? dayFocusInputs(
  DayTheoreticalBest result,
  String Function(Object? reference) lapLabel,
) {
  final computed = result.computed, summary = result.summary;
  final actual = computed?.actualBest;
  if (result.state != DayTheoreticalBestState.ready ||
      computed == null ||
      summary == null ||
      actual == null) {
    return null;
  }
  final reference = actual.lapReference;
  final referenceLabel = lapLabel(reference);
  final ranking = rankOutingTimeLosses(computed, maximumResults: maximumDayLapRows);
  final names = {for (final sector in computed.best.sectors) sector.segmentId: sector.name};
  final observations = computed.cornerObservations;
  final cornerIds = observations.keys.toList()..sort();
  return FocusInputs(
    referenceLap: reference,
    referenceLabel: referenceLabel,
    comparedLapCount: ranking.valid ? ranking.comparedLapCount : 0,
    gaps: [
      for (final sector in summary.sectors)
        if (sector.lossSeconds != null && sector.sourceLapReference != null)
          FocusSectorGap(
            segmentId: sector.segmentId,
            name: sector.name,
            gapSeconds: sector.lossSeconds!,
            bestLap: reference,
            bestLapLabel: referenceLabel,
            sourceLap: sector.sourceLapReference,
            sourceLapLabel: lapLabel(sector.sourceLapReference),
          ),
    ],
    losses: [
      if (ranking.valid)
        for (final loss in ranking.losses)
          FocusLoss(
            segmentId: loss.window.segmentId,
            name: loss.window.name,
            lossSeconds: loss.lossSeconds,
            lap: loss.lapReference,
          ),
    ],
    corners: [
      for (final id in cornerIds)
        FocusCorner(segmentId: id, name: names[id] ?? id, observations: observations[id]!),
    ],
  );
}

/// The focus areas of a ready theoretical best, or none.
List<FocusArea> dayFocusAreas(
  DayTheoreticalBest result,
  String Function(Object? reference) lapLabel,
) {
  final inputs = dayFocusInputs(result, lapLabel);
  return inputs == null ? const [] : selectFocusAreas(inputs);
}

/// A lap reference as the day report writes it.
Map<String, Object?> dayLapReferenceJson(DayLapReference reference) => {
  'runId': reference.runId,
  'sourceRevision': reference.sourceRevision,
  'type': reference.type.label,
  'startTime': reference.startTime,
  'endTime': reference.endTime,
};

/// The analysis decisions [analysis]'s group shown is computed under: the
/// group, each run's approved segments ([documentRuns], the day document's
/// `event.runs` with unsaved edits), the eligible laps, the excluded laps
/// and the best lap. Opaque; equal decisions give equal keys.
List<int> dayDecisionsKey(
  DayAnalysis analysis, {
  Iterable<Object?> documentRuns = const [],
  Map<DayLapReference, String> exclusions = const {},
}) {
  final eligible = dayEligibleLaps(analysis);
  final excluded = exclusions.entries.toList()
    ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
  final key = {
    'group': analysis.chosenGroupId ?? '',
    'runs': [
      for (final value in documentRuns)
        if (value case final Map<String, Object?> run)
          {'id': run['id'], 'trackSegments': run['trackSegments']},
    ],
    'population': [for (final row in eligible) dayLapReferenceJson(row.reference)],
    'exclusions': [
      for (final entry in excluded)
        {'reference': dayLapReferenceJson(entry.key), 'reason': entry.value},
    ],
    'best': switch (analysis.ranking?.bestOfDay) {
      final best? => dayLapReferenceJson(best.reference),
      null => null,
    },
  };
  return sha256.convert(utf8.encode(jsonEncode(key))).bytes;
}

/// The day report of [analysis]'s group shown, from what the day has
/// computed: [theoretical] (the shown group's theoretical best, null until
/// calculated, [theoreticalLoading] while it is), its [theoreticalKey]
/// ([dayDecisionsKey] when it was requested), the time losses of each
/// session's best or with [allLaps] every lap, and the [channels] summaries
/// ([channelsLoading] while they are calculated). [runs] are the day's runs
/// in order with their context; [lapsLoading] while the day's laps are
/// derived again.
Map<String, Object?> dayReport({
  required DayAnalysis analysis,
  required String eventId,
  required List<ProgressionRunInfo> runs,
  List<int> decisionsKey = const [],
  bool lapsLoading = false,
  DayTheoreticalBest? theoretical,
  bool theoreticalLoading = false,
  List<int> theoreticalKey = const [],
  bool allLaps = false,
  DayChannelSummaries? channels,
  bool channelsLoading = false,
}) => buildOutingDayReport(
  dayReportSources(
    analysis: analysis,
    eventId: eventId,
    runs: runs,
    decisionsKey: decisionsKey,
    lapsLoading: lapsLoading,
    theoretical: theoretical,
    theoreticalLoading: theoreticalLoading,
    theoreticalKey: theoreticalKey,
    allLaps: allLaps,
    channels: channels,
    channelsLoading: channelsLoading,
  ),
);

/// What [dayReport] assembles its document from.
DayReportSources dayReportSources({
  required DayAnalysis analysis,
  required String eventId,
  required List<ProgressionRunInfo> runs,
  List<int> decisionsKey = const [],
  bool lapsLoading = false,
  DayTheoreticalBest? theoretical,
  bool theoreticalLoading = false,
  List<int> theoreticalKey = const [],
  bool allLaps = false,
  DayChannelSummaries? channels,
  bool channelsLoading = false,
}) {
  final rows = {for (final row in analysis.rows) row.reference: row};
  String label(Object? reference) {
    final row = rows[reference];
    return row == null ? '' : '${row.runName} · LAP ${row.lapNumber}';
  }

  Object? json(Object? reference) =>
      reference is DayLapReference ? dayLapReferenceJson(reference) : reference;
  final group = analysis.chosenGroup;
  final hasGroup = group != null && group.resolved && group.ranking != null;
  final ready = theoretical != null && theoretical.state == DayTheoreticalBestState.ready;
  final progression = hasGroup ? dayProgression(analysis, runs) : null;
  final summary = ready ? theoretical.summary : null;
  final channelError = channels?.error ?? '';
  return DayReportSources(
    eventId: eventId,
    // While the laps are derived again there is no ranking to name a group.
    groupId: hasGroup && !lapsLoading ? group.id : '',
    groupLabel: hasGroup && !lapsLoading ? group.label : '',
    decisionsKey: decisionsKey,
    theoreticalKey: theoreticalKey,
    lapsLoading: lapsLoading,
    ranking: hasGroup ? group.ranking : null,
    progression: progression,
    consistency: hasGroup ? dayLapConsistency(analysis) : null,
    eligibleLaps: hasGroup ? dayEligibleLaps(analysis) : const [],
    theoreticalStatus: theoreticalLoading
        ? DayResultStatus.computing
        : theoretical == null
        ? DayResultStatus.notComputed
        : ready
        ? DayResultStatus.available
        : DayResultStatus.unavailable,
    theoreticalMessage: theoreticalLoading ? '' : theoretical?.message ?? '',
    theoretical: theoreticalLoading ? null : summary,
    timeLosses: ready && !theoreticalLoading
        ? theoretical.publishedTimeLosses(allLaps: allLaps)
        : null,
    // The sessions in the progression's order.
    sectionProgression: ready && !theoreticalLoading
        ? theoretical.sectionProgression([
            for (final run in progression?.runs ?? const <ProgressionRun>[]) run.run,
          ])
        : null,
    focus: ready && !theoreticalLoading ? dayFocusInputs(theoretical, label) : null,
    channelStatus: channelsLoading
        ? DayResultStatus.computing
        : channels == null
        ? DayResultStatus.notComputed
        : channelError.isNotEmpty
        ? DayResultStatus.unavailable
        : DayResultStatus.available,
    channelMessage: channelsLoading ? '' : channelError,
    channels: channelsLoading || channelError.isNotEmpty ? null : channels,
    lapLabel: label,
    referenceJson: json,
  );
}
