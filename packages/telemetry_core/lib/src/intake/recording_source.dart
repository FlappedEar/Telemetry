// Port of VBOOverlay native/src/telemetry/TelemetrySource.{h,cpp}: which files
// are recordings, and a recording's identity by content (FET-15).
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../operation.dart';

/// The recording formats the app imports. The parser is chosen by file
/// extension only, ignoring case.
enum RecordingFormat { vbo, rcz }

/// Largest recording accepted, in bytes (128 MiB), for VBO and RCZ alike.
const int maximumRecordingBytes = 128 * 1024 * 1024;

const int _readChunkBytes = 64 * 1024;

/// A recording could not be read, or changed while it was read.
final class RecordingSourceError implements Exception {
  const RecordingSourceError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The text after the last dot of the file name, lower-cased; empty without
/// a dot. Matches `QFileInfo::suffix().toLower()`.
String fileSuffix(String path) {
  final name = fileName(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// The last path component, accepting both separators.
String fileName(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  return cut < 0 ? path : path.substring(cut + 1);
}

/// The format a path is imported as, or null when it is not a recording.
RecordingFormat? recordingFormatOf(String path) => switch (fileSuffix(path)) {
  'vbo' => RecordingFormat.vbo,
  'rcz' => RecordingFormat.rcz,
  _ => null,
};

bool supportsRecordingPath(String path) => recordingFormatOf(path) != null;

/// The source id stored for a recording: `sha256:` and the lowercase hex
/// SHA-256 of the whole file. Never derived from the file name.
String recordingSourceId(String contentSha256Hex) => 'sha256:$contentSha256Hex';

/// SHA-256 of the whole file at [path], as lowercase hex.
///
/// [expectedBytes] is the size seen before reading; it must be 1 B to
/// [maximumRecordingBytes]. A file whose size differs before or after reading,
/// or that ends early, is an error: identity is only taken of a stable file.
/// Cooperatively cancellable between 64 KiB reads.
String contentSha256(String path, int expectedBytes, {CancellationCheck? cancelled}) {
  throwIfCancelled(cancelled);
  if (expectedBytes <= 0 || expectedBytes > maximumRecordingBytes) {
    throw const ResourceLimitError('Telemetry file exceeds the content identity size limit.');
  }
  final RandomAccessFile file;
  try {
    file = File(path).openSync();
  } on FileSystemException {
    throw const RecordingSourceError('Cannot read telemetry source.');
  }
  try {
    if (file.lengthSync() != expectedBytes) {
      throw const RecordingSourceError(
        'Telemetry source changed while reading; retry with a stable file.',
      );
    }
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    final buffer = Uint8List(_readChunkBytes);
    var remaining = expectedBytes;
    while (remaining > 0) {
      throwIfCancelled(cancelled);
      final wanted = remaining < _readChunkBytes ? remaining : _readChunkBytes;
      final read = file.readIntoSync(buffer, 0, wanted);
      if (read <= 0) {
        throw const RecordingSourceError('Telemetry source read failed or was truncated.');
      }
      hash.add(Uint8List.sublistView(buffer, 0, read));
      remaining -= read;
    }
    throwIfCancelled(cancelled);
    if (file.lengthSync() != expectedBytes || file.positionSync() != expectedBytes) {
      throw const RecordingSourceError(
        'Telemetry source changed while reading; retry with a stable file.',
      );
    }
    hash.close();
    return digest.value.toString();
  } on FileSystemException {
    throw const RecordingSourceError('Telemetry source read failed or was truncated.');
  } finally {
    file.closeSync();
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;
  Digest get value => _value!;
  @override
  void add(Digest data) => _value = data;
  @override
  void close() {}
}
