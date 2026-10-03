import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'comparison_page.dart' show ComparisonPanelBuilder;
import 'touch.dart';
import 'corner_details.dart' show lapAColor, lapBColor;
import 'telemetry_chart.dart';

/// The comparison page's G-G, driving-state and coasting panels (FET-39),
/// in order, for `comparisonPanels`.
final List<ComparisonPanelBuilder> drivingComparisonPanels = [
  (context, panel) =>
      ComparisonGgPanel(comparison: panel.comparison, window: panel.window),
  (context, panel) => ComparisonDrivingStatesPanel(
    comparison: panel.comparison,
    window: panel.window,
  ),
  (context, panel) => ComparisonCoastingPanel(
    comparison: panel.comparison,
    window: panel.window,
  ),
];

const List<Color> _lapColors = [lapAColor, lapBColor];
const List<String> _lapNames = ['A', 'B'];

/// Lane colours of the driving-state strips.
const Color brakingStateColor = Color(0xFFE53935);
const Color acceleratingStateColor = Color(0xFF00897B);
const Color corneringStateColor = Color(0xFF1E88E5);
const Color coastingStateColor = Color(0xFFFB8C00);
const Color trailBrakingStateColor = Color(0xFF8E24AA);

/// The amber of an inferred value's label.
const Color inferredColor = Color(0xFFE09A1F);

/// Why a lap has no G-G, in words.
String ggReasonText(String reason) => switch (reason) {
  ggMissingLongitudinal => 'No longitudinal G recorded',
  ggMissingLateral => 'No lateral G recorded',
  ggUnsupportedUnit => 'G in an unsupported unit',
  ggNoOverlap => 'No samples in this stretch',
  drivingIncompleteCoverage => 'Does not cover this stretch',
  _ => 'Not available',
};

/// How a state was obtained, as a short label: "measured", "calculated
/// from GPS", "inferred" or why it is unknown.
String provenanceLabel(DrivingStateTrack track) => switch (track.provenance) {
  drivingStateMeasured => 'measured',
  drivingStateCalculated => 'calculated from GPS',
  drivingStateInferred => 'inferred',
  _ => switch (track.unresolvedReason) {
    'unitMismatch' => 'unexpected unit',
    'inferenceDisabled' => 'not recorded',
    'pedalStateUnknown' => 'pedals unknown',
    'noSpeedChannel' => 'no speed',
    _ => 'not recorded',
  },
};

/// Where a lap's pedal states come from, in a sentence.
String pedalSourceText(DrivingStateClassification states) {
  String pedal(DrivingStateTrack track, String measured, String inferred) =>
      switch (track.provenance) {
        drivingStateMeasured => measured,
        drivingStateInferred => inferred,
        _ =>
          track.unresolvedReason == 'unitMismatch'
              ? '${track.channel} is in an unexpected unit'
              : 'no ${measured.split(' ').first} channel',
      };
  final braking = pedal(
    states.braking,
    'brake pedal recorded',
    'braking inferred from deceleration (no brake channel)',
  );
  final accelerating = pedal(
    states.accelerating,
    'accelerator pedal recorded',
    'accelerating inferred from longitudinal G (no accelerator channel)',
  );
  final cornering = switch (states.cornering.provenance) {
    drivingStateMeasured => 'lateral G measured',
    drivingStateCalculated => 'lateral G calculated from GPS by the logger',
    _ => 'no lateral G',
  };
  return '${braking[0].toUpperCase()}${braking.substring(1)}; '
      '$accelerating; $cornering.';
}

/// Where a lap's coasting comes from, or why it cannot be told (Overlays'
/// CoastingPanel).
String coastingProvenanceText(CoastingSummary summary) =>
    switch (summary.provenance) {
      drivingStateMeasured =>
        'Measured: from the recorded brake and accelerator pedals.',
      drivingStateInferred =>
        'Inferred from longitudinal G: this recording has no brake or no '
            'accelerator pedal channel.',
      _ => switch (summary.unresolvedReason) {
        'pedalStateUnknown' =>
          'Cannot be told: the recording has neither pedal channels nor '
              'longitudinal G.',
        'noSpeedChannel' => 'Cannot be told: the recording has no speed.',
        'unitMismatch' =>
          'Cannot be told: a pedal or speed channel is in an unexpected unit.',
        _ => 'Coasting is not available for this stretch.',
      },
    };

/// "4.2 s · 128 m over 9 episodes (5.1 % of the lap)".
String coastingSummaryText(CoastingSummary summary, String of) {
  final count = summary.episodes.length;
  final share = summary.lapSeconds > 0
      ? 100 * summary.coastingSeconds / summary.lapSeconds
      : 0.0;
  return '${summary.coastingSeconds.toStringAsFixed(1)} s · '
      '${summary.coastingMeters.round()} m over $count '
      '${count == 1 ? 'episode' : 'episodes'} '
      '(${share.toStringAsFixed(1)} % of $of)';
}

/// Coasting is an observation, never a verdict.
const String coastingNote =
    'Coasting is time at speed with neither pedal pressed. It is not a '
    'mistake by itself: a lift can settle the car or be forced by traffic.';

String _stretchText((double, double) range, ChartWindow window) => window.zoomed
    ? 'Selected stretch · ${(range.$2 - range.$1).round()} m'
    : 'Whole lap';

/// A titled card of the comparison page.
class _PanelCard extends StatelessWidget {
  const _PanelCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              Text(subtitle, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// A result computed once per shown range of a comparison.
abstract class _RangeState<W extends StatefulWidget, T> extends State<W> {
  LapComparison get comparison;
  ChartWindow get window;
  T compute((double, double) range);

  (double, double)? _range;
  LapComparison? _of;
  late T _value;

  T valueFor((double, double) range) {
    if (_range != range || !identical(_of, comparison)) {
      _range = range;
      _of = comparison;
      _value = compute(range);
    }
    return _value;
  }

  Widget buildFor(BuildContext context, (double, double) range, T value);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: window.range,
    builder: (context, range, _) => buildFor(context, range, valueFor(range)),
  );
}

/// A/B G-G scatter over the shown stretch (Overlays' ComparisonGgPanel):
/// lateral G left-right as the driver feels it, longitudinal G up when
/// accelerating and down when braking. Peaks and sample counts come from
/// every pair; only the drawn points are thinned. Observed values, not a
/// share of available grip.
class ComparisonGgPanel extends StatefulWidget {
  const ComparisonGgPanel({
    super.key,
    required this.comparison,
    required this.window,
  });

  final LapComparison comparison;
  final ChartWindow window;

  /// The points drawn per lap, at most (the peaks come on top).
  static const int maximumPoints = 1500;

  @override
  State<ComparisonGgPanel> createState() => _ComparisonGgPanelState();
}

class _ComparisonGgPanelState
    extends _RangeState<ComparisonGgPanel, ComparisonGgScatter> {
  @override
  LapComparison get comparison => widget.comparison;
  @override
  ChartWindow get window => widget.window;

  @override
  ComparisonGgScatter compute((double, double) range) => comparisonGgScatter(
    comparison,
    range.$1,
    range.$2,
    ComparisonGgPanel.maximumPoints,
  );

  @override
  Widget buildFor(
    BuildContext context,
    (double, double) range,
    ComparisonGgScatter scatter,
  ) {
    final theme = Theme.of(context);
    final laps = scatter.laps;
    String peak(int slot, GgPeak? Function(GgPeaks) pick) {
      if (slot >= laps.length || !laps[slot].valid) return '—';
      final value = pick(laps[slot].peaks);
      return value == null ? '—' : '${value.value.toStringAsFixed(2)} g';
    }

    String samples(int slot) {
      if (slot >= laps.length) return '—';
      final lap = laps[slot];
      return lap.valid
          ? '${lap.peaks.sampleCount}'
          : ggReasonText(lap.unavailableReason);
    }

    TableRow row(String label, String key, String Function(int) value) =>
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(label, style: theme.textTheme.bodySmall),
            ),
            for (final slot in const [0, 1])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  value(slot),
                  key: ValueKey('gg$key ${_lapNames[slot]}'),
                  textAlign: TextAlign.end,
                ),
              ),
          ],
        );

    final sources = <String>[];
    for (final slot in const [0, 1]) {
      final pairs = slot < laps.length ? laps[slot].pairs : null;
      if (pairs == null) continue;
      final calculated =
          pairs.longitudinalChannel.toLowerCase().endsWith('-calc') ||
          pairs.lateralChannel.toLowerCase().endsWith('-calc');
      sources.add(
        '${_lapNames[slot]}: ${pairs.longitudinalChannel} / '
        '${pairs.lateralChannel}, '
        '${calculated ? 'calculated from GPS by the logger' : 'measured'}'
        '${pairs.unitsDeclared ? '' : ', units not declared by the recording'}',
      );
    }
    return _PanelCard(
      key: const ValueKey('ggPanel'),
      title: 'G-G',
      subtitle: _stretchText(range, window),
      children: [
        _Legend(
          entries: [
            for (final slot in const [0, 1])
              ('Lap ${_lapNames[slot]}', _lapColors[slot]),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final side = math.min(constraints.maxWidth, 360.0);
            return Center(
              child: SizedBox.square(
                dimension: side,
                child: Semantics(
                  label:
                      'G-G diagram of laps A and B: peak combined '
                      '${peak(0, (p) => p.combined)} and '
                      '${peak(1, (p) => p.combined)}',
                  child: CustomPaint(
                    key: const ValueKey('ggPlot'),
                    painter: GgPainter(
                      laps: laps,
                      gridColor: theme.colorScheme.outlineVariant,
                      labelStyle: theme.textTheme.labelSmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.4),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (final slot in const [0, 1])
                  Text(
                    _lapNames[slot],
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: readableOn(context, _lapColors[slot]),
                    ),
                  ),
              ],
            ),
            row('Peak lateral', 'Lateral', (s) => peak(s, (p) => p.lateral)),
            row('Peak braking', 'Braking', (s) => peak(s, (p) => p.braking)),
            row(
              'Peak accelerating',
              'Acceleration',
              (s) => peak(s, (p) => p.acceleration),
            ),
            row('Peak combined', 'Combined', (s) => peak(s, (p) => p.combined)),
            row('Samples', 'Samples', samples),
          ],
        ),
        const SizedBox(height: 8),
        for (final source in sources)
          Text(source, style: theme.textTheme.bodySmall),
        Text(
          'Observed accelerations, not a share of available grip. Rings '
          'every 0.5 g; a circle marks each lap\'s peaks.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The outer ring of a G-G diagram in g: at least 1 g, rounded up to
/// 0.5 g past the largest [combined] peak.
double ggScale(Iterable<double?> combined) {
  var largest = 1.0;
  for (final value in combined) {
    if (value != null) largest = math.max(largest, value);
  }
  return (largest * 2 + 0.2).ceil() / 2;
}

/// Draws both laps' G-G pairs: rings every 0.5 g, lateral left (+) on the
/// left, accelerating up, and a circle on each lap's lateral, braking and
/// combined peaks.
class GgPainter extends CustomPainter {
  GgPainter({
    required this.laps,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<ComparisonGgLap> laps;
  final Color gridColor;
  final TextStyle labelStyle;

  /// The outer ring in g (see [ggScale]).
  double get scaleG => ggScale([
    for (final lap in laps)
      if (lap.valid) lap.peaks.combined?.value,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = math.min(size.width, size.height);
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = side / 2 - 16;
    if (radius <= 0) return;
    final scale = scaleG;
    Offset at(double lateral, double longitudinal) => Offset(
      centre.dx - lateral / scale * radius,
      centre.dy - longitudinal / scale * radius,
    );
    final grid = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var ring = 0.5; ring <= scale + 1e-6; ring += 0.5) {
      canvas.drawCircle(centre, ring / scale * radius, grid);
    }
    canvas
      ..drawLine(centre - Offset(radius, 0), centre + Offset(radius, 0), grid)
      ..drawLine(centre - Offset(0, radius), centre + Offset(0, radius), grid);
    void label(String text, Offset anchor, Alignment alignment) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final offset = Offset(
        anchor.dx - painter.width * (alignment.x + 1) / 2,
        anchor.dy - painter.height * (alignment.y + 1) / 2,
      );
      painter.paint(canvas, offset);
    }

    label('accelerating', Offset(centre.dx, 0), Alignment.topCenter);
    label('braking', Offset(centre.dx, size.height), Alignment.bottomCenter);
    label('left', Offset(0, centre.dy - 2), Alignment.bottomLeft);
    label('right', Offset(size.width, centre.dy - 2), Alignment.bottomRight);
    label(
      '${scale.toStringAsFixed(1)} g',
      Offset(centre.dx + radius * 0.72, centre.dy - radius * 0.72),
      Alignment.bottomLeft,
    );

    for (var slot = 0; slot < laps.length && slot < 2; ++slot) {
      final lap = laps[slot];
      if (!lap.valid) continue;
      final color = _lapColors[slot];
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList([
          for (final point in lap.points) ...[
            at(point.lateralG, point.longitudinalG).dx,
            at(point.lateralG, point.longitudinalG).dy,
          ],
        ]),
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.square,
      );
      final ring = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final peak in [
        lap.peaks.lateral,
        lap.peaks.braking,
        lap.peaks.combined,
      ]) {
        if (peak == null) continue;
        canvas.drawCircle(
          at(peak.point.lateralG, peak.point.longitudinalG),
          5,
          ring,
        );
      }
    }
  }

  @override
  bool shouldRepaint(GgPainter oldDelegate) =>
      !identical(oldDelegate.laps, laps) ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelStyle != labelStyle;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<(String, Color)> entries;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final (label, color) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: 4),
              Text(label, style: style),
            ],
          ),
      ],
    );
  }
}

/// Parts of a range as fractions 0..1, from recording-time intervals placed
/// on [trace]; a part ending exactly at the start/finish seam ends at 1.
List<RangeFraction> stripFractions(
  List<DrivingStateInterval> intervals,
  List<ProgressSegment> trace,
  double from,
  double to,
) {
  final span = to - from;
  if (!(span > 0)) return const [];
  final parts = <RangeFraction>[];
  for (final interval in intervals) {
    final a = progressAtTime(trace, interval.start);
    var b = progressAtTime(trace, interval.end);
    if (a == null || b == null) continue;
    if (b < a) b = to;
    final start = ((a - from) / span).clamp(0.0, 1.0);
    final end = ((b - from) / span).clamp(0.0, 1.0);
    if (end > start) parts.add((from: start, to: end));
  }
  return parts;
}

/// One lap's lanes of a driving-state strip.
typedef StripLanes = List<(Color, List<RangeFraction>)>;

/// Lanes of states along a stretch, with the cursor (a fraction of the
/// stretch, or outside it).
class StripPainter extends CustomPainter {
  StripPainter({
    required this.lanes,
    required this.background,
    required this.cursorColor,
    this.cursor,
  }) : super(repaint: cursor);

  final StripLanes lanes;
  final Color background;
  final Color cursorColor;
  final ValueListenable<double>? cursor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || lanes.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final laneHeight = size.height / lanes.length;
    for (var i = 0; i < lanes.length; ++i) {
      final (color, parts) = lanes[i];
      final paint = Paint()..color = color;
      for (final part in parts) {
        canvas.drawRect(
          Rect.fromLTWH(
            part.from * size.width,
            i * laneHeight + 1,
            math.max(1.0, (part.to - part.from) * size.width),
            laneHeight - 2,
          ),
          paint,
        );
      }
    }
    final at = cursor?.value;
    if (at != null && at >= 0 && at <= 1) {
      canvas.drawLine(
        Offset(at * size.width, 0),
        Offset(at * size.width, size.height),
        Paint()
          ..color = cursorColor
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(StripPainter oldDelegate) =>
      !identical(oldDelegate.lanes, lanes) ||
      oldDelegate.background != background;
}

/// A strip of lanes with its lap's letter in front.
class _LapStrip extends StatelessWidget {
  const _LapStrip({
    super.key,
    required this.slot,
    required this.lanes,
    required this.cursor,
    this.onTapFraction,
  });

  final int slot;
  final StripLanes lanes;
  final ValueListenable<double> cursor;
  final ValueChanged<double>? onTapFraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = math.max(16.0, lanes.length * 8.0);
    final tappable = onTapFraction != null;
    // A tappable strip is a 48 dp target, however thin it is drawn.
    final margin = tappable ? math.max(4.0, (48 - height) / 2) : 4.0;
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            _lapNames[slot],
            style: theme.textTheme.labelLarge?.copyWith(
              color: readableOn(context, _lapColors[slot]),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Semantics(
              label: 'Lap ${_lapNames[slot]} along the track',
              hint: tappable ? 'Tap to move the cursor there' : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: !tappable
                    ? null
                    : (details) => onTapFraction!(
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        ),
                      ),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: margin),
                  child: SizedBox(
                    height: height,
                    child: CustomPaint(
                      painter: StripPainter(
                        lanes: lanes,
                        background: theme.colorScheme.surfaceContainerHighest,
                        cursorColor: theme.colorScheme.onSurface,
                        cursor: cursor,
                      ),
                    ),
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

/// The window's cursor as a fraction of [range].
class _CursorFraction extends ValueNotifier<double> {
  _CursorFraction(this.cursor, this.range) : super(double.nan) {
    cursor.addListener(_update);
    _update();
  }

  final ValueListenable<double> cursor;
  final (double, double) range;

  void _update() {
    final span = range.$2 - range.$1;
    value = span > 0 ? (cursor.value - range.$1) / span : double.nan;
  }

  @override
  void dispose() {
    cursor.removeListener(_update);
    super.dispose();
  }
}

/// Holds a [_CursorFraction] for the range shown.
mixin _CursorFractionState<W extends StatefulWidget> on State<W> {
  _CursorFraction? _cursor;

  ValueListenable<double> cursorFraction(
    ValueListenable<double> cursor,
    (double, double) range,
  ) {
    final current = _cursor;
    if (current != null &&
        identical(current.cursor, cursor) &&
        current.range == range) {
      return current;
    }
    current?.dispose();
    return _cursor = _CursorFraction(cursor, range);
  }

  @override
  void dispose() {
    _cursor?.dispose();
    super.dispose();
  }
}

/// When each lap brakes, accelerates, corners, coasts and brakes while
/// cornering over the shown stretch, with how each was obtained: measured
/// from a pedal, calculated by the logger from GPS, or inferred from
/// longitudinal G when the recording has no such pedal channel.
class ComparisonDrivingStatesPanel extends StatefulWidget {
  const ComparisonDrivingStatesPanel({
    super.key,
    required this.comparison,
    required this.window,
  });

  final LapComparison comparison;
  final ChartWindow window;

  @override
  State<ComparisonDrivingStatesPanel> createState() =>
      _ComparisonDrivingStatesPanelState();
}

class _ComparisonDrivingStatesPanelState
    extends _RangeState<ComparisonDrivingStatesPanel, List<LapDrivingStates>>
    with _CursorFractionState<ComparisonDrivingStatesPanel> {
  @override
  LapComparison get comparison => widget.comparison;
  @override
  ChartWindow get window => widget.window;

  @override
  List<LapDrivingStates> compute((double, double) range) =>
      comparisonDrivingStates(comparison, range.$1, range.$2);

  @override
  Widget buildFor(
    BuildContext context,
    (double, double) range,
    List<LapDrivingStates> laps,
  ) {
    final theme = Theme.of(context);
    final cursor = cursorFraction(window.cursor, range);
    StripLanes lanes(int slot) {
      final lap = laps[slot];
      final trace = comparison.trace(slot);
      List<RangeFraction> parts(List<DrivingStateInterval> intervals) =>
          stripFractions(intervals, trace, range.$1, range.$2);
      return [
        (brakingStateColor, parts(lap.states.braking.active)),
        (trailBrakingStateColor, parts(lap.overlap)),
        (corneringStateColor, parts(lap.states.cornering.active)),
        (acceleratingStateColor, parts(lap.states.accelerating.active)),
        (coastingStateColor, parts(lap.states.coasting.active)),
      ];
    }

    Widget cell(int slot, String state) {
      final lap = slot < laps.length ? laps[slot] : null;
      final key = ValueKey('drivingState $state ${_lapNames[slot]}');
      if (lap == null || !lap.valid) {
        return Text(
          '—',
          key: key,
          textAlign: TextAlign.end,
          style: theme.textTheme.bodyMedium,
        );
      }
      final braking = lap.states.braking, cornering = lap.states.cornering;
      final DrivingStateTrack? track = switch (state) {
        'braking' => braking,
        'accelerating' => lap.states.accelerating,
        'cornering' => cornering,
        'coasting' => lap.states.coasting,
        _ => null,
      };
      final intervals = track?.active ?? lap.overlap;
      final bool known, inferred;
      final String tag;
      if (track != null) {
        known = track.isKnown;
        inferred = track.provenance == drivingStateInferred;
        tag = provenanceLabel(track);
      } else {
        // Braking while cornering needs both states.
        known = braking.isKnown && cornering.isKnown;
        inferred = braking.provenance == drivingStateInferred;
        tag = !known
            ? provenanceLabel(braking.isKnown ? cornering : braking)
            : inferred
            ? 'inferred'
            : cornering.provenance == drivingStateCalculated
            ? 'brake measured, lateral G from GPS'
            : 'measured';
      }
      final seconds = intervalSeconds(intervals);
      final share = lap.seconds > 0 ? 100 * seconds / lap.seconds : 0.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            known
                // A number keeps its unit: a narrow column wraps after
                // the "·" only.
                ? state == 'trail'
                      ? '${seconds.toStringAsFixed(1)}\u00a0s · '
                            '${lap.overlapMeters.round()}\u00a0m'
                      : '${seconds.toStringAsFixed(1)}\u00a0s · '
                            '${share.round()}\u00a0%'
                : '—',
            key: key,
            textAlign: TextAlign.end,
          ),
          Text(
            tag,
            key: ValueKey('drivingSource $state ${_lapNames[slot]}'),
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall?.copyWith(
              color: inferred
                  ? readableOn(context, inferredColor)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    TableRow row(String label, Color color, String state) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(width: 10, height: 10, color: color),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: theme.textTheme.bodySmall)),
            ],
          ),
        ),
        for (final slot in const [0, 1])
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
            child: cell(slot, state),
          ),
      ],
    );

    return _PanelCard(
      key: const ValueKey('drivingStatesPanel'),
      title: 'Driving states',
      subtitle: _stretchText(range, window),
      children: [
        for (final slot in const [0, 1])
          if (slot < laps.length && laps[slot].valid)
            _LapStrip(
              key: ValueKey('drivingStrip ${_lapNames[slot]}'),
              slot: slot,
              lanes: lanes(slot),
              cursor: cursor,
              onTapFraction: (fraction) => window.cursor.value =
                  range.$1 + (range.$2 - range.$1) * fraction,
            )
          else
            Text(
              '${_lapNames[slot]}: ${ggReasonText(slot < laps.length ? laps[slot].unavailableReason : '')}',
              style: theme.textTheme.bodySmall,
            ),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.3),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (final slot in const [0, 1])
                  Text(
                    _lapNames[slot],
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: readableOn(context, _lapColors[slot]),
                    ),
                  ),
              ],
            ),
            row('Braking', brakingStateColor, 'braking'),
            row('Braking while cornering', trailBrakingStateColor, 'trail'),
            row('Cornering', corneringStateColor, 'cornering'),
            row('Accelerating', acceleratingStateColor, 'accelerating'),
            row('Coasting', coastingStateColor, 'coasting'),
          ],
        ),
        const SizedBox(height: 8),
        for (final slot in const [0, 1])
          if (slot < laps.length && laps[slot].valid)
            Text(
              '${_lapNames[slot]}: ${pedalSourceText(laps[slot].states)}',
              key: ValueKey('drivingSources ${_lapNames[slot]}'),
              style: theme.textTheme.bodySmall,
            ),
        Text(
          'Each lap\'s share of its own time over this stretch. States '
          'overlap: cornering can come with braking, accelerating or '
          'coasting. Tap a strip to move the cursor there. Longer braking '
          'while cornering is not automatically better or safer.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Where each lap coasts over the shown stretch: totals, where on the
/// stretch, and each episode, which moves the cursor there.
class ComparisonCoastingPanel extends StatefulWidget {
  const ComparisonCoastingPanel({
    super.key,
    required this.comparison,
    required this.window,
  });

  final LapComparison comparison;
  final ChartWindow window;

  @override
  State<ComparisonCoastingPanel> createState() =>
      _ComparisonCoastingPanelState();
}

class _ComparisonCoastingPanelState
    extends _RangeState<ComparisonCoastingPanel, List<LapDrivingStates>>
    with _CursorFractionState<ComparisonCoastingPanel> {
  @override
  LapComparison get comparison => widget.comparison;
  @override
  ChartWindow get window => widget.window;

  @override
  List<LapDrivingStates> compute((double, double) range) =>
      comparisonDrivingStates(comparison, range.$1, range.$2);

  @override
  Widget buildFor(
    BuildContext context,
    (double, double) range,
    List<LapDrivingStates> laps,
  ) {
    final theme = Theme.of(context);
    final cursor = cursorFraction(window.cursor, range);
    final of = window.zoomed ? 'the stretch' : 'the lap';
    return _PanelCard(
      key: const ValueKey('comparisonCoastingPanel'),
      title: 'Coasting',
      subtitle: _stretchText(range, window),
      children: [
        for (final slot in const [0, 1]) ...[
          Builder(
            builder: (context) {
              final lap = slot < laps.length ? laps[slot] : null;
              final coasting = lap?.coasting;
              final known =
                  lap != null &&
                  lap.valid &&
                  coasting!.provenance != drivingStateUnknown;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_lapNames[slot]}  ',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: readableOn(context, _lapColors[slot]),
                          ),
                        ),
                        TextSpan(
                          text: known
                              ? coastingSummaryText(coasting, of)
                              : lap == null || !lap.valid
                              ? ggReasonText(lap?.unavailableReason ?? '')
                              : 'Not available',
                        ),
                      ],
                    ),
                    key: ValueKey('coastingSummary ${_lapNames[slot]}'),
                  ),
                  if (lap != null && lap.valid)
                    Text(
                      coastingProvenanceText(coasting!),
                      key: ValueKey('coastingSource ${_lapNames[slot]}'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: coasting.provenance == drivingStateInferred
                            ? readableOn(context, inferredColor)
                            : null,
                      ),
                    ),
                  if (known) ...[
                    _LapStrip(
                      key: ValueKey('coastingStrip ${_lapNames[slot]}'),
                      slot: slot,
                      lanes: [
                        (
                          coastingStateColor,
                          stripFractions(
                            lap.states.coasting.active,
                            comparison.trace(slot),
                            range.$1,
                            range.$2,
                          ),
                        ),
                      ],
                      cursor: cursor,
                      onTapFraction: (fraction) => window.cursor.value =
                          range.$1 + (range.$2 - range.$1) * fraction,
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        for (final (index, episode)
                            in coasting.episodes.indexed)
                          if (episode.startProgressMeters != null)
                            ActionChip(
                              key: ValueKey(
                                'coastingEpisode ${_lapNames[slot]} $index',
                              ),
                              label: Text(
                                '${episode.startProgressMeters!.round()} m · '
                                '${episode.seconds.toStringAsFixed(1)} s',
                              ),
                              onPressed: () => window.cursor.value =
                                  episode.startProgressMeters!,
                            ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ],
        Text(
          '$coastingNote Each episode is listed by where it starts on the '
          'track; select one to move the cursor there.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
