import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry_core/telemetry_core.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('import_runner'));
  // On Windows a cancelled job's killed isolate can still hold a recording
  // open for a moment, and an open file cannot be deleted there.
  tearDown(() async {
    for (var attempt = 1; ; attempt++) {
      try {
        directory.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        if (attempt == 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  const vbo =
      '[header]\ncoordinate units = degrees\n[column names]\ntime latitude longitude velocity\n'
      '[data]\n0 50 20 72\n1 50.001 20.001 80\n';

  test('runs the scan and the plan in a background isolate', () async {
    File('${directory.path}/a.vbo').writeAsStringSync(vbo);
    final progress = <(int, int)>[];
    final job = const IsolateDayImporter().start((
      paths: [directory.path],
      includeSubfolders: false,
    ), (processed, total) => progress.add((processed, total)));
    final outcome = await job.result;
    expect(outcome.plan!.runs, hasLength(1));
    expect(outcome.plan!.runs.single.telemetry.valueAt('speed', 0), 72.0);
    expect(progress.last, (1, 1));
  });

  test(
    'cancel completes with OperationCancelled and delivers nothing',
    () async {
      File('${directory.path}/a.vbo').writeAsStringSync(vbo);
      final job = const IsolateDayImporter().start((
        paths: [directory.path],
        includeSubfolders: false,
      ), (_, _) {});
      job.cancel();
      await expectLater(job.result, throwsA(isA<OperationCancelled>()));
    },
  );
}
