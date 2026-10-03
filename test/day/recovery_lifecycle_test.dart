import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/recovery_store.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_page_test.dart' show FakeDocuments, circuitVbo;
import '../support/temp_directory.dart';

// Its own file and one widget test: recovery work is queued app-wide, and
// work queued under another test's fake clock never finishes.

/// Keeps recovery snapshots in memory and counts them.
final class MemoryRecoveryStore implements RecoveryStore {
  final List<DayRecovery> written = [];

  @override
  Future<String?> path() async => '/memory/day-recovery.json';

  @override
  Future<DayRecovery?> load() async => written.lastOrNull;

  @override
  Future<void> write(DayRecovery recovery) async => written.add(recovery);

  @override
  Future<void> clear() async => written.clear();
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('lifecycle'));
  tearDown(() => deleteTemporaryDirectory(directory));

  DayImportOutcome importDay() {
    final path = '${directory.path}/a.vbo';
    File(path).writeAsStringSync(circuitVbo([30, 28, 31]));
    return runDayImport((paths: [path], includeSubfolders: false));
  }

  testWidgets('writes waiting changes when the app leaves the foreground', (
    tester,
  ) async {
    final outcome = importDay();
    final memory = MemoryRecoveryStore();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      recovery: memory,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: FakeDocuments(),
          recovery: memory,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(memory.written, hasLength(1));

    final rows = [
      for (final row in controller.analysis.rows)
        if (row.type == LapSectionType.lap) row,
    ];
    // The platforms go through inactive first whenever the app leaves the
    // foreground (then hidden, paused and, when closed, detached).
    Future<void> leave() async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
    }

    Future<void> resume() async {
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
    }

    for (final (index, reason) in ['Traffic', 'Red flag'].indexed) {
      expect(controller.exclude(rows[index], reason), isTrue);
      // Well before the recovery delay, the app leaves the foreground.
      await tester.pump(const Duration(milliseconds: 10));
      await leave();
      expect(memory.written, hasLength(index + 2));
      expect(
        openRecoveredDay(memory.written.last).exclusions.values,
        contains(reason),
      );
      await resume();
      await tester.pump(const Duration(seconds: 1));
      expect(
        memory.written,
        hasLength(index + 2),
        reason: 'nothing left to write',
      );
    }

    // A desktop quit waits for the write and then lets the app exit.
    expect(controller.exclude(rows[2], 'Quit'), isTrue);
    await tester.pump(const Duration(milliseconds: 10));
    final exit = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(await exit, AppExitResponse.exit);
    expect(memory.written, hasLength(4));
    expect(
      openRecoveredDay(memory.written.last).exclusions.values,
      contains('Quit'),
    );
  });
}
