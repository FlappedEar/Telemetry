// Finding a day's moved or renamed recordings in a folder (FET-40), by the
// identity the document stores, as FlappedEar Overlays relinks a recording:
// the content SHA-256 and the telemetry-v1 fingerprint, never the file name
// alone (VBOOverlay docs/project-format.md "Opening and relinking",
// docs/event-project-format.md; AppController::relinkVbo).
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;

import '../intake/recording_source.dart';
import '../operation.dart';
import 'day_document.dart';

/// What [findMovedRecordings] found in a folder.
final class RecordingSearch {
  const RecordingSearch({this.found = const {}, this.different = const {}});

  /// The file to open for each missing run, by run id: a file with the
  /// recording's content, or for a recording the document has no identity
  /// for, a file of the same name. [openDay] verifies each again.
  final Map<String, String> found;

  /// Files named like a missing recording that are another recording, by
  /// run id. They are not used.
  final Map<String, String> different;
}

/// Looks under [folder] (and its subfolders, at most [maximumFiles] files
/// looked at, links not followed) for the [missing] recordings of a day.
///
/// A recording whose document stores its content SHA-256 is found by that
/// alone, whatever the file is called now; one with only a fingerprint by its
/// size and sampled SHA-256 (the parsed part of the fingerprint is checked
/// when the day opens). Only a recording the document has no identity for is
/// found by its file name, as Overlays accepts any compatible file for it.
/// Only VBO and RCZ files of the right size are read.
RecordingSearch findMovedRecordings(
  String folder,
  List<MissingRecording> missing, {
  int maximumFiles = 20000,
  CancellationCheck? cancelled,
}) {
  final files = <File>[];
  try {
    for (final entity in Directory(folder).listSync(recursive: true, followLinks: false)) {
      if (files.length >= maximumFiles) break;
      if (entity is File && supportsRecordingPath(entity.path)) files.add(entity);
    }
  } on FileSystemException {
    // A folder that cannot be listed further: use what was found.
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  final found = <String, String>{};
  final different = <String, String>{};
  final digests = <String, String>{};
  final sampled = <String, String>{};
  int? sizeOf(File file) {
    try {
      return file.lengthSync();
    } on FileSystemException {
      return null;
    }
  }

  String digestOf(File file, int size) => digests.putIfAbsent(file.path, () {
    try {
      return contentSha256(file.path, size, cancelled: cancelled);
    } on RecordingSourceError {
      return '';
    } on ResourceLimitError {
      return '';
    }
  });

  for (final recording in missing) {
    throwIfCancelled(cancelled);
    final name = p.basename(recording.path.replaceAll(r'\', '/')).toLowerCase();
    final fingerprint = recording.fingerprint;
    final expectedSize = fingerprint['size'];
    final expectedSampled = fingerprint['sampledSha256'];
    final identified = recording.contentSha256.isNotEmpty || fingerprint.isNotEmpty;
    bool matches(File file) {
      final size = sizeOf(file);
      if (size == null || size <= 0) return false;
      if (expectedSize is int && size != expectedSize) return false;
      if (recording.contentSha256.isNotEmpty) {
        return digestOf(file, size) == recording.contentSha256;
      }
      if (expectedSampled is String) {
        return sampled.putIfAbsent(file.path, () => fet.sampledSha256(file.path)) ==
            expectedSampled;
      }
      return expectedSize is int;
    }

    String? match;
    String? sameName;
    // A file of the same name first, so a copy that was only moved is
    // preferred to an identical one elsewhere.
    for (final file in [
      ...files.where((file) => p.basename(file.path).toLowerCase() == name),
      ...files.where((file) => p.basename(file.path).toLowerCase() != name),
    ]) {
      throwIfCancelled(cancelled);
      final named = p.basename(file.path).toLowerCase() == name;
      if (!identified) {
        if (named) match = file.path;
        if (named) break;
        continue;
      }
      if (matches(file)) {
        match = file.path;
        break;
      }
      if (named) sameName ??= file.path;
    }
    if (match != null) {
      found[recording.runId] = match;
    } else if (sameName != null) {
      different[recording.runId] = sameName;
    }
  }
  return RecordingSearch(found: found, different: different);
}
