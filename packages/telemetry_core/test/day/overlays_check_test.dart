// Opens a day written by this package with FlappedEar Overlays' own C++ code
// (tool/cpp_project_check). Runs only when FLAPPEDEAR_OVERLAYS_CHECK names
// the built checker; see tool/README.md.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';
import '../support/fusion_pair.dart';

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
      // The chosen group's best lap got automatic segments, which Overlays accepts.
      final segmented = [
        for (final run in (event['runs'] as List).cast<Map<String, Object?>>())
          if (run['trackSegments'] case final List<Object?> segments when segments.isNotEmpty)
            run['id'],
      ];
      expect(segmented, [regrouped.ranking!.bestOfDay!.runId]);
      expect((checked[other]!['trackConfiguration'] as Map)['layoutId'], 'Club');
      expect((checked[other]!['trackConfiguration'] as Map)['direction'], 'clockwise');
    },
    skip: checker == null ? 'Set FLAPPEDEAR_OVERLAYS_CHECK to tool/cpp_project_check' : false,
  );

  test('Overlays opens a day whose segments were edited, and keeps them on re-save', () async {
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
      edits.split(result, idAt(0), (first.startProgressMeters + first.endProgressMeters) / 2),
      isEmpty,
    );
    result = calculate();
    expect(edits.merge(result, idAt(2), idAt(3)), isEmpty);
    result = calculate();
    final moved = result.segments[1];
    expect(
      edits.edit(
        result,
        idAt(1),
        name: 'Renamed',
        type: 'sector',
        startMeters: moved.startProgressMeters,
        endMeters: moved.endProgressMeters + 5,
      ),
      isEmpty,
    );
    result = calculate();
    expect(edits.remove(result, idAt(result.segments.length - 1)), isEmpty);
    // The removed segment's proposal is open again: rejected in the review
    // (FET-56), stored in the run's trackSegmentReview.
    result = calculate();
    final review = dayProposalReview(
      result,
      segmentReviewLap(result),
      outingRuns(runs)[result.segmentRunId],
    );
    final open = review
        .items(result.runSegments, null)
        .indexWhere((item) => item.state == SegmentReviewState.proposed);
    expect(open, isNonNegative);
    expect(edits.setRejected(result, review, const [], open), isEmpty);

    final path = p.join(root, 'edited.fetproject');
    final document = dayDocument(
      eventId: newEventId(),
      name: 'Edited segments',
      runs: runs,
      analysis: analysis,
      projectPath: path,
      trackSegments: edits.runs,
      trackSegmentReviews: edits.reviews,
    );
    await saveDayDocument(path, document);
    final [checked] = check([path]);
    expect(checked['valid'], isTrue, reason: '${checked['error']}');
    expect(checked['resaveKeepsEvent'], isTrue);
    final saved = {
      for (final run in ((document['event'] as Map)['runs'] as List).cast<Map<String, Object?>>())
        run['id']: run['trackSegments'],
    };
    for (final run in (checked['runs'] as List).cast<Map<String, Object?>>()) {
      final segments = saved[run['runId']] as List<Object?>?;
      expect(run['trackSegments'], {
        'valid': true,
        'count': segments?.length ?? 0,
        'revision': segments == null ? '' : fet.trackSegmentSetRevision(segments),
      });
    }
    expect(saved[result.segmentRunId], edits.runs[result.segmentRunId]);
    final reviewed = (checked['runs'] as List).cast<Map<String, Object?>>().firstWhere(
      (run) => run['runId'] == result.segmentRunId,
    );
    expect(reviewed['trackSegmentReview'], {'valid': true, 'rejected': 1});
  }, skip: checker == null ? 'Set FLAPPEDEAR_OVERLAYS_CHECK to tool/cpp_project_check' : false);

  test(
    'Overlays validates and applies a fusion decision Telemetry wrote, and keeps it on re-save',
    () async {
      Directory(p.join(root, 'recordings')).createSync();
      final (vbo, rcz) = writeFusionPair(p.join(root, 'recordings'), satellites: true);
      final plan = prepareTelemetryImport([vbo, rcz]);
      final primary = plan.runs.firstWhere((run) => run.format == RecordingFormat.vbo);
      final runs = nameRunsInRecordingOrder([primary]);
      final fusions = fuseImportedRuns(plan, [primary]);
      final fusion = withFusionRule(
        fusions[primary.id]!,
        primary,
        'sats',
        FusionRule.preferAlternative,
      )!;
      final analysis = analyzeDay([
        DayRunInput(
          runId: primary.id,
          name: runs.single.name,
          contentSha256: primary.contentSha256,
          session: primary.telemetry,
          laps: primary.laps,
        ),
      ]);
      final path = p.join(root, 'fused.fetproject');
      final document = dayDocument(
        eventId: newEventId(),
        name: 'Fused day',
        runs: runs,
        analysis: analysis,
        projectPath: path,
        fusions: {primary.id: fusion},
      );
      await saveDayDocument(path, document);
      final [checked] = check([path]);
      expect(checked['valid'], isTrue, reason: '${checked['error']}');
      expect(checked['resaveKeepsEvent'], isTrue);
      final run = (checked['runs'] as List).single as Map<String, Object?>;
      expect(run['fusion'], {
        'state': 'applied',
        'alternativeResolved': true,
        'alternativeContentRevision': fusion.alternative!.contentSha256,
        'rules': 1,
      });

      // Bound to other content: still valid, but Overlays no longer applies it.
      final stale = fet.qtJsonDecode(jsonEncode(document)) as Map<String, Object?>;
      final staleRun = ((stale['event'] as Map)['runs'] as List).single as Map;
      (staleRun['fusion'] as Map)['primarySourceRevision'] = 'd' * 64;
      final stalePath = p.join(root, 'stale.fetproject');
      await saveDayDocument(stalePath, stale);
      final [staleChecked] = check([stalePath]);
      expect(staleChecked['valid'], isTrue, reason: '${staleChecked['error']}');
      expect(
        (((staleChecked['runs'] as List).single as Map)['fusion'] as Map)['state'],
        'needsRevalidation',
      );
    },
    skip: checker == null ? 'Set FLAPPEDEAR_OVERLAYS_CHECK to tool/cpp_project_check' : false,
  );
}
