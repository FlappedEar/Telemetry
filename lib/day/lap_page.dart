import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'comparison_page.dart';
import 'day_results_controller.dart';
import 'lap_coasting_panel.dart';
import 'telemetry_chart.dart';
import 'touch.dart';
import 'track_map.dart';

/// The channels last chosen for a lap's charts, kept while the app runs.
final ValueNotifier<List<String>?> rememberedLapChannels = ValueNotifier(null);

/// One lap section: its time, where it stands in the day, its trace on the
/// map coloured by speed, over the best lap of the day in grey, and its
/// channels on a time axis. A drag on a chart moves a cursor, shown on the
/// map.
class LapPage extends StatefulWidget {
  const LapPage({
    super.key,
    required this.controller,
    required this.row,
    this.initialCursor,
  });

  final DayResultsController controller;
  final DayLapRow row;

  /// Where the cursor starts, in recording time; the lap's start when null.
  final double? initialCursor;

  @override
  State<LapPage> createState() => _LapPageState();
}

class _LapPageState extends State<LapPage> {
  bool _showBest = true;

  // Static geometry: computed once per lap, never on rebuilds.
  late final GeoCoordinate? _origin;
  late final LapPath _path;
  late final (Offset, Offset)? _gate;
  DayLapReference? _bestReference;
  LapPath? _bestPath;

  late final TelemetrySession? _session;
  late final ChartWindow _window = ChartWindow(
    widget.row.start,
    widget.row.end,
    cursor: widget.initialCursor,
  );
  final ValueNotifier<List<MapMark>> _cursorMarks = ValueNotifier(const []);
  late List<String> _channels;

  // Series of the range shown, and each channel's value axis over the lap.
  (double, double)? _seriesRange;
  final Map<String, ChartSeries> _series = {};
  final Map<String, (double, double)> _axes = {};

  @override
  void initState() {
    super.initState();
    final session = _session = widget.controller.session(widget.row.runId);
    _channels = session == null
        ? const []
        : lapChartChannels(session, remembered: rememberedLapChannels.value);
    _window.cursor.addListener(_moveMark);
    _origin = session == null ? null : mapOrigin(session);
    _path = session == null
        ? LapPath(origin: const GeoCoordinate(0, 0), segments: const [])
        : lapPath(session, widget.row.start, widget.row.end, origin: _origin);
    _gate = session == null || _origin == null
        ? null
        : mapGate(session, _origin);
    _moveMark();
  }

  @override
  void dispose() {
    _window.cursor.removeListener(_moveMark);
    _window.dispose();
    _cursorMarks.dispose();
    super.dispose();
  }

  // The cursor's place on the trace, between the two fixes around it; none
  // in a GPS gap, which is never bridged.
  void _moveMark() {
    final time = _window.cursor.value;
    for (final segment in _path.segments) {
      if (segment.isEmpty ||
          time < segment.first.telemetryTime ||
          time > segment.last.telemetryTime) {
        continue;
      }
      var low = 0, high = segment.length - 1;
      while (high - low > 1) {
        final middle = (low + high) ~/ 2;
        segment[middle].telemetryTime <= time ? low = middle : high = middle;
      }
      final a = segment[low], b = segment[high];
      final span = b.telemetryTime - a.telemetryTime;
      final t = span > 0 ? (time - a.telemetryTime) / span : 0.0;
      _cursorMarks.value = [
        MapMark(
          a.eastMeters + (b.eastMeters - a.eastMeters) * t,
          a.northMeters + (b.northMeters - a.northMeters) * t,
          Colors.white,
          radius: 7,
        ),
      ];
      return;
    }
    _cursorMarks.value = const [];
  }

  // Channels a chart can show: everything recorded but the position.
  List<String> get _chartable {
    final session = _session;
    if (session == null) return const [];
    final position = {
      session.aliases['latitude'] ?? 'latitude',
      session.aliases['longitude'] ?? 'longitude',
    };
    return [
      for (final name in session.channelNames())
        if (!position.contains(name)) name,
    ];
  }

  void _setChannels(List<String> channels) {
    setState(() => _channels = channels);
    rememberedLapChannels.value = List.unmodifiable(channels);
  }

  ChartSeries _seriesOf(String channel, (double, double) range) {
    if (_seriesRange != range) {
      _seriesRange = range;
      _series.clear();
    }
    return _series[channel] ??= timeSeries(
      _session!,
      channel,
      range.$1,
      range.$2,
      600,
    );
  }

  (double, double) _axisOf(String channel) => _axes[channel] ??= chartValueAxis(
    [timeSeries(_session!, channel, widget.row.start, widget.row.end, 300)],
  );

  String _axisText(double time) =>
      '${(time - widget.row.start).toStringAsFixed(1)} s';

  List<Widget> _charts(BuildContext context) {
    final session = _session;
    final theme = Theme.of(context);
    if (session == null || !(widget.row.end > widget.row.start)) {
      return const [];
    }
    return [
      const SizedBox(height: 16),
      Text('Channels', style: theme.textTheme.titleMedium),
      Text(
        isTouchPlatform(context)
            ? 'Tap a chart or drag sideways across it to move the cursor; the '
                  'white dot shows it on the map. Two fingers zoom and move '
                  'the map.'
            : 'Drag across a chart to move the cursor; the white dot shows it '
                  'on the map.',
        style: theme.textTheme.bodySmall,
      ),
      ChartWindowControls(window: _window, axisText: _axisText),
      ValueListenableBuilder(
        valueListenable: _window.range,
        builder: (context, range, _) => Column(
          children: [
            for (final channel in _channels)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TelemetryChart(
                  key: ValueKey('lapChart $channel'),
                  title: channel,
                  source: widget.controller.channelSource(
                    widget.row.runId,
                    channel,
                  ),
                  lines: [
                    ChartLine(
                      '',
                      _seriesOf(channel, range),
                      theme.colorScheme.primary,
                    ),
                  ],
                  start: range.$1,
                  end: range.$2,
                  cursor: _window.cursor,
                  onCursor: (value) => _window.cursor.value = value,
                  valueAxis: _axisOf(channel),
                  onRemove: () => _setChannels([
                    for (final shown in _channels)
                      if (shown != channel) shown,
                  ]),
                ),
              ),
          ],
        ),
      ),
      if (_channels.isEmpty)
        Text('No channel shown.', style: theme.textTheme.bodySmall),
      AddChannelButton(
        channels: _chartable,
        shown: _channels,
        sources: widget.controller.channelSources(widget.row.runId),
        onAdd: (channel) => _setChannels([..._channels, channel]),
      ),
    ];
  }

  Future<void> _compare() async {
    final controller = widget.controller;
    final row = widget.row;
    final partner = controller.comparisonPartner(row);
    final other = await pickComparisonLap(
      context,
      title: context.l10n.pickLapB(context.l10n.lap(row)),
      candidates: [
        for (final candidate in controller.comparisonCandidates(row))
          if (candidate.reference != row.reference) candidate,
      ],
      suggested: partner,
    );
    if (other == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ComparisonPage(controller: controller, a: row, b: other),
      ),
    );
  }

  LapPath? _best() {
    final best = widget.controller.ranking?.bestOfDay;
    if (best == null || best.reference == widget.row.reference) return null;
    if (_bestReference != best.reference) {
      final session = widget.controller.session(best.runId);
      _bestReference = best.reference;
      _bestPath = session == null
          ? null
          : lapPath(
              session,
              best.start,
              best.end,
              origin: _origin ?? _path.origin,
            );
    }
    return _bestPath;
  }

  Future<void> _exclude() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ExcludeDialog(),
    );
    if (reason != null) widget.controller.exclude(widget.row, reason);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(row.displayName)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final theme = Theme.of(context);
          final best = controller.ranking?.bestOfDay;
          final issues = controller.issues(row);
          final reason = controller.exclusionReason(row);
          final bestPath = _showBest ? _best() : null;
          final comparable = controller
              .comparisonCandidates(row)
              .any((candidate) => candidate.reference == row.reference);
          final summary = <Widget>[
            Text(
              displayTime(row.durationSeconds),
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 4),
            if (controller.isBestOfDay(row))
              const Text('Best lap of the day')
            else if (best != null && row.type == LapSectionType.lap)
              Text(
                '${displayDelta(row.durationSeconds - best.durationSeconds)} '
                'to the best of the day (${best.displayName})',
              ),
            if (controller.isBestOfRun(row) && !controller.isBestOfDay(row))
              Text('Best lap of ${row.runName}'),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  issue == LapIssue.userExclusion && reason != null
                      ? 'Not ranked: excluded (“$reason”)'
                      : 'Not ranked: ${issue.label}',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (row.type == LapSectionType.lap) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (reason == null)
                    OutlinedButton.icon(
                      onPressed: _exclude,
                      icon: const Icon(Icons.block),
                      label: const Text('Exclude from ranking…'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => controller.include(row),
                      icon: const Icon(Icons.undo),
                      label: const Text('Include in ranking'),
                    ),
                  if (comparable)
                    OutlinedButton.icon(
                      key: const ValueKey('lapCompare'),
                      onPressed: _compare,
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('Compare with…'),
                    ),
                ],
              ),
            ],
          ];
          final trace = _path.isEmpty
              ? const Center(child: Text('No GPS recorded for this section.'))
              : Card(
                  clipBehavior: Clip.antiAlias,
                  child: TrackMap(
                    path: _path,
                    reference: bestPath,
                    gate: _gate,
                    movingMarks: _cursorMarks,
                    semanticLabel:
                        'Trace of ${row.displayName}, coloured by speed',
                  ),
                );
          final legend = <Widget>[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Speed', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                Expanded(child: SpeedLegend(path: _path)),
              ],
            ),
            if (best != null && best.reference != row.reference)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showBest,
                onChanged: (value) => setState(() => _showBest = value),
                title: Text('Show the best lap (${best.displayName}) in grey'),
              ),
          ];
          final charts = [
            ..._charts(context),
            ?lapCoastingPanel(controller, row, _window),
          ];
          return LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              if (constraints.maxWidth >= 800) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 300, child: ListView(children: summary)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ListView(
                          children: [
                            SizedBox(
                              height: (height * 0.55).clamp(240.0, 560.0),
                              child: trace,
                            ),
                            ...legend,
                            ...charts,
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              // The map keeps a readable size, the charts follow it; a
              // short screen (a small phone sideways, or with large text)
              // gives the map most of its height.
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ...summary,
                  const SizedBox(height: 12),
                  SizedBox(
                    height: height >= 600
                        ? (height * 0.45).clamp(220.0, 420.0)
                        : (height - 48).clamp(220.0, 420.0),
                    child: trace,
                  ),
                  ...legend,
                  ...charts,
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ExcludeDialog extends StatefulWidget {
  const _ExcludeDialog();

  @override
  State<_ExcludeDialog> createState() => _ExcludeDialogState();
}

class _ExcludeDialogState extends State<_ExcludeDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Exclude this lap'),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: 256,
      decoration: const InputDecoration(
        labelText: 'Reason',
        hintText: 'Traffic, yellow flag…',
      ),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Exclude'),
      ),
    ],
  );
}
