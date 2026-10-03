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
    directory = Directory.systemTemp.createTempSync('day_document');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  String write(String relative, String text) {
    final file = File(p.join(root, relative))..createSync(recursive: true);
    file.writeAsStringSync(text);
    return file.path;
  }

  ({List<NamedRun> runs, DayAnalysis analysis}) importDay(List<String> paths) {
    final plan = prepareTelemetryImport(paths);
    final runs = nameRunsInRecordingOrder(plan.runs);
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

  test('saves a day and opens it with its layouts and exclusions', () async {
    final a = write('recordings/a.vbo', circuitVbo([30, 28, 31]));
    final b = write('recordings/b.vbo', circuitVbo([29, 32]));
    final day = importDay([a, b]);
    final best = day.analysis.ranking!.bestOfDay!;
    final exclusions = {best.reference: 'Traffic'};
    final bId = day.runs.firstWhere((named) => named.run.sourcePath == b).run.id;
    final analysis = regroupDay(
      day.analysis,
      manualTracks: {
        bId: const TrackConfiguration(layoutId: 'Club', direction: TrackDirection.counterclockwise),
      },
      exclusions: exclusions,
    );
    final path = p.join(root, 'day.fetproject');
    final document = dayDocument(
      eventId: newEventId(),
      name: 'Test day',
      runs: day.runs,
      analysis: analysis,
      exclusions: exclusions,
      projectPath: path,
    );
    expect(fet.validateFetproject(document), isNull);
    final runs = (document['event'] as Map)['runs'] as List;
    final reference = (((runs.first as Map)['sources'] as Map)['telemetry'] as List).first as Map;
    expect((reference['reference'] as Map)['relativePath'], startsWith('recordings/'));
    expect(((reference['reference'] as Map)['fingerprint'] as Map)['kind'], 'telemetry-v1');
    final aJson = runs.firstWhere((run) => (run as Map)['id'] != bId) as Map;
    expect((aJson['trackInference'] as Map)['layoutId'], startsWith('gps-route-v1:'));
    expect((aJson['trackConfiguration'] as Map)['layoutId'], isNull);
    await saveDayDocument(path, document);

    final opened = openDay(path);
    expect(opened.missing, isEmpty);
    expect(opened.name, 'Test day');
    expect(
      [for (final named in opened.runs) named.name],
      [for (final named in day.runs) named.name],
    );
    expect(opened.exclusions, exclusions);
    expect(opened.analysis!.manualTracks[bId]?.layoutId, 'Club');
    expect(opened.analysis!.ranking!.bestOfDay!.reference, analysis.ranking!.bestOfDay!.reference);
    expect(opened.analysis!.ranking!.bestOfDay!.reference, isNot(best.reference));

    // Saving the opened day again gives the same document, one saved
    // revision later.
    final again = dayDocument(
      eventId: opened.eventId,
      name: opened.name,
      runs: opened.runs,
      analysis: opened.analysis!,
      exclusions: opened.exclusions,
      projectPath: path,
      previous: opened.document,
      previousPath: path,
    );
    final state = opened.document['documentState'] as Map;
    expect(state['savedRevision'], '1');
    expect(again['documentState'], {'id': state['id'], 'savedRevision': '2'});
    expect(
      fet.qtCompactJson({...again, 'documentState': state}),
      fet.qtCompactJson(opened.document),
    );
  });

  group('comparison decisions (FET-53)', () {
    Map<String, Object?> decisionsOf(Map<String, Object?> document) =>
        ((document['event'] as Map)['analysisDecisions'] as Map? ?? const {})
            .cast<String, Object?>();

    test('the group is saved only when the user chose it', () async {
      final day = importDay([
        write('a.vbo', circuitVbo([30, 28, 31])),
      ]);
      final path = p.join(root, 'day.fetproject');
      Map<String, Object?> save({Map<String, Object?>? previous, bool groupChosen = false}) =>
          dayDocument(
            eventId: 'event',
            name: 'Day',
            runs: day.runs,
            analysis: day.analysis,
            projectPath: path,
            previous: previous,
            previousPath: path,
            groupChosen: groupChosen,
          );
      // Never chosen: no decision, also on a save of a day saved so.
      final automatic = save();
      expect((automatic['event'] as Map).containsKey('analysisDecisions'), isFalse);
      expect((save(previous: automatic)['event'] as Map).containsKey('analysisDecisions'), isFalse);
      // Chosen: saved, and kept by later saves.
      final chosen = save(previous: automatic, groupChosen: true);
      expect(decisionsOf(chosen)['comparisonGroupId'], day.analysis.chosenGroupId);
      expect(decisionsOf(save(previous: chosen))['comparisonGroupId'], day.analysis.chosenGroupId);
    });

    test('saves the pair, range and charts and opens them again', () async {
      final a = write('recordings/a.vbo', circuitVbo([30, 28, 31]));
      final b = write('recordings/b.vbo', circuitVbo([29, 32, 27]));
      final day = importDay([a, b]);
      final laps = day.analysis.ranking!.eligibleLaps;
      final path = p.join(root, 'day.fetproject');
      final document = dayDocument(
        eventId: newEventId(),
        name: 'Compared',
        runs: day.runs,
        analysis: day.analysis,
        projectPath: path,
        comparison: ComparisonDecisions(
          slots: [laps[0].reference, laps[1].reference],
          range: (12.5, 240.0),
          channels: const ['Δ time', 'velocity'],
        ),
      );
      expect(fet.validateFetproject(document), isNull);
      final decisions = decisionsOf(document);
      expect(decisions.containsKey('comparisonGroupId'), isFalse);
      final slots = decisions['comparisonSlots'] as List;
      expect((slots.first as Map)['runId'], laps[0].runId);
      expect((slots.first as Map)['type'], 'LAP');
      expect(decisions['comparisonRange'], {'startMeters': 12.5, 'endMeters': 240.0});
      expect(decisions['comparisonChannels'], ['Δ time', 'velocity']);
      // Keys of another version are kept.
      decisions['futureDecision'] = {'kept': true};
      (document['event'] as Map)['analysisDecisions'] = decisions;
      await saveDayDocument(path, document);

      final opened = openDay(path);
      expect(opened.comparison.slots, [laps[0].reference, laps[1].reference]);
      expect(opened.comparison.range, (12.5, 240.0));
      expect(opened.comparison.channels, ['Δ time', 'velocity']);
      // Saved again without changes: the same decisions.
      final again = dayDocument(
        eventId: opened.eventId,
        name: opened.name,
        runs: opened.runs,
        analysis: opened.analysis!,
        projectPath: path,
        previous: opened.document,
        previousPath: path,
      );
      expect(decisionsOf(again), decisions);
      // An invalid range or channel list is not written.
      final refused = dayDocument(
        eventId: opened.eventId,
        name: opened.name,
        runs: opened.runs,
        analysis: opened.analysis!,
        projectPath: path,
        previous: opened.document,
        previousPath: path,
        comparison: const ComparisonDecisions(range: (50, 10), channels: ['a', 'b', 'c', 'd', 'e']),
      );
      expect(decisionsOf(refused), decisions);

      // A lap of a changed recording is not one of the day's: read as no lap,
      // and kept in the document as it was.
      File(b).writeAsStringSync(circuitVbo([31, 30]));
      final changed = openDay(path);
      final bRun = day.runs.firstWhere((named) => named.run.sourcePath == b).run.id;
      expect(changed.comparison.slots, [
        for (final lap in [laps[0], laps[1]]) lap.runId == bRun ? null : lap.reference,
      ]);
    });
  });

  test('opens the rest of the day when a recording is missing or changed', () async {
    final a = write('a.vbo', circuitVbo([30, 28, 31]));
    final b = write('b.vbo', circuitVbo([29, 32]));
    final day = importDay([a, b]);
    final path = p.join(root, 'day.fetproject');
    final document = dayDocument(
      eventId: newEventId(),
      name: 'Test day',
      runs: day.runs,
      analysis: day.analysis,
      projectPath: path,
    );
    (document['event'] as Map)['futureEvent'] = {'kept': true};
    await saveDayDocument(path, document);

    final moved = p.join(root, 'moved', 'b.vbo');
    Directory(p.dirname(moved)).createSync();
    File(b).renameSync(moved);
    File(a).writeAsStringSync(circuitVbo([30, 28, 30]));
    final opened = openDay(path);
    expect(opened.runs, isEmpty);
    expect(
      {for (final m in opened.missing) m.path: m.reason},
      {'a.vbo': 'The file found is a different recording.', 'b.vbo': 'Recording not found.'},
    );

    final bRun = day.runs.firstWhere((named) => named.run.sourcePath == b).run.id;
    final relinked = openDay(path, relinked: {bRun: moved});
    expect(relinked.runs.single.run.id, bRun);
    expect(relinked.analysis, isNotNull);

    // Saving keeps the run that did not open, and unknown keys.
    final saved = dayDocument(
      eventId: relinked.eventId,
      name: relinked.name,
      runs: relinked.runs,
      analysis: relinked.analysis!,
      projectPath: path,
      previous: relinked.document,
      previousPath: path,
    );
    expect(fet.validateFetproject(saved), isNull);
    final event = saved['event'] as Map;
    expect(event['runs'] as List, hasLength(2));
    expect(event['futureEvent'], {'kept': true});
    final bJson = (event['runs'] as List).firstWhere((run) => (run as Map)['id'] == bRun) as Map;
    final bReference = ((bJson['sources'] as Map)['telemetry'] as List).first as Map;
    expect((bReference['reference'] as Map)['relativePath'], 'moved/b.vbo');
  });

  test('opens the Overlays sample event with its recordings', () {
    final folder = p.join(root, 'sample');
    Directory(folder).createSync();
    for (final name in ['event-laps.vbo', 'basic.vbo']) {
      File('test/fixtures/$name').copySync(p.join(folder, name));
    }
    File('../fetproject/test/fixtures/event-demo.fetproject')
        .copySync(p.join(folder, 'event.fetproject'));
    final opened = openDay(p.join(folder, 'event.fetproject'));
    expect(opened.missing, isEmpty);
    expect(
      [for (final named in opened.runs) named.name],
      ['Run 1 — synthetic GPS laps', 'Run 2 — synthetic channels'],
    );
    expect(opened.runs.first.run.id, 'demo-laps');
  });

  test('names a day after its first dated recording', () {
    expect(defaultDayName(const []), 'Day');
    expect(newEventId(), matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('continues the document identity and saved revision', () {
    final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final first = nextDocumentState(null);
    expect(first['id'], matches(uuid));
    expect(first['savedRevision'], '1');
    final second = nextDocumentState({...first, 'extra': true});
    expect(second, {'id': first['id'], 'savedRevision': '2', 'extra': true});
    expect(nextDocumentState({'id': 'overlays-id', 'savedRevision': '41'})['savedRevision'], '42');
    expect(
      nextDocumentState({'id': 'x', 'savedRevision': '18446744073709551615'})['savedRevision'],
      '18446744073709551615',
    );
    for (final malformed in [
      {'id': '', 'savedRevision': '3'},
      {'id': 'x', 'savedRevision': 3},
      {'id': 'x', 'savedRevision': '18446744073709551616'},
      {'id': 'x' * 129, 'savedRevision': '3'},
    ]) {
      final state = nextDocumentState(malformed);
      expect(state['id'], matches(uuid));
      expect(state['savedRevision'], '1');
    }
  });
}
