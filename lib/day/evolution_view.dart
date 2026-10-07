import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'touch.dart';
import 'weather_text.dart';

/// A session's line colour: fainter for earlier sessions. The marker
/// ([EvolutionMarker]) and the label at the line's end tell sessions apart;
/// the colour only hints at their order.
Color evolutionColor(ColorScheme scheme, int index, int count) => Color.lerp(
  scheme.outlineVariant,
  scheme.primary,
  count <= 1 ? 1.0 : 0.25 + 0.75 * index / (count - 1),
)!;

/// A session's marker shape on the By lap chart, by its place in the list.
enum EvolutionMarker {
  circle,
  square,
  triangle,
  diamond,
  cross,
  plus;

  static EvolutionMarker of(int index) => values[index % values.length];

  /// Draws the marker centred on [centre], [radius] across half its width.
  void paint(Canvas canvas, Offset centre, double radius, Color color) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    switch (this) {
      case EvolutionMarker.circle:
        canvas.drawCircle(centre, radius, fill);
      case EvolutionMarker.square:
        canvas.drawRect(
          Rect.fromCenter(
            center: centre,
            width: radius * 1.8,
            height: radius * 1.8,
          ),
          fill,
        );
      case EvolutionMarker.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx, centre.dy - radius * 1.2)
            ..lineTo(centre.dx + radius * 1.1, centre.dy + radius * 0.9)
            ..lineTo(centre.dx - radius * 1.1, centre.dy + radius * 0.9)
            ..close(),
          fill,
        );
      case EvolutionMarker.diamond:
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx, centre.dy - radius * 1.3)
            ..lineTo(centre.dx + radius * 1.1, centre.dy)
            ..lineTo(centre.dx, centre.dy + radius * 1.3)
            ..lineTo(centre.dx - radius * 1.1, centre.dy)
            ..close(),
          fill,
        );
      case EvolutionMarker.cross:
        canvas.drawLine(
          centre + Offset(-radius, -radius),
          centre + Offset(radius, radius),
          stroke,
        );
        canvas.drawLine(
          centre + Offset(-radius, radius),
          centre + Offset(radius, -radius),
          stroke,
        );
      case EvolutionMarker.plus:
        canvas.drawLine(
          centre + Offset(-radius * 1.2, 0),
          centre + Offset(radius * 1.2, 0),
          stroke,
        );
        canvas.drawLine(
          centre + Offset(0, -radius * 1.2),
          centre + Offset(0, radius * 1.2),
          stroke,
        );
    }
  }
}

/// Why a lap is not ranked, as the day's lap list says it: "Excluded:
/// yellow flag", "Not ranked: Incomplete GPS".
String evolutionNotRankedText(AppLocalizations l10n, EvolutionLap lap) {
  if (lap.issues.contains(LapIssue.userExclusion)) {
    return lap.userReason.isEmpty
        ? l10n.lapExcludedNoReason
        : l10n.lapExcluded(lap.userReason);
  }
  return lap.issues.isEmpty
      ? l10n.lapNotRanked(l10n.lapIssue(LapIssue.ineligibleLap))
      : l10n.lapNotRanked(l10n.lapIssue(lap.issues.first));
}

/// The progression's By lap view (FET-227): every timed lap of each session
/// in order on a chart and in a table, the first lap in each session's
/// middle half, and each session against the one before at the same laps.
class EvolutionView extends StatelessWidget {
  const EvolutionView({
    super.key,
    required this.evolution,
    this.onOpenLap,
    this.weatherOf,
  });

  final DayEvolution evolution;
  final void Function(DayLapRow lap)? onOpenLap;

  /// A session's weather by run id, or null.
  final SessionWeather? Function(String runId)? weatherOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final evolution = this.evolution;
    if (!evolution.hasLaps) {
      return Text(l10n.evolutionNoLaps, key: const ValueKey('evolutionNone'));
    }
    final sessions = evolution.sessions;
    final colors = [
      for (var i = 0; i < sessions.length; ++i)
        evolutionColor(theme.colorScheme, i, sessions.length),
    ];
    final low = evolution.minimumSeconds, high = evolution.maximumSeconds;
    var weatherShown = false;
    final small = theme.textTheme.bodySmall;
    final details = <Widget>[];
    for (final session in sessions) {
      final weather = weatherOf?.call(session.runId);
      final air = weather == null
          ? null
          : weatherTemperatureText(l10n, weather.summary);
      if (air != null) weatherShown = true;
      details.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            key: ValueKey('evolutionSession ${session.runId}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.session(session.runName),
                style: theme.textTheme.titleSmall,
              ),
              if (air != null)
                Text(
                  l10n.evolutionAir(air),
                  key: ValueKey('evolutionAir ${session.runId}'),
                  style: small,
                ),
              ..._paceLines(l10n, session, small),
              if (session.previousRunName case final previous?)
                Text(
                  session.sameLapsDeltaSeconds == null
                      ? l10n.evolutionSameLapsTooFew(
                          l10n.session(previous),
                          session.sameLapsCount,
                          minimumConsistencySamples,
                        )
                      : l10n.evolutionSameLaps(
                          l10n.session(previous),
                          displayDelta(session.sameLapsDeltaSeconds!),
                          session.sameLapsCount,
                        ),
                  key: ValueKey('evolutionSameLaps ${session.runId}'),
                  style: small,
                ),
              for (final lap in session.laps)
                if (!lap.eligible)
                  Text(
                    '${l10n.evolutionLap(lap.lapNumber)} · '
                    '${evolutionNotRankedText(l10n, lap)}',
                    key: ValueKey(
                      'evolutionNotRanked ${session.runId} ${lap.lapNumber}',
                    ),
                    style: small,
                  ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.evolutionIntro, style: small),
        const SizedBox(height: 8),
        if (low != null && high != null) ...[
          _Chart(evolution: evolution, colors: colors, low: low, high: high),
          const SizedBox(height: 8),
        ],
        _Table(evolution: evolution, colors: colors, onOpenLap: onOpenLap),
        const SizedBox(height: 8),
        Text(
          l10n.evolutionPaceExplained(minimumConsistencySamples),
          style: small,
        ),
        ...details,
        const SizedBox(height: 8),
        Text(
          l10n.evolutionCaveat,
          key: const ValueKey('evolutionCaveat'),
          style: small,
        ),
        if (weatherShown)
          Text(
            '${l10n.weatherModelled} ${weatherCredit(l10n)}',
            key: const ValueKey('evolutionWeatherCredit'),
            style: small,
          ),
      ],
    );
  }

  List<Widget> _paceLines(
    AppLocalizations l10n,
    SessionEvolution session,
    TextStyle? style,
  ) {
    if (session.laps.isEmpty) {
      return [Text(l10n.progressionNoRecordedLaps, style: style)];
    }
    final pace = session.paceLapNumber;
    if (pace == null) {
      return [
        Text(
          l10n.evolutionPaceNeedsLaps(minimumConsistencySamples),
          key: ValueKey('evolutionPace ${session.runId}'),
          style: style,
        ),
      ];
    }
    final first = session.laps.firstWhere((lap) => lap.lapNumber == pace);
    return [
      Text(
        l10n.evolutionPaceFrom(pace, session.lapsBeforePace),
        key: ValueKey('evolutionPace ${session.runId}'),
        style: style,
      ),
      if (session.notCountedBeforePace > 0)
        Text(
          l10n.evolutionPaceNotCounted(session.notCountedBeforePace),
          style: style,
        ),
      if (session.quickerLaterLap case final later?)
        Text(
          l10n.evolutionQuickerLater(
            later.lapNumber,
            displayTime(first.seconds - later.seconds),
            pace,
          ),
          key: ValueKey('evolutionQuickerLater ${session.runId}'),
          style: style,
        ),
    ];
  }
}

/// Lap time by lap number, one line per session, each with its own marker
/// and its name at its last lap; a lap that is not ranked breaks its line.
class _Chart extends StatelessWidget {
  const _Chart({
    required this.evolution,
    required this.colors,
    required this.low,
    required this.high,
  });

  final DayEvolution evolution;
  final List<Color> colors;
  final double low, high;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final label = theme.textTheme.labelSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: theme.colorScheme.onSurfaceVariant,
    );
    final sessions = evolution.sessions;
    final laps = evolution.maximumLapNumber;
    return Semantics(
      label: l10n.evolutionChartLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 200,
              width: double.infinity,
              child: CustomPaint(
                key: const ValueKey('evolutionChart'),
                painter: _EvolutionPainter(
                  evolution: evolution,
                  colors: colors,
                  low: low,
                  high: high,
                  grid: theme.colorScheme.outlineVariant,
                  labelStyle: label ?? const TextStyle(fontSize: 11),
                  slowest: displayTime(high),
                  quickest: displayTime(low),
                  firstLap: l10n.evolutionLap(1),
                  lastLap: laps > 1 ? l10n.evolutionLap(laps) : null,
                  names: [
                    for (final session in sessions)
                      l10n.session(session.runName),
                  ],
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (var i = 0; i < sessions.length; ++i)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CustomPaint(
                          painter: _MarkerPainter(
                            EvolutionMarker.of(i),
                            colors[i],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.session(sessions[i].runName),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.marker, this.color);

  final EvolutionMarker marker;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => marker.paint(
    canvas,
    size.center(Offset.zero),
    size.shortestSide / 3,
    color,
  );

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.marker != marker || old.color != color;
}

class _EvolutionPainter extends CustomPainter {
  _EvolutionPainter({
    required this.evolution,
    required this.colors,
    required this.low,
    required this.high,
    required this.grid,
    required this.labelStyle,
    required this.slowest,
    required this.quickest,
    required this.firstLap,
    required this.lastLap,
    required this.names,
    required this.textScaler,
  });

  final DayEvolution evolution;
  final List<Color> colors;
  final double low, high;
  final Color grid;
  final TextStyle labelStyle;
  final String slowest, quickest, firstLap;
  final String? lastLap;
  final List<String> names;
  final TextScaler textScaler;

  static const _pad = 6.0, _gap = 6.0, _nameWidth = 84.0;

  TextPainter _text(String text, TextStyle style, [double? maxWidth]) =>
      TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth ?? double.infinity);

  @override
  void paint(Canvas canvas, Size size) {
    final top = _text(slowest, labelStyle),
        bottom = _text(quickest, labelStyle);
    final first = _text(firstLap, labelStyle);
    final last = lastLap == null ? null : _text(lastLap!, labelStyle);
    final gutter = math.max(top.width, bottom.width) + _gap;
    final sessions = evolution.sessions;
    final nameWidth = math.min(_nameWidth, size.width / 4);
    final labels = [
      for (var i = 0; i < sessions.length; ++i)
        _text(names[i], labelStyle.copyWith(color: colors[i]), nameWidth),
    ];
    final labelWidth = labels.fold(0.0, (w, label) => math.max(w, label.width));
    // The plot: left of the session names, above the lap numbers.
    final left = gutter + _pad;
    final right = math.max(left + 1, size.width - labelWidth - _gap - _pad);
    final plotTop = _pad;
    final plotBottom = math.max(plotTop + 1, size.height - first.height - _gap);
    final laps = evolution.maximumLapNumber;
    double x(int lap) => laps <= 1
        ? (left + right) / 2
        : left + (right - left) * (lap - 1) / (laps - 1);
    // Slower laps higher up.
    double y(double seconds) => high <= low
        ? (plotTop + plotBottom) / 2
        : plotTop +
              (plotBottom - plotTop) *
                  ((high - seconds) / (high - low)).clamp(0.0, 1.0);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, y(high)), Offset(right, y(high)), gridPaint);
    canvas.drawLine(Offset(left, y(low)), Offset(right, y(low)), gridPaint);
    top.paint(
      canvas,
      Offset(gutter - _gap - top.width, y(high) - top.height / 2),
    );
    bottom.paint(
      canvas,
      Offset(gutter - _gap - bottom.width, y(low) - bottom.height / 2),
    );
    // Lap numbers centred under their lap.
    final axis = plotBottom + _gap;
    first.paint(canvas, Offset(x(1) - first.width / 2, axis));
    if (last != null) {
      last.paint(canvas, Offset(x(laps) - last.width / 2, axis));
    }

    final placed = <Rect>[];
    for (var i = 0; i < sessions.length; ++i) {
      final line = Paint()
        ..color = colors[i]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final marker = EvolutionMarker.of(i);
      Offset? previous, end;
      for (final lap in sessions[i].laps) {
        if (!lap.eligible) {
          previous = null;
          continue;
        }
        final point = Offset(x(lap.lapNumber), y(lap.seconds));
        if (previous != null) canvas.drawLine(previous, point, line);
        previous = point;
        end = point;
      }
      for (final lap in sessions[i].laps) {
        if (lap.eligible) {
          marker.paint(
            canvas,
            Offset(x(lap.lapNumber), y(lap.seconds)),
            4,
            colors[i],
          );
        }
      }
      if (end == null) continue;
      // The session's name at its last lap, moved down past names already
      // placed so none covers another.
      final label = labels[i];
      var rect = Rect.fromLTWH(
        end.dx + _gap,
        end.dy - label.height / 2,
        label.width,
        label.height,
      );
      for (var tries = 0; tries < sessions.length; ++tries) {
        final overlap = placed.where((other) => other.overlaps(rect));
        if (overlap.isEmpty) break;
        rect = rect.translate(0, overlap.first.bottom - rect.top + 1);
      }
      placed.add(rect);
      label.paint(canvas, rect.topLeft);
    }
  }

  @override
  bool shouldRepaint(_EvolutionPainter old) =>
      old.evolution != evolution ||
      old.low != low ||
      old.high != high ||
      old.grid != grid ||
      old.labelStyle != labelStyle ||
      old.slowest != slowest ||
      old.quickest != quickest ||
      old.firstLap != firstLap ||
      old.lastLap != lastLap ||
      old.textScaler != textScaler ||
      !_same(old.colors, colors) ||
      !_same(old.names, names);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; ++i) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Sessions by lap number: the session names stay while the laps scroll
/// sideways on a phone, so a column is the same point of every session.
class _Table extends StatelessWidget {
  const _Table({required this.evolution, required this.colors, this.onOpenLap});

  final DayEvolution evolution;
  final List<Color> colors;
  final void Function(DayLapRow lap)? onOpenLap;

  static const _nameWidth = 112.0, _cellWidth = 88.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final label = theme.textTheme.labelMedium;
    final laps = evolution.maximumLapNumber;
    final sessions = evolution.sessions;
    return StickyTable(
      key: const ValueKey('evolutionTable'),
      firstWidth: _nameWidth,
      cellWidths: [for (var n = 0; n < laps; ++n) _cellWidth],
      rowHeight: 52,
      header: StickyRow(
        first: const SizedBox.shrink(),
        cells: [
          for (var n = 1; n <= laps; ++n)
            TableCellText(
              l10n.evolutionLap(n),
              style: label,
              alignment: Alignment.center,
            ),
        ],
      ),
      rows: [
        for (var i = 0; i < sessions.length; ++i)
          StickyRow(
            first: Row(
              children: [
                const SizedBox(width: 6),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CustomPaint(
                    painter: _MarkerPainter(EvolutionMarker.of(i), colors[i]),
                  ),
                ),
                Expanded(
                  child: TableCellText(
                    l10n.session(sessions[i].runName),
                    style: label,
                    alignment: Alignment.centerLeft,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            cells: [
              for (var n = 1; n <= laps; ++n) _cell(context, sessions[i], n),
            ],
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, SessionEvolution session, int number) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final scheme = theme.colorScheme;
    EvolutionLap? lap;
    for (final candidate in session.laps) {
      if (candidate.lapNumber == number) {
        lap = candidate;
        break;
      }
    }
    final numbers = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final small = theme.textTheme.labelSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (lap == null) {
      return Center(
        child: Text('—', style: numbers?.copyWith(color: scheme.outline)),
      );
    }
    final pace = session.paceLapNumber;
    // Before the first lap in the session's middle half: grey.
    final early = pace != null && number < pace;
    final colour = !lap.eligible || early ? scheme.outline : null;
    final shown = lap;
    return InkWell(
      key: ValueKey('evolutionCell ${session.runId} $number'),
      onTap: onOpenLap == null ? null : () => onOpenLap!(shown.row),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // Only a last resort: the cell grows with the text size.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lap.eligible ? displayTime(lap.seconds) : '—',
                style: numbers?.copyWith(
                  fontWeight: lap.eligible ? FontWeight.bold : null,
                  color: colour,
                ),
              ),
              Text(
                lap.eligible
                    ? l10n.evolutionSinceFirstLap(
                        displayClock(lap.secondsSinceFirstLap),
                      )
                    : l10n.evolutionNotRanked,
                style: small?.copyWith(color: colour),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
