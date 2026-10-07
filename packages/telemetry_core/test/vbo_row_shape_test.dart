// Truth tests for rows that do not fit the header (FET-242): a header with
// more names than any row has values cannot be matched to the values, so the
// file is refused rather than read with the wrong column as its clock.
import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('fet242'));
  tearDown(() => directory.deleteSync(recursive: true));

  String write(String text) {
    final file = File('${directory.path}/t.vbo')..writeAsStringSync(text);
    return file.path;
  }

  Matcher refusedAsMismatch() => throwsA(
    isA<VboParseError>().having(
      (error) => error.message,
      'message',
      contains('time column cannot be found'),
    ),
  );

  test('header "UTC time rpm" with rows "0.0 1" is refused, not read with rpm as time', () {
    // The header splits on spaces: utc, time, rpm (3 names); rows have 2 values.
    final path = write('[column names]\nUTC time rpm\n[data]\n0.0 1\n0.1 2\n0.2 3\n');
    expect(() => parseVboFile(path), refusedAsMismatch());
  });

  test('a header with more names than any row has values is refused', () {
    final path = write('[column names]\nspeed time rpm brake\n[data]\n50 0.0 1000\n51 0.1 2000\n');
    expect(() => parseVboFile(path), refusedAsMismatch());
  });

  test('time first, rows short of trailing values: read, with the missing values warned about', () {
    final session = parseVboFile(
      write('[column names]\ntime rpm brake speed\n[data]\n0.0 1000 0\n0.1 2000 10\n'),
    );
    expect(session.channels['rpm']!.timestamps, [0.0, closeTo(0.1, 1e-9)]);
    expect(session.warnings.any((warning) => warning.contains('missing 1 value')), isTrue);
  });

  test('the refusal reaches the import as a file error, not an unexpected one', () {
    final path = write('[column names]\nrpm time brake\n[data]\n1000 0.0\n2000 0.1\n');
    final plan = prepareTelemetryImport([path]);
    expect(plan.runs, isEmpty);
    expect(plan.files.single.status, TelemetryImportFileStatus.error);
    expect(plan.files.single.message, contains('time column cannot be found'));
    expect(plan.files.single.message, isNot(startsWith(unexpectedFileError)));
  });

  test('a few short rows among full ones keep the good rows and warn', () {
    final path = write(
      '[column names]\ntime rpm brake\n[data]\n'
      '0.0 1000 0\n0.1 2000\n0.2 3000 20\n0.3 4000 30\n',
    );
    final session = parseVboFile(path);
    expect(session.channels['rpm']!.values, [1000, 2000, 3000, 4000]);
    expect(session.channels['brake']!.values.where((value) => value.isFinite), hasLength(3));
    expect(session.warnings.any((warning) => warning.contains('missing 1 value')), isTrue);
  });

  test('a normal file is unaffected and has no warnings', () {
    final session = parseVboFile(
      write('[column names]\ntime rpm brake\n[data]\n0.0 1000 0\n0.1 2000 10\n'),
    );
    expect(session.channels['rpm']!.timestamps, [0.0, closeTo(0.1, 1e-9)]);
    expect(session.warnings, isEmpty);
  });

  test('rows with extra values still read', () {
    final session = parseVboFile(write('[column names]\ntime rpm\n[data]\n0.0 1 9\n0.1 2 9\n'));
    expect(session.channels['rpm']!.values, [1, 2]);
  });
}
