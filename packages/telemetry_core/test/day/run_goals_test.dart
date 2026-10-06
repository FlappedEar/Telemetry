import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _coasting = SessionGoal(
  kind: CoachKind.excessiveCoasting,
  segmentName: 'Corner 3',
  startProgressMeters: 800,
  endProgressMeters: 900,
);
const _lift = SessionGoal(
  kind: CoachKind.earlyLift,
  segmentName: 'Corner 3',
  startProgressMeters: 800,
  endProgressMeters: 900,
);

DayCoach _coach(List<CoachCornerGoalValues> values) =>
    DayCoach(runId: 'run2', reason: CoachReason.ready, previousRunId: 'run1', goalValues: values);

void main() {
  group('stored goals', () {
    test('round trip through a run', () {
      final run = <String, Object?>{'id': 'run1'};
      expect(applyRunGoals(run, RunGoals(goals: [_coasting, _lift])), isTrue);
      expect(run[runGoalsKey], {
        'version': runGoalsVersion,
        'goals': [
          {
            'kind': 'excessiveCoasting',
            'segment': 'Corner 3',
            'startProgressMeters': 800.0,
            'endProgressMeters': 900.0,
          },
          {
            'kind': 'earlyLift',
            'segment': 'Corner 3',
            'startProgressMeters': 800.0,
            'endProgressMeters': 900.0,
          },
        ],
      });
      expect(RunGoals.fromJson(run[runGoalsKey]), RunGoals(goals: [_coasting, _lift]));
      expect(RunMetadata.fromRun(run).goals, RunGoals(goals: [_coasting, _lift]));
      // The same goals again change nothing.
      expect(applyRunGoals(run, RunGoals(goals: [_coasting, _lift])), isFalse);
    });

    test('removing every goal removes the key, but keeps unknown keys', () {
      final run = <String, Object?>{'id': 'run1'};
      applyRunGoals(run, RunGoals(goals: [_coasting]));
      expect(applyRunGoals(run, RunGoals()), isTrue);
      expect(run.containsKey(runGoalsKey), isFalse);

      final kept = <String, Object?>{
        runGoalsKey: {
          'version': runGoalsVersion,
          'note': 'from a later app',
          'goals': [_coasting.toJson()],
        },
      };
      expect(applyRunGoals(kept, RunGoals()), isTrue);
      expect(kept[runGoalsKey], {'version': runGoalsVersion, 'note': 'from a later app'});
    });

    test('goals this app would not write are shown and never rewritten', () {
      final cases = <Object?>[
        // Goals it cannot read, kept among those it can.
        {
          'version': runGoalsVersion,
          'goals': [
            _coasting.toJson(),
            {..._lift.toJson(), 'kind': 'improving'},
            {..._lift.toJson(), 'endProgressMeters': 800},
            {..._lift.toJson(), 'segment': 3},
            'Corner 3',
          ],
        },
        // A key of a later app in a goal.
        {
          'version': runGoalsVersion,
          'goals': [
            {..._coasting.toJson(), 'targetMeters': 10},
          ],
        },
        // More than three, a goal twice, one without a corner name.
        {
          'version': runGoalsVersion,
          'goals': [for (var i = 0; i < 4; ++i) _coasting.toJson()],
        },
        {
          'version': runGoalsVersion,
          'goals': [
            {..._coasting.toJson(), 'segment': ' '},
          ],
        },
        // Not an object, goals not a list, a group that is not text.
        'Corner 3',
        {'version': runGoalsVersion, 'goals': 'Corner 3'},
        {
          'version': runGoalsVersion,
          'groupId': 3,
          'goals': [_coasting.toJson()],
        },
      ];
      for (final stored in cases) {
        final goals = RunGoals.fromJson(stored);
        expect(goals.readOnly, isTrue, reason: '$stored');
        expect(runGoalsProblem(goals), isNull);
        final run = <String, Object?>{runGoalsKey: stored};
        expect(applyRunGoals(run, RunGoals(goals: [_lift])), isFalse);
        expect(run[runGoalsKey], same(stored));
      }
      expect(RunGoals.fromJson(cases.first).goals, [_coasting]);
      expect(RunGoals.fromJson(cases[1]).goals, [_coasting]);
      expect(RunGoals.fromJson(cases[2]).goals, hasLength(maximumRunGoals));
      expect(RunGoals.fromJson(null).readOnly, isFalse);
      expect(RunGoals.fromJson(null).isEmpty, isTrue);
    });

    test('the group the goals were set on is stored with them', () {
      final run = <String, Object?>{'id': 'run1'};
      applyRunGoals(run, RunGoals(goals: [_coasting], groupId: 'group-a'));
      expect((run[runGoalsKey]! as Map)['groupId'], 'group-a');
      expect(RunGoals.fromJson(run[runGoalsKey]).groupId, 'group-a');
      expect(applyRunGoals(run, RunGoals()), isTrue);
      expect(run.containsKey(runGoalsKey), isFalse);
    });

    test('goals of another version are not read or rewritten', () {
      final stored = <String, Object?>{'version': 'session-goals-v9', 'goals': <Object?>[]};
      final run = <String, Object?>{runGoalsKey: stored};
      final goals = RunGoals.fromJson(stored);
      expect(goals.readOnly, isTrue);
      expect(goals.isEmpty, isTrue);
      expect(applyRunGoals(run, RunGoals(goals: [_coasting])), isFalse);
      expect(run[runGoalsKey], same(stored));
      expect(runGoalsProblem(goals), isNull);
    });

    test('at most three goals, each once, at a corner with a length', () {
      expect(runGoalsProblem(RunGoals(goals: [_coasting, _lift])), isNull);
      expect(
        runGoalsProblem(
          RunGoals(
            goals: [
              _coasting,
              _lift,
              for (final kind in [CoachKind.lateThrottle, CoachKind.lowMinimumSpeed])
                SessionGoal(
                  kind: kind,
                  segmentName: 'Corner 3',
                  startProgressMeters: 800,
                  endProgressMeters: 900,
                ),
            ],
          ),
        ),
        contains('at most 3'),
      );
      expect(runGoalsProblem(RunGoals(goals: [_coasting, _coasting])), contains('twice'));
      expect(
        runGoalsProblem(
          RunGoals(
            goals: [
              const SessionGoal(
                kind: CoachKind.improving,
                segmentName: 'Corner 3',
                startProgressMeters: 800,
                endProgressMeters: 900,
              ),
            ],
          ),
        ),
        isNotNull,
      );
      expect(
        runGoalsProblem(
          RunGoals(
            goals: [
              const SessionGoal(
                kind: CoachKind.earlyLift,
                segmentName: ' ',
                startProgressMeters: 800,
                endProgressMeters: 900,
              ),
            ],
          ),
        ),
        contains('corner'),
      );
    });

    test('session details keep the goals unless they are passed', () {
      final run = <String, Object?>{
        'id': 'run1',
        'name': 'Session 1',
        runGoalsKey: {
          'version': runGoalsVersion,
          'goals': [_coasting.toJson()],
        },
      };
      // Details edited without goals leave the stored goals alone.
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1', notes: 'Dry')), isTrue);
      expect(RunGoals.fromJson(run[runGoalsKey]).goals, [_coasting]);
      expect(
        applyRunMetadata(run, RunMetadata.fromRun(run).withGoals(RunGoals(goals: [_lift]))),
        isTrue,
      );
      expect(RunGoals.fromJson(run[runGoalsKey]).goals, [_lift]);
      expect(
        runMetadataProblem(RunMetadata.fromRun(run).withGoals(RunGoals(goals: [_lift, _lift]))),
        contains('twice'),
      );
    });
  });

  group('checked on the next session', () {
    CoachCornerGoalValues corner({
      String name = 'Corner 3',
      double start = 805,
      double end = 895,
      Map<CoachKind, CoachGoalValue> before = const {},
      Map<CoachKind, CoachGoalValue> now = const {},
    }) => CoachCornerGoalValues(
      segmentId: name,
      name: name,
      startProgressMeters: start,
      endProgressMeters: end,
      before: before,
      now: now,
    );

    test('better, the same or worse by the main focus\'s steps', () {
      final checks = checkSessionGoals(
        RunGoals(goals: [_coasting, _lift]),
        _coach([
          corner(
            name: 'Corner 2',
            start: 300,
            end: 400,
            before: {CoachKind.excessiveCoasting: (value: 9, laps: 4)},
            now: {CoachKind.excessiveCoasting: (value: 0, laps: 4)},
          ),
          corner(
            before: {
              CoachKind.excessiveCoasting: (value: 1.8, laps: 4),
              CoachKind.earlyLift: (value: 700, laps: 4),
            },
            now: {
              CoachKind.excessiveCoasting: (value: 1.2, laps: 3),
              CoachKind.earlyLift: (value: 695, laps: 3),
            },
          ),
        ]),
      );
      expect(checks[0].outcome, CoachGoalOutcome.better);
      expect(checks[0].measuredName, 'Corner 3');
      expect(checks[0].before, (value: 1.8, laps: 4));
      expect(checks[0].now, (value: 1.2, laps: 3));
      expect(checks[0].metric, CoachMetric.longestCoast);
      // 5 m earlier is within the 8 m step.
      expect(checks[1].outcome, CoachGoalOutcome.unchanged);
    });

    test('goals set on other compared laps are not measured', () {
      final values = [
        corner(
          before: {CoachKind.excessiveCoasting: (value: 1.8, laps: 4)},
          now: {CoachKind.excessiveCoasting: (value: 1.2, laps: 3)},
        ),
      ];
      final goals = RunGoals(goals: [_coasting], groupId: 'group-a');
      final [other] = checkSessionGoals(goals, _coach(values), groupId: 'group-b');
      expect(other.outcome, CoachGoalOutcome.notMeasured);
      expect(other.otherGroup, isTrue);
      final [same] = checkSessionGoals(goals, _coach(values), groupId: 'group-a');
      expect(same.outcome, CoachGoalOutcome.better);
      expect(same.otherGroup, isFalse);
    });

    test('a corner across the start line is found while drawn the same', () {
      const across = SessionGoal(
        kind: CoachKind.excessiveCoasting,
        segmentName: 'Corner 9',
        startProgressMeters: 2900,
        endProgressMeters: 40,
      );
      expect(
        RunGoals.fromJson({
          'goals': [across.toJson()],
        }).goals,
        [across],
      );
      expect(runGoalsProblem(RunGoals(goals: [across])), isNull);
      final values = {CoachKind.excessiveCoasting: (value: 1.8, laps: 3)};
      final now = {CoachKind.excessiveCoasting: (value: 1.2, laps: 3)};
      final [found] = checkSessionGoals(
        RunGoals(goals: [across]),
        _coach([
          corner(start: 300, end: 400, before: values, now: now),
          corner(name: 'Corner 9', start: 2900, end: 40, before: values, now: now),
        ]),
      );
      expect(found.outcome, CoachGoalOutcome.better);
      expect(found.measuredName, 'Corner 9');
      final [moved] = checkSessionGoals(
        RunGoals(goals: [across]),
        _coach([corner(name: 'Corner 9', start: 2890, end: 40, before: values, now: now)]),
      );
      expect(moved.outcome, CoachGoalOutcome.notMeasured);
    });

    test('later throttle is worse', () {
      final throttle = SessionGoal(
        kind: CoachKind.lateThrottle,
        segmentName: 'Corner 3',
        startProgressMeters: 800,
        endProgressMeters: 900,
      );
      final [check] = checkSessionGoals(
        RunGoals(goals: [throttle]),
        _coach([
          corner(
            before: {CoachKind.lateThrottle: (value: 850, laps: 3)},
            now: {CoachKind.lateThrottle: (value: 862, laps: 3)},
          ),
        ]),
      );
      expect(check.outcome, CoachGoalOutcome.worse);
      expect(coachGoalUnit(CoachKind.lateThrottle, 'km/h'), 'm');
      expect(coachGoalUnit(CoachKind.lowMinimumSpeed, 'mph'), 'mph');
    });

    test('not measured: no corner there, or too few laps with the measure', () {
      final checks = checkSessionGoals(
        RunGoals(goals: [_coasting, _lift]),
        _coach([
          corner(
            before: {CoachKind.excessiveCoasting: (value: 1.8, laps: 4)},
            now: {CoachKind.earlyLift: (value: 700, laps: 3)},
          ),
        ]),
      );
      expect(checks.map((c) => c.outcome), everyElement(CoachGoalOutcome.notMeasured));
      expect(checks.map((c) => c.measuredName), everyElement('Corner 3'));
      expect(checks[0].now, isNull);
      expect(checks[1].before, isNull);

      final [elsewhere] = checkSessionGoals(
        RunGoals(goals: [_coasting]),
        _coach([corner(start: 1200, end: 1300)]),
      );
      expect(elsewhere.outcome, CoachGoalOutcome.notMeasured);
      expect(elsewhere.measuredName, isEmpty);
    });
  });
}
