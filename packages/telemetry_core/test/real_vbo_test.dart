// Runs only when FLAPPEDEAR_REAL_VBO names a real recording. Real recordings are
// private and never committed; report this result separately from synthetic tests.
@TestOn('vm')
library;

import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  final path = Platform.environment['FLAPPEDEAR_REAL_VBO'] ?? '';
  final skip = path.isEmpty ? 'FLAPPEDEAR_REAL_VBO is not set' : null;

  test('parses a real VBO with strictly increasing, finite timestamps', () {
    final session = parseVboFile(path);
    expect(session.sampleCount, greaterThan(0));
    expect(session.channels, isNotEmpty);
    expect(session.duration.isFinite && session.duration >= 0, isTrue);
    var finite = 0;
    for (final channel in session.channels.values) {
      expect(channel.sampleCount, session.sampleCount);
      for (var i = 1; i < channel.timestamps.length; ++i) {
        expect(channel.timestamps[i], greaterThan(channel.timestamps[i - 1]));
      }
      finite += channel.values.where((v) => v.isFinite).length;
    }
    expect(finite, greaterThan(0));
    printOnFailure('${session.sampleCount} samples, ${session.channels.length} channels');
  }, skip: skip);

  test('derives laps from a real VBO', () {
    final laps = deriveSourceLapSession(parseVboFile(path));
    for (var i = 1; i < laps.acceptedPasses.length; ++i) {
      expect(
        laps.acceptedPasses[i].telemetryTime,
        greaterThan(laps.acceptedPasses[i - 1].telemetryTime),
      );
    }
    if (laps.timedLaps.isNotEmpty) {
      expect(laps.fastestLapIndex, isNotNull);
    }
    // ignore: avoid_print
    print(
      'real laps: ${laps.status.name}, ${laps.timedLaps.length} laps, '
      'fastest ${laps.fastestLapIndex == null ? 'none' : laps.timedLaps[laps.fastestLapIndex!].durationSeconds}',
    );
  }, skip: skip);
}
