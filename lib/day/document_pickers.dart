import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../import/file_access.dart';
import '../l10n.dart';

/// Chooses where days are saved and which one opens. Replaced by a fake in
/// widget tests.
abstract interface class DocumentPickers {
  /// Where to save a day called [name]; null when the user cancelled.
  Future<String?> saveLocation(String name);

  /// A day to open; null when the user cancelled.
  Future<String?> pickDocument();

  /// A folder to look for missing recordings in; null when cancelled.
  Future<String?> pickFolder();

  /// Days saved inside the app (phones), newest first; empty on desktop,
  /// where days are files the user chose.
  Future<List<String>> savedDays();
}

bool get _desktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

const _extension = '.fetproject';

/// The name of a day's file: [name] without characters file systems refuse,
/// with the `.fetproject` extension once, even when [name] already ends in it.
String documentFileName(String name) {
  var cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-').trim();
  while (cleaned.toLowerCase().endsWith(_extension)) {
    cleaned = cleaned
        .substring(0, cleaned.length - _extension.length)
        .trimRight();
  }
  return '${cleaned.isEmpty ? 'Day' : cleaned}$_extension';
}

/// The name the save dialog suggests for [fileName]. The macOS panel adds
/// the extension of the accepted type itself, so it gets the name without
/// it (given with it, the panel showed `Day.fetproject.fetproject`).
String suggestedSaveName(String fileName, {required bool macOS}) =>
    macOS ? p.basenameWithoutExtension(fileName) : fileName;

/// [path] with the `.fetproject` extension once: added when the user's name
/// left it out, kept (in any case) when it is there.
String withDocumentExtension(String path) =>
    p.extension(path).toLowerCase() == _extension ? path : '$path$_extension';

/// On desktop, the system save and open dialogs (the macOS sandbox grants
/// write access to what the user picks). On phones, which have no save
/// dialog here, days are saved in the app's own documents folder and opened
/// from a list.
final class PlatformDocumentPickers implements DocumentPickers {
  const PlatformDocumentPickers();

  static XTypeGroup get _documents => XTypeGroup(
    label: deviceL10n().documentPickerDays,
    extensions: const ['fetproject'],
  );

  static Future<Directory> _daysFolder() async {
    final folder = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'Days'),
    );
    await folder.create(recursive: true);
    return folder;
  }

  @override
  Future<String?> saveLocation(String name) async {
    final fileName = documentFileName(name);
    if (_desktop) {
      final location = await getSaveLocation(
        suggestedName: suggestedSaveName(fileName, macOS: Platform.isMacOS),
        acceptedTypeGroups: [_documents],
      );
      if (location == null) return null;
      return withDocumentExtension(location.path);
    }
    final folder = await _daysFolder();
    var path = p.join(folder.path, fileName);
    for (var copy = 2; File(path).existsSync(); ++copy) {
      path = p.join(
        folder.path,
        '${p.basenameWithoutExtension(fileName)} ($copy)$_extension',
      );
    }
    return path;
  }

  @override
  Future<String?> pickDocument() async =>
      (await openFile(acceptedTypeGroups: _desktop ? [_documents] : const []))
          ?.path;

  @override
  Future<String?> pickFolder() async {
    final folder = await getDirectoryPath(
      confirmButtonText: deviceL10n().documentPickerLookInFolder,
    );
    if (folder != null) await const PlatformFileAccess().remember([folder]);
    return folder;
  }

  @override
  Future<List<String>> savedDays() async {
    if (_desktop) return const [];
    final folder = await _daysFolder();
    final days = [
      for (final entity in folder.listSync())
        if (entity is File && entity.path.endsWith(_extension)) entity,
    ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return [for (final file in days) file.path];
  }
}
