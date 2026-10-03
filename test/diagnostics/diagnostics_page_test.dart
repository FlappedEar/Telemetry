import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/diagnostics/app_diagnostics.dart';
import 'package:telemetry/diagnostics/diagnostics_page.dart';
import 'package:telemetry/import/day_import_controller.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';

import '../day/rectangle_vbo.dart';
import '../support/temp_directory.dart';

/// Runs the real import synchronously.
final class _Job implements DayImportJob {
  _Job(this.request);
  final DayImportRequest request;

  @override
  Future<DayImportOutcome> get result => Future(() => runDayImport(request));

  @override
  void cancel() {}
}

final class _Importer implements DayImporter {
  @override
  DayImportJob start(
    DayImportRequest request,
    void Function(int, int) progress,
  ) => _Job(request);
}

const _mib = 1024 * 1024;

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('diagnostics'));
  tearDown(() => deleteTemporaryDirectory(directory));

  List<String> writeDay() => [
    for (final (name, speeds) in [
      ('a.vbo', [30.0, 28.0, 31.0]),
      ('b.vbo', [29.0, 32.0]),
    ])
      (File('${directory.path}/$name')..writeAsStringSync(
            rectangleVbo([
              for (final speed in speeds) rectangleLap(speed),
            ], car: true),
          ))
          .path,
  ];

  testWidgets('shows the last import step by step, its counts and memory', (
    tester,
  ) async {
    final diagnostics = AppDiagnostics();
    final controller = DayImportController(
      importer: _Importer(),
      diagnostics: diagnostics,
    );
    addTearDown(controller.dispose);
    final paths = writeDay();
    await tester.runAsync(() async {
      expect(controller.start(paths, includeSubfolders: false), isTrue);
      while (controller.isWorking) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    final finished = controller.state as DayImportFinished;
    final samples = finished.runs.fold(
      0,
      (sum, named) => sum + named.run.telemetry.sampleCount,
    );
    diagnostics.recordStep(
      DiagnosticSteps.theoreticalBest,
      const Duration(milliseconds: 1840),
    );

    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsPage(
          diagnostics: diagnostics,
          memory: () => (current: 96 * _mib, peak: 222 * _mib + _mib ~/ 2),
        ),
      ),
    );
    for (final step in [
      DiagnosticSteps.scan,
      DiagnosticSteps.parse,
      DiagnosticSteps.analysis,
      DiagnosticSteps.importTotal,
      DiagnosticSteps.theoreticalBest,
    ]) {
      expect(find.text(step), findsOneWidget);
    }
    expect(find.text('1.84 s'), findsOneWidget);
    String trailing(String key) =>
        ((tester.widget<ListTile>(find.byKey(ValueKey(key))).trailing!) as Text)
            .data!;
    expect(trailing('diagnosticsSessions'), '2');
    expect(trailing('diagnosticsSamples'), '$samples');
    expect(trailing('diagnosticsCurrentMemory'), '96.0 MiB');
    expect(trailing('diagnosticsPeakMemory'), '222.5 MiB');
  });

  testWidgets('says what is not available', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsPage(
          diagnostics: AppDiagnostics(),
          memory: () {
            ++reads;
            return (current: null, peak: null);
          },
        ),
      ),
    );
    expect(find.text('No day imported since the app started.'), findsOneWidget);
    expect(find.text('Not available'), findsNWidgets(2));
    final before = reads;
    await tester.tap(find.byKey(const ValueKey('refreshDiagnostics')));
    await tester.pump();
    expect(reads, greaterThan(before));
    // The memory is read again while the page is open.
    await tester.pump(const Duration(seconds: 2));
    expect(reads, greaterThan(before + 1));
  });

  test('reads the memory the platform reports', () {
    final memory = readProcessMemory();
    // The test machine reports both; a platform without them gives null.
    expect(memory.current, anyOf(isNull, greaterThan(0)));
    expect(
      memory.peak,
      anyOf(isNull, greaterThanOrEqualTo(memory.current ?? 0)),
    );
  });

  testWidgets('opens from the import page menu', (tester) async {
    final controller = DayImportController(
      importer: _Importer(),
      diagnostics: AppDiagnostics(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      TelemetryApp(home: DayImportPage(controller: controller)),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('openDiagnostics')));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticsPage), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticsPage), findsNothing);
  });

  testWidgets('opens from the day results menu', (tester) async {
    final outcome = runDayImport((paths: writeDay(), includeSubfolders: false));
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticsPage), findsOneWidget);
  });
}
