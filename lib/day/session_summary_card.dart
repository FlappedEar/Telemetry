import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/label_value_row.dart';
import 'channel_cards.dart'
    show channelLabelIn, channelReasonText, channelValueText;
import 'next_session_card.dart' show CoachText, coachSpeedLabel, coachValue;
import 'theoretical_best_card.dart' show TheoreticalBestText;

/// A session in 30 seconds (FET-233): its best lap against the day so far,
/// how repeatable its laps were, its biggest gain and loss since the
/// session before, the biggest gap left to the quickest typical time, the
/// car's hottest temperatures and the coach's goal. Every number comes from
/// the day's results ([summarizeSession]); nothing is recalculated here. A
/// line without a result says why.
class SessionSummaryCard extends StatelessWidget {
  const SessionSummaryCard({
    super.key,
    required this.runId,
    required this.session,
    required this.progression,
    required this.sectionsState,
    required this.sections,
    required this.coach,
    required this.coachLoading,
    this.coachError = '',
    required this.channels,
    this.ownGoals,
    this.onBriefing,
  });

  /// Opens the briefing for the next session; null shows no button.
  final VoidCallback? onBriefing;

  /// The driver's own goals set after the session before ([session] names
  /// it), and their checks on this one ([checkSessionGoals], FET-218): null
  /// checks while they cannot be made, [noLaps] when that session or this
  /// one has no laps among the compared laps. Null when no goals were set.
  final ({
    RunGoals goals,
    String session,
    List<SessionGoalCheck>? checks,
    bool noLaps,
  })?
  ownGoals;

  /// The session summarized (the one the coach coaches) and its name.
  final String runId;
  final String session;

  final DayProgression progression;

  /// The theoretical best's state, null while it is calculated, and its
  /// section progression in [progression]'s order when it is ready.
  final DayTheoreticalBestState? sectionsState;
  final SectionProgression? sections;

  final DayCoach? coach;
  final bool coachLoading;

  /// Why the coach could not run; empty when it ran.
  final String coachError;

  /// The day's channel summaries; null until they are calculated.
  final DayChannelSummaries? channels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final summary = summarizeSession(
      runId,
      progression: progression,
      sections: sectionsState == DayTheoreticalBestState.ready
          ? sections
          : null,
      coach: coachLoading ? null : coach,
      channels: channels,
    );
    return Card(
      key: const ValueKey('sessionSummary'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The briefing beside the title, below it when they do not fit.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  l10n.summaryTitle(l10n.session(session)),
                  style: theme.textTheme.titleMedium,
                ),
                if (onBriefing case final open?)
                  FilledButton.tonalIcon(
                    key: const ValueKey('sessionSummaryBriefing'),
                    onPressed: open,
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(l10n.briefingTitle),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              summary == null
                  ? l10n.summaryNotShown(l10n.session(session))
                  : l10n.summaryIntro,
              key: const ValueKey('sessionSummaryIntro'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (summary != null) ..._rows(context, summary),
          ],
        ),
      ),
    );
  }

  /// How the session did on one of the driver's goals, as the Next session
  /// card words the main focus.
  String _ownGoal(BuildContext context, SessionGoalCheck check) {
    final l10n = context.l10n;
    final coach = this.coach!;
    final speedUnit = coachSpeedLabel(
      context,
      converted: coach.speedsConverted,
    );
    final unit = coachGoalUnit(check.goal.kind, coach.speedUnit);
    final outcome = switch (check.outcome) {
      CoachGoalOutcome.better => l10n.coachGoalBetter,
      CoachGoalOutcome.unchanged => l10n.coachGoalUnchanged,
      CoachGoalOutcome.worse => l10n.coachGoalWorse,
      CoachGoalOutcome.notMeasured when check.otherGroup =>
        l10n.summaryOwnGoalOtherGroup,
      CoachGoalOutcome.notMeasured when check.measuredName.isEmpty =>
        l10n.coachGoalNoCorner,
      CoachGoalOutcome.notMeasured => l10n.coachGoalNotMeasured,
    };
    final text = switch ((check.before, check.now)) {
      (final before?, final now?) =>
        '${l10n.coachGoalMeasured(l10n.coachMetric(check.metric), coachValue(before.value, unit, speedUnit), coachValue(now.value, unit, speedUnit))} $outcome',
      _ => outcome,
    };
    // Today's corners can differ from those the goal was set at.
    return check.measuredName.isNotEmpty &&
            check.measuredName != check.goal.segmentName
        ? '$text\n${l10n.coachGoalMeasuredAt(l10n.tbSegmentName(check.measuredName))}'
        : text;
  }

  /// What the car did over the session's ranked laps (FET-228), each part
  /// saying why when it could not be read; null when neither was recorded.
  Widget? _carWatch(
    BuildContext context,
    CarWatch watch,
    Widget Function(String key, String label, String value) row,
  ) {
    final l10n = context.l10n;
    if (!watch.recorded) return null;
    String g(double value) => '${fixed(value, 3)}\u00a0g';
    String fallText(CarWatchFall fall) {
      final text = l10n.summaryCarFall(
        fixed(fall.fall * 100, 0),
        '${fall.fromLap}',
        '${fall.toLap}',
        g(fall.from),
        g(fall.to),
      );
      final alongside = fall.alongside;
      return alongside == null
          ? text
          : l10n.summaryCarFallWith(
              text,
              channelLabelIn(context, alongside.channel),
              channelValueText(alongside.from, alongside.unit),
              channelValueText(alongside.to, alongside.unit),
            );
    }

    String rise(CarWatchRise rise) => l10n.summaryCarRise(
      channelLabelIn(context, rise.channel),
      channelValueText(rise.from, rise.unit),
      channelValueText(rise.to, rise.unit),
      '${rise.fromLap}',
      '${rise.toLap}',
    );
    final lines = <String>[
      // Temperatures still rising, or why none was read.
      ...switch (watch.temperatures) {
        CarWatchStatus.read when watch.rises.isNotEmpty => [
          for (final item in watch.rises) rise(item),
        ],
        CarWatchStatus.read => [l10n.summaryCarSettledTemperatures],
        CarWatchStatus.needsLaps => [
          l10n.summaryCarTemperaturesNeedLaps(carWatchLaps),
        ],
        CarWatchStatus.missingOnLap => [
          l10n.summaryCarTemperaturesMissing(carWatchLaps),
        ],
        CarWatchStatus.notRecorded => const <String>[],
      },
      // Strong acceleration falling, or why it was not read.
      ...switch (watch.acceleration) {
        CarWatchStatus.read => [
          if (watch.fall case final fall?) ...[
            fallText(fall),
            l10n.summaryCarFallNote,
          ] else
            l10n.summaryCarSettledAcceleration,
        ],
        CarWatchStatus.needsLaps => [
          l10n.summaryCarAccelerationNeedsLaps(carWatchAccelerationLaps),
        ],
        CarWatchStatus.missingOnLap => [l10n.summaryCarAccelerationMissing],
        CarWatchStatus.notRecorded => const <String>[],
      },
    ];
    return row(
      'sessionSummaryCarWatch',
      l10n.summaryCarWatch,
      lines.join('\n'),
    );
  }

  List<Widget> _rows(BuildContext context, SessionSummary summary) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final numbers = theme.textTheme.bodyLarge?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget row(String key, String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: LabelValueRow(
        key: ValueKey(key),
        crossAxisAlignment: CrossAxisAlignment.start,
        label: Text(label, style: theme.textTheme.labelLarge),
        value: Text(value, style: numbers, textAlign: TextAlign.end),
      ),
    );
    final previous = summary.previousRunName;
    final pending = sectionsState == null;
    final ready = sectionsState == DayTheoreticalBestState.ready;

    final best = summary.bestLap;
    final earlier = summary.earlierBestLap;
    final String bestText;
    if (best == null) {
      bestText = l10n.summaryNoBest;
    } else if (earlier == null) {
      bestText = summary.firstSession
          ? l10n.summaryBestFirst(displayTime(best.durationSeconds))
          : l10n.summaryBestNoEarlier(displayTime(best.durationSeconds));
    } else if (summary.newBest) {
      bestText = l10n.summaryBestNew(
        displayTime(best.durationSeconds),
        displayDelta(summary.bestDeltaSeconds!),
      );
    } else if (summary.bestDeltaSeconds == 0) {
      bestText = l10n.summaryBestEqual(
        displayTime(best.durationSeconds),
        l10n.session(earlier.runName),
      );
    } else {
      bestText = l10n.summaryBestBehind(
        displayTime(best.durationSeconds),
        displayDelta(summary.bestDeltaSeconds!),
        l10n.session(earlier.runName),
      );
    }

    final spread = summary.lapSpread;
    final previousSpread = summary.previousLapSpread;
    final spreadText = spread == null
        ? l10n.consistencyNeedsLaps(minimumConsistencySamples)
        : previous != null && previousSpread != null
        ? l10n.summarySpreadThen(
            fixed(spread, 3),
            l10n.session(previous),
            fixed(previousSpread, 3),
          )
        : l10n.summarySpreadValue(fixed(spread, 3));

    String change(SessionSegmentChange? value) => pending
        ? l10n.summaryWorking
        : summary.firstSession
        ? l10n.summaryFirstSession
        : previous == null
        ? l10n.summaryNoEarlierRanked
        : summary.segmentsCompared == 0
        ? l10n.summaryNotCompared
        : value == null
        ? l10n.summaryNoChange(fixed(sessionSummaryChangeSeconds, 2))
        : l10n.summaryChange(
            l10n.tbSegmentName(value.name),
            displayDelta(value.deltaSeconds),
          );

    final gap = summary.biggestGap;
    final channels = this.channels;
    final temperatures = summary.temperatures;
    final goal = summary.goal;
    return [
      row('sessionSummaryBest', l10n.summaryBestLap, bestText),
      row('sessionSummarySpread', l10n.summarySpread, spreadText),
      if (pending || ready) ...[
        row(
          'sessionSummaryGain',
          l10n.summaryGain,
          change(summary.biggestGain),
        ),
        row(
          'sessionSummaryLoss',
          l10n.summaryLoss,
          change(summary.biggestLoss),
        ),
        if (previous != null && summary.segmentsCompared > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.summaryAgainst(l10n.session(previous)),
              key: const ValueKey('sessionSummaryAgainst'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        row(
          'sessionSummaryGap',
          l10n.summaryGap,
          pending
              ? l10n.summaryWorking
              : summary.segmentsTimed == 0
              ? l10n.summaryGapNeedsLaps
              : summary.sessionsTimed < 2
              ? l10n.summaryOnlySession
              : gap == null
              ? l10n.summaryGapNone(fixed(sessionSummaryChangeSeconds, 2))
              : l10n.summaryGapValue(
                  l10n.tbSegmentName(gap.name),
                  displayDelta(gap.deltaSeconds),
                ),
        ),
      ] else
        row(
          'sessionSummarySegments',
          l10n.summarySegments,
          l10n.summarySegmentsUnavailable,
        ),
      if (channels == null)
        row('sessionSummaryCar', l10n.summaryCar, l10n.summaryWorking)
      else if (temperatures.isNotEmpty)
        row(
          'sessionSummaryCar',
          l10n.summaryCar,
          [
            for (final t in temperatures)
              previous != null && t.previousMaximum != null
                  ? l10n.summaryTemperatureThen(
                      channelLabelIn(context, t.channel),
                      channelValueText(t.maximum, t.unit),
                      l10n.session(previous),
                      channelValueText(t.previousMaximum, t.unit),
                    )
                  : l10n.summaryTemperature(
                      channelLabelIn(context, t.channel),
                      channelValueText(t.maximum, t.unit),
                    ),
          ].join('\n'),
        )
      else if (summary.temperatureReason.isNotEmpty)
        row(
          'sessionSummaryCar',
          l10n.summaryCar,
          channelReasonText(l10n, summary.temperatureReason),
        )
      else if (channels.temperatureChannels.isNotEmpty)
        // The day records temperatures, this session does not.
        row('sessionSummaryCar', l10n.summaryCar, l10n.channelNotRecorded),
      if (channels != null && summary.carWatch != null)
        ?_carWatch(context, summary.carWatch!, row),
      if (!summary.firstSession)
        if (goal != null)
          row(
            'sessionSummaryGoal',
            l10n.summaryGoal(l10n.session(goal.runName)),
            // As the Next session card words it.
            '${l10n.tbSegmentName(goal.measuredName.isEmpty ? goal.finding.segmentName : goal.measuredName)}: ${switch (goal.outcome) {
              CoachGoalOutcome.better => l10n.coachGoalBetter,
              CoachGoalOutcome.unchanged => l10n.coachGoalUnchanged,
              CoachGoalOutcome.worse => l10n.coachGoalWorse,
              CoachGoalOutcome.notMeasured when goal.measuredName.isEmpty => l10n.coachGoalNoCorner,
              CoachGoalOutcome.notMeasured => l10n.coachGoalNotMeasured,
            }}',
          )
        else
          row(
            'sessionSummaryGoal',
            l10n.summaryGoalBefore,
            coachLoading || pending
                ? l10n.summaryWorking
                : !ready
                // The coach needs the theoretical best.
                ? l10n.summarySegmentsUnavailable
                : coachError.isNotEmpty
                ? l10n.summaryCoachFailed
                : l10n.summaryNoFocus,
          ),
      if (ownGoals case final own?)
        for (var i = 0; i < own.goals.goals.length; ++i)
          row(
            'sessionSummaryOwnGoal$i',
            l10n.summaryOwnGoal(
              l10n.coachItemTitle(
                l10n.tbSegmentName(own.goals.goals[i].segmentName),
                l10n.coachKind(own.goals.goals[i].kind),
              ),
            ),
            switch (own.checks) {
              final checks? => _ownGoal(context, checks[i]),
              // Why there is no check yet, as the focus line says it.
              null when own.noLaps => l10n.summaryOwnGoalNoLaps(
                l10n.session(own.session),
              ),
              null when coachLoading || pending => l10n.summaryWorking,
              null when !ready => l10n.summarySegmentsUnavailable,
              null when coachError.isNotEmpty => l10n.summaryCoachFailed,
              null => l10n.summaryWorking,
            },
          ),
    ];
  }
}
