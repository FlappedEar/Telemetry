// Round trips with FlappedEar Overlays' own C++ code in both directions
// (FET-40), on the shared fixtures' recordings. Runs only when
// FLAPPEDEAR_OVERLAYS_ROUNDTRIP names the built tool/cpp_project_roundtrip;
// see tool/README.md.
//
// Telemetry → Overlays → Telemetry: a day Telemetry saved (edited segments,
// an exclusion, the group shown, notes and conditions already present, a
// session's structured setup and unknown keys in open objects) is opened and saved by Overlays and opened
// again by Telemetry: nothing is lost and the analysis is the same.
//
// Overlays → Telemetry → Overlays: a day Overlays built and saved (segments
// renamed and merged, an exclusion, notes, comparison decisions and editor
// state) opens in Telemetry with the same sessions, laps, exclusions, group
// and segments; Telemetry's save keeps every field, and Overlays reads it back
// the same.
//
// Session details (FET-52): the same edits of a session's name, notes,
// conditions and setup changes, made in Telemetry and by Overlays'
// updateRunMetadata on the same day, save the same document; a day Telemetry
// renamed opens in Overlays with its name, and Overlays' save keeps it.
//
// FET_ROUNDTRIP_RECORDINGS names other recordings (a folder of VBO files, or
// RCZ files with FET_ROUNDTRIP_EXTENSION=.rcz; for example a real day, never
// committed) to use instead of the fixtures';
// FET_PARITY_REPORT=1 prints counts only.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/roundtrip.dart';

final _tool = Platform.environment['FLAPPEDEAR_OVERLAYS_ROUNDTRIP'];
final _recordings = Platform.environment['FET_ROUNDTRIP_RECORDINGS'];
final _extension = Platform.environment['FET_ROUNDTRIP_EXTENSION'] ?? '.vbo';
final _report = Platform.environment.containsKey('FET_PARITY_REPORT');

Object? _run(List<String> arguments) {
  final result = Process.runSync(
    _tool!,
    arguments,
    environment: {'LC_ALL': 'C.UTF-8'},
    stdoutEncoding: utf8,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String);
}

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

/// A session's setup as Telemetry stores it, with keys it does not know.
const setupFixture = {
  'version': 'session-setup-v1',
  'pressureUnit': 'psi',
  'coldPressure': {'fl': 30, 'fr': 30.5, 'rl': 28, 'rr': 28.25, 'futureWheel': 'kept'},
  'hotPressure': {'fl': 34.5, 'rr': 32},
  'tyre': 'Pirelli Diablo Supercorsa SC2',
  'fuelStartLitres': 8.5,
  'futureSetup': {'kept': true},
};

/// Keys Overlays adds to a document Telemetry saved: its own defaults for
/// settings Telemetry does not have. Everything else must match.
const _overlaysDefaults = {'mapSettings', 'exportSettings'};

void main() {
  late Directory directory;
  late String root;
  late List<String> recordings;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('overlays_roundtrip');
    root = directory.resolveSymbolicLinksSync();
    if (_recordings == null) {
      copyRoundtripFixtures(root);
      recordings = [
        for (final name in ['morning', 'midday', 'afternoon'])
          p.join(root, 'recordings', '$name.vbo'),
      ];
    } else {
      recordings = [
        for (final file in Directory(_recordings!).listSync())
          if (file is File && file.path.toLowerCase().endsWith(_extension)) file.path,
      ]..sort();
    }
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'Telemetry → Overlays → Telemetry keeps the day and its analysis',
    () async {
      final runs = nameRunsInRecordingOrder(prepareTelemetryImport(recordings).runs);
      final inputs = [
        for (final named in runs)
          DayRunInput(
            runId: named.run.id,
            name: named.name,
            contentSha256: named.run.contentSha256,
            session: named.run.telemetry,
            laps: named.run.laps,
          ),
      ];
      var analysis = analyzeDay(inputs);
      final best = analysis.ranking!.bestOfDay!;
      final excluded = analysis.ranking!.eligibleLaps.firstWhere(
        (row) => row.reference != best.reference,
      );
      final exclusions = {excluded.reference: 'Traffic'};
      analysis = regroupDay(analysis, manualTracks: const {}, exclusions: exclusions);

      // Segments edited from the automatic ones: renamed, split and merged.
      final edits = DaySegmentEdits(random: Random(2));
      DayTheoreticalBest calculate() => dayTheoreticalBest(
        analysis,
        outingRuns(runs),
        documentRuns: edits.applyTo(const []),
        random: Random(1),
      );
      var result = calculate();
      expect(result.state, DayTheoreticalBestState.ready, reason: result.message);
      String idAt(int index) => result.approvedSegment(index)!['id']! as String;
      final first = result.segments.first;
      expect(
        edits.edit(
          result,
          idAt(0),
          name: 'Renamed in Telemetry',
          type: first.type,
          startMeters: first.startProgressMeters,
          endMeters: first.endProgressMeters,
        ),
        isEmpty,
      );
      result = calculate();
      final second = result.segments[1];
      expect(
        edits.split(result, idAt(1), (second.startProgressMeters + second.endProgressMeters) / 2),
        isEmpty,
      );
      result = calculate();
      expect(edits.merge(result, idAt(3), idAt(4)), isEmpty);

      final path = p.join(root, 'telemetry-day.fetproject');
      final eventId = newEventId();
      var document = dayDocument(
        eventId: eventId,
        name: 'Telemetry day',
        runs: runs,
        analysis: analysis,
        exclusions: exclusions,
        projectPath: path,
        trackSegments: edits.runs,
      );
      await saveDayDocument(path, document);

      // Fields another version or app wrote earlier: notes and conditions,
      // and unknown keys in open objects. Telemetry keeps them on its save.
      final event = _object(document['event']);
      final firstRun = _object((event['runs']! as List).first);
      firstRun['notes'] = 'Dry line from lap 2';
      firstRun['conditions'] = 'Overcast, 14 °C';
      firstRun['futureRunField'] = {'kept': true};
      // Telemetry's structured setup (FET-188), with keys of a later version
      // in it and in a wheel object: Overlays keeps it without reading it.
      firstRun[runSetupKey] = setupFixture;
      final source = _object((_object(firstRun['sources'])['telemetry']! as List).first);
      source['futureSourceField'] = [1, 2, 3];
      _object(source['reference'])['futureReferenceField'] = 'kept';
      event['futureEventField'] = {'nested': 'value'};
      event['analysisDecisions'] ??= <String, Object?>{};
      _object(event['analysisDecisions'])['futureDecision'] = 7;
      _object(document['documentState'])['futureState'] = 'kept';
      document['futureTopLevel'] = {'version': 9};
      await saveDayDocument(path, document);
      final opened = openDay(path);
      expect(opened.missing, isEmpty);
      document = dayDocument(
        eventId: opened.eventId,
        name: opened.name,
        runs: opened.runs,
        analysis: opened.analysis!,
        exclusions: opened.exclusions,
        projectPath: path,
        previous: opened.document,
        previousPath: path,
      );
      await saveDayDocument(path, document);
      final telemetrySaved = readDayDocument(path);
      final telemetryDay = openDay(path);
      final before = telemetryView(telemetryDay);

      // Overlays opens it, sees the same day, and saves it.
      final resaved = _object(_run(['resave', path]));
      expect(
        jsonDifferences(overlaysView(_object(resaved['opened'])), before, tolerance: 1e-9),
        isEmpty,
      );
      final overlaysSaved = readDayDocument(path);
      expect(fet.validateFetproject(overlaysSaved), isNull);
      // Nothing lost or changed; Overlays only adds its own default settings,
      // so no closed object gains a key. An unchanged document keeps its
      // revision; every save writes a new saveId (KAN-183).
      final telemetrySaveId = _object(telemetrySaved['documentState'])['saveId'];
      final overlaysState = _object(overlaysSaved['documentState']);
      expect(
        overlaysState['saveId'],
        isA<String>().having((id) => id.isNotEmpty, 'not empty', isTrue),
      );
      expect(overlaysState['saveId'], isNot(telemetrySaveId));
      expect(
        jsonDifferences(telemetrySaved, {
          for (final entry in overlaysSaved.entries)
            if (!_overlaysDefaults.contains(entry.key) || telemetrySaved.containsKey(entry.key))
              entry.key: entry.key == 'documentState'
                  ? {...overlaysState, 'saveId': telemetrySaveId}
                  : entry.value,
        }),
        isEmpty,
      );
      // What Overlays saved: the same day under its own new saveId.
      final afterOverlays = {
        ...before,
        'documentState': {..._object(before['documentState']), 'saveId': overlaysState['saveId']},
      };
      expect(
        jsonDifferences(overlaysView(_object(resaved['saved'])), afterOverlays, tolerance: 1e-9),
        isEmpty,
      );

      // Telemetry opens it again: the same day and analysis.
      final again = openDay(path);
      expect(again.missing, isEmpty);
      final againFirst = _object((_object(again.document['event'])['runs']! as List).first);
      expect(againFirst[runSetupKey], setupFixture);
      expect(RunMetadata.fromRun(againFirst).setup, RunSetup.fromJson(setupFixture));
      expect(RunSetup.fromJson(setupFixture).pressureUnit, PressureUnit.psi);
      expect(jsonDifferences(telemetryView(again), afterOverlays, tolerance: 1e-9), isEmpty);
      final next = dayDocument(
        eventId: again.eventId,
        name: again.name,
        runs: again.runs,
        analysis: again.analysis!,
        exclusions: again.exclusions,
        projectPath: path,
        previous: again.document,
        previousPath: path,
      );
      expect(_object(next['documentState'])['id'], _object(telemetrySaved['documentState'])['id']);
      expect(
        int.parse(_object(next['documentState'])['savedRevision']! as String),
        int.parse(_object(telemetrySaved['documentState'])['savedRevision']! as String) + 1,
      );
      expect(
        jsonDifferences(
          {...next, 'documentState': null},
          {...overlaysSaved, 'documentState': null},
          unordered: const {'event.lapExclusions'},
        ),
        isEmpty,
      );
      if (_report) {
        final view = before;
        print(
          'T→O→T: ${(view['runs']! as List).length} sessions, '
          '${(view['laps']! as List).length} lap sections, '
          '${telemetryDay.exclusions.length} exclusion(s), '
          '${[for (final run in view['runs']! as List) (_object(_object(run)['trackSegments'])['count']! as int)].reduce((a, b) => a + b)} segments: equal',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: _tool == null ? 'Set FLAPPEDEAR_OVERLAYS_ROUNDTRIP to tool/cpp_project_roundtrip' : false,
  );

  test(
    'Overlays → Telemetry → Overlays keeps the day and every Overlays field',
    () async {
      final path = p.join(root, 'overlays-built.fetproject');
      final created = _object(_run(['create', path, 'Overlays day', ...recordings]));
      final overlaysSaved = readDayDocument(path);

      final day = openDay(path);
      expect(day.missing, isEmpty);
      expect(jsonDifferences(telemetryView(day), overlaysView(created), tolerance: 1e-9), isEmpty);
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
      final telemetrySaved = readDayDocument(path);
      expect(
        jsonDifferences(
          {...telemetrySaved, 'documentState': null},
          {...overlaysSaved, 'documentState': null},
          unordered: const {'event.lapExclusions'},
        ),
        isEmpty,
      );

      final [inspected as Map<String, Object?>] = _run(['inspect', path])! as List;
      final state = _object(inspected['documentState']);
      final createdState = _object(created['documentState']);
      expect(state['id'], createdState['id']);
      expect(
        int.parse(state['savedRevision']! as String),
        int.parse(createdState['savedRevision']! as String) + 1,
      );
      expect(
        jsonDifferences(
          overlaysView(inspected)..remove('documentState'),
          overlaysView(created)..remove('documentState'),
        ),
        isEmpty,
      );
      if (_report) {
        final laps = (created['laps']! as List).cast<Map<String, Object?>>();
        print(
          'O→T→O: ${(created['runs']! as List).length} sessions, ${laps.length} lap sections, '
          '${laps.where((lap) => lap['excluded'] == true).length} exclusion(s), '
          '${[for (final run in created['runs']! as List) (_object(_object(run)['trackSegments'])['count']! as int)].reduce((a, b) => a + b)} segments: equal',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: _tool == null ? 'Set FLAPPEDEAR_OVERLAYS_ROUNDTRIP to tool/cpp_project_roundtrip' : false,
  );

  test(
    'session details edited in Telemetry are saved as Overlays saves them',
    () async {
      final runs = nameRunsInRecordingOrder(prepareTelemetryImport(recordings).runs);
      final analysis = analyzeDay([
        for (final named in runs)
          DayRunInput(
            runId: named.run.id,
            name: named.name,
            contentSha256: named.run.contentSha256,
            session: named.run.telemetry,
            laps: named.run.laps,
          ),
      ]);
      final path = p.join(root, 'details.fetproject');
      await saveDayDocument(
        path,
        dayDocument(
          eventId: newEventId(),
          name: 'Day before',
          runs: runs,
          analysis: analysis,
          projectPath: path,
        ),
      );

      // Each edit starts from the day the previous one saved: a legacy record
      // without the keys, texts with spaces, blank and cleared texts.
      const edits = [
        RunMetadata(name: '  Warm-up  ', notes: ' Brake earlier into T1 ', setupChanges: '   '),
        RunMetadata(name: 'Warm-up', conditions: 'Dry, 18 °C', setupChanges: 'Tyres +0.1 bar'),
        RunMetadata(name: 'Sesja próbna ✓', notes: 'Line 1\nLine 2', conditions: ''),
      ];
      const index = 1;
      var current = path;
      for (final (step, edit) in edits.indexed) {
        final overlaysPath = p.join(root, 'overlays-$step.fetproject');
        final inspected = _object(
          _run([
            'metadata',
            current,
            overlaysPath,
            '$index',
            edit.name,
            edit.notes,
            edit.conditions,
            edit.setupChanges,
          ]),
        );
        final overlaysSaved = readDayDocument(overlaysPath);

        final day = openDay(current);
        expect(day.missing, isEmpty);
        final runId = ((_object(day.document['event'])['runs']! as List)[index] as Map)['id']!;
        final name = edit.name.trim();
        final telemetryPath = p.join(root, 'telemetry-$step.fetproject');
        final document = dayDocument(
          eventId: day.eventId,
          name: day.name,
          runs: [
            for (final named in day.runs)
              named.run.id == runId ? (run: named.run, name: name) : named,
          ],
          analysis: renameDayRun(day.analysis!, runId as String, name, exclusions: day.exclusions),
          exclusions: day.exclusions,
          projectPath: telemetryPath,
          previous: day.document,
          previousPath: current,
          runMetadata: {runId: edit},
        );
        await saveDayDocument(telemetryPath, document);
        final telemetrySaved = readDayDocument(telemetryPath);
        final telemetryRun = _object((_object(telemetrySaved['event'])['runs']! as List)[index]);
        final overlaysRun = _object((_object(overlaysSaved['event'])['runs']! as List)[index]);
        for (final key in ['name', ...runMetadataTextKeys]) {
          expect(telemetryRun.containsKey(key), overlaysRun.containsKey(key), reason: '$step $key');
          expect(telemetryRun[key], overlaysRun[key], reason: '$step $key');
        }
        // The whole documents match but for paths relative to their own
        // files, Overlays' own default settings and documentState.
        Map<String, Object?> comparable(Map<String, Object?> saved) => {
          for (final entry in saved.entries)
            if (!_overlaysDefaults.contains(entry.key) && entry.key != 'documentState')
              entry.key: entry.value,
        };
        expect(
          jsonDifferences(
            comparable(telemetrySaved),
            comparable(overlaysSaved),
            unordered: const {'event.lapExclusions'},
          ),
          isEmpty,
        );
        // Overlays sees Telemetry's edit as its own, laps named after it.
        final [telemetryInspected as Map<String, Object?>] =
            _run(['inspect', telemetryPath])! as List;
        expect(
          jsonDifferences(
            overlaysView(telemetryInspected)..remove('documentState'),
            overlaysView(inspected)..remove('documentState'),
            tolerance: 1e-9,
          ),
          isEmpty,
        );
        expect(
          jsonDifferences(
            telemetryView(openDay(telemetryPath))..remove('documentState'),
            overlaysView(inspected)..remove('documentState'),
            tolerance: 1e-9,
          ),
          isEmpty,
        );
        current = telemetryPath;
      }

      // A day renamed in Telemetry keeps its name through Overlays.
      final day = openDay(current);
      const dayName = 'Żółta flaga – evening ✓';
      expect(dayNameProblem(dayName), isNull);
      await saveDayDocument(
        current,
        dayDocument(
          eventId: day.eventId,
          name: dayName,
          runs: day.runs,
          analysis: day.analysis!,
          exclusions: day.exclusions,
          projectPath: current,
          previous: day.document,
          previousPath: current,
        ),
      );
      final resaved = _object(_run(['resave', current]));
      expect(_object(resaved['opened'])['eventName'], dayName);
      expect(_object(resaved['saved'])['eventName'], dayName);
      expect(openDay(current).name, dayName);
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: _tool == null ? 'Set FLAPPEDEAR_OVERLAYS_ROUNDTRIP to tool/cpp_project_roundtrip' : false,
  );
}
