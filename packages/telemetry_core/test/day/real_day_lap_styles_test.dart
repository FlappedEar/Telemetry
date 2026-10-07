// Lap styles (FET-223) on a real day. Set FLAPPEDEAR_REAL_DAY to a folder of
// one day's VBO files; nothing from them is written anywhere. The expected
// figures are the owner's Jastrząb day of 29 August 2026 (best lap 1:49.898).
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

String _time(double seconds) {
  final whole = seconds.floor();
  final milliseconds = ((seconds - whole) * 1000).round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}';
}

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test('the ranked laps of the day are grouped by style, with the best lap of each', () {
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
    final day = result.lapStyles!;
    final styles = day.styles;
    print(
      'timed laps ${day.timedLapCount}, grouped ${day.groupedLapCount}, corners with a typical '
      '${styles.cornerCount}, braking figures ${day.brakeCornerFigures}, throttle figures '
      '${day.throttleCornerFigures}, deceleration unit assumed ${day.brakeUnitAssumed}',
    );
    expect(styles.available, isTrue, reason: styles.unavailableReason);
    expect(day.timedLapCount, 25);
    expect(day.groupedLapCount, result.laps.length);
    expect(day.groupedLapCount, lessThanOrEqualTo(day.timedLapCount));

    // The best lap of the day, as the day's other results have it.
    expect(styles.best!.seconds, closeTo(109.898, 0.0005));
    expect(day.rowOf(styles.best!).reference, result.bestLap!.reference);

    // Braking came from the deceleration, never the pedal.
    for (final input in day.inputs) {
      for (final sample in input.corners) {
        if (sample.brakeBeforeEntryMeters == null) continue;
        expect(sample.brakeSource, startsWith(brakingMethodInferred), reason: '$input');
      }
    }

    // Every lap is in exactly one style, and each style's best is its quickest.
    var grouped = 0;
    for (final group in styles.groups) {
      grouped += group.laps.length;
      for (final lap in group.laps) {
        expect(lap.seconds, greaterThanOrEqualTo(group.best.seconds));
        expect(lap.style, group.style);
      }
      print(
        '${group.style.name}: ${group.laps.length} laps, best '
        '${_time(group.best.seconds)} (${day.rowOf(group.best).displayName}), '
        '${group.bestDeltaSeconds.toStringAsFixed(3)} s behind the best lap, '
        '${group.quickerHalfCount} in the quicker half, typical '
        '${group.typicalSeconds == null ? '—' : _time(group.typicalSeconds!)}',
      );
    }
    expect(grouped, day.groupedLapCount);
    print('best lap ${_time(styles.best!.seconds)} is ${styles.best!.style.name}');
    for (final lap in styles.laps) {
      expect(lap.seconds.isFinite, isTrue);
      expect(lap.medianBrakeMeters?.isFinite ?? true, isTrue);
    }
  }, skip: skip);
}
