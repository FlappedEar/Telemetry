// Port of the day part of VBOOverlay native/src/telemetry/OutingLapDerivation
// and AnalysisControllerOuting.cpp (FET-22): from a day's runs to its lap
// rows, compatibility groups and the ranking of the chosen group.
import 'package:fetproject/fetproject.dart' as fet;

import '../laps/lap_session.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import '../timing_gate.dart';
import 'compatibility.dart';
import 'day_laps.dart';
import 'day_ranking.dart';
import 'track_inference.dart';

/// One run of a day, as imported.
final class DayRunInput {
  const DayRunInput({
    required this.runId,
    required this.name,
    required this.contentSha256,
    required this.session,
    required this.laps,
    this.layoutName,
    this.direction,
  });

  final String runId;

  /// "Session N".
  final String name;
  final String contentSha256;
  final TelemetrySession session;
  final LapSession laps;

  /// The user's layout name; when set with [direction], inference is not
  /// used for this run.
  final String? layoutName;
  final TrackDirection? direction;

  bool get manual => layoutName != null || direction != null;
}

/// A message about one run (or the whole day when [runId] is empty).
final class DayMessage {
  const DayMessage(this.runId, this.text);

  final String runId;
  final String text;
}

/// Runs whose laps can be compared, with their ranking.
final class DayGroup {
  const DayGroup({
    required this.id,
    required this.resolved,
    required this.label,
    required this.configuration,
    required this.runIds,
    required this.lapCount,
    required this.eligibleLapCount,
    this.ranking,
  });

  /// The `compatibility-v1` id, or `unresolved:` and the run id.
  final String id;
  final bool resolved;

  /// "Group 1 · Detected route · Clockwise", or "Unresolved · Session 2".
  final String label;
  final TrackConfiguration configuration;
  final List<String> runIds;
  final int lapCount;
  final int eligibleLapCount;

  /// Null for an unresolved group.
  final DayRanking? ranking;
}

/// Everything the day results show.
final class DayAnalysis {
  DayAnalysis({
    required List<DayLapRow> rows,
    required Map<String, TrackConfiguration> configurations,
    required Map<String, TrackInference> inferences,
    required List<DayGroup> groups,
    required this.chosenGroupId,
    required List<DayMessage> messages,
  }) : rows = List.unmodifiable(rows),
       configurations = Map.unmodifiable(configurations),
       inferences = Map.unmodifiable(inferences),
       groups = List.unmodifiable(groups),
       messages = List.unmodifiable(messages);

  /// Every lap section of the day, in recording-time order.
  final List<DayLapRow> rows;
  final Map<String, TrackConfiguration> configurations;
  final Map<String, TrackInference> inferences;
  final List<DayGroup> groups;

  /// The group whose ranking leads the results; null when none is resolved.
  final String? chosenGroupId;
  final List<DayMessage> messages;

  DayGroup? get chosenGroup {
    for (final group in groups) {
      if (group.id == chosenGroupId) return group;
    }
    return null;
  }

  DayRanking? get ranking => chosenGroup?.ranking;
}

/// The `gates-v1` revision of [session]'s timing gates, or null when they
/// are unresolved (not exactly one start gate, an invalid coordinate...).
String? sessionGateRevision(TelemetrySession session) => fet.gatesV1Revision([
  for (final gate in session.timingGates)
    (
      type: switch (gate.type) {
        TimingGateType.start => fet.TimingGateType.start,
        TimingGateType.split => fet.TimingGateType.split,
        TimingGateType.unknown => fet.TimingGateType.unknown,
      },
      aLatitude: gate.endpointA.latitudeDegrees,
      aLongitude: gate.endpointA.longitudeDegrees,
      bLatitude: gate.endpointB.latitudeDegrees,
      bLongitude: gate.endpointB.longitudeDegrees,
    ),
], westPositive: _westPositive(session));

bool _westPositive(TelemetrySession session) =>
    session.metadata['gpsLongitudeConvention'] == 'west-positive';

/// Derives a day: each run's lap rows and route, the groups of runs that
/// share a layout, direction and timing gates, and the ranking of each
/// group. One failing run adds a message and the others continue. The group
/// shown first ([DayAnalysis.chosenGroupId]) is [preferredGroupId] when it
/// is resolved, otherwise the group with the most eligible laps.
DayAnalysis analyzeDay(
  List<DayRunInput> runs, {
  Map<DayLapReference, String> exclusions = const {},
  String? preferredGroupId,
  CancellationCheck? cancelled,
}) {
  if (runs.length > 64) throw const ResourceLimitError('Too many recordings in this day.');
  final rows = <DayLapRow>[];
  final messages = <DayMessage>[];
  final inferences = <String, TrackInference>{};
  final sources = <TrackGroupingSource>[];
  for (var index = 0; index < runs.length; ++index) {
    throwIfCancelled(cancelled);
    final run = runs[index];
    try {
      final runRows = dayLapRows(
        run.session,
        run.laps,
        runId: run.runId,
        runName: run.name,
        sourceRevision: run.contentSha256,
        sourceOrder: index,
        cancelled: cancelled,
      );
      if (runRows.length > maximumDayLapRows - rows.length) {
        throw const ResourceLimitError('This day exceeds the 20,000 lap-section limit.');
      }
      final inference = inferTrack(
        run.laps,
        longitudeIsWestPositive: _westPositive(run.session),
        cancelled: cancelled,
      );
      inferences[run.runId] = inference;
      sources.add(
        TrackGroupingSource(
          runId: run.runId,
          contentSha256: run.contentSha256,
          manual: run.manual,
          configuration: TrackConfiguration(
            layoutId: run.layoutName,
            direction: run.direction,
            gateRevision: sessionGateRevision(run.session),
          ),
        ),
      );
      if (run.session.metadata['firstTimestampMilliseconds'] == null) {
        messages.add(
          DayMessage(
            run.runId,
            'Recording date and time unavailable; listed after the dated recordings in import order.',
          ),
        );
      }
      if (run.laps.acceptedPasses.isEmpty) {
        messages.add(
          DayMessage(run.runId, 'No reliable start/finish passes; lap type is unknown.'),
        );
      }
      if (!inference.supported && !run.manual) {
        messages.add(DayMessage(run.runId, inference.reason));
      }
      rows.addAll(runRows);
    } on OperationCancelled {
      rethrow;
    } on Exception catch (error) {
      messages.add(DayMessage(run.runId, '$error'));
    }
  }
  throwIfCancelled(cancelled);
  final grouped = groupInferredTracks(
    {
      for (final source in sources)
        if (!source.manual) source.runId: inferences[source.runId]!,
    },
    sources,
    cancelled: cancelled,
  );
  grouped.reasons.forEach((runId, reason) => messages.add(DayMessage(runId, reason)));
  final manualRuns = {
    for (final source in sources)
      if (source.manual) source.runId,
  };
  final marked = [
    for (final row in rows)
      if (row.type == LapSectionType.lap &&
          row.referenceEligible &&
          !manualRuns.contains(row.runId) &&
          (grouped.configurations[row.runId]?.detectedRoute ?? false) &&
          !(inferences[row.runId]?.matchingLaps.contains(row.lapNumber) ?? false))
        row.copyWith(offRoute: true)
      else
        row,
  ];
  return _assemble(
    sortDayLaps(marked),
    grouped.configurations,
    inferences,
    messages,
    exclusions,
    preferredGroupId,
    cancelled,
  );
}

/// [day] ranked again with new [exclusions] or another [preferredGroupId].
/// Rows, routes and groups are kept, so this is cheap enough for the
/// interface thread.
DayAnalysis rerankDay(
  DayAnalysis day, {
  Map<DayLapReference, String> exclusions = const {},
  String? preferredGroupId,
}) => _assemble(
  day.rows,
  day.configurations,
  day.inferences,
  day.messages,
  exclusions,
  preferredGroupId,
  null,
);

DayAnalysis _assemble(
  List<DayLapRow> sorted,
  Map<String, TrackConfiguration> configurations,
  Map<String, TrackInference> inferences,
  List<DayMessage> messages,
  Map<DayLapReference, String> exclusions,
  String? preferredGroupId,
  CancellationCheck? cancelled,
) {
  final groups = _groups(sorted, configurations, exclusions, cancelled);
  String? chosen;
  if (preferredGroupId != null &&
      groups.any((group) => group.resolved && group.id == preferredGroupId)) {
    chosen = preferredGroupId;
  } else {
    DayGroup? best;
    for (final group in groups) {
      if (group.resolved && (best == null || group.eligibleLapCount > best.eligibleLapCount)) {
        best = group;
      }
    }
    chosen = best?.id;
  }
  return DayAnalysis(
    rows: sorted,
    configurations: configurations,
    inferences: inferences,
    groups: groups,
    chosenGroupId: chosen,
    messages: messages,
  );
}

List<DayGroup> _groups(
  List<DayLapRow> rows,
  Map<String, TrackConfiguration> configurations,
  Map<DayLapReference, String> exclusions,
  CancellationCheck? cancelled,
) {
  final order = <String>[];
  final members = <String, List<String>>{};
  final names = <String, String>{};
  for (final row in rows) {
    final configuration = configurations[row.runId] ?? const TrackConfiguration();
    final id = configuration.compatibilityGroupId ?? 'unresolved:${row.runId}';
    final runs = members.putIfAbsent(id, () {
      order.add(id);
      return [];
    });
    if (!runs.contains(row.runId)) runs.add(row.runId);
    names.putIfAbsent(row.runId, () => row.runName);
  }
  final result = <DayGroup>[];
  var number = 0;
  for (final id in order) {
    throwIfCancelled(cancelled);
    final runIds = members[id]!;
    final configuration = configurations[runIds.first] ?? const TrackConfiguration();
    final resolved = !id.startsWith('unresolved:');
    final lapCount = rows
        .where((row) => row.type == LapSectionType.lap && runIds.contains(row.runId))
        .length;
    if (!resolved) {
      result.add(
        DayGroup(
          id: id,
          resolved: false,
          label: 'Unresolved · ${names[runIds.first]}',
          configuration: configuration,
          runIds: List.unmodifiable(runIds),
          lapCount: lapCount,
          eligibleLapCount: 0,
        ),
      );
      continue;
    }
    final ranking = rankDayLaps(rows, id, configurations, exclusions: exclusions);
    final layout = configuration.detectedRoute ? 'Detected route' : configuration.layoutId!;
    result.add(
      DayGroup(
        id: id,
        resolved: true,
        label: 'Group ${++number} · $layout · ${configuration.direction!.label}',
        configuration: configuration,
        runIds: List.unmodifiable(runIds),
        lapCount: lapCount,
        eligibleLapCount: ranking.eligibleLapCount,
        ranking: ranking,
      ),
    );
  }
  return result;
}
