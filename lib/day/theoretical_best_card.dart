import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_controller.dart' show offersCalculateAgain;
import '../format.dart';
import '../l10n.dart';
import '../units.dart';
import 'corner_details.dart';
import 'time_losses_card.dart' show CompareLaps, lapStretch;
import 'touch.dart';
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
    this.onEditSegments,
    this.onAnalyze,
    this.onRetry,
  });

  /// Calculates again after a failure or with nothing to use, as Overlays'
  /// "Calculate again"; no button when null.
  final VoidCallback? onRetry;

  /// Opens the segment editor; no button when null.
  final VoidCallback? onEditSegments;

  /// Opens two laps in the Corner Analyzer on a segment; no button when
  /// null.
  final CompareLaps? onAnalyze;

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

/// Overlays' "Calculate again" under a theoretical best that failed or had
/// nothing to use.
class CalculateAgainButton extends StatelessWidget {
  const CalculateAgainButton(this.onPressed, {super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: OutlinedButton.icon(
      key: const ValueKey('calculateAgain'),
      onPressed: onPressed,
      icon: const Icon(Icons.refresh),
      label: Text(context.l10n.calculateAgain),
    ),
  );
}

class _TheoreticalBestCardState extends State<TheoreticalBestCard> {
  // Kept for the page: the list rebuilds the card when it scrolls back.
  late DayLapReference? _selected = readPageState(context, _storage);
  static const _storage = 'theoreticalBestLap';

  void _choose(DayLapReference? reference) {
    setState(() => _selected = reference);
    writePageState(context, _storage, reference);
  }

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
            ] else if (result.state != DayTheoreticalBestState.ready) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(result.message),
              ),
              if (widget.onRetry case final retry?
                  when offersCalculateAgain(result))
                CalculateAgainButton(retry),
            ] else
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
        '${result.automaticSegments
            ? ' Segments proposed from the best lap; saving the day keeps them.'
            : result.segmentsAutomatic
            ? ''
            : ' The segments include your corrections.'}',
        style: theme.textTheme.bodySmall,
      ),
      if (widget.onEditSegments != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('editSegments'),
            icon: const Icon(Icons.edit_road),
            label: const Text('Edit segments'),
            onPressed: widget.onEditSegments,
          ),
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
          onChanged: _choose,
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
        if (widget.onAnalyze != null)
          Text(
            'The compare button opens this lap against the best lap through '
            'the segment in the Corner Analyzer.',
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
        onSelect: _choose,
      ),
      ..._variability(context, result),
    ];
  }

  // Each corner's braking, speeds, pickup and line from lap to lap, as
  // Overlays lists them (driving_variability.dart).
  List<Widget> _variability(BuildContext context, DayTheoreticalBest result) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final corners = [
      for (final row in result.segments)
        if (row.variability case final variability?) (row, variability),
    ];
    return [
      const SizedBox(height: 16),
      Text(l10n.variabilityHeading, style: theme.textTheme.titleSmall),
      Text(l10n.variabilityIntro, style: theme.textTheme.bodySmall),
      if (corners.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.variabilityNone,
            key: const ValueKey('noVariability'),
          ),
        )
      else
        for (final (row, variability) in corners)
          _VariabilityTile(name: row.name, variability: variability),
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
    final segment = result.segments[index];
    final analyze = _analyze(result, lap, index);
    final corner = result.cornerAt(index);
    final comparison = corner?.compare(lap.lap.reference);
    speedUnitOf(context); // The summary's speeds follow the setting.
    final summary = comparison == null ? null : cornerSummary(comparison);
    final row = Padding(
      // 36 + 12: a 48 dp row to tap.
      padding: const EdgeInsets.symmetric(vertical: 6),
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
                Text(segment.name),
                // Wraps at 360 dp: the lap that set the time matters.
                Text(
                  _lossDetail(result, lap, index),
                  style: theme.textTheme.bodySmall,
                ),
                if (summary != null && summary.isNotEmpty)
                  Text(
                    summary,
                    key: ValueKey('cornerSummary ${corner!.name}'),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            lap.lossSeconds[index] == null
                ? '—'
                : '+${lap.lossSeconds[index]!.toStringAsFixed(3)} s',
            textAlign: TextAlign.end,
            style: theme.textTheme.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (analyze != null)
            IconButton(
              key: ValueKey('lossAnalyze ${segment.name}'),
              tooltip: 'Open in the Corner Analyzer',
              icon: const Icon(Icons.compare_arrows),
              onPressed: analyze,
            )
          else if (comparison != null)
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        ],
      ),
    );
    if (corner == null || comparison == null) return row;
    return InkWell(
      key: ValueKey('lossRow ${corner.name}'),
      onTap: () => showCornerDetails(
        context,
        corner,
        lap.lap.reference,
        onAnalyze: analyze,
      ),
      child: row,
    );
  }

  // Opens [lap] (or, for the best lap, the lap that set the segment's
  // fastest time) against the best lap through segment [index].
  VoidCallback? _analyze(
    DayTheoreticalBest result,
    DayLapSectors lap,
    int index,
  ) {
    final onAnalyze = widget.onAnalyze;
    final segment = result.segments[index];
    if (onAnalyze == null) return null;
    final pair = dayTheoreticalBestSectorPair(
      result,
      segment.segmentId,
      lap: lap.lap,
    );
    if (pair == null) return null;
    final (a, b) = pair;
    return () => onAnalyze(
      a,
      b,
      lapStretch(
        result,
        a,
        segment.startProgressMeters,
        segment.endProgressMeters,
      ),
      segmentId: segment.segmentId,
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

/// The lines of one corner's [CornerVariability], as Overlays writes them:
/// a metric measured on no lap is left out, one on fewer than three laps
/// says so, and braking points and pickups say whether they were measured or
/// inferred.
List<String> variabilityLines(
  AppLocalizations l10n,
  CornerVariability variability,
  String speedUnit,
) {
  final unit = speedUnit.trim().isEmpty ? '' : ' ${speedUnit.trim()}';
  String? spread(String label, ConsistencySummary summary, String provenance) {
    if (summary.count == 0) return null;
    final tail = '${l10n.variabilityLaps(summary.count)} · $provenance';
    if (!summary.available) return l10n.variabilityTooFew(label, tail);
    return l10n.variabilitySpread(
      label,
      '${fixed(summary.interquartileRange!, 1)} m',
      tail,
    );
  }

  String? speed(String label, ConsistencySummary summary) {
    if (summary.count == 0) return null;
    final tail = l10n.variabilityLaps(summary.count);
    if (!summary.available) return l10n.variabilityTooFew(label, tail);
    return l10n.variabilityTypical(
      label,
      '${fixed(summary.median!, 1)}$unit',
      '${fixed(summary.interquartileRange!, 1)}$unit',
      tail,
    );
  }

  final line = variability.lineOffset;
  final accuracy = variability.typicalGpsAccuracyMeters;
  return [
    ?spread(
      l10n.variabilityBraking,
      variability.brakingPointMeasured,
      l10n.variabilityMeasured,
    ),
    ?spread(
      l10n.variabilityBraking,
      variability.brakingPointInferred,
      l10n.variabilityInferred,
    ),
    ?speed(l10n.variabilityApex, variability.apexSpeed),
    ?speed(l10n.variabilityMinimum, variability.minimumSpeed),
    ?speed(l10n.variabilityExit, variability.exitSpeed),
    ?spread(
      l10n.variabilityPickup,
      variability.pickupMeasured,
      l10n.variabilityMeasured,
    ),
    ?spread(
      l10n.variabilityPickup,
      variability.pickupInferred,
      l10n.variabilityInferred,
    ),
    if (line.available)
      l10n.variabilityLine(
            fixed(line.interquartileRange!, 1),
            accuracy == null
                ? l10n.variabilityGpsUnknown
                : l10n.variabilityGpsAccuracy(
                    fixed(accuracy, accuracy < 1 ? 2 : 1),
                  ),
          ) +
          (variability.lineSpreadResolvable
              ? ''
              : l10n.variabilityLineUnresolved),
  ];
}

/// One corner's variability, folded to its name and first line.
class _VariabilityTile extends StatelessWidget {
  const _VariabilityTile({required this.name, required this.variability});

  final String name;
  final CornerVariability variability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final lines = variabilityLines(l10n, variability, speedUnitOf(context));
    return ExpansionTile(
      key: ValueKey('variability $name'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      expandedAlignment: Alignment.centerLeft,
      title: Text(name),
      subtitle: Text(
        lines.isEmpty ? l10n.variabilityNotMeasured : lines.first,
        style: theme.textTheme.bodySmall,
      ),
      children: [
        for (final line in lines.skip(1))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(line, style: theme.textTheme.bodySmall),
          ),
      ],
    );
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

/// Laps by segments: the lap column stays while the segments scroll
/// sideways on a phone.
class _SectorTable extends StatelessWidget {
  const _SectorTable({
    required this.result,
    required this.selected,
    required this.onSelect,
  });

  final DayTheoreticalBest result;
  final DayLapReference? selected;
  final ValueChanged<DayLapReference> onSelect;

  static const _lapWidth = 112.0, _timeWidth = 80.0, _cellWidth = 64.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final segments = result.segments;
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = theme.textTheme.labelMedium;
    Widget name(String text, {TextStyle? style}) => TableCellText(
      text,
      style: style ?? theme.textTheme.bodyMedium,
      alignment: Alignment.centerLeft,
      maxLines: 2,
    );
    return StickyTable(
      key: const ValueKey('sectorTable'),
      firstWidth: _lapWidth,
      cellWidths: [_timeWidth, for (final _ in segments) _cellWidth],
      headerHeight: 44,
      header: StickyRow(
        first: name('Lap', style: label),
        cells: [
          TableCellText('Time', style: label),
          // The full name, on two lines: there is no hover to explain a
          // short one.
          for (final segment in segments)
            TableCellText(segment.name, style: label, maxLines: 2),
        ],
      ),
      rows: [
        for (final lap in result.laps)
          StickyRow(
            key: ValueKey('sectorRow ${lap.lap.displayName}'),
            onTap: () => onSelect(lap.lap.reference),
            color: lap.lap.reference == selected
                ? scheme.secondaryContainer
                : null,
            first: name(
              '${lap.lap.displayName}${lap.bestOfDay ? ' · best' : ''}',
            ),
            cells: [
              TableCellText(
                displayTime(lap.lap.durationSeconds),
                style: numbers,
              ),
              for (var i = 0; i < segments.length; ++i)
                _fastest(lap, i)
                    ? TableCellText(
                        lap.seconds(i)!.toStringAsFixed(3),
                        style: numbers?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                        color: scheme.primaryContainer,
                      )
                    : TableCellText(
                        lap.seconds(i)?.toStringAsFixed(3) ?? '—',
                        style: numbers,
                      ),
            ],
          ),
      ],
      footer: StickyRow(
        first: name('Fastest', style: label),
        cells: [
          TableCellText(
            result.theoreticalBestSeconds == null
                ? '—'
                : displayTime(result.theoreticalBestSeconds!),
            style: numbers?.copyWith(fontWeight: FontWeight.bold),
          ),
          for (final segment in segments)
            TableCellText(
              segment.seconds?.toStringAsFixed(3) ?? '—',
              style: numbers?.copyWith(fontWeight: FontWeight.bold),
            ),
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
