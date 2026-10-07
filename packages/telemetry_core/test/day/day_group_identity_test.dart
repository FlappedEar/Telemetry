// A day's route group keeps its id when a recording is added (FET-259).
// The kept corners and segments are stored under the group's id
// (`trackConfigurationReference`); a recording whose id sorts before the
// day's runs must not rename the group, in memory or in a saved day.
import 'dart:io';
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';
import '../support/circuits.dart';

DayRunInput _run(String digit, TelemetrySession session, {String? name}) => DayRunInput(
  runId: 'run:${digit * 64}',
  name: name ?? 'Session',
  contentSha256: digit * 64,
  session: session,
  laps: deriveSourceLapSession(session),
);

String _groupId(DayAnalysis day) {
  final resolved = day.groups.where((group) => group.resolved).toList();
  expect(resolved, hasLength(1));
  return resolved.single.id;
}

void main() {
  group('a recording added to a day', () {
    // Session 1 (its id sorts after the added recording's) is slower, so its
    // kept segments still time every lap of the day.
    final first = _run('b', rectangleSession([(_) => 30, (_) => 30.5]), name: 'Session 1');
    final added = _run('0', rectangleSession([(_) => 29, (_) => 29.5]), name: 'Session 2');
    final outing = {
      for (final run in [first, added]) run.runId: OutingRun(run.session, run.laps),
    };

    test('the fixture: grouped afresh, the added recording would rename the group', () {
      expect(added.runId.compareTo(first.runId), lessThan(0));
      expect(_groupId(analyzeDay([first, added])), isNot(_groupId(analyzeDay([first]))));
    });

    test('keeps the group id and the kept segments', () {
      final day = analyzeDay([first]);
      final id = _groupId(day);
      final edits = DaySegmentEdits(random: math.Random(1));
      final shown = dayTheoreticalBest(day, outing, random: math.Random(2));
      expect(shown.automaticSegments, isTrue);
      expect(edits.keepAutomatic(shown), isTrue);
      final kept = [for (final segment in shown.runSegments) segment['id']];
      expect(kept, isNotEmpty);

      final extended = extendDay(
        day,
        analyzeDayRuns([added], existingRuns: 1, existingRows: day.rows.length),
      );
      expect(_groupId(extended), id);
      expect(extended.chosenGroupId, id);
      expect(extended.groups.single.runIds, unorderedEquals([first.runId, added.runId]));

      final after = dayTheoreticalBest(extended, outing, documentRuns: edits.applyTo(const []));
      expect(after.state, DayTheoreticalBestState.ready);
      expect(after.groupId, id);
      expect(after.automaticSegments, isFalse, reason: 'the kept segments are found');
      expect(after.segmentRunId, first.runId);
      expect([for (final segment in after.runSegments) segment['id']], kept);

      // Grouping again (a layout set and cleared) keeps it too.
      expect(_groupId(regroupDay(extended, manualTracks: const {})), id);
    });
  });

  group('groupInferredTracks', () {
    final route = inferTrack(deriveSourceLapSession(rectangleSession([(_) => 30, (_) => 30])));
    const gates = TrackConfiguration(gateRevision: 'gates-v1:x');
    final stable = 'gps-route-v1:${'d' * 64}';
    TrackRouteProvenance provenance(String revision, {String? layoutId, String? algorithm}) =>
        TrackRouteProvenance(
          algorithm: algorithm ?? trackInferenceVersion,
          sourceRevision: revision,
          gateRevision: gates.gateRevision,
          layoutId: layoutId ?? stable,
          direction: route.route!.direction,
        );
    TrackGroupingSource source(String id, {TrackRouteProvenance? previous}) => TrackGroupingSource(
      runId: id,
      contentSha256: id * 64,
      configuration: gates,
      previous: previous,
    );
    String layout(InferredTrackGroups grouped, String id) => grouped.configurations[id]!.layoutId!;

    test("keeps the id a run was given, whichever run's id sorts first", () {
      final grouped = groupInferredTracks(
        {'a': route, 'b': route},
        [source('a'), source('b', previous: provenance('b' * 64))],
      );
      expect(layout(grouped, 'a'), stable);
      expect(layout(grouped, 'b'), stable);
      expect(grouped.provenance['a'], provenance('a' * 64));
      expect(grouped.provenance['b'], provenance('b' * 64));
    });

    test('derives the id again when the saved route no longer applies', () {
      final derived = layout(groupInferredTracks({'b': route}, [source('b')]), 'b');
      expect(derived, isNot(stable));
      for (final stale in [
        provenance('b' * 64, algorithm: 'gps-route-v0'),
        provenance('c' * 64), // another recording
        TrackRouteProvenance(
          algorithm: trackInferenceVersion,
          sourceRevision: 'b' * 64,
          gateRevision: 'gates-v1:y',
          layoutId: stable,
          direction: route.route!.direction,
        ),
        TrackRouteProvenance(
          algorithm: trackInferenceVersion,
          sourceRevision: 'b' * 64,
          gateRevision: gates.gateRevision,
          layoutId: stable,
          direction: route.route!.direction == TrackDirection.clockwise
              ? TrackDirection.counterclockwise
              : TrackDirection.clockwise,
        ),
      ]) {
        expect(
          layout(groupInferredTracks({'b': route}, [source('b', previous: stale)]), 'b'),
          derived,
        );
      }
    });

    test('an id two groups claim is kept by neither, and never reused', () {
      final other = inferTrack(
        deriveSourceLapSession(
          rectangleSession([(_) => 30, (_) => 30], centre: const GeoCoordinate(52.01, 21.0)),
        ),
      );
      final grouped = groupInferredTracks(
        {'a': route, 'b': other},
        [source('a', previous: provenance('a' * 64)), source('b', previous: provenance('b' * 64))],
      );
      expect(layout(grouped, 'a'), isNot(layout(grouped, 'b')));
      expect([layout(grouped, 'a'), layout(grouped, 'b')], isNot(contains(stable)));
    });

    test('reads the saved trackInference, and nothing malformed', () {
      expect(TrackRouteProvenance.fromJson(provenance('b' * 64).toJson()), provenance('b' * 64));
      for (final bad in <Object?>[
        null,
        'gps-route-v1',
        {...provenance('b' * 64).toJson(), 'layoutId': 'Club'},
        {...provenance('b' * 64).toJson(), 'direction': 'unknown'},
        {...provenance('b' * 64).toJson(), 'sourceRevision': 3},
      ]) {
        expect(TrackRouteProvenance.fromJson(bad), isNull);
      }
    });
  });

  group('a saved day', () {
    late Directory directory;
    late String root;
    final eventId = newEventId();
    setUp(() {
      directory = Directory.systemTemp.createTempSync('day_group_identity');
      root = directory.resolveSymbolicLinksSync();
    });
    tearDown(() => directory.deleteSync(recursive: true));

    String write(String name, String text) {
      final file = File(p.join(root, name))..writeAsStringSync(text);
      return file.path;
    }

    List<NamedRun> named(List<String> paths, {int existing = 0}) =>
        nameRunsInRecordingOrder(prepareTelemetryImport(paths).runs, existingRuns: existing);

    List<DayRunInput> inputs(List<NamedRun> runs) => [
      for (final run in runs)
        DayRunInput(
          runId: run.run.id,
          name: run.name,
          contentSha256: run.run.contentSha256,
          session: run.run.telemetry,
          laps: run.run.laps,
        ),
    ];

    Map<String, Object?> save(
      String path,
      List<NamedRun> runs,
      DayAnalysis analysis, {
      Map<String, Object?>? previous,
      Map<String, List<Map<String, Object?>>> segments = const {},
    }) {
      final document = dayDocument(
        eventId: eventId,
        name: 'Test day',
        runs: runs,
        analysis: analysis,
        projectPath: path,
        previous: previous,
        previousPath: previous == null ? '' : path,
        trackSegments: segments,
        random: math.Random(4),
      );
      expect(fet.validateFetproject(document), isNull);
      return document;
    }

    List<Object?> documentRuns(Map<String, Object?> document) =>
        (document['event']! as Map)['runs']! as List;

    test('keeps its group and kept segments when a recording that sorts first is added', () async {
      final a = write('a.vbo', circuitVbo([30, 28, 31]));
      final first = named([a]);
      // A recording of the same circuit whose content sorts before Session 1's.
      String? b;
      for (var k = 0; k < 64 && b == null; ++k) {
        final candidate = write('b$k.vbo', circuitVbo([31 + k / 100, 29, 32]));
        if (prepareTelemetryImport([candidate]).runs.single.id.compareTo(first.single.run.id) < 0) {
          b = candidate;
        }
      }
      expect(b, isNotNull);

      final day = analyzeDay(inputs(first));
      final id = _groupId(day);
      // A kept corner of the group, stored as the day stores one.
      final corner = {
        'id': 'kept-corner',
        'type': 'corner',
        'name': 'Hairpin',
        'startProgressMeters': 100.0,
        'endProgressMeters': 200.0,
        'trackConfigurationReference': id,
      };
      final path = p.join(root, 'day.fetproject');
      await saveDayDocument(
        path,
        save(
          path,
          first,
          day,
          segments: {
            first.single.run.id: [corner],
          },
        ),
      );

      // Opened, the recording added, saved and opened again.
      final opened = openDay(path);
      expect(_groupId(opened.analysis!), id);
      final second = named([b!], existing: 1);
      final extended = extendDay(
        opened.analysis!,
        analyzeDayRuns(inputs(second), existingRuns: 1, existingRows: opened.analysis!.rows.length),
      );
      expect(_groupId(extended), id);
      final both = [...opened.runs, ...second];
      await saveDayDocument(path, save(path, both, extended, previous: opened.document));

      final reopened = openDay(path);
      expect(reopened.runs, hasLength(2));
      expect(_groupId(reopened.analysis!), id);
      expect(groupHasApprovedSegments(documentRuns(reopened.document), id), isTrue);
      final saved = documentRuns(reopened.document).cast<Map<String, Object?>>();
      for (final run in saved) {
        expect((run['trackInference']! as Map)['layoutId'], isNotNull);
      }
      expect(
        {for (final run in saved) (run['trackInference']! as Map)['layoutId']},
        hasLength(1),
        reason: 'both runs on the one route',
      );
    });

    test('an old day without trackInference opens as before', () async {
      final a = write('a.vbo', circuitVbo([30, 28, 31]));
      final runs = named([a]);
      final day = analyzeDay(inputs(runs));
      final path = p.join(root, 'day.fetproject');
      final document = save(path, runs, day);
      for (final run in documentRuns(document)) {
        (run! as Map).remove('trackInference');
      }
      await saveDayDocument(path, document);
      expect(_groupId(openDay(path).analysis!), _groupId(day));
    });
  });
}
