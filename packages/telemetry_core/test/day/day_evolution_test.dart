import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _gates = 'gates-v1:0000000000000000000000000000000000000000000000000000000000000000';
const _revision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _track = TrackConfiguration(
  layoutId: 'Test circuit',
  direction: TrackDirection.clockwise,
  gateRevision: _gates,
);
const _otherTrack = TrackConfiguration(
  layoutId: 'Test circuit',
  direction: TrackDirection.counterclockwise,
  gateRevision: _gates,
);

DayLapRow _section(String run, LapSectionType type, int number, double start, double duration) =>
    DayLapRow(
      runId: run,
      runName: 'Session $run',
      type: type,
      lapNumber: number,
      start: start,
      end: start + duration,
      sourceRevision: _revision,
      referenceEligible: true,
    );

/// An out lap from [start] lasting [outLap], then timed laps back to back.
List<DayLapRow> _session(String run, double start, double outLap, List<double> laps) {
  final rows = [_section(run, LapSectionType.outLap, 0, start, outLap)];
  var time = start + outLap;
  for (var i = 0; i < laps.length; ++i) {
    rows.add(_section(run, LapSectionType.lap, i + 1, time, laps[i]));
    time += laps[i];
  }
  rows.add(_section(run, LapSectionType.inLap, 0, time, 120));
  return rows;
}

void main() {
  final groupId = _track.compatibilityGroupId!;
  final rows = [
    ..._session('1', 5, 150, [100, 95, 92, 91, 93]),
    ..._session('2', 0, 140, [98, 94, 90, 91, 92]),
    ..._session('3', 0, 130, [96, 97]),
    ..._session('4', 0, 130, [80, 81, 82]),
  ];
  final configurations = {'1': _track, '2': _track, '3': _track, '4': _otherTrack};
  final excluded = rows.firstWhere(
    (row) => row.runId == '2' && row.type == LapSectionType.lap && row.lapNumber == 1,
  );
  final ranking = rankDayLaps(
    rows,
    groupId,
    configurations,
    exclusions: {excluded.reference: 'Yellow flag'},
  );
  final progression = summarizeDayProgression(rows, ranking, [
    for (final id in ['1', '2', '3', '4']) ProgressionRunInfo(id: id, name: 'Session $id'),
  ], configurations);
  final evolution = summarizeDayEvolution(rows, ranking, progression);

  test('lists the group\'s sessions in the progression\'s order with every timed lap', () {
    expect(evolution.groupId, groupId);
    expect([for (final session in evolution.sessions) session.runId], ['1', '2', '3']);
    final first = evolution.sessions.first;
    expect([for (final lap in first.laps) lap.lapNumber], [1, 2, 3, 4, 5]);
    expect([for (final lap in first.laps) lap.seconds], [100, 95, 92, 91, 93]);
    // Time counts from the first timed lap, not from the recording's start.
    expect(first.laps.first.secondsSinceFirstLap, 0);
    expect(first.laps[1].secondsSinceFirstLap, 100);
    expect(first.laps[4].secondsSinceFirstLap, 378);
    expect(evolution.maximumLapNumber, 5);
    expect(evolution.hasLaps, isTrue);
  });

  test('lists a lap the ranking leaves out with its reasons, never measuring it', () {
    final second = evolution.sessions[1];
    final lap = second.laps.first;
    expect(lap.eligible, isFalse);
    expect(lap.issues, [LapIssue.userExclusion]);
    expect(lap.atPace, isFalse);
    // 98 s is excluded: the scale runs from 90 to 100.
    expect(evolution.minimumSeconds, 90);
    expect(evolution.maximumSeconds, 100);
    expect(second.typicalSeconds, 91.5);
  });

  test('finds the first lap at the session\'s pace (its upper quartile or quicker)', () {
    final [first, second, third] = evolution.sessions;
    // 91 92 93 95 100: the upper quartile is 95, reached on lap 2.
    expect(first.paceLimitSeconds, 95);
    expect(first.typicalSeconds, 93);
    expect(first.paceLapNumber, 2);
    expect(first.lapsBeforePace, 1);
    expect(first.notCountedBeforePace, 0);
    expect([for (final lap in first.laps) lap.atPace], [false, true, true, true, true]);
    // 90 91 92 94: 92.5. Lap 1 is not measured and lap 2 (94 s) is slower.
    expect(second.paceLimitSeconds, closeTo(92.5, 1e-12));
    expect(second.paceLapNumber, 3);
    expect(second.lapsBeforePace, 2);
    expect(second.notCountedBeforePace, 1);
    // Two laps are too few for a pace.
    expect(third.paceLimitSeconds, isNull);
    expect(third.typicalSeconds, isNull);
    expect(third.paceLapNumber, isNull);
    expect(third.lapsBeforePace, 0);
  });

  test('compares each session with the one before at the same lap numbers', () {
    final [first, second, third] = evolution.sessions;
    expect(first.previousRunId, isNull);
    expect(first.sameLapsDeltaSeconds, isNull);
    // Laps 2-5: -1, -2, 0, -1; lap 1 of session 2 is not measured.
    expect(second.previousRunName, 'Session 1');
    expect(second.sameLapsCount, 4);
    expect(second.sameLapsDeltaSeconds, -1);
    // Only lap 2 pairs up (lap 1 of session 2 is not measured): too few.
    expect(third.previousRunId, '2');
    expect(third.sameLapsCount, 1);
    expect(third.sameLapsDeltaSeconds, isNull);
  });

  test('gives nothing without a group, or for another group\'s ranking', () {
    final none = summarizeDayEvolution(
      rows,
      rankDayLaps(rows, null, configurations),
      DayProgression(groupId: null, state: DayRankingState.selectionRequired),
    );
    expect(none.sessions, isEmpty);
    expect(none.hasLaps, isFalse);
    expect(none.maximumLapNumber, 0);
    final other = summarizeDayEvolution(
      rows,
      rankDayLaps(rows, _otherTrack.compatibilityGroupId, configurations),
      progression,
    );
    expect(other.sessions, isEmpty);
  });

  test('a session without a recording is listed without laps', () {
    final withEmpty = summarizeDayProgression(
      rows,
      ranking,
      [
        for (final id in ['1', '5']) ProgressionRunInfo(id: id, name: 'Session $id'),
      ],
      {...configurations, '5': _track},
    );
    final result = summarizeDayEvolution(rows, ranking, withEmpty);
    expect([for (final session in result.sessions) session.runId], ['1', '5']);
    expect(result.sessions.last.laps, isEmpty);
    expect(result.sessions.last.sameLapsCount, 0);
  });
}
