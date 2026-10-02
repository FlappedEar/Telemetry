import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'support/sessions.dart';

void main() {
  test('parses the realistic fixture', () {
    final session = parseVboFile('test/fixtures/basic.vbo');
    expect(session.sampleCount, 3);
    expect(session.duration, 1.0);
    expect(session.metadata['vehicle'], 'Test Car');
    expect(session.channels.containsKey('mystery'), isTrue);
    expect(session.aliases['speed'], 'velocity');
    expect(session.aliases['rpm'], 'rpm');
    expect(session.aliases['throttle'], 'throttle');
    expect(session.aliases['brake'], 'brake');
    expect(session.aliases['heartRate'], 'heart_rate');
    expect(session.channels['velocity']!.values, [0.0, 50.0, 100.0]);
  });

  test('reads clock times from the text before plain seconds', () {
    List<double> times(String rows) =>
        parse('[column names]\ntime speed\n[data]\n$rows').channels['speed']!.timestamps;
    expect(times('00:00:00.000 1\n00:00:00.100 2\n00:00:00.200 3'), _near([0.0, 0.1, 0.2]));
    expect(times('003059.500 1\n003100.500 2\n003101.500 3'), _near([0.0, 1.0, 2.0]));
    expect(times('091428.380 1\n091428.480 2\n091428.580 3'), _near([0.0, 0.1, 0.2]));
    expect(times('0 1\n0.1 2\n0.2 3\n10.5 4'), _near([0.0, 0.1, 0.2, 10.5]));
  });

  test('keeps timestamps strictly increasing across midnight and bad rows', () {
    final midnight = parse(
      '[column names]\ntime speed rpm\n[data]\n'
      '235959.800 1 10\n235959.900 2 20\n000000.000 3 30\n000000.100 4 40',
    );
    expect(midnight.channels['speed']!.timestamps, _near([0.0, 0.1, 0.2, 0.3]));
    expect(midnight.channels['rpm']!.timestamps, hasLength(4));
    expect(midnight.warnings.any((w) => w.contains('midnight rollover')), isTrue);

    final guarded = parse(
      '[column names]\ntime speed rpm\n[data]\n'
      '120000.000 1 10\n120000.100 2 20\n120000.100 3 30\n115959.900 4 40\n'
      '126199 5 50\n246000 6 60\n12:61:00 7 70\n12:00:60 8 80\n120000.200 9 90',
    );
    final speed = guarded.channels['speed']!;
    expect(speed.values, [1.0, 2.0, 9.0]);
    expect(guarded.channels['rpm']!.values, hasLength(3));
    expect(guarded.warnings.length, greaterThanOrEqualTo(6));
  });

  group('rejects derived times outside the 64-bit microsecond range', () {
    final boundary = 9223372036854775808.0 / 1000000.0;
    final rows = {
      'positive finite extreme': '1e308 1\n1.1e308 2',
      'negative finite extreme': '-1e308 1\n1e308 2',
      'elapsed exceeds microseconds': '-6000000000000 1\n6000000000000 2',
      'backward difference exceeds range': '6000000000000 1\n-6000000000000 2',
      'mixed clock and extreme relative': '23:59:59 1\n00:00:00 2\n1e308 3',
      'elapsed precision collapse': '-1000000000000 1\n0 2\n0.000001 3',
      'rounded-up int64 boundary': '0 1\n${boundary.toStringAsPrecision(17)} 2',
    };
    rows.forEach((name, data) {
      test(name, () {
        expect(
          () => parse('[column names]\ntime speed\n[data]\n$data'),
          throwsA(isA<VboParseError>()),
        );
      });
    });
  });

  test('keeps mixed clocks consistent across midnight', () {
    final session = parse(
      '[column names]\ntime speed rpm\n[data]\n'
      '23:59:59 10 100\n0 20 200\n00:00:00 30 300\n'
      '86401 40 400\n00:00:02 50 500\n00:00:02 60 600\n'
      '00:00:01 70 700\n00:00:03 80 800',
    );
    expect(session.duration, 4.0);
    expect(session.sampleCount, 5);
    expect(session.channels['speed']!.values, [10, 30, 40, 50, 80]);
    expect(session.channels['rpm']!.values, [100, 300, 400, 500, 800]);
    for (final channel in session.channels.values) {
      expect(channel.timestamps, [0, 1, 2, 3, 4]);
    }
    expect(session.warnings, hasLength(4)); // backward, rollover, duplicate, backward
  });

  test('names columns uniquely and never empty', () {
    final session = parse('[column names]\ntime,a,a,a (2),,b\n[data]\n0,1,2,3,4,5\n1,1,2,3,4,5\n');
    expect(session.channels, hasLength(5));
    expect(session.channels['a']!.values.first, 1.0);
    expect(session.channels['a (2)']!.values.first, 3.0); // the header's own "a (2)"
    expect(session.channels['a (3)']!.values.first, 2.0);
    expect(session.channels['column 5']!.values.first, 4.0);
    expect(session.channels['b']!.values.first, 5.0);
  });

  test('rejects more than one data or column-names section', () {
    expect(
      () => parse('[column names]\ntime speed\n[data]\n0 1\n[data2]\n0 9\n'),
      throwsA(isA<VboParseError>()),
    );
    expect(
      () => parse('[column names]\ntime speed\n[column names 2]\ntime rpm\n[data]\n0 1\n'),
      throwsA(isA<VboParseError>()),
    );
  });

  test('reads a file exactly as its text, with CRLF and lone CR', () {
    const mixed = '[column names]\r\ntime speed\r\n[data]\r\n0 1\r\n1 2\r3 4\n2 5\n';
    final directory = Directory.systemTemp.createTempSync('vbo');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/mixed.vbo')..writeAsStringSync(mixed);
    final fromFile = parseVboFile(file.path);
    final fromText = parse(mixed);
    expect(fromFile.channels['speed']!.values, fromText.channels['speed']!.values);
    expect(fromFile.channels['speed']!.timestamps, fromText.channels['speed']!.timestamps);
  });

  test('treats a value beyond the float range as no data', () {
    final values = parse('[column names]\ntime speed\n[data]\n0 1e39\n1 2\n2 -1e40\n')
        .channels['speed']!
        .values;
    expect(values, hasLength(3));
    expect(values[0].isNaN && values[2].isNaN, isTrue);
    expect(values[1], 2.0);
  });

  test('keeps comma and whitespace row formats', () {
    final comma = parse(
      '﻿# ignored\r\n[column names]\r\ntime, \'speed\',\r\n'
      'rpm, sensor name\r\n[data]\r\n0, 10, , 7, extra,\r\n'
      '1, 20, 200, 8\r\n2, 30\r\n',
    );
    expect(comma.sampleCount, 3);
    expect(comma.channels['speed']!.values, [10, 20, 30]);
    expect(comma.channels['speed']!.timestamps, [0, 1, 2]);
    final rpm = comma.channels['rpm']!.values;
    expect(rpm[0].isNaN && rpm[2].isNaN, isTrue);
    expect(rpm[1], 200.0);
    expect(comma.channels['sensor name']!.values[0], 7.0);
    expect(comma.warnings, ['Row 1: ignored 2 extra value(s).', 'Row 3: missing 2 value(s).']);

    final whitespace = parse(
      '[column names]\ntime\tspeed\nrpm\vsensor name\n[data]\n'
      '0\t10\v100\f7\n1 20\r200 8',
    );
    expect(whitespace.sampleCount, 2);
    expect(whitespace.channels['rpm']!.values, [100, 200]);
    expect(whitespace.channels['sensor name']!.values, [7, 8]);
    expect(whitespace.warnings, isEmpty);
  });

  test('prefers RaceChrono calculated acceleration', () {
    final session = parse(
      '[column names]\ntime latacc longacc latacc-calc longacc-calc\n[data]\n'
      '0 0 0 0.5 -0.75\n1 0 0 invalid nan\n2 0 0 -0.25 0.125\n',
    );
    expect(session.valueAt('lateralAcceleration', 0), 0.5);
    expect(session.valueAt('longitudinalAcceleration', 0), -0.75);
    expect(session.valueAt('latacc', 0), 0.0);
    expect(session.valueAt('lateralAcceleration', 1), isNull);
    expect(session.valueAt('longitudinalAcceleration', 1), isNull);
    expect(session.valueAt('lateralAcceleration', 2), -0.25);
    final calculatedOnly = parse(
      '[column names]\ntime latacc-calc longacc-calc\n[data]\n0 0.5 -0.75\n1 0.5 -0.75\n',
    );
    expect(calculatedOnly.valueAt('lateralAcceleration', 0), 0.5);
    expect(calculatedOnly.valueAt('longitudinalAcceleration', 0), -0.75);
  });

  test('points throttle at the accelerator pedal when it has data', () {
    final pedal = parse(
      '[column names]\ntime throttle accelerator_pedal\n[data]\n0 10 20\n1 11 21\n',
    );
    expect(pedal.aliases['throttle'], 'accelerator_pedal');
    final emptyPedal = parse(
      '[column names]\ntime throttle accelerator_pedal\n[data]\n0 10 x\n1 11 y\n',
    );
    expect(emptyPedal.aliases['throttle'], 'throttle');
  });

  test('never exposes NaN through valueAt and never bridges a missing sample', () {
    final session = parse('[column names]\ntime speed\n[data]\n0 10\n1 x\n2 30\n');
    expect(session.valueAt('speed', 0.5), isNull);
    expect(session.valueAt('speed', 1), isNull);
    expect(session.valueAt('speed', 0.5, InterpolationMode.previous), 10);
    expect(session.valueAt('speed', 1.6, InterpolationMode.nearest), 30);
    expect(session.valueAt('speed', 1.5, InterpolationMode.nearest), isNull); // tie: earlier
    expect(session.valueAt('speed', -0.1), isNull);
    expect(session.valueAt('speed', 2.1), isNull);
    expect(session.valueAt('speed', double.nan), isNull);
  });

  test('computes the gap threshold from the median interval', () {
    final regular = parse('[column names]\ntime a\n[data]\n0 1\n0.1 1\n0.2 1\n0.3 1\n0.4 1\n');
    expect(telemetryGapThreshold(regular.channels['a']!), closeTo(0.3, 1e-12));
    expect(telemetryGapThreshold(regular.channels['a']!, 0.75), 0.75);
    final sparse = parse('[column names]\ntime a\n[data]\n0 1\n0.5 1\n2 1\n3.5 1\n');
    expect(telemetryGapThreshold(sparse.channels['a']!), 4.5);
  });

  test('decodes damaged UTF-8 one replacement per byte of a broken prefix', () {
    final session = parseVboFile('test/parity/corpus/bad_utf8.vbo');
    expect(session.metadata['name'], 'café �� x��');
    expect(session.channels.keys, contains('a�'));
  });
}

Matcher _near(List<double> expected) =>
    pairwiseCompare<double, double>(expected, (e, a) => (a - e).abs() < 1e-6, 'within 1e-6 of');
