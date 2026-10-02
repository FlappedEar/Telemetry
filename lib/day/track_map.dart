import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
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

/// What is drawn under the trace.
enum MapBackground {
  streets('Streets'),
  satellite('Satellite'),
  none('Trace only');

  const MapBackground(this.label);

  final String label;
}

/// The MapTiler key, given at build time with
/// `--dart-define=MAPTILER_KEY=...`; empty when satellite is unavailable.
/// Never stored in the repository.
const String mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

/// A raster tile service. Swappable: another provider is another value.
final class TileSource {
  const TileSource({
    required this.urlTemplate,
    required this.attribution,
    this.maxNativeZoom = 19,
  });

  final String urlTemplate;
  final String attribution;
  final int maxNativeZoom;
}

/// OpenStreetMap's standard tiles, used within its tile usage policy: the app
/// identifies itself, shows the attribution and keeps viewed tiles cached.
const streetTiles = TileSource(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: '© OpenStreetMap contributors',
);

/// MapTiler satellite imagery for [key].
TileSource satelliteTiles(String key) => TileSource(
  urlTemplate:
      'https://api.maptiler.com/maps/satellite/256/{z}/{x}/{y}.jpg?key=$key',
  attribution: '© MapTiler © OpenStreetMap contributors',
  maxNativeZoom: 20,
);

/// The backgrounds this build offers.
List<MapBackground> get availableBackgrounds => [
  MapBackground.streets,
  if (mapTilerKey.isNotEmpty) MapBackground.satellite,
  MapBackground.none,
];

/// The background of every map, shared while the app runs. Tests draw the
/// trace only, without network.
final ValueNotifier<MapBackground> mapBackground = ValueNotifier(
  !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
      ? MapBackground.none
      : mapTilerKey.isNotEmpty
      ? MapBackground.satellite
      : MapBackground.streets,
);

/// Loads tiles; replaced in tests, which have no network.
@visibleForTesting
TileProvider Function()? debugTileProvider;

/// The tile source for [background], or null for the trace only.
TileSource? tileSourceFor(MapBackground background) => switch (background) {
  MapBackground.streets => streetTiles,
  MapBackground.satellite =>
    mapTilerKey.isEmpty ? streetTiles : satelliteTiles(mapTilerKey),
  MapBackground.none => null,
};

/// [point] of [path] back in degrees (the inverse of the path's projection).
LatLng pathLatLng(GeoCoordinate origin, double east, double north) {
  final point = unprojectCoordinate(east, north, origin);
  return LatLng(point.latitudeDegrees, point.longitudeDegrees);
}

/// The GPS trace of a lap coloured by speed, over street or satellite tiles
/// or on a plain background, with an optional reference lap in grey under it
/// and the start/finish line. North is up. Pinch or scroll to zoom; the
/// layers button switches the background.
class TrackMap extends StatelessWidget {
  const TrackMap({
    super.key,
    required this.path,
    this.reference,
    this.gate,
    this.semanticLabel = 'Track map',
    this.interactive = true,
    this.pointColor,
  });

  final LapPath path;
  final LapPath? reference;
  final (Offset, Offset)? gate;
  final String semanticLabel;

  /// The colour of the trace up to each fix, instead of its speed; null for
  /// a fix leaves it in the neutral colour.
  final Color? Function(PathPoint point)? pointColor;

  /// Whether the map pans, zooms and shows the layers button.
  final bool interactive;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: mapBackground,
    builder: (context, background, _) {
      final tiles = tileSourceFor(background);
      return Semantics(
        label: semanticLabel,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: tiles == null
                    ? _plainMap(context)
                    : _TiledMap(
                        key: ValueKey(tiles.urlTemplate),
                        tiles: tiles,
                        path: path,
                        reference: reference,
                        gate: gate,
                        interactive: interactive,
                        pointColor: pointColor,
                      ),
              ),
              if (interactive)
                Positioned(top: 8, right: 8, child: _LayersButton(background)),
            ],
          ),
        ),
      );
    },
  );

  Widget _plainMap(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final painter = CustomPaint(
      painter: _TrackPainter(
        path: path,
        reference: reference,
        gate: gate,
        referenceColor: scheme.outlineVariant,
        noSpeedColor: scheme.onSurface,
        gateColor: scheme.error,
        pointColor: pointColor,
      ),
      child: const SizedBox.expand(),
    );
    return interactive
        ? InteractiveViewer(
            maxScale: 12,
            child: RepaintBoundary(child: painter),
          )
        : RepaintBoundary(child: painter);
  }
}

class _LayersButton extends StatelessWidget {
  const _LayersButton(this.current);

  final MapBackground current;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
    shape: const CircleBorder(),
    child: PopupMenuButton<MapBackground>(
      tooltip: 'Map background',
      icon: const Icon(Icons.layers_outlined),
      initialValue: current,
      onSelected: (value) => mapBackground.value = value,
      itemBuilder: (context) => [
        for (final background in availableBackgrounds)
          CheckedPopupMenuItem(
            value: background,
            checked: background == current,
            child: Text(background.label),
          ),
      ],
    ),
  );
}

/// The trace on map tiles.
class _TiledMap extends StatelessWidget {
  const _TiledMap({
    super.key,
    required this.tiles,
    required this.path,
    required this.reference,
    required this.gate,
    required this.interactive,
    this.pointColor,
  });

  final TileSource tiles;
  final LapPath path;
  final LapPath? reference;
  final (Offset, Offset)? gate;
  final bool interactive;
  final Color? Function(PathPoint point)? pointColor;

  // Neighbouring fixes of one colour band share a polyline: a lap has
  // thousands of fixes but only a few dozen colour changes.
  static const _bands = 32;

  List<Polyline<Object>> _speedLines(Color noSpeedColor) {
    final range = speedRange(path);
    final (low, high) = range ?? (0.0, 0.0);
    final spread = high - low;
    Color colorOf(PathPoint point) {
      if (pointColor case final color?) return color(point) ?? noSpeedColor;
      final speed = point.speed;
      if (speed == null || !speed.isFinite) return noSpeedColor;
      final fraction = spread > 0 ? (speed - low) / spread : 0.5;
      return speedColor((fraction * _bands).roundToDouble() / _bands);
    }

    final lines = <Polyline<Object>>[];
    for (final segment in path.segments) {
      if (segment.length < 2) continue;
      var points = [_at(path, segment.first)];
      var color = colorOf(segment[1]);
      for (var i = 1; i < segment.length; ++i) {
        final next = colorOf(segment[i]);
        final point = _at(path, segment[i]);
        if (next != color) {
          lines.add(_line(points, color));
          points = [points.last];
          color = next;
        }
        points.add(point);
      }
      lines.add(_line(points, color));
    }
    return lines;
  }

  static Polyline<Object> _line(List<LatLng> points, Color color) => Polyline(
    points: points,
    color: color,
    strokeWidth: 4,
    strokeJoin: StrokeJoin.round,
  );

  /// One dark outline under the whole trace, so the colour bands join
  /// seamlessly and stay readable on any background.
  List<Polyline<Object>> _outline() => [
    for (final segment in path.segments)
      if (segment.length > 1)
        Polyline(
          points: [for (final point in segment) _at(path, point)],
          color: Colors.black54,
          strokeWidth: 7,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
  ];

  static LatLng _at(LapPath path, PathPoint point) =>
      pathLatLng(path.origin, point.eastMeters, point.northMeters);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = [
      for (final candidate in [path, ?reference])
        for (final segment in candidate.segments)
          for (final point in segment) _at(candidate, point),
    ];
    if (all.isEmpty) return const SizedBox.expand();
    final first = path.segments.firstOrNull;
    LatLng? start;
    double? heading;
    if (first != null && first.length > 1) {
      start = _at(path, first.first);
      var ahead = 1;
      while (ahead < first.length - 1 &&
          math.sqrt(
                math.pow(first[ahead].eastMeters - first.first.eastMeters, 2) +
                    math.pow(
                      first[ahead].northMeters - first.first.northMeters,
                      2,
                    ),
              ) <
              8) {
        ++ahead;
      }
      heading = math.atan2(
        first[ahead].eastMeters - first.first.eastMeters,
        first[ahead].northMeters - first.first.northMeters,
      );
    }
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: all,
          padding: const EdgeInsets.all(24),
          maxZoom: 18,
        ),
        maxZoom: 21,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: tiles.urlTemplate,
          userAgentPackageName: 'com.flappedear.telemetry',
          maxNativeZoom: tiles.maxNativeZoom,
          tileProvider: debugTileProvider?.call(),
        ),
        if (reference case final reference?)
          PolylineLayer(
            polylines: [
              for (final segment in reference.segments)
                Polyline(
                  points: [for (final point in segment) _at(reference, point)],
                  color: Colors.white.withValues(alpha: 0.75),
                  strokeWidth: 7,
                  borderStrokeWidth: 1,
                  borderColor: Colors.black38,
                ),
            ],
          ),
        PolylineLayer(polylines: [..._outline(), ..._speedLines(Colors.white)]),
        if (gate case (final a, final b))
          PolylineLayer(
            polylines: [
              Polyline(
                points: [
                  pathLatLng(path.origin, a.dx, a.dy),
                  pathLatLng(path.origin, b.dx, b.dy),
                ],
                color: scheme.error,
                strokeWidth: 4,
              ),
            ],
          ),
        if (start != null && heading != null)
          MarkerLayer(
            markers: [
              Marker(
                point: start,
                width: 28,
                height: 28,
                child: Transform.rotate(
                  angle: heading,
                  child: const Icon(
                    Icons.navigation,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 3)],
                  ),
                ),
              ),
            ],
          ),
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            color: scheme.surface.withValues(alpha: 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              tiles.attribution,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ],
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
    this.pointColor,
  }) : range = speedRange(path);

  final LapPath path;
  final LapPath? reference;
  final (Offset, Offset)? gate;
  final Color referenceColor;
  final Color noSpeedColor;
  final Color gateColor;
  final Color? Function(PathPoint point)? pointColor;
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
        linePaint.color = pointColor != null
            ? pointColor!(segment[i]) ?? noSpeedColor
            : speed == null || !speed.isFinite
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
      old.gateColor != gateColor ||
      old.pointColor != pointColor;
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
