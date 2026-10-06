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

final _progression = DayProgression(
  groupId: 'g',
  state: DayRankingState.available,
  runs: [
    _run('1', 112.0, q1: 0.5, q3: 1.2),
    _run('2', 109.898, q1: 0.1, q3: 0.5),
  ],
);

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
  DayTheoreticalBest? result,
  DayCoach? coach,
  bool coachLoading = false,
  DayChannelSummaries? channels,
  bool channelsLoading = false,
  Locale? locale,
}) => tester.pumpWidget(
  TelemetryApp(
    locale: locale,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SessionSummaryCard(
          runId: runId,
          session: 'Session $runId',
          progression: _progression,
          result: result,
          coach: coach,
          coachLoading: coachLoading,
          channels: channels,
          channelsLoading: channelsLoading,
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
  testWidgets('the latest session: new best, spread, car and goal', (
    tester,
  ) async {
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
      _text(tester, 'sessionSummaryCar'),
      'Car, hottest | Oil 112 °C (Session 1: 104 °C)',
    );
    expect(
      _text(tester, 'sessionSummaryGoal'),
      'Focus from Session 1 | Corner 3: Better.',
    );
    // The theoretical best is not ready yet.
    expect(_text(tester, 'sessionSummaryGain'), 'Biggest gain | Working…');
    expect(_text(tester, 'sessionSummaryGap'), 'Biggest gap left | Working…');
  });

  testWidgets('the first session, values still being worked out', (
    tester,
  ) async {
    await _pump(tester, runId: '1', coachLoading: true, channelsLoading: true);
    expect(
      _text(tester, 'sessionSummaryBest'),
      'Best lap | 1:52.000 · first session of the day',
    );
    expect(_text(tester, 'sessionSummarySpread'), 'Lap-time spread | 0.700 s');
    expect(_text(tester, 'sessionSummaryCar'), 'Car, hottest | Working…');
    // No session before, so no goal to check.
    expect(find.byKey(const ValueKey('sessionSummaryGoal')), findsNothing);
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

  testWidgets(
    'a theoretical best without a result leaves out the segment lines',
    (tester) async {
      await _pump(
        tester,
        result: DayTheoreticalBest(
          groupId: 'g',
          state: DayTheoreticalBestState.unavailable,
        ),
      );
      expect(find.byKey(const ValueKey('sessionSummaryGain')), findsNothing);
      expect(find.byKey(const ValueKey('sessionSummaryGap')), findsNothing);
    },
  );

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
  });
}
