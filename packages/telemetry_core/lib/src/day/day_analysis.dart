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

/// The most recordings one day holds.
const int maximumDayRuns = 64;

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
  const DayMessage(this.runId, this.text, {this.detail = ''});

  final String runId;
  final String text;

  /// For a defect ([unexpectedRunError]): its stack trace, for a bug
  /// report; empty otherwise.
  final String detail;
}

/// How [DayMessage.text] starts when a session's analysis hit a defect (an
/// [Error]); the error follows.
const unexpectedRunError = 'Unexpected error while analysing this session: ';

/// [DayMessage.text] of a session whose laps could not be timed: the
/// start/finish line was not crossed reliably.
const noPassesNote = 'No reliable start/finish passes; lap type is unknown.';

/// [DayMessage.text] of a session without GPS positions, so no laps can be
/// timed whatever the start/finish line.
const noGpsNote = 'No GPS positions in this recording; laps cannot be timed.';

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
    List<TrackGroupingSource> sources = const [],
    List<DayMessage> runMessages = const [],
    Map<String, TrackConfiguration> manualTracks = const {},
  }) : sources = List.unmodifiable(sources),
       runMessages = List.unmodifiable(runMessages),
       manualTracks = Map.unmodifiable(manualTracks),
       rows = List.unmodifiable(rows),
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

  /// Each run's content and gate revision, without the user's layout:
  /// what [regroupDay] groups again.
  final List<TrackGroupingSource> sources;

  /// Messages that do not depend on grouping.
  final List<DayMessage> runMessages;

  /// The user's layout name and direction per run.
  final Map<String, TrackConfiguration> manualTracks;

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

/// Whether [session] has GPS positions to time laps from: latitude and
/// longitude channels, and its [laps] did not report
/// [LapSessionStatus.noUsableGps] (only checked when there is a line). Lap
/// detection checks the start/finish line first, as FlappedEar Overlays
/// does, so a recording without GPS reports a missing line.
bool hasGpsPositions(TelemetrySession session, LapSession laps) =>
    laps.status != LapSessionStatus.noUsableGps &&
    session.channels.containsKey(session.aliases['latitude']) &&
    session.channels.containsKey(session.aliases['longitude']);

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
}) => extendDay(
  null,
  analyzeDayRuns(runs, cancelled: cancelled),
  manualTracks: {
    for (final run in runs)
      if (run.manual)
        run.runId: TrackConfiguration(layoutId: run.layoutName, direction: run.direction),
  },
  exclusions: exclusions,
  preferredGroupId: preferredGroupId,
  cancelled: cancelled,
);

/// The part of a day that each run contributes on its own, before grouping:
/// its lap rows, route and messages. Computed once per run, so a run added
/// to a day is the only one read again ([extendDay]).
final class DayRunsPart {
  DayRunsPart({
    required List<DayLapRow> rows,
    required Map<String, TrackInference> inferences,
    required List<TrackGroupingSource> sources,
    required List<DayMessage> messages,
  }) : rows = List.unmodifiable(rows),
       inferences = Map.unmodifiable(inferences),
       sources = List.unmodifiable(sources),
       messages = List.unmodifiable(messages);

  /// In the order derived, not sorted.
  final List<DayLapRow> rows;
  final Map<String, TrackInference> inferences;
  final List<TrackGroupingSource> sources;
  final List<DayMessage> messages;
}

/// The lap rows, routes and messages of [runs], numbered for import order
/// after [existingRuns] runs and checked against the day's limits with
/// [existingRows] rows already in it. Heavy: run it off the interface
/// thread.
DayRunsPart analyzeDayRuns(
  List<DayRunInput> runs, {
  int existingRuns = 0,
  int existingRows = 0,
  CancellationCheck? cancelled,
}) {
  if (runs.length > maximumDayRuns - existingRuns) {
    throw const ResourceLimitError('Too many recordings in this day.');
  }
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
        sourceOrder: existingRuns + index,
        cancelled: cancelled,
      );
      if (runRows.length > maximumDayLapRows - existingRows - rows.length) {
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
          configuration: TrackConfiguration(gateRevision: sessionGateRevision(run.session)),
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
        // Without GPS no start/finish line could help; say what is missing.
        messages.add(
          DayMessage(run.runId, hasGpsPositions(run.session, run.laps) ? noPassesNote : noGpsNote),
        );
      }
      rows.addAll(runRows);
    } on OperationCancelled {
      rethrow;
    } on Exception catch (error) {
      messages.add(DayMessage(run.runId, '$error'));
    } on Error catch (error, stack) {
      // A defect in one run's analysis leaves the other runs of the day.
      messages.add(DayMessage(run.runId, '$unexpectedRunError$error', detail: '$stack'));
    }
  }
  throwIfCancelled(cancelled);
  return DayRunsPart(rows: rows, inferences: inferences, sources: sources, messages: messages);
}

/// [day] (none for a new day) with the runs of [added], grouped and ranked
/// again with the user's [manualTracks], [exclusions] and
/// [preferredGroupId]. The same day as [analyzeDay] of all the runs, in the
/// same order, without reading the earlier runs again.
DayAnalysis extendDay(
  DayAnalysis? day,
  DayRunsPart added, {
  Map<String, TrackConfiguration> manualTracks = const {},
  Map<DayLapReference, String> exclusions = const {},
  String? preferredGroupId,
  CancellationCheck? cancelled,
}) {
  final known = {for (final source in day?.sources ?? const <TrackGroupingSource>[]) source.runId};
  for (final source in added.sources) {
    if (!known.add(source.runId)) {
      throw ArgumentError.value(source.runId, 'added', 'Run already in the day');
    }
  }
  if (known.length > maximumDayRuns) {
    throw const ResourceLimitError('Too many recordings in this day.');
  }
  return _group(
    sortDayLaps([
      for (final row in day?.rows ?? const <DayLapRow>[])
        row.offRoute ? row.copyWith(offRoute: false) : row,
      ...added.rows,
    ]),
    {...?day?.inferences, ...added.inferences},
    [...?day?.sources, ...added.sources],
    [...?day?.runMessages, ...added.messages],
    manualTracks,
    exclusions,
    preferredGroupId,
    cancelled,
  );
}

/// [day] with run [runId]'s lap rows, route and messages replaced by
/// [replacement]'s (the same run read from another recording: a new primary,
/// FET-57), grouped and ranked again with the user's [manualTracks],
/// [exclusions] and [preferredGroupId]. Every other run is kept as it was,
/// in its place; [replacement]'s rows keep the run's place in the day's
/// order ([DayLapRow.sourceOrder]).
DayAnalysis replaceDayRun(
  DayAnalysis day,
  String runId,
  DayRunsPart replacement, {
  required int sourceOrder,
  Map<String, TrackConfiguration> manualTracks = const {},
  Map<DayLapReference, String> exclusions = const {},
  String? preferredGroupId,
  CancellationCheck? cancelled,
}) {
  if (replacement.sources.any((source) => source.runId != runId) ||
      replacement.rows.any((row) => row.runId != runId)) {
    throw ArgumentError.value(runId, 'replacement', 'Not only run $runId');
  }
  final sources = <TrackGroupingSource>[];
  var placed = false;
  for (final source in day.sources) {
    if (source.runId != runId) {
      sources.add(source);
    } else if (!placed) {
      sources.addAll(replacement.sources);
      placed = true;
    }
  }
  if (!placed) sources.addAll(replacement.sources);
  return _group(
    sortDayLaps([
      for (final row in day.rows)
        if (row.runId != runId) row.offRoute ? row.copyWith(offRoute: false) : row,
      for (final row in replacement.rows) row.copyWith(sourceOrder: sourceOrder),
    ]),
    {
      for (final MapEntry(:key, :value) in day.inferences.entries)
        if (key != runId) key: value,
      ...replacement.inferences,
    },
    sources,
    [
      for (final message in day.runMessages)
        if (message.runId != runId) message,
      ...replacement.messages,
    ],
    manualTracks,
    exclusions,
    preferredGroupId,
    cancelled,
  );
}

/// [day] grouped again with the user's layout name and direction per run in
/// [manualTracks] (a run left out uses its detected route). Rows and routes
/// are kept, so this is cheap enough for the interface thread.
DayAnalysis regroupDay(
  DayAnalysis day, {
  required Map<String, TrackConfiguration> manualTracks,
  Map<DayLapReference, String> exclusions = const {},
  String? preferredGroupId,
}) => _group(
  [for (final row in day.rows) row.offRoute ? row.copyWith(offRoute: false) : row],
  day.inferences,
  day.sources,
  day.runMessages,
  manualTracks,
  exclusions,
  preferredGroupId,
  null,
);

DayAnalysis _group(
  List<DayLapRow> rows,
  Map<String, TrackInference> inferences,
  List<TrackGroupingSource> baseSources,
  List<DayMessage> runMessages,
  Map<String, TrackConfiguration> manualTracks,
  Map<DayLapReference, String> exclusions,
  String? preferredGroupId,
  CancellationCheck? cancelled,
) {
  final sources = [
    for (final source in baseSources)
      if (manualTracks[source.runId] case final manual?)
        TrackGroupingSource(
          runId: source.runId,
          contentSha256: source.contentSha256,
          manual: true,
          configuration: TrackConfiguration(
            layoutId: manual.layoutId,
            direction: manual.direction,
            gateRevision: source.configuration.gateRevision,
          ),
        )
      else
        source,
  ];
  final messages = [...runMessages];
  for (final source in sources) {
    final inference = inferences[source.runId];
    if (!source.manual && inference != null && !inference.supported) {
      messages.add(DayMessage(source.runId, inference.reason));
    }
  }
  final grouped = groupInferredTracks(
    {
      for (final source in sources)
        if (!source.manual && inferences[source.runId] != null)
          source.runId: inferences[source.runId]!,
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
    marked,
    grouped.configurations,
    inferences,
    messages,
    exclusions,
    preferredGroupId,
    cancelled,
    sources: baseSources,
    runMessages: runMessages,
    manualTracks: manualTracks,
  );
}

/// [day] with only the runs [runIds]: the day as it stood before the
/// other runs were added. Grouped again, as adding them would.
DayAnalysis dayWithRuns(
  DayAnalysis day,
  Set<String> runIds, {
  Map<DayLapReference, String> exclusions = const {},
  String? preferredGroupId,
  CancellationCheck? cancelled,
}) => _group(
  [
    for (final row in day.rows)
      if (runIds.contains(row.runId)) row.offRoute ? row.copyWith(offRoute: false) : row,
  ],
  {
    for (final MapEntry(:key, :value) in day.inferences.entries)
      if (runIds.contains(key)) key: value,
  },
  [
    for (final source in day.sources)
      if (runIds.contains(source.runId)) source,
  ],
  [
    for (final message in day.runMessages)
      if (runIds.contains(message.runId)) message,
  ],
  {
    for (final MapEntry(:key, :value) in day.manualTracks.entries)
      if (runIds.contains(key)) key: value,
  },
  {
    for (final MapEntry(:key, :value) in exclusions.entries)
      if (runIds.contains(key.runId)) key: value,
  },
  preferredGroupId,
  cancelled,
);

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
  sources: day.sources,
  runMessages: day.runMessages,
  manualTracks: day.manualTracks,
);

/// [day] with run [runId] named [name] in its lap rows, groups and
/// rankings; everything else as it was. Cheap enough for the interface thread.
DayAnalysis renameDayRun(
  DayAnalysis day,
  String runId,
  String name, {
  Map<DayLapReference, String> exclusions = const {},
  String? preferredGroupId,
}) => _assemble(
  [for (final row in day.rows) row.runId == runId ? row.copyWith(runName: name) : row],
  day.configurations,
  day.inferences,
  day.messages,
  exclusions,
  preferredGroupId ?? day.chosenGroupId,
  null,
  sources: day.sources,
  runMessages: day.runMessages,
  manualTracks: day.manualTracks,
);

DayAnalysis _assemble(
  List<DayLapRow> sorted,
  Map<String, TrackConfiguration> configurations,
  Map<String, TrackInference> inferences,
  List<DayMessage> messages,
  Map<DayLapReference, String> exclusions,
  String? preferredGroupId,
  CancellationCheck? cancelled, {
  List<TrackGroupingSource> sources = const [],
  List<DayMessage> runMessages = const [],
  Map<String, TrackConfiguration> manualTracks = const {},
}) {
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
    sources: sources,
    runMessages: runMessages,
    manualTracks: manualTracks,
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
