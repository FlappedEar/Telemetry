// Ports VBOOverlay native/tests/RczTests.cpp (synthetic archives only).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'rcz_fixture.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('rcz_parser'));
  tearDown(() => temp.deleteSync(recursive: true));

  TelemetrySession parse(Uint8List bytes, {CancellationCheck? cancelled}) {
    final path = '${temp.path}/synthetic.rcz';
    File(path).writeAsBytesSync(bytes, flush: true);
    return RczParser.parseFile(path, cancelled: cancelled);
  }

  Uint8List replace(Uint8List bytes, String from, String to) {
    final source = utf8.decode(bytes);
    expect(source, contains(from));
    return text(source.replaceFirst(from, to));
  }

  for (final compressed in [false, true]) {
    test('native channels (${compressed ? 'deflated' : 'stored'})', () {
      final session = parse(zip(fixtureMembers(), compressed: compressed));
      expect(session.sampleCount, 5);
      expect(session.duration, 2.0);
      expect(session.startTime, (fixtureOrigin % 86400000) / 1000.0);
      expect(session.valueAt('speed', .2), 72.0);
      expect(session.valueAt('rpm', .25), 3000.0);
      expect(session.valueAt('rpm', .75), 4000.0);
      expect(session.valueAt('rpm', .2), isNull);
      expect(session.valueAt('heartRate', .15), 120.0);
      expect(session.valueAt('brake', .25), 0.0);
      expect(session.valueAt('x_acc-acc', .15), 1.0);
      expect(session.valueAt('latitude', .1), 50.0);
      expect(session.valueAt('longitude', .1), 20.0);
      expect(session.valueAt('lateralAcceleration', .15), isNull);
      expect(session.valueAt('longitudinalAcceleration', .15), isNull);
      expect(session.valueAt('speed', 1.0), isNull, reason: 'a gap is never bridged');
      expect(session.valueAt('speed', 2.0), 180.0);
      expect(session.channel('speed')!.unit, 'km/h');
      expect(session.metadata['format'], 'RaceChrono RCZ v1');
      expect(session.metadata['session'], 'Synthetic');
      expect(session.warnings.last, rczAccelerationNote);
      expect(session.timingGates, hasLength(1));
      final gate = session.timingGates.single;
      expect(gate.type, TimingGateType.start);
      expect(gate.endpointA.latitudeDegrees, greaterThan(50.0));
      expect(gate.endpointB.latitudeDegrees, lessThan(50.0));
      expect((gate.endpointB.longitudeDegrees - 20.0).abs(), lessThan(1e-8));
      expect(supportsRecordingPath('SESSION.RCZ'), isTrue);
    });
  }

  test('gaps get missing-value boundaries just inside the gap', () {
    final speed = parse(zip(fixtureMembers())).channel('speed')!;
    expect(speed.timestamps, hasLength(7));
    expect(speed.timestamps[4], greaterThan(.4));
    expect(speed.timestamps[4] - .4, lessThan(1e-12));
    expect(speed.timestamps[5], lessThan(2.0));
    expect(speed.values[4].isNaN && speed.values[5].isNaN, isTrue);
    for (var i = 1; i < speed.timestamps.length; ++i) {
      expect(speed.timestamps[i], greaterThan(speed.timestamps[i - 1]));
    }
  });

  test('channels of one clock share its timestamps', () {
    final session = parse(zip(fixtureMembers()));
    final latitude = session.channel('latitude')!, longitude = session.channel('longitude')!;
    expect(identical(latitude.timestamps, longitude.timestamps), isTrue);
    for (final channel in session.channels.values) {
      expect(channel.values, hasLength(channel.timestamps.length));
    }
    expect(session.channel('speed')!.values.where((value) => value.isNaN), hasLength(2));
  });

  test('prefers the accelerator pedal for throttle', () {
    final files = fixtureMembers()
      ..['channel_5_200_10025_1_1'] = ticks([250, 1250])
      ..['channel2_5_200_10025_10025_3'] = doubles([13.3, 80.4])
      ..['channel_5_200_10071_1_1'] = ticks([250, 1250])
      ..['channel2_5_200_10071_10071_3'] = doubles([0, 100]);
    final rcz = parse(zip(files));
    expect(rcz.aliases['throttle'], 'accelerator_pos-obd');
    expect(rcz.valueAt('throttle', .25), 0.0);
    expect((rcz.valueAt('throttle_pos-obd', .25)! - 13.3).abs(), lessThan(1e-4));
    files
      ..remove('channel_5_200_10071_1_1')
      ..remove('channel2_5_200_10071_10071_3');
    expect(parse(zip(files)).aliases['throttle'], 'throttle_pos-obd');
  });

  test('missing values and the declared primary GPS', () {
    final files = fixtureMembers()
      ..['channel_1_300_0_4_0'] = ints([10000, 0x7fffffff, 30000, 40000, 50000])
      ..['channel2_5_200_10024_10024_3'] = doubles([3000, double.infinity])
      // An undeclared GPS must not override the selected device.
      ..['channel_1_100_0_4_0'] = ints([999999]);
    final session = parse(zip(files));
    expect(session.valueAt('speed', .2), isNull);
    expect(session.valueAt('speed', .15), isNull);
    expect(session.valueAt('rpm', 1.25), isNull);
    expect(session.valueAt('speed', .3), 108.0);
    for (final channel in session.channels.values) {
      expect(channel.values.every((v) => v.isFinite || v.isNaN), isTrue);
    }
  });

  test('unknown channels are warned about and omitted', () {
    final files = fixtureMembers()
      ..['channel_9_1_0_1_1'] = ticks([100])
      ..['channel_9_1_0_77_0'] = ints([1]);
    final session = parse(zip(files));
    expect(session.warnings, contains('Unsupported recorded channel: channel_9_1_0_77_0'));
  });

  test('invalid gate metadata drops the gates and keeps the telemetry', () {
    final files = fixtureMembers()
      ..['trackId.json'] = text(
        '{"track":{"traps":[{"type":3,"uniDirectional":true,"centerLatitude":300000000,'
        '"centerLongitude":120000000,"width":0,"bearing":90000}]}}',
      );
    final session = parse(zip(files));
    expect(session.timingGates, isEmpty);
    expect(session.warnings.first, startsWith('RCZ: Invalid timing gate'));
    expect(session.valueAt('speed', .2), 72.0);

    files['trackId.json'] = text('{"track":{"traps":[{"type":1}]}}');
    expect(parse(zip(files)).warnings, contains('Unsupported timing gate ignored.'));
  });

  group('rejects invalid sessions:', () {
    final cases = <String, void Function(Map<String, Uint8List>)>{
      'version': (f) =>
          f['session.json'] = replace(f['session.json']!, '"version":1', '"version":2'),
      'origin': (f) => f['sessionfragment.json'] = replace(
        f['sessionfragment.json']!,
        '1780000000000',
        '1780000000001',
      ),
      'resumed': (f) => f['session.json'] = replace(
        f['session.json']!,
        '"laps":[]',
        '"laps":[{"sessionResume":1}]',
      ),
      'multiple': (f) => f['other/session.json'] = f['session.json']!,
      'missing': (f) => f.remove('channel_1_300_0_3_1'),
      'timestamps': (f) => f['channel_1_300_0_1_1'] = ticks([100, 200, 200, 400, 2000]),
      'length': (f) => f['channel_1_300_0_4_0'] = Uint8List.sublistView(
        f['channel_1_300_0_4_0']!,
        0,
        f['channel_1_300_0_4_0']!.length - 1,
      ),
      'encoding': (f) => f['channel_1_300_0_4_9'] = f.remove('channel_1_300_0_4_0')!,
      'ambiguous': (f) => f
        ..['channel_6_401_0_1_1'] = f['channel_6_400_0_1_1']!
        ..['channel_6_401_0_41_0'] = f['channel_6_400_0_41_0']!,
      'path': (f) => f['../session.json'] = f['session.json']!,
      'json': (f) => f['session.json'] = text('not JSON'),
      'deep-json': (f) => f['session.json'] = text('{"nested":${'[' * 26}0${']' * 26}}'),
      'malformed channel name': (f) => f['channel_1_x'] = ints([1]),
      'beyond 24 hours': (f) => f['channel_1_300_0_1_1'] = ticks([100, 200, 300, 400, 86400001]),
    };
    for (final MapEntry(key: kind, value: edit) in cases.entries) {
      test(kind, () {
        final files = fixtureMembers();
        edit(files);
        expect(() => parse(zip(files)), throwsA(isA<RczFormatError>()));
      });
    }
  });

  test('cancels while decoding', () {
    var checks = 0;
    expect(
      () => parse(zip(fixtureMembers()), cancelled: () => ++checks >= 30),
      throwsA(isA<OperationCancelled>()),
    );
    expect(checks, 30);
  });

  final realRcz = Platform.environment['FLAPPEDEAR_REAL_RCZ'];
  test('private real recording (FLAPPEDEAR_REAL_RCZ)', () {
    final session = RczParser.parseFile(realRcz!);
    final laps = deriveSourceLapSession(session);
    // Summary figures only: the recording itself is private.
    print(
      'channels=${session.channels.length} samples=${session.sampleCount} '
      'duration=${session.duration.toStringAsFixed(1)}s gates=${session.timingGates.length} '
      'warnings=${session.warnings.length} laps=${laps.timedLaps.length}',
    );
    expect(session.channel('speed'), isNotNull);
    expect(session.channel('latitude'), isNotNull);
  }, skip: realRcz == null ? 'FLAPPEDEAR_REAL_RCZ is not set' : false);
}
