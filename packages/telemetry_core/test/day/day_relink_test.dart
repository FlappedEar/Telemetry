// Finding moved or renamed recordings by their identity, as Overlays relinks
// them, and opening the day with the saved group (FET-40).
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

void main() {
  late Directory directory;
  late String root;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('day_relink');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  String write(String relative, String text) {
    final file = File(p.join(root, relative))..createSync(recursive: true);
    file.writeAsStringSync(text);
    return file.path;
  }

  ({List<NamedRun> runs, DayAnalysis analysis}) importDay(List<String> paths) {
    final runs = nameRunsInRecordingOrder(prepareTelemetryImport(paths).runs);
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
    );
  }

  /// A saved day of a.vbo and b.vbo with an exclusion in b's session; returns
  /// the document's path and b's run id.
  Future<(String, String, Map<DayLapReference, String>)> saveDay() async {
    final a = write('day/recordings/a.vbo', circuitVbo([30, 28, 31]));
    final b = write('day/recordings/b.vbo', circuitVbo([29, 32, 27]));
    final day = importDay([a, b]);
    final bRun = day.runs.firstWhere((named) => named.run.sourcePath == b).run.id;
    final excluded = day.analysis.rows.firstWhere(
      (row) => row.runId == bRun && row.type == LapSectionType.lap,
    );
    final exclusions = {excluded.reference: 'Traffic'};
    final analysis = regroupDay(day.analysis, manualTracks: const {}, exclusions: exclusions);
    final path = p.join(root, 'day', 'day.fetproject');
    await saveDayDocument(
      path,
      dayDocument(
        eventId: newEventId(),
        name: 'Relink day',
        runs: day.runs,
        analysis: analysis,
        exclusions: exclusions,
        projectPath: path,
      ),
    );
    return (path, bRun, exclusions);
  }

  Map<String, Object?> primary(Map<String, Object?> document, String runId) {
    final run = ((document['event']! as Map)['runs']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((run) => run['id'] == runId);
    return ((run['sources']! as Map)['telemetry']! as List).cast<Map<String, Object?>>().first;
  }

  test('finds a moved and renamed recording by its content and saves its new path', () async {
    final (path, bRun, exclusions) = await saveDay();
    final before = readDayDocument(path);
    final moved = p.join(root, 'archive', 'deep', 'renamed session.vbo');
    Directory(p.dirname(moved)).createSync(recursive: true);
    File(p.join(root, 'day', 'recordings', 'b.vbo')).renameSync(moved);
    // Another recording with the old name is in the folder too.
    write('archive/b.vbo', circuitVbo([31, 31]));

    final opened = openDay(path);
    expect(opened.missing.single.runId, bRun);
    expect(opened.missing.single.contentSha256, primary(before, bRun)['contentSha256']);
    expect(opened.missing.single.fingerprint['kind'], 'telemetry-v1');
    final search = findMovedRecordings(p.join(root, 'archive'), opened.missing);
    expect(search.found, {bRun: moved});
    expect(search.different, isEmpty);

    final relinked = openDay(path, relinked: search.found);
    expect(relinked.missing, isEmpty);
    expect(relinked.relinked, {bRun});
    expect(relinked.exclusions, exclusions);
    final saved = dayDocument(
      eventId: relinked.eventId,
      name: relinked.name,
      runs: relinked.runs,
      analysis: relinked.analysis!,
      exclusions: relinked.exclusions,
      projectPath: path,
      previous: relinked.document,
      previousPath: path,
    );
    expect(fet.validateFetproject(saved), isNull);
    final source = primary(saved, bRun);
    final reference = source['reference']! as Map<String, Object?>;
    expect(reference['relativePath'], '../archive/deep/renamed session.vbo');
    expect(reference['absolutePath'], moved);
    // Same content: the same identity, configuration and exclusions.
    final old = primary(before, bRun);
    expect(source['contentSha256'], old['contentSha256']);
    expect(reference['fingerprint'], (old['reference']! as Map)['fingerprint']);
    expect((saved['event']! as Map)['lapExclusions'], (before['event']! as Map)['lapExclusions']);
    // Opening the saved day needs no relink.
    await saveDayDocument(path, saved);
    final reopened = openDay(path);
    expect(reopened.missing, isEmpty);
    expect(reopened.relinked, isEmpty);
  });

  test('refuses a different recording with the same name', () async {
    final (path, bRun, _) = await saveDay();
    File(p.join(root, 'day', 'recordings', 'b.vbo')).deleteSync();
    final other = write('elsewhere/b.vbo', circuitVbo([29, 32, 28]));
    final opened = openDay(path);
    final search = findMovedRecordings(p.join(root, 'elsewhere'), opened.missing);
    expect(search.found, isEmpty);
    expect(search.different, {bRun: other});
    // Even when asked to use it, opening refuses it.
    final forced = openDay(path, relinked: {bRun: other});
    expect(forced.missing.single.reason, 'The file found is a different recording.');
    expect(forced.relinked, isEmpty);
  });

  test('a recording with the same content but another fingerprint is refused', () async {
    final (path, bRun, _) = await saveDay();
    final document = readDayDocument(path);
    final reference = primary(document, bRun)['reference']! as Map<String, Object?>;
    final fingerprint = {...reference['fingerprint']! as Map<String, Object?>, 'sampleCount': 1};
    reference['fingerprint'] = fingerprint;
    // The binding of the track configuration follows the fingerprint.
    final run = ((document['event']! as Map)['runs']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((run) => run['id'] == bRun);
    (run['trackConfiguration']! as Map)['sourceFingerprint'] = fingerprint;
    (primary(document, bRun)['importProvenance']! as Map)['fingerprint'] = fingerprint;
    await saveDayDocument(path, document);
    final opened = openDay(path);
    expect(
      opened.missing.single,
      isA<MissingRecording>().having(
        (m) => m.reason,
        'reason',
        'The file found is a different recording.',
      ),
    );
  });

  test(
    'finds by fingerprint when the document has no content SHA-256, by name when it has neither',
    () async {
      final (path, bRun, _) = await saveDay();
      final document = readDayDocument(path);
      final source = primary(document, bRun);
      source.remove('contentSha256');
      source.remove('importProvenance');
      await saveDayDocument(path, document);
      final moved = p.join(root, 'found', 'renamed.vbo');
      Directory(p.dirname(moved)).createSync();
      File(p.join(root, 'day', 'recordings', 'b.vbo')).renameSync(moved);

      var opened = openDay(path);
      expect(opened.missing.single.contentSha256, isEmpty);
      expect(findMovedRecordings(p.join(root, 'found'), opened.missing).found, {bRun: moved});

      // Without any identity only the name can find it.
      final reference = source['reference']! as Map<String, Object?>;
      reference.remove('fingerprint');
      final run = ((document['event']! as Map)['runs']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((run) => run['id'] == bRun);
      (run['trackConfiguration']! as Map)['sourceFingerprint'] = <String, Object?>{};
      (document['event']! as Map).remove('lapExclusions');
      await saveDayDocument(path, document);
      opened = openDay(path);
      expect(opened.missing.single.fingerprint, isEmpty);
      expect(findMovedRecordings(p.join(root, 'found'), opened.missing).found, isEmpty);
      final named = p.join(root, 'found', 'b.vbo');
      File(moved).renameSync(named);
      final search = findMovedRecordings(p.join(root, 'found'), opened.missing);
      expect(search.found, {bRun: named});
      expect(openDay(path, relinked: search.found).missing, isEmpty);
    },
  );

  test('opens with the saved group and keeps it while it cannot be shown', () async {
    final a = write('day/a.vbo', circuitVbo([30, 28, 31]));
    final b = write('day/b.vbo', circuitVbo([29, 32, 27]));
    final day = importDay([a, b]);
    final bRun = day.runs.firstWhere((named) => named.run.sourcePath == b).run.id;
    // b in its own layout: two groups; b's has fewer laps and is not the default.
    final regrouped = regroupDay(
      day.analysis,
      manualTracks: {
        bRun: const TrackConfiguration(
          layoutId: 'Club',
          direction: TrackDirection.counterclockwise,
        ),
      },
    );
    final bGroup = regrouped.configurations[bRun]!.compatibilityGroupId!;
    final shown = regroupDay(
      day.analysis,
      manualTracks: {
        bRun: const TrackConfiguration(
          layoutId: 'Club',
          direction: TrackDirection.counterclockwise,
        ),
      },
      preferredGroupId: bGroup,
    );
    expect(shown.chosenGroupId, bGroup);
    expect(regrouped.chosenGroupId, isNot(bGroup));
    final path = p.join(root, 'day', 'day.fetproject');
    await saveDayDocument(
      path,
      dayDocument(
        eventId: newEventId(),
        name: 'Two layouts',
        runs: day.runs,
        analysis: shown,
        projectPath: path,
      ),
    );
    expect(openDay(path).analysis!.chosenGroupId, bGroup);

    // b's recording is missing: its group cannot be shown, and stays saved.
    File(b).deleteSync();
    final opened = openDay(path);
    expect(opened.analysis!.chosenGroupId, isNot(bGroup));
    Map<String, Object?> save({bool groupChosen = false}) => dayDocument(
      eventId: opened.eventId,
      name: opened.name,
      runs: opened.runs,
      analysis: opened.analysis!,
      projectPath: path,
      previous: opened.document,
      previousPath: path,
      groupChosen: groupChosen,
    );
    String? savedGroup(Map<String, Object?> document) =>
        ((document['event']! as Map)['analysisDecisions']! as Map)['comparisonGroupId'] as String?;
    expect(savedGroup(save()), bGroup);
    expect(savedGroup(save(groupChosen: true)), opened.analysis!.chosenGroupId);
  });
}
