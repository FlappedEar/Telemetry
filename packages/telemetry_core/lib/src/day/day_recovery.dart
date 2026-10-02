// The unsaved day kept in the app's own folder so a crash or a closed app
// loses nothing (FET-7, after FlappedEar Overlays' `ProjectRecoveryStore`).
// The file is this app's, not a `.fetproject`: it wraps the day's version 3
// document with where it was last saved and when.
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;

import '../operation.dart';
import 'day_document.dart';

/// The recovery file format this app writes and reads.
const dayRecoveryVersion = 1;
const _kind = 'flappedear-telemetry-day-recovery';

/// An unsaved day: its document, written as if saved at [basePath] so its
/// relative recording paths resolve against it.
final class DayRecovery {
  DayRecovery({
    required this.document,
    required this.originalPath,
    required this.basePath,
    required this.timestamp,
  });

  /// The version 3 document of the day.
  final Map<String, Object?> document;

  /// Where the day was last saved or opened from; empty for a day never
  /// saved.
  final String originalPath;

  /// The path [document]'s relative paths are relative to: [originalPath],
  /// or the recovery file itself for a day never saved.
  final String basePath;
  final DateTime timestamp;

  Map<String, Object?> get _event => document['event'] as Map<String, Object?>;
  String get eventId => _event['id'] as String;
  String get name => _event['name'] as String;
}

/// The bytes of the recovery file of [recovery].
List<int> encodeDayRecovery(DayRecovery recovery) {
  final error = fet.validateFetproject(recovery.document);
  if (error != null) throw fet.FetprojectError(error);
  final bytes = utf8.encode(
    fet.encodeFetproject({
      'kind': _kind,
      'recoveryVersion': dayRecoveryVersion,
      'timestamp': recovery.timestamp.toUtc().toIso8601String(),
      'originalProjectPath': recovery.originalPath,
      'basePath': recovery.basePath,
      'project': recovery.document,
    }),
  );
  if (bytes.length > fet.maximumProjectBytes) {
    throw fet.FetprojectError(
      'The recovery snapshot would be ${bytes.length} bytes; the limit is '
      '${fet.maximumProjectBytes} bytes.',
    );
  }
  return bytes;
}

/// The recovery in [bytes]. Throws [fet.FetprojectError] for anything this
/// app did not write: another kind or version, or an invalid document.
DayRecovery decodeDayRecovery(List<int> bytes) {
  if (bytes.length > fet.maximumProjectBytes) {
    throw const fet.FetprojectError('The recovery snapshot is too large.');
  }
  final Object? decoded;
  try {
    decoded = fet.qtJsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const fet.FetprojectError('The recovery snapshot is not valid JSON.');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['kind'] != _kind ||
      decoded['recoveryVersion'] != dayRecoveryVersion) {
    throw const fet.FetprojectError('Unsupported recovery snapshot.');
  }
  final timestamp = DateTime.tryParse(decoded['timestamp'] as String? ?? '');
  final original = decoded['originalProjectPath'];
  final base = decoded['basePath'];
  final project = decoded['project'];
  if (timestamp == null ||
      original is! String ||
      base is! String ||
      base.isEmpty ||
      project is! Map<String, Object?>) {
    throw const fet.FetprojectError('The recovery snapshot is malformed.');
  }
  final error = fet.validateFetproject(project);
  if (error != null) throw fet.FetprojectError(error);
  return DayRecovery(
    document: project,
    originalPath: original,
    basePath: base,
    timestamp: timestamp,
  );
}

/// Writes [recovery] to [path] atomically, creating its folder.
Future<void> writeDayRecovery(String path, DayRecovery recovery) async {
  final bytes = encodeDayRecovery(recovery);
  final file = File(path);
  final temporary = File('$path.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp');
  try {
    await file.parent.create(recursive: true);
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
  } on FileSystemException catch (failure) {
    try {
      if (await temporary.exists()) await temporary.delete();
    } on FileSystemException {
      // The original failure is the one worth reporting.
    }
    throw fet.FetprojectError('Could not write the recovery snapshot: ${failure.message}');
  }
}

/// The recovery at [path]; null when there is none. Throws
/// [fet.FetprojectError] when the file cannot be used.
DayRecovery? readDayRecovery(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  if (file.lengthSync() > fet.maximumProjectBytes) {
    throw const fet.FetprojectError('The recovery snapshot is too large.');
  }
  return decodeDayRecovery(file.readAsBytesSync());
}

/// Removes the recovery at [path], if any.
Future<void> clearDayRecovery(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException catch (failure) {
    throw fet.FetprojectError('Could not remove the recovery snapshot: ${failure.message}');
  }
}

/// Opens the day in [recovery] (see [openDay]).
OpenedDay openRecoveredDay(DayRecovery recovery, {CancellationCheck? cancelled}) =>
    openDayDocument(recovery.document, recovery.basePath, cancelled: cancelled);
