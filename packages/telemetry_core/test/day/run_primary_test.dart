// A run's recordings (FET-57): "Make primary" and the manual clock check
// with its accept or refuse, on synthetic VBO/RCZ pairs: no real data.
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_pair.dart';

void main() {
  late Directory directory;
  late String root;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('run_primary');
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

  Map<String, Object?> save(
    String path,
    List<NamedRun> runs,
    DayAnalysis analysis,
    Map<String, RunFusion> fusions, {
    OpenedDay? previous,
  }) {
    final document = dayDocument(
      eventId: previous?.eventId ?? 'event',
      name: 'Day',
      runs: runs,
      analysis: analysis,
      projectPath: path,
      previous: previous?.document,
      previousPath: path,
      fusions: fusions,
    );
    expect(fet.validateFetproject(document), isNull);
    return document;
  }

  test('replacing a run gives the day analysed with that run read from the other recording', () {
    final recordings = p.join(root, 'recordings');
    final (vbo1, rcz1) = writeFusionPair(recordings, name: 'first');
    final (vbo2, _) = writeFusionPair(
      recordings,
      name: 'second',
      speeds: const [31, 28, 30, 27, 33, 29],
    );
    final day = importDay([vbo1, rcz1, vbo2]);
    expect(day.runs, hasLength(2));
    final named = day.runs.first;
    final fusion = day.fusions[named.run.id]!;
    final rcz = runFromRecording(named.run, fusion.alternative!);
    expect(rcz.id, named.run.id);
    expect(rcz.sourceId, fusion.alternativeSourceId);
    expect(rcz.format, RecordingFormat.rcz);
    final others = day.analysis.rows.where((row) => row.runId != named.run.id).length;
    final part = analyzeNewPrimary(rcz, named.name, otherRows: others);
    final replaced = replaceDayRun(
      day.analysis,
      named.run.id,
      part,
      sourceOrder: runSourceOrder(day.analysis, named.run.id, 0),
    );
    final expected = analyzeDay([
      for (final run in [rcz, day.runs.last.run])
        DayRunInput(
          runId: run.id,
          name: day.runs.firstWhere((other) => other.run.id == run.id).name,
          contentSha256: run.contentSha256,
          session: run.telemetry,
          laps: run.laps,
        ),
    ]);
    String rows(DayAnalysis analysis) => [
      for (final row in analysis.rows)
        '${row.runId} ${row.sourceRevision} ${row.type.label} ${row.lapNumber} '
            '${row.start} ${row.end} ${row.sourceOrder} ${row.offRoute}',
    ].join('\n');
    expect(rows(replaced), rows(expected));
    expect(replaced.chosenGroupId, expected.chosenGroupId);
    expect(
      replaced.ranking?.bestOfDay?.durationSeconds,
      expected.ranking?.bestOfDay?.durationSeconds,
    );
    expect(
      replaced.rows
          .where((row) => row.runId == named.run.id)
          .map((row) => row.sourceRevision)
          .toSet(),
      {rcz.contentSha256},
    );
    expect(
      () => replaceDayRun(day.analysis, 'another run', part, sourceOrder: 0),
      throwsArgumentError,
    );
  });

  test('making the RCZ primary saves it as Overlays does and keeps the VBO beside it', () async {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    final named = day.runs.single;
    final fused = day.fusions[named.run.id]!;
    expect(fused.fused, isTrue);
    final path = p.join(root, 'day.fetproject');
    await saveDayDocument(path, save(path, day.runs, day.analysis, day.fusions));
    final opened = openDay(path);
    expect(runJson(opened.document, named.run.id)['fusion'], isA<Map<String, Object?>>());
    final applied = fuseOpenedDay(opened);

    // Make primary: the RCZ is read as the run, the VBO kept beside it.
    final rczRun = runFromRecording(named.run, applied[named.run.id]!.alternative!);
    final part = analyzeNewPrimary(rczRun, named.name);
    final analysis = replaceDayRun(opened.analysis!, named.run.id, part, sourceOrder: 0);
    final runs = [(run: rczRun, name: named.name)];
    final kept = RunFusion.primaryOnly(
      primary: rczRun,
      alternative: runFromRecording(named.run, named.run),
    );
    expect(kept.state, RunFusionState.primaryOnly);
    expect(kept.decision, isNull);
    final document = save(path, runs, analysis, {named.run.id: kept}, previous: opened);
    final run = runJson(document, named.run.id);
    expect(run['primaryTelemetrySourceId'], fused.alternativeSourceId);
    expect(run.containsKey('fusion'), isFalse, reason: 'the fusion no longer applies');
    final configuration = run['trackConfiguration'] as Map<String, Object?>;
    expect(configuration['sourceId'], fused.alternativeSourceId);
    expect(configuration['layoutId'], isNull);
    expect(configuration['direction'], 'unknown');
    final sources = ((run['sources'] as Map)['telemetry'] as List).cast<Map<String, Object?>>();
    expect(
      [for (final source in sources) source['id']],
      [named.run.sourceId, fused.alternativeSourceId],
    );
    expect(
      (configuration['sourceFingerprint'] as Map),
      ((sources.last['reference'] as Map)['fingerprint'] as Map),
    );
    await saveDayDocument(path, document);

    // Opened again: the RCZ is the run, the VBO is kept apart, not aligned.
    final again = openDay(path);
    expect(again.runs.single.run.format, RecordingFormat.rcz);
    expect(again.runs.single.run.sourceId, fused.alternativeSourceId);
    final alternative = again.alternatives[named.run.id]!;
    expect(alternative.sourceId, named.run.sourceId);
    expect(alternative.automatic, isFalse);
    final reopened = fuseOpenedDay(again)[named.run.id]!;
    expect(reopened.state, RunFusionState.primaryOnly);
    expect(reopened.alignment, isNull, reason: 'not aligned');
    expect(reopened.alternative!.format, RecordingFormat.vbo);
    // Saved again unchanged but for the revision.
    final resaved = save(path, again.runs, again.analysis!, {
      named.run.id: reopened,
    }, previous: again);
    expect(runJson(resaved, named.run.id), runJson(document, named.run.id));

    // Making the VBO primary again: the RCZ is fused automatically again.
    final vboRun = runFromRecording(again.runs.single.run, reopened.alternative!);
    final back = replaceDayRun(
      again.analysis!,
      named.run.id,
      analyzeNewPrimary(vboRun, named.name),
      sourceOrder: 0,
    );
    await saveDayDocument(
      path,
      save(
        path,
        [(run: vboRun, name: named.name)],
        back,
        {named.run.id: RunFusion.primaryOnly(primary: vboRun, alternative: again.runs.single.run)},
        previous: again,
      ),
    );
    final third = openDay(path);
    expect(third.runs.single.run.sourceId, named.run.sourceId);
    expect(third.alternatives[named.run.id]!.automatic, isTrue);
    expect(fuseOpenedDay(third)[named.run.id]!.fused, isTrue);
  });

  test('the clock check measures the offset and keeps the rules chosen for the recording', () {
    final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
    final day = importDay([vbo, rcz]);
    final primary = day.runs.single.run;
    final chosen = withFusionRule(day.fusions[primary.id]!, primary, 'sats', FusionRule.fillGaps)!;
    final checked = checkRunClock(primary, chosen.alternative!, chosen.decision);
    expect(checked.fused, isTrue);
    expect(checked.fromDocument, isFalse);
    final alignment = checked.alignment!;
    expect(alignment.status, alignmentAligned);
    expect(alignment.offset, closeTo(0.1, 0.02), reason: 'the RCZ starts 0.1 s later');
    expect(checked.clock.offsetSeconds, alignment.offset);
    expect(checked.rules['sats'], FusionRule.fillGaps);
    expect(checked.decision!['clock'], chosen.decision!['clock']);
  });

  test(
    'a refused alignment removes the fusion, as Overlays does, and the run reads the primary only',
    () async {
      final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
      final day = importDay([vbo, rcz]);
      final named = day.runs.single;
      final path = p.join(root, 'day.fetproject');
      await saveDayDocument(path, save(path, day.runs, day.analysis, day.fusions));
      final opened = openDay(path);
      final fusion = fuseOpenedDay(opened)[named.run.id]!;
      final checked = checkRunClock(named.run, fusion.alternative!, fusion.decision);
      final refused = RunFusion.primaryOnly(
        primary: named.run,
        alternative: checked.alternative!,
        alignment: checked.alignment,
        declined: true,
      );
      expect(refused.session, isNull, reason: 'the analysis reads the primary only');
      expect(refused.channelOrigins, isEmpty);
      expect(refused.status, alignmentAligned);
      final document = save(path, opened.runs, opened.analysis!, {
        named.run.id: refused,
      }, previous: opened);
      final run = runJson(document, named.run.id);
      expect(run.containsKey('fusion'), isFalse);
      expect(run['fusionDeclined'], fusion.alternative!.sourceId);
      expect(run['primaryTelemetrySourceId'], named.run.sourceId);
      expect(((run['sources'] as Map)['telemetry'] as List), hasLength(2), reason: 'the RCZ stays');
      await saveDayDocument(path, document);
      // A refusal made by the user is saved as `fusionDeclined`, so the RCZ
      // is not fused again when the day opens (FET-142)...
      final again = openDay(path);
      expect(again.alternatives[named.run.id]!.automatic, isFalse);
      expect(fuseOpenedDay(again)[named.run.id]!.state, RunFusionState.primaryOnly);
    },
  );

  group('an exclusion and a comparison pair of the VBO across VBO, RCZ and VBO again', () {
    // Saves [runs] at [path] as the day [previous] was opened, with
    // [exclusions], the comparison [slots] and [fusions].
    Future<OpenedDay> saveAndOpen(
      String path,
      List<NamedRun> runs,
      DayAnalysis analysis,
      Map<String, RunFusion> fusions, {
      OpenedDay? previous,
      Map<DayLapReference, String> exclusions = const {},
      List<DayLapReference?>? slots,
    }) async {
      final document = dayDocument(
        eventId: previous?.eventId ?? 'event',
        name: 'Day',
        runs: runs,
        analysis: analysis,
        exclusions: exclusions,
        projectPath: path,
        previous: previous?.document,
        previousPath: path,
        fusions: fusions,
        comparison: ComparisonDecisions(slots: slots),
      );
      expect(fet.validateFetproject(document), isNull);
      await saveDayDocument(path, document);
      return openDay(path);
    }

    // [day]'s run read from its other recording, as "Make primary" does,
    // with the exclusions the app then has: those the document keeps for the
    // new primary's laps.
    (List<NamedRun>, DayAnalysis, Map<String, RunFusion>, Map<DayLapReference, String>) switched(
      OpenedDay day,
      TelemetryRunProposal other,
    ) {
      final named = day.runs.single;
      final primary = runFromRecording(named.run, other);
      // Rebuilt from the saved document, as the app does.
      final exclusions = recordingExclusions(day.document, named.run.id, primary);
      return (
        [(run: primary, name: named.name)],
        replaceDayRun(
          day.analysis!,
          named.run.id,
          analyzeNewPrimary(primary, named.name),
          sourceOrder: 0,
          exclusions: exclusions,
        ),
        {named.run.id: RunFusion.primaryOnly(primary: primary, alternative: named.run)},
        exclusions,
      );
    }

    test('saved before the switch, kept as stored and applied again', () async {
      final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
      final day = importDay([vbo, rcz]);
      final runId = day.runs.single.run.id;
      final laps = day.analysis.rows
          .where((row) => row.type == LapSectionType.lap && row.referenceEligible)
          .toList();
      expect(laps.length, greaterThanOrEqualTo(3));
      final excluded = laps[0].reference;
      final pair = [laps[1].reference, laps[2].reference];
      final path = p.join(root, 'day.fetproject');
      final rczRecording = day.fusions[runId]!.alternative!;

      var opened = await saveAndOpen(
        path,
        day.runs,
        day.analysis,
        day.fusions,
        exclusions: {excluded: 'Traffic'},
        slots: pair,
      );
      final stored = readDayDocument(path)['event'] as Map;
      expect(opened.exclusions, {excluded: 'Traffic'});
      expect(opened.comparison.slots, pair);

      // The RCZ made primary and saved: the VBO's exclusion and pair are
      // kept exactly as stored.
      final (rczRuns, rczAnalysis, rczFusions, rczExclusions) = switched(opened, rczRecording);
      expect(rczExclusions, isEmpty);
      // An exclusion of the old recording left in the session is not written.
      opened = await saveAndOpen(
        path,
        rczRuns,
        rczAnalysis,
        rczFusions,
        previous: opened,
        exclusions: {excluded: 'Other'},
      );
      final event = readDayDocument(path)['event'] as Map;
      expect(event['lapExclusions'], stored['lapExclusions']);
      expect(
        (event['analysisDecisions'] as Map)['comparisonSlots'],
        (stored['analysisDecisions'] as Map)['comparisonSlots'],
      );
      // Not laps of the RCZ: not applied while it is primary.
      expect(opened.runs.single.run.format, RecordingFormat.rcz);
      expect(opened.exclusions, isEmpty);
      expect(opened.comparison.slots, [null, null]);

      // The VBO made primary again and the day reopened: both apply again.
      final kept = fuseOpenedDay(opened)[runId]!;
      final (vboRuns, vboAnalysis, vboFusions, vboExclusions) = switched(opened, kept.alternative!);
      // Switched back, the VBO's exclusion applies at once.
      expect(vboExclusions, {excluded: 'Traffic'});
      expect(vboAnalysis.rows.firstWhere((row) => row.reference == excluded), isNotNull);
      opened = await saveAndOpen(
        path,
        vboRuns,
        vboAnalysis,
        vboFusions,
        previous: opened,
        exclusions: vboExclusions,
      );
      expect(opened.runs.single.run.sourceId, day.runs.single.run.sourceId);
      expect(opened.exclusions, {excluded: 'Traffic'});
      expect(opened.comparison.slots, pair);
      expect(((readDayDocument(path)['event'] as Map)['lapExclusions'] as List), hasLength(1));
    });

    test('documentComparison matches a switched run as saved with its new primary', () async {
      final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
      final day = importDay([vbo, rcz]);
      final runId = day.runs.single.run.id;
      final laps = day.analysis.rows
          .where((row) => row.type == LapSectionType.lap && row.referenceEligible)
          .toList();
      final pair = [laps[1].reference, laps[2].reference];
      final path = p.join(root, 'day.fetproject');
      var opened = await saveAndOpen(path, day.runs, day.analysis, day.fusions, slots: pair);
      final (rczRuns, rczAnalysis, rczFusions, _) = switched(
        opened,
        day.fusions[runId]!.alternative!,
      );
      // The document still saves the VBO as primary: a pair of its laps is
      // not one of the RCZ's.
      expect(documentComparison(opened.document, rczRuns).slots, [null, null]);

      opened = await saveAndOpen(path, rczRuns, rczAnalysis, rczFusions, previous: opened);
      expect(opened.runs.single.run.format, RecordingFormat.rcz);
      expect(documentComparison(opened.document, opened.runs).slots, [null, null]);
      // The VBO primary again, before saving: the document saves the RCZ,
      // yet the pair of the VBO's laps applies.
      final (vboRuns, _, _, _) = switched(opened, fuseOpenedDay(opened)[runId]!.alternative!);
      expect(documentComparison(opened.document, vboRuns).slots, pair);
    });
  });
}
