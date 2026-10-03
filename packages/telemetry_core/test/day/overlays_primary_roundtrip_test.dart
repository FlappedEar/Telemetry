// A run's recordings across the two apps (FET-57): "Make primary" and the
// clock check with its accept or refuse. Runs only when
// FLAPPEDEAR_OVERLAYS_ROUNDTRIP names the built tool/cpp_project_roundtrip;
// see tool/README.md.
//
// Overlays imports a VBO as a day, attaches the RCZ of the same drive and
// approves fusing it, with its own controllers. Then, on copies of that day:
// Overlays makes the RCZ primary (KAN-90) and Telemetry makes it primary
// too, and both documents and what each app sees in them agree; Overlays
// removes the fusion (KAN-103) and Telemetry refuses the alignment, and the
// documents are the same; Overlays' "Check clock" (KAN-101) and Telemetry's
// clock check measure the same offset.
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_pair.dart';
import '../support/roundtrip.dart';

final _tool = Platform.environment['FLAPPEDEAR_OVERLAYS_ROUNDTRIP'];
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

Map<String, Object?> _inspect(String path) =>
    (_output(['inspect', path])! as List).single as Map<String, Object?>;

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

Map<String, Object?> _runJson(Map<String, Object?> document, String runId) =>
    ((document['event']! as Map)['runs']! as List).cast<Map<String, Object?>>().firstWhere(
      (run) => run['id'] == runId,
    );

/// The run [runId] of Overlays' `inspect` report.
Map<String, Object?> _inspectedRun(Map<String, Object?> inspected, String runId) =>
    (inspected['runs']! as List).cast<Map<String, Object?>>().firstWhere(
      (run) => run['id'] == runId,
    );

/// [document] without what differs between two saves of one day.
Map<String, Object?> _comparable(Map<String, Object?> document) => {
  ...document,
  'documentState': null,
};

/// Telemetry saves [day] at [path] with [fusions] (and [runs] and
/// [analysis] in place of the opened ones).
Future<Map<String, Object?>> _telemetrySave(
  String path,
  OpenedDay day,
  Map<String, RunFusion> fusions, {
  List<NamedRun>? runs,
  DayAnalysis? analysis,
}) async {
  final document = dayDocument(
    eventId: day.eventId,
    name: day.name,
    runs: runs ?? day.runs,
    analysis: analysis ?? day.analysis!,
    exclusions: day.exclusions,
    projectPath: path,
    previous: day.document,
    previousPath: path,
    fusions: fusions,
  );
  expect(fet.validateFetproject(document), isNull);
  await saveDayDocument(path, document);
  return readDayDocument(path);
}

void main() {
  late Directory directory;
  late String root;
  late String vbo, rcz;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('overlays_primary');
    root = directory.resolveSymbolicLinksSync();
    Directory(p.join(root, 'recordings')).createSync();
    (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  /// Overlays' day of the pair with the RCZ fused, saved at [path]; returns
  /// the run's id.
  String overlaysFusedDay(String path) {
    _run(['import', path, 'Overlays day', vbo]);
    expect(_object(_run(['attach', path, '1', rcz])['evidence'])['matched'], isTrue);
    return _run(['fuse', path, '1', '*=primaryOnly'])['runId']! as String;
  }

  test(
    'a primary Overlays made opens in Telemetry with the other recording kept beside it',
    () async {
      final path = p.join(root, 'overlays.fetproject');
      final runId = overlaysFusedDay(path);
      final made = _run(['primary', path, runId]);
      final inspected = _object(made['inspected']);
      final overlaysSaved = readDayDocument(path);
      final run = _runJson(overlaysSaved, runId);
      expect(run['primaryTelemetrySourceId'], made['primarySourceId']);
      expect(run.containsKey('fusion'), isFalse);
      expect(_inspectedRun(inspected, runId).containsKey('fusion'), isFalse);

      final day = openDay(path);
      expect(day.missing, isEmpty);
      expect(day.runs.single.run.sourceId, made['primarySourceId']);
      expect(day.runs.single.run.format, RecordingFormat.rcz);
      expect(
        jsonDifferences(telemetryView(day), overlaysView(inspected), tolerance: 1e-9),
        isEmpty,
      );
      final kept = fuseOpenedDay(day)[runId]!;
      expect(kept.state, RunFusionState.primaryOnly);
      expect(kept.alternative!.format, RecordingFormat.vbo);

      final saved = await _telemetrySave(path, day, {runId: kept});
      expect(jsonDifferences(_comparable(saved), _comparable(overlaysSaved)), isEmpty);
      final again = _inspect(path);
      expect(
        jsonDifferences(
          overlaysView(again)..remove('documentState'),
          overlaysView(inspected)..remove('documentState'),
        ),
        isEmpty,
      );
      expect(
        _inspectedRun(again, runId)['recordings'],
        _inspectedRun(inspected, runId)['recordings'],
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );

  test(
    'Telemetry makes a primary as Overlays does: the same document and the same day in Overlays',
    () async {
      final overlaysPath = p.join(root, 'overlays.fetproject');
      final runId = overlaysFusedDay(overlaysPath);
      final telemetryPath = p.join(root, 'telemetry.fetproject');
      File(overlaysPath).copySync(telemetryPath);
      final made = _run(['primary', overlaysPath, runId]);
      final overlaysSaved = readDayDocument(overlaysPath);

      final day = openDay(telemetryPath);
      final named = day.runs.single;
      final fusion = fuseOpenedDay(day)[runId]!;
      expect(fusion.fused, isTrue);
      final primary = runFromRecording(named.run, fusion.alternative!);
      final analysis = replaceDayRun(
        day.analysis!,
        runId,
        analyzeNewPrimary(primary, named.name),
        sourceOrder: runSourceOrder(day.analysis!, runId, 0),
      );
      final saved = await _telemetrySave(
        telemetryPath,
        day,
        {runId: RunFusion.primaryOnly(primary: primary, alternative: named.run)},
        runs: [(run: primary, name: named.name)],
        analysis: analysis,
      );
      expect(_runJson(saved, runId)['primaryTelemetrySourceId'], made['primarySourceId']);
      expect(
        jsonDifferences(_comparable(saved), _comparable(overlaysSaved), tolerance: 1e-9),
        isEmpty,
      );
      final inspected = _inspect(telemetryPath);
      final overlaysInspected = _object(made['inspected']);
      expect(
        jsonDifferences(
          overlaysView(inspected)..remove('documentState'),
          overlaysView(overlaysInspected)..remove('documentState'),
        ),
        isEmpty,
      );
      expect(
        _inspectedRun(inspected, runId)['recordings'],
        _inspectedRun(overlaysInspected, runId)['recordings'],
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );

  test(
    'a refused alignment is saved as Overlays saves a removed fusion',
    () async {
      final overlaysPath = p.join(root, 'overlays.fetproject');
      final runId = overlaysFusedDay(overlaysPath);
      final telemetryPath = p.join(root, 'telemetry.fetproject');
      File(overlaysPath).copySync(telemetryPath);
      final removed = _run(['unfuse', overlaysPath, runId]);
      final overlaysSaved = readDayDocument(overlaysPath);
      expect(_runJson(overlaysSaved, runId).containsKey('fusion'), isFalse);

      final day = openDay(telemetryPath);
      final named = day.runs.single;
      final fusion = fuseOpenedDay(day)[runId]!;
      final checked = checkRunClock(named.run, fusion.alternative!, fusion.decision);
      final refused = RunFusion.primaryOnly(
        primary: named.run,
        alternative: checked.alternative!,
        alignment: checked.alignment,
      );
      final saved = await _telemetrySave(telemetryPath, day, {runId: refused});
      expect(jsonDifferences(_comparable(saved), _comparable(overlaysSaved)), isEmpty);
      final inspected = _inspect(telemetryPath);
      expect(_inspectedRun(inspected, runId).containsKey('fusion'), isFalse);
      expect(
        jsonDifferences(
          overlaysView(inspected)..remove('documentState'),
          overlaysView(_object(removed['inspected']))..remove('documentState'),
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );

  test(
    'the clock check measures what Overlays\' Check clock measures, and accepting it saves its clock',
    () async {
      final path = p.join(root, 'overlays.fetproject');
      final runId = overlaysFusedDay(path);
      final overlaysDecision = _object(_runJson(readDayDocument(path), runId)['fusion']);
      final clock = _run(['clock', path, runId]);
      final measured = _object(clock['alignment']);

      final day = openDay(path);
      final named = day.runs.single;
      final fusion = fuseOpenedDay(day)[runId]!;
      expect(clock['sourceId'], fusion.alternativeSourceId);
      final checked = checkRunClock(named.run, fusion.alternative!, fusion.decision);
      final alignment = checked.alignment!;
      expect(alignment.status, measured['status']);
      expect(alignment.reason, measured['reason']);
      expect(alignment.offset, closeTo((measured['offsetSeconds']! as num).toDouble(), 1e-9));
      expect(
        alignment.uncertaintySeconds,
        closeTo((measured['uncertaintySeconds']! as num).toDouble(), 1e-9),
      );
      expect(alignment.driftPpm == null, measured['driftPpm'] == null);
      expect(alignment.usedWindows, measured['usedWindows']);
      expect(alignment.windows.length, measured['windows']);
      expect(alignment.correlation, closeTo((measured['correlation']! as num).toDouble(), 1e-9));
      expect(
        alignment.declaredOffset,
        closeTo((measured['declaredOffsetSeconds']! as num).toDouble(), 1e-9),
      );

      // Accepted: the decision Overlays approved for the same alignment.
      expect(checked.fused, isTrue);
      final saved = await _telemetrySave(path, day, {runId: checked});
      expect(
        jsonDifferences(_runJson(saved, runId)['fusion'], overlaysDecision, tolerance: 1e-9),
        isEmpty,
      );
      expect(_object(_inspectedRun(_inspect(path), runId)['fusion'])['state'], 'applied');
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );
}
