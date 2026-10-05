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

import 'package:archive/archive_io.dart';
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
  var recordingsMissing = 0;
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
          recordingsMissing++;
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
    recordingsMissing: recordingsMissing,
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
Future<ProfileBundleImport> readProfileBundle(
  DriverProfile into,
  String folder,
  String bundle, {
  Random? random,
}) async {
  final input = InputFileStream(bundle);
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } on Object {
      throw const ProfileBundleError('This file is not a profile bundle.');
    }
    final entries = <String, ArchiveFile>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll(r'\', '/');
      if (!_allowed(name)) {
        throw ProfileBundleError('The bundle holds a file it may not: $name.');
      }
      entries[name] = entry;
    }
    final manifest = _json(entries[_manifestName], 64 * 1024);
    if (manifest == null || manifest['format'] != profileBundleFormat) {
      throw const ProfileBundleError('This file is not a profile bundle.');
    }
    if (manifest['version'] case final int version when version > profileBundleVersion) {
      throw const ProfileBundleError('The bundle is from a newer version of the app.');
    }
    final index = entries[profileIndexName];
    if (index == null || index.size > maximumProfileCharacters * 4) {
      throw const ProfileBundleError('The bundle has no profile.');
    }
    final DriverProfile from;
    try {
      from = decodeDriverProfile(utf8.decode(_bytes(index)));
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

    final recordings = Directory(p.join(folder, profileRecordingsFolderName));
    var written = 0;
    // A bundle's recording name, by the name it has in this folder.
    final placed = <String, String>{};
    for (final eventId in merge.added) {
      final entry = entries['$profileDaysFolderName/$eventId.fetproject']!;
      final Map<String, Object?> document;
      try {
        document = fet.decodeFetproject(_bytes(entry));
      } on Object {
        throw ProfileBundleError('The day $eventId in the bundle cannot be read.');
      }
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
          recordings.createSync(recursive: true);
          here = name;
          for (var copy = 2; ; copy++) {
            final file = File(p.join(recordings.path, here!));
            if (!file.existsSync()) {
              _extract(recording, file.path);
              written++;
              break;
            }
            // Named by its content, so the same name is the same recording.
            if (file.lengthSync() == recording.size) break;
            here = '${p.basenameWithoutExtension(name)} ($copy)${p.extension(name)}';
          }
          placed[name] = here;
        }
        if (here != name) {
          source['reference'] = {...reference, 'relativePath': '$prefix$here'};
        }
      }
      days.createSync(recursive: true);
      await fet.writeFetproject(p.join(days.path, '$eventId.fetproject'), document);
    }
    return ProfileBundleImport(
      profile: merge.profile,
      added: merge.added,
      alreadyHere: present,
      notAdded: [...merge.notAdded, ...missing],
      recordings: written,
    );
  } finally {
    input.closeSync();
  }
}

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
  if (file.isEmpty || file.startsWith('.') || file != _safeName(file)) return false;
  return (parts[0] == profileDaysFolderName && file.endsWith('.fetproject')) ||
      parts[0] == profileRecordingsFolderName;
}

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

/// [entry]'s content, no more than it declares.
List<int> _bytes(ArchiveFile entry) {
  final bytes = entry.readBytes() ?? const <int>[];
  if (bytes.length != entry.size) {
    throw ProfileBundleError('${entry.name} in the bundle is damaged.');
  }
  return bytes;
}

/// Writes [entry] to [path], beside it first; a damaged or oversized entry
/// leaves nothing behind.
void _extract(ArchiveFile entry, String path) {
  if (entry.size > maximumBundleRecordingBytes) {
    throw ProfileBundleError('${entry.name} in the bundle is too large.');
  }
  final partial = '$path.partial';
  final output = OutputFileStream(partial);
  try {
    entry.writeContent(output);
    output.closeSync();
    if (File(partial).lengthSync() != entry.size) {
      throw ProfileBundleError('${entry.name} in the bundle is damaged.');
    }
    File(partial).renameSync(path);
  } on Object {
    try {
      output.closeSync();
    } on Object {
      // Closed already.
    }
    _delete(partial);
    rethrow;
  }
}

void _delete(String path) {
  try {
    File(path).deleteSync();
  } on Object {
    // Not there.
  }
}
