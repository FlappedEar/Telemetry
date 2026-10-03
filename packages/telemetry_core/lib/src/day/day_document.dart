// A day saved as a version 3 `.fetproject` document and opened again
// (FET-26). The document is the one FlappedEar Overlays reads: runs with
// their recordings, track configurations and lap exclusions.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart' as fet;

import '../analysis/automatic_segments.dart';
import '../intake/import_plan.dart';
import '../intake/recording_source.dart';
import '../operation.dart';
import '../source_fingerprint.dart';
import 'compatibility.dart';
import 'day_analysis.dart';
import 'day_fusion.dart';
import 'day_laps.dart';
import 'run_metadata.dart';
import 'track_inference.dart';

/// A new event id: 32 random lowercase hex digits.
String newEventId([Random? random]) {
  final source = random ?? Random.secure();
  return [for (var i = 0; i < 16; ++i) source.nextInt(256).toRadixString(16).padLeft(2, '0')]
      .join();
}

/// The default name of a day: "Day 2026-09-27" from the first dated
/// recording, or "Day" when none is dated.
String defaultDayName(List<NamedRun> runs) {
  int? first;
  for (final named in runs) {
    final start = recordingTimestamp(named.run.telemetry);
    if (start != null && (first == null || start < first)) first = start;
  }
  if (first == null) return 'Day';
  final date = DateTime.fromMillisecondsSinceEpoch(first, isUtc: true);
  String two(int value) => value.toString().padLeft(2, '0');
  return 'Day ${date.year}-${two(date.month)}-${two(date.day)}';
}

Map<String, Object?> _copy(Map<String, Object?>? value) =>
    value == null ? {} : fet.qtJsonDecode(jsonEncode(value)) as Map<String, Object?>;

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

/// [run]'s primary telemetry source entry, or null.
Map<String, Object?>? _primarySource(Map<String, Object?> run) {
  final telemetry = _object(run['sources'])?['telemetry'];
  if (telemetry is! List) return null;
  for (final value in telemetry) {
    final source = _object(value);
    if (source != null && source['id'] == run['primaryTelemetrySourceId']) return source;
  }
  return null;
}

Map<String, Object?> _rebaseVideo(Map<String, Object?> video, String from, String to) {
  final chapters = video['chapters'];
  final rebased = fet.rebaseReference(video, from, to);
  if (chapters is List && chapters.isNotEmpty) {
    rebased['chapters'] = [
      for (final chapter in chapters) fet.rebaseReference(_object(chapter) ?? {}, from, to),
    ];
  }
  return rebased;
}

/// [run] (a document run that was not opened) with its references moved to
/// the document at [to].
Map<String, Object?> _rebaseRun(Map<String, Object?> run, String from, String to) {
  if (from == to) return run;
  final sources = _object(run['sources']);
  if (sources == null) return run;
  final telemetry = sources['telemetry'];
  if (telemetry is List) {
    sources['telemetry'] = [
      for (final value in telemetry)
        if (_object(value) case final source?)
          {
            ...source,
            'reference': fet.rebaseReference(_object(source['reference']) ?? {}, from, to),
          }
        else
          value,
    ];
  }
  if (_object(sources['video']) case final video?) {
    sources['video'] = _rebaseVideo(video, from, to);
  }
  return run;
}

Map<String, Object?> _unknownConfiguration(
  String sourceId,
  Map<String, Object?> fingerprint,
  String? gates,
) => {
  'layoutId': null,
  'direction': 'unknown',
  'gateRevision': gates,
  'sourceId': sourceId,
  'sourceFingerprint': fingerprint,
};

/// A comparison of two laps as Overlays saves it in the event's
/// `analysisDecisions` (KAN-41, FET-53): the A/B pair, the range shown on
/// the shared track-position axis and the charts shown. When writing
/// ([dayDocument]), a null field keeps what the document has; when read
/// ([OpenedDay.comparison]), a null field is not saved or not usable.
final class ComparisonDecisions {
  const ComparisonDecisions({this.slots, this.range, this.channels});

  /// Laps A and B; an entry is null when that slot is empty, or (read back)
  /// when its lap is not one of this day's any more (a changed recording or
  /// lap derivation): the document then keeps it as it was, unapplied.
  final List<DayLapReference?>? slots;

  /// The range shown, in meters along the shared axis.
  final (double, double)? range;

  /// The charts shown, by channel name ("Δ time" included), at
  /// most [fet.maximumComparisonChannels].
  final List<String>? channels;

  bool get isEmpty => slots == null && range == null && channels == null;

  /// [other]'s fields where it has them, this one's elsewhere.
  ComparisonDecisions overriddenBy(ComparisonDecisions other) => ComparisonDecisions(
    slots: other.slots ?? slots,
    range: other.range ?? range,
    channels: other.channels ?? channels,
  );

  /// Whether Overlays accepts [range] (finite, from 0, increasing, bounded).
  static bool validRange((double, double) range) =>
      range.$1.isFinite &&
      range.$2.isFinite &&
      range.$1 >= 0 &&
      range.$2 > range.$1 &&
      range.$2 <= fet.maximumComparisonRangeMeters;

  /// Whether Overlays accepts [channels]: at most four distinct names, each
  /// as its `validText` (not blank once trimmed, no NUL, bounded).
  static bool validChannels(List<String> channels) =>
      channels.length <= fet.maximumComparisonChannels &&
      channels.toSet().length == channels.length &&
      channels.every(
        (name) =>
            fet.qtTrimmed(name).isNotEmpty &&
            !name.contains('\u0000') &&
            name.length <= fet.maximumIdCharacters,
      );
}

/// The version 3 document of a day, to be saved at [projectPath].
///
/// [previous] is the document the day was opened from (saved at
/// [previousPath]), or null for a new day: everything in it that this app does
/// not manage is kept, including runs whose recordings could not be opened.
/// Each opened run gets its recording's reference (relative to [projectPath]
/// when close enough), content SHA-256 and fingerprint, the user's layout and
/// direction or the unknown configuration, and the detected route's
/// provenance. Exclusions become lap references with this event's id.
///
/// [trackSegments] replaces runs' `trackSegments` by run id (the segments the
/// user edited; an empty list removes the key, as Overlays stores it), before
/// anything else is decided about segments.
///
/// With [automaticSegments], the chosen group's best lap gets its segment
/// proposals as approved `trackSegments` when no run has segments for the
/// group yet ([automaticTrackSegments]); [random] mints their ids.
///
/// [groupChosen] says the user chose the group shown: it is saved as
/// `analysisDecisions.comparisonGroupId`. Otherwise the document's saved
/// group, or its absence, is kept as it was, as Overlays writes the group
/// only when the user chooses one (`selectOutingComparisonGroup`), so a day
/// whose group was never chosen stays "automatic".
///
/// [comparison] is the comparison the user set up (see
/// [ComparisonDecisions]); its null fields keep the document's.
///
/// [fusions] are the runs' alternative recordings by run id: each one is
/// written as a source of its run, and a fused run gets its `fusion`
/// decision. A run whose alternative could not be aligned or used keeps the
/// document's decision as it was (no longer bound to its recordings, so not
/// applied), a run whose alternative the user keeps apart
/// ([RunFusionState.primaryOnly]) has its decision removed, and a run
/// without one keeps its sources as they were.
/// [pendingAlternatives] are alternative recordings not fused yet, by run
/// id: each is written as a source, so the day opened again aligns it, and
/// the run's decision stays as it was.
///
/// [runMetadata] are the user's edits of runs' names, notes, conditions and
/// setup changes by run id, written as Overlays writes them
/// ([applyRunMetadata]).
///
/// Reads each recording's first, middle and last 64 KiB for its fingerprint.
Map<String, Object?> dayDocument({
  required String eventId,
  required String name,
  required List<NamedRun> runs,
  required DayAnalysis analysis,
  Map<DayLapReference, String> exclusions = const {},
  required String projectPath,
  Map<String, Object?>? previous,
  String previousPath = '',
  Map<String, List<Map<String, Object?>>> trackSegments = const {},
  bool automaticSegments = true,
  bool groupChosen = false,
  ComparisonDecisions comparison = const ComparisonDecisions(),
  Map<String, RunFusion> fusions = const {},
  Map<String, TelemetryRunProposal> pendingAlternatives = const {},
  Map<String, RunMetadata> runMetadata = const {},
  Random? random,
}) {
  final chosenGroup = analysis.chosenGroup;
  final document = _copy(previous);
  final event = _object(document['event']) ?? <String, Object?>{};
  final previousRuns = <String, Map<String, Object?>>{};
  final order = <String>[];
  if (event['runs'] case final List<Object?> stored) {
    for (final value in stored) {
      if (_object(value) case final run? when run['id'] is String) {
        previousRuns[run['id'] as String] = run;
        order.add(run['id'] as String);
      }
    }
  }
  final opened = <String, Map<String, Object?>>{};
  for (final named in runs) {
    final run = named.run;
    final fingerprint = telemetryFingerprint(run.sourcePath, run.telemetry);
    final json = previousRuns[run.id] ?? <String, Object?>{};
    json['id'] = run.id;
    json['name'] = named.name;
    json['primaryTelemetrySourceId'] = run.sourceId;
    final sources = _object(json['sources']) ?? <String, Object?>{};
    final telemetry = <Object?>[];
    var primaryWritten = false;
    final fusion = fusions[run.id];
    // An RCZ added and not aligned yet replaces the one the run's fusion
    // could use.
    final pending = pendingAlternatives[run.id];
    final alternative = pending ?? fusion?.alternative;
    var alternativeWritten = alternative == null;
    for (final value in (sources['telemetry'] as List?) ?? const []) {
      final source = _object(value);
      if (source == null) continue;
      if (source['id'] == run.sourceId) {
        primaryWritten = true;
        telemetry.add(_sourceEntry(source, run, fingerprint, projectPath));
      } else if (alternative != null && source['id'] == alternative.sourceId) {
        alternativeWritten = true;
        telemetry.add(
          _sourceEntry(
            source,
            alternative,
            telemetryFingerprint(alternative.sourcePath, alternative.telemetry),
            projectPath,
          ),
        );
      } else {
        telemetry.add({
          ...source,
          'reference': fet.rebaseReference(
            _object(source['reference']) ?? {},
            previousPath,
            projectPath,
          ),
        });
      }
    }
    if (!primaryWritten) {
      telemetry.insert(0, _sourceEntry({'id': run.sourceId}, run, fingerprint, projectPath));
    }
    if (!alternativeWritten && telemetry.length < fet.maximumSourcesPerRun) {
      telemetry.add(
        _sourceEntry(
          {'id': alternative!.sourceId},
          alternative,
          telemetryFingerprint(alternative.sourcePath, alternative.telemetry),
          projectPath,
        ),
      );
      alternativeWritten = true;
    }
    sources['telemetry'] = telemetry;
    if (fusion?.decision case final decision? when alternativeWritten && pending == null) {
      json['fusion'] = decision;
    } else if (fusion?.state == RunFusionState.primaryOnly && pending == null) {
      // Refused, or the primary changed: no fusion, as Overlays removes it.
      json.remove('fusion');
    }
    if (_object(sources['video']) case final video?) {
      sources['video'] = _rebaseVideo(video, previousPath, projectPath);
    }
    json['sources'] = sources;
    json['sync'] ??= {'offset': 0.0, 'timeScale': 1.0};
    final gates = sessionGateRevision(run.telemetry);
    final manual = analysis.manualTracks[run.id];
    json['trackConfiguration'] = manual == null
        ? _unknownConfiguration(run.sourceId, fingerprint, gates)
        : {
            ..._unknownConfiguration(run.sourceId, fingerprint, gates),
            'layoutId': manual.layoutId,
            'direction': manual.direction?.name ?? 'unknown',
          };
    final configuration = analysis.configurations[run.id];
    final route = analysis.inferences[run.id]?.route;
    if (manual == null && route != null && configuration != null && configuration.detectedRoute) {
      json['trackInference'] = {
        'algorithm': trackInferenceVersion,
        'sourceRevision': run.contentSha256,
        'gateRevision': gates,
        'layoutId': configuration.layoutId,
        'direction': route.direction.name,
      };
    } else {
      json.remove('trackInference');
    }
    opened[run.id] = json;
    if (!order.contains(run.id)) order.add(run.id);
  }
  final allRuns = [
    for (final id in order) opened[id] ?? _rebaseRun(previousRuns[id]!, previousPath, projectPath),
  ];
  for (final run in allRuns) {
    final edited = trackSegments[run['id']];
    if (edited == null) continue;
    if (edited.isEmpty) {
      run.remove('trackSegments');
    } else {
      run['trackSegments'] = _copy({'segments': edited})['segments'];
    }
  }
  for (final run in allRuns) {
    if (runMetadata[run['id']] case final metadata?) applyRunMetadata(run, metadata);
  }
  if (automaticSegments) _approveAutomaticSegments(allRuns, opened, runs, analysis, random);

  // A lap reference of [reference]'s run as the document names it: of the
  // run's current recording, or of the other recording it keeps beside it
  // (a lap of the primary before "Make primary", FET-57), named as that
  // recording's laps are when it is the primary again. Null when it is of
  // neither.
  final current = {for (final named in runs) named.run.id: named.run};
  Map<String, Object?>? referenceJson(DayLapReference reference) {
    final run = opened[reference.runId];
    final recording = current[reference.runId];
    if (run == null || recording == null || reference.type != LapSectionType.lap) return null;
    if (reference.sourceRevision == recording.contentSha256) {
      return _lapReferenceJson(eventId, run, reference);
    }
    final other = fusions[reference.runId]?.alternative;
    if (other == null || other.contentSha256 != reference.sourceRevision) return null;
    return _lapReferenceJson(eventId, _asPrimary(run, other), reference);
  }

  final exclusionEntries = <Object?>[];
  final kept = <String>{};
  if (event['lapExclusions'] case final List<Object?> stored) {
    // Exclusions of runs that were not opened stay as they were, and so do
    // those of a recording an opened run does not read now or of another
    // lap derivation (as Overlays keeps them): they apply again when that
    // recording is the run's primary again. The others are written from
    // [exclusions].
    for (final value in stored) {
      final reference = _object(_object(value)?['reference']);
      final runId = reference?['runId'];
      final run = opened[runId];
      final applies =
          run != null &&
          reference?['sourceRevision'] == current[runId]?.contentSha256 &&
          reference?['derivationKey'] == fet.lapDerivationV1Key(run);
      if (!applies) {
        exclusionEntries.add(value);
        if (reference != null) kept.add(_lapIdentity(reference));
      }
    }
  }
  final sorted = exclusions.entries.toList()
    ..sort((a, b) {
      final byRun = order.indexOf(a.key.runId).compareTo(order.indexOf(b.key.runId));
      return byRun != 0 ? byRun : a.key.startTime.compareTo(b.key.startTime);
    });
  for (final MapEntry(key: reference, value: reason) in sorted) {
    final json = referenceJson(reference);
    // A lap kept as stored is not written twice.
    if (json == null || kept.contains(_lapIdentity(json))) continue;
    exclusionEntries.add({'reference': json, 'reason': reason});
  }

  // The comparison decisions, as Overlays saves them: the group only when
  // the user chose one (a saved group this day cannot show, or none, stays
  // as it was), and the comparison's pair, range and charts the user set up.
  // Keys this app does not know are kept; the object is added only when
  // something is decided, as Overlays adds it.
  final decisions = _object(event['analysisDecisions']) ?? <String, Object?>{};
  if (groupChosen) {
    decisions['comparisonGroupId'] = chosenGroup != null && chosenGroup.resolved
        ? chosenGroup.id
        : null;
  }
  if (comparison.slots case final slots? when slots.length == 2) {
    final written = [
      for (final reference in slots) reference == null ? null : referenceJson(reference),
    ];
    // A lap of a run that was not opened cannot be named: the pair is not changed.
    if (written.indexed.every((entry) => entry.$2 != null || slots[entry.$1] == null)) {
      decisions['comparisonSlots'] = written;
    }
  }
  if (comparison.range case final range? when ComparisonDecisions.validRange(range)) {
    decisions['comparisonRange'] = {'startMeters': range.$1, 'endMeters': range.$2};
  }
  if (comparison.channels case final channels? when ComparisonDecisions.validChannels(channels)) {
    decisions['comparisonChannels'] = [...channels];
  }
  if (decisions.isNotEmpty || event.containsKey('analysisDecisions')) {
    event['analysisDecisions'] = decisions;
  }
  event['id'] = eventId;
  event['name'] = name;
  event['runs'] = allRuns;
  if (!order.contains(event['activeRunId'])) event['activeRunId'] = order.first;
  if (exclusionEntries.isEmpty) {
    event.remove('lapExclusions');
  } else {
    event['lapExclusions'] = exclusionEntries;
  }
  for (final key in ['sources', 'sync', 'videoPath', 'vboPath']) {
    document.remove(key);
  }
  document['version'] = 3;
  document['event'] = event;
  document['documentState'] = nextDocumentState(_object(document['documentState']));
  return document;
}

/// [run] (a document run) as it is saved with [recording] as its primary,
/// as far as its laps are named ([fet.lapDerivationV1Key]): the recording's
/// source and the unknown track configuration, as "Make primary" leaves it.
Map<String, Object?> _asPrimary(Map<String, Object?> run, TelemetryRunProposal recording) {
  final fingerprint = telemetryFingerprint(recording.sourcePath, recording.telemetry);
  return {
    ...run,
    'primaryTelemetrySourceId': recording.sourceId,
    'sources': {
      'telemetry': [
        {
          'id': recording.sourceId,
          'reference': {'fingerprint': fingerprint},
        },
      ],
    },
    'trackConfiguration': _unknownConfiguration(
      recording.sourceId,
      fingerprint,
      sessionGateRevision(recording.telemetry),
    ),
  };
}

/// The lap exclusions [document] keeps for run [runId]'s laps of
/// [recording] that apply once it is the run's primary again ("Make
/// primary", FET-57): those named with its content and the lap derivation
/// it then has. What the day excludes again when the run switches back.
Map<DayLapReference, String> recordingExclusions(
  Map<String, Object?>? document,
  String runId,
  TelemetryRunProposal recording,
) {
  final event = _object(document?['event']);
  final runs = event?['runs'];
  Map<String, Object?>? run;
  for (final value in runs is List ? runs : const []) {
    if (_object(value) case final candidate? when candidate['id'] == runId) run = candidate;
  }
  final stored = event?['lapExclusions'];
  if (run == null || stored is! List) return const {};
  final asPrimary = {runId: _asPrimary(run, recording)};
  final loaded = {runId: recording.contentSha256};
  final result = <DayLapReference, String>{};
  for (final value in stored) {
    if (_object(value)
        case {'reference': final Map<String, Object?> reference, 'reason': final String reason}
        when reference['runId'] == runId && reference['type'] == LapSectionType.lap.label) {
      final applied = _appliedLapReference(reference, asPrimary, loaded);
      if (applied != null) result[applied] = reason;
    }
  }
  return result;
}

/// The lap a document's lap reference names, whatever lap derivation it
/// was named with: its run, recording, type and times.
String _lapIdentity(Map<String, Object?> reference) => fet.qtCompactJson([
  reference['runId'],
  reference['sourceRevision'],
  reference['type'],
  reference['startTime'],
  reference['endTime'],
]);

/// [reference] as a document's lap reference (`source-laps-v1`) of [run].
Map<String, Object?> _lapReferenceJson(
  String eventId,
  Map<String, Object?> run,
  DayLapReference reference,
) => {
  'version': 1,
  'algorithm': fet.lapReferenceAlgorithm,
  'eventId': eventId,
  'runId': reference.runId,
  'sourceId': run['primaryTelemetrySourceId'],
  'sourceRevision': reference.sourceRevision,
  'derivationKey': fet.lapDerivationV1Key(run),
  'type': reference.type.label,
  'startTime': reference.startTime,
  'endTime': reference.endTime,
};

/// Segments without manual review (Overlays KAN-136): when no run stores
/// segments approved for the chosen group, the proposals of the group's best
/// lap are approved into that lap's run. They are ordinary approved segments,
/// kept on later saves like any others.
void _approveAutomaticSegments(
  List<Map<String, Object?>> allRuns,
  Map<String, Map<String, Object?>> opened,
  List<NamedRun> runs,
  DayAnalysis analysis,
  Random? random,
) {
  final group = analysis.chosenGroup;
  final best = analysis.ranking?.bestOfDay;
  if (group == null || !group.resolved || best == null) return;
  final json = opened[best.runId];
  if (json == null || !group.runIds.contains(best.runId)) return;
  for (final named in runs) {
    if (named.run.id != best.runId) continue;
    final segments = automaticTrackSegments(
      documentRuns: allRuns,
      groupId: group.id,
      storedSegments: json['trackSegments'],
      session: named.run.telemetry,
      laps: named.run.laps,
      lapNumber: best.lapNumber,
      startTime: best.start,
      endTime: best.end,
      random: random,
    );
    if (segments != null) json['trackSegments'] = segments;
    return;
  }
}

/// A random UUID (version 4) without braces, as Qt's
/// `QUuid::createUuid().toString(QUuid::WithoutBraces)` writes it.
String newDocumentId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = [for (var i = 0; i < 16; ++i) source.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

final _maximumRevision = BigInt.parse('18446744073709551615');

/// The `documentState` of the next save after [previous]: the same `id`
/// (a new one when it is missing or malformed, as Overlays does) and
/// `savedRevision` one higher, so Overlays treats its own older recovery
/// snapshot of this document as stale. Other keys are kept.
Map<String, Object?> nextDocumentState(Map<String, Object?>? previous) {
  final state = _copy(previous);
  final id = state['id'];
  final revision = state['savedRevision'];
  final parsed = revision is String && RegExp(r'^[0-9]{1,20}$').hasMatch(revision)
      ? BigInt.parse(revision)
      : null;
  if (id is! String ||
      id.isEmpty ||
      id.length > 128 ||
      parsed == null ||
      parsed > _maximumRevision) {
    state['id'] = newDocumentId();
    state['savedRevision'] = '1';
  } else {
    state['savedRevision'] = (parsed < _maximumRevision ? parsed + BigInt.one : parsed).toString();
  }
  return state;
}

/// The document entry of [run]'s recording (a run's primary or alternative
/// source): its reference, content SHA-256 and import provenance.
Map<String, Object?> _sourceEntry(
  Map<String, Object?> source,
  TelemetryRunProposal run,
  Map<String, Object?> fingerprint,
  String projectPath,
) {
  final stored = _object(source['reference']) ?? const <String, Object?>{};
  final provenance = _object(source['importProvenance']);
  return {
    ...source,
    'id': run.sourceId,
    'contentSha256': run.contentSha256,
    'reference': {
      for (final entry in stored.entries)
        if (!const {'relativePath', 'absolutePath', 'fingerprint'}.contains(entry.key))
          entry.key: entry.value,
      ...fet.SourceReference(
        absolutePath: run.sourcePath,
        fingerprint: fingerprint,
      ).toJson(projectPath),
    },
    // The import's provenance stays while it is this content's; a file
    // that now holds another recording of the same drive gets its own.
    'importProvenance': provenance != null && provenance['sha256'] == run.contentSha256
        ? provenance
        : {'sha256': run.contentSha256, 'format': run.format.name, 'fingerprint': fingerprint},
  };
}

/// A run of an opened document whose recording could not be used.
final class MissingRecording {
  const MissingRecording({
    required this.runId,
    required this.name,
    required this.path,
    required this.reason,
    this.contentSha256 = '',
    this.fingerprint = const {},
  });

  final String runId;
  final String name;

  /// The path the document names, relative when it has one.
  final String path;
  final String reason;

  /// The recording's content SHA-256 as the document asserts it; empty when
  /// it asserts none.
  final String contentSha256;

  /// The recording's `telemetry-v1` fingerprint as the document stores it;
  /// empty when it has none.
  final Map<String, Object?> fingerprint;
}

/// A day read back from a document.
final class OpenedDay {
  const OpenedDay({
    required this.path,
    required this.document,
    required this.eventId,
    required this.name,
    required this.runs,
    required this.exclusions,
    required this.missing,
    required this.analysis,
    this.alternatives = const {},
    this.relinked = const {},
    this.comparison = const ComparisonDecisions(),
  });

  /// The comparison the document saved: its laps of this day (a stale one
  /// is null), range and charts.
  final ComparisonDecisions comparison;

  /// The runs' alternative recordings as the document names them, by run
  /// id, also of runs whose recording is [missing] (to find them both when
  /// relinking). Not read yet: [resolveDocumentAlternative] reads, checks
  /// and fuses those of opened runs in the background once the day shows.
  final Map<String, DocumentAlternative> alternatives;

  /// The alternative recordings of the runs whose recording is [missing],
  /// to look for with them ([findMovedRecordings]).
  List<MissingRecording> get missingAlternatives => [
    for (final recording in missing)
      if (alternatives[recording.runId] case final alternative?)
        alternative.missing(recording.name, 'Recording not found.'),
  ];

  final String path;

  /// The document as read: what [dayDocument] keeps when saving again.
  final Map<String, Object?> document;
  final String eventId;
  final String name;

  /// The runs whose recordings were found and verified, in document order.
  final List<NamedRun> runs;
  final Map<DayLapReference, String> exclusions;
  final List<MissingRecording> missing;

  /// Null when no recording could be opened.
  final DayAnalysis? analysis;

  /// The runs whose recording was found somewhere else than the document
  /// says and verified: the day has changes until saved, and saving writes
  /// the new paths (Overlays marks a relinked document dirty).
  final Set<String> relinked;
}

/// A document's lap [reference] as a reference to a lap of this day, or null
/// when it is stale for the run's recording or lap derivation (kept in the
/// document, not applied). [runs] are the document's runs by id, [loaded]
/// the content SHA-256 of each opened run's recording.
DayLapReference? _appliedLapReference(
  Map<String, Object?> reference,
  Map<Object?, Map<String, Object?>> runs,
  Map<String, String> loaded,
) {
  final runId = reference['runId'];
  final run = runs[runId];
  if (run == null ||
      loaded[runId] != reference['sourceRevision'] ||
      reference['derivationKey'] != fet.lapDerivationV1Key(run)) {
    return null;
  }
  return DayLapReference(
    runId: runId as String,
    sourceRevision: reference['sourceRevision'] as String,
    type: LapSectionType.lap,
    startTime: (reference['startTime'] as num).toDouble(),
    endTime: (reference['endTime'] as num).toDouble(),
  );
}

/// The comparison [document] (a validated day) saves in its
/// `analysisDecisions`, with its laps as laps of the opened [runs]: a lap
/// whose run is not opened, or whose recording or derivation changed, is
/// null.
ComparisonDecisions documentComparison(Map<String, Object?> document, List<NamedRun> runs) {
  final event = _object(document['event']) ?? const <String, Object?>{};
  final decisions = _object(event['analysisDecisions']) ?? const <String, Object?>{};
  final byId = <Object?, Map<String, Object?>>{
    for (final run in ((event['runs'] as List?) ?? const []).whereType<Map<String, Object?>>())
      run['id']: run,
  };
  final loaded = {for (final named in runs) named.run.id: named.run.contentSha256};
  final slots = decisions['comparisonSlots'];
  final range = _object(decisions['comparisonRange']);
  final channels = decisions['comparisonChannels'];
  return ComparisonDecisions(
    slots: slots is List
        ? [
            for (final slot in slots)
              slot is Map<String, Object?> ? _appliedLapReference(slot, byId, loaded) : null,
          ]
        : null,
    range: range != null && range['startMeters'] is num && range['endMeters'] is num
        ? ((range['startMeters']! as num).toDouble(), (range['endMeters']! as num).toDouble())
        : null,
    channels: channels is List
        ? [
            for (final name in channels)
              if (name is String) name,
          ]
        : null,
  );
}

/// The document at [path], refusing a file over the 4 MiB limit first.
Map<String, Object?> readDayDocument(String path) {
  final file = File(path);
  if (!file.existsSync()) throw fet.FetprojectError('$path is not a readable file.');
  final size = file.lengthSync();
  if (size > fet.maximumProjectBytes) {
    throw fet.FetprojectError(
      'The document is $size bytes; the limit is ${fet.maximumProjectBytes} bytes.',
    );
  }
  return fet.decodeFetproject(file.readAsBytesSync());
}

/// The content SHA-256 a document source asserts: its `contentSha256`, or a
/// legacy import's digest while its fingerprint still matches. Empty when it
/// asserts none (Overlays' `sourceContentRevision`).
String _expectedRevision(Map<String, Object?> source) {
  if (source['contentSha256'] case final String digest) return digest;
  final provenance = _object(source['importProvenance']);
  final fingerprint = _object(_object(source['reference'])?['fingerprint']);
  final digest = provenance?['sha256'];
  if (fingerprint != null &&
      fingerprint.isNotEmpty &&
      digest is String &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) &&
      fet.qtCompactJson(provenance?['fingerprint']) == fet.qtCompactJson(fingerprint)) {
    return digest;
  }
  return '';
}

/// Opens the day saved at [path]: reads and validates the document, finds
/// each run's recording (relative path first, then absolute; [relinked]
/// overrides by run id), checks it is the same content, and analyses the day
/// with the saved layouts, exclusions and group shown. A recording that is missing,
/// unreadable or different is listed in [OpenedDay.missing] and the rest of
/// the day still opens. Throws [fet.FetprojectError] for an invalid document.
///
/// [relinkedAlternatives] overrides where runs' alternative recordings are,
/// by run id, as [relinked] does for their recordings.
OpenedDay openDay(
  String path, {
  Map<String, String> relinked = const {},
  Map<String, String> relinkedAlternatives = const {},
  CancellationCheck? cancelled,
}) => openDayDocument(
  readDayDocument(path),
  path,
  relinked: relinked,
  relinkedAlternatives: relinkedAlternatives,
  cancelled: cancelled,
);

/// Opens a day from its already validated [document], whose relative
/// recording paths are relative to [path] (see [openDay]).
OpenedDay openDayDocument(
  Map<String, Object?> document,
  String path, {
  Map<String, String> relinked = const {},
  Map<String, String> relinkedAlternatives = const {},
  CancellationCheck? cancelled,
}) {
  final event = document['event'] as Map<String, Object?>;
  final runs = [for (final value in event['runs'] as List) value as Map<String, Object?>];
  final missing = <MissingRecording>[];
  final candidates = <(Map<String, Object?>, Map<String, Object?>, String)>[];
  MissingRecording missingRecording(
    Map<String, Object?> run,
    Map<String, Object?> source,
    String reason,
  ) => MissingRecording(
    runId: run['id'] as String,
    name: run['name'] as String,
    path: fet.SourceReference.fromJson(_object(source['reference'])!).displayPath,
    reason: reason,
    contentSha256: _expectedRevision(source),
    fingerprint: _object(_object(source['reference'])?['fingerprint']) ?? const {},
  );
  final moved = <String>{};
  for (final run in runs) {
    final source = _primarySource(run)!;
    final reference = fet.SourceReference.fromJson(_object(source['reference'])!);
    final stored = reference.resolve(path);
    final resolved = relinked[run['id']] ?? stored;
    if (relinked.containsKey(run['id']) && resolved != stored) moved.add(run['id'] as String);
    if (resolved.isEmpty) {
      missing.add(missingRecording(run, source, 'Recording not found.'));
    } else {
      candidates.add((run, source, resolved));
    }
  }
  final plan = candidates.isEmpty
      ? null
      : prepareTelemetryImport([for (final (_, _, file) in candidates) file], cancelled: cancelled);
  final named = <NamedRun>[];
  final inputs = <DayRunInput>[];
  final manualTracks = <String, TrackConfiguration>{};
  for (var index = 0; index < candidates.length; ++index) {
    final (run, source, file) = candidates[index];
    final runId = run['id'] as String;
    final runName = run['name'] as String;
    final result = plan!.files[index];
    TelemetryRunProposal? loaded;
    for (final proposal in plan.runs) {
      if (proposal.id == result.runId) loaded = proposal;
    }
    String? problem;
    if (result.status == TelemetryImportFileStatus.error) {
      problem = result.message;
    } else if (result.status == TelemetryImportFileStatus.duplicate) {
      problem = 'The same recording as another session of this day.';
    } else {
      // Overlays' rule: a recording is the same when its content SHA-256 (if
      // the document asserts one) and its fingerprint (if stored) both match.
      // Never by its path or name.
      final expected = _expectedRevision(source);
      final storedFingerprint = _object(_object(source['reference'])?['fingerprint']) ?? const {};
      if (expected.isNotEmpty && expected != loaded!.contentSha256) {
        problem = 'The file found is a different recording.';
      } else if (storedFingerprint.isNotEmpty &&
          fet.qtCompactJson(storedFingerprint) !=
              fet.qtCompactJson(telemetryFingerprint(file, loaded!.telemetry))) {
        problem = 'The file found is a different recording.';
      }
    }
    if (problem != null) {
      missing.add(missingRecording(run, source, problem));
      continue;
    }
    final proposal = TelemetryRunProposal(
      id: runId,
      sourceId: source['id'] as String,
      sourcePath: loaded!.sourcePath,
      format: loaded.format,
      contentSha256: loaded.contentSha256,
      telemetry: loaded.telemetry,
      laps: loaded.laps,
    );
    named.add((run: proposal, name: runName));
    final configuration = fet.runTrackConfiguration(run);
    final layout = configuration['layoutId'];
    final direction = switch (configuration['direction']) {
      'clockwise' => TrackDirection.clockwise,
      'counterclockwise' => TrackDirection.counterclockwise,
      _ => null,
    };
    // Overlays' manualTrackConfiguration: a layout name or a known direction.
    final manual = layout is String || direction != null;
    if (manual) {
      manualTracks[runId] = TrackConfiguration(layoutId: layout as String?, direction: direction);
    }
    inputs.add(
      DayRunInput(
        runId: runId,
        name: runName,
        contentSha256: proposal.contentSha256,
        session: proposal.telemetry,
        laps: proposal.laps,
        layoutName: manual ? layout as String? : null,
        direction: direction,
      ),
    );
  }

  final alternatives = _openAlternatives(runs, path, relinkedAlternatives);

  final exclusions = <DayLapReference, String>{};
  final byId = {for (final run in runs) run['id']: run};
  final loadedIds = {for (final run in named) run.run.id: run.run.contentSha256};
  DayLapReference? applied(Map<String, Object?> reference) =>
      _appliedLapReference(reference, byId, loadedIds);

  for (final value in (event['lapExclusions'] as List?) ?? const []) {
    final entry = value as Map<String, Object?>;
    final reference = applied(entry['reference'] as Map<String, Object?>);
    if (reference != null) exclusions[reference] = entry['reason'] as String;
  }
  final comparison = documentComparison(document, named);
  // The group saved as shown leads again when it is still one of the day's.
  final savedGroup = _object(event['analysisDecisions'])?['comparisonGroupId'];
  final analysis = inputs.isEmpty
      ? null
      : analyzeDay(
          inputs,
          exclusions: exclusions,
          preferredGroupId: savedGroup is String ? savedGroup : null,
          cancelled: cancelled,
        );
  return OpenedDay(
    path: path,
    document: document,
    eventId: event['id'] as String,
    name: event['name'] as String,
    runs: named,
    exclusions: exclusions,
    missing: missing,
    analysis: analysis,
    alternatives: alternatives,
    comparison: comparison,
    relinked: {
      for (final runId in moved)
        if (named.any((run) => run.run.id == runId)) runId,
    },
  );
}

/// A run's alternative recording as an opened document names it (see
/// [OpenedDay.alternatives]).
final class DocumentAlternative {
  const DocumentAlternative({
    required this.runId,
    required this.sourceId,
    required this.path,
    required this.displayPath,
    this.contentSha256 = '',
    this.fingerprint = const {},
    this.decision,
    this.relinked = false,
    this.automatic = true,
  });

  final String runId;

  /// The document's id of the source.
  final String sourceId;

  /// The file to read; empty when it was not found.
  final String path;

  /// The path the document names, relative when it has one.
  final String displayPath;

  /// The recording's content SHA-256 as the document asserts it; empty when
  /// it asserts none.
  final String contentSha256;

  /// Its `telemetry-v1` fingerprint as the document stores it; empty when it
  /// has none.
  final Map<String, Object?> fingerprint;

  /// The run's `fusion` decision, if it has one.
  final Map<String, Object?>? decision;

  /// [path] was found somewhere else than the document says.
  final bool relinked;

  /// Without a [decision], whether it is aligned and fused when the day
  /// opens: the RCZ of a VBO run is (FET-51); the VBO of an RCZ run, as a
  /// run has after "Make primary" (FET-57), is only kept beside it.
  final bool automatic;

  /// The format its name says, or null.
  RecordingFormat? get format => recordingFormatOf(displayPath);

  /// The alternative as a missing recording of run [name], for
  /// [findMovedRecordings].
  MissingRecording missing(String name, String reason) => MissingRecording(
    runId: runId,
    name: name,
    path: displayPath,
    reason: reason,
    contentSha256: contentSha256,
    fingerprint: fingerprint,
  );
}

/// The alternative recording of each run of [runs] that has one: the source
/// its `fusion` decision names, else the first RCZ source of a VBO run
/// ([DocumentAlternative.automatic]), else the first VBO source of an RCZ
/// run (kept beside it, not fused). [relinked] overrides where it is, by run
/// id. Nothing is read.
Map<String, DocumentAlternative> _openAlternatives(
  List<Map<String, Object?>> runs,
  String path,
  Map<String, String> relinked,
) {
  final result = <String, DocumentAlternative>{};
  for (final run in runs) {
    final runId = run['id'] as String;
    final primary = _primarySource(run);
    final telemetry = _object(run['sources'])?['telemetry'];
    if (primary == null || telemetry is! List) continue;
    String displayPath(Map<String, Object?> source) =>
        fet.SourceReference.fromJson(_object(source['reference']) ?? const {}).displayPath;
    final primaryFormat = recordingFormatOf(displayPath(primary));
    final vbo = primaryFormat == RecordingFormat.vbo;
    final rcz = primaryFormat == RecordingFormat.rcz;
    final decision = _object(run['fusion']);
    Map<String, Object?>? source;
    Map<String, Object?>? kept;
    for (final value in telemetry) {
      final candidate = _object(value);
      final id = candidate?['id'];
      if (candidate == null || id == primary['id'] || id is! String) continue;
      if (_object(candidate['reference']) == null) continue;
      final format = recordingFormatOf(displayPath(candidate));
      final chosen = decision != null && decision['alternativeSourceId'] == id;
      final automatic = decision == null && vbo && format == RecordingFormat.rcz;
      if (chosen || (automatic && source == null)) {
        source = candidate;
        if (chosen) break;
      }
      if (decision == null && rcz && format == RecordingFormat.vbo) kept ??= candidate;
    }
    final automatic = source != null;
    source ??= kept;
    if (source == null) continue;
    final reference = fet.SourceReference.fromJson(_object(source['reference'])!);
    final stored = reference.resolve(path);
    final file = relinked[runId] ?? stored;
    result[runId] = DocumentAlternative(
      runId: runId,
      sourceId: source['id'] as String,
      path: file,
      displayPath: reference.displayPath,
      contentSha256: _expectedRevision(source),
      fingerprint: _object(_object(source['reference'])?['fingerprint']) ?? const {},
      decision: decision,
      relinked: file.isNotEmpty && file != stored,
      automatic: automatic,
    );
  }
  return result;
}

/// Reads [alternative] (a document's alternative recording of [primary]),
/// checks it and fuses it: with the document's decision, without aligning
/// again, while that is bound to both recordings' content; otherwise aligned
/// and fused afresh. A file that is not the content the document asserts is
/// used only when it is the same drive as [primary] in the other format
/// ([sameDriveInOtherFormat]): it is then aligned afresh, keeping the
/// decision's rules for channels both still measure ([keepFusionChoices]),
/// and its source entry is updated when the day is saved
/// ([RunFusion.documentChanged]); otherwise it is "a different recording" and
/// nothing is fused. An alternative that is not [DocumentAlternative.automatic]
/// and has no decision is checked and kept beside the primary
/// ([RunFusionState.primaryOnly]), not aligned. A source with neither a content SHA-256 nor a
/// fingerprint is used only when it is the same drive, never by its path
/// alone. Takes seconds: run it in
/// the background.
RunFusion resolveDocumentAlternative(
  TelemetryRunProposal primary,
  DocumentAlternative alternative, {
  CancellationCheck? cancelled,
}) {
  RunFusion unavailable(String reason) => RunFusion.unavailable(
    primarySourceId: primary.sourceId,
    primaryRevision: primary.contentSha256,
    alternativeSourceId: alternative.sourceId,
    alternativeFormat: alternative.format,
    reason: reason,
  );
  if (alternative.path.isEmpty) return unavailable('Recording not found.');
  final plan = prepareTelemetryImport([alternative.path], cancelled: cancelled);
  final status = plan.files.single;
  TelemetryRunProposal? loaded;
  for (final proposal in plan.runs) {
    if (proposal.id == status.runId) loaded = proposal;
  }
  if (status.status == TelemetryImportFileStatus.error || loaded == null) {
    return unavailable(status.message);
  }
  // A file is never accepted only because of its path: without a content
  // SHA-256 or fingerprint to check (as Overlays may write the source), it
  // must be the same drive as the run's recording.
  final identified = alternative.contentSha256.isNotEmpty || alternative.fingerprint.isNotEmpty;
  final same =
      identified &&
      (alternative.contentSha256.isEmpty || alternative.contentSha256 == loaded.contentSha256) &&
      (alternative.fingerprint.isEmpty ||
          fet.qtCompactJson(alternative.fingerprint) ==
              fet.qtCompactJson(telemetryFingerprint(alternative.path, loaded.telemetry)));
  if (!same && !sameDriveInOtherFormat(primary, loaded, cancelled: cancelled)) {
    return unavailable('The file found is a different recording.');
  }
  final changed = identified && !same;
  final recording = TelemetryRunProposal(
    id: loaded.id,
    sourceId: alternative.sourceId,
    sourcePath: loaded.sourcePath,
    format: loaded.format,
    contentSha256: loaded.contentSha256,
    telemetry: loaded.telemetry,
    laps: loaded.laps,
  );
  final fusion = alternative.decision == null && !alternative.automatic
      ? RunFusion.primaryOnly(primary: primary, alternative: recording)
      : fuseWithDecision(primary, recording, alternative.decision, cancelled: cancelled);
  return changed || alternative.relinked ? fusion.withDocumentChanged() : fusion;
}

/// Every alternative recording of [day] resolved and fused
/// ([resolveDocumentAlternative]), by run id: what the app does in the
/// background once the day shows.
Map<String, RunFusion> fuseOpenedDay(OpenedDay day, {CancellationCheck? cancelled}) => {
  for (final named in day.runs)
    if (day.alternatives[named.run.id] case final alternative?)
      named.run.id: resolveDocumentAlternative(named.run, alternative, cancelled: cancelled),
};

/// Writes [document] to [path] atomically (see [fet.writeFetproject]).
Future<void> saveDayDocument(String path, Map<String, Object?> document) =>
    fet.writeFetproject(path, document);
