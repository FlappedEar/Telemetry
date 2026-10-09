// A real day's route group keeps one id while its sessions are added one at
// a time, as at the track (FET-259). Set FLAPPEDEAR_REAL_DAY to a folder of
// one day's recordings; nothing from them is written anywhere, and only
// aggregates are printed.
import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test('sessions added one at a time keep the group id', () {
    final files =
        Directory(folder)
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.vbo'))
            .map((file) => file.path)
            .toList()
          ..sort();
    expect(files, hasLength(6));
    // Named and added in recording-time order, with their real content ids.
    final runs = nameRunsInRecordingOrder(prepareTelemetryImport(files).runs);
    expect(runs, hasLength(6));
    DayAnalysis? day;
    final ids = <String?>[];
    for (final (index, named) in runs.indexed) {
      day = extendDay(
        day,
        analyzeDayRuns(
          [
            DayRunInput(
              runId: named.run.id,
              name: named.name,
              contentSha256: named.run.contentSha256,
              session: named.run.telemetry,
              laps: named.run.laps,
            ),
          ],
          existingRuns: index,
          existingRows: day?.rows.length ?? 0,
        ),
      );
      ids.add(day.chosenGroupId);
    }
    final resolved = day!.groups.where((group) => group.resolved).toList();
    final laps = day.rows.where((row) => row.type == LapSectionType.lap).length;
    final best = formatLapTime(day.ranking!.bestOfDay!.durationSeconds, 3);
    print(
      '${runs.length} sessions, ${ids.toSet().length} group id(s) while adding, '
      '${resolved.length} group(s), $laps laps, best $best',
    );
    expect(ids, everyElement(isNotNull));
    expect(ids.toSet(), hasLength(1), reason: 'the group is never renamed');
    expect(resolved, hasLength(1));
    expect(resolved.single.id, ids.first);
    expect(laps, 25);
    expect(best, '1:49.898');
  }, skip: skip);
}
