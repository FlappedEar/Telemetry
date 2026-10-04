// The reviewed import (FET-58), as Overlays' `confirmBatchImport` checks it,
// on synthetic recordings only.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_pair.dart';

void main() {
  group('checkImportChoices', () {
    const runs = ['a', 'b', 'c'];

    test('accepts runs of their own, skips and a recording joining a run', () {
      expect(checkImportChoices(runs, {'a': 'a', 'b': 'a', 'c': skipRecording}), isNull);
      expect(checkImportChoices(runs, {'a': 'a', 'b': 'b', 'c': 'c'}), isNull);
    });

    test('refuses choices for other recordings than the reviewed ones', () {
      expect(checkImportChoices(runs, {'a': 'a', 'b': 'b'}), ImportChoiceProblem.changed);
      expect(
        checkImportChoices(runs, {'a': 'a', 'b': 'b', 'c': 'c', 'd': 'd'}),
        ImportChoiceProblem.changed,
      );
      expect(checkImportChoices(runs, {'a': 'a', 'b': 'x', 'c': 'c'}), ImportChoiceProblem.changed);
    });

    test('a recording joins only a run of its own (no chains, no skipped run)', () {
      expect(
        checkImportChoices(runs, {'a': skipRecording, 'b': 'a', 'c': 'c'}),
        ImportChoiceProblem.targetNotRun,
      );
      expect(
        checkImportChoices(runs, {'a': 'b', 'b': 'c', 'c': 'c'}),
        ImportChoiceProblem.targetNotRun,
      );
      expect(
        checkImportChoices(runs, {'a': 'b', 'b': 'a', 'c': 'c'}),
        ImportChoiceProblem.targetNotRun,
      );
    });

    test('a run keeps one other recording', () {
      expect(
        checkImportChoices(runs, {'a': 'a', 'b': 'a', 'c': 'a'}),
        ImportChoiceProblem.tooManyRecordings,
      );
    });

    test('nothing to import is refused', () {
      expect(
        checkImportChoices(runs, {for (final run in runs) run: skipRecording}),
        ImportChoiceProblem.nothingSelected,
      );
    });

    test("a recording may join one of the day's sessions without one", () {
      expect(checkImportChoices(['a'], {'a': 's1'}, runs: {'s1', 's2'}), isNull);
      expect(
        checkImportChoices(['a'], {'a': 's1'}, runs: {'s1'}, alreadyGrouped: {'s1'}),
        ImportChoiceProblem.tooManyRecordings,
      );
      expect(
        checkImportChoices(['a', 'b'], {'a': 's1', 'b': 's1'}, runs: {'s1'}),
        ImportChoiceProblem.tooManyRecordings,
      );
      // Not one of the day's sessions, nor a reviewed recording.
      expect(checkImportChoices(['a'], {'a': 's3'}, runs: {'s1'}), ImportChoiceProblem.changed);
    });
  });

  test('releaseOrphanedChoices makes a recording whose run went away a run again', () {
    expect(releaseOrphanedChoices({'a': skipRecording, 'b': 'a', 'c': 'c'}), {
      'a': skipRecording,
      'b': 'b',
      'c': 'c',
    });
    expect(releaseOrphanedChoices({'a': 'c', 'b': 'a', 'c': 'c'}), {'a': 'c', 'b': 'b', 'c': 'c'});
    expect(releaseOrphanedChoices({'a': 's1'}, runs: {'s1'}), {'a': 's1'});
  });

  group('a VBO and an RCZ of one drive', () {
    late Directory directory;
    late TelemetryImportPlan plan;
    late TelemetryRunProposal vbo, rcz;
    setUp(() {
      directory = Directory.systemTemp.createTempSync('import_review');
      final (vboPath, rczPath) = writeFusionPair(directory.path);
      final other = p.join(directory.path, 'other.vbo');
      File(other).writeAsStringSync(
        '[header]\ncoordinate units = degrees\n[column names]\ntime latitude longitude velocity\n'
        '[data]\n0 50 20 72\n1 50.001 20.001 80\n',
      );
      plan = prepareTelemetryImport([rczPath, vboPath, other]);
      rcz = plan.runs[0];
      vbo = plan.runs[1];
    });
    tearDown(() => directory.deleteSync(recursive: true));

    test('are one run without review: the VBO, with the RCZ as its alternative', () {
      final automatic = automaticImportChoices(plan);
      expect(automatic, {rcz.id: vbo.id, vbo.id: vbo.id, plan.runs[2].id: plan.runs[2].id});
      expect(chosenRuns(plan, automatic), [vbo, plan.runs[2]]);
      expect(importedAlternatives(plan, [vbo, plan.runs[2]]), {vbo.id: rcz});
    });

    test('the review can make the RCZ the run and the VBO its alternative', () {
      final choices = {rcz.id: rcz.id, vbo.id: rcz.id, plan.runs[2].id: skipRecording};
      expect(checkImportChoices(plan.runs.map((run) => run.id), choices), isNull);
      expect(chosenRuns(plan, choices), [rcz]);
      expect(importedAlternatives(plan, [rcz], choices: choices), {rcz.id: vbo});
    });

    test('the review can keep them apart', () {
      final choices = {for (final run in plan.runs) run.id: run.id};
      expect(chosenRuns(plan, choices), plan.runs);
      expect(importedAlternatives(plan, plan.runs, choices: choices), isEmpty);
    });

    test('the review can pair recordings the automatic grouping does not', () {
      final other = plan.runs[2];
      final choices = {rcz.id: rcz.id, vbo.id: vbo.id, other.id: vbo.id};
      expect(importedAlternatives(plan, [rcz, vbo], choices: choices), {vbo.id: other});
    });
  });
}
