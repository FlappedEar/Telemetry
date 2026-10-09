import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

void main() {
  late Directory directory;
  late String root;
  final now = DateTime.utc(2026, 10, 9, 12);
  final old = now.subtract(const Duration(days: 3));
  setUp(() {
    directory = Directory.systemTemp.createTempSync('owned_sweep');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  // A copy the way MainActivity.copyBatch makes it: files/<area>/<batch>/<name>.
  String copy(String area, String batch, String name, String text, {DateTime? at}) {
    final made = at ?? old;
    final file = File(p.join(root, area, '${made.millisecondsSinceEpoch}-$batch', name))
      ..createSync(recursive: true);
    file.writeAsStringSync(text);
    file.setLastModifiedSync(made);
    return file.path;
  }

  Future<String> saveDay(String recording, String relative) async {
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
    final path = p.join(root, relative);
    Directory(p.dirname(path)).createSync(recursive: true);
    await saveDayDocument(
      path,
      dayDocument(
        eventId: newEventId(),
        name: 'Test day',
        runs: runs,
        analysis: analysis,
        projectPath: path,
      ),
    );
    return path;
  }

  int sweep({List<String> days = const [], List<String> keep = const [], DateTime? at}) =>
      sweepOwnedRecordingFolders(
        folders: [p.join(root, 'incoming'), p.join(root, 'picked')],
        dayPaths: days,
        keep: keep,
        now: at ?? now,
      );

  test('deletes unused old copies and their emptied folders only', () async {
    final used = copy('picked', 'b1', 'used.vbo', circuitVbo([30, 28, 31]));
    final day = await saveDay(used, 'Days/day.fetproject');
    final duplicate = copy('incoming', 'b2', 'dup.vbo', circuitVbo([30, 28, 31]));
    final rejected = copy('incoming', 'b3', 'broken.rcz', 'not an archive');
    final stub = copy('picked', 'b4', 'notes.txt', '');
    final text = copy('picked', 'b5', 'notes.txt', 'keep me');
    final loose = File(p.join(root, 'incoming', 'loose.vbo'))..writeAsStringSync('x');
    loose.setLastModifiedSync(old);

    expect(sweep(days: [day]), 3);

    expect(File(used).existsSync(), isTrue);
    expect(File(duplicate).existsSync(), isFalse);
    expect(File(rejected).existsSync(), isFalse);
    expect(File(stub).existsSync(), isFalse);
    expect(Directory(p.dirname(duplicate)).existsSync(), isFalse);
    // Not a recording and not empty, and not in a batch folder: left alone.
    expect(File(text).existsSync(), isTrue);
    expect(loose.existsSync(), isTrue);
    expect(Directory(p.dirname(used)).existsSync(), isTrue);
  });

  test('keeps a copy any day or the recovery snapshot names, and a new one', () async {
    final a = copy('picked', 'a', 'a.vbo', circuitVbo([30, 28, 31]));
    final b = copy('picked', 'b', 'b.vbo', circuitVbo([29, 32, 33]));
    final recovering = copy('incoming', 'c', 'c.vbo', 'restored');
    final fresh = copy(
      'incoming',
      'd',
      'd.vbo',
      'just shared',
      at: now.subtract(const Duration(hours: 2)),
    );
    // A day in another folder than the profile's still counts.
    final elsewhere = await saveDay(b, 'documents/Days/other.fetproject');
    expect(sweep(days: [elsewhere], keep: [recovering]), 1);
    expect(File(a).existsSync(), isFalse);
    for (final kept in [b, recovering, fresh]) {
      expect(File(kept).existsSync(), isTrue, reason: kept);
    }
    // The fresh one goes once it is old enough.
    expect(sweep(days: [elsewhere], keep: [recovering], at: now.add(const Duration(days: 2))), 1);
    expect(File(fresh).existsSync(), isFalse);
  });

  test('an unreadable day stops the sweep before anything is deleted', () {
    final copyPath = copy('picked', 'a', 'a.vbo', circuitVbo([30, 28, 31]));
    final broken = p.join(root, 'Days', 'broken.fetproject');
    File(broken)
      ..createSync(recursive: true)
      ..writeAsStringSync('{broken');
    expect(sweep(days: [broken]), 0);
    expect(File(copyPath).existsSync(), isTrue);
  });

  test('a day whose file is gone names nothing and does not stop the sweep', () {
    final copyPath = copy('picked', 'a', 'a.vbo', circuitVbo([30, 28, 31]));
    expect(sweep(days: [p.join(root, 'Days', 'gone.fetproject')]), 1);
    expect(File(copyPath).existsSync(), isFalse);
  });

  test('a folder still being filled is not removed, an old empty one is', () {
    final fresh = Directory(p.join(root, 'picked', '${now.millisecondsSinceEpoch}-new'))
      ..createSync(recursive: true);
    final stale = Directory(p.join(root, 'picked', '${old.millisecondsSinceEpoch}-empty'))
      ..createSync(recursive: true);
    expect(sweep(), 0);
    expect(fresh.existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);
    // No folders at all is fine.
    expect(
      sweepOwnedRecordingFolders(folders: [p.join(root, 'nothing')], dayPaths: const [], now: now),
      0,
    );
  });
}
