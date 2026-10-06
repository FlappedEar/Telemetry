// Port of FlappedEar Overlays native/src/telemetry/MapLayers.{h,cpp} and the
// map normalization of native/src/telemetry/TrackGeometry.{h,cpp} (revision
// d4d1039, FET-37): a lap's racing line on a map normalized for one or two
// laps, and the line coloured by a value (speed, the A−B delta, G, pedals, a
// temperature). Values are sampled along the lap's progress, then placed on
// the map through the lap's own time at that progress. Nothing is bridged: a
// progress, time, position or value that is missing (a GPS gap, a channel
// gap, an implausible or placeholder sample) ends a polyline.
import 'dart:math' as math;
import 'dart:typed_data';

import '../geometry.dart';
import '../telemetry_session.dart';
import 'channel_summary.dart';
import 'outing_theoretical_best.dart' show MapPoint;
import 'track_progress.dart';

/// Names the way map layers are sampled; stored with a layer's result.
const String mapLayerAlgorithm = 'map-layer-v1';

/// How GPS fixes become [MapPoint]s (normalized map positions: the map is
/// a unit square, x grows east and y south, and both laps of a pair share
/// one scale): local metres around the first valid fix
/// (east-positive whatever the recording's longitude convention, north up),
/// centred on their bounding box and divided by its larger side (at least
/// 1 m).
final class MapGeometry {
  const MapGeometry({
    this.minimumX = 0.0,
    this.minimumY = 0.0,
    this.width = 0.0,
    this.height = 0.0,
    this.centerX = 0.0,
    this.centerY = 0.0,
    this.normalizationScale = 1.0,
    this.originLatitude = 0.0,
    this.originLongitude = 0.0,
    this.longitudeIsWestPositive = false,
    this.pointCount = 0,
    this.valid = false,
  });

  /// The local bounding box, metres east and south of the origin.
  final double minimumX;
  final double minimumY;
  final double width;
  final double height;
  final double centerX;
  final double centerY;
  final double normalizationScale;

  /// The origin in the recording's own coordinates.
  final double originLatitude;
  final double originLongitude;

  /// The recording writes west longitudes as positive (RaceChrono VBO).
  final bool longitudeIsWestPositive;

  /// How many fixes the geometry was built from.
  final int pointCount;
  final bool valid;
}

(double, double) _toLocal(
  double latitude,
  double longitude,
  double originLatitude,
  double originLongitude,
  bool westPositive,
) {
  final projected = projectCoordinate(
    GeoCoordinate(latitude, longitude),
    GeoCoordinate(originLatitude, originLongitude),
  );
  // Only the map presentation is converted; samples, gates and saved data
  // keep the recording's convention.
  return (westPositive ? -projected.eastMeters : projected.eastMeters, -projected.northMeters);
}

/// The geometry of index-paired [latitudes] and [longitudes] (degrees);
/// invalid fixes are skipped and none valid gives an invalid geometry.
MapGeometry mapGeometryFromCoordinates(
  List<double> latitudes,
  List<double> longitudes, {
  bool longitudeIsWestPositive = false,
}) {
  final count = math.min(latitudes.length, longitudes.length);
  double? originLatitude, originLongitude;
  var minimumX = double.infinity, minimumY = double.infinity;
  var maximumX = double.negativeInfinity, maximumY = double.negativeInfinity;
  var points = 0;
  for (var index = 0; index < count; ++index) {
    final latitude = latitudes[index], longitude = longitudes[index];
    if (!isValidCoordinate(GeoCoordinate(latitude, longitude))) continue;
    originLatitude ??= latitude;
    originLongitude ??= longitude;
    final (x, y) = _toLocal(
      latitude,
      longitude,
      originLatitude,
      originLongitude,
      longitudeIsWestPositive,
    );
    minimumX = math.min(minimumX, x);
    minimumY = math.min(minimumY, y);
    maximumX = math.max(maximumX, x);
    maximumY = math.max(maximumY, y);
    ++points;
  }
  if (points == 0) return MapGeometry(longitudeIsWestPositive: longitudeIsWestPositive);
  final width = maximumX - minimumX, height = maximumY - minimumY;
  return MapGeometry(
    minimumX: minimumX,
    minimumY: minimumY,
    width: width,
    height: height,
    // As a rectangle's centre: its corner plus half its size.
    centerX: minimumX + width / 2,
    centerY: minimumY + height / 2,
    normalizationScale: math.max(1.0, math.max(width, height)),
    originLatitude: originLatitude!,
    originLongitude: originLongitude!,
    longitudeIsWestPositive: longitudeIsWestPositive,
    pointCount: points,
    valid: true,
  );
}

bool _westPositive(TelemetrySession session) =>
    session.metadata['gpsLongitudeConvention'] == 'west-positive';

/// The geometry of every fix of [session] (Overlays' `buildTrackGeometry`).
MapGeometry sessionMapGeometry(TelemetrySession session) {
  final latitude = session.channel('latitude');
  final longitude = session.channel('longitude');
  if (latitude == null || longitude == null) {
    return MapGeometry(longitudeIsWestPositive: _westPositive(session));
  }
  return mapGeometryFromCoordinates(
    [for (final value in latitude.values) value],
    [for (final value in longitude.values) value],
    longitudeIsWestPositive: _westPositive(session),
  );
}

// The recording's fixes in [start]..[end], as Overlays collects them for a
// map: the sampled latitude (2000 buckets) with the longitude at each sample
// time, both stored as float32.
void _appendFixes(
  TelemetrySession session,
  double start,
  double end,
  List<double> latitudes,
  List<double> longitudes,
) {
  final float = Float32List(1);
  double single(double value) => (float..[0] = value)[0];
  for (final segment in session.sampledSegments('latitude', start, end, 2000)) {
    for (final sample in segment) {
      final longitude = session.valueAt('longitude', sample.time, InterpolationMode.longitude);
      if (longitude == null) continue;
      latitudes.add(single(sample.value));
      longitudes.add(single(longitude));
    }
  }
}

/// The geometry of one lap section's own fixes (the lap page's map in
/// Overlays' `loadOutingLapDetail`).
MapGeometry lapMapGeometry(TelemetrySession session, double start, double end) {
  final latitudes = <double>[], longitudes = <double>[];
  _appendFixes(session, start, end, latitudes, longitudes);
  return mapGeometryFromCoordinates(
    latitudes,
    longitudes,
    longitudeIsWestPositive: _westPositive(session),
  );
}

/// One normalization for two laps' fixes, so both are drawn to one scale
/// (Overlays' `buildSharedTrackGeometry`). Both laps are on the same track,
/// so lap A's longitude convention is used for both.
MapGeometry sharedMapGeometry(
  TelemetrySession sessionA,
  double startA,
  double endA,
  TelemetrySession sessionB,
  double startB,
  double endB,
) {
  final latitudes = <double>[], longitudes = <double>[];
  _appendFixes(sessionA, startA, endA, latitudes, longitudes);
  _appendFixes(sessionB, startB, endB, latitudes, longitudes);
  return mapGeometryFromCoordinates(
    latitudes,
    longitudes,
    longitudeIsWestPositive: _westPositive(sessionA),
  );
}

/// Where [session] was at [time] on [geometry]'s map, or null without a
/// valid fix there (Overlays' `currentTrackPoint`).
MapPoint? mapPointAt(TelemetrySession session, double time, MapGeometry geometry) {
  if (!geometry.valid) return null;
  final latitude = session.valueAt('latitude', time);
  final longitude = session.valueAt('longitude', time, InterpolationMode.longitude);
  if (latitude == null ||
      longitude == null ||
      !isValidCoordinate(GeoCoordinate(latitude, longitude))) {
    return null;
  }
  final (x, y) = _toLocal(
    latitude,
    longitude,
    geometry.originLatitude,
    geometry.originLongitude,
    geometry.longitudeIsWestPositive,
  );
  if (!x.isFinite ||
      !y.isFinite ||
      !geometry.normalizationScale.isFinite ||
      geometry.normalizationScale <= 0.0) {
    return null;
  }
  final normalizedX = (x - geometry.centerX) / geometry.normalizationScale + 0.5;
  final normalizedY = (y - geometry.centerY) / geometry.normalizationScale + 0.5;
  return normalizedX.isFinite && normalizedY.isFinite ? (x: normalizedX, y: normalizedY) : null;
}

/// Where the normalized map position ([x], [y]) of [geometry] is on the
/// earth, the inverse of [mapPointAt]: degrees, east-positive whatever the
/// recording's longitude convention, so the point can be drawn over map
/// tiles. Null for an invalid geometry or a position that is not finite.
GeoCoordinate? mapPointCoordinate(double x, double y, MapGeometry geometry) {
  if (!geometry.valid ||
      !x.isFinite ||
      !y.isFinite ||
      !geometry.normalizationScale.isFinite ||
      geometry.normalizationScale <= 0.0) {
    return null;
  }
  final east = (x - 0.5) * geometry.normalizationScale + geometry.centerX;
  final south = (y - 0.5) * geometry.normalizationScale + geometry.centerY;
  // The map's x is already east-positive; only the origin's longitude is in
  // the recording's convention.
  final origin = GeoCoordinate(
    geometry.originLatitude,
    geometry.longitudeIsWestPositive ? -geometry.originLongitude : geometry.originLongitude,
  );
  final coordinate = unprojectCoordinate(east, -south, origin);
  return coordinate.latitudeDegrees.isFinite && coordinate.longitudeDegrees.isFinite
      ? coordinate
      : null;
}

/// One lap section's trace on [geometry]'s map, as runs of fixes: a GPS gap
/// (a missing longitude or a gap in the sampled latitude) starts a new run
/// (Overlays' `buildTrackSegments`).
List<List<MapPoint>> mapTrace(
  TelemetrySession session,
  double start,
  double end,
  MapGeometry geometry,
) {
  final track = <List<MapPoint>>[];
  if (!geometry.valid) return track;
  for (final segment in session.sampledSegments('latitude', start, end, 2000)) {
    var points = <MapPoint>[];
    for (final sample in segment) {
      final longitude = session.valueAt('longitude', sample.time, InterpolationMode.longitude);
      if (longitude == null) {
        if (points.isNotEmpty) {
          track.add(points);
          points = [];
        }
        continue;
      }
      final point = mapPointAt(session, sample.time, geometry);
      if (point != null) points.add(point);
    }
    if (points.isNotEmpty) track.add(points);
  }
  return track;
}

/// A progress position (metres on the shared axis) and a value there.
typedef ProgressValue = ({double progress, double value});

/// One point of a map layer: where on the map, and the value there in the
/// source unit.
final class MapLayerPoint {
  const MapLayerPoint(this.x, this.y, this.value);

  final double x;
  final double y;
  final double value;
}

/// A lap's line coloured by a value: polylines of at least two points, and
/// the range of their values (null when there is no polyline).
final class MapLayerTrace {
  const MapLayerTrace({this.polylines = const [], this.minimum, this.maximum});

  final List<List<MapLayerPoint>> polylines;
  final double? minimum;
  final double? maximum;
}

/// [channel]'s value at [time] from its two neighbouring samples, linearly
/// interpolated. Null when either neighbour is missing, not finite, not
/// plausible under [policy], or when they are further apart than the
/// channel's gap threshold.
double? plausibleChannelValue(
  TelemetryChannel channel,
  double time,
  ChannelSummaryPolicy policy,
  bool zeroPlaceholder,
) {
  final times = channel.timestamps;
  if (!time.isFinite || times.isEmpty || times.length != channel.values.length) return null;
  final index = lowerBound(times, time);
  if (index == times.length) return null;
  final double nextValue = channel.values[index];
  if (!plausibleSample(nextValue, policy, zeroPlaceholder)) return null;
  final nextTime = times[index];
  if (nextTime == time) return nextValue;
  if (index == 0) return null;
  final previousTime = times[index - 1];
  final double previousValue = channel.values[index - 1];
  if (!plausibleSample(previousValue, policy, zeroPlaceholder)) return null;
  final gapLimit = telemetryGapThreshold(channel);
  if (gapLimit > 0.0 && nextTime - previousTime > gapLimit) return null;
  final span = nextTime - previousTime;
  if (!(span > 0.0)) return null;
  return previousValue + (nextValue - previousValue) * (time - previousTime) / span;
}

/// The channel (or alias) [channelOrAlias] at up to [maximumPoints] evenly
/// spaced progress positions over 0..[axisLengthMeters] of [trace] (the
/// count clamped to 2..4000), split wherever there is no value.
List<List<ProgressValue>> channelAlongProgress(
  TelemetrySession session,
  String channelOrAlias,
  List<ProgressSegment> trace,
  double axisLengthMeters,
  int maximumPoints, [
  ChannelSummaryPolicy policy = const ChannelSummaryPolicy(),
]) {
  final result = <List<ProgressValue>>[];
  final found = session.channel(channelOrAlias);
  if (found == null || !axisLengthMeters.isFinite || !(axisLengthMeters > 0.0)) return result;
  final zeroPlaceholder = zeroIsPlaceholder(found, policy);
  final points = maximumPoints.clamp(2, 4000);
  var current = <ProgressValue>[];
  for (var index = 0; index < points; ++index) {
    final progress = axisLengthMeters * index / (points - 1);
    final time = timeAtProgress(trace, progress);
    final value = time == null ? null : plausibleChannelValue(found, time, policy, zeroPlaceholder);
    if (value == null) {
      if (current.isNotEmpty) {
        result.add(current);
        current = [];
      }
      continue;
    }
    current.add((progress: progress, value: value));
  }
  if (current.isNotEmpty) result.add(current);
  return result;
}

/// Places progress/value pairs on [geometry]'s map at [session]'s position
/// for that progress on [trace], with the layer's range.
MapLayerTrace placeOnMap(
  TelemetrySession session,
  List<ProgressSegment> trace,
  MapGeometry geometry,
  List<List<ProgressValue>> values,
) {
  if (!geometry.valid) return const MapLayerTrace();
  final polylines = <List<MapLayerPoint>>[];
  for (final segment in values) {
    var current = <MapLayerPoint>[];
    void flush() {
      if (current.length >= 2) polylines.add(current);
      current = [];
    }

    for (final sample in segment) {
      final time = timeAtProgress(trace, sample.progress);
      final position = time == null ? null : mapPointAt(session, time, geometry);
      if (position == null || !sample.value.isFinite) {
        flush();
        continue;
      }
      current.add(MapLayerPoint(position.x, position.y, sample.value));
    }
    flush();
  }
  double? minimum, maximum;
  for (final polyline in polylines) {
    for (final point in polyline) {
      if (minimum == null || point.value < minimum) minimum = point.value;
      if (maximum == null || point.value > maximum) maximum = point.value;
    }
  }
  return MapLayerTrace(
    polylines: List.unmodifiable(polylines.map(List<MapLayerPoint>.unmodifiable)),
    minimum: minimum,
    maximum: maximum,
  );
}
