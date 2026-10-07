import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'segment_spread_map.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText;

/// "1:31.234 · spread 0.412 s", or "Needs at least 3 laps" when there are
/// too few: a missing value is never shown as zero.
String consistencyText(AppLocalizations l10n, ConsistencySummary summary) {
  if (!summary.available ||
      summary.median == null ||
      summary.interquartileRange == null) {
    return l10n.consistencyNeedsLaps(minimumConsistencySamples);
  }
  return l10n.consistencyValue(
    displayTime(summary.median!),
    summary.interquartileRange!.toStringAsFixed(3),
  );
}

/// "7 laps", "1 lap".
String lapCountText(AppLocalizations l10n, int count) =>
    l10n.consistencyLapCount(count);

/// How repeatable the group's lap times and segment times are: the median
/// (typical time) and the interquartile range (spread of the middle half),
/// over the day, per session and per segment.
class ConsistencyCard extends StatelessWidget {
  const ConsistencyCard({
    super.key,
    required this.laps,
    required this.result,
    this.loading = false,
    this.sections,
    this.spreadRunId,
    this.onSpreadRun,
    this.path,
    this.gate,
  });

  /// The lap times' consistency.
  final LapConsistency laps;

  /// The theoretical best, whose segments carry their consistency; null
  /// while it is calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;

  /// Each session's segment times, for where the laps vary; with [path]
  /// (the best lap's trace) and [gate] the map draws on.
  final SectionProgression? sections;

  /// The session where the laps vary is shown for, kept by the page.
  final String? spreadRunId;
  final ValueChanged<String>? onSpreadRun;
  final LapPath? path;
  final (Offset, Offset)? gate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = this.result;
    Widget row(String label, ConsistencySummary summary, Key key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label)),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  consistencyText(l10n, summary),
                  key: key,
                  textAlign: TextAlign.end,
                  style: summary.available
                      ? null
                      : theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                ),
                Text(
                  lapCountText(l10n, summary.count),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.consistencyHeading, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              l10n.consistencyIntro(minimumConsistencySamples),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(l10n.consistencyLapTimes, style: theme.textTheme.titleSmall),
            // With one session the day and the session are the same laps:
            // one row, named after the session.
            row(
              laps.runs.length == 1
                  ? l10n.session(laps.runs.single.runName)
                  : l10n.consistencyAllSessions,
              laps.day,
              const ValueKey('lapConsistency day'),
            ),
            if (laps.runs.length > 1)
              for (final run in laps.runs)
                row(
                  l10n.session(run.runName),
                  run.laps,
                  ValueKey('lapConsistency ${run.runId}'),
                ),
            const SizedBox(height: 8),
            Text(
              l10n.consistencySegmentTimes,
              style: theme.textTheme.titleSmall,
            ),
            if (loading || result == null)
              Text(l10n.consistencyMeasuring)
            else if (result.state != DayTheoreticalBestState.ready)
              Text(l10n.tbDependent(result))
            else
              for (final segment in result.segments)
                row(
                  l10n.tbSegmentName(segment.name),
                  segment.consistency,
                  ValueKey('sectorConsistency ${segment.segmentId}'),
                ),
            if (!loading &&
                result != null &&
                result.state == DayTheoreticalBestState.ready &&
                sections != null &&
                sections!.sessions.isNotEmpty) ...[
              const SizedBox(height: 16),
              SegmentSpreadMap(
                result: result,
                sections: sections!,
                selectedRunId: spreadRunId,
                onSelectRun: onSpreadRun,
                path: path,
                gate: gate,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
