import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _gates = 'gates-v1:0000000000000000000000000000000000000000000000000000000000000000';
const _revision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

DayLapRow lap(
  String run,
  int number,
  double start,
  double duration, {
  int? clock,
  bool eligible = true,
  LapReferenceIssue issue = LapReferenceIssue.none,
  bool offRoute = false,
}) => DayLapRow(
  runId: run,
  runName: 'Session ${run.substring(run.length - 1)}',
  type: LapSectionType.lap,
  lapNumber: number,
  start: start,
  end: start + duration,
  sourceRevision: _revision,
  timestampMilliseconds: clock,
  referenceEligible: eligible,
  referenceIssue: issue,
  offRoute: offRoute,
);

DayLapRow section(String run, LapSectionType type, double start, double end) => DayLapRow(
  runId: run,
  runName: 'Session ${run.substring(run.length - 1)}',
  type: type,
  lapNumber: 0,
  start: start,
  end: end,
  sourceRevision: _revision,
);

const _track = TrackConfiguration(
  layoutId: 'Jastrząb',
  direction: TrackDirection.clockwise,
  gateRevision: _gates,
);

void main() {
  group('dayLapRows', () {
    test('lists OUT, every timed lap and IN, with clocks from the recording', () {
      final session = circuitSession(firstTimestampMilliseconds: 1756454409000);
      final laps = deriveSourceLapSession(session);
      final rows = dayLapRows(
        session,
        laps,
        runId: 'run:1',
        runName: 'Session 1',
        sourceRevision: _revision,
        sourceOrder: 2,
      );
      expect(laps.timedLaps, hasLength(3));
      expect(rows.map((row) => row.type.label), ['OUT', 'LAP', 'LAP', 'LAP', 'IN']);
      expect(rows.map((row) => row.lapNumber), [0, 1, 2, 3, 0]);
      expect(rows.first.start, 0.0);
      expect(rows.first.end, laps.acceptedPasses.first.telemetryTime);
      expect(rows.last.end, session.duration);
      for (final row in rows) {
        expect(row.timestampMilliseconds, 1756454409000 + (row.start * 1000).round());
        expect(row.sourceOrder, 2);
      }
      final timed = rows.where((row) => row.type == LapSectionType.lap).toList();
      expect(timed.map((row) => row.durationSeconds), [
        for (final lap in laps.timedLaps) lap.endTelemetryTime - lap.startTelemetryTime,
      ]);
      // The 31 m/s lap is the fastest.
      expect(timed.map((row) => row.bestOfRun), [false, false, true]);
      expect(timed[1].displayName, 'Session 1 · LAP 2');
      expect(rows.first.displayName, 'Session 1 · OUT');
    });

    test('gives one UNKNOWN section without a gate pass, and no clock without one', () {
      final session = circuitSession(speeds: [30.0]);
      final noGate = TelemetrySession(
        duration: session.duration,
        startTime: 0,
        metadata: const {},
        channels: session.channels,
        aliases: session.aliases,
        warnings: const [],
        timingGates: const [],
        sampleCount: session.sampleCount,
      );
      final rows = dayLapRows(
        noGate,
        deriveSourceLapSession(noGate),
        runId: 'run:1',
        runName: 'Session 1',
        sourceRevision: _revision,
      );
      expect(rows, hasLength(1));
      expect(rows.single.type, LapSectionType.unknown);
      expect(rows.single.start, 0.0);
      expect(rows.single.end, noGate.duration);
      expect(rows.single.timestampMilliseconds, isNull);
    });

    test('honours cancellation', () {
      final session = circuitSession();
      expect(
        () => dayLapRows(
          session,
          deriveSourceLapSession(session),
          runId: 'run:1',
          runName: 'Session 1',
          sourceRevision: _revision,
          cancelled: () => true,
        ),
        throwsA(isA<OperationCancelled>()),
      );
    });
  });

  test('references are exact bounds in one content, not lap numbers', () {
    final a = lap('run:1', 1, 10.0, 90.0);
    final renamed = DayLapRow(
      runId: 'run:1',
      runName: 'Renamed',
      type: LapSectionType.lap,
      lapNumber: 7,
      start: 10.0,
      end: 100.0,
      sourceRevision: _revision,
    );
    expect(renamed.reference, a.reference);
    expect(lap('run:1', 1, 10.0, 90.000001).reference, isNot(a.reference));
  });

  test('sortDayLaps orders by clock, then undated runs in import order', () {
    final rows = [
      section('run:3', LapSectionType.unknown, 0, 10).copyWith(sourceOrder: 0),
      lap('run:2', 1, 5, 90, clock: 2000),
      lap('run:1', 1, 5, 90, clock: 1000),
      lap('run:4', 1, 0, 90).copyWith(sourceOrder: 1),
      lap('run:4', 2, 90, 90).copyWith(sourceOrder: 1),
    ];
    expect(sortDayLaps(rows).map((row) => '${row.runId}/${row.lapNumber}'), [
      'run:1/1',
      'run:2/1',
      'run:3/0',
      'run:4/1',
      'run:4/2',
    ]);
  });

  group('compatibility', () {
    test('a group needs a known layout, direction and gate revision', () {
      expect(_track.compatibilityGroupId, startsWith('compatibility-v1:'));
      expect(lapCompatibilityIssues(_track), isEmpty);
      expect(const TrackConfiguration(gateRevision: _gates).compatibilityGroupId, isNull);
      expect(lapCompatibilityIssues(const TrackConfiguration()), [
        LapIssue.layoutUnresolved,
        LapIssue.directionUnresolved,
        LapIssue.timingGateUnresolved,
      ]);
    });

    test('names what differs from a reference configuration', () {
      final other = _track.copyWith(layoutId: 'Short', direction: TrackDirection.counterclockwise);
      expect(lapCompatibilityIssues(other, reference: _track), [
        LapIssue.changedLayout,
        LapIssue.oppositeDirection,
      ]);
      expect(lapCompatibilityIssues(_track, issue: LapReferenceIssue.gpsGap, userExcluded: true), [
        LapIssue.incompleteGps,
        LapIssue.userExclusion,
      ]);
    });
  });

  group('rankDayLaps', () {
    final configurations = {'run:1': _track, 'run:2': _track, 'run:3': _track};
    final groupId = _track.compatibilityGroupId;

    test('needs a group', () {
      final ranking = rankDayLaps([lap('run:1', 1, 0, 90)], null, configurations);
      expect(ranking.state, DayRankingState.selectionRequired);
      expect(ranking.bestOfDay, isNull);
    });

    test('finds the best of the day and of each run, with quartiles', () {
      final rows = [
        section('run:1', LapSectionType.outLap, 0, 10),
        lap('run:1', 1, 10, 112.0, clock: 1000),
        lap('run:1', 2, 122, 110.5, clock: 2000),
        lap('run:1', 3, 232.5, 111.0, clock: 3000),
        lap('run:1', 4, 343.5, 113.0, clock: 4000),
        section('run:1', LapSectionType.inLap, 456.5, 500),
        lap('run:2', 1, 10, 109.898, clock: 9000),
        lap('run:2', 2, 119.898, 125.0, clock: 9500, issue: LapReferenceIssue.gpsGap),
      ];
      final ranking = rankDayLaps(rows, groupId, configurations);
      expect(ranking.state, DayRankingState.available);
      expect(ranking.bestOfDay!.displayName, 'Session 2 · LAP 1');
      expect(formatLapTime(ranking.bestOfDay!.durationSeconds, 3), '1:49.898');
      expect(ranking.lapCount, 6);
      expect(ranking.eligibleLapCount, 5);
      expect(ranking.runs.map((run) => run.runId), ['run:2', 'run:1']);
      final first = ranking.runs[1];
      expect(first.bestLap!.lapNumber, 2);
      expect(first.lapCount, 4);
      expect(first.distribution!.minimum, 110.5);
      expect(first.distribution!.q1, closeTo(110.875, 1e-9));
      expect(first.distribution!.median, closeTo(111.5, 1e-9));
      expect(first.distribution!.q3, closeTo(112.25, 1e-9));
      expect(first.distribution!.maximum, 113.0);
      expect(ranking.excludedLaps.single.row.lapNumber, 2);
      expect(ranking.excludedLaps.single.issues, [LapIssue.incompleteGps]);
    });

    test('applies user exclusions, off-route laps and stale sources', () {
      final fastest = lap('run:1', 1, 0, 100);
      final rows = [
        fastest,
        lap('run:1', 2, 100, 105),
        lap('run:2', 1, 0, 101, offRoute: true),
        lap('run:3', 1, 0, 99),
      ];
      final ranking = rankDayLaps(
        rows,
        groupId,
        configurations,
        exclusions: {fastest.reference: 'Yellow flag'},
        staleRunIds: {'run:3'},
      );
      expect(ranking.bestOfDay!.displayName, 'Session 1 · LAP 2');
      expect(ranking.runs.map((run) => run.runId), ['run:1', 'run:2', 'run:3']);
      expect(ranking.runs[1].available, isFalse);
      final reasons = {
        for (final excluded in ranking.excludedLaps) excluded.row.displayName: excluded.issues,
      };
      expect(reasons, {
        'Session 1 · LAP 1': [LapIssue.userExclusion],
        'Session 2 · LAP 1': [LapIssue.differentRecordedRoute],
        'Session 3 · LAP 1': [LapIssue.staleSource],
      });
      expect(ranking.excludedLaps.first.userReason, 'Yellow flag');
      expect(
        eligibleDayLaps(
          rows,
          groupId,
          configurations,
          exclusions: {fastest.reference: 'Yellow flag'},
          staleRunIds: {'run:3'},
        ).map((row) => row.displayName),
        ['Session 1 · LAP 2'],
      );
    });

    test('ranks only the chosen group', () {
      final configs = {
        'run:1': _track,
        'run:2': _track.copyWith(direction: TrackDirection.counterclockwise),
      };
      final ranking = rankDayLaps(
        [lap('run:1', 1, 0, 110), lap('run:2', 1, 0, 100)],
        groupId,
        configs,
      );
      expect(ranking.bestOfDay!.runId, 'run:1');
      expect(ranking.runs.map((run) => run.runId), ['run:1']);
    });

    test('breaks ties by clock, then run, never by name or lap number', () {
      final rows = [
        lap('run:2', 1, 0, 100, clock: 5000),
        lap('run:1', 9, 0, 100, clock: 5000),
        lap('run:3', 1, 0, 100, clock: 1000),
        lap('run:1', 1, 200, 100),
      ];
      final ranking = rankDayLaps(rows, groupId, configurations);
      expect(ranking.eligibleLaps.map((row) => '${row.runId}/${row.lapNumber}'), [
        'run:3/1',
        'run:1/9',
        'run:2/1',
        'run:1/1',
      ]);
      expect(ranking.tieCount, 4);
    });

    test('refuses more rows than the limit', () {
      final rows = List.generate(
        maximumDayLapRows + 1,
        (index) => lap('run:1', index, index * 1.0, 1),
      );
      expect(() => rankDayLaps(rows, groupId, configurations), throwsA(isA<ResourceLimitError>()));
    });
  });
}
