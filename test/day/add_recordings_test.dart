import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../../packages/telemetry_core/test/rcz/rcz_fixture.dart';
import 'day_results_page_test.dart' show FakeDocuments, circuitVbo;
import 'rectangle_vbo.dart';
import 'recovery_test.dart' show FileRecoveryStore;

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

/// An addition that finishes only when cancelled.
final class _PendingAppender implements DayAppender {
  @override
  DayAppendJob start(DayAppendRequest request, void Function(int, int) _) =>
      _PendingJob();
}

final class _PendingJob implements DayAppendJob {
  final _completer = Completer<DayAppendOutcome>();

  @override
  Future<DayAppendOutcome> get result => _completer.future;

  @override
  void cancel() => _completer.completeError(const OperationCancelled());
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

  test('a reopened day keeps the group it was saved with', () async {
    final a = write('a.vbo', [30, 28, 31, 30]);
    final r = '${directory.path}/r.vbo';
    File(r).writeAsStringSync(rectangleVbo([(_) => 20, (_) => 21]));
    final first = runDayImport((paths: [a, r], includeSubfolders: false));
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    expect(controller.analysis.groups, hasLength(2));
    final other = controller.analysis.groups.firstWhere(
      (group) => group.id != controller.analysis.chosenGroupId,
    );
    controller.chooseGroup(other.id);
    final path = '${directory.path}/Day.fetproject';
    await controller.save(path);

    final opened = DayResultsController.opened(
      openDay(path),
      appender: _SyncAppender(),
    );
    expect(opened.analysis.chosenGroupId, other.id);
    final b = write('b.vbo', [29, 33, 30]);
    expect((await opened.addRecordings([b])).added, ['Session 3']);
    expect(opened.analysis.chosenGroupId, other.id);
    final saved = (readDayDocument(path)['event'] as Map)['analysisDecisions'];
    expect((saved as Map)['comparisonGroupId'], other.id);
  });

  test('adding to a saved day leaves another day\'s unsaved work', () async {
    final store = FileRecoveryStore('${directory.path}/day-recovery.json');
    // Day A, changed and not saved: the app keeps it for recovery.
    final other = runDayImport((
      paths: [
        write('x.vbo', [31, 31, 31]),
      ],
      includeSubfolders: false,
    ));
    final unsaved = DayResultsController(
      runs: other.runs,
      analysis: other.analysis!,
      recovery: store,
    );
    await unsaved.flushRecovery();
    unsaved.dispose();
    final kept = (await store.load())!;

    // Day B, saved, gets a shared recording.
    final first = runDayImport((
      paths: [
        write('a.vbo', [30, 28, 31]),
      ],
      includeSubfolders: false,
    ));
    final path = '${directory.path}/B.fetproject';
    final saved = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
    );
    await saved.save(path);
    saved.dispose();
    final day = DayResultsController.opened(
      openDay(path),
      recovery: store,
      appender: _SyncAppender(),
    );
    final addition = await day.addRecordings([
      write('b.vbo', [29, 33]),
    ]);
    expect(addition.savedTo, path);
    await day.flushRecovery();
    day.dispose();
    final after = (await store.load())!;
    expect(
      (after.document['event'] as Map)['id'],
      (kept.document['event'] as Map)['id'],
    );
    expect(after.timestamp, kept.timestamp);
  });

  test(
    'a session added during a save leaves another day\'s unsaved work',
    () async {
      final store = FileRecoveryStore('${directory.path}/day-recovery.json');
      final other = runDayImport((
        paths: [
          write('x.vbo', [31, 31, 31]),
        ],
        includeSubfolders: false,
      ));
      final unsaved = DayResultsController(
        runs: other.runs,
        analysis: other.analysis!,
        recovery: store,
      );
      await unsaved.flushRecovery();
      unsaved.dispose();
      final kept = (await store.load())!;

      final first = runDayImport((
        paths: [
          write('a.vbo', [30, 28, 31]),
        ],
        includeSubfolders: false,
      ));
      final path = '${directory.path}/B.fetproject';
      final saved = DayResultsController(
        runs: first.runs,
        analysis: first.analysis!,
      );
      await saved.save(path);
      saved.dispose();
      final gate = Completer<void>();
      final second = Completer<void>();
      var writes = 0;
      final day = DayResultsController.opened(
        openDay(path),
        recovery: store,
        appender: _SyncAppender(),
        writer: (path, document) async {
          await (++writes == 1 ? gate.future : second.future);
          await saveDayDocument(path, document);
        },
      );
      final saving = day.save(path);
      final adding = day.addRecordings([
        write('b.vbo', [29, 33]),
      ]);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await saving;
      // Longer than the recovery delay, while the second save runs.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      second.complete();
      expect((await adding).savedTo, path);
      await day.flushRecovery();
      day.dispose();
      final after = (await store.load())!;
      expect(
        (after.document['event'] as Map)['id'],
        (kept.document['event'] as Map)['id'],
      );
      expect(writes, 2);
    },
  );

  test('an added session counts toward the day\'s speed units', () async {
    final first = runDayImport((
      paths: [
        write('a.vbo', [30, 28, 31]),
      ],
      includeSubfolders: false,
    ));
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    addTearDown(controller.dispose);
    expect(declaredSpeedUnits, hasLength(1));
    await controller.addRecordings([
      write('b.vbo', [29, 33]),
    ]);
    expect(declaredSpeedUnits, hasLength(2));
  });

  test('a session added while the day is being saved is not lost', () async {
    final a = write('a.vbo', [30, 28, 31]);
    final b = write('b.vbo', [29, 33]);
    final first = runDayImport((paths: [a], includeSubfolders: false));
    final gate = Completer<void>();
    final written = <String>[];
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
      writer: (path, document) async {
        if (written.isEmpty) await gate.future;
        await saveDayDocument(path, document);
        written.add(path);
      },
    );
    final path = '${directory.path}/Day.fetproject';
    final saving = controller.save(path);
    final adding = controller.addRecordings([b]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.runs, hasLength(2));
    gate.complete();
    await saving;
    final addition = await adding;
    // Saved again once the first save, made before the session came, ended.
    expect(addition.savedTo, path);
    expect(written, [path, path]);
    expect(controller.dirty, isFalse);
    final runs = (readDayDocument(path)['event'] as Map)['runs'] as List;
    expect(runs, hasLength(2));
  });

  test(
    'closing the day while adding says the recordings were not added',
    () async {
      final a = write('a.vbo', [30, 28, 31]);
      final first = runDayImport((paths: [a], includeSubfolders: false));
      final controller = DayResultsController(
        runs: first.runs,
        analysis: first.analysis!,
        appender: _PendingAppender(),
      );
      final adding = controller.addRecordings([
        write('b.vbo', [29, 33]),
      ]);
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      final addition = await adding;
      expect(addition.closed, isTrue);
      expect(addition.added, isEmpty);
    },
  );

  test('a save asked for while another runs follows it', () async {
    final a = write('a.vbo', [30, 28, 31]);
    final first = runDayImport((paths: [a], includeSubfolders: false));
    final gate = Completer<void>();
    final written = <String>[];
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      writer: (path, document) async {
        if (written.isEmpty) await gate.future;
        await saveDayDocument(path, document);
        written.add(path);
      },
    );
    final one = '${directory.path}/One.fetproject';
    final two = '${directory.path}/Two.fetproject';
    final firstSave = controller.save(one);
    final second = controller.save(two);
    gate.complete();
    await Future.wait([firstSave, second]);
    expect(written, [one, two]);
    expect(controller.documentPath, two);
  });

  test('the RCZ of a session already in the day becomes its alternative', () async {
    // Synthetic recordings of one 31-second drive, as VBO and as RCZ.
    final origin = DateTime.fromMillisecondsSinceEpoch(
      fixtureOrigin + 100,
      isUtc: true,
    );
    String two(int value) => value.toString().padLeft(2, '0');
    final text = StringBuffer(
      'File created on ${two(origin.day)}/${two(origin.month)}/${origin.year} at '
      '${two(origin.hour)}:${two(origin.minute)}:${two(origin.second)}\n'
      '[comments]\nGenerated by RaceChrono Pro v10.2.4\n'
      '[column names]\ntime latitude longitude velocity\n[data]\n',
    );
    for (var i = 0; i < 32; ++i) {
      final t = origin.add(Duration(seconds: i));
      final clock =
          '${two(t.hour)}${two(t.minute)}${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
      final latitude = ((50.0 + i * .0001) * 60.0).toStringAsFixed(9);
      text.write('$clock $latitude -1200 72\n');
    }
    final vbo = '${directory.path}/export.vbo';
    File(vbo).writeAsStringSync(text.toString());
    final timestamps = ByteData(32 * 8), coordinates = ByteData(32 * 8);
    final speed = ByteData(32 * 4);
    for (var i = 0; i < 32; ++i) {
      timestamps.setInt64(i * 8, fixtureOrigin + 100 + i * 1000, Endian.little);
      coordinates.setInt32(i * 8, 300000000 + i * 600, Endian.little);
      coordinates.setInt32(i * 8 + 4, 120000000, Endian.little);
      speed.setInt32(i * 4, 20000, Endian.little);
    }
    final rcz = '${directory.path}/archive.rcz';
    File(rcz).writeAsBytesSync(
      zip(
        fixtureMembers()
          ..['channel_1_300_0_1_1'] = timestamps.buffer.asUint8List()
          ..['channel_1_300_0_3_1'] = coordinates.buffer.asUint8List()
          ..['channel_1_300_0_4_0'] = speed.buffer.asUint8List(),
      ),
    );
    // Imported together they are one session.
    expect(
      runDayImport((paths: [vbo, rcz], includeSubfolders: false)).runs,
      hasLength(1),
    );
    final first = runDayImport((paths: [vbo], includeSubfolders: false));
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _SyncAppender(),
    );
    final addition = await controller.addRecordings([rcz]);
    expect(addition.added, isEmpty);
    expect(addition.combined, ['Session 1']);
    expect(addition.notes, [
      'archive.rcz: the same drive as Session 1 in the other format; kept as '
          'its alternative source.',
    ]);
    expect(controller.runs, hasLength(1));
    await controller.fusionsSettled;
    // A steady 72 km/h for 31 s has nothing to line the clocks up on.
    final fusion = controller.fusion(controller.runs.single.run.id)!;
    expect(fusion.fused, isFalse);
    expect(fusion.alternativeFormat, RecordingFormat.rcz);
  });

  testWidgets('the day stays open while a session is being added', (
    tester,
  ) async {
    final a = write('a.vbo', [30, 28, 31]);
    final first = runDayImport((paths: [a], includeSubfolders: false));
    final controller = DayResultsController(
      runs: first.runs,
      analysis: first.analysis!,
      appender: _PendingAppender(),
    );
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DayResultsPage.controller(
                  controller: controller,
                  documents: FakeDocuments(),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    unawaited(
      controller.addRecordings([
        write('b.vbo', [29, 33]),
      ]),
    );
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DayResultsPage), findsOneWidget);
    expect(find.text('Wait until the session is added.'), findsOneWidget);
    controller.cancelAdding();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(controller.adding, isFalse);
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(DayResultsPage), findsNothing);
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
