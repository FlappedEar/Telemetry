import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'track_map.dart';

// Apple Maps (MapKit) under the trace, on iPhone, iPad and Mac only.
//
// The map is a native MKMapView placed as the bottom layer of the same
// [FlutterMap] that draws the trace over street and satellite tiles, so
// every line, dot and arrow is drawn once, by the same Dart layers, in all
// three styles. Flutter stays in charge of the camera: its gestures move
// the map exactly as over tiles (see [TouchMap]), the MKMapView takes no
// gesture of its own, and after each camera change it is told which part of
// the world to show as a [MercatorRegion]. flutter_map's EPSG:3857 camera
// and MapKit's map points are the same Web Mercator plane, so the native
// map and the Dart overlays share one projection.

/// Whether this platform offers Apple Maps: iOS, iPadOS and macOS.
bool get appleMapsAvailable =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };

/// The Apple Maps style, given to the map like a tile source. It loads no
/// tiles: [mapTileLayer] draws an [AppleMapLayer] for it. MapKit needs no
/// key and shows its own legal notice.
const appleMapSource = TileSource(
  urlTemplate: 'mapkit:standard',
  attribution: 'Apple Maps',
);

/// Whether [tiles] is [appleMapSource].
bool isAppleMapSource(TileSource tiles) => identical(tiles, appleMapSource);

/// The native view type, registered by the iOS and macOS runners
/// (AppleMapView.swift in each).
const appleMapViewType = 'com.flappedear.telemetry/apple_map';

/// The largest latitude Web Mercator shows, as in flutter_map's EPSG:3857.
const double _maxLatitude = 85.0511287798066;

/// [point] on the Web Mercator world square, whose side is 1: x grows east
/// from 180° W, y grows south from the top edge. MapKit's MKMapPoint is this
/// times the width of MKMapRect.world.
Offset mercatorOf(LatLng point) {
  final latitude =
      point.latitude.clamp(-_maxLatitude, _maxLatitude) * math.pi / 180;
  final sine = math.sin(latitude);
  return Offset(
    (point.longitude + 180) / 360,
    0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi),
  );
}

/// The point at [mercator] on the world square, back in degrees.
LatLng latLngOfMercator(Offset mercator) => LatLng(
  math.atan(_sinh(math.pi * (1 - 2 * mercator.dy))) * 180 / math.pi,
  mercator.dx * 360 - 180,
);

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

/// The part of the Web Mercator world square (see [mercatorOf]) a map
/// shows, north up: its top-left corner and its size. Both the native map's
/// visible rectangle and the overlays' positions come from it.
@immutable
final class MercatorRegion {
  const MercatorRegion(this.left, this.top, this.width, this.height);

  /// What a camera at [center] and [zoom] shows on a map of [size] logical
  /// pixels, as flutter_map's EPSG:3857 camera does: the world is
  /// 256 × 2^[zoom] pixels wide.
  factory MercatorRegion.ofCamera({
    required LatLng center,
    required double zoom,
    required Size size,
  }) {
    final world = 256 * math.pow(2, zoom).toDouble();
    final middle = mercatorOf(center);
    return MercatorRegion(
      middle.dx - size.width / 2 / world,
      middle.dy - size.height / 2 / world,
      size.width / world,
      size.height / world,
    );
  }

  final double left;
  final double top;
  final double width;
  final double height;

  /// Where [point] lands on a map of [size] showing this region.
  Offset toScreen(LatLng point, Size size) {
    final at = mercatorOf(point);
    return Offset(
      (at.dx - left) / width * size.width,
      (at.dy - top) / height * size.height,
    );
  }

  /// The place at [offset] on a map of [size] showing this region.
  LatLng fromScreen(Offset offset, Size size) => latLngOfMercator(
    Offset(
      left + offset.dx / size.width * width,
      top + offset.dy / size.height * height,
    ),
  );

  /// Whether every side is a finite, usable number.
  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width > 0 &&
      height > 0;

  /// The region as sent to the native map: left, top, width, height.
  List<double> toList() => [left, top, width, height];

  @override
  bool operator ==(Object other) =>
      other is MercatorRegion &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'MercatorRegion($left, $top, $width, $height)';
}

/// Builds what is drawn in place of the native map; set by tests, which
/// have no platform views.
@visibleForTesting
Widget Function(BuildContext context, MercatorRegion region)?
debugAppleMapBuilder;

/// The Apple map as the bottom layer of a [FlutterMap]: it shows what the
/// map's camera shows, and the layers after it are drawn over it.
class AppleMapLayer extends StatelessWidget {
  const AppleMapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final region = MercatorRegion.ofCamera(
      center: camera.center,
      zoom: camera.zoom,
      size: camera.nonRotatedSize,
    );
    final builder = debugAppleMapBuilder;
    return SizedBox.expand(
      child: builder != null
          ? builder(context, region)
          : IgnorePointer(child: AppleMapView(region: region)),
    );
  }
}

/// The native MapKit view showing [region]. It takes no gesture: the map
/// around it moves the camera.
class AppleMapView extends StatefulWidget {
  const AppleMapView({super.key, required this.region});

  final MercatorRegion region;

  @override
  State<AppleMapView> createState() => _AppleMapViewState();
}

class _AppleMapViewState extends State<AppleMapView> {
  MethodChannel? _channel;
  MercatorRegion? _sent;

  @override
  void didUpdateWidget(AppleMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _send();
  }

  void _created(int id) {
    _channel = MethodChannel('$appleMapViewType/$id');
    _sent = null;
    _send();
  }

  void _send() {
    final channel = _channel, region = widget.region;
    if (channel == null || region == _sent || !region.isValid) return;
    _sent = region;
    _push(channel, region);
  }

  static Future<void> _push(
    MethodChannel channel,
    MercatorRegion region,
  ) async {
    try {
      await channel.invokeMethod<void>('setRegion', region.toList());
    } on PlatformException {
      // The view went away while the camera moved; nothing to show it on.
    } on MissingPluginException {
      // Likewise: the view's channel is already gone.
    }
  }

  @override
  Widget build(BuildContext context) {
    final region = widget.region;
    final params = region.isValid ? region.toList() : null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => UiKitView(
        viewType: appleMapViewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      TargetPlatform.macOS => AppKitView(
        viewType: appleMapViewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      _ => const SizedBox.expand(),
    };
  }
}
