// The driver's own goals for the next session (FET-218, idea 1 of FET-217):
// up to three changes, each at one corner ("Corner 3: reduce coasting"),
// set after a session for the session after it and checked once that
// session is added, as the coach's main focus is checked ([CoachGoalCheck]).
// Telemetry stores them as an open object `nextGoals` on the session they
// were set after (`event.runs[]`), which FlappedEar Overlays keeps as it is
// without showing it.
import 'day_coach.dart';

/// The version of a session's stored goals.
const runGoalsVersion = 'session-goals-v1';

/// The run key the goals for the session after it are stored under.
const runGoalsKey = 'nextGoals';

/// The most goals for one session.
const maximumRunGoals = 3;

/// One goal: a change of [kind] at the corner [segmentName], which lay from
/// [startProgressMeters] to [endProgressMeters] on the lap's shared axis
/// when the goal was set.
final class SessionGoal {
  const SessionGoal({
    required this.kind,
    required this.segmentName,
    required this.startProgressMeters,
    required this.endProgressMeters,
  });

  /// One of [coachGoalKinds].
  final CoachKind kind;
  final String segmentName;
  final double startProgressMeters, endProgressMeters;

  /// The goal stored as [value], or null when it is not one: a known
  /// [coachGoalKinds] name, a name and a range of positive length.
  static SessionGoal? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final kind = coachGoalKinds.where((kind) => kind.name == value['kind']).firstOrNull;
    final name = value['segment'];
    final start = value['startProgressMeters'];
    final end = value['endProgressMeters'];
    if (kind == null || name is! String || start is! num || end is! num) return null;
    if (!start.isFinite || !end.isFinite || end <= start) return null;
    return SessionGoal(
      kind: kind,
      segmentName: name,
      startProgressMeters: start.toDouble(),
      endProgressMeters: end.toDouble(),
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'segment': segmentName,
    'startProgressMeters': startProgressMeters,
    'endProgressMeters': endProgressMeters,
  };

  @override
  bool operator ==(Object other) =>
      other is SessionGoal &&
      other.kind == kind &&
      other.segmentName == segmentName &&
      other.startProgressMeters == startProgressMeters &&
      other.endProgressMeters == endProgressMeters;

  @override
  int get hashCode => Object.hash(kind, segmentName, startProgressMeters, endProgressMeters);
}

/// The goals set after a session for the session after it.
final class RunGoals {
  RunGoals({List<SessionGoal> goals = const [], this.unknownVersion})
    : goals = List.unmodifiable(goals);

  /// The goals a run stores ([runGoalsKey]), read leniently: a goal that
  /// is not one ([SessionGoal.fromJson]) is left out, and at most
  /// [maximumRunGoals] are read. Goals stored under another version than
  /// [runGoalsVersion] are not read and are [readOnly].
  factory RunGoals.fromJson(Object? value) {
    if (value is! Map<String, Object?>) return RunGoals();
    final version = value['version'];
    if (version != null && version != runGoalsVersion) {
      return RunGoals(unknownVersion: '$version');
    }
    final stored = value['goals'];
    return RunGoals(
      goals: [
        if (stored is List)
          for (final item in stored) ?SessionGoal.fromJson(item),
      ].take(maximumRunGoals).toList(),
    );
  }

  final List<SessionGoal> goals;

  /// The stored version when it is not [runGoalsVersion], or null.
  final String? unknownVersion;

  /// Stored under a version this app does not read: never rewritten.
  bool get readOnly => unknownVersion != null;

  bool get isEmpty => goals.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is RunGoals &&
      other.unknownVersion == unknownVersion &&
      other.goals.length == goals.length &&
      [for (var i = 0; i < goals.length; ++i) other.goals[i] == goals[i]].every((same) => same);

  @override
  int get hashCode => Object.hash(unknownVersion, Object.hashAll(goals));
}

/// Why [goals] cannot be saved, or null when they can: at most
/// [maximumRunGoals], each a [coachGoalKinds] change at a named corner of
/// positive length, no two the same change at the same corner. Read-only
/// goals are never written, so they have no problem.
String? runGoalsProblem(RunGoals goals) {
  if (goals.readOnly) return null;
  if (goals.goals.length > maximumRunGoals) return 'A session has at most $maximumRunGoals goals.';
  final seen = <(CoachKind, String)>{};
  for (final goal in goals.goals) {
    if (!coachGoalKinds.contains(goal.kind)) return 'A goal is not a change to work on.';
    if (goal.segmentName.trim().isEmpty) return 'A goal needs a corner.';
    if (!goal.startProgressMeters.isFinite ||
        !goal.endProgressMeters.isFinite ||
        goal.endProgressMeters <= goal.startProgressMeters) {
      return 'A goal\'s corner has no length.';
    }
    if (!seen.add((goal.kind, goal.segmentName))) return 'A goal is there twice.';
  }
  return null;
}

/// Writes [goals] into [run] (a document run) as its [runGoalsKey]: the
/// goal list is replaced, other keys of the stored object stay; no goals
/// left removes it unless it holds keys this app does not know. Goals equal
/// to the stored ones, or stored under another version, leave [run] as it
/// was. Returns whether [run] changed. [goals] must have no
/// [runGoalsProblem].
bool applyRunGoals(Map<String, Object?> run, RunGoals goals) {
  final stored = RunGoals.fromJson(run[runGoalsKey]);
  if (stored.readOnly || goals.readOnly || stored == goals) return false;
  final current = run[runGoalsKey];
  final object = <String, Object?>{
    if (current is Map<String, Object?>) ...current,
    'version': runGoalsVersion,
  };
  if (goals.isEmpty) {
    object.remove('goals');
  } else {
    object['goals'] = [for (final goal in goals.goals) goal.toJson()];
  }
  if (object.keys.every((key) => key == 'version')) {
    run.remove(runGoalsKey);
  } else {
    run[runGoalsKey] = object;
  }
  return true;
}

/// How the session coached did on one of the goals set after the session
/// before it.
final class SessionGoalCheck {
  const SessionGoalCheck({
    required this.goal,
    required this.outcome,
    this.measuredName = '',
    this.before,
    this.now,
  });

  final SessionGoal goal;
  final CoachGoalOutcome outcome;

  /// Today's corner the goal was measured at: the one overlapping it most
  /// ([coachMatchingSegment]); empty when none does.
  final String measuredName;

  /// The measure in the session before and in the session coached; null
  /// when not measured.
  final CoachGoalValue? before, now;

  /// The measure, as the main focus's check names it.
  CoachMetric get metric => coachGoalMetric(goal.kind);
}

/// What a goal of [kind] is measured by: the lift point, the longest coast,
/// the minimum speed, the throttle return, the share of laps picking up the
/// throttle early, or the braking point range.
CoachMetric coachGoalMetric(CoachKind kind) => switch (kind) {
  CoachKind.earlyLift => CoachMetric.liftPoint,
  CoachKind.excessiveCoasting => CoachMetric.longestCoast,
  CoachKind.lowMinimumSpeed => CoachMetric.minimumSpeed,
  CoachKind.lateThrottle => CoachMetric.throttleReturn,
  CoachKind.earlyThrottle => CoachMetric.earlyThrottleShare,
  CoachKind.inconsistentBraking || CoachKind.improving => CoachMetric.brakingSpread,
};

/// The unit of a goal of [kind]'s measure; minimum speeds are in
/// [speedUnit].
String coachGoalUnit(CoachKind kind, String speedUnit) => switch (kind) {
  CoachKind.excessiveCoasting => 's',
  CoachKind.lowMinimumSpeed => speedUnit,
  CoachKind.earlyThrottle => '%',
  _ => 'm',
};

/// [goals] (set after [DayCoach.previousRunId]) checked on the session
/// [coach] coached: each goal's measure at the corner of today's that
/// overlaps it most, in both sessions, judged by the same clear step as
/// the main focus ([coachGoalOutcome]). A goal is not measured when no
/// corner overlaps it or either session has too few laps with the measure.
List<SessionGoalCheck> checkSessionGoals(RunGoals goals, DayCoach coach) {
  final corners = coach.goalValues;
  final ranges = [
    for (final corner in corners)
      (start: corner.startProgressMeters, end: corner.endProgressMeters),
  ];
  return [
    for (final goal in goals.goals)
      () {
        final match = coachMatchingSegment((
          start: goal.startProgressMeters,
          end: goal.endProgressMeters,
        ), ranges);
        if (match == null) {
          return SessionGoalCheck(goal: goal, outcome: CoachGoalOutcome.notMeasured);
        }
        final corner = corners[match];
        final before = corner.before[goal.kind], now = corner.now[goal.kind];
        if (before == null || now == null) {
          return SessionGoalCheck(
            goal: goal,
            outcome: CoachGoalOutcome.notMeasured,
            measuredName: corner.name,
            before: before,
            now: now,
          );
        }
        return SessionGoalCheck(
          goal: goal,
          outcome: coachGoalOutcome(
            goal.kind,
            before.value,
            now.value,
            perMetrePerSecond: coach.perMetrePerSecond,
          ),
          measuredName: corner.name,
          before: before,
          now: now,
        );
      }(),
  ];
}
