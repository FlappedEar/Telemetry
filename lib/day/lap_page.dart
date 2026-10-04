import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/headline_bar.dart';
import '../ui/theme.dart';
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
      '${(time - widget.row.start).toStringAsFixed(1)}\u00a0s';

  List<Widget> _charts(BuildContext context) {
    final session = _session;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    if (session == null || !(widget.row.end > widget.row.start)) {
      return const [];
    }
    return [
      const SizedBox(height: 16),
      Text(l10n.lapPageChannels, style: theme.textTheme.titleMedium),
      Text(
        isTouchPlatform(context)
            ? l10n.lapPageCursorHintTouch
            : l10n.lapPageCursorHint,
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
        Text(l10n.lapPageNoChannel, style: theme.textTheme.bodySmall),
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
    await _openComparison(other);
  }

  // This lap as A against [other] as B.
  Future<void> _openComparison(DayLapRow other) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ComparisonPage(
        controller: widget.controller,
        a: widget.row,
        b: other,
      ),
    ),
  );

  // The best lap of the day for this lap's own track layout; for an out or
  // in section, which has no layout of its own, that of the layout shown.
  DayLapRow? get _dayBest {
    final controller = widget.controller;
    final row = widget.row;
    return row.type == LapSectionType.lap
        ? dayBestComparisonLap(controller.analysis, row)
        : controller.ranking?.bestOfDay;
  }

  LapPath? _best() {
    final best = _dayBest;
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.lap(row))),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final theme = Theme.of(context);
          final best = _dayBest;
          final issues = controller.issues(row);
          final reason = controller.exclusionReason(row);
          final bestPath = _showBest ? _best() : null;
          final comparable = controller
              .comparisonCandidates(row)
              .any((candidate) => candidate.reference == row.reference);
          final colors = FetColors.of(context);
          final timed = row.type == LapSectionType.lap;
          final bestOfDay = timed && best?.reference == row.reference;
          final bestOfRun =
              timed &&
              dayBestComparisonLap(
                    controller.analysis,
                    row,
                    sameRun: true,
                  )?.reference ==
                  row.reference;
          final against = timed && best != null && !bestOfDay ? best : null;
          // Rounded as shown, so "±0.000 s" is never red.
          final gapMilliseconds = against == null
              ? 0
              : ((row.durationSeconds - against.durationSeconds) * 1000)
                    .round();
          // This lap in amber, as "you", over the best lap of the day in
          // the reference blue; tapping the blue bar compares the two.
          final bars = <Widget>[
            HeadlineBar(
              key: const ValueKey('lapTimeBar'),
              label: bestOfDay
                  ? l10n.lapPageBestOfDay
                  : bestOfRun
                  ? l10n.lapPageBestOfSession(l10n.session(row.runName))
                  : l10n.lapPageThisLap,
              title: l10n.lap(row),
              time: displayTime(row.durationSeconds),
              color: colors.you,
              onColor: colors.onLap,
            ),
            if (against != null) ...[
              const SizedBox(height: 4),
              HeadlineBar(
                key: const ValueKey('lapBestBar'),
                label: l10n.dayBestLabel,
                title: l10n.lap(against),
                time: displayTime(against.durationSeconds),
                color: colors.reference,
                onColor: colors.onLap,
                onTap: controller.comparable(row, against)
                    ? () => _openComparison(against)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.lapPageGapToBest(
                  displayDelta(row.durationSeconds - against.durationSeconds),
                ),
                key: const ValueKey('lapGapToBest'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: FetTheme.mono,
                  color: gapMilliseconds > 0
                      ? colors.loss
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ];
          final summary = <Widget>[
            ...bars,
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  issue == LapIssue.userExclusion && reason != null
                      ? l10n.lapPageNotRankedExcluded(reason)
                      : l10n.lapNotRanked(l10n.lapIssue(issue)),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ];
          final actions = <Widget>[
            if (timed)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (comparable)
                    OutlinedButton.icon(
                      key: const ValueKey('lapCompare'),
                      onPressed: _compare,
                      icon: const Icon(Icons.compare_arrows),
                      label: Text(l10n.lapPageCompareWith),
                    ),
                  if (reason == null)
                    OutlinedButton.icon(
                      onPressed: _exclude,
                      icon: const Icon(Icons.block),
                      label: Text(l10n.lapPageExclude),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => controller.include(row),
                      icon: const Icon(Icons.undo),
                      label: Text(l10n.lapPageInclude),
                    ),
                ],
              ),
          ];
          final trace = _path.isEmpty
              ? Center(child: Text(l10n.lapPageNoGps))
              : Card(
                  clipBehavior: Clip.antiAlias,
                  child: TrackMap(
                    path: _path,
                    reference: bestPath,
                    gate: _gate,
                    movingMarks: _cursorMarks,
                    semanticLabel: l10n.lapPageTraceLabel(l10n.lap(row)),
                  ),
                );
          final legend = <Widget>[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(l10n.lapPageSpeed, style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                Expanded(child: SpeedLegend(path: _path)),
              ],
            ),
            if (best != null && best.reference != row.reference)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showBest,
                onChanged: (value) => setState(() => _showBest = value),
                title: Text(l10n.lapPageShowBest(l10n.lap(best))),
              ),
          ];
          final charts = [
            ..._charts(context),
            ?lapCoastingPanel(controller, row, _window),
          ];
          return LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              // A wide window that is also tall enough; a phone sideways
              // scrolls the page instead, so the map keeps its size.
              if (constraints.maxWidth >= 800 && height >= 600) {
                // The summary across the top; the map stays in view on the
                // left while the charts scroll on the right, so the cursor
                // on a chart is always visible on the trace.
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: height * 0.45),
                        child: SingleChildScrollView(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: summary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 6,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: actions,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: trace),
                                  ...legend,
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 6,
                              child: ListView(
                                key: const ValueKey('lapCharts'),
                                children: charts,
                              ),
                            ),
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
                  if (actions.isNotEmpty) const SizedBox(height: 12),
                  ...actions,
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
    title: Text(context.l10n.lapPageExcludeTitle),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: 256,
      decoration: InputDecoration(
        labelText: context.l10n.lapPageReason,
        hintText: context.l10n.lapPageReasonHint,
      ),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: Text(context.l10n.lapPageExcludeAction),
      ),
    ],
  );
}
