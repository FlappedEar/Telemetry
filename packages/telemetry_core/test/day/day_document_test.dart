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

    // Saving the opened day again gives the same document.
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
    expect(fet.qtCompactJson(again), fet.qtCompactJson(opened.document));
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
}
