import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// `save-journal` in the app's support folder: where a day written in place
/// (the macOS sandbox, see `writeFetproject`) is kept until it reads back
/// whole. Null in `flutter test` and where there is no support folder.
Future<String?> saveJournalDirectory() async {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
  try {
    return p.join(
      (await getApplicationSupportDirectory()).path,
      'save-journal',
    );
  } on Exception {
    return null;
  }
}

/// Writes a day's document, keeping it in [saveJournalDirectory] while it
/// is written in place: the controller's default writer.
Future<void> saveDayWithJournal(
  String path,
  Map<String, Object?> document,
) async => saveDayDocument(
  path,
  document,
  journalDirectory: await saveJournalDirectory(),
);

/// Finishes a save of [path] the app did not live to finish, before the day
/// is opened (see [completeInterruptedSave]). Never throws: a day that
/// cannot be completed opens, or fails to, as it would have.
Future<void> completeInterruptedDaySave(String path) async {
  final directory = await saveJournalDirectory();
  if (directory == null) return;
  try {
    final outcome = await completeInterruptedSave(
      path,
      journalDirectory: directory,
    );
    if (outcome != InterruptedSave.none) {
      debugPrint('Interrupted save of $path: ${outcome.name}');
    }
  } on Object catch (error) {
    debugPrint('Interrupted save of $path not checked: $error');
  }
}
