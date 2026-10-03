// Takes the user guide's screenshots from the real app widgets, with the
// made-up day of demo_day.dart. Not part of CI. Run from the repository root:
//
//   flutter test tool/user_guide/capture_screens_test.dart --update-goldens
//
// The pictures land in docs/user-guide/assets/screens/. Text is drawn with
// Roboto and icons with Material Icons from the Flutter SDK, so they look like
// the app on Android rather than the test font's boxes. Maps show the street
// background's controls and attribution over plain grey tiles (no network).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/driving_panels.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/day_import_controller.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';

import 'demo_day.dart';

const _out = '../../docs/user-guide/assets/screens';
const _desktop = Size(1280, 800);
const _phone = Size(412, 915);

final _root = GlobalKey();

/// Plain light grey tiles in place of the street map: tests have no network.
final class _PlainTiles extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGN4+eYZAAV9Arz1x/UjAAAAAElFTkSuQmCC',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

/// Imports on the test's own thread, so the page shows real results.
final class _DirectImporter implements DayImporter {
  @override
  DayImportJob start(
    DayImportRequest request,
    void Function(int, int) progress,
  ) => _DirectJob(runDayImport(request));
}

final class _DirectJob implements DayImportJob {
  _DirectJob(DayImportOutcome outcome) : result = Future.value(outcome);

  @override
  final Future<DayImportOutcome> result;

  @override
  void cancel() {}
}

final class _Pickers implements RecordingPickers {
  _Pickers(this.recordings);

  final List<String> recordings;

  @override
  Future<List<String>> pickRecordings() async => recordings;

  @override
  Future<String?> pickFolder() async => null;
}

Future<void> _loadFonts() async {
  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable)
          .parent
          .parent
          .parent
          .parent
          .parent
          .parent
          .path;
  final fonts = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('$fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  // Symbols Roboto lacks (▲ ◆ ● ┆), as the system font supplies them on a
  // phone. The test engine falls back to fonts registered under these names.
  final symbols = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
  if (symbols.existsSync()) {
    for (final family in ['sans-serif', 'DejaVu Sans', 'Noto Sans Symbols']) {
      final loader = FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(symbols.readAsBytesSync())));
      await loader.load();
    }
  }
}

void main() {
  late Directory directory;
  late List<String> recordings;

  setUpAll(() async {
    WidgetsApp.debugAllowBannerOverride = false;
    // The street map as in the app, with plain tiles: tests have no network.
    // ignore: invalid_use_of_visible_for_testing_member
    debugTileProvider = _PlainTiles.new;
    mapBackground.value = MapBackground.streets;
    await _loadFonts();
    directory = Directory.systemTemp.createTempSync('user_guide');
    recordings = [
      for (final MapEntry(key: name, value: text) in demoDay().entries)
        (File('${directory.path}/$name')..writeAsStringSync(text)).path,
    ];
  });
  tearDownAll(() => directory.deleteSync(recursive: true));

  Future<void> size(WidgetTester tester, Size logical, double ratio) async {
    tester.view.physicalSize = logical * ratio;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
  }

  Future<void> shot(WidgetTester tester, String name, [Finder? finder]) async {
    await tester.pumpAndSettle();
    await expectLater(
      finder ?? find.byKey(_root),
      matchesGoldenFile('$_out/$name.png'),
    );
  }

  Widget app(Widget home) => RepaintBoundary(
    key: _root,
    child: TelemetryApp(home: home),
  );

  DayImportOutcome importDay() =>
      runDayImport((paths: recordings, includeSubfolders: false));

  testWidgets('import page', (tester) async {
    debugDisableShadows = false;
    await size(tester, _desktop, 1.5);
    final controller = DayImportController(importer: _DirectImporter());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        DayImportPage(
          controller: controller,
          pickers: _Pickers(recordings),
          picksFolders: true,
          acceptsDrops: true,
        ),
      ),
    );
    await shot(tester, 'import-empty');
    await tester.tap(find.text('Choose recordings…'));
    await tester.pumpAndSettle();
    await shot(tester, 'import-done');
    debugDisableShadows = true;
  });

  testWidgets('phone import page', (tester) async {
    debugDisableShadows = false;
    await size(tester, _phone, 2);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = DayImportController(importer: _DirectImporter());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        DayImportPage(
          controller: controller,
          pickers: _Pickers(recordings),
          picksFolders: false,
          acceptsDrops: false,
        ),
      ),
    );
    await tester.tap(find.text('Choose recordings…'));
    await tester.pumpAndSettle();
    await shot(tester, 'phone-import-done');
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  });

  /// Scrolls [finder] to the top of its list.
  Future<void> toTop(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(
      tester.element(finder.first),
      alignment: 0.02,
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollIn(
    WidgetTester tester,
    Finder list,
    Finder target, {
    double delta = 300,
  }) async {
    for (var i = 0; i < 100 && target.hitTestable().evaluate().isEmpty; ++i) {
      await tester.drag(list, Offset(0, -delta), warnIfMissed: false);
      await tester.pump();
    }
    await toTop(tester, target);
  }

  Finder list(String key) => find
      .descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> showDay(WidgetTester tester, Size logical, double ratio) async {
    await size(tester, logical, ratio);
    final outcome = importDay();
    await tester.pumpWidget(
      app(DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  testWidgets('day results, wide', (tester) async {
    debugDisableShadows = false;
    await showDay(tester, _desktop, 1.5);
    await shot(tester, 'day-wide');
    final summary = list('dayResultsSummary');

    await scrollIn(tester, summary, find.text('Theoretical best'));
    await shot(tester, 'theoretical-best');
    await scrollIn(tester, summary, find.text('Where the time goes'));
    await shot(tester, 'where-the-time-goes');
    await scrollIn(tester, summary, find.text('Sector times'));
    await shot(tester, 'sector-times');
    await scrollIn(tester, summary, find.text('Time losses'));
    await shot(tester, 'time-losses');
    await scrollIn(tester, summary, find.text('Where to look next'));
    await shot(tester, 'where-to-look-next');
    await scrollIn(tester, summary, find.text('Consistency'));
    await shot(tester, 'consistency');
    await scrollIn(tester, summary, find.text('Progression'));
    await shot(tester, 'progression');
    await scrollIn(tester, summary, find.text('Best lap of each session'));
    await shot(tester, 'sessions-and-circuits');

    // A circuit.
    await scrollIn(tester, summary, find.text('Circuits'));
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await shot(tester, 'circuit-dialog');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A corner's details, from the theoretical best's losses.
    final corner = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('lossRow Corner'),
    );
    await scrollIn(tester, summary, corner, delta: -300);
    await tester.tap(corner.first);
    await tester.pumpAndSettle();
    await shot(tester, 'corner-details');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    // The segment editor.
    await toTop(tester, find.text('Edit segments'));
    await tester.tap(find.text('Edit segments'));
    await tester.pumpAndSettle();
    await shot(tester, 'segment-editor');

    // The day report.
    await back(tester);
    await tester.tap(find.byTooltip('Day report'));
    await tester.pumpAndSettle();
    await shot(tester, 'day-report');
    debugDisableShadows = true;
  });

  testWidgets('a lap, wide', (tester) async {
    debugDisableShadows = false;
    await showDay(tester, _desktop, 1.5);
    await tester.tap(find.text('Tap to open the lap.'));
    await tester.pumpAndSettle();
    await shot(tester, 'lap-wide');
    await back(tester);

    final lap = find.descendant(
      of: find.byKey(const ValueKey('dayResultsLaps')),
      matching: find.text('Session 2 · LAP 4'),
    );
    await tester.scrollUntilVisible(
      lap,
      200,
      scrollable: list('dayResultsLaps'),
    );
    await tester.tap(lap);
    await tester.pumpAndSettle();
    await shot(tester, 'lap-other');
    await tester.tap(find.text('Exclude from ranking…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Traffic in the hairpin');
    await tester.pumpAndSettle();
    await shot(tester, 'exclude-dialog');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Drag the right-hand column below the map, which takes drags itself.
    for (var i = 0; i < 40 && find.text('Coasting').evaluate().isEmpty; ++i) {
      await tester.dragFrom(const Offset(1000, 700), const Offset(0, -300));
      await tester.pump();
    }
    await toTop(tester, find.text('Coasting'));
    await shot(tester, 'lap-coasting');
    debugDisableShadows = true;
  });

  testWidgets('compare laps, wide', (tester) async {
    debugDisableShadows = false;
    await showDay(tester, _desktop, 1.5);
    await tester.tap(find.text('Compare two laps'));
    await tester.pumpAndSettle();
    await shot(tester, 'compare-pick-a');
    await tester.tap(find.textContaining('Session 2 · LAP 4').last);
    await tester.pumpAndSettle();
    await shot(tester, 'compare-pick-b');
    await tester.tap(find.text('Suggested: the fastest'));
    await tester.pumpAndSettle();
    await shot(tester, 'compare-wide');

    await tester.tap(find.byKey(const ValueKey('comparisonMapLayerPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Δ time').last);
    await tester.pumpAndSettle();
    await shot(tester, 'compare-delta-map');

    final page = find.byType(Scrollable).hitTestable().last;
    await scrollIn(tester, page, find.text('Corner Analyzer'));
    await shot(tester, 'corner-analyzer-no-segments');
    await tester.tap(find.text('Use the theoretical best’s segments'));
    await tester.pumpAndSettle();
    await scrollIn(tester, page, find.byType(ComparisonGgPanel));
    await shot(tester, 'gg');
    await scrollIn(tester, page, find.byType(ComparisonDrivingStatesPanel));
    await shot(tester, 'driving-states');
    await scrollIn(tester, page, find.byType(ComparisonCoastingPanel));
    await shot(tester, 'compare-coasting');
    debugDisableShadows = true;
  });

  testWidgets('corner analyzer from a loss', (tester) async {
    debugDisableShadows = false;
    await showDay(tester, _desktop, 1.5);
    final open = find.byTooltip('Open in the Corner Analyzer');
    await scrollIn(tester, list('dayResultsSummary'), open);
    await tester.tap(open.first);
    await tester.pumpAndSettle();
    await shot(tester, 'corner-analyzer-segment');
    debugDisableShadows = true;
  });

  testWidgets('phone', (tester) async {
    debugDisableShadows = false;
    await showDay(tester, _phone, 2);
    await shot(tester, 'phone-results');
    await tester.tap(find.widgetWithText(Tab, 'Laps'));
    await tester.pumpAndSettle();
    await shot(tester, 'phone-laps');
    final best = find.descendant(
      of: find.byKey(const ValueKey('dayResultsLaps')),
      matching: find.text('Session 3 · LAP 2'),
    );
    await tester.scrollUntilVisible(
      best,
      200,
      scrollable: list('dayResultsLaps'),
    );
    await tester.tap(best);
    await tester.pumpAndSettle();
    await shot(tester, 'phone-lap');
    await toTop(tester, find.text('Channels'));
    await shot(tester, 'phone-lap-charts');
    debugDisableShadows = true;
  });
}
