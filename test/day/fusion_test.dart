// A session's VBO and RCZ combined without a review (FET-51), on synthetic
// recordings of one drive: no real data.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/document_pickers.dart';
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

/// Holds each background fusion until the test lets it run.
final class _HeldFusions {
  final jobs = <_HeldTask>[];

  FusionTask call(FusionJob job) {
    final task = _HeldTask(job);
    jobs.add(task);
    return task;
  }

  /// Runs the [index]th job held; [settle] lets its result be applied
  /// (widget tests pump instead).
  Future<void> release(int index, {bool settle = true}) async {
    jobs[index].run();
    if (settle) await pumpEventQueue();
  }
}

final class _HeldTask implements FusionTask {
  _HeldTask(this.job);

  final FusionJob job;
  final _done = Completer<RunFusion?>();
  bool cancelled = false;

  void run() {
    if (_done.isCompleted) return;
    try {
      _done.complete(job(() => cancelled));
    } on Object catch (error) {
      _done.completeError(error);
    }
  }

  @override
  Future<RunFusion?> get result => _done.future;

  @override
  void cancel() {
    cancelled = true;
    if (!_done.isCompleted) _done.completeError(const OperationCancelled());
  }
}

/// Folder pickers that answer [folder].
final class _Documents implements DocumentPickers {
  _Documents(this.folder);

  final String folder;

  @override
  Future<String?> saveLocation(String name) async => null;

  @override
  Future<String?> pickDocument() async => null;

  @override
  Future<String?> pickFolder() async => folder;

  @override
  Future<List<String>> savedDays() async => const [];
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

TelemetrySession _session(
  TelemetrySession session,
  Map<String, TelemetryChannel> channels,
) => TelemetrySession(
  duration: session.duration,
  startTime: session.startTime,
  metadata: session.metadata,
  channels: channels,
  aliases: session.aliases,
  warnings: session.warnings,
  timingGates: session.timingGates,
  sampleCount: session.sampleCount,
);

TelemetryChannel _changed(
  TelemetryChannel channel,
  double Function(double) f,
) => TelemetryChannel(
  name: channel.name,
  unit: channel.unit,
  timestamps: channel.timestamps,
  values: Float32List.fromList([for (final value in channel.values) f(value)]),
);

/// An RCZ of [primary]'s drive in its units whose speed reads 8 % higher
/// and whose position lies about 20 m north-east, with engine speed added:
/// speed and GPS conflict, so the user can choose the RCZ for them.
TelemetryRunProposal _conflictingRcz(TelemetryRunProposal primary) {
  final session = primary.telemetry;
  final speed = session.aliases['speed']!;
  final latitude = session.aliases['latitude']!;
  final longitude = session.aliases['longitude']!;
  final channels = {
    for (final MapEntry(:key, :value) in session.channels.entries)
      key: key == speed
          ? _changed(value, (v) => v * 1.08)
          : key == latitude || key == longitude
          ? _changed(value, (v) => v + 0.01)
          : value,
    'rpm': _changed(session.channels[speed]!, (v) => 2000 + v * 30),
  };
  final sha = 'a' * 64;
  return TelemetryRunProposal(
    id: 'run:$sha',
    sourceId: 'sha256:$sha',
    sourcePath: '${primary.sourcePath}.rcz',
    format: RecordingFormat.rcz,
    contentSha256: sha,
    telemetry: _session(session, channels),
    laps: primary.laps,
  );
}

Map<String, Object?> _runJson(String path) =>
    ((readDayDocument(path)['event'] as Map)['runs'] as List).single
        as Map<String, Object?>;

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('fusion'));
  tearDown(() => directory.deleteSync(recursive: true));

  DayImportOutcome importDay(List<String> paths) =>
      runDayImport((paths: paths, includeSubfolders: false));

  test('the results show first, and the RCZ is combined after', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final alone = importDay([vbo]);
    final both = importDay([vbo, rcz]);
    expect(both.runs, hasLength(1));
    // The import itself does not align: that waits until the day shows.
    expect(
      both.steps.map((step) => step.name),
      isNot(contains('Align and combine VBO and RCZ')),
    );
    final runId = both.runs.single.run.id;
    expect(both.alternatives.keys, [runId]);
    final plain = DayResultsController(
      runs: alone.runs,
      analysis: alone.analysis!,
    );
    final held = _HeldFusions();
    final fused = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      alternatives: both.alternatives,
      fusionRunner: held.call,
    );
    addTearDown(plain.dispose);
    addTearDown(fused.dispose);

    // Before: the VBO's results, and a fusion on its way.
    expect(fused.fusion(runId), isNull);
    expect(fused.fusionPending(runId), 'RCZ');
    expect(_rows(fused), _rows(plain));
    expect(fused.session(runId)!.channels, isNot(contains('rpm-obd')));
    final laps = fused.comparisonCandidates();
    expect(
      fused.comparison(laps[0], laps[1])!.chartChannels,
      isNot(contains('rpm-obd')),
    );
    var notified = 0;
    fused.addListener(() => ++notified);

    await held.release(0);
    await fused.fusionsSettled;
    expect(notified, greaterThan(0));
    expect(fused.fusionPending(runId), isNull);
    final fusion = fused.fusion(runId)!;
    expect(fusion.fused, isTrue);
    expect(fused.session(runId)!.channels, contains('rpm-obd'));
    expect(fused.channelSource(runId, 'rpm-obd'), 'RCZ');
    expect(fused.channelSource(runId, 'velocity'), '');
    // The comparison and the channel summaries read the fused channels now.
    expect(
      fused.comparison(laps[0], laps[1])!.chartChannels,
      contains('rpm-obd'),
    );
    expect(_rows(fused), _rows(plain));
  });

  test('"Use RCZ" on speed and on GPS changes no lap row, timing, ranking or '
      'theoretical best', () async {
    final (vbo, _) = writeFusionPair(directory.path);
    final alone = importDay([vbo]);
    final primary = alone.runs.single.run;
    final runId = primary.id;
    final fusion = fuseRunRecordings(primary, _conflictingRcz(primary));
    expect(fusion.fused, isTrue);
    final speed = primary.telemetry.aliases['speed']!;
    final latitude = primary.telemetry.aliases['latitude']!;
    expect([
      for (final channel in fusion.conflicts) channel.key,
    ], containsAll(['speed', 'latitude', 'longitude']));
    final plain = DayResultsController(
      runs: alone.runs,
      analysis: alone.analysis!,
    );
    final fused = DayResultsController(
      runs: alone.runs,
      analysis: alone.analysis!,
      fusions: {runId: fusion},
    );
    addTearDown(plain.dispose);
    addTearDown(fused.dispose);
    await plain.requestTheoreticalBest();
    final best = plain.theoreticalBest!.summary!;
    expect(best.totalSeconds, isNotNull);

    for (final key in ['speed', 'latitude', 'longitude']) {
      await fused.setFusionRule(runId, key, FusionRule.preferAlternative);
      expect(fused.fusion(runId)!.ruleOf(key), FusionRule.preferAlternative);
    }
    // The RCZ's speed and position are what the channels read now.
    final session = fused.session(runId)!;
    final recorded = primary.telemetry;
    expect(
      session.valueAt(speed, 100.0)! / recorded.valueAt(speed, 100.0)!,
      closeTo(1.08, 0.01),
    );
    expect(
      session.valueAt(latitude, 100.0)! - recorded.valueAt(latitude, 100.0)!,
      closeTo(0.01, 0.001),
    );
    expect(fused.channelSource(runId, speed), 'RCZ');
    expect(fused.dirty, isTrue);

    // Laps, timing, ranking and the theoretical best are the VBO's alone.
    expect(_rows(fused), _rows(plain));
    await fused.requestTheoreticalBest();
    final timed = fused.theoreticalBest!.summary!;
    expect(timed.totalSeconds, best.totalSeconds);
    expect(timed.differenceSeconds, best.differenceSeconds);
    expect(
      [
        for (final segment in fused.theoreticalBest!.segments)
          (segment.seconds, segment.sourceLapReference),
      ],
      [
        for (final segment in plain.theoreticalBest!.segments)
          (segment.seconds, segment.sourceLapReference),
      ],
    );
  });

  test(
    'an added channel and a conflict, from import to save and reopen',
    () async {
      final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
      final both = importDay([vbo, rcz]);
      final runId = both.runs.single.run.id;
      final controller = DayResultsController(
        runs: both.runs,
        analysis: both.analysis!,
        alternatives: both.alternatives,
      );
      addTearDown(controller.dispose);
      await controller.fusionsSettled;
      final fusion = controller.fusion(runId)!;
      expect(fusion.channelOrigins, {'rpm-obd': 'added'});
      expect([for (final channel in fusion.conflicts) channel.key], ['sats']);
      await controller.setFusionRule(runId, 'sats', FusionRule.fillGaps);
      final path = '${directory.path}/Day.fetproject';
      // The writer validates the document as FlappedEar Overlays does.
      await controller.save(path);
      expect(controller.dirty, isFalse);
      final run = _runJson(path);
      final sources = (run['sources'] as Map)['telemetry'] as List;
      expect(sources, hasLength(2));
      final decision = run['fusion'] as Map;
      expect(decision['alternativeSourceId'], fusion.alternativeSourceId);
      expect(decision['rules'], [
        {'key': 'sats', 'rule': 'fillGaps'},
      ]);

      final held = _HeldFusions();
      final opened = DayResultsController.opened(
        openDay(path),
        fusionRunner: held.call,
      );
      addTearDown(opened.dispose);
      // The day shows before its RCZ is read.
      expect(opened.fusion(runId), isNull);
      expect(opened.fusionPending(runId), 'RCZ');
      expect(_rows(opened), _rows(controller));
      await held.release(0);
      await opened.fusionsSettled;
      final applied = opened.fusion(runId)!;
      expect(applied.fromDocument, isTrue, reason: 'not aligned again');
      expect(applied.ruleOf('sats'), FusionRule.fillGaps);
      expect(applied.channelOrigins, {'rpm-obd': 'added', 'sats': 'fillGaps'});
      expect(opened.channelSource(runId, 'rpm-obd'), 'RCZ');
      expect(
        opened.dirty,
        isFalse,
        reason: 'the saved decision changes nothing',
      );
      expect(_rows(opened), _rows(controller));
    },
  );

  test(
    'a day without a decision has changes only once fusion makes one',
    () async {
      final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
      final both = importDay([vbo, rcz]);
      final runId = both.runs.single.run.id;
      final controller = DayResultsController(
        runs: both.runs,
        analysis: both.analysis!,
        alternatives: both.alternatives,
      );
      addTearDown(controller.dispose);
      await controller.fusionsSettled;
      final path = '${directory.path}/Day.fetproject';
      await controller.save(path);
      // As a day saved before FET-51 keeps it: the RCZ, without a decision.
      final document = readDayDocument(path);
      final run = ((document['event'] as Map)['runs'] as List).single as Map;
      run.remove('fusion');
      // The writer refuses a document Overlays would not open.
      await saveDayDocument(path, document);

      final held = _HeldFusions();
      final opened = DayResultsController.opened(
        openDay(path),
        fusionRunner: held.call,
      );
      addTearDown(opened.dispose);
      expect(opened.dirty, isFalse);
      await held.release(0);
      await opened.fusionsSettled;
      expect(opened.fusion(runId)!.fused, isTrue);
      expect(opened.fusion(runId)!.fromDocument, isFalse);
      expect(opened.dirty, isTrue, reason: 'the new decision is not saved');
    },
  );

  test(
    'a session added after channels were read is compared and summarized',
    () async {
      final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
      final both = importDay([vbo, rcz]);
      final controller = DayResultsController(
        runs: both.runs,
        analysis: both.analysis!,
        alternatives: both.alternatives,
        appender: _SyncAppender(),
      );
      addTearDown(controller.dispose);
      await controller.fusionsSettled;
      // Fill what reads channels: a comparison and the Car/Driver summaries.
      final first = controller.comparisonCandidates();
      expect(controller.comparison(first[0], first[1]), isNotNull);
      await controller.requestChannelSummaries();
      expect(controller.channelSummaries!.runs, hasLength(1));

      // A plain VBO of another drive, no RCZ.
      final other = Directory('${directory.path}/other')..createSync();
      final (plain, _) = writeFusionPair(
        other.path,
        name: 'plain',
        speeds: const [31, 26, 30, 28, 33, 27, 29, 25, 32, 30],
      );
      final addition = await controller.addRecordings([plain]);
      expect(addition.added, hasLength(1));
      final added = controller.runs.last.run.id;
      final laps = [
        for (final row in controller.analysis.rows)
          if (row.runId == added && row.type == LapSectionType.lap) row,
      ];
      expect(laps.length, greaterThanOrEqualTo(2));
      final comparison = controller.comparison(laps[0], laps[1]);
      expect(comparison, isNotNull);
      expect(controller.comparison(laps[0], first[0]), isNotNull);
      await controller.requestChannelSummaries();
      final summaries = controller.channelSummaries!.runs;
      expect(summaries.map((run) => run.runId), contains(added));
      expect(
        summaries.firstWhere((run) => run.runId == added).unavailableReason,
        isEmpty,
      );
    },
  );

  test('a rule change that fails leaves the choice usable', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final both = importDay([vbo, rcz]);
    final runId = both.runs.single.run.id;
    final primary = both.runs.single.run;
    final fusion = fuseRunRecordings(primary, both.alternatives[runId]!);
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      fusions: {runId: fusion},
      fusionRunner: (_) => throw StateError('out of memory'),
    );
    addTearDown(controller.dispose);
    await controller.setFusionRule(runId, 'sats', FusionRule.fillGaps);
    expect(controller.fusionUpdating(runId), isFalse);
    expect(controller.fusion(runId)!.ruleOf('sats'), FusionRule.primaryOnly);
    await controller.fusionsSettled;
  });

  test(
    'a fusion result for a run asked again or a closed day is dropped',
    () async {
      final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
      final first = importDay([vbo]);
      final runId = first.runs.single.run.id;
      final held = _HeldFusions();
      final controller = DayResultsController(
        runs: first.runs,
        analysis: first.analysis!,
        appender: _SyncAppender(),
        fusionRunner: held.call,
      );
      addTearDown(controller.dispose);
      await controller.addRecordings([rcz]);
      expect(controller.fusionPending(runId), 'RCZ');
      // Added again before the first finished: only the latest counts.
      await controller.addRecordings([rcz]);
      expect(held.jobs, hasLength(2));
      expect(held.jobs[0].cancelled, isTrue, reason: 'superseded: stopped');
      await held.release(0);
      expect(controller.fusion(runId), isNull);
      expect(controller.fusionPending(runId), 'RCZ');
      await held.release(1);
      await controller.fusionsSettled;
      expect(controller.fusion(runId)!.fused, isTrue);

      final closed = DayResultsController(
        runs: first.runs,
        analysis: first.analysis!,
        appender: _SyncAppender(),
        fusionRunner: held.call,
      );
      await closed.addRecordings([rcz]);
      closed.dispose();
      expect(held.jobs[2].cancelled, isTrue, reason: 'stopped on close');
      await held.release(2);
      expect(closed.fusion(runId), isNull);
    },
  );

  test('queued alignments do not start once the day closes', () async {
    final slots = DayResultsController.fusionSlots;
    DayResultsController.fusionSlots = 1;
    addTearDown(() => DayResultsController.fusionSlots = slots);
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final other = Directory('${directory.path}/other')..createSync();
    final (vbo2, rcz2) = writeFusionPair(
      other.path,
      name: 'other',
      speeds: const [31, 26, 30, 28, 33, 27, 29, 25, 32, 30],
    );
    final both = importDay([vbo, rcz, vbo2, rcz2]);
    expect(both.alternatives, hasLength(2));
    final held = _HeldFusions();
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      alternatives: both.alternatives,
      fusionRunner: held.call,
    );
    await pumpEventQueue();
    expect(held.jobs, hasLength(1), reason: 'one at a time');
    controller.dispose();
    expect(held.jobs.single.cancelled, isTrue);
    await pumpEventQueue();
    expect(held.jobs, hasLength(1), reason: 'the queued one never started');
  });

  test('a day saved while its RCZ is lined up keeps the RCZ', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final both = importDay([vbo, rcz]);
    final runId = both.runs.single.run.id;
    final held = _HeldFusions();
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      alternatives: both.alternatives,
      fusionRunner: held.call,
    );
    final path = '${directory.path}/Day.fetproject';
    expect(controller.fusionPending(runId), 'RCZ');
    await controller.save(path);
    controller.dispose();
    final run = _runJson(path);
    expect((run['sources'] as Map)['telemetry'] as List, hasLength(2));
    expect(run['fusion'], isNull, reason: 'nothing decided yet');

    final opened = DayResultsController.opened(openDay(path));
    addTearDown(opened.dispose);
    await opened.fusionsSettled;
    expect(opened.fusion(runId)!.fused, isTrue, reason: 'aligned on opening');
  });

  test(
    'an RCZ added to a saved day is in the file before it is lined up',
    () async {
      final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
      final first = importDay([vbo]);
      final runId = first.runs.single.run.id;
      final held = _HeldFusions();
      final controller = DayResultsController(
        runs: first.runs,
        analysis: first.analysis!,
        appender: _SyncAppender(),
        fusionRunner: held.call,
      );
      final path = '${directory.path}/Day.fetproject';
      await controller.save(path);
      final addition = await controller.addRecordings([rcz]);
      expect(addition.savedTo, path);
      // Closed before the alignment ends.
      controller.dispose();
      expect(
        (_runJson(path)['sources'] as Map)['telemetry'] as List,
        hasLength(2),
      );

      final opened = DayResultsController.opened(openDay(path));
      addTearDown(opened.dispose);
      await opened.fusionsSettled;
      expect(opened.fusion(runId)!.fused, isTrue);
    },
  );

  test('an RCZ added to a session whose RCZ could not be aligned replaces it '
      'in the file at once', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final plan = prepareTelemetryImport([vbo, rcz]);
    final primary = plan.runs.firstWhere(
      (run) => run.format == RecordingFormat.vbo,
    );
    final a = plan.runs.firstWhere((run) => run.format == RecordingFormat.rcz);
    // A that cannot be aligned: its clock says 40 s later.
    final shifted = TelemetryRunProposal(
      id: a.id,
      sourceId: a.sourceId,
      sourcePath: a.sourcePath,
      format: a.format,
      contentSha256: a.contentSha256,
      laps: a.laps,
      telemetry: TelemetrySession(
        duration: a.telemetry.duration,
        startTime: a.telemetry.startTime,
        metadata: {
          ...a.telemetry.metadata,
          'firstTimestampMilliseconds': '${fusionPairOrigin + 40100}',
        },
        channels: a.telemetry.channels,
        aliases: a.telemetry.aliases,
        warnings: a.telemetry.warnings,
        timingGates: a.telemetry.timingGates,
        sampleCount: a.telemetry.sampleCount,
      ),
    );
    final notAligned = fuseRunRecordings(primary, shifted);
    expect(notAligned.fused, isFalse);
    expect(notAligned.alternative, isNotNull);
    final alone = importDay([vbo]);
    final runId = alone.runs.single.run.id;
    final held = _HeldFusions();
    final controller = DayResultsController(
      runs: alone.runs,
      analysis: alone.analysis!,
      fusions: {runId: notAligned},
      appender: _SyncAppender(),
      fusionRunner: held.call,
    );
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    // B: the same drive exported again.
    final again = Directory('${directory.path}/again')..createSync();
    final (_, b) = writeFusionPair(
      again.path,
      satellites: true,
      satelliteDifference: 6,
    );
    final addition = await controller.addRecordings([b]);
    expect(addition.combined, ['Session 1']);
    expect(addition.savedTo, path);
    controller.dispose(); // before B is lined up
    final sources = ((_runJson(path)['sources'] as Map)['telemetry'] as List)
        .cast<Map<String, Object?>>();
    expect(sources, hasLength(2), reason: 'B takes A\'s entry');
    expect(sources.last['id'], a.sourceId);
    expect(
      (sources.last['reference'] as Map)['relativePath'],
      'again/drive.rcz',
    );
    expect(_runJson(path)['fusion'], isNull);

    final opened = DayResultsController.opened(openDay(path));
    addTearDown(opened.dispose);
    await opened.fusionsSettled;
    final fusion = opened.fusion(runId)!;
    expect(fusion.fused, isTrue, reason: 'B is the source');
    // Compared resolved: the macOS temp folder is reached through a link
    // (/var is /private/var), and the reopened path is the resolved one.
    expect(
      File(fusion.alternative!.sourcePath).resolveSymbolicLinksSync(),
      File(b).resolveSymbolicLinksSync(),
    );
  });

  test('an RCZ whose alignment job crashed is said not combined, and still '
      'saved to try again', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final first = importDay([vbo]);
    final runId = first.runs.single.run.id;
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
      fusionRunner: (_) => throw StateError('out of memory'),
    );
    addTearDown(controller.dispose);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    final addition = await controller.addRecordings([rcz]);
    await controller.fusionsSettled;
    final fusion = controller.fusion(runId)!;
    expect(fusion.state, RunFusionState.unavailable);
    expect(fusion.reason, fusionFailedReason);
    expect(fusion.alternativeSourceId, 'sha256:${_sha(rcz)}');
    expect(controller.fusionPending(runId), isNull);
    expect(controller.missingAlternatives, isEmpty, reason: 'not missing');
    // Reported as added but not combined, not as combined.
    expect(controller.lastAddition!.notCombined, ['Session 1']);
    expect(controller.lastAddition!.combined, isEmpty);
    expect(addition.notCombined, ['Session 1']);
    // Saved again later, it is still the session's source.
    await controller.save(path);
    final sources = (_runJson(path)['sources'] as Map)['telemetry'] as List;
    expect(sources, hasLength(2));
    final opened = DayResultsController.opened(openDay(path));
    addTearDown(opened.dispose);
    await opened.fusionsSettled;
    expect(opened.fusion(runId)!.fused, isTrue, reason: 'tried again');
  });

  test('an RCZ whose alignment crashes after its addition reported is '
      'said not combined', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final first = importDay([vbo]);
    final runId = first.runs.single.run.id;
    final tasks = <_HeldTask>[];
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
      fusionRunner: (_) {
        final task = _HeldTask((_) => throw StateError('out of memory'));
        tasks.add(task);
        return task;
      },
    );
    addTearDown(controller.dispose);
    final addition = await controller.addRecordings([rcz]);
    expect(addition.combined, ['Session 1']);
    expect(controller.lastAddition, same(addition));
    tasks.single.run();
    await controller.fusionsSettled;
    expect(controller.fusion(runId)!.reason, fusionFailedReason);
    expect(controller.lastAddition!.notCombined, ['Session 1']);
  });

  test('an RCZ that cannot be aligned is still saved as the source', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final first = importDay([vbo]);
    final runId = first.runs.single.run.id;
    final primary = first.runs.single.run;
    // Whatever the job is, the alignment says: not aligned.
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
      fusionRunner: (_) {
        final rczRun = prepareTelemetryImport([rcz]).runs.single;
        final task = _HeldTask((_) => fuseRunRecordings(primary, _late(rczRun)))
          ..run();
        return task;
      },
    );
    addTearDown(controller.dispose);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    await controller.addRecordings([rcz]);
    await controller.fusionsSettled;
    final fusion = controller.fusion(runId)!;
    expect(fusion.state, RunFusionState.notAligned);
    expect(fusion.alternative, isNotNull);
    expect(controller.lastAddition!.notCombined, isEmpty);
    expect(controller.dirty, isFalse, reason: 'saved again');
    final run = _runJson(path);
    expect((run['sources'] as Map)['telemetry'] as List, hasLength(2));
    expect(run['fusion'], isNull);
  });

  group('a fusion isolate', () {
    test('returns its result', () async {
      final (vbo, rcz) = writeFusionPair(directory.path);
      final plan = prepareTelemetryImport([vbo, rcz]);
      final primary = plan.runs.firstWhere(
        (run) => run.format == RecordingFormat.vbo,
      );
      final alternative = plan.runs.firstWhere(
        (run) => run.format == RecordingFormat.rcz,
      );
      final task = isolateFusionRunner(
        (cancelled) =>
            fuseRunRecordings(primary, alternative, cancelled: cancelled),
      );
      expect((await task.result)!.fused, isTrue);
    });

    test('cancelled before it has started, stops with OperationCancelled', () {
      final task = isolateFusionRunner((_) => null);
      task.cancel();
      expect(task.result, throwsA(isA<OperationCancelled>()));
    });

    test('an error inside it reaches the caller as an error', () {
      final task = isolateFusionRunner(
        (_) => throw StateError('broken recording'),
      );
      expect(
        task.result,
        throwsA(predicate((error) => '$error'.contains('broken recording'))),
      );
    });
  });

  test('an RCZ added to a saved VBO session is combined and saved', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final first = importDay([vbo]);
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    addTearDown(controller.dispose);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    final before = _rows(controller);
    final addition = await controller.addRecordings([rcz]);
    expect(addition.added, isEmpty);
    expect(addition.combined, ['Session 1']);
    expect(addition.notes, [
      'drive.rcz: the same drive as Session 1 in the other format; kept as its '
          'alternative source.',
    ]);
    await controller.fusionsSettled;
    final runId = first.runs.single.run.id;
    expect(controller.fusion(runId)!.fused, isTrue);
    expect(controller.session(runId)!.channels, contains('rpm-obd'));
    expect(_rows(controller), before);
    // Saved again once combined, as the addition was.
    expect(controller.dirty, isFalse);
    expect(_runJson(path)['fusion'], isNotNull);
  });

  test(
    'an RCZ added again for a session whose RCZ is missing takes its place',
    () async {
      final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
      final both = importDay([vbo, rcz]);
      final runId = both.runs.single.run.id;
      final controller = DayResultsController(
        runs: both.runs,
        analysis: both.analysis!,
        alternatives: both.alternatives,
      );
      addTearDown(controller.dispose);
      await controller.fusionsSettled;
      final path = '${directory.path}/Day.fetproject';
      await controller.save(path);
      final sourceId = controller.fusion(runId)!.alternativeSourceId;
      final moved = '${directory.path}/kept/drive.rcz';
      Directory('${directory.path}/kept').createSync();
      File(rcz).renameSync(moved);

      final opened = DayResultsController.opened(
        openDay(path),
        appender: _SyncAppender(),
      );
      addTearDown(opened.dispose);
      await opened.fusionsSettled;
      expect(opened.fusion(runId)!.state, RunFusionState.unavailable);
      expect(opened.missingAlternatives, hasLength(1));
      await opened.addRecordings([moved]);
      await opened.fusionsSettled;
      expect(opened.fusion(runId)!.fused, isTrue);
      expect(opened.fusion(runId)!.alternativeSourceId, sourceId);
      expect(opened.dirty, isFalse, reason: 'saved again after combining');
      final run = _runJson(path);
      final sources = ((run['sources'] as Map)['telemetry'] as List)
          .cast<Map<String, Object?>>();
      expect(sources, hasLength(2), reason: 'one entry for the RCZ');
      expect(sources.last['id'], sourceId);
      expect(
        (sources.last['reference'] as Map)['relativePath'],
        'kept/drive.rcz',
      );
    },
  );

  test('an RCZ of the same drive added again keeps the rules chosen', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final both = importDay([vbo, rcz]);
    final runId = both.runs.single.run.id;
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      alternatives: both.alternatives,
    );
    addTearDown(controller.dispose);
    await controller.fusionsSettled;
    await controller.setFusionRule(runId, 'sats', FusionRule.fillGaps);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    File(rcz).deleteSync();
    // The same drive exported again, other content.
    final again = Directory('${directory.path}/again')..createSync();
    final (_, other) = writeFusionPair(
      again.path,
      satellites: true,
      satelliteDifference: 6,
    );

    final opened = DayResultsController.opened(
      openDay(path),
      appender: _SyncAppender(),
    );
    addTearDown(opened.dispose);
    await opened.fusionsSettled;
    expect(opened.fusion(runId)!.state, RunFusionState.unavailable);
    final addition = await opened.addRecordings([other]);
    expect(addition.combined, ['Session 1']);
    await opened.fusionsSettled;
    final fusion = opened.fusion(runId)!;
    expect(fusion.fused, isTrue);
    expect(fusion.fromDocument, isFalse, reason: 'aligned afresh');
    expect(fusion.ruleOf('sats'), FusionRule.fillGaps, reason: 'kept');
  });

  test('an RCZ written again for the same drive is aligned afresh', () async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final both = importDay([vbo, rcz]);
    final runId = both.runs.single.run.id;
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      alternatives: both.alternatives,
    );
    addTearDown(controller.dispose);
    await controller.fusionsSettled;
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    final again = Directory('${directory.path}/again')..createSync();
    final (_, other) = writeFusionPair(again.path);
    File(other).copySync(rcz);

    final opened = DayResultsController.opened(openDay(path));
    addTearDown(opened.dispose);
    expect(opened.dirty, isFalse);
    await opened.fusionsSettled;
    final fusion = opened.fusion(runId)!;
    expect(fusion.fused, isTrue);
    expect(fusion.fromDocument, isFalse);
    expect(fusion.conflicts, isEmpty);
    expect(opened.dirty, isTrue, reason: 'its source entry is updated');
    await opened.save(path);
    final run = _runJson(path);
    final sources = (run['sources'] as Map)['telemetry'] as List;
    expect(sources, hasLength(2));
    expect(
      (sources.last as Map)['contentSha256'],
      fusion.alternative!.contentSha256,
    );
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
    expect(addition.combined, isEmpty);
    final added = controller.runs.last.run;
    expect(added.format, RecordingFormat.vbo);
    expect(controller.fusionPending(added.id), 'RCZ');
    await controller.fusionsSettled;
    expect(controller.fusion(added.id)!.fused, isTrue);
    expect(controller.channelSource(added.id, 'rpm-obd'), 'RCZ');
  });

  testWidgets('shows what the RCZ added and lets a conflict be decided', (
    tester,
  ) async {
    final (vbo, rcz) = writeFusionPair(directory.path, satellites: true);
    final both = importDay([vbo, rcz]);
    final runId = both.runs.single.run.id;
    final held = _HeldFusions();
    final controller = DayResultsController(
      runs: both.runs,
      analysis: both.analysis!,
      alternatives: both.alternatives,
      fusionRunner: held.call,
    );
    final before = _rows(controller);
    await tester.binding.setSurfaceSize(const Size(400, 8000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    // The day shows at once; its RCZ is lined up meanwhile.
    expect(find.text('Lining up with its RCZ…'), findsOneWidget);
    await held.release(0, settle: false);
    await tester.pumpAndSettle();
    expect(find.text('Lining up with its RCZ…'), findsNothing);
    expect(find.text('Combined with its RCZ: 1 channel added'), findsOneWidget);
    expect(
      find.text('Satellites: the VBO and the RCZ disagree'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Use RCZ'));
    await tester.tap(find.text('Use RCZ'));
    await tester.pumpAndSettle();
    await held.release(1, settle: false);
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

  testWidgets('an RCZ with nothing to add says so in one quiet line', (
    tester,
  ) async {
    final (vbo, rcz) = writeFusionPair(directory.path);
    final plan = prepareTelemetryImport([vbo, rcz]);
    final primary = plan.runs.firstWhere(
      (run) => run.format == RecordingFormat.vbo,
    );
    final alternative = plan.runs.firstWhere(
      (run) => run.format == RecordingFormat.rcz,
    );
    final bare = TelemetryRunProposal(
      id: alternative.id,
      sourceId: alternative.sourceId,
      sourcePath: alternative.sourcePath,
      format: alternative.format,
      contentSha256: alternative.contentSha256,
      laps: alternative.laps,
      telemetry: _session(alternative.telemetry, {
        for (final MapEntry(:key, :value)
            in alternative.telemetry.channels.entries)
          if (key != 'rpm-obd') key: value,
      }),
    );
    final fusion = fuseRunRecordings(primary, bare);
    expect(fusion.fused, isTrue);
    expect(fusion.channelOrigins, isEmpty);
    final alone = importDay([vbo]);
    final controller = DayResultsController(
      runs: alone.runs,
      analysis: alone.analysis!,
      fusions: {primary.id: fusion},
    );
    await tester.binding.setSurfaceSize(const Size(400, 8000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    final offset = fusion.clock.offsetSeconds;
    expect(
      find.text(
        'Lined up with its RCZ (${offset < 0 ? '−' : '+'}'
        '${offset.abs().toStringAsFixed(2)} s); nothing to add',
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

  // Lets the search's isolate and file work finish between frames.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 400 && !done(); ++i) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  for (final rczOnly in [false, true]) {
    testWidgets(
      rczOnly
          ? 'finds a moved RCZ in a folder and combines it again'
          : 'finds a fused day\'s moved recordings and combines them again',
      (tester) async {
        final recordings = Directory('${directory.path}/recordings')
          ..createSync();
        final (vbo, rcz) = writeFusionPair(recordings.path, satellites: true);
        final path = '${directory.path}/Day.fetproject';
        // Another session stays where it was, so the day still opens.
        final stays = Directory('${directory.path}/stays')..createSync();
        final (other, _) = writeFusionPair(
          stays.path,
          name: 'other',
          speeds: const [31, 26, 30, 28, 33, 27, 29, 25, 32, 30],
        );
        final opened = (await tester.runAsync(() async {
          final both = importDay([vbo, rcz, other]);
          final fusedId = both.alternatives.keys.single;
          final controller = DayResultsController(
            runs: both.runs,
            analysis: both.analysis!,
            alternatives: both.alternatives,
          );
          await controller.fusionsSettled;
          await controller.setFusionRule(fusedId, 'sats', FusionRule.fillGaps);
          await controller.save(path);
          controller.dispose();
          final moved = Directory('${directory.path}/archive/deep')
            ..createSync(recursive: true);
          if (rczOnly) {
            File(rcz).renameSync('${moved.path}/renamed.rcz');
          } else {
            recordings.renameSync('${moved.path}/recordings');
          }
          return openDay(path);
        }))!;
        expect(opened.missing, hasLength(rczOnly ? 0 : 1));
        DayResultsController? replaced;
        final day = rczOnly ? DayResultsController.opened(opened) : null;
        if (day != null) await tester.runAsync(() => day.fusionsSettled);
        await tester.binding.setSurfaceSize(const Size(400, 8000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          TelemetryApp(
            home: day != null
                ? DayResultsPage.controller(
                    controller: day,
                    documents: _Documents('${directory.path}/archive'),
                    replace: (controller) => replaced = controller,
                  )
                : DayResultsPage.opened(
                    day: opened,
                    documents: _Documents('${directory.path}/archive'),
                  ),
          ),
        );
        await tester.pumpAndSettle();
        if (rczOnly) {
          expect(
            find.text('The RCZ of 1 session could not be used'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              ': recordings/drive.rcz · the recording was not found',
            ),
            findsOneWidget,
          );
        } else {
          expect(find.text('1 session could not be opened'), findsOneWidget);
        }
        await tester.tap(find.text('Find recordings in a folder…'));
        if (rczOnly) {
          await waitFor(tester, () => replaced != null);
          final relinked = replaced!;
          addTearDown(relinked.dispose);
          await tester.runAsync(() => relinked.fusionsSettled);
          final runId = relinked.runs
              .firstWhere((named) => relinked.fusion(named.run.id) != null)
              .run
              .id;
          final fusion = relinked.fusion(runId)!;
          expect(fusion.fused, isTrue);
          expect(fusion.fromDocument, isTrue);
          expect(fusion.ruleOf('sats'), FusionRule.fillGaps);
          expect(relinked.channelSource(runId, 'rpm-obd'), 'RCZ');
          expect(relinked.dirty, isTrue, reason: 'its new place is saved');
          expect(relinked.missingAlternatives, isEmpty);
        } else {
          await waitFor(
            tester,
            () => find
                .text('Combined with its RCZ: 1 channel added')
                .evaluate()
                .isNotEmpty,
          );
          expect(find.text('1 session could not be opened'), findsNothing);
          expect(
            find.text('Combined with its RCZ: 1 channel added'),
            findsOneWidget,
          );
          expect(
            find.text('Satellites: the VBO and the RCZ disagree'),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets(
    'an RCZ found only by its name that is another drive is not used',
    (tester) async {
      final recordings = Directory('${directory.path}/recordings')
        ..createSync();
      final (vbo, rcz) = writeFusionPair(recordings.path, satellites: true);
      final path = '${directory.path}/Day.fetproject';
      final day = (await tester.runAsync(() async {
        final both = importDay([vbo, rcz]);
        final controller = DayResultsController(
          runs: both.runs,
          analysis: both.analysis!,
          alternatives: both.alternatives,
        );
        await controller.fusionsSettled;
        await controller.save(path);
        controller.dispose();
        File(rcz).deleteSync();
        // Another drive's RCZ, named like the missing one.
        final archive = Directory('${directory.path}/archive')..createSync();
        final scratch = Directory('${directory.path}/scratch')..createSync();
        final (_, other) = writeFusionPair(
          scratch.path,
          speeds: const [31, 26, 30, 28, 33, 27, 29, 25, 32, 30],
        );
        File(other).copySync('${archive.path}/drive.rcz');
        final day = DayResultsController.opened(openDay(path));
        await day.fusionsSettled;
        return day;
      }))!;
      DayResultsController? replaced;
      await tester.binding.setSurfaceSize(const Size(400, 8000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.controller(
            controller: day,
            documents: _Documents('${directory.path}/archive'),
            replace: (controller) => replaced = controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The RCZ of 1 session could not be used'),
        findsOneWidget,
      );
      await tester.tap(find.text('Find recordings in a folder…'));
      await waitFor(
        tester,
        () => find
            .text('Not used, a different recording: drive.rcz.')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.text('Not used, a different recording: drive.rcz.'),
        findsOneWidget,
      );
      expect(replaced, isNull, reason: 'nothing else was found');
      expect(
        find.text('The RCZ of 1 session could not be used'),
        findsOneWidget,
      );
    },
  );

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
          alternatives: both.alternatives,
        );
        addTearDown(controller.dispose);
        await controller.fusionsSettled;
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

/// [run] recorded on a clock that says 40 s later than it is: the declared
/// clocks disagree with the speed traces, so it cannot be aligned.
TelemetryRunProposal _late(TelemetryRunProposal run) => TelemetryRunProposal(
  id: run.id,
  sourceId: run.sourceId,
  sourcePath: run.sourcePath,
  format: run.format,
  contentSha256: run.contentSha256,
  laps: run.laps,
  telemetry: TelemetrySession(
    duration: run.telemetry.duration,
    startTime: run.telemetry.startTime,
    metadata: {
      ...run.telemetry.metadata,
      'firstTimestampMilliseconds': '${fusionPairOrigin + 40100}',
    },
    channels: run.telemetry.channels,
    aliases: run.telemetry.aliases,
    warnings: run.telemetry.warnings,
    timingGates: run.telemetry.timingGates,
    sampleCount: run.telemetry.sampleCount,
  ),
);

/// The content SHA-256 of the file at [path].
String _sha(String path) =>
    prepareTelemetryImport([path]).runs.single.contentSha256;
