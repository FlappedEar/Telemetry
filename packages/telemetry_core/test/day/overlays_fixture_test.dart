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

/// [value] with what FET-250 moved on opening a day saved with `gates-v1:`
/// (the group ids, the gate revisions and the keys derived from them) set
/// to one placeholder, so the rest of Overlays' day is compared as it was.
Object? withoutMigratedIds(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: switch (entry.key) {
          'comparisonGroupId' ||
          'groupId' ||
          'trackConfigurationReference' ||
          'gateRevision' ||
          'derivationKey' ||
          'revision' => entry.value is String ? 'migrated' : entry.value,
          _ => withoutMigratedIds(entry.value),
        },
    };
  }
  if (value is List) return [for (final item in value) withoutMigratedIds(item)];
  return value;
}

/// Every string of [value] under a key named [key].
Iterable<String> valuesOf(Object? value, String key) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key == key && entry.value is String) yield entry.value! as String;
      yield* valuesOf(entry.value, key);
    }
  } else if (value is List) {
    for (final item in value) {
      yield* valuesOf(item, key);
    }
  }
}

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
      withoutMigratedIds(telemetryView(day)) as Map<String, Object?>,
      withoutMigratedIds(overlaysView(inspected)) as Map<String, Object?>,
      tolerance: 1e-9,
    );
    expect(differences, isEmpty);
    final shown = day.analysis!.chosenGroupId!;
    expect(shown, startsWith('compatibility-v1:'));
    // The day was saved with the gate revision of before FET-250: the group
    // shown, and the segments kept under its id, follow to the new id.
    expect(overlaysView(inspected)['comparisonGroupId'], isNot(shown));
    final event = day.document['event']! as Map<String, Object?>;
    expect((event['analysisDecisions']! as Map)['comparisonGroupId'], shown);
    final references = valuesOf(event['runs'], 'trackConfigurationReference').toSet();
    expect(references, {shown});
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
        withoutMigratedIds({...saved, 'documentState': null}) as Map<String, Object?>,
        withoutMigratedIds({...movedTo(original, p.dirname(path)), 'documentState': null})
            as Map<String, Object?>,
        unordered: const {'event.lapExclusions'},
      ),
      isEmpty,
    );
    // The ids that moved (FET-250) are the new ones all through, and the
    // lap exclusion still applies on the next open.
    expect(valuesOf(saved, 'gateRevision'), everyElement(startsWith('gates-v2:')));
    expect(valuesOf(original, 'gateRevision'), everyElement(startsWith('gates-v1:')));
    final shown = day.analysis!.chosenGroupId!;
    expect(valuesOf(saved, 'comparisonGroupId'), [shown]);
    expect(valuesOf(saved, 'trackConfigurationReference').toSet(), {shown});
    // Every lap reference carries the key of its run as saved now.
    final savedRuns = {
      for (final run in (saved['event']! as Map)['runs']! as List)
        (run as Map)['id']: run.cast<String, Object?>(),
    };
    final references = [
      for (final entry in (saved['event']! as Map)['lapExclusions']! as List)
        (entry as Map)['reference'],
      ...(((saved['event']! as Map)['analysisDecisions']! as Map)['comparisonSlots']! as List),
    ].whereType<Map<String, Object?>>();
    expect(references, isNotEmpty);
    for (final reference in references) {
      expect(
        reference['derivationKey'],
        fet.lapDerivationV1Key(savedRuns[reference['runId']]!),
        reason: 'the key of run ${reference['runId']}',
      );
    }
    // And it opens again the same, with the comparison pair still applied.
    expect(day.comparison.slots, everyElement(isNotNull));
    final reopened = openDay(path);
    expect(reopened.comparison.slots, day.comparison.slots);
    expect(reopened.analysis!.chosenGroupId, shown);
    expect(reopened.exclusions, day.exclusions);
    expect(day.exclusions, isNotEmpty);
    final view = telemetryView(reopened)..remove('documentState');
    final expected = overlaysView(inspected)..remove('documentState');
    expect(
      jsonDifferences(
        withoutMigratedIds(view) as Map<String, Object?>,
        withoutMigratedIds(expected) as Map<String, Object?>,
        tolerance: 1e-9,
      ),
      isEmpty,
    );
  });
}
