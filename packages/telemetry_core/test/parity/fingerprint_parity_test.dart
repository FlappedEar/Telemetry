// telemetry-v1 fingerprint parity with FlappedEar Overlays (FET-40): for
// every recording of the parity corpus, the RCZ corpus, the fixtures and the
// shared round-trip recordings, Telemetry's fingerprint is the one Overlays
// stores (tool/cpp_project_roundtrip `fingerprint`), and a recording Overlays
// cannot read is one Telemetry cannot read either.
//
// FET_FINGERPRINT_REFERENCE names another reference (for example one made
// locally for private recordings, never committed); its `file` entries are
// paths as given to the tool, relative to this package or absolute.
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'departures.dart';

void main() {
  final local = Platform.environment['FET_FINGERPRINT_REFERENCE'];
  final referencePath = local ?? 'test/parity/fingerprint_reference.json';
  final reference = [
    for (final value in jsonDecode(File(referencePath).readAsStringSync()) as List)
      value as Map<String, Object?>,
  ];

  test('the reference covers every corpus recording', () {
    final listed = {for (final entry in reference) entry['file']};
    for (final directory in [
      'test/parity/corpus',
      'test/parity/driving',
      'test/parity/rcz_corpus',
      'test/fixtures',
      '../fetproject/test/fixtures/roundtrip/recordings',
    ]) {
      for (final file in Directory(directory).listSync()) {
        if (file is File && supportsRecordingPath(file.path)) {
          expect(listed, contains(file.path), reason: 'regenerate the reference');
        }
      }
    }
    expect(reference.where((entry) => (entry['file'] as String).endsWith('.rcz')), isNotEmpty);
  }, skip: local != null ? 'another reference' : false);

  test('Telemetry fingerprints every recording as Overlays does', () {
    var compared = 0, refused = 0;
    for (final entry in reference) {
      final path = entry['file'] as String;
      final expected = entry['fingerprint'];
      TelemetrySession? session;
      Object? error;
      try {
        session = loadRecording(path);
      } on Exception catch (caught) {
        error = caught;
      }
      if (refusedByTelemetry(path)) {
        expect(session, isNull, reason: '$path: Telemetry refuses it');
        continue;
      }
      if (expected == null) {
        expect(session, isNull, reason: '$path: Overlays refuses it (${entry['error']})');
        ++refused;
        continue;
      }
      expect(error, isNull, reason: '$path: Overlays reads it');
      // Compared as Overlays compares them: the compact JSON of both objects.
      expect(
        fet.qtCompactJson(telemetryFingerprint(path, session!)),
        fet.qtCompactJson(expected),
        reason: path,
      );
      ++compared;
    }
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      print('fingerprints: $compared equal, $refused refused by both');
    }
    expect(compared, greaterThan(0));
  });
}
