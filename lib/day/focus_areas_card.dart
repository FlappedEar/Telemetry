import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../units.dart';
import 'corner_details.dart' show lapAColor, lapBColor;
import 'time_losses_card.dart' show CompareLaps, lapStretch;
import 'track_map.dart';

/// The heading of a focus area's kind.
String focusKindText(FocusAreaKind kind) => switch (kind) {
  FocusAreaKind.sectorGap => 'Best lap against the fastest sector',
  FocusAreaKind.repeatedLoss => 'Repeated loss',
  FocusAreaKind.brakingSpread => 'Braking-point spread',
  FocusAreaKind.minimumSpeedSpread => 'Lowest-speed spread',
};

/// Readable text for why there is no focus area.
const String noFocusAreaText =
    'No loss, sector gap or spread is large enough to single out.';

/// Where to look next (Overlays' focus areas): at most three areas selected
/// from measured losses, sector gaps and corner spreads. Each shows what was
/// measured apart from a hypothesis to check; neither is a cause or an
/// instruction. Tapping an area compares its two laps.
class FocusAreasCard extends StatelessWidget {
  const FocusAreasCard({
    super.key,
    required this.result,
    required this.areas,
    required this.lapLabel,
    this.loading = false,
    this.path,
    this.gate,
    this.wide = false,
    this.onOpenLap,
    this.onCompare,
  });

  /// Null while the theoretical best is calculated for the first time.
  final DayTheoreticalBest? result;
  final List<FocusArea> areas;
  final String Function(Object? reference) lapLabel;
  final bool loading;

  /// The best lap's trace, for the comparison's map.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;
  final void Function(DayLapRow lap)? onOpenLap;
  final CompareLaps? onCompare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = this.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where to look next', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (loading || result == null)
              const Text('Selected with the theoretical best…')
            else if (result.state != DayTheoreticalBestState.ready)
              Text(result.message)
            else if (result.computed?.actualBest == null)
              const Text(timeLossBestLapUntimedMessage)
            else if (areas.isEmpty)
              const Text(noFocusAreaText, key: ValueKey('focusAreasNone'))
            else ...[
              Text(
                'Each starts with what was measured. The line under it is a '
                'hypothesis to check in the laps, not a cause or an '
                'instruction.',
                style: theme.textTheme.bodySmall,
              ),
              for (var i = 0; i < areas.length; ++i)
                _area(context, result, areas[i], i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _area(
    BuildContext context,
    DayTheoreticalBest result,
    FocusArea area,
    int index,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('focusArea $index'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FocusAreaPage(
            result: result,
            area: area,
            lapLabel: lapLabel,
            path: path,
            gate: gate,
            wide: wide,
            onOpenLap: onOpenLap,
            onCompare: onCompare,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${focusKindText(area.kind)} · ${area.name}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('Observed: ${area.observation}'),
                  const SizedBox(height: 2),
                  Text(
                    'Hypothesis: ${area.hypothesis}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Compare ${_label(area.lap)} with ${_label(area.against)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }

  String _label(Object? reference) {
    final label = lapLabel(reference);
    return label.isEmpty ? 'a lap unavailable' : label;
  }
}

/// One focus area opened: the two laps through its segment, what was
/// measured on each and the segment on the map.
class FocusAreaPage extends StatefulWidget {
  const FocusAreaPage({
    super.key,
    required this.result,
    required this.area,
    required this.lapLabel,
    this.path,
    this.gate,
    this.wide = false,
    this.onOpenLap,
    this.onCompare,
  });

  final DayTheoreticalBest result;
  final FocusArea area;
  final String Function(Object? reference) lapLabel;

  /// The best lap's trace.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;
  final void Function(DayLapRow lap)? onOpenLap;
  final CompareLaps? onCompare;

  @override
  State<FocusAreaPage> createState() => _FocusAreaPageState();
}

class _FocusAreaPageState extends State<FocusAreaPage> {
  late final int _segment = widget.result.segments.indexWhere(
    (segment) => segment.segmentId == widget.area.segmentId,
  );

  // Whether each fix of the best lap's trace is in the area's segment.
  late final Map<double, bool> _inSegment = _segmentFixes();

  Map<double, bool> _segmentFixes() {
    final result = widget.result, path = widget.path, best = result.bestLap;
    if (path == null || best == null || _segment < 0) return const {};
    return {
      for (final segment in path.segments)
        for (final point in segment)
          point.telemetryTime:
              result.segmentAtTime(best, point.telemetryTime) == _segment,
    };
  }

  DayLapSectors? _lap(Object? reference) {
    for (final lap in widget.result.laps) {
      if (lap.lap.reference == reference) return lap;
    }
    return null;
  }

  CornerLapObservation? _observation(Object? reference) {
    final observations =
        widget.result.computed?.cornerObservations[widget.area.segmentId] ??
        const [];
    for (final observation in observations) {
      if (observation.lapReference == reference) return observation;
    }
    return null;
  }

  // What the area measured on one lap: its time through the segment, and
  // for a corner spread its braking point or lowest speed.
  String _measure(Object? reference) {
    final lap = _lap(reference);
    final seconds = lap == null || _segment < 0 ? null : lap.seconds(_segment);
    final parts = [seconds == null ? 'not timed' : displayTime(seconds)];
    final observation = _observation(reference);
    switch (widget.area.kind) {
      case FocusAreaKind.brakingSpread:
        final meters = observation?.brakingPointMeters;
        parts.add(
          meters == null
              ? 'braking point not measured'
              : 'braking starts at ${meters.round()} m',
        );
      case FocusAreaKind.minimumSpeedSpread:
        final speed = observation?.minimumSpeed;
        final label = speedUnitOf(context, widget.area.unit);
        final unit = label.isEmpty ? '' : ' $label';
        parts.add(
          speed == null
              ? 'lowest speed not measured'
              : 'lowest speed ${speed.toStringAsFixed(1)}$unit',
        );
      case FocusAreaKind.sectorGap || FocusAreaKind.repeatedLoss:
        break;
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final area = widget.area;
    final path = widget.path;
    final first = _lap(area.lap)?.lap, second = _lap(area.against)?.lap;
    Widget lapRow(String role, Object? reference, Color color, Key key) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: Container(width: 12, height: 12, color: color),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$role · ${widget.lapLabel(reference).isEmpty ? 'unavailable' : widget.lapLabel(reference)}',
                style: theme.textTheme.titleSmall,
              ),
              Text(_measure(reference), key: key),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(area.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            focusKindText(area.kind),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Observed: ${area.observation}',
            style: theme.textTheme.titleMedium,
            key: const ValueKey('focusObservation'),
          ),
          const SizedBox(height: 8),
          Text(
            'Hypothesis: ${area.hypothesis}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
            key: const ValueKey('focusHypothesis'),
          ),
          const SizedBox(height: 16),
          Text('Through ${area.name}', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          lapRow('A', area.lap, lapAColor, const ValueKey('focusLapA')),
          const SizedBox(height: 8),
          lapRow('B', area.against, lapBColor, const ValueKey('focusLapB')),
          if (path != null && !path.isEmpty && _segment >= 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: widget.wide ? 420 : 300,
              child: IgnorePointer(
                child: TrackMap(
                  key: const ValueKey('focusMap'),
                  interactive: false,
                  path: path,
                  gate: widget.gate,
                  pointColor: (point) =>
                      _inSegment[point.telemetryTime] ?? false
                      ? lapAColor
                      : theme.colorScheme.outlineVariant,
                  semanticLabel: 'Best lap trace with ${area.name} highlighted',
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Measured on these laps only. It does not say which way is faster '
            'or safe.',
            style: theme.textTheme.bodySmall,
          ),
          if (widget.onOpenLap != null)
            Wrap(
              spacing: 8,
              children: [
                for (final (key, lap) in [('A', first), ('B', second)])
                  if (lap != null)
                    TextButton.icon(
                      key: ValueKey('focusOpenLap$key'),
                      icon: const Icon(Icons.map_outlined),
                      label: Text('Open ${lap.displayName}'),
                      onPressed: () => widget.onOpenLap!(lap),
                    ),
              ],
            ),
          if (widget.onCompare != null &&
              first != null &&
              second != null &&
              first.reference != second.reference)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('focusCompare'),
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Compare laps A and B'),
                onPressed: () => widget.onCompare!(
                  first,
                  second,
                  _segment < 0
                      ? null
                      : lapStretch(
                          widget.result,
                          first,
                          widget.result.segments[_segment].startProgressMeters,
                          widget.result.segments[_segment].endProgressMeters,
                        ),
                  segmentId: _segment < 0
                      ? null
                      : widget.result.segments[_segment].segmentId,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
