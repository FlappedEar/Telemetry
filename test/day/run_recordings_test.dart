// A session's recordings (FET-57): "Make primary" and the clock check with
// its accept or refuse, on a synthetic VBO and RCZ of one drive: no real
// data.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../../packages/telemetry_core/test/support/fusion_pair.dart';

/// A fusion job run once [gate] completes.
final class _GatedTask implements FusionTask {
  _GatedTask(Future<void> gate, FusionJob job)
    : result = gate.then((_) => job(() => false));

  @override
  final Future<RunFusion?> result;

  @override
  void cancel() {}
}

Map<String, Object?> _runJson(String path) =>
    ((readDayDocument(path)['event'] as Map)['runs'] as List).single
        as Map<String, Object?>;

/// Each lap row's run, recording and times.
List<String> _rows(DayAnalysis analysis) => [
  for (final row in analysis.rows)
    '${row.runId} ${row.sourceRevision} ${row.type.label} ${row.lapNumber} '
        '${row.start} ${row.end}',
];

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('recordings'));
  tearDown(() => directory.deleteSync(recursive: true));

  Future<(DayResultsController, String)> fusedDay() async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final both = runDayImport((paths: [vbo, rcz], includeSubfolders: false));
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      alternatives: both.alternatives,
    );
    addTearDown(controller.dispose);
    await controller.fusionsSettled;
    final runId = both.runs.single.run.id;
    expect(controller.fusion(runId)!.fused, isTrue);
    return (controller, runId);
  }

  test('the clock check measures the offset and waits to be accepted or '
      'refused', () async {
    final (controller, runId) = await fusedDay();
    expect(controller.recordingsEditable(runId), isTrue);
    final fused = controller.fusion(runId)!;
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);

    final checking = controller.checkClock(runId);
    expect(controller.clockChecking(runId), isTrue);
    expect(controller.recordingsEditable(runId), isFalse);
    await checking;
    final check = controller.clockCheck(runId)!;
    expect(check.alignment!.status, alignmentAligned);
    expect(check.alignment!.offset, closeTo(0.1, 0.02));
    // Nothing changed yet.
    expect(identical(controller.fusion(runId), fused), isTrue);
    expect(controller.dirty, isFalse);

    // Refused: the RCZ is kept beside the VBO, and the session reads the
    // VBO only.
    controller.refuseClock(runId);
    expect(controller.clockCheck(runId), isNull);
    final refused = controller.fusion(runId)!;
    expect(refused.state, RunFusionState.primaryOnly);
    expect(controller.session(runId)!.channels, isNot(contains('rpm-obd')));
    expect(controller.channelSources(runId), isEmpty);
    expect(controller.dirty, isTrue);
    await controller.save(path);
    final run = _runJson(path);
    expect(
      run.containsKey('fusion'),
      isFalse,
      reason: 'as Overlays removes it',
    );
    expect((run['sources'] as Map)['telemetry'] as List, hasLength(2));

    // Checked and accepted again: combined with the measured clock.
    await controller.checkClock(runId);
    controller.acceptClock(runId);
    final accepted = controller.fusion(runId)!;
    expect(accepted.fused, isTrue);
    expect(accepted.clock.offsetSeconds, check.clock.offsetSeconds);
    expect(controller.session(runId)!.channels, contains('rpm-obd'));
    await controller.save(path);
    final decision = _runJson(path)['fusion'] as Map;
    expect(
      (decision['clock'] as Map)['offsetSeconds'],
      check.clock.offsetSeconds,
    );
  });

  test('"Don\'t combine" refuses without a check', () async {
    final (controller, runId) = await fusedDay();
    controller.refuseClock(runId);
    expect(controller.fusion(runId)!.state, RunFusionState.primaryOnly);
    expect(controller.session(runId)!.channels, isNot(contains('rpm-obd')));
  });

  test('making the RCZ primary derives the laps again from it and is saved '
      'as Overlays saves it', () async {
    final (controller, runId) = await fusedDay();
    final vbo = controller.runs.single.run;
    final rcz = controller.fusion(runId)!.alternative!;
    expect(
      controller.setTrack([runId], 'Short', TrackDirection.clockwise),
      isTrue,
    );
    await controller.requestTheoreticalBest();
    expect(controller.theoreticalBest, isNotNull);
    // Only a saved day changes its primary.
    await controller.makePrimary(runId);
    expect(controller.recordingsProblem(runId), RecordingsProblem.unsaved);
    expect(controller.runs.single.run.format, RecordingFormat.vbo);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);

    final changing = controller.makePrimary(runId);
    expect(controller.primaryChanging(runId), isTrue);
    await changing;
    await controller.fusionsSettled;
    expect(controller.primaryChanging(runId), isFalse);
    final run = controller.runs.single.run;
    expect(run.id, runId);
    expect(run.format, RecordingFormat.rcz);
    expect(run.sourceId, rcz.sourceId);
    // The laps come from the RCZ now, as a day of the RCZ alone has them.
    final alone = analyzeDay([
      DayRunInput(
        runId: runId,
        name: controller.runs.single.name,
        contentSha256: rcz.contentSha256,
        session: rcz.telemetry,
        laps: rcz.laps,
      ),
    ]);
    expect(_rows(controller.analysis), _rows(alone));
    // The layout set for the VBO is not inherited; results are calculated
    // again.
    expect(controller.analysis.manualTracks, isEmpty);
    expect(controller.theoreticalBest, isNull);
    final kept = controller.fusion(runId)!;
    expect(kept.state, RunFusionState.primaryOnly);
    expect(kept.alternative!.sourceId, vbo.sourceId);
    expect(kept.alternative!.format, RecordingFormat.vbo);
    expect(controller.session(runId), same(rcz.telemetry));
    expect(controller.dirty, isTrue);

    await controller.save(path);
    final saved = _runJson(path);
    expect(saved['primaryTelemetrySourceId'], rcz.sourceId);
    expect(saved.containsKey('fusion'), isFalse);
    expect((saved['trackConfiguration'] as Map)['sourceId'], rcz.sourceId);
    expect((saved['trackConfiguration'] as Map)['layoutId'], isNull);
    expect((saved['sources'] as Map)['telemetry'] as List, hasLength(2));

    // Opened again: the RCZ is the session, the VBO kept beside it.
    final opened = DayResultsController.opened(openDay(path));
    addTearDown(opened.dispose);
    await opened.fusionsSettled;
    expect(opened.runs.single.run.format, RecordingFormat.rcz);
    expect(opened.fusion(runId)!.state, RunFusionState.primaryOnly);
    expect(_rows(opened.analysis), _rows(controller.analysis));

    // And back: the VBO is the session again.
    await opened.makePrimary(runId);
    await opened.fusionsSettled;
    expect(opened.runs.single.run.sourceId, vbo.sourceId);
    expect(opened.analysis.rows.map((row) => row.sourceRevision).toSet(), {
      vbo.contentSha256,
    });
  });

  test('an exclusion and the comparison pair of the VBO come back when it '
      'is the primary again', () async {
    final (controller, runId) = await fusedDay();
    final vbo = controller.runs.single.run;
    final laps = controller.analysis.rows
        .where((row) => row.type == LapSectionType.lap && row.referenceEligible)
        .toList();
    expect(controller.exclude(laps[0], 'Traffic'), isTrue);
    controller.rememberComparisonPair(laps[1], laps[2]);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);

    await controller.makePrimary(runId);
    expect(controller.runs.single.run.format, RecordingFormat.rcz);
    await controller.save(path);
    final rczDay = DayResultsController.opened(openDay(path));
    addTearDown(rczDay.dispose);
    await rczDay.fusionsSettled;
    expect(rczDay.exclusions, isEmpty);
    expect(rczDay.savedComparisonPair, isNull);

    await rczDay.makePrimary(runId);
    expect(rczDay.runs.single.run.sourceId, vbo.sourceId);
    // At once, before saving: the VBO's exclusion applies again.
    expect(rczDay.exclusions, {laps[0].reference: 'Traffic'});
    await rczDay.save(path);
    final vboDay = DayResultsController.opened(openDay(path));
    addTearDown(vboDay.dispose);
    await vboDay.fusionsSettled;
    expect(vboDay.exclusions, {laps[0].reference: 'Traffic'});
    final pair = vboDay.savedComparisonPair!;
    expect(
      [pair.$1.reference, pair.$2.reference],
      [laps[1].reference, laps[2].reference],
    );
  });

  test('a clock check waiting for the user no longer applies once a rule '
      'changed', () async {
    final (controller, runId) = await fusedDay();
    await controller.checkClock(runId);
    expect(controller.clockCheck(runId), isNotNull);
    await controller.setFusionRule(runId, 'sats', FusionRule.preferAlternative);
    expect(controller.clockCheck(runId), isNull);
    controller.acceptClock(runId);
    expect(
      controller.fusion(runId)!.ruleOf('sats'),
      FusionRule.preferAlternative,
      reason: 'the rule change is not reverted',
    );
  });

  test('a clock check waiting for the user no longer applies once another '
      'RCZ is added', () async {
    final (controller, runId) = await fusedDay();
    final old = controller.fusion(runId)!.alternative!;
    controller.refuseClock(runId);
    await controller.checkClock(runId);
    expect(controller.clockCheck(runId), isNotNull);
    // Another RCZ of the same drive, its satellite counts other.
    final other = Directory('${directory.path}/other')..createSync();
    final (_, rcz) = writeFusionPair(
      other.path,
      satellites: true,
      satelliteDifference: 7,
    );
    final addition = controller.addRecordings([rcz]);
    // Not while recordings are added, nor after: the check was of the RCZ
    // the addition replaces.
    controller.acceptClock(runId);
    expect(controller.fusion(runId)!.state, RunFusionState.primaryOnly);
    await addition;
    expect(controller.clockCheck(runId), isNull);
    controller.acceptClock(runId);
    await controller.fusionsSettled;
    final fusion = controller.fusion(runId)!;
    expect(fusion.alternative!.contentSha256, isNot(old.contentSha256));
    expect(fusion.fused, isTrue);
  });

  test('making a primary whose file changed or is gone changes nothing and '
      'says why', () async {
    final (controller, runId) = await fusedDay();
    final rcz = controller.fusion(runId)!.alternative!;
    await controller.save('${directory.path}/Day.fetproject');
    final file = File(rcz.sourcePath);
    final bytes = file.readAsBytesSync();
    file.writeAsBytesSync([...bytes.reversed]);
    await controller.makePrimary(runId);
    expect(controller.runs.single.run.format, RecordingFormat.vbo);
    expect(
      controller.recordingsProblem(runId),
      RecordingsProblem.primaryChanged,
    );
    file.deleteSync();
    await controller.makePrimary(runId);
    expect(controller.runs.single.run.format, RecordingFormat.vbo);
    expect(
      controller.recordingsProblem(runId),
      RecordingsProblem.primaryMissing,
    );
    file.writeAsBytesSync(bytes);
    await controller.makePrimary(runId);
    expect(controller.recordingsProblem(runId), isNull);
    expect(controller.runs.single.run.format, RecordingFormat.rcz);
  });

  test('clock checks and primary changes wait for a free slot', () async {
    final previous = DayResultsController.fusionSlots;
    DayResultsController.fusionSlots = 1;
    addTearDown(() => DayResultsController.fusionSlots = previous);
    final (vbo1, rcz1) = writeFusionPair(directory.path, name: 'first');
    final (vbo2, rcz2) = writeFusionPair(
      directory.path,
      name: 'second',
      speeds: const [31, 28, 30, 27, 33, 29],
    );
    final day = runDayImport((
      paths: [vbo1, rcz1, vbo2, rcz2],
      includeSubfolders: false,
    ));
    // Once [hold] is set, fusion jobs wait until released.
    final held = <Completer<void>>[];
    var hold = false;
    final controller = DayResultsController(
      runs: day.runs,
      analysis: day.analysis!,
      alternatives: day.alternatives,
      fusionRunner: (job) {
        final gate = Completer<void>();
        if (hold) {
          held.add(gate);
        } else {
          gate.complete();
        }
        return _GatedTask(gate.future, job);
      },
    );
    addTearDown(controller.dispose);
    await controller.fusionsSettled;
    expect(
      [for (final named in day.runs) controller.fusion(named.run.id)?.fused],
      [true, true],
    );
    await controller.save('${directory.path}/Day.fetproject');
    hold = true;
    final [first, second] = [for (final named in day.runs) named.run.id];
    final check = controller.checkClock(first);
    final change = controller.makePrimary(second);
    expect(controller.primaryChanging(second), isTrue);
    await pumpEventQueue();
    // The clock check holds the only slot: the primary change waits.
    expect(held, hasLength(1));
    expect(controller.runs.last.run.format, RecordingFormat.vbo);
    // Retry, Find recordings and leaving the day wait meanwhile.
    expect(controller.recordingsBusy, isTrue);
    held.single.complete();
    await Future.wait([check, change]);
    expect(controller.recordingsBusy, isFalse);
    expect(controller.clockCheck(first), isNotNull);
    expect(controller.runs.last.run.format, RecordingFormat.rcz);
  });

  test('B1: a lap included again before the switch is not excluded after '
      'it', () async {
    final (controller, runId) = await fusedDay();
    final lap = controller.analysis.rows.firstWhere(
      (row) => row.type == LapSectionType.lap && row.referenceEligible,
    );
    expect(controller.exclude(lap, 'Traffic'), isTrue);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    controller.include(lap);
    // Unsaved: refused, nothing changes.
    await controller.makePrimary(runId);
    expect(controller.recordingsProblem(runId), RecordingsProblem.unsaved);
    expect(controller.runs.single.run.format, RecordingFormat.vbo);
    await controller.save(path);
    await controller.makePrimary(runId);
    expect(controller.runs.single.run.format, RecordingFormat.rcz);
    await controller.save(path);
    await controller.makePrimary(runId);
    expect(controller.exclusions, isEmpty);
    await controller.save(path);
    expect(
      (readDayDocument(path)['event'] as Map).containsKey('lapExclusions'),
      isFalse,
    );
    final reopened = DayResultsController.opened(openDay(path));
    addTearDown(reopened.dispose);
    expect(reopened.exclusions, isEmpty);
  });

  test('B2: with a layout set on the VBO, its exclusion no longer applies '
      'after switching back, in the session as in the file', () async {
    final (controller, runId) = await fusedDay();
    expect(
      controller.setTrack([runId], 'Short', TrackDirection.clockwise),
      isTrue,
    );
    final laps = controller.analysis.rows
        .where((row) => row.type == LapSectionType.lap && row.referenceEligible)
        .toList();
    expect(controller.exclude(laps[0], 'Traffic'), isTrue);
    controller.rememberComparisonPair(laps[1], laps[2]);
    // An unsaved choice is never written with another lap derivation: the
    // switch waits for the save.
    await controller.makePrimary(runId);
    expect(controller.recordingsProblem(runId), RecordingsProblem.unsaved);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    final stored = (readDayDocument(path)['event'] as Map)['lapExclusions'];

    await controller.makePrimary(runId);
    expect(controller.exclusions, isEmpty);
    await controller.save(path);
    // The VBO's exclusion and pair are kept as stored.
    final event = readDayDocument(path)['event'] as Map;
    expect(event['lapExclusions'], stored);
    expect(
      ((event['analysisDecisions'] as Map)['comparisonSlots'] as List).first,
      isNotNull,
    );

    // Back on the VBO the layout is gone: its laps are named with another
    // lap derivation, so the exclusion does not apply, here or reopened.
    await controller.makePrimary(runId);
    expect(controller.runs.single.run.format, RecordingFormat.vbo);
    expect(controller.analysis.manualTracks, isEmpty);
    expect(controller.exclusions, isEmpty);
    await controller.save(path);
    final reopened = DayResultsController.opened(openDay(path));
    addTearDown(reopened.dispose);
    expect(reopened.exclusions, controller.exclusions);
    expect(reopened.savedComparisonPair, isNull);
  });

  test(
    'closing the day while a primary change waits for a slot stops it',
    () async {
      final previous = DayResultsController.fusionSlots;
      DayResultsController.fusionSlots = 1;
      addTearDown(() => DayResultsController.fusionSlots = previous);
      final (vbo1, rcz1) = writeFusionPair(directory.path, name: 'first');
      final (vbo2, rcz2) = writeFusionPair(
        directory.path,
        name: 'second',
        speeds: const [31, 28, 30, 27, 33, 29],
      );
      final day = runDayImport((
        paths: [vbo1, rcz1, vbo2, rcz2],
        includeSubfolders: false,
      ));
      var hold = false;
      final controller = DayResultsController(
        runs: day.runs,
        analysis: day.analysis!,
        alternatives: day.alternatives,
        fusionRunner: (job) =>
            _GatedTask(hold ? Completer<void>().future : Future.value(), job),
      );
      await controller.fusionsSettled;
      await controller.save('${directory.path}/Day.fetproject');
      hold = true;
      final [first, second] = [for (final named in day.runs) named.run.id];
      final check = controller.checkClock(first);
      final change = controller.makePrimary(second);
      await pumpEventQueue();
      expect(controller.primaryChanging(second), isTrue);
      controller.dispose();
      // Both end without a result instead of waiting forever.
      await change.timeout(const Duration(seconds: 5));
      expect(controller.runs.last.run.format, RecordingFormat.vbo);
      unawaited(check);
    },
  );

  testWidgets('the session shows its recordings\' actions, the clock check '
      'and the primary change', (tester) async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final both = runDayImport((paths: [vbo, rcz], includeSubfolders: false));
    final runId = both.runs.single.run.id;
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      alternatives: both.alternatives,
    );
    await tester.binding.setSurfaceSize(const Size(400, 8000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Combined with its RCZ: 1 channel added'), findsOneWidget);
    expect(find.byKey(ValueKey('dontCombine $runId')), findsOneWidget);
    expect(find.text('Make RCZ primary'), findsOneWidget);

    await tester.ensureVisible(find.text('Check clock'));
    await tester.tap(find.text('Check clock'));
    await tester.pumpAndSettle();
    expect(find.text('The clocks line up.'), findsOneWidget);
    expect(
      find.textContaining(
        'Measured from the speed traces: VBO time = RCZ time +0.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('clockReopenNote $runId')), findsOneWidget);
    await tester.ensureVisible(find.text('Refuse'));
    await tester.tap(find.text('Refuse'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Its RCZ is kept beside it and not combined until the day is opened '
        'again',
      ),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('dontCombine $runId')), findsNothing);

    // The refusal is unsaved: the primary changes only on a saved day.
    await tester.ensureVisible(find.text('Make RCZ primary'));
    await tester.tap(find.text('Make RCZ primary'));
    await tester.pumpAndSettle();
    expect(
      find.text('Save the day before changing the primary recording.'),
      findsOneWidget,
    );
    expect(controller.runs.single.run.format, RecordingFormat.vbo);
    await tester.runAsync(
      () => controller.save('${directory.path}/Day.fetproject'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Make RCZ primary'));
    await tester.tap(find.text('Make RCZ primary'));
    await tester.pumpAndSettle();
    expect(controller.runs.single.run.format, RecordingFormat.rcz);
    expect(
      find.text('Its VBO is kept beside it and not combined'),
      findsOneWidget,
    );
    expect(find.text('Make VBO primary'), findsOneWidget);

    // The page disposes the day's controller.
    await tester.pumpWidget(const SizedBox());
  });
}
