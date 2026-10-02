// Where a document's recordings live, following FlappedEar Overlays'
// ProjectSourceReferenceCodec (VBOOverlay ca2bde5) (FET-25).
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Whether [path] is absolute as Qt's `QDir::isAbsolutePath` sees it on this
/// platform: a leading slash or a `:` resource path, and on Windows a drive
/// or UNC path.
bool qtIsAbsolutePath(String path, {bool? windows}) {
  if (path.isEmpty) return false;
  if (path.startsWith('/') || path.startsWith(':')) return true;
  if (!(windows ?? Platform.isWindows)) return false;
  return path.startsWith(r'\') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);
}

/// One recording's location: a path relative to the document, an absolute
/// path and the recording's fingerprint. Either path may be empty.
final class SourceReference {
  const SourceReference({
    this.relativePath = '',
    this.absolutePath = '',
    this.fingerprint = const {},
  });

  /// The reference stored in [json]; missing keys read as empty.
  factory SourceReference.fromJson(Map<String, Object?> json) {
    final fingerprint = json['fingerprint'];
    return SourceReference(
      relativePath: (json['relativePath'] as String? ?? '').replaceAll(
        r'\',
        '/',
      ),
      absolutePath: json['absolutePath'] as String? ?? '',
      fingerprint: fingerprint is Map<String, Object?> ? fingerprint : const {},
    );
  }

  final String relativePath;
  final String absolutePath;
  final Map<String, Object?> fingerprint;

  bool get isEmpty => relativePath.isEmpty && absolutePath.isEmpty;

  String get displayPath => relativePath.isEmpty ? absolutePath : relativePath;

  /// The reference as saved in the document at [projectPath]: the cleaned
  /// absolute path, and a relative path when the recording is at most two
  /// folders above the document. An empty [projectPath] keeps the stored
  /// relative path.
  Map<String, Object?> toJson(String projectPath) {
    if (isEmpty) return {};
    final result = <String, Object?>{};
    final absolute = _cleanAbsolutePath(absolutePath);
    if (absolute.isNotEmpty) {
      result['absolutePath'] = absolute;
      if (projectPath.isNotEmpty) {
        final relative = _boundedRelative(
          absolute,
          _projectDirectory(projectPath),
        );
        if (relative != null) {
          result['relativePath'] = relative;
        } else if (relativePath.isNotEmpty) {
          result['relativePath'] = relativePath.replaceAll(r'\', '/');
        }
      } else if (relativePath.isNotEmpty) {
        result['relativePath'] = relativePath.replaceAll(r'\', '/');
      }
    } else if (relativePath.isNotEmpty) {
      result['relativePath'] = relativePath.replaceAll(r'\', '/');
    }
    if (fingerprint.isNotEmpty) result['fingerprint'] = fingerprint;
    return result;
  }

  /// The reference to save in the document moving from
  /// [previousProjectPath] to [targetProjectPath]: located through the
  /// previous document, a missing file kept at its old place rather than
  /// reinterpreted against the new folder.
  Map<String, Object?> forSave(
    String previousProjectPath,
    String targetProjectPath,
  ) {
    if (isEmpty) return {};
    var absolute = resolve(previousProjectPath);
    if (absolute.isEmpty &&
        relativePath.isNotEmpty &&
        previousProjectPath.isNotEmpty) {
      absolute = p.join(_projectDirectory(previousProjectPath), relativePath);
    }
    if (absolute.isEmpty) absolute = absolutePath;
    if (absolute.isEmpty) return toJson(targetProjectPath);
    return SourceReference(
      absolutePath: absolute,
      fingerprint: fingerprint,
    ).toJson(targetProjectPath);
  }

  /// The recording's file for the document at [projectPath], or an empty
  /// string when neither path names an existing file. The relative path wins
  /// and may climb at most two folders above the document, so a shared
  /// document cannot point anywhere on the disk with `../`.
  String resolve(String projectPath) {
    if (relativePath.isNotEmpty &&
        projectPath.isNotEmpty &&
        !qtIsAbsolutePath(relativePath)) {
      final directory = _projectDirectory(projectPath);
      final candidate = p.normalize(p.join(directory, relativePath));
      if (_boundedRelative(candidate, directory) != null &&
          FileSystemEntity.isFileSync(candidate)) {
        return _cleanAbsolutePath(candidate);
      }
    }
    if (absolutePath.isNotEmpty && FileSystemEntity.isFileSync(absolutePath)) {
      return _cleanAbsolutePath(absolutePath);
    }
    return '';
  }
}

/// [reference] (a JSON object with paths, a fingerprint and possibly keys
/// this version does not know) moved from [previousProjectPath] to
/// [targetProjectPath]. Unknown keys are kept.
Map<String, Object?> rebaseReference(
  Map<String, Object?> reference,
  String previousProjectPath,
  String targetProjectPath,
) {
  final known = SourceReference.fromJson(reference)
      .forSave(previousProjectPath, targetProjectPath);
  return {
    for (final entry in reference.entries)
      if (!const {
        'relativePath',
        'absolutePath',
        'fingerprint',
      }.contains(entry.key))
        entry.key: entry.value,
    ...known,
  };
}

/// [path] relative to [directory] with forward slashes, or null when it is
/// on another drive or more than two folders above [directory].
String? _boundedRelative(String path, String directory) {
  final String relative;
  try {
    relative = p.relative(path, from: directory).replaceAll(r'\', '/');
  } on p.PathException {
    return null;
  }
  var remaining = relative;
  var parents = 0;
  while (remaining.startsWith('../')) {
    parents++;
    remaining = remaining.substring(3);
  }
  if (qtIsAbsolutePath(relative) || relative == '..' || parents > 2) {
    return null;
  }
  return relative;
}

/// The absolute, cleaned and, when it exists, symlink-free form of [path].
String _cleanAbsolutePath(String path) {
  if (path.isEmpty) return '';
  final absolute = p.normalize(p.absolute(path));
  try {
    if (FileSystemEntity.typeSync(absolute) != FileSystemEntityType.notFound) {
      return p.normalize(File(absolute).resolveSymbolicLinksSync());
    }
  } on FileSystemException {
    // Fall back to the spelled path, as Qt does without a canonical path.
  }
  return absolute;
}

String _projectDirectory(String projectPath) =>
    _cleanAbsolutePath(p.dirname(p.absolute(projectPath)));

/// SHA-256 over the first, middle and last 64 KiB of the file at [path], as
/// Overlays' `sampledDigest` reads them (a small file is read three times),
/// or an empty string when it cannot be read.
String sampledSha256(String path) {
  const block = 64 * 1024;
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final size = file.lengthSync();
    final bytes = <int>[];
    for (final offset in [
      0,
      size ~/ 2 - block ~/ 2 < 0 ? 0 : size ~/ 2 - block ~/ 2,
      size - block < 0 ? 0 : size - block,
    ]) {
      file.setPositionSync(offset);
      bytes.addAll(file.readSync(block));
    }
    return sha256.convert(bytes).toString();
  } on FileSystemException {
    return '';
  } finally {
    file?.closeSync();
  }
}

/// [seconds] in whole microseconds, rounded half away from zero; 0 when not
/// finite.
int roundedMicroseconds(double seconds) =>
    seconds.isFinite ? (seconds * 1000000.0).round() : 0;
