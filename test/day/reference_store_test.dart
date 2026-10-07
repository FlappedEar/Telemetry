// A day's reference lap kept in the driver profile (FET-276): restored when
// the day is opened again, a cleared one staying cleared, the recording kept
// inside the profile and never as a path, missing files and failed saves
// told, and the same on the day page in English and Polish. Recordings here
// are synthetic: no real data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/profile_reference_store.dart';
import 'package:telemetry/day/reference_lap.dart';
import 'package:telemetry/day/reference_lap_page.dart' show referenceLine;
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../support/temp_directory.dart';
import 'rectangle_vbo.dart';

final class _Pickers implements RecordingPickers {
  _Pickers(this.paths);

  List<String> paths;

  @override
  Future<List<String>> pickRecordings() async => paths;

  @override
  Future<String?> pickFolder() async => null;
}

/// Records what a holder asks its store to keep, answering as told.
final class _FakeStore implements ReferenceStore {
  ReferenceChoice? restored;
  final kept = <ReferenceChoice?>[];
  bool answer = true;
  Object? failure;
  int restores = 0;

  @override
  Future<ReferenceChoice?> restore(String eventId) async {
    ++restores;
    return restored;
  }

  @override
  Future<bool> keep(String eventId, ReferenceChoice? choice) async {
    kept.add(choice);
    if (failure case final failure?) throw failure;
    return answer;
  }
}

Future<R> _inPlace<R>(FutureOr<R> Function() computation) async =>
    computation();

Type _typeOf<T>() => T;

/// A disk whose writes of the profile can be held back and made to fail,
/// one by one, to tell which write failed.
final class _Disk {
  /// While set, a write of the profile waits for it.
  Completer<void>? hold;

  /// How many of the next writes of the profile fail.
  int failing = 0;

  Future<R> background<R>(FutureOr<R> Function() computation) async {
    // The profile is written by the one job that returns nothing.
    if (R == _typeOf<void>()) {
      if (hold case final hold?) await hold.future;
      if (failing > 0) {
        failing--;
        throw const FileSystemException('disk full');
      }
    }
    return computation();
  }
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('refstore'));
  tearDown(() => deleteTemporaryDirectory(directory));

  String profileFolder() => p.join(directory.path, 'Profile');

  ProfileLibrary library() => ProfileLibrary(
    store: FolderProfileStore(profileFolder()),
    defaultCarName: 'Car',
    defaultTrackName: (number) => 'Track $number',
    background: _inPlace,
  );

  ProfileLibrary libraryOn(
    String folder, {
    Future<R> Function<R>(FutureOr<R> Function())? background,
  }) => ProfileLibrary(
    store: FolderProfileStore(folder),
    defaultCarName: 'Car',
    defaultTrackName: (number) => 'Track $number',
    background: background ?? _inPlace,
  );

  String write(String name, String text) {
    final path = p.join(directory.path, name);
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsStringSync(text);
    return path;
  }

  String withoutLine(String vbo) =>
      vbo.replaceFirst(RegExp(r'\[laptiming\]\n[^\n]*\n'), '');

  // A friend's recording: three laps, the second slow, no line of its own.
  String friend([String name = 'friend.vbo']) => write(
    'friends/$name',
    withoutLine(
      rectangleVbo([
        rectangleLap(32),
        rectangleLap(32, 100, 200, 20),
        rectangleLap(31.5),
      ], pedals: true),
    ),
  );

  /// A day imported from [name], saved in the profile's days folder.
  Future<DayResultsController> savedDay(
    String name,
    List<double Function(double)> laps,
  ) async {
    final outcome = runDayImport((
      paths: [write('own/$name.vbo', rectangleVbo(laps, pedals: true))],
      includeSubfolders: false,
    ));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final path = profileDayPath(profileFolder(), controller.eventId);
    Directory(p.dirname(path)).createSync(recursive: true);
    await controller.save(path);
    return controller;
  }

  List<double Function(double)> todayLaps() => [
    rectangleLap(30, 50, 120, 20),
    rectangleLap(31, 300, 400, 25),
    rectangleLap(30),
  ];

  // Today's line, as the day page times a reference on it.
  ReferenceLine realLine() {
    final outcome = runDayImport((
      paths: [write('own/line.vbo', rectangleVbo(todayLaps(), pedals: true))],
      includeSubfolders: false,
    ));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    addTearDown(controller.dispose);
    return referenceLine(controller)!;
  }

  ProfileReferenceStore storeOf(ProfileLibrary library, {bool keeps = true}) =>
      ProfileReferenceStore(library, keepsDay: () => keeps);

  String profileText() =>
      File(p.join(profileFolder(), profileFileName)).readAsStringSync();

  group('ProfileReferenceStore', () {
    test('a recording file is kept as a copy in the profile, never as a path, '
        'and restored from a new start', () async {
      final today = await savedDay('today', todayLaps());
      final shelf = library();
      await shelf.load();
      final store = storeOf(shelf);
      final source = friend();
      final content = File(source).readAsBytesSync();

      expect(await store.restore(today.eventId), isNull);
      expect(
        await store.keep(
          today.eventId,
          ReferenceChoice(
            source: ReferenceFile(source),
            recordingId: 'friend.vbo',
            lapNumber: 2,
          ),
        ),
        isTrue,
      );
      await shelf.flush();

      // In the profile: the choice and the copy's name, not where it was.
      final text = profileText();
      expect(text, isNot(contains(directory.path)));
      expect(text, isNot(contains('friends')));
      final reference =
          decodeDriverProfile(text).day(today.eventId)!.reference
              as ProfileReferenceFile;
      expect(reference.recordingId, 'friend.vbo');
      expect(reference.lapNumber, 2);
      expect(reference.name, 'friend.vbo');
      final copy = p.join(profileFolder(), 'Recordings', reference.fileName);
      expect(File(copy).readAsBytesSync(), content);
      expect(reference.fileName, matches(RegExp(r'^[0-9a-f]{64}\.vbo$')));

      // Another start: the same choice, on the copy, under the file's name.
      File(source).deleteSync();
      final again = library();
      await again.load();
      final restored = (await storeOf(again).restore(today.eventId))!;
      final file = restored.source as ReferenceFile;
      expect(file.path, copy);
      expect(file.name, 'friend.vbo');
      expect(file.expectedBytes, content.length);
      expect(restored.recordingId, 'friend.vbo');
      expect(restored.lapNumber, 2);
    });

    test('a lap of another day is kept as that day, and says so when the day '
        'is gone', () async {
      final today = await savedDay('today', todayLaps());
      final earlier = await savedDay('earlier', [
        rectangleLap(32),
        rectangleLap(31),
      ]);
      final shelf = library();
      await shelf.load();
      final store = storeOf(shelf);
      final earlierDay = shelf.profile!.day(earlier.eventId)!;
      final runId = earlier.runs.single.run.id;
      await store.keep(
        today.eventId,
        ReferenceChoice(
          source: ReferenceProfileDay(
            path: shelf.pathOf(earlierDay)!,
            eventId: earlier.eventId,
            dayName: earlierDay.name,
          ),
          recordingId: runId,
          lapNumber: 2,
        ),
      );
      await shelf.flush();
      final day = decodeDriverProfile(profileText()).day(today.eventId)!;
      final reference = day.reference as ProfileReferenceDay;
      expect(reference.eventId, earlier.eventId);
      expect(reference.recordingId, runId);
      expect(reference.lapNumber, 2);
      expect(profileText(), isNot(contains(directory.path)));
      expect(
        Directory(p.join(profileFolder(), 'Recordings')).existsSync(),
        isFalse,
      );

      var restored = (await store.restore(today.eventId))!;
      expect(restored.source, isA<ReferenceProfileDay>());
      expect(
        (restored.source as ReferenceProfileDay).path,
        shelf.pathOf(earlierDay),
      );
      expect(restored.recordingId, runId);

      // The other day deleted from the profile: the choice stays and says so.
      await shelf.deleteDay(earlier.eventId);
      restored = (await store.restore(today.eventId))!;
      final gone = restored.source as ReferenceProfileDay;
      expect(gone.path, isEmpty);
      expect(gone.dayName, earlierDay.name);
      expect(gone.eventId, earlier.eventId);
      final result = loadReference((
        source: gone,
        line: realLine(),
      ), () => false);
      expect(result.error, referenceDayMissing);
    });

    test('clearing forgets it for good and removes the copy nothing else uses; '
        'a copy another day uses stays', () async {
      final a = await savedDay('a', todayLaps());
      final b = await savedDay('b', [rectangleLap(30), rectangleLap(31)]);
      final shelf = library();
      await shelf.load();
      final store = storeOf(shelf);
      final shared = friend('shared.vbo');
      final own = friend('own.vbo');
      File(own).writeAsStringSync('${File(own).readAsStringSync()}\n');
      Future<void> keep(String id, String path, [int lap = 1]) async =>
          store.keep(
            id,
            ReferenceChoice(
              source: ReferenceFile(path),
              recordingId: p.basename(path),
              lapNumber: lap,
            ),
          );
      await keep(a.eventId, shared);
      await keep(b.eventId, shared, 2);
      await keep(a.eventId, own, 3);
      final recordings = Directory(p.join(profileFolder(), 'Recordings'));
      // The shared copy once, a's own change replaced the shared one for a.
      expect(recordings.listSync(), hasLength(2));
      // b still uses the shared copy: a's change did not remove it.
      expect(shelf.referenceOf(b.eventId), isA<ProfileReferenceFile>());

      expect(await store.keep(a.eventId, null), isTrue);
      await shelf.flush();
      expect(recordings.listSync(), hasLength(1), reason: 'a\'s own copy went');
      expect(await store.restore(a.eventId), isNull);
      // Cleared stays cleared across a start.
      final again = library();
      await again.load();
      expect(await storeOf(again).restore(a.eventId), isNull);
      expect(await storeOf(again).restore(b.eventId), isNotNull);
      expect(await store.keep(b.eventId, null), isTrue);
      await shelf.flush();
      expect(recordings.listSync(), isEmpty);
    });

    test('a day deleted from the profile forgets its reference and its copy, '
        'unless another day uses it', () async {
      final a = await savedDay('a', todayLaps());
      final b = await savedDay('b', [rectangleLap(30), rectangleLap(31)]);
      final shelf = library();
      await shelf.load();
      final store = storeOf(shelf);
      final path = friend();
      for (final id in [a.eventId, b.eventId]) {
        await store.keep(
          id,
          ReferenceChoice(
            source: ReferenceFile(path),
            recordingId: 'friend.vbo',
            lapNumber: 1,
          ),
        );
      }
      final copy = Directory(p.join(profileFolder(), 'Recordings'))
          .listSync()
          .single
          .path;
      final deleted = (await shelf.deleteDay(a.eventId))!;
      expect(deleted.recordingsKept, greaterThanOrEqualTo(1));
      expect(File(copy).existsSync(), isTrue);
      expect(
        shelf.profile!.days.map((d) => d.eventId),
        isNot(contains(a.eventId)),
      );
      expect(shelf.referenceOf(a.eventId), isNull);
      expect(File(path).existsSync(), isTrue, reason: 'the friend\'s own file');
      await shelf.deleteDay(b.eventId);
      await shelf.flush();
      expect(File(copy).existsSync(), isFalse);
      expect(File(path).existsSync(), isTrue);
      expect(profileText(), isNot(contains('friend')));
    });

    test('a day recorded again keeps its reference, and one chosen before the '
        'day is in the profile is given to it', () async {
      final today = await savedDay('today', todayLaps());
      final shelf = library();
      await shelf.load();
      final store = storeOf(shelf);
      await store.keep(
        today.eventId,
        ReferenceChoice(
          source: ReferenceFile(friend()),
          recordingId: 'friend.vbo',
          lapNumber: 1,
        ),
      );
      await shelf.recordDay(
        eventId: today.eventId,
        path: today.documentPath!,
        name: 'Renamed',
        analysis: today.analysis,
      );
      await shelf.flush();
      expect(shelf.profile!.day(today.eventId)!.name, 'Renamed');
      expect(shelf.referenceOf(today.eventId), isNotNull);

      // A new day, chosen for before it was listed.
      final outcome = runDayImport((
        paths: [write('own/new.vbo', rectangleVbo(todayLaps(), pedals: true))],
        includeSubfolders: false,
      ));
      const id = 'brandnewday';
      final path = (await shelf.dayPath(id))!;
      File(path).writeAsStringSync(
        jsonEncode(
          dayDocument(
            eventId: id,
            name: 'New',
            runs: outcome.runs,
            analysis: outcome.analysis!,
            projectPath: path,
          ),
        ),
      );
      expect(shelf.profile!.day(id), isNull);
      await store.keep(
        id,
        ReferenceChoice(
          source: ReferenceFile(friend('other.vbo')),
          recordingId: 'other.vbo',
          lapNumber: 2,
        ),
      );
      expect((await store.restore(id))!.lapNumber, 2);
      await shelf.recordDay(
        eventId: id,
        path: path,
        name: 'New',
        analysis: outcome.analysis!,
      );
      await shelf.flush();
      final given = shelf.profile!.day(id)!.reference as ProfileReferenceFile;
      expect(given.recordingId, 'other.vbo');
      expect(given.lapNumber, 2);
      expect(decodeDriverProfile(profileText()).day(id)!.reference, isNotNull);
    });

    test('keeps nothing for a day that is not in the profile', () async {
      final today = await savedDay('today', todayLaps());
      final shelf = library();
      await shelf.load();
      final store = storeOf(shelf, keeps: false);
      expect(
        await store.keep(
          today.eventId,
          ReferenceChoice(
            source: ReferenceFile(friend()),
            recordingId: 'friend.vbo',
            lapNumber: 1,
          ),
        ),
        isFalse,
      );
      expect(shelf.referenceOf(today.eventId), isNull);
      expect(
        Directory(p.join(profileFolder(), 'Recordings')).existsSync(),
        isFalse,
      );
    });

    test(
      'says why a reference was not kept, and keeps no copy it made',
      () async {
        final today = await savedDay('today', todayLaps());
        final shelf = library();
        await shelf.load();
        final store = storeOf(shelf);
        Future<ProfileReferenceProblem?> problem(String path) async {
          try {
            await store.keep(
              today.eventId,
              ReferenceChoice(
                source: ReferenceFile(path),
                recordingId: p.basename(path),
                lapNumber: 1,
              ),
            );
            return null;
          } on ProfileReferenceError catch (error) {
            return error.problem;
          }
        }

        expect(
          await problem(write('notes.txt', 'x')),
          ProfileReferenceProblem.fileType,
        );
        expect(
          await problem(p.join(directory.path, 'missing.vbo')),
          ProfileReferenceProblem.fileUnreadable,
        );
        expect(
          await problem(write('empty.vbo', '')),
          ProfileReferenceProblem.fileEmpty,
        );
        // The profile already keeps the most recordings.
        for (var i = 0; i < maximumReferenceFiles; i++) {
          final other = await savedDay('d$i', [
            rectangleLap(30 + i / 100),
            rectangleLap(31),
          ]);
          await shelf.recordDay(
            eventId: other.eventId,
            path: other.documentPath!,
            name: 'd$i',
            analysis: other.analysis,
          );
          final path = write('ref/$i.vbo', 'recording number $i\n');
          await store.keep(
            other.eventId,
            ReferenceChoice(
              source: ReferenceFile(path),
              recordingId: '$i.vbo',
              lapNumber: 1,
            ),
          );
        }
        final recordings = Directory(p.join(profileFolder(), 'Recordings'));
        expect(recordings.listSync(), hasLength(maximumReferenceFiles));
        expect(
          await problem(write('one more.vbo', 'one more\n')),
          ProfileReferenceProblem.tooManyFiles,
        );
        expect(recordings.listSync(), hasLength(maximumReferenceFiles));
        expect(
          recordings.listSync().where((e) => e.path.contains('.partial')),
          isEmpty,
        );
        expect(shelf.referenceOf(today.eventId), isNull);
      },
    );

    test(
      'a profile that cannot be written is told, not dropped silently',
      () async {
        final today = await savedDay('today', todayLaps());
        // The profile file's place is taken by a folder: it cannot be written.
        Directory(p.join(profileFolder(), profileFileName))
            .createSync(recursive: true);
        File(p.join(profileFolder(), profileFileName, 'x'))
            .writeAsStringSync('x');
        final shelf = library();
        await shelf.load();
        expect(shelf.profile!.day(today.eventId), isNotNull);
        final store = storeOf(shelf);
        await expectLater(
          store.keep(
            today.eventId,
            ReferenceChoice(
              source: ReferenceFile(friend()),
              recordingId: 'friend.vbo',
              lapNumber: 1,
            ),
          ),
          throwsA(
            isA<ProfileReferenceError>().having(
              (error) => error.problem,
              'problem',
              ProfileReferenceProblem.notWritten,
            ),
          ),
        );
        // Nothing is kept: not in memory, and no copy left behind.
        expect(shelf.referenceOf(today.eventId), isNull);
        final recordings = Directory(p.join(profileFolder(), 'Recordings'));
        expect(
          !recordings.existsSync() || recordings.listSync().isEmpty,
          isTrue,
        );
      },
    );
  });

  group('the library keeps references in order and tells what it did', () {
    ReferenceChoice choice(String path, [int lap = 2]) => ReferenceChoice(
      source: ReferenceFile(path),
      recordingId: p.basename(path),
      lapNumber: lap,
    );

    Directory recordings() => Directory(p.join(profileFolder(), 'Recordings'));

    Future<String> newDay(ProfileLibrary shelf, String id) async {
      final outcome = runDayImport((
        paths: [write('own/$id.vbo', rectangleVbo(todayLaps(), pedals: true))],
        includeSubfolders: false,
      ));
      final path = (await shelf.dayPath(id))!;
      File(path).writeAsStringSync(
        jsonEncode(
          dayDocument(
            eventId: id,
            name: id,
            runs: outcome.runs,
            analysis: outcome.analysis!,
            projectPath: path,
          ),
        ),
      );
      return path;
    }

    DayAnalysis analysisOf(String id) => runDayImport((
      paths: [write('own/$id.vbo', rectangleVbo(todayLaps(), pedals: true))],
      includeSubfolders: false,
    )).analysis!;

    test(
      'a restore sees what was asked just before it, kept or cleared',
      () async {
        final today = await savedDay('today', todayLaps());
        final shelf = library();
        await shelf.load();
        final store = storeOf(shelf);
        final keeping = store.keep(today.eventId, choice(friend()));
        // Not waited for: the copy is still being made.
        final restored = await store.restore(today.eventId);
        expect(restored!.lapNumber, 2);
        expect((restored.source as ReferenceFile).name, 'friend.vbo');
        await keeping;
        final clearing = store.keep(today.eventId, null);
        expect(await store.restore(today.eventId), isNull);
        await clearing;
        // A day not in the profile yet is held, and read the same way.
        await newDay(shelf, 'brandnew');
        final holding = store.keep('brandnew', choice(friend('b.vbo'), 3));
        expect((await store.restore('brandnew'))!.lapNumber, 3);
        await holding;
      },
    );

    test(
      'a copy a day waiting to be listed uses stays when another day goes',
      () async {
        final a = await savedDay('a', todayLaps());
        final shelf = library();
        await shelf.load();
        final shared = friend('shared.vbo');
        await newDay(shelf, 'waiting');
        expect(
          await shelf.setFileReference(
            a.eventId,
            source: shared,
            name: 'shared.vbo',
            recordingId: 'shared.vbo',
            lapNumber: 1,
          ),
          isTrue,
        );
        await shelf.setFileReference(
          'waiting',
          source: shared,
          name: 'shared.vbo',
          recordingId: 'shared.vbo',
          lapNumber: 2,
        );
        final copy = recordings().listSync().single.path;
        await shelf.deleteDay(a.eventId);
        expect(
          File(copy).existsSync(),
          isTrue,
          reason: 'the waiting day uses it',
        );
        await shelf.recordDay(
          eventId: 'waiting',
          path: (await shelf.dayPath('waiting'))!,
          name: 'waiting',
          analysis: analysisOf('waiting'),
        );
        await shelf.flush();
        expect(shelf.profile!.day('waiting')!.reference, isNotNull);
        expect(File(copy).existsSync(), isTrue);
      },
    );

    test(
      'a day outside the profile\'s days folder is not deleted, its copy is',
      () async {
        final x = await savedDay('x', todayLaps());
        final folder = profileFolder();
        final moved = p.join(folder, 'Elsewhere', 'x.fetproject');
        Directory(p.dirname(moved)).createSync(recursive: true);
        File(x.documentPath!).renameSync(moved);
        final copy = keepReferenceFile(folder, friend());
        var profile = addDayToProfile(
          DriverProfile.empty(),
          ProfileDayInput(
            eventId: x.eventId,
            file: 'Elsewhere/x.fetproject',
            name: 'X',
          ),
          defaultCarName: 'Car',
          defaultTrackName: 'Track',
        );
        profile = setProfileDayReference(
          profile,
          x.eventId,
          copy.reference('friend.vbo', 'friend.vbo', 1),
        );
        File(p.join(folder, profileFileName))
            .writeAsStringSync(encodeDriverProfile(profile));
        final shelf = library();
        await shelf.load();
        expect(shelf.referenceOf(x.eventId), isNotNull);
        final copyPath = p.join(folder, 'Recordings', '${copy.sha256}.vbo');
        await shelf.deleteDay(x.eventId);
        await shelf.flush();
        expect(
          File(moved).existsSync(),
          isTrue,
          reason: 'not the profile\'s to delete',
        );
        expect(File(copyPath).existsSync(), isFalse);
        expect(shelf.profile!.day(x.eventId), isNull);
      },
    );

    test('references waiting for their day count against the limits', () async {
      final today = await savedDay('today', todayLaps());
      final shelf = library();
      await shelf.load();
      for (var i = 0; i < maximumReferenceFiles; i++) {
        await shelf.setFileReference(
          'waiting$i',
          source: write('ref/$i.vbo', 'recording number $i\n'),
          name: '$i.vbo',
          recordingId: '$i.vbo',
          lapNumber: 1,
        );
      }
      Future<ProfileReferenceProblem?> problem(String id) async {
        try {
          await shelf.setFileReference(
            id,
            source: write('ref/more-$id.vbo', 'one more for $id\n'),
            name: 'more.vbo',
            recordingId: 'more.vbo',
            lapNumber: 1,
          );
          return null;
        } on ProfileReferenceError catch (error) {
          return error.problem;
        }
      }

      expect(
        await problem(today.eventId),
        ProfileReferenceProblem.tooManyFiles,
      );
      expect(
        await problem('waitingMore'),
        ProfileReferenceProblem.tooManyFiles,
      );
      expect(recordings().listSync(), hasLength(maximumReferenceFiles));
      expect(shelf.referenceOf(today.eventId), isNull);
    });

    test('a waiting reference the profile has no room for when its day is '
        'listed is dropped, its copy removed, and the user told', () async {
      // A bundle from another profile brings one more recording.
      final source = libraryOn(p.join(directory.path, 'Source'));
      await source.load();
      final path = await newDay(source, 'brought');
      await source.recordDay(
        eventId: 'brought',
        path: path,
        name: 'brought',
        analysis: analysisOf('brought'),
      );
      await source.setFileReference(
        'brought',
        source: friend('brought.vbo'),
        name: 'brought.vbo',
        recordingId: 'brought.vbo',
        lapNumber: 1,
      );
      final bundle = p.join(directory.path, 'x$profileBundleExtension');
      expect(await source.exportBundle(bundle), isNotNull);

      final shelf = library();
      await shelf.load();
      for (var i = 0; i < maximumReferenceFiles - 1; i++) {
        await shelf.setFileReference(
          'waiting$i',
          source: write('ref/$i.vbo', 'recording number $i\n'),
          name: '$i.vbo',
          recordingId: '$i.vbo',
          lapNumber: 1,
        );
      }
      await newDay(shelf, 'last');
      final lastFile = write('ref/last.vbo', 'distinct content of the last\n');
      await shelf.setFileReference(
        'last',
        source: lastFile,
        name: 'last.vbo',
        recordingId: 'last.vbo',
        lapNumber: 1,
      );
      expect(recordings().listSync(), hasLength(maximumReferenceFiles));
      final imported = (await shelf.importBundle(bundle))!;
      expect(imported.added, ['brought']);
      expect(imported.referencesNotKept, isEmpty);

      var told = 0;
      shelf.addListener(() {
        if (shelf.referenceDropped('last') != null) told++;
      });
      await shelf.recordDay(
        eventId: 'last',
        path: (await shelf.dayPath('last'))!,
        name: 'last',
        analysis: analysisOf('last'),
      );
      await shelf.flush();
      expect(shelf.profile!.day('last')!.reference, isNull);
      expect(
        shelf.referenceDropped('last')!.problem,
        ProfileReferenceProblem.tooManyFiles,
      );
      expect(told, greaterThan(0));
      // Its copy goes once the changes of references so far are done.
      await shelf.restoreReference('last');
      final lastCopy = keepReferenceFile(
        p.join(directory.path, 'probe'),
        lastFile,
      );
      expect(
        File(p.join(profileFolder(), 'Recordings', '${lastCopy.sha256}.vbo'))
            .existsSync(),
        isFalse,
      );
      final broughtCopy =
          shelf.profile!.day('brought')!.reference as ProfileReferenceFile;
      expect(File(shelf.referenceFilePath(broughtCopy)!).existsSync(), isTrue);
    });

    test(
      'a write that failed is this change\'s failure, not another\'s',
      () async {
        final today = await savedDay('today', todayLaps());
        final disk = _Disk();
        final shelf = libraryOn(profileFolder(), background: disk.background);
        await shelf.load();
        await shelf.flush();
        // Another change's write is held, then fails; this change's follows.
        disk.hold = Completer<void>();
        shelf.renameCar(shelf.profile!.cars.first.id, 'Renamed');
        final keeping = shelf.setFileReference(
          today.eventId,
          source: friend(),
          name: 'friend.vbo',
          recordingId: 'friend.vbo',
          lapNumber: 2,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        disk.failing = 1;
        disk.hold!.complete();
        expect(await keeping, isTrue);
        await shelf.flush();
        expect(shelf.referenceOf(today.eventId), isNotNull);
        expect(profileText(), contains('friend.vbo'));
        expect(recordings().listSync(), hasLength(1));
      },
    );

    test('a write that failed takes the reference back from the profile as '
        'it is now, and nothing else', () async {
      final today = await savedDay('today', todayLaps());
      final disk = _Disk();
      final shelf = libraryOn(profileFolder(), background: disk.background);
      await shelf.load();
      await shelf.flush();
      disk.hold = Completer<void>();
      final keeping = shelf.setFileReference(
        today.eventId,
        source: friend(),
        name: 'friend.vbo',
        recordingId: 'friend.vbo',
        lapNumber: 2,
      );
      Object? failure;
      final told = keeping.then<void>(
        (_) {},
        onError: (Object e) => failure = e,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Another change is made while the write is on its way.
      shelf.renameCar(shelf.profile!.cars.first.id, 'Renamed');
      disk.failing = 1;
      disk.hold!.complete();
      await told;
      await shelf.flush();
      expect(
        failure,
        isA<ProfileReferenceError>().having(
          (error) => error.problem,
          'problem',
          ProfileReferenceProblem.notWritten,
        ),
      );
      expect(shelf.referenceOf(today.eventId), isNull);
      final onDisk = decodeDriverProfile(profileText());
      expect(onDisk.day(today.eventId)!.reference, isNull);
      expect(onDisk.cars.first.name, 'Renamed');
      expect(shelf.profile!.cars.first.name, 'Renamed');
      expect(recordings().listSync(), isEmpty, reason: 'its copy went');
    });

    /// A profile of one day whose `reference` is [value] as written by
    /// another version, with Recordings holding a copy the value names (when
    /// it says `NAMED`) and an orphan nothing names.
    Future<({File named, File orphan, ProfileLibrary shelf})> unreadable(
      Object? value,
    ) async {
      final today = await savedDay('today', todayLaps());
      final folder = profileFolder();
      final profile = addDayToProfile(
        DriverProfile.empty(),
        ProfileDayInput(
          eventId: today.eventId,
          file: 'Days/${today.eventId}.fetproject',
          name: 'Today',
        ),
        defaultCarName: 'Car',
        defaultTrackName: 'Track',
      );
      final json =
          jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
      final named = keepReferenceFile(
        folder,
        write('ref/named.vbo', 'named\n'),
      );
      final orphan = keepReferenceFile(
        folder,
        write('ref/orphan.vbo', 'orphan\n'),
      );
      Object? named_(Object? v) => switch (v) {
        'NAMED' => named.sha256,
        final Map m => {for (final e in m.entries) e.key: named_(e.value)},
        final List l => [for (final e in l) named_(e)],
        _ => v,
      };
      ((json['days'] as List).single as Map<String, Object?>)['reference'] =
          named_(value);
      File(p.join(folder, profileFileName)).writeAsStringSync(jsonEncode(json));
      final shelf = library();
      await shelf.load();
      // The sweep runs behind the load; give it its time.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return (
        named: File(p.join(folder, 'Recordings', '${named.sha256}.vbo')),
        orphan: File(p.join(folder, 'Recordings', '${orphan.sha256}.vbo')),
        shelf: shelf,
      );
    }

    test('the sweep keeps a copy a reference it cannot read names', () async {
      for (final value in <Object?>[
        {'kind': 'tape', 'sha256': 'NAMED', 'extension': '.vbo'},
        {
          'kind': 'newer',
          'inner': [
            {'sha256': 'NAMED'},
          ],
        },
      ]) {
        if (Directory(profileFolder()).existsSync()) {
          Directory(profileFolder()).deleteSync(recursive: true);
        }
        final r = await unreadable(value);
        addTearDown(r.shelf.dispose);
        expect(r.named.existsSync(), isTrue, reason: '$value');
        expect(r.orphan.existsSync(), isFalse, reason: 'the sweep ran');
      }
    });

    test(
      'the sweep stops when a reference has a shape it cannot read',
      () async {
        for (final value in <Object?>[
          'a path: /home/me/friend.vbo',
          42,
          [1],
        ]) {
          if (Directory(profileFolder()).existsSync()) {
            Directory(profileFolder()).deleteSync(recursive: true);
          }
          final r = await unreadable(value);
          addTearDown(r.shelf.dispose);
          expect(r.named.existsSync(), isTrue, reason: '$value');
          expect(
            r.orphan.existsSync(),
            isTrue,
            reason: 'nothing is guessed: $value',
          );
        }
      },
    );

    test(
      'copies nothing uses are swept once at start-up, and only those',
      () async {
        final today = await savedDay('today', todayLaps());
        final first = library();
        await first.load();
        await first.setFileReference(
          today.eventId,
          source: friend(),
          name: 'friend.vbo',
          recordingId: 'friend.vbo',
          lapNumber: 1,
        );
        final folder = profileFolder();
        final orphan = keepReferenceFile(
          folder,
          write('ref/orphan.vbo', 'nothing uses this\n'),
        );
        final notes = File(p.join(folder, 'Recordings', 'notes.vbo'))
          ..writeAsStringSync('mine');
        final kept = recordings().listSync().map((e) => e.path).toSet()
          ..remove(p.join(folder, 'Recordings', '${orphan.sha256}.vbo'))
          ..remove(notes.path);
        final again = library();
        await again.load();
        final gone = File(p.join(folder, 'Recordings', '${orphan.sha256}.vbo'));
        for (var i = 0; i < 100 && gone.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(gone.existsSync(), isFalse);
        expect(notes.existsSync(), isTrue);
        expect(kept.single, isNotEmpty);
        expect(File(kept.single).existsSync(), isTrue, reason: 'a reference');
        expect(again.referenceOf(today.eventId), isNotNull);
      },
    );
  });

  group('ReferenceLapHolder with a store', () {
    late ReferenceLine line;
    setUp(() => line = realLine());

    test(
      'restores once, and a reference cleared meanwhile stays cleared',
      () async {
        final store = _FakeStore()
          ..restored = ReferenceChoice(
            source: ReferenceFile(
              '/profile/Recordings/x.vbo',
              label: 'friend.vbo',
            ),
            recordingId: 'friend.vbo',
            lapNumber: 2,
          );
        var loads = 0;
        final gate = Completer<void>();
        final h = ReferenceLapHolder(
          dayId: 'day',
          store: store,
          loader: (request) {
            ++loads;
            return _Never(gate.future);
          },
        );
        addTearDown(h.dispose);
        expect(h.restoreTried, isFalse);
        final first = h.restore(line);
        expect(h.restoreTried, isTrue);
        // Cleared while the store was still being read: nothing comes back.
        h.clear();
        await first;
        expect(loads, 0);
        expect(h.state, ReferenceState.none);
        await Future<void>.delayed(Duration.zero);
        expect(store.kept, [null]);
        await h.restore(line);
        expect(store.restores, 1, reason: 'read once');
        expect(h.state, ReferenceState.none);
      },
    );

    test('a restored reference is not written back, and a source that cannot '
        'be read keeps what was kept', () async {
      final store = _FakeStore()
        ..restored = ReferenceChoice(
          source: ReferenceFile(
            '/profile/Recordings/missing.vbo',
            label: 'friend.vbo',
          ),
          recordingId: 'friend.vbo',
          lapNumber: 2,
        );
      final h = ReferenceLapHolder(dayId: 'day', store: store);
      addTearDown(h.dispose);
      await h.restore(line);
      await Future<void>.delayed(Duration.zero);
      expect(h.state, ReferenceState.failed);
      expect(h.error, referenceFileMissing);
      expect(h.keepState, ReferenceKeep.saved);
      // Nothing was forgotten or rewritten.
      expect(store.kept, isEmpty);
      // Only an explicit clear forgets it.
      h.clear();
      await Future<void>.delayed(Duration.zero);
      expect(store.kept, [null]);
    });

    test(
      'a store that fails is told to the user, and tried again on request',
      () async {
        final store = _FakeStore()
          ..failure = const ProfileReferenceError(
            ProfileReferenceProblem.notWritten,
            'The profile could not be written.',
          );
        final h = ReferenceLapHolder(dayId: 'day', store: store);
        addTearDown(h.dispose);
        // Forgetting it is kept the same way, and told when it fails.
        h.clear();
        await Future<void>.delayed(Duration.zero);
        expect(h.keepState, ReferenceKeep.failed);
        expect(h.keepFailedToForget, isTrue);
        expect(h.keepProblem, ProfileReferenceProblem.notWritten);
        store.failure = null;
        h.retryKeep();
        await Future<void>.delayed(Duration.zero);
        expect(h.keepState, ReferenceKeep.saved);
        expect(store.kept, [null, null]);
      },
    );

    test('a lap that is gone shows the fastest and leaves the choice as it '
        'was, until a lap is chosen on purpose', () async {
      final store = _FakeStore()
        ..restored = ReferenceChoice(
          source: ReferenceFile(friend()),
          recordingId: 'friend.vbo',
          lapNumber: 99,
        );
      final h = ReferenceLapHolder(dayId: 'day', store: store);
      addTearDown(h.dispose);
      await h.restore(line);
      await Future<void>.delayed(Duration.zero);
      expect(h.state, ReferenceState.ready);
      expect(h.lap!.lapNumber, isNot(99));
      expect(h.keepState, ReferenceKeep.saved);
      expect(store.kept, isEmpty);
      // Read again (today's line changed): still the stored lap asked for.
      await h.reload(line);
      await Future<void>.delayed(Duration.zero);
      expect(store.kept, isEmpty);
      // A lap chosen on purpose is the new choice.
      final other = h.timing!.candidates.last;
      h.choose(other);
      await Future<void>.delayed(Duration.zero);
      expect(store.kept.single!.lapNumber, other.lapNumber);
    });

    test('a choice the store could not keep after all is told, and tried '
        'again on request', () async {
      final store = _FakeStore()
        ..restored = ReferenceChoice(
          source: ReferenceFile(friend()),
          recordingId: 'friend.vbo',
          lapNumber: 2,
        );
      final h = ReferenceLapHolder(dayId: 'day', store: store);
      addTearDown(h.dispose);
      await h.restore(line);
      await Future<void>.delayed(Duration.zero);
      expect(h.keepState, ReferenceKeep.saved);
      h.keepDropped(ProfileReferenceProblem.tooManyFiles);
      expect(h.keepState, ReferenceKeep.failed);
      expect(h.keepProblem, ProfileReferenceProblem.tooManyFiles);
      h.retryKeep();
      await Future<void>.delayed(Duration.zero);
      expect(h.keepState, ReferenceKeep.saved);
      expect(store.kept.single!.lapNumber, 2);
    });

    test('a store that keeps nothing says so', () async {
      final store = _FakeStore()..answer = false;
      final h = ReferenceLapHolder(dayId: 'day', store: store);
      addTearDown(h.dispose);
      h.clear();
      await Future<void>.delayed(Duration.zero);
      expect(h.keepState, ReferenceKeep.unsaved);
    });
  });

  group('the day page', () {
    Future<void> openCompare(
      WidgetTester tester,
      DayResultsController controller,
      ProfileLibrary library, {
      List<String> picks = const [],
      Locale? locale,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          locale: locale,
          home: DayResultsPage.controller(
            controller: controller,
            pickers: _Pickers(picks),
            library: library,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('daySection-compare')));
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    String textOf(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    /// Lets the library and the reference read in the background finish.
    Future<void> settle(WidgetTester tester) async {
      // Work started in the real zone (the library's own, at start-up) and
      // in the test's fake one hands over to each other a few times.
      for (var round = 0; round < 4; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
      }
    }

    Future<DayResultsController> reopened(DayResultsController day) async =>
        DayResultsController.opened(openDay(day.documentPath!));

    for (final polish in [false, true]) {
      testWidgets('remembers the reference of a day, its recording copied into '
          'the profile${polish ? ' (Polish)' : ''}', (tester) async {
        final locale = polish ? const Locale('pl') : null;
        final today = await tester.runAsync(
          () => savedDay('today', todayLaps()),
        );
        final shelf = library();
        addTearDown(shelf.dispose);
        await tester.runAsync(shelf.load);
        final source = friend();
        await openCompare(
          tester,
          today!,
          shelf,
          picks: [source],
          locale: locale,
        );
        await tapKey(tester, 'referenceLoadFile');
        await settle(tester);
        final label = textOf(tester, 'referenceLabel');
        expect(
          label,
          contains(
            polish ? 'Odniesienie: friend.vbo' : 'Reference: friend.vbo',
          ),
        );
        expect(
          textOf(tester, 'referenceKeep'),
          polish
              ? 'Zapamiętane dla tego dnia w Twoim profilu kierowcy, razem z kopią zapisu.'
              : 'Remembered for this day in your driver profile, with a copy of the recording.',
        );
        // Another lap is remembered too.
        await tapKey(tester, 'referenceChooseLap');
        await tapKey(tester, 'referenceLap 0 2');
        await settle(tester);
        await settle(tester);
        final text = profileText();
        expect(text, isNot(contains(directory.path)));
        final stored =
            decodeDriverProfile(text).day(today.eventId)!.reference
                as ProfileReferenceFile;
        expect(stored.lapNumber, 2);
        final chosen = textOf(tester, 'referenceLabel');

        // The day opened again, the friend's own file gone: the reference is
        // there, on the copy, and the same lap.
        await tester.pumpWidget(const SizedBox());
        File(source).deleteSync();
        final next = (await tester.runAsync(() => reopened(today)))!;
        final shelf2 = library();
        addTearDown(shelf2.dispose);
        await tester.runAsync(shelf2.load);
        await openCompare(tester, next, shelf2, locale: locale);
        await settle(tester);
        expect(textOf(tester, 'referenceLabel'), chosen);
        expect(
          textOf(tester, 'referenceKeep'),
          polish
              ? 'Zapamiętane dla tego dnia w Twoim profilu kierowcy, razem z kopią zapisu.'
              : 'Remembered for this day in your driver profile, with a copy of the recording.',
        );
        expect(find.byKey(const ValueKey('referenceProblem')), findsNothing);
        // It compares with today's best straight away.
        expect(find.byKey(const ValueKey('referenceCompare')), findsOneWidget);

        // Cleared, it stays cleared.
        await tapKey(tester, 'referenceClear');
        await settle(tester);
        await settle(tester);
        await tester.pumpWidget(const SizedBox());
        final third = (await tester.runAsync(() => reopened(today)))!;
        final shelf3 = library();
        addTearDown(shelf3.dispose);
        await tester.runAsync(shelf3.load);
        await openCompare(tester, third, shelf3, locale: locale);
        await settle(tester);
        expect(find.byKey(const ValueKey('referenceLabel')), findsNothing);
        expect(find.byKey(const ValueKey('referenceClear')), findsNothing);
        expect(
          Directory(p.join(profileFolder(), 'Recordings')).listSync(),
          isEmpty,
        );
      });

      testWidgets('a copy missing from the profile does not stop the day and '
          'says so${polish ? ' (Polish)' : ''}', (tester) async {
        final locale = polish ? const Locale('pl') : null;
        final today = (await tester.runAsync(
          () => savedDay('today', todayLaps()),
        ))!;
        final shelf = library();
        addTearDown(shelf.dispose);
        await tester.runAsync(shelf.load);
        await openCompare(
          tester,
          today,
          shelf,
          picks: [friend()],
          locale: locale,
        );
        await tapKey(tester, 'referenceLoadFile');
        await settle(tester);
        await settle(tester);
        await tester.pumpWidget(const SizedBox());
        final copies = Directory(p.join(profileFolder(), 'Recordings'));
        copies.listSync().single.deleteSync();

        final next = (await tester.runAsync(() => reopened(today)))!;
        final shelf2 = library();
        addTearDown(shelf2.dispose);
        await tester.runAsync(shelf2.load);
        await openCompare(tester, next, shelf2, locale: locale);
        await settle(tester);
        expect(
          textOf(tester, 'referenceProblem'),
          polish
              ? startsWith(
                  'Zapis zapamiętany dla tego odniesienia nie został znaleziony',
                )
              : startsWith(
                  'The recording kept for this reference was not found',
                ),
        );
        expect(find.byKey(const ValueKey('referenceLabel')), findsNothing);
        // The day itself opened as usual.
        expect(find.byKey(const ValueKey('referenceLoadFile')), findsOneWidget);
        // The choice is still kept until the driver clears it.
        expect(shelf2.referenceOf(next.eventId), isNotNull);
        await tapKey(tester, 'referenceClear');
        await settle(tester);
        expect(shelf2.referenceOf(next.eventId), isNull);
      });

      testWidgets('a profile that cannot be written says the reference is not '
          'remembered${polish ? ' (Polish)' : ''}', (tester) async {
        final locale = polish ? const Locale('pl') : null;
        final today = (await tester.runAsync(
          () => savedDay('today', todayLaps()),
        ))!;
        Directory(p.join(profileFolder(), profileFileName)).createSync();
        File(p.join(profileFolder(), profileFileName, 'x'))
            .writeAsStringSync('x');
        final shelf = library();
        addTearDown(shelf.dispose);
        await tester.runAsync(shelf.load);
        await openCompare(
          tester,
          today,
          shelf,
          picks: [friend()],
          locale: locale,
        );
        await tapKey(tester, 'referenceLoadFile');
        await settle(tester);
        // The reference works while the day is open.
        expect(find.byKey(const ValueKey('referenceLabel')), findsOneWidget);
        expect(
          textOf(tester, 'referenceKeep'),
          polish
              ? 'Nie zapamiętano: Nie udało się zapisać Twojego profilu kierowcy. Odniesienie zostaje, dopóki ten dzień jest otwarty.'
              : 'Not remembered: Your driver profile could not be written. It stays while this day is open.',
        );
        expect(
          find.byKey(const ValueKey('referenceKeepRetry')),
          findsOneWidget,
        );
        expect(
          Directory(p.join(profileFolder(), 'Recordings')).listSync(),
          isEmpty,
          reason: 'the copy made for it was removed',
        );
      });
    }

    testWidgets('without a profile the reference lives while the day is open, '
        'and says so', (tester) async {
      final outcome = runDayImport((
        paths: [write('own/t.vbo', rectangleVbo(todayLaps(), pedals: true))],
        includeSubfolders: false,
      ));
      final controller = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
      );

      await tester.binding.setSurfaceSize(const Size(1200, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage.controller(
            controller: controller,
            pickers: _Pickers([friend()]),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('daySection-compare')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'referenceLoadFile');
      await settle(tester);
      expect(
        textOf(tester, 'referenceKeep'),
        startsWith('Kept while this day is open; not remembered'),
      );
    });
  });
}

/// A background task that never finishes until [done].
final class _Never implements BackgroundTask<ReferenceLoaded> {
  _Never(this.done);

  final Future<void> done;

  @override
  Future<ReferenceLoaded> get result async {
    await done;
    return const ReferenceLoaded.failed('never');
  }

  @override
  void cancel() {}
}
