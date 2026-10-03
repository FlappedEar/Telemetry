import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../units.dart';
import 'comparison_page.dart';
import 'corner_details.dart' show cornerReasonText, lapAColor, lapBColor;
import 'day_results_controller.dart';
import 'telemetry_chart.dart' show ChartWindow;
import 'touch.dart';

/// The Corner Analyzer under a comparison's charts (registered in
/// [comparisonPanels]).
Widget? cornerAnalyzerPanel(
  BuildContext context,
  ComparisonPanelContext panel,
) => CornerAnalyzerPanel(key: const ValueKey('cornerAnalyzer'), panel: panel);

/// Overlays' Corner Analyzer for laps A and B: the approved segments both
/// share and, for the chosen one, a one-line summary, a chart of both laps'
/// speed through it (with the braking points, throttle pickups and lowest
/// speeds on the lines) and A, B and Δ (A − B) of its figures, grouped as a
/// driver reads a corner: time, braking, corner, exit. Choosing a segment
/// zooms the charts to it and puts the cursor in its middle.
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

/// The segment picker's label: "Corner 1 · 170 m". The type is added only
/// when the name does not already say it ("S1 · sector · 300 m").
String segmentPickerLabel(ComparisonSegment segment, double axisLength) {
  final type = segment.type.trim();
  final length = '${segmentLengthMeters(segment, axisLength).round()} m';
  final name = segment.name.trim();
  if (type.isEmpty || name.toLowerCase().contains(type.toLowerCase())) {
    return '$name · $length';
  }
  return '$name · $type · $length';
}

String _unit(String unit) => unit.trim().isEmpty ? '' : ' ${unit.trim()}';

String _signed(double value, int digits, String unit) {
  final text = value.abs().toStringAsFixed(digits);
  if (double.parse(text) == 0) return '±$text$unit';
  return '${value > 0 ? '+' : '−'}$text$unit';
}

bool _rounded(double value, int digits) =>
    double.parse(value.abs().toStringAsFixed(digits)) == 0;

/// One plain line on who is faster through the segment, from the sector
/// time's Δ and, when one lap also carries more speed, the largest speed
/// difference in its favour: "A is 0.015 s faster here and carries 5.7 km/h
/// more entry speed." Null without a sector time on both laps.
String? cornerAnalyzerSummary(SegmentAnalysis analysis) {
  final delta = analysis.sectorTime?.delta.value;
  if (delta == null || !delta.isFinite) return null;
  if (_rounded(delta, 3)) return 'A and B take the same time here.';
  final faster = delta < 0 ? 'A' : 'B';
  final time = '${delta.abs().toStringAsFixed(3)} s';
  final corner = analysis.corner;
  final unit = speedUnitLabel(corner?.unit ?? analysis.speeds.unit);
  final speeds = corner != null
      ? [
          ('entry speed', corner.entry.delta.value),
          ('minimum speed', corner.minimum.delta.value),
          ('exit speed', corner.exit.delta.value),
        ]
      : [
          ('entry speed', analysis.speeds.entry.delta.value),
          ('lowest speed', analysis.speeds.minimum.delta.value),
          ('exit speed', analysis.speeds.exit.delta.value),
        ];
  String? reason;
  var largest = 0.0;
  for (final (name, value) in speeds) {
    if (value == null || !value.isFinite) continue;
    // In the faster lap's favour: A's speed higher when A is faster.
    final favour = delta < 0 ? value : -value;
    if (favour > largest && !_rounded(favour, 1)) {
      largest = favour;
      reason = name;
    }
  }
  if (reason == null) return '$faster is $time faster here.';
  return '$faster is $time faster here and carries '
      '${largest.toStringAsFixed(1)}${_unit(unit)} more $reason.';
}

class _CornerAnalyzerPanelState extends State<CornerAnalyzerPanel> {
  String? _selected;
  bool _focusApplied = false;

  ComparisonPanelContext get _panel => widget.panel;

  // The segment chosen is kept for the page: on a phone the list rebuilds
  // the panel when it scrolls back, which must not choose (and zoom to) the
  // segment it was opened on again.
  static const _storage = 'cornerAnalyzerSegment';

  @override
  void initState() {
    super.initState();
    final kept = readPageState<(Object, Object, String?)>(context, _storage);
    if (kept != null &&
        kept.$1 == _panel.a.reference &&
        kept.$2 == _panel.b.reference) {
      _selected = kept.$3;
      _focusApplied = true;
    }
  }

  void _remember() => writePageState(context, _storage, (
    _panel.a.reference,
    _panel.b.reference,
    _selected,
  ));

  void _select(ComparisonSegment segment, {bool scroll = false}) {
    setState(() => _selected = segment.id);
    _remember();
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
                              segmentPickerLabel(segment, length),
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
    final summary = analysis == null ? null : cornerAnalyzerSummary(analysis);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return [
      if (summary != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            summary,
            key: const ValueKey('cornerAnalyzerSummary'),
            style: theme.textTheme.titleSmall,
          ),
        ),
      if (analysis != null && segment.endMeters > segment.startMeters)
        SegmentSpeedChart(
          key: const ValueKey('cornerAnalyzerChart'),
          comparison: _panel.comparison,
          analysis: analysis,
          window: _panel.window,
          lapNames: [_panel.a.displayName, _panel.b.displayName],
        )
      else if (analysis != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'No speed chart: this segment crosses the start/finish line.',
            key: const ValueKey('cornerAnalyzerNoChart'),
            style: small,
          ),
        ),
      const SizedBox(height: 8),
      if (analysis == null)
        const Text('No figures for this segment.')
      else
        AnalyzerTable(analysis: analysis, heartRate: heartRate),
      const SizedBox(height: 6),
      if (heartRate != null && heartRate.laps.any((lap) => lap.valid))
        Text(
          'Heart rate: mean over this segment · A '
          '${_coverage(heartRate.laps[0])} · B ${_coverage(heartRate.laps[1])}. '
          'Observed values only.',
          key: const ValueKey('cornerAnalyzerHeartRateNote'),
          style: small,
        ),
      Text(
        'Δ is A − B, coloured by the lap that is faster or carries more '
        'speed. '
        '${analysis?.braking != null || analysis?.exitEffects != null ? 'Braking and pickup are distances from the corner entry; braking later or picking up earlier is not automatically faster. ' : ''}'
        'Observed differences, not instructions.',
        style: small,
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
    return summary.unavailableReason == channelSummaryMissing
        ? 'not recorded'
        : 'no valid samples';
  }
  return '${summary.sampleCount} samples, '
      '${(summary.coverage * 100).round()}% covered';
}

/// How a row's Δ reads: who is faster, who carries more, or which way a
/// position or an amount differs (not better or worse).
enum _Compare { time, speed, position, amount }

/// One row of the table: how to show its values.
typedef _Row = ({
  String id,
  String label,
  AnalyzerMetric metric,
  String Function(double value) value,
  String Function(double delta) delta,
  // The Δ shown, from the analyzer's A − B.
  double Function(double delta) shownDelta,
  _Compare compare,
  // Words for a positive and a negative Δ.
  (String, String) words,
});

typedef _Group = (String, List<_Row>);

double _same(double value) => value;

/// A, B and Δ (A − B) of a segment's figures, grouped into time, braking,
/// corner and exit, every value with its unit. A missing value says why in
/// words under the row's name; a value inferred from another channel says
/// so.
class AnalyzerTable extends StatelessWidget {
  const AnalyzerTable({super.key, required this.analysis, this.heartRate});

  final SegmentAnalysis analysis;
  final ComparisonHeartRate? heartRate;

  List<_Group> _groups(BuildContext context) {
    final segment = analysis.segment;
    final corner = analysis.corner;
    final speedUnit = _unit(
      speedUnitOf(context, corner?.unit ?? analysis.speeds.unit),
    );
    String speed(double v) => '${v.toStringAsFixed(1)}$speedUnit';
    String speedDelta(double d) => _signed(d, 1, speedUnit);
    String meters(double v) => '${v.round()} m';
    String metersDelta(double d) => _signed(d, 0, ' m');

    _Row speedRow(String id, String label, AnalyzerMetric metric) => (
      id: id,
      label: label,
      metric: metric,
      value: speed,
      delta: speedDelta,
      shownDelta: _same,
      compare: _Compare.speed,
      words: ('A higher', 'B higher'),
    );

    final groups = <_Group>[];
    if (analysis.sectorTime case final metric?) {
      groups.add((
        'Time',
        [
          (
            id: 'sectorTime',
            label: segment.corner ? 'Time through the corner' : 'Sector time',
            metric: metric,
            value: displayTime,
            delta: displayDelta,
            shownDelta: _same,
            compare: _Compare.time,
            words: ('B faster', 'A faster'),
          ),
        ],
      ));
    }

    if (analysis.braking case final braking?) {
      // Shown as metres before the corner entry; the analyzer's Δ is along
      // the lap, so a later braking point is a smaller distance before it.
      final entry = segment.startMeters;
      final decelerationUnit = _unit(
        analysis.brakingMetrics
                ?.map((lap) => lap.decelerationUnit)
                .firstWhere((unit) => unit.isNotEmpty, orElse: () => '') ??
            '',
      );
      AnalyzerMetric beforeEntry(AnalyzerMetric metric) {
        AnalyzerValue side(AnalyzerValue value) => AnalyzerValue(
          value: value.value == null ? null : entry - value.value!,
          provenance: value.provenance,
          unavailableReason: value.unavailableReason,
        );
        return AnalyzerMetric(
          a: side(metric.a),
          b: side(metric.b),
          delta: metric.delta,
        );
      }

      groups.add((
        'Braking',
        [
          (
            id: 'brakingPoint',
            label: 'Braking starts, before entry',
            metric: beforeEntry(braking.point),
            value: meters,
            delta: metersDelta,
            shownDelta: (d) => -d,
            compare: _Compare.position,
            words: ('A brakes earlier', 'A brakes later'),
          ),
          (
            id: 'brakingTime',
            label: 'Time on the brakes',
            metric: braking.seconds,
            value: (v) => '${v.toStringAsFixed(2)} s',
            delta: (d) => _signed(d, 2, ' s'),
            shownDelta: _same,
            compare: _Compare.amount,
            words: ('A longer', 'A shorter'),
          ),
          (
            id: 'peakDeceleration',
            label: 'Peak deceleration',
            metric: braking.peakDeceleration,
            value: (v) => '${v.toStringAsFixed(2)}$decelerationUnit',
            delta: (d) => _signed(d, 2, decelerationUnit),
            shownDelta: _same,
            compare: _Compare.amount,
            words: ('A harder', 'A softer'),
          ),
        ],
      ));
    }

    if (corner != null) {
      groups.add((
        'Corner',
        [
          speedRow('entry', 'Entry speed', corner.entry),
          speedRow('apex', 'Apex speed', corner.apex),
          speedRow('minimum', 'Minimum speed', corner.minimum),
        ],
      ));
    } else {
      groups.add((
        segment.corner ? 'Corner' : 'Speed',
        [
          speedRow('entry', 'Entry speed', analysis.speeds.entry),
          speedRow('maximum', 'Top speed', analysis.speeds.maximum),
          speedRow('minimum', 'Lowest speed', analysis.speeds.minimum),
          if (!segment.corner)
            speedRow('exit', 'Exit speed', analysis.speeds.exit),
        ],
      ));
    }

    if (segment.corner) {
      final exit = analysis.exitEffects;
      AnalyzerMetric afterEntry(AnalyzerMetric metric) {
        AnalyzerValue side(AnalyzerValue value) => AnalyzerValue(
          value: value.value == null
              ? null
              : value.value! - segment.startMeters,
          provenance: value.provenance,
          unavailableReason: value.unavailableReason,
        );
        return AnalyzerMetric(
          a: side(metric.a),
          b: side(metric.b),
          delta: metric.delta,
        );
      }

      groups.add((
        'Exit',
        [
          speedRow('exit', 'Exit speed', corner?.exit ?? analysis.speeds.exit),
          if (exit != null)
            (
              id: 'pickup',
              label: 'Throttle pickup, after entry',
              metric: afterEntry(exit.pickup),
              value: meters,
              delta: metersDelta,
              shownDelta: _same,
              compare: _Compare.position,
              words: ('A later', 'A earlier'),
            ),
        ],
      ));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final groups = _groups(context);

    Widget cell(
      String key,
      String text, {
      String note = '',
      TextStyle? style,
      Color? noteColor,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // A number stays on one line, a little smaller if a phone's
          // column is too narrow for large text.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              text,
              key: ValueKey('cornerAnalyzer $key'),
              style: style ?? numbers,
              textAlign: TextAlign.end,
            ),
          ),
          if (note.isNotEmpty)
            Text(
              note,
              key: ValueKey('cornerAnalyzer $key note'),
              style: noteColor == null
                  ? small
                  : small?.copyWith(color: noteColor),
              textAlign: TextAlign.end,
            ),
        ],
      ),
    );

    Widget side(String key, AnalyzerValue side, String Function(double) show) {
      final value = side.value;
      if (value == null) return cell(key, '—');
      return cell(
        key,
        show(value),
        note: side.provenance == metricInferred ? 'inferred' : '',
      );
    }

    Widget delta(String key, _Row row) {
      final raw = row.metric.delta.value;
      if (raw == null || !raw.isFinite) return cell(key, '—');
      final shown = row.shownDelta(raw);
      final text = row.delta(shown);
      final level = text.startsWith('±');
      final (positive, negative) = row.words;
      final words = level ? 'same' : (shown > 0 ? positive : negative);
      Color? color;
      if (!level) {
        // Time: a negative Δ is A faster. Speed: a positive Δ is A higher.
        color = switch (row.compare) {
          _Compare.time => shown < 0 ? lapAColor : lapBColor,
          _Compare.speed => shown > 0 ? lapAColor : lapBColor,
          _ => null,
        };
      }
      return cell(
        key,
        text,
        note: words,
        style: numbers?.copyWith(fontWeight: FontWeight.w600, color: color),
        noteColor: color,
      );
    }

    // Why a row has no value or no Δ, in words, under its name.
    String why(_Row row) {
      final metric = row.metric;
      String? reason(AnalyzerValue value) => value.value == null
          ? _sentence(cornerReasonText(value.unavailableReason))
          : null;
      final a = reason(metric.a), b = reason(metric.b);
      if (a != null && b != null) {
        return a == b ? '$a (both laps)' : 'A: $a · B: $b';
      }
      if (a != null) return 'A: $a';
      if (b != null) return 'B: $b';
      if (metric.delta.value == null &&
          metric.delta.unavailableReason.isNotEmpty) {
        return 'Not compared: ${cornerReasonText(metric.delta.unavailableReason)}';
      }
      return '';
    }

    Widget label(String key, String text, String note) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (note.isNotEmpty)
            Text(note, key: ValueKey('cornerAnalyzer $key note'), style: small),
        ],
      ),
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

    final divider = BoxDecoration(
      border: Border(
        top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
      ),
    );
    // A unit the recording does not declare is said once, at its group.
    final speedUnitMissing = speedUnitOf(
      context,
      analysis.corner?.unit ?? analysis.speeds.unit,
    ).isEmpty;
    final decelerationUnitMissing = (analysis.brakingMetrics ?? const []).every(
      (lap) => lap.decelerationUnit.trim().isEmpty,
    );
    TableRow group(String name) => TableRow(
      key: ValueKey('cornerAnalyzerGroupRow $name'),
      decoration: divider,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.toUpperCase(),
                key: ValueKey('cornerAnalyzerGroup $name'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
      ],
    );

    final laps = heartRate?.laps ?? const <HeartRateLap>[];
    final heartRateShown = laps.length == 2 && laps.any((lap) => lap.valid);
    String bpm(HeartRateLap lap) =>
        lap.valid ? '${lap.summary.mean!.toStringAsFixed(0)} bpm' : '—';

    final missing = [
      if (speedUnitMissing) 'speed',
      if (decelerationUnitMissing && analysis.braking != null) 'deceleration',
    ];
    final table = Table(
      key: const ValueKey('cornerAnalyzerTable'),
      columnWidths: const {
        0: FlexColumnWidth(1.35),
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
        for (final (name, rows) in groups) ...[
          group(name),
          for (final row in rows)
            TableRow(
              key: ValueKey('cornerAnalyzerRow ${row.id}'),
              children: [
                label(row.id, row.label, why(row)),
                side('${row.id} A', row.metric.a, row.value),
                side('${row.id} B', row.metric.b, row.value),
                delta('${row.id} Δ', row),
              ],
            ),
        ],
        if (heartRateShown) ...[
          group('Driver'),
          TableRow(
            key: const ValueKey('cornerAnalyzerRow heartRate'),
            children: [
              label('heartRate', 'Heart rate', ''),
              cell('heartRate A', bpm(laps[0])),
              cell('heartRate B', bpm(laps[1])),
              laps[0].valid && laps[1].valid
                  ? cell(
                      'heartRate Δ',
                      _signed(
                        laps[0].summary.mean! - laps[1].summary.mean!,
                        0,
                        ' bpm',
                      ),
                      style: numbers?.copyWith(fontWeight: FontWeight.w600),
                    )
                  : cell('heartRate Δ', '—'),
            ],
          ),
        ],
      ],
    );
    if (missing.isEmpty) return table;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This recording does not declare its ${missing.join(' and ')} '
          'unit${missing.length > 1 ? 's' : ''}: those values are shown as '
          'recorded, without a unit.',
          key: const ValueKey('cornerAnalyzerUnitNote'),
          style: small,
        ),
        const SizedBox(height: 4),
        table,
      ],
    );
  }
}

String _sentence(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// Both laps' speed through a segment and a lead-in before it, on the shared
/// axis, against metres from the segment's start: the segment shaded between
/// its entry and exit, its apex dashed, and each lap's braking point (▲),
/// throttle pickup (◆) and lowest speed (●) drawn on that lap's line. A tap
/// or a drag moves the shared cursor.
class SegmentSpeedChart extends StatelessWidget {
  const SegmentSpeedChart({
    super.key,
    required this.comparison,
    required this.analysis,
    required this.window,
    this.lapNames = const ['', ''],
    this.height = 220,
  });

  final LapComparison comparison;
  final SegmentAnalysis analysis;
  final ChartWindow window;

  /// Lap A's and lap B's names for the legend.
  final List<String> lapNames;
  final double height;

  /// The progress range drawn: a lead-in before the segment (enough to show
  /// the braking points), the segment, the throttle pickups and a short
  /// run-out, within the axis.
  (double, double) get range {
    final segment = analysis.segment;
    final length = math.max(0.0, segment.endMeters - segment.startMeters);
    var start = segment.startMeters - math.max(40.0, length * 0.3);
    var end = segment.endMeters + math.max(20.0, length * 0.12);
    for (final braking in analysis.brakingMetrics ?? const <BrakingMetrics>[]) {
      if (braking.brakingPointMeters case final point?) {
        start = math.min(start, point - 20);
      }
    }
    for (final exit in analysis.exitMetrics ?? const <ExitMetrics>[]) {
      if (exit.pickup.progressMeters case final point?) {
        end = math.max(end, point + 15);
      }
    }
    return (math.max(0.0, start), math.min(comparison.axisLengthMeters, end));
  }

  /// The markers of both laps, each at its distance along the shared axis.
  List<SpeedChartMarker> get markers {
    final markers = <SpeedChartMarker>[];
    for (final slot in const [0, 1]) {
      final braking = analysis.brakingMetrics?[slot].brakingPointMeters;
      if (braking != null) {
        markers.add((kind: SpeedMarkerKind.braking, slot: slot, at: braking));
      }
      final pickup = analysis.exitMetrics?[slot].pickup.progressMeters;
      if (pickup != null) {
        markers.add((kind: SpeedMarkerKind.pickup, slot: slot, at: pickup));
      }
      final minimum = analysis.cornerSpeeds?[slot].minimum;
      if (minimum != null && minimum.value != null) {
        markers.add((
          kind: SpeedMarkerKind.minimum,
          slot: slot,
          at: minimum.progressMeters,
        ));
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (start, end) = range;
    final series = [
      for (final slot in const [0, 1])
        comparison.channelSeries(slot, 'speed', start, end, 300),
    ];
    final hasData = series.any((series) => series.hasData);
    final unit = speedUnitOf(
      context,
      series
          .firstWhere((series) => series.hasData, orElse: () => series.first)
          .unit,
    ).trim();
    final segment = analysis.segment;
    final apex = analysis.phases?.apex;
    final apexes = apex == null
        ? const <double>[]
        : apex.resolved
        ? [apex.progressMeters]
        : analysis.phases!.apexCandidatesMeters;
    final corner = segment.corner;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final painterStyle = (theme.textTheme.labelSmall ?? const TextStyle())
        .copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11);

    double plotLeft(double width) => SegmentSpeedPainter.leftGutter;
    double plotWidth(double width) => math.max(
      1.0,
      width - SegmentSpeedPainter.leftGutter - SegmentSpeedPainter.rightGutter,
    );
    void move(double dx, double width) {
      final fraction = ((dx - plotLeft(width)) / plotWidth(width)).clamp(
        0.0,
        1.0,
      );
      window.cursor.value = start + (end - start) * fraction;
    }

    if (!hasData) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          series.every((series) => series.reason == chartReasonChannelMissing)
              ? 'No speed recorded on either lap: no speed chart.'
              : 'No speed samples on either lap through ${segment.name}.',
          key: const ValueKey('cornerAnalyzerChartEmpty'),
          style: small,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              'Speed through ${segment.name}',
              key: const ValueKey('cornerAnalyzerChartTitle'),
              style: theme.textTheme.titleSmall,
            ),
            ValueListenableBuilder<double>(
              valueListenable: window.cursor,
              builder: (context, cursor, _) {
                if (cursor < start || cursor > end) {
                  return const SizedBox.shrink();
                }
                String at(int slot) {
                  final value = seriesValueAt(series[slot], start, end, cursor);
                  return value == null ? '—' : value.toStringAsFixed(1);
                }

                final offset = (cursor - segment.startMeters).round();
                return Text.rich(
                  key: const ValueKey('cornerAnalyzerChartCursor'),
                  TextSpan(
                    style: small,
                    children: [
                      TextSpan(
                        text:
                            'Cursor ${offset < 0 ? '−' : ''}${offset.abs()} m: ',
                      ),
                      TextSpan(
                        text: 'A ${at(0)}',
                        style: const TextStyle(color: lapAColor),
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: 'B ${at(1)}',
                        style: const TextStyle(color: lapBColor),
                      ),
                      TextSpan(text: unit.isEmpty ? '' : ' $unit'),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Semantics(
          label: 'Speed through ${segment.name} chart',
          child: SizedBox(
            height: height,
            child: LayoutBuilder(
              // Sideways drags and taps move the cursor; upward and downward
              // drags scroll the page.
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    move(details.localPosition.dx, constraints.maxWidth),
                onHorizontalDragStart: (details) =>
                    move(details.localPosition.dx, constraints.maxWidth),
                onHorizontalDragUpdate: (details) =>
                    move(details.localPosition.dx, constraints.maxWidth),
                child: ValueListenableBuilder<double>(
                  valueListenable: window.cursor,
                  builder: (context, cursor, _) => CustomPaint(
                    key: const ValueKey('cornerAnalyzerChartPlot'),
                    size: Size(constraints.maxWidth, height),
                    painter: SegmentSpeedPainter(
                      start: start,
                      end: end,
                      segmentStart: segment.startMeters,
                      segmentEnd: segment.endMeters,
                      series: series,
                      markers: markers,
                      minimumSpeeds: [
                        for (final slot in const [0, 1])
                          analysis.cornerSpeeds?[slot].minimum.value,
                      ],
                      apexes: apexes,
                      boundaryNames: corner
                          ? const ('Entry', 'Exit')
                          : const ('Start', 'End'),
                      unit: unit,
                      cursor: cursor,
                      cursorColor: theme.colorScheme.tertiary,
                      grid: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                      boundary: theme.colorScheme.outline,
                      shade: theme.colorScheme.onSurface.withValues(
                        alpha: 0.06,
                      ),
                      ink: theme.colorScheme.onSurfaceVariant,
                      surface: theme.colorScheme.surfaceContainerLow,
                      textStyle: painterStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: SegmentSpeedPainter.leftGutter,
            top: 2,
          ),
          child: Text(
            'Distance from the ${corner ? 'corner' : 'segment'} entry (m) · '
            'shaded: the ${corner ? 'corner' : 'segment'}'
            '${unit.isEmpty ? ' · speed unit not declared in the recording' : ''}',
            key: const ValueKey('cornerAnalyzerChartAxis'),
            style: small,
          ),
        ),
        const SizedBox(height: 6),
        _Legend(
          lapNames: lapNames,
          apex: apexes.isNotEmpty,
          kinds: {for (final marker in markers) marker.kind},
          ink: theme.colorScheme.onSurface,
          style: small,
        ),
      ],
    );
  }
}

/// [series]' value at [meters] of a chart drawn over [start]..[end] (its
/// points' x a fraction of that range), interpolated between neighbouring
/// points; null in a gap or outside the range.
double? seriesValueAt(
  ChartSeries series,
  double start,
  double end,
  double meters,
) {
  final span = end - start;
  if (span <= 0) return null;
  final fraction = (meters - start) / span;
  for (final part in series.segments) {
    if (part.isEmpty) continue;
    if (fraction < part.first.x - 1e-9 || fraction > part.last.x + 1e-9) {
      continue;
    }
    for (var index = 1; index < part.length; ++index) {
      final p0 = part[index - 1], p1 = part[index];
      if (fraction <= p1.x + 1e-12) {
        final width = p1.x - p0.x;
        if (width <= 0) return p1.y;
        final t = ((fraction - p0.x) / width).clamp(0.0, 1.0);
        return p0.y + (p1.y - p0.y) * t;
      }
    }
    return part.last.y;
  }
  return null;
}

/// What a chart marker shows.
enum SpeedMarkerKind { braking, pickup, minimum }

/// One lap's ([slot] 0 is A) marker at [at] metres along the shared axis.
typedef SpeedChartMarker = ({SpeedMarkerKind kind, int slot, double at});

Color _lapColor(int slot) => slot == 0 ? lapAColor : lapBColor;

/// A "nice" step (1, 2 or 5 × 10ⁿ) for about [count] ticks over [span].
double _niceStep(double span, double count) {
  if (span <= 0 || count <= 0) return 1;
  final raw = span / count;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
  final normalized = raw / magnitude;
  final nice = normalized <= 1
      ? 1
      : normalized <= 2
      ? 2
      : normalized <= 5
      ? 5
      : 10;
  return nice * magnitude.toDouble();
}

void _drawMarker(
  Canvas canvas,
  SpeedMarkerKind kind,
  Offset at,
  Color fill,
  Color outline, {
  double scale = 1,
}) {
  final path = Path();
  switch (kind) {
    case SpeedMarkerKind.braking:
      final s = 6.5 * scale;
      path
        ..moveTo(at.dx, at.dy - s)
        ..lineTo(at.dx + s, at.dy + s * 0.75)
        ..lineTo(at.dx - s, at.dy + s * 0.75)
        ..close();
    case SpeedMarkerKind.pickup:
      final s = 6 * scale;
      path
        ..moveTo(at.dx, at.dy - s)
        ..lineTo(at.dx + s, at.dy)
        ..lineTo(at.dx, at.dy + s)
        ..lineTo(at.dx - s, at.dy)
        ..close();
    case SpeedMarkerKind.minimum:
      path.addOval(Rect.fromCircle(center: at, radius: 4.5 * scale));
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale,
  );
  canvas.drawPath(path, Paint()..color = fill);
}

/// Paints [SegmentSpeedChart]: a speed axis with its unit and gridlines on
/// the left, metres from the segment's entry along the bottom.
class SegmentSpeedPainter extends CustomPainter {
  SegmentSpeedPainter({
    required this.start,
    required this.end,
    required this.segmentStart,
    required this.segmentEnd,
    required this.series,
    required this.markers,
    required this.minimumSpeeds,
    required this.apexes,
    required this.boundaryNames,
    required this.unit,
    required this.cursor,
    required this.cursorColor,
    required this.grid,
    required this.boundary,
    required this.shade,
    required this.ink,
    required this.surface,
    required this.textStyle,
  });

  static const leftGutter = 44.0;
  static const rightGutter = 10.0;
  static const topGutter = 24.0;
  static const bottomGutter = 20.0;

  final double start;
  final double end;
  final double segmentStart;
  final double segmentEnd;

  /// Lap A's and lap B's speed; each point's x is a fraction of
  /// [start]..[end].
  final List<ChartSeries> series;
  final List<SpeedChartMarker> markers;

  /// Each lap's lowest speed in the corner, as measured; labelled at its dot.
  final List<double?> minimumSpeeds;
  final List<double> apexes;
  final (String, String) boundaryNames;
  final String unit;
  final double cursor;
  final Color cursorColor;
  final Color grid;
  final Color boundary;
  final Color shade;
  final Color ink;
  final Color surface;
  final TextStyle textStyle;

  /// Lap [slot]'s speed at [meters], read from its line; null in a gap or
  /// outside the drawn range.
  double? speedAt(int slot, double meters) => slot < series.length
      ? seriesValueAt(series[slot], start, end, meters)
      : null;

  TextPainter _text(String text, {Color? color, FontWeight? weight}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: textStyle.copyWith(color: color, fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      leftGutter,
      topGutter,
      math.max(leftGutter + 1, size.width - rightGutter),
      math.max(topGutter + 1, size.height - bottomGutter),
    );
    final span = math.max(1e-9, end - start);
    double x(double meters) => plot.left + (meters - start) / span * plot.width;

    // The speed range: both lines, rounded out to whole gridlines.
    var low = double.infinity, high = -double.infinity;
    for (final line in series) {
      for (final part in line.segments) {
        for (final point in part) {
          low = math.min(low, point.y);
          high = math.max(high, point.y);
        }
      }
    }
    for (final value in minimumSpeeds) {
      if (value == null) continue;
      low = math.min(low, value);
      high = math.max(high, value);
    }
    if (!low.isFinite || !high.isFinite) return;
    if (high - low < 1) {
      low -= 0.5;
      high += 0.5;
    }
    final step = _niceStep(high - low, math.max(2, plot.height / 40));
    low = (low / step).floor() * step;
    high = (high / step).ceil() * step;
    if (high <= low) high = low + step;
    double y(double value) =>
        plot.bottom - (value - low) / (high - low) * plot.height;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // The segment, shaded.
    final shadeLeft = x(segmentStart).clamp(plot.left, plot.right);
    final shadeRight = x(segmentEnd).clamp(plot.left, plot.right);
    canvas.drawRect(
      Rect.fromLTRB(shadeLeft, plot.top, shadeRight, plot.bottom),
      Paint()..color = shade,
    );

    // Speed gridlines and labels; the unit above them.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final digits = step < 1 ? 1 : 0;
    for (var value = low; value <= high + step / 2; value += step) {
      final at = y(value);
      canvas.drawLine(Offset(plot.left, at), Offset(plot.right, at), gridPaint);
      final label = _text(value.toStringAsFixed(digits));
      label.paint(
        canvas,
        Offset(plot.left - 6 - label.width, at - label.height / 2),
      );
    }
    {
      final label = _text(
        unit.isEmpty ? 'speed' : unit,
        weight: FontWeight.w600,
      );
      label.paint(canvas, Offset(math.max(0, plot.left - 6 - label.width), 2));
    }

    // Distance gridlines: metres from the segment's entry.
    final xStep = _niceStep(span, math.max(2, plot.width / 70));
    final first = ((start - segmentStart) / xStep).ceil();
    final last = ((end - segmentStart) / xStep).floor();
    for (var index = first; index <= last; ++index) {
      final meters = segmentStart + index * xStep;
      final at = x(meters);
      canvas.drawLine(Offset(at, plot.top), Offset(at, plot.bottom), gridPaint);
      final value = index * xStep;
      final label = _text(
        value == 0
            ? '0'
            : '${value < 0 ? '−' : ''}${value.abs().toStringAsFixed(0)}',
      );
      final left = (at - label.width / 2).clamp(0.0, size.width - label.width);
      label.paint(canvas, Offset(left, plot.bottom + 3));
    }

    // The plot's frame: the axes.
    final axisPaint = Paint()
      ..color = boundary
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axisPaint);

    // Entry and exit: solid lines, named above the plot.
    final boundaryPaint = Paint()
      ..color = boundary
      ..strokeWidth = 1.5;
    final (entryName, exitName) = boundaryNames;
    for (final (meters, name, alignEnd) in [
      (segmentStart, entryName, false),
      (segmentEnd, exitName, true),
    ]) {
      if (meters < start - 1e-9 || meters > end + 1e-9) continue;
      final at = x(meters);
      canvas.drawLine(
        Offset(at, plot.top),
        Offset(at, plot.bottom),
        boundaryPaint,
      );
      final label = _text(name, color: ink, weight: FontWeight.w600);
      final left = alignEnd ? at - label.width - 3 : at + 3;
      label.paint(canvas, Offset(left.clamp(0.0, size.width - label.width), 1));
    }

    // The apex (or each candidate of a double apex): dashed.
    final apexPaint = Paint()
      ..color = ink
      ..strokeWidth = 1;
    var apexLabelRight = -double.infinity;
    for (final meters in apexes) {
      if (meters < start || meters > end) continue;
      final at = x(meters);
      for (var top = plot.top; top < plot.bottom; top += 6) {
        canvas.drawLine(
          Offset(at, top),
          Offset(at, math.min(plot.bottom, top + 3)),
          apexPaint,
        );
      }
      final label = _text('Apex', color: ink);
      final rect = Offset(at - label.width / 2, plot.top + 1) & label.size;
      if (rect.left > apexLabelRight + 4) {
        label.paint(canvas, rect.topLeft);
        apexLabelRight = rect.right;
      }
    }

    // Both laps' speed, B under A; gaps stay open.
    for (final slot in const [1, 0]) {
      if (slot >= series.length) continue;
      final paint = Paint()
        ..color = _lapColor(slot)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      for (final part in series[slot].segments) {
        if (part.isEmpty) continue;
        double px(ChartPoint point) => plot.left + point.x * plot.width;
        final path = Path()..moveTo(px(part.first), y(part.first.y));
        for (final point in part.skip(1)) {
          path.lineTo(px(point), y(point.y));
        }
        canvas.drawPath(path, paint);
      }
    }

    // Markers on their lap's line.
    final obstacles = <Rect>[];
    final labels = <(SpeedChartMarker, Offset, double)>[];
    for (final marker in markers) {
      if (marker.at < start - 1e-9 || marker.at > end + 1e-9) continue;
      final value = marker.kind == SpeedMarkerKind.minimum
          ? minimumSpeeds[marker.slot] ?? speedAt(marker.slot, marker.at)
          : speedAt(marker.slot, marker.at);
      final at = Offset(
        x(marker.at),
        value == null ? plot.bottom : y(value).clamp(plot.top, plot.bottom),
      );
      _drawMarker(canvas, marker.kind, at, _lapColor(marker.slot), surface);
      obstacles.add(Rect.fromCircle(center: at, radius: 6));
      if (marker.kind == SpeedMarkerKind.minimum && value != null) {
        labels.add((marker, at, value));
      }
    }

    // Each lowest speed labelled with its value, beside its dot where it
    // does not cover another label or marker: A prefers the left, B the
    // right.
    for (final (marker, at, value) in labels) {
      final label = _text(
        value.toStringAsFixed(1),
        color: _lapColor(marker.slot),
        weight: FontWeight.w700,
      );
      final w = label.width, h = label.height;
      final below = Offset(at.dx - w / 2, at.dy + 8);
      final above = Offset(at.dx - w / 2, at.dy - 8 - h);
      final left = Offset(at.dx - 9 - w, at.dy - h / 2);
      final right = Offset(at.dx + 9, at.dy - h / 2);
      final candidates = marker.slot == 0
          ? [below, left, above, right]
          : [below, right, above, left];
      Rect? chosen;
      for (final topLeft in candidates) {
        final rect = topLeft & Size(w, h);
        final inside =
            rect.left >= plot.left &&
            rect.right <= plot.right &&
            rect.top >= plot.top &&
            rect.bottom <= plot.bottom;
        if (inside &&
            !obstacles.any((other) => other.overlaps(rect.inflate(1)))) {
          chosen = rect;
          break;
        }
      }
      chosen ??= Rect.fromLTWH(
        below.dx.clamp(plot.left, math.max(plot.left, plot.right - w)),
        math.min(below.dy, plot.bottom - h),
        w,
        h,
      );
      obstacles.add(chosen);
      canvas.drawRRect(
        RRect.fromRectAndRadius(chosen.inflate(2), const Radius.circular(3)),
        Paint()..color = surface.withValues(alpha: 0.9),
      );
      label.paint(canvas, chosen.topLeft);
    }

    // The shared cursor, with a dot where it crosses each lap's line.
    if (cursor >= start && cursor <= end) {
      final at = x(cursor);
      canvas.drawLine(
        Offset(at, plot.top),
        Offset(at, plot.bottom),
        Paint()
          ..color = cursorColor
          ..strokeWidth = 1.2,
      );
      for (final slot in const [0, 1]) {
        final value = speedAt(slot, cursor);
        if (value == null) continue;
        final point = Offset(at, y(value));
        canvas.drawCircle(point, 3.5, Paint()..color = cursorColor);
        canvas.drawCircle(point, 2, Paint()..color = _lapColor(slot));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SegmentSpeedPainter old) =>
      old.cursor != cursor ||
      old.start != start ||
      old.end != end ||
      !identical(old.series, series) ||
      old.grid != grid ||
      old.ink != ink ||
      old.surface != surface;
}

/// The chart's key: both laps' lines with their names and every marker.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.lapNames,
    required this.apex,
    required this.kinds,
    required this.ink,
    this.style,
  });

  final List<String> lapNames;
  final bool apex;
  final Set<SpeedMarkerKind> kinds;
  final Color ink;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    Widget item(String key, Widget symbol, String text) => Row(
      key: ValueKey('cornerAnalyzerLegend $key'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 18, height: 14, child: symbol),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: style)),
      ],
    );
    Widget line(Color color) =>
        Center(child: Container(width: 18, height: 3, color: color));
    Widget marker(SpeedMarkerKind kind) => CustomPaint(
      painter: _SymbolPainter(
        (canvas, size) => _drawMarker(
          canvas,
          kind,
          size.center(Offset.zero),
          ink,
          Colors.transparent,
          scale: 0.85,
        ),
      ),
    );
    String name(int slot) {
      final lap = slot < lapNames.length ? lapNames[slot].trim() : '';
      return '${slot == 0 ? 'A' : 'B'}${lap.isEmpty ? '' : ' · $lap'}';
    }

    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        item('A', line(lapAColor), name(0)),
        item('B', line(lapBColor), name(1)),
        if (kinds.contains(SpeedMarkerKind.braking))
          item('braking', marker(SpeedMarkerKind.braking), 'Braking starts'),
        if (kinds.contains(SpeedMarkerKind.pickup))
          item('pickup', marker(SpeedMarkerKind.pickup), 'Throttle pickup'),
        if (kinds.contains(SpeedMarkerKind.minimum))
          item('minimum', marker(SpeedMarkerKind.minimum), 'Lowest speed'),
        if (apex)
          item(
            'apex',
            CustomPaint(
              painter: _SymbolPainter((canvas, size) {
                final paint = Paint()
                  ..color = ink
                  ..strokeWidth = 1;
                for (var top = 0.0; top < size.height; top += 5) {
                  canvas.drawLine(
                    Offset(size.width / 2, top),
                    Offset(size.width / 2, math.min(size.height, top + 3)),
                    paint,
                  );
                }
              }),
            ),
            'Apex',
          ),
      ],
    );
  }
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.draw);

  final void Function(Canvas canvas, Size size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(_SymbolPainter old) => false;
}
