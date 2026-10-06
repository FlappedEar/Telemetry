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
  /// [coachGoalKinds] name, a name and a range that is not empty (it ends
  /// before it starts when the corner runs across the start line).
  static SessionGoal? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final kind = coachGoalKinds.where((kind) => kind.name == value['kind']).firstOrNull;
    final name = value['segment'];
    final start = value['startProgressMeters'];
    final end = value['endProgressMeters'];
    if (kind == null || name is! String || start is! num || end is! num) return null;
    if (!start.isFinite || !end.isFinite || end == start) return null;
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

/// The keys of a stored goal this app reads; a goal with others is kept as
/// it is ([RunGoals.readOnly]).
const _goalKeys = {'kind', 'segment', 'startProgressMeters', 'endProgressMeters'};

/// The goals set after a session for the session after it.
final class RunGoals {
  RunGoals({
    List<SessionGoal> goals = const [],
    this.groupId = '',
    this.unknownVersion,
    this.unreadable = false,
  }) : goals = List.unmodifiable(goals);

  /// The goals a run stores ([runGoalsKey]). Goals stored under another
  /// version than [runGoalsVersion] are not read. Anything this app would
  /// not write itself (a value that is not an object, goals that are not a
  /// list, a goal it cannot read or with keys it does not know, more than
  /// [maximumRunGoals], a goal there twice or without a corner name) makes
  /// them [readOnly], with the goals it could read, so nothing stored is
  /// lost by an edit.
  factory RunGoals.fromJson(Object? value) {
    if (value == null) return RunGoals();
    if (value is! Map<String, Object?>) return RunGoals(unreadable: true);
    final version = value['version'];
    if (version != null && version != runGoalsVersion) {
      return RunGoals(unknownVersion: '$version');
    }
    var unreadable = false;
    final group = value['groupId'];
    if (group != null && group is! String) unreadable = true;
    final stored = value['goals'];
    if (stored != null && stored is! List) unreadable = true;
    final goals = <SessionGoal>[];
    final seen = <(CoachKind, String)>{};
    for (final item in stored is List ? stored : const <Object?>[]) {
      final goal = SessionGoal.fromJson(item);
      if (goal == null ||
          (item as Map<String, Object?>).keys.any((key) => !_goalKeys.contains(key)) ||
          goal.segmentName.trim().isEmpty ||
          !seen.add((goal.kind, goal.segmentName))) {
        unreadable = true;
      }
      if (goal != null) goals.add(goal);
    }
    if (goals.length > maximumRunGoals) unreadable = true;
    return RunGoals(
      goals: goals.take(maximumRunGoals).toList(),
      groupId: group is String ? group : '',
      unreadable: unreadable,
    );
  }

  final List<SessionGoal> goals;

  /// The compared laps (group) the goals' corners were set on; empty when
  /// not known.
  final String groupId;

  /// The stored version when it is not [runGoalsVersion], or null.
  final String? unknownVersion;

  /// Stored in a form this app would not write itself (see
  /// [RunGoals.fromJson]).
  final bool unreadable;

  /// Stored under another version or in a form this app would not write:
  /// shown as far as it can be read, never rewritten.
  bool get readOnly => unknownVersion != null || unreadable;

  bool get isEmpty => goals.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is RunGoals &&
      other.unknownVersion == unknownVersion &&
      other.unreadable == unreadable &&
      other.groupId == groupId &&
      other.goals.length == goals.length &&
      [for (var i = 0; i < goals.length; ++i) other.goals[i] == goals[i]].every((same) => same);

  @override
  int get hashCode => Object.hash(unknownVersion, unreadable, groupId, Object.hashAll(goals));
}

/// Why [goals] cannot be saved, or null when they can: at most
/// [maximumRunGoals], each a [coachGoalKinds] change at a named corner
/// whose range is not empty, no two the same change at the same corner.
/// Read-only goals are never written, so they have no problem.
String? runGoalsProblem(RunGoals goals) {
  if (goals.readOnly) return null;
  if (goals.goals.length > maximumRunGoals) return 'A session has at most $maximumRunGoals goals.';
  final seen = <(CoachKind, String)>{};
  for (final goal in goals.goals) {
    if (!coachGoalKinds.contains(goal.kind)) return 'A goal is not a change to work on.';
    if (goal.segmentName.trim().isEmpty) return 'A goal needs a corner.';
    if (!goal.startProgressMeters.isFinite ||
        !goal.endProgressMeters.isFinite ||
        goal.endProgressMeters == goal.startProgressMeters) {
      return 'A goal\'s corner is empty.';
    }
    if (!seen.add((goal.kind, goal.segmentName))) return 'A goal is there twice.';
  }
  return null;
}

/// Writes [goals] into [run] (a document run) as its [runGoalsKey]: the
/// goal list and the group are replaced, other keys of the stored object
/// stay; no goals left removes it unless it holds keys this app does not
/// know. Goals equal to the stored ones, or stored ones that are
/// [RunGoals.readOnly], leave [run] as it was. Returns whether [run] changed. [goals] must have no
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
    object.remove('groupId');
  } else {
    object['goals'] = [for (final goal in goals.goals) goal.toJson()];
    if (goals.groupId.isEmpty) {
      object.remove('groupId');
    } else {
      object['groupId'] = goals.groupId;
    }
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
    this.otherGroup = false,
  });

  final SessionGoal goal;

  /// Not measured because the goal was set on other compared laps (another
  /// group) than those shown.
  final bool otherGroup;
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
/// corner overlaps it or either session has too few laps with the measure,
/// and when the goals were set on another group of compared laps than
/// [groupId] (the coach's), whose corners lie elsewhere.
List<SessionGoalCheck> checkSessionGoals(RunGoals goals, DayCoach coach, {String groupId = ''}) {
  if (goals.groupId.isNotEmpty && groupId.isNotEmpty && goals.groupId != groupId) {
    return [
      for (final goal in goals.goals)
        SessionGoalCheck(goal: goal, outcome: CoachGoalOutcome.notMeasured, otherGroup: true),
    ];
  }
  final corners = coach.goalValues;
  final ranges = [
    for (final corner in corners)
      (start: corner.startProgressMeters, end: corner.endProgressMeters),
  ];
  return [
    for (final goal in goals.goals)
      () {
        // The corner as it was drawn, else the one overlapping it most. A
        // corner across the start line (ending before it starts) is found
        // only while it is drawn the same.
        final same = corners.indexWhere(
          (c) =>
              c.startProgressMeters == goal.startProgressMeters &&
              c.endProgressMeters == goal.endProgressMeters,
        );
        final match = same >= 0
            ? same
            : coachMatchingSegment((
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
