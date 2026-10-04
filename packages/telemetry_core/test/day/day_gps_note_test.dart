import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

DayRunInput _run(String path) {
  final session = parseVboFile(path);
  return DayRunInput(
    runId: path,
    name: path.split('/').last,
    contentSha256: path,
    session: session,
    laps: deriveSourceLapSession(session),
  );
}

void main() {
  test('a recording without GPS says so instead of a missing line', () {
    final run = _run('test/parity/corpus/acceleration_aliases.vbo');
    // Lap detection still reports the line first, as in Overlays.
    expect(run.laps.status, LapSessionStatus.noSourceStartGate);
    expect(hasGpsPositions(run.session, run.laps), isFalse);
    expect(analyzeDay([run]).messages.map((message) => message.text), contains(noGpsNote));
  });

  test('a recording with GPS but no start/finish line keeps the start/finish note', () {
    final directory = Directory.systemTemp.createTempSync('gps_note');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/no-line.vbo';
    File(path).writeAsStringSync(
      File('test/parity/corpus/laps_gps_gap.vbo')
          .readAsStringSync()
          .replaceAll(RegExp(r'\[laptiming\][^\[]*'), ''),
    );
    final run = _run(path);
    expect(run.laps.status, LapSessionStatus.noSourceStartGate);
    expect(hasGpsPositions(run.session, run.laps), isTrue);
    final notes = analyzeDay([run]).messages.map((message) => message.text);
    expect(notes, contains(noPassesNote));
    expect(notes, isNot(contains(noGpsNote)));
  });
}
