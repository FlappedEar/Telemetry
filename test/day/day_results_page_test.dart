import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/comparison_page.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/document_pickers.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/file_access.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'blank_tiles.dart';
import '../support/temp_directory.dart';

/// Pickers that answer from fixed values.
final class FakeDocuments implements DocumentPickers {
  FakeDocuments({this.location, this.folder, this.document});

  final String? location;
  final String? folder;
  final String? document;
  final names = <String>[];

  @override
  Future<String?> saveLocation(String name) async {
    names.add(name);
    return location;
  }

  @override
  Future<String?> pickDocument() async => document;

  @override
  Future<String?> pickFolder() async => folder;

  @override
  Future<List<String>> savedDays() async => const [];
}

/// Counts what the import page asks of file access.
final class FakeFileAccess implements FileAccess {
  final remembered = <String>[];
  var restored = 0;

  @override
  Future<void> remember(List<String> paths) async => remembered.addAll(paths);

  @override
  Future<void> restore() async => ++restored;
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
  tearDown(() => deleteTemporaryDirectory(directory));

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
    await tester.binding.setSurfaceSize(const Size(400, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
      ),
    );
    // The best lap leads, as a bar with its name and time.
    final bar = find.byKey(const ValueKey('dayBestBar'));
    for (final text in [
      'Best day',
      best.displayName,
      displayTime(best.durationSeconds),
    ]) {
      expect(find.descendant(of: bar, matching: find.text(text)), findsOne);
    }
    expect(find.byType(TrackMap), findsOneWidget);
    expect(find.text('Best lap of each session'), findsOneWidget);
    // On a phone the laps are the second tab.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Laps'));
    await tester.pumpAndSettle();
    expect(find.text('Best of the day'), findsOneWidget);
    // Every other ranked lap shows its gap to the best of the day.
    final second = outcome.analysis!.ranking!.eligibleLaps[1];
    expect(
      find.text(displayDelta(second.durationSeconds - best.durationSeconds)),
      findsOneWidget,
    );
    // OUT, 3 laps, IN; OUT, 2 laps, IN.
    expect(find.textContaining(' · OUT'), findsNWidgets(2));
    expect(find.textContaining(' · IN'), findsNWidgets(2));
  });

  for (final (name, size, section) in [
    ('phone', const Size(400, 900), NavigationDestination),
    ('desktop', const Size(1200, 900), NavigationRailDestination),
  ]) {
    testWidgets('Compare suggests each session best against the day ($name)', (
      tester,
    ) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
        'b.vbo': [29, 32],
      });
      final ranking = outcome.analysis!.ranking!;
      final best = ranking.bestOfDay!;
      final other = ranking.runs
          .map((run) => run.bestLap)
          .firstWhere((lap) => lap != null && lap.reference != best.reference)!;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
        ),
      );
      expect(find.byKey(const ValueKey('daySections')), findsOneWidget);
      expect(find.byKey(const ValueKey('comparePick')), findsNothing);
      if (section == NavigationDestination) {
        await tester.tap(find.widgetWithText(NavigationDestination, 'Compare'));
      } else {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('Compare'),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comparePick')), findsOneWidget);
      final pair = find.byKey(ValueKey('comparePair-${other.reference}'));
      expect(pair, findsOneWidget);
      expect(
        find.descendant(
          of: pair,
          matching: find.text(
            displayDelta(other.durationSeconds - best.durationSeconds),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(pair);
      await tester.pumpAndSettle();
      expect(find.byType(ComparisonPage), findsOneWidget);
    });
  }

  testWidgets('the day sections speak Polish', (tester) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32],
    });
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
      ),
    );
    for (final label in ['Dzień', 'Okrążenia', 'Porównaj']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(NavigationDestination, 'Porównaj'));
    await tester.pumpAndSettle();
    expect(find.text('Wybierz dwa okrążenia'), findsOneWidget);
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

  testWidgets('the circuit dialog speaks Polish on a phone', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32],
    });
    await tester.binding.setSurfaceSize(const Size(360, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
      ),
    );
    await tester.tap(find.text('Session 1').last);
    await tester.pumpAndSettle();
    expect(find.text('Sesja 1'), findsOneWidget);
    expect(
      find.textContaining('przeciwnie do ruchu wskazówek zegara'),
      findsOneWidget,
    );
    expect(find.text('Przeciwnie do ruchu wskazówek zegara'), findsOneWidget);
    expect(
      find.text('Także dla sesji na tej samej trasie: Sesja 2'),
      findsOneWidget,
    );
    expect(find.text('Zapisz'), findsOneWidget);
    expect(find.text('Anuluj'), findsOneWidget);
    // On a narrow phone the long direction labels are stacked.
    final directions = tester.widget<SegmentedButton<TrackDirection>>(
      find.byType(SegmentedButton<TrackDirection>),
    );
    expect(directions.direction, Axis.vertical);
  });

  testWidgets('names the circuit of a session and its route', (tester) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
      'b.vbo': [29, 32],
    });
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
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
    // The title, beside the bottom bar's Day section.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Day')),
      findsOneWidget,
    );
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
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Day')),
      findsOneWidget,
    );
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

  test('names a day file without characters file systems refuse', () {
    expect(documentFileName('Day 2026/09/27'), 'Day 2026-09-27.fetproject');
  });

  /// A saved two-session day whose second recording was then moved to
  /// [moveTo] (relative to the test folder), opened again.
  Future<(String, OpenedDay)> savedDayMissingB(
    WidgetTester tester,
    String moveTo,
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
      final target = File('${directory.path}/$moveTo');
      target.parent.createSync(recursive: true);
      File('${directory.path}/b.vbo').renameSync(target.path);
      return openDay(path);
    }))!;
    return (path, opened);
  }

  // Lets the search's isolate and file work finish between frames.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && !done(); ++i) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'finds a moved and renamed recording by its content, and saves where it is now',
    (tester) async {
      final (path, opened) = await savedDayMissingB(
        tester,
        'archive/deep/renamed.vbo',
      );
      // A different recording named like the missing one is not used.
      File('${directory.path}/archive/b.vbo')
          .writeAsStringSync(circuitVbo([31, 30]));
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.opened(
            day: opened,
            documents: FakeDocuments(folder: '${directory.path}/archive'),
          ),
        ),
      );
      expect(find.text('Track day'), findsOneWidget);
      await tester.tap(find.text('Find recordings in a folder…'));
      await waitFor(
        tester,
        () => find.text('1 session could not be opened').evaluate().isEmpty,
      );
      expect(find.text('1 session could not be opened'), findsNothing);
      expect(find.textContaining('Session 2 · LAP'), findsWidgets);
      // Found somewhere new: the day has changes until saved.
      expect(find.text('Track day •'), findsOneWidget);

      await tester.tap(find.byTooltip('Save'));
      await waitFor(tester, () => find.text('Track day').evaluate().isNotEmpty);
      expect(find.text('Track day'), findsOneWidget);
      final saved = (await tester.runAsync(() async => readDayDocument(path)))!;
      final references = [
        for (final run in (saved['event']! as Map)['runs']! as List)
          (((run as Map)['sources']! as Map)['telemetry']! as List).first
              as Map,
      ];
      expect(
        [
          for (final source in references)
            (source['reference']! as Map)['relativePath'],
        ],
        ['a.vbo', 'archive/deep/renamed.vbo'],
      );
    },
  );

  testWidgets(
    'a day none of whose recordings can be read offers to find them, and opens',
    (tester) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final path = '${directory.path}/Day.fetproject';
      await tester.runAsync(() async {
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
        Directory('${directory.path}/moved').createSync();
        File('${directory.path}/a.vbo')
            .renameSync('${directory.path}/moved/a.vbo');
      });
      final access = FakeFileAccess();
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayImportPage(
            documents: FakeDocuments(
              document: path,
              folder: '${directory.path}/moved',
            ),
            fileAccess: access,
          ),
        ),
      );
      await tester.tap(find.text('Open a saved day…'));
      await waitFor(
        tester,
        () => find.text('Track day could not be opened').evaluate().isNotEmpty,
      );
      // Access kept from earlier launches is restored before reading.
      expect(access.restored, 1);
      expect(
        find.textContaining('a.vbo · Recording not found.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('cannotOpenFindRecordings')));
      await waitFor(
        tester,
        () => find.byType(DayResultsPage).evaluate().isNotEmpty,
      );
      expect(find.byType(DayResultsPage), findsOneWidget);
      expect(find.text('Track day could not be opened'), findsNothing);
      // Found somewhere new: the day has changes until saved.
      expect(find.text('Track day •'), findsOneWidget);
    },
  );

  testWidgets('a recording added while finding recordings is kept', (
    tester,
  ) async {
    final (_, opened) = await savedDayMissingB(tester, 'archive/b.vbo');
    final controller = DayResultsController.opened(
      opened,
      appender: _AppendHere(),
    );
    final c = '${directory.path}/c.vbo';
    File(c).writeAsStringSync(circuitVbo([31, 30, 32]));
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: FakeDocuments(folder: '${directory.path}/archive'),
        ),
      ),
    );
    await tester.tap(find.text('Find recordings in a folder…'));
    await tester.pump();
    // Shared while the day's recordings are searched for.
    final addition = await tester.runAsync(() => controller.addRecordings([c]));
    expect(addition!.added, ['Session 3']);
    await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(
      find.text('Recordings were added meanwhile. Find the recordings again.'),
      findsOneWidget,
    );
    expect(controller.runs, hasLength(2));
  });

  testWidgets('refuses a different recording with the missing one\'s name', (
    tester,
  ) async {
    final (_, opened) = await savedDayMissingB(tester, 'gone/b.vbo');
    File('${directory.path}/gone/b.vbo').deleteSync();
    File('${directory.path}/elsewhere/b.vbo').createSync(recursive: true);
    File('${directory.path}/elsewhere/b.vbo')
        .writeAsStringSync(circuitVbo([29, 33]));
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.opened(
          day: opened,
          documents: FakeDocuments(folder: '${directory.path}/elsewhere'),
        ),
      ),
    );
    await tester.tap(find.text('Find recordings in a folder…'));
    await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(
      find.text(
        'b.vbo in that folder is a different recording and was not used.',
      ),
      findsOneWidget,
    );
    expect(find.text('1 session could not be opened'), findsOneWidget);
    expect(find.text('Track day'), findsOneWidget);
  });

  testWidgets('draws the trace over street tiles with attribution', (
    tester,
  ) async {
    final outcome = importDay({
      'a.vbo': [30, 28, 31],
    });
    mapBackground.value = MapBackground.streets;
    debugTileProvider = BlankTiles.new;
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
    // A real map is always under the trace: no trace-only choice.
    await tester.tap(find.byTooltip('Map background'));
    await tester.pumpAndSettle();
    expect(find.text('Streets'), findsOneWidget);
    expect(find.text('Trace only'), findsNothing);
    expect(find.text('Plain'), findsNothing);
    expect(availableBackgrounds, isNot(contains(MapBackground.none)));
    expect(
      find.byType(CheckedPopupMenuItem<MapBackground>),
      findsNWidgets(availableBackgrounds.length),
    );
    await tester.tap(find.byType(CheckedPopupMenuItem<MapBackground>).first);
    await tester.pumpAndSettle();
    expect(mapBackground.value, MapBackground.streets);
    expect(find.byType(FlutterMap), findsOneWidget);
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

/// Prepares additions on the test's own thread.
final class _AppendHere implements DayAppender {
  @override
  DayAppendJob start(DayAppendRequest request, void Function(int, int) _) =>
      _AppendedJob(runDayAppend(request));
}

final class _AppendedJob implements DayAppendJob {
  _AppendedJob(DayAppendOutcome outcome) : result = Future.value(outcome);

  @override
  final Future<DayAppendOutcome> result;

  @override
  void cancel() {}
}
