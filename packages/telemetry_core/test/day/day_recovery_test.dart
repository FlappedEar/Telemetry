import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

void main() {
  late Directory directory;
  late String root;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('day_recovery');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  String write(String relative, String text) {
    final file = File(p.join(root, relative))..createSync(recursive: true);
    file.writeAsStringSync(text);
    return file.path;
  }

  ({List<NamedRun> runs, DayAnalysis analysis}) importDay(List<String> paths) {
    final runs = nameRunsInRecordingOrder(prepareTelemetryImport(paths).runs);
    return (
      runs: runs,
      analysis: analyzeDay([
        for (final named in runs)
          DayRunInput(
            runId: named.run.id,
            name: named.name,
            contentSha256: named.run.contentSha256,
            session: named.run.telemetry,
            laps: named.run.laps,
          ),
      ]),
    );
  }

  test('an unsaved day is written, read back and opened with its exclusion', () async {
    final a = write('recordings/a.vbo', circuitVbo([30, 28, 31]));
    final day = importDay([a]);
    final best = day.analysis.ranking!.bestOfDay!;
    final exclusions = {best.reference: 'Traffic'};
    final analysis = regroupDay(day.analysis, manualTracks: const {}, exclusions: exclusions);
    final path = p.join(root, 'app', 'day-recovery.json');
    final eventId = newEventId();
    final document = dayDocument(
      eventId: eventId,
      name: 'Unsaved',
      runs: day.runs,
      analysis: analysis,
      exclusions: exclusions,
      projectPath: path,
    );
    final time = DateTime.utc(2026, 10, 3, 6, 30);
    await writeDayRecovery(
      path,
      DayRecovery(document: document, originalPath: '', basePath: path, timestamp: time),
    );
    expect(Directory(p.dirname(path)).listSync(), hasLength(1));

    final recovery = readDayRecovery(path)!;
    expect(recovery.eventId, eventId);
    expect(recovery.name, 'Unsaved');
    expect(recovery.originalPath, isEmpty);
    expect(recovery.timestamp, time);
    final opened = openRecoveredDay(recovery);
    expect(opened.missing, isEmpty);
    expect(opened.exclusions, {best.reference: 'Traffic'});
    expect(opened.analysis!.ranking!.bestOfDay!.reference, isNot(best.reference));

    await clearDayRecovery(path);
    expect(readDayRecovery(path), isNull);
    await clearDayRecovery(path);
  });

  test('refuses files it did not write', () {
    List<int> bytes(Object value) => utf8.encode(jsonEncode(value));
    expect(() => decodeDayRecovery(utf8.encode('{')), throwsA(isA<FetprojectError>()));
    expect(
      () => decodeDayRecovery(
        bytes({'recoveryVersion': 2, 'dirty': true, 'project': <String, Object?>{}}),
      ),
      throwsA(isA<FetprojectError>()),
    );
    expect(
      () => decodeDayRecovery(
        bytes({
          'kind': 'flappedear-telemetry-day-recovery',
          'recoveryVersion': 1,
          'timestamp': '2026-10-03T06:30:00.000Z',
          'originalProjectPath': '',
          'basePath': '/x/day-recovery.json',
          'project': {'version': 3},
        }),
      ),
      throwsA(isA<FetprojectError>()),
    );
  });
}
