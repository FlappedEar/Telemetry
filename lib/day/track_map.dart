import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// Where a day's map is centred: the middle of [session]'s start/finish
/// line, east-positive, or null when the recording has none.
GeoCoordinate? mapOrigin(TelemetrySession session) {
  for (final gate in session.timingGates) {
    if (gate.type != TimingGateType.start) continue;
    final sign = session.metadata['gpsLongitudeConvention'] == 'west-positive'
        ? -1.0
        : 1.0;
    final origin = GeoCoordinate(
      (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2,
      sign *
          (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) /
          2,
    );
    return isValidCoordinate(origin) ? origin : null;
  }
  return null;
}

/// The start/finish line of [session] in metres around [origin], or null.
(Offset, Offset)? mapGate(TelemetrySession session, GeoCoordinate origin) {
  for (final gate in session.timingGates) {
    if (gate.type != TimingGateType.start) continue;
    final sign = session.metadata['gpsLongitudeConvention'] == 'west-positive'
        ? -1.0
        : 1.0;
    Offset project(GeoCoordinate point) {
      final metric = projectCoordinate(
        GeoCoordinate(point.latitudeDegrees, sign * point.longitudeDegrees),
        origin,
      );
      return Offset(metric.eastMeters, metric.northMeters);
    }

    return (project(gate.endpointA), project(gate.endpointB));
  }
  return null;
}

/// Speed colours, slow to fast (a viridis-like ramp, readable in light and
/// dark themes and distinct from the A/B comparison colours).
const List<Color> speedRamp = [
  Color(0xff440154),
  Color(0xff3b528b),
  Color(0xff21918c),
  Color(0xff5ec962),
  Color(0xfffde725),
];

Color speedColor(double fraction) {
  final t = fraction.clamp(0.0, 1.0) * (speedRamp.length - 1);
  final index = t.floor().clamp(0, speedRamp.length - 2);
  return Color.lerp(speedRamp[index], speedRamp[index + 1], t - index)!;
}

/// The finite speed range of [path], or null without speed.
(double, double)? speedRange(LapPath path) {
  double? low, high;
  for (final segment in path.segments) {
    for (final point in segment) {
      final speed = point.speed;
      if (speed == null || !speed.isFinite) continue;
      low = low == null ? speed : math.min(low, speed);
      high = high == null ? speed : math.max(high, speed);
    }
  }
  return low == null ? null : (low, high!);
}

/// The GPS trace of a lap on a plain background (no map tiles), coloured by
/// speed, with an optional reference lap in grey under it and the
/// start/finish line. North is up. Pinch or scroll to zoom.
class TrackMap extends StatelessWidget {
  const TrackMap({
    super.key,
    required this.path,
    this.reference,
    this.gate,
    this.semanticLabel = 'Track map',
  });

  final LapPath path;
  final LapPath? reference;
  final (Offset, Offset)? gate;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      child: ClipRect(
        child: InteractiveViewer(
          maxScale: 12,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _TrackPainter(
                path: path,
                reference: reference,
                gate: gate,
                referenceColor: scheme.outlineVariant,
                noSpeedColor: scheme.onSurface,
                gateColor: scheme.error,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.path,
    required this.reference,
    required this.gate,
    required this.referenceColor,
    required this.noSpeedColor,
    required this.gateColor,
  }) : range = speedRange(path);

  final LapPath path;
  final LapPath? reference;
  final (Offset, Offset)? gate;
  final Color referenceColor;
  final Color noSpeedColor;
  final Color gateColor;
  final (double, double)? range;

  @override
  void paint(Canvas canvas, Size size) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void include(double x, double y) {
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }

    for (final candidate in [path, ?reference]) {
      for (final segment in candidate.segments) {
        for (final point in segment) {
          include(point.eastMeters, point.northMeters);
        }
      }
    }
    if (!minX.isFinite || size.isEmpty) return;
    const padding = 16.0;
    final spanX = math.max(maxX - minX, 1.0),
        spanY = math.max(maxY - minY, 1.0);
    final scale = math.min(
      (size.width - 2 * padding) / spanX,
      (size.height - 2 * padding) / spanY,
    );
    if (!scale.isFinite || scale <= 0) return;
    final dx = (size.width - spanX * scale) / 2,
        dy = (size.height - spanY * scale) / 2;
    Offset at(double east, double north) => Offset(
      dx + (east - minX) * scale,
      size.height - dy - (north - minY) * scale,
    );

    final referencePaint = Paint()
      ..color = referenceColor
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final segment in reference?.segments ?? const <List<PathPoint>>[]) {
      final line = Path();
      for (var i = 0; i < segment.length; ++i) {
        final point = at(segment[i].eastMeters, segment[i].northMeters);
        i == 0
            ? line.moveTo(point.dx, point.dy)
            : line.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(line, referencePaint);
    }

    final linePaint = Paint()
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final (low, high) = range ?? (0.0, 0.0);
    final spread = high - low;
    for (final segment in path.segments) {
      for (var i = 1; i < segment.length; ++i) {
        final speed = segment[i].speed;
        linePaint.color = speed == null || !speed.isFinite
            ? noSpeedColor
            : speedColor(spread > 0 ? (speed - low) / spread : 0.5);
        canvas.drawLine(
          at(segment[i - 1].eastMeters, segment[i - 1].northMeters),
          at(segment[i].eastMeters, segment[i].northMeters),
          linePaint,
        );
      }
    }

    if (gate case (final a, final b)) {
      canvas.drawLine(
        at(a.dx, a.dy),
        at(b.dx, b.dy),
        Paint()
          ..color = gateColor
          ..strokeWidth = 3,
      );
    }

    // Where the section starts, and which way it goes.
    final first = path.segments.firstOrNull;
    if (first != null && first.length > 1) {
      final start = at(first.first.eastMeters, first.first.northMeters);
      canvas.drawCircle(start, 6, Paint()..color = noSpeedColor);
      var ahead = 1;
      while (ahead < first.length - 1 &&
          (at(first[ahead].eastMeters, first[ahead].northMeters) - start)
                  .distance <
              24) {
        ++ahead;
      }
      final next = at(first[ahead].eastMeters, first[ahead].northMeters);
      final direction = next - start;
      if (direction.distance > 0) {
        final unit = direction / direction.distance;
        final tip = start + unit * 22;
        final normal = Offset(-unit.dy, unit.dx);
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(
              (tip - unit * 10 + normal * 6).dx,
              (tip - unit * 10 + normal * 6).dy,
            )
            ..lineTo(
              (tip - unit * 10 - normal * 6).dx,
              (tip - unit * 10 - normal * 6).dy,
            )
            ..close(),
          Paint()..color = noSpeedColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.path != path ||
      old.reference != reference ||
      old.gate != gate ||
      old.referenceColor != referenceColor ||
      old.noSpeedColor != noSpeedColor ||
      old.gateColor != gateColor;
}

/// The speed scale under a map: slow and fast ends with their values.
class SpeedLegend extends StatelessWidget {
  const SpeedLegend({super.key, required this.path});

  final LapPath path;

  @override
  Widget build(BuildContext context) {
    final range = speedRange(path);
    final theme = Theme.of(context);
    if (range == null) {
      return Text(
        'No speed recorded; the trace is drawn in one colour.',
        style: theme.textTheme.bodySmall,
      );
    }
    final unit = path.speedUnit.isEmpty ? '' : ' ${path.speedUnit}';
    return Row(
      children: [
        Text(
          '${range.$1.toStringAsFixed(0)}$unit',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: const LinearGradient(colors: speedRamp),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${range.$2.toStringAsFixed(0)}$unit',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
