import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';
import '../ui/label_value_row.dart';
import 'day_results_controller.dart';
import 'driving_panels.dart'
    show
        coastingNote,
        coastingProvenanceText,
        coastingSummaryText,
        inferredColor;
import 'telemetry_chart.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText;
import 'touch.dart';

/// The lap page's coasting panel, or null without the lap's recording.
Widget? lapCoastingPanel(
  DayResultsController controller,
  DayLapRow row,
  ChartWindow window,
) {
  final session = controller.session(row.runId);
  if (session == null || !(row.end > row.start)) return null;
  return LapCoastingPanel(
    key: const ValueKey('lapCoastingPanel'),
    controller: controller,
    row: row,
    session: session,
    window: window,
  );
}

/// Where one lap coasts, at speed with neither pedal pressed (Overlays'
/// CoastingPanel): the lap's total, by approved segment once the day's
/// segments are calculated, and each episode, which moves the cursor there.
/// An observation, not a verdict.
class LapCoastingPanel extends StatefulWidget {
  const LapCoastingPanel({
    super.key,
    required this.controller,
    required this.row,
    required this.session,
    required this.window,
  });

  final DayResultsController controller;
  final DayLapRow row;
  final TelemetrySession session;
  final ChartWindow window;

  @override
  State<LapCoastingPanel> createState() => _LapCoastingPanelState();
}

class _LapCoastingPanelState extends State<LapCoastingPanel> {
  DayTheoreticalBest? _segmentsFrom;
  CoastingSummary? _summary;
  bool _segmented = false;

  // The lap on the day's shared axis and its approved segments, when the
  // theoretical best is calculated for this lap's group.
  (List<ProgressSegment>, ApprovedSegmentation)? _segments(
    DayTheoreticalBest? result,
  ) {
    final computed = result?.computed;
    if (result == null ||
        computed == null ||
        result.state != DayTheoreticalBestState.ready ||
        !computed.axis.valid ||
        !computed.approved.valid ||
        computed.approved.segments.isEmpty) {
      return null;
    }
    final inGroup = widget.controller.analysis.groups.any(
      (group) =>
          group.id == result.groupId && group.runIds.contains(widget.row.runId),
    );
    if (!inGroup) return null;
    for (var i = 0; i < computed.population.length; ++i) {
      if (computed.population[i].times.lapReference == widget.row.reference) {
        return (computed.traces[i], computed.approved);
      }
    }
    return (
      projectLapTrace(
        computed.axis,
        widget.session,
        widget.row.start,
        widget.row.end,
      ),
      computed.approved,
    );
  }

  CoastingSummary _current() {
    final result = widget.controller.theoreticalBest;
    if (_summary == null || !identical(result, _segmentsFrom)) {
      final segments = _segments(result);
      _segmentsFrom = result;
      _segmented = segments != null;
      _summary = summarizeCoasting(
        widget.session,
        widget.row.start,
        widget.row.end,
        lapTrace: segments?.$1,
        approved: segments?.$2,
      );
    }
    return _summary!;
  }

  @override
  void didUpdateWidget(LapCoastingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.reference != widget.row.reference ||
        !identical(oldWidget.session, widget.session)) {
      _summary = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final summary = _current();
    final known = summary.valid && summary.provenance != drivingStateUnknown;
    final names = {
      for (final segment in summary.segments)
        segment.segmentId: l10n.tbSegmentName(segment.name),
    };
    String amount(double seconds, double meters) =>
        '${seconds.toStringAsFixed(1)}\u00a0s · ${meters.round()}\u00a0m';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.coastingTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              if (known)
                Text(
                  coastingSummaryText(l10n, summary),
                  key: const ValueKey('lapCoastingSummary'),
                  style: theme.textTheme.titleSmall,
                ),
              Text(
                coastingProvenanceText(l10n, summary),
                key: const ValueKey('lapCoastingProvenance'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: summary.provenance == drivingStateInferred
                      ? readableOn(context, inferredColor)
                      : null,
                ),
              ),
              Text(coastingNote(l10n), style: theme.textTheme.bodySmall),
              if (known && _segmented) ...[
                const SizedBox(height: 8),
                Text(l10n.coastingBySegment, style: theme.textTheme.titleSmall),
                for (final segment in summary.segments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: LabelValueRow(
                      label: Text(
                        l10n.tbSegmentName(segment.name),
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Wraps at its "·" with very large text.
                      value: Text(
                        segment.seconds > 0.05
                            ? amount(segment.seconds, segment.meters)
                            : '—',
                        key: ValueKey(
                          'lapCoastingSegment ${segment.segmentId}',
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ),
              ] else if (known && summary.episodes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.controller.theoreticalBestLoading
                        ? l10n.coastingBySegmentLoading
                        : l10n.coastingBySegmentNeedsSegments,
                    key: const ValueKey('lapCoastingNoSegments'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (known && summary.episodes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(l10n.coastingEpisodes, style: theme.textTheme.titleSmall),
                for (final (index, episode) in summary.episodes.indexed)
                  ButtonRow(
                    child: InkWell(
                      key: ValueKey('lapCoastingEpisode $index'),
                      onTap: () =>
                          widget.window.cursor.value = episode.startTime,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            const Icon(Icons.my_location, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${names[episode.segmentId] ?? l10n.coastingIntoLap((episode.startTime - widget.row.start).toStringAsFixed(1))}'
                                ' · ${amount(episode.seconds, episode.meters)}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
