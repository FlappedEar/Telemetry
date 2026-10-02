// Opens a day written by this package with FlappedEar Overlays' own C++ code
// (tool/cpp_project_check). Runs only when FLAPPEDEAR_OVERLAYS_CHECK names
// the built checker; see tool/README.md.
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

void main() {
  final checker = Platform.environment['FLAPPEDEAR_OVERLAYS_CHECK'];
  late Directory directory;
  late String root;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('overlays_check');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  List<Map<String, Object?>> check(List<String> paths) {
    final result = Process.runSync(checker!, paths);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return [
      for (final value in jsonDecode(result.stdout as String) as List)
        value as Map<String, Object?>,
    ];
  }

  test(
    'Overlays opens a saved day with its layouts, exclusions and identity, and keeps it on re-save',
    () async {
      final paths = [
        for (final (name, speeds) in [
          ('a.vbo', <double>[30, 28, 31]),
          ('b.vbo', <double>[29, 32, 27]),
        ])
          (File(p.join(root, 'recordings', name))
                ..createSync(recursive: true)
                ..writeAsStringSync(circuitVbo(speeds)))
              .path,
      ];
      final runs = nameRunsInRecordingOrder(prepareTelemetryImport(paths).runs);
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
      final best = analysis.ranking!.bestOfDay!;
      final exclusions = {best.reference: 'Traffic'};
      final other = runs.firstWhere((named) => named.run.id != best.runId).run.id;
      final regrouped = regroupDay(
        analysis,
        manualTracks: {
          other: const TrackConfiguration(layoutId: 'Club', direction: TrackDirection.clockwise),
        },
        exclusions: exclusions,
      );
      final path = p.join(root, 'day.fetproject');
      final document = dayDocument(
        eventId: newEventId(),
        name: 'Overlays check',
        runs: runs,
        analysis: regrouped,
        exclusions: exclusions,
        projectPath: path,
      );
      await saveDayDocument(path, document);

      final [result] = check([path]);
      expect(result['valid'], isTrue, reason: '${result['error']}');
      expect(result['documentState'], document['documentState']);
      expect(result['resaveKeepsEvent'], isTrue);
      final checked = {for (final run in result['runs'] as List) (run as Map)['runId']: run};
      final event = document['event'] as Map<String, Object?>;
      for (final named in runs) {
        final run = checked[named.run.id]!;
        final saved = (event['runs'] as List).cast<Map<String, Object?>>().firstWhere(
          (json) => json['id'] == named.run.id,
        );
        expect(run['resolved'], isTrue);
        expect(run['fingerprint'], 'match');
        expect(run['expectedRevision'], named.run.contentSha256);
        expect(run['contentRevision'], named.run.contentSha256);
        expect(run['derivationKey'], fet.lapDerivationV1Key(saved));
        expect(run['timedLaps'], named.run.laps.timedLaps.length);
        expect(run['excludedLaps'], [
          if (named.run.id == best.runId)
            {'start': best.start, 'end': best.end, 'reason': 'Traffic'},
        ]);
      }
      expect((checked[other]!['trackConfiguration'] as Map)['layoutId'], 'Club');
      expect((checked[other]!['trackConfiguration'] as Map)['direction'], 'clockwise');
    },
    skip: checker == null ? 'Set FLAPPEDEAR_OVERLAYS_CHECK to tool/cpp_project_check' : false,
  );
}
