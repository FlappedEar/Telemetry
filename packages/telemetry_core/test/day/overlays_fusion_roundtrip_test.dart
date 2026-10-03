// A source fusion FlappedEar Overlays decided, opened in Telemetry (FET-55).
// Runs only when FLAPPEDEAR_OVERLAYS_ROUNDTRIP names the built
// tool/cpp_project_roundtrip; see tool/README.md.
//
// Overlays imports a VBO as a day, attaches the RCZ of the same drive to its
// run as an alternative recording (KAN-90) and approves fusing it with a rule
// (KAN-103), with its own controllers. Telemetry opens the day and applies
// the same decision without aligning again: the same clock and rules, the
// same channels taken from the RCZ ("origins") and bit-identical fused
// channels. Telemetry's re-save keeps the decision and every other field, and
// Overlays applies it again from Telemetry's save.
//
// FET_FUSION_ROUNDTRIP_DAY=<folder> (for example a real day, never committed)
// does the same for every VBO/RCZ pair of the folder, one day per pair, with
// every conflicting channel left to the VBO (primaryOnly); it prints summary
// figures only.
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_json.dart';
import '../support/fusion_pair.dart';
import '../support/roundtrip.dart';

final _tool = Platform.environment['FLAPPEDEAR_OVERLAYS_ROUNDTRIP'];
final _realDay = Platform.environment['FET_FUSION_ROUNDTRIP_DAY'];
const _skip = 'Set FLAPPEDEAR_OVERLAYS_ROUNDTRIP to tool/cpp_project_roundtrip';

Object? _output(List<String> arguments) {
  final result = Process.runSync(
    _tool!,
    arguments,
    environment: {'LC_ALL': 'C.UTF-8'},
    stdoutEncoding: utf8,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String);
}

Map<String, Object?> _run(List<String> arguments) => _output(arguments)! as Map<String, Object?>;

List<Object?> _runList(List<String> arguments) => _output(arguments)! as List<Object?>;

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

/// The run [runId] of Overlays' `inspect` report.
Map<String, Object?> _inspectedRun(Map<String, Object?> inspected, String runId) =>
    (inspected['runs']! as List).cast<Map<String, Object?>>().firstWhere(
      (run) => run['id'] == runId,
    );

/// Every channel of [session] as the tool reports Overlays' fused session.
Map<String, Object?> _channels(TelemetrySession session) => {
  for (final MapEntry(:key, value: channel) in session.channels.entries)
    key: {
      'name': channel.name,
      'unit': channel.unit,
      'count': channel.timestamps.length,
      'digest': channelDigest(channel),
    },
};

/// Overlays builds a day of [vbo] with [rcz] attached and fused with
/// [rules]; returns the `fuse` report.
Map<String, Object?> _overlaysFusedDay(String path, String vbo, String rcz, List<String> rules) {
  _run(['import', path, 'Overlays fused day', vbo]);
  final attached = _run(['attach', path, '1', rcz]);
  expect(_object(attached['evidence'])['matched'], isTrue);
  return _run(['fuse', path, '1', ...rules]);
}

/// Checks that Telemetry opens the day Overlays fused at [path] with the same
/// decision applied, and that its re-save keeps the document and the
/// decision; returns the number of channels taken from the alternative.
Future<int> _checkFusedDay(String path, Map<String, Object?> fused) async {
  final overlaysSaved = readDayDocument(path);
  final inspected = _object(fused['inspected']);
  final runId = fused['runId']! as String;
  final overlaysFusion = _object(_inspectedRun(inspected, runId)['fusion']);
  expect(overlaysFusion['state'], 'applied');
  expect(overlaysFusion['applied'], isTrue);
  final decision = _object(overlaysFusion['decision']);
  expect(decision['alternativeSourceId'], fused['alternativeSourceId']);

  // Telemetry opens it: the same day, and the decision applied as saved.
  final day = openDay(path);
  expect(day.missing, isEmpty);
  expect(jsonDifferences(telemetryView(day), overlaysView(inspected), tolerance: 1e-9), isEmpty);
  final alternative = day.alternatives[runId]!;
  expect(alternative.sourceId, decision['alternativeSourceId']);
  expect(alternative.decision, decision);
  final fusions = fuseOpenedDay(day);
  final applied = fusions[runId]!;
  expect(applied.state, RunFusionState.fused, reason: applied.reason);
  expect(applied.fromDocument, isTrue, reason: 'applied without aligning again');
  expect(applied.documentChanged, isFalse);
  final primary = day.runs.firstWhere((named) => named.run.id == runId).run;
  expect(fusionDecisionApplies(decision, primary, applied.alternative!), isTrue);
  final clock = _object(decision['clock']);
  expect(applied.clock.offsetSeconds, clock['offsetSeconds']);
  expect(applied.clock.driftPpm, clock['driftPpm']);
  expect(applied.rules, fusionDecisionRules(decision));
  expect(applied.channelOrigins, overlaysFusion['origins']);
  expect(jsonDifferences(_channels(applied.session!), overlaysFusion['channels']), isEmpty);

  // Telemetry saves it: Overlays' document, one revision on.
  final document = dayDocument(
    eventId: day.eventId,
    name: day.name,
    runs: day.runs,
    analysis: day.analysis!,
    exclusions: day.exclusions,
    projectPath: path,
    previous: day.document,
    previousPath: path,
    fusions: fusions,
  );
  await saveDayDocument(path, document);
  final telemetrySaved = readDayDocument(path);
  expect(fet.validateFetproject(telemetrySaved), isNull);
  // Known difference (FET-55 finding): Overlays saves
  // `event.analysisDecisions` only once the user chooses a comparison group;
  // Telemetry always saves the group shown, so it adds it to a day Overlays
  // saved without one. Everything else is Overlays' document.
  final telemetryEvent = Map.of(_object(telemetrySaved['event']));
  if (!_object(overlaysSaved['event']).containsKey('analysisDecisions')) {
    expect(telemetryEvent.remove('analysisDecisions'), {
      'comparisonGroupId': inspected['comparisonGroupId'],
    });
  }
  expect(
    jsonDifferences(
      {...telemetrySaved, 'documentState': null, 'event': telemetryEvent},
      {...overlaysSaved, 'documentState': null},
      unordered: const {'event.lapExclusions'},
    ),
    isEmpty,
  );
  final state = _object(telemetrySaved['documentState']);
  final overlaysState = _object(overlaysSaved['documentState']);
  expect(state['id'], overlaysState['id']);
  expect(
    int.parse(state['savedRevision']! as String),
    int.parse(overlaysState['savedRevision']! as String) + 1,
  );

  // Overlays applies the decision from Telemetry's save as before.
  final [again as Map<String, Object?>] = _runList(['inspect', path]);
  expect(_inspectedRun(again, runId)['fusion'], overlaysFusion);
  expect(
    jsonDifferences(
      overlaysView(again)..remove('documentState'),
      overlaysView(inspected)..remove('documentState'),
    ),
    isEmpty,
  );
  return applied.channelOrigins.length;
}

void main() {
  late Directory directory;
  late String root;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('overlays_fusion');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'a fusion Overlays approved opens in Telemetry with the same decision applied and is re-saved unchanged',
    () async {
      Directory(p.join(root, 'recordings')).createSync();
      final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
      final path = p.join(root, 'overlays-fused.fetproject');
      final fused = _overlaysFusedDay(path, vbo, rcz, ['sats=preferAlternative']);
      // Overlays saw the satellite counts conflict, took the RCZ's for them
      // and added its engine speed.
      expect(_object(fused['preview'])['conflicts'], ['sats']);
      final decision = _object(
        _object(
          _inspectedRun(_object(fused['inspected']), fused['runId']! as String)['fusion'],
        )['decision'],
      );
      expect(decision['algorithm'], 'channel-fusion-v1');
      expect(decision['rules'], [
        {'key': 'sats', 'rule': 'preferAlternative'},
      ]);
      final run = ((readDayDocument(path)['event']! as Map)['runs']! as List).single as Map;
      final sources = ((run['sources']! as Map)['telemetry']! as List).cast<Map<String, Object?>>();
      expect(sources, hasLength(2));
      expect(_object(sources.last['importProvenance'])['format'], 'rcz');

      final origins = await _checkFusedDay(path, fused);
      expect(origins, 2, reason: 'rpm-obd added, sats preferAlternative');
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );

  test(
    'every VBO/RCZ pair of FET_FUSION_ROUNDTRIP_DAY fused by Overlays opens the same in Telemetry',
    () async {
      final paths = [
        for (final entity in Directory(_realDay!).listSync())
          if (entity is File && supportsRecordingPath(entity.path)) entity.path,
      ]..sort();
      final plan = prepareTelemetryImport(paths);
      final runs = {for (final run in plan.runs) run.id: run};
      final pairs = [
        for (final MapEntry(key: alternative, value: primary) in automaticVboPrimaries(
          plan,
        ).entries)
          if (alternative != primary) (runs[primary]!.sourcePath, runs[alternative]!.sourcePath),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      expect(pairs, isNotEmpty);
      var origins = 0;
      for (var index = 0; index < pairs.length; ++index) {
        final (vbo, rcz) = pairs[index];
        final path = p.join(root, 'pair-${index + 1}.fetproject');
        final fused = _overlaysFusedDay(path, vbo, rcz, ['*=primaryOnly']);
        origins += await _checkFusedDay(path, fused);
      }
      print(
        'Overlays-fused pairs: ${pairs.length} of ${paths.length} recordings, '
        '$origins channel(s) from the RCZ: same decision in Telemetry, re-saved unchanged',
      );
    },
    timeout: const Timeout(Duration(minutes: 60)),
    skip: _tool == null
        ? _skip
        : _realDay == null
        ? 'Set FET_FUSION_ROUNDTRIP_DAY to a folder of recordings'
        : false,
  );
}
