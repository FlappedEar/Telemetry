// Finding a day's moved or renamed recordings in a folder (FET-40), by the
// identity the document stores, as FlappedEar Overlays relinks a recording:
// the content SHA-256 and the telemetry-v1 fingerprint, never the file name
// alone (VBOOverlay docs/project-format.md "Opening and relinking",
// docs/event-project-format.md; AppController::relinkVbo).
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;

import '../intake/import_plan.dart';
import '../intake/recording_source.dart';
import '../operation.dart';
import 'day_document.dart';

/// What [findMovedRecordings] found in a folder.
final class RecordingSearch {
  const RecordingSearch({
    this.found = const {},
    this.different = const {},
    this.alternatives = const {},
    this.alternativesByName = const {},
  });

  /// The file to open for each missing run, by run id: a file with the
  /// recording's content, or for a recording the document has no identity
  /// for, a file of the same name. [openDay] verifies each again.
  final Map<String, String> found;

  /// Files named like a missing recording that are another recording, by
  /// run id. They are not used.
  final Map<String, String> different;

  /// The file to open for each missing alternative recording, by run id: a
  /// file with its content, else one of the same name, which is used only
  /// when it is the same drive as the run's recording
  /// ([resolveDocumentAlternative] checks).
  final Map<String, String> alternatives;

  /// The runs of [alternatives] whose file was found by its name only, not
  /// by the content the document asserts.
  final Set<String> alternativesByName;
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
///
/// [missingAlternatives] are runs' alternative recordings (the RCZ of a
/// VBO) that could not be used, found the same way, except that a file of
/// the same name with other content is offered too: an RCZ written again
/// is still the same drive.
RecordingSearch findMovedRecordings(
  String folder,
  List<MissingRecording> missing, {
  List<MissingRecording> missingAlternatives = const [],
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

  final alternatives = <String, String>{};
  final alternativesByName = <String>{};
  for (final (index, recording) in [...missing, ...missingAlternatives].indexed) {
    final alternative = index >= missing.length;
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
    if (alternative) {
      if ((match ?? sameName) case final file?) alternatives[recording.runId] = file;
      if (match == null && sameName != null) alternativesByName.add(recording.runId);
    } else if (match != null) {
      found[recording.runId] = match;
    } else if (sameName != null) {
      different[recording.runId] = sameName;
    }
  }
  return RecordingSearch(
    found: found,
    different: different,
    alternatives: alternatives,
    alternativesByName: alternativesByName,
  );
}

/// A day opened again after looking in [folder] for its [missing]
/// recordings and its [missingAlternatives] ([findMovedRecordings]).
typedef RelinkedDay = ({
  OpenedDay day,
  RecordingSearch search,

  /// Alternatives found by name only that are not the same drive as their
  /// run's recording ([sameDriveInOtherFormat]): not used, by run id with
  /// the file found.
  Map<String, String> differentAlternatives,
});

/// Looks in [folder] for the [missing] recordings and [missingAlternatives]
/// of the day saved at [path] and opens it again with those found. An
/// alternative found only by its name is used only when it is the same
/// drive as its run's recording; otherwise it is reported in
/// [RelinkedDay.differentAlternatives], never accepted for its name.
RelinkedDay relinkDay(
  String path,
  String folder,
  List<MissingRecording> missing, {
  List<MissingRecording> missingAlternatives = const [],
  CancellationCheck? cancelled,
}) {
  final search = findMovedRecordings(
    folder,
    missing,
    missingAlternatives: missingAlternatives,
    cancelled: cancelled,
  );
  var day = openDay(
    path,
    relinked: search.found,
    relinkedAlternatives: search.alternatives,
    cancelled: cancelled,
  );
  final different = <String, String>{};
  final byName = [
    for (final named in day.runs)
      if (search.alternativesByName.contains(named.run.id)) named,
  ];
  if (byName.isNotEmpty) {
    final plan = prepareTelemetryImport([
      for (final named in byName) search.alternatives[named.run.id]!,
    ], cancelled: cancelled);
    for (final (index, named) in byName.indexed) {
      final status = plan.files[index];
      TelemetryRunProposal? loaded;
      for (final proposal in plan.runs) {
        if (proposal.id == status.runId) loaded = proposal;
      }
      if (loaded == null || !sameDriveInOtherFormat(named.run, loaded, cancelled: cancelled)) {
        different[named.run.id] = search.alternatives[named.run.id]!;
      }
    }
  }
  if (different.isNotEmpty) {
    day = openDay(
      path,
      relinked: search.found,
      relinkedAlternatives: {
        for (final MapEntry(:key, :value) in search.alternatives.entries)
          if (!different.containsKey(key)) key: value,
      },
      cancelled: cancelled,
    );
  }
  return (day: day, search: search, differentAlternatives: different);
}
