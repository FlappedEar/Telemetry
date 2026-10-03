// A session's VBO and RCZ combined without a review (FET-51), on synthetic
// recordings of one drive: no real data.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/fusion_panel.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../../packages/telemetry_core/test/support/fusion_pair.dart';

/// Prepares additions on the test's own thread.
final class _SyncAppender implements DayAppender {
  @override
  DayAppendJob start(DayAppendRequest request, void Function(int, int) _) =>
      _SyncJob(runDayAppend(request));
}

final class _SyncJob implements DayAppendJob {
  _SyncJob(DayAppendOutcome outcome) : result = Future.value(outcome);

  @override
  final Future<DayAppendOutcome> result;

  @override
  void cancel() {}
}

/// What a lap row shows and is ranked by.
List<Object> _rows(DayResultsController controller) => [
  for (final row in controller.analysis.rows)
    (
      row.reference,
      row.displayName,
      row.start,
      row.end,
      row.durationSeconds,
      controller.issues(row).join(","),
      controller.isBestOfDay(row),
      controller.isBestOfRun(row),
    ),
  controller.ranking?.bestOfDay?.reference ?? 'no best lap',
];

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('fusion'));
  tearDown(() => directory.deleteSync(recursive: true));

  DayImportOutcome importDay(List<String> paths) =>
      runDayImport((paths: paths, includeSubfolders: false));

  test(
    'the RCZ adds its channels and never changes laps or rankings',
    () async {
      final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
      final alone = importDay([vbo]);
      final both = importDay([vbo, rcz]);
      expect(both.runs, hasLength(1));
      expect(
        both.steps.map((step) => step.name),
        contains('Align and combine VBO and RCZ'),
      );
      final runId = both.runs.single.run.id;
      final plain = DayResultsController(
        runs: alone.runs,
        analysis: alone.analysis!,
      );
      final fused = DayResultsController(
        runs: both.runs,
        analysis: both.analysis!,
        fusions: both.fusions,
      );
      addTearDown(plain.dispose);
      addTearDown(fused.dispose);

      final fusion = fused.fusion(runId)!;
      expect(fusion.fused, isTrue);
      expect(fused.session(runId)!.channels, contains('rpm-obd'));
      expect(plain.session(runId)!.channels, isNot(contains('rpm-obd')));
      expect(fused.channelSource(runId, 'rpm-obd'), 'RCZ');
      expect(fused.channelSource(runId, 'velocity'), '');
      // The comparison and the channel summaries read the fused channels.
      final laps = fused.comparisonCandidates();
      expect(
        fused.comparison(laps[0], laps[1])!.chartChannels,
        contains('rpm-obd'),
      );
      // Lap rows, timing and ranking are the VBO's alone.
      expect(_rows(fused), _rows(plain));

      // Using the RCZ for the channel they disagree on changes no lap either.
      expect([for (final channel in fusion.conflicts) channel.key], ['sats']);
      await fused.setFusionRule(runId, 'sats', FusionRule.preferAlternative);
      expect(fused.fusion(runId)!.ruleOf('sats'), FusionRule.preferAlternative);
      expect(fused.channelSource(runId, 'sats'), 'RCZ');
      expect(fused.dirty, isTrue);
      expect(_rows(fused), _rows(plain));
      await fused.requestTheoreticalBest();
      await plain.requestTheoreticalBest();
      // So is the theoretical best, timed from the VBO.
      final timed = fused.theoreticalBest!.summary!;
      expect(timed.totalSeconds, isNotNull);
      expect(timed.totalSeconds, plain.theoreticalBest!.summary!.totalSeconds);
      expect(
        timed.differenceSeconds,
        plain.theoreticalBest!.summary!.differenceSeconds,
      );
    },
  );

  test(
    'saves the decision and opens the day with it, without aligning again',
    () async {
      final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
      final both = importDay([vbo, rcz]);
      final runId = both.runs.single.run.id;
      final controller = DayResultsController(
        runs: both.runs,
        analysis: both.analysis!,
        fusions: both.fusions,
      );
      addTearDown(controller.dispose);
      await controller.setFusionRule(runId, 'sats', FusionRule.fillGaps);
      final path = '${directory.path}/Day.fetproject';
      // The writer validates the document as FlappedEar Overlays does.
      await controller.save(path);
      final run =
          ((readDayDocument(path)['event'] as Map)['runs'] as List).single
              as Map;
      final decision = run['fusion'] as Map;
      expect(
        decision['alternativeSourceId'],
        controller.fusion(runId)!.alternativeSourceId,
      );
      expect(decision['rules'], [
        {'key': 'sats', 'rule': 'fillGaps'},
      ]);

      final opened = DayResultsController.opened(openDay(path));
      addTearDown(opened.dispose);
      expect(opened.dirty, isFalse);
      final applied = opened.fusion(runId)!;
      expect(applied.fromDocument, isTrue);
      expect(applied.ruleOf('sats'), FusionRule.fillGaps);
      expect(opened.channelSource(runId, 'rpm-obd'), 'RCZ');
      expect(_rows(opened), _rows(controller));
    },
  );

  test('an RCZ added to its VBO session is combined with it', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final first = importDay([vbo]);
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    addTearDown(controller.dispose);
    final before = _rows(controller);
    final addition = await controller.addRecordings([rcz]);
    expect(addition.added, isEmpty);
    expect(addition.combined, ['Session 1']);
    expect(addition.notes, [
      'drive.rcz: the same drive as Session 1 in the other format; kept as its '
          'alternative source.',
    ]);
    final runId = first.runs.single.run.id;
    expect(controller.fusion(runId)!.fused, isTrue);
    expect(controller.session(runId)!.channels, contains('rpm-obd'));
    expect(controller.dirty, isTrue);
    expect(_rows(controller), before);
  });

  test('a VBO and RCZ added together become one fused session', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, name: 'later');
    final firstDir = Directory('${directory.path}/first')..createSync();
    final (earlier, _) = writeFusionPair(
      firstDir.path,
      speeds: const [31, 26, 30, 28, 33, 27, 29, 25, 32, 30],
    );
    final first = importDay([earlier]);
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    addTearDown(controller.dispose);
    final addition = await controller.addRecordings([vbo, rcz]);
    expect(addition.added, ['Session 2']);
    final added = controller.runs.last.run;
    expect(added.format, RecordingFormat.vbo);
    expect(controller.fusion(added.id)!.fused, isTrue);
    expect(controller.channelSource(added.id, 'rpm-obd'), 'RCZ');
  });

  testWidgets('shows what the RCZ added and lets a conflict be decided', (
    tester,
  ) async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final both = importDay([vbo, rcz]);
    final runId = both.runs.single.run.id;
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      fusions: both.fusions,
    );
    final before = _rows(controller);
    await tester.binding.setSurfaceSize(const Size(400, 8000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Combined with its RCZ: 1 channel added'), findsOneWidget);
    expect(find.text('sats: the VBO and the RCZ disagree'), findsOneWidget);
    await tester.ensureVisible(find.text('Use RCZ'));
    await tester.tap(find.text('Use RCZ'));
    await tester.pumpAndSettle();
    expect(
      controller.fusion(runId)!.ruleOf('sats'),
      FusionRule.preferAlternative,
    );
    expect(_rows(controller), before);

    // The lap's charts say which channel came from the RCZ.
    final lap = controller.analysis.rows.firstWhere(
      (row) => row.type == LapSectionType.lap,
    );
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: lap),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('addChartChannel')));
    await tester.pumpAndSettle();
    expect(find.text('rpm-obd · from RCZ'), findsOneWidget);
    await tester.tap(find.text('rpm-obd · from RCZ'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lapChart rpm-obd')),
        matching: find.text('from RCZ'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('says in one line why an RCZ was not combined', (tester) async {
    final (vbo, rcz) = writeFusionPair(directory.path);
    final plan = prepareTelemetryImport([vbo, rcz]);
    final primary = plan.runs.firstWhere(
      (run) => run.format == RecordingFormat.vbo,
    );
    final alternative = plan.runs.firstWhere(
      (run) => run.format == RecordingFormat.rcz,
    );
    // Recorded on its own clock 40 s later than it says: the declared clocks
    // disagree with the speed traces.
    final shifted = TelemetryRunProposal(
      id: alternative.id,
      sourceId: alternative.sourceId,
      sourcePath: alternative.sourcePath,
      format: alternative.format,
      contentSha256: alternative.contentSha256,
      laps: alternative.laps,
      telemetry: TelemetrySession(
        duration: alternative.telemetry.duration,
        startTime: alternative.telemetry.startTime,
        metadata: {
          ...alternative.telemetry.metadata,
          'firstTimestampMilliseconds': '${fusionPairOrigin + 40100}',
        },
        channels: alternative.telemetry.channels,
        aliases: alternative.telemetry.aliases,
        warnings: alternative.telemetry.warnings,
        timingGates: alternative.telemetry.timingGates,
        sampleCount: alternative.telemetry.sampleCount,
      ),
    );
    final fusion = fuseRunRecordings(primary, shifted);
    expect(fusion.fused, isFalse);
    expect(fusion.reason, 'declaredClockDisagrees');
    final both = importDay([vbo]);
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      fusions: {primary.id: fusion},
    );
    await tester.binding.setSurfaceSize(const Size(400, 8000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Not combined with its RCZ: their clocks disagree with their speed traces',
      ),
      findsOneWidget,
    );
    expect(
      controller.session(primary.id)!.channels,
      isNot(contains('rpm-obd')),
    );
  });

  for (final scale in const [1.0, 1.3]) {
    testWidgets(
      'the choice fits a small phone with 48 dp targets at text x$scale',
      (tester) async {
        final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
        final both = importDay([vbo, rcz]);
        final runId = both.runs.single.run.id;
        final controller = DayResultsController(
          runs: both.runs,
          analysis: both.analysis!,
          fusions: both.fusions,
        );
        addTearDown(controller.dispose);
        await tester.binding.setSurfaceSize(const Size(360, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          TelemetryApp(
            home: MediaQuery.withClampedTextScaling(
              minScaleFactor: scale,
              maxScaleFactor: scale,
              child: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SessionFusion(controller: controller, runId: runId),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Keep VBO'), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      },
    );
  }
}
