import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import '../units.dart';
import 'day_context.dart';
import 'theoretical_best_card.dart'
    show CalculateAgainButton, TheoreticalBestText;
import 'time_losses_card.dart' show TimeLossText;
import 'corner_details.dart' show lapAColor, lapBColor;
import 'track_map.dart';
import '../ui/readable_list.dart';

extension CoachText on AppLocalizations {
  /// What a coach item asks, as its heading.
  String coachKind(CoachKind kind) => switch (kind) {
    CoachKind.earlyLift => coachKindEarlyLift,
    CoachKind.excessiveCoasting => coachKindExcessiveCoasting,
    CoachKind.lowMinimumSpeed => coachKindLowMinimumSpeed,
    CoachKind.lateThrottle => coachKindLateThrottle,
    CoachKind.earlyThrottle => coachKindEarlyThrottle,
    CoachKind.inconsistentBraking => coachKindInconsistentBraking,
    CoachKind.improving => coachKindImproving,
  };

  /// What to try, or to keep.
  String coachAction(CoachKind kind) => switch (kind) {
    CoachKind.earlyLift => coachActionEarlyLift,
    CoachKind.excessiveCoasting => coachActionExcessiveCoasting,
    CoachKind.lowMinimumSpeed => coachActionLowMinimumSpeed,
    CoachKind.lateThrottle => coachActionLateThrottle,
    CoachKind.earlyThrottle => coachActionEarlyThrottle,
    CoachKind.inconsistentBraking => coachActionInconsistentBraking,
    CoachKind.improving => coachActionImproving,
  };

  String coachMetric(CoachMetric metric) => switch (metric) {
    CoachMetric.liftPoint => coachMetricLiftPoint,
    CoachMetric.longestCoast => coachMetricLongestCoast,
    CoachMetric.minimumSpeed => coachMetricMinimumSpeed,
    CoachMetric.throttleReturn => coachMetricThrottleReturn,
    CoachMetric.segmentTime => coachMetricSegmentTime,
    CoachMetric.exitSpeed => coachMetricExitSpeed,
    CoachMetric.brakingStart => coachMetricBrakingStart,
    CoachMetric.coastDistance => coachMetricCoastDistance,
    CoachMetric.brakingSpread => coachMetricBrakingSpread,
    CoachMetric.nextStraightTime => coachMetricNextStraightTime,
    CoachMetric.firstThrottle => coachMetricFirstThrottle,
    CoachMetric.earlyThrottleShare => coachMetricEarlyThrottleShare,
    CoachMetric.combinedG => coachMetricCombinedG,
    CoachMetric.highestCombinedG => coachMetricHighestCombinedG,
  };

  /// Why the plan is what it is; [session] names the session coached.
  String coachReason(CoachReason reason, String session) => switch (reason) {
    CoachReason.ready => coachReasonReady,
    CoachReason.noSegments => coachReasonNoSegments,
    CoachReason.noLapInGroup => coachReasonNoLapInGroup(session),
    CoachReason.noCorners => coachReasonNoCorners,
    CoachReason.noRecording => coachReasonNoRecording(session),
    CoachReason.noCornerMeasurements => coachReasonNoCornerMeasurements(
      session,
    ),
    CoachReason.noFasterLap => coachReasonNoFasterLap(session),
    CoachReason.noPedals => coachReasonNoPedals,
    CoachReason.noPattern => coachReasonNoPattern,
    CoachReason.tooFewLaps => coachReasonTooFewLaps,
    CoachReason.belowThreshold => coachReasonBelowThreshold,
    CoachReason.notInSession => coachReasonNotInSession,
  };

  /// What was measured for [finding], in one sentence; speeds labelled
  /// [speedUnit] (see [coachValue]).
  String coachMeasured(CoachFinding finding, String? speedUnit) {
    final evidence = finding.evidence.first;
    final metric = coachMetric(evidence.key);
    if (finding.kind == CoachKind.improving) {
      return coachMeasuredImproving(
        metric,
        coachValue(evidence.reference, evidence.unit, speedUnit),
        coachValue(evidence.observed, evidence.unit, speedUnit),
      );
    }
    final observed = coachValue(evidence.observed, evidence.unit, speedUnit);
    final reference = coachValue(evidence.reference, evidence.unit, speedUnit);
    // Braking consistency compares with the day's three fastest laps,
    // which can be this session's.
    if (finding.kind == CoachKind.inconsistentBraking) {
      return coachMeasuredFastest(metric, observed, reference);
    }
    return evidence.referenceLaps.length == 1
        ? coachMeasuredOne(metric, observed, reference)
        : coachMeasuredMany(metric, observed, reference);
  }
}

/// The label for the coach's speeds in [context], following the unit
/// setting: the day's speed unit, empty when nothing says. The coach reports
/// speeds in the unit every recording's speeds are in (unlabelled read as
/// km/h), so they are the recorded numbers. Null, so speeds are not shown,
/// when the recordings' units disagree: the coach then reports converted
/// km/h ([converted]).
String? coachSpeedLabel(BuildContext context, {required bool converted}) {
  final label = speedUnitOf(context);
  if (converted) return null;
  if (label.isEmpty &&
      openDayContext.speedUnits.any((unit) => unit.isNotEmpty)) {
    return null;
  }
  return label;
}

/// A coach value with its unit: positions in whole metres, shares of laps in
/// whole percent, G with two decimals, the rest with one decimal ("46.9 km/h",
/// "3.3 s", "412 m", "67%", "0.72 g"). Speeds are labelled
/// [speedUnit] (unlabelled when it is empty) and not shown when it is null
/// (see [coachSpeedLabel]).
String coachValue(double value, String unit, String? speedUnit) {
  if (!value.isFinite) return '—';
  if (unit == 'm') return '${value.round()}\u00a0m';
  if (unit == '%') return '${value.round()}%';
  if (unit == 'g') return '${fixed(value, 2)}\u00a0g';
  if (unit == 'km/h' || unit == 'mph') {
    if (speedUnit == null) return '—';
    return speedUnit.isEmpty
        ? fixed(value, 1)
        : '${fixed(value, 1)}\u00a0$speedUnit';
  }
  return '${fixed(value, 1)}\u00a0$unit';
}

/// Whether [finding] reports a speed (in km/h or mph, see [coachSpeedLabel]).
bool _hasSpeed(CoachFinding finding) => finding.evidence.any(
  (evidence) => evidence.unit == 'km/h' || evidence.unit == 'mph',
);

/// The coach between sessions: at most three items for the next run, each
/// a labelled suggestion with what was measured apart from what to try.
/// An empty plan says why. "Why?" opens an item's measured values and its
/// corner on the map.
class NextSessionCard extends StatelessWidget {
  const NextSessionCard({
    super.key,
    required this.coach,
    required this.result,
    required this.session,
    required this.lapLabel,
    this.loading = false,
    this.error = '',
    this.path,
    this.gate,
    this.wide = false,
    this.speedsConverted = false,
    this.withoutTheoreticalBest = false,
    this.onRetry,
    this.printable = false,
    this.goals,
    this.goalsOtherGroup = false,
    this.onGoalsChanged,
  });

  /// [goals] were set on other compared laps than those shown: none is
  /// added to them.
  final bool goalsOtherGroup;

  /// The driver's own goals for the session after [session] (FET-218);
  /// null hides them.
  final RunGoals? goals;

  /// Saves changed [goals]; null shows them without buttons.
  final ValueChanged<RunGoals>? onGoalsChanged;

  /// Drawn into the shared report image: no buttons.
  final bool printable;

  /// Null while it is prepared.
  final DayCoach? coach;
  final DayTheoreticalBest? result;

  /// The name of the session coached: "Session 4".
  final String session;
  final String Function(Object? reference) lapLabel;
  final bool loading;
  final String error;

  /// The best lap's trace, for the item's map.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;

  /// Whether the coach's speeds are converted (see [coachSpeedLabel]).
  final bool speedsConverted;

  /// The theoretical best failed, so the coach cannot run.
  final bool withoutTheoreticalBest;

  /// Prepares the plan again after [error].
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final coach = this.coach;
    final speedUnit = coachSpeedLabel(context, converted: speedsConverted);
    return Card(
      key: const ValueKey('nextSessionCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coachTitle, style: theme.textTheme.titleMedium),
            if (session.isNotEmpty)
              Text(
                l10n.coachSubtitle(l10n.session(session)),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            if (withoutTheoreticalBest)
              Text(
                l10n.coachNoTheoreticalBest,
                key: const ValueKey('coachReason'),
              )
            else if (error.isNotEmpty) ...[
              Text(
                l10n.coachFailed(l10n.taskFailure(error)),
                key: const ValueKey('coachReason'),
              ),
              if (onRetry case final retry? when !printable)
                CalculateAgainButton(retry),
            ] else if (loading || coach == null)
              Text(l10n.coachLoading)
            else ...[
              Text(
                l10n.coachReason(coach.reason, session),
                key: const ValueKey('coachReason'),
              ),
              if (coach.goal case final goal?) _goal(context, goal, speedUnit),
              _CoachPlan(
                plan: [for (final item in coach.plan) item.finding],
                result: printable ? null : result,
                path: path,
                gate: gate,
                wide: wide,
                item: (context, finding, index, selected) =>
                    _item(context, finding, index, speedUnit, selected),
              ),
              if (speedUnit == null &&
                  [
                    ...coach.plan.map((item) => item.finding),
                    ?coach.goal?.finding,
                  ].any(_hasSpeed)) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.coachSpeedHidden,
                  key: const ValueKey('coachSpeedHidden'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (coach.slowLaps.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.coachSlowLaps(
                    [
                      for (final lap in coach.slowLaps)
                        lapLabel(lap.reference).isEmpty
                            ? l10n.lap(lap)
                            : l10n.timeLossLapLabel(lapLabel(lap.reference)),
                    ].join(', '),
                  ),
                  key: const ValueKey('coachSlowLaps'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (coach.plan.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(l10n.coachFooter, style: theme.textTheme.bodySmall),
              ],
              // The shared report shows goals only once some are set.
              if (goals case final goals? when !printable || !goals.isEmpty)
                _ownGoals(context, coach, goals),
            ],
          ],
        ),
      ),
    );
  }

  /// The driver's own goals for the next session: each a change at a
  /// corner of today's, at most [maximumRunGoals], checked once the next
  /// session is added.
  Widget _ownGoals(BuildContext context, DayCoach coach, RunGoals goals) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final corners = result?.corners ?? const <DayCorner>[];
    final change = printable || goals.readOnly ? null : onGoalsChanged;
    return Padding(
      key: const ValueKey('ownGoals'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.ownGoalsTitle, style: theme.textTheme.titleSmall),
          Text(
            goals.readOnly
                ? l10n.ownGoalsReadOnly
                : goals.isEmpty
                ? l10n.ownGoalsNone(maximumRunGoals)
                : l10n.ownGoalsIntro,
            key: const ValueKey('ownGoalsIntro'),
            style: theme.textTheme.bodySmall,
          ),
          for (var i = 0; i < goals.goals.length; ++i)
            Row(
              key: ValueKey('ownGoal$i'),
              children: [
                Expanded(
                  child: Text(
                    l10n.coachItemTitle(
                      l10n.tbSegmentName(goals.goals[i].segmentName),
                      l10n.coachKind(goals.goals[i].kind),
                    ),
                  ),
                ),
                if (change != null)
                  IconButton(
                    key: ValueKey('ownGoalRemove$i'),
                    tooltip: l10n.ownGoalsRemove,
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        change(RunGoals(goals: [...goals.goals]..removeAt(i))),
                  ),
              ],
            ),
          if (change != null && goals.goals.length < maximumRunGoals)
            if (goalsOtherGroup)
              Text(
                l10n.ownGoalsOtherGroup,
                key: const ValueKey('ownGoalsOtherGroup'),
                style: theme.textTheme.bodySmall,
              )
            else if (coach.reason == CoachReason.noLapInGroup)
              Text(
                l10n.ownGoalsNeedLaps(l10n.session(session)),
                key: const ValueKey('ownGoalsNeedLaps'),
                style: theme.textTheme.bodySmall,
              )
            else if (corners.isEmpty)
              Text(
                l10n.ownGoalsNeedCorners,
                key: const ValueKey('ownGoalsNeedCorners'),
                style: theme.textTheme.bodySmall,
              )
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('ownGoalsAdd'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.ownGoalsAdd),
                  onPressed: () async {
                    final focus = coach.focus?.finding;
                    final goal = await showDialog<SessionGoal>(
                      context: context,
                      builder: (context) => _GoalDialog(
                        corners: corners,
                        taken: goals.goals,
                        segmentId: focus?.kind.corrective == true
                            ? focus!.segmentId
                            : null,
                        kind: focus?.kind.corrective == true
                            ? focus!.kind
                            : null,
                      ),
                    );
                    if (goal != null) {
                      change(RunGoals(goals: [...goals.goals, goal]));
                    }
                  },
                ),
              ),
        ],
      ),
    );
  }

  /// How this session did on the main focus of the session before.
  Widget _goal(BuildContext context, CoachGoalCheck goal, String? speedUnit) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final finding = goal.finding;
    final outcome = switch (goal.outcome) {
      CoachGoalOutcome.better => l10n.coachGoalBetter,
      CoachGoalOutcome.unchanged => l10n.coachGoalUnchanged,
      CoachGoalOutcome.worse => l10n.coachGoalWorse,
      // No corner of today's overlaps the focus's.
      CoachGoalOutcome.notMeasured when goal.measuredName.isEmpty =>
        l10n.coachGoalNoCorner,
      CoachGoalOutcome.notMeasured => l10n.coachGoalNotMeasured,
    };
    return Padding(
      key: const ValueKey('coachGoal'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.coachGoalLabel(l10n.session(goal.runName)),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.coachItemTitle(
              l10n.tbSegmentName(finding.segmentName),
              l10n.coachKind(finding.kind),
            ),
            style: theme.textTheme.titleSmall,
          ),
          Text(switch ((goal.before, goal.now)) {
            (final before?, final now?) =>
              '${l10n.coachGoalMeasured(l10n.coachMetric(goal.metric), coachValue(before, goal.unit, speedUnit), coachValue(now, goal.unit, speedUnit))} $outcome',
            _ => outcome,
          }, key: const ValueKey('coachGoalResult')),
          // Today's corners can differ from those of the focus.
          if (goal.measuredName.isNotEmpty &&
              goal.measuredName != finding.segmentName)
            Text(
              l10n.coachGoalMeasuredAt(goal.measuredName),
              key: const ValueKey('coachGoalMeasuredAt'),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    CoachFinding finding,
    int index,
    String? speedUnit,
    // Tapped to show the item's corner on the map; null without one.
    _Selection? selection,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final keep = !finding.kind.corrective;
    Widget labelled(String label, String text, Key key) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: text),
          ],
        ),
        key: key,
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  // The first item is the main focus (see DayCoach.focus).
                  index == 0 ? l10n.coachFocusLabel : l10n.coachLaterLabel,
                  key: ValueKey('coachLabel $index'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.coachItemTitle(
            l10n.tbSegmentName(finding.segmentName),
            l10n.coachKind(finding.kind),
          ),
          style: index == 0
              ? theme.textTheme.titleMedium
              : theme.textTheme.titleSmall,
        ),
        labelled(
          l10n.coachMeasuredLabel,
          l10n.coachMeasured(finding, speedUnit),
          ValueKey('coachMeasured $index'),
        ),
        labelled(
          keep ? l10n.coachKeepLabel : l10n.coachTryLabel,
          l10n.coachAction(finding.kind),
          ValueKey('coachAction $index'),
        ),
        if (result != null && !printable)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey('coachWhy $index'),
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CoachItemPage(
                    finding: finding,
                    result: result!,
                    lapLabel: lapLabel,
                    path: path,
                    gate: gate,
                    wide: wide,
                    speedsConverted: speedsConverted,
                  ),
                ),
              ),
              child: Text(l10n.coachWhy),
            ),
          ),
      ],
    );
    if (selection == null) {
      return Padding(
        key: ValueKey('coachItem $index'),
        padding: const EdgeInsets.only(top: 12),
        child: content,
      );
    }
    // The item whose corner the map shows is marked in the map's colour.
    return Padding(
      key: ValueKey('coachItem $index'),
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        button: true,
        selected: selection.selected,
        onTapHint: l10n.coachShowOnMap,
        child: InkWell(
          key: ValueKey('coachItemSelect $index'),
          onTap: selection.select,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsetsDirectional.only(start: 10),
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(
                  color: selection.selected
                      ? FetColors.of(context).dayBest
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Whether an item's corner is the one the map shows, and how to show it.
typedef _Selection = ({bool selected, VoidCallback select});

/// A corner's number as the coach names it, for the map: "10" for
/// "Corner 10", "3–4" for "Corners 3–4", "3 (2)" for a split "Corner 3 (2)";
/// any other name as the app shows it.
String coachCornerNumber(AppLocalizations l10n, String name) {
  final match = _cornerNumber.firstMatch(name);
  return match == null
      ? l10n.tbSegmentName(name)
      : '${match.group(1)}${match.group(2) ?? ''}';
}

final _cornerNumber = RegExp(r'^Corners? (\d+(?:–\d+)?)( \(\d+\))?$');

/// Where each corner of [result] lies on [path], the best lap's trace: the
/// segment of each fix, and each corner's middle fix, for its number.
final class CoachCornerPlaces {
  CoachCornerPlaces(DayTheoreticalBest result, LapPath path) {
    final best = result.bestLap;
    if (best == null) return;
    final fixes = <int, List<PathPoint>>{};
    for (final segment in path.segments) {
      for (final point in segment) {
        final index = result.segmentAtTime(best, point.telemetryTime);
        segmentOf[point.telemetryTime] = index;
        if (index != null) (fixes[index] ??= []).add(point);
      }
    }
    for (final corner in result.corners) {
      final points = fixes[corner.segmentIndex];
      if (points == null || points.isEmpty) continue;
      final middle = points[points.length ~/ 2];
      corners.add((corner, middle.eastMeters, middle.northMeters));
    }
  }

  /// No corners: without a trace.
  CoachCornerPlaces.none();

  /// The segment index of each fix of the path, by its telemetry time.
  final Map<double, int?> segmentOf = {};

  /// Each corner found on the path, with the place of its number.
  final List<(DayCorner, double east, double north)> corners = [];
}

/// The coach's items, under the best lap's map with the day's corners
/// numbered as the coach names them (FET-260). The corner of the item
/// selected (the main focus to start with) is highlighted; tapping an item
/// selects it. Without a map, only the items.
class _CoachPlan extends StatefulWidget {
  const _CoachPlan({
    required this.plan,
    required this.result,
    required this.path,
    required this.gate,
    required this.wide,
    required this.item,
  });

  final List<CoachFinding> plan;

  /// Null leaves the map out (the shared report has none).
  final DayTheoreticalBest? result;
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;
  final Widget Function(
    BuildContext context,
    CoachFinding finding,
    int index,
    _Selection? selection,
  )
  item;

  @override
  State<_CoachPlan> createState() => _CoachPlanState();
}

class _CoachPlanState extends State<_CoachPlan> {
  // The segment of the item selected; the first item's while it is not in
  // the plan.
  String? _selected;

  final _map = GlobalKey();

  @override
  void didUpdateWidget(_CoachPlan old) {
    super.didUpdateWidget(old);
    // A new plan starts on its main focus again.
    final ids = [for (final finding in widget.plan) finding.segmentId];
    final before = [for (final finding in old.plan) finding.segmentId];
    if (!listEquals(ids, before)) _selected = null;
  }

  void _select(String segmentId) {
    setState(() => _selected = segmentId);
    // The map may be scrolled away above the items.
    if (_map.currentContext case final map?) {
      Scrollable.ensureVisible(
        map,
        duration: const Duration(milliseconds: 200),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  // Worked out again only for another result or trace.
  CoachCornerPlaces? _places;
  (DayTheoreticalBest, LapPath)? _placesOf;

  CoachCornerPlaces? _cornerPlaces() {
    final result = widget.result, path = widget.path;
    if (result == null || path == null || path.isEmpty) return null;
    final (r, p) = _placesOf ?? (null, null);
    if (!identical(r, result) || !identical(p, path)) {
      _placesOf = (result, path);
      _places = CoachCornerPlaces(result, path);
    }
    return _places;
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final places = _cornerPlaces();
    if (places == null || places.corners.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < plan.length; ++i)
            widget.item(context, plan[i], i, null),
        ],
      );
    }
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final highlight = FetColors.of(context).dayBest;
    // Only an item whose corner is on the map can be selected.
    final placed = {
      for (final (corner, _, _) in places.corners) corner.segmentId,
    };
    final selectable = [
      for (final finding in plan)
        if (placed.contains(finding.segmentId)) finding.segmentId,
    ];
    final selected = selectable.contains(_selected)
        ? _selected
        : selectable.firstOrNull;
    final named = {for (final finding in plan) finding.segmentId};
    final segments = widget.result!.segments;
    int? indexOf(String? id) {
      final index = segments.indexWhere((s) => s.segmentId == id);
      return index < 0 ? null : index;
    }

    final selectedIndex = indexOf(selected);
    final namedIndices = {for (final id in named) ?indexOf(id)};
    final selectedName = plan
        .where((f) => f.segmentId == selected)
        .firstOrNull
        ?.segmentName;
    final labels = [
      // The corners the coach names on top of the others, the selected
      // one last.
      for (final pass in [0, 1, 2])
        for (final (corner, east, north) in places.corners)
          if (switch (pass) {
            0 => !named.contains(corner.segmentId),
            1 =>
              named.contains(corner.segmentId) && corner.segmentId != selected,
            _ => corner.segmentId == selected,
          })
            MapLabel(
              east,
              north,
              coachCornerNumber(l10n, corner.name),
              switch (pass) {
                0 => const Color(0xcc202020),
                1 => Colors.white,
                _ => highlight,
              },
              emphasized: pass == 2,
            ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          key: _map,
          height: widget.wide ? 360 : 260,
          child: IgnorePointer(
            child: TrackMap(
              key: const ValueKey('coachCornerMap'),
              interactive: false,
              path: widget.path!,
              gate: widget.gate,
              pointColor: (point) {
                final index = places.segmentOf[point.telemetryTime];
                if (index == null) return theme.colorScheme.outlineVariant;
                if (index == selectedIndex) return highlight;
                if (namedIndices.contains(index)) {
                  return theme.colorScheme.onSurface;
                }
                return theme.colorScheme.outlineVariant;
              },
              labels: labels,
              semanticLabel: selectedName == null
                  ? l10n.coachCornerMap
                  : l10n.coachCornerMapSelected(
                      l10n.tbSegmentName(selectedName),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          plan.isEmpty
              ? l10n.coachCornerMapNote
              : l10n.coachCornerMapNoteSelect,
          key: const ValueKey('coachCornerMapNote'),
          style: theme.textTheme.bodySmall,
        ),
        for (var i = 0; i < plan.length; ++i)
          widget.item(
            context,
            plan[i],
            i,
            selectable.contains(plan[i].segmentId)
                ? (
                    selected: plan[i].segmentId == selected,
                    select: () => _select(plan[i].segmentId),
                  )
                : null,
          ),
      ],
    );
  }
}

/// The laps of earlier sessions showing [finding]'s pattern too: never the
/// session coached's own (a braking item reads all of them, but lists only
/// those off the usual point as the session's).
List<DayLapRow> coachEarlierLaps(CoachFinding finding) {
  final coached = {for (final lap in finding.sessionLaps) lap.runId};
  return [
    for (final lap in finding.affectedLaps)
      if (!coached.contains(lap.runId)) lap,
  ];
}

/// One coach item opened: its measured values, the laps behind them and
/// its corner on the best lap's trace.
class CoachItemPage extends StatefulWidget {
  const CoachItemPage({
    super.key,
    required this.finding,
    required this.result,
    required this.lapLabel,
    this.path,
    this.gate,
    this.wide = false,
    this.speedsConverted = false,
  });

  final CoachFinding finding;
  final DayTheoreticalBest result;
  final String Function(Object? reference) lapLabel;
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;

  /// Whether the coach's speeds are converted (see [coachSpeedLabel]).
  final bool speedsConverted;

  @override
  State<CoachItemPage> createState() => _CoachItemPageState();
}

class _CoachItemPageState extends State<CoachItemPage> {
  late final int _segment = widget.result.segments.indexWhere(
    (segment) => segment.segmentId == widget.finding.segmentId,
  );

  // Whether each fix of the best lap's trace is in the item's segment.
  late final Map<double, bool> _inSegment = _segmentFixes();

  Map<double, bool> _segmentFixes() {
    final result = widget.result, path = widget.path, best = result.bestLap;
    if (path == null || best == null || _segment < 0) return const {};
    return {
      for (final segment in path.segments)
        for (final point in segment)
          point.telemetryTime:
              result.segmentAtTime(best, point.telemetryTime) == _segment,
    };
  }

  // Where each corner's number goes.
  late final CoachCornerPlaces _places = widget.path == null
      ? CoachCornerPlaces.none()
      : CoachCornerPlaces(widget.result, widget.path!);

  List<DayLapRow> _earlier(CoachFinding finding) => coachEarlierLaps(finding);

  // The item's points along the lap (a lift, a braking start or a throttle
  // return): this session's and the faster laps', on the best lap's path.
  // A change only: an improvement compares the latest lap with an earlier
  // one, not with faster laps.
  late final CoachEvidence? _points = widget.finding.kind.corrective
      ? widget.finding.evidence
            .where((e) => e.unit == 'm' && _pointMetrics.contains(e.key))
            .firstOrNull
      : null;
  late final MapMark? _thisMark = _markAt(_points?.observed, lapAColor);
  late final MapMark? _fasterMark = _markAt(_points?.reference, lapBColor);

  static const _pointMetrics = {
    CoachMetric.liftPoint,
    CoachMetric.brakingStart,
    CoachMetric.throttleReturn,
    CoachMetric.firstThrottle,
  };

  MapMark? _markAt(double? progress, Color color) {
    final result = widget.result, path = widget.path, best = result.bestLap;
    if (progress == null || path == null || best == null) return null;
    final time = result.timeAt(best, progress);
    if (time == null) return null;
    final at = lapPathPointAt(path, time);
    return at == null ? null : MapMark(at.east, at.north, color, radius: 7);
  }

  Widget _legend(Color color, String text, Key key) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, key: key)),
      ],
    ),
  );

  String _laps(AppLocalizations l10n, List<DayLapRow> laps) => [
    for (final lap in laps)
      widget.lapLabel(lap.reference).isEmpty
          ? l10n.lap(lap)
          : l10n.timeLossLapLabel(widget.lapLabel(lap.reference)),
  ].join(', ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final finding = widget.finding;
    final path = widget.path;
    final keep = !finding.kind.corrective;
    final speedUnit = coachSpeedLabel(
      context,
      converted: widget.speedsConverted,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tbSegmentName(finding.segmentName))),
      body: ReadableListView(
        children: [
          Text(
            '${l10n.coachLabel} · ${l10n.coachKind(finding.kind)}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.coachMeasured(finding, speedUnit),
            style: theme.textTheme.titleMedium,
            key: const ValueKey('coachWhyMeasured'),
          ),
          const SizedBox(height: 12),
          for (final evidence in finding.evidence)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.coachMetric(evidence.key)),
              subtitle: Text(
                l10n.coachWhyValues(
                  coachValue(evidence.observed, evidence.unit, speedUnit),
                  coachValue(evidence.reference, evidence.unit, speedUnit),
                ),
              ),
            ),
          if (speedUnit == null && _hasSpeed(finding))
            Text(l10n.coachSpeedHidden, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(l10n.coachWhyAffected, style: theme.textTheme.labelLarge),
          Text(_laps(l10n, finding.sessionLaps)),
          if (_earlier(finding).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l10n.coachWhyEarlier, style: theme.textTheme.labelLarge),
            Text(_laps(l10n, _earlier(finding))),
          ],
          const SizedBox(height: 8),
          Text(
            keep
                ? l10n.coachWhyBefore
                : finding.kind == CoachKind.inconsistentBraking
                ? l10n.coachWhyFastest
                : l10n.coachWhyFaster,
            style: theme.textTheme.labelLarge,
          ),
          Text(_laps(l10n, finding.evidence.first.referenceLaps)),
          if (path != null && !path.isEmpty && _segment >= 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: widget.wide ? 420 : 300,
              child: IgnorePointer(
                child: TrackMap(
                  key: const ValueKey('coachMap'),
                  interactive: false,
                  path: path,
                  gate: widget.gate,
                  pointColor: (point) =>
                      _inSegment[point.telemetryTime] ?? false
                      // The best lap's trace, in the day best's purple.
                      ? FetColors.of(context).dayBest
                      : theme.colorScheme.outlineVariant,
                  semanticLabel: l10n.coachWhyMap(
                    l10n.tbSegmentName(finding.segmentName),
                  ),
                  marks: [?_fasterMark, ?_thisMark],
                  // Every corner's number; this item's on top, highlighted.
                  labels: [
                    for (final pass in [false, true])
                      for (final (corner, east, north) in _places.corners)
                        if ((corner.segmentId == finding.segmentId) == pass)
                          MapLabel(
                            east,
                            north,
                            coachCornerNumber(l10n, corner.name),
                            pass
                                ? FetColors.of(context).dayBest
                                : const Color(0xcc202020),
                            emphasized: pass,
                          ),
                  ],
                ),
              ),
            ),
            if (_points case final points?) ...[
              if (_thisMark != null)
                _legend(
                  lapAColor,
                  l10n.coachMapThis(l10n.coachMetric(points.key)),
                  const ValueKey('coachMapThis'),
                ),
              if (_fasterMark != null)
                _legend(
                  lapBColor,
                  finding.kind == CoachKind.inconsistentBraking
                      ? l10n.coachMapFastest(l10n.coachMetric(points.key))
                      : l10n.coachMapFaster(l10n.coachMetric(points.key)),
                  const ValueKey('coachMapFaster'),
                ),
            ],
          ],
          const SizedBox(height: 12),
          Text(
            '${keep ? l10n.coachKeepLabel : l10n.coachTryLabel}: '
            '${l10n.coachAction(finding.kind)}',
          ),
          const SizedBox(height: 12),
          Text(
            l10n.coachWhySupport(fixed(finding.confidence, 2)),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Picks a corner of today's and a change to work on there; the coach's
/// main focus is picked to start with.
class _GoalDialog extends StatefulWidget {
  const _GoalDialog({
    required this.corners,
    required this.taken,
    this.segmentId,
    this.kind,
  });

  final List<DayCorner> corners;

  /// The goals already set: the same change at the same corner is not
  /// offered again.
  final List<SessionGoal> taken;
  final String? segmentId;
  final CoachKind? kind;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late int _corner = math.max(
    0,
    widget.corners.indexWhere((c) => c.segmentId == widget.segmentId),
  );
  late CoachKind _kind = widget.kind ?? coachGoalKinds.first;

  bool get _taken => widget.taken.any(
    (goal) =>
        goal.kind == _kind && goal.segmentName == widget.corners[_corner].name,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.ownGoalsAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            key: const ValueKey('ownGoalCorner'),
            initialValue: _corner,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.ownGoalsCorner),
            items: [
              for (var i = 0; i < widget.corners.length; ++i)
                DropdownMenuItem(
                  value: i,
                  child: Text(l10n.tbSegmentName(widget.corners[i].name)),
                ),
            ],
            onChanged: (value) => setState(() => _corner = value ?? _corner),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CoachKind>(
            key: const ValueKey('ownGoalKind'),
            initialValue: _kind,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.ownGoalsChange),
            items: [
              for (final kind in coachGoalKinds)
                DropdownMenuItem(
                  value: kind,
                  child: Text(l10n.coachKind(kind)),
                ),
            ],
            onChanged: (value) => setState(() => _kind = value ?? _kind),
          ),
          if (_taken)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.ownGoalsTaken,
                key: const ValueKey('ownGoalTaken'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('ownGoalSave'),
          onPressed: _taken
              ? null
              : () {
                  final corner = widget.corners[_corner];
                  Navigator.of(context).pop(
                    SessionGoal(
                      kind: _kind,
                      segmentName: corner.name,
                      startProgressMeters: corner.startProgressMeters,
                      endProgressMeters: corner.endProgressMeters,
                    ),
                  );
                },
          child: Text(l10n.ownGoalsSave),
        ),
      ],
    );
  }
}
