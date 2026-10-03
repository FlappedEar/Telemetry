import 'dart:io';

/// Deletes a test's temporary folder.
///
/// On Windows a file that the test's background work (an import isolate, a
/// recovery write) still has open cannot be deleted. The folder is then left
/// for the runner's temp cleanup instead of failing a test whose checks have
/// already passed. Every other platform still fails on a delete error.
void deleteTemporaryDirectory(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
  }
}
