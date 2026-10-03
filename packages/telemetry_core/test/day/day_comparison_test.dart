import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';

double Function(double) _constant(double speed) =>
    (d) => speed;

DayRunInput _run(String id, TelemetrySession session) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
  session: session,
  laps: deriveSourceLapSession(session),
);

void main() {
  final runs = [
    _run('run1', rectangleSession([_constant(30), _constant(31), _constant(29)])),
    _run('run2', rectangleSession([_constant(28), _constant(32)])),
    // Another circuit: never compared with the rectangle.
    _run('run3', circuitSession(speeds: const [30, 30, 30])),
  ];
  final analysis = analyzeDay(runs);
  final group = analysis.chosenGroup!;
  final laps = analysis.rows.where((row) => row.type == LapSectionType.lap).toList();
  DayLapRow lap(String runId, int number) =>
      laps.firstWhere((row) => row.runId == runId && row.lapNumber == number);

  test('candidates are the eligible laps of the lap group', () {
    final candidates = dayComparisonCandidates(analysis, lap('run1', 1));
    expect(candidates.length, group.eligibleLapCount);
    expect(candidates.every((row) => row.runId != 'run3'), isTrue);
    expect(dayComparisonCandidates(analysis).length, group.eligibleLapCount);
    expect(dayLapGroupId(analysis, lap('run1', 1)), group.id);
  });

  test('two different laps of one group compare; others do not', () {
    expect(dayLapsComparable(analysis, lap('run1', 1), lap('run2', 1)), isTrue);
    expect(dayLapsComparable(analysis, lap('run1', 1), lap('run1', 1)), isFalse);
    final other = laps.firstWhere((row) => row.runId == 'run3');
    expect(dayLapsComparable(analysis, lap('run1', 1), other), isFalse);
  });

  test('B can be the best of the group or of A session', () {
    final best = group.ranking!.bestOfDay!;
    expect(dayBestComparisonLap(analysis, lap('run1', 2)), best);
    final runBest = dayBestComparisonLap(analysis, lap('run1', 2), sameRun: true)!;
    expect(runBest.runId, 'run1');
    expect(runBest.durationSeconds, lessThanOrEqualTo(lap('run1', 1).durationSeconds));
  });

  test('a day lap becomes a comparison lap of its recording', () {
    final named = [
      for (final run in runs)
        (
          run: TelemetryRunProposal(
            id: run.runId,
            sourceId: run.runId,
            sourcePath: '${run.runId}.vbo',
            format: RecordingFormat.vbo,
            contentSha256: run.contentSha256,
            telemetry: run.session,
            laps: run.laps,
          ),
          name: run.name,
        ),
    ];
    final row = lap('run2', 2);
    final comparisonLap = dayComparisonLap(named, row)!;
    expect(comparisonLap.session, same(runs[1].session));
    expect(comparisonLap.start, row.start);
    expect(comparisonLap.lapNumber, 2);
    final out = analysis.rows.firstWhere((row) => row.type == LapSectionType.outLap);
    expect(dayComparisonLap(named, out), isNull);
    final comparison = LapComparison(dayComparisonLap(named, lap('run1', 1))!, comparisonLap);
    // Lap B at 32 m/s, lap A at 30 m/s: A is behind at the line.
    expect(
      comparison.deltaSeries(0, comparison.axisLengthMeters, 100).segments.last.last.y,
      greaterThan(1),
    );
  });
}
