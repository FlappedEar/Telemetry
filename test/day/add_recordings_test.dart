import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_page_test.dart' show FakeDocuments, circuitVbo;

/// Prepares additions on the test's own thread.
final class _SyncAppender implements DayAppender {
  final requests = <DayAppendRequest>[];

  @override
  DayAppendJob start(DayAppendRequest request, void Function(int, int) _) {
    requests.add(request);
    return _SyncJob(runDayAppend(request));
  }
}

final class _SyncJob implements DayAppendJob {
  _SyncJob(DayAppendOutcome outcome) : result = Future.value(outcome);

  @override
  final Future<DayAppendOutcome> result;

  @override
  void cancel() {}
}

final class _FakePickers implements RecordingPickers {
  _FakePickers(this.recordings);

  final List<String> recordings;

  @override
  Future<List<String>> pickRecordings() async => recordings;

  @override
  Future<String?> pickFolder() async => null;
}

// Recordings here are synthetic (circuitVbo): no real data.
void main() {
  late Directory directory;
  setUp(
    () => directory = Directory.systemTemp.createTempSync('add_recordings'),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  String write(String name, List<double> speeds) {
    final path = '${directory.path}/$name';
    File(path).writeAsStringSync(circuitVbo(speeds));
    return path;
  }

  String describe(DayAnalysis day) => [
    for (final row in day.rows) '${row.displayName} ${row.referenceEligible}',
    for (final group in day.groups)
      '${group.id} ${group.runIds} ${group.ranking?.bestOfDay?.displayName}',
    'chosen ${day.chosenGroupId}',
  ].join('\n');

  test('adds only the new recording as the next session', () async {
    final a = write('a.vbo', [30, 28, 31]);
    final b = write('b.vbo', [29, 33]);
    final first = runDayImport((paths: [a], includeSubfolders: false));
    final appender = _SyncAppender();
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: appender,
    );
    final best = controller.ranking!.bestOfDay!;
    final row = controller.analysis.rows.firstWhere(
      (row) => row.reference == best.reference,
    );
    expect(controller.exclude(row, 'Traffic'), isTrue);

    final addition = await controller.addRecordings([b]);
    expect(addition.added, ['Session 2']);
    expect(addition.error, isEmpty);
    expect(addition.savedTo, isNull);
    expect(controller.lastAddition, same(addition));
    // The day's own recording was not offered for reading again.
    expect(appender.requests.single.paths, [b]);
    expect(appender.requests.single.runCount, 1);
    expect(controller.runs.map((named) => named.name), [
      'Session 1',
      'Session 2',
    ]);
    expect(controller.dirty, isTrue);
    expect(controller.exclusions.values, ['Traffic']);

    final whole = runDayImport((paths: [a, b], includeSubfolders: false));
    expect(
      describe(controller.analysis),
      describe(
        rerankDay(whole.analysis!, exclusions: {best.reference: 'Traffic'}),
      ),
    );
    expect(controller.ranking!.bestOfDay!.displayName, 'Session 2 · LAP 2');
  });

  test('a recording already in the day is not added twice', () async {
    final a = write('a.vbo', [30, 28, 31]);
    final copy = write('copy.vbo', [30, 28, 31]);
    final first = runDayImport((paths: [a], includeSubfolders: false));
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    final before = controller.analysis;
    final addition = await controller.addRecordings([copy]);
    expect(addition.added, isEmpty);
    expect(addition.notes, ['copy.vbo: already in this day.']);
    expect(controller.runs, hasLength(1));
    expect(controller.analysis, same(before));
  });

  test('a saved day is saved again with the new session', () async {
    final a = write('a.vbo', [30, 28, 31]);
    final b = write('b.vbo', [29, 33]);
    final first = runDayImport((paths: [a], includeSubfolders: false));
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);
    final saved = readDayDocument(path);

    final addition = await controller.addRecordings([b]);
    expect(addition.savedTo, path);
    expect(controller.dirty, isFalse);
    final document = readDayDocument(path);
    final runs = (document['event'] as Map)['runs'] as List;
    expect(
      [for (final run in runs) (run as Map)['name']],
      ['Session 1', 'Session 2'],
    );
    final state = document['documentState'] as Map;
    final savedState = saved['documentState'] as Map;
    expect(state['id'], savedState['id']);
    expect(
      int.parse('${state['savedRevision']}'),
      int.parse('${savedState['savedRevision']}') + 1,
    );

    // Opened again, the day adds its next recording as Session 3.
    final opened = DayResultsController.opened(
      openDay(path),
      appender: _SyncAppender(),
    );
    expect(opened.runs, hasLength(2));
    final c = write('c.vbo', [31, 30, 32]);
    expect((await opened.addRecordings([c])).added, ['Session 3']);
    expect(opened.analysis.groups.single.runIds, hasLength(3));
  });

  testWidgets('Add recordings on the day page adds and says so', (
    tester,
  ) async {
    final a = write('a.vbo', [30, 28, 31]);
    final b = write('b.vbo', [29, 33]);
    final first = runDayImport((paths: [a], includeSubfolders: false));
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: FakeDocuments(),
          pickers: _FakePickers([b]),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('addRecordings')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Session 2 added to the day.'), findsOneWidget);
    expect(controller.runs, hasLength(2));
  });
}
