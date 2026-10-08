// Takes the user guide's screenshots from the real app widgets. Not part of
// CI. Run from the repository root, with a folder of the day's recordings:
//
//   GUIDE_RECORDINGS=../refdata \
//     flutter test tool/user_guide/capture_screens_test.dart --update-goldens
//
// The guide shows the owner's Jastrząb day of 29 August 2026 (FlappedEar/refdata),
// which the owner approved for the public guide, heart rate included; the
// recordings themselves never leave that repository. Without GUIDE_RECORDINGS
// the made-up day of demo_day.dart is used, for trying the tool out.
//
// The pictures land in docs/user-guide/assets/screens/. Text is drawn with
// the app's bundled Sora and JetBrains Mono and icons with Material Icons from
// the Flutter SDK, so they look like the app rather than the test font's
// boxes. Maps show the street background's controls and attribution over
// plain grey tiles (no network). Sessions' weather is the weather service's
// answer for the day, recorded in jastrzab_weather.json.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/app/app_navigation.dart';
import 'package:telemetry/channel_names.dart';
import 'package:telemetry/day/day_context.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/reference_lap.dart';
import 'package:telemetry/day/day_weather.dart';
import 'package:telemetry/day/driving_panels.dart';
import 'package:telemetry/day/next_session_card.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/day_import_controller.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry/profile/profile_page.dart';
import 'package:telemetry/profile/track_notebook_page.dart';
import 'package:telemetry/settings_dialog.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry/day/recovery_store.dart';
import 'package:telemetry_core/telemetry_core.dart'
    show
        DayRecovery,
        NotebookItem,
        TrackNotebook,
        ImportChoices,
        clearDayRecovery,
        readDayRecovery,
        writeDayRecovery;
import 'package:telemetry/ui/theme.dart';

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

/// The driver profile in [folder], read and written on the test's thread.
ProfileLibrary _library(String folder) => ProfileLibrary(
  store: FolderProfileStore(folder),
  defaultCarName: 'My car',
  defaultTrackName: (number) => 'Track $number',
  background: <R>(FutureOr<R> Function() computation) async => computation(),
);

/// Imports on the test's own thread, so the page shows real results.
final class _DirectImporter implements DayImporter {
  @override
  DayImportJob start(
    DayImportRequest request,
    void Function(int, int) progress, {
    ImportChoices? choices,
  }) => _DirectJob(runDayImport(request, choices: choices));
}

/// Keeps the unsaved day in a file, as the app does, so the import page
/// shows the day left with its sessions.
final class _FileRecovery implements RecoveryStore {
  _FileRecovery(this.file);

  final String file;

  @override
  Future<String?> path() async => file;

  @override
  Future<DayRecovery?> load() async => readDayRecovery(file);

  @override
  Future<void> write(DayRecovery recovery) => writeDayRecovery(file, recovery);

  @override
  Future<void> clear() => clearDayRecovery(file);
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

  List<String> recordings;

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
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  List<String> bundled(String family) => [
    for (final file in Directory('assets/fonts').listSync())
      if (file.path.endsWith('.ttf') &&
          file.uri.pathSegments.last.startsWith('$family-'))
        file.path,
  ];

  await load(FetTheme.sans, bundled('Sora'));
  await load(FetTheme.mono, bundled('JetBrainsMono'));
  await load('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
}

void main() {
  late Directory directory;
  late List<String> recordings;
  late String bestName, otherName;

  DayImportOutcome importDay() =>
      runDayImport((paths: recordings, includeSubfolders: false));

  setUpAll(() async {
    WidgetsApp.debugAllowBannerOverride = false;
    // The street map as in the app, with plain tiles: tests have no network.
    // ignore: invalid_use_of_visible_for_testing_member
    debugTileProvider = _PlainTiles.new;
    mapBackground.value = MapBackground.streets;
    // The weather service's real answer for the day, recorded (tests have
    // no network): every session of the Jastrząb day gets its weather.
    final weather = jsonDecode(
      File('tool/user_guide/jastrzab_weather.json').readAsStringSync(),
    );
    defaultWeatherFetcher = (_) async => weather;
    await _loadFonts();
    directory = Directory.systemTemp.createTempSync('user_guide');
    final real = Platform.environment['GUIDE_RECORDINGS'];
    recordings = real != null
        ? [
            for (final file in Directory(real).listSync())
              if (RegExp(
                r'\.(vbo|rcz)$',
                caseSensitive: false,
              ).hasMatch(file.path))
                file.path,
          ]
        : [
            for (final MapEntry(key: name, value: text) in demoDay().entries)
              (File('${directory.path}/$name')..writeAsStringSync(text)).path,
          ];
    recordings.sort();
    final analysis = importDay().analysis!;
    final best = analysis.ranking!.bestOfDay!;
    bestName = best.displayName;
    // Lap A of the comparisons: the best lap of the session before the best
    // lap's session (or after it), so it differs from the best lap.
    final ranked = analysis.rows
        .where((row) => row.referenceEligible && row.runId != best.runId)
        .toList();
    final runs = {for (final row in analysis.rows) row.runId}.toList();
    final index = runs.indexOf(best.runId);
    final other = runs[index > 0 ? index - 1 : index + 1];
    final candidates = ranked.where((row) => row.runId == other).toList()
      ..sort((x, y) => (x.end - x.start).compareTo(y.end - y.start));
    otherName = (candidates.isEmpty ? ranked : candidates).first.displayName;
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

  /// Lets file and isolate work run between frames until [done].
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 500 && !done(); ++i) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
    await tester.pumpAndSettle();
  }

  /// Imports [pickers]' recordings from [page]; their day opens by itself.
  Future<void> importDayFrom(WidgetTester tester, DayImportPage page) async {
    await tester.pumpWidget(app(page));
    await tester.tap(find.text('Import sessions…'));
    await until(
      tester,
      () => find.byType(DayResultsPage).evaluate().isNotEmpty,
    );
  }

  /// Waits until the day shown is saved in the library at [folder] by
  /// itself, as the app does, and its recordings are lined up and saved too.
  Future<void> savedIn(WidgetTester tester, String folder) async {
    await until(tester, () {
      final days = Directory('$folder/Days');
      return days.existsSync() &&
          days.listSync().any((file) => file.path.endsWith('.fetproject'));
    });
    // The RCZs are lined up in the background, and the day saves again by
    // itself a moment after.
    for (var i = 0; i < 40; ++i) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
  }

  /// Goes back from the day to the import page, which lists its sessions.
  Future<void> backToImport(WidgetTester tester) async {
    // As the back button does: a day in the library saves its changes first.
    await Navigator.of(tester.element(find.byType(DayResultsPage))).maybePop();
    await until(
      tester,
      () => find.byKey(const ValueKey('lastDay')).evaluate().isNotEmpty,
    );
    // The snackbar of the import notes, if any, is not part of the picture.
    ScaffoldMessenger.of(tester.element(find.byType(DayImportPage)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
  }

  /// Closes the day page and waits for its recovery file, so nothing is
  /// left running for the next test.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 25; ++i) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('import page', (tester) async {
    debugDisableShadows = false;
    await size(tester, _desktop, 1.5);
    final controller = DayImportController(importer: _DirectImporter());
    addTearDown(controller.dispose);
    final page = DayImportPage(
      controller: controller,
      pickers: _Pickers(recordings),
      picksFolders: true,
      acceptsDrops: true,
      recovery: _FileRecovery('${directory.path}/import-recovery.json'),
      library: _library('${directory.path}/Profile'),
    );
    await tester.pumpWidget(app(page));
    // The logo is read from the app's assets before the first picture.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/splash-logo.png'),
        tester.element(find.byType(DayImportPage)),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'import-empty');
    await importDayFrom(tester, page);
    await savedIn(tester, '${directory.path}/Profile');
    await backToImport(tester);
    await shot(tester, 'import-done');
    // The library, with the day just imported in it.
    await tester.tap(find.byKey(const ValueKey('place-library')));
    await tester.pumpAndSettle();
    await shot(tester, 'library');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await close(tester);
    debugDisableShadows = true;
  });

  testWidgets('phone import page', (tester) async {
    debugDisableShadows = false;
    await size(tester, _phone, 2);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = DayImportController(importer: _DirectImporter());
    addTearDown(controller.dispose);
    await importDayFrom(
      tester,
      DayImportPage(
        controller: controller,
        pickers: _Pickers(recordings),
        picksFolders: false,
        acceptsDrops: false,
        recovery: _FileRecovery('${directory.path}/phone-recovery.json'),
        library: _library('${directory.path}/PhoneProfile'),
      ),
    );
    await savedIn(tester, '${directory.path}/PhoneProfile');
    await backToImport(tester);
    await shot(tester, 'phone-import-done');
    await close(tester);
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  });

  testWidgets('import review', (tester) async {
    debugDisableShadows = false;
    await size(tester, _desktop, 1.5);
    // The recordings under plain names ("recording-1.vbo"), so the picture
    // shows no file names of the day; their content is unchanged.
    final named = Directory('${directory.path}/review')..createSync();
    final stems = <String, int>{};
    final copies = [
      for (final path in recordings)
        File(path)
            .copySync(
              '${named.path}/recording-${stems.putIfAbsent(path.substring(0, path.lastIndexOf('.')).toLowerCase(), () => stems.length + 1)}'
              '${path.substring(path.lastIndexOf('.')).toLowerCase()}',
            )
            .path,
    ];
    // The day's first session, then the rest added with a review.
    final controller = DayImportController(importer: _DirectImporter());
    addTearDown(controller.dispose);
    final first = copies
        .where((path) => path.contains('recording-1.'))
        .toList();
    final pickers = _Pickers(first);
    await importDayFrom(
      tester,
      DayImportPage(
        controller: controller,
        pickers: pickers,
        picksFolders: true,
        acceptsDrops: true,
      ),
    );
    pickers.recordings = [
      for (final path in copies)
        if (!first.contains(path)) path,
    ];
    // The import notes of the first session are not part of the picture.
    ScaffoldMessenger.of(tester.element(find.byType(DayResultsPage)))
        .removeCurrentSnackBar();
    await tester.tap(find.byKey(const ValueKey('moreMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('addAndReviewRecordings')));
    await until(
      tester,
      () => find.text('Review the import').evaluate().isNotEmpty,
    );
    await shot(tester, 'import-review');
    await close(tester);
    debugDisableShadows = true;
  });

  /// Scrolls [finder] to the top of its list.
  Future<void> toTop(WidgetTester tester, Finder finder) async {
    // Twice: the first scroll can land short while the cards around the
    // target are laid out for the first time.
    for (var i = 0; i < 2; ++i) {
      await Scrollable.ensureVisible(
        tester.element(finder.first),
        alignment: 0.02,
      );
      await tester.pumpAndSettle();
    }
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
    // The app's places around the day, as the start page shows them.
    // Day and Coach switch the page between its tabs and its coach.
    final host = Object();
    final coach = ValueNotifier(false);
    void sync() => appNavigation.update(
      section: coach.value ? AppSection.coach : AppSection.day,
      dayAvailable: true,
      libraryAvailable: true,
    );
    appNavigation.attach(host, (section) {
      if (section == AppSection.day || section == AppSection.coach) {
        coach.value = section == AppSection.coach;
      }
    });
    coach.addListener(sync);
    sync();
    addTearDown(() => appNavigation.detach(host));
    final outcome = importDay();
    await tester.pumpWidget(
      app(
        DayResultsPage(
          runs: outcome.runs,
          analysis: outcome.analysis!,
          coach: coach,
        ),
      ),
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

    // The coach's card and its first item's measured values.
    await tester.tap(find.byKey(const ValueKey('place-coach')));
    await tester.pumpAndSettle();
    await shot(tester, 'session-summary');
    await tester.ensureVisible(find.byType(NextSessionCard));
    await tester.pumpAndSettle();
    await shot(tester, 'next-session');
    final why = find.byKey(const ValueKey('coachWhy 0'));
    if (why.evaluate().isNotEmpty) {
      await tester.ensureVisible(why);
      await tester.pumpAndSettle();
      await tester.tap(why);
      await tester.pumpAndSettle();
      await shot(tester, 'coach-why');
      await back(tester);
    }
    // A goal of the driver's own for the next session: the coach's main
    // focus, as Add a goal suggests it.
    final addGoal = find.byKey(const ValueKey('ownGoalsAdd'));
    if (addGoal.evaluate().isNotEmpty) {
      await tester.ensureVisible(addGoal);
      await tester.pumpAndSettle();
      await tester.tap(addGoal);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ownGoalSave')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('ownGoals')));
      await tester.pumpAndSettle();
      await shot(tester, 'own-goals');
    }
    // Before you go out: the briefing from the session summary, with the
    // goal just set.
    final briefing = find.byKey(const ValueKey('sessionSummaryBriefing'));
    await scrollIn(tester, list('dayResultsCoach'), briefing, delta: -300);
    await tester.pumpAndSettle();
    await tester.tap(briefing);
    await tester.pumpAndSettle();
    await shot(tester, 'briefing');
    await back(tester);
    // Every segment since the session before, from the session summary.
    final changes = find.byKey(const ValueKey('sessionSummaryChanges'));
    await scrollIn(tester, list('dayResultsCoach'), changes, delta: -300);
    await tester.pumpAndSettle();
    await tester.tap(changes);
    await tester.pumpAndSettle();
    await shot(tester, 'session-changes');
    await back(tester);
    // The observations, on the Overview.
    await tester.tap(find.byKey(const ValueKey('place-day')));
    await tester.pumpAndSettle();
    await scrollIn(tester, summary, find.text('Where to look next'));
    await shot(tester, 'where-to-look-next');

    await scrollIn(tester, summary, find.text('Theoretical best'));
    await shot(tester, 'theoretical-best');
    await scrollIn(tester, summary, find.text('Where the time goes'));
    await shot(tester, 'where-the-time-goes');
    await scrollIn(tester, summary, find.text('Sector times'));
    await shot(tester, 'sector-times');
    // Each corner lap to lap, the first one opened.
    await scrollIn(tester, summary, find.text('Lap to lap in each corner'));
    final variability = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('variability '),
    );
    await tester.tap(variability.first);
    await tester.pumpAndSettle();
    await toTop(tester, find.text('Lap to lap in each corner'));
    await shot(tester, 'corner-variability');
    // The best phases of the day (FET-226): closed at first, opened for the
    // shots.
    final bestPhases = find.byKey(const ValueKey('bestPhasesToggle'));
    await scrollIn(tester, summary, bestPhases);
    await tester.tap(bestPhases);
    await tester.pumpAndSettle();
    await toTop(tester, bestPhases);
    await shot(tester, 'best-phases');
    await scrollIn(tester, summary, find.text('Part by part'));
    await shot(tester, 'best-phases-parts');
    await scrollIn(tester, summary, find.text('Time losses'));
    await shot(tester, 'time-losses');
    await scrollIn(tester, summary, find.text('Consistency'));
    await shot(tester, 'consistency');
    await scrollIn(tester, summary, find.text('Where the laps vary'));
    await shot(tester, 'segment-spread');
    await scrollIn(tester, summary, find.text('Progression'));
    await shot(tester, 'progression');
    // Every lap of each session by lap number, then back to By session.
    Finder progressionView(String label) => find.descendant(
      of: find.byKey(const ValueKey('progressionView')),
      matching: find.text(label),
    );
    await tester.tap(progressionView('By lap'));
    await tester.pumpAndSettle();
    await toTop(tester, find.text('Progression'));
    await shot(tester, 'progression-by-lap');
    await tester.tap(progressionView('By session'));
    await tester.pumpAndSettle();
    await scrollIn(tester, summary, find.text('G-G envelope'));
    await shot(tester, 'gg-envelope');
    await scrollIn(tester, summary, find.text('Grip and balance'));
    // Closed at first: opened for the shot.
    await tester.tap(find.byKey(const ValueKey('gripToggle')));
    await tester.pumpAndSettle();
    await toTop(tester, find.text('Grip and balance'));
    await shot(tester, 'grip-and-balance');
    // The lap styles (FET-223): closed at first, opened with the group of
    // the day's best lap.
    await scrollIn(tester, summary, find.text('Lap styles'));
    await tester.tap(find.byKey(const ValueKey('lapStylesToggle')));
    await tester.pumpAndSettle();
    // The group of the day's best lap, opened.
    await tester.tap(find.byKey(const ValueKey('lapStylesGroup typical')));
    await tester.pumpAndSettle();
    await toTop(tester, find.text('Lap styles'));
    await shot(tester, 'lap-styles');
    await scrollIn(tester, summary, find.text('Best lap of each session'));
    await shot(tester, 'sessions-and-circuits');

    // A circuit.
    await scrollIn(tester, summary, find.text('Circuits'));
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await shot(tester, 'circuit-dialog');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A session's details.
    await scrollIn(tester, summary, find.text('Session details'), delta: -300);
    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();
    // Sample setup values to show the table filled in; cancelled below, so
    // nothing is kept.
    for (final (row, values) in [
      ('cold', ['2.1', '2.1', '2.0', '2.0']),
      ('hot', ['2.4', '2.4', '2.3', '2.3']),
    ]) {
      for (final (index, wheel) in ['fl', 'fr', 'rl', 'rr'].indexed) {
        await tester.enterText(
          find.byKey(ValueKey('sessionSetup $row $wheel')),
          values[index],
        );
      }
    }
    await tester.enterText(
      find.byKey(const ValueKey('sessionSetupTyre')),
      'Semi-slick',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shot(tester, 'session-details-dialog');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A corner's details, from the theoretical best's losses.
    final corner = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('lossRow Corner '),
    );
    await scrollIn(tester, summary, corner, delta: -300);
    await tester.tap(corner.first);
    await tester.pumpAndSettle();
    await shot(tester, 'corner-details');
    // What kind of corner it is (FET-220), further down the same sheet.
    await tester.ensureVisible(find.byKey(const ValueKey('cornerClass')));
    await tester.pumpAndSettle();
    await shot(tester, 'corner-type');
    // How it is braked into (FET-219), under the corner type.
    await tester.ensureVisible(find.byKey(const ValueKey('brakingTechnique')));
    await tester.pumpAndSettle();
    await shot(tester, 'braking-technique');
    // Beside the rail: the page's own top edge closes the details.
    await tester.tapAt(const Offset(120, 4));
    await tester.pumpAndSettle();
    // Where the corner's time came from, on another lap against the best:
    // Session 6's lap 3, then back to the best lap.
    Future<void> chooseLap(String name) async {
      final row = find.byKey(ValueKey('sectorRow $name'));
      await scrollIn(tester, summary, row);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    await chooseLap('Session 6 · LAP 3');
    await scrollIn(tester, summary, corner, delta: -300);
    await tester.tap(corner.first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('cornerPhasesTitle')));
    await tester.pumpAndSettle();
    await shot(tester, 'corner-phases');
    await tester.tapAt(const Offset(120, 4));
    await tester.pumpAndSettle();
    await chooseLap('Session 5 · LAP 2');

    // The segment editor.
    await toTop(tester, find.text('Edit segments'));
    await tester.tap(find.text('Edit segments'));
    await tester.pumpAndSettle();
    await shot(tester, 'segment-editor');
    // A boundary placed on the map.
    final firstSegment = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('segment ') &&
          w is ListTile,
    );
    await tester.tap(firstSegment.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick end')));
    await tester.pumpAndSettle();
    await shot(tester, 'segment-pick');
    // The optional review of the automatic proposals.
    await tester.tap(find.byKey(const ValueKey('pick end')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('reviewProposals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reviewProposals')));
    await tester.pumpAndSettle();
    await shot(tester, 'segment-review');
    await back(tester);

    // The day report.
    await back(tester);
    await tester.tap(find.byKey(const ValueKey('daySection-report')));
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
      matching: find.text(otherName),
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

  testWidgets('channel names', (tester) async {
    debugDisableShadows = false;
    addTearDown(() {
      channelNamesSetting.value = const {};
      listedChannelsSetting.value = const [];
    });
    await showDay(tester, _desktop, 1.5);
    // Names and stars as a driver would give the OBD channels.
    for (final (channel, name) in const [
      ('accelerator_pos-obd', 'Throttle'),
      ('brake_pos-obd', 'Brake'),
      ('rpm-obd', 'RPM'),
    ]) {
      if (!openDayContext.recordedChannels.contains(channel)) continue;
      setChannelName(channel, name);
      setChannelListed(channel, true);
    }
    await tester.tap(find.byType(SettingsButton).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('openChannelNames')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('openChannelNames')));
    await tester.pumpAndSettle();
    await shot(tester, 'channel-names');
    debugDisableShadows = true;
  });

  testWidgets('compare laps, wide', (tester) async {
    debugDisableShadows = false;
    await showDay(tester, _desktop, 1.5);
    await tester.tap(find.text('Compare two laps'));
    await tester.pumpAndSettle();
    await shot(tester, 'compare-pick-a');
    final pick = find.textContaining(otherName);
    await scrollIn(tester, find.byType(Scrollable).last, pick);
    await tester.tap(pick.last);
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

  testWidgets('reference lap, wide', (tester) async {
    debugDisableShadows = false;
    await size(tester, _desktop, 1.5);
    // The reference: the best lap's session as a file under a plain name;
    // today: the day's other sessions.
    final whole = importDay();
    final best = whole.analysis!.ranking!.bestOfDay!;
    final source = whole.runs
        .firstWhere((named) => named.run.id == best.runId)
        .run
        .sourcePath;
    String stemOf(String path) =>
        path.substring(0, path.lastIndexOf('.')).toLowerCase();
    final stem = stemOf(source);
    final reference = File(
      recordings.firstWhere(
        (path) => stemOf(path) == stem && path.toLowerCase().endsWith('.vbo'),
      ),
    ).copySync('${directory.path}/reference.vbo').path;
    final today = runDayImport((
      paths: [
        for (final path in recordings)
          if (stemOf(path) != stem) path,
      ],
      includeSubfolders: false,
    ));
    // The day kept in a profile, as a saved day is: the reference is
    // remembered there.
    final profileFolder = '${directory.path}/ReferenceProfile';
    final controller = DayResultsController(
      runs: today.runs,
      analysis: today.analysis!,
      name: 'Jastrząb',
    );
    final dayFile = profileDayPath(profileFolder, controller.eventId);
    Directory('$profileFolder/Days').createSync(recursive: true);
    await tester.runAsync(() => controller.save(dayFile));
    final library = _library(profileFolder);
    addTearDown(library.dispose);
    await tester.runAsync(library.load);
    await tester.pumpWidget(
      app(
        DayResultsPage.controller(
          controller: controller,
          pickers: _Pickers([reference]),
          library: library,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daySection-compare')));
    await tester.pumpAndSettle();
    final load = find.byKey(const ValueKey('referenceLoadFile'));
    await tester.ensureVisible(load);
    await tester.pumpAndSettle();
    await tester.tap(load);
    // The reference is read and timed on the test's thread, on the next
    // frame.
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('referenceLabel')), findsOneWidget);
    // Remembered in the profile before the picture is taken.
    await until(
      tester,
      () => referenceLapOf(controller).keepState == ReferenceKeep.saved,
    );
    await tester.pumpAndSettle();
    await toTop(tester, find.byKey(const ValueKey('referenceSection')));
    await shot(tester, 'reference-lap');
    await tester.tap(find.byKey(const ValueKey('referenceCompare')));
    await tester.pumpAndSettle();
    await shot(tester, 'reference-compare');
    debugDisableShadows = true;
  });

  testWidgets('corner analyzer from a loss', (tester) async {
    debugDisableShadows = false;
    await showDay(tester, _desktop, 1.5);
    // A single corner's loss, not a group of corners across the line.
    final open = find.descendant(
      of: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('lossRow Corner '),
      ),
      matching: find.byTooltip('Open in the Corner Analyzer'),
    );
    await scrollIn(tester, list('dayResultsSummary'), open);
    await tester.tap(open.first);
    await tester.pumpAndSettle();
    await shot(tester, 'corner-analyzer-segment');
    debugDisableShadows = true;
  });

  testWidgets('profile', (tester) async {
    debugDisableShadows = false;
    await size(tester, _desktop, 1.5);
    // The day recorded in a profile of its own, as saving it does.
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      name: 'Jastrząb',
    );
    addTearDown(controller.dispose);
    unawaited(controller.requestTheoreticalBest());
    await until(tester, () => controller.theoreticalBest != null);
    final folder = '${directory.path}/ProfileShot';
    final library = _library(folder);
    await tester.runAsync(library.load);
    // Off the fake clock: the profile's writes are real file work.
    await tester.runAsync(
      () => library.recordDay(
        eventId: controller.eventId,
        path: profileDayPath(folder, controller.eventId),
        name: controller.name,
        analysis: controller.analysis,
        recordings: {
          for (final named in controller.runs)
            named.run.id: controller.session(named.run.id),
        },
        theoreticalBest: controller.theoreticalBest,
      ),
    );
    await tester.runAsync(library.flush);
    final host = Object();
    appNavigation.attach(host, (_) {});
    appNavigation.update(
      section: AppSection.profile,
      dayAvailable: false,
      libraryAvailable: true,
    );
    addTearDown(() => appNavigation.detach(host));
    await tester.pumpWidget(app(ProfilePage(library: library)));
    await tester.pumpAndSettle();
    await shot(tester, 'profile');
    final page = list('profile');
    await scrollIn(
      tester,
      page,
      find.byKey(const ValueKey('skill paceConsistency')),
    );
    await shot(tester, 'profile-skills');
    // One day only: the day-by-day figures say a trend needs more days.
    await scrollIn(tester, page, find.byKey(const ValueKey('profileTrends')));
    await shot(tester, 'profile-trends');

    // The track's notebook, with a few example notes.
    final track = library.profile!.tracks.first;
    final corners = track.corners;
    // Off the fake clock, as the profile's writes are.
    await tester.runAsync(() async {
      library.setTrackNotebook(
        track.id,
        TrackNotebook(
          notes: 'Grippy when dry. Bumpy braking into the first corner.',
          cornerNotes: {
            if (corners.isNotEmpty)
              corners.first.id: 'Brake at the 100 m board',
          },
          toTry: [
            NotebookItem(id: 'a', text: 'Third gear through the chicane'),
            NotebookItem(id: 'b', text: 'Later turn-in, earlier throttle'),
            NotebookItem(id: 'c', text: 'Use all the kerb on exit', done: true),
          ],
        ),
      );
      await library.flush();
    });
    // Opened over the profile: the app keeps one navigator.
    unawaited(
      Navigator.of(tester.element(find.byType(ProfilePage))).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TrackNotebookPage(library: library, trackId: track.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'track-notebook');
    debugDisableShadows = true;
  });

  testWidgets('phone', (tester) async {
    debugDisableShadows = false;
    await showDay(tester, _phone, 2);
    await shot(tester, 'phone-results');
    await tester.tap(find.byKey(const ValueKey('daySection-laps')));
    await tester.pumpAndSettle();
    await shot(tester, 'phone-laps');
    final best = find.descendant(
      of: find.byKey(const ValueKey('dayResultsLaps')),
      matching: find.text(bestName),
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
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daySection-compare')));
    await tester.pumpAndSettle();
    await shot(tester, 'phone-compare');
    debugDisableShadows = true;
  });

  testWidgets('phone in sunlight', (tester) async {
    debugDisableShadows = false;
    appLookSetting.value = AppLook.sunlight;
    addTearDown(() {
      appLookSetting.value = AppLook.dark;
      debugDisableShadows = true;
    });
    await showDay(tester, _phone, 2);
    await tester.tap(find.byKey(const ValueKey('place-coach')));
    await tester.pumpAndSettle();
    await shot(tester, 'phone-sunlight-coach');
    await tester.tap(find.byKey(const ValueKey('place-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daySection-laps')));
    await tester.pumpAndSettle();
    final best = find.descendant(
      of: find.byKey(const ValueKey('dayResultsLaps')),
      matching: find.text(bestName),
    );
    await tester.scrollUntilVisible(
      best,
      200,
      scrollable: list('dayResultsLaps'),
    );
    await tester.tap(best);
    await tester.pumpAndSettle();
    await toTop(tester, find.text('Channels'));
    await shot(tester, 'phone-sunlight-lap-charts');
    debugDisableShadows = true;
  });
}
