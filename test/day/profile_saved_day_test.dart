// The driver profile measures a day from what was saved, not from edits made
// while the file was being written (audit F09). Synthetic recordings.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../support/inline_runners.dart';
import 'day_results_page_test.dart' show FakeDocuments, circuitVbo;

final class _Library extends ProfileLibrary {
  _Library(String folder)
    : super(
        store: FolderProfileStore(folder),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: <R>(FutureOr<R> Function() computation) async =>
            computation(),
      );

  final names = <String>[];
  final analyses = <DayAnalysis>[];

  @override
  Future<void> recordDay({
    required String eventId,
    required String path,
    required String name,
    required DayAnalysis analysis,
    Map<String, TelemetrySession?>? recordings,
    DayTheoreticalBest? theoreticalBest,
    Map<String, ProfileWeather?>? weather,
    Map<String, ProfileSetup?>? setups,
  }) {
    names.add(name);
    analyses.add(analysis);
    return super.recordDay(
      eventId: eventId,
      path: path,
      name: name,
      analysis: analysis,
      recordings: recordings,
      theoreticalBest: theoreticalBest,
      weather: weather,
      setups: setups,
    );
  }
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('saved_day'));
  tearDown(() => directory.deleteSync(recursive: true));

  DayImportOutcome importDay() {
    final path = '${directory.path}/a.vbo';
    File(path).writeAsStringSync(circuitVbo([30, 28, 31]));
    return runDayImport((paths: [path], includeSubfolders: false));
  }

  test('the saved day is the revision the writer was given', () async {
    final day = importDay();
    final gate = Completer<void>();
    var fail = false;
    final controller = DayResultsController(
      runs: day.runs,
      analysis: day.analysis!,
      writer: (path, document) async {
        await gate.future;
        if (fail) throw const FileSystemException('disk full');
      },
    );
    addTearDown(controller.dispose);
    expect(controller.savedDay, isNull);
    final first = controller.name;
    final analysisAtSave = controller.analysis;
    final saving = controller.save('${directory.path}/Day.fetproject');
    // Edits made while the writer waits.
    expect(controller.renameDay('Edited meanwhile'), isNull);
    final best = controller.ranking!.bestOfDay!;
    final row = controller.analysis.rows.firstWhere(
      (row) => row.reference == best.reference,
    );
    expect(controller.exclude(row, 'Traffic'), isTrue);
    expect(controller.analysis, isNot(same(analysisAtSave)));
    gate.complete();
    await saving;
    expect(controller.dirty, isTrue);
    expect(controller.savedDay!.name, first);
    expect(controller.savedDay!.analysis, same(analysisAtSave));
    expect(controller.name, 'Edited meanwhile');

    // The next save fails: the saved day stays the one on disk.
    fail = true;
    await expectLater(
      controller.save('${directory.path}/Day.fetproject'),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.savedDay!.name, first);
    fail = false;
    await controller.save('${directory.path}/Day.fetproject');
    expect(controller.savedDay!.name, 'Edited meanwhile');
    expect(controller.savedDay!.analysis, same(controller.analysis));
  });

  test(
    'a theoretical best belongs to the saved day only under its decisions',
    () async {
      final day = importDay();
      final controller = DayResultsController(
        runs: day.runs,
        analysis: day.analysis!,
        writer: (path, document) async {},
        theoreticalBestRunner: asyncRunner((job) async => job()),
      );
      addTearDown(controller.dispose);
      final path = '${directory.path}/Day.fetproject';
      await controller.save(path);
      expect(controller.savedTheoreticalBest, isNull);
      // Worked out after the save, for the saved day's decisions: recorded.
      await controller.requestTheoreticalBest();
      final best = controller.theoreticalBest;
      expect(best, isNotNull);
      expect(controller.savedTheoreticalBest, same(best));

      // A lap is excluded: the live best is for other decisions now.
      final row = controller.analysis.rows.firstWhere(
        (row) => row.reference == controller.ranking!.bestOfDay!.reference,
      );
      expect(controller.exclude(row, 'Traffic'), isTrue);
      await controller.requestTheoreticalBest();
      expect(
        controller.savedTheoreticalBest,
        isNot(same(controller.theoreticalBest)),
      );
      expect(controller.savedTheoreticalBest, isNull);
    },
  );

  test(
    'a best finished while the save runs counts only under the saved decisions',
    () async {
      final day = importDay();
      final gate = Completer<void>();
      final controller = DayResultsController(
        runs: day.runs,
        analysis: day.analysis!,
        writer: (path, document) => gate.future,
        theoreticalBestRunner: asyncRunner((job) async => job()),
      );
      addTearDown(controller.dispose);
      final saving = controller.save('${directory.path}/Day.fetproject');
      // A lap is excluded while the writer waits, and the best is worked out
      // for that: it is not the saved day's.
      final row = controller.analysis.rows.firstWhere(
        (row) => row.reference == controller.ranking!.bestOfDay!.reference,
      );
      expect(controller.exclude(row, 'Traffic'), isTrue);
      await controller.requestTheoreticalBest();
      expect(controller.theoreticalBest, isNotNull);
      gate.complete();
      await saving;
      expect(controller.savedTheoreticalBest, isNull);
      // Worked out again under the live decisions, which the file lacks.
      await controller.requestTheoreticalBest();
      expect(controller.theoreticalBest, isNotNull);
      expect(controller.savedTheoreticalBest, isNull);
    },
  );

  test('a day opened as its file holds it keeps that after edits and a failed save', () async {
    final day = importDay();
    final path = '${directory.path}/Day.fetproject';
    final first = DayResultsController(
      runs: day.runs,
      analysis: day.analysis!,
      writer: saveDayDocument,
    );
    addTearDown(first.dispose);
    await first.save(path);
    final document = readDayDocument(path);
    final opened = DayResultsController(
      runs: day.runs,
      analysis: day.analysis!,
      eventId: first.eventId,
      name: first.name,
      openedFrom: path,
      openedDocument: document,
      writer: (path, document) async =>
          throw const FileSystemException('disk full'),
    );
    addTearDown(opened.dispose);
    final name = opened.name;
    expect(opened.savedDay!.name, name);
    expect(opened.renameDay('Edited'), isNull);
    await expectLater(opened.save(path), throwsA(isA<FileSystemException>()));
    expect(opened.savedDay!.name, name);

    // A day restored with changes the file does not hold has no saved day.
    final restored = DayResultsController(
      runs: day.runs,
      analysis: day.analysis!,
      openedFrom: path,
      openedDocument: document,
      recovered: true,
      writer: (path, document) async {},
    );
    addTearDown(restored.dispose);
    expect(restored.savedDay, isNull);
    await restored.save(path);
    expect(restored.savedDay, isNotNull);
  });

  testWidgets('the profile records the saved revision, not the live edits', (
    tester,
  ) async {
    final day = importDay();
    final gate = Completer<void>();
    var fail = false;
    final controller = DayResultsController(
      runs: day.runs,
      analysis: day.analysis!,
      writer: (path, document) async {
        await gate.future;
        if (fail) throw const FileSystemException('disk full');
      },
    );
    final library = _Library('${directory.path}/Profile');
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: FakeDocuments(location: '${directory.path}/d.fetproject'),
          library: library,
        ),
      ),
    );
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 300 && !done(); ++i) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(done(), isTrue);
    }

    final original = controller.name;
    await until(() => controller.saving);
    expect(controller.renameDay('Edited meanwhile'), isNull);
    gate.complete();
    await until(() => library.names.isNotEmpty && !controller.saving);
    // Whatever was recorded so far is the revision the writer was given.
    expect(library.names, everyElement(original));

    // The autosave of the edit fails: the profile never saw it.
    fail = true;
    await tester.pump(const Duration(seconds: 3));
    await until(() => !controller.saving && controller.dirty);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(library.names, everyElement(original));

    // When it is saved, the profile follows.
    fail = false;
    await until(() => library.names.contains('Edited meanwhile'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'a save finishing after the page was left records what it wrote',
    (tester) async {
      final day = importDay();
      final gate = Completer<void>();
      final controller = DayResultsController(
        runs: day.runs,
        analysis: day.analysis!,
        writer: (path, document) => gate.future,
      );
      final library = _Library('${directory.path}/Profile');
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.controller(
            controller: controller,
            documents: FakeDocuments(
              location: '${directory.path}/d.fetproject',
            ),
            library: library,
          ),
        ),
      );
      final original = controller.name;
      for (var i = 0; i < 300 && !controller.saving; ++i) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(controller.saving, isTrue);
      expect(controller.renameDay('Edited meanwhile'), isNull);
      // The page is left while the file is written.
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      for (var i = 0; i < 300 && library.names.isEmpty; ++i) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(library.names, isNotEmpty);
      expect(library.names, everyElement(original));
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
