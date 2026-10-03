// A session's recordings (FET-57): "Make primary" and the clock check with
// its accept or refuse, on a synthetic VBO and RCZ of one drive: no real
// data.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../../packages/telemetry_core/test/support/fusion_pair.dart';

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

    final path = '${directory.path}/Day.fetproject';
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
