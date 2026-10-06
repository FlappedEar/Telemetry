import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'channel_cards.dart'
    show channelLabelIn, channelReasonText, channelValueText;
import 'next_session_card.dart' show CoachText, coachSpeedLabel;
import 'session_summary_card.dart' show carWatchLines;
import 'theoretical_best_card.dart' show TheoreticalBestText;

/// Before the next session, in a few large lines on a page of its own
/// (FET-232, idea 17 of FET-217):
/// the coach's main focus with what was measured, the change for once that
/// feels settled, the driver's own goals and the biggest gap left to the
/// quickest typical time. Every line comes from results the Coach place
/// already shows ([DayCoach], [RunGoals], [summarizeSession]); a line
/// without one says why.
class BriefingCard extends StatelessWidget {
  const BriefingCard({
    super.key,
    required this.runId,
    required this.session,
    required this.progression,
    required this.sectionsState,
    required this.sections,
    required this.coach,
    required this.coachLoading,
    this.coachError = '',
    this.speedsConverted = false,
    required this.goals,
    this.channels,
    this.lastLap,
    this.bestLap,
  });

  /// The session the briefing comes from (the latest) and its name.
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

  /// Whether the coach's speeds are converted (see [coachSpeedLabel]).
  final bool speedsConverted;

  /// The driver's goals for the next session, set after [session].
  final RunGoals goals;

  /// The day's channel summaries, null while they are worked out.
  final DayChannelSummaries? channels;

  /// The session's last ranked lap on the circuit shown, and the best of
  /// the day there (trackside, FET-234); null when there is none.
  final DayLapRow? lastLap, bestLap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ready = sectionsState == DayTheoreticalBestState.ready;
    final pending = sectionsState == null;
    final coach = coachLoading ? null : this.coach;
    final coached = coach != null && coach.runId == runId;
    final speedUnit = coachSpeedLabel(context, converted: speedsConverted);

    final changes = [
      if (coached)
        for (final item in coach.plan)
          if (item.finding.kind.corrective) item.finding,
    ];
    final keep = coached ? coach.focus?.finding : null;
    final String focus;
    String? measured;
    if (coachLoading || pending) {
      focus = l10n.summaryWorking;
    } else if (!ready) {
      focus = l10n.summarySegmentsUnavailable;
    } else if (coachError.isNotEmpty) {
      focus = l10n.summaryCoachFailed;
    } else if (!coached) {
      focus = l10n.summaryWorking;
    } else if ((changes.isNotEmpty ? changes.first : keep) case final item?) {
      focus = _title(l10n, item);
      // Labelled apart, as on the Next session card; a speed that cannot
      // be shown reads "—" there too, and says why.
      measured =
          '${l10n.coachMeasuredLabel}: '
          '${l10n.coachMeasured(item, speedUnit)}';
      if (speedUnit == null && _hasSpeed(item)) {
        measured = '$measured\n${l10n.coachSpeedHidden}';
      }
    } else {
      focus = l10n.coachReason(coach.reason, l10n.session(session));
    }

    final summary = summarizeSession(
      runId,
      progression: progression,
      sections: ready ? sections : null,
      channels: channels,
    );
    final gap = summary?.biggestGap;
    final String chance;
    if (pending) {
      chance = l10n.summaryWorking;
    } else if (!ready) {
      chance = l10n.summarySegmentsUnavailable;
    } else if (summary == null) {
      chance = l10n.summaryNotShown(l10n.session(session));
    } else if (summary.segmentsTimed == 0) {
      chance = l10n.summaryGapNeedsLaps;
    } else if (summary.sessionsTimed < 2) {
      chance = l10n.summaryOnlySession;
    } else if (gap == null) {
      chance = l10n.summaryGapNone(fixed(sessionSummaryChangeSeconds, 2));
    } else {
      chance = l10n.summaryGapValue(
        l10n.tbSegmentName(gap.name),
        displayDelta(gap.deltaSeconds),
      );
    }

    Widget line(
      String key,
      String label,
      String value, [
      String? detail,
    ]) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Large, to be read at the car.
          Text(value, style: theme.textTheme.titleLarge),
          if (detail != null) Text(detail, style: theme.textTheme.bodyLarge),
        ],
      ),
    );

    return Card(
      key: const ValueKey('briefing'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.briefingFrom(l10n.session(session)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            _laps(context),
            line(
              'briefingFocus',
              changes.isEmpty && keep != null && coached
                  ? l10n.coachKeepLabel
                  : l10n.coachFocusLabel,
              focus,
              measured,
            ),
            // The coach's other points, up to three in all.
            for (var i = 1; i < changes.length && i < 3; i++)
              line(
                i == 1 ? 'briefingThen' : 'briefingThen$i',
                l10n.coachLaterLabel,
                _title(l10n, changes[i]),
              ),
            line(
              'briefingGoals',
              l10n.briefingGoals,
              goals.isEmpty
                  // Goals this version does not read are still kept.
                  ? (goals.readOnly
                        ? l10n.ownGoalsReadOnly
                        : l10n.briefingNoGoals)
                  : [
                      for (final goal in goals.goals)
                        l10n.coachItemTitle(
                          l10n.tbSegmentName(goal.segmentName),
                          l10n.coachKind(goal.kind),
                        ),
                    ].join('\n'),
            ),
            ?_car(context, summary, line),
            line('briefingChance', l10n.briefingChance, chance),
          ],
        ),
      ),
    );
  }

  /// The last ranked lap, the best of the day and the gap, in digits to be
  /// read from a few steps away.
  Widget _laps(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final last = lastLap, best = bestLap;
    if (last == null) {
      return Padding(
        key: const ValueKey('briefingLaps'),
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          l10n.summaryNotShown(l10n.session(session)),
          style: theme.textTheme.titleMedium,
        ),
      );
    }
    final digits = theme.textTheme.displaySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget tile(String key, String label, String value, String? detail) =>
        Column(
          key: ValueKey(key),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(value, style: digits),
            if (detail != null) Text(detail, style: theme.textTheme.bodyMedium),
          ],
        );
    return Padding(
      key: const ValueKey('briefingLaps'),
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 32,
        runSpacing: 12,
        children: [
          tile(
            'briefingLastLap',
            l10n.briefingLastLap,
            displayTime(last.durationSeconds),
            l10n.lapName(l10n.session(last.runName), last.lapNumber),
          ),
          if (best != null) ...[
            tile(
              'briefingBestLap',
              l10n.briefingDayBest,
              displayTime(best.durationSeconds),
              l10n.lapName(l10n.session(best.runName), best.lapNumber),
            ),
            tile(
              'briefingDelta',
              l10n.briefingDelta,
              displayDelta(last.durationSeconds - best.durationSeconds),
              null,
            ),
          ],
        ],
      ),
    );
  }

  /// The hottest temperatures and what the car did over the last laps, as
  /// the session summary shows them; null when the day records neither.
  Widget? _car(
    BuildContext context,
    SessionSummary? summary,
    Widget Function(String key, String label, String value, [String? detail])
    line,
  ) {
    final l10n = context.l10n;
    final channels = this.channels;
    if (channels == null) {
      return line('briefingCar', l10n.briefingCar, l10n.summaryWorking);
    }
    if (channels.error.isNotEmpty) {
      return line(
        'briefingCar',
        l10n.briefingCar,
        channelReasonText(l10n, channels.error),
      );
    }
    if (summary == null) return null;
    final hottest = [
      for (final t in summary.temperatures)
        l10n.summaryTemperature(
          channelLabelIn(context, t.channel),
          channelValueText(t.maximum, t.unit),
        ),
    ].join(' · ');
    final watch = summary.carWatch;
    final lines = watch == null
        ? const <String>[]
        : carWatchLines(context, watch);
    if (hottest.isEmpty && lines.isEmpty) {
      return summary.temperatureReason.isEmpty
          ? null
          : line(
              'briefingCar',
              l10n.briefingCar,
              channelReasonText(l10n, summary.temperatureReason),
            );
    }
    final more = hottest.isEmpty ? lines.skip(1).toList() : lines;
    return line(
      'briefingCar',
      l10n.briefingCar,
      hottest.isEmpty ? lines.first : hottest,
      more.isEmpty ? null : more.join('\n'),
    );
  }

  String _title(AppLocalizations l10n, CoachFinding finding) =>
      l10n.coachItemTitle(
        l10n.tbSegmentName(finding.segmentName),
        l10n.coachKind(finding.kind),
      );

  /// Whether the measured sentence ([AppLocalizations.coachMeasured],
  /// which reads the first evidence) holds a speed.
  static bool _hasSpeed(CoachFinding finding) =>
      finding.evidence.first.unit == 'km/h' ||
      finding.evidence.first.unit == 'mph';
}
