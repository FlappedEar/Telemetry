// The one gap rule (Overlays KAN-157): no value lookup, and no auto-sync
// correlation, bridges a loss of signal. Ports of Overlays'
// TelemetryCoreTests::neverBridgesALossOfSignal and syncIgnoresALossOfGpsFix.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

TelemetrySession _session(TelemetryChannel speed) => TelemetrySession(
  duration: speed.timestamps.isEmpty ? 0.0 : speed.timestamps.last,
  startTime: 0.0,
  metadata: const {},
  channels: {speed.name: speed},
  aliases: {'speed': speed.name},
  warnings: const [],
  timingGates: const [],
  sampleCount: speed.timestamps.length,
);

void main() {
  test('never bridges a loss of signal', () {
    // A 30 s loss of GPS fix (samples dropped, as the GoPro decoder does) is
    // no data in every interpolation mode; samples either side stay.
    final times = <double>[], values = <double>[];
    for (var tick = 0; tick <= 600; ++tick) {
      if (tick > 200 && tick < 500) continue; // no fix from 20.0 s to 50.0 s
      times.add(tick / 10.0);
      values.add(tick.toDouble());
    }
    final speed = TelemetryChannel(
      name: 'speed',
      unit: 'km/h',
      timestamps: Float64List.fromList(times),
      values: Float32List.fromList(values),
    );
    final session = _session(speed);
    for (final mode in InterpolationMode.values) {
      expect(session.valueAt('speed', 20.05, mode), isNull, reason: '$mode');
      expect(session.valueAt('speed', 35.0, mode), isNull, reason: '$mode');
      expect(session.valueAt('speed', 49.95, mode), isNull, reason: '$mode');
    }
    expect(session.valueAt('speed', 20.0), 200.0);
    expect(session.valueAt('speed', 50.0), 500.0);
    expect(session.valueAt('speed', 10.05), closeTo(100.5, 1e-6));
    expect(session.valueAt('speed', 10.04, InterpolationMode.previous), 100.0);
    expect(telemetryValueAt(speed, 35.0), isNull);
  });

  test('auto-sync ignores a loss of GPS fix', () {
    // Auto-sync must not correlate the straight ramp it would draw across a
    // loss of fix: dropped samples count exactly like samples marked as no
    // data.
    double speedAt(double time) =>
        50.0 + 18.0 * math.sin(time * 0.21) + 7.0 * math.sin(time * 0.73) + time * 0.08;
    TelemetrySession recording({required bool lossOfFix, required bool markLoss}) {
      final times = <double>[], values = <double>[];
      for (var tick = 0; tick <= 600; ++tick) {
        final time = tick * 0.2;
        final lost = lossOfFix && time > 40.0 && time < 70.0;
        if (lost && !markLoss) continue;
        times.add(time);
        values.add(lost ? double.nan : speedAt(time));
      }
      return _session(
        TelemetryChannel(
          name: 'speed',
          unit: 'km/h',
          timestamps: Float64List.fromList(times),
          values: Float32List.fromList(values),
        ),
      );
    }

    final telemetry = recording(lossOfFix: false, markLoss: false);
    final dropped = synchronizeTelemetry(recording(lossOfFix: true, markLoss: false), telemetry);
    final marked = synchronizeTelemetry(recording(lossOfFix: true, markLoss: true), telemetry);
    expect(dropped.offset.abs(), lessThan(0.05));
    expect(dropped.diagnostics.validSamples, marked.diagnostics.validSamples);
    final continuous = synchronizeTelemetry(
      recording(lossOfFix: false, markLoss: false),
      telemetry,
    );
    expect(dropped.diagnostics.validSamples, lessThan(continuous.diagnostics.validSamples - 250));
  });
}
