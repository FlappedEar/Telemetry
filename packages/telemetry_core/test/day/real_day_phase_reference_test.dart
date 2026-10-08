// The corner-phase reference (FET-226) on a real day. Set
// FLAPPEDEAR_REAL_DAY to a folder of one day's VBO files; nothing from them
// is written anywhere.
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test('the best phases of the day sit at or under the raw theoretical best', () {
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
    final phases = result.bestPhases!;
    String name(Object? reference) =>
        result.laps.firstWhere((lap) => lap.lap.reference == reference).lap.displayName;
    String time(double? seconds) => seconds == null ? '—' : formatLapTime(seconds, 3)!;
    final best = result.bestLap!;
    final losses = phases.lossesOf(best.reference);
    expect(losses, hasLength(phases.pieces.length));
    for (final (i, piece) in phases.pieces.indexed) {
      final p = piece.piece;
      final what = p.part == PhasePart.whole
          ? (p.corner ? 'whole (not split: ${p.splitReason})' : 'whole')
          : p.part.name;
      print(
        '${p.name} $what: ${piece.seconds?.toStringAsFixed(3)} s from '
        '${piece.seconds == null ? '—' : name(piece.lapReference)}; best lap loses '
        '${losses[i]?.toStringAsFixed(3)} s; join ${piece.join.name}'
        '${piece.joinMetresPerSecond == null ? '' : ' (${(piece.joinMetresPerSecond! * 3.6).toStringAsFixed(1)} km/h)'}',
      );
    }
    print(
      'best phases ${time(phases.totalSeconds)} from ${phases.lapCount} laps; joined '
      '${time(phases.joinedSeconds)} from ${phases.joinedLapCount} laps '
      '(${phases.joinedUnavailableReason}); raw ${time(result.theoreticalBestSeconds)}; '
      'realistic ${time(result.realistic?.totalSeconds)}; best lap ${time(result.bestLapSeconds)} '
      '(its pieces ${time(phases.lapTotal(best.reference))}); speed unit "${phases.speedUnit}"; '
      'apart ${phases.joinsOf(PhaseJoin.apart).length}, joins '
      '${phases.joinsOf(PhaseJoin.joins).length}, unknown ${phases.joinsOf(PhaseJoin.unknown).length}',
    );
    expect(phases.valid, isTrue);
    // A finer grain of the same idea: never slower than the raw best, and
    // the joined pieces never slower than the joined segments.
    expect(phases.totalSeconds, lessThanOrEqualTo(result.theoreticalBestSeconds! + 1e-6));
    expect(phases.joinedSeconds, isNotNull);
    expect(phases.joinedSeconds, lessThanOrEqualTo(result.realistic!.totalSeconds! + 1e-6));
    expect(phases.joinedSeconds, greaterThanOrEqualTo(phases.totalSeconds! - 1e-6));
    // The best lap's own pieces add up to its sector sum.
    expect(phases.lapTotal(best.reference), closeTo(result.bestLapSeconds!, 0.01));
    // Every corner of the day that is not split says why.
    for (final piece in phases.pieces) {
      if (piece.piece.corner && piece.piece.part == PhasePart.whole) {
        expect(piece.piece.splitReason, isNotEmpty, reason: piece.piece.name);
      }
    }
  }, skip: skip);
}
