// Truth tests for rows that do not fit the header (FET-242, FET-271): a header
// with more names than most rows have values, or rows with more values than
// names, cannot be matched to the values, so the file is refused rather than
// read with the wrong column as its clock.
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

  Matcher refusedAsExtra() => throwsA(
    isA<VboParseError>().having(
      (error) => error.message,
      'message',
      contains('more values than its header has names'),
    ),
  );

  test('a few rows with extra values among normal ones still read, and warn', () {
    final session = parseVboFile(
      write('[column names]\ntime rpm\n[data]\n0.0 1\n0.1 2 9\n0.2 3\n'),
    );
    expect(session.channels['rpm']!.values, [1, 2, 3]);
    expect(session.warnings.where((warning) => warning.contains('extra')), hasLength(1));
  });

  test('header "time lat" with rows "1 0.0 5" is refused, not timed by the counter (FET-271)', () {
    // An unnamed counter column stands before the real time; its values
    // 1, 2, 3 would otherwise time the file at one sample a second.
    final path = write('[column names]\ntime lat\n[data]\n1 0.0 5\n2 0.1 6\n3 0.2 7\n');
    expect(() => parseVboFile(path), refusedAsExtra());
  });

  test('most rows with extra values are refused when the time column is first too', () {
    final path = write('[column names]\ntime rpm\n[data]\n0.0 1 9\n0.1 2 9\n');
    expect(() => parseVboFile(path), refusedAsExtra());
  });

  test('trailing separators leave empty extra fields, which are not extra values', () {
    final session = parseVboFile(
      write('[column names]\ntime,rpm\n[data]\n0.0,1,,\n0.1,2,,\n0.2,3,,\n'),
    );
    expect(session.channels['rpm']!.values, [1, 2, 3]);
  });

  test('a tie of rows with extra values and normal rows is read', () {
    final session = parseVboFile(write('[column names]\ntime rpm\n[data]\n0.0 1 9\n0.1 2\n'));
    expect(session.channels['rpm']!.values, [1, 2]);
  });

  test('a row dropped as a false midnight rollover is no evidence of the shape (FET-271)', () {
    // Kept: 213000 (normal) and 213002 (extra); the early-morning row between
    // them is dropped as no rollover, so the extra rows are a tie, not a majority.
    final session = parseVboFile(
      write('[column names]\ntime rpm\n[data]\n213000 1\n001500 2 9\n213002 3 9\n'),
    );
    expect(session.channels['rpm']!.values, [1, 3]);
  });

  test('a short row dropped as a false midnight rollover does not count either', () {
    // Kept: 213000 (full) and 213002 (full); the dropped row is short.
    final session = parseVboFile(
      write('[column names]\nrpm time brake\n[data]\n1 213000 0\n2 001500\n3 213002 0\n'),
    );
    expect(session.channels['rpm']!.values, [1, 3]);
  });

  test('extra values in rows skipped for their time do not count', () {
    final session = parseVboFile(
      write('[column names]\ntime rpm\n[data]\n0.0 1\nbad 2 9\nbad 3 9\n0.1 4\n'),
    );
    expect(session.channels['rpm']!.values, [1, 4]);
  });

  test('full rows skipped for their time do not outvote the short rows read', () {
    // Both full rows have an invalid time, so only the two short rows are
    // kept, and their "time" is the rpm column.
    final path = write(
      '[column names]\nspeed time rpm\n[data]\n0.0 10\n0.1 11\n50 bad 1000\n51 bad 2000\n',
    );
    expect(() => parseVboFile(path), refusedAsMismatch());
  });

  test('a tie of short and full rows with time not first is read', () {
    final session = parseVboFile(
      write('[column names]\nrpm time brake\n[data]\n1000 0.0 0\n2000 0.1\n'),
    );
    expect(session.channels['rpm']!.timestamps, [0.0, closeTo(0.1, 1e-9)]);
  });

  test('a single short row with time not first is refused', () {
    final path = write('[column names]\nrpm time brake\n[data]\n1000 0.0\n');
    expect(() => parseVboFile(path), refusedAsMismatch());
  });
}
