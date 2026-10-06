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
    this.goalChecks = const [],
  });

  /// The driver's own goals set after the session before, checked on this
  /// one ([checkSessionGoals], FET-218).
  final List<SessionGoalCheck> goalChecks;

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
            Text(
              l10n.summaryTitle(l10n.session(session)),
              style: theme.textTheme.titleMedium,
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
      for (var i = 0; i < goalChecks.length; ++i)
        row(
          'sessionSummaryOwnGoal$i',
          l10n.summaryOwnGoal(
            l10n.coachItemTitle(
              l10n.tbSegmentName(goalChecks[i].goal.segmentName),
              l10n.coachKind(goalChecks[i].goal.kind),
            ),
          ),
          _ownGoal(context, goalChecks[i]),
        ),
    ];
  }
}
