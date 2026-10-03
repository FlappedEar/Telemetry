// Writes the synthetic RCZ archives of test/parity/rcz_corpus, built with the
// RCZ fixture (ported from VBOOverlay native/tests/RczFixture.h). No real
// recording. Run from packages/telemetry_core:
//   dart run test/parity/write_rcz_corpus.dart
import 'dart:io';
import 'dart:typed_data';

import '../rcz/rcz_fixture.dart';

/// A longer session on device 300 at 10 Hz: [samples] GPS fixes along a
/// line with speed, so the archive is larger than the fingerprint's three
/// sampled 64 KiB blocks.
Map<String, Uint8List> longMembers(int samples) {
  final members = fixtureMembers();
  final offsets = [for (var i = 0; i < samples; ++i) 100 + i * 100];
  members['channel_1_300_0_1_1'] = ticks(offsets);
  members['channel_1_300_0_3_1'] = ints([
    for (var i = 0; i < samples; ++i) ...[300000000 + i * 7, 120000000 + (i * i) % 9973],
  ]);
  members['channel_1_300_0_4_0'] = ints([
    for (var i = 0; i < samples; ++i) 10000 + (i * 37) % 20000,
  ]);
  return members;
}

void main() {
  final out = Directory('test/parity/rcz_corpus')..createSync(recursive: true);
  void write(String name, Uint8List bytes) => File('${out.path}/$name').writeAsBytesSync(bytes);
  write('basic.rcz', zip(fixtureMembers()));
  write('stored.rcz', zip(fixtureMembers(), compressed: false));
  write(
    'pedals.rcz',
    zip(
      fixtureMembers()
        ..['channel_5_200_10025_1_1'] = ticks([250, 1250])
        ..['channel2_5_200_10025_10025_3'] = doubles([13.3, 80.4])
        ..['channel_5_200_10071_1_1'] = ticks([250, 1250])
        ..['channel2_5_200_10071_10071_3'] = doubles([0, 100]),
    ),
  );
  write(
    'missing_values.rcz',
    zip(
      fixtureMembers()
        ..['channel_1_300_0_4_0'] = ints([10000, 0x7fffffff, 30000, 40000, 50000])
        ..['channel2_5_200_10024_10024_3'] = doubles([3000, double.infinity])
        ..['channel_1_100_0_4_0'] = ints([999999]),
    ),
  );
  write(
    'unknown_channel.rcz',
    zip(
      fixtureMembers()
        ..['channel_9_1_0_1_1'] = ticks([100])
        ..['channel_9_1_0_77_0'] = ints([1]),
    ),
  );
  write('long_stored.rcz', zip(longMembers(12000), compressed: false));
  write('long.rcz', zip(longMembers(12000)));
  write(
    'error_version.rcz',
    zip(
      fixtureMembers()
        ..['session.json'] = text(
          '{"version":2,"firstTimestamp":1780000000000,"trackName":"Synthetic","laps":[]}',
        ),
    ),
  );
}
