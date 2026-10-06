import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/library_page.dart';
import 'package:telemetry/profile/profile_bundle_pickers.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry/profile/profile_page.dart';
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
      'measures a day in another isolate; a newer recording of it wins',
      () async {
        final outcome = importDay({
          'a.vbo': [30, 28, 31, 29],
          'b.vbo': [29, 32, 30],
        });
        final analysis = outcome.analysis!;
        final recordings = {
          for (final named in outcome.runs) named.run.id: named.run.telemetry,
        };
        final best = dayTheoreticalBest(analysis, outingRuns(outcome.runs));
        expect(best.state, DayTheoreticalBestState.ready);
        // The first measuring finishes after the second.
        final gate = Completer<void>();
        final shelf = ProfileLibrary(
          store: FolderProfileStore(profileFolder()),
          defaultCarName: 'My car',
          defaultTrackName: (number) => 'Track $number',
          background: <R>(FutureOr<R> Function() job) async {
            final result = await Isolate.run(job);
            if (result is ProfileDayInput && result.name == 'Older') {
              await gate.future;
            }
            return result;
          },
        );
        final path = (await shelf.dayPath('e1'))!;
        await shelf.load();
        final older = shelf.recordDay(
          eventId: 'e1',
          path: path,
          name: 'Older',
          analysis: analysis,
          recordings: recordings,
          theoreticalBest: best,
        );
        final newer = shelf.recordDay(
          eventId: 'e1',
          path: path,
          name: 'Newer',
          analysis: analysis,
          recordings: recordings,
          theoreticalBest: best,
        );
        await newer;
        gate.complete();
        await older;
        await shelf.flush();
        final day = shelf.profile!.day('e1')!;
        expect(day.name, 'Newer');
        expect(day.sessions.first.stats!.corners, isNotEmpty);
        expect(day.sessions.first.stats!.distanceMeters, greaterThan(0));
        // A flush waits for a day still being measured, as quitting does.
        final other = (await shelf.dayPath('e2'))!;
        unawaited(
          shelf.recordDay(
            eventId: 'e2',
            path: other,
            name: 'Other',
            analysis: analysis,
            recordings: recordings,
            theoreticalBest: best,
          ),
        );
        await shelf.flush();
        expect(
          decodeDriverProfile(
            File(p.join(profileFolder(), profileFileName)).readAsStringSync(),
          ).day('e2'),
          isNotNull,
        );
      },
    );

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

    group('weather', () {
      ProfileWeather weather(double temperature, String revision) =>
          ProfileWeather(temperatureC: temperature, sourceRevision: revision);

      test('given while the day is measured, the newer weather wins', () async {
        final outcome = importDay({
          'a.vbo': [30, 28, 31],
        });
        final run = outcome.runs.single.run;
        var gate = Completer<void>()..complete();
        final shelf = ProfileLibrary(
          store: FolderProfileStore(profileFolder()),
          defaultCarName: 'My car',
          defaultTrackName: (number) => 'Track $number',
          background: <R>(FutureOr<R> Function() job) async {
            final result = await job();
            if (result is ProfileDayInput) await gate.future;
            return result;
          },
        );
        final path = (await shelf.dayPath('e1'))!;
        await shelf.recordDay(
          eventId: 'e1',
          path: path,
          name: 'Day',
          analysis: outcome.analysis!,
        );
        gate = Completer<void>();
        final measuring = shelf.recordDay(
          eventId: 'e1',
          path: path,
          name: 'Day',
          analysis: outcome.analysis!,
          weather: {run.id: weather(15, run.contentSha256)},
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          shelf.recordWeather('e1', {run.id: weather(21, run.contentSha256)}),
          isTrue,
        );
        gate.complete();
        await measuring;
        await shelf.flush();
        expect(
          shelf.profile!.day('e1')!.sessions.single.weather!.temperatureC,
          21,
        );
      });

      test('given before the day is in the profile, or when measuring '
          'fails, it reaches the profile with the next record', () async {
        final outcome = importDay({
          'a.vbo': [30, 28, 31],
        });
        final run = outcome.runs.single.run;
        var fail = true;
        final shelf = ProfileLibrary(
          store: FolderProfileStore(profileFolder()),
          defaultCarName: 'My car',
          defaultTrackName: (number) => 'Track $number',
          background: <R>(FutureOr<R> Function() job) async {
            final result = await job();
            if (result is ProfileDayInput && fail) {
              throw StateError('not measured');
            }
            return result;
          },
        );
        final path = (await shelf.dayPath('e1'))!;
        await shelf.load();
        // Not in the profile yet: held, not lost.
        expect(
          shelf.recordWeather('e1', {run.id: weather(21, run.contentSha256)}),
          isFalse,
        );
        await shelf.recordDay(
          eventId: 'e1',
          path: path,
          name: 'Day',
          analysis: outcome.analysis!,
        );
        expect(shelf.profile!.day('e1'), isNull);
        fail = false;
        await shelf.recordDay(
          eventId: 'e1',
          path: path,
          name: 'Day',
          analysis: outcome.analysis!,
        );
        await shelf.flush();
        expect(
          shelf.profile!.day('e1')!.sessions.single.weather!.temperatureC,
          21,
        );
        // Weather of a recording since replaced is not applied.
        final other = ProfileLibrary(
          store: FolderProfileStore(p.join(directory.path, 'Other')),
          defaultCarName: 'My car',
          defaultTrackName: (number) => 'Track $number',
          background: _inPlace,
        );
        final otherPath = (await other.dayPath('e1'))!;
        await other.load();
        other.recordWeather('e1', {run.id: weather(21, 'f' * 64)});
        await other.recordDay(
          eventId: 'e1',
          path: otherPath,
          name: 'Day',
          analysis: outcome.analysis!,
        );
        expect(other.profile!.day('e1')!.sessions.single.weather, isNull);
      });
    });

    test('setups go to a listed day at once and are held when measuring '
        'fails', () async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final run = outcome.runs.single.run;
      var fail = true;
      final shelf = ProfileLibrary(
        store: FolderProfileStore(profileFolder()),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: <R>(FutureOr<R> Function() job) async {
          final result = await job();
          if (result is ProfileDayInput && fail) {
            throw StateError('not measured');
          }
          return result;
        },
      );
      final path = (await shelf.dayPath('e1'))!;
      await shelf.load();
      final setup = ProfileSetup.of({
        'version': runSetupVersion,
        'pressureUnit': 'bar',
        'coldPressure': {'fl': 2.1},
      });
      // Not in the profile yet, and the measure fails: held, not lost.
      await shelf.recordDay(
        eventId: 'e1',
        path: path,
        name: 'Day',
        analysis: outcome.analysis!,
        setups: {run.id: setup},
      );
      expect(shelf.profile!.day('e1'), isNull);
      expect(shelf.givenSetups('e1')![run.id]!.json, setup!.json);
      // Recorded without setups (a restored day): the held ones apply.
      fail = false;
      await shelf.recordDay(
        eventId: 'e1',
        path: path,
        name: 'Day',
        analysis: outcome.analysis!,
      );
      await shelf.flush();
      expect(shelf.profile!.day('e1')!.sessions.single.setup!.json, setup.json);
      // Listed now: a save's setups reach it even when its measure fails.
      fail = true;
      await shelf.recordDay(
        eventId: 'e1',
        path: path,
        name: 'Day',
        analysis: outcome.analysis!,
        setups: {run.id: null},
      );
      await shelf.flush();
      expect(shelf.profile!.day('e1')!.sessions.single.setup, isNull);
    });

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
            // Refused before any question about replacing it.
            documents: FakeDocuments(location: other, replacesUnasked: true),
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
      expect(find.byType(AlertDialog), findsNothing);
      expect(File(other).readAsStringSync(), 'kept');
      expect(
        find.text('Not exported: choose a place outside the library.'),
        findsOneWidget,
      );
      await shelf.flush();
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('asks before an export replaces a file the save dialog did '
        'not ask about', (tester) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final shelf = library();
      await shelf.load();
      final existing = p.join(directory.path, 'Export.fetproject');
      File(existing).writeAsStringSync('kept');
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        writer: writer,
      );
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.controller(
            controller: controller,
            documents: FakeDocuments(location: existing, replacesUnasked: true),
            library: shelf,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      Future<void> export() async {
        await tester.tap(find.byKey(const ValueKey('moreMenu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export for Overlays…'));
        await tester.pumpAndSettle();
      }

      await export();
      expect(find.text('Replace Export.fetproject?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(File(existing).readAsStringSync(), 'kept');
      expect(find.textContaining('Exported as'), findsNothing);

      await export();
      await tester.tap(find.byKey(const ValueKey('replaceDayFile')));
      await tester.pumpAndSettle();
      expect(File(existing).readAsStringSync(), isNot('kept'));
      expect(find.text('Exported as Export.fetproject.'), findsOneWidget);
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

    testWidgets('a session setup reaches the library when the day is saved', (
      tester,
    ) async {
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
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final runId = controller.runs.first.run.id;
      ProfileSession session() => shelf.profile!.days.single.sessions
          .singleWhere((session) => session.runId == runId);
      expect(session().setup, isNull);
      expect(controller.runSetupWaitsForSave(runId), isFalse);

      final setup = RunSetup(
        pressureUnit: PressureUnit.bar,
        cold: const WheelPressures(fl: 2.1, fr: 2.1),
        tyre: 'Pirelli SC2',
      );
      expect(
        controller.updateRunMetadata(
          runId,
          RunMetadata(name: controller.runs.first.name, setup: setup),
        ),
        isNull,
      );
      await tester.pump();
      // Entered, not saved: the library still has none, and the page knows.
      expect(controller.runSetupWaitsForSave(runId), isTrue);
      expect(controller.savedRunSetup(runId), isNull);
      expect(session().setup, isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await shelf.flush();
      expect(controller.dirty, isFalse);
      expect(controller.runSetupWaitsForSave(runId), isFalse);
      expect(session().setup!.setup, setup);
      expect(session().setup!.json, controller.savedRunSetup(runId));
      // Cleared and saved: cleared in the library too.
      expect(
        controller.updateRunMetadata(
          runId,
          RunMetadata(name: controller.runs.first.name),
        ),
        isNull,
      );
      await tester.pump();
      expect(
        controller.runSetupWaitsForSave(runId),
        isFalse,
        reason: 'nothing entered waits for the save',
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await shelf.flush();
      expect(controller.dirty, isFalse);
      expect(session().setup, isNull);
    });

    testWidgets('a restored day keeps the library\'s setups until saved', (
      tester,
    ) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
      });
      final shelf = library();
      late String path;
      late String eventId;
      late String name;
      await tester.runAsync(() async {
        final first = DayResultsController(
          runs: outcome.runs,
          analysis: outcome.analysis!,
          writer: writer,
        );
        eventId = first.eventId;
        name = first.name;
        path = (await shelf.dayPath(eventId))!;
        await first.save(path);
        first.dispose();
      });
      final runId = outcome.runs.single.run.id;
      const kept = {
        'version': runSetupVersion,
        'pressureUnit': 'psi',
        'coldPressure': {'fl': 30},
      };
      await shelf.recordDay(
        eventId: eventId,
        path: path,
        name: name,
        analysis: outcome.analysis!,
        setups: {runId: ProfileSetup.of(kept)},
      );
      await shelf.flush();
      // The recovery snapshot holds a setup the file does not.
      final snapshot =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      final run =
          ((snapshot['event']! as Map<String, Object?>)['runs']! as List).single
              as Map<String, Object?>;
      run[runSetupKey] = {
        'version': runSetupVersion,
        'pressureUnit': 'bar',
        'coldPressure': {'fl': 2.1},
      };
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
        eventId: eventId,
        name: name,
        openedFrom: path,
        openedDocument: snapshot,
        recovered: true,
        writer: writer,
      );
      expect(controller.setupsSaved, isFalse);
      expect(controller.runSetupWaitsForSave(runId), isTrue);
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.controller(
            controller: controller,
            documents: FakeDocuments(),
            library: shelf,
          ),
        ),
      );
      await tester.pump();
      await shelf.flush();
      // Recorded on opening, without the snapshot's setup.
      ProfileSetup? setup() => shelf.profile!.days.single.sessions.single.setup;
      expect(setup()!.json, kept);
      // Saved by itself: the restored setup is the day's now.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await shelf.flush();
      expect(controller.dirty, isFalse);
      expect(controller.setupsSaved, isTrue);
      expect(controller.runSetupWaitsForSave(runId), isFalse);
      expect(setup()!.setup.pressureUnit, PressureUnit.bar);
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

      // Settles until [done] holds, on the real clock: leaving the day
      // saves it with real file writes first, which take as long as the
      // machine takes. A fixed wait failed once on a slow Windows runner.
      Future<void> settleUntil(bool Function() done) async {
        final clock = Stopwatch()..start();
        while (clock.elapsed < const Duration(seconds: 15)) {
          await tester.pumpAndSettle();
          if (done()) return settle();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        fail('The app did not get there in 15 seconds.');
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
      await settleUntil(
        () => find.byType(DayResultsPage).evaluate().isNotEmpty,
      );
      expect(find.byType(DayResultsPage), findsOneWidget);
      // The restored change has the day's mark of unsaved changes.
      expect(find.textContaining('Test day •'), findsOneWidget);

      // Coach shows the skills across days under what to try next.
      await tester.tap(find.byKey(const ValueKey('place-coach')));
      await settle();
      expect(find.byKey(const ValueKey('skillLevels')), findsOneWidget);

      // Profile from the day: the day leaves first, then the library it
      // was opened from closes and the profile shows, alone.
      int? selected() => tester
          .widget<NavigationRail>(find.byKey(const ValueKey('appPlaces')))
          .selectedIndex;
      await tester.tap(find.byKey(const ValueKey('place-profile')));
      await settleUntil(
        () =>
            find.byType(DayResultsPage).evaluate().isEmpty &&
            find.byType(ProfilePage).evaluate().isNotEmpty,
      );
      expect(find.byType(DayResultsPage), findsNothing);
      expect(find.byType(LibraryPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(selected(), 4);
      // What it waited for: the day saved its restored change on leaving.
      expect(await tester.runAsync(store.load), isNull);
      expect(File(saved).readAsStringSync(), contains('Traffic'));
      // And back to the day kept, then to Library.
      await tester.tap(find.byKey(const ValueKey('place-day')));
      await settleUntil(
        () => find.byType(DayResultsPage).evaluate().isNotEmpty,
      );
      expect(find.byType(DayResultsPage), findsOneWidget);
      expect(find.byType(ProfilePage), findsNothing);
      await tester.tap(find.byKey(const ValueKey('place-library')));
      await settleUntil(
        () =>
            find.byType(DayResultsPage).evaluate().isEmpty &&
            find.byType(LibraryPage).evaluate().isNotEmpty,
      );
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(ProfilePage), findsNothing);
      expect(selected(), 1);
    });

    testWidgets('Profile is a place beside Library and Home', (tester) async {
      final shelf = library();
      await shelf.load();
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayImportPage(
            documents: FakeDocuments(),
            recovery: FileRecoveryStore(
              p.join(directory.path, 'support', 'day-recovery.json'),
            ),
            library: shelf,
          ),
        ),
      );
      await tester.pumpAndSettle();
      int? selected() => tester
          .widget<NavigationRail>(find.byKey(const ValueKey('appPlaces')))
          .selectedIndex;
      await tester.tap(find.byKey(const ValueKey('place-profile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.byKey(const ValueKey('profileEmpty')), findsOneWidget);
      expect(selected(), 4);
      // One of them at a time: Library takes Profile's place, and back.
      await tester.tap(find.byKey(const ValueKey('place-library')));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(ProfilePage), findsNothing);
      expect(selected(), 1);
      await tester.tap(find.byKey(const ValueKey('place-profile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.byType(LibraryPage), findsNothing);
      await tester.tap(find.byKey(const ValueKey('place-home')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsNothing);
      expect(selected(), 0);
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

  group('Profile bundle', () {
    // A library at [folder] holding day e1, saved there as the app saves
    // it, its recordings outside the profile.
    Future<ProfileLibrary> withDay(
      String folder, {
      Future<R> Function<R>(FutureOr<R> Function()) background = _inPlace,
    }) async {
      final outcome = importDay({
        'a.vbo': [30, 28, 31],
        'b.vbo': [29, 32],
      });
      final shelf = ProfileLibrary(
        store: FolderProfileStore(folder),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: background,
      );
      final path = (await shelf.dayPath('e1'))!;
      await saveDayDocument(
        path,
        dayDocument(
          eventId: 'e1',
          name: 'Test day',
          runs: outcome.runs,
          analysis: outcome.analysis!,
          projectPath: path,
        ),
      );
      await shelf.recordDay(
        eventId: 'e1',
        path: path,
        name: 'Test day',
        analysis: outcome.analysis!,
      );
      await shelf.flush();
      return shelf;
    }

    test('moves the days and their recordings to another library, in other isolates', () async {
      final here = await withDay(profileFolder(), background: Isolate.run);
      final bundle = p.join(directory.path, 'driver.feprofile');
      final export = (await here.exportBundle(bundle))!;
      expect(export.days, 1);
      expect(export.recordings, 2);
      for (final name in ['a.vbo', 'b.vbo']) {
        File(p.join(directory.path, name)).deleteSync();
      }

      final elsewhere = p.join(directory.path, 'Other');
      final there = ProfileLibrary(
        store: FolderProfileStore(elsewhere),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: Isolate.run,
      );
      final read = (await there.importBundle(bundle))!;
      expect(read.added, ['e1']);
      expect(there.profile!.day('e1')!.name, 'Test day');
      final day = openDay(p.join(elsewhere, 'Days', 'e1.fetproject'));
      expect(day.missing, isEmpty);
      expect(day.runs, hasLength(2));

      // Written: a library opened again has the day.
      final reopened = ProfileLibrary(
        store: FolderProfileStore(elsewhere),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: Isolate.run,
      );
      await reopened.load();
      expect(reopened.profile!.day('e1'), isNotNull);

      // Again: nothing is added twice.
      final again = (await there.importBundle(bundle))!;
      expect(again.added, isEmpty);
      expect(there.profile!.days, hasLength(1));
    });

    test('keeps a day recorded while a bundle is read', () async {
      final here = await withDay(profileFolder());
      final bundle = p.join(directory.path, 'driver.feprofile');
      await here.exportBundle(bundle);
      final elsewhere = p.join(directory.path, 'Other');
      final gate = Completer<void>();
      final reading = Completer<void>();
      final there = ProfileLibrary(
        store: FolderProfileStore(elsewhere),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: <R>(FutureOr<R> Function() job) async {
          final result = await job();
          if (result is ProfileBundleImport) {
            reading.complete();
            await gate.future;
          }
          return result;
        },
      );
      final imported = there.importBundle(bundle);
      await reading.future;
      // Meanwhile a day is saved on this device.
      final outcome = importDay({
        'c.vbo': [30, 29, 31],
      });
      await there.recordDay(
        eventId: 'h1',
        path: (await there.dayPath('h1'))!,
        name: 'Here',
        analysis: outcome.analysis!,
      );
      expect(there.profile!.day('h1'), isNotNull);
      gate.complete();
      final read = (await imported)!;
      expect(read.added, ['e1']);
      expect(
        {for (final day in there.profile!.days) day.eventId},
        {'h1', 'e1'},
      );
      await there.flush();
      final reopened = ProfileLibrary(
        store: FolderProfileStore(elsewhere),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: _inPlace,
      );
      await reopened.load();
      expect(
        {for (final day in reopened.profile!.days) day.eventId},
        {'h1', 'e1'},
      );
    });

    test('says when the imported days could not be written', () async {
      final here = await withDay(profileFolder());
      final bundle = p.join(directory.path, 'driver.feprofile');
      await here.exportBundle(bundle);
      final elsewhere = p.join(directory.path, 'Other');
      var failing = true;
      final there = ProfileLibrary(
        store: FolderProfileStore(elsewhere),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: <R>(FutureOr<R> Function() job) async {
          final result = await job();
          // The profile's write: a full disk, once.
          if (result == null && failing) {
            failing = false;
            throw const FileSystemException('No space left on device');
          }
          return result;
        },
      );
      await there.load();
      await expectLater(
        there.importBundle(bundle),
        throwsA(
          isA<ProfileNotSaved>().having(
            (error) => error.import.added,
            'added',
            ['e1'],
          ),
        ),
      );
      // Kept in memory, and written with the next change.
      expect(there.profile!.day('e1'), isNotNull);
      there.renameCar(there.profile!.cars.single.id, 'Clio');
      await there.flush();
      final reopened = ProfileLibrary(
        store: FolderProfileStore(elsewhere),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: _inPlace,
      );
      await reopened.load();
      expect(reopened.profile!.day('e1'), isNotNull);
      expect(reopened.profile!.cars.single.name, 'Clio');
    });

    testWidgets('exports from the menu and imports on another device', (
      tester,
    ) async {
      final here = await tester.runAsync(() => withDay(profileFolder()));
      final saved = p.join(directory.path, 'Saved', 'driver.feprofile');
      Directory(p.dirname(saved)).createSync();
      final pickers = _FakeBundlePickers(
        location: saved,
        work: p.join(directory.path, 'work.feprofile'),
      );
      await tester.pumpWidget(
        TelemetryApp(
          home: LibraryPage(library: here!, open: (_) {}, pickers: pickers),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('libraryExport')));
      await _untilSnackBar(tester);
      expect(find.text('Profile exported with 1 day.'), findsOneWidget);
      expect(File(saved).existsSync(), isTrue);
      expect(File(pickers.work).existsSync(), isFalse);
      expect(pickers.suggested, startsWith('Driver profile '));

      final there = ProfileLibrary(
        store: FolderProfileStore(p.join(directory.path, 'Other')),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
        background: _inPlace,
      );
      final picking = _FakeBundlePickers(bundle: saved);
      await tester.runAsync(there.load);
      // The other device: a new app.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        TelemetryApp(
          home: LibraryPage(library: there, open: (_) {}, pickers: picking),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('libraryEmpty')), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('libraryImport')));
      await _untilSnackBar(tester);
      expect(find.text('1 day added.'), findsOneWidget);
      expect(picking.released, [saved]);
      expect(find.byKey(const ValueKey('libraryDay-e1')), findsOneWidget);

      // A file that is not a profile changes nothing.
      final notes = File(p.join(directory.path, 'notes.feprofile'))
        ..writeAsStringSync('{}');
      picking.bundle = notes.path;
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('libraryImport')));
      await _untilSnackBar(tester);
      expect(find.textContaining('cannot be imported'), findsOneWidget);
      expect(there.profile!.days, hasLength(1));
      // The profile is written in place here: nothing is left running.
      await tester.pumpAndSettle();
    });

    testWidgets('shares the file on phones', (tester) async {
      final here = await tester.runAsync(() => withDay(profileFolder()));
      final pickers = _FakeBundlePickers(
        shares: true,
        work: p.join(directory.path, 'work.feprofile'),
      );
      await tester.pumpWidget(
        TelemetryApp(
          home: LibraryPage(library: here!, open: (_) {}, pickers: pickers),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('libraryExport')));
      await _untilSnackBar(tester);
      expect(pickers.shared, [pickers.work]);
      expect(File(pickers.work).existsSync(), isTrue);
      expect(find.text('Profile exported with 1 day.'), findsOneWidget);

      // Closed without sharing: nothing to confirm.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pumpAndSettle();
      pickers.sharing = false;
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('libraryExport')));
      for (var turn = 0; turn < 300 && pickers.shared.length < 2; turn++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(pickers.shared, hasLength(2));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('libraryWorking')), findsNothing);
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

final class _FakeBundlePickers implements ProfileBundlePickers {
  _FakeBundlePickers({
    this.shares = false,
    this.location,
    this.work = '',
    this.bundle,
  });

  @override
  final bool shares;
  final String? location;
  final String work;
  String? bundle;
  String? suggested;
  final shared = <String>[];

  @override
  Future<String?> saveLocation(String fileName) async {
    suggested = fileName;
    return location;
  }

  @override
  Future<String> workFile(String fileName) async => work;

  /// Whether the share sheet shares, or is closed.
  bool sharing = true;
  final released = <String>[];

  @override
  Future<bool> share(String path, Rect origin) async {
    shared.add(path);
    return sharing;
  }

  @override
  Future<void> release(String path) async => released.add(path);

  @override
  Future<String?> pickBundle() async => bundle;
}

/// Runs the page's export or import, which reads and writes real files,
/// until its snack bar shows.
Future<void> _untilSnackBar(WidgetTester tester) async {
  for (var turn = 0; turn < 300; turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.byType(SnackBar).evaluate().isNotEmpty) break;
  }
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsOneWidget);
}
