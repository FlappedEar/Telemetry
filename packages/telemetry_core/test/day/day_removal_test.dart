import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

void main() {
  late Directory directory;
  late String root;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('day_removal');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  String write(String relative, String text) {
    final file = File(p.join(root, relative))..createSync(recursive: true);
    file.writeAsStringSync(text);
    return file.path;
  }

  /// A saved day of [paths]' recordings with each run's best lap excluded
  /// and compared, at [relative].
  Future<({String path, List<NamedRun> runs, Map<String, Object?> document})> saveDay(
    List<String> paths, {
    String relative = 'day.fetproject',
  }) async {
    final plan = prepareTelemetryImport(paths);
    final runs = nameRunsInRecordingOrder(plan.runs);
    final analysis = analyzeDay([
      for (final named in runs)
        DayRunInput(
          runId: named.run.id,
          name: named.name,
          contentSha256: named.run.contentSha256,
          session: named.run.telemetry,
          laps: named.run.laps,
        ),
    ]);
    final rows = [
      for (final named in runs)
        analysis.rows.firstWhere(
          (row) => row.runId == named.run.id && row.reference.type == LapSectionType.lap,
        ),
    ];
    final path = p.join(root, relative);
    Directory(p.dirname(path)).createSync(recursive: true);
    final document = dayDocument(
      eventId: newEventId(),
      name: 'Test day',
      runs: runs,
      analysis: analysis,
      exclusions: {for (final row in rows) row.reference: 'Traffic'},
      comparison: ComparisonDecisions(slots: [rows.first.reference, rows.last.reference]),
      projectPath: path,
    );
    await saveDayDocument(path, document);
    return (path: path, runs: runs, document: readDayDocument(path));
  }

  group('removeRunFromDayDocument', () {
    test('takes the run, its exclusions and its comparison lap out', () async {
      final day = await saveDay([
        write('a.vbo', circuitVbo([30, 28, 31])),
        write('b.vbo', circuitVbo([29, 32, 33])),
      ]);
      final removed = day.runs.last.run.id;
      final kept = day.runs.first.run.id;
      final event = day.document['event']! as Map<String, Object?>;
      event['activeRunId'] = removed;

      final next = removeRunFromDayDocument(day.document, removed);

      expect(fet.validateFetproject(next), isNull);
      expect(dayDocumentRunIds(next), [kept]);
      final nextEvent = next['event']! as Map<String, Object?>;
      expect(nextEvent['activeRunId'], kept);
      final exclusions = nextEvent['lapExclusions']! as List;
      expect(exclusions, hasLength(1));
      expect(((exclusions.single as Map)['reference'] as Map)['runId'], kept);
      final slots = (nextEvent['analysisDecisions']! as Map)['comparisonSlots']! as List;
      expect((slots.first as Map)['runId'], kept);
      expect(slots.last, isNull);
      final before = day.document['documentState']! as Map;
      final after = next['documentState']! as Map;
      expect(after['id'], before['id']);
      expect(after['savedRevision'], '2');
      // The document given is not changed.
      expect(dayDocumentRunIds(day.document), hasLength(2));

      // Saved and opened again, the day has only the session left.
      await saveDayDocument(day.path, next);
      final opened = openDay(day.path);
      expect([for (final named in opened.runs) named.run.id], [kept]);
      expect(opened.analysis!.rows.every((row) => row.runId == kept), isTrue);
      expect(opened.exclusions.keys.single.runId, kept);
    });

    test('refuses the only run and an unknown one', () async {
      final day = await saveDay([
        write('a.vbo', circuitVbo([30, 28, 31])),
      ]);
      expect(
        () => removeRunFromDayDocument(day.document, day.runs.single.run.id),
        throwsA(isA<RunNotRemoved>()),
      );
      expect(
        () => removeRunFromDayDocument(day.document, 'no-such-run'),
        throwsA(isA<RunNotRemoved>()),
      );
    });

    test('keeps unknown keys and the other runs as they were', () async {
      final day = await saveDay([
        write('a.vbo', circuitVbo([30, 28, 31])),
        write('b.vbo', circuitVbo([29, 32, 33])),
      ]);
      day.document['futureKey'] = {'x': 1};
      final event = day.document['event']! as Map<String, Object?>;
      ((event['runs']! as List).first as Map)['futureRunKey'] = 'kept';
      final next = removeRunFromDayDocument(day.document, day.runs.last.run.id);
      expect(next['futureKey'], {'x': 1});
      final run = ((next['event']! as Map)['runs']! as List).single as Map;
      expect(run['futureRunKey'], 'kept');
    });
  });

  group('deleteDayFiles', () {
    test('deletes the day and the copies only it uses', () async {
      final owned = p.join(root, 'support');
      final shared = write('support/incoming/1/a.vbo', circuitVbo([30, 28, 31]));
      final both = write('support/incoming/2/b.vbo', circuitVbo([29, 32, 33]));
      final mine = write('drive/c.vbo', circuitVbo([31, 30, 32]));
      final day = await saveDay([
        shared,
        both,
        mine,
      ], relative: 'support/Profile/Days/d1.fetproject');
      final other = await saveDay([both], relative: 'support/Profile/Days/d2.fetproject');

      final result = deleteDayFiles(
        dayPath: day.path,
        otherDayPaths: [day.path, other.path],
        ownedFolders: [owned],
      );

      expect(result.recordings, 1);
      expect(result.recordingsKept, 1);
      expect(File(day.path).existsSync(), isFalse);
      expect(File(shared).existsSync(), isFalse);
      // Its folder held only it.
      expect(Directory(p.dirname(shared)).existsSync(), isFalse);
      expect(File(both).existsSync(), isTrue);
      // The driver's own file stays.
      expect(File(mine).existsSync(), isTrue);
      expect(File(other.path).existsSync(), isTrue);
    });

    test('never deletes what is not a recording copy, whatever the day names', () async {
      final support = p.join(root, 'support');
      final profileFile = write('support/Profile/driver.feprofile', '{}');
      final otherDay = write('support/Profile/Days/other.fetproject', '{}');
      final copy = write('support/Profile/Recordings/a.vbo', circuitVbo([30, 28, 31]));
      final day = await saveDay([copy], relative: 'support/Profile/Days/d1.fetproject');
      // A crafted day: its sources name the profile and another day.
      final event = day.document['event']! as Map<String, Object?>;
      final run = (event['runs']! as List).single as Map<String, Object?>;
      final sources = (run['sources']! as Map)['telemetry']! as List;
      for (final (index, target) in [profileFile, otherDay].indexed) {
        final source = {...(sources.first as Map<String, Object?>)};
        source['id'] = 'crafted-$index';
        source['reference'] = {'absolutePath': target};
        sources.add(source);
      }
      File(day.path).writeAsStringSync(jsonEncode(day.document));
      expect(dayRecordingPaths(readDayDocument(day.path), day.path), hasLength(3));

      final result = deleteDayFiles(
        dayPath: day.path,
        otherDayPaths: const [],
        // Even when everything is said to be the app's own.
        ownedFolders: [support],
      );
      expect(result.recordings, 1);
      expect(File(copy).existsSync(), isFalse);
      expect(File(profileFile).existsSync(), isTrue);
      expect(File(otherDay).existsSync(), isTrue);
    });

    test('keeps every copy when another day cannot be read', () async {
      final copy = write('support/Profile/Recordings/a.vbo', circuitVbo([30, 28, 31]));
      final day = await saveDay([copy], relative: 'support/Profile/Days/d1.fetproject');
      final unreadable = write('support/Profile/Days/d2.fetproject', '{not json');
      final result = deleteDayFiles(
        dayPath: day.path,
        otherDayPaths: [unreadable],
        ownedFolders: [p.join(root, 'support/Profile/Recordings')],
      );
      expect(result.recordings, 0);
      expect(result.recordingsKept, 1);
      expect(File(copy).existsSync(), isTrue);
      expect(File(day.path).existsSync(), isFalse);
    });

    test('deletes a day that cannot be read without its recordings', () {
      final path = write('support/Profile/Days/broken.fetproject', '{');
      final result = deleteDayFiles(
        dayPath: path,
        otherDayPaths: const [],
        ownedFolders: [p.join(root, 'support')],
      );
      expect(result.recordings, 0);
      expect(File(path).existsSync(), isFalse);
    });
  });

  test('removeProfileDay leaves the other days, cars and tracks', () {
    final profile = DriverProfile(
      driverId: 'driver',
      cars: [ProfileCar(id: 'car', name: 'Car')],
      days: [
        ProfileDay(eventId: 'a', file: 'Days/a.fetproject', name: 'A', carId: 'car'),
        ProfileDay(eventId: 'b', file: 'Days/b.fetproject', name: 'B', carId: 'car'),
      ],
      lastCarId: 'car',
    );
    final next = removeProfileDay(profile, 'a');
    expect([for (final day in next.days) day.eventId], ['b']);
    expect(next.cars, profile.cars);
    expect(next.lastCarId, 'car');
    expect(identical(removeProfileDay(next, 'a'), next), isTrue);
  });

  test('a session added after one was removed gets a number no session has', () {
    final plan = prepareTelemetryImport([
      write('n.vbo', circuitVbo([30, 28, 31])),
    ]);
    final named = nameRunsInRecordingOrder(
      plan.runs,
      existingRuns: 2,
      takenNames: ['Session 1', 'Session 3'],
    );
    expect(named.single.name, 'Session 4');
    expect(nameRunsInRecordingOrder(plan.runs, existingRuns: 2).single.name, 'Session 3');
  });
}
