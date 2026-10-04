import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import '../units.dart';
import 'apple_map.dart';
import 'corner_analyzer_panel.dart';
import 'corner_details.dart' show lapAColor, lapBColor;
import 'day_results_controller.dart';
import 'driving_panels.dart';
import 'lap_page.dart';
import 'telemetry_chart.dart';
import 'touch.dart';
import 'track_map.dart';

/// What a panel under a comparison's charts gets: the pair, its comparison
/// and the shared cursor and range.
final class ComparisonPanelContext {
  const ComparisonPanelContext({
    required this.controller,
    required this.a,
    required this.b,
    required this.comparison,
    required this.window,
    required this.openLap,
    this.focusSegmentId,
    this.fromTheoreticalBest = false,
    this.useTheoreticalBest,
  });

  final DayResultsController controller;
  final DayLapRow a;
  final DayLapRow b;
  final LapComparison comparison;
  final ChartWindow window;

  /// Opens lap 0 (A) or 1 (B) at a position on the shared axis.
  final void Function(int slot, double progressMeters) openLap;

  /// The segment the page was opened for, such as a time loss's.
  final String? focusSegmentId;

  /// The page measures against the theoretical best's segments (opened from
  /// one of its results, or asked for).
  final bool fromTheoreticalBest;

  /// Switches the page to the theoretical best's segments.
  final VoidCallback? useTheoreticalBest;
}

/// A panel under a comparison's charts. Where analyses of a pair plug in
/// (the Corner Analyzer, FET-38; G-G and driving states, FET-39): each gets
/// the comparison and its shared cursor and range, and returns null when it
/// has nothing to show.
typedef ComparisonPanelBuilder = Widget? Function(
  BuildContext context,
  ComparisonPanelContext panel,
);

/// The extra panels of every comparison page, in order.
final List<ComparisonPanelBuilder> comparisonPanels = [
  cornerAnalyzerPanel,
  ...drivingComparisonPanels,
];

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
    final l10n = context.l10n;
    // With very large text the time goes under the lap's name, which would
    // otherwise be squeezed to a letter per line.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    Widget option(DayLapRow row, {bool best = false}) {
      final time = displayTime(row.durationSeconds);
      return ListTile(
        key: ValueKey(
          '${best ? 'suggestedLap' : 'pickLap'} ${row.displayName}',
        ),
        leading: best ? const Icon(Icons.emoji_events_outlined) : null,
        title: Text(l10n.lap(row)),
        subtitle: stacked
            ? Text(best ? '$time · ${l10n.suggestedFastest}' : time)
            : best
            ? Text(l10n.suggestedFastest)
            : null,
        trailing: stacked
            ? null
            : Text(time, style: theme.textTheme.titleSmall),
        onTap: () => Navigator.pop(context, row),
      );
    }

    return SimpleDialog(
      // A lap's time stays near its name on a large screen.
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 440),
      title: Text(title),
      children: [
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(l10n.noOtherRankedLap),
          ),
        if (suggested != null) option(suggested, best: true),
        for (final row in candidates) option(row),
      ],
    );
  },
);

/// Two laps of one group, A (amber) against B (blue), on a shared
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
    this.segmentId,
    this.fromTheoreticalBest = false,
  });

  final DayResultsController controller;
  final DayLapRow a;
  final DayLapRow b;

  /// A stretch of lap A to show first, in its recording time (such as a
  /// time loss's segment); the whole lap when null.
  final (double, double)? focus;

  /// The segment to show first in the Corner Analyzer.
  final String? segmentId;

  /// Opened from a result of the theoretical best: the laps are measured
  /// against its segments when their own differ.
  final bool fromTheoreticalBest;

  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

/// The text for an unavailable map layer, as Overlays words it.
String mapLayerUnavailableText(
  AppLocalizations l10n,
  MapLayerOption? option,
  ComparisonMapLayer layer,
) {
  if (layer.valid) return '';
  final lap = layer.slot == 0 ? 'A' : 'B';
  if (option != null && !option.available) {
    return l10n.compareLayerNotRecordedEither;
  }
  return switch (layer.reason) {
    'channelMissing' => l10n.compareLayerNotRecordedOn(lap),
    'noSamples' => l10n.compareLayerNoSamples(lap),
    _ => l10n.compareNoSharedPosition,
  };
}

/// A map layer's name from `telemetry_core` ([id], as [label]) in the
/// app's language; a recorded temperature keeps its channel's name.
String _layerLabel(AppLocalizations l10n, String id, String label) =>
    switch (id) {
      'speed' => l10n.compareLayerSpeed,
      'delta' => l10n.compareLayerDelta,
      'lateralG' => l10n.compareLayerLateralG,
      'longitudinalG' => l10n.compareLayerLongitudinalG,
      'throttle' => l10n.compareLayerThrottle,
      'brake' => l10n.compareLayerBrake,
      'temperature' => l10n.compareLayerTemperature,
      _ => label,
    };

/// What an end of a diverging map layer's scale means, in the app's
/// language.
String _layerEndLabel(AppLocalizations l10n, String label) => switch (label) {
  'A ahead' => l10n.compareLayerAAhead,
  'A behind' => l10n.compareLayerABehind,
  'braking' => l10n.compareLayerBraking,
  'accelerating' => l10n.compareLayerAccelerating,
  _ => label,
};

class _ComparisonPageState extends State<ComparisonPage> {
  late DayLapRow _a = widget.a, _b = widget.b;
  late bool _fromTheoreticalBest = widget.fromTheoreticalBest;
  LapComparison? _comparison;
  ChartWindow? _window;
  List<String> _channels = const [];
  String _layerId = '';
  int _layerSlot = 1;

  (double, double)? _seriesRange;
  final Map<String, ChartSeries> _series = {};
  final Map<String, (double, double)> _axes = {};
  final Map<(String, int), ComparisonMapLayer> _layers = {};

  // Saves the range shown once a zoom or drag settles.
  Timer? _rangeSave;

  @override
  void initState() {
    super.initState();
    _pair(focus: widget.focus, opening: true);
  }

  @override
  void dispose() {
    if (_rangeSave?.isActive ?? false) {
      // A zoom left just before the page closed is still saved, after the
      // frame: the day's listeners must not rebuild during this teardown.
      _rangeSave!.cancel();
      final (start, end) = _window!.range.value;
      final controller = widget.controller;
      WidgetsBinding.instance
        ..addPostFrameCallback(
          (_) => controller.rememberComparisonRange(start, end),
        )
        ..scheduleFrame();
    }
    _window?.range.removeListener(_rangeChanged);
    _window?.dispose();
    super.dispose();
  }

  // The comparison set up here is saved with the day (FET-53), as Overlays
  // saves its comparison: the pair, the range shown and the charts.
  void _remember(void Function(DayResultsController controller) change) {
    // After the frame: the day's listeners rebuild, which is not allowed
    // while this page builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) change(widget.controller);
    });
  }

  void _rangeChanged() {
    _rangeSave?.cancel();
    _rangeSave = Timer(const Duration(milliseconds: 300), _saveRange);
  }

  void _saveRange() {
    final window = _window;
    if (window == null || !mounted) return;
    final (start, end) = window.range.value;
    widget.controller.rememberComparisonRange(start, end);
  }

  void _setChannels(List<String> channels) {
    _channels = channels;
    _remember((controller) => controller.rememberComparisonChannels(channels));
  }

  /// Shows the pair [_a], [_b]. [opening] the page, the day's saved range
  /// and charts are shown again where they fit this pair (as Overlays
  /// restores them when its comparison view opens); otherwise the range is
  /// the whole lap and the charts shown stay where the pair has them.
  void _pair({(double, double)? focus, bool opening = false}) {
    final previous = _comparison == null ? null : _channels;
    _rangeSave?.cancel();
    _window?.range.removeListener(_rangeChanged);
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
    final length = comparison.axisLengthMeters;
    final saved = opening ? widget.controller.savedComparison : null;
    final savedRange = saved?.range;
    final window = _window = ChartWindow(
      0,
      length,
      range:
          focus == null &&
              savedRange != null &&
              savedRange.$2 > savedRange.$1 &&
              savedRange.$1 >= 0 &&
              savedRange.$2 <= length + 1e-3
          ? (savedRange.$1, math.min(savedRange.$2, length))
          : null,
    );
    final available = comparison.chartChannels;
    final kept = [
      for (final channel
          in (opening ? saved?.channels : previous) ?? const <String>[])
        if (available.contains(channel)) channel,
    ];
    final channels = kept.isNotEmpty ? kept : comparison.defaultChartChannels;
    if (opening) {
      _channels = channels;
    } else {
      _setChannels(channels);
    }
    if (focus != null) {
      final trace = comparison.trace(0);
      final start = progressAtTime(trace, focus.$1);
      final end = progressAtTime(trace, focus.$2);
      if (start != null && end != null && end > start) {
        window.focus(start, end);
        window.cursor.value = start;
      }
    }
    final a = _a, b = _b;
    _remember((controller) => controller.rememberComparisonPair(a, b));
    if (!opening) _rangeChanged();
    window.range.addListener(_rangeChanged);
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
      title: slot == 0 ? context.l10n.pickLapA : context.l10n.lapB,
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
    final window = _window;
    if (window != null) _openLapAt(slot, window.cursor.value);
  }

  void _openLapAt(int slot, double progressMeters) {
    final comparison = _comparison;
    if (comparison == null) return;
    final row = slot == 0 ? _a : _b;
    final time = comparison.timeAt(slot, progressMeters);
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
    final l10n = context.l10n;
    final delta = _a.durationSeconds - _b.durationSeconds;
    Widget badge(int slot) {
      final row = slot == 0 ? _a : _b;
      final color = slot == 0 ? lapAColor : lapBColor;
      return ButtonRow(
        child: InkWell(
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
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${slot == 0 ? 'A' : 'B'} · ${l10n.lap(row)}',
                        style: theme.textTheme.titleSmall,
                        // Wraps rather than cutting off the lap, which tells
                        // A from B.
                        maxLines: 3,
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
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, runSpacing: 4, children: [badge(0), badge(1)]),
        const SizedBox(height: 4),
        Text(
          l10n.compareLapDelta(displayDelta(delta)),
          key: const ValueKey('comparisonLapDelta'),
          style: theme.textTheme.titleLarge,
        ),
        Text(l10n.compareDeltaExplained, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('comparisonSwap'),
              onPressed: () => _setPair(_b, _a),
              icon: const Icon(Icons.swap_horiz),
              label: Text(l10n.compareSwap),
            ),
            OutlinedButton(
              key: const ValueKey('comparisonBestOfRun'),
              onPressed: () => _bestAsB(sameRun: true),
              child: Text(
                l10n.compareBestOfSessionAsB(l10n.session(_a.runName)),
              ),
            ),
            OutlinedButton(
              key: const ValueKey('comparisonBestOfDay'),
              onPressed: () => _bestAsB(sameRun: false),
              child: Text(l10n.compareBestOfDayAsB),
            ),
          ],
        ),
      ],
    );
  }

  Widget _map(BuildContext context, double height) {
    final comparison = _comparison!;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final options = comparison.mapLayerOptions;
    final layer = _layer;
    MapLayerOption? option;
    for (final candidate in options) {
      if (candidate.id == _layerId) option = candidate;
    }
    final unavailable = layer == null
        ? ''
        : mapLayerUnavailableText(l10n, option, layer);
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
                  DropdownMenuItem(
                    value: '',
                    child: Text(l10n.compareLayerLine),
                  ),
                  for (final option in options)
                    DropdownMenuItem(
                      value: option.id,
                      child: Text(
                        option.available
                            ? _layerLabel(l10n, option.id, option.label)
                            : l10n.compareLayerOptionNotRecorded(
                                _layerLabel(l10n, option.id, option.label),
                              ),
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
                // The selected lap in its own colour and the other one
                // neutral, so B is never amber.
                style: SegmentedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  selectedBackgroundColor: _layerSlot == 0
                      ? lapAColor
                      : lapBColor,
                  selectedForegroundColor: FetColors.of(context).onLap,
                ),
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
    final l10n = context.l10n;
    final comparison = _comparison!;
    final window = _window!;
    return [
      Text(l10n.compareChannelsByPosition, style: theme.textTheme.titleMedium),
      Text(
        isTouchPlatform(context)
            ? l10n.compareCursorHintTouch
            : l10n.compareCursorHint,
        style: theme.textTheme.bodySmall,
      ),
      ChartWindowControls(
        window: window,
        axisText: (meters) => '${meters.round()}\u00a0m',
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
                        title: l10n.compareDeltaChart,
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
                        note: l10n.compareDeltaNote,
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
        onAdd: (channel) =>
            setState(() => _setChannels([..._channels, channel])),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final slot in const [0, 1])
            TextButton.icon(
              key: ValueKey('comparisonOpenLap${slot == 0 ? 'A' : 'B'}'),
              style: TextButton.styleFrom(
                foregroundColor: slot == 0 ? lapAColor : lapBColor,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(l10n.compareOpenLapHere(slot == 0 ? 'A' : 'B')),
              onPressed: () => _openLap(slot),
            ),
        ],
      ),
      if (!_panelsFirst) ..._panels(context),
      const SizedBox(height: 8),
      Text(l10n.compareDisclaimer, style: theme.textTheme.bodySmall),
    ];
  }

  // Opened for a segment: its analysis comes first, the charts after it.
  bool get _panelsFirst => widget.segmentId != null;

  List<Widget> _panels(BuildContext context) => [
    for (final builder in comparisonPanels)
      ?builder(
        context,
        ComparisonPanelContext(
          controller: widget.controller,
          a: _a,
          b: _b,
          comparison: _comparison!,
          window: _window!,
          openLap: _openLapAt,
          focusSegmentId: widget.segmentId,
          fromTheoreticalBest: _fromTheoreticalBest,
          useTheoreticalBest: () => setState(() => _fromTheoreticalBest = true),
        ),
      ),
  ];

  void _remove(String channel) => setState(
    () => _setChannels([
      for (final shown in _channels)
        if (shown != channel) shown,
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final comparison = _comparison;
    final ready = comparison != null && comparison.axis.valid;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.compareTitle)),
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
                      ? l10n.compareRecordingsUnavailable
                      : l10n.compareNoSharedPosition,
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
                    children: [
                      if (_panelsFirst) ..._panels(context),
                      ..._charts(context),
                    ],
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
              if (_panelsFirst) ..._panels(context),
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

/// Map layer scales. None of them uses lap A's amber or lap B's blue, except
/// Δ time, whose ends are the laps themselves.
///
/// Sequential (speed, throttle, brake): purple, dim, to mint, bright.
const List<Color> sequentialLayerStops = [Color(0xFF4A2A7A), Color(0xFFB8F5E0)];

/// Diverging (lateral and longitudinal G): magenta, grey at zero, teal,
/// symmetric around zero so zero is always neutral.
const List<Color> divergingLayerStops = [
  Color(0xFFE05BD8),
  Color(0xFF8B95A1),
  Color(0xFF2FD6A8),
];

/// Δ time (A − B): lap A's colour where A is ahead, grey at zero, lap B's
/// where B is ahead.
const List<Color> deltaLayerStops = [lapAColor, Color(0xFF8B95A1), lapBColor];

/// The colour stops of [layer]'s scale.
List<Color> mapLayerStops(ComparisonMapLayer layer) => layer.id == 'delta'
    ? deltaLayerStops
    : layer.diverging
    ? divergingLayerStops
    : sequentialLayerStops;

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
  final stops = mapLayerStops(layer);
  if (!layer.diverging) return Color.lerp(stops[0], stops[1], t)!;
  return t < 0.5
      ? Color.lerp(stops[0], stops[1], t * 2)!
      : Color.lerp(stops[1], stops[2], (t - 0.5) * 2)!;
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
    final l10n = context.l10n;
    final (low, high) = mapLayerRange(layer);
    final unit = displayUnitOf(context, layer.channel, layer.unit);
    final stops = mapLayerStops(layer);
    String end(double value, String label) =>
        '${mapLayerValueText(layer, value)}'
        '${layer.diverging && label.isNotEmpty ? ' ${_layerEndLabel(l10n, label)}' : ''}';
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
          '${l10n.compareLegendLap(_layerLabel(l10n, layer.id, layer.label), layer.slot == 0 ? 'A' : 'B')}'
          '${unit.isEmpty ? '' : ' · $unit'}'
          '${layer.provenance == 'calculated' ? ' · ${l10n.compareLegendCalculated}' : ''}',
          key: const ValueKey('comparisonMapLegendSource'),
          style: theme.textTheme.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Both laps on one map over street or satellite tiles (the shared
/// [mapBackground], switched with the layers button), with the zoom window
/// highlighted on lap B and a marker per lap at the cursor. The lines and
/// the layer are built once; the range and the markers are separate layers,
/// rebuilt only when they change. Under tests without tiles both laps are
/// drawn to the same scale on a plain background.
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
    if (a.isEmpty && b.isEmpty) {
      return Center(child: Text(context.l10n.compareNoGps));
    }
    return Semantics(
      label: context.l10n.compareMapLabel,
      child: ValueListenableBuilder(
        valueListenable: mapBackground,
        builder: (context, background, _) {
          final tiles = tileSourceFor(background);
          return ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  // One finger scrolls the page on a phone; two fingers
                  // zoom into a corner.
                  child: tiles == null
                      ? PinchZoom(
                          desktop: false,
                          child: _plainMap(context, a, b),
                        )
                      : _TiledOverlayMap(
                          key: ValueKey((tiles.urlTemplate, comparison)),
                          tiles: tiles,
                          comparison: comparison,
                          layer: layer,
                          window: window,
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: MapLayersButton(background),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _plainMap(
    BuildContext context,
    List<List<MapPoint>> a,
    List<List<MapPoint>> b,
  ) {
    final theme = Theme.of(context);
    return LayoutBuilder(
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
    );
  }
}

/// [x], [y] on [geometry]'s normalized overlay map in degrees, or null.
LatLng? _overlayLatLng(MapGeometry geometry, double x, double y) {
  final coordinate = mapPointCoordinate(x, y, geometry);
  return coordinate == null
      ? null
      : LatLng(coordinate.latitudeDegrees, coordinate.longitudeDegrees);
}

// Each lap's overlay track in degrees, computed once per track; a position
// with no place on the earth ends a line (never bridged).
final Expando<List<List<LatLng>>> _overlayDegrees = Expando(
  'comparison overlay degrees',
);

// A map layer's coloured polylines, computed once per layer.
final Expando<List<Polyline<Object>>> _layerLines = Expando(
  'comparison layer lines',
);

/// The comparison map over tiles: both laps' lines and the optional layer
/// are static; only the range highlight and the cursor markers rebuild.
class _TiledOverlayMap extends StatelessWidget {
  const _TiledOverlayMap({
    super.key,
    required this.tiles,
    required this.comparison,
    required this.layer,
    required this.window,
  });

  final TileSource tiles;
  final LapComparison comparison;
  final ComparisonMapLayer? layer;
  final ChartWindow window;

  // Neighbouring points of one colour band share a polyline.
  static const _bands = 32;

  List<List<LatLng>> _track(int slot) {
    final track = comparison.overlayTrack(slot);
    final cached = _overlayDegrees[track];
    if (cached != null) return cached;
    final geometry = comparison.geometry;
    final lines = <List<LatLng>>[];
    for (final run in track) {
      var line = <LatLng>[];
      for (final point in run) {
        final at = _overlayLatLng(geometry, point.x, point.y);
        if (at == null) {
          if (line.length > 1) lines.add(line);
          line = [];
          continue;
        }
        line.add(at);
      }
      if (line.length > 1) lines.add(line);
    }
    // An empty track is a shared const list: nothing to cache on.
    if (track.isNotEmpty) _overlayDegrees[track] = lines;
    return lines;
  }

  List<Polyline<Object>> _layerPolylines(ComparisonMapLayer layer) {
    final cached = _layerLines[layer];
    if (cached != null) return cached;
    final geometry = comparison.geometry;
    final (low, high) = mapLayerRange(layer);
    final spread = high - low;
    Color colorOf(MapLayerPoint from, MapLayerPoint to) {
      final value = (from.value + to.value) / 2;
      final banded = spread > 0
          ? low +
                ((value - low) / spread * _bands).roundToDouble() /
                    _bands *
                    spread
          : value;
      return mapLayerColor(layer, banded);
    }

    // Runs of placed points; a point with no place on the earth ends a run.
    final runs = <List<(LatLng, MapLayerPoint)>>[];
    for (final polyline in layer.trace.polylines) {
      var run = <(LatLng, MapLayerPoint)>[];
      for (final point in polyline) {
        final at = _overlayLatLng(geometry, point.x, point.y);
        if (at == null) {
          if (run.length > 1) runs.add(run);
          run = [];
          continue;
        }
        run.add((at, point));
      }
      if (run.length > 1) runs.add(run);
    }

    // One dark outline under each run, so the colour bands join seamlessly
    // and stay readable on any background.
    final lines = <Polyline<Object>>[
      for (final run in runs)
        Polyline(
          points: [for (final (at, _) in run) at],
          color: Colors.black54,
          strokeWidth: 8,
        ),
    ];
    for (final run in runs) {
      var points = [run.first.$1];
      var color = colorOf(run[0].$2, run[1].$2);
      for (var i = 1; i < run.length; ++i) {
        final next = colorOf(run[i - 1].$2, run[i].$2);
        if (next != color) {
          lines.add(Polyline(points: points, color: color, strokeWidth: 5));
          points = [points.last];
          color = next;
        }
        points.add(run[i].$1);
      }
      lines.add(Polyline(points: points, color: color, strokeWidth: 5));
    }
    return _layerLines[layer] = lines;
  }

  static Polyline<Object> _line(
    List<LatLng> points,
    Color color,
    double width,
  ) => Polyline(
    points: points,
    color: color,
    strokeWidth: width,
    borderStrokeWidth: 1.5,
    borderColor: Colors.black54,
  );

  /// Lap B over the zoom window, sampled along the shared axis; a gap on
  /// lap B ends the highlight and is never bridged.
  List<Polyline<Object>> _rangeLines() {
    if (!window.zoomed) return const [];
    final geometry = comparison.geometry;
    final (start, end) = window.range.value;
    final step = math.max(2.0, (end - start) / 150);
    final lines = <Polyline<Object>>[];
    var points = <LatLng>[];
    void flush() {
      if (points.length > 1) {
        lines.add(
          Polyline(
            points: points,
            color: Colors.white.withValues(alpha: 0.85),
            strokeWidth: 11,
            borderStrokeWidth: 1.5,
            borderColor: Colors.black54,
          ),
        );
      }
      points = [];
    }

    for (var meters = start; meters <= end + 1e-6; meters += step) {
      final point = comparison.positionAt(1, math.min(meters, end));
      final at = point == null
          ? null
          : _overlayLatLng(geometry, point.x, point.y);
      if (at == null) {
        flush();
        continue;
      }
      points.add(at);
    }
    flush();
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final a = _track(0), b = _track(1);
    final all = [
      for (final line in [...a, ...b]) ...line,
    ];
    if (all.isEmpty) return const SizedBox.expand();
    final shown = layer;
    final dimmed = shown != null;
    final geometry = comparison.geometry;
    return TouchMap(
      builder: (context, controller, interaction) => FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCameraFit: CameraFit.coordinates(
            coordinates: all,
            padding: const EdgeInsets.all(24),
            maxZoom: 18,
          ),
          maxZoom: mapMaxZoom(tiles),
          minZoom: mapMinZoom(tiles),
          cameraConstraint: mapCameraConstraint(tiles),
          interactionOptions: interaction,
        ),
        children: [
          mapTileLayer(tiles),
          // Under the laps, so both stay readable inside the window.
          ValueListenableBuilder(
            valueListenable: window.range,
            builder: (context, _, _) => PolylineLayer(
              key: const ValueKey('comparisonMapRange'),
              polylines: _rangeLines(),
            ),
          ),
          PolylineLayer(
            polylines: [
              for (final (lines, color) in [(a, lapAColor), (b, lapBColor)])
                for (final line in lines)
                  _line(
                    line,
                    dimmed ? color.withValues(alpha: 0.35) : color,
                    3.5,
                  ),
              if (shown != null) ..._layerPolylines(shown),
            ],
          ),
          ValueListenableBuilder(
            valueListenable: window.cursor,
            builder: (context, cursor, _) => CircleLayer(
              key: const ValueKey('comparisonMapMarkers'),
              circles: [
                for (final slot in const [0, 1])
                  if (comparison.positionAt(slot, cursor) case final point?)
                    if (_overlayLatLng(geometry, point.x, point.y)
                        case final at?)
                      CircleMarker(
                        point: at,
                        radius: 7,
                        color: slot == 0 ? lapAColor : lapBColor,
                        borderColor: const Color(0xFF111214),
                        borderStrokeWidth: 2.5,
                      ),
              ],
            ),
          ),
          MapAttribution(tiles),
        ],
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
        ..drawCircle(centre, 8, Paint()..color = const Color(0xFF111214))
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
