import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import '../units.dart';
import 'theoretical_best_card.dart' show CalculateAgainButton;
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
  if (label.isEmpty && declaredSpeedUnits.any((unit) => unit.isNotEmpty)) {
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
  });

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
              if (onRetry case final retry?) CalculateAgainButton(retry),
            ] else if (loading || coach == null)
              Text(l10n.coachLoading)
            else ...[
              Text(
                l10n.coachReason(coach.reason, session),
                key: const ValueKey('coachReason'),
              ),
              if (coach.goal case final goal?) _goal(context, goal, speedUnit),
              for (var i = 0; i < coach.plan.length; ++i)
                _item(context, coach.plan[i].finding, i, speedUnit),
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
            ],
          ],
        ),
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
              finding.segmentName,
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
    return Padding(
      key: ValueKey('coachItem $index'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
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
              finding.segmentName,
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
          if (result != null)
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
      ),
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
      appBar: AppBar(title: Text(finding.segmentName)),
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
                  semanticLabel: l10n.coachWhyMap(finding.segmentName),
                  marks: [?_fasterMark, ?_thisMark],
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
