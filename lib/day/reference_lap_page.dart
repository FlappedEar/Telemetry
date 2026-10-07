import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../import/day_import_page.dart' show RecordingPickers;
import '../l10n.dart';
import '../profile/profile_library.dart';
import '../ui/theme.dart';
import '../units.dart';
import 'comparison_page.dart' show pickComparisonLap;
import 'corner_analyzer_panel.dart' show segmentPickerLabel;
import 'corner_details.dart' show cornerReasonText, lapAColor, lapBColor;
import 'day_results_controller.dart';
import 'reference_lap.dart';
import 'telemetry_chart.dart';
import 'touch.dart';

/// Today's start/finish line a reference is timed on: the line of the
/// day's best lap in the group shown. Null without a ranked lap.
TimingGate? referenceGate(DayResultsController controller) {
  final best = controller.ranking?.bestOfDay;
  if (best == null) return null;
  for (final named in controller.runs) {
    if (named.run.id == best.runId) return named.run.laps.selectedStartGate;
  }
  return null;
}

/// Where [lap] of [holder]'s source comes from, in words: the file's name,
/// or the day's name and the session.
String referenceSourceText(
  AppLocalizations l10n,
  ReferenceSource source,
  ReferenceLapCandidate lap,
) => switch (source) {
  ReferenceFile() => source.name,
  ReferenceProfileDay() => l10n.referenceDaySession(
    source.name,
    l10n.session(lap.recordingLabel),
  ),
};

/// "Reference: friend.vbo, lap 3, 1:49.898": the reference lap's name
/// wherever it is shown; null without one.
String? referenceLabel(AppLocalizations l10n, ReferenceLapHolder holder) {
  final source = holder.source, lap = holder.lap;
  if (source == null || lap == null) return null;
  return l10n.referenceLabel(
    referenceSourceText(l10n, source, lap),
    lap.lapNumber,
    displayTime(lap.durationSeconds),
  );
}

/// [meters] for a distance far from the line: metres below a kilometre.
String _distanceText(double meters) =>
    meters >= 1000 ? '${fixed(meters / 1000, 1)} km' : '${meters.round()} m';

/// Why [holder]'s source is not used, in words; empty when it is.
String referenceProblemText(AppLocalizations l10n, ReferenceLapHolder holder) {
  if (holder.state == ReferenceState.failed) {
    return holder.error == referenceDayHasNoRecordings
        ? l10n.referenceDayNoRecordings
        : l10n.referenceFailed(l10n.coreText(holder.error));
  }
  final timing = holder.timing;
  if (holder.state != ReferenceState.refused || timing == null) return '';
  return switch (timing.refusal) {
    ReferenceRefusal.wrongTrack => l10n.referenceRefusedWrongTrack(
      _distanceText(timing.nearestGateDistanceMeters ?? 0),
    ),
    ReferenceRefusal.noGps => l10n.referenceRefusedNoGps,
    ReferenceRefusal.invalidGate => l10n.referenceRefusedGate,
    ReferenceRefusal.noTimedLap ||
    ReferenceRefusal.none => l10n.referenceRefusedNoLap,
  };
}

/// Asks for one of [library]'s days other than [eventId]; null when none
/// was chosen.
Future<ReferenceProfileDay?> pickReferenceDay(
  BuildContext context,
  ProfileLibrary library,
  String eventId,
) {
  final profile = library.profile;
  final days =
      [
        for (final day in profile?.days ?? const <ProfileDay>[])
          if (day.eventId != eventId && library.pathOf(day) != null) day,
      ]..sort(
        (x, y) =>
            (y.startMilliseconds ?? 0).compareTo(x.startMilliseconds ?? 0),
      );
  return showDialog<ReferenceProfileDay>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return SimpleDialog(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
        title: Text(l10n.referencePickDay),
        children: [
          if (days.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(l10n.referenceNoDays),
            ),
          for (final day in days)
            ListTile(
              key: ValueKey('referenceDay ${day.eventId}'),
              title: Text(day.name),
              subtitle: Text(
                [
                  if (day.trackId case final id?)
                    if (profile?.track(id) case final track?) track.name,
                  if (day.bestLapSeconds case final best?) displayTime(best),
                ].join(' · '),
              ),
              onTap: () => Navigator.pop(
                context,
                ReferenceProfileDay(
                  path: library.pathOf(day)!,
                  eventId: day.eventId,
                  dayName: day.name,
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Asks which of [holder]'s laps is the reference; null when none was
/// chosen.
Future<ReferenceLapCandidate?> pickReferenceLap(
  BuildContext context,
  ReferenceLapHolder holder,
) {
  final timing = holder.timing, source = holder.source;
  if (timing == null || source == null) return Future.value();
  final fastest = timing.fastest;
  return showDialog<ReferenceLapCandidate>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final l10n = context.l10n;
      return SimpleDialog(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
        title: Text(l10n.referencePickLap),
        children: [
          for (final lap in timing.candidates)
            ListTile(
              key: ValueKey(
                'referenceLap ${lap.recordingIndex} ${lap.lapNumber}',
              ),
              leading: identical(lap, fastest)
                  ? const Icon(Icons.emoji_events_outlined)
                  : null,
              selected: identical(lap, holder.lap),
              title: Text(
                l10n.referenceLapOption(
                  referenceSourceText(l10n, source, lap),
                  lap.lapNumber,
                ),
              ),
              subtitle: identical(lap, fastest)
                  ? Text(l10n.suggestedFastest)
                  : null,
              trailing: Text(
                displayTime(lap.durationSeconds),
                style: theme.textTheme.titleSmall,
              ),
              onTap: () => Navigator.pop(context, lap),
            ),
        ],
      );
    },
  );
}

/// The reference lap part of the Compare section (FET-175): load one from
/// a file or an earlier day, see it named, choose its lap, compare with
/// it, clear it. Shows [holder], which the day page keeps apart from the
/// day.
class ReferenceLapSection extends StatelessWidget {
  const ReferenceLapSection({
    super.key,
    required this.controller,
    required this.holder,
    required this.pickers,
    required this.onCompare,
    this.library,
  });

  final DayResultsController controller;
  final ReferenceLapHolder holder;

  /// Chooses the recording file, as adding recordings does.
  final RecordingPickers pickers;

  /// The driver profile whose days can give a reference; none when null.
  final ProfileLibrary? library;

  /// Opens the comparison of today's lap [a] with the reference.
  final void Function(DayLapRow a) onCompare;

  Future<void> _loadFile(TimingGate gate) async {
    final paths = await pickers.pickRecordings();
    if (paths.isEmpty) return;
    await holder.load(ReferenceFile(paths.first), gate);
  }

  Future<void> _loadDay(BuildContext context, TimingGate gate) async {
    final library = this.library;
    if (library == null) return;
    final day = await pickReferenceDay(context, library, controller.eventId);
    if (day == null) return;
    await holder.load(day, gate);
  }

  Future<void> _chooseLap(BuildContext context) async {
    final lap = await pickReferenceLap(context, holder);
    if (lap != null) holder.choose(lap);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([holder, controller]),
    builder: (context, _) {
      final theme = Theme.of(context);
      final l10n = context.l10n;
      final gate = referenceGate(controller);
      final best = controller.ranking?.bestOfDay;
      final library = this.library;
      final days = library != null && library.available;
      final loading = holder.state == ReferenceState.loading;
      final label = referenceLabel(l10n, holder);
      final problem = referenceProblemText(l10n, holder);
      final muted = theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Column(
        key: const ValueKey('referenceSection'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.referenceTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.referenceIntro, style: muted),
          const SizedBox(height: 12),
          if (gate == null)
            Text(
              l10n.referenceNeedsLap,
              key: const ValueKey('referenceNeedsLap'),
              style: muted,
            ),
          if (loading)
            Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.referenceLoading(holder.source?.name ?? ''),
                    key: const ValueKey('referenceLoading'),
                  ),
                ),
              ],
            ),
          if (problem.isNotEmpty)
            Text(
              problem,
              key: const ValueKey('referenceProblem'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          if (label != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: lapBColor,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(label, key: const ValueKey('referenceLabel')),
                subtitle: Text(l10n.referenceNotSaved),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (label != null && best != null)
                FilledButton.icon(
                  key: const ValueKey('referenceCompare'),
                  onPressed: () => onCompare(best),
                  icon: const Icon(Icons.compare_arrows),
                  label: Text(l10n.referenceCompare),
                ),
              if (label != null && (holder.timing?.candidates.length ?? 0) > 1)
                OutlinedButton(
                  key: const ValueKey('referenceChooseLap'),
                  onPressed: () => _chooseLap(context),
                  child: Text(l10n.referenceChooseLap),
                ),
              OutlinedButton.icon(
                key: const ValueKey('referenceLoadFile'),
                onPressed: gate == null || loading
                    ? null
                    : () => _loadFile(gate),
                icon: const Icon(Icons.file_open_outlined),
                label: Text(l10n.referenceLoadFile),
              ),
              if (days)
                OutlinedButton.icon(
                  key: const ValueKey('referenceLoadDay'),
                  onPressed: gate == null || loading
                      ? null
                      : () => _loadDay(context, gate),
                  icon: const Icon(Icons.history),
                  label: Text(l10n.referenceLoadDay),
                ),
              if (holder.state != ReferenceState.none)
                TextButton.icon(
                  key: const ValueKey('referenceClear'),
                  onPressed: holder.clear,
                  icon: const Icon(Icons.close),
                  label: Text(l10n.referenceClear),
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// The units of channel [alias] on today's lap and on the reference, each
/// as its recording declares it or as assumed for an unlabelled speed.
ReferenceChannelUnits _units(
  DayResultsController controller,
  DayLapRow a,
  TelemetrySession reference,
  String alias,
) {
  final assumed = speedUnitSetting.value.unit;
  TelemetrySession? recording;
  for (final named in controller.runs) {
    if (named.run.id == a.runId) recording = named.run.telemetry;
  }
  final own = recording == null
      ? null
      : referenceChannelUnits(recording, reference, alias, assumed: assumed);
  if (own != null && own.today.recorded) return own;
  // A channel fused from the session's other recording: its unit as the
  // analysis reads it.
  return referenceChannelUnits(
    controller.session(a.runId) ?? reference,
    reference,
    alias,
    assumed: assumed,
  );
}

/// Today's lap [a] (amber) against the reference lap (blue) on [a]'s
/// track-position axis: the Δ time (A − reference), speed, throttle and
/// brake in each side's own unit, and today's segments timed on both laps.
/// Nothing here changes the day.
class ReferenceComparisonPage extends StatefulWidget {
  const ReferenceComparisonPage({
    super.key,
    required this.controller,
    required this.holder,
    required this.a,
  });

  final DayResultsController controller;
  final ReferenceLapHolder holder;
  final DayLapRow a;

  @override
  State<ReferenceComparisonPage> createState() =>
      _ReferenceComparisonPageState();
}

class _ReferenceComparisonPageState extends State<ReferenceComparisonPage> {
  late DayLapRow _a = widget.a;
  ReferenceLapComparison? _comparison;
  ChartWindow? _window;
  ReferenceLapCandidate? _builtFor;
  List<ReferenceSegmentTime> _segments = const [];
  final Map<String, ChartSeries> _series = {};
  (double, double)? _seriesRange;

  @override
  void initState() {
    super.initState();
    widget.holder.addListener(_referenceChanged);
    _build();
  }

  @override
  void dispose() {
    widget.holder.removeListener(_referenceChanged);
    _window?.dispose();
    super.dispose();
  }

  void _referenceChanged() {
    if (!identical(widget.holder.lap, _builtFor)) setState(_build);
  }

  void _build() {
    _window?.dispose();
    _window = null;
    _comparison = null;
    _segments = const [];
    _series.clear();
    _seriesRange = null;
    final holder = widget.holder, controller = widget.controller;
    final lap = _builtFor = holder.lap;
    final timing = holder.timing, recording = holder.session;
    if (lap == null || timing == null || recording == null) return;
    final session = controller.session(_a.runId);
    LapSession? laps;
    for (final named in controller.runs) {
      if (named.run.id == _a.runId) laps = named.run.laps;
    }
    if (session == null || laps == null) return;
    final comparison = _comparison = ReferenceLapComparison(
      today: ComparisonLap(
        session: session,
        laps: laps,
        start: _a.start,
        end: _a.end,
        lapNumber: _a.lapNumber,
      ),
      timing: timing,
      lap: lap,
      // As every analysis reads a speed: its declared unit, else the one
      // assumed in settings.
      referenceSession: withEffectiveSpeedUnits(
        recording,
        assumed: speedUnitSetting.value.unit,
      ),
      segmentation: controller.segmentationFor(_a),
    );
    if (!comparison.comparison.axis.valid) return;
    _window = ChartWindow(0, comparison.comparison.axisLengthMeters);
    _segments = comparison.segmentTimes();
  }

  Future<void> _changeA() async {
    final controller = widget.controller;
    final picked = await pickComparisonLap(
      context,
      title: context.l10n.pickLapA,
      candidates: [
        for (final row in controller.comparisonCandidates(_a))
          if (row.reference != _a.reference) row,
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _a = picked;
      _build();
    });
  }

  ChartSeries _seriesOf(int slot, String channel, (double, double) range) {
    if (_seriesRange != range) {
      _seriesRange = range;
      _series.clear();
    }
    final comparison = _comparison!.comparison;
    return _series['$slot|$channel'] ??= channel == deltaTimeChannel
        ? comparison.deltaSeries(range.$1, range.$2, 600)
        : comparison.channelSeries(slot, channel, range.$1, range.$2, 600);
  }

  Widget _badge(
    BuildContext context, {
    required Color color,
    required String title,
    String? subtitle,
    Key? key,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final content = Padding(
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
                  title,
                  key: key,
                  style: theme.textTheme.titleSmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) Text(subtitle),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.outline,
            ),
          ],
        ],
      ),
    );
    return onTap == null
        ? content
        : ButtonRow(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: content,
            ),
          );
  }

  Widget _header(BuildContext context, String label) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final comparison = _comparison;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _badge(
              context,
              key: const ValueKey('referenceComparisonLapA'),
              color: lapAColor,
              title: 'A · ${l10n.lap(_a)}',
              subtitle: displayTime(_a.durationSeconds),
              onTap: _changeA,
            ),
            _badge(
              context,
              key: const ValueKey('referenceComparisonLabel'),
              color: lapBColor,
              title: label,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (comparison != null)
          Text(
            l10n.compareLapDelta(displayDelta(comparison.lapDeltaSeconds)),
            key: const ValueKey('referenceLapDelta'),
            style: theme.textTheme.titleLarge,
          ),
        Text(l10n.referenceDeltaExplained, style: theme.textTheme.bodySmall),
        Text(l10n.referenceKeptApart, style: theme.textTheme.bodySmall),
      ],
    );
  }

  String _unitText(AppLocalizations l10n, ReferenceUnit unit) {
    if (unit.unit.isEmpty) return l10n.referenceUnitNone;
    return unit.assumed ? l10n.referenceUnitAssumed(unit.unit) : unit.unit;
  }

  List<Widget> _charts(BuildContext context) {
    final l10n = context.l10n;
    final reference = widget.holder.session!;
    final comparison = _comparison!.comparison;
    final window = _window!;
    final length = comparison.axisLengthMeters;
    final today = comparison.a.session, referenceSession = comparison.b.session;
    return [
      ChartWindowControls(
        window: window,
        axisText: (meters) => '${meters.round()} m',
      ),
      ValueListenableBuilder(
        valueListenable: window.range,
        builder: (context, range, _) {
          final charts = <Widget>[
            TelemetryChart(
              key: const ValueKey('referenceChart delta'),
              title: l10n.compareDeltaChart,
              lines: [
                ChartLine(
                  '',
                  _seriesOf(0, deltaTimeChannel, range),
                  deltaLineColor,
                ),
              ],
              start: range.$1,
              end: range.$2,
              cursor: window.cursor,
              onCursor: (value) => window.cursor.value = value,
              valueAxis: chartValueAxis([
                comparison.deltaSeries(0, length, 300),
              ], zeroLine: true),
              zeroLine: true,
              delta: true,
              note: l10n.referenceDeltaNote,
            ),
          ];
          for (final (alias, name) in [
            ('speed', l10n.compareLayerSpeed),
            ('throttle', l10n.compareLayerThrottle),
            ('brake', l10n.compareLayerBrake),
          ]) {
            final units = _units(widget.controller, _a, reference, alias);
            if (!units.today.recorded && !units.reference.recorded) continue;
            final unitsNote = l10n.referenceUnits(
              _unitText(l10n, units.today),
              _unitText(l10n, units.reference),
            );
            final todayName = today.aliases[alias] ?? alias;
            final referenceName = referenceSession.aliases[alias] ?? alias;
            TelemetryChart chart(
              String key,
              String title,
              List<(int, String)> slots,
              String note,
            ) => TelemetryChart(
              key: ValueKey('referenceChart $key'),
              title: title,
              lines: [
                for (final (slot, label) in slots)
                  ChartLine(
                    label,
                    _seriesOf(slot, alias, range),
                    slot == 0 ? lapAColor : lapBColor,
                  ),
              ],
              start: range.$1,
              end: range.$2,
              cursor: window.cursor,
              onCursor: (value) => window.cursor.value = value,
              valueAxis: chartValueAxis([
                for (final (slot, _) in slots)
                  comparison.channelSeries(slot, alias, 0, length, 300),
              ]),
              note: note,
              // The reference is not one of the day's recordings.
              source: '',
              unitsAsRecorded: true,
            );
            if (units.comparable ||
                !units.today.recorded ||
                !units.reference.recorded) {
              charts.add(
                chart(alias, units.today.recorded ? todayName : referenceName, [
                  (0, 'A'),
                  (1, l10n.referenceShort),
                ], unitsNote),
              );
            } else {
              // Different units: one chart each, never on one axis.
              final apart = '${l10n.referenceUnitsApart} $unitsNote';
              charts
                ..add(
                  chart('$alias A', l10n.referenceChartOf(name, 'A'), [
                    (0, 'A'),
                  ], apart),
                )
                ..add(
                  chart(
                    '$alias reference',
                    l10n.referenceChartOf(name, l10n.referenceShort),
                    [(1, l10n.referenceShort)],
                    apart,
                  ),
                );
            }
          }
          return Column(
            children: [
              for (final chart in charts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: chart,
                ),
            ],
          );
        },
      ),
    ];
  }

  Widget _segmentTable(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = FetColors.of(context);
    final comparison = _comparison!;
    final segmentation = comparison.segmentation;
    final length = comparison.comparison.axisLengthMeters;
    final mono = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: FetTheme.mono,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget cell(String text, {TextStyle? style, Color? color}) => SizedBox(
      width: 84,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: (style ?? mono)?.copyWith(color: color),
      ),
    );
    final header = theme.textTheme.labelMedium;
    return Column(
      key: const ValueKey('referenceSegments'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.referenceSegmentsTitle, style: theme.textTheme.titleMedium),
        if (segmentation.shared == null)
          Text(
            l10n.referenceSegmentsNone,
            key: const ValueKey('referenceSegmentsNone'),
            style: theme.textTheme.bodySmall,
          )
        else ...[
          if (segmentation.borrowed)
            Text(
              l10n.referenceSegmentsBorrowed,
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(l10n.referenceColumnSegment, style: header)),
              cell('A', style: header),
              cell(l10n.referenceShort, style: header),
              cell('Δ', style: header),
            ],
          ),
          for (final time in _segments)
            Padding(
              key: ValueKey('referenceSegment ${time.segment.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: time.deltaSeconds == null
                  ? Text(
                      l10n.referenceSegmentNotTimed(
                        segmentPickerLabel(l10n, time.segment, length),
                        cornerReasonText(l10n, time.unavailableReason),
                      ),
                      style: theme.textTheme.bodySmall,
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            segmentPickerLabel(l10n, time.segment, length),
                          ),
                        ),
                        cell(displayTime(time.todaySeconds!)),
                        cell(displayTime(time.referenceSeconds!)),
                        cell(
                          displayDelta(time.deltaSeconds!),
                          color: time.deltaSeconds! > 0
                              ? colors.loss
                              : time.deltaSeconds! < 0
                              ? colors.gain
                              : null,
                        ),
                      ],
                    ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = referenceLabel(l10n, widget.holder);
    final comparison = _comparison;
    final ready = comparison != null && _window != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.referenceCompareTitle)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(constraints.maxWidth, 960.0);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: ListView(
                key: const ValueKey('referenceComparison'),
                padding: const EdgeInsets.all(16),
                children: [
                  if (label == null)
                    Text(
                      l10n.referenceGone,
                      key: const ValueKey('referenceComparisonGone'),
                    )
                  else ...[
                    _header(context, label),
                    const SizedBox(height: 12),
                    if (!ready)
                      Text(
                        comparison == null
                            ? l10n.compareRecordingsUnavailable
                            : l10n.compareNoSharedPosition,
                        key: const ValueKey('referenceComparisonUnavailable'),
                      )
                    else ...[
                      _segmentTable(context),
                      const SizedBox(height: 16),
                      Text(
                        l10n.compareChannelsByPosition,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ..._charts(context),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      l10n.compareDisclaimer,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
