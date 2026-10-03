import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

void main() {
  group('runMetadataProblem', () {
    test('accepts a name and bounded texts', () {
      expect(runMetadataProblem(const RunMetadata(name: 'Session 1')), isNull);
      expect(
        runMetadataProblem(
          RunMetadata(name: 'x' * 160, notes: 'n' * 4096, conditions: '', setupChanges: 's'),
        ),
        isNull,
      );
    });

    test('refuses a blank, long or NUL name and long or NUL texts', () {
      expect(runMetadataProblem(const RunMetadata(name: '  ')), isNotNull);
      // Overlays counts the name as typed, before trimming.
      expect(runMetadataProblem(RunMetadata(name: ' ${'x' * 160}')), isNotNull);
      expect(runMetadataProblem(const RunMetadata(name: 'a\u0000b')), isNotNull);
      expect(runMetadataProblem(RunMetadata(name: 'a', notes: 'n' * 4097)), isNotNull);
      expect(runMetadataProblem(const RunMetadata(name: 'a', conditions: '\u0000')), isNotNull);
      expect(runMetadataProblem(const RunMetadata(name: 'a', setupChanges: 'x\u0000')), isNotNull);
    });

    test('counts UTF-16 code units, as Qt does', () {
      // 80 emoji are 160 code units.
      expect(runMetadataProblem(RunMetadata(name: '🏁' * 80)), isNull);
      expect(runMetadataProblem(RunMetadata(name: '🏁' * 81)), isNotNull);
    });
  });

  group('applyRunMetadata', () {
    test('trims the name and keeps texts as written', () {
      final run = <String, Object?>{'id': 'r', 'name': 'Session 1'};
      expect(
        applyRunMetadata(
          run,
          const RunMetadata(name: '  Warm-up  ', notes: ' Dry line ', conditions: 'Wet'),
        ),
        isTrue,
      );
      expect(run, {'id': 'r', 'name': 'Warm-up', 'notes': ' Dry line ', 'conditions': 'Wet'});
    });

    test('an unchanged legacy record gains no keys', () {
      final run = <String, Object?>{'id': 'r', 'name': 'Session 1'};
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1')), isFalse);
      expect(run, {'id': 'r', 'name': 'Session 1'});
    });

    test('a cleared or blank text is stored as null, as Overlays stores it', () {
      final run = <String, Object?>{
        'id': 'r',
        'name': 'Session 1',
        'notes': 'Old',
        'conditions': null,
      };
      expect(
        applyRunMetadata(run, const RunMetadata(name: 'Session 1', notes: '', setupChanges: '  ')),
        isTrue,
      );
      expect(run, {
        'id': 'r',
        'name': 'Session 1',
        'notes': null,
        'conditions': null,
        'setupChanges': null,
      });
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1')), isFalse);
    });

    test('reads a stored document run', () {
      final metadata = RunMetadata.fromRun(const {
        'name': 'Session 2',
        'notes': 'N',
        'conditions': null,
      });
      expect(metadata, const RunMetadata(name: 'Session 2', notes: 'N'));
    });
  });

  test('applyRunMetadataEdits copies edited runs and adds runs not saved yet', () {
    final stored = <String, Object?>{'id': 'a', 'name': 'Session 1', 'notes': 'x'};
    final runs = applyRunMetadataEdits(
      [stored, 7],
      {
        'a': const RunMetadata(name: 'Session 1', notes: 'y'),
        'b': const RunMetadata(name: 'Session 2', conditions: 'Dry'),
      },
    );
    expect(stored['notes'], 'x');
    expect(runs, [
      {'id': 'a', 'name': 'Session 1', 'notes': 'y'},
      7,
      {'id': 'b', 'name': 'Session 2', 'conditions': 'Dry'},
    ]);
  });

  test('dayNameProblem follows the event name rules', () {
    expect(dayNameProblem('Day 2026-08-29'), isNull);
    expect(dayNameProblem(' ${'x' * 160} '), isNull);
    expect(dayNameProblem('x' * 161), isNotNull);
    expect(dayNameProblem(' '), isNotNull);
    expect(dayNameProblem('a\u0000'), isNotNull);
  });

  group('a day', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('run_metadata'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('saves edited metadata and a renamed day, and opens them again', () async {
      final root = directory.resolveSymbolicLinksSync();
      final a = p.join(root, 'a.vbo');
      final b = p.join(root, 'b.vbo');
      File(a).writeAsStringSync(circuitVbo([30, 28, 31]));
      File(b).writeAsStringSync(circuitVbo([29, 32]));
      final runs = nameRunsInRecordingOrder(prepareTelemetryImport([a, b]).runs);
      var analysis = analyzeDay([
        for (final named in runs)
          DayRunInput(
            runId: named.run.id,
            name: named.name,
            contentSha256: named.run.contentSha256,
            session: named.run.telemetry,
            laps: named.run.laps,
          ),
      ]);
      final first = runs.first.run.id;
      analysis = renameDayRun(analysis, first, 'Warm-up');
      expect(
        {
          for (final row in analysis.rows)
            if (row.runId == first) row.runName,
        },
        {'Warm-up'},
      );
      expect([for (final run in analysis.ranking!.runs) run.runName], contains('Warm-up'));
      final named = [
        for (final run in runs) run.run.id == first ? (run: run.run, name: 'Warm-up') : run,
      ];
      final path = p.join(root, 'day.fetproject');
      final document = dayDocument(
        eventId: newEventId(),
        name: 'Łódź, morning',
        runs: named,
        analysis: analysis,
        projectPath: path,
        runMetadata: {
          first: const RunMetadata(
            name: 'Warm-up',
            notes: 'Brake earlier into T1',
            conditions: 'Dry, 18 °C',
            setupChanges: 'Tyres +0.1 bar',
          ),
        },
      );
      expect(fet.validateFetproject(document), isNull);
      await saveDayDocument(path, document);
      final opened = openDay(path);
      expect(opened.name, 'Łódź, morning');
      final run = ((opened.document['event']! as Map)['runs']! as List).firstWhere(
        (run) => (run as Map)['id'] == first,
      ) as Map<String, Object?>;
      expect(
        RunMetadata.fromRun(run),
        const RunMetadata(
          name: 'Warm-up',
          notes: 'Brake earlier into T1',
          conditions: 'Dry, 18 °C',
          setupChanges: 'Tyres +0.1 bar',
        ),
      );
      final other = ((opened.document['event']! as Map)['runs']! as List).firstWhere(
        (run) => (run as Map)['id'] != first,
      ) as Map<String, Object?>;
      for (final key in runMetadataTextKeys) {
        expect(other.containsKey(key), isFalse);
      }
      expect([for (final run in opened.runs) run.name], contains('Warm-up'));
    });
  });
}
