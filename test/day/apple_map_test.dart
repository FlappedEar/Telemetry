import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:telemetry/day/apple_map.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/l10n/app_localizations.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'blank_tiles.dart';

void main() {
  group('the shared projection', () {
    test('puts the world on a unit square, as MapKit map points do', () {
      expect(mercatorOf(const LatLng(0, 0)), const Offset(0.5, 0.5));
      expect(mercatorOf(const LatLng(0, -180)).dx, 0);
      expect(mercatorOf(const LatLng(0, 180)).dx, 1);
      expect(
        mercatorOf(const LatLng(85.0511287798066, 0)).dy,
        closeTo(0, 1e-9),
      );
      expect(mercatorOf(const LatLng(-89, 0)).dy, closeTo(1, 1e-9));
      // North is up: further north is higher on the square.
      expect(
        mercatorOf(const LatLng(52.1, 21)).dy,
        lessThan(mercatorOf(const LatLng(52, 21)).dy),
      );
    });

    test('maps a place to the screen and back', () {
      const size = Size(390, 260);
      final region = MercatorRegion.ofCamera(
        center: const LatLng(52.0, 21.0),
        zoom: 16.4,
        size: size,
      );
      expect(region.isValid, isTrue);
      // The camera's centre is the middle of the map.
      final middle = region.toScreen(const LatLng(52.0, 21.0), size);
      expect(middle.dx, closeTo(size.width / 2, 1e-6));
      expect(middle.dy, closeTo(size.height / 2, 1e-6));
      for (final offset in const [
        Offset.zero,
        Offset(390, 260),
        Offset(12.5, 200.25),
        Offset(-40, 300),
      ]) {
        final place = region.fromScreen(offset, size);
        final back = region.toScreen(place, size);
        expect(back.dx, closeTo(offset.dx, 1e-6));
        expect(back.dy, closeTo(offset.dy, 1e-6));
      }
      const place = LatLng(52.00123, 20.99876);
      final again = region.fromScreen(region.toScreen(place, size), size);
      expect(again.latitude, closeTo(place.latitude, 1e-9));
      expect(again.longitude, closeTo(place.longitude, 1e-9));
    });

    test('agrees with the flutter_map camera the overlays are drawn with', () {
      final random = math.Random(48);
      for (final (center, zoom, size) in const [
        (LatLng(52.0, 21.0), 16.0, Size(412, 300)),
        (LatLng(52.0, 21.0), 18.73, Size(1200, 520)),
        (LatLng(-33.86, 151.21), 14.2, Size(320, 320)),
        (LatLng(64.1, -21.9), 20.9, Size(800, 600)),
        (LatLng(0.0, 0.0), 3.5, Size(500, 400)),
      ]) {
        final camera = MapCamera(
          crs: const Epsg3857(),
          center: center,
          zoom: zoom,
          rotation: 0,
          nonRotatedSize: size,
        );
        final region = MercatorRegion.ofCamera(
          center: camera.center,
          zoom: camera.zoom,
          size: camera.nonRotatedSize,
        );
        for (var i = 0; i < 50; ++i) {
          final screen = Offset(
            random.nextDouble() * size.width,
            random.nextDouble() * size.height,
          );
          final place = camera.screenOffsetToLatLng(screen);
          final ours = region.toScreen(place, size);
          final theirs = camera.latLngToScreenOffset(place);
          expect((ours - theirs).distance, lessThan(1), reason: '$place');
          expect((ours - screen).distance, lessThan(1), reason: '$place');
        }
      }
    });
  });

  test('sends MapKit a region within one world', () {
    // Across the antimeridian, east or west: the same place, left in [0, 1).
    expect(const MercatorRegion(-0.25, 0.3, 0.1, 0.05).toList(), [
      0.75,
      0.3,
      0.1,
      0.05,
    ]);
    final east = const MercatorRegion(1.3, 0.3, 0.1, 0.05).toList();
    expect(east[0], closeTo(0.3, 1e-12));
    expect(const MercatorRegion(-1e-18, 0.3, 0.1, 0.05).toList()[0], 0);
    for (final left in [-3.7, -1.0, -0.5, 0.0, 0.999, 1.0, 2.25]) {
      final sent = MercatorRegion(left, 0.3, 0.1, 0.05).toList()[0];
      expect(sent, greaterThanOrEqualTo(0));
      expect(sent, lessThan(1));
      // The same place on the repeating world.
      final turns = left - sent;
      expect(turns, closeTo(turns.roundToDouble(), 1e-12));
    }
    // Never more than the world.
    expect(const MercatorRegion(0.2, 0.1, 1.5, 1.2).toList(), [
      0.2,
      0.1,
      1.0,
      1.0,
    ]);
    // A region inside the world is sent as it is.
    const inside = MercatorRegion(0.55, 0.33, 0.0001, 0.00007);
    expect(inside.toList(), [0.55, 0.33, 0.0001, 0.00007]);
  });

  group('the style choice', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('offers Apple Maps on iOS and macOS only', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        final apple =
            platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
        expect(appleMapsAvailable, apple, reason: '$platform');
        expect(
          availableBackgrounds.contains(MapBackground.apple),
          apple,
          reason: '$platform',
        );
        // A choice made where it was offered falls back to streets elsewhere.
        expect(
          tileSourceFor(MapBackground.apple),
          same(apple ? appleMapSource : streetTiles),
          reason: '$platform',
        );
      }
    });

    for (final platform in TargetPlatform.values) {
      testWidgets('the layers button on ${platform.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(width: 400, height: 300, child: _map()),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Map background'));
        await tester.pumpAndSettle();
        expect(find.text('Streets'), findsOneWidget);
        final apple =
            platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
        expect(find.text('Apple Maps'), apple ? findsOneWidget : findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('over the Apple map', () {
    final regions = <MercatorRegion>[];
    setUp(() {
      regions.clear();
      mapBackground.value = MapBackground.apple;
      debugAppleMapBuilder = (context, region) {
        regions.add(region);
        return const ColoredBox(
          key: ValueKey('stubAppleMap'),
          color: Color(0xffd6e5c4),
        );
      };
    });
    tearDown(() {
      mapBackground.value = MapBackground.none;
      debugAppleMapBuilder = null;
      debugDefaultTargetPlatformOverride = null;
    });

    Future<ValueNotifier<List<MapMark>>> show(
      WidgetTester tester,
      TargetPlatform platform,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final cursor = ValueNotifier([const MapMark(40, 0, Colors.red)]);
      addTearDown(cursor.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: _map(
                  reference: _path(width: 220),
                  marks: const [MapMark(100, 50, Colors.blue)],
                  movingMarks: cursor,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return cursor;
    }

    /// Where each element is in paint order: later is drawn on top.
    int order(WidgetTester tester, Finder finder) {
      final target = tester.element(finder);
      return tester.allElements.toList().indexOf(target);
    }

    for (final platform in const [TargetPlatform.iOS, TargetPlatform.macOS]) {
      testWidgets('every overlay is drawn above the map on ${platform.name}', (
        tester,
      ) async {
        final cursor = await show(tester, platform);
        final map = find.byKey(const ValueKey('stubAppleMap'));
        expect(map, findsOneWidget);
        expect(find.byType(TileLayer), findsNothing);
        // MapKit attributes itself at the bottom; the app's Legal link is
        // top left, clear of it.
        expect(find.text('Apple Maps'), findsNothing);
        expect(find.byKey(const ValueKey('appleMapLegal')), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('appleMapLegal'))),
          tester.getTopLeft(map) + const Offset(8, 8),
        );
        expect(
          find.descendant(of: find.byType(FlutterMap), matching: map),
          findsOneWidget,
        );

        // The speed-coloured trace over the reference lap, the start/finish
        // line, the segment boundary, the cursor and the start arrow: the
        // same layers as over tiles, all after (above) the map.
        final lines = tester
            .widgetList<PolylineLayer>(find.byType(PolylineLayer))
            .expand((layer) => layer.polylines)
            .toList();
        expect(lines.map((line) => line.color), contains(Colors.black54));
        expect(
          lines.map((line) => line.color),
          contains(isIn([for (var i = 0; i <= 32; ++i) speedColor(i / 32)])),
        );
        final circles = tester
            .widgetList<CircleLayer>(find.byType(CircleLayer))
            .expand((layer) => layer.circles)
            .map((circle) => circle.color);
        expect(circles, containsAll([Colors.blue, Colors.red]));
        expect(find.byIcon(Icons.navigation), findsOneWidget);
        final below = order(tester, map);
        for (final layer in [
          find.byType(PolylineLayer).first,
          find.byType(CircleLayer).first,
          find.byType(CircleLayer).last,
          find.byType(MarkerLayer),
        ]) {
          expect(order(tester, layer), greaterThan(below));
        }

        // The native map is shown the camera's region: a place lands on the
        // same pixel of the map and of the overlays.
        MapCamera camera() => MapCamera.of(tester.element(map));
        void sameProjection() {
          final region = regions.last;
          final size = camera().nonRotatedSize;
          expect(size, const Size(400, 300));
          for (final place in [
            pathLatLng(const GeoCoordinate(52, 21), 0, 0),
            pathLatLng(const GeoCoordinate(52, 21), 200, 100),
            pathLatLng(const GeoCoordinate(52, 21), -30, 140),
          ]) {
            final offset = region.toScreen(place, size);
            final drawn = camera().latLngToScreenOffset(place);
            expect((offset - drawn).distance, lessThan(1));
          }
        }

        sameProjection();

        // The cursor moves without touching the map.
        final shown = regions.length;
        cursor.value = [const MapMark(80, 10, Colors.red)];
        await tester.pump();
        expect(regions.length, shown);

        // Flutter's gestures move the camera, and the map follows: two
        // fingers on a phone or tablet, the wheel on a Mac.
        final before = camera().zoom;
        final centre = tester.getCenter(map);
        if (platform == TargetPlatform.iOS) {
          final first = await tester.startGesture(
            centre - const Offset(20, 0),
            pointer: 7,
          );
          final second = await tester.startGesture(
            centre + const Offset(20, 0),
            pointer: 8,
          );
          for (var step = 1; step <= 5; ++step) {
            await first.moveTo(centre - Offset(20.0 + step * 12, 0));
            await second.moveTo(centre + Offset(20.0 + step * 12, 0));
            await tester.pump();
          }
          await first.up();
          await second.up();
        } else {
          final mouse = TestPointer(1, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(mouse.hover(centre));
          await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
        }
        await tester.pumpAndSettle();
        expect(camera().zoom, greaterThan(before));
        expect(regions.length, greaterThan(shown));
        sameProjection();
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('the camera stays within what MapKit can show', (tester) async {
      await show(tester, TargetPlatform.macOS);
      final map = find.byKey(const ValueKey('stubAppleMap'));
      MapCamera camera() => MapCamera.of(tester.element(map));
      expect(camera().maxZoom, appleMapMaxZoom);
      expect(camera().minZoom, appleMapMinZoom);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final centre = tester.getCenter(map);
      await tester.sendEventToBinding(mouse.hover(centre));
      for (var i = 0; i < 40; ++i) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, -400)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(camera().zoom, lessThanOrEqualTo(19));
      expect(camera().zoom, greaterThan(18.5));
      expect(regions.last.width, closeTo(400 / (256 * math.pow(2, 19)), 1e-12));
      for (var i = 0; i < 80; ++i) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 400)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(camera().zoom, greaterThanOrEqualTo(3));
      // The whole map is inside the world, top to bottom.
      final region = regions.last;
      expect(region.top, greaterThanOrEqualTo(-1e-9));
      expect(region.top + region.height, lessThanOrEqualTo(1 + 1e-9));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the street and satellite styles keep their zoom', (
      tester,
    ) async {
      debugTileProvider = BlankTiles.new;
      addTearDown(() => debugTileProvider = null);
      mapBackground.value = MapBackground.streets;
      await show(tester, TargetPlatform.macOS);
      final camera = MapCamera.of(tester.element(find.byType(TileLayer)));
      expect(camera.maxZoom, 21);
      expect(camera.minZoom, isNull);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Legal opens Apple\'s notice', (tester) async {
      final opened = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(appleMapViewType),
        (call) async {
          opened.add((call.method, call.arguments));
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(appleMapViewType),
          null,
        ),
      );
      await show(tester, TargetPlatform.iOS);
      await tester.tap(find.byKey(const ValueKey('appleMapLegal')));
      await tester.pump();
      expect(opened, [('openLegal', appleMapLegalUrl)]);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('elsewhere the choice falls back to street tiles', (
      tester,
    ) async {
      debugTileProvider = BlankTiles.new;
      addTearDown(() => debugTileProvider = null);
      await show(tester, TargetPlatform.android);
      expect(find.byKey(const ValueKey('stubAppleMap')), findsNothing);
      expect(find.byType(AppleMapLayer), findsNothing);
      expect(find.byType(TileLayer), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  // The real platform view, with the engine's side mocked: no stub map.
  group('the native map', () {
    late List<MethodCall> platformViews;
    late List<(int, MethodCall)> mapCalls;
    setUp(() => mapBackground.value = MapBackground.apple);
    tearDown(() {
      mapBackground.value = MapBackground.none;
      debugDefaultTargetPlatformOverride = null;
    });

    void mock(WidgetTester tester) {
      platformViews = [];
      mapCalls = [];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        platformViews.add(call);
        if (call.method == 'create') {
          final id = (call.arguments as Map)['id'] as int;
          messenger.setMockMethodCallHandler(
            MethodChannel('$appleMapViewType/$id'),
            (call) async {
              mapCalls.add((id, call));
              return null;
            },
          );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
    }

    for (final platform in const [TargetPlatform.iOS, TargetPlatform.macOS]) {
      testWidgets('on ${platform.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        mock(tester);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(width: 400, height: 300, child: _map()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The platform's own kind of view, under IgnorePointer: the map
        // around it takes every gesture.
        final native = platform == TargetPlatform.iOS
            ? find.byType(UiKitView)
            : find.byType(AppKitView);
        expect(native, findsOneWidget);
        expect(
          find.byType(platform == TargetPlatform.iOS ? AppKitView : UiKitView),
          findsNothing,
        );
        final ignore = tester.widget<IgnorePointer>(
          find.ancestor(of: native, matching: find.byType(IgnorePointer)).first,
        );
        expect(ignore.ignoring, isTrue);
        expect(
          find.descendant(
            of: find.byType(AppleMapLayer),
            matching: find.byType(IgnorePointer),
          ),
          findsOneWidget,
        );

        MapCamera camera() => MapCamera.of(tester.element(native));
        List<double> expected() => MercatorRegion.ofCamera(
          center: camera().center,
          zoom: camera().zoom,
          size: camera().nonRotatedSize,
        ).toList();
        void sentIs(List<double> region) {
          final values = (mapCalls.last.$2.arguments as List).cast<double>();
          expect(values, hasLength(4));
          for (var i = 0; i < 4; ++i) {
            expect(values[i], closeTo(region[i], 1e-15));
          }
        }

        // Created with the camera's region as its parameters.
        final create = platformViews.singleWhere(
          (call) => call.method == 'create',
        );
        final arguments = create.arguments as Map;
        expect(arguments['viewType'], appleMapViewType);
        final params = const StandardMessageCodec().decodeMessage(
          ByteData.sublistView(arguments['params'] as Uint8List),
        );
        expect(params, isA<List<Object?>>());
        expect((params as List).length, 4);
        final id = arguments['id'] as int;

        // Then told the region once it exists.
        expect(mapCalls, isNotEmpty);
        expect(mapCalls.every((call) => call.$1 == id), isTrue);
        expect(mapCalls.last.$2.method, 'setRegion');
        sentIs(expected());

        // A camera change sends the new region.
        final before = mapCalls.length;
        final zoom = camera().zoom;
        final centre = tester.getCenter(native);
        if (platform == TargetPlatform.iOS) {
          final first = await tester.startGesture(
            centre - const Offset(20, 0),
            pointer: 7,
          );
          final second = await tester.startGesture(
            centre + const Offset(20, 0),
            pointer: 8,
          );
          for (var step = 1; step <= 5; ++step) {
            await first.moveTo(centre - Offset(20.0 + step * 12, 0));
            await second.moveTo(centre + Offset(20.0 + step * 12, 0));
            await tester.pump();
          }
          await first.up();
          await second.up();
        } else {
          final mouse = TestPointer(1, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(mouse.hover(centre));
          await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
        }
        await tester.pumpAndSettle();
        expect(camera().zoom, greaterThan(zoom));
        expect(mapCalls.length, greaterThan(before));
        expect(mapCalls.last.$2.method, 'setRegion');
        sentIs(expected());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });
}

/// A loop of [width] metres around the start, faster on the far side.
LapPath _path({double width = 200}) => LapPath(
  origin: const GeoCoordinate(52, 21),
  segments: [
    [
      for (var i = 0; i <= 40; ++i)
        PathPoint(
          i.toDouble(),
          width / 2 * (1 - math.cos(i / 40 * 2 * math.pi)),
          120 * math.sin(i / 40 * 2 * math.pi),
          60 + 60 * math.sin(i / 40 * math.pi),
        ),
    ],
  ],
);

Widget _map({
  LapPath? reference,
  List<MapMark> marks = const [],
  ValueListenable<List<MapMark>>? movingMarks,
}) => TrackMap(
  path: _path(),
  reference: reference,
  gate: (const Offset(0, -10), const Offset(0, 10)),
  marks: marks,
  movingMarks: movingMarks,
);
