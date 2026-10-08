// The GPS path of a lap section for the track map (FET-23). The map shows
// the trace only, no tiles (plan decision 13).
import '../geometry.dart';
import '../operation.dart';
import '../telemetry_session.dart';

/// A recorded GPS fix in metres east and north of the path's origin, with
/// the speed there in the recording's unit (null when not recorded).
final class PathPoint {
  const PathPoint(this.telemetryTime, this.eastMeters, this.northMeters, this.speed);

  final double telemetryTime;
  final double eastMeters;
  final double northMeters;
  final double? speed;
}

/// A lap's path as runs of continuous fixes. A GPS gap or an invalid fix
/// ends a run, so the map never draws a line across missing data.
final class LapPath {
  LapPath({required this.origin, required List<List<PathPoint>> segments, this.speedUnit = ''})
    : segments = List.unmodifiable(segments.map(List<PathPoint>.unmodifiable));

  final GeoCoordinate origin;
  final List<List<PathPoint>> segments;
  final String speedUnit;

  bool get isEmpty => segments.every((segment) => segment.isEmpty);
}

/// The recorded fixes of [session] from [start] to [end] seconds, projected
/// around [origin] (by default the first fix), thinned evenly to at most
/// [maximumPoints]. Fixes further apart in time than the GPS gap threshold
/// start a new segment.
LapPath lapPath(
  TelemetrySession session,
  double start,
  double end, {
  GeoCoordinate? origin,
  int maximumPoints = 4000,
  CancellationCheck? cancelled,
}) {
  final latitude = session.channel('latitude');
  final longitude = session.channel('longitude');
  final speedChannel = session.channel('speed');
  final empty = LapPath(origin: origin ?? const GeoCoordinate(0, 0), segments: const []);
  if (latitude == null ||
      longitude == null ||
      !start.isFinite ||
      !end.isFinite ||
      end <= start ||
      maximumPoints < 2) {
    return empty;
  }
  // Drawn east-positive whatever the recording's convention, so the map is
  // never mirrored.
  final westPositive = session.metadata['gpsLongitudeConvention'] == 'west-positive';
  final times = latitude.timestamps;
  final first = lowerBound(times, start);
  final last = upperBound(times, end);
  if (last - first < 2) return empty;
  final stride = ((last - first) + maximumPoints - 1) ~/ maximumPoints;
  final gap = telemetryGapThreshold(latitude, 0.5) * (stride < 1 ? 1 : stride);
  final segments = <List<PathPoint>>[];
  var current = <PathPoint>[];
  GeoCoordinate? center = origin;
  double? previousTime;
  for (var index = first; index < last; index += stride < 1 ? 1 : stride) {
    if ((index & 0xff) == 0) throwIfCancelled(cancelled);
    final time = times[index];
    final lon = longitude.timestamps.length > index && longitude.timestamps[index] == time
        ? longitude.values[index].toDouble()
        : session.valueAt('longitude', time, InterpolationMode.longitude);
    final coordinate = GeoCoordinate(
      latitude.values[index].toDouble(),
      westPositive ? -(lon ?? double.nan) : lon ?? double.nan,
    );
    if (!isValidCoordinate(coordinate) || (previousTime != null && time - previousTime > gap)) {
      if (current.length > 1) segments.add(current);
      current = [];
      if (!isValidCoordinate(coordinate)) {
        previousTime = null;
        continue;
      }
    }
    center ??= coordinate;
    final point = projectCoordinate(coordinate, center);
    final speed = speedChannel == null ? null : session.valueAt('speed', time);
    current.add(PathPoint(time, point.eastMeters, point.northMeters, speed));
    previousTime = time;
  }
  if (current.length > 1) segments.add(current);
  return LapPath(
    origin: center ?? const GeoCoordinate(0, 0),
    segments: segments,
    speedUnit: speedChannel?.unit ?? '',
  );
}

/// Where [path] was at [telemetryTime], between the two fixes around it;
/// null outside its runs of fixes (in a GPS gap, before or after the lap).
({double east, double north})? lapPathPointAt(LapPath path, double telemetryTime) {
  for (final segment in path.segments) {
    if (segment.isEmpty ||
        telemetryTime < segment.first.telemetryTime ||
        telemetryTime > segment.last.telemetryTime) {
      continue;
    }
    var low = 0, high = segment.length - 1;
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      segment[middle].telemetryTime <= telemetryTime ? low = middle : high = middle;
    }
    final a = segment[low], b = segment[high];
    final span = b.telemetryTime - a.telemetryTime;
    final t = span > 0 ? (telemetryTime - a.telemetryTime) / span : 0.0;
    return (
      east: a.eastMeters + (b.eastMeters - a.eastMeters) * t,
      north: a.northMeters + (b.northMeters - a.northMeters) * t,
    );
  }
  return null;
}
