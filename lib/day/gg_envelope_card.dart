import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import 'background_task.dart';
import 'driving_panels.dart' show ggReasonText, ggScale;
import 'touch.dart' show readableOn;

/// What the envelope is worked out from: the laps that count and each
/// run's G channels ([ggEnvelopeSession]).
typedef GgEnvelopeInput = ({
  List<DayLapRow> laps,
  Map<String, TelemetrySession?> sessions,
});

/// Starts the envelope's calculation; replaced in widget tests.
typedef GgEnvelopeRunner = BackgroundTask<DayGgEnvelope> Function(
  GgEnvelopeInput input,
);

/// In a background isolate, stopped at once when cancelled; under
/// `flutter test` as a microtask, which a widget test's fake clock runs
/// without leaving a timer behind, stopped at its next cancellation check.
BackgroundTask<DayGgEnvelope> defaultGgEnvelopeRunner(GgEnvelopeInput input) =>
    backgroundRunsInline
    ? _InlineGgEnvelopeTask(input)
    : runInBackground(_ggEnvelopeJob, input);

// Failures come back as in [runInBackground].
final class _InlineGgEnvelopeTask implements BackgroundTask<DayGgEnvelope> {
  _InlineGgEnvelopeTask(GgEnvelopeInput input) {
    result = Future.microtask(() {
      if (_cancelled) throw const OperationCancelled();
      try {
        return _ggEnvelopeJob(input, () => _cancelled);
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(backgroundFailure(error), stack);
      }
    });
  }

  bool _cancelled = false;

  @override
  late final Future<DayGgEnvelope> result;

  @override
  void cancel() => _cancelled = true;
}

DayGgEnvelope _ggEnvelopeJob(
  GgEnvelopeInput input,
  CancellationCheck cancelled,
) => dayGgEnvelope(input.laps, input.sessions, cancelled: cancelled);

/// The sessions' colours, earliest to latest: from blue to yellow, none of
/// them lap A's amber, lap B's blue or the day's best purple, each readable
/// on the dark panels.
const List<Color> ggSessionRamp = [
  Color(0xff4fb3ff),
  Color(0xff2fd6a8),
  Color(0xffb5e550),
  Color(0xffffe45c),
];

/// The colour of session [index] of [count].
Color ggSessionColor(int index, int count) {
  if (count <= 1) return ggSessionRamp.last;
  final t = index / (count - 1) * (ggSessionRamp.length - 1);
  final lower = t.floor().clamp(0, ggSessionRamp.length - 2);
  return Color.lerp(ggSessionRamp[lower], ggSessionRamp[lower + 1], t - lower)!;
}

/// "0.94 g".
String ggValueText(double value) => '${fixed(value, 2)}\u00a0g';

extension GgEnvelopeText on AppLocalizations {
  /// A direction's name: "Braking + turning left".
  String ggDirection(GgDirection direction) => switch (direction) {
    GgDirection.accelerating => ggDirectionAccelerating,
    GgDirection.acceleratingLeft => ggDirectionAcceleratingLeft,
    GgDirection.left => ggDirectionLeft,
    GgDirection.brakingLeft => ggDirectionBrakingLeft,
    GgDirection.braking => ggDirectionBraking,
    GgDirection.brakingRight => ggDirectionBrakingRight,
    GgDirection.right => ggDirectionRight,
    GgDirection.acceleratingRight => ggDirectionAcceleratingRight,
  };

  /// Why a session has no envelope.
  String ggEnvelopeReason(String reason) => switch (reason) {
    // `this.`: the core's reason constants have the same names.
    ggEnvelopeTooFewSamples => this.ggEnvelopeTooFewSamples(
      ggEnvelopeMinimumSamples,
    ),
    channelRecordingUnavailable => this.channelRecordingUnavailable,
    _ => ggReasonText(this, reason),
  };
}

/// The G-G envelope of each session over the shown group's ranked laps
/// (FET-230), worked out in the background whenever the laps or the
/// sessions' G channels change.
class GgEnvelopeCard extends StatefulWidget {
  const GgEnvelopeCard({
    super.key,
    required this.laps,
    required this.sessionOf,
    this.runner = defaultGgEnvelopeRunner,
  });

  /// The laps that count: the shown group's eligible laps
  /// (`dayEligibleLaps`), without out, in and excluded laps.
  final List<DayLapRow> laps;

  /// The session of a run as the analysis that reads channels sees it.
  final TelemetrySession? Function(String runId) sessionOf;
  final GgEnvelopeRunner runner;

  @override
  State<GgEnvelopeCard> createState() => _GgEnvelopeCardState();
}

class _GgEnvelopeCardState extends State<GgEnvelopeCard> {
  BackgroundTask<DayGgEnvelope>? _task;
  int _generation = 0;
  List<Object?> _key = const [];
  DayGgEnvelope? _result;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(GgEnvelopeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _task?.cancel();
    super.dispose();
  }

  // Starts again when the laps, their sessions' names or a run's G
  // channels are not the ones the shown result (or the one on its way) was
  // worked out from: a renamed session is named anew.
  void _update() {
    final runIds = {for (final row in widget.laps) row.runId};
    final sessions = {for (final id in runIds) id: widget.sessionOf(id)};
    final key = <Object?>[
      for (final row in widget.laps) ...[row.reference, row.runName],
      for (final MapEntry(key: id, value: session) in sessions.entries) ...[
        id,
        session?.channel('longitudinalAcceleration'),
        session?.channel('lateralAcceleration'),
      ],
    ];
    if (listEquals(key, _key)) return;
    _key = key;
    _start(sessions);
  }

  void _start(Map<String, TelemetrySession?> sessions) {
    _task?.cancel();
    final generation = ++_generation;
    // The result shown stays until the new one arrives.
    _error = '';
    final BackgroundTask<DayGgEnvelope> task;
    try {
      task = widget.runner((
        laps: List.of(widget.laps),
        sessions: {
          for (final MapEntry(key: id, value: session) in sessions.entries)
            id: session == null ? null : ggEnvelopeSession(session),
        },
      ));
    } on Object catch (failure) {
      _result = null;
      _error = '$failure';
      return;
    }
    _task = task;
    task.result.then(
      (result) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _task = null;
          _result = result.error.isEmpty ? result : null;
          _error = result.error;
        });
      },
      onError: (Object failure) {
        if (!mounted ||
            generation != _generation ||
            failure is OperationCancelled) {
          return;
        }
        setState(() {
          _task = null;
          _result = null;
          _error = '$failure';
        });
      },
    );
  }

  void _retry() => setState(() {
    final runIds = {for (final row in widget.laps) row.runId};
    _start({for (final id in runIds) id: widget.sessionOf(id)});
  });

  @override
  Widget build(BuildContext context) => GgEnvelopeView(
    envelope: _result,
    loading: _task != null,
    error: _error,
    onRetry: _retry,
  );
}

/// The G-G envelope card's contents: the diagram, the best of the day and
/// the latest session per direction, what the latest session leaves unused,
/// and why a session has none.
class GgEnvelopeView extends StatelessWidget {
  const GgEnvelopeView({
    super.key,
    required this.envelope,
    this.loading = false,
    this.error = '',
    this.onRetry,
  });

  final DayGgEnvelope? envelope;
  final bool loading;
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final small = theme.textTheme.bodySmall;
    return Card(
      key: const ValueKey('ggEnvelopeCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.ggEnvelopeTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(l10n.ggEnvelopeIntro, style: small),
            const SizedBox(height: 8),
            // Calculated again for changed laps: the earlier result stays
            // until the new one arrives.
            if (loading && envelope != null && error.isEmpty) ...[
              LinearProgressIndicator(
                key: const ValueKey('ggEnvelopeRecalculating'),
                semanticsLabel: l10n.ggEnvelopeCalculating,
              ),
              const SizedBox(height: 8),
            ],
            ..._body(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final l10n = context.l10n;
    final envelope = this.envelope;
    if (error.isNotEmpty) {
      return [
        Text(
          l10n.ggEnvelopeFailed(error),
          key: const ValueKey('ggEnvelopeError'),
        ),
        if (onRetry != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onRetry,
              child: Text(l10n.calculateAgain),
            ),
          ),
      ];
    }
    if (envelope == null) {
      return [Text(l10n.ggEnvelopeCalculating)];
    }
    final notes = [
      for (final session in envelope.sessions)
        if (!session.valid)
          l10n.ggEnvelopeSessionUnavailable(
            l10n.session(session.runName),
            l10n.ggEnvelopeReason(session.unavailableReason),
          ),
    ];
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    if (!envelope.any) {
      return [
        Text(l10n.ggEnvelopeNone, key: const ValueKey('ggEnvelopeNone')),
        for (final note in notes) Text(note, style: small),
      ];
    }
    final colors = FetColors.of(context);
    final valid = [
      for (final session in envelope.sessions)
        if (session.valid) session,
    ];
    final latest = envelope.latest;
    final margin = ggValueText(ggEnvelopeUnusedMarginG);
    Color sessionColor(SessionGgEnvelope session) => readableOn(
      context,
      ggSessionColor(
        envelope.sessions.indexOf(session),
        envelope.sessions.length,
      ),
    );
    final unusedText = latest == null
        ? null
        : !latest.valid
        ? l10n.ggEnvelopeLatestNone(l10n.session(latest.runName))
        : valid.length < 2
        ? l10n.ggEnvelopeOneSession
        : envelope.unused.isEmpty
        ? l10n.ggEnvelopeAllUsed(l10n.session(latest.runName), margin)
        : l10n.ggEnvelopeUnused(
            l10n.session(latest.runName),
            [
              for (final unused in envelope.unused)
                l10n.ggEnvelopeUnusedItem(
                  l10n.ggDirection(unused.direction),
                  ggValueText(unused.latestG),
                  ggValueText(unused.best.valueG),
                  l10n.session(unused.best.runName),
                ),
            ].join('; '),
          );
    return [
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final session in valid)
            _LegendEntry(
              label: l10n.session(session.runName),
              color: sessionColor(session),
              thick: identical(session, latest),
            ),
          _LegendEntry(
            label: l10n.ggEnvelopeBestOfDay,
            color: colors.dayBest,
            dashed: true,
          ),
        ],
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SizedBox.square(
            dimension: math.min(constraints.maxWidth, 300.0),
            child: Semantics(
              label: l10n.ggEnvelopeSemantics,
              child: CustomPaint(
                key: const ValueKey('ggEnvelopePlot'),
                painter: GgEnvelopePainter(
                  sessions: [
                    for (final session in valid)
                      (
                        values: [
                          for (final direction in GgDirection.values)
                            session.valueG(direction),
                        ],
                        color: sessionColor(session),
                        latest: identical(session, latest),
                      ),
                  ],
                  best: [for (final best in envelope.best) best?.valueG],
                  bestColor: colors.dayBest,
                  gridColor: theme.colorScheme.outlineVariant,
                  labelStyle: theme.textTheme.labelSmall!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  axisLabels: [
                    l10n.drivingGgAccelerating,
                    l10n.drivingGgBraking,
                    l10n.drivingGgLeft,
                    l10n.drivingGgRight,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      _table(context, envelope, latest),
      if (unusedText != null) ...[
        const SizedBox(height: 8),
        Text(unusedText, key: const ValueKey('ggEnvelopeUnused')),
      ],
      const SizedBox(height: 8),
      for (final note in notes) Text(note, style: small),
      // Every session, with an envelope or not.
      for (final session in envelope.sessions)
        if (session.excludedOutliers > 0)
          Text(
            l10n.ggEnvelopeOutliers(
              l10n.session(session.runName),
              session.excludedOutliers,
              '${fixed(ggPlausibleLimitG, 0)}\u00a0g',
            ),
            key: ValueKey('ggEnvelopeOutliers ${session.runId}'),
            style: small,
          ),
      for (final source in _sources(l10n, valid)) Text(source, style: small),
      Text(l10n.ggEnvelopeMissingNote(ggEnvelopeMinimumSamples), style: small),
      Text(l10n.ggEnvelopeNote(margin), style: small),
    ];
  }

  Widget _table(
    BuildContext context,
    DayGgEnvelope envelope,
    SessionGgEnvelope? latest,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final header = theme.textTheme.labelMedium;
    final unused = {for (final item in envelope.unused) item.direction};
    Widget cell(String text, {Key? key, TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(text, key: key, textAlign: TextAlign.end, style: style),
    );
    return Table(
      key: const ValueKey('ggEnvelopeTable'),
      columnWidths: const {
        0: FlexColumnWidth(1.6),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            Text(l10n.ggEnvelopeDirection, style: header),
            cell(l10n.ggEnvelopeBestOfDay, style: header),
            cell(
              latest == null
                  ? '—'
                  : l10n.ggEnvelopeLatest(l10n.session(latest.runName)),
              style: header,
            ),
          ],
        ),
        for (final direction in GgDirection.values)
          TableRow(
            key: ValueKey('ggEnvelopeRow ${direction.name}'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(l10n.ggDirection(direction)),
              ),
              cell(
                switch (envelope.best[direction.index]) {
                  final best? => l10n.ggEnvelopeBestValue(
                    ggValueText(best.valueG),
                    l10n.session(best.runName),
                  ),
                  null => '—',
                },
                key: ValueKey('ggEnvelopeBest ${direction.name}'),
                style: numbers,
              ),
              cell(
                switch (latest?.valueG(direction)) {
                  final value? => ggValueText(value),
                  null => '—',
                },
                key: ValueKey('ggEnvelopeLatest ${direction.name}'),
                style: unused.contains(direction)
                    ? numbers?.copyWith(
                        color: FetColors.of(context).loss,
                        fontWeight: FontWeight.w700,
                      )
                    : numbers,
              ),
            ],
          ),
      ],
    );
  }

  // Where the G comes from: one line when every session reads the same
  // channels, else one per session.
  static List<String> _sources(
    AppLocalizations l10n,
    List<SessionGgEnvelope> sessions,
  ) {
    String line(String name, SessionGgEnvelope session) =>
        '${l10n.drivingGgSource(name, session.longitudinalChannel, session.lateralChannel, session.calculated ? l10n.drivingGgCalculated : l10n.drivingMeasured)}'
        '${session.unitsDeclared ? '' : ', ${l10n.channelUnitsNotDeclared}'}';
    (String, String, bool) of(SessionGgEnvelope session) => (
      session.longitudinalChannel,
      session.lateralChannel,
      session.unitsDeclared,
    );
    if (sessions.isEmpty) return const [];
    if (sessions.every((session) => of(session) == of(sessions.first))) {
      return [
        line(
          sessions.length == 1
              ? l10n.session(sessions.single.runName)
              : l10n.consistencyAllSessions,
          sessions.first,
        ),
      ];
    }
    return [
      for (final session in sessions)
        line(l10n.session(session.runName), session),
    ];
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.label,
    required this.color,
    this.thick = false,
    this.dashed = false,
  });

  final String label;
  final Color color;
  final bool thick;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 18,
        height: 10,
        child: CustomPaint(
          painter: _LegendLine(color: color, thick: thick, dashed: dashed),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _LegendLine extends CustomPainter {
  _LegendLine({required this.color, required this.thick, required this.dashed});

  final Color color;
  final bool thick;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thick ? 3.5 : 2;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 3, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LegendLine oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.thick != thick ||
      oldDelegate.dashed != dashed;
}

/// One session's envelope as drawn: a value per [GgDirection] (null where
/// there is none), its colour, and whether it is the latest session.
typedef GgEnvelopeTrace = ({List<double?> values, Color color, bool latest});

/// Draws each session's envelope through the eight directions, accelerating
/// up and left on the left as on the comparison's G-G, with the day's best
/// dashed. A direction without a value breaks the line: it is never
/// bridged.
class GgEnvelopePainter extends CustomPainter {
  GgEnvelopePainter({
    required this.sessions,
    required this.best,
    required this.bestColor,
    required this.gridColor,
    required this.labelStyle,
    required this.axisLabels,
  });

  final List<GgEnvelopeTrace> sessions;
  final List<double?> best;
  final Color bestColor;
  final Color gridColor;
  final TextStyle labelStyle;

  /// The words at the top, bottom, left and right of the diagram.
  final List<String> axisLabels;

  /// The outer ring in g (see [ggScale]).
  double get scaleG => ggScale(best);

  /// Where [value] g in [direction] is drawn on a diagram around [centre]
  /// whose outer ring, [radius] from it, is [scaleG]: accelerating up,
  /// turning left on the left, as on the comparison's G-G.
  @visibleForTesting
  static Offset project(
    Offset centre,
    double radius,
    double scaleG,
    GgDirection direction,
    double value,
  ) => Offset(
    centre.dx - math.sin(direction.angle) * value / scaleG * radius,
    centre.dy - math.cos(direction.angle) * value / scaleG * radius,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = math.min(size.width, size.height);
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = side / 2 - 16;
    if (radius <= 0) return;
    final scale = scaleG;
    Offset at(GgDirection direction, double value) =>
        project(centre, radius, scale, direction, value);
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
      painter.paint(
        canvas,
        Offset(
          anchor.dx - painter.width * (alignment.x + 1) / 2,
          anchor.dy - painter.height * (alignment.y + 1) / 2,
        ),
      );
    }

    label(axisLabels[0], Offset(centre.dx, 0), Alignment.topCenter);
    label(
      axisLabels[1],
      Offset(centre.dx, size.height),
      Alignment.bottomCenter,
    );
    label(axisLabels[2], Offset(0, centre.dy - 2), Alignment.bottomLeft);
    label(
      axisLabels[3],
      Offset(size.width, centre.dy - 2),
      Alignment.bottomRight,
    );
    label(
      '${scale.toStringAsFixed(1)}\u00a0g',
      Offset(centre.dx + radius * 0.72, centre.dy - radius * 0.72),
      Alignment.bottomLeft,
    );

    // Each pair of neighbouring directions that both have a value.
    Iterable<(Offset, Offset)> segments(List<double?> values) sync* {
      const directions = GgDirection.values;
      for (var i = 0; i < directions.length; ++i) {
        final next = (i + 1) % directions.length;
        final a = values.length > i ? values[i] : null;
        final b = values.length > next ? values[next] : null;
        if (a == null || b == null) continue;
        yield (at(directions[i], a), at(directions[next], b));
      }
    }

    void dot(List<double?> values, Paint paint) {
      for (final direction in GgDirection.values) {
        final value = values.length > direction.index
            ? values[direction.index]
            : null;
        if (value != null) {
          canvas.drawCircle(at(direction, value), paint.strokeWidth, paint);
        }
      }
    }

    // Earlier sessions first, the latest on top.
    for (final session in [
      ...sessions.where((session) => !session.latest),
      ...sessions.where((session) => session.latest),
    ]) {
      final paint = Paint()
        ..color = session.latest
            ? session.color
            : session.color.withValues(alpha: 0.75)
        ..strokeWidth = session.latest ? 3.5 : 1.5
        ..strokeCap = StrokeCap.round;
      for (final (from, to) in segments(session.values)) {
        canvas.drawLine(from, to, paint);
      }
      // A direction whose neighbours have no value still shows.
      dot(session.values, paint);
    }
    final dashed = Paint()
      ..color = bestColor
      ..strokeWidth = 2;
    for (final (from, to) in segments(best)) {
      final length = (to - from).distance;
      if (length <= 0) continue;
      final step = (to - from) / length;
      for (var d = 0.0; d < length; d += 8) {
        canvas.drawLine(
          from + step * d,
          from + step * math.min(d + 4, length),
          dashed,
        );
      }
    }
  }

  @override
  bool shouldRepaint(GgEnvelopePainter oldDelegate) =>
      !listEquals(oldDelegate.best, best) ||
      oldDelegate.sessions.length != sessions.length ||
      [
        for (var i = 0; i < sessions.length; ++i)
          !listEquals(oldDelegate.sessions[i].values, sessions[i].values) ||
              oldDelegate.sessions[i].color != sessions[i].color ||
              oldDelegate.sessions[i].latest != sessions[i].latest,
      ].any((changed) => changed) ||
      !listEquals(oldDelegate.axisLabels, axisLabels) ||
      oldDelegate.bestColor != bestColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelStyle != labelStyle;
}
