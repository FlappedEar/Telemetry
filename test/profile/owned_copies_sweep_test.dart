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
  }) => ProfileLibrary(
    store: FolderProfileStore(p.join(root, 'Profile')),
    defaultCarName: 'My car',
    defaultTrackName: (number) => 'Track $number',
    background: <R>(FutureOr<R> Function() computation) async => computation(),
    copyBatchFolders: () async => [
      p.join(root, 'incoming'),
      p.join(root, 'picked'),
    ],
    otherDayFolders: () async => [p.join(root, 'documents', 'Days')],
    recoveredRecordings: () async =>
        (recordings: recovered, readable: readable),
  );

  // The sweep waits behind the imports, then runs; [done] ends the wait.
  Future<void> started(ProfileLibrary library, [bool Function()? done]) async {
    await library.load();
    for (var i = 0; i < 100 && !(done?.call() ?? false); ++i) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (done == null && i == 5) break;
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

  test('a recovery snapshot that cannot be read stops the sweep', () async {
    final unused = copy('incoming', 'a', 'dup.vbo', circuitVbo([30, 28, 31]));
    await started(library(readable: false));
    expect(File(unused).existsSync(), isTrue);
  });
}
