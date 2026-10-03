// The review before an import or an addition is committed (FET-58), on
// synthetic recordings only: a VBO and an RCZ of one drive
// (writeFusionPair) and other drives (circuitVbo).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/day_import_controller.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../../packages/telemetry_core/test/support/fusion_pair.dart';
import '../day/day_results_page_test.dart' show circuitVbo;
import '../support/temp_directory.dart';

final class _Done<T> {
  _Done(T value) : result = Future.value(value);
  final Future<T> result;
  void cancel() {}
}

final class _ImportJob extends _Done<DayImportOutcome> implements DayImportJob {
  _ImportJob(super.value);
}

final class _PreviewJob extends _Done<ImportPreview>
    implements ImportPreviewJob {
  _PreviewJob(super.value);
}

final class _AppendJob extends _Done<DayAppendOutcome> implements DayAppendJob {
  _AppendJob(super.value);
}

/// Imports on the test's own thread.
final class _Importer implements DayImporter {
  final choices = <ImportChoices?>[];

  @override
  DayImportJob start(
    DayImportRequest request,
    void Function(int, int) progress, {
    ImportChoices? choices,
  }) {
    this.choices.add(choices);
    return _ImportJob(runDayImport(request, choices: choices));
  }
}

/// Prepares reviews on the test's own thread.
final class _Preparer implements ImportPreparer {
  final requests = <DayImportRequest>[];

  @override
  ImportPreviewJob start(DayImportRequest request, void Function(int, int) _) {
    requests.add(request);
    return _PreviewJob(runImportPreview(request));
  }
}

/// Prepares additions on the test's own thread.
final class _Appender implements DayAppender {
  final requests = <DayAppendRequest>[];

  @override
  DayAppendJob start(DayAppendRequest request, void Function(int, int) _) {
    requests.add(request);
    return _AppendJob(runDayAppend(request));
  }
}

final class _Pickers implements RecordingPickers {
  List<String> recordings = const [];

  @override
  Future<List<String>> pickRecordings() async => recordings;

  @override
  Future<String?> pickFolder() async => null;
}

void main() {
  late Directory directory;
  late String vbo, rcz, other;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('import_review');
    (vbo, rcz) = writeFusionPair(directory.path);
    other = p.join(directory.path, 'other.vbo');
    File(other).writeAsStringSync(circuitVbo([30, 28, 31]));
  });
  tearDown(() => deleteTemporaryDirectory(directory));

  /// The run ids of the plan's recordings, by file name.
  Map<String, String> ids(TelemetryImportPlan plan) => {
    for (final run in plan.runs) p.basename(run.sourcePath): run.id,
  };

  group('an import as reviewed', () {
    test('the RCZ is the session, the VBO kept with it, a file skipped', () {
      final request = (paths: [vbo, rcz, other], includeSubfolders: false);
      final preview = runImportPreview(request);
      final id = ids(preview.plan!);
      final outcome = runDayImport(
        request,
        choices: {
          id['drive.rcz']!: id['drive.rcz']!,
          id['drive.vbo']!: id['drive.rcz']!,
          id['other.vbo']!: skipRecording,
        },
      );
      expect(outcome.reviewChanged, isFalse);
      expect(outcome.runs.map((named) => named.run.id), [id['drive.rcz']!]);
      expect(outcome.runs.single.name, 'Session 1');
      expect(outcome.alternatives.keys, [id['drive.rcz']!]);
      expect(outcome.alternatives[id['drive.rcz']!]!.id, id['drive.vbo']!);
      // Without review the VBO leads, with the RCZ as its alternative.
      final automatic = runDayImport(request);
      expect(automatic.runs.map((named) => named.run.id), [
        id['drive.vbo']!,
        id['other.vbo']!,
      ]);
      expect(automatic.alternatives[id['drive.vbo']!]!.id, id['drive.rcz']!);
    });

    test('nothing is imported when the files are not the ones reviewed', () {
      final reviewed = runImportPreview((
        paths: [vbo, rcz],
        includeSubfolders: false,
      ));
      final outcome = runDayImport((
        paths: [vbo, rcz, other],
        includeSubfolders: false,
      ), choices: automaticImportChoices(reviewed.plan!));
      expect(outcome.reviewChanged, isTrue);
      expect(outcome.runs, isEmpty);
      expect(outcome.analysis, isNull);
    });

    test(
      'the controller waits for the review and imports as confirmed',
      () async {
        final importer = _Importer();
        final preparer = _Preparer();
        final controller = DayImportController(
          importer: importer,
          preparer: preparer,
        );
        addTearDown(controller.dispose);
        expect(controller.review([vbo, rcz], includeSubfolders: false), isTrue);
        await pumpEventQueue();
        final review = controller.state as DayImportReviewing;
        expect(importer.choices, isEmpty, reason: 'nothing imported yet');
        // A second import waits until the review ends.
        expect(controller.start([other], includeSubfolders: false), isFalse);
        final id = review.plan.runs.map((run) => run.id).toList();
        expect(controller.confirm({id[0]: skipRecording}), isFalse);
        expect(controller.confirm({for (final run in id) run: run}), isTrue);
        await pumpEventQueue();
        final finished = controller.state as DayImportFinished;
        expect(finished.runs, hasLength(2));
        expect(finished.alternatives, isEmpty);

        expect(controller.review([other], includeSubfolders: false), isTrue);
        await pumpEventQueue();
        expect(controller.isReviewing, isTrue);
        controller.cancel();
        expect(controller.state, isA<DayImportCancelled>());
        expect(importer.choices, hasLength(1));
      },
    );
  });

  group('an addition as reviewed', () {
    late _Appender appender;
    late DayResultsController day;
    setUp(() {
      final first = runDayImport((paths: [vbo], includeSubfolders: false));
      appender = _Appender();
      day = DayResultsController(
        runs: first.runs,
        analysis: first.analysis!,
        appender: appender,
        preparer: _Preparer(),
      );
    });
    tearDown(() => day.dispose());

    test('offers what adding without review would do', () async {
      final review = (await day.reviewAddition([rcz, other, vbo]))!;
      final id = ids(review.plan!);
      final session = day.runs.single;
      // The RCZ joins the day's VBO session; the VBO is in the day already.
      expect(review.automatic, {
        id['drive.rcz']!: session.run.id,
        id['other.vbo']!: id['other.vbo']!,
        id['drive.vbo']!: skipRecording,
      });
      expect(review.alreadyInDay, contains(id['drive.vbo']!));
      expect(review.sessions, [(runId: session.run.id, name: 'Session 1')]);
      expect(review.automaticNewDay[id['drive.rcz']!], id['drive.vbo']!);

      final addition = await day.addRecordings(
        [rcz, other, vbo],
        review: review,
        choices: review.automatic,
      );
      expect(addition.reviewChanged, isFalse);
      expect(addition.added, ['Session 2']);
      expect(addition.combined, ['Session 1']);
      expect(appender.requests.single.choices, review.automatic);
    });

    test('adds only what the user chose', () async {
      final review = (await day.reviewAddition([rcz, other]))!;
      final id = ids(review.plan!);
      final addition = await day.addRecordings(
        [rcz, other],
        review: review,
        choices: {
          id['drive.rcz']!: skipRecording,
          id['other.vbo']!: id['other.vbo']!,
        },
      );
      expect(addition.added, ['Session 2']);
      expect(addition.combined, isEmpty);
      expect(day.runs.map((named) => named.run.id), [
        day.runs.first.run.id,
        id['other.vbo']!,
      ]);
    });

    test(
      'never gives a session that has another recording a new one',
      () async {
        // The RCZ joins Session 1 without review; it then has two recordings.
        expect((await day.addRecordings([rcz])).combined, ['Session 1']);
        final sessionId = day.runs.single.run.id;
        final (vbo2, rcz2) = writeFusionPair(
          (Directory(p.join(directory.path, 'again'))..createSync()).path,
          name: 'again',
        );
        final review = (await day.reviewAddition([rcz2]))!;
        final id = ids(review.plan!);
        expect(review.alreadyGrouped, {sessionId});
        // Not offered as "Same run as Session 1", and refused if asked for.
        expect(review.automatic[id['again.rcz']!], isNot(sessionId));
        final addition = await day.addRecordings(
          [rcz2],
          review: review,
          choices: {id['again.rcz']!: sessionId},
        );
        expect(addition.reviewChanged, isTrue);
        expect(day.fusion(sessionId)!.alternative!.sourcePath, rcz);
        expect(File(vbo2).existsSync(), isTrue);
      },
    );

    test(
      'a session whose saved RCZ is missing keeps it: no new one is offered',
      () async {
        expect((await day.addRecordings([rcz])).combined, ['Session 1']);
        await day.fusionsSettled;
        final path = p.join(directory.path, 'day.fetproject');
        await day.save(path);
        File(rcz).deleteSync();
        final opened = DayResultsController.opened(
          openDay(path),
          appender: _Appender(),
          preparer: _Preparer(),
        );
        addTearDown(opened.dispose);
        final sessionId = opened.runs.single.run.id;
        final (_, again) = writeFusionPair(
          (Directory(p.join(directory.path, 'same'))..createSync()).path,
        );
        final review = (await opened.reviewAddition([again]))!;
        expect(review.alreadyGrouped, {sessionId});
        expect(review.automatic.values, isNot(contains(sessionId)));
      },
    );

    test(
      'adds nothing when a session got another recording during the review',
      () async {
        final review = (await day.reviewAddition([other]))!;
        final id = ids(review.plan!);
        // Same number of sessions, but Session 1 now has its RCZ.
        expect((await day.addRecordings([rcz])).combined, ['Session 1']);
        final addition = await day.addRecordings(
          [other],
          review: review,
          choices: {id['other.vbo']!: id['other.vbo']!},
        );
        expect(addition.reviewChanged, isTrue);
        expect(day.runs, hasLength(1));
      },
    );

    test('adds nothing when the day changed during the review', () async {
      final review = (await day.reviewAddition([rcz]))!;
      final id = ids(review.plan!);
      expect((await day.addRecordings([other])).added, ['Session 2']);
      final addition = await day.addRecordings(
        [rcz],
        review: review,
        choices: {id['drive.rcz']!: id['drive.rcz']!},
      );
      expect(addition.reviewChanged, isTrue);
      expect(day.runs, hasLength(2));
    });
  });

  group('the review page', () {
    late _Importer importer;
    late _Pickers pickers;
    late DayImportController controller;
    setUp(() {
      importer = _Importer();
      pickers = _Pickers();
      controller = DayImportController(
        importer: importer,
        preparer: _Preparer(),
      );
    });
    tearDown(() => controller.dispose());

    Future<void> show(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayImportPage(
            controller: controller,
            pickers: pickers,
            picksFolders: false,
          ),
        ),
      );
    }

    Future<void> choose(WidgetTester tester, int file, String choice) async {
      await tester.tap(find.byKey(ValueKey('reviewChoice:$file')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
    }

    testWidgets('lists every file and imports as chosen', (tester) async {
      pickers.recordings = [rcz, vbo, other];
      await show(tester);
      // Automatic by default: no review unless asked for.
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('reviewBeforeImport')))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('reviewBeforeImport')));
      await tester.pump();
      await tester.tap(find.text('Choose recordings…'));
      await tester.pumpAndSettle();

      expect(find.text('Review the import'), findsOneWidget);
      for (final file in [rcz, vbo, other]) {
        expect(find.text(p.basename(file)), findsOneWidget);
      }
      // The RCZ is the same run as the VBO, as without review.
      expect(find.text('Same run as drive.vbo'), findsOneWidget);
      expect(find.text('2 new sessions'), findsOneWidget);
      expect(
        find.text('Possibly the same run as drive.vbo: the GPS traces agree.'),
        findsOneWidget,
      );

      // The VBO joins the RCZ instead; the other drive is skipped.
      await choose(tester, 0, 'Import as a new session');
      await choose(tester, 1, 'Same run as drive.rcz');
      await choose(tester, 2, 'Skip this file');
      expect(find.text('1 new session'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirmReview')));
      await tester.pumpAndSettle();

      final finished = controller.state as DayImportFinished;
      expect(finished.runs.single.run.format, RecordingFormat.rcz);
      expect(finished.alternatives.values.single.format, RecordingFormat.vbo);
      expect(find.text('1 session imported'), findsOneWidget);
      // The next import needs no approval again.
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('reviewBeforeImport')))
            .value,
        isFalse,
      );
    });

    testWidgets('a single file can be reviewed, and closing imports nothing', (
      tester,
    ) async {
      pickers.recordings = [other];
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('reviewBeforeImport')));
      await tester.tap(find.text('Choose recordings…'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reviewFile:0')), findsOneWidget);
      expect(find.byKey(const ValueKey('reviewFile:1')), findsNothing);
      expect(find.text('Import'), findsOneWidget);

      await choose(tester, 0, 'Skip this file');
      expect(find.text('Choose at least one file to import.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirmReview')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(
        find.text('Import cancelled. Nothing was imported.'),
        findsOneWidget,
      );
      expect(importer.choices, isEmpty);

      // Without the box, the same file is imported at once.
      await tester.tap(find.text('Choose recordings…'));
      await tester.pumpAndSettle();
      expect(find.text('Review the import'), findsNothing);
      expect(find.text('1 session imported'), findsOneWidget);
      expect(importer.choices, [null]);
    });
  });

  group('"Add and review recordings…" on a day', () {
    Future<(DayResultsController, _Appender)> showDay(
      WidgetTester tester,
      _Pickers pickers, {
      bool Function(List<String>, ImportChoices)? startNewDay,
    }) async {
      final first = runDayImport((paths: [vbo], includeSubfolders: false));
      final appender = _Appender();
      final day = DayResultsController(
        runs: first.runs,
        analysis: first.analysis!,
        appender: appender,
        preparer: _Preparer(),
      );
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const TelemetryApp(home: Scaffold(body: Text('Import a day'))),
      );
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => DayResultsPage.controller(
                  controller: day,
                  pickers: pickers,
                  startNewDay: startNewDay,
                ),
              ),
            ),
      );
      await tester.pumpAndSettle();
      return (day, appender);
    }

    Future<void> openReview(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('moreMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add and review recordings…'));
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
    }

    testWidgets('adds the recordings to the day as reviewed', (tester) async {
      final pickers = _Pickers()..recordings = [rcz, other];
      final (day, appender) = await showDay(tester, pickers);
      await openReview(tester);
      expect(find.text('Review the import'), findsOneWidget);
      // Only "Add to this day": no new day was offered by the caller.
      expect(find.byKey(const ValueKey('reviewDestination')), findsNothing);
      expect(find.text('Same run as Session 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirmReview')));
      await tester.pumpAndSettle();
      expect(appender.requests.single.choices, isNotNull);
      expect(day.runs.map((named) => named.name), ['Session 1', 'Session 2']);
    });

    testWidgets('can start a new day instead, with no unsaved changes', (
      tester,
    ) async {
      final pickers = _Pickers()..recordings = [rcz, other];
      final started = <(List<String>, ImportChoices)>[];
      // The first start is refused, as while another import runs.
      var accept = false;
      final (day, appender) = await showDay(
        tester,
        pickers,
        startNewDay: (paths, choices) {
          started.add((paths, choices));
          return accept;
        },
      );
      // An unsaved day is not left for a new one.
      expect(day.dirty, isTrue);
      await openReview(tester);
      expect(
        find.text('Save this day before starting a new one.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Start a new day'));
      await tester.pumpAndSettle();
      expect(find.text('Add to the day'), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => day.save(p.join(directory.path, 'day.fetproject')),
      );
      await tester.pumpAndSettle();
      expect(day.dirty, isFalse);

      await openReview(tester);
      expect(
        find.text('Save this day before starting a new one.'),
        findsNothing,
      );
      await tester.tap(find.text('Start a new day'));
      await tester.pumpAndSettle();
      // As without review: the RCZ is a session of its own in a new day.
      expect(find.text('Same run as Session 1'), findsNothing);
      expect(find.text('2 new sessions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirmReview')));
      await tester.pumpAndSettle();
      // Refused: the day stays open and says why; nothing was added.
      expect(started, hasLength(1));
      expect(
        find.text('Finish the current import first. Nothing was imported.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('moreMenu')), findsOneWidget);
      expect(appender.requests, isEmpty);
      started.clear();
      accept = true;

      await openReview(tester);
      await tester.tap(find.text('Start a new day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmReview')));
      await tester.pumpAndSettle();
      expect(started.single.$1, [rcz, other]);
      expect(started.single.$2.values.toSet(), started.single.$2.keys.toSet());
      expect(appender.requests, isEmpty);
      expect(find.text('Import a day'), findsOneWidget, reason: 'day closed');
    });
  });
}
