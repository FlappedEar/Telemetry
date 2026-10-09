// Start-up reclaim of the recording copies Android makes (audit F11): the
// library wires the sweep to the profile's days, the other days folder and
// the recovery snapshot. Synthetic recordings.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../day/day_results_page_test.dart' show circuitVbo;
import '../support/temp_directory.dart';

void main() {
  late Directory directory;
  late String root;
  final old = DateTime.now().subtract(const Duration(days: 3));
  setUp(() {
    directory = Directory.systemTemp.createTempSync('owned_copies');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => deleteTemporaryDirectory(directory));

  String copy(String area, String batch, String name, String text) {
    final file = File(
      p.join(root, area, '${old.millisecondsSinceEpoch}-$batch', name),
    )..createSync(recursive: true);
    file.writeAsStringSync(text);
    file.setLastModifiedSync(old);
    return file.path;
  }

  Future<void> saveDay(String recording, String path) async {
    final plan = prepareTelemetryImport([recording]);
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
    Directory(p.dirname(path)).createSync(recursive: true);
    await saveDayDocument(
      path,
      dayDocument(
        eventId: newEventId(),
        name: 'Day',
        runs: runs,
        analysis: analysis,
        projectPath: path,
      ),
    );
  }

  ProfileLibrary library({
    Set<String> recovered = const {},
    bool readable = true,
    bool otherDaysKnown = true,
  }) => ProfileLibrary(
    store: FolderProfileStore(p.join(root, 'Profile')),
    defaultCarName: 'My car',
    defaultTrackName: (number) => 'Track $number',
    background: <R>(FutureOr<R> Function() computation) async => computation(),
    copyBatchFolders: () async => [
      p.join(root, 'incoming'),
      p.join(root, 'picked'),
    ],
    ownedRecordingFolders: () async => [
      p.join(root, 'incoming'),
      p.join(root, 'picked'),
    ],
    otherDayFolders: () async => otherDaysKnown
        ? [p.join(root, 'documents', 'Days')]
        : throw const FileSystemException('Documents not available'),
    recoveredRecordings: () async =>
        (recordings: recovered, readable: readable),
  );

  // The sweep waits behind the imports, then runs; [done] ends the wait.
  Future<void> started(ProfileLibrary library, [bool Function()? done]) async {
    await library.load();
    for (var i = 0; i < 100 && !(done?.call() ?? false); ++i) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (done == null && i == 19) break;
    }
  }

  test('start-up deletes copies no day and no recovery names', () async {
    final unused = copy('incoming', 'a', 'dup.vbo', circuitVbo([30, 28, 31]));
    final rejected = copy('picked', 'b', 'bad.rcz', 'not an archive');
    final inProfile = copy('picked', 'c', 'p.vbo', circuitVbo([29, 32, 33]));
    final inOther = copy('picked', 'd', 'o.vbo', circuitVbo([31, 30, 29]));
    final recovering = copy('incoming', 'e', 'r.vbo', 'restored day');
    await saveDay(inProfile, p.join(root, 'Profile', 'Days', 'p.fetproject'));
    await saveDay(inOther, p.join(root, 'documents', 'Days', 'o.fetproject'));

    await started(
      library(recovered: {recovering}),
      () => !File(unused).existsSync() && !File(rejected).existsSync(),
    );

    expect(File(unused).existsSync(), isFalse);
    expect(File(rejected).existsSync(), isFalse);
    for (final kept in [inProfile, inOther, recovering]) {
      expect(File(kept).existsSync(), isTrue, reason: kept);
    }
  });

  test('deleting a day keeps the copies another folder\'s day, or the '
      'recovery snapshot, still uses', () async {
    final shared = copy('picked', 'a', 'shared.vbo', circuitVbo([30, 28, 31]));
    final restored = copy('picked', 'b', 'r.vbo', circuitVbo([29, 32, 33]));
    final alone = copy('picked', 'c', 'x.vbo', circuitVbo([31, 30, 29]));
    await saveDay(shared, p.join(root, 'Profile', 'Days', 'p.fetproject'));
    await saveDay(shared, p.join(root, 'documents', 'Days', 'o.fetproject'));
    await saveDay(restored, p.join(root, 'Profile', 'Days', 'q.fetproject'));
    await saveDay(alone, p.join(root, 'Profile', 'Days', 'r.fetproject'));
    final days = library(recovered: {restored});
    await days.load();
    final profile = days.profile!;
    for (final day in profile.days) {
      await days.deleteDay(day.eventId);
    }
    expect(File(shared).existsSync(), isTrue, reason: 'used by another folder');
    expect(File(restored).existsSync(), isTrue, reason: 'recovery names it');
    expect(File(alone).existsSync(), isFalse);
  });

  test('days saved elsewhere that cannot be listed stop the sweep and keep '
      'the copies of a deleted day', () async {
    final unused = copy('incoming', 'a', 'dup.vbo', circuitVbo([30, 28, 31]));
    final inProfile = copy('picked', 'c', 'p.vbo', circuitVbo([29, 32, 33]));
    await saveDay(inProfile, p.join(root, 'Profile', 'Days', 'p.fetproject'));
    final days = library(otherDaysKnown: false);
    await started(days);
    expect(File(unused).existsSync(), isTrue);
    await days.deleteDay(days.profile!.days.single.eventId);
    expect(File(inProfile).existsSync(), isTrue);
  });

  test('a recovery snapshot that cannot be read stops the sweep', () async {
    final unused = copy('incoming', 'a', 'dup.vbo', circuitVbo([30, 28, 31]));
    await started(library(readable: false));
    expect(File(unused).existsSync(), isTrue);
  });
}
