// The reviewed import (FET-58) between FlappedEar Overlays and Telemetry.
// Runs only when FLAPPEDEAR_OVERLAYS_ROUNDTRIP names the built
// tool/cpp_project_roundtrip; see tool/README.md.
//
// Overlays' advanced import review (BatchImportDialog) makes the RCZ of a
// synthetic drive the run and its VBO "Same run as" the RCZ, overriding the
// automatic pairing, and skips a third file. Telemetry opens that day with
// the VBO as the run's alternative recording, and its re-save keeps every
// source. Telemetry's own review with the same choices saves the run as
// Overlays does: one run, the same primary and the same sources with their
// content and import provenance, and Overlays opens it with the same
// recordings. Synthetic recordings only.
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_pair.dart';

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

List<Map<String, Object?>> _runs(Map<String, Object?> document) =>
    ((document['event']! as Map)['runs']! as List).cast<Map<String, Object?>>();

/// How a document groups recordings into runs, without the ids each app
/// mints: per run, its primary's content and its sources' content, format
/// and import provenance.
List<Map<String, Object?>> _grouping(Map<String, Object?> document) => [
  for (final run in _runs(document))
    () {
      final sources = ((run['sources']! as Map)['telemetry']! as List).cast<Map<String, Object?>>();
      final primary = sources.firstWhere(
        (source) => source['id'] == run['primaryTelemetrySourceId'],
      );
      final entries = [
        for (final source in sources)
          {
            'contentSha256': source['contentSha256'],
            'format': (source['importProvenance']! as Map)['format'],
            'provenanceSha256': (source['importProvenance']! as Map)['sha256'],
            'provenanceFingerprint': fet.qtCompactJson(
              (source['importProvenance']! as Map)['fingerprint'],
            ),
            'fingerprint': fet.qtCompactJson((source['reference']! as Map)['fingerprint']),
          },
      ]..sort((a, b) => '${a['contentSha256']}'.compareTo('${b['contentSha256']}'));
      return {'primary': primary['contentSha256'], 'sources': entries};
    }(),
];

/// The recordings Overlays' `inspect` lists for each run: format and
/// whether it is the primary, in its order.
List<List<Object?>> _recordings(Map<String, Object?> inspected) => [
  for (final run in (inspected['runs']! as List).cast<Map<String, Object?>>())
    [
      for (final recording in (run['recordings']! as List).cast<Map<String, Object?>>())
        '${(recording['format']! as String).toLowerCase()} ${recording['primary'] == true ? 'primary' : 'alternative'}',
    ]..sort(),
];

void main() {
  late Directory directory;
  late String root;
  late String vbo, rcz, other;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('overlays_review');
    root = directory.resolveSymbolicLinksSync();
    final recordings = p.join(root, 'recordings');
    Directory(recordings).createSync();
    (vbo, rcz) = writeFusionPair(recordings);
    // Another synthetic drive, which the review skips.
    (other, _) = writeFusionPair(recordings, name: 'other', speeds: const [28, 31, 27, 30]);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'a review that makes the RCZ the run and skips a file is stored and read alike',
    () async {
      // Overlays reviews: RCZ a run, VBO the same run as the RCZ, other skipped.
      final overlaysPath = p.join(root, 'overlays-reviewed.fetproject');
      final reviewed = _run([
        'review',
        overlaysPath,
        'Reviewed day',
        '$rcz=new',
        '$vbo=same:1',
        '$other=skip',
      ]);
      expect(
        [for (final row in (reviewed['rows']! as List).cast<Map<String, Object?>>()) row['status']],
        ['ready', 'ready', 'ready'],
      );
      final inspected = reviewed['inspected']! as Map<String, Object?>;
      expect(inspected['valid'], isTrue);
      expect(_recordings(inspected), [
        ['rcz primary', 'vbo alternative'],
      ]);
      final overlaysSaved = readDayDocument(overlaysPath);

      // Telemetry opens it: one session, the RCZ's laps, the VBO kept beside
      // it, not fused: Overlays decided no fusion (FET-57's rule).
      final day = openDay(overlaysPath);
      expect(day.missing, isEmpty);
      expect(day.runs, hasLength(1));
      final session = day.runs.single.run;
      expect(session.format, RecordingFormat.rcz);
      final alternative = day.alternatives[session.id]!;
      expect(alternative.format, RecordingFormat.vbo);
      final vboSource = ((_runs(overlaysSaved).single['sources']! as Map)['telemetry']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((source) => (source['importProvenance']! as Map)['format'] == 'vbo');
      expect(alternative.sourceId, vboSource['id']);
      expect(alternative.automatic, isFalse);

      // Telemetry's re-save keeps both sources and the primary as they were,
      // and decides no fusion for Overlays.
      final fusions = fuseOpenedDay(day);
      expect(fusions[session.id]!.fused, isFalse);
      final resaved = dayDocument(
        eventId: day.eventId,
        name: day.name,
        runs: day.runs,
        analysis: day.analysis!,
        exclusions: day.exclusions,
        projectPath: overlaysPath,
        previous: day.document,
        previousPath: overlaysPath,
        fusions: fusions,
      );
      expect(fet.validateFetproject(resaved), isNull);
      expect(_grouping(resaved), _grouping(overlaysSaved));
      expect(_runs(resaved).single.containsKey('fusion'), isFalse);
      await saveDayDocument(overlaysPath, resaved);
      // Overlays adds the skipped file to Telemetry's save in its review and
      // knows the RCZ is in the day already.
      final again = _run(['review-append', overlaysPath, '$other=new', '$rcz=skip']);
      expect(
        [for (final row in (again['rows']! as List).cast<Map<String, Object?>>()) row['existing']],
        [false, true],
      );
      expect(_recordings(again['inspected']! as Map<String, Object?>), [
        ['rcz primary', 'vbo alternative'],
        ['vbo primary'],
      ]);

      // Telemetry reviews the same choices and saves the day as Overlays does.
      final plan = prepareTelemetryImport([rcz, vbo, other]);
      final choices = {
        plan.runs[0].id: plan.runs[0].id,
        plan.runs[1].id: plan.runs[0].id,
        plan.runs[2].id: skipRecording,
      };
      expect(checkImportChoices(plan.runs.map((run) => run.id), choices), isNull);
      final runs = nameRunsInRecordingOrder(chosenRuns(plan, choices));
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
      final telemetryPath = p.join(root, 'telemetry-reviewed.fetproject');
      // The pair the user made is fused when it is imported, and its saved
      // decision carries it from then on.
      final alternatives = importedAlternatives(plan, [
        for (final named in runs) named.run,
      ], choices: choices);
      final fused = {
        for (final named in runs)
          if (alternatives[named.run.id] case final alternative?)
            named.run.id: fuseRunRecordings(named.run, alternative),
      };
      expect(fused.values.single.fused, isTrue);
      final document = dayDocument(
        eventId: newEventId(),
        name: 'Reviewed day',
        runs: runs,
        analysis: analysis,
        projectPath: telemetryPath,
        fusions: fused,
      );
      expect(
        (_runs(document).single['fusion']! as Map)['alternativeSourceId'],
        alternatives.values.single.sourceId,
      );
      expect(fet.validateFetproject(document), isNull);
      await saveDayDocument(telemetryPath, document);
      expect(_grouping(readDayDocument(telemetryPath)), _grouping(overlaysSaved));
      final [opened as Map<String, Object?>] = _output(['inspect', telemetryPath])! as List;
      expect(opened['valid'], isTrue);
      expect(_recordings(opened), _recordings(inspected));
      // And Telemetry reads its own save back the same way.
      final reopened = openDay(telemetryPath);
      final reopenedId = reopened.runs.single.run.id;
      expect(reopened.alternatives[reopenedId]!.format, RecordingFormat.vbo);
      final reapplied = fuseOpenedDay(reopened)[reopenedId]!;
      expect(reapplied.fused, isTrue);
      expect(reapplied.fromDocument, isTrue, reason: 'the saved decision, not aligned again');
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );

  test(
    'a pairing Overlays made that is not a VBO with its RCZ is kept and never fused',
    () async {
      // Two VBOs made one run in Overlays' review, as an alternative
      // attached in Run details would be.
      final path = p.join(root, 'overlays-two-vbo.fetproject');
      final reviewed = _run(['review', path, 'Two VBOs', '$vbo=new', '$other=same:1']);
      expect(_recordings(reviewed['inspected']! as Map<String, Object?>), [
        ['vbo alternative', 'vbo primary'],
      ]);
      final saved = readDayDocument(path);
      final day = openDay(path);
      expect(day.alternatives, isEmpty);
      expect(fuseOpenedDay(day), isEmpty);
      final resaved = dayDocument(
        eventId: day.eventId,
        name: day.name,
        runs: day.runs,
        analysis: day.analysis!,
        exclusions: day.exclusions,
        projectPath: path,
        previous: day.document,
        previousPath: path,
        fusions: fuseOpenedDay(day),
      );
      expect(_runs(resaved).single.containsKey('fusion'), isFalse);
      expect(_grouping(resaved), _grouping(saved));
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );
}
