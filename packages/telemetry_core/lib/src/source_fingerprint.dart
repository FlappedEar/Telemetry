import 'dart:io';

import 'package:fetproject/fetproject.dart';

import 'telemetry_session.dart';

/// The `telemetry-v1` fingerprint FlappedEar Overlays stores with a
/// recording's reference (`ProjectSourceReferenceCodec::telemetryFingerprint`):
/// the file's size and sampled SHA-256, and the parsed session's sample
/// count, duration and channels. A document whose fingerprint differs from
/// the file found on disk points at another recording.
Map<String, Object?> telemetryFingerprint(String path, TelemetrySession session) {
  // Qt's QString ordering: by UTF-16 code unit, case-sensitive.
  final names = session.channels.keys.toList()..sort();
  return {
    'kind': 'telemetry-v1',
    'size': FileSystemEntity.isFileSync(path) ? File(path).lengthSync() : 0,
    'sampledSha256': sampledSha256(path),
    'sampleCount': session.sampleCount,
    'durationUs': roundedMicroseconds(session.duration),
    'channels': [
      for (final name in names)
        {
          'name': name,
          'unit': session.channels[name]!.unit,
          'samples': session.channels[name]!.values.length,
        },
    ],
  };
}
