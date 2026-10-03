import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';

/// "1:31.234 · spread 0.412 s", or "Needs at least 3 laps" when there are
/// too few: a missing value is never shown as zero.
String consistencyText(ConsistencySummary summary) {
  if (!summary.available ||
      summary.median == null ||
      summary.interquartileRange == null) {
    return 'Needs at least $minimumConsistencySamples laps';
  }
  return '${displayTime(summary.median!)} · spread '
      '${summary.interquartileRange!.toStringAsFixed(3)} s';
}

/// "7 laps", "1 lap".
String lapCountText(int count) => '$count ${count == 1 ? 'lap' : 'laps'}';

/// How repeatable the group's lap times and segment times are: the median
/// (typical time) and the interquartile range (spread of the middle half),
/// over the day, per session and per segment.
class ConsistencyCard extends StatelessWidget {
  const ConsistencyCard({
    super.key,
    required this.laps,
    required this.result,
    this.loading = false,
  });

  /// The lap times' consistency.
  final LapConsistency laps;

  /// The theoretical best, whose segments carry their consistency; null
  /// while it is calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  consistencyText(summary),
                  key: key,
                  textAlign: TextAlign.end,
                  style: summary.available
                      ? null
                      : theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                ),
                Text(
                  lapCountText(summary.count),
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
            Text('Consistency', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Typical time is the median; the spread is the interquartile '
              'range, the width of the middle half of the laps, so one slow '
              'or quick lap does not dominate it. At least '
              '$minimumConsistencySamples laps are needed.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text('Lap times', style: theme.textTheme.titleSmall),
            row('All sessions', laps.day, const ValueKey('lapConsistency day')),
            for (final run in laps.runs)
              row(
                run.runName,
                run.laps,
                ValueKey('lapConsistency ${run.runId}'),
              ),
            const SizedBox(height: 8),
            Text('Segment times', style: theme.textTheme.titleSmall),
            if (loading || result == null)
              const Text('Measured with the theoretical best…')
            else if (result.state != DayTheoreticalBestState.ready)
              Text(result.message)
            else
              for (final segment in result.segments)
                row(
                  segment.name,
                  segment.consistency,
                  ValueKey('sectorConsistency ${segment.segmentId}'),
                ),
          ],
        ),
      ),
    );
  }
}
