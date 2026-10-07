// The theoretical best of a real day from its VBO and from its RaceChrono RCZ
// files (FET-249). Set FLAPPEDEAR_REAL_DAY to a folder of one day's
// recordings, each session as both; nothing from them is written anywhere.
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

DayTheoreticalBest _theoreticalBest(String folder, String extension) {
  final files =
      Directory(folder)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith(extension))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  expect(files.length, greaterThanOrEqualTo(2));
  final runs = [
    for (final (index, file) in files.indexed)
      () {
        final session = loadRecording(file.path);
        return DayRunInput(
          runId: 'run${index + 1}',
          name: 'Session ${index + 1}',
          contentSha256: '${index + 1}'.padLeft(64, '0'),
          session: session,
          laps: deriveSourceLapSession(session),
        );
      }(),
  ];
  return dayTheoreticalBest(analyzeDay(runs), {
    for (final run in runs) run.runId: OutingRun(run.session, run.laps),
  }, random: Random(1));
}

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test('the RCZ files give the day the same segments as the VBO files', () {
    final vbo = _theoreticalBest(folder, '.vbo');
    final rcz = _theoreticalBest(folder, '.rcz');
    for (final result in [vbo, rcz]) {
      expect(result.state, DayTheoreticalBestState.ready, reason: result.message);
      expect(result.automaticSegments, isTrue);
    }
    print(
      'VBO: ${vbo.segments.length} segments, ${vbo.theoreticalBestSeconds}; '
      'RCZ: ${rcz.segments.length} segments, ${rcz.theoreticalBestSeconds}',
    );
    expect(rcz.segments.length, vbo.segments.length);
    expect(rcz.bestLapSeconds, closeTo(vbo.bestLapSeconds!, 0.01));
    expect(rcz.theoreticalBestSeconds, closeTo(vbo.theoreticalBestSeconds!, 0.5));
  }, skip: skip);
}
