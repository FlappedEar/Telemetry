// Truth tests for TelemetryChannel (FET-202): a channel cannot be built
// malformed and cannot change once built.
import 'dart:typed_data';

import 'package:telemetry_core/src/telemetry_session.dart' show adoptChannelTimestamps;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'support/sessions.dart';

TelemetryChannel _channel(List<double> times, List<double> values) => TelemetryChannel(
  name: 'c',
  timestamps: Float64List.fromList(times),
  values: Float32List.fromList(values),
);

void main() {
  test('a channel copies what it is given, so later changes do not reach it', () {
    final times = Float64List.fromList([0.0, 0.1, 0.2, 0.3]);
    final values = Float32List.fromList([1, 2, 3, 4]);
    final channel = TelemetryChannel(name: 'c', timestamps: times, values: values);
    final interval = channel.baseIntervalSeconds;
    times[1] = 5.0;
    times[2] = 6.0;
    values[0] = 99;
    expect(channel.timestamps, [0.0, 0.1, 0.2, 0.3]);
    expect(channel.values.first, 1.0);
    expect(channel.baseIntervalSeconds, interval);
    expect(telemetryValueAt(channel, 0.15), closeTo(2.5, 1e-6));
  });

  test('a channel cannot be changed through its lists', () {
    final channel = _channel([0.0, 0.1], [1, 2]);
    expect(() => channel.timestamps[0] = 1.0, throwsUnsupportedError);
    expect(() => channel.values[0] = 1.0, throwsUnsupportedError);
    expect(() => channel.timestamps.sort(), throwsUnsupportedError);
  });

  test('a malformed channel cannot be built', () {
    expect(() => _channel([0.0, 0.1], [1]), throwsArgumentError);
    expect(() => _channel([0.0, 0.1, 0.1], [1, 2, 3]), throwsArgumentError);
    expect(() => _channel([0.0, 0.2, 0.1], [1, 2, 3]), throwsArgumentError);
    expect(() => _channel([0.0, double.nan], [1, 2]), throwsArgumentError);
    expect(() => _channel([double.negativeInfinity, 0.0], [1, 2]), throwsArgumentError);
    expect(() => _channel([0.0, double.infinity], [1, 2]), throwsArgumentError);
    // NaN values are missing data and allowed; so is an empty channel.
    expect(_channel([0.0, 0.1], [double.nan, 2]).values.first, isNaN);
    expect(_channel([], []).sampleCount, 0);
  });

  test('channels on one adopted clock share it without a copy', () {
    final clock = adoptChannelTimestamps(Float64List.fromList([0.0, 0.1, 0.3, 0.4]));
    final a = TelemetryChannel(
      name: 'a',
      timestamps: clock,
      values: Float32List.fromList([1, 2, 3, 4]),
    );
    final b = TelemetryChannel(
      name: 'b',
      timestamps: clock,
      values: Float32List.fromList([5, 6, 7, 8]),
    );
    expect(identical(a.timestamps, clock), isTrue);
    expect(identical(b.timestamps, clock), isTrue);
    expect(a.baseIntervalSeconds, b.baseIntervalSeconds);
    expect(() => clock[0] = 1.0, throwsUnsupportedError);
    // An adopted clock is still checked.
    expect(
      () => TelemetryChannel(
        name: 'bad',
        timestamps: adoptChannelTimestamps(Float64List.fromList([0.0, 0.0])),
        values: Float32List(2),
      ),
      throwsArgumentError,
    );
  });

  test('parsed recordings have read-only channels', () {
    final session = parse(fixture('event-laps.vbo'));
    for (final channel in session.channels.values) {
      expect(() => channel.values[0] = 0.0, throwsUnsupportedError, reason: channel.name);
      expect(() => channel.timestamps[0] = 0.0, throwsUnsupportedError, reason: channel.name);
    }
  });

  test('derived channels are read-only too', () {
    final session = gpsSession([0, 1, 2], [52.0, 52.0, 52.0], [21.0, 21.0, 21.0]);
    final latitude = session.channel('latitude')!;
    expect(() => latitude.values[0] = 0.0, throwsUnsupportedError);
  });

  test('RCZ channels are read-only', () {
    final session = loadRecording('test/parity/rcz_corpus/basic.rcz');
    expect(session.channels, isNotEmpty);
    for (final channel in session.channels.values) {
      if (channel.sampleCount == 0) continue;
      expect(() => channel.values[0] = 0.0, throwsUnsupportedError, reason: channel.name);
      expect(() => channel.timestamps[0] = 0.0, throwsUnsupportedError, reason: channel.name);
    }
  });

  test('fused channels are read-only', () {
    final primary = parse(fixture('event-laps.vbo'));
    final result = fuseChannels(
      primary,
      'vbo',
      [FusionSource(sourceId: 'copy', session: primary, alignmentStatus: 'aligned')],
      policy: FusionPolicy(
        rules: {
          for (final name in primary.channels.keys)
            name: (sourceId: 'copy', rule: FusionRule.fillGaps),
        },
      ),
    );
    for (final fused in result.channels) {
      final channel = fused.channel;
      if (channel.sampleCount == 0) continue;
      expect(() => channel.values[0] = 0.0, throwsUnsupportedError, reason: channel.name);
      expect(() => channel.timestamps[0] = 0.0, throwsUnsupportedError, reason: channel.name);
    }
  });
}
