// Moving a driver profile to another device (FET-133): one zip file with
// the profile, every day's document and the recordings the days use.
//
//   bundle.json                 {"format": profileBundleFormat, "version": 1}
//   driver.feprofile            the profile (driver_profile.dart)
//   Days/<eventId>.fetproject   each day, its recordings referenced as
//                               ../Recordings/<name>
//   Recordings/<name>           each recording once: <content SHA-256>.<ext>
//
// Reading one adds the days this profile does not have to its folder and
// index ([mergeDriverProfile]); nothing already here is changed.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;

import '../day/day_document.dart';
import 'driver_profile.dart';

const profileBundleFormat = 'flappedear-profile-bundle';
const profileBundleVersion = 1;

/// The extension of a bundle.
const profileBundleExtension = '.feprofile';

/// The profile's index and days folder inside its folder, as the app keeps
/// them.
const profileIndexName = 'driver.feprofile';
const profileDaysFolderName = 'Days';
const profileRecordingsFolderName = 'Recordings';

/// The largest recording a bundle may hold.
const maximumBundleRecordingBytes = 4 * 1024 * 1024 * 1024;

const _manifestName = 'bundle.json';

/// What [writeProfileBundle] wrote.
final class ProfileBundleExport {
  const ProfileBundleExport({
    this.days = 0,
    this.recordings = 0,
    this.daysMissing = const [],
    this.recordingsMissing = 0,
  });

  /// Days written with their documents.
  final int days;

  /// Recording files written.
  final int recordings;

  /// Days of the profile whose document was not in its folder: listed in
  /// the bundle's profile, without a document.
  final List<String> daysMissing;

  /// Recordings the days use that were not found: their days say so when
  /// opened, as on this device.
  final int recordingsMissing;
}

/// Writes [profile], kept in [folder], as a bundle at [target]: written
/// beside it first and moved into place, so a bundle is never half written.
Future<ProfileBundleExport> writeProfileBundle(
  DriverProfile profile,
  String folder,
  String target,
) async {
  final partial = '$target.partial';
  final encoder = ZipFileEncoder()..create(partial);
  var days = 0;
  final daysMissing = <String>[];
  // Each recording not found once, however many days use it.
  final missingRecordings = <String>{};
  // Each recording once, by the file it is on this device.
  final written = <String, String>{};
  final names = <String>{};
  try {
    encoder.addArchiveFile(
      ArchiveFile.string(
        _manifestName,
        jsonEncode({'format': profileBundleFormat, 'version': profileBundleVersion}),
      ),
    );
    for (final day in profile.days) {
      final path = p.joinAll([folder, ...day.file.split('/')]);
      final Map<String, Object?> document;
      try {
        document = readDayDocument(path);
      } on Object {
        daysMissing.add(day.eventId);
        continue;
      }
      for (final source in _telemetrySources(document)) {
        final reference = source['reference'];
        if (reference is! Map<String, Object?>) continue;
        final file = fet.SourceReference.fromJson(reference).resolve(path);
        if (file.isEmpty) {
          final digest = source['contentSha256'];
          missingRecordings.add(digest is String ? digest : jsonEncode(reference));
          continue;
        }
        var name = written[file];
        if (name == null) {
          final digest = source['contentSha256'];
          final extension = p.extension(file).toLowerCase();
          name = digest is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)
              ? '$digest$extension'
              : _safeName(p.basename(file));
          for (var copy = 2; names.contains(name); copy++) {
            name = '${p.basenameWithoutExtension(name!)} ($copy)$extension';
          }
          await encoder.addFile(File(file), '$profileRecordingsFolderName/$name');
          names.add(name!);
          written[file] = name;
        }
        source['reference'] = {
          for (final entry in reference.entries)
            if (entry.key != 'absolutePath' && entry.key != 'relativePath') entry.key: entry.value,
          'relativePath': '../$profileRecordingsFolderName/$name',
        };
      }
      encoder.addArchiveFile(
        ArchiveFile.string(
          '$profileDaysFolderName/${day.eventId}.fetproject',
          fet.encodeFetproject(document),
        ),
      );
      days++;
    }
    encoder.addArchiveFile(ArchiveFile.string(profileIndexName, encodeDriverProfile(profile)));
    await encoder.close();
  } on Object {
    try {
      await encoder.close();
    } on Object {
      // Already closed or never opened.
    }
    _delete(partial);
    rethrow;
  }
  File(partial).renameSync(target);
  return ProfileBundleExport(
    days: days,
    recordings: written.length,
    daysMissing: daysMissing,
    recordingsMissing: missingRecordings.length,
  );
}

/// What [readProfileBundle] added.
final class ProfileBundleImport {
  const ProfileBundleImport({
    required this.profile,
    this.added = const [],
    this.alreadyHere = const [],
    this.notAdded = const [],
    this.recordings = 0,
    this.notebooks = const [],
    this.notebookCut = false,
    this.source,
  });

  /// The profile with the days added: the caller writes it.
  final DriverProfile profile;

  /// Event ids of the days added.
  final List<String> added;

  /// Days this profile already had, left as they are.
  final List<String> alreadyHere;

  /// Days past this profile's limits, or without their document.
  final List<String> notAdded;

  /// Recording files added to the profile's folder.
  final int recordings;

  /// Tracks whose notebook took something of the bundle's
  /// ([ProfileMerge.notebooks]).
  final List<String> notebooks;

  /// Whether some of the bundle's notebook text did not fit.
  final bool notebookCut;

  /// The bundle's own profile, to merge again ([mergeDriverProfile]) into
  /// a profile changed while the bundle was read: merging [profile] would
  /// bring back what was changed meanwhile.
  final DriverProfile? source;
}

/// A bundle that cannot be read: not one, damaged, or too large.
final class ProfileBundleError implements Exception {
  const ProfileBundleError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Adds the days of the bundle at [bundle] that [into] does not have to the
/// profile kept in [folder]: their recordings, then their documents, are
/// written there; the profile with them is returned for the caller to
/// write. A day whose document is already in the folder is left as it is.
///
/// Everything is read and checked before anything is put in place: a
/// bundle that is not one, or is damaged anywhere, throws
/// [ProfileBundleError] and leaves the folder as it was.
Future<ProfileBundleImport> readProfileBundle(
  DriverProfile into,
  String folder,
  String bundle, {
  Random? random,
}) async {
  final input = InputFileStream(bundle);
  try {
    // Only the zip's directory is read here: archive's decoder would
    // unpack some entries (Unix links) whole, before anything is checked.
    final directory = ZipDirectory();
    try {
      directory.read(input);
    } on Object {
      throw const ProfileBundleError('This file is not a profile bundle.');
    }
    final entries = <String, ArchiveFile>{};
    for (final header in directory.fileHeaders) {
      final zip = header.file;
      if (zip == null) continue;
      final name = zip.filename.replaceAll(r'\', '/');
      if (name.endsWith('/')) continue;
      // Plain files only: no links, devices or folders by mode.
      final type = (header.externalFileAttributes >> 16) & 0xf000;
      if (!_allowed(name) || (header.versionMadeBy >> 8 == 3 && type != 0 && type != 0x8000)) {
        throw ProfileBundleError('The bundle holds a file it may not: $name.');
      }
      if (entries.containsKey(name)) {
        throw ProfileBundleError('The bundle holds $name twice.');
      }
      entries[name] = ArchiveFile.file(name, zip.uncompressedSize, zip)..crc32 = zip.crc32;
    }
    final manifest = _json(entries[_manifestName], 64 * 1024);
    if (manifest == null || manifest['format'] != profileBundleFormat) {
      throw const ProfileBundleError('This file is not a profile bundle.');
    }
    final version = manifest['version'];
    if (version is! int || version < 1 || version > profileBundleVersion) {
      throw const ProfileBundleError('The bundle is from another version of the app.');
    }
    final index = entries[profileIndexName];
    if (index == null || index.size > maximumProfileCharacters * 4) {
      throw const ProfileBundleError('The bundle has no profile.');
    }
    final DriverProfile from;
    try {
      from = decodeDriverProfile(utf8.decode(_bytes(index)));
    } on ProfileBundleError {
      rethrow;
    } on Object {
      throw const ProfileBundleError("The bundle's profile cannot be read.");
    }

    final days = Directory(p.join(folder, profileDaysFolderName));
    final candidates = <String>{};
    final present = <String>[];
    final missing = <String>[];
    for (final day in from.days) {
      if (into.day(day.eventId) != null) {
        present.add(day.eventId);
        continue;
      }
      final entry = entries['$profileDaysFolderName/${day.eventId}.fetproject'];
      if (entry == null || entry.size > fet.maximumProjectBytes) {
        missing.add(day.eventId);
      } else if (File(p.join(days.path, '${day.eventId}.fetproject')).existsSync()) {
        present.add(day.eventId);
      } else {
        candidates.add(day.eventId);
      }
    }
    final merge = mergeDriverProfile(into, from, only: candidates, random: random);

    // Every day read before anything is written.
    final documents = <String, Map<String, Object?>>{};
    for (final eventId in merge.added) {
      final entry = entries['$profileDaysFolderName/$eventId.fetproject']!;
      final Map<String, Object?> document;
      try {
        document = fet.decodeFetproject(_bytes(entry));
      } on Object {
        throw ProfileBundleError('The day $eventId in the bundle cannot be read.');
      }
      final event = document['event'];
      if (event is! Map<String, Object?> || event['id'] != eventId) {
        throw ProfileBundleError('The day $eventId in the bundle is another day.');
      }
      documents[eventId] = document;
    }

    final recordings = Directory(p.join(folder, profileRecordingsFolderName));
    // Recordings are unpacked beside the profile first, checked, and moved
    // into place only once every one of them is whole.
    _deleteStaging(folder);
    final staging = Directory(p.join(folder, '$_stagingPrefix${_stagingSuffix(random)}'));
    // A bundle's recording name, by the name it has in this folder.
    final placed = <String, String>{};
    // Staged files, by the name they take in Recordings.
    final staged = <String, String>{};
    final created = <String>[];
    try {
      for (final document in documents.values) {
        for (final source in _telemetrySources(document)) {
          final reference = source['reference'];
          if (reference is! Map<String, Object?>) continue;
          final relative = reference['relativePath'];
          const prefix = '../$profileRecordingsFolderName/';
          if (relative is! String || !relative.startsWith(prefix)) continue;
          final name = relative.substring(prefix.length);
          final recording = entries['$profileRecordingsFolderName/$name'];
          if (recording == null) continue;
          var here = placed[name];
          if (here == null) {
            final digest = source['contentSha256'];
            here = name;
            for (var copy = 2; ; copy++) {
              final taken = staged.keys.any((other) => other.toLowerCase() == here!.toLowerCase());
              final file = File(p.join(recordings.path, here!));
              if (!taken && !file.existsSync()) {
                staging.createSync(recursive: true);
                final path = p.join(staging.path, '${staged.length}');
                _extract(recording, path);
                staged[here] = path;
                // The recording the day was analysed from, or none.
                if (digest is String && await _sha256(path) != digest) {
                  throw ProfileBundleError('${recording.name} in the bundle is damaged.');
                }
                break;
              }
              // The same recording when its content is the one the day names.
              if (!taken &&
                  digest is String &&
                  file.lengthSync() == recording.size &&
                  await _sha256(file.path) == digest) {
                break;
              }
              here = '${p.basenameWithoutExtension(name)} ($copy)${p.extension(name)}';
            }
            placed[name] = here;
          }
          if (here != name) {
            source['reference'] = {...reference, 'relativePath': '$prefix$here'};
          }
        }
      }
      // Into place: the recordings, then the days that use them.
      if (staged.isNotEmpty) recordings.createSync(recursive: true);
      for (final MapEntry(key: name, value: path) in staged.entries) {
        final target = p.join(recordings.path, name);
        File(path).renameSync(target);
        created.add(target);
      }
      for (final MapEntry(key: eventId, value: document) in documents.entries) {
        days.createSync(recursive: true);
        final target = p.join(days.path, '$eventId.fetproject');
        created.add(target);
        await fet.writeFetproject(target, document);
      }
    } on Object {
      // Nothing half done is left: a day here is one the profile lists.
      created.forEach(_delete);
      rethrow;
    } finally {
      _deleteStaging(folder);
    }
    return ProfileBundleImport(
      profile: merge.profile,
      added: merge.added,
      alreadyHere: present,
      notAdded: [...merge.notAdded, ...missing],
      recordings: staged.length,
      notebooks: merge.notebooks,
      notebookCut: merge.notebookCut,
      source: from,
    );
  } finally {
    input.closeSync();
  }
}

const _stagingPrefix = '.bundle-import-';

String _stagingSuffix(Random? random) {
  final source = random ?? Random.secure();
  return List.generate(8, (_) => source.nextInt(16).toRadixString(16)).join();
}

/// Removes what an import cut short left in [folder].
void _deleteStaging(String folder) {
  final directory = Directory(folder);
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync()) {
    if (entity is Directory && p.basename(entity.path).startsWith(_stagingPrefix)) {
      try {
        entity.deleteSync(recursive: true);
      } on Object {
        // Removed by the next import.
      }
    }
  }
}

Future<String> _sha256(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

/// Every telemetry source entry of [document]'s runs.
Iterable<Map<String, Object?>> _telemetrySources(Map<String, Object?> document) sync* {
  final event = document['event'];
  if (event is! Map<String, Object?>) return;
  final runs = event['runs'];
  if (runs is! List) return;
  for (final run in runs) {
    if (run is! Map<String, Object?>) continue;
    final sources = run['sources'];
    if (sources is! Map<String, Object?>) continue;
    final telemetry = sources['telemetry'];
    if (telemetry is! List) continue;
    yield* telemetry.whereType<Map<String, Object?>>();
  }
}

/// Only the bundle's own files, each a plain name in its folder.
bool _allowed(String name) {
  if (name == _manifestName || name == profileIndexName) return true;
  final parts = name.split('/');
  if (parts.length != 2) return false;
  final file = parts[1];
  if (file.isEmpty ||
      file.startsWith('.') ||
      file.endsWith('.') ||
      file.endsWith(' ') ||
      file != _safeName(file) ||
      _reserved.hasMatch(file)) {
    return false;
  }
  return (parts[0] == profileDaysFolderName && file.endsWith('.fetproject')) ||
      parts[0] == profileRecordingsFolderName;
}

/// Names Windows keeps for devices, with any extension.
final _reserved = RegExp(
  r'^(con|prn|aux|nul|conin\$|conout\$|com[0-9¹²³]|lpt[0-9¹²³])(\.|$)',
  caseSensitive: false,
);

/// [name] without characters file systems refuse.
String _safeName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-');

Map<String, Object?>? _json(ArchiveFile? entry, int maximum) {
  if (entry == null || entry.size > maximum) return null;
  try {
    final value = jsonDecode(utf8.decode(_bytes(entry)));
    return value is Map<String, Object?> ? value : null;
  } on Object {
    return null;
  }
}

/// [entry]'s content: no more than it declares, unpacked no further than
/// that, and matching its checksum.
List<int> _bytes(ArchiveFile entry) {
  final bytes = BytesBuilder(copy: false);
  _unpack(entry, bytes.add);
  return bytes.takeBytes();
}

/// Writes [entry] to [path]: no more than it declares, matching its
/// checksum; a damaged or oversized entry leaves nothing behind.
void _extract(ArchiveFile entry, String path) {
  if (entry.size > maximumBundleRecordingBytes) {
    throw ProfileBundleError('${entry.name} in the bundle is too large.');
  }
  final file = File(path).openSync(mode: FileMode.writeOnly);
  try {
    try {
      _unpack(entry, file.writeFromSync);
    } finally {
      file.closeSync();
    }
  } on Object {
    _delete(path);
    rethrow;
  }
}

/// Hands [entry]'s content to [write] a piece at a time, as it is unpacked:
/// never more than the size it declares, so a small bundle cannot unpack
/// into more memory or disk than it says; then checks its size and CRC-32.
/// Only stored and deflated, unencrypted entries, as bundles are written.
void _unpack(ArchiveFile entry, void Function(List<int> bytes) write) {
  final zip = entry.rawContent;
  if (zip is! ZipFile ||
      zip.flags & 0x1 != 0 ||
      (zip.compressionMethod != CompressionType.none &&
          zip.compressionMethod != CompressionType.deflate)) {
    throw ProfileBundleError(
      '${entry.name} in the bundle is stored in a way this app does not read.',
    );
  }
  var length = 0;
  var crc = 0;
  void add(List<int> bytes) {
    length += bytes.length;
    if (length > entry.size) throw const _TooLong();
    crc = getCrc32(bytes, crc);
    write(bytes);
  }

  final raw = zip.getStream(decompress: false);
  final start = raw.position;
  try {
    final inflate = zip.compressionMethod == CompressionType.deflate
        ? ZLibCodec(raw: true).decoder.startChunkedConversion(_Pieces(add))
        : null;
    while (!raw.isEOS) {
      final piece = raw.readBytes(64 * 1024).toUint8List();
      if (inflate == null) {
        add(piece);
      } else {
        inflate.add(piece);
      }
    }
    inflate?.close();
  } on FileSystemException {
    // Writing where it is unpacked, or reading the bundle, failed.
    rethrow;
  } on Object {
    throw ProfileBundleError('${entry.name} in the bundle is damaged.');
  } finally {
    raw.setPosition(start);
  }
  final expected = entry.crc32 ?? zip.crc32;
  if (length != entry.size || crc != expected) {
    throw ProfileBundleError('${entry.name} in the bundle is damaged.');
  }
}

/// What the inflater unpacks, handed on as it comes.
final class _Pieces implements Sink<List<int>> {
  _Pieces(this._add);

  final void Function(List<int> bytes) _add;

  @override
  void add(List<int> data) => _add(data);

  @override
  void close() {}
}

/// More unpacked than an entry declares.
final class _TooLong implements Exception {
  const _TooLong();
}

void _delete(String path) {
  try {
    File(path).deleteSync();
  } on Object {
    // Not there.
  }
}
