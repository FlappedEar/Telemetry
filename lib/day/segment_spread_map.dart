import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText;
import 'track_map.dart';

/// The colour of each spread band, from repeatable to varied: a green to
/// red ramp that keeps clear of lap A's amber and lap B's blue.
List<Color> segmentSpreadColors(BuildContext context) => [
  const Color(0xFF2FD6A8),
  const Color(0xFFB5E550),
  const Color(0xFFFFE45C),
  const Color(0xFFFF8A5C),
  FetColors.of(context).loss,
];

/// The best lap's trace outside every segment (between two, or not timed):
/// apart from the grey of a segment with too few laps.
const Color segmentSpreadOutsideColor = Color(0xFF9B8CFF);

/// Where a session's laps vary (FET-224): the best lap's trace coloured by
/// each segment's spread in the chosen session (the interquartile range of
/// its times there, from the section progression), in fixed bands, with the
/// segments listed from the most varied. A segment with too few laps is
/// left grey and says so.
class SegmentSpreadMap extends StatefulWidget {
  const SegmentSpreadMap({
    super.key,
    required this.result,
    required this.sections,
    this.selectedRunId,
    this.onSelectRun,
    this.path,
    this.gate,
  });

  /// The theoretical best: its segments and the best lap the map follows.
  final DayTheoreticalBest result;

  /// Each session's times through each segment.
  final SectionProgression sections;

  /// The session shown; the latest when null or no longer in [sections].
  /// Kept by the page, so a recalculation keeps the choice.
  final String? selectedRunId;
  final ValueChanged<String>? onSelectRun;

  /// The best lap's trace; no map without it.
  final LapPath? path;
  final (Offset, Offset)? gate;

  @override
  State<SegmentSpreadMap> createState() => _SegmentSpreadMapState();
}

class _SegmentSpreadMapState extends State<SegmentSpreadMap> {
  // The segment of each fix of the best lap's trace, by its time.
  DayTheoreticalBest? _indexedResult;
  LapPath? _indexedPath;
  Map<double, int?> _segmentOfFix = const {};

  Map<double, int?> _segments(DayTheoreticalBest result, LapPath path) {
    if (!identical(result, _indexedResult) || !identical(path, _indexedPath)) {
      _indexedResult = result;
      _indexedPath = path;
      final best = result.bestLap;
      _segmentOfFix = best == null
          ? const {}
          : {
              for (final segment in path.segments)
                for (final point in segment)
                  point.telemetryTime: result.segmentAtTime(
                    best,
                    point.telemetryTime,
                  ),
            };
    }
    return _segmentOfFix;
  }

  // The map's colours, kept while their inputs are the same, so the trace is
  // not repainted on every rebuild of the page.
  Object? _coloursKey;
  Color? Function(PathPoint)? _colours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sessions = widget.sections.sessions;
    if (sessions.isEmpty) return const SizedBox.shrink();
    // The latest session first, as the progression orders them.
    final session = sessions.firstWhere(
      (session) => session.run.id == widget.selectedRunId,
      orElse: () => sessions.last,
    );
    final colors = segmentSpreadColors(context);
    final neutral = theme.colorScheme.outline;

    // Each segment's spread in the session, by its id.
    final spreads = <String, ConsistencySummary>{
      for (final row in widget.sections.segments)
        for (final cell in row.cells)
          if (cell.runId == session.runId) row.segmentId: cell.summary,
    };
    double? spreadOf(String segmentId) {
      final summary = spreads[segmentId];
      return summary != null && summary.available
          ? summary.interquartileRange
          : null;
    }

    final segments = widget.result.segments;
    final listed = [
      for (final segment in segments)
        (segment: segment, spread: spreadOf(segment.segmentId)),
    ]..sort((a, b) => (b.spread ?? -1).compareTo(a.spread ?? -1));
    final path = widget.path;
    final ofFix = path == null
        ? const <double, int?>{}
        : _segments(widget.result, path);
    final outside = ofFix.values.contains(null);
    final key = (
      widget.result,
      widget.sections,
      path,
      session.runId,
      neutral,
      colors.last,
    );
    if (key != _coloursKey) {
      _coloursKey = key;
      _colours = (PathPoint point) {
        final index = ofFix[point.telemetryTime];
        if (index == null) return segmentSpreadOutsideColor;
        final spread = spreadOf(segments[index].segmentId);
        return spread == null ? neutral : colors[segmentSpreadBand(spread)];
      };
    }

    Widget swatch(Color color) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    String band(int index) {
      final edges = segmentSpreadBandsSeconds;
      String s(double value) => fixed(value, 2);
      if (index == 0) return l10n.spreadBandAtMost(s(edges.first));
      if (index == edges.length) return l10n.spreadBandAbove(s(edges.last));
      return l10n.spreadBandBetween(s(edges[index - 1]), s(edges[index]));
    }

    return Column(
      key: const ValueKey('segmentSpread'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.spreadMapHeading, style: theme.textTheme.titleSmall),
        Text(l10n.spreadMapIntro, style: theme.textTheme.bodySmall),
        if (sessions.length > 1)
          DropdownButton<String>(
            key: const ValueKey('segmentSpreadSession'),
            isExpanded: true,
            value: session.run.id,
            items: [
              for (final candidate in sessions)
                DropdownMenuItem(
                  value: candidate.run.id,
                  child: Text(l10n.session(candidate.run.name)),
                ),
            ],
            onChanged: (id) {
              if (id != null) widget.onSelectRun?.call(id);
            },
          ),
        if (path != null && !path.isEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: IgnorePointer(
              child: TrackMap(
                key: const ValueKey('segmentSpreadMap'),
                interactive: false,
                path: path,
                gate: widget.gate,
                semanticLabel: l10n.spreadMapLabel(
                  l10n.session(session.run.name),
                ),
                pointColor: _colours,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          key: const ValueKey('segmentSpreadLegend'),
          spacing: 12,
          runSpacing: 4,
          children: [
            for (var i = 0; i < colors.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  swatch(colors[i]),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(band(i), style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                swatch(neutral),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    l10n.consistencyNeedsLaps(minimumConsistencySamples),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (outside)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  swatch(segmentSpreadOutsideColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      l10n.spreadOutsideSegments,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        // The segments, most varied first, with their spread: the legend's
        // numbers, not only colours.
        for (final (:segment, :spread) in listed)
          Padding(
            key: ValueKey('segmentSpread ${segment.segmentId}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                swatch(
                  spread == null ? neutral : colors[segmentSpreadBand(spread)],
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Text(l10n.tbSegmentName(segment.name)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 3,
                  child: Text(
                    spread == null
                        ? l10n.consistencyNeedsLaps(minimumConsistencySamples)
                        : l10n.progressionSpread(fixed(spread, 3)),
                    textAlign: TextAlign.end,
                    style: spread == null
                        ? theme.textTheme.bodyMedium?.copyWith(color: neutral)
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
