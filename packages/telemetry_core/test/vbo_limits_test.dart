import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'support/sessions.dart';

final _resourceLimit = throwsA(isA<ResourceLimitError>());

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('vbo-limits'));
  tearDown(() => directory.deleteSync(recursive: true));

  String write(String name, String text) {
    final file = File('${directory.path}/$name')..writeAsStringSync(text);
    return file.path;
  }

  test('rejects a file over 128 MiB before reading it', () {
    final file = File('${directory.path}/oversized.vbo')..createSync();
    final handle = file.openSync(mode: FileMode.write)
      ..truncateSync(VboLimits.maximumFileBytes + 1)
      ..closeSync();
    expect(handle, isNotNull);
    expect(() => parseVboFile(file.path), _resourceLimit);
  });

  test('rejects too many columns, rows and over-long fields', () {
    final names = [for (var c = 0; c <= VboLimits.maximumColumns; ++c) 'c$c'];
    final values = List.filled(names.length, '1');
    expect(
      () => parse('[column names]\n${names.join(' ')}\n[data]\n${values.join(' ')}'),
      _resourceLimit,
    );

    final rows = StringBuffer('[column names]\ntime speed\n[data]\n');
    for (var row = 0; row <= VboLimits.maximumDataRows; ++row) {
      rows.write('0 1\n');
    }
    expect(() => parse(rows.toString()), _resourceLimit);

    final longField = '1' * (VboLimits.maximumFieldCharacters + 1);
    expect(() => parse('[column names]\ntime speed\n[data]\n0 $longField'), _resourceLimit);
  });

  test('bounds header metadata and decoded values before allocation', () {
    final header = StringBuffer('[${'a' * 80000}]\n');
    for (var line = 0; line < 1500; ++line) {
      header.write('x\n');
    }
    header.write('[column names]\ntime speed\n[data]\n0 1\n1 2\n');
    expect(() => parseVboFile(write('long-section.vbo', header.toString())), _resourceLimit);

    final many = StringBuffer('[header]\n');
    for (var line = 0; line <= VboLimits.maximumMetadataEntries; ++line) {
      many.write('x\n');
    }
    many.write('[column names]\ntime speed\n[data]\n0 1\n');
    expect(() => parseVboFile(write('many-entries.vbo', many.toString())), _resourceLimit);

    final wide = StringBuffer('[column names]\n');
    for (var column = 0; column < 512; ++column) {
      wide.write('c$column ');
    }
    wide.write('\n[data]\n');
    for (var row = 0; row < 400000; ++row) {
      wide.write('1\n');
    }
    expect(() => parseVboFile(write('wide.vbo', wide.toString())), _resourceLimit);
  });

  test('bounds rows made mostly of separators', () {
    final separators = ',' * 200000;
    const prefix = '[column names]\ntime,speed\n[data]\n0,42';
    final parsed = parse(prefix + separators);
    expect(parsed.sampleCount, 1);
    expect(parsed.channels['speed']!.values, [42]);
    expect(parsed.warnings, ['Row 1: ignored 200000 extra value(s).']);
    // Ignored values still respect the field limit.
    expect(
      () => parse(prefix + separators + 'x' * (VboLimits.maximumFieldCharacters + 1)),
      _resourceLimit,
    );
    expect(() => parse('[column names]\n$separators\n[data]\n0'), _resourceLimit);
  });

  test('applies line, column and field limits at their exact boundaries', () {
    const valid = '[column names]\ntime speed\n[data]\n0 42';
    final comment = '#${'x' * (VboLimits.maximumLineCharacters - 1)}';
    expect(parse('$comment\r\n$valid').sampleCount, 1);
    expect(() => parse('${comment}x\n$valid'), _resourceLimit);
    // A final CR is content, unlike the CR of a CRLF.
    expect(() => parse('$valid\n$comment\r'), _resourceLimit);

    final emptyLines = '\n' * (VboLimits.maximumLines - 4);
    expect(parse(emptyLines + valid).sampleCount, 1);
    expect(() => parse('$emptyLines$valid\n'), _resourceLimit);

    final names = ['time', for (var i = 1; i < VboLimits.maximumColumns; ++i) 'c$i'];
    final values = ['0', for (var i = 1; i < VboLimits.maximumColumns; ++i) '1'];
    expect(
      parse('[column names]\n${names.join(' ')}\n[data]\n${values.join(' ')}').channels,
      hasLength(VboLimits.maximumColumns - 1),
    );

    final field = 'x' * VboLimits.maximumFieldCharacters;
    String header(String name) => '[column names]\ntime,speed,$name\n[data]\n0,42,1';
    expect(parse(header(field)).channels.containsKey(field), isTrue);
    expect(() => parse(header('${field}x')), _resourceLimit);

    // Trimming never turns harmless padding into an oversized field.
    final padding = ' ' * (VboLimits.maximumFieldCharacters + 1);
    expect(
      parse('[column names]\ntime,speed\n[data]\n0,${padding}42$padding,')
          .channels['speed']!
          .values[0],
      42.0,
    );
    expect(() => parse('[column names]\ntime,speed\n[data]\n0,4${padding}2'), _resourceLimit);

    // A comma field can span header lines.
    final half = 'x' * (VboLimits.maximumFieldCharacters ~/ 2);
    expect(() => parse('[column names]\ntime,$half\n$half\n[data]\n0,1'), _resourceLimit);
  });

  test('rejects an over-long section name', () {
    final name = 'a' * (VboLimits.maximumSectionNameCharacters + 1);
    expect(() => parse('[$name]\n[column names]\ntime a\n[data]\n0 1\n'), _resourceLimit);
  });

  test('caps warnings at 200 and counts the rest', () {
    final rows = StringBuffer('[column names]\ntime a b\n[data]\n');
    for (var row = 0; row < 250; ++row) {
      rows.write('$row 1\n');
    }
    final session = parse(rows.toString());
    expect(session.warnings, hasLength(201));
    expect(session.warnings.last, '… 50 additional parser warnings omitted.');
  });
}
