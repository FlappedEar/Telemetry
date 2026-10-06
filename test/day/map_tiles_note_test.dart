// FET-177: without a connection the map's tiles fail, and the map says its
// background needs one for as long as a failed tile is shown.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/main.dart';

import 'blank_tiles.dart';

/// Tiles that never decode, as when no tile server answers; with [every]
/// above 1, only every [every]th tile fails (the rest come from the cache).
final class _SomeTiles extends TileProvider {
  _SomeTiles({this.every = 1});

  final int every;
  final _blank = BlankTiles();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      (coordinates.x + coordinates.y) % every == 0
      ? MemoryImage(Uint8List.fromList([1, 2, 3]))
      : _blank.getImage(coordinates, options);
}

const _note = ValueKey('mapTilesNote');

void main() {
  tearDown(() {
    debugTileProvider = null;
    resetMapTilesUnavailable();
  });

  Widget map({MapController? controller}) => FlutterMap(
    mapController: controller,
    options: const MapOptions(initialCenter: LatLng(52, 21), initialZoom: 15),
    children: [mapTileLayer(streetTiles), MapAttribution(streetTiles)],
  );

  Future<void> show(
    WidgetTester tester,
    Widget body, {
    Locale locale = const Locale('en'),
  }) => tester.pumpWidget(
    TelemetryApp(
      locale: locale,
      home: Scaffold(body: body),
    ),
  );

  // Real time for the images to fail or decode, then the frames after
  // (loaded tiles fade in).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; ++i) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('failed tiles show the note; tiles that load hide it', (
    tester,
  ) async {
    debugTileProvider = _SomeTiles.new;
    await show(tester, map());
    await settle(tester);
    expect(mapTilesUnavailable.value, isTrue);
    expect(find.byKey(_note), findsOneWidget);
    expect(
      find.text(
        'The map background needs a connection; the trace is drawn without it.',
      ),
      findsOneWidget,
    );
    // Clear of the background button at the top and the attribution on
    // the right.
    final note = tester.getRect(find.byKey(_note));
    final screen = tester.getRect(find.byType(FlutterMap));
    expect(note.bottom, greaterThan(screen.height / 2));
    expect(note.right, lessThanOrEqualTo(screen.width * 0.6 + 1));

    // Signal again: the map shown next loads its tiles and the note goes.
    debugTileProvider = BlankTiles.new;
    await show(tester, KeyedSubtree(key: UniqueKey(), child: map()));
    await settle(tester);
    expect(mapTilesUnavailable.value, isFalse);
    expect(find.byKey(_note), findsNothing);
  });

  testWidgets('a pan with some tiles from the cache keeps the note', (
    tester,
  ) async {
    debugTileProvider = () => _SomeTiles(every: 3);
    final controller = MapController();
    await show(tester, map(controller: controller));
    await settle(tester);
    expect(find.byKey(_note), findsOneWidget);
    controller.move(const LatLng(52.001, 21.001), 15);
    await settle(tester);
    expect(mapTilesUnavailable.value, isTrue);
    expect(find.byKey(_note), findsOneWidget);
  });

  testWidgets('a map that loads beside one that failed keeps the note', (
    tester,
  ) async {
    debugTileProvider = _SomeTiles.new;
    await show(tester, Column(children: [Expanded(child: map())]));
    await settle(tester);
    debugTileProvider = BlankTiles.new;
    await show(
      tester,
      Column(
        children: [
          Expanded(child: map()),
          Expanded(
            child: KeyedSubtree(key: UniqueKey(), child: map()),
          ),
        ],
      ),
    );
    await settle(tester);
    expect(find.byKey(_note), findsNWidgets(2));
    // The failed map closes: nothing failed is shown any more.
    await show(tester, const SizedBox());
    await settle(tester);
    expect(mapTilesUnavailable.value, isFalse);
  });

  testWidgets('the note speaks Polish', (tester) async {
    debugTileProvider = _SomeTiles.new;
    await show(tester, map(), locale: const Locale('pl'));
    await settle(tester);
    expect(
      find.text(
        'Tło mapy wymaga połączenia z internetem; ślad jest rysowany bez niego.',
      ),
      findsOneWidget,
    );
  });
}
