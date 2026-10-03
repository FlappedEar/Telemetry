import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';
import '../units.dart';
import 'apple_map.dart';
import 'touch.dart';

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

/// Speed colours, slow to fast. Every stop keeps at least 5:1 contrast with
/// the app's charcoal panels, so the slow end stays visible on the dark
/// theme, and the ramp avoids the amber and blue of the two compared laps.
const List<Color> speedRamp = [
  Color(0xff8a7dff),
  Color(0xff4fb3ff),
  Color(0xff2fd6a8),
  Color(0xffb5e550),
  Color(0xffffe45c),
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

/// What is drawn under the trace. Every map shows real tiles: [none] is
/// not offered to users; it is the network-free plain drawing used under
/// tests.
enum MapBackground {
  streets('Streets'),
  satellite('Satellite'),
  apple('Apple Maps'),
  none('Plain');

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

/// The backgrounds this build offers: always a real map under the trace.
List<MapBackground> get availableBackgrounds => [
  MapBackground.streets,
  if (mapTilerKey.isNotEmpty) MapBackground.satellite,
  if (appleMapsAvailable) MapBackground.apple,
];

/// The background of every map, shared while the app runs. Tests draw the
/// trace on a plain background, without network, unless they provide
/// [debugTileProvider].
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

/// The tile source for [background], or null for the plain test drawing.
TileSource? tileSourceFor(MapBackground background) => switch (background) {
  MapBackground.streets => streetTiles,
  MapBackground.satellite =>
    mapTilerKey.isEmpty ? streetTiles : satelliteTiles(mapTilerKey),
  MapBackground.apple => appleMapsAvailable ? appleMapSource : streetTiles,
  MapBackground.none => null,
};

/// The tile layer of [tiles], identified to the tile server as the app
/// (the native map for [appleMapSource]).
Widget mapTileLayer(TileSource tiles) => isAppleMapSource(tiles)
    ? const AppleMapLayer()
    : TileLayer(
        urlTemplate: tiles.urlTemplate,
        userAgentPackageName: 'com.flappedear.telemetry',
        maxNativeZoom: tiles.maxNativeZoom,
        tileProvider: debugTileProvider?.call(),
      );

/// The attribution [tiles] require, in a map's bottom-right corner.
class MapAttribution extends StatelessWidget {
  const MapAttribution(this.tiles, {super.key});

  final TileSource tiles;

  @override
  Widget build(BuildContext context) =>
      isAppleMapSource(tiles) ? const AppleMapLegal() : _chip(context);

  Widget _chip(BuildContext context) => Align(
    alignment: Alignment.bottomRight,
    child: Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        tiles.attribution,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ),
  );
}

/// [point] of [path] back in degrees (the inverse of the path's projection).
LatLng pathLatLng(GeoCoordinate origin, double east, double north) {
  final point = unprojectCoordinate(east, north, origin);
  return LatLng(point.latitudeDegrees, point.longitudeDegrees);
}

/// A point drawn over the trace, such as a segment boundary: [east] and
/// [north] metres around the path's origin.
@immutable
final class MapMark {
  const MapMark(this.east, this.north, this.color, {this.radius = 6});

  final double east;
  final double north;
  final Color color;
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is MapMark &&
      other.east == east &&
      other.north == north &&
      other.color == color &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(east, north, color, radius);
}

/// The GPS trace of a lap coloured by speed, over street or satellite tiles
/// (a plain background only under tests), with an optional reference lap in
/// grey under it and the start/finish line. North is up. On a phone or tablet
/// one finger scrolls the page and two fingers zoom and move the map (a
/// double tap also zooms the tiles); on desktop the mouse drags and the
/// wheel zooms. The layers button switches the background. See [TouchMap].
class TrackMap extends StatelessWidget {
  const TrackMap({
    super.key,
    required this.path,
    this.reference,
    this.gate,
    this.semanticLabel = 'Track map',
    this.interactive = true,
    this.pointColor,
    this.marks = const [],
    this.movingMarks,
    this.onTapMeters,
  });

  final LapPath path;
  final LapPath? reference;
  final (Offset, Offset)? gate;
  final String semanticLabel;

  /// Called with the place tapped or clicked, in metres east and north of
  /// the path's origin; the map takes no taps when null.
  final void Function(double east, double north)? onTapMeters;

  /// Points that move, such as a chart cursor's position: only this layer
  /// repaints when they change, never the trace.
  final ValueListenable<List<MapMark>>? movingMarks;

  /// Points drawn over the trace, last on top.
  final List<MapMark> marks;

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
                        marks: marks,
                        movingMarks: movingMarks,
                        onTapMeters: onTapMeters,
                      ),
              ),
              if (interactive)
                Positioned(
                  top: 8,
                  right: 8,
                  child: MapLayersButton(background),
                ),
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
        // Neutral, so the line stays apart from the red loss scale.
        gateColor: scheme.onSurface,
        pointColor: pointColor,
        marks: marks,
      ),
      child: const SizedBox.expand(),
    );
    final moving = movingMarks;
    final onTap = onTapMeters;
    // Inside the pinch zoom, so a tap lands where the trace is drawn.
    final drawn = onTap == null
        ? RepaintBoundary(child: painter)
        : LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final at = _mapUnfit(path, reference, constraints.biggest);
                if (at == null) return;
                final (east, north) = at(details.localPosition);
                onTap(east, north);
              },
              child: RepaintBoundary(child: painter),
            ),
          );
    final layers = moving == null
        ? drawn
        : Stack(
            children: [
              Positioned.fill(child: drawn),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MovingMarksPainter(
                      path: path,
                      reference: reference,
                      marks: moving,
                    ),
                  ),
                ),
              ),
            ],
          );
    // Two fingers zoom and move the map on a phone; one finger is left to
    // the page's scroll.
    return interactive ? PinchZoom(child: layers) : layers;
  }
}

/// Switches the shared [mapBackground] of every map.
class MapLayersButton extends StatelessWidget {
  const MapLayersButton(this.current, {super.key});

  final MapBackground current;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
    shape: const CircleBorder(),
    child: PopupMenuButton<MapBackground>(
      tooltip: context.l10n.mapBackgroundMenu,
      icon: const Icon(Icons.layers_outlined),
      initialValue: current,
      onSelected: (value) => mapBackground.value = value,
      itemBuilder: (context) => [
        for (final background in availableBackgrounds)
          CheckedPopupMenuItem(
            value: background,
            checked: background == current,
            child: Text(switch (background) {
              MapBackground.streets => context.l10n.mapBackgroundStreets,
              MapBackground.satellite => context.l10n.mapBackgroundSatellite,
              MapBackground.apple => context.l10n.mapBackgroundApple,
              MapBackground.none => context.l10n.mapBackgroundPlain,
            }),
          ),
      ],
    ),
  );
}

/// A tiled map, built by [builder] with its controller and the gestures it
/// may take itself. On a phone or tablet one finger is left to the page's
/// scroll, so the map never traps it: two fingers zoom and move the map,
/// keeping the place under them, and a double tap zooms in. On desktop the
/// mouse drags and the wheel zooms. Not [interactive], it takes no gesture.
class TouchMap extends StatefulWidget {
  const TouchMap({super.key, this.interactive = true, required this.builder});

  final bool interactive;
  final Widget Function(
    BuildContext context,
    MapController controller,
    InteractionOptions interaction,
  )
  builder;

  @override
  State<TouchMap> createState() => _TouchMapState();
}

class _TouchMapState extends State<TouchMap> {
  final _map = MapController();
  MapCamera? _startCamera;
  LatLng? _startFocus;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _pinchStart(Offset focal) {
    final camera = _startCamera = _map.camera;
    _startFocus = camera.screenOffsetToLatLng(focal);
  }

  // The place first under the fingers stays under them while they zoom
  // and move.
  void _pinchUpdate(Offset focal, double scale) {
    final camera = _startCamera, focus = _startFocus;
    if (camera == null || focus == null || scale <= 0) return;
    final zoom = camera.clampZoom(camera.zoom + math.log(scale) / math.ln2);
    final point = camera.projectAtZoom(focus, zoom);
    final centre = camera.unprojectAtZoom(
      point - (focal - camera.size.center(Offset.zero)),
      zoom,
    );
    _map.move(centre, zoom);
  }

  @override
  Widget build(BuildContext context) {
    final touch = widget.interactive && isTouchPlatform(context);
    final map = widget.builder(
      context,
      _map,
      InteractionOptions(
        // On a phone the map's own drag would trap the page's scroll; two
        // fingers are handled around the map.
        flags: !widget.interactive
            ? InteractiveFlag.none
            : touch
            ? InteractiveFlag.doubleTapZoom
            : InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
    );
    if (!touch) return map;
    return TwoFingerGestures(
      onStart: _pinchStart,
      onUpdate: _pinchUpdate,
      child: map,
    );
  }
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
    this.marks = const [],
    this.movingMarks,
    this.onTapMeters,
  });

  final void Function(double east, double north)? onTapMeters;
  final List<MapMark> marks;
  final ValueListenable<List<MapMark>>? movingMarks;
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
    return TouchMap(
      interactive: interactive,
      builder: (context, controller, interaction) => FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCameraFit: CameraFit.coordinates(
            coordinates: all,
            padding: const EdgeInsets.all(24),
            maxZoom: 18,
          ),
          maxZoom: mapMaxZoom(tiles),
          minZoom: mapMinZoom(tiles),
          cameraConstraint: mapCameraConstraint(tiles),
          interactionOptions: interaction,
          onTap: switch (onTapMeters) {
            final onTap? => (_, point) {
              final at = projectCoordinate(
                GeoCoordinate(point.latitude, point.longitude),
                path.origin,
              );
              onTap(at.eastMeters, at.northMeters);
            },
            null => null,
          },
        ),
        children: [
          mapTileLayer(tiles),
          if (reference case final reference?)
            PolylineLayer(
              polylines: [
                for (final segment in reference.segments)
                  Polyline(
                    points: [
                      for (final point in segment) _at(reference, point),
                    ],
                    color: Colors.white.withValues(alpha: 0.75),
                    strokeWidth: 7,
                    borderStrokeWidth: 1,
                    borderColor: Colors.black38,
                  ),
              ],
            ),
          PolylineLayer(
            polylines: [..._outline(), ..._speedLines(Colors.white)],
          ),
          if (gate case (final a, final b))
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [
                    pathLatLng(path.origin, a.dx, a.dy),
                    pathLatLng(path.origin, b.dx, b.dy),
                  ],
                  color: Colors.white,
                  strokeWidth: 4,
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.black87,
                ),
              ],
            ),
          if (marks.isNotEmpty)
            CircleLayer(
              circles: [
                for (final mark in marks)
                  CircleMarker(
                    point: pathLatLng(path.origin, mark.east, mark.north),
                    radius: mark.radius,
                    color: mark.color,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2,
                  ),
              ],
            ),
          if (movingMarks case final moving?)
            ValueListenableBuilder(
              valueListenable: moving,
              builder: (context, marks, _) => CircleLayer(
                circles: [
                  for (final mark in marks)
                    CircleMarker(
                      point: pathLatLng(path.origin, mark.east, mark.north),
                      radius: mark.radius,
                      color: mark.color,
                      borderColor: Colors.black87,
                      borderStrokeWidth: 2,
                    ),
                ],
              ),
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
          MapAttribution(tiles),
        ],
      ),
    );
  }
}

// The bounding box of a path's fixes, computed once per path.
final Expando<Rect> _bounds = Expando('track map bounds');

Rect? _pathBounds(LapPath path) {
  final cached = _bounds[path];
  if (cached != null) return cached;
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final segment in path.segments) {
    for (final point in segment) {
      minX = math.min(minX, point.eastMeters);
      maxX = math.max(maxX, point.eastMeters);
      minY = math.min(minY, point.northMeters);
      maxY = math.max(maxY, point.northMeters);
    }
  }
  if (!minX.isFinite) return null;
  return _bounds[path] = Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Where a point [east]/[north] metres around the origin lands on a plain
/// map of [size] showing [path] and [reference]; null when there is nothing
/// to fit.
Offset Function(double east, double north)? _mapFit(
  LapPath path,
  LapPath? reference,
  Size size,
) {
  final own = _pathBounds(path);
  final other = reference == null ? null : _pathBounds(reference);
  final box = own == null
      ? other
      : other == null
      ? own
      : own.expandToInclude(other);
  if (box == null || size.isEmpty) return null;
  const padding = 16.0;
  final spanX = math.max(box.width, 1.0), spanY = math.max(box.height, 1.0);
  final scale = math.min(
    (size.width - 2 * padding) / spanX,
    (size.height - 2 * padding) / spanY,
  );
  if (!scale.isFinite || scale <= 0) return null;
  final dx = (size.width - spanX * scale) / 2,
      dy = (size.height - spanY * scale) / 2;
  return (east, north) => Offset(
    dx + (east - box.left) * scale,
    size.height - dy - (north - box.top) * scale,
  );
}

/// The inverse of [_mapFit]: metres east and north of the origin at a
/// point of a plain map of [size].
(double, double) Function(Offset point)? _mapUnfit(
  LapPath path,
  LapPath? reference,
  Size size,
) {
  final fit = _mapFit(path, reference, size);
  if (fit == null) return null;
  final origin = fit(0, 0), unit = fit(1, 1);
  final scale = unit.dx - origin.dx;
  if (!(scale > 0)) return null;
  return (point) =>
      ((point.dx - origin.dx) / scale, (origin.dy - point.dy) / scale);
}

class _MovingMarksPainter extends CustomPainter {
  _MovingMarksPainter({
    required this.path,
    required this.reference,
    required this.marks,
  }) : super(repaint: marks);

  final LapPath path;
  final LapPath? reference;
  final ValueListenable<List<MapMark>> marks;

  @override
  void paint(Canvas canvas, Size size) {
    if (marks.value.isEmpty) return;
    final at = _mapFit(path, reference, size);
    if (at == null) return;
    for (final mark in marks.value) {
      final centre = at(mark.east, mark.north);
      canvas
        ..drawCircle(centre, mark.radius + 2, Paint()..color = Colors.black87)
        ..drawCircle(centre, mark.radius, Paint()..color = mark.color);
    }
  }

  @override
  bool shouldRepaint(_MovingMarksPainter old) =>
      old.path != path || old.reference != reference || old.marks != marks;
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
    this.marks = const [],
  }) : range = speedRange(path);

  final List<MapMark> marks;

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
    final at = _mapFit(path, reference, size);
    if (at == null) return;

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

    for (final mark in marks) {
      final centre = at(mark.east, mark.north);
      canvas
        ..drawCircle(centre, mark.radius + 2, Paint()..color = Colors.white)
        ..drawCircle(centre, mark.radius, Paint()..color = mark.color);
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
      old.pointColor != pointColor ||
      !listEquals(old.marks, marks);
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
        context.l10n.speedLegendNoSpeed,
        style: theme.textTheme.bodySmall,
      );
    }
    final label = speedUnitOf(context, path.speedUnit);
    final unit = label.isEmpty ? '' : ' $label';
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
