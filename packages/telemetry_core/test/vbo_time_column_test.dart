// Truth tests for VBO timing (FET-203): rows are placed in time only by a
// time column the file declares, never by a made-up clock.
import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('fet203'));
  tearDown(() => directory.deleteSync(recursive: true));

  String write(String name, String text) {
    final file = File('${directory.path}/$name')..writeAsStringSync(text);
    return file.path;
  }

  const rows = '[data]\n0.0 1000 0\n0.1 2000 10\n0.2 3000 20\n';

  test('a VBO with no time column is refused, not timed one row a second', () {
    final path = write('no-time.vbo', '[column names]\nrpm brake\n[data]\n1000 0\n2000 10\n');
    expect(
      () => parseVboFile(path),
      throwsA(
        isA<VboParseError>().having(
          (error) => error.message,
          'message',
          contains('no time column'),
        ),
      ),
    );
  });

  test('a time column under an unknown name is refused too', () {
    for (final name in ['t', 'secs', 'zeit', 'elapsed']) {
      final path = write('$name.vbo', '[column names]\n$name rpm brake\n$rows');
      expect(() => parseVboFile(path), throwsA(isA<VboParseError>()), reason: name);
    }
  });

  test('the known time column names are read', () {
    for (final name in ['time', 'Time', 'TIMESTAMP', 'utc_time', 'utctime']) {
      final session = parseVboFile(write('ok.vbo', '[column names]\n$name rpm brake\n$rows'));
      expect(session.channels['rpm']!.timestamps, [0.0, closeTo(0.1, 1e-9), closeTo(0.2, 1e-9)]);
      expect(session.duration, closeTo(0.2, 1e-9), reason: name);
    }
  });

  test('importing a VBO with no time column reports a file error', () {
    final path = write('no-time.vbo', '[column names]\nrpm brake\n[data]\n1000 0\n2000 10\n');
    final plan = prepareTelemetryImport([path]);
    expect(plan.runs, isEmpty);
    expect(plan.files.single.status, TelemetryImportFileStatus.error);
    expect(plan.files.single.message, contains('no time column'));
    expect(plan.files.single.message, isNot(startsWith(unexpectedFileError)));
  });
}
