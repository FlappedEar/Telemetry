// A day built and saved by FlappedEar Overlays' own code (the committed
// fixture, see tool/README.md, cpp_project_roundtrip) opens in Telemetry with
// the same sessions, laps, exclusions, group, segments and results Overlays
// reported, and Telemetry's re-save keeps every field Overlays wrote (FET-40).
// Pure Dart: runs in CI.
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/roundtrip.dart';

/// [document] (the committed fixture) with the folder Overlays wrote it in
/// replaced by [folder] in its absolute paths.
Map<String, Object?> movedTo(Map<String, Object?> document, String folder) =>
    jsonDecode(jsonEncode(document).replaceAll('"$overlaysFixtureFolder/', '"$folder/'))
        as Map<String, Object?>;

void main() {
  late Directory directory;
  late String path;
  late Map<String, Object?> inspected;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('overlays_fixture');
    copyRoundtripFixtures(directory.path);
    path = p.join(directory.resolveSymbolicLinksSync(), 'overlays-day.fetproject');
    inspected = jsonDecode(
      File(p.join(directory.path, 'overlays-day.inspected.json')).readAsStringSync(),
    ) as Map<String, Object?>;
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('the fixture is what Overlays writes: valid, with segments, exclusions and lap names', () {
    final document = readDayDocument(path);
    expect(fet.validateFetproject(document), isNull);
    final event = document['event']! as Map<String, Object?>;
    final runs = (event['runs']! as List).cast<Map<String, Object?>>();
    expect([for (final run in runs) run['name']], ['Session 1', 'Session 2', 'Session 3']);
    expect(runs.where((run) => run['trackSegments'] != null), hasLength(1));
    expect(event['lapExclusions'], hasLength(1));
    // Overlays-only state the fixture carries: editor sync, video and
    // channels, the scene, export and map settings, comparison decisions.
    expect(document.keys, containsAll(['scene', 'analysis', 'mapSettings', 'exportSettings']));
    expect(
      (event['analysisDecisions']! as Map).keys,
      containsAll([
        'comparisonGroupId',
        'comparisonSlots',
        'comparisonRange',
        'comparisonChannels',
      ]),
    );
    expect((runs.first['sources']! as Map)['video'], isNotNull);
  });

  test('Telemetry opens it as Overlays does', () {
    final day = openDay(path);
    expect(day.missing, isEmpty);
    final differences = jsonDifferences(
      telemetryView(day),
      overlaysView(inspected),
      tolerance: 1e-9,
    );
    expect(differences, isEmpty);
    expect(day.analysis!.chosenGroupId, startsWith('compatibility-v1:'));
  });

  test('Telemetry re-saves it keeping everything Overlays wrote', () async {
    final day = openDay(path);
    final original = readDayDocument(path);
    final document = dayDocument(
      eventId: day.eventId,
      name: day.name,
      runs: day.runs,
      analysis: day.analysis!,
      exclusions: day.exclusions,
      projectPath: path,
      previous: day.document,
      previousPath: path,
    );
    await saveDayDocument(path, document);
    final saved = readDayDocument(path);
    expect(fet.validateFetproject(saved), isNull);
    // The same document but for the revision, which continues, and the
    // absolute paths, which follow the moved folder as Overlays rebases them;
    // exclusions are kept as a set (Telemetry orders them by session and time).
    expect((saved['documentState']! as Map)['id'], (original['documentState']! as Map)['id']);
    expect(
      int.parse((saved['documentState']! as Map)['savedRevision']! as String),
      int.parse((original['documentState']! as Map)['savedRevision']! as String) + 1,
    );
    expect(
      jsonDifferences(
        {...saved, 'documentState': null},
        {...movedTo(original, p.dirname(path)), 'documentState': null},
        unordered: const {'event.lapExclusions'},
      ),
      isEmpty,
    );
    // And it opens again the same.
    final reopened = openDay(path);
    final view = telemetryView(reopened)..remove('documentState');
    final expected = overlaysView(inspected)..remove('documentState');
    expect(jsonDifferences(view, expected, tolerance: 1e-9), isEmpty);
  });
}
