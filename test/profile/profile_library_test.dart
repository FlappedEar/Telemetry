import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/library_page.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../day/day_results_page_test.dart' show FakeDocuments, circuitVbo;
import '../day/recovery_test.dart' show FileRecoveryStore;
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('profile'));
  tearDown(() => deleteTemporaryDirectory(directory));

  String profileFolder() => p.join(directory.path, 'Profile');

  ProfileLibrary library() => ProfileLibrary(
    store: FolderProfileStore(profileFolder()),
    defaultCarName: 'My car',
    defaultTrackName: (number) => 'Track $number',
    background: _inPlace,
  );

  DayImportOutcome importDay(Map<String, List<double>> files) {
    final paths = <String>[];
    files.forEach((name, speeds) {
      final path = p.join(directory.path, name);
      File(path).writeAsStringSync(circuitVbo(speeds));
      paths.add(path);
    });
    return runDayImport((paths: paths, includeSubfolders: false));
  }

  // Writes as the app does, without the isolate and journal of the real
  // writer, so a widget test's fake clock can run it.
  Future<void> writer(String path, Map<String, Object?> document) async {
    // No folder is made here: the library makes the day's folder.
    File(path).writeAsStringSync(jsonEncode(document));
  }

  group('ProfileLibrary', () {
    test(
      'records a day saved in the profile and writes a profile that reads back',
      () async {
        final outcome = importDay({
          'a.vbo': [30, 28, 31],
          'b.vbo': [29, 32],
        });
        final shelf = library();
        final path = (await shelf.dayPath('e1'))!;
        expect(path, p.join(profileFolder(), 'Days', 'e1.fetproject'));
        await shelf.recordDay(
          eventId: 'e1',
          path: path,
          name: 'Day',
          analysis: outcome.analysis!,
        );
        await shelf.flush();
        final read = decodeDriverProfile(
          File(p.join(profileFolder(), profileFileName)).readAsStringSync(),
        );
        expect(read.days.single.file, 'Days/e1.fetproject');
        expect(read.cars.single.name, 'My car');
        expect(read.tracks.single.name, 'Track 1');
        expect(
          read.days.single.bestLapSeconds,
          outcome.analysis!.ranking!.bestOfDay!.durationSeconds,
        );
      },
    );

    test('ignores a day saved elsewhere', () async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final shelf = library();
      await shelf.recordDay(
        eventId: 'e1',
        path: p.join(directory.path, 'Elsewhere.fetproject'),
        name: 'Day',
        analysis: outcome.analysis!,
      );
      expect(shelf.profile!.days, isEmpty);
    });

    test('keeps an unreadable profile beside and starts a new one', () async {
      Directory(profileFolder()).createSync();
      final file = File(p.join(profileFolder(), profileFileName))
        ..writeAsStringSync('{broken');
      final shelf = library();
      await shelf.load();
      expect(shelf.available, isTrue);
      expect(shelf.profile!.days, isEmpty);
      expect(file.existsSync(), isFalse);
      final kept = Directory(profileFolder())
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                p.basename(f.path).startsWith('$profileFileName.unreadable-'),
          );
      expect(kept.single.readAsStringSync(), '{broken');
    });

    test(
      'keeps a newer version\'s profile as it is, without a library',
      () async {
        Directory(profileFolder()).createSync();
        const newer = '{"format":"flappedear-driver-profile","version":99}';
        final file = File(p.join(profileFolder(), profileFileName))
          ..writeAsStringSync(newer);
        final shelf = library();
        await shelf.load();
        expect(shelf.available, isFalse);
        expect(await shelf.dayPath('e1'), isNull);
        expect(file.readAsStringSync(), newer);
        expect(Directory(profileFolder()).listSync(), hasLength(1));
      },
    );

    test('lists the days in its folder that the profile does not', () async {
      final days = Directory(p.join(profileFolder(), 'Days'))
        ..createSync(recursive: true);
      File(p.join(days.path, 'old.fetproject')).writeAsStringSync(
        jsonEncode({
          'event': {'id': 'old', 'name': 'Old day'},
        }),
      );
      File(p.join(days.path, 'broken.fetproject')).writeAsStringSync('{');
      final shelf = library();
      await shelf.load();
      await shelf.flush();
      final read = decodeDriverProfile(
        File(p.join(profileFolder(), profileFileName)).readAsStringSync(),
      );
      expect(read.days.single.eventId, 'old');
      expect(read.days.single.name, 'Old day');
      expect(read.days.single.file, 'Days/old.fetproject');
    });

    test('lists unlisted days off the UI thread too', () async {
      final days = Directory(p.join(profileFolder(), 'Days'))
        ..createSync(recursive: true);
      File(p.join(days.path, 'old.fetproject')).writeAsStringSync(
        jsonEncode({
          'event': {'id': 'old', 'name': 'Old day'},
        }),
      );
      // The real isolate: its jobs must hold nothing that cannot be sent.
      final shelf = ProfileLibrary(
        store: FolderProfileStore(profileFolder()),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
      );
      await shelf.load();
      await shelf.flush();
      expect(shelf.profile!.days.single.eventId, 'old');
      final read = decodeDriverProfile(
        File(p.join(profileFolder(), profileFileName)).readAsStringSync(),
      );
      expect(read.days.single.eventId, 'old');
    });

    test('without a folder there is no library', () async {
      final shelf = ProfileLibrary(
        store: const _NoFolder(),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
      );
      await shelf.load();
      expect(shelf.available, isFalse);
      expect(await shelf.dayPath('e1'), isNull);
    });
  });

  group('day page with a library', () {
    testWidgets(
      'saves a new day in the library by itself, and exports a copy',
      (tester) async {
        final outcome = importDay({
          'a.vbo': [30, 28, 31],
          'b.vbo': [29, 32],
        });
        final shelf = library();
        await shelf.load();
        final controller = DayResultsController(
          runs: outcome.runs,
          analysis: outcome.analysis!,
          writer: writer,
        );
        final export = p.join(directory.path, 'Export.fetproject');
        final documents = FakeDocuments(location: export);
        await tester.binding.setSurfaceSize(const Size(1200, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          TelemetryApp(
            home: DayResultsPage.controller(
              controller: controller,
              documents: documents,
              library: shelf,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final saved = p.join(
          profileFolder(),
          'Days',
          '${controller.eventId}.fetproject',
        );
        expect(controller.documentPath, saved);
        expect(File(saved).existsSync(), isTrue);
        expect(documents.names, isEmpty, reason: 'no save dialog');
        expect(find.text('Saved in your library.'), findsOneWidget);
        expect(shelf.profile!.days.single.eventId, controller.eventId);
        expect(shelf.profile!.days.single.sessions, hasLength(2));
        // What each session measured, from its recording, and once the
        // theoretical best is worked out, the day's and its corners.
        expect(
          controller.theoreticalBest?.state,
          DayTheoreticalBestState.ready,
        );
        final day = shelf.profile!.days.single;
        for (final session in day.sessions) {
          expect(session.stats?.distanceMeters, greaterThan(0));
          expect(session.stats?.rankedLaps, greaterThan(0));
        }
        expect(
          day.theoreticalBestSeconds,
          controller.theoreticalBest!.computed!.best.totalSeconds,
        );
        final corners = shelf.profile!.tracks.single.corners;
        expect(corners, hasLength(controller.theoreticalBest!.corners.length));
        expect(corners, isNotEmpty);
        expect(day.sessions.expand((s) => s.stats!.corners), isNotEmpty);
        for (final session in day.sessions) {
          for (final corner in session.stats!.corners) {
            expect(corners.map((c) => c.id), contains(corner.cornerId));
          }
        }

        await tester.tap(find.byKey(const ValueKey('moreMenu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export for Overlays…'));
        await tester.pumpAndSettle();
        expect(documents.names, [controller.name]);
        expect(File(export).existsSync(), isTrue);
        expect(find.text('Exported as Export.fetproject.'), findsOneWidget);
        expect(
          controller.documentPath,
          saved,
          reason: 'the day stays in the library',
        );
        await shelf.flush();
      },
      // Export is offered on desktop, where Overlays runs.
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('never exports over a day in the library', (tester) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final shelf = library();
      await shelf.load();
      final other = p.join(profileFolder(), 'Days', 'other.fetproject');
      File(other)
        ..createSync(recursive: true)
        ..writeAsStringSync('kept');
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        writer: writer,
      );
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.controller(
            controller: controller,
            documents: FakeDocuments(location: other),
            library: shelf,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('moreMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export for Overlays…'));
      await tester.pumpAndSettle();
      expect(File(other).readAsStringSync(), 'kept');
      expect(
        find.text('Not exported: choose a place outside the library.'),
        findsOneWidget,
      );
      await shelf.flush();
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('going back during the first save waits for it and records '
        'the day', (tester) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final shelf = library();
      await shelf.load();
      final gate = Completer<void>();
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        writer: (path, document) async {
          await gate.future;
          await writer(path, document);
        },
      );
      await tester.pumpWidget(
        TelemetryApp(home: const Scaffold(body: Text('home'))),
      );
      unawaited(
        Navigator.of(tester.element(find.text('home'))).push(
          MaterialPageRoute<void>(
            builder: (_) => DayResultsPage.controller(
              controller: controller,
              documents: FakeDocuments(),
              library: shelf,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.saving, isTrue);
      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('home'), findsNothing, reason: 'waits for the save');
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      await shelf.flush();
      expect(shelf.profile!.days.single.eventId, controller.eventId);
      expect(
        File(
          p.join(profileFolder(), 'Days', '${controller.eventId}.fetproject'),
        ).existsSync(),
        isTrue,
      );
    });

    testWidgets('a save that fails still lets the day be left', (tester) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      // The days folder cannot be made: a file has its name.
      File(p.join(profileFolder(), 'Days'))
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      final shelf = library();
      await shelf.load();
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        writer: writer,
      );
      await tester.pumpWidget(
        TelemetryApp(home: const Scaffold(body: Text('home'))),
      );
      unawaited(
        Navigator.of(tester.element(find.text('home'))).push(
          MaterialPageRoute<void>(
            builder: (_) => DayResultsPage.controller(
              controller: controller,
              documents: FakeDocuments(),
              library: shelf,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.documentPath, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a page opened over the day while it saves to leave stays', (
      tester,
    ) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final shelf = library();
      await shelf.load();
      final gate = Completer<void>();
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        writer: (path, document) async {
          await gate.future;
          await writer(path, document);
        },
      );
      await tester.pumpWidget(
        TelemetryApp(home: const Scaffold(body: Text('home'))),
      );
      final navigator = Navigator.of(tester.element(find.text('home')));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => DayResultsPage.controller(
              controller: controller,
              documents: FakeDocuments(),
              library: shelf,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.binding.handlePopRoute();
      await tester.pump();
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('on top')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('on top'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(DayResultsPage), findsOneWidget);
      await shelf.flush();
    });

    testWidgets('saves a change by itself once the day is left alone', (
      tester,
    ) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
        'b.vbo': [29, 32],
      });
      final shelf = library();
      await shelf.load();
      final saved = <Map<String, Object?>>[];
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        writer: (path, document) async {
          saved.add(document);
          await writer(path, document);
        },
      );
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.controller(
            controller: controller,
            documents: FakeDocuments(),
            library: shelf,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      // The first save says so; its message goes after a while.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final best = outcome.analysis!.ranking!.bestOfDay!;
      expect(controller.exclude(best, 'Traffic'), isTrue);
      await tester.pump();
      expect(controller.dirty, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(saved, hasLength(1), reason: 'not while changes may follow');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(saved, hasLength(2));
      expect(controller.dirty, isFalse);
      expect(find.text('Saved in your library.'), findsNothing);
      await shelf.flush();
    });

    testWidgets('without a library a new day waits for Save, as before', (
      tester,
    ) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        writer: writer,
      );
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.controller(
            controller: controller,
            documents: FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.documentPath, isNull);
    });
  });

  group('LibraryPage', () {
    testWidgets('lists days by car and track, renames and opens them', (
      tester,
    ) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
        'b.vbo': [29, 32],
      });
      final shelf = library();
      await (() async {
        final path = (await shelf.dayPath('e1'))!;
        await shelf.recordDay(
          eventId: 'e1',
          path: path,
          name: 'Test day',
          analysis: outcome.analysis!,
        );
      })();
      final opened = <String>[];
      await tester.pumpWidget(
        TelemetryApp(
          home: LibraryPage(library: shelf, open: opened.add),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My car'), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.textContaining('Test day'), findsOneWidget);
      expect(find.textContaining('2 sessions'), findsOneWidget);

      await tester.tap(find.byTooltip('Rename track'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('libraryRenameField')),
        'Jastrząb',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Jastrząb'), findsOneWidget);

      await tester.tap(find.byTooltip('Change car'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('libraryNewCar')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('libraryRenameField')),
        'Civic',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Civic'), findsOneWidget);
      expect(
        find.text('My car'),
        findsNothing,
        reason: 'a car without days is not listed',
      );

      await tester.tap(find.byKey(const ValueKey('libraryDay-e1')));
      expect(opened, [p.join(profileFolder(), 'Days', 'e1.fetproject')]);
      await shelf.flush();
    });

    testWidgets('says the library cannot be used once it is read', (
      tester,
    ) async {
      final shelf = ProfileLibrary(
        store: const _NoFolder(),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: _inPlace,
      );
      // Not read before the page opens, as when it is opened first.
      await tester.pumpWidget(
        TelemetryApp(
          home: LibraryPage(library: shelf, open: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('cannot be used now'), findsOneWidget);
    });

    testWidgets('opens a day with its changes kept for recovery', (
      tester,
    ) async {
      final store = FileRecoveryStore(
        p.join(directory.path, 'support', 'day-recovery.json'),
      );
      final shelf = library();
      late String saved;
      late Future<void> Function() recorded;
      await tester.runAsync(() async {
        final outcome = importDay({
          'a.vbo': [30, 28, 31],
          'b.vbo': [29, 32],
        });
        final controller = DayResultsController(
          runs: outcome.runs,
          analysis: outcome.analysis!,
          name: 'Test day',
          recovery: store,
          writer: writer,
        );
        saved = (await shelf.dayPath(controller.eventId))!;
        await controller.save(saved);
        recorded = () => shelf.recordDay(
          eventId: controller.eventId,
          path: saved,
          name: controller.name,
          analysis: controller.analysis,
        );
        // A change the app ended before saving: kept for recovery only.
        expect(
          controller.exclude(outcome.analysis!.ranking!.bestOfDay!, 'Traffic'),
          isTrue,
        );
        await controller.flushRecovery();
        controller.dispose();
      });
      // Recorded on the test's clock, where the library's writes run.
      await recorded();
      await shelf.flush();
      Future<void> settle() async {
        for (var i = 0; i < 10; ++i) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
        }
      }

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayImportPage(
            documents: FakeDocuments(),
            recovery: store,
            library: shelf,
          ),
        ),
      );
      await settle();
      await tester.tap(find.byKey(const ValueKey('place-library')));
      await settle();
      await tester.tap(find.textContaining('Test day'));
      await tester.runAsync(() async {
        for (var i = 0; i < 100; ++i) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (find.byType(DayResultsPage).evaluate().isNotEmpty) break;
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(DayResultsPage), findsOneWidget);
      // The restored change has the day's mark of unsaved changes.
      expect(find.textContaining('Test day •'), findsOneWidget);
    });

    testWidgets('says where days will go while it is empty', (tester) async {
      final shelf = library();
      await shelf.load();
      await tester.pumpWidget(
        TelemetryApp(
          home: LibraryPage(library: shelf, open: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('libraryEmpty')), findsOneWidget);
    });
  });
}

Future<R> _inPlace<R>(FutureOr<R> Function() computation) async =>
    computation();

final class _NoFolder implements ProfileStore {
  const _NoFolder();

  @override
  Future<String?> folder() async => null;
}
