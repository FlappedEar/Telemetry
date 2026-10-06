import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/session_summary_card.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

const _revision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

DayLapRow _lap(String run, double duration) => DayLapRow(
  runId: run,
  runName: 'Session $run',
  type: LapSectionType.lap,
  lapNumber: 2,
  start: 10,
  end: 10 + duration,
  sourceRevision: _revision,
  referenceEligible: true,
);

ProgressionRun _run(
  String id,
  double best, {
  int laps = 4,
  double q1 = 0,
  double q3 = 0,
}) => ProgressionRun(
  run: ProgressionRunInfo(id: id, name: 'Session $id'),
  state: ProgressionRunState.available,
  lapCount: laps,
  eligibleLapCount: laps,
  bestLap: _lap(id, best),
  distribution: LapDistribution(
    minimum: best,
    q1: best + q1,
    median: best + (q1 + q3) / 2,
    q3: best + q3,
    maximum: best + q3,
  ),
);

ProgressionRun _empty(String id) => ProgressionRun(
  run: ProgressionRunInfo(id: id, name: 'Session $id'),
  state: ProgressionRunState.noEligibleLaps,
);

DayProgression _progression(List<ProgressionRun> runs) =>
    DayProgression(groupId: 'g', state: DayRankingState.available, runs: runs);

final _day = _progression([
  _run('1', 112.0, q1: 0.5, q3: 1.2),
  _run('2', 109.898, q1: 0.1, q3: 0.5),
]);

SectionProgressionCell _cell(String run, List<double> laps) =>
    SectionProgressionCell(
      runId: run,
      summary: summarizeConsistency(laps),
      laps: [for (final seconds in laps) SectionLapTime(seconds, null)],
    );

// Two sessions through two segments, as publishSectorProgression gives
// them: Corner 1 0.3 s quicker in session 2, Straight 2 0.2 s slower.
SectionProgression _sections({bool small = false}) {
  SectionProgressionRow row(
    String id,
    String name,
    List<double> one,
    List<double> two,
  ) {
    final cells = [_cell('1', one), _cell('2', two)];
    double? fastest;
    for (final cell in cells) {
      final median = cell.summary.median;
      if (cell.summary.available && (fastest == null || median! < fastest)) {
        fastest = median;
      }
    }
    return SectionProgressionRow(
      segmentId: id,
      name: name,
      type: 'corner',
      cells: cells,
      fastestTypical: fastest,
    );
  }

  return SectionProgression(
    sessions: [
      for (final id in ['1', '2'])
        SectionProgressionSession(
          run: ProgressionRunInfo(id: id, name: 'Session $id'),
          laps: const ConsistencySummary(),
        ),
    ],
    segments: small
        ? [
            row('c1', 'Corner 1', [10.0, 10.1, 10.2], [10.0, 10.12, 10.2]),
          ]
        : [
            row('c1', 'Corner 1', [10.0, 10.1, 10.2], [9.7, 9.8, 9.9]),
            row('s2', 'Straight 2', [8.0, 8.1, 8.2], [8.2, 8.3, 8.4]),
          ],
  );
}

final _channels = DayChannelSummaries(
  runs: [
    for (final (id, oil) in [('1', 104.0), ('2', 112.0)])
      RunChannelSummaries(
        runId: id,
        runName: 'Session $id',
        channels: [
          RunChannel(
            channel: 'engine_oil_temp-obd',
            unit: 'C',
            run: ChannelSummary(maximum: oil, valid: true),
          ),
        ],
      ),
  ],
);

DayCoach _coach(String runId) => DayCoach(
  runId: runId,
  reason: CoachReason.ready,
  goal: CoachGoalCheck(
    runId: '1',
    runName: 'Session 1',
    finding: CoachFinding(
      kind: CoachKind.excessiveCoasting,
      segmentId: 'c3',
      segmentName: 'Corner 3',
      confidence: 0.5,
      evidence: [
        CoachEvidence(
          key: CoachMetric.longestCoast,
          metric: 'Longest coast',
          observed: 2,
          reference: 1,
          unit: 's',
          referenceLaps: const [],
          detail: '',
        ),
      ],
      affectedLaps: const [],
    ),
    outcome: CoachGoalOutcome.better,
    before: 2,
    now: 1.2,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  String runId = '2',
  DayProgression? progression,
  DayTheoreticalBestState? state = DayTheoreticalBestState.ready,
  SectionProgression? sections,
  DayCoach? coach,
  bool coachLoading = false,
  String coachError = '',
  DayChannelSummaries? channels,
  Locale? locale,
}) => tester.pumpWidget(
  TelemetryApp(
    locale: locale,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SessionSummaryCard(
          runId: runId,
          session: 'Session $runId',
          progression: progression ?? _day,
          sectionsState: state,
          sections: sections ?? _sections(),
          coach: coach,
          coachLoading: coachLoading,
          coachError: coachError,
          channels: channels,
        ),
      ),
    ),
  ),
);

String _text(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .join(' | ');

void main() {
  testWidgets('the latest session: every line', (tester) async {
    await _pump(tester, coach: _coach('2'), channels: _channels);
    expect(find.text('Session 2 in 30 seconds'), findsOneWidget);
    expect(
      _text(tester, 'sessionSummaryBest'),
      'Best lap | 1:49.898 · new best of the day (−2.102 s)',
    );
    expect(
      _text(tester, 'sessionSummarySpread'),
      'Lap-time spread | 0.400 s (Session 1: 0.700 s)',
    );
    expect(
      _text(tester, 'sessionSummaryGain'),
      'Biggest gain | Corner 1 −0.300 s',
    );
    expect(
      _text(tester, 'sessionSummaryLoss'),
      'Biggest loss | Straight 2 +0.200 s',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sessionSummaryAgainst')))
          .data,
      'Gains and losses: typical segment times against Session 1.',
    );
    // Straight 2's 8.3 against session 1's 8.1.
    expect(
      _text(tester, 'sessionSummaryGap'),
      'Biggest gap left | Straight 2 +0.200 s to the quickest typical time there',
    );
    expect(
      _text(tester, 'sessionSummaryCar'),
      'Car, hottest | Oil 112 °C (Session 1: 104 °C)',
    );
    expect(
      _text(tester, 'sessionSummaryGoal'),
      'Focus from Session 1 | Corner 3: Better.',
    );
  });

  testWidgets('no change by the threshold; not a new best', (tester) async {
    await _pump(
      tester,
      progression: _progression([
        _run('1', 109.0),
        _run('2', 109.5, q1: 0.1, q3: 0.5),
      ]),
      sections: _sections(small: true),
    );
    expect(
      _text(tester, 'sessionSummaryBest'),
      'Best lap | 1:49.500 · +0.500 s on the best of Session 1',
    );
    expect(
      _text(tester, 'sessionSummaryGain'),
      'Biggest gain | None by 0.05 s or more',
    );
    expect(
      _text(tester, 'sessionSummaryLoss'),
      'Biggest loss | None by 0.05 s or more',
    );
  });

  testWidgets('the quickest typical time everywhere', (tester) async {
    await _pump(tester, runId: '1', sections: _sections(small: true));
    expect(
      _text(tester, 'sessionSummaryGap'),
      'Biggest gap left | Within 0.05 s of the quickest typical time wherever timed',
    );
    // A session timed alone has nothing to compare with.
    await _pump(
      tester,
      runId: '1',
      sections: SectionProgression(
        sessions: [_sections().sessions[0]],
        segments: [
          SectionProgressionRow(
            segmentId: 'c1',
            name: 'Corner 1',
            type: 'corner',
            cells: [
              _cell('1', [10.0, 10.1, 10.2]),
            ],
            fastestTypical: 10.1,
          ),
        ],
      ),
    );
    expect(
      _text(tester, 'sessionSummaryGap'),
      'Biggest gap left | No other session to compare with',
    );
  });

  testWidgets('a tie with the earlier best', (tester) async {
    await _pump(
      tester,
      progression: _progression([_run('1', 109.0), _run('2', 109.0)]),
    );
    expect(
      _text(tester, 'sessionSummaryBest'),
      'Best lap | 1:49.000 · equals the best of Session 1',
    );
  });

  testWidgets('the first session, values still being worked out', (
    tester,
  ) async {
    await _pump(
      tester,
      runId: '1',
      progression: _progression([_day.runs[0]]),
      state: null,
      coachLoading: true,
    );
    expect(
      _text(tester, 'sessionSummaryBest'),
      'Best lap | 1:52.000 · first session of the day',
    );
    expect(_text(tester, 'sessionSummarySpread'), 'Lap-time spread | 0.700 s');
    expect(_text(tester, 'sessionSummaryGain'), 'Biggest gain | Working…');
    expect(_text(tester, 'sessionSummaryGap'), 'Biggest gap left | Working…');
    expect(_text(tester, 'sessionSummaryCar'), 'Car, hottest | Working…');
    // No session before, so no goal to check.
    expect(find.byKey(const ValueKey('sessionSummaryGoal')), findsNothing);
  });

  testWidgets('the first session once the theoretical best is ready', (
    tester,
  ) async {
    await _pump(tester, runId: '1', progression: _progression([_day.runs[0]]));
    expect(
      _text(tester, 'sessionSummaryGain'),
      'Biggest gain | First session: nothing to compare with',
    );
    expect(find.byKey(const ValueKey('sessionSummaryAgainst')), findsNothing);
  });

  testWidgets('earlier sessions without a ranked lap', (tester) async {
    await _pump(
      tester,
      progression: _progression([
        _empty('1'),
        _run('2', 109.0, q1: 0.1, q3: 0.5),
      ]),
    );
    expect(
      _text(tester, 'sessionSummaryBest'),
      'Best lap | 1:49.000 · no earlier session has a ranked lap',
    );
    expect(
      _text(tester, 'sessionSummaryGain'),
      'Biggest gain | No earlier session has a ranked lap',
    );
    expect(
      _text(tester, 'sessionSummaryGoal'),
      'Focus from the session before | No change to work on was given',
    );
  });

  testWidgets('fewer than three laps through the segments', (tester) async {
    await _pump(
      tester,
      sections: SectionProgression(
        sessions: _sections().sessions,
        segments: [
          SectionProgressionRow(
            segmentId: 'c1',
            name: 'Corner 1',
            type: 'corner',
            cells: [
              _cell('1', [10.0]),
              _cell('2', [9.0, 9.1]),
            ],
          ),
        ],
      ),
    );
    expect(
      _text(tester, 'sessionSummaryGain'),
      'Biggest gain | Needs 3 laps through a segment in both sessions',
    );
    expect(
      _text(tester, 'sessionSummaryGap'),
      'Biggest gap left | Needs 3 laps through a segment',
    );
  });

  testWidgets('without a theoretical best, the segment lines say why', (
    tester,
  ) async {
    await _pump(tester, state: DayTheoreticalBestState.unavailable);
    expect(find.byKey(const ValueKey('sessionSummaryGain')), findsNothing);
    expect(
      _text(tester, 'sessionSummarySegments'),
      'Segments | Not available without a theoretical best',
    );
    // Nor does the coach run without it.
    expect(
      _text(tester, 'sessionSummaryGoal'),
      'Focus from the session before | Not available without a theoretical best',
    );
  });

  testWidgets('the car and the goal say why when they have nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      coachError: 'boom',
      channels: DayChannelSummaries(error: 'Channel summaries were cancelled.'),
    );
    expect(_text(tester, 'sessionSummaryCar'), startsWith('Car, hottest | '));
    expect(_text(tester, 'sessionSummaryCar'), isNot(contains('Working')));
    expect(
      _text(tester, 'sessionSummaryGoal'),
      'Focus from the session before | The coach could not run',
    );

    await _pump(tester, coachLoading: true, channels: DayChannelSummaries());
    expect(
      _text(tester, 'sessionSummaryGoal'),
      'Focus from the session before | Working…',
    );
    // No temperature recorded: no car line.
    expect(find.byKey(const ValueKey('sessionSummaryCar')), findsNothing);

    // The day records one, this session does not.
    await _pump(
      tester,
      channels: DayChannelSummaries(
        runs: [
          _channels.runs[0],
          RunChannelSummaries(runId: '2', runName: 'Session 2'),
        ],
      ),
    );
    expect(_text(tester, 'sessionSummaryCar'), 'Car, hottest | Not recorded');
  });

  testWidgets('a session the progression does not list says why', (
    tester,
  ) async {
    await _pump(tester, runId: '9');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sessionSummaryIntro')))
          .data,
      'Session 9 has no timed laps on the circuit shown.',
    );
    expect(find.byKey(const ValueKey('sessionSummaryBest')), findsNothing);
  });

  testWidgets('in Polish', (tester) async {
    await _pump(
      tester,
      coach: _coach('2'),
      channels: _channels,
      locale: const Locale('pl'),
    );
    expect(find.text('Sesja 2 w 30 sekund'), findsOneWidget);
    expect(
      _text(tester, 'sessionSummaryBest'),
      'Najlepsze okrążenie | 1:49.898 · nowy najlepszy czas dnia (−2.102 s)',
    );
    expect(
      _text(tester, 'sessionSummaryGoal'),
      'Cel po sesji: Sesja 1 | Zakręt 3: Lepiej.',
    );
    expect(
      _text(tester, 'sessionSummaryGain'),
      'Największy zysk | Zakręt 1 −0.300 s',
    );
  });
}
