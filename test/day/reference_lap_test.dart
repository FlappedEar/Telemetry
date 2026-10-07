// The reference lap (FET-175): a lap from outside the day, loaded from a
// file or an earlier day, named, compared with today's laps and cleared,
// never joining the day. Recordings here are synthetic (rectangleVbo,
// circuitVbo): no real data.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/recovery_store.dart';
import 'package:telemetry/day/reference_lap.dart';
import 'package:telemetry/day/reference_lap_page.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/profile_library.dart';
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

/// Counts what the day gives recovery to keep.
final class _CountingRecovery implements RecoveryStore {
  int writes = 0;

  @override
  Future<String?> path() async => null;

  @override
  Future<DayRecovery?> load() async => null;

  @override
  Future<void> write(DayRecovery recovery) async => ++writes;

  @override
  Future<void> clear() async {}
}

const _metersPerDegree = 6371000.0 * math.pi / 180.0;

/// [vbo] (a [rectangleVbo]) moved [north] metres north: another circuit
/// when far enough.
String _moved(String vbo, double north) {
  final degrees = north / _metersPerDegree;
  final lines = vbo.split('\n');
  var data = false;
  for (var i = 0; i < lines.length; ++i) {
    final line = lines[i];
    if (line.startsWith('Start ')) {
      final fields = line.split(' ');
      for (final index in [2, 4]) {
        fields[index] = (double.parse(fields[index]) + degrees).toStringAsFixed(
          8,
        );
      }
      lines[i] = fields.join(' ');
    } else if (line == '[data]') {
      data = true;
    } else if (data && line.isNotEmpty) {
      final fields = line.split(' ');
      fields[1] = (double.parse(fields[1]) + degrees).toStringAsFixed(8);
      lines[i] = fields.join(' ');
    }
  }
  return lines.join('\n');
}

/// [vbo] (a [rectangleVbo]) with its start/finish line [north] metres up the
/// start straight: the same circuit timed on another line.
String _lineMoved(String vbo, double north) {
  final degrees = north / _metersPerDegree;
  return vbo.replaceFirstMapped(
    RegExp(r'^Start (.*) start$', multiLine: true),
    (match) {
      final fields = match[1]!.split(' ');
      for (final index in [1, 3]) {
        fields[index] = (double.parse(fields[index]) + degrees).toStringAsFixed(
          8,
        );
      }
      return 'Start ${fields.join(' ')} start';
    },
  );
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
  DayResultsController today({String? unit, RecoveryStore? recovery}) {
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
      recovery: recovery,
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
    _Pickers pickers, {
    ProfileLibrary? library,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          pickers: pickers,
          library: library,
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
      final recovery = _CountingRecovery();
      final controller = today(recovery: recovery);
      // Saved, so any change to the day would show as unsaved changes.
      await tester.runAsync(
        () => controller.save('${directory.path}/today.fetproject'),
      );
      expect(controller.dirty, isFalse);
      final writes = recovery.writes;
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
      final line = referenceLine(controller)!;
      final timing = timeReferenceLaps([
        ReferenceRecording(
          label: 'friend.vbo',
          session: parseVboFile(pickers.paths.first),
        ),
      ], line);
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
      // Neither declares its speed unit and none is assumed: two loggers'
      // unlabelled speeds may be in different units, so never on one axis.
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
      // Nothing to save and nothing for recovery to keep.
      expect(controller.dirty, isFalse);
      expect(recovery.writes, writes);
    },
  );

  testWidgets('times segments of today against the reference', (tester) async {
    final controller = today();
    await tester.runAsync(controller.requestTheoreticalBest);
    final holder = ReferenceLapHolder();
    addTearDown(holder.dispose);
    await tester.runAsync(
      () => holder.load(ReferenceFile(friend()), referenceLine(controller)!),
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
    expect(find.textContaining('not timed on one of the laps'), findsNothing);
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
        referenceLine(controller)!,
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
      () => holder.load(ReferenceFile(friend()), referenceLine(controller)!),
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
    final gate = referenceLine(controller)!;
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
    await holder.load(ReferenceFile(friend()), referenceLine(controller)!);
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
        line: referenceLine(controller)!,
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
        line: referenceLine(controller)!,
      ), () => false);
      expect(missing.error, referenceDayHasNoRecordings);
      expect(backgroundRunsInline, isTrue);
    },
  );

  DayResultsController dayOf(List<String> paths) {
    final outcome = runDayImport((paths: paths, includeSubfolders: false));
    return DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
  }

  String runOf(DayResultsController controller, String name) => controller.runs
      .firstWhere((named) => named.run.sourcePath.endsWith(name))
      .run
      .id;

  testWidgets(
    "switching to another group's line asks for the reference again",
    (tester) async {
      final controller = dayOf([
        write(
          'a.vbo',
          rectangleVbo([rectangleLap(30), rectangleLap(31)], pedals: true),
        ),
        // Another circuit 5 km north, the same shape.
        write(
          'c.vbo',
          _moved(
            rectangleVbo([
              rectangleLap(29),
              rectangleLap(30),
              rectangleLap(30.5),
            ], pedals: true),
            5000,
          ),
        ),
      ]);
      final groups = [
        for (final group in controller.analysis.groups)
          if (group.resolved) group,
      ];
      expect(groups, hasLength(2));
      String groupOf(String name) => groups
          .firstWhere((group) => group.runIds.contains(runOf(controller, name)))
          .id;
      controller.chooseGroup(groupOf('a.vbo'));
      final pickers = _Pickers([friend()]);
      await openCompare(tester, controller, pickers);
      await tapKey(tester, 'referenceLoadFile');
      expect(find.byKey(const ValueKey('referenceCompare')), findsOneWidget);
      final holder = referenceLapOf(controller);
      final timed = holder.timing;

      // The other circuit's line: the reference's laps no longer apply.
      controller.chooseGroup(groupOf('c.vbo'));
      await tester.pumpAndSettle();
      expect(
        textOf(tester, 'referenceStale'),
        startsWith('Timed on another start/finish line'),
      );
      expect(find.byKey(const ValueKey('referenceCompare')), findsNothing);
      expect(find.byKey(const ValueKey('referenceChooseLap')), findsNothing);
      // Not re-timed behind the driver's back.
      expect(identical(holder.timing, timed), isTrue);

      // Loaded again on that line: the friend drove the first circuit.
      await tapKey(tester, 'referenceReload');
      expect(find.byKey(const ValueKey('referenceStale')), findsNothing);
      expect(
        textOf(tester, 'referenceProblem'),
        startsWith('Not used: this recording is from another track.'),
      );

      // Back on the first circuit, loaded again: the same lap as before.
      controller.chooseGroup(groupOf('a.vbo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('referenceStale')), findsOneWidget);
      await tapKey(tester, 'referenceReload');
      expect(holder.state, ReferenceState.ready);
      expect(holder.lap!.lapNumber, timed!.fastest!.lapNumber);

      // The comparison open while the group changes stops showing a Δ.
      await tapKey(tester, 'referenceCompare');
      expect(find.byKey(const ValueKey('referenceLapDelta')), findsOneWidget);
      controller.chooseGroup(groupOf('c.vbo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('referenceLapDelta')), findsNothing);
      expect(find.byKey(const ValueKey('referenceChart delta')), findsNothing);
      expect(
        textOf(tester, 'referenceComparisonStale'),
        startsWith('Timed on another start/finish line'),
      );
    },
  );

  testWidgets('a lap A timed on another line than the reference has no Δ', (
    tester,
  ) async {
    final controller = dayOf([
      write(
        'a.vbo',
        rectangleVbo([rectangleLap(31), rectangleLap(31.5)], pedals: true),
      ),
      // The same circuit, its start/finish line 20 m up the straight.
      write(
        'b.vbo',
        _lineMoved(
          rectangleVbo([rectangleLap(29), rectangleLap(29.5)], pedals: true),
          20,
        ),
      ),
    ]);
    final best = controller.ranking!.bestOfDay!;
    expect(best.runId, runOf(controller, 'a.vbo'));
    // A start/finish line of its own puts it in a group of its own; its
    // laps are timed on that line, not the reference's.
    expect(
      controller.analysis.groups.where((group) => group.resolved),
      hasLength(2),
    );
    final other = controller.analysis.rows.firstWhere(
      (row) =>
          row.runId == runOf(controller, 'b.vbo') &&
          row.type == LapSectionType.lap,
    );
    final holder = ReferenceLapHolder();
    addTearDown(holder.dispose);
    await tester.runAsync(
      () => holder.load(ReferenceFile(friend()), referenceLine(controller)!),
    );
    expect(holder.state, ReferenceState.ready);
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ReferenceComparisonPage(
          controller: controller,
          holder: holder,
          a: other,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('referenceLapDelta')), findsNothing);
    expect(
      textOf(tester, 'referenceComparisonStale'),
      startsWith('Lap A was timed on another start/finish line'),
    );
    expect(find.byKey(const ValueKey('referenceSegments')), findsNothing);
  });

  testWidgets(
    "an earlier day of the profile is a reference, its excluded laps marked "
    "and today's own day left out",
    (tester) async {
      final profile = Directory('${directory.path}/profile');
      Directory('${profile.path}/$profileDaysFolder')
          .createSync(recursive: true);
      // The earlier day: its fastest lap (the first, at 32 m/s) excluded.
      final earlier = dayOf([
        write(
          'earlier.vbo',
          rectangleVbo([
            rectangleLap(32),
            rectangleLap(31),
            rectangleLap(31.5),
          ], pedals: true),
        ),
      ]);
      addTearDown(earlier.dispose);
      expect(
        earlier.exclude(earlier.ranking!.bestOfDay!, 'Cut a corner'),
        isTrue,
      );
      final controller = today();
      await tester.runAsync(() async {
        await earlier.save(
          '${profile.path}/$profileDaysFolder/earlier.fetproject',
        );
        // Today is in the profile too, and never its own reference.
        await controller.save(
          '${profile.path}/$profileDaysFolder/today.fetproject',
        );
      });
      final library = ProfileLibrary(
        store: FolderProfileStore(profile.path),
        defaultCarName: 'Car',
        defaultTrackName: (number) => 'Track $number',
        background: <R>(FutureOr<R> Function() computation) async =>
            computation(),
      );
      addTearDown(library.dispose);
      await tester.runAsync(library.load);
      expect(library.available, isTrue);
      expect(
        library.profile!.days.map((day) => day.eventId),
        containsAll([earlier.eventId, controller.eventId]),
      );
      final earlierName = library.profile!.days
          .firstWhere((day) => day.eventId == earlier.eventId)
          .name;

      await openCompare(tester, controller, _Pickers([]), library: library);
      await tapKey(tester, 'referenceLoadDay');
      expect(
        find.byKey(ValueKey('referenceDay ${earlier.eventId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('referenceDay ${controller.eventId}')),
        findsNothing,
      );
      await tapKey(tester, 'referenceDay ${earlier.eventId}');
      final holder = referenceLapOf(controller);
      expect(holder.state, ReferenceState.ready);
      expect(holder.source, isA<ReferenceProfileDay>());
      // Lap 1 was excluded on its day: the fastest of the others is lap 3.
      expect(
        holder.timing!.candidates.where((lap) => lap.excluded).single.lapNumber,
        1,
      );
      expect(holder.lap!.lapNumber, 3);
      expect(holder.lap!.recordingId, earlier.runs.single.run.id);
      final label = textOf(tester, 'referenceLabel');
      expect(label, startsWith('Reference: $earlierName'));
      expect(label, contains('lap 3'));

      // The picker marks it, and it can still be chosen on purpose.
      await tapKey(tester, 'referenceChooseLap');
      expect(
        find.byKey(const ValueKey('referenceLapExcluded 0 1')),
        findsOneWidget,
      );
      expect(find.text('Excluded on its day: Cut a corner'), findsOneWidget);
      await tapKey(tester, 'referenceLap 0 1');
      expect(holder.lap!.lapNumber, 1);
      expect(holder.lap!.excluded, isTrue);
    },
  );

  testWidgets('says when only the first of several files is used', (
    tester,
  ) async {
    final controller = today();
    final pickers = _Pickers([friend(), write('second.vbo', 'x')]);
    await openCompare(tester, controller, pickers);
    await tapKey(tester, 'referenceLoadFile');
    expect(
      find.text('A reference is one recording: only friend.vbo is used.'),
      findsOneWidget,
    );
    expect(
      textOf(tester, 'referenceLabel'),
      startsWith('Reference: friend.vbo'),
    );
  });

  test('the reference lap goes with its day, and stops loading', () async {
    final controller = today();
    final holder = referenceLapOf(controller, dayId: controller.eventId);
    expect(identical(referenceLapOf(controller), holder), isTrue);
    final cancelled = Completer<void>();
    final loading = holder.load(
      ReferenceFile(friend()),
      referenceLine(controller)!,
    );
    holder.addListener(() {
      if (holder.disposed) cancelled.complete();
    });
    // The shell disposing (or discarding) the day disposes its reference.
    controller.dispose();
    expect(holder.disposed, isTrue);
    await loading;
    expect(holder.lap, isNull);
    expect(cancelled.isCompleted, isFalse);
    // A later page of a new day gets a new holder.
    final next = today();
    addTearDown(next.dispose);
    expect(identical(referenceLapOf(next), holder), isFalse);
  });
}
