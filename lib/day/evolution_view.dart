import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'touch.dart';
import 'weather_text.dart';

/// "2:31" from 151 seconds: when a lap began after the session's first
/// timed lap.
String sinceFirstLapText(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '—';
  final whole = seconds.round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

/// A session's line colour: fainter for earlier sessions.
Color evolutionColor(ColorScheme scheme, int index, int count) => Color.lerp(
  scheme.outlineVariant,
  scheme.primary,
  count <= 1 ? 1.0 : 0.25 + 0.75 * index / (count - 1),
)!;

/// The progression's By lap view (FET-227): every timed lap of each session
/// in order on a chart and in a table, when each session reached its own
/// pace, and each session against the one before at the same laps.
class EvolutionView extends StatelessWidget {
  const EvolutionView({
    super.key,
    required this.evolution,
    this.onOpenLap,
    this.weatherOf,
  });

  final DayEvolution? evolution;
  final void Function(DayLapRow lap)? onOpenLap;

  /// A session's weather by run id, or null.
  final SessionWeather? Function(String runId)? weatherOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final evolution = this.evolution;
    if (evolution == null || !evolution.hasLaps) {
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
    for (var i = 0; i < sessions.length; ++i) {
      final session = sessions[i];
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
                '${i + 1}. ${l10n.session(session.runName)}',
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
    ];
  }
}

/// Lap time by lap number, one line per session; a lap that is not counted
/// breaks its line.
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
    );
    final sessions = evolution.sessions;
    return Semantics(
      label: l10n.evolutionChartLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(displayTime(high), style: label),
                      Text(displayTime(low), style: label),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: CustomPaint(
                      key: const ValueKey('evolutionChart'),
                      painter: _EvolutionPainter(
                        evolution: evolution,
                        colors: colors,
                        low: low,
                        high: high,
                        grid: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const Spacer(),
                Text(l10n.evolutionLap(1), style: label),
                const Spacer(flex: 8),
                Text(
                  l10n.evolutionLap(evolution.maximumLapNumber),
                  style: label,
                ),
              ],
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
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i],
                          shape: BoxShape.circle,
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

class _EvolutionPainter extends CustomPainter {
  const _EvolutionPainter({
    required this.evolution,
    required this.colors,
    required this.low,
    required this.high,
    required this.grid,
  });

  final DayEvolution evolution;
  final List<Color> colors;
  final double low, high;
  final Color grid;

  static const _pad = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final laps = evolution.maximumLapNumber;
    double x(int lap) => laps <= 1
        ? size.width / 2
        : _pad + (size.width - 2 * _pad) * (lap - 1) / (laps - 1);
    // Slower laps higher up.
    double y(double seconds) => high <= low
        ? size.height / 2
        : _pad +
              (size.height - 2 * _pad) *
                  ((high - seconds) / (high - low)).clamp(0.0, 1.0);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(high)), Offset(size.width, y(high)), gridPaint);
    canvas.drawLine(Offset(0, y(low)), Offset(size.width, y(low)), gridPaint);
    final sessions = evolution.sessions;
    for (var i = 0; i < sessions.length; ++i) {
      final line = Paint()
        ..color = colors[i]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final dot = Paint()..color = colors[i];
      Offset? previous;
      for (final lap in sessions[i].laps) {
        if (!lap.eligible) {
          previous = null;
          continue;
        }
        final point = Offset(x(lap.lapNumber), y(lap.seconds));
        if (previous != null) canvas.drawLine(previous, point, line);
        canvas.drawCircle(point, 3, dot);
        previous = point;
      }
    }
  }

  @override
  bool shouldRepaint(_EvolutionPainter old) =>
      old.evolution != evolution ||
      old.low != low ||
      old.high != high ||
      old.grid != grid ||
      !_sameColors(old.colors, colors);

  static bool _sameColors(List<Color> a, List<Color> b) {
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
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors[i],
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: TableCellText(
                    '${i + 1}. ${l10n.session(sessions[i].runName)}',
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
    // Before the session reached its pace: grey.
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
                        sinceFirstLapText(lap.secondsSinceFirstLap),
                      )
                    : l10n.evolutionNotCounted,
                style: small?.copyWith(color: colour),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
