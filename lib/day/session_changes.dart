import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText;

/// Every segment's change since the session before (FET-236, idea 2 of
/// FET-217): the segments that got quicker and slower by
/// [sessionSummaryChangeSeconds] or more, most first, each with its spread
/// now and then, and how many stayed about the same. Every number is the
/// session summary's ([SessionSummary.changes]); a list that cannot be
/// shown says why.
class SessionChanges extends StatelessWidget {
  const SessionChanges({
    super.key,
    required this.session,
    required this.summary,
    required this.pending,
    required this.ready,
  });

  /// The session's name, for a summary that is not there.
  final String session;

  /// Null when the progression does not list the session.
  final SessionSummary? summary;

  /// The theoretical best is still worked out, or is not there.
  final bool pending, ready;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final summary = this.summary;
    final previous = summary?.previousRunName;
    final threshold = fixed(sessionSummaryChangeSeconds, 2);

    Widget note(String text, [String key = 'sessionChangesReason']) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: theme.textTheme.bodyLarge),
    );

    final String? reason = pending
        ? l10n.summaryWorking
        : !ready
        ? l10n.summarySegmentsUnavailable
        : summary == null
        ? l10n.summaryNotShown(l10n.session(session))
        : summary.firstSession
        ? l10n.summaryFirstSession
        : previous == null
        ? l10n.summaryNoEarlierRanked
        : summary.segmentsCompared == 0
        ? l10n.summaryNotCompared
        : null;
    if (reason != null || summary == null || previous == null) {
      return Card(
        key: const ValueKey('sessionChanges'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: note(reason ?? l10n.summaryWorking),
        ),
      );
    }

    final gains = [
      for (final change in summary.changes)
        if (change.deltaSeconds <= -sessionSummaryChangeSeconds) change,
    ]..sort((a, b) => a.deltaSeconds.compareTo(b.deltaSeconds));
    final losses = [
      for (final change in summary.changes)
        if (change.deltaSeconds >= sessionSummaryChangeSeconds) change,
    ]..sort((a, b) => b.deltaSeconds.compareTo(a.deltaSeconds));
    final same = summary.changes.length - gains.length - losses.length;
    final before = l10n.session(previous);

    final numbers = theme.textTheme.titleMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget item(SessionSegmentChange change) {
      final spread = change.spreadSeconds,
          spreadBefore = change.referenceSpreadSeconds;
      return Padding(
        key: ValueKey('sessionChange ${change.segmentId}'),
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tbSegmentName(change.name),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    l10n.changesTypical(
                      displayTime(change.seconds),
                      before,
                      displayTime(change.referenceSeconds),
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (spread != null && spreadBefore != null)
                    Text(
                      l10n.changesSpread(
                        fixed(spread, 3),
                        before,
                        fixed(spreadBefore, 3),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(displayDelta(change.deltaSeconds), style: numbers),
          ],
        ),
      );
    }

    Widget heading(String key, String text) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(top: 20),
      child: Text(text, style: theme.textTheme.titleMedium),
    );

    return Card(
      key: const ValueKey('sessionChanges'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.changesIntro(before, threshold),
              key: const ValueKey('sessionChangesIntro'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if ((summary.lapSpread, summary.previousLapSpread) case (
              final spread?,
              final spreadBefore?,
            ))
              Padding(
                key: const ValueKey('sessionChangesLapSpread'),
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${l10n.summarySpread}: ${l10n.summarySpreadThen(fixed(spread, 3), before, fixed(spreadBefore, 3))}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            heading('sessionChangesQuicker', l10n.changesQuicker),
            if (gains.isEmpty)
              note(
                l10n.changesNoneQuicker(threshold),
                'sessionChangesNoneQuicker',
              )
            else
              for (final change in gains) item(change),
            heading('sessionChangesSlower', l10n.changesSlower),
            if (losses.isEmpty)
              note(
                l10n.changesNoneSlower(threshold),
                'sessionChangesNoneSlower',
              )
            else
              for (final change in losses) item(change),
            if (same > 0)
              Padding(
                key: const ValueKey('sessionChangesSame'),
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  l10n.changesSame(same, threshold),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
