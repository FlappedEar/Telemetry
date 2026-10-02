// A day saved as a version 3 `.fetproject` document and opened again
// (FET-26). The document is the one FlappedEar Overlays reads: runs with
// their recordings, track configurations and lap exclusions.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart' as fet;

import '../intake/import_plan.dart';
import '../operation.dart';
import '../source_fingerprint.dart';
import 'compatibility.dart';
import 'day_analysis.dart';
import 'day_laps.dart';
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
    for (final value in (sources['telemetry'] as List?) ?? const []) {
      final source = _object(value);
      if (source == null) continue;
      if (source['id'] == run.sourceId) {
        primaryWritten = true;
        telemetry.add(_primaryEntry(source, run, fingerprint, projectPath));
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
      telemetry.insert(0, _primaryEntry({'id': run.sourceId}, run, fingerprint, projectPath));
    }
    sources['telemetry'] = telemetry;
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

  final exclusionEntries = <Object?>[];
  if (event['lapExclusions'] case final List<Object?> stored) {
    // Exclusions of runs that were not opened stay as they were.
    for (final value in stored) {
      final runId = _object(_object(value)?['reference'])?['runId'];
      if (!opened.containsKey(runId)) exclusionEntries.add(value);
    }
  }
  final sorted = exclusions.entries.toList()
    ..sort((a, b) {
      final byRun = order.indexOf(a.key.runId).compareTo(order.indexOf(b.key.runId));
      return byRun != 0 ? byRun : a.key.startTime.compareTo(b.key.startTime);
    });
  for (final MapEntry(key: reference, value: reason) in sorted) {
    final run = opened[reference.runId];
    if (run == null || reference.type != LapSectionType.lap) continue;
    exclusionEntries.add({
      'reference': {
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
      },
      'reason': reason,
    });
  }

  // The group shown, as Overlays saves its comparison choice. Other saved
  // decisions (slots, range, channels) are kept as they were.
  final decisions = _object(event['analysisDecisions']) ?? <String, Object?>{};
  decisions['comparisonGroupId'] = chosenGroup != null && chosenGroup.resolved
      ? chosenGroup.id
      : null;
  event['analysisDecisions'] = decisions;
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
  return document;
}

Map<String, Object?> _primaryEntry(
  Map<String, Object?> source,
  TelemetryRunProposal run,
  Map<String, Object?> fingerprint,
  String projectPath,
) {
  final stored = _object(source['reference']) ?? const <String, Object?>{};
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
    'importProvenance':
        source['importProvenance'] ??
        {'sha256': run.contentSha256, 'format': run.format.name, 'fingerprint': fingerprint},
  };
}

/// A run of an opened document whose recording could not be used.
final class MissingRecording {
  const MissingRecording({
    required this.runId,
    required this.name,
    required this.path,
    required this.reason,
  });

  final String runId;
  final String name;

  /// The path the document names, relative when it has one.
  final String path;
  final String reason;
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
  });

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
/// with the saved layouts and exclusions. A recording that is missing,
/// unreadable or different is listed in [OpenedDay.missing] and the rest of
/// the day still opens. Throws [fet.FetprojectError] for an invalid document.
OpenedDay openDay(
  String path, {
  Map<String, String> relinked = const {},
  CancellationCheck? cancelled,
}) => openDayDocument(readDayDocument(path), path, relinked: relinked, cancelled: cancelled);

/// Opens a day from its already validated [document], whose relative
/// recording paths are relative to [path] (see [openDay]).
OpenedDay openDayDocument(
  Map<String, Object?> document,
  String path, {
  Map<String, String> relinked = const {},
  CancellationCheck? cancelled,
}) {
  final event = document['event'] as Map<String, Object?>;
  final runs = [for (final value in event['runs'] as List) value as Map<String, Object?>];
  final missing = <MissingRecording>[];
  final candidates = <(Map<String, Object?>, Map<String, Object?>, String)>[];
  for (final run in runs) {
    final source = _primarySource(run)!;
    final reference = fet.SourceReference.fromJson(_object(source['reference'])!);
    final resolved = relinked[run['id']] ?? reference.resolve(path);
    if (resolved.isEmpty) {
      missing.add(
        MissingRecording(
          runId: run['id'] as String,
          name: run['name'] as String,
          path: reference.displayPath,
          reason: 'Recording not found.',
        ),
      );
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
      final expected = _expectedRevision(source);
      final storedFingerprint = _object(_object(source['reference'])?['fingerprint']) ?? const {};
      if (expected.isNotEmpty && expected != loaded!.contentSha256) {
        problem = 'The file found is a different recording.';
      } else if (expected.isEmpty &&
          storedFingerprint.isNotEmpty &&
          fet.qtCompactJson(storedFingerprint) !=
              fet.qtCompactJson(telemetryFingerprint(file, loaded!.telemetry))) {
        problem = 'The file found is a different recording.';
      }
    }
    if (problem != null) {
      missing.add(
        MissingRecording(
          runId: runId,
          name: runName,
          path: fet.SourceReference.fromJson(_object(source['reference'])!).displayPath,
          reason: problem,
        ),
      );
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

  final exclusions = <DayLapReference, String>{};
  final byId = {for (final run in runs) run['id']: run};
  final loadedIds = {for (final run in named) run.run.id: run.run.contentSha256};
  for (final value in (event['lapExclusions'] as List?) ?? const []) {
    final entry = value as Map<String, Object?>;
    final reference = entry['reference'] as Map<String, Object?>;
    final runId = reference['runId'];
    final run = byId[runId];
    if (run == null ||
        loadedIds[runId] != reference['sourceRevision'] ||
        reference['derivationKey'] != fet.lapDerivationV1Key(run)) {
      continue; // Stale for this recording or configuration: kept, not applied.
    }
    exclusions[DayLapReference(
          runId: runId as String,
          sourceRevision: reference['sourceRevision'] as String,
          type: LapSectionType.lap,
          startTime: (reference['startTime'] as num).toDouble(),
          endTime: (reference['endTime'] as num).toDouble(),
        )] =
        entry['reason'] as String;
  }
  final analysis = inputs.isEmpty
      ? null
      : analyzeDay(inputs, exclusions: exclusions, cancelled: cancelled);
  return OpenedDay(
    path: path,
    document: document,
    eventId: event['id'] as String,
    name: event['name'] as String,
    runs: named,
    exclusions: exclusions,
    missing: missing,
    analysis: analysis,
  );
}

/// Writes [document] to [path] atomically (see [fet.writeFetproject]).
Future<void> saveDayDocument(String path, Map<String, Object?> document) =>
    fet.writeFetproject(path, document);
