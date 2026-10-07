// Port of VBOOverlay native/src/telemetry/TrackInference.{h,cpp} (FET-22):
// the route a recording's laps follow, and which runs share a route.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../geometry.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import 'compatibility.dart';

/// The algorithm stamp of detected routes and their `gps-route-v1:` ids.
const String trackInferenceVersion = 'gps-route-v1';

/// The points of every [RouteShape].
const int routeShapePointCount = 256;
const int _shapePoints = routeShapePointCount;
const int _maximumRepresentatives = 64;

/// A lap that leaves the line the other laps took by more than this is off
/// the route (KAN-137).
const double maximumLineDeviationMeters = 12.0;

/// A complete lap resampled to 256 points evenly spaced along its length, in
/// metres around [origin]. Never stored.
final class RouteShape {
  const RouteShape({
    required this.origin,
    required this.points,
    required this.lengthMeters,
    required this.direction,
  });

  final GeoCoordinate origin;
  final List<MetricPoint> points;
  final double lengthMeters;
  final TrackDirection direction;
}

/// The route of one recording, or why there is none.
final class TrackInference {
  const TrackInference({this.route, this.matchingLaps = const {}, this.reason = ''});

  final RouteShape? route;

  /// Lap numbers that follow [route] and stay on the other laps' line.
  final Set<int> matchingLaps;
  final String reason;

  bool get supported => route != null;
}

double _distance(MetricPoint a, MetricPoint b) =>
    hypot(a.eastMeters - b.eastMeters, a.northMeters - b.northMeters);

double _toSegment(MetricPoint p, MetricPoint a, MetricPoint b) {
  final abx = b.eastMeters - a.eastMeters, aby = b.northMeters - a.northMeters;
  final length2 = abx * abx + aby * aby;
  final t = length2 > 0
      ? (((p.eastMeters - a.eastMeters) * abx + (p.northMeters - a.northMeters) * aby) / length2)
            .clamp(0.0, 1.0)
      : 0.0;
  return _distance(p, MetricPoint(a.eastMeters + abx * t, a.northMeters + aby * t));
}

RouteShape? _shape(LapTrace trace, GeoCoordinate origin, bool westPositive) {
  if (trace.points.length < 12 || trace.points.length > 4096) return null;
  final points = <MetricPoint>[];
  for (final sample in trace.points) {
    final point = MetricPoint(
      westPositive ? -sample.eastMeters : sample.eastMeters,
      sample.northMeters,
    );
    if (!point.eastMeters.isFinite || !point.northMeters.isFinite) return null;
    // Drop sub-3 m GPS jitter before resampling by distance. Timing is unused.
    if (points.isEmpty || _distance(points.last, point) >= 3) points.add(point);
  }
  if (points.length < 12 || _distance(points.first, points.last) > 25) return null;
  points.add(points.first);
  final cumulative = <double>[0.0];
  var area = 0.0;
  for (var i = 1; i < points.length; ++i) {
    final a = points[i - 1], b = points[i];
    cumulative.add(cumulative.last + _distance(a, b));
    area += a.eastMeters * b.northMeters - b.eastMeters * a.northMeters;
  }
  final length = cumulative.last;
  // Tiny, degenerate or self-cancelling windings, such as figure eights.
  if (length < 100 || length > 30000 || area.abs() * .5 < .005 * length * length) return null;
  final resampled = <MetricPoint>[];
  var segment = 1;
  for (var i = 0; i < _shapePoints; ++i) {
    final target = length * i / _shapePoints;
    while (segment + 1 < cumulative.length && cumulative[segment] < target) {
      ++segment;
    }
    final span = cumulative[segment] - cumulative[segment - 1];
    if (span <= 0) return null;
    final fraction = (target - cumulative[segment - 1]) / span;
    final a = points[segment - 1], b = points[segment];
    resampled.add(
      MetricPoint(
        a.eastMeters + (b.eastMeters - a.eastMeters) * fraction,
        a.northMeters + (b.northMeters - a.northMeters) * fraction,
      ),
    );
  }
  return RouteShape(
    origin: origin,
    points: List.unmodifiable(resampled),
    lengthMeters: length,
    direction: area < 0 ? TrackDirection.clockwise : TrackDirection.counterclockwise,
  );
}

/// [trace]'s route: the lap resampled as [RouteShape] around [origin], its
/// east metres mirrored when the recording's longitudes are west-positive
/// (as [inferTrack] does); null for a lap too short, too long, open or
/// self-cancelling to have one.
RouteShape? lapRouteShape(LapTrace trace, GeoCoordinate origin, {bool westPositive = false}) =>
    _shape(trace, origin, westPositive);

/// Whether two routes are the same circuit: same direction, length within
/// 5 %, and, for some starting offset, every point within 25 m of the other
/// route's path with an RMS of at most 10 m. Never rotated, mirrored or
/// reversed to make a match.
bool routesMatch(RouteShape a, RouteShape b, {CancellationCheck? cancelled}) {
  throwIfCancelled(cancelled);
  if (a.points.length != _shapePoints ||
      b.points.length != _shapePoints ||
      a.direction != b.direction ||
      (a.lengthMeters - b.lengthMeters).abs() > .05 * math.max(a.lengthMeters, b.lengthMeters)) {
    return false;
  }
  final offset = projectCoordinate(b.origin, a.origin);
  final scale =
      math.cos(a.origin.latitudeDegrees * radiansPerDegree) /
      math.cos(b.origin.latitudeDegrees * radiansPerDegree);
  if (!scale.isFinite || scale.abs() > 2) return false;
  final projected = [
    for (final point in b.points)
      MetricPoint(
        point.eastMeters * scale + offset.eastMeters,
        point.northMeters + offset.northMeters,
      ),
  ];
  // Each point is measured against the other route's path (its two
  // neighbouring segments), so an along-track offset is not a difference.
  for (var shift = 0; shift < _shapePoints; ++shift) {
    throwIfCancelled(cancelled);
    var squared = 0.0;
    var within = true;
    for (var i = 0; i < _shapePoints; ++i) {
      final k = (i + shift) % _shapePoints;
      final previous = projected[(k + _shapePoints - 1) % _shapePoints];
      final next = projected[(k + 1) % _shapePoints];
      final d = math.min(
        _toSegment(a.points[i], previous, projected[k]),
        _toSegment(a.points[i], projected[k], next),
      );
      if (d > 25) {
        within = false;
        break;
      }
      squared += d * d;
    }
    if (within && squared <= _shapePoints * 100.0) return true;
  }
  return false;
}

/// For each lap in [lapNumbers], the largest distance from one of its points
/// to the nearest path of any other of those laps, capped at
/// [maximumLineDeviationMeters] + 4. Empty with fewer than three laps: there
/// is no line to compare against.
Map<int, double> lapLineDeviations(
  List<LapTrace> traces,
  Set<int> lapNumbers, {
  CancellationCheck? cancelled,
}) {
  const cell = 4.0;
  const cap = maximumLineDeviationMeters + 4.0;
  final used = <LapTrace>[];
  var points = 0;
  for (final trace in traces) {
    if (lapNumbers.contains(trace.lapNumber) && trace.points.length >= 2) {
      used.add(trace);
      points += trace.points.length;
    }
  }
  if (used.length < 3 || points > 4000000) return {};
  // Coordinates in typed lists and grid entries packed into one integer,
  // so the search allocates nothing per point. The order of the search and
  // the arithmetic are those of [_toSegment], so the result is the same.
  final east = [
    for (final trace in used)
      Float64List.fromList([for (final point in trace.points) point.eastMeters]),
  ];
  final north = [
    for (final trace in used)
      Float64List.fromList([for (final point in trace.points) point.northMeters]),
  ];
  var longest = 0;
  for (final trace in used) {
    longest = math.max(longest, trace.points.length);
  }
  final indexBits = longest.bitLength;
  final indexMask = (1 << indexBits) - 1;
  int key(int x, int y) => x * 1000003 + y;
  final grid = <int, List<int>>{};
  final cellX = <Int32List>[], cellY = <Int32List>[];
  for (var lap = 0; lap < used.length; ++lap) {
    final xs = east[lap], ys = north[lap];
    final cx = Int32List(xs.length), cy = Int32List(xs.length);
    for (var index = 0; index < xs.length; ++index) {
      cx[index] = (xs[index] / cell).floor();
      cy[index] = (ys[index] / cell).floor();
      grid.putIfAbsent(key(cx[index], cy[index]), () => []).add(lap << indexBits | index);
    }
    cellX.add(cx);
    cellY.add(cy);
  }
  double toSegment(double px, double py, double ax, double ay, double bx, double by) {
    final abx = bx - ax, aby = by - ay;
    final length2 = abx * abx + aby * aby;
    final t = length2 > 0 ? (((px - ax) * abx + (py - ay) * aby) / length2).clamp(0.0, 1.0) : 0.0;
    return hypot(px - (ax + abx * t), py - (ay + aby * t));
  }

  final reach = (cap / cell).ceil();
  final result = <int, double>{};
  for (var lap = 0; lap < used.length; ++lap) {
    throwIfCancelled(cancelled);
    var worst = 0.0;
    final xs = east[lap], ys = north[lap];
    for (var sample = 0; sample < xs.length; ++sample) {
      final px = xs[sample], py = ys[sample];
      final cx = (px / cell).floor(), cy = (py / cell).floor();
      var nearest = cap;
      for (var dx = -reach; dx <= reach; ++dx) {
        for (var dy = -reach; dy <= reach; ++dy) {
          final found = grid[key(cx + dx, cy + dy)];
          if (found == null) continue;
          for (final entry in found) {
            final other = entry >> indexBits;
            if (other == lap) continue;
            final index = entry & indexMask;
            final ox = east[other], oy = north[other];
            final qx = ox[index], qy = oy[index];
            // The segment from the previous point is measured from that
            // point's entry when it is in the window too: each segment once.
            // The minimum of the same distances is the same in any order
            // (they are never negative zero).
            if (index > 0 &&
                ((cellX[other][index - 1] - cx).abs() > reach ||
                    (cellY[other][index - 1] - cy).abs() > reach)) {
              nearest = math.min(nearest, toSegment(px, py, ox[index - 1], oy[index - 1], qx, qy));
            }
            if (index + 1 < ox.length) {
              nearest = math.min(nearest, toSegment(px, py, qx, qy, ox[index + 1], oy[index + 1]));
            }
          }
        }
      }
      worst = math.max(worst, nearest);
    }
    result[used[lap].lapNumber] = worst;
  }
  return result;
}

/// The route most of a recording's complete laps follow, and which laps
/// follow it. Needs at least two matching laps, and 60 % of the laps tried.
TrackInference inferTrack(
  LapSession laps, {
  bool longitudeIsWestPositive = false,
  CancellationCheck? cancelled,
}) {
  throwIfCancelled(cancelled);
  if (laps.lapTraces.length > 20000) {
    throw const ResourceLimitError('Too many lap traces for route inference.');
  }
  const notEnough = TrackInference(
    reason: 'Not enough repeated, complete GPS laps to identify a route automatically.',
  );
  final gate = laps.selectedStartGate;
  if (gate == null || laps.lapTraces.length < 2) return notEnough;
  final midpoint = geoMidpoint(gate.endpointA, gate.endpointB);
  final origin = GeoCoordinate(
    midpoint.latitudeDegrees,
    (longitudeIsWestPositive ? -1 : 1) * midpoint.longitudeDegrees,
  );
  final candidates = <RouteShape>[];
  final stride = math.max(
    1,
    (laps.lapTraces.length + _maximumRepresentatives - 1) ~/ _maximumRepresentatives,
  );
  for (var i = 0; i < laps.lapTraces.length; i += stride) {
    throwIfCancelled(cancelled);
    final candidate = _shape(laps.lapTraces[i], origin, longitudeIsWestPositive);
    if (candidate != null) candidates.add(candidate);
  }
  if (candidates.length < 2) return notEnough;
  final clusters = <List<int>>[];
  for (var i = 0; i < candidates.length; ++i) {
    var added = false;
    for (final cluster in clusters) {
      if (cluster.every((j) => routesMatch(candidates[i], candidates[j], cancelled: cancelled))) {
        cluster.add(i);
        added = true;
        break;
      }
    }
    if (!added) clusters.add([i]);
  }
  var best = clusters.first;
  for (final cluster in clusters) {
    if (cluster.length > best.length) best = cluster;
  }
  if (best.length < 2 || best.length * 5 < candidates.length * 3) {
    return const TrackInference(
      reason: "Complete laps follow conflicting routes; review this recording's layout.",
    );
  }
  final route = candidates[best.first];
  final matching = <int>{};
  for (final trace in laps.lapTraces) {
    throwIfCancelled(cancelled);
    final shape = _shape(trace, origin, longitudeIsWestPositive);
    if (shape != null && routesMatch(route, shape, cancelled: cancelled)) {
      matching.add(trace.lapNumber);
    }
  }
  // KAN-137: a lap can match the overall shape and still leave the line
  // every other lap took (off track, a detour, the pit lane).
  final deviations = lapLineDeviations(laps.lapTraces, matching, cancelled: cancelled);
  deviations.forEach((lap, deviation) {
    if (deviation > maximumLineDeviationMeters) matching.remove(lap);
  });
  return TrackInference(route: route, matchingLaps: Set.unmodifiable(matching));
}

/// One run's input to [groupInferredTracks].
final class TrackGroupingSource {
  const TrackGroupingSource({
    required this.runId,
    required this.contentSha256,
    required this.configuration,
    this.manual = false,
  });

  final String runId;
  final String contentSha256;

  /// The run's stored configuration: the user's layout and direction when
  /// [manual], and always the recording's gate revision.
  final TrackConfiguration configuration;

  /// The user set the layout or direction; inference never overrides it.
  final bool manual;
}

/// The configurations after grouping, and the runs that could not be placed.
final class InferredTrackGroups {
  const InferredTrackGroups({required this.configurations, required this.reasons});

  final Map<String, TrackConfiguration> configurations;

  /// Run id → why its route could not be assigned automatically.
  final Map<String, String> reasons;
}

/// Groups runs whose routes match, complete-link (a near match cannot bridge
/// two incompatible routes), and gives every group a `gps-route-v1:` layout.
/// A run close to two incompatible groups is left unassigned. Manual
/// configurations are kept as they are.
InferredTrackGroups groupInferredTracks(
  Map<String, TrackInference> inferences,
  List<TrackGroupingSource> sources, {
  CancellationCheck? cancelled,
}) {
  if (sources.length > 64 || inferences.length > 64) {
    throw const ResourceLimitError('Too many runs for route grouping.');
  }
  final byId = {for (final source in sources) source.runId: source};
  final configurations = {for (final source in sources) source.runId: source.configuration};
  final reasons = <String, String>{};
  final ids = byId.keys.toList()..sort();
  bool matches(String a, String b) =>
      routesMatch(inferences[a]!.route!, inferences[b]!.route!, cancelled: cancelled);
  bool supported(String id) => inferences[id]?.supported ?? false;

  final clusters = <List<String>>[];
  for (final id in ids) {
    throwIfCancelled(cancelled);
    if (!supported(id)) continue;
    var added = false;
    for (final cluster in clusters) {
      if (cluster.every((other) => matches(id, other))) {
        cluster.add(id);
        added = true;
        break;
      }
    }
    if (!added) clusters.add([id]);
  }
  if (clusters.length > 1) {
    for (final id in ids) {
      if (!supported(id)) continue;
      var count = 0;
      for (final cluster in clusters) {
        if (cluster.every((other) => other == id || matches(id, other))) ++count;
      }
      if (count > 1) {
        reasons[id] =
            "GPS route matches more than one incompatible group; review this recording's layout.";
      }
    }
  }
  for (final cluster in clusters) {
    cluster.removeWhere(reasons.containsKey);
  }
  clusters.removeWhere((cluster) => cluster.isEmpty);
  final reserved = <String>{};
  for (final cluster in clusters) {
    final seed = utf8.encode('${cluster.first}\u0000${byId[cluster.first]!.contentSha256}');
    String layoutId;
    var salt = 0;
    do {
      layoutId =
          '$trackInferenceVersion:${sha256.convert([...seed, 0, ...ascii.encode('${salt++}')])}';
    } while (reserved.contains(layoutId));
    reserved.add(layoutId);
    for (final id in cluster) {
      final source = byId[id]!;
      if (source.manual) continue;
      configurations[id] = TrackConfiguration(
        layoutId: layoutId,
        direction: inferences[id]!.route!.direction,
        gateRevision: source.configuration.gateRevision,
      );
    }
  }
  return InferredTrackGroups(
    configurations: Map.unmodifiable(configurations),
    reasons: Map.unmodifiable(reasons),
  );
}
