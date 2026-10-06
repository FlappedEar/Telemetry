// FET-210: a fused session's duration, start time and sample count describe
// every channel in it; fused channels never reach outside the primary's span.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

TelemetryChannel _channel(
  String name,
  String unit,
  double end,
  double rate,
  double Function(double) value,
) {
  final times = <double>[], values = <double>[];
  for (var time = 0.0; time <= end + 1e-9; time += 1.0 / rate) {
    times.add(time);
    values.add(value(time));
  }
  return TelemetryChannel(
    name: name,
    unit: unit,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
}

TelemetrySession _session(double duration, List<(TelemetryChannel, String?)> channels) =>
    TelemetrySession(
      duration: duration,
      startTime: 12.0,
      metadata: const {},
      channels: {for (final (channel, _) in channels) channel.name: channel},
      aliases: {for (final (channel, alias) in channels) ?alias: channel.name},
      warnings: const [],
      timingGates: const [],
      sampleCount: (duration * 10).round() + 1,
    );

double _speedAt(double t) => 100.0 + 20.0 * math.sin(0.1 * t);

final _primary = _session(100.0, [(_channel('velocity', 'km/h', 100.0, 10.0, _speedAt), 'speed')]);

TelemetrySession _alternative(double offset) => _session(120.0, [
  (_channel('velocity', 'km/h', 120.0, 5.0, (t) => _speedAt(t + offset)), 'speed'),
  (_channel('rpm-obd', 'rpm', 120.0, 5.0, (t) => 4000.0 + 1000.0 * math.sin(0.3 * t)), 'rpm'),
]);

void main() {
  for (final offset in [-30.0, 10.0]) {
    test('every channel of a fused session lies within its span (offset $offset s)', () {
      final fusion = fuseChannels(
        _primary,
        'vbo',
        [
          FusionSource(
            sourceId: 'rcz',
            session: _alternative(offset),
            clock: SourceClock(offsetSeconds: offset),
            alignmentStatus: 'aligned',
          ),
        ],
        policy: const FusionPolicy(
          rules: {'speed': (sourceId: 'rcz', rule: FusionRule.preferAlternative)},
        ),
      );
      // The fused channels themselves reach past the primary.
      expect(
        fusion.channels.any(
          (channel) =>
              channel.channel.timestamps.first < 0.0 ||
              channel.channel.timestamps.last > _primary.duration,
        ),
        isTrue,
      );
      final session = fusedSession(_primary, fusion);
      expect(session.duration, _primary.duration);
      expect(session.startTime, _primary.startTime);
      expect(session.sampleCount, _primary.sampleCount);
      expect(session.metadata['fusedChannels'], 'rpm-obd,velocity');
      for (final channel in session.channels.values) {
        expect(channel.timestamps.first, greaterThanOrEqualTo(-1e-6), reason: channel.name);
        expect(
          channel.timestamps.last,
          lessThanOrEqualTo(session.duration + 1e-6),
          reason: channel.name,
        );
        expect(channel.values.any((value) => value.isFinite), isTrue, reason: channel.name);
      }
      // Inside the span nothing is lost: the alternative's speed is used.
      expect(session.valueAt('speed', 50.0), closeTo(_speedAt(50.0), 0.01));
    });
  }

  test('an added channel wholly outside the span is left out', () {
    final fusion = fuseChannels(_primary, 'vbo', [
      FusionSource(
        sourceId: 'rcz',
        session: _alternative(0.0),
        clock: const SourceClock(offsetSeconds: 500.0),
        alignmentStatus: 'aligned',
      ),
    ]);
    final session = fusedSession(_primary, fusion);
    expect(session.channels.keys, ['velocity']);
    expect(session.aliases.containsKey('rpm'), isFalse);
    expect(session.metadata['fusedChannels'], '');
  });
}
