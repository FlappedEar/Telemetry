import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import 'corner_details.dart' show lapAColor, lapBColor;
import 'day_results_controller.dart';
import 'lap_page.dart';
import 'telemetry_chart.dart';

/// A panel under a comparison's charts. Where later analyses of a pair plug
/// in (the corner analyzer, FET-38; G-G and driving states, FET-39): each
/// gets the comparison and its shared cursor and range, and returns null
/// when it has nothing to show.
typedef ComparisonPanelBuilder = Widget? Function(
  BuildContext context,
  LapComparison comparison,
  ChartWindow window,
);

/// The extra panels of every comparison page, in order. None yet.
final List<ComparisonPanelBuilder> comparisonPanels = [];

/// Asks for a lap of [candidates]; [suggested] is offered first.
Future<DayLapRow?> pickComparisonLap(
  BuildContext context, {
  required String title,
  required List<DayLapRow> candidates,
  DayLapRow? suggested,
}) => showDialog<DayLapRow>(
  context: context,
  builder: (context) {
    final theme = Theme.of(context);
    Widget option(DayLapRow row, {bool best = false}) => ListTile(
      key: ValueKey('${best ? 'suggestedLap' : 'pickLap'} ${row.displayName}'),
      leading: best ? const Icon(Icons.emoji_events_outlined) : null,
      title: Text(row.displayName),
      subtitle: best ? const Text('Suggested: the fastest') : null,
      trailing: Text(
        displayTime(row.durationSeconds),
        style: theme.textTheme.titleSmall,
      ),
      onTap: () => Navigator.pop(context, row),
    );
    return SimpleDialog(
      title: Text(title),
      children: [
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('No other ranked lap of this group to compare with.'),
          ),
        if (suggested != null) option(suggested, best: true),
        for (final row in candidates) option(row),
      ],
    );
  },
);

/// Two laps of one group, A (green) against B (orange), on a shared
/// track-position axis: the Δ time (A − B, positive when A is behind), the
/// channels of both laps, and both lines on one map, optionally coloured by
/// a recorded value. A drag on a chart moves one cursor, shown on the map
/// for both laps.
class ComparisonPage extends StatefulWidget {
  const ComparisonPage({
    super.key,
    required this.controller,
    required this.a,
    required this.b,
    this.focus,
  });

  final DayResultsController controller;
  final DayLapRow a;
  final DayLapRow b;

  /// A stretch of lap A to show first, in its recording time (such as a
  /// time loss's segment); the whole lap when null.
  final (double, double)? focus;

  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

/// The text for an unavailable map layer, as Overlays words it.
String mapLayerUnavailableText(
  MapLayerOption? option,
  ComparisonMapLayer layer,
) {
  if (layer.valid) return '';
  final lap = layer.slot == 0 ? 'A' : 'B';
  if (option != null && !option.available) return 'Not recorded on either lap.';
  return switch (layer.reason) {
    'channelMissing' => 'Not recorded on lap $lap.',
    'noSamples' => 'No usable samples on lap $lap.',
    _ => 'No shared track position for this pair.',
  };
}

class _ComparisonPageState extends State<ComparisonPage> {
  late DayLapRow _a = widget.a, _b = widget.b;
  LapComparison? _comparison;
  ChartWindow? _window;
  List<String> _channels = const [];
  String _layerId = '';
  int _layerSlot = 1;

  (double, double)? _seriesRange;
  final Map<String, ChartSeries> _series = {};
  final Map<String, (double, double)> _axes = {};
  final Map<(String, int), ComparisonMapLayer> _layers = {};

  @override
  void initState() {
    super.initState();
    _pair(focus: widget.focus);
  }

  @override
  void dispose() {
    _window?.dispose();
    super.dispose();
  }

  void _pair({(double, double)? focus}) {
    final previous = _comparison == null ? null : _channels;
    _window?.dispose();
    _window = null;
    _series.clear();
    _seriesRange = null;
    _axes.clear();
    _layers.clear();
    final comparison = _comparison = widget.controller.comparison(_a, _b);
    if (comparison == null || !comparison.axis.valid) {
      _channels = const [];
      return;
    }
    final window = _window = ChartWindow(0, comparison.axisLengthMeters);
    final available = comparison.chartChannels;
    final kept = [
      for (final channel in previous ?? const <String>[])
        if (available.contains(channel)) channel,
    ];
    _channels = kept.isNotEmpty ? kept : comparison.defaultChartChannels;
    if (focus != null) {
      final trace = comparison.trace(0);
      final start = progressAtTime(trace, focus.$1);
      final end = progressAtTime(trace, focus.$2);
      if (start != null && end != null && end > start) {
        window.focus(start, end);
        window.cursor.value = start;
      }
    }
  }

  void _setPair(DayLapRow a, DayLapRow b) {
    if (a.reference == b.reference) return;
    setState(() {
      _a = a;
      _b = b;
      _pair();
    });
  }

  Future<void> _change(int slot) async {
    final controller = widget.controller;
    final current = slot == 0 ? _a : _b, other = slot == 0 ? _b : _a;
    final picked = await pickComparisonLap(
      context,
      title: 'Lap ${slot == 0 ? 'A' : 'B'}',
      candidates: [
        for (final row in controller.comparisonCandidates(other))
          if (row.reference != other.reference &&
              row.reference != current.reference)
            row,
      ],
    );
    if (picked == null || !mounted) return;
    slot == 0 ? _setPair(picked, _b) : _setPair(_a, picked);
  }

  void _bestAsB({required bool sameRun}) {
    final best = widget.controller.comparisonPartner(_a, sameRun: sameRun);
    if (best != null) _setPair(_a, best);
  }

  void _openLap(int slot) {
    final comparison = _comparison, window = _window;
    if (comparison == null || window == null) return;
    final row = slot == 0 ? _a : _b;
    final time = comparison.timeAt(slot, window.cursor.value);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LapPage(
          controller: widget.controller,
          row: row,
          initialCursor: time,
        ),
      ),
    );
  }

  ChartSeries _seriesOf(int slot, String channel, (double, double) range) {
    if (_seriesRange != range) {
      _seriesRange = range;
      _series.clear();
    }
    final comparison = _comparison!;
    return _series['$slot|$channel'] ??= channel == deltaTimeChannel
        ? comparison.deltaSeries(range.$1, range.$2, 600)
        : comparison.channelSeries(slot, channel, range.$1, range.$2, 600);
  }

  (double, double) _axisOf(String channel) {
    final comparison = _comparison!;
    final length = comparison.axisLengthMeters;
    return _axes[channel] ??= channel == deltaTimeChannel
        ? chartValueAxis([
            comparison.deltaSeries(0, length, 300),
          ], zeroLine: true)
        : chartValueAxis([
            comparison.channelSeries(0, channel, 0, length, 300),
            comparison.channelSeries(1, channel, 0, length, 300),
          ]);
  }

  ComparisonMapLayer? get _layer => _layerId.isEmpty || _comparison == null
      ? null
      : _layers[(_layerId, _layerSlot)] ??= _comparison!.mapLayer(
          _layerId,
          _layerSlot,
        );

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final delta = _a.durationSeconds - _b.durationSeconds;
    Widget badge(int slot) {
      final row = slot == 0 ? _a : _b;
      final color = slot == 0 ? lapAColor : lapBColor;
      return InkWell(
        key: ValueKey('comparisonLap${slot == 0 ? 'A' : 'B'}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _change(slot),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${slot == 0 ? 'A' : 'B'} · ${row.displayName}',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(displayTime(row.durationSeconds)),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.edit_outlined,
                size: 18,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, runSpacing: 4, children: [badge(0), badge(1)]),
        const SizedBox(height: 4),
        Text(
          'Lap Δ ${displayDelta(delta)}',
          key: const ValueKey('comparisonLapDelta'),
          style: theme.textTheme.titleLarge,
        ),
        Text(
          'Δ is A − B: positive when A is behind.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('comparisonSwap'),
              onPressed: () => _setPair(_b, _a),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Swap A and B'),
            ),
            OutlinedButton(
              key: const ValueKey('comparisonBestOfRun'),
              onPressed: () => _bestAsB(sameRun: true),
              child: Text('B: best of ${_a.runName}'),
            ),
            OutlinedButton(
              key: const ValueKey('comparisonBestOfDay'),
              onPressed: () => _bestAsB(sameRun: false),
              child: const Text('B: best of the day'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _map(BuildContext context, double height) {
    final comparison = _comparison!;
    final theme = Theme.of(context);
    final options = comparison.mapLayerOptions;
    final layer = _layer;
    MapLayerOption? option;
    for (final candidate in options) {
      if (candidate.id == _layerId) option = candidate;
    }
    final unavailable = layer == null
        ? ''
        : mapLayerUnavailableText(option, layer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                key: const ValueKey('comparisonMapLayerPicker'),
                isExpanded: true,
                value: _layerId,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Line: A / B')),
                  for (final option in options)
                    DropdownMenuItem(
                      value: option.id,
                      child: Text(
                        option.available
                            ? option.label
                            : '${option.label} · not recorded',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _layerId = id ?? ''),
              ),
            ),
            if (_layerId.isNotEmpty) ...[
              const SizedBox(width: 8),
              SegmentedButton<int>(
                key: const ValueKey('comparisonMapLayerSlot'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('A')),
                  ButtonSegment(value: 1, label: Text('B')),
                ],
                selected: {_layerSlot},
                onSelectionChanged: (slot) =>
                    setState(() => _layerSlot = slot.first),
              ),
            ],
          ],
        ),
        SizedBox(
          height: height,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _OverlayMap(
              key: const ValueKey('comparisonMap'),
              comparison: comparison,
              layer: layer != null && layer.valid ? layer : null,
              window: _window!,
            ),
          ),
        ),
        if (layer != null) ...[
          if (unavailable.isNotEmpty)
            Text(
              unavailable,
              key: const ValueKey('comparisonMapLayerUnavailable'),
              style: theme.textTheme.bodySmall,
            )
          else
            _LayerLegend(layer: layer),
        ],
      ],
    );
  }

  List<Widget> _charts(BuildContext context) {
    final theme = Theme.of(context);
    final comparison = _comparison!;
    final window = _window!;
    return [
      Text('Channels by track position', style: theme.textTheme.titleMedium),
      Text(
        'Both laps at the same place on the track. Drag across a chart to '
        'move the cursor; the dots show both laps on the map.',
        style: theme.textTheme.bodySmall,
      ),
      ChartWindowControls(
        window: window,
        axisText: (meters) => '${meters.round()} m',
      ),
      ValueListenableBuilder(
        valueListenable: window.range,
        builder: (context, range, _) => Column(
          children: [
            for (final channel in _channels)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: channel == deltaTimeChannel
                    ? TelemetryChart(
                        key: ValueKey('comparisonChart $channel'),
                        title: 'Δ time (A − B)',
                        lines: [
                          ChartLine(
                            '',
                            _seriesOf(0, channel, range),
                            deltaLineColor,
                          ),
                        ],
                        start: range.$1,
                        end: range.$2,
                        cursor: window.cursor,
                        onCursor: (value) => window.cursor.value = value,
                        valueAxis: _axisOf(channel),
                        zeroLine: true,
                        delta: true,
                        note: '+ = A behind',
                        onRemove: () => _remove(channel),
                      )
                    : TelemetryChart(
                        key: ValueKey('comparisonChart $channel'),
                        title: channel,
                        lines: [
                          ChartLine(
                            'A',
                            _seriesOf(0, channel, range),
                            lapAColor,
                          ),
                          ChartLine(
                            'B',
                            _seriesOf(1, channel, range),
                            lapBColor,
                          ),
                        ],
                        start: range.$1,
                        end: range.$2,
                        cursor: window.cursor,
                        onCursor: (value) => window.cursor.value = value,
                        valueAxis: _axisOf(channel),
                        onRemove: () => _remove(channel),
                      ),
              ),
          ],
        ),
      ),
      AddChannelButton(
        channels: comparison.chartChannels,
        shown: _channels,
        onAdd: (channel) => setState(() => _channels = [..._channels, channel]),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final slot in const [0, 1])
            TextButton.icon(
              key: ValueKey('comparisonOpenLap${slot == 0 ? 'A' : 'B'}'),
              icon: const Icon(Icons.open_in_new),
              label: Text('Open lap ${slot == 0 ? 'A' : 'B'} here'),
              onPressed: () => _openLap(slot),
            ),
        ],
      ),
      for (final builder in comparisonPanels)
        ?builder(context, comparison, window),
      const SizedBox(height: 8),
      Text(
        'Observed differences between two laps, not instructions.',
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  void _remove(String channel) => setState(
    () => _channels = [
      for (final shown in _channels)
        if (shown != channel) shown,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final comparison = _comparison;
    final ready = comparison != null && comparison.axis.valid;
    return Scaffold(
      appBar: AppBar(title: const Text('Compare laps')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final header = _header(context);
          if (!ready) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                header,
                const SizedBox(height: 16),
                Text(
                  comparison == null
                      ? 'The recordings of these laps are not available.'
                      : 'No shared track position for this pair.',
                  key: const ValueKey('comparisonUnavailable'),
                ),
              ],
            );
          }
          if (constraints.maxWidth >= 900) {
            final mapHeight = (constraints.maxHeight * 0.6).clamp(260.0, 560.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: ListView(
                    key: const ValueKey('comparisonSummary'),
                    padding: const EdgeInsets.all(16),
                    children: [
                      header,
                      const SizedBox(height: 12),
                      _map(context, mapHeight),
                    ],
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: ListView(
                    key: const ValueKey('comparisonCharts'),
                    padding: const EdgeInsets.all(16),
                    children: _charts(context),
                  ),
                ),
              ],
            );
          }
          final mapHeight = math.min(
            (constraints.maxWidth - 32).clamp(220.0, 420.0),
            math.max(220.0, constraints.maxHeight - 48),
          );
          return ListView(
            key: const ValueKey('comparisonSummary'),
            padding: const EdgeInsets.all(16),
            children: [
              header,
              const SizedBox(height: 12),
              _map(context, mapHeight),
              const SizedBox(height: 16),
              ..._charts(context),
            ],
          );
        },
      ),
    );
  }
}

/// Sequential: one blue hue, dim to bright. Diverging: blue, grey at zero,
/// amber, symmetric around zero so zero is always neutral.
const List<Color> sequentialLayerStops = [Color(0xFF28527A), Color(0xFFE3F4FF)];
const List<Color> divergingLayerStops = [
  Color(0xFF4F9DFF),
  Color(0xFF8B95A1),
  Color(0xFFFFAB40),
];

/// The colour scale of [layer]: its low and high ends.
(double, double) mapLayerRange(ComparisonMapLayer layer) {
  final minimum = layer.trace.minimum ?? 0, maximum = layer.trace.maximum ?? 0;
  if (layer.diverging) {
    final extent = math.max(math.max(minimum.abs(), maximum.abs()), 1e-9);
    return (-extent, extent);
  }
  return (minimum, math.max(maximum, minimum + 1e-9));
}

Color mapLayerColor(ComparisonMapLayer layer, double value) {
  final (low, high) = mapLayerRange(layer);
  final t = ((value - low) / (high - low)).clamp(0.0, 1.0);
  if (!layer.diverging) {
    return Color.lerp(sequentialLayerStops[0], sequentialLayerStops[1], t)!;
  }
  return t < 0.5
      ? Color.lerp(divergingLayerStops[0], divergingLayerStops[1], t * 2)!
      : Color.lerp(
          divergingLayerStops[1],
          divergingLayerStops[2],
          (t - 0.5) * 2,
        )!;
}

String mapLayerValueText(ComparisonMapLayer layer, double value) {
  final (low, high) = mapLayerRange(layer);
  final magnitude = math.max(low.abs(), high.abs());
  final digits = magnitude >= 100
      ? 0
      : magnitude >= 10
      ? 1
      : 2;
  return '${layer.diverging && value > 0 ? '+' : ''}${value.toStringAsFixed(digits)}';
}

class _LayerLegend extends StatelessWidget {
  const _LayerLegend({required this.layer});

  final ComparisonMapLayer layer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (low, high) = mapLayerRange(layer);
    final stops = layer.diverging ? divergingLayerStops : sequentialLayerStops;
    String end(double value, String label) =>
        '${mapLayerValueText(layer, value)}'
        '${layer.diverging && label.isNotEmpty ? ' $label' : ''}';
    return Column(
      key: const ValueKey('comparisonMapLegend'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(colors: stops),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                end(low, layer.negativeLabel),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(
                end(high, layer.positiveLabel),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          '${layer.label} · lap ${layer.slot == 0 ? 'A' : 'B'}'
          '${layer.unit.isEmpty ? '' : ' · ${layer.unit}'}'
          '${layer.provenance == 'calculated' ? ' · calculated' : ''}',
          key: const ValueKey('comparisonMapLegendSource'),
          style: theme.textTheme.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Both laps on one map to the same scale (the shared normalization), with
/// the zoom window highlighted on lap B and a marker per lap at the cursor.
/// The lines and the layer are drawn once; the range and the markers are
/// separate layers, repainted only when they change.
class _OverlayMap extends StatelessWidget {
  const _OverlayMap({
    super.key,
    required this.comparison,
    required this.layer,
    required this.window,
  });

  final LapComparison comparison;
  final ComparisonMapLayer? layer;
  final ChartWindow window;

  @override
  Widget build(BuildContext context) {
    final a = comparison.overlayTrack(0), b = comparison.overlayTrack(1);
    final theme = Theme.of(context);
    if (a.isEmpty && b.isEmpty) {
      return const Center(child: Text('No GPS data in this section'));
    }
    return Semantics(
      label: 'Laps A and B on one map',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(
            0.0,
            math.min(constraints.maxWidth, constraints.maxHeight) - 24,
          );
          return Center(
            child: SizedBox.square(
              dimension: side,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _TracksPainter(a: a, b: b, layer: layer),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RangePainter(
                        comparison: comparison,
                        window: window,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MarkersPainter(
                        comparison: comparison,
                        cursor: window.cursor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TracksPainter extends CustomPainter {
  _TracksPainter({required this.a, required this.b, required this.layer});

  final List<List<MapPoint>> a;
  final List<List<MapPoint>> b;
  final ComparisonMapLayer? layer;

  @override
  void paint(Canvas canvas, Size size) {
    final dimmed = layer != null;
    void trace(List<List<MapPoint>> segments, Color color) {
      final paint = Paint()
        ..color = dimmed ? color.withValues(alpha: 0.3) : color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final points in segments) {
        if (points.length < 2) continue;
        final path = Path()
          ..moveTo(points.first.x * size.width, points.first.y * size.height);
        for (final point in points.skip(1)) {
          path.lineTo(point.x * size.width, point.y * size.height);
        }
        canvas.drawPath(path, paint);
      }
    }

    trace(a, lapAColor);
    trace(b, lapBColor);
    final shown = layer;
    if (shown == null) return;
    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final polyline in shown.trace.polylines) {
      for (var i = 1; i < polyline.length; ++i) {
        final from = polyline[i - 1], to = polyline[i];
        paint.color = mapLayerColor(shown, (from.value + to.value) / 2);
        canvas.drawLine(
          Offset(from.x * size.width, from.y * size.height),
          Offset(to.x * size.width, to.y * size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TracksPainter old) =>
      !identical(old.a, a) || !identical(old.b, b) || old.layer != layer;
}

class _RangePainter extends CustomPainter {
  _RangePainter({
    required this.comparison,
    required this.window,
    required this.color,
  }) : super(repaint: window.range);

  final LapComparison comparison;
  final ChartWindow window;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!window.zoomed) return;
    final (start, end) = window.range.value;
    final step = math.max(2.0, (end - start) / 150);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    var path = Path();
    var drawing = false;
    for (var meters = start; meters <= end + 1e-6; meters += step) {
      final point = comparison.positionAt(1, math.min(meters, end));
      if (point == null) {
        // A gap on lap B ends the highlight; it is never bridged.
        if (drawing) canvas.drawPath(path, paint);
        path = Path();
        drawing = false;
        continue;
      }
      final x = point.x * size.width, y = point.y * size.height;
      drawing ? path.lineTo(x, y) : path.moveTo(x, y);
      drawing = true;
    }
    if (drawing) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.comparison != comparison ||
      old.window != window ||
      old.color != color;
}

class _MarkersPainter extends CustomPainter {
  _MarkersPainter({required this.comparison, required this.cursor})
    : super(repaint: cursor);

  final LapComparison comparison;
  final ValueListenable<double> cursor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final slot in const [0, 1]) {
      final point = comparison.positionAt(slot, cursor.value);
      if (point == null) continue;
      final centre = Offset(point.x * size.width, point.y * size.height);
      canvas
        ..drawCircle(centre, 8, Paint()..color = const Color(0xFF0C150F))
        ..drawCircle(
          centre,
          6,
          Paint()..color = slot == 0 ? lapAColor : lapBColor,
        );
    }
  }

  @override
  bool shouldRepaint(_MarkersPainter old) =>
      old.comparison != comparison || old.cursor != cursor;
}
