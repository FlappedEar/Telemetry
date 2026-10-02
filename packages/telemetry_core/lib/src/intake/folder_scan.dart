// Port of VBOOverlay native/src/telemetry/TelemetryFolderScan.{h,cpp}
// (KAN-87, KAN-88, KAN-173): the recordings a folder, or a mix of dropped or
// shared items, holds (FET-15).
import 'dart:io';

import 'package:path/path.dart' as p;

import '../operation.dart';
import 'recording_source.dart';

/// Bounds for choosing a folder of recordings. Callers may lower, never
/// raise, them.
final class TelemetryFolderScanLimits {
  const TelemetryFolderScanLimits({
    this.maximumDepth = 8,
    this.maximumEntries = 20000,
    this.maximumFiles = 64,
  });

  /// Subfolder levels below the chosen folder.
  final int maximumDepth;

  /// Files and folders inspected.
  final int maximumEntries;

  /// The batch import limit.
  final int maximumFiles;

  static const ceiling = TelemetryFolderScanLimits();

  TelemetryFolderScanLimits _clamped() => TelemetryFolderScanLimits(
    maximumDepth: maximumDepth.clamp(0, ceiling.maximumDepth),
    maximumEntries: maximumEntries.clamp(1, ceiling.maximumEntries),
    maximumFiles: maximumFiles.clamp(1, ceiling.maximumFiles),
  );
}

/// The recordings found, for the ordinary import review.
final class TelemetryFolderScan {
  const TelemetryFolderScan({
    this.files = const [],
    this.notes = const [],
    this.error = '',
    this.cancelled = false,
  });

  const TelemetryFolderScan.cancelledScan() : this(cancelled: true);

  /// `.vbo` and `.rcz` files as absolute paths. Empty when [error] is set or
  /// the scan was cancelled.
  final List<String> files;

  /// What was skipped and why, for the user.
  final List<String> notes;

  /// Empty unless the scan failed.
  final String error;

  final bool cancelled;
}

// KAN-173: a leading dot is hidden on Unix only. The macOS AppleDouble
// sidecars ("._name.vbo") that SD cards and exFAT drives carry would otherwise
// be imported on Windows, so dot entries are skipped on every platform.
bool _isDotEntry(String name) => name.startsWith('.');
bool _isAppleDoubleSidecar(String name) => name.startsWith('._');

String _absolute(String path) => p.normalize(p.absolute(path));

String? _canonical(String path) {
  try {
    return p.normalize(Directory(path).resolveSymbolicLinksSync());
  } on FileSystemException {
    return null;
  }
}

/// Scans [folder] for VBO and RCZ recordings (extension ignoring case).
///
/// Subfolders are included only when asked. Symbolic links, to files or
/// folders, are never followed and are reported. Dot entries are skipped. A
/// folder is visited once by its canonical path, so no link or mount can
/// cause a cycle. More recordings than `maximumFiles` is an error, never a
/// silent truncation. Cooperatively cancellable.
///
/// Entries are listed in code-unit order of their names; the result is
/// sorted by path.
TelemetryFolderScan scanTelemetryFolder(
  String folder, {
  required bool includeSubfolders,
  CancellationCheck? cancelled,
  TelemetryFolderScanLimits limits = const TelemetryFolderScanLimits(),
}) {
  limits = limits._clamped();
  if (folder.isEmpty || !FileSystemEntity.isDirectorySync(folder)) {
    return const TelemetryFolderScan(error: 'The folder does not exist or is not a folder.');
  }
  if (FileSystemEntity.isLinkSync(folder)) {
    return const TelemetryFolderScan(error: 'Choose the folder itself, not a link to it.');
  }
  final files = <String>[];
  final visited = <String>{};
  final pending = <(String, int)>[(_absolute(folder), 0)];
  var inspected = 0, links = 0, others = 0, tooDeep = 0;
  var entryLimit = false;
  try {
    while (pending.isNotEmpty && !entryLimit) {
      throwIfCancelled(cancelled);
      final (path, depth) = pending.removeAt(0);
      final canonical = _canonical(path);
      if (canonical == null || !visited.add(canonical)) continue;
      final List<FileSystemEntity> entries;
      try {
        entries = Directory(path).listSync(followLinks: false);
      } on FileSystemException {
        continue; // unreadable folder: nothing listed, as QDir does
      }
      entries.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (_isDotEntry(name)) continue;
        throwIfCancelled(cancelled);
        if (++inspected > limits.maximumEntries) {
          entryLimit = true;
          break;
        }
        if (entry is Link) {
          ++links;
          continue;
        }
        final absolutePath = p.join(path, name);
        if (entry is Directory) {
          if (!includeSubfolders) continue;
          if (depth + 1 > limits.maximumDepth) {
            ++tooDeep;
            continue;
          }
          pending.add((absolutePath, depth + 1));
          continue;
        }
        if (entry is File && supportsRecordingPath(name)) {
          files.add(absolutePath);
        } else {
          ++others;
        }
      }
    }
  } on OperationCancelled {
    return const TelemetryFolderScan.cancelledScan();
  }
  files.sort();
  if (files.length > limits.maximumFiles) {
    return TelemetryFolderScan(
      error:
          'The folder holds ${files.length} recordings; import at most '
          '${limits.maximumFiles} at a time. Choose a smaller folder.',
    );
  }
  final notes = <String>[
    if (entryLimit)
      'Stopped after ${limits.maximumEntries} files and folders; recordings beyond that were not scanned.',
    if (tooDeep > 0)
      '$tooDeep folder(s) deeper than ${limits.maximumDepth} levels were not scanned.',
    if (links > 0) '$links link(s) were not followed.',
    if (others > 0) '$others other file(s) were ignored; only VBO and RCZ recordings are imported.',
  ];
  return TelemetryFolderScan(
    files: files,
    notes: notes,
    error: files.isEmpty
        ? 'No VBO or RCZ recordings were found${includeSubfolders ? '' : ' (subfolders were not included)'}.'
        : '',
  );
}

/// What was dropped, chosen or shared (any mix of recordings, other files and
/// folders) as one list of recordings for the ordinary review.
///
/// Folders are scanned as by [scanTelemetryFolder]. A file that is not a VBO
/// or RCZ recording, is missing, is a macOS metadata sidecar or is a link is
/// reported and skipped. A recording reached twice (same canonical path)
/// counts once. A folder with nothing to import is reported and skipped when
/// there are other sources, and is the error when it is the only one. More
/// recordings than `maximumFiles` in total is an error.
TelemetryFolderScan scanTelemetrySources(
  List<String> paths, {
  required bool includeSubfolders,
  CancellationCheck? cancelled,
  TelemetryFolderScanLimits limits = const TelemetryFolderScanLimits(),
}) {
  limits = TelemetryFolderScanLimits(
    maximumDepth: limits.maximumDepth,
    maximumEntries: limits.maximumEntries,
    maximumFiles: limits.maximumFiles.clamp(1, TelemetryFolderScanLimits.ceiling.maximumFiles),
  );
  final files = <String>[];
  final notes = <String>[];
  final seen = <String>{};
  void add(String path) {
    final canonical = _canonical(path) ?? path;
    if (seen.add(canonical)) files.add(path);
  }

  for (final path in paths) {
    if (cancelled != null && cancelled()) {
      return const TelemetryFolderScan.cancelledScan();
    }
    final name = fileName(path).isEmpty ? path : fileName(path);
    final isLink = FileSystemEntity.isLinkSync(path);
    if (!isLink && FileSystemEntity.isDirectorySync(path)) {
      final scan = scanTelemetryFolder(
        path,
        includeSubfolders: includeSubfolders,
        cancelled: cancelled,
        limits: limits,
      );
      if (scan.cancelled) return const TelemetryFolderScan.cancelledScan();
      if (scan.error.isNotEmpty && paths.length == 1) return scan;
      notes.addAll(scan.notes.map((note) => '$name: $note'));
      if (scan.error.isNotEmpty) {
        notes.add('$name: ${scan.error}');
        continue;
      }
      scan.files.forEach(add);
      continue;
    }
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      notes.add('$name: not found; not imported.');
    } else if (_isAppleDoubleSidecar(name)) {
      notes.add('$name: a macOS metadata file, not a recording; not imported.');
    } else if (isLink) {
      notes.add('$name: a link; not followed.');
    } else if (type == FileSystemEntityType.file && supportsRecordingPath(path)) {
      add(_absolute(path));
    } else {
      notes.add('$name: not a VBO or RCZ recording; not imported.');
    }
  }
  if (files.length > limits.maximumFiles) {
    return TelemetryFolderScan(
      notes: notes,
      error: 'That is ${files.length} recordings; import at most ${limits.maximumFiles} at a time.',
    );
  }
  return TelemetryFolderScan(
    files: files,
    notes: notes,
    error: files.isEmpty ? 'No VBO or RCZ recordings to import.' : '',
  );
}
