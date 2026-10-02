import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  test('fingerprints a recording as Overlays stores it', () {
    const path = 'test/fixtures/basic.vbo';
    final bytes = File(path).readAsBytesSync();
    final session = parseVboFile(path);
    final fingerprint = telemetryFingerprint(path, session);
    expect(fingerprint['kind'], 'telemetry-v1');
    expect(fingerprint['size'], bytes.length);
    // A file under 64 KiB is sampled three times whole.
    expect(fingerprint['sampledSha256'], sha256.convert([...bytes, ...bytes, ...bytes]).toString());
    expect(fingerprint['sampleCount'], 3);
    expect(fingerprint['durationUs'], 1000000);
    final channels = (fingerprint['channels'] as List).cast<Map<String, Object?>>();
    final names = [for (final channel in channels) channel['name'] as String];
    expect(names, [...names]..sort());
    expect(names, session.channels.keys.toSet().toList()..sort());
    expect(channels.firstWhere((channel) => channel['name'] == 'velocity'), {
      'name': 'velocity',
      'unit': session.channels['velocity']!.unit,
      'samples': 3,
    });
  });
}
