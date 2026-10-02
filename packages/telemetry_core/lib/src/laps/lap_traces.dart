import '../geometry.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import 'lap_session.dart';

const int _maximumTracePoints = 700000;
const int _maximumPointsPerLapTrace = 4096;

/// The path of every eligible lap, in metres around [origin]: the interpolated
/// position at the start, the recorded fixes in between (thinned evenly to at
/// most 4,096 points in all), and the interpolated position at the end.
List<LapTrace> buildLapTraces(
  TelemetrySession session,
  List<TimedLap> laps,
  GeoCoordinate origin,
  CancellationCheck? cancelled,
) {
  final latitude = session.channels[session.aliases['latitude']];
  final longitude = session.channels[session.aliases['longitude']];
  if (latitude == null ||
      longitude == null ||
      latitude.timestamps.length != latitude.values.length ||
      longitude.timestamps.length != longitude.values.length) {
    return const [];
  }
  var totalPoints = 0;
  void append(List<LapTracePoint> points, double time, MetricPoint point) {
    if (totalPoints >= _maximumTracePoints) {
      throw const ResourceLimitError('Lap traces contain too many GPS points.');
    }
    points.add(LapTracePoint(time, point.eastMeters, point.northMeters));
    ++totalPoints;
  }

  void appendInterpolated(List<LapTracePoint> points, double time) {
    final latitudeValue = session.valueAt('latitude', time);
    final longitudeValue = session.valueAt('longitude', time);
    if (latitudeValue == null || longitudeValue == null) return;
    final coordinate = GeoCoordinate(latitudeValue, longitudeValue);
    if (!isValidCoordinate(coordinate)) return;
    final point = projectCoordinate(coordinate, origin);
    if (!point.eastMeters.isFinite || !point.northMeters.isFinite) return;
    if (points.isNotEmpty && (points.last.telemetryTime - time).abs() <= 1e-9) return;
    append(points, time, point);
  }

  final traces = <LapTrace>[];
  final times = latitude.timestamps;
  for (final lap in laps) {
    throwIfCancelled(cancelled);
    if (!lap.referenceEligible) continue;
    final points = <LapTracePoint>[];
    appendInterpolated(points, lap.startTelemetryTime);
    final first = upperBound(times, lap.startTelemetryTime);
    final end = lowerBound(times, lap.endTelemetryTime, first);
    final rawPointCount = end - first;
    final stride = _ceilStride(rawPointCount);
    for (
      var index = first, ordinal = 0;
      index < times.length && times[index] < lap.endTelemetryTime;
      ++index, ++ordinal
    ) {
      if ((index & 0xff) == 0) throwIfCancelled(cancelled);
      if (ordinal % stride != 0) continue;
      if (index >= longitude.timestamps.length || times[index] != longitude.timestamps[index]) {
        continue;
      }
      final coordinate = GeoCoordinate(latitude.values[index], longitude.values[index]);
      if (!isValidCoordinate(coordinate)) continue;
      final point = projectCoordinate(coordinate, origin);
      if (!point.eastMeters.isFinite || !point.northMeters.isFinite) continue;
      append(points, times[index], point);
    }
    appendInterpolated(points, lap.endTelemetryTime);
    if (points.length >= 2) {
      traces.add(
        LapTrace(
          lapNumber: lap.number,
          startTelemetryTime: lap.startTelemetryTime,
          durationSeconds: lap.durationSeconds,
          points: List.unmodifiable(points),
        ),
      );
    }
  }
  return traces;
}

/// Every n-th fix so that the fixes plus the two interpolated ends fit the
/// per-lap limit.
int _ceilStride(int rawPointCount) {
  final stride = (rawPointCount + _maximumPointsPerLapTrace - 3) ~/ (_maximumPointsPerLapTrace - 2);
  return stride < 1 ? 1 : stride;
}
