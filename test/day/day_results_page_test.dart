import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/document_pickers.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// Transparent tiles, without network.
final class _BlankTiles extends TileProvider {
  // A 1x1 transparent PNG.
  static final _png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    ),
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

/// Pickers that answer from fixed values.
final class FakeDocuments implements DocumentPickers {
  FakeDocuments({this.location, this.folder});

  final String? location;
  final String? folder;
  final names = <String>[];

  @override
  Future<String?> saveLocation(String name) async {
    names.add(name);
    return location;
  }

  @override
  Future<String?> pickDocument() async => null;

  @override
  Future<String?> pickFolder() async => folder;

  @override
  Future<List<String>> savedDays() async => const [];
}

/// A synthetic, undated recording driving a 100 m circle through a start
/// line, one lap per speed (m/s), at 10 Hz. No real data.
String circuitVbo(List<double> speeds) {
  const lat0 = 52.0, lon0 = 21.0;
  const metersPerDegree = 6371000.0 * math.pi / 180.0;
  final cosLat = math.cos(lat0 * math.pi / 180.0);
  String coordinate(double east, double north) =>
      '${(lat0 + north / metersPerDegree).toStringAsFixed(8)} '
      '${(lon0 + east / (metersPerDegree * cosLat)).toStringAsFixed(8)}';
  final gateA = coordinate(-10, 0).split(' '),
      gateB = coordinate(10, 0).split(' ');
  final rows = StringBuffer();
  var travelled = 0.0, t = 0.0;
  final total = (speeds.length + 0.5) * 2 * math.pi;
  while (travelled < total) {
    final lap = math.min(travelled ~/ (2 * math.pi), speeds.length - 1);
    final a = -0.25 + travelled;
    rows.writeln(
      '${t.toStringAsFixed(2)} ${coordinate(-100 + 100 * math.cos(a), 100 * math.sin(a))} '
      '${(speeds[lap] * 3.6 * (0.8 + 0.2 * math.cos(2 * a))).toStringAsFixed(2)}',
    );
    travelled += speeds[lap] / 10 / 100;
    t += 0.1;
  }
  return '[header]\ncoordinate units = degrees\n[laptiming]\n'
      'Start ${gateA[1]} ${gateA[0]} ${gateB[1]} ${gateB[0]} start\n'
      '[column names]\ntime latitude longitude velocity\n[data]\n$rows';
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('day_results'));
  tearDown(() => directory.deleteSync(recursive: true));

  DayImportOutcome importDay(Map<String, List<double>> files) {
    final paths = <String>[];
    files.forEach((name, speeds) {
      final path = '${directory.path}/$name';
      File(path).writeAsStringSync(circuitVbo(speeds));
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  testWidgets('leads with the best lap of the day and lists every section', (
    tester,
  ) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32],
    });
    expect(outcome.analysis, isNotNull);
    final best = outcome.analysis!.ranking!.bestOfDay!;
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
      ),
    );
    expect(find.text('Best day'), findsOneWidget);
    expect(find.text(best.displayName), findsWidgets);
    expect(find.byType(TrackMap), findsOneWidget);
    expect(find.text('Best lap of each session'), findsOneWidget);
    expect(find.text('Best of the day'), findsOneWidget);
    // OUT, 3 laps, IN; OUT, 2 laps, IN.
    expect(find.textContaining(' · OUT'), findsNWidgets(2));
    expect(find.textContaining(' · IN'), findsNWidgets(2));
  });

  testWidgets(
    'opens a lap with its trace, and excluding the best lap re-ranks the day',
    (tester) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final analysis = outcome.analysis!;
      final best = analysis.ranking!.bestOfDay!;
      final second = analysis.ranking!.eligibleLaps[1];
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage(runs: outcome.runs, analysis: analysis),
        ),
      );
      await tester.tap(find.text('Tap to open the lap.'));
      await tester.pumpAndSettle();
      expect(find.byType(LapPage), findsOneWidget);
      expect(find.text('Best lap of the day'), findsOneWidget);
      expect(find.byType(TrackMap), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);

      await tester.tap(find.text('Exclude from ranking…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Traffic');
      await tester.pump();
      await tester.tap(find.text('Exclude'));
      await tester.pumpAndSettle();
      expect(find.text('Not ranked: excluded (“Traffic”)'), findsOneWidget);
      expect(find.text('Include in ranking'), findsOneWidget);
      expect(
        find.textContaining('to the best of the day (${second.displayName})'),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Excluded: Traffic'), findsOneWidget);
      expect(find.text(second.displayName), findsWidgets);
      expect(best.reference, isNot(second.reference));
    },
  );

  testWidgets('names the circuit of a session and its route', (tester) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32],
    });
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
      ),
    );
    expect(
      find.textContaining('Group 1 · Detected route · Counterclockwise'),
      findsOneWidget,
    );
    await tester.tap(find.text('Session 1').last);
    await tester.pumpAndSettle();
    expect(find.text('Circuit of Session 1'), findsOneWidget);
    expect(
      find.textContaining('Also for the sessions on the same route: Session 2'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'Club');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Group 1 · Club · Counterclockwise'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Club · Counterclockwise · set by you'),
      findsNWidgets(2),
    );

    await tester.tap(find.text('Session 2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use the detected route'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Club · Counterclockwise · set by you'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Detected route · Counterclockwise · inferred from GPS',
      ),
      findsOneWidget,
    );
  });

  testWidgets('saves the day and opens it again with its exclusion', (
    tester,
  ) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32],
    });
    final best = outcome.analysis!.ranking!.bestOfDay!;
    final path = '${directory.path}/Day.fetproject';
    final saved = <Map<String, Object?>>[];
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      writer: (path, document) async => saved.add(document),
    );
    expect(controller.exclude(best, 'Traffic'), isTrue);
    final documents = FakeDocuments(location: path);
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: documents,
        ),
      ),
    );
    expect(find.text('Day results'), findsOneWidget);
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(documents.names, ['Day']);
    expect(find.text('Saved as Day.fetproject.'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(saved, hasLength(1));

    final opened = (await tester.runAsync(() async {
      await saveDayDocument(path, saved.single);
      return openDay(path);
    }))!;
    expect(opened.missing, isEmpty);
    expect(opened.exclusions, {best.reference: 'Traffic'});
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.opened(day: opened, documents: documents),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Excluded: Traffic'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
  });

  testWidgets('lists the sessions whose recordings are missing', (
    tester,
  ) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32],
    });
    final path = '${directory.path}/Day.fetproject';
    final opened = (await tester.runAsync(() async {
      await saveDayDocument(
        path,
        dayDocument(
          eventId: newEventId(),
          name: 'Track day',
          runs: outcome.runs,
          analysis: outcome.analysis!,
          projectPath: path,
        ),
      );
      File('${directory.path}/b.vbo').deleteSync();
      return openDay(path);
    }))!;
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.opened(day: opened, documents: FakeDocuments()),
      ),
    );
    expect(find.text('1 session could not be opened'), findsOneWidget);
    expect(find.textContaining('b.vbo · Recording not found.'), findsOneWidget);
    expect(find.text('Find recordings in a folder…'), findsOneWidget);
  });

  test('finds missing recordings by file name in a folder', () {
    Directory('${directory.path}/moved/deep').createSync(recursive: true);
    File('${directory.path}/moved/deep/B.VBO').writeAsStringSync('');
    expect(
      findRecordings(directory.path, const [
        MissingRecording(
          runId: 'run-b',
          name: 'Session 2',
          path: 'b.vbo',
          reason: 'Recording not found.',
        ),
      ]),
      {'run-b': '${directory.path}/moved/deep/B.VBO'},
    );
    expect(documentFileName('Day 2026/09/27'), 'Day 2026-09-27.fetproject');
  });

  testWidgets('draws the trace over street tiles with attribution', (
    tester,
  ) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
    });
    mapBackground.value = MapBackground.streets;
    debugTileProvider = _BlankTiles.new;
    addTearDown(() {
      mapBackground.value = MapBackground.none;
      debugTileProvider = null;
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
      ),
    );
    await tester.tap(find.text('Tap to open the lap.'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    await tester.tap(find.byTooltip('Map background'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trace only'));
    await tester.pumpAndSettle();
    expect(mapBackground.value, MapBackground.none);
    expect(find.byType(FlutterMap), findsNothing);
  });

  test('maps metres around the origin back to degrees', () {
    const origin = GeoCoordinate(52.0, 21.0);
    final point = pathLatLng(origin, 100, -50);
    final metric = projectCoordinate(
      GeoCoordinate(point.latitude, point.longitude),
      origin,
    );
    expect(metric.eastMeters, closeTo(100, 1e-6));
    expect(metric.northMeters, closeTo(-50, 1e-6));
  });

  test('speed colours run from the slow end to the fast end of the ramp', () {
    expect(speedColor(0), speedRamp.first);
    expect(speedColor(1), speedRamp.last);
    expect(speedColor(-3), speedRamp.first);
  });
}
