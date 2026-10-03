// A day's runs fused with their alternative recordings without a review
// (FET-51), on synthetic VBO/RCZ pairs: no real data.
import 'dart:io';
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_pair.dart';

void main() {
  late Directory directory;
  late String root;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('day_fusion');
    root = directory.resolveSymbolicLinksSync();
    Directory(p.join(root, 'recordings')).createSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  ({List<NamedRun> runs, DayAnalysis analysis, Map<String, RunFusion> fusions}) importDay(
    List<String> paths,
  ) {
    final plan = prepareTelemetryImport(paths);
    final groups = automaticVboPrimaries(plan);
    final runs = nameRunsInRecordingOrder([
      for (final run in plan.runs)
        if (groups[run.id] == run.id) run,
    ]);
    return (
      runs: runs,
      analysis: analyzeDay([
        for (final named in runs)
          DayRunInput(
            runId: named.run.id,
            name: named.name,
            contentSha256: named.run.contentSha256,
            session: named.run.telemetry,
            laps: named.run.laps,
          ),
      ]),
      fusions: fuseImportedRuns(plan, [for (final named in runs) named.run]),
    );
  }

  Map<String, Object?> runJson(Map<String, Object?> document, String runId) =>
      ((document['event'] as Map)['runs'] as List).cast<Map<String, Object?>>().firstWhere(
        (run) => run['id'] == runId,
      );

  test('adds the channels only the RCZ has and keeps the VBO where they conflict', () {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    expect(day.runs, hasLength(1));
    final primary = day.runs.single.run;
    final fusion = day.fusions[primary.id]!;
    expect(fusion.state, RunFusionState.fused);
    expect(fusion.status, alignmentAligned);
    expect(fusion.clock.offsetSeconds, closeTo(0.1, 0.06));
    expect(fusion.alternative!.format, RecordingFormat.rcz);
    expect(fusion.channelOrigins, {'rpm-obd': 'added'});
    expect([for (final channel in fusion.conflicts) channel.key], ['sats']);
    expect(fusion.rules, {'sats': FusionRule.primaryOnly});
    expect(fusion.result!.unresolved, isEmpty);
    final session = fusion.session!;
    expect(session.channel('rpm'), isNotNull);
    // Shared channels stay the VBO's samples.
    for (final name in primary.telemetry.channels.keys) {
      expect(identical(session.channels[name], primary.telemetry.channels[name]), isTrue);
    }
    // The fused session never feeds lap timing: the VBO's laps stay as they were.
    expect(primary.laps.timedLaps, hasLength(10));

    final rcz2 = withFusionRule(fusion, primary, 'sats', FusionRule.preferAlternative)!;
    expect(rcz2.channelOrigins, {'rpm-obd': 'added', 'sats': 'preferAlternative'});
    expect(rcz2.session!.valueAt('sats', 100.0), primary.telemetry.valueAt('sats', 100.0)! + 5);
    expect(rcz2.decision!['rules'], [
      {'key': 'sats', 'rule': 'preferAlternative'},
    ]);
  });

  test('does not fuse recordings whose clocks cannot be aligned', () {
    // A constant speed has nothing to align on.
    final (vbo, rcz) = writeFusionPair(
      p.join(root, 'recordings'),
      speeds: const [30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    );
    final plan = prepareTelemetryImport([vbo, rcz]);
    final primary = plan.runs.firstWhere((run) => run.format == RecordingFormat.vbo);
    final alternative = plan.runs.firstWhere((run) => run.format == RecordingFormat.rcz);
    final fusion = fuseRunRecordings(primary, _flat(alternative));
    expect(fusion.state, RunFusionState.notAligned);
    expect(fusion.status, isNot(alignmentAligned));
    expect(fusion.reason, isNotEmpty);
    expect(fusion.session, isNull);
    expect(fusion.decision, isNull);
    expect(fusion.channelOrigins, isEmpty);
  });

  test('saves the decision bound to both recordings and applies it again on open', () async {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    final primary = day.runs.single.run;
    final chosen = withFusionRule(day.fusions[primary.id]!, primary, 'sats', FusionRule.fillGaps)!;
    final path = p.join(root, 'day.fetproject');
    final document = dayDocument(
      eventId: newEventId(),
      name: 'Fused day',
      runs: day.runs,
      analysis: day.analysis,
      projectPath: path,
      fusions: {primary.id: chosen},
    );
    expect(fet.validateFetproject(document), isNull);
    final run = runJson(document, primary.id);
    final sources = ((run['sources'] as Map)['telemetry'] as List).cast<Map<String, Object?>>();
    expect(
      [for (final source in sources) source['id']],
      [primary.sourceId, chosen.alternative!.sourceId],
    );
    final alternativeSource = sources.last;
    expect(alternativeSource['contentSha256'], chosen.alternative!.contentSha256);
    expect((alternativeSource['reference'] as Map)['relativePath'], 'recordings/drive.rcz');
    expect((alternativeSource['importProvenance'] as Map)['format'], 'rcz');
    final fusion = run['fusion'] as Map<String, Object?>;
    expect(fusion['algorithm'], 'channel-fusion-v1');
    expect(fusion['alternativeSourceId'], chosen.alternative!.sourceId);
    expect(fusion['primarySourceRevision'], primary.contentSha256);
    expect(fusion['alternativeSourceRevision'], chosen.alternative!.contentSha256);
    expect(fusion['clock'], {
      'offsetSeconds': chosen.clock.offsetSeconds,
      'driftPpm': 0.0,
      'uncertaintySeconds': chosen.uncertaintySeconds,
      'alignmentAlgorithm': 'recording-alignment-v1',
      'resolvedByDeclaredClock': chosen.resolvedByDeclaredClock,
    });
    expect(fusion['rules'], [
      {'key': 'sats', 'rule': 'fillGaps'},
    ]);
    await saveDayDocument(path, document);

    final opened = openDay(path);
    final applied = fuseOpenedDay(opened)[primary.id]!;
    expect(applied.fromDocument, isTrue, reason: 'applied without aligning again');
    expect(applied.documentChanged, isFalse);
    expect(opened.alternatives[primary.id]!.path, rcz, reason: 'not read when opening');
    expect(applied.clock.offsetSeconds, chosen.clock.offsetSeconds);
    expect(applied.rules, {'sats': FusionRule.fillGaps});
    expect(applied.channelOrigins, {'rpm-obd': 'added', 'sats': 'fillGaps'});
    // Saved again, the decision is unchanged.
    final again = dayDocument(
      eventId: opened.eventId,
      name: opened.name,
      runs: opened.runs,
      analysis: opened.analysis!,
      projectPath: path,
      previous: opened.document,
      previousPath: path,
      fusions: fuseOpenedDay(opened),
    );
    expect(runJson(again, primary.id)['fusion'], fusion);
    expect(((runJson(again, primary.id)['sources'] as Map)['telemetry'] as List), hasLength(2));
  });

  test('aligns again when the decision is not bound to the recordings', () async {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    final primary = day.runs.single.run;
    final path = p.join(root, 'day.fetproject');
    final document = dayDocument(
      eventId: newEventId(),
      name: 'Fused day',
      runs: day.runs,
      analysis: day.analysis,
      projectPath: path,
      fusions: day.fusions,
    );
    final fusion = runJson(document, primary.id)['fusion'] as Map<String, Object?>;
    // Bound to other content of the RCZ (still a valid document).
    fusion['alternativeSourceRevision'] = 'c' * 64;
    fusion['clock'] = {...fusion['clock'] as Map<String, Object?>, 'offsetSeconds': 40.0};
    expect(fet.validateFetproject(document), isNull);
    await saveDayDocument(path, document);
    final opened = openDay(path);
    final aligned = fuseOpenedDay(opened)[primary.id]!;
    expect(aligned.fromDocument, isFalse);
    expect(aligned.fused, isTrue);
    expect(aligned.clock.offsetSeconds, closeTo(0.1, 0.06));
    // Saving writes the new decision.
    final again = dayDocument(
      eventId: opened.eventId,
      name: opened.name,
      runs: opened.runs,
      analysis: opened.analysis!,
      projectPath: path,
      previous: opened.document,
      previousPath: path,
      fusions: fuseOpenedDay(opened),
    );
    final rewritten = runJson(again, primary.id)['fusion'] as Map<String, Object?>;
    expect(rewritten['alternativeSourceRevision'], aligned.alternative!.contentSha256);
    expect(fet.validateFetproject(again), isNull);
  });

  test('a missing RCZ leaves the day open and its decision saved as it was', () async {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    final primary = day.runs.single.run;
    final path = p.join(root, 'day.fetproject');
    final document = dayDocument(
      eventId: newEventId(),
      name: 'Fused day',
      runs: day.runs,
      analysis: day.analysis,
      projectPath: path,
      fusions: day.fusions,
    );
    await saveDayDocument(path, document);
    File(rcz).renameSync(p.join(root, 'elsewhere.rcz'));
    final opened = openDay(path);
    expect(opened.missing, isEmpty);
    expect(opened.runs, hasLength(1));
    final fusion = fuseOpenedDay(opened)[primary.id]!;
    expect(fusion.state, RunFusionState.unavailable);
    expect(fusion.reason, 'Recording not found.');
    expect(fusion.alternativeFormat, RecordingFormat.rcz);
    final again = dayDocument(
      eventId: opened.eventId,
      name: opened.name,
      runs: opened.runs,
      analysis: opened.analysis!,
      projectPath: path,
      previous: opened.document,
      previousPath: path,
      fusions: fuseOpenedDay(opened),
    );
    expect(runJson(again, primary.id)['fusion'], runJson(document, primary.id)['fusion']);
    expect(runJson(again, primary.id)['sources'], runJson(document, primary.id)['sources']);
  });

  test('a different file in the RCZ\'s place is not used', () async {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    final primary = day.runs.single.run;
    final path = p.join(root, 'day.fetproject');
    await saveDayDocument(
      path,
      dayDocument(
        eventId: newEventId(),
        name: 'Fused day',
        runs: day.runs,
        analysis: day.analysis,
        projectPath: path,
        fusions: day.fusions,
      ),
    );
    Directory(p.join(root, 'other')).createSync();
    final (_, otherRcz) = writeFusionPair(
      p.join(root, 'other'),
      speeds: const [31, 26, 30, 28, 33, 27, 29, 25, 32, 30],
    );
    File(otherRcz).copySync(rcz);
    final opened = openDay(path);
    expect(opened.runs, hasLength(1));
    final fusion = fuseOpenedDay(opened)[primary.id]!;
    expect(fusion.state, RunFusionState.unavailable);
    expect(fusion.reason, 'The file found is a different recording.');
    expect(fusion.session, isNull);
  });

  test('an RCZ written again for the same drive is aligned afresh and its entry updated', () async {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    final primary = day.runs.single.run;
    final path = p.join(root, 'day.fetproject');
    final document = dayDocument(
      eventId: newEventId(),
      name: 'Fused day',
      runs: day.runs,
      analysis: day.analysis,
      projectPath: path,
      fusions: day.fusions,
    );
    await saveDayDocument(path, document);
    final before = runJson(document, primary.id);
    // The same drive exported again: other content (no satellite count).
    Directory(p.join(root, 'other')).createSync();
    final (_, again) = writeFusionPair(p.join(root, 'other'));
    File(again).copySync(rcz);

    final opened = openDay(path);
    final fusion = fuseOpenedDay(opened)[primary.id]!;
    expect(fusion.state, RunFusionState.fused);
    expect(fusion.fromDocument, isFalse, reason: 'aligned afresh');
    expect(fusion.documentChanged, isTrue);
    expect(fusion.alternativeSourceId, (before['fusion'] as Map)['alternativeSourceId']);
    expect(fusion.channelOrigins, {'rpm-obd': 'added'});
    expect(fusion.conflicts, isEmpty);

    final saved = dayDocument(
      eventId: opened.eventId,
      name: opened.name,
      runs: opened.runs,
      analysis: opened.analysis!,
      projectPath: path,
      previous: opened.document,
      previousPath: path,
      fusions: {primary.id: fusion},
    );
    expect(fet.validateFetproject(saved), isNull);
    final run = runJson(saved, primary.id);
    final sources = ((run['sources'] as Map)['telemetry'] as List).cast<Map<String, Object?>>();
    expect(sources, hasLength(2), reason: 'the entry is updated, not added');
    final sha = fusion.alternative!.contentSha256;
    expect(sources.last['contentSha256'], sha);
    expect((sources.last['importProvenance'] as Map)['sha256'], sha);
    expect((run['fusion'] as Map)['alternativeSourceRevision'], sha);
    await saveDayDocument(path, saved);
    final reopened = fuseOpenedDay(openDay(path))[primary.id]!;
    expect(reopened.fromDocument, isTrue);
    expect(reopened.documentChanged, isFalse);
  });

  test('a moved RCZ is found by its content and fused again', () async {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    final primary = day.runs.single.run;
    final path = p.join(root, 'day.fetproject');
    await saveDayDocument(
      path,
      dayDocument(
        eventId: newEventId(),
        name: 'Fused day',
        runs: day.runs,
        analysis: day.analysis,
        projectPath: path,
        fusions: day.fusions,
      ),
    );
    Directory(p.join(root, 'recordings')).renameSync(p.join(root, 'moved'));
    File(p.join(root, 'moved', 'drive.rcz')).renameSync(p.join(root, 'moved', 'renamed.rcz'));
    final missing = openDay(path);
    expect(missing.runs, isEmpty);
    expect(missing.alternatives.keys, [primary.id], reason: 'to find it with its run');

    final search = findMovedRecordings(
      p.join(root, 'moved'),
      missing.missing,
      missingAlternatives: [
        for (final recording in missing.missing)
          if (missing.alternatives[recording.runId] case final alternative?)
            alternative.missing(recording.name, 'Recording not found.'),
      ],
    );
    expect(search.found, {primary.id: p.join(root, 'moved', 'drive.vbo')});
    expect(search.alternatives, {primary.id: p.join(root, 'moved', 'renamed.rcz')});
    final relinked = openDay(
      path,
      relinked: search.found,
      relinkedAlternatives: search.alternatives,
    );
    final fusion = fuseOpenedDay(relinked)[primary.id]!;
    expect(fusion.fused, isTrue);
    expect(fusion.fromDocument, isTrue, reason: 'the same content: the decision applies');
    expect(fusion.documentChanged, isTrue, reason: 'its new place is saved');
  });
}

/// [run] with a constant speed: nothing to align on.
TelemetryRunProposal _flat(TelemetryRunProposal run) {
  final session = run.telemetry;
  final speedName = session.aliases['speed']!;
  final speed = session.channels[speedName]!;
  return TelemetryRunProposal(
    id: run.id,
    sourceId: run.sourceId,
    sourcePath: run.sourcePath,
    format: run.format,
    contentSha256: run.contentSha256,
    laps: run.laps,
    telemetry: TelemetrySession(
      duration: session.duration,
      startTime: session.startTime,
      metadata: session.metadata,
      channels: {
        ...session.channels,
        speedName: TelemetryChannel(
          name: speedName,
          unit: speed.unit,
          timestamps: speed.timestamps,
          values: Float32List(speed.values.length)..fillRange(0, speed.values.length, 72.0),
        ),
      },
      aliases: session.aliases,
      warnings: session.warnings,
      timingGates: session.timingGates,
      sampleCount: session.sampleCount,
    ),
  );
}
