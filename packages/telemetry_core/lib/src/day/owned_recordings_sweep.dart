// Reclaiming recording copies the app made and no day keeps (audit F11).
//
// On Android every file picked in the app or shared to it is copied into
// its own folder under `incoming` or `picked` before the app knows whether
// the recording will be used. A duplicate, a rejected file or a cancelled
// import leaves a copy no day names. This deletes those copies, and only
// those: a copy is kept when any saved day, or the recovery snapshot,
// names it, when it is younger than the grace period (an import may still
// be on its way to a day), or when anything about it cannot be checked.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'day_document.dart';
import 'day_removal.dart';

/// How long a copy is left alone after it was made or last changed.
const ownedRecordingsGrace = Duration(days: 1);

const _recordingExtensions = {'.vbo', '.rcz'};

String _canonical(String path) {
  final absolute = p.normalize(p.absolute(path));
  try {
    if (FileSystemEntity.typeSync(absolute) != FileSystemEntityType.notFound) {
      return p.normalize(File(absolute).resolveSymbolicLinksSync());
    }
  } on FileSystemException {
    // The path as spelled.
  }
  return absolute;
}

// MainActivity names a batch folder `<milliseconds since 1970>-<uuid>`.
bool _madeBefore(String folder, DateTime cutoff) {
  final stamp = int.tryParse(p.basename(folder).split('-').first);
  return stamp != null && DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true).isBefore(cutoff);
}

/// Deletes the recording copies in the batch folders of [folders] (each
/// copy lives in its own folder, `<folder>/<batch>/<name>`) that none of the
/// days at [dayPaths] names, that are not one of [keep] (the recordings of
/// the recovery snapshot, or an import still running), and that were last
/// changed more than [grace] before [now]. Only a `.vbo` or `.rcz` file, or
/// an empty file (what the app makes of a file that is not a recording), is
/// deleted; a batch folder left empty goes too. A day that cannot be read
/// stops the sweep before anything is deleted: it may use any copy. Files
/// directly in [folders], links and anything else are left alone.
///
/// Returns how many files were deleted.
int sweepOwnedRecordingFolders({
  required Iterable<String> folders,
  required Iterable<String> dayPaths,
  Iterable<String> keep = const [],
  required DateTime now,
  Duration grace = ownedRecordingsGrace,
}) {
  final used = <String>{for (final path in keep) _canonical(path)};
  for (final dayPath in dayPaths) {
    try {
      used.addAll(dayRecordingPaths(readDayDocument(dayPath), dayPath).map(_canonical));
    } on Object {
      return 0;
    }
  }
  final cutoff = now.subtract(grace);
  var deleted = 0;
  for (final folder in folders) {
    final List<FileSystemEntity> batches;
    try {
      final root = Directory(folder);
      if (!root.existsSync()) continue;
      batches = root.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final batch in batches) {
      if (batch is! Directory) continue;
      try {
        final entries = batch.listSync(followLinks: false);
        var left = 0, removed = 0;
        for (final entry in entries) {
          if (entry is! File) {
            ++left;
            continue;
          }
          final stat = entry.statSync();
          final candidate =
              _recordingExtensions.contains(p.extension(entry.path).toLowerCase()) ||
              stat.size == 0;
          if (!candidate ||
              !stat.modified.isBefore(cutoff) ||
              used.contains(_canonical(entry.path))) {
            ++left;
            continue;
          }
          try {
            entry.deleteSync();
            ++deleted;
            ++removed;
          } on FileSystemException {
            ++left;
          }
        }
        // Not a folder an import is still filling: one emptied here, or
        // made (its name starts with the time) before the grace period.
        if (left == 0 && (removed > 0 || _madeBefore(batch.path, cutoff))) {
          batch.deleteSync();
        }
      } on FileSystemException {
        continue;
      }
    }
  }
  return deleted;
}
