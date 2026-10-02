import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import 'corner_details.dart';
import 'track_map.dart';

/// The colour of a loss of [fraction] (0 to 1) of the largest: one hue, dim
/// to bright, as in Overlays' "Where your best lap can improve".
Color lossColor(double fraction) {
  final t = fraction.clamp(0.0, 1.0);
  return Color.from(
    alpha: 1,
    red: 0.30 + 0.70 * t,
    green: 0.36 + 0.24 * t,
    blue: 0.42 - 0.22 * t,
  );
}

/// "C1" for "Corner 1", "S2" for "Straight 2", "C3–4" for "Corners 3–4".
String shortSegmentName(String name) {
  final match = RegExp(r'^(\w)\w*\s+(.+)$').firstMatch(name.trim());
  if (match == null) return name;
  return '${match.group(1)!.toUpperCase()}${match.group(2)}';
}

/// A group's theoretical best: the best lap, the theoretical best and the
/// time available; a loss map (the best lap's trace, each segment coloured
/// by the time the chosen lap loses there to the fastest time); where that
/// time is; and every lap's sector times with the fastest of each segment
/// highlighted.
class TheoreticalBestCard extends StatefulWidget {
  const TheoreticalBestCard({
    super.key,
    required this.result,
    this.loading = false,
    this.path,
    this.gate,
    this.wide = false,
  });

  /// Null while it is calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;

  /// The best lap's trace, for the loss map.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;

  @override
  State<TheoreticalBestCard> createState() => _TheoreticalBestCardState();
}

class _TheoreticalBestCardState extends State<TheoreticalBestCard> {
  DayLapReference? _selected;

  // The segment of each fix of the best lap's trace, by its time.
  DayTheoreticalBest? _indexedResult;
  LapPath? _indexedPath;
  Map<double, int?> _segmentOfFix = const {};

  DayLapSectors? _selectedLap(DayTheoreticalBest result) {
    DayLapSectors? best;
    for (final lap in result.laps) {
      if (lap.lap.reference == _selected) return lap;
      if (lap.bestOfDay) best = lap;
    }
    return best ?? (result.laps.isEmpty ? null : result.laps.first);
  }

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

  String _lapName(DayTheoreticalBest result, Object? reference) {
    for (final lap in result.laps) {
      if (lap.lap.reference == reference) return lap.lap.displayName;
    }
    return 'lap unavailable';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theoretical best', style: theme.textTheme.labelLarge),
            if (widget.loading || result == null) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Timing every lap on one track axis…'),
            ] else if (result.state != DayTheoreticalBestState.ready)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(result.message),
              )
            else
              ..._ready(context, result),
          ],
        ),
      ),
    );
  }

  List<Widget> _ready(BuildContext context, DayTheoreticalBest result) {
    final theme = Theme.of(context);
    final lap = _selectedLap(result);
    final path = widget.path;
    return [
      const SizedBox(height: 8),
      _Headline(result: result),
      if (result.message.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(result.message),
      ],
      const SizedBox(height: 4),
      Text(
        'The fastest time of each of the ${result.segments.length} segments '
        'across ${result.laps.length} laps. It combines parts of different '
        'laps, so it does not show that the whole lap can be driven that fast.'
        '${result.automaticSegments ? ' Segments proposed from the best lap; saving the day keeps them.' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      if (lap != null) ...[
        const SizedBox(height: 16),
        Text('Where the time goes', style: theme.textTheme.titleSmall),
        DropdownButton<DayLapReference>(
          key: const ValueKey('lossLap'),
          isExpanded: true,
          value: lap.lap.reference,
          items: [
            for (final candidate in result.laps)
              DropdownMenuItem(
                value: candidate.lap.reference,
                child: Text(
                  '${candidate.lap.displayName} · ${displayTime(candidate.lap.durationSeconds)}'
                  '${candidate.bestOfDay ? ' · best' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (reference) => setState(() => _selected = reference),
        ),
        if (path != null && !path.isEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: widget.wide ? 360 : 260,
            child: IgnorePointer(
              child: TrackMap(
                key: const ValueKey('lossMap'),
                interactive: false,
                path: path,
                gate: widget.gate,
                pointColor: _lossColors(result, lap, path),
                semanticLabel:
                    'Best lap trace, each segment coloured by the time '
                    '${lap.lap.displayName} loses there',
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _LossLegend(maximum: _maximumLoss(lap)),
        const SizedBox(height: 8),
        if (result.corners.isNotEmpty)
          Text(
            'Tap a corner for its speeds, braking and pickup against the best lap.',
            style: theme.textTheme.bodySmall,
          ),
        ..._losses(context, result, lap),
      ],
      const SizedBox(height: 16),
      Text('Sector times', style: theme.textTheme.titleSmall),
      Text(
        'The fastest time of each segment is highlighted. Tap a lap to show '
        'its losses on the map.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      _SectorTable(
        result: result,
        selected: lap?.lap.reference,
        onSelect: (reference) => setState(() => _selected = reference),
      ),
    ];
  }

  double _maximumLoss(DayLapSectors lap) => math.max(
    0.001,
    lap.lossSeconds.fold(0.0, (high, loss) => math.max(high, loss ?? 0.0)),
  );

  Color? Function(PathPoint) _lossColors(
    DayTheoreticalBest result,
    DayLapSectors lap,
    LapPath path,
  ) {
    final segments = _segments(result, path);
    final maximum = _maximumLoss(lap);
    final neutral = Theme.of(context).colorScheme.outline;
    return (point) {
      final index = segments[point.telemetryTime];
      if (index == null) return neutral;
      final loss = lap.lossSeconds[index];
      return loss == null ? neutral : lossColor(loss / maximum);
    };
  }

  List<Widget> _losses(
    BuildContext context,
    DayTheoreticalBest result,
    DayLapSectors lap,
  ) {
    final maximum = _maximumLoss(lap);
    final order = List.generate(result.segments.length, (index) => index)
      ..sort((a, b) {
        final left = lap.lossSeconds[a] ?? -1.0,
            right = lap.lossSeconds[b] ?? -1.0;
        return left != right ? right.compareTo(left) : a.compareTo(b);
      });
    return [
      for (final index in order) _lossRow(context, result, lap, index, maximum),
    ];
  }

  // One segment's loss; a corner also shows its minimum speed and braking
  // point against the best lap, and opens its details when tapped.
  Widget _lossRow(
    BuildContext context,
    DayTheoreticalBest result,
    DayLapSectors lap,
    int index,
    double maximum,
  ) {
    final theme = Theme.of(context);
    final corner = result.cornerAt(index);
    final comparison = corner?.compare(lap.lap.reference);
    final summary = comparison == null ? null : cornerSummary(comparison);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 36,
            decoration: BoxDecoration(
              color: lap.lossSeconds[index] == null
                  ? theme.colorScheme.outline
                  : lossColor(lap.lossSeconds[index]! / maximum),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.segments[index].name),
                Text(
                  _lossDetail(result, lap, index),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (summary != null && summary.isNotEmpty)
                  Text(
                    summary,
                    key: ValueKey('cornerSummary ${corner!.name}'),
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            lap.lossSeconds[index] == null
                ? '—'
                : '+${lap.lossSeconds[index]!.toStringAsFixed(3)} s',
            style: theme.textTheme.titleSmall,
          ),
          if (comparison != null)
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        ],
      ),
    );
    if (corner == null || comparison == null) return row;
    return InkWell(
      key: ValueKey('lossRow ${corner.name}'),
      onTap: () => showCornerDetails(context, corner, lap.lap.reference),
      child: row,
    );
  }

  String _lossDetail(DayTheoreticalBest result, DayLapSectors lap, int index) {
    final segment = result.segments[index];
    if (segment.seconds == null) return segment.unavailableReason;
    if (lap.lossSeconds[index] == null) {
      return 'Not fully covered on this lap · fastest ${displayTime(segment.seconds!)}';
    }
    if (segment.sourceLapReference == lap.lap.reference) {
      return 'Fastest here · ${displayTime(segment.seconds!)}';
    }
    return 'Fastest ${displayTime(segment.seconds!)} · '
        '${_lapName(result, segment.sourceLapReference)}';
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.result});

  final DayTheoreticalBest result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = result.bestLapSeconds;
    final total = result.theoreticalBestSeconds;
    final available = result.availableSeconds;
    Widget stat(String label, String value, Key key, [Color? color]) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          value,
          key: key,
          style: theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        stat(
          result.summary?.actualBest?.coversWholeLap ?? true
              ? 'Best lap'
              : 'Best lap, same segments',
          best == null ? '—' : displayTime(best),
          const ValueKey('bestLapTime'),
        ),
        stat(
          'Theoretical best',
          total == null ? '—' : displayTime(total),
          const ValueKey('theoreticalBestTime'),
          theme.colorScheme.primary,
        ),
        stat(
          'Available',
          available == null ? '—' : '${available.toStringAsFixed(3)} s',
          const ValueKey('availableTime'),
          theme.colorScheme.tertiary,
        ),
      ],
    );
  }
}

class _LossLegend extends StatelessWidget {
  const _LossLegend({required this.maximum});

  final double maximum;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Text('0 s', style: style),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(colors: [lossColor(0), lossColor(1)]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('+${maximum.toStringAsFixed(3)} s', style: style),
      ],
    );
  }
}

/// Laps by segments, scrolling sideways on a phone.
class _SectorTable extends StatelessWidget {
  const _SectorTable({
    required this.result,
    required this.selected,
    required this.onSelect,
  });

  final DayTheoreticalBest result;
  final DayLapReference? selected;
  final ValueChanged<DayLapReference> onSelect;

  static const _lapWidth = 136.0, _timeWidth = 76.0, _cellWidth = 62.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final segments = result.segments;
    final numbers = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget cell(
      String text,
      double width, {
      TextStyle? style,
      Color? color,
      Alignment alignment = Alignment.centerRight,
    }) => Container(
      width: width,
      height: 36,
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final header = Row(
      children: [
        cell(
          'Lap',
          _lapWidth,
          style: theme.textTheme.labelMedium,
          alignment: Alignment.centerLeft,
        ),
        cell('Time', _timeWidth, style: theme.textTheme.labelMedium),
        for (final segment in segments)
          Tooltip(
            message: segment.name,
            child: cell(
              shortSegmentName(segment.name),
              _cellWidth,
              style: theme.textTheme.labelMedium,
            ),
          ),
      ],
    );
    final rows = [
      for (final lap in result.laps)
        InkWell(
          key: ValueKey('sectorRow ${lap.lap.displayName}'),
          onTap: () => onSelect(lap.lap.reference),
          child: Container(
            color: lap.lap.reference == selected
                ? scheme.secondaryContainer
                : null,
            child: Row(
              children: [
                cell(
                  '${lap.lap.displayName}${lap.bestOfDay ? ' ★' : ''}',
                  _lapWidth,
                  style: theme.textTheme.bodySmall,
                  alignment: Alignment.centerLeft,
                ),
                cell(
                  displayTime(lap.lap.durationSeconds),
                  _timeWidth,
                  style: numbers,
                ),
                for (var i = 0; i < segments.length; ++i)
                  _fastest(lap, i)
                      ? cell(
                          lap.seconds(i)!.toStringAsFixed(3),
                          _cellWidth,
                          style: numbers?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                          color: scheme.primaryContainer,
                        )
                      : cell(
                          lap.seconds(i)?.toStringAsFixed(3) ?? '—',
                          _cellWidth,
                          style: numbers,
                        ),
              ],
            ),
          ),
        ),
    ];
    final fastest = Row(
      children: [
        cell(
          'Fastest',
          _lapWidth,
          style: theme.textTheme.labelMedium,
          alignment: Alignment.centerLeft,
        ),
        cell(
          result.theoreticalBestSeconds == null
              ? '—'
              : displayTime(result.theoreticalBestSeconds!),
          _timeWidth,
          style: numbers?.copyWith(fontWeight: FontWeight.bold),
        ),
        for (final segment in segments)
          cell(
            segment.seconds?.toStringAsFixed(3) ?? '—',
            _cellWidth,
            style: numbers?.copyWith(fontWeight: FontWeight.bold),
          ),
      ],
    );
    return SingleChildScrollView(
      key: const ValueKey('sectorTable'),
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const Divider(height: 1),
          ...rows,
          const Divider(height: 1),
          fastest,
        ],
      ),
    );
  }

  // The lap that set the segment's fastest time.
  bool _fastest(DayLapSectors lap, int index) {
    final segment = result.segments[index];
    return segment.seconds != null &&
        segment.sourceLapReference == lap.lap.reference;
  }
}
