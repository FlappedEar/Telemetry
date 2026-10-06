// Taking a session out of a day, and deleting a whole day kept in the
// driver profile (FET-241).
//
// A session is removed from the day's document, which then opens again
// without it: its laps, the theoretical best, the coach and the profile's
// numbers are all worked out again from what is left, as for any day
// opened. The document stays one that FlappedEar Overlays reads: no lap
// exclusion or comparison lap names the session removed.
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;

import 'day_document.dart';

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

/// Why a session cannot be removed from a day's document.
final class RunNotRemoved implements Exception {
  const RunNotRemoved(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [document] (a version 3 day document) without its run [runId]: the run
/// itself, the lap exclusions of its laps, and the comparison laps of it
/// (the slot is emptied, as Overlays saves an empty slot). The active run
/// becomes the first one left when it was [runId]. The saved comparison
/// group and everything else are kept; the group is chosen again when the
/// day no longer has it. Segments approved on the run go with it: the day
/// then approves the proposals of its best lap, as a day without segments
/// does. The document's state is that of a new save
/// ([nextDocumentState]). [document] itself is not changed.
///
/// Throws [RunNotRemoved] when the document has no run [runId] or it is
/// the only one: a day keeps at least one session (Overlays refuses an
/// event without runs).
Map<String, Object?> removeRunFromDayDocument(Map<String, Object?> document, String runId) {
  final copy = jsonDecode(jsonEncode(document)) as Map<String, Object?>;
  final event = _object(copy['event']);
  final runs = event?['runs'];
  if (event == null || runs is! List) throw const RunNotRemoved('The day has no sessions.');
  final kept = [
    for (final run in runs)
      if (_object(run)?['id'] != runId) run,
  ];
  if (kept.length == runs.length) throw RunNotRemoved('The day has no session $runId.');
  if (kept.isEmpty) throw const RunNotRemoved('A day keeps at least one session.');
  event['runs'] = kept;
  if (event['activeRunId'] == runId) {
    event['activeRunId'] = [
      for (final run in kept)
        if (_object(run)?['id'] case final String id) id,
    ].first;
  }
  bool ofRun(Object? reference) => _object(reference)?['runId'] == runId;
  if (event['lapExclusions'] case final List<Object?> exclusions) {
    final left = [
      for (final exclusion in exclusions)
        if (!ofRun(_object(exclusion)?['reference'])) exclusion,
    ];
    if (left.isEmpty) {
      event.remove('lapExclusions');
    } else {
      event['lapExclusions'] = left;
    }
  }
  if (_object(event['analysisDecisions']) case final decisions?) {
    if (decisions['comparisonSlots'] case final List<Object?> slots) {
      decisions['comparisonSlots'] = [for (final slot in slots) ofRun(slot) ? null : slot];
    }
  }
  copy['documentState'] = nextDocumentState(_object(copy['documentState']));
  if (fet.validateFetproject(copy) case final problem?) throw RunNotRemoved(problem);
  return copy;
}

/// [before] (a day's document before a session was removed) to be saved
/// over [current] (the document saved since): [before] one saved revision
/// after [current], so the session comes back as it was (Undo).
Map<String, Object?> restoredDayDocument(
  Map<String, Object?> before,
  Map<String, Object?> current,
) {
  final copy = jsonDecode(jsonEncode(before)) as Map<String, Object?>;
  copy['documentState'] = nextDocumentState(_object(current['documentState']));
  if (fet.validateFetproject(copy) case final problem?) throw RunNotRemoved(problem);
  return copy;
}

/// Whether run [runId] of [document] holds approved segments (the day's
/// corners), which go when it is removed.
bool dayRunHoldsSegments(Map<String, Object?> document, String runId) {
  if (_object(document['event'])?['runs'] case final List<Object?> runs) {
    for (final run in runs) {
      final json = _object(run);
      if (json?['id'] != runId) continue;
      final segments = json?['trackSegments'];
      return segments is List && segments.isNotEmpty;
    }
  }
  return false;
}

/// The run ids of [document], in its order.
List<String> dayDocumentRunIds(Map<String, Object?> document) => [
  if (_object(document['event'])?['runs'] case final List<Object?> runs)
    for (final run in runs)
      if (_object(run)?['id'] case final String id) id,
];

/// The recordings that [document], saved at [path], names and that exist:
/// every telemetry source of every run, as each resolves from [path].
Set<String> dayRecordingPaths(Map<String, Object?> document, String path) {
  final found = <String>{};
  if (_object(document['event'])?['runs'] case final List<Object?> runs) {
    for (final run in runs) {
      final sources = _object(_object(run)?['sources'])?['telemetry'];
      if (sources is! List) continue;
      for (final source in sources) {
        final reference = _object(_object(source)?['reference']);
        if (reference == null) continue;
        final file = fet.SourceReference.fromJson(reference).resolve(path);
        if (file.isNotEmpty) found.add(file);
      }
    }
  }
  return found;
}

/// What deleting a day's files did.
final class DayFilesDeleted {
  const DayFilesDeleted({required this.recordings, required this.recordingsKept});

  /// Recordings deleted: copies the app made, used by no other day.
  final int recordings;

  /// Recordings the app made copies of that another day still uses.
  final int recordingsKept;
}

String _canonical(String path) {
  final absolute = p.normalize(p.absolute(path));
  try {
    if (FileSystemEntity.typeSync(absolute) != FileSystemEntityType.notFound) {
      return p.normalize(Directory(absolute).resolveSymbolicLinksSync());
    }
  } on FileSystemException {
    // The path as spelled.
  }
  return absolute;
}

/// The extensions of recordings the app copies ([deleteDayFiles] deletes
/// nothing else).
const _recordingExtensions = {'.vbo', '.rcz'};

/// Deletes the day saved at [dayPath] and the recordings it names that live
/// in one of [ownedFolders] (folders holding only copies the app made: the
/// profile's copied recordings, files shared to the app) and that none of
/// the days at [otherDayPaths] names. Only a `.vbo` or `.rcz` file is ever
/// deleted that way: a recording anywhere else, or anything else the
/// document names, is left alone. When one of the other days cannot be
/// read, no recording is deleted, as it may use them. An emptied folder a
/// recording was the only file of is removed too, unless it is one of
/// [ownedFolders]. A day whose own document cannot be read is deleted
/// without its recordings.
DayFilesDeleted deleteDayFiles({
  required String dayPath,
  required Iterable<String> otherDayPaths,
  required Iterable<String> ownedFolders,
}) {
  Set<String>? recordingsOf(String path) {
    if (!File(path).existsSync()) return const {};
    try {
      return dayRecordingPaths(readDayDocument(path), path);
    } on Object {
      return null;
    }
  }

  final recordings = recordingsOf(dayPath) ?? const <String>{};
  final roots = [for (final folder in ownedFolders) _canonical(folder)];
  bool owned(String file) => roots.any((root) => p.isWithin(root, file));
  final candidates = {
    for (final file in recordings)
      if (_recordingExtensions.contains(p.extension(file).toLowerCase()) && owned(_canonical(file)))
        _canonical(file),
  };
  final used = <String>{};
  var unreadable = false;
  if (candidates.isNotEmpty) {
    final self = _canonical(dayPath);
    for (final other in {for (final path in otherDayPaths) _canonical(path)}) {
      if (p.equals(other, self)) continue;
      final files = recordingsOf(other);
      if (files == null) {
        unreadable = true;
        break;
      }
      for (final file in files) {
        used.add(_canonical(file));
      }
    }
  }
  if (File(dayPath).existsSync()) File(dayPath).deleteSync();
  var deleted = 0;
  var kept = 0;
  for (final file in candidates) {
    if (unreadable || used.contains(file)) {
      ++kept;
      continue;
    }
    try {
      File(file).deleteSync();
      ++deleted;
    } on FileSystemException {
      continue;
    }
    final folder = Directory(p.dirname(file));
    try {
      if (!roots.any((root) => p.equals(root, folder.path)) &&
          owned(folder.path) &&
          folder.listSync().isEmpty) {
        folder.deleteSync();
      }
    } on FileSystemException {
      // Left in place.
    }
  }
  return DayFilesDeleted(recordings: deleted, recordingsKept: kept);
}
