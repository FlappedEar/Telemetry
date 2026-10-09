// The copies of reference recordings in the profile's `Recordings` folder
// (FET-276): made once per content, named by its SHA-256 as a bundle names
// the recordings of its days, and found again from the profile by that
// name alone, never by a path the profile holds.
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../day/day_document.dart';
import '../day/day_removal.dart';
import 'driver_profile.dart';
import 'profile_bundle.dart';

/// A copy [keepReferenceFile] made or found.
final class ReferenceFileCopy {
  const ReferenceFileCopy({required this.sha256, required this.extension, required this.bytes});

  final String sha256;

  /// `.vbo` or `.rcz`, lower case.
  final String extension;
  final int bytes;

  /// The copy as a reference to lap [lapNumber] of [recordingId] (the
  /// file's name), for [setProfileDayReference].
  ProfileReferenceFile reference(String name, String recordingId, int lapNumber) =>
      ProfileReferenceFile(
        recordingId: recordingId,
        lapNumber: lapNumber,
        sha256: sha256,
        extension: extension,
        bytes: bytes,
        name: name,
      );
}

/// Where [reference]'s copy is in the profile kept in [folder]; null when
/// its hash or extension is not one a copy can have. The name is built
/// only from a checked hash and one of [referenceFileExtensions], so no
/// profile or bundle can point it outside `Recordings`.
String? profileReferenceFilePath(String folder, ProfileReferenceFile reference) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(reference.sha256) ||
      !referenceFileExtensions.contains(reference.extension)) {
    return null;
  }
  return p.join(folder, profileRecordingsFolderName, reference.fileName);
}

/// Copies the recording [source] into `Recordings` of the profile kept in
/// [folder], as `<SHA-256><extension>`, unless that copy is already there
/// (the same content is one file however many days use it). The copy is
/// written beside and moved into place, hashed as it is read, and never
/// past [maximumReferenceFileBytes]. Only a `.vbo` or `.rcz` file is copied.
/// Throws [ProfileReferenceError].
ReferenceFileCopy keepReferenceFile(String folder, String source) {
  final extension = p.extension(source).toLowerCase();
  if (!referenceFileExtensions.contains(extension)) {
    throw const ProfileReferenceError(
      ProfileReferenceProblem.fileType,
      'A reference recording is a VBO or RCZ file.',
    );
  }
  final recordings = Directory(p.join(folder, profileRecordingsFolderName));
  final partial = File(
    p.join(
      recordings.path,
      '.reference-${List.generate(8, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}.partial',
    ),
  );
  RandomAccessFile? input;
  RandomAccessFile? output;
  try {
    if (FileSystemEntity.typeSync(source) != FileSystemEntityType.file) {
      throw const ProfileReferenceError(
        ProfileReferenceProblem.fileUnreadable,
        'The reference recording is not a file.',
      );
    }
    final declared = File(source).lengthSync();
    if (declared == 0) {
      throw const ProfileReferenceError(
        ProfileReferenceProblem.fileEmpty,
        'The reference recording is empty.',
      );
    }
    if (declared > maximumReferenceFileBytes) {
      throw const ProfileReferenceError(
        ProfileReferenceProblem.fileTooLarge,
        'The reference recording is too large to keep.',
      );
    }
    recordings.createSync(recursive: true);
    input = File(source).openSync();
    output = partial.openSync(mode: FileMode.writeOnly);
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    var length = 0;
    while (true) {
      final chunk = input.readSync(64 * 1024);
      if (chunk.isEmpty) break;
      length += chunk.length;
      // A file that grew while it was copied.
      if (length > maximumReferenceFileBytes) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.fileTooLarge,
          'The reference recording is too large to keep.',
        );
      }
      hash.add(chunk);
      output.writeFromSync(chunk);
    }
    hash.close();
    output.closeSync();
    output = null;
    final sha = digest.value.toString();
    final target = File(p.join(recordings.path, '$sha$extension'));
    if (target.existsSync()) {
      // The copy is there when it is the content its name says; a damaged
      // one is replaced by the file just read.
      if (target.lengthSync() == length && _hashOf(target.path) == sha) {
        partial.deleteSync();
        return ReferenceFileCopy(sha256: sha, extension: extension, bytes: length);
      }
      target.deleteSync();
    }
    partial.renameSync(target.path);
    return ReferenceFileCopy(sha256: sha, extension: extension, bytes: length);
  } on FileSystemException catch (error) {
    throw ProfileReferenceError(
      ProfileReferenceProblem.fileUnreadable,
      'The reference recording could not be copied: ${error.message}',
    );
  } finally {
    input?.closeSync();
    try {
      output?.closeSync();
    } on Object {
      // Already closed.
    }
    try {
      if (partial.existsSync()) partial.deleteSync();
    } on Object {
      // Left beside; harmless.
    }
  }
}

String _hashOf(String path) {
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  final input = File(path).openSync();
  try {
    while (true) {
      final chunk = input.readSync(64 * 1024);
      if (chunk.isEmpty) break;
      hash.add(chunk);
    }
  } finally {
    input.closeSync();
  }
  hash.close();
  return digest.value.toString();
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Deletes the copy of [reference] in the profile kept in [folder] when
/// nothing uses it any more: no name in [stillReferenced] (the copies the
/// profile's days keep, by file name) and no recording of the days at
/// [dayPaths] (every day in the days folder, listed in the profile or not)
/// is that file. Unreadable days count as using it. Only a file inside
/// `Recordings` is ever deleted. Whether it was deleted.
bool deleteUnusedReferenceFile({
  required String folder,
  required ProfileReferenceFile reference,
  required Set<String> stillReferenced,
  required Iterable<String> dayPaths,
}) {
  final path = profileReferenceFilePath(folder, reference);
  if (path == null || stillReferenced.contains(reference.fileName)) return false;
  final file = File(path);
  if (!file.existsSync()) return false;
  final canonical = _canonical(path);
  for (final dayPath in dayPaths) {
    try {
      if (dayRecordingPaths(
        readDayDocument(dayPath),
        dayPath,
      ).any((used) => p.equals(_canonical(used), canonical))) {
        return false;
      }
    } on Object {
      return false;
    }
  }
  try {
    file.deleteSync();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Deletes the reference recording copies in [folder]'s `Recordings` that
/// nothing uses: a file named like a copy (a SHA-256 and `.vbo` or `.rcz`)
/// that is not in [stillReferenced] (the file names the profile's days and
/// pending references keep) and is no recording of the days at [dayPaths]
/// (every day in the days folder, listed in the profile or not), and the
/// half-written `.reference-*.partial` files. Anything else in the folder is
/// left alone, and a day that cannot be read stops the sweep: it may use
/// any of them. The caller makes sure no copy is being made or placed.
/// How many files were deleted.
int sweepReferenceFiles({
  required String folder,
  required Set<String> stillReferenced,
  required Iterable<String> dayPaths,
}) {
  final recordings = Directory(p.join(folder, 'Recordings'));
  final List<FileSystemEntity> entries;
  try {
    if (!recordings.existsSync()) return 0;
    entries = recordings.listSync(followLinks: false);
  } on FileSystemException {
    return 0;
  }
  final used = <String>{};
  var daysRead = false;
  var deleted = 0;
  for (final entry in entries) {
    if (entry is! File) continue;
    final name = p.basename(entry.path);
    final partial = name.startsWith('.reference-') && name.endsWith('.partial');
    if (!partial) {
      if (!_copyName.hasMatch(name) || stillReferenced.contains(name)) continue;
      if (!daysRead) {
        for (final dayPath in dayPaths) {
          try {
            used.addAll(dayRecordingPaths(readDayDocument(dayPath), dayPath).map(_canonical));
          } on Object {
            return deleted;
          }
        }
        daysRead = true;
      }
      if (used.contains(_canonical(entry.path))) continue;
    }
    try {
      entry.deleteSync();
      deleted++;
    } on FileSystemException {
      // Left; tried again next time.
    }
  }
  return deleted;
}

final _copyName = RegExp(r'^[0-9a-f]{64}(\.vbo|\.rcz)$');

String _canonical(String path) {
  final absolute = p.normalize(p.absolute(path));
  try {
    if (FileSystemEntity.typeSync(absolute) != FileSystemEntityType.notFound) {
      return p.normalize(File(absolute).resolveSymbolicLinksSync());
    }
  } on FileSystemException {
    // As spelled.
  }
  return absolute;
}
