import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../units.dart';

extension LapStylesText on AppLocalizations {
  /// A style's name in the app's language.
  String lapStyleName(LapStyle style) => switch (style) {
    LapStyle.conservative => lapStyleConservative,
    LapStyle.lateBraking => lapStyleLateBraking,
    LapStyle.earlyThrottle => lapStyleEarlyThrottle,
    LapStyle.mixed => lapStyleMixed,
    LapStyle.typical => lapStyleTypical,
    LapStyle.outlier => lapStyleOutlier,
  };

  /// What a style means, in one sentence.
  String lapStyleRule(LapStyle style) => switch (style) {
    LapStyle.conservative => lapStylesRuleConservative,
    LapStyle.lateBraking => lapStylesRuleLateBraking,
    LapStyle.earlyThrottle => lapStylesRuleEarlyThrottle,
    LapStyle.mixed => lapStylesRuleMixed,
    LapStyle.typical => lapStylesRuleTypical,
    LapStyle.outlier => lapStylesRuleOutlier,
  };
}

/// The day's ranked laps by how they were driven (FET-223): per style, how
/// many laps, the quickest one and how its braking, throttle and speeds sat
/// against the day's typical. All inferred, from the same corner figures the
/// Corner Analyzer shows; not a cause of lap time. Worked out with the
/// theoretical best, in the same background job.
class LapStylesCard extends StatefulWidget {
  const LapStylesCard({
    super.key,
    required this.result,
    this.loading = false,
    this.onOpenLap,
  });

  /// Null while it is calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;
  final void Function(DayLapRow lap)? onOpenLap;

  @override
  State<LapStylesCard> createState() => _LapStylesCardState();
}

class _LapStylesCardState extends State<LapStylesCard> {
  /// Shown in full; closed at first, as the day page is long.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = widget.result;
    final day = result?.lapStyles;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.lapStylesHeading,
                        style: theme.textTheme.labelLarge,
                      ),
                      Container(
                        key: const ValueKey('lapStylesInferred'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.lapStylesInferredBadge,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('lapStylesToggle'),
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? l10n.lapStylesHide : l10n.lapStylesShow),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Closed, the long day page keeps one line for it.
            Text(
              _open
                  ? l10n.lapStylesIntro(lapStylesMinimumLaps)
                  : l10n.lapStylesSummary,
              style: theme.textTheme.bodySmall,
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              if (widget.loading || result == null)
                Text(
                  l10n.lapStylesWorking,
                  key: const ValueKey('lapStylesWorking'),
                )
              else if (result.state != DayTheoreticalBestState.ready ||
                  day == null)
                Text(
                  l10n.lapStylesUnavailable,
                  key: const ValueKey('lapStylesUnavailable'),
                )
              else
                ..._body(context, day),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, DayLapStyles day) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final styles = day.styles;
    final small = theme.textTheme.bodySmall;
    final basis = Text(
      l10n.lapStylesBasis(
        day.groupedLapCount,
        day.timedLapCount,
        styles.cornerCount,
      ),
      key: const ValueKey('lapStylesBasis'),
      style: small,
    );
    if (!styles.available) {
      return [
        basis,
        const SizedBox(height: 8),
        Text(
          styles.unavailableReason == lapStylesTooFewLaps
              ? l10n.lapStylesTooFewLaps(lapStylesMinimumLaps)
              : l10n.lapStylesTooFewCorners(lapStylesMinimumCorners),
          key: const ValueKey('lapStylesNotGrouped'),
        ),
        ..._notes(context, day),
      ];
    }
    final best = styles.best!;
    final bestGroup = styles.bestLapGroup!;
    return [
      basis,
      const SizedBox(height: 4),
      Text(l10n.lapStylesFewLaps, style: small),
      const SizedBox(height: 12),
      Text(
        l10n.lapStylesBestLine(
          l10n.lap(day.rowOf(best)),
          displayTime(best.seconds),
          l10n.lapStyleName(bestGroup.style),
        ),
        key: const ValueKey('lapStylesBestLine'),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      for (final group in styles.groups) _group(context, day, group),
      const SizedBox(height: 12),
      Text(l10n.lapStylesRulesHeading, style: theme.textTheme.titleSmall),
      for (final style in LapStyle.values)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(l10n.lapStyleRule(style), style: small),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          l10n.lapStylesRuleThresholds(
            fixed(lapStylesBrakeMeters, 0),
            fixed(lapStylesThrottleMeters, 0),
            fixed(lapStylesSpeedShare * 100, 0),
            fixed(lapStylesExtremeFactor, 0),
            lapStylesMinimumCorners,
          ),
          style: small,
        ),
      ),
      ..._notes(context, day),
    ];
  }

  List<Widget> _notes(BuildContext context, DayLapStyles day) {
    final l10n = context.l10n;
    final small = Theme.of(context).textTheme.bodySmall;
    final notes = [
      if (day.brakeCornerFigures > 0) l10n.lapStylesBrakeNote,
      if (day.brakeCornerFigures == 0) l10n.lapStylesNoBraking,
      if (day.brakeCornerFigures > 0 && day.brakeUnitAssumed)
        l10n.lapStylesBrakeUnitAssumed,
      if (day.speedUnitMissing) l10n.lapStylesSpeedUnitMissing,
    ];
    return [
      for (final note in notes)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(note, style: small),
        ),
    ];
  }

  Widget _group(BuildContext context, DayLapStyles day, LapStyleGroup group) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final small = theme.textTheme.bodySmall;
    final best = group.best;
    final row = day.rowOf(best);
    final isDayBest = group.bestDeltaSeconds == 0;
    final laps = group.laps.length;
    return Theme(
      // No dividers above and below each group when it opens.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('lapStylesGroup ${group.style.name}'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          l10n.lapStylesGroupTitle(l10n.lapStyleName(group.style), laps),
        ),
        subtitle: Text(
          [
            l10n.lapStylesGroupBest(l10n.lap(row), displayTime(best.seconds)),
            isDayBest
                ? l10n.lapStylesGroupIsDayBest
                : l10n.lapStylesGroupBehind(
                    displayDelta(group.bestDeltaSeconds),
                  ),
          ].join(' · '),
          style: small,
        ),
        children: [
          Text(
            [
              group.typicalSeconds == null
                  ? l10n.lapStylesGroupTypicalNeeds(lapStylesMinimumLaps)
                  : l10n.lapStylesGroupTypical(
                      displayTime(group.typicalSeconds!),
                    ),
              l10n.lapStylesGroupQuickerHalf(group.quickerHalfCount, laps),
            ].join(' · '),
            key: ValueKey('lapStylesGroupFigures ${group.style.name}'),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.lapStylesBestAgainst(l10n.lap(row), day.groupedLapCount),
            style: theme.textTheme.titleSmall,
          ),
          ..._comparison(context, best),
          const SizedBox(height: 8),
          Text(l10n.lapStylesLapsHeading, style: theme.textTheme.titleSmall),
          for (final lap in group.laps)
            ListTile(
              key: ValueKey('lapStylesLap ${day.rowOf(lap).displayName}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.lap(day.rowOf(lap))),
              trailing: Text(displayTime(lap.seconds)),
              onTap: widget.onOpenLap == null
                  ? null
                  : () => widget.onOpenLap!(day.rowOf(lap)),
            ),
        ],
      ),
    );
  }

  /// A lap's braking, throttle and speeds against the day's typical.
  List<Widget> _comparison(BuildContext context, LapStyleResult lap) {
    final l10n = context.l10n;
    String braking(double? median) {
      if (median == null) return '';
      final metres = median.abs().round();
      if (metres == 0) return l10n.lapStylesMedianSame;
      return median > 0
          ? l10n.lapStylesMedianMetresEarlier(metres)
          : l10n.lapStylesMedianMetresLater(metres);
    }

    String throttle(double? median) {
      if (median == null) return '';
      final metres = median.abs().round();
      if (metres == 0) return l10n.lapStylesMedianSame;
      return median > 0
          ? l10n.lapStylesMedianMetresLater(metres)
          : l10n.lapStylesMedianMetresEarlier(metres);
    }

    // A speed with its unit as the recording declares it; none shown when it
    // declares none (the card says so once).
    String speed(double? median) {
      if (median == null) return '';
      final unit = speedUnitOf(context, lap.speedUnit).trim();
      final text = fixed(median.abs(), 1);
      final shown = unit.isEmpty ? text : '$text $unit';
      if (double.parse(text) == 0) return l10n.lapStylesMedianSame;
      return median > 0
          ? l10n.lapStylesMedianFaster(shown)
          : l10n.lapStylesMedianSlower(shown);
    }

    final lines = <String>[
      if (lap.brake.measured == 0)
        l10n.lapStylesNotMeasured(l10n.lapStylesBrakeName)
      else
        l10n.lapStylesBrakeLine(
          lap.brake.positive,
          lap.brake.negative,
          lap.brake.measured,
          braking(lap.medianBrakeMeters),
        ),
      if (lap.throttle.measured == 0)
        l10n.lapStylesNotMeasured(l10n.lapStylesThrottleName)
      else
        l10n.lapStylesThrottleLine(
          lap.throttle.negative,
          lap.throttle.positive,
          lap.throttle.measured,
          throttle(lap.medianPickupMeters),
        ),
      if (lap.minimumSpeed.measured == 0)
        l10n.lapStylesNotMeasured(l10n.lapStylesMinimumName)
      else
        l10n.lapStylesSpeedLine(
          l10n.lapStylesMinimumName,
          lap.minimumSpeed.positive,
          lap.minimumSpeed.negative,
          lap.minimumSpeed.measured,
          speed(lap.medianMinimumSpeed),
        ),
      if (lap.exitSpeed.measured == 0)
        l10n.lapStylesNotMeasured(l10n.lapStylesExitName)
      else
        l10n.lapStylesSpeedLine(
          l10n.lapStylesExitName,
          lap.exitSpeed.positive,
          lap.exitSpeed.negative,
          lap.exitSpeed.measured,
          speed(lap.medianExitSpeed),
        ),
      if (lap.outlierReason == LapOutlierReason.unlike)
        l10n.lapStylesOutlierUnlike(lap.extremeCorners, lap.cornersCompared)
      else if (lap.outlierReason == LapOutlierReason.fewCorners)
        l10n.lapStylesOutlierFew(lap.cornersCompared, lapStylesMinimumCorners),
    ];
    return [
      for (final line in lines)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(line)),
    ];
  }
}
