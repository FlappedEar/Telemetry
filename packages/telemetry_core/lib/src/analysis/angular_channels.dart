// Angular channels (heading) wrap at 0°/360°. Charts draw them unwrapped, so
// crossing north is a continuous line rather than a vertical jump; the
// recorded values stay as they are.
import 'dart:math' as math;
import 'dart:typed_data';

import '../telemetry_session.dart';

final RegExp _angularName = RegExp(
  r'^(?:gps[ _-]?)?(?:heading|course|bearing)(?:[ _-].*)?$',
  caseSensitive: false,
);

const Set<String> _degreeUnits = {'', 'deg', 'degree', 'degrees', '°'};

/// Whether [channel] is a compass direction in degrees (a heading, course or
/// bearing), whose values wrap at 360.
bool isAngularChannel(TelemetryChannel channel) =>
    _angularName.hasMatch(channel.name.trim()) &&
    _degreeUnits.contains(channel.unit.trim().toLowerCase());

/// [value] (degrees) as a compass direction in 0 up to 360.
double normalizeDegrees(double value) {
  final wrapped = value % 360.0;
  return wrapped < 0.0 ? wrapped + 360.0 : wrapped;
}

/// The multiple of 360 that moves [value] into 0 up to 360.
double degreesTurnOffset(double value) => -360.0 * (value / 360.0).floorToDouble();

/// The multiple of 360 that moves [value] within half a turn of [reference].
double degreesTurnOffsetNear(double value, double reference) =>
    -360.0 * ((value - reference) / 360.0).roundToDouble();

final Expando<TelemetrySession> _unwrappedViews = Expando('unwrapped angles');

/// A session holding only [channel] unwrapped: each sample moves by whole
/// turns so it is within half a turn of the previous finite one. Missing
/// values stay missing; the times are the channel's own. Built once per
/// channel.
TelemetrySession unwrappedAngleSession(TelemetryChannel channel) =>
    _unwrappedViews[channel] ??= TelemetrySession(
      duration: channel.timestamps.isEmpty
          ? 0.0
          : channel.timestamps.last - channel.timestamps.first,
      startTime: 0.0,
      metadata: const {},
      channels: {channel.name: _unwrapped(channel)},
      aliases: const {},
      warnings: const [],
      timingGates: const [],
      sampleCount: channel.sampleCount,
    );

TelemetryChannel _unwrapped(TelemetryChannel channel) {
  final values = Float32List(channel.values.length);
  double? previous;
  for (var index = 0; index < values.length; ++index) {
    final raw = channel.values[index].toDouble();
    if (!raw.isFinite) {
      values[index] = double.nan;
      continue;
    }
    final value = previous == null ? raw : raw + degreesTurnOffsetNear(raw, previous);
    values[index] = value;
    previous = value;
  }
  return TelemetryChannel(
    name: channel.name,
    unit: channel.unit,
    timestamps: channel.timestamps,
    values: values,
  );
}

/// The first finite value of the only channel of [session] at or after
/// [time] (seconds), or null.
double? firstFiniteValueFrom(TelemetrySession session, String name, double time) {
  final found = session.channel(name);
  if (found == null || !time.isFinite) return null;
  final start = math.max(0, lowerBound(found.timestamps, time));
  for (var index = start; index < found.values.length; ++index) {
    final value = found.values[index];
    if (value.isFinite) return value.toDouble();
  }
  return null;
}
