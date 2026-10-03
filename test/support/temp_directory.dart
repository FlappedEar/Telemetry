import 'dart:io';

/// Deletes a test's temporary folder.
///
/// On Windows a file still open cannot be deleted, for example a recording
/// that a cancelled import isolate is closing as it stops. The delete is
/// retried for up to two seconds, then fails: a file that stays open is a
/// leak worth seeing. The wait is a blocking sleep, so it also works in a
/// widget test's fake clock.
void deleteTemporaryDirectory(Directory directory) {
  for (var attempt = 1; ; attempt++) {
    try {
      directory.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (!Platform.isWindows || attempt == 20) rethrow;
      sleep(const Duration(milliseconds: 100));
    }
  }
}
