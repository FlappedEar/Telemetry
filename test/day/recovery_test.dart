import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/recovery_store.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_page_test.dart' show FakeDocuments, circuitVbo;
import '../support/temp_directory.dart';

/// The recovery file in a test folder.
final class FileRecoveryStore implements RecoveryStore {
  FileRecoveryStore(this.file);

  final String file;

  @override
  Future<String?> path() async => file;

  @override
  Future<DayRecovery?> load() async => readDayRecovery(file);

  @override
  Future<void> write(DayRecovery recovery) => writeDayRecovery(file, recovery);

  @override
  Future<void> clear() => clearDayRecovery(file);
}

void main() {
  late Directory directory;
  late FileRecoveryStore store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('day_recovery');
    store = FileRecoveryStore('${directory.path}/support/day-recovery.json');
  });
  tearDown(() => deleteTemporaryDirectory(directory));

  DayImportOutcome importDay() {
    final path = '${directory.path}/a.vbo';
    File(path).writeAsStringSync(circuitVbo([30, 28, 31]));
    return runDayImport((paths: [path], includeSubfolders: false));
  }

  test('keeps an unsaved day until it is saved', () async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      recovery: store,
      writer: (path, document) async {},
    );
    await controller.flushRecovery();
    expect((await store.load())!.originalPath, isEmpty);

    final best = controller.ranking!.bestOfDay!;
    final row = controller.analysis.rows.firstWhere(
      (row) => row.reference == best.reference,
    );
    expect(controller.exclude(row, 'Traffic'), isTrue);
    await controller.flushRecovery();
    final kept = (await store.load())!;
    expect(kept.eventId, controller.eventId);

    final restored = DayResultsController.recovered(
      openRecoveredDay(kept),
      kept,
      recovery: store,
    );
    expect(restored.dirty, isTrue);
    expect(restored.documentPath, isNull);
    expect(restored.exclusions.values, ['Traffic']);
    expect(
      restored.ranking!.bestOfDay!.reference,
      controller.ranking!.bestOfDay!.reference,
    );

    await controller.save('${directory.path}/day.fetproject');
    await controller.flushRecovery();
    expect(await store.load(), isNull);
    controller.dispose();
    restored.dispose();
  });

  test(
    'a change made while saving keeps the day unsaved and recoverable',
    () async {
      final outcome = importDay();
      final written = <Map<String, Object?>>[];
      var blocked = Completer<void>();
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        recovery: store,
        writer: (path, document) async {
          written.add(document);
          await blocked.future;
        },
      );
      final best = controller.ranking!.bestOfDay!;
      final row = controller.analysis.rows.firstWhere(
        (row) => row.reference == best.reference,
      );

      // The save's snapshot is taken, then the user excludes a lap while the
      // file is still being written.
      final path = '${directory.path}/day.fetproject';
      final saving = controller.save(path);
      expect(controller.saving, isTrue);
      expect(controller.exclude(row, 'Traffic'), isTrue);
      blocked.complete();
      await saving;
      await controller.flushRecovery();

      expect(written, hasLength(1));
      expect(openDayDocument(written.single, path).exclusions, isEmpty);
      expect(controller.documentPath, path);
      expect(controller.dirty, isTrue);
      final kept = (await store.load())!;
      expect(kept.originalPath, path);
      expect(openRecoveredDay(kept).exclusions.values, [
        'Traffic',
      ], reason: 'the exclusion survives in recovery');

      // Saving again writes the exclusion and only then marks the day clean;
      // repeating the same exclusion while it saves changes nothing.
      blocked = Completer<void>();
      final again = controller.save(path);
      expect(controller.exclude(row, 'Traffic'), isTrue);
      blocked.complete();
      await again;
      await controller.flushRecovery();
      expect(controller.dirty, isFalse);
      expect(openDayDocument(written.last, path).exclusions.values, [
        'Traffic',
      ]);
      expect(await store.load(), isNull);
      controller.dispose();
    },
  );

  testWidgets('offers to restore or discard the unsaved day', (tester) async {
    // Lets file and isolate work finish between frames.
    Future<void> settle() async {
      for (var i = 0; i < 10; ++i) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
    }

    await tester.runAsync(() async {
      final outcome = importDay();
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        name: 'Test day',
        recovery: store,
      );
      await controller.flushRecovery();
      controller.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayImportPage(documents: FakeDocuments(), recovery: store),
      ),
    );
    await settle();
    expect(find.textContaining('Test day has unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; ++i) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (find.byType(DayResultsPage).evaluate().isNotEmpty) break;
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(DayResultsPage), findsOneWidget);
    expect(find.text('Day results'), findsOneWidget);

    await tester.pageBack();
    await settle();
    // The day just left is listed with its sessions, still unsaved.
    expect(find.text('Test day'), findsOneWidget);
    expect(find.textContaining('Not saved yet'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('importSession Session 1')),
      findsOneWidget,
    );
    await tester.tap(find.text('Discard…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await settle();
    expect(find.textContaining('has unsaved changes'), findsNothing);
    expect(find.text('Test day'), findsNothing);
    expect(File(store.file).existsSync(), isFalse);
  });
}
