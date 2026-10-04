import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/diagnostics/app_diagnostics.dart';
import 'package:telemetry/diagnostics/diagnostics_page.dart';
import 'package:telemetry/import/day_import_controller.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart' show ImportChoices;

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
    void Function(int, int) progress, {
    ImportChoices? choices,
  }) => _Job(request);
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
      TelemetryApp(
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
    expect(find.text('1.84\u00a0s'), findsOneWidget);
    String trailing(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    expect(trailing('diagnosticsSessions'), '2');
    expect(trailing('diagnosticsSamples'), '$samples');
    expect(trailing('diagnosticsCurrentMemory'), '96.0\u00a0MiB');
    expect(trailing('diagnosticsPeakMemory'), '222.5\u00a0MiB');
  });

  testWidgets('says what is not available', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      TelemetryApp(
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

  testWidgets('the diagnostics page speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    final diagnostics = AppDiagnostics()
      ..recordImport(
        const ImportDiagnostics(
          steps: [
            (name: DiagnosticSteps.scan, duration: Duration(milliseconds: 120)),
          ],
          recordings: 2,
          sessions: 2,
          samples: 100,
          channelSamples: 400,
        ),
      )
      ..recordStep(
        DiagnosticSteps.theoreticalBest,
        const Duration(milliseconds: 1840),
      );
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: DiagnosticsPage(
          diagnostics: diagnostics,
          memory: () => (current: 96 * _mib, peak: null),
        ),
      ),
    );
    expect(find.text('Diagnostyka'), findsOneWidget);
    expect(find.text('Ostatni import'), findsOneWidget);
    expect(find.text('Wyszukiwanie zapisów'), findsOneWidget);
    expect(find.text('Odcinki i teoretyczny czas okrążenia'), findsOneWidget);
    expect(find.text('Pamięć'), findsOneWidget);
    expect(find.text('Niedostępne'), findsOneWidget);
    expect(find.text('96.0\u00a0MiB'), findsOneWidget);
    expect(find.text('1.84\u00a0s'), findsOneWidget);
    expect(find.text('Diagnostics'), findsNothing);
    expect(find.text('Last import'), findsNothing);
    expect(find.text(DiagnosticSteps.scan), findsNothing);
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

  testWidgets('a phone with text ×2 keeps each label readable', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(() => Intl.defaultLocale = null);
    for (final locale in const [Locale('en'), Locale('pl')]) {
      await tester.pumpWidget(
        TelemetryApp(
          locale: locale,
          home: DiagnosticsPage(
            diagnostics: AppDiagnostics(),
            memory: () => (current: 96 * _mib, peak: 222 * _mib),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = find.text(
        locale.languageCode == 'en' ? 'Current' : 'Bieżąca',
      );
      // At least a few letters per line, not one.
      expect(tester.getSize(label).width, greaterThan(80));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a desktop window keeps the page 720 wide', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TelemetryApp(
        home: DiagnosticsPage(
          diagnostics: AppDiagnostics(),
          memory: () => (current: 96 * _mib, peak: null),
        ),
      ),
    );
    final value = tester.getRect(
      find.byKey(const ValueKey('diagnosticsCurrentMemory')),
    );
    // At the right edge of the centred page, near its label.
    expect(value.right, closeTo((1600 + 720) / 2 - 16, 1));
    await tester.pumpWidget(const SizedBox());
  });
}
