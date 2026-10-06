import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _revision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

DayLapRow _lap(String run, int number, double duration) => DayLapRow(
  runId: run,
  runName: 'Session $run',
  type: LapSectionType.lap,
  lapNumber: number,
  start: 10,
  end: 10 + duration,
  sourceRevision: _revision,
  referenceEligible: true,
);

ProgressionRun _run(String id, {DayLapRow? best, int laps = 0, double? q1, double? q3}) =>
    ProgressionRun(
      run: ProgressionRunInfo(id: id, name: id),
      state: ProgressionRunState.available,
      lapCount: laps,
      eligibleLapCount: laps,
      bestLap: best,
      distribution: q1 == null
          ? null
          : LapDistribution(minimum: q1, q1: q1, median: (q1 + q3!) / 2, q3: q3, maximum: q3),
    );

SectionProgressionCell _cell(String run, List<double> laps) => SectionProgressionCell(
  runId: run,
  summary: summarizeConsistency(laps),
  laps: [for (final seconds in laps) SectionLapTime(seconds, null)],
);

// As publishSectorProgression builds it: the quickest median of any run.
SectionProgressionRow _row({
  required String segmentId,
  required String name,
  required String type,
  required List<SectionProgressionCell> cells,
}) {
  double? fastest;
  for (final cell in cells) {
    final median = cell.summary.median;
    if (cell.summary.available && (fastest == null || median! < fastest)) fastest = median;
  }
  return SectionProgressionRow(
    segmentId: segmentId,
    name: name,
    type: type,
    cells: cells,
    fastestTypical: fastest,
  );
}

SectionProgressionSession _session(String id) => SectionProgressionSession(
  run: ProgressionRunInfo(id: id, name: id),
  laps: const ConsistencySummary(),
);

RunChannel _temperature(String name, double? maximum) => RunChannel(
  channel: name,
  unit: 'C',
  run: ChannelSummary(channel: name, unit: 'C', maximum: maximum, valid: maximum != null),
);

void main() {
  final progression = DayProgression(
    groupId: 'g',
    state: DayRankingState.available,
    runs: [
      _run('1', best: _lap('1', 2, 112.0), laps: 4, q1: 113.0, q3: 114.0),
      _run('2', best: _lap('2', 3, 110.5), laps: 2, q1: 110.5, q3: 111.0),
      _run('3', best: _lap('3', 1, 110.0), laps: 3, q1: 110.2, q3: 110.6),
    ],
  );
  final sections = SectionProgression(
    sessions: [_session('1'), _session('2'), _session('3')],
    segments: [
      _row(
        segmentId: 'c1',
        name: 'Corner 1',
        type: 'corner',
        cells: [
          _cell('1', [10.0, 10.2, 10.4]),
          _cell('2', [9.6, 9.8, 10.0]),
          _cell('3', [9.5, 9.6, 9.7]),
        ],
      ),
      _row(
        segmentId: 's2',
        name: 'Straight 2',
        type: 'straight',
        cells: [
          _cell('1', [8.0, 8.1, 8.2]),
          _cell('2', [8.0, 8.1, 8.2]),
          _cell('3', [8.3, 8.4, 8.5]),
        ],
      ),
      _row(
        segmentId: 'c3',
        name: 'Corner 3',
        type: 'corner',
        cells: [
          _cell('1', [20.0, 20.1, 20.2]),
          _cell('2', [21.0, 21.02, 21.04]),
          _cell('3', [21.0, 21.04, 21.08]),
        ],
      ),
      _row(
        segmentId: 'c4',
        name: 'Corner 4',
        type: 'corner',
        cells: [
          _cell('1', [5.0, 5.1, 5.2]),
          _cell('2', [5.0]),
          _cell('3', [5.4, 5.5, 5.6]),
        ],
      ),
    ],
  );

  test('a new best, the gain and loss since the session before, and the gap left', () {
    final summary = summarizeSession('3', progression: progression, sections: sections)!;
    expect(summary.runName, '3');
    expect(summary.previousRunName, '2');
    expect(summary.firstSession, isFalse);
    expect(summary.bestLap!.durationSeconds, 110.0);
    expect(summary.earlierBestLap!.durationSeconds, 110.5);
    expect(summary.newBest, isTrue);
    expect(summary.bestDeltaSeconds, closeTo(-0.5, 1e-9));
    // Session 3 has three laps; session 2 only two, so it has no spread.
    expect(summary.lapSpread, closeTo(0.4, 1e-9));
    expect(summary.previousLapSpread, isNull);
    // Corner 4 has no typical time in session 2 (one lap).
    expect(summary.segmentsCompared, 3);
    expect(summary.biggestGain!.name, 'Corner 1');
    expect(summary.biggestGain!.deltaSeconds, closeTo(-0.2, 1e-9));
    expect(summary.biggestLoss!.name, 'Straight 2');
    expect(summary.biggestLoss!.deltaSeconds, closeTo(0.3, 1e-9));
    // Typical against the quickest typical of any session: Corner 3 is
    // 21.04 against session 1's 20.1.
    expect(summary.biggestGap!.name, 'Corner 3');
    expect(summary.biggestGap!.referenceSeconds, closeTo(20.1, 1e-9));
    expect(summary.biggestGap!.deltaSeconds, closeTo(0.94, 1e-9));
  });

  test('a change under the threshold is neither a gain nor a loss', () {
    final summary = summarizeSession(
      '3',
      progression: progression,
      sections: SectionProgression(sessions: sections.sessions, segments: [sections.segments[2]]),
    )!;
    // Corner 3 moved 0.02 s.
    expect(summary.segmentsCompared, 1);
    expect(summary.biggestGain, isNull);
    expect(summary.biggestLoss, isNull);
    expect(summary.biggestGap, isNotNull);
  });

  test('the best is against every other session; a slower best has a positive delta', () {
    final summary = summarizeSession('2', progression: progression, sections: sections)!;
    expect(summary.previousRunName, '1');
    // Session 3, listed after it, was quicker.
    expect(summary.earlierBestLap!.runId, '3');
    expect(summary.newBest, isFalse);
    expect(summary.bestDeltaSeconds, closeTo(0.5, 1e-9));
    expect(summary.previousLapSpread, closeTo(1.0, 1e-9));
    expect(summary.lapSpread, isNull);

    final slower = DayProgression(
      groupId: 'g',
      state: DayRankingState.available,
      runs: [progression.runs[2], progression.runs[0]],
    );
    final later = summarizeSession('1', progression: slower)!;
    expect(later.newBest, isFalse);
    expect(later.bestDeltaSeconds, closeTo(2.0, 1e-9));
  });

  test('the first session has nothing to compare with', () {
    final summary = summarizeSession('1', progression: progression, sections: sections)!;
    expect(summary.firstSession, isTrue);
    expect(summary.newBest, isFalse);
    expect(summary.previousRunName, isNull);
    final alone = summarizeSession(
      '1',
      progression: DayProgression(
        groupId: 'g',
        state: DayRankingState.available,
        runs: [progression.runs[0]],
      ),
    )!;
    expect(alone.earlierBestLap, isNull);
    expect(alone.bestDeltaSeconds, isNull);
    expect(summary.segmentsCompared, 0);
    expect(summary.biggestGain, isNull);
    expect(summary.biggestLoss, isNull);
    // Still the gap left: Straight 2's typical 8.1 is the quickest, Corner
    // 3's 20.1 too; Corner 1's 10.2 against session 3's 9.6.
    expect(summary.biggestGap!.name, 'Corner 1');
    expect(summary.biggestGap!.deltaSeconds, closeTo(0.6, 1e-9));
  });

  test('sessions and segments not ready yet give no segment lines', () {
    final summary = summarizeSession('3', progression: progression)!;
    expect(summary.segmentsCompared, 0);
    expect(summary.biggestGain, isNull);
    expect(summary.biggestGap, isNull);
    expect(summarizeSession('9', progression: progression), isNull);
  });

  test('the hottest temperatures against the session before', () {
    final channels = DayChannelSummaries(
      runs: [
        RunChannelSummaries(
          runId: '2',
          runName: '2',
          channels: [_temperature('engine_oil_temp-obd', 104.0)],
        ),
        RunChannelSummaries(
          runId: '3',
          runName: '3',
          channels: [
            _temperature('coolant_temp-obd', 92.0),
            _temperature('engine_oil_temp-obd', 112.0),
            _temperature('gearbox_temp-obd', null),
          ],
        ),
      ],
    );
    final summary = summarizeSession('3', progression: progression, channels: channels)!;
    expect(
      [for (final t in summary.temperatures) t.channel],
      ['engine_oil_temp-obd', 'coolant_temp-obd'],
    );
    expect(summary.temperatures[0].maximum, 112.0);
    expect(summary.temperatures[0].previousMaximum, 104.0);
    expect(summary.temperatures[0].unit, 'C');
    expect(summary.temperatures[1].previousMaximum, isNull);

    final failed = summarizeSession(
      '3',
      progression: progression,
      channels: DayChannelSummaries(runs: channels.runs, error: 'cancelled'),
    )!;
    expect(failed.temperatures, isEmpty);
    expect(failed.temperatureReason, 'cancelled');
  });

  test("the goal is the coach's only when it coached this session", () {
    final finding = CoachFinding(
      kind: CoachKind.lowMinimumSpeed,
      segmentId: 'c1',
      segmentName: 'Corner 1',
      confidence: 0.5,
      evidence: [
        CoachEvidence(
          key: CoachMetric.minimumSpeed,
          metric: 'Minimum speed',
          observed: 60,
          reference: 63,
          unit: 'km/h',
          referenceLaps: const [],
          detail: '',
        ),
      ],
      affectedLaps: const [],
    );
    final goal = CoachGoalCheck(
      runId: '2',
      runName: '2',
      finding: finding,
      outcome: CoachGoalOutcome.better,
      before: 60,
      now: 62,
    );
    final coach = DayCoach(runId: '3', reason: CoachReason.ready, goal: goal);
    expect(summarizeSession('3', progression: progression, coach: coach)!.goal, same(goal));
    expect(summarizeSession('2', progression: progression, coach: coach)!.goal, isNull);
  });

  test('the session before without a ranked lap is skipped for comparisons', () {
    final withGap = DayProgression(
      groupId: 'g',
      state: DayRankingState.available,
      runs: [
        progression.runs[0],
        ProgressionRun(
          run: const ProgressionRunInfo(id: '2', name: '2'),
          state: ProgressionRunState.noRecordedLaps,
        ),
        progression.runs[2],
      ],
    );
    final summary = summarizeSession(
      '3',
      progression: withGap,
      sections: SectionProgression(
        sessions: [sections.sessions[0], sections.sessions[2]],
        segments: [
          for (final row in sections.segments)
            _row(
              segmentId: row.segmentId,
              name: row.name,
              type: row.type,
              cells: [row.cells[0], row.cells[2]],
            ),
        ],
      ),
    )!;
    expect(summary.earlierSessions, 2);
    expect(summary.firstSession, isFalse);
    expect(summary.previousRunName, '1');
    expect(summary.previousLapSpread, closeTo(1.0, 1e-9));
    // Against session 1: Corner 1 10.2 -> 9.6, Corner 3 20.1 -> 21.04.
    expect(summary.segmentsCompared, 4);
    expect(summary.biggestGain!.name, 'Corner 1');
    expect(summary.biggestLoss!.name, 'Corner 3');
  });

  test('earlier sessions without a ranked lap: no previous, not the first', () {
    final none = DayProgression(
      groupId: 'g',
      state: DayRankingState.available,
      runs: [
        ProgressionRun(
          run: const ProgressionRunInfo(id: '1', name: '1'),
          state: ProgressionRunState.noEligibleLaps,
        ),
        progression.runs[2],
      ],
    );
    final summary = summarizeSession('3', progression: none)!;
    expect(summary.firstSession, isFalse);
    expect(summary.previousRunName, isNull);
    expect(summary.earlierBestLap, isNull);
    expect(summary.newBest, isFalse);
  });

  test('a tie with the earlier best is not a new best', () {
    final tie = DayProgression(
      groupId: 'g',
      state: DayRankingState.available,
      runs: [
        _run('1', best: _lap('1', 1, 110.0), laps: 3, q1: 110.0, q3: 110.5),
        _run('2', best: _lap('2', 1, 110.0), laps: 3, q1: 110.0, q3: 110.5),
      ],
    );
    final summary = summarizeSession('2', progression: tie)!;
    expect(summary.newBest, isFalse);
    expect(summary.bestDeltaSeconds, 0);
    // Less than half a millisecond apart reads as the same time.
    final near = summarizeSession(
      '2',
      progression: DayProgression(
        groupId: 'g',
        state: DayRankingState.available,
        runs: [
          tie.runs[0],
          _run('2', best: _lap('2', 1, 109.9998), laps: 3, q1: 110.0, q3: 110.5),
        ],
      ),
    )!;
    expect(near.newBest, isFalse);
    expect(near.bestDeltaSeconds, 0);
  });

  test('a temperature in another unit is not compared, a failure says why', () {
    RunChannelSummaries run(String id, String unit, double maximum) => RunChannelSummaries(
      runId: id,
      runName: id,
      channels: [
        RunChannel(
          channel: 'engine_oil_temp-obd',
          unit: unit,
          run: ChannelSummary(maximum: maximum, valid: true),
        ),
      ],
    );
    final mixed = summarizeSession(
      '3',
      progression: progression,
      channels: DayChannelSummaries(runs: [run('2', 'F', 230), run('3', 'C', 112)]),
    )!;
    expect(mixed.temperatures.single.previousMaximum, isNull);
    final same = summarizeSession(
      '3',
      progression: progression,
      channels: DayChannelSummaries(runs: [run('2', '°C', 104), run('3', 'C', 112)]),
    )!;
    expect(same.temperatures.single.previousMaximum, 104);
    final unread = summarizeSession(
      '3',
      progression: progression,
      channels: DayChannelSummaries(
        runs: [RunChannelSummaries(runId: '3', runName: '3', unavailableReason: 'missing')],
      ),
    )!;
    expect(unread.temperatures, isEmpty);
    expect(unread.temperatureReason, 'missing');
  });

  test('no gap when the session has the quickest typical time everywhere', () {
    final summary = summarizeSession(
      '2',
      progression: progression,
      sections: SectionProgression(sessions: sections.sessions, segments: [sections.segments[1]]),
    )!;
    expect(summary.segmentsTimed, 1);
    expect(summary.biggestGap, isNull);
  });
}
