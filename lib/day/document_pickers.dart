import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../import/file_access.dart';

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

/// The name of a day's file: [name] without characters file systems refuse,
/// with the `.fetproject` extension.
String documentFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-').trim();
  return '${cleaned.isEmpty ? 'Day' : cleaned}.fetproject';
}

/// On desktop, the system save and open dialogs (the macOS sandbox grants
/// write access to what the user picks). On phones, which have no save
/// dialog here, days are saved in the app's own documents folder and opened
/// from a list.
final class PlatformDocumentPickers implements DocumentPickers {
  const PlatformDocumentPickers();

  static const _documents = XTypeGroup(
    label: 'FlappedEar day',
    extensions: ['fetproject'],
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
        suggestedName: fileName,
        acceptedTypeGroups: const [_documents],
      );
      if (location == null) return null;
      final path = location.path;
      return p.extension(path) == '.fetproject' ? path : '$path.fetproject';
    }
    final folder = await _daysFolder();
    var path = p.join(folder.path, fileName);
    for (var copy = 2; File(path).existsSync(); ++copy) {
      path = p.join(
        folder.path,
        '${p.basenameWithoutExtension(fileName)} ($copy).fetproject',
      );
    }
    return path;
  }

  @override
  Future<String?> pickDocument() async => (await openFile(
    acceptedTypeGroups: _desktop ? const [_documents] : const [],
  ))?.path;

  @override
  Future<String?> pickFolder() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Look in this folder',
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
        if (entity is File && entity.path.endsWith('.fetproject')) entity,
    ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return [for (final file in days) file.path];
  }
}
