import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

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

DayLapRow _lap(
  String run,
  int number,
  double start,
  double duration, {
  int? clock,
  bool eligible = true,
}) => DayLapRow(
  runId: run,
  runName: 'Session $run',
  type: LapSectionType.lap,
  lapNumber: number,
  start: start,
  end: start + duration,
  sourceRevision: _revision,
  timestampMilliseconds: clock,
  referenceEligible: eligible,
);

DayLapRow _out(String run, {int? clock}) => DayLapRow(
  runId: run,
  runName: 'Session $run',
  type: LapSectionType.outLap,
  lapNumber: 0,
  start: 0,
  end: 10,
  sourceRevision: _revision,
  timestampMilliseconds: clock,
);

ProgressionRunInfo _info(String run, {String? notes}) =>
    ProgressionRunInfo(id: run, name: 'Session $run', notes: notes);

void main() {
  final groupId = _track.compatibilityGroupId!;

  group('summarizeDayProgression', () {
    // Run 3 was recorded first, run 1 second; run 2 and 4 have no clock.
    final rows = [
      _out('3', clock: 1000),
      _lap('3', 1, 10, 92, clock: 11000),
      _lap('3', 2, 102, 91, clock: 103000),
      _lap('3', 3, 193, 93, clock: 194000),
      _out('1', clock: 5000000),
      _lap('1', 1, 10, 90, clock: 5010000),
      _lap('1', 2, 100, 95, clock: 5100000),
      _lap('2', 1, 10, 99, eligible: false),
      _lap('4', 1, 10, 89),
      _lap('5', 1, 10, 80),
    ];
    final configurations = {
      '1': _track,
      '2': _track,
      '3': _track,
      '4': _track,
      '5': _otherTrack,
      '6': _track,
    };
    final exclusions = {rows[6].reference: 'Yellow flag'};
    final ranking = rankDayLaps(rows, groupId, configurations, exclusions: exclusions);
    final runs = [
      for (final id in ['1', '2', '3', '4', '5', '6']) _info(id, notes: 'n$id'),
    ];
    final progression = summarizeDayProgression(rows, ranking, runs, configurations);

    test('lists the group\'s runs by clock, then in the day\'s order', () {
      expect(progression.state, DayRankingState.available);
      expect(progression.groupId, groupId);
      expect([for (final run in progression.runs) run.runId], ['3', '1', '2', '4', '6']);
      expect(progression.runs[0].firstSectionUtcMilliseconds, 1000);
      expect(progression.runs[0].chronologyKnown, isTrue);
      expect(progression.runs[2].chronologyKnown, isFalse);
      expect(progression.runs[0].run.notes, 'n3');
      expect(progression.lapCount, 7);
      expect(progression.eligibleLapCount, 5);
    });

    test('gives each run its state, best lap and quartiles', () {
      final [first, second, noEligible, last, noRecording] = progression.runs;
      expect(first.state, ProgressionRunState.available);
      expect(first.bestLap!.lapNumber, 2);
      expect(first.distribution!.median, 92);
      expect(second.eligibleLapCount, 1);
      expect(second.lapCount, 2);
      expect(second.excludedLaps.single.userReason, 'Yellow flag');
      expect(noEligible.state, ProgressionRunState.noEligibleLaps);
      expect(noEligible.bestLap, isNull);
      expect(noEligible.distribution, isNull);
      expect(noEligible.excludedLaps.single.issues, [LapIssue.ineligibleLap]);
      expect(noRecording.state, ProgressionRunState.noRecordedLaps);
      expect(noRecording.lapCount, 0);
      expect(last.bestLap!.durationSeconds, 89);
      expect(progression.minimumSeconds, 89);
      expect(progression.maximumSeconds, 93);
    });

    test('compares each best lap with the run listed before it, never across a gap', () {
      final deltas = [for (final run in progression.runs) run.bestDeltaPreviousListedSeconds];
      expect(deltas[0], isNull);
      expect(deltas[1], closeTo(90 - 91, 1e-12));
      expect(deltas[2], isNull);
      // Run 4 follows run 2, which has no eligible lap.
      expect(deltas[3], isNull);
      expect(deltas[4], isNull);
      expect(progression.runs[1].previousListedRunName, 'Session 3');
      expect(progression.runs[0].previousListedRunName, isNull);
    });

    test('is empty without a group', () {
      final none = summarizeDayProgression(
        rows,
        rankDayLaps(rows, null, configurations),
        runs,
        configurations,
      );
      expect(none.state, DayRankingState.selectionRequired);
      expect(none.runs, isEmpty);
      expect(none.minimumSeconds, isNull);
    });

    test('refuses too many runs', () {
      expect(
        () =>
            summarizeDayProgression(rows, ranking, [for (var i = 0; i < 65; ++i) _info('$i')], {}),
        throwsA(isA<ResourceLimitError>()),
      );
    });
  });

  group('summarizeLapConsistency', () {
    test('needs three laps for a median and spread', () {
      final two = summarizeLapConsistency([_lap('1', 1, 0, 90), _lap('1', 2, 90, 91)]);
      expect(two.day.available, isFalse);
      expect(two.day.count, 2);
      expect(two.day.unavailableReason, consistencyTooFewSamples);
      expect(two.day.median, isNull);
      expect(two.day.interquartileRange, isNull);
      expect(summarizeLapConsistency(const []).day.available, isFalse);
    });

    test('gives the day and each run in the order they were recorded', () {
      final consistency = summarizeLapConsistency([
        _lap('2', 1, 0, 92),
        _lap('1', 1, 0, 90),
        _lap('2', 2, 92, 94),
        _lap('2', 3, 186, 93),
        _lap('1', 2, 90, 100),
      ]);
      expect(consistency.day.count, 5);
      expect(consistency.day.median, 93);
      expect(consistency.day.q1, 92);
      expect(consistency.day.q3, 94);
      expect(consistency.day.interquartileRange, 2);
      expect([for (final run in consistency.runs) run.runId], ['2', '1']);
      expect(consistency.runs[0].runName, 'Session 2');
      expect(consistency.runs[0].laps.median, 93);
      expect(consistency.runs[0].laps.interquartileRange, closeTo(1, 1e-12));
      expect(consistency.runs[1].laps.available, isFalse);
    });
  });

  test('progressionRunInfo reads the context a day document records', () {
    final session = rectangleSession([(d) => 30.0]);
    NamedRun named(String id, String name) => (
      run: TelemetryRunProposal(
        id: id,
        sourceId: 'sha256:$_revision',
        sourcePath: '/$id.vbo',
        format: RecordingFormat.vbo,
        contentSha256: _revision,
        telemetry: session,
        laps: deriveSourceLapSession(session),
      ),
      name: name,
    );
    final info = progressionRunInfo(
      [named('run:1', 'Session 1'), named('run:2', 'Session 2')],
      documentRuns: [
        {
          'id': 'run:1',
          'setup': {'version': 'session-setup-v1', 'tyre': ' '},
        },
        {
          'id': 'run:2',
          'notes': 'Wet',
          'conditions': ' ',
          'setupChanges': 3,
          'setup': {
            'pressureUnit': 'bar',
            'coldPressure': {'fl': 2.1, 'rr': 9.9},
            'fuelStartLitres': 8.5,
          },
        },
        'not a run',
      ],
    );
    expect([for (final run in info) run.name], ['Session 1', 'Session 2']);
    expect(info[0].notes, isNull);
    expect(info[1].notes, 'Wet');
    expect(info[1].conditions, isNull);
    expect(info[1].setupChanges, isNull);
    // A setup with nothing in it is not recorded; an invalid pressure is not
    // entered.
    expect(info[0].setup, isNull);
    expect(
      info[1].setup,
      const RunSetup(
        pressureUnit: PressureUnit.bar,
        cold: WheelPressures(fl: 2.1),
        fuelStartLitres: 8.5,
      ),
    );
  });

  group('a day', () {
    double Function(double) lap(double speed, [double from = 0, double to = 0, double slow = 0]) =>
        (d) => d >= from && d <= to ? slow : speed;
    DayRunInput run(String id, TelemetrySession session) => DayRunInput(
      runId: id,
      name: 'Session ${id.substring(id.length - 1)}',
      contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
      session: session,
      laps: deriveSourceLapSession(session),
    );
    final runs = [
      run(
        'run1',
        rectangleSession([
          lap(30, 50, 120, 20),
          lap(31, 300, 400, 25),
          lap(30, 550, 650, 22),
          lap(30.5),
        ], firstTimestampMilliseconds: 1756454409000),
      ),
      run(
        'run2',
        rectangleSession([
          lap(29),
          lap(30.5, 700, 780, 20),
          lap(30, 100, 160, 24),
        ], firstTimestampMilliseconds: 1756444409000),
      ),
    ];
    final analysis = analyzeDay(runs);
    final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
    final infos = [for (final run in runs) ProgressionRunInfo(id: run.runId, name: run.name)];
    final best = dayTheoreticalBest(analysis, outing, random: Random(3));

    test('lists the runs in recording order with their best laps', () {
      final progression = dayProgression(analysis, infos);
      expect(progression.groupId, analysis.chosenGroupId);
      expect([for (final run in progression.runs) run.runId], ['run2', 'run1']);
      expect(progression.runs.every((run) => run.bestLap != null), isTrue);
      expect(dayProgressions(analysis, infos).keys, [analysis.chosenGroupId]);
      expect(dayProgression(analysis, infos, groupId: 'other').runs, isEmpty);
    });

    test('gives the lap consistency of the eligible laps', () {
      final consistency = dayLapConsistency(analysis);
      final eligible = dayEligibleLaps(analysis);
      expect(consistency.day.count, eligible.length);
      expect(consistency.day.available, eligible.length >= 3);
      expect([for (final run in consistency.runs) run.runId], ['run2', 'run1']);
      expect(dayLapConsistencies(analysis).keys, [analysis.chosenGroupId]);
    });

    test('ranks the losses and opens their comparison', () {
      final losses = best.publishedTimeLosses(allLaps: true);
      expect(losses.available, isTrue);
      expect(losses.referenceLap, best.bestLap!.reference);
      expect(losses.losses, isNotEmpty);
      for (var i = 1; i < losses.losses.length; ++i) {
        expect(losses.losses[i].lossSeconds, lessThanOrEqualTo(losses.losses[i - 1].lossSeconds));
      }
      final first = losses.losses.first;
      final comparison = best.compareLoss(first)!;
      expect(comparison.lapReference, first.lapReference);
      expect(comparison.referenceLap, best.bestLap!.reference);
      expect(comparison.differenceSeconds, closeTo(first.lossSeconds, 1e-9));
      // Run bests only: one lap per run at most, the best lap itself never.
      final runBests = best.publishedTimeLosses();
      // The best lap's run compares only the best lap, which is the reference.
      expect(runBests.comparedLapCount, 1);
      expect(runBests.losses.every((loss) => loss.lapReference != best.bestLap!.reference), isTrue);
    });

    test('gives each section per run in the progression\'s order', () {
      final order = [for (final run in dayProgression(analysis, infos).runs) run.run];
      final sections = best.sectionProgression(order);
      expect([for (final session in sections.sessions) session.runId], ['run2', 'run1']);
      expect(sections.segments.length, best.segments.length);
      for (final row in sections.segments) {
        expect(row.cells.length, 2);
        final run1 = row.cells[1];
        expect(run1.laps.length, 4);
        expect(run1.summary.available, isTrue);
        expect(run1.laps.first.seconds, lessThanOrEqualTo(run1.laps.last.seconds));
        expect(row.fastestTypical, isNotNull);
      }
    });

    test('has nothing to show without a result', () {
      final none = DayTheoreticalBest(
        groupId: '',
        state: DayTheoreticalBestState.unavailable,
        message: 'No segments.',
      );
      expect(none.publishedTimeLosses().available, isFalse);
      expect(none.publishedTimeLosses().message, 'No segments.');
      expect(none.sectionProgression(infos).segments, isEmpty);
    });
  });
}
