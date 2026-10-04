import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import '../units.dart';
import 'theoretical_best_card.dart' show CalculateAgainButton;
import 'time_losses_card.dart' show TimeLossText;
import 'track_map.dart';
import '../ui/readable_list.dart';

extension CoachText on AppLocalizations {
  /// What a coach item asks, as its heading.
  String coachKind(CoachKind kind) => switch (kind) {
    CoachKind.earlyLift => coachKindEarlyLift,
    CoachKind.excessiveCoasting => coachKindExcessiveCoasting,
    CoachKind.lowMinimumSpeed => coachKindLowMinimumSpeed,
    CoachKind.lateThrottle => coachKindLateThrottle,
    CoachKind.improving => coachKindImproving,
  };

  /// What to try, or to keep.
  String coachAction(CoachKind kind) => switch (kind) {
    CoachKind.earlyLift => coachActionEarlyLift,
    CoachKind.excessiveCoasting => coachActionExcessiveCoasting,
    CoachKind.lowMinimumSpeed => coachActionLowMinimumSpeed,
    CoachKind.lateThrottle => coachActionLateThrottle,
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

/// A coach value with its unit: positions in whole metres, the rest with
/// one decimal ("46.9 km/h", "3.3 s", "412 m"). Speeds are labelled
/// [speedUnit] (unlabelled when it is empty) and not shown when it is null
/// (see [coachSpeedLabel]).
String coachValue(double value, String unit, String? speedUnit) {
  if (!value.isFinite) return '—';
  if (unit == 'm') return '${value.round()}\u00a0m';
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
              for (var i = 0; i < coach.plan.length; ++i)
                _item(context, coach.plan[i].finding, i, speedUnit),
              if (speedUnit == null &&
                  coach.plan.any((item) => _hasSpeed(item.finding))) ...[
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.coachLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
            style: theme.textTheme.titleSmall,
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

  /// The laps of earlier sessions showing the pattern too.
  List<DayLapRow> _earlier(CoachFinding finding) => [
    for (final lap in finding.affectedLaps)
      if (!finding.sessionLaps.contains(lap)) lap,
  ];

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
            keep ? l10n.coachWhyBefore : l10n.coachWhyFaster,
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
                ),
              ),
            ),
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
