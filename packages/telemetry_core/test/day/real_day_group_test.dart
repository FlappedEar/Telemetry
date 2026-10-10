// A day recorded in both RaceChrono formats is one circuit (FET-250): the
// VBO and the RCZ of the owner's Jastrząb day of 29 August 2026 give one
// start-gate revision, so a day mixing the formats forms one route group
// whichever of the six sessions come as which. Set FLAPPEDEAR_REAL_DAY to a
// folder of that day's .vbo and .rcz files (FlappedEar/refdata); nothing from
// them is written anywhere.
import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

DayRunInput _run(String path, int index) {
  final session = loadRecording(path);
  final digest = '${index + 1}' * 64;
  return DayRunInput(
    runId: 'run:$digest',
    name: 'Session ${index + 1}',
    contentSha256: digest,
    session: session,
    laps: deriveSourceLapSession(session),
  );
}

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  List<String> recordings(String extension) =>
      (Directory(folder)
          .listSync()
          .whereType<File>()
          .map((file) => file.path)
          .where((path) => path.toLowerCase().endsWith(extension))
          .toList()
        ..sort());

  test('each session gives the same gate revision as a VBO and as an RCZ', () {
    final vbos = recordings('.vbo'), rczs = recordings('.rcz');
    expect(vbos, hasLength(6));
    expect(rczs, hasLength(6));
    final revisions = {
      for (final path in [...vbos, ...rczs]) sessionGateRevision(_run(path, 0).session),
    };
    expect(revisions, hasLength(1));
    expect(revisions.single, startsWith('gates-v2:'));
  }, skip: skip);

  test('sessions 1 to 3 as VBO and 4 to 6 as RCZ form one group, as the one-format days do', () {
    final vbos = recordings('.vbo'), rczs = recordings('.rcz');
    final day = analyzeDay([
      for (var index = 0; index < 3; ++index) _run(vbos[index], index),
      for (var index = 3; index < 6; ++index) _run(rczs[index], index),
    ]);
    final resolved = day.groups.where((group) => group.resolved).toList();
    expect(resolved, hasLength(1));
    expect(resolved.single.runIds, hasLength(6));
    expect(day.groups, hasLength(1));
    // The ranking is that of the days in one format (docs/kan79-full-day-acceptance.md).
    expect(day.ranking!.bestOfDay!.durationSeconds, closeTo(109.898, 0.001), reason: '1:49.898');
    final vboDay = analyzeDay([for (var i = 0; i < 6; ++i) _run(vbos[i], i)]);
    final rczDay = analyzeDay([for (var i = 0; i < 6; ++i) _run(rczs[i], i)]);
    // Session 2 is a VBO here, and its lap 3 is eligible there but not as an
    // RCZ (the formats time it differently; not a group matter).
    expect(day.ranking!.eligibleLapCount, vboDay.ranking!.eligibleLapCount);
    expect(vboDay.ranking!.eligibleLapCount - rczDay.ranking!.eligibleLapCount, 1);
    // The formats time a lap to within a millisecond of each other.
    for (final single in [vboDay, rczDay]) {
      expect(
        day.ranking!.bestOfDay!.durationSeconds,
        closeTo(single.ranking!.bestOfDay!.durationSeconds, 0.001),
      );
    }
  }, skip: skip);

  test('a day saved before, as two groups, moves both old ids to the one group', () {
    final vbos = recordings('.vbo'), rczs = recordings('.rcz');
    final runs = [for (var i = 0; i < 6; ++i) _run(i.isEven ? vbos[i] : rczs[i], i)];
    final day = analyzeDay(runs);
    final moved = legacyGroupIds(day, {for (final run in runs) run.runId: run.session});
    expect(moved.keys.toSet(), hasLength(2), reason: 'a group per format before');
    expect(moved.values.toSet(), {day.chosenGroupId});
  }, skip: skip);

  test('the VBO day, the RCZ day and the mixed day all have the same group id', () {
    final vbos = recordings('.vbo'), rczs = recordings('.rcz');
    String groupOf(List<DayRunInput> runs) => analyzeDay(runs).chosenGroupId!;
    final vboDay = groupOf([for (var i = 0; i < 6; ++i) _run(vbos[i], i)]);
    final rczDay = groupOf([for (var i = 0; i < 6; ++i) _run(rczs[i], i)]);
    final mixed = groupOf([for (var i = 0; i < 6; ++i) _run(i.isEven ? vbos[i] : rczs[i], i)]);
    expect(rczDay, vboDay);
    expect(mixed, vboDay);
  }, skip: skip);
}
