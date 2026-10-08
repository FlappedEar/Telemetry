// Grip and balance proxies (FET-229) on a real day. Set FLAPPEDEAR_REAL_DAY
// to a folder of one day's VBO files; nothing from them is written anywhere.
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

String _figure(GripFigure figure) => figure.known
    ? 'typical ${figure.typical?.toStringAsFixed(2) ?? '—'} peak '
          '${figure.peak!.toStringAsFixed(2)} ${figure.source.unit} (${figure.lapCount} laps)'
    : 'not known (${figure.reason})';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test('every corner timed on the day has its grip figures', () {
    final files =
        Directory(folder)
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.vbo'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);
    final runs = <DayRunInput>[
      for (final (index, file) in files.indexed)
        () {
          final session = withEffectiveSpeedUnits(parseVboFile(file.path));
          return DayRunInput(
            runId: 'run${index + 1}',
            name: 'Session ${index + 1}',
            contentSha256: '${index + 1}'.padLeft(64, '0'),
            session: session,
            laps: deriveSourceLapSession(session),
          );
        }(),
    ];
    final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
    final result = dayTheoreticalBest(analyzeDay(runs), outing, random: Random(1));
    expect(result.state, DayTheoreticalBestState.ready);
    final grip = result.grip!;
    expect(grip.corners.length, result.corners.length);
    for (final corner in grip.corners) {
      print(
        '${corner.name}: cornering ${_figure(corner.lateral)}; braking '
        '${_figure(corner.braking)}; exit ${_figure(corner.traction)}; balance '
        '${corner.balance.known ? corner.balance.typical : corner.balance.reason}',
      );
      final laps = result.corners.firstWhere((c) => c.segmentId == corner.segmentId).laps;
      if (laps.isEmpty) continue;
      expect(corner.lateral.known, isTrue, reason: '${corner.name}: ${corner.lateral.reason}');
      expect(corner.braking.known, isTrue, reason: '${corner.name}: ${corner.braking.reason}');
      expect(corner.traction.known, isTrue, reason: '${corner.name}: ${corner.traction.reason}');
      expect(corner.lateral.typical, isNotNull, reason: corner.name);
      // Every lap of a corner timed there is read: none is left without a
      // value ("not timed" or otherwise), and none is measured differently.
      for (final figure in [corner.lateral, corner.braking, corner.traction]) {
        expect(figure.unmeasured, 0, reason: corner.name);
        expect(figure.leftOut, 0, reason: corner.name);
        expect(figure.lapCount, laps.length, reason: corner.name);
      }
    }
    for (final session in grip.sessions) {
      expect(session.bands, isNotEmpty, reason: session.bandsReason);
      expect(session.bands.first.lateral.known, isTrue, reason: session.runName);
    }
  }, skip: skip);
}
