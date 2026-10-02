import 'dart:io';
import 'dart:typed_data';

import '../operation.dart';
import '../telemetry_session.dart';
import 'vbo_limits.dart';
import 'vbo_parser.dart';

/// Reads and parses the VBO file at [path]. The size is checked before and
/// while reading, so an oversized file is never read whole.
TelemetrySession parseVboFile(String path, {CancellationCheck? cancelled}) {
  throwIfCancelled(cancelled);
  final RandomAccessFile file;
  try {
    file = File(path).openSync();
  } on FileSystemException catch (error) {
    throw VboParseError('Could not open VBO: ${error.osError?.message ?? error.message}');
  }
  try {
    final size = file.lengthSync();
    if (size > VboLimits.maximumFileBytes) {
      throw const ResourceLimitError('VBO exceeds the supported 128 MiB file size limit.');
    }
    final builder = BytesBuilder(copy: false);
    const chunkSize = 1024 * 1024;
    while (true) {
      throwIfCancelled(cancelled);
      final Uint8List chunk;
      try {
        chunk = file.readSync(chunkSize);
      } on FileSystemException catch (error) {
        throw VboParseError('Could not read VBO: ${error.osError?.message ?? error.message}');
      }
      if (chunk.isEmpty) break;
      if (chunk.length > VboLimits.maximumFileBytes - builder.length) {
        throw const ResourceLimitError('VBO exceeds the supported 128 MiB file size limit.');
      }
      builder.add(chunk);
    }
    throwIfCancelled(cancelled);
    return VboParser.parseBytes(builder.takeBytes(), cancelled: cancelled);
  } finally {
    file.closeSync();
  }
}
