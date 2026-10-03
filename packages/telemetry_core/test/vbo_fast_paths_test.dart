// The VBO parser's fast paths (FET-41) against the plain rules they replace:
// a regular expression and double.parse for numbers, scanRow for fields,
// and a sorted copy for the median interval.
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/src/vbo/vbo_row_scanner.dart';
import 'package:telemetry_core/src/vbo/vbo_text.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

final _decimal = RegExp(r'^[+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$');

double? _reference(String text) {
  final trimmed = trimSpace(text);
  return _decimal.hasMatch(trimmed) ? double.parse(trimmed) : null;
}

Matcher _same(double? expected) => predicate<double?>(
  (actual) => expected == null
      ? actual == null
      : actual != null && actual == expected && actual.isNegative == expected.isNegative,
  '$expected',
);

void main() {
  test('numbers read exactly as double.parse reads them', () {
    const spellings = [
      '0',
      '-0',
      '+0',
      '-0.000',
      '0.',
      '.5',
      '+.5',
      '-.5',
      '5.',
      '1e5',
      '1E+05',
      '1e-5',
      '123456789012345',
      '1234567890123456',
      '12345678901234567890',
      '0.1',
      '0.2',
      '0.3',
      '1.7976931348623157e308',
      '1e309',
      '-1e309',
      '4.9e-324',
      '1e-400',
      '1e22',
      '1e23',
      '9007199254740993',
      '0.000000000000000000001',
      '123.456e-30',
      ' 7.25 ',
      ' 3 ',
      '00012.5000',
      '1e',
      'e5',
      '.',
      '-',
      '+-1',
      '1.2.3',
      '0x10',
      'nan',
      'inf',
      '1,5',
      '',
      '1 2',
      '1e+',
      '12e1000000000',
      '-12e-1000000000',
    ];
    for (final text in spellings) {
      expect(parseDecimal(text), _same(_reference(text)), reason: '"$text"');
    }
    final random = Random(41);
    for (var i = 0; i < 20000; ++i) {
      final value = (random.nextDouble() - 0.5) * pow(10, random.nextInt(16) - 6);
      for (final text in [
        value.toStringAsFixed(random.nextInt(9)),
        '$value',
        value.toStringAsExponential(random.nextInt(17)),
      ]) {
        expect(parseDecimal(text), _same(_reference(text)), reason: '"$text"');
      }
    }
  });

  test('a range is read in place', () {
    expect(parseDecimalRange('a 12.5 b', 1, 6), 12.5);
    expect(parseDecimalRange('x-3e2y', 1, 5), -300.0);
    expect(parseDecimalRange('12', 1, 1), isNull);
  });

  test('row bounds split rows as scanRow does', () {
    const rows = [
      '1 2 3',
      '  1\t2   3  ',
      '1,2,3',
      ' 1 , 2 ,3 ',
      '1,,3,',
      ',',
      '1 2 3 4 5 6',
      '1,2,3,4,5,6',
      ' 1  2',
      '  1  , 2 ',
      'a b c d',
      '1\u000b2\u000c3',
    ];
    for (final row in rows) {
      for (final retained in [1, 3, 8]) {
        final expected = scanRow([row], retained, false, null);
        final bounds = RowBounds(retained)..scan(row, null);
        expect(bounds.count, expected.count, reason: '"$row"');
        expect(
          [
            for (var i = 0; i < bounds.retained; ++i)
              row.substring(bounds.starts[i], bounds.ends[i]),
          ],
          expected.cells,
          reason: '"$row"',
        );
      }
    }
  });

  test('row bounds refuse an overlong field', () {
    final long = '1' * (VboLimits.maximumFieldCharacters + 1);
    for (final row in ['$long 2', '2,$long', '3 4 $long']) {
      expect(() => scanRow([row], 1, false, null), throwsA(isA<ResourceLimitError>()));
      expect(() => RowBounds(1).scan(row, null), throwsA(isA<ResourceLimitError>()));
    }
    // Trailing white space of a comma field does not count.
    final padded = '${'1' * VboLimits.maximumFieldCharacters}${' ' * 10},2';
    expect(RowBounds(2)..scan(padded, null), isA<RowBounds>());
  });

  test('the median interval is the sorted middle', () {
    final random = Random(7);
    for (var trial = 0; trial < 300; ++trial) {
      final length = random.nextInt(60);
      final times = Float64List(length);
      var time = 0.0;
      for (var i = 0; i < length; ++i) {
        // Repeated intervals, ties and the occasional non-increasing step.
        time += [0.1, 0.1, 0.05, 0.2, 1.5, 0.0, -0.1][random.nextInt(7)];
        times[i] = time;
      }
      final intervals = [
        for (var i = 1; i < length; ++i)
          if (times[i] - times[i - 1] > 0) times[i] - times[i - 1],
      ]..sort();
      final expected = intervals.isEmpty ? 0.0 : intervals[intervals.length ~/ 2];
      final channel = TelemetryChannel(name: 'c', timestamps: times, values: Float32List(length));
      expect(channel.baseIntervalSeconds, expected);
      // A second channel on the same clock reads the same median.
      expect(
        TelemetryChannel(
          name: 'd',
          timestamps: times,
          values: Float32List(length),
        ).baseIntervalSeconds,
        expected,
      );
    }
  });
}
