import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import 'comparison_page.dart';
import 'corner_details.dart' show cornerReasonText, lapAColor, lapBColor;
import 'day_results_controller.dart';
import 'telemetry_chart.dart' show ChartWindow;

/// The Corner Analyzer under a comparison's charts (registered in
/// [comparisonPanels]).
Widget? cornerAnalyzerPanel(
  BuildContext context,
  ComparisonPanelContext panel,
) => CornerAnalyzerPanel(key: const ValueKey('cornerAnalyzer'), panel: panel);

/// Overlays' Corner Analyzer for laps A and B: the approved segments both
/// share, and for the chosen one A, B and Δ (A − B) of the sector time,
/// speeds, braking point, throttle pickup and heart rate, with a chart of
/// both laps' speed through it. Choosing a segment zooms the charts to it
/// and puts the cursor in its middle.
class CornerAnalyzerPanel extends StatefulWidget {
  const CornerAnalyzerPanel({super.key, required this.panel});

  final ComparisonPanelContext panel;

  @override
  State<CornerAnalyzerPanel> createState() => _CornerAnalyzerPanelState();
}

/// The segment's length on an axis of [axisLength] metres, also across
/// start/finish.
double segmentLengthMeters(ComparisonSegment segment, double axisLength) {
  final length = segment.endMeters - segment.startMeters;
  return length >= 0 ? length : length + axisLength;
}

String _segmentLabel(ComparisonSegment segment, double axisLength) =>
    '${segment.name} · ${segment.type} · '
    '${segmentLengthMeters(segment, axisLength).round()} m';

class _CornerAnalyzerPanelState extends State<CornerAnalyzerPanel> {
  String? _selected;
  bool _focusApplied = false;

  ComparisonPanelContext get _panel => widget.panel;

  void _select(ComparisonSegment segment, {bool scroll = false}) {
    setState(() => _selected = segment.id);
    _show(segment);
    if (scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 250),
          );
        }
      });
    }
  }

  // Zooms the shared charts to [segment] with the cursor in its middle; a
  // segment across start/finish only moves the cursor to its start.
  void _show(ComparisonSegment segment) {
    final window = _panel.window;
    if (segment.endMeters > segment.startMeters) {
      window.focus(segment.startMeters, segment.endMeters);
      window.cursor.value = (segment.startMeters + segment.endMeters) / 2;
    } else {
      window.cursor.value = segment.startMeters;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _panel.controller,
    builder: (context, _) {
      final view = _panel.controller.cornerAnalyzer(
        _panel.a,
        _panel.b,
        fromTheoreticalBest: _panel.fromTheoreticalBest,
      );
      if (view == null) return const SizedBox.shrink();
      return _content(context, view);
    },
  );

  Widget _content(BuildContext context, DayCornerAnalyzer view) {
    final theme = Theme.of(context);
    final analyzer = view.analyzer;
    final segments = analyzer.segments;
    final length = analyzer.axisLengthMeters;
    ComparisonSegment? selected = analyzer.segment(_selected ?? '');
    if (selected == null && segments.isNotEmpty) {
      final requested = _focusApplied
          ? null
          : analyzer.segment(_panel.focusSegmentId ?? '');
      if (requested != null) {
        _focusApplied = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _select(requested, scroll: true);
        });
      }
      selected = requested ?? segments.first;
      _selected = selected.id;
    }
    final index = selected == null ? -1 : segments.indexOf(selected);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Corner Analyzer', style: theme.textTheme.titleMedium),
            if (view.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  view.note,
                  key: const ValueKey('cornerAnalyzerNote'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            if (segments.isEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'No matching approved segments for these two laps. Approve '
                'the same track segmentation on both to use the Corner '
                'Analyzer.',
                key: ValueKey('cornerAnalyzerEmpty'),
              ),
              if (view.theoreticalBestAvailable &&
                  _panel.useTheoreticalBest != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    key: const ValueKey('cornerAnalyzerUseTheoreticalBest'),
                    onPressed: _panel.useTheoreticalBest,
                    child: const Text('Use the theoretical best’s segments'),
                  ),
                ),
            ] else if (selected != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('cornerAnalyzerPrevious'),
                    tooltip: 'Previous segment',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: index > 0
                        ? () => _select(segments[index - 1])
                        : null,
                  ),
                  Expanded(
                    child: DropdownButton<String>(
                      key: const ValueKey('cornerAnalyzerSegmentPicker'),
                      isExpanded: true,
                      value: selected.id,
                      items: [
                        for (final segment in segments)
                          DropdownMenuItem(
                            value: segment.id,
                            child: Text(
                              _segmentLabel(segment, length),
                              key: ValueKey(
                                'cornerAnalyzerSegment ${segment.name}',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        final segment = analyzer.segment(id ?? '');
                        if (segment != null) _select(segment);
                      },
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('cornerAnalyzerNext'),
                    tooltip: 'Next segment',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: index + 1 < segments.length
                        ? () => _select(segments[index + 1])
                        : null,
                  ),
                ],
              ),
              ..._segment(context, analyzer, selected),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _segment(
    BuildContext context,
    CornerAnalyzer analyzer,
    ComparisonSegment segment,
  ) {
    final theme = Theme.of(context);
    final analysis = analyzer.analyze(segment.id);
    final heartRate = segment.endMeters == segment.startMeters
        ? null
        : analyzer.heartRate(segment.startMeters, segment.endMeters);
    return [
      if (analysis != null && segment.endMeters > segment.startMeters)
        SegmentSpeedChart(
          key: const ValueKey('cornerAnalyzerChart'),
          comparison: _panel.comparison,
          analysis: analysis,
          window: _panel.window,
        ),
      if (analysis == null)
        const Text('No figures for this segment.')
      else
        AnalyzerTable(analysis: analysis, heartRate: heartRate),
      const SizedBox(height: 4),
      if (analysis?.braking != null || analysis?.exitEffects != null)
        Text(
          'Braking point and throttle pickup are positions along the lap '
          '(m). Δ positive: A later.',
          style: theme.textTheme.bodySmall,
        ),
      if (heartRate != null && heartRate.laps.any((lap) => lap.valid))
        Text(
          'Heart rate: mean over this segment · A '
          '${_coverage(heartRate.laps[0])} · B ${_coverage(heartRate.laps[1])}. '
          'Observed values only.',
          key: const ValueKey('cornerAnalyzerHeartRateNote'),
          style: theme.textTheme.bodySmall,
        ),
      Text(
        'Δ is A − B. Observed differences, not instructions.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (segment.endMeters > segment.startMeters)
            OutlinedButton.icon(
              key: const ValueKey('cornerAnalyzerZoom'),
              icon: const Icon(Icons.center_focus_strong_outlined),
              label: const Text('Zoom to segment'),
              onPressed: () => _show(segment),
            ),
          for (final slot in const [0, 1])
            TextButton.icon(
              key: ValueKey('cornerAnalyzerOpenLap${slot == 0 ? 'A' : 'B'}'),
              icon: const Icon(Icons.open_in_new),
              label: Text('Lap ${slot == 0 ? 'A' : 'B'} here'),
              onPressed: () => _panel.openLap(slot, segment.startMeters),
            ),
        ],
      ),
    ];
  }
}

String _coverage(HeartRateLap lap) {
  final summary = lap.summary;
  if (!lap.valid) {
    return summary.unavailableReason == 'channelMissing'
        ? 'not recorded'
        : 'no valid samples';
  }
  return '${summary.sampleCount} samples, '
      '${(summary.coverage * 100).round()}% covered';
}

String _signed(double value, int digits, String unit) {
  final text = value.abs().toStringAsFixed(digits);
  if (double.parse(text) == 0) return '±$text$unit';
  return '${value > 0 ? '+' : '−'}$text$unit';
}

/// One row of the table: how to show its values.
typedef _Row = ({
  String id,
  String label,
  AnalyzerMetric metric,
  String Function(double value) value,
  String Function(double delta) delta,
});

/// A, B and Δ (A − B) of a segment's figures. A missing value says why; a
/// value inferred from another channel says so.
class AnalyzerTable extends StatelessWidget {
  const AnalyzerTable({super.key, required this.analysis, this.heartRate});

  final SegmentAnalysis analysis;
  final ComparisonHeartRate? heartRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final small = theme.textTheme.bodySmall;
    String speed(String unit) => unit.trim().isEmpty ? '' : ' ${unit.trim()}';
    final rows = <_Row>[
      if (analysis.sectorTime case final metric?)
        (
          id: 'sectorTime',
          label: 'Sector time',
          metric: metric,
          value: displayTime,
          delta: displayDelta,
        ),
      if (analysis.corner case final corner?)
        for (final (id, label, metric) in [
          ('entry', 'Entry speed', corner.entry),
          ('apex', 'Apex speed', corner.apex),
          ('minimum', 'Minimum speed', corner.minimum),
          ('exit', 'Exit speed', corner.exit),
        ])
          (
            id: id,
            label: label,
            metric: metric,
            value: (v) => '${v.toStringAsFixed(1)}${speed(corner.unit)}',
            delta: (d) => _signed(d, 1, ''),
          )
      else
        for (final (id, label, metric) in [
          ('entry', 'Entry speed', analysis.speeds.entry),
          ('maximum', 'Top speed', analysis.speeds.maximum),
          ('minimum', 'Lowest speed', analysis.speeds.minimum),
          ('exit', 'Exit speed', analysis.speeds.exit),
        ])
          (
            id: id,
            label: label,
            metric: metric,
            value: (v) =>
                '${v.toStringAsFixed(1)}${speed(analysis.speeds.unit)}',
            delta: (d) => _signed(d, 1, ''),
          ),
      if (analysis.braking case final braking?)
        (
          id: 'brakingPoint',
          label: 'Braking point',
          metric: braking.point,
          value: (v) => '${v.toStringAsFixed(1)} m',
          delta: (d) => _signed(d, 1, ' m'),
        ),
      if (analysis.exitEffects case final exit?)
        (
          id: 'pickup',
          label: 'Throttle pickup',
          metric: exit.pickup,
          value: (v) => '${v.toStringAsFixed(1)} m',
          delta: (d) => _signed(d, 1, ' m'),
        ),
    ];

    Widget cell(String key, String text, String note, {bool strong = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                text,
                key: ValueKey('cornerAnalyzer $key'),
                style: strong
                    ? numbers?.copyWith(fontWeight: FontWeight.w600)
                    : numbers,
                textAlign: TextAlign.end,
              ),
              if (note.isNotEmpty)
                Text(
                  note,
                  key: ValueKey('cornerAnalyzer $key note'),
                  style: small,
                  textAlign: TextAlign.end,
                ),
            ],
          ),
        );

    Widget side(String key, AnalyzerValue side, String Function(double) show) {
      final value = side.value;
      if (value == null) {
        return cell(key, '—', cornerReasonText(side.unavailableReason));
      }
      return cell(
        key,
        show(value),
        side.provenance == metricInferred ? 'inferred' : '',
      );
    }

    Widget delta(
      String key,
      AnalyzerDelta delta,
      String Function(double) show,
    ) {
      final value = delta.value;
      return value == null
          ? cell(
              key,
              '—',
              delta.unavailableReason.isEmpty
                  ? ''
                  : cornerReasonText(delta.unavailableReason),
            )
          : cell(key, show(value), '', strong: true);
    }

    Widget label(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text),
    );

    Widget heading(String text, Color? color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (color != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(child: Text(text, style: theme.textTheme.titleSmall)),
        ],
      ),
    );

    final laps = heartRate?.laps ?? const <HeartRateLap>[];
    final heartRateShown = laps.length == 2 && laps.any((lap) => lap.valid);
    String bpm(HeartRateLap lap) =>
        lap.valid ? '${lap.summary.mean!.toStringAsFixed(0)} bpm' : '—';

    return Table(
      key: const ValueKey('cornerAnalyzerTable'),
      columnWidths: const {
        0: FlexColumnWidth(1.3),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            heading('A', lapAColor),
            heading('B', lapBColor),
            heading('Δ A − B', null),
          ],
        ),
        for (final row in rows)
          TableRow(
            key: ValueKey('cornerAnalyzerRow ${row.id}'),
            children: [
              label(row.label),
              side('${row.id} A', row.metric.a, row.value),
              side('${row.id} B', row.metric.b, row.value),
              delta('${row.id} Δ', row.metric.delta, row.delta),
            ],
          ),
        if (heartRateShown)
          TableRow(
            key: const ValueKey('cornerAnalyzerRow heartRate'),
            children: [
              label('Heart rate'),
              cell('heartRate A', bpm(laps[0]), ''),
              cell('heartRate B', bpm(laps[1]), ''),
              laps[0].valid && laps[1].valid
                  ? cell(
                      'heartRate Δ',
                      _signed(
                        laps[0].summary.mean! - laps[1].summary.mean!,
                        0,
                        ' bpm',
                      ),
                      '',
                      strong: true,
                    )
                  : cell('heartRate Δ', '—', ''),
            ],
          ),
      ],
    );
  }
}

/// Both laps' speed through a segment and a little before it, on the shared
/// axis: the segment shaded, its apex marked, each lap's braking point drawn
/// as an upward triangle, its throttle pickup as a diamond and its lowest
/// speed as a dot. A tap or a drag moves the shared cursor.
class SegmentSpeedChart extends StatelessWidget {
  const SegmentSpeedChart({
    super.key,
    required this.comparison,
    required this.analysis,
    required this.window,
    this.height = 140,
  });

  final LapComparison comparison;
  final SegmentAnalysis analysis;
  final ChartWindow window;
  final double height;

  /// The progress range drawn: the segment, its braking points and pickups,
  /// and a margin, within the axis.
  (double, double) get range {
    final segment = analysis.segment;
    var start = segment.startMeters, end = segment.endMeters;
    for (final braking in analysis.brakingMetrics ?? const <BrakingMetrics>[]) {
      if (braking.brakingPointMeters case final point?) {
        start = math.min(start, point);
      }
    }
    for (final exit in analysis.exitMetrics ?? const <ExitMetrics>[]) {
      if (exit.pickup.progressMeters case final point?) {
        end = math.max(end, point);
      }
    }
    final margin = math.max(10.0, (end - start) * 0.1);
    return (
      math.max(0.0, start - margin),
      math.min(comparison.axisLengthMeters, end + margin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (start, end) = range;
    final series = [
      for (final slot in const [0, 1])
        comparison.channelSeries(slot, 'speed', start, end, 200),
    ];
    final markers = _markers();
    final unit = series
        .firstWhere((series) => series.hasData, orElse: () => series.first)
        .unit;
    void move(double dx, double width) {
      if (width <= 0) return;
      window.cursor.value = start + (end - start) * (dx / width).clamp(0, 1);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            series.any((series) => series.hasData)
                ? 'Speed${unit.trim().isEmpty ? '' : ' (${unit.trim()})'} '
                      'through ${analysis.segment.name}'
                : 'No speed recorded on either lap through '
                      '${analysis.segment.name}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  move(details.localPosition.dx, constraints.maxWidth),
              onHorizontalDragUpdate: (details) =>
                  move(details.localPosition.dx, constraints.maxWidth),
              child: ValueListenableBuilder<double>(
                valueListenable: window.cursor,
                builder: (context, cursor, _) => CustomPaint(
                  size: Size(constraints.maxWidth, height),
                  painter: _SegmentSpeedPainter(
                    start: start,
                    end: end,
                    segmentStart: analysis.segment.startMeters,
                    segmentEnd: analysis.segment.endMeters,
                    series: series,
                    markers: markers,
                    apex: analysis.phases?.apex.resolved ?? false
                        ? analysis.phases!.apex.progressMeters
                        : null,
                    cursor: cursor,
                    grid: theme.colorScheme.outlineVariant,
                    shade: theme.colorScheme.primary.withValues(alpha: 0.08),
                    ink: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          '▲ braking point · ◆ throttle pickup · ● lowest speed'
          '${analysis.phases?.apex.resolved ?? false ? ' · ┆ apex' : ''}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  List<_Marker> _markers() {
    final markers = <_Marker>[];
    for (final slot in const [0, 1]) {
      final color = slot == 0 ? lapAColor : lapBColor;
      final braking = analysis.brakingMetrics?[slot].brakingPointMeters;
      if (braking != null) {
        markers.add((
          kind: _MarkerKind.braking,
          at: braking,
          value: null,
          color: color,
        ));
      }
      final pickup = analysis.exitMetrics?[slot].pickup.progressMeters;
      if (pickup != null) {
        markers.add((
          kind: _MarkerKind.pickup,
          at: pickup,
          value: null,
          color: color,
        ));
      }
      final minimum = analysis.cornerSpeeds?[slot].minimum;
      if (minimum != null && minimum.value != null) {
        markers.add((
          kind: _MarkerKind.minimum,
          at: minimum.progressMeters,
          value: minimum.value,
          color: color,
        ));
      }
    }
    return markers;
  }
}

enum _MarkerKind { braking, pickup, minimum }

typedef _Marker = ({_MarkerKind kind, double at, double? value, Color color});

class _SegmentSpeedPainter extends CustomPainter {
  _SegmentSpeedPainter({
    required this.start,
    required this.end,
    required this.segmentStart,
    required this.segmentEnd,
    required this.series,
    required this.markers,
    required this.apex,
    required this.cursor,
    required this.grid,
    required this.shade,
    required this.ink,
  });

  final double start;
  final double end;
  final double segmentStart;
  final double segmentEnd;
  final List<ChartSeries> series;
  final List<_Marker> markers;
  final double? apex;
  final double cursor;
  final Color grid;
  final Color shade;
  final Color ink;

  static const _markerBand = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final span = math.max(1e-9, end - start);
    final plotHeight = size.height - _markerBand;
    double x(double meters) => (meters - start) / span * size.width;

    // The segment itself.
    canvas.drawRect(
      Rect.fromLTRB(x(segmentStart), 0, x(segmentEnd), plotHeight),
      Paint()..color = shade,
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, plotHeight),
      Offset(size.width, plotHeight),
      gridPaint,
    );
    for (final edge in [segmentStart, segmentEnd]) {
      canvas.drawLine(
        Offset(x(edge), 0),
        Offset(x(edge), plotHeight),
        gridPaint,
      );
    }

    // The value axis: both laps' speeds, with a margin.
    var low = double.infinity, high = -double.infinity;
    for (final line in series) {
      for (final part in line.segments) {
        for (final point in part) {
          low = math.min(low, point.y);
          high = math.max(high, point.y);
        }
      }
    }
    if (low.isFinite && high.isFinite) {
      final pad = math.max(1.0, (high - low) * 0.1);
      low -= pad;
      high += pad;
      double y(double value) =>
          plotHeight - (value - low) / (high - low) * plotHeight;
      for (var slot = 0; slot < series.length; ++slot) {
        final paint = Paint()
          ..color = slot == 0 ? lapAColor : lapBColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        for (final part in series[slot].segments) {
          if (part.isEmpty) continue;
          final path = Path()..moveTo(x(part.first.x), y(part.first.y));
          for (final point in part.skip(1)) {
            path.lineTo(x(point.x), y(point.y));
          }
          canvas.drawPath(path, paint);
        }
      }
      for (final marker in markers) {
        if (marker.kind == _MarkerKind.minimum && marker.value != null) {
          canvas.drawCircle(
            Offset(x(marker.at), y(marker.value!)),
            4,
            Paint()..color = marker.color,
          );
        }
      }
    }

    // The apex: a dashed line.
    if (apex case final at?) {
      final paint = Paint()
        ..color = ink
        ..strokeWidth = 1;
      for (var top = 0.0; top < plotHeight; top += 6) {
        canvas.drawLine(
          Offset(x(at), top),
          Offset(x(at), math.min(plotHeight, top + 3)),
          paint,
        );
      }
    }

    // Braking points point up; pickups are diamonds, A above B.
    for (final marker in markers) {
      final paint = Paint()..color = marker.color;
      final cx = x(marker.at);
      final base = size.height - 2;
      switch (marker.kind) {
        case _MarkerKind.braking:
          canvas.drawPath(
            Path()
              ..moveTo(cx, base - 11)
              ..lineTo(cx - 6, base)
              ..lineTo(cx + 6, base)
              ..close(),
            paint,
          );
        case _MarkerKind.pickup:
          final cy = base - 6;
          canvas.drawPath(
            Path()
              ..moveTo(cx, cy - 6)
              ..lineTo(cx + 5, cy)
              ..lineTo(cx, cy + 6)
              ..lineTo(cx - 5, cy)
              ..close(),
            paint,
          );
        case _MarkerKind.minimum:
          break;
      }
    }

    // The shared cursor.
    if (cursor >= start && cursor <= end) {
      canvas.drawLine(
        Offset(x(cursor), 0),
        Offset(x(cursor), plotHeight),
        Paint()
          ..color = ink
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentSpeedPainter old) =>
      old.cursor != cursor ||
      old.start != start ||
      old.end != end ||
      !identical(old.series, series) ||
      old.grid != grid;
}
