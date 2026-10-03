// The background task in its own isolate, as the app runs it outside
// `flutter test` (FET-54). Synthetic recordings only.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_page_test.dart' show circuitVbo;
import '../support/temp_directory.dart';

int _double(int value, CancellationCheck cancelled) => value * 2;

int _formatError(String text, CancellationCheck cancelled) =>
    throw FormatException('Not a number', text);

int _stateError(Object? _, CancellationCheck cancelled) =>
    throw StateError('Out of memory');

int _forever(Object? _, CancellationCheck cancelled) {
  while (true) {
    sleep(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('background'));
  tearDown(() => deleteTemporaryDirectory(directory));

  test('a job returns its result from another isolate', () async {
    expect(await runInIsolate(_double, 21).result, 42);
  });

  test('a job that throws fails with BackgroundTaskFailed', () async {
    await expectLater(
      runInIsolate(_formatError, 'x').result,
      throwsA(
        isA<BackgroundTaskFailed>().having(
          (failed) => failed.message,
          'message',
          contains('Not a number'),
        ),
      ),
    );
    await expectLater(
      runInIsolate(_stateError, null).result,
      throwsA(
        isA<BackgroundTaskFailed>().having(
          (failed) => failed.message,
          'message',
          contains('Out of memory'),
        ),
      ),
    );
  });

  test('a job that cannot be sent fails instead of throwing', () async {
    final port = ReceivePort();
    addTearDown(port.close);
    // A closure carrying a port, as one made in a widget's method carries
    // the widget's state.
    final task = runInIsolate(
      (Object? _, CancellationCheck cancelled) => port.hashCode,
      null,
    );
    await expectLater(task.result, throwsA(isA<BackgroundTaskFailed>()));
  });

  test('a cancelled job is stopped', () async {
    final task = runInIsolate(_forever, null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    task.cancel();
    await expectLater(task.result, throwsA(isA<OperationCancelled>()));
  });

  test(
    'a saved day opens again in another isolate; a corrupt one fails',
    () async {
      final outcome = runDayImport((
        paths: [
          (File(
            '${directory.path}/a.vbo',
          )..writeAsStringSync(circuitVbo([30, 28, 31]))).path,
        ],
        includeSubfolders: false,
      ));
      final path = '${directory.path}/Day.fetproject';
      await saveDayDocument(
        path,
        dayDocument(
          eventId: newEventId(),
          name: 'Track day',
          runs: outcome.runs,
          analysis: outcome.analysis!,
          projectPath: path,
        ),
      );
      final day = await runInIsolate(reopenDay, path).result;
      expect(day.runs, hasLength(1));
      expect(day.analysis, isNotNull);

      File(path).writeAsStringSync('{not json');
      await expectLater(
        runInIsolate(reopenDay, path).result,
        throwsA(isA<BackgroundTaskFailed>()),
      );
      File(path).deleteSync();
      await expectLater(
        runInIsolate(reopenDay, path).result,
        throwsA(isA<BackgroundTaskFailed>()),
      );
    },
  );
}
