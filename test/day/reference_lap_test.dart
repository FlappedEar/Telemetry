// The reference lap (FET-175): a lap from outside the day, loaded from a
// file or an earlier day, named, compared with today's laps and cleared,
// never joining the day. Recordings here are synthetic (rectangleVbo,
// circuitVbo): no real data.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/reference_lap.dart';
import 'package:telemetry/day/reference_lap_page.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../../packages/telemetry_core/test/support/circuit_vbo.dart';
import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

final class _Pickers implements RecordingPickers {
  _Pickers(this.paths);

  List<String> paths;

  @override
  Future<List<String>> pickRecordings() async => paths;

  @override
  Future<String?> pickFolder() async => null;
}

/// [vbo] without its own start/finish line, or with a `[header]` line
/// declaring its speed unit.
String _without(String vbo, {String? unit}) {
  var text = vbo.replaceFirst(RegExp(r'\[laptiming\]\n[^\n]*\n'), '');
  if (unit != null) {
    text = text.replaceFirst('[header]\n', '[header]\nvelocity $unit\n');
  }
  return text;
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('reference'));
  tearDown(() {
    speedUnitSetting.value = SpeedUnitSetting.automatic;
    deleteTemporaryDirectory(directory);
  });

  String write(String name, String text) {
    final path = '${directory.path}/$name';
    File(path).writeAsStringSync(text);
    return path;
  }

  // Today: two sessions, the first declaring its speed [unit] when given.
  DayResultsController today({String? unit}) {
    var first = rectangleVbo([
      rectangleLap(30, 50, 120, 20),
      rectangleLap(31, 300, 400, 25),
      rectangleLap(30),
    ], pedals: true);
    if (unit != null) {
      first = first.replaceFirst('[header]\n', '[header]\nvelocity $unit\n');
    }
    final paths = [
      write('a.vbo', first),
      write(
        'b.vbo',
        rectangleVbo([
          rectangleLap(29),
          rectangleLap(30.5, 700, 780, 20),
        ], pedals: true),
      ),
    ];
    final outcome = runDayImport((paths: paths, includeSubfolders: false));
    return DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
  }

  // A friend's recording: three laps, the second slow from 100 to 200 m,
  // without a start/finish line of its own.
  String friend({String? unit}) => write(
    'friend.vbo',
    _without(
      rectangleVbo([
        rectangleLap(32),
        rectangleLap(32, 100, 200, 20),
        rectangleLap(31.5),
      ], pedals: true),
      unit: unit,
    ),
  );

  Future<void> openCompare(
    WidgetTester tester,
    DayResultsController controller,
    _Pickers pickers,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          pickers: pickers,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('daySection-compare')));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets(
    'loads a reference from a file, names it, compares and clears it, '
    'and the day never changes',
    (tester) async {
      final controller = today();
      final analysis = controller.analysis;
      final best = controller.ranking!.bestOfDay!;
      final candidates = controller.comparisonCandidates().length;
      final pickers = _Pickers([friend()]);
      await openCompare(tester, controller, pickers);
      expect(find.byKey(const ValueKey('referenceSection')), findsOneWidget);
      expect(find.byKey(const ValueKey('referenceLabel')), findsNothing);
      // No profile here: only a file can be loaded.
      expect(find.byKey(const ValueKey('referenceLoadDay')), findsNothing);

      await tapKey(tester, 'referenceLoadFile');
      // The fastest of its laps on today's line: the first, at 32 m/s.
      final gate = referenceGate(controller)!;
      final timing = timeReferenceLaps([
        ReferenceRecording(
          label: 'friend.vbo',
          session: parseVboFile(pickers.paths.first),
        ),
      ], gate);
      final fastest = timing.fastest!;
      expect(fastest.lapNumber, 1);
      expect(
        textOf(tester, 'referenceLabel'),
        'Reference: friend.vbo, lap 1, '
        '${displayTime(fastest.durationSeconds)}',
      );

      // Its slow second lap instead.
      await tapKey(tester, 'referenceChooseLap');
      expect(find.text('Suggested: the fastest'), findsOneWidget);
      await tapKey(tester, 'referenceLap 0 2');
      final slow = timing.candidates.firstWhere((lap) => lap.lapNumber == 2);
      final label =
          'Reference: friend.vbo, lap 2, ${displayTime(slow.durationSeconds)}';
      expect(textOf(tester, 'referenceLabel'), label);

      // Compared with today's best: the same name, Δ today − reference.
      await tapKey(tester, 'referenceCompare');
      expect(find.byType(ReferenceComparisonPage), findsOneWidget);
      expect(textOf(tester, 'referenceComparisonLabel'), label);
      expect(
        textOf(tester, 'referenceLapDelta'),
        'Lap Δ ${displayDelta(best.durationSeconds - slow.durationSeconds)}',
      );
      expect(
        find.byKey(const ValueKey('referenceChart delta')),
        findsOneWidget,
      );
      // One speed chart: both declare nothing and nothing is assumed, so
      // both read without a unit, and say so.
      expect(
        find.byKey(const ValueKey('referenceChart speed')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Units: A no unit · reference no unit'),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey('referenceChart throttle')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('referenceSegments')), findsOneWidget);

      // Cleared from the comparison's day page: the page says so.
      final page = tester.state<State>(find.byType(ReferenceComparisonPage));
      final holder = (page.widget as ReferenceComparisonPage).holder;
      holder.clear();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('referenceComparisonGone')),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('referenceLabel')), findsNothing);
      expect(find.byKey(const ValueKey('referenceClear')), findsNothing);

      // Loaded again and cleared with the button.
      await tapKey(tester, 'referenceLoadFile');
      expect(find.byKey(const ValueKey('referenceLabel')), findsOneWidget);
      await tapKey(tester, 'referenceClear');
      expect(find.byKey(const ValueKey('referenceLabel')), findsNothing);

      // The reference never joined the day.
      expect(identical(controller.analysis, analysis), isTrue);
      expect(controller.ranking!.bestOfDay!.reference, best.reference);
      expect(controller.comparisonCandidates(), hasLength(candidates));
      expect(
        controller.runs.map((run) => run.run.sourcePath),
        isNot(contains(pickers.paths.first)),
      );
    },
  );

  testWidgets('times segments of today against the reference', (tester) async {
    final controller = today();
    await tester.runAsync(controller.requestTheoreticalBest);
    final holder = ReferenceLapHolder();
    addTearDown(holder.dispose);
    await tester.runAsync(
      () => holder.load(ReferenceFile(friend()), referenceGate(controller)!),
    );
    holder.choose(holder.timing!.candidates[1]);
    final best = controller.ranking!.bestOfDay!;
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ReferenceComparisonPage(
          controller: controller,
          holder: holder,
          a: best,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final segmentation = controller.segmentationFor(best);
    expect(segmentation.shared, isNotNull);
    final segments = comparisonApprovedSegments(segmentation.shared);
    expect(segments, isNotEmpty);
    for (final segment in segments) {
      expect(
        find.byKey(ValueKey('referenceSegment ${segment.id}')),
        findsOneWidget,
      );
    }
    // The reference's slow stretch is where today's lap gains: a negative
    // Δ (green), never a missing one.
    expect(find.textContaining('not timed on both laps'), findsNothing);
    expect(find.textContaining(RegExp(r'^−\d')), findsWidgets);
  });

  testWidgets('refuses a recording from another track, saying why', (
    tester,
  ) async {
    final controller = today();
    final pickers = _Pickers([
      write('elsewhere.vbo', circuitVbo([30, 31], latitude: 53.0)),
    ]);
    await openCompare(tester, controller, pickers);
    await tapKey(tester, 'referenceLoadFile');
    expect(find.byKey(const ValueKey('referenceLabel')), findsNothing);
    expect(
      textOf(tester, 'referenceProblem'),
      startsWith('Not used: this recording is from another track.'),
    );
    expect(textOf(tester, 'referenceProblem'), contains('km'));
    expect(find.byKey(const ValueKey('referenceCompare')), findsNothing);
    expect(find.byKey(const ValueKey('referenceClear')), findsOneWidget);
  });

  testWidgets('a file that is not a recording says why', (tester) async {
    final controller = today();
    final pickers = _Pickers([write('notes.txt', 'hello')]);
    await openCompare(tester, controller, pickers);
    await tapKey(tester, 'referenceLoadFile');
    expect(
      textOf(tester, 'referenceProblem'),
      startsWith('The reference could not be read: '),
    );
  });

  testWidgets('never pools speeds in different units', (tester) async {
    // Today declares km/h; the reference declares mph.
    final controller = today(unit: 'kmh');
    final holder = ReferenceLapHolder();
    addTearDown(holder.dispose);
    await tester.runAsync(
      () => holder.load(
        ReferenceFile(friend(unit: 'mph')),
        referenceGate(controller)!,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ReferenceComparisonPage(
          controller: controller,
          holder: holder,
          a: controller.ranking!.bestOfDay!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('referenceChart speed')), findsNothing);
    expect(
      find.byKey(const ValueKey('referenceChart speed A')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('referenceChart speed reference')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Different units: shown apart, never subtracted.'),
      findsWidgets,
    );
    expect(find.textContaining('A km/h · reference mph'), findsWidgets);
  });

  testWidgets('an undeclared unit is assumed, and says so', (tester) async {
    speedUnitSetting.value = SpeedUnitSetting.kilometresPerHour;
    final controller = today(unit: 'kmh');
    final holder = ReferenceLapHolder();
    addTearDown(holder.dispose);
    await tester.runAsync(
      () => holder.load(ReferenceFile(friend()), referenceGate(controller)!),
    );
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ReferenceComparisonPage(
          controller: controller,
          holder: holder,
          a: controller.ranking!.bestOfDay!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('referenceChart speed')), findsOneWidget);
    expect(
      find.textContaining('A km/h · reference km/h (assumed)'),
      findsWidgets,
    );
  });

  test('a stale load never replaces a newer one', () async {
    final controller = today();
    final gate = referenceGate(controller)!;
    final first = friend();
    final second = write('other.vbo', File(first).readAsStringSync());
    final holder = ReferenceLapHolder();
    addTearDown(holder.dispose);
    final older = holder.load(ReferenceFile(first), gate);
    final newer = holder.load(ReferenceFile(second), gate);
    await Future.wait([older, newer]);
    expect(holder.state, ReferenceState.ready);
    expect(holder.source, ReferenceFile(second));
    // Cleared while loading: nothing comes back.
    final cleared = holder.load(ReferenceFile(first), gate);
    holder.clear();
    await cleared;
    expect(holder.state, ReferenceState.none);
    expect(holder.lap, isNull);
  });

  test('a reference is read and timed in its own isolate', () async {
    debugRunInIsolate = true;
    addTearDown(() => debugRunInIsolate = false);
    final controller = today();
    final holder = ReferenceLapHolder();
    addTearDown(holder.dispose);
    await holder.load(ReferenceFile(friend()), referenceGate(controller)!);
    expect(holder.state, ReferenceState.ready);
    expect(holder.lap!.lapNumber, 1);
    expect(holder.session, isNotNull);
  });

  test(
    'an earlier day saved in a file gives its sessions as references',
    () async {
      final controller = today();
      final saved = '${directory.path}/earlier.fetproject';
      await controller.save(saved);
      final loaded = loadReference((
        source: ReferenceProfileDay(
          path: saved,
          eventId: controller.eventId,
          dayName: 'Earlier day',
        ),
        gate: referenceGate(controller)!,
      ), () => false);
      final timing = loaded.timing!;
      expect(timing.usable, isTrue);
      expect(timing.recordings.map((recording) => recording.label), [
        'Session 1',
        'Session 2',
      ]);
      // The day's own best, on the same line.
      expect(
        timing.fastest!.durationSeconds,
        closeTo(controller.ranking!.bestOfDay!.durationSeconds, 0.001),
      );

      // Its recordings gone: said, not shown as an empty reference.
      for (final file in directory.listSync()) {
        if (file.path.endsWith('.vbo')) file.deleteSync();
      }
      final missing = loadReference((
        source: ReferenceProfileDay(
          path: saved,
          eventId: controller.eventId,
          dayName: 'Earlier day',
        ),
        gate: referenceGate(controller)!,
      ), () => false);
      expect(missing.error, referenceDayHasNoRecordings);
      expect(backgroundRunsInline, isTrue);
    },
  );
}
