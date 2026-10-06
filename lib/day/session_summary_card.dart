import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/label_value_row.dart';
import 'channel_cards.dart' show channelLabelIn, channelValueText;
import 'theoretical_best_card.dart' show TheoreticalBestText;

/// A session in 30 seconds (FET-233): its best lap against the day so far,
/// how repeatable its laps were, its biggest gain and loss since the
/// session before, the biggest gap left to the day's fastest, the car's
/// hottest temperatures and the coach's goal. Every number comes from the
/// day's results ([summarizeSession]); nothing is recalculated here.
class SessionSummaryCard extends StatefulWidget {
  const SessionSummaryCard({
    super.key,
    required this.runId,
    required this.session,
    required this.progression,
    required this.result,
    required this.coach,
    required this.coachLoading,
    required this.channels,
    required this.channelsLoading,
  });

  /// The session summarized (the one the coach coaches) and its name.
  final String runId;
  final String session;

  final DayProgression progression;

  /// The theoretical best, whose section times give the segment lines;
  /// null until it is calculated.
  final DayTheoreticalBest? result;
  final DayCoach? coach;
  final bool coachLoading;

  /// The day's channel summaries; null until requested and calculated.
  final DayChannelSummaries? channels;
  final bool channelsLoading;

  @override
  State<SessionSummaryCard> createState() => _SessionSummaryCardState();
}

class _SessionSummaryCardState extends State<SessionSummaryCard> {
  // The section progression, worked out again only when the theoretical
  // best or the progression changes.
  (DayTheoreticalBest?, DayProgression, SectionProgression?)? _sections;

  SectionProgression? get _sectionProgression {
    final result = widget.result, progression = widget.progression;
    final cached = _sections;
    if (cached != null &&
        identical(cached.$1, result) &&
        identical(cached.$2, progression)) {
      return cached.$3;
    }
    final sections = result?.sectionProgression([
      for (final run in progression.runs) run.run,
    ]);
    _sections = (result, progression, sections);
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final summary = summarizeSession(
      widget.runId,
      progression: widget.progression,
      sections: _sectionProgression,
      coach: widget.coachLoading ? null : widget.coach,
      channels: widget.channels,
    );
    return Card(
      key: const ValueKey('sessionSummary'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.summaryTitle(l10n.session(widget.session)),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              summary == null
                  ? l10n.summaryNotShown(l10n.session(widget.session))
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
    String segment(SessionSegmentChange change) => l10n.summaryChange(
      l10n.tbSegmentName(change.name),
      displayDelta(change.deltaSeconds),
    );
    final previous = summary.previousRunName;
    // Segment lines wait for the theoretical best, and are left out when
    // it has no result.
    final segmentsPending = widget.result == null;
    final segmentsShown =
        segmentsPending ||
        widget.result!.state == DayTheoreticalBestState.ready;

    final best = summary.bestLap;
    final earlier = summary.earlierBestLap;
    final bestText = best == null
        ? l10n.summaryNoBest
        : earlier == null
        ? l10n.summaryBestFirst(displayTime(best.durationSeconds))
        : summary.newBest
        ? l10n.summaryBestNew(
            displayTime(best.durationSeconds),
            displayDelta(summary.bestDeltaSeconds!),
          )
        : l10n.summaryBestBehind(
            displayTime(best.durationSeconds),
            displayDelta(summary.bestDeltaSeconds!),
            l10n.session(earlier.runName),
          );

    final spread = summary.lapSpread,
        previousSpread = summary.previousLapSpread;
    final spreadText = spread == null
        ? l10n.consistencyNeedsLaps(minimumConsistencySamples)
        : previous != null && previousSpread != null
        ? l10n.summarySpreadThen(
            fixed(spread, 3),
            l10n.session(previous),
            fixed(previousSpread, 3),
          )
        : l10n.summarySpreadValue(fixed(spread, 3));

    String change(SessionSegmentChange? value) => segmentsPending
        ? l10n.summaryWorking
        : previous == null
        ? l10n.summaryFirstSession
        : summary.segmentsCompared == 0
        ? l10n.summaryNotCompared
        : value == null
        ? l10n.summaryNoChange
        : segment(value);

    final gap = summary.biggestGap;
    final goal = summary.goal;
    final temperatures = summary.temperatures;
    return [
      row('sessionSummaryBest', l10n.summaryBestLap, bestText),
      row('sessionSummarySpread', l10n.summarySpread, spreadText),
      if (segmentsShown) ...[
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
      ],
      if (previous != null && summary.segmentsCompared > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.summaryAgainst(l10n.session(previous)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      if (segmentsPending || gap != null)
        row(
          'sessionSummaryGap',
          l10n.summaryGap,
          gap == null
              ? l10n.summaryWorking
              : l10n.summaryGapValue(
                  l10n.tbSegmentName(gap.name),
                  displayDelta(gap.deltaSeconds),
                ),
        ),
      if (widget.channels == null && widget.channelsLoading)
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
        ),
      if (widget.coachLoading && previous != null)
        row(
          'sessionSummaryGoal',
          l10n.summaryGoal(l10n.session(previous)),
          l10n.summaryWorking,
        )
      else if (goal != null)
        row(
          'sessionSummaryGoal',
          l10n.summaryGoal(l10n.session(goal.runName)),
          '${l10n.tbSegmentName(goal.finding.segmentName)}: ${switch (goal.outcome) {
            CoachGoalOutcome.better => l10n.coachGoalBetter,
            CoachGoalOutcome.unchanged => l10n.coachGoalUnchanged,
            CoachGoalOutcome.worse => l10n.coachGoalWorse,
            CoachGoalOutcome.notMeasured => l10n.coachGoalNotMeasured,
          }}',
        ),
    ];
  }
}
