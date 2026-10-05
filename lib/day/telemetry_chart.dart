import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../channel_names.dart';
import '../format.dart';
import '../l10n.dart';
import '../units.dart';
import 'channel_sources.dart';
import 'touch.dart';

/// The colour of the Δ time line (one line, not an A/B pair): neutral, so it
/// is not read as lap A's amber or lap B's blue.
const Color deltaLineColor = Color(0xFFB0B0B0);

/// [deltaLineColor] on a light background: the same grey, darker.
const Color deltaLineLightColor = Color(0xFF3A3A3A);

/// One line of a chart: a lap's series in its colour.
@immutable
final class ChartLine {
  const ChartLine(this.label, this.series, this.color);

  /// "A", "B", or empty for a single line.
  final String label;
  final ChartSeries series;
  final Color color;
}

/// Why a chart has no line, in words. Distinct from "no data in this
/// range", which is not a failure.
String chartReasonText(AppLocalizations l10n, String reason) =>
    switch (reason) {
      chartReasonChannelMissing => l10n.chartReasonNotRecorded,
      chartReasonInvalidRange => l10n.chartReasonInvalidRange,
      chartReasonChannelMalformed => l10n.chartReasonUnreadable,
      _ => reason,
    };

/// [value] with as many decimals as the magnitude [scale] needs.
String chartValueText(double value, double scale, String unit) {
  final digits = _chartDigits(scale);
  return '${value.toStringAsFixed(digits)}${unit.isEmpty ? '' : '\u00a0$unit'}';
}

int _chartDigits(double scale) {
  final magnitude = scale.abs();
  return magnitude >= 100
      ? 0
      : magnitude >= 10
      ? 1
      : 2;
}

/// [value] (unwrapped degrees) as the compass direction it shows, rounded as
/// [chartValueText] rounds at [scale] first, so north reads 0 and never 360.
double chartDegrees(double value, double scale) {
  final factor = math.pow(10, _chartDigits(scale)).toDouble();
  final rounded = (normalizeDegrees(value) * factor).round() / factor;
  return rounded >= 360 ? rounded - 360 : rounded;
}

/// The value axis of a chart, fixed over the whole lap so zooming does not
/// make a small wobble look large: the lines' extent padded by 8 % (or by
/// half a unit when flat), and zero included for [zeroLine].
(double, double) chartValueAxis(
  Iterable<ChartSeries> series, {
  bool zeroLine = false,
}) {
  var low = double.infinity, high = -double.infinity;
  for (final line in series) {
    if (!line.hasData) continue;
    low = math.min(low, line.minimum);
    high = math.max(high, line.maximum);
  }
  if (!low.isFinite) return (0, 1);
  if (zeroLine) {
    low = math.min(low, 0);
    high = math.max(high, 0);
  }
  final padding = high == low
      ? math.max(0.5, low.abs() * 0.05)
      : (high - low) * 0.08;
  return (low - padding, high + padding);
}

/// One channel over the range shown, with a cursor: a drag or a tap on the
/// chart moves the cursor ([onCursor], in axis units between [start] and
/// [end]); only the cursor layer repaints while it moves.
class TelemetryChart extends StatelessWidget {
  const TelemetryChart({
    super.key,
    required this.title,
    required this.lines,
    required this.start,
    required this.end,
    required this.cursor,
    required this.onCursor,
    required this.valueAxis,
    this.zeroLine = false,
    this.note = '',
    this.source,
    this.delta = false,
    this.onRemove,
    this.choices = const [],
    this.onPick,
    this.choiceLabel,
    this.height = 120,
  });

  /// The channel shown, as recorded (the Δ time chart: its name in the
  /// app's language); the chart says the name the driver gave a channel in
  /// settings ([channelNameOf]) and the recorded name under it.
  final String title;
  final List<ChartLine> lines;

  /// The range shown, in axis units (seconds or metres).
  final double start;
  final double end;

  /// The cursor in axis units.
  final ValueListenable<double> cursor;
  final ValueChanged<double> onCursor;

  /// The fixed value axis, low to high.
  final (double, double) valueAxis;

  /// Draws the zero line (Δ time).
  final bool zeroLine;

  /// Shown under the title, such as "+ = A behind".
  final String note;

  /// The format of the other recording the channel came from ("RCZ"), said
  /// under the title; empty when it is the session's own. When null, the
  /// open day says ([dayChannelSources]).
  final String? source;

  /// The values are seconds of difference, shown with [displayDelta].
  final bool delta;

  /// Removes the chart; none when null.
  final VoidCallback? onRemove;

  /// The channels the chart can show instead, listed when its title is
  /// tapped; [onPick] gets the one chosen. A plain title when [onPick] is
  /// null.
  final List<String> choices;
  final ValueChanged<String>? onPick;

  /// The name listed for a choice; [channelMenuLabel] when null.
  final String Function(String channel)? choiceLabel;
  final double height;

  double _fraction(double value) =>
      end > start ? (value - start) / (end - start) : 0;

  /// The value at the cursor; a compass direction drawn unwrapped reads as
  /// the recorded 0 up to 360.
  String _value(ChartLine line, double fraction, String unit) {
    final read = nearestChartValue(line.series, fraction);
    if (read == null) return '–';
    if (delta) return displayDelta(read);
    final scale = math.max(valueAxis.$1.abs(), valueAxis.$2.abs());
    final value = line.series.angular ? chartDegrees(read, scale) : read;
    return chartValueText(value, scale, unit);
  }

  // The lowest and highest value a screen reader says: a compass direction
  // as recorded, from where it starts to where it ends round the compass, or
  // 0 to 360 when it turns all the way round.
  double _spokenLow(ChartSeries series) => !series.angular
      ? series.minimum
      : series.maximum - series.minimum >= 360
      ? 0
      : normalizeDegrees(series.minimum);

  double _spokenHigh(ChartSeries series) => !series.angular
      ? series.maximum
      : series.maximum - series.minimum >= 360
      ? 360
      : normalizeDegrees(series.maximum);

  String _summaryValue(double value, String unit) {
    if (delta) return displayDelta(value);
    final scale = math.max(valueAxis.$1.abs(), valueAxis.$2.abs());
    return chartValueText(value, scale, unit);
  }

  // The chart's name; with [onPick], a menu of the channels it can show
  // instead.
  Widget _heading(BuildContext context, String name) {
    final style = Theme.of(context).textTheme.titleSmall;
    final pick = onPick;
    if (pick == null) {
      return Text(name, style: style, overflow: TextOverflow.ellipsis);
    }
    final others = choices;
    String label(String channel) =>
        choiceLabel?.call(channel) ?? channelMenuLabel(context, channel);
    return PopupMenuButton<String>(
      key: ValueKey('chartPick $title'),
      tooltip: context.l10n.chartChangeChannel(name),
      enabled: others.isNotEmpty,
      onSelected: (value) => chooseChannel(context, value, others, label, pick),
      itemBuilder: (context) => channelMenuItems(context, others, label),
      // A 48 dp target, as every button on a touch screen.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(name, style: style, overflow: TextOverflow.ellipsis),
            ),
            if (others.isNotEmpty) Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final shown = lines.where((line) => line.series.hasData).toList();
    final failed = [
      for (final line in lines)
        if (!line.series.hasData)
          '${line.label.isEmpty ? '' : '${line.label}: '}'
              '${line.series.reason.isEmpty ? l10n.chartNoDataInRange : chartReasonText(l10n, line.series.reason)}',
    ];
    final braking = lines.any((line) => line.series.brakingUp);
    final from = source ?? dayChannelSources[title] ?? '';
    final provenance = from.isEmpty ? '' : l10n.channelFromSource(from);
    final name = channelNameOf(context, title);
    final recordedAs = name == title ? '' : l10n.chartRecordedAs(title);
    final message = shown.isNotEmpty
        ? null
        : lines.every((line) => line.series.reason.isEmpty)
        ? l10n.chartNoData
        : l10n.chartNotAvailable(failed.join(' · '));
    void move(Offset local, double width) {
      if (width <= 0 || end <= start) return;
      onCursor(start + (local.dx / width).clamp(0.0, 1.0) * (end - start));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heading(context, name),
                    if (note.isNotEmpty ||
                        recordedAs.isNotEmpty ||
                        provenance.isNotEmpty ||
                        braking ||
                        (shown.isNotEmpty && failed.isNotEmpty))
                      Text(
                        [
                          if (note.isNotEmpty) note,
                          if (recordedAs.isNotEmpty) recordedAs,
                          if (provenance.isNotEmpty) provenance,
                          if (braking) l10n.chartBrakingUp,
                          if (shown.isNotEmpty) ...failed,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                  ],
                ),
              ),
              // At most 60 % of the row, wrapping with large text rather
              // than overflowing it.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.6,
                ),
                child: ValueListenableBuilder(
                  valueListenable: cursor,
                  builder: (context, value, _) {
                    final fraction = _fraction(value);
                    final inside = fraction >= 0 && fraction <= 1;
                    return Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      children: [
                        for (final line in lines)
                          Text(
                            '${line.label.isEmpty ? '' : '${line.label} '}'
                            '${inside ? _value(line, fraction, displayUnitOf(context, title, line.series.unit)) : '–'}',
                            key: ValueKey('chartValue $title ${line.label}'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: line.color == deltaLineColor
                                  ? null
                                  : readableOn(context, line.color),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: l10n.chartRemove(name),
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: LayoutBuilder(
            // A tap (on lifting the finger, so the start of a page scroll
            // does not move it) or a sideways drag moves the cursor; an
            // upward or downward drag scrolls the page.
            // With a mouse or a trackpad the cursor also follows the
            // pointer, as in other telemetry tools; touch is unchanged.
            builder: (context, constraints) => MouseRegion(
              key: ValueKey('chartHover $title'),
              cursor: SystemMouseCursors.precise,
              onHover: (event) =>
                  move(event.localPosition, constraints.maxWidth),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    move(details.localPosition, constraints.maxWidth),
                onHorizontalDragStart: (details) =>
                    move(details.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (details) =>
                    move(details.localPosition, constraints.maxWidth),
                child: Semantics(
                  // What the lines show, not just their name: each line's
                  // lowest and highest value in the range shown.
                  label: [
                    l10n.chartSemantics(name),
                    for (final line in shown)
                      l10n.chartSemanticsRange(
                        line.label.isEmpty ? '' : '${line.label}: ',
                        _summaryValue(
                          _spokenLow(line.series),
                          displayUnitOf(context, title, line.series.unit),
                        ),
                        _summaryValue(
                          _spokenHigh(line.series),
                          displayUnitOf(context, title, line.series.unit),
                        ),
                      ),
                  ].join(', '),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _SeriesPainter(
                              lines: shown,
                              axis: valueAxis,
                              zeroLine: zeroLine,
                              gridColor: scheme.outlineVariant,
                              zeroColor: scheme.outline,
                              labelStyle: theme.textTheme.labelSmall!.copyWith(
                                color: scheme.onSurfaceVariant,
                                // Readable where a line runs under it.
                                backgroundColor: scheme.surface.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                              dark: theme.brightness == Brightness.dark,
                              delta: delta,
                              // One axis: labelled only when every line
                              // shown is in one unit.
                              unit:
                                  shown.isEmpty ||
                                      !shown.every(
                                        (line) => sameSpeedUnit(
                                          line.series.unit,
                                          shown.first.series.unit,
                                        ),
                                      )
                                  ? ''
                                  : displayUnitOf(
                                      context,
                                      title,
                                      shown.first.series.unit,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      if (message != null)
                        Center(
                          child: Text(
                            message,
                            key: ValueKey('chartMessage $title'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _CursorPainter(
                            cursor: cursor,
                            start: start,
                            end: end,
                            lines: shown,
                            axis: valueAxis,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// The y of [value] on a chart of [height]; braking (a negative longitudinal
// G) is drawn upward.
double _chartY(
  double value,
  (double, double) axis,
  double height,
  bool brakingUp,
) {
  final fraction = (value - axis.$1) / math.max(1e-6, axis.$2 - axis.$1);
  return 3 + (brakingUp ? fraction : 1 - fraction) * math.max(1, height - 6);
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({
    required this.lines,
    required this.axis,
    required this.zeroLine,
    required this.gridColor,
    required this.zeroColor,
    required this.labelStyle,
    required this.delta,
    required this.unit,
    this.dark = false,
  });

  final List<ChartLine> lines;
  final (double, double) axis;
  final bool zeroLine;
  final Color gridColor;
  final Color zeroColor;
  final TextStyle labelStyle;
  final bool delta;
  final String unit;

  /// The Δ line is drawn darker on a light background, where its yellow is
  /// faint.
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; ++i) {
      final x = size.width * i / 4, y = size.height * i / 4;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), grid)
        ..drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final brakingUp = lines.any((line) => line.series.brakingUp);
    if (zeroLine && axis.$1 < 0 && axis.$2 > 0) {
      final y = _chartY(0, axis, size.height, brakingUp);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = zeroColor
          ..strokeWidth = 1.5,
      );
    }
    if (lines.isNotEmpty) {
      final scale = math.max(axis.$1.abs(), axis.$2.abs());
      String label(double value) =>
          delta ? displayDelta(value) : chartValueText(value, scale, unit);
      final top = brakingUp ? axis.$1 : axis.$2,
          bottom = brakingUp ? axis.$2 : axis.$1;
      final high = TextPainter(
        text: TextSpan(text: label(top), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final low = TextPainter(
        text: TextSpan(text: label(bottom), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      high.paint(canvas, const Offset(4, 2));
      low.paint(canvas, Offset(4, size.height - low.height - 2));
    }
    // On white, a faint dark edge under each line keeps the light lap
    // colours (A's amber) visible; the colours themselves stay.
    final edge = dark
        ? null
        : (Paint()
            ..color = const Color(0x59000000)
            ..strokeWidth = 4
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round);
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color == deltaLineColor && !dark
            ? deltaLineLightColor
            : line.color
        // Thicker in the light look, for reading in the sun.
        ..strokeWidth = dark ? 2 : 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      // Each run stays separate: a gap is never bridged.
      for (final segment in line.series.segments) {
        if (segment.length == 1) {
          canvas.drawCircle(
            Offset(
              segment.first.x * size.width,
              _chartY(
                segment.first.y,
                axis,
                size.height,
                line.series.brakingUp,
              ),
            ),
            1.5,
            Paint()..color = line.color,
          );
          continue;
        }
        final path = Path();
        for (var i = 0; i < segment.length; ++i) {
          final x = segment[i].x * size.width;
          final y = _chartY(
            segment[i].y,
            axis,
            size.height,
            line.series.brakingUp,
          );
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        if (edge != null) canvas.drawPath(path, edge);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SeriesPainter old) =>
      !listEquals(
        [for (final line in old.lines) line.series],
        [for (final line in lines) line.series],
      ) ||
      old.axis != axis ||
      old.zeroLine != zeroLine ||
      old.gridColor != gridColor ||
      old.zeroColor != zeroColor ||
      old.labelStyle != labelStyle ||
      old.unit != unit ||
      old.dark != dark;
}

class _CursorPainter extends CustomPainter {
  _CursorPainter({
    required this.cursor,
    required this.start,
    required this.end,
    required this.lines,
    required this.axis,
    required this.color,
  }) : super(repaint: cursor);

  final ValueListenable<double> cursor;
  final double start;
  final double end;
  final List<ChartLine> lines;
  final (double, double) axis;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (end <= start || size.isEmpty) return;
    final fraction = (cursor.value - start) / (end - start);
    if (!(fraction >= 0 && fraction <= 1)) return;
    final x = fraction * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
    for (final line in lines) {
      final value = nearestChartValue(line.series, fraction);
      if (value == null) continue;
      final centre = Offset(
        x,
        _chartY(value, axis, size.height, line.series.brakingUp),
      );
      canvas
        ..drawCircle(centre, 5, Paint()..color = Colors.black54)
        ..drawCircle(centre, 4, Paint()..color = line.color);
    }
  }

  @override
  bool shouldRepaint(_CursorPainter old) =>
      old.cursor != cursor ||
      old.start != start ||
      old.end != end ||
      old.axis != axis ||
      old.color != color ||
      !identical(old.lines, lines);
}

/// The zoom window of a set of charts: the full extent, the range shown and
/// the cursor. Zooming centres on the cursor; moving the cursor out of the
/// range (with the slider) pans the range to follow it.
final class ChartWindow {
  ChartWindow(
    this.fullStart,
    this.fullEnd, {
    double? cursor,
    (double, double)? range,
  }) : cursor = ValueNotifier(
         (cursor ?? fullStart)
             .clamp(fullStart, math.max(fullStart, fullEnd))
             .toDouble(),
       ),
       range = ValueNotifier(range ?? (fullStart, fullEnd)) {
    this.cursor.addListener(_follow);
  }

  final double fullStart;
  final double fullEnd;
  final ValueNotifier<double> cursor;
  final ValueNotifier<(double, double)> range;

  double get fullSpan => math.max(0, fullEnd - fullStart);

  /// The narrowest range: 1/64 of the whole.
  double get minimumSpan => fullSpan / 64;

  bool get zoomed => range.value.$2 - range.value.$1 < fullSpan - 1e-9;

  void _follow() {
    final (start, end) = range.value;
    final at = cursor.value;
    if (at >= start && at <= end) return;
    _show(at, end - start);
  }

  void _show(double centre, double span) {
    final clamped = span
        .clamp(math.min(minimumSpan, fullSpan), fullSpan)
        .toDouble();
    var start = centre - clamped / 2;
    start = start.clamp(fullStart, fullEnd - clamped).toDouble();
    range.value = (start, start + clamped);
  }

  void zoomIn() => _show(cursor.value, (range.value.$2 - range.value.$1) / 2);

  void zoomOut() => _show(cursor.value, (range.value.$2 - range.value.$1) * 2);

  void reset() => range.value = (fullStart, fullEnd);

  /// Shows [start]..[end], such as a segment opened from a time loss.
  void focus(double start, double end) {
    if (!(end > start)) return;
    final low = math.max(fullStart, start), high = math.min(fullEnd, end);
    if (!(high > low)) return;
    range.value = (low, high);
    if (cursor.value < low || cursor.value > high) cursor.value = low;
  }

  void dispose() {
    cursor.dispose();
    range.dispose();
  }
}

/// The zoom buttons, the range shown and a slider for the cursor over the
/// whole lap (a large touch target; charts take drags too).
class ChartWindowControls extends StatelessWidget {
  const ChartWindowControls({
    super.key,
    required this.window,
    required this.axisText,
  });

  final ChartWindow window;

  /// An axis value in words, such as "12.4 s" or "640 m".
  final String Function(double value) axisText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder(
          valueListenable: window.range,
          builder: (context, range, _) => Row(
            children: [
              IconButton(
                key: const ValueKey('chartZoomOut'),
                tooltip: l10n.chartZoomOut,
                icon: const Icon(Icons.zoom_out),
                onPressed: window.zoomed ? window.zoomOut : null,
              ),
              IconButton(
                key: const ValueKey('chartZoomIn'),
                tooltip: l10n.chartZoomIn,
                icon: const Icon(Icons.zoom_in),
                onPressed: range.$2 - range.$1 > window.minimumSpan + 1e-9
                    ? window.zoomIn
                    : null,
              ),
              IconButton(
                key: const ValueKey('chartZoomReset'),
                tooltip: l10n.chartWholeLap,
                icon: const Icon(Icons.fit_screen_outlined),
                onPressed: window.zoomed ? window.reset : null,
              ),
              Expanded(
                child: Text(
                  '${axisText(range.$1)} – ${axisText(range.$2)}',
                  key: const ValueKey('chartRange'),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (window.fullSpan > 0)
          ValueListenableBuilder(
            valueListenable: window.cursor,
            builder: (context, value, _) => Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    axisText(value),
                    key: const ValueKey('chartCursor'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('chartCursorSlider'),
                    min: window.fullStart,
                    max: window.fullEnd,
                    value: value
                        .clamp(window.fullStart, window.fullEnd)
                        .toDouble(),
                    onChanged: (value) => window.cursor.value = value,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// [channel] as a chart menu lists it: its names ([channelLabelOf]) and,
/// when it came from another recording, " · from RCZ" ([sources], or the
/// open day's [dayChannelSources] when null).
String channelMenuLabel(
  BuildContext context,
  String channel, [
  Map<String, String>? sources,
]) {
  final source = (sources ?? dayChannelSources)[channel] ?? '';
  final name = channelLabelOf(context, channel);
  return source.isEmpty
      ? name
      : '$name · ${context.l10n.channelFromSource(source)}';
}

/// A menu of channels to add to a set of charts, by the names the driver
/// gave them; disabled at four.
class AddChannelButton extends StatelessWidget {
  String _label(BuildContext context, String channel) =>
      choiceLabel?.call(channel) ?? channelMenuLabel(context, channel, sources);

  const AddChannelButton({
    super.key,
    required this.channels,
    required this.shown,
    required this.onAdd,
    this.sources,
    this.choiceLabel,
  });

  final List<String> channels;
  final List<String> shown;
  final ValueChanged<String> onAdd;

  /// The channels that came from another recording, with its format
  /// ("RCZ"); when null, the open day's ([dayChannelSources]).
  final Map<String, String>? sources;

  /// The name listed for a channel; [channelMenuLabel] with [sources] when
  /// null.
  final String Function(String channel)? choiceLabel;

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final channel in channels)
        if (!shown.contains(channel)) channel,
    ];
    final full = shown.length >= maximumChartChannels;
    final l10n = context.l10n;
    final label = full
        ? l10n.chartAtMost(maximumChartChannels)
        : l10n.chartAddChannel;
    return PopupMenuButton<String>(
      key: const ValueKey('addChartChannel'),
      enabled: !full && available.isNotEmpty,
      tooltip: label,
      onSelected: (value) => chooseChannel(
        context,
        value,
        available,
        (channel) => _label(context, channel),
        onAdd,
      ),
      itemBuilder: (context) => channelMenuItems(
        context,
        available,
        (channel) => _label(context, channel),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_chart,
              color: full || available.isEmpty
                  ? Theme.of(context).disabledColor
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(label)),
          ],
        ),
      ),
    );
  }
}
