import 'dart:io';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';

TelemetrySession parse(String text, {CancellationCheck? cancelled}) =>
    VboParser.parse(text, cancelled: cancelled);

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A session holding only latitude and longitude channels.
TelemetrySession gpsSession(
  List<double> times,
  List<double> latitudes,
  List<double> longitudes, {
  List<double>? longitudeTimes,
  List<TimingGate> gates = const [],
}) {
  TelemetryChannel channel(String name, List<double> t, List<double> v) => TelemetryChannel(
    name: name,
    timestamps: Float64List.fromList(t),
    values: Float32List.fromList(v),
  );
  return TelemetrySession(
    duration: times.last - times.first,
    startTime: 0,
    metadata: const {},
    channels: {
      'latitude': channel('latitude', times, latitudes),
      'longitude': channel('longitude', longitudeTimes ?? times, longitudes),
    },
    aliases: const {'latitude': 'latitude', 'longitude': 'longitude'},
    warnings: const [],
    timingGates: gates,
    sampleCount: times.length,
  );
}

/// [session] with its latitude and longitude channels replaced by [transform]
/// of their times and values.
TelemetrySession editGps(
  TelemetrySession session,
  void Function(
    List<double> latTimes,
    List<double> latValues,
    List<double> lonTimes,
    List<double> lonValues,
  )
  transform,
) {
  final lat = session.channel('latitude')!;
  final lon = session.channel('longitude')!;
  final latTimes = lat.timestamps.toList();
  final latValues = lat.values.toList();
  final lonTimes = lon.timestamps.toList();
  final lonValues = lon.values.toList();
  transform(latTimes, latValues, lonTimes, lonValues);
  return gpsSession(
    latTimes,
    latValues,
    lonValues,
    longitudeTimes: lonTimes,
    gates: session.timingGates,
  );
}
