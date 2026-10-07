// Synthetic tracks with a known centre line, laps driven along them with a
// known distance at every fix, and the projection's outcome measured against
// that ground truth (FET-215). No real data.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';

import 'sessions.dart';
import 'synthetic_loop.dart';

/// Where every synthetic track sits; any mid-latitude origin will do.
const projectionOrigin = GeoCoordinate(52.0, 21.0);

/// A closed centre line in metres around [projectionOrigin], starting at the
/// timing gate, sampled about every metre. The last point is not repeated.
final class SyntheticTrack {
  SyntheticTrack(List<(double, double)> points) : points = List.unmodifiable(points) {
    final closed = [...points, points.first];
    final cumulative = <double>[0.0];
    for (var i = 1; i < closed.length; ++i) {
      cumulative.add(
        cumulative.last +
            math.sqrt(
              math.pow(closed[i].$1 - closed[i - 1].$1, 2) +
                  math.pow(closed[i].$2 - closed[i - 1].$2, 2),
            ),
      );
    }
    _cumulative = cumulative;
    _closed = closed;
  }

  /// A loop of [loopPoints]: [half] followed by itself turned 180 degrees.
  factory SyntheticTrack.loop(List<LoopStep> half) => SyntheticTrack(loopPoints(half));

  /// A figure-eight whose two diagonals, each [diagonalMeters] long, cross
  /// at [crossingDegrees] in the middle, joined by two circular lobes. The
  /// gate is a quarter of a diagonal past the crossing, heading away from
  /// it; the lap reaches the crossing again at [figureEightCrossing].
  factory SyntheticTrack.figureEight({
    double diagonalMeters = 300.0,
    double crossingDegrees = 90.0,
  }) {
    final theta = crossingDegrees / 2.0 * math.pi / 180.0;
    final arm = diagonalMeters / 2.0;
    // The lobe's chord joins the ends of the two diagonals on one side.
    final radius = arm * math.tan(theta);
    final lobe = 180.0 + crossingDegrees;
    final points = <(double, double)>[(0.0, 0.0)];
    var heading = theta;
    void straightOn(double meters) {
      final steps = math.max(1, meters.round());
      for (var i = 0; i < steps; ++i) {
        final (x, y) = points.last;
        points.add((
          x + meters / steps * math.cos(heading),
          y + meters / steps * math.sin(heading),
        ));
      }
    }

    void turn(double degrees) {
      final angle = degrees * math.pi / 180.0;
      final steps = math.max(1, (angle.abs() * radius).round());
      final ds = angle.abs() * radius / steps;
      for (var i = 0; i < steps; ++i) {
        heading += angle / steps / 2.0;
        final (x, y) = points.last;
        points.add((x + ds * math.cos(heading), y + ds * math.sin(heading)));
        heading += angle / steps / 2.0;
      }
    }

    // From the crossing: out along one diagonal, round the right lobe
    // clockwise, back through the crossing, round the left lobe
    // anticlockwise and back to the crossing.
    straightOn(arm);
    turn(-lobe);
    straightOn(2 * arm);
    turn(lobe);
    straightOn(arm);
    points.removeLast(); // back at the crossing
    // Start halfway along the first arm, heading away from the crossing.
    final start = (arm / 2).round();
    final (startX, startY) = points[start];
    return SyntheticTrack([
      for (var i = 0; i < points.length; ++i)
        (
          points[(start + i) % points.length].$1 - startX,
          points[(start + i) % points.length].$2 - startY,
        ),
    ]);
  }

  final List<(double, double)> points;
  late final List<(double, double)> _closed;
  late final List<double> _cumulative;

  double get lengthMeters => _cumulative.last;

  /// The centre line at [meters] from the gate, wrapping round the loop,
  /// and its unit tangent.
  ((double, double), (double, double)) at(double meters) {
    var s = meters % lengthMeters;
    if (s < 0) s += lengthMeters;
    var low = 0, high = _cumulative.length - 1;
    while (high - low > 1) {
      final middle = (low + high) >> 1;
      if (_cumulative[middle] <= s) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final a = _closed[low], b = _closed[high];
    final span = _cumulative[high] - _cumulative[low];
    final f = span > 0 ? (s - _cumulative[low]) / span : 0.0;
    final tx = (b.$1 - a.$1) / span, ty = (b.$2 - a.$2) / span;
    return ((a.$1 + (b.$1 - a.$1) * f, a.$2 + (b.$2 - a.$2) * f), (tx, ty));
  }

  /// Signed curvature at [meters] (positive turns left), from the heading
  /// change over 5 m either side.
  double curvatureAt(double meters) {
    final (_, (ax, ay)) = at(meters - 5.0);
    final (_, (bx, by)) = at(meters + 5.0);
    final change = math.atan2(ax * by - ay * bx, ax * bx + ay * by);
    return change / 10.0;
  }

  /// The gate: 20 m across the centre line at the start, its middle there.
  TimingGate get gate {
    final ((x, y), (tx, ty)) = at(0.0);
    final a = unprojectCoordinate(x - ty * 10.0, y + tx * 10.0, projectionOrigin);
    final b = unprojectCoordinate(x + ty * 10.0, y - tx * 10.0, projectionOrigin);
    return TimingGate(type: TimingGateType.start, sourceName: 'Start', endpointA: a, endpointB: b);
  }

  /// The progress axis of the centre line itself, as the reference lap.
  ProgressAxis axis() => buildProgressAxis(
    LapTrace(
      lapNumber: 1,
      startTelemetryTime: 0.0,
      durationSeconds: points.length.toDouble(),
      points: [
        for (var i = 0; i < points.length; ++i)
          LapTracePoint(i.toDouble(), points[i].$1, points[i].$2),
      ],
    ),
    projectionOrigin,
    gate,
  );

  /// The fastest speed (m/s) at [meters] for [lateralG] of cornering, at
  /// most [topSpeed]: slow in hairpins, fast on straights.
  double cornerSpeed(double meters, {double lateralG = 1.2, double topSpeed = 45.0}) {
    final curvature = curvatureAt(meters).abs();
    if (curvature < 1e-6) return topSpeed;
    return math.min(topSpeed, math.sqrt(lateralG * 9.81 / curvature));
  }
}

/// Where a lap of [SyntheticTrack.figureEight] with the same arguments
/// crosses its other diagonal, in metres from the gate.
double figureEightCrossing({double diagonalMeters = 300.0, double crossingDegrees = 90.0}) {
  final arm = diagonalMeters / 2.0;
  final radius = arm * math.tan(crossingDegrees / 2.0 * math.pi / 180.0);
  final lobe = radius * (180.0 + crossingDegrees) * math.pi / 180.0;
  return arm / 2.0 + lobe + arm;
}

/// One lap driven on a [SyntheticTrack]: the GPS session and, for each fix,
/// the true distance from the gate along the centre line (unwrapped, so
/// from 0 to the track length).
final class DrivenTrackLap {
  DrivenTrackLap(this.session, this.times, this.truth);

  final TelemetrySession session;
  final List<double> times;
  final List<double> truth;

  double get endTime => times.last;

  /// Each fix in metres around [projectionOrigin], as the projection sees it.
  List<MetricPoint> get localPoints {
    final latitude = session.channel('latitude')!, longitude = session.channel('longitude')!;
    return [
      for (var i = 0; i < times.length; ++i)
        projectCoordinate(GeoCoordinate(latitude.values[i], longitude.values[i]), projectionOrigin),
    ];
  }
}

/// Drives one lap of [track] from the gate, a fix every [interval] seconds,
/// at [speed] (m/s) as a function of distance (default: [cornerSpeed]),
/// [lateral] metres to the left of the centre line as a function of
/// distance, plus seeded GPS error of about [noise] metres (standard
/// deviation) in each direction. Like a real receiver's, the error is
/// correlated over [noiseSeconds] (a first-order random walk back to zero);
/// 0 makes it independent from fix to fix, uniform within ±[noise] m.
/// [schedule] replaces the distances driven: it gets each fix's index and
/// returns its distance, or null when the lap is over.
DrivenTrackLap driveTrack(
  SyntheticTrack track, {
  double interval = 0.1,
  double Function(double meters)? speed,
  double Function(double meters)? lateral,
  double noise = 0.0,
  double noiseSeconds = 1.0,
  int seed = 1,
  bool Function(double meters)? dropFix,
  double? Function(int index)? schedule,
}) {
  final random = math.Random(seed);
  final times = <double>[], latitudes = <double>[], longitudes = <double>[], truth = <double>[];
  var s = 0.0, t = 0.0;
  var errorX = 0.0, errorY = 0.0;
  final keep = noiseSeconds > 0 ? math.exp(-interval / noiseSeconds) : 0.0;
  // Uniform with the given standard deviation (√3 σ either side).
  double draw() => noise * math.sqrt(3.0) * (2 * random.nextDouble() - 1);
  double step(double error) => noiseSeconds > 0
      ? keep * error + math.sqrt(1 - keep * keep) * draw()
      : noise * (2 * random.nextDouble() - 1);
  if (noiseSeconds > 0) {
    errorX = draw();
    errorY = draw();
  }
  for (var index = 0; ; ++index) {
    final double meters;
    if (schedule != null) {
      final next = schedule(index);
      if (next == null) break;
      meters = next;
    } else {
      if (s > track.lengthMeters) break;
      meters = s;
    }
    if (!(dropFix?.call(meters) ?? false)) {
      final ((x, y), (tx, ty)) = track.at(meters);
      final offset = lateral?.call(meters) ?? 0.0;
      errorX = step(errorX);
      errorY = step(errorY);
      final coordinate = unprojectCoordinate(
        x - ty * offset + errorX,
        y + tx * offset + errorY,
        projectionOrigin,
      );
      times.add(t);
      latitudes.add(coordinate.latitudeDegrees);
      longitudes.add(coordinate.longitudeDegrees);
      truth.add(meters);
    }
    s += (speed ?? track.cornerSpeed)(s) * interval;
    t += interval;
  }
  return DrivenTrackLap(gpsSession(times, latitudes, longitudes), times, truth);
}

/// How a lap's projection compares with its ground truth.
final class ProjectionOutcome {
  ProjectionOutcome({
    required this.segments,
    required this.fixes,
    required this.projected,
    required this.maximumError,
    required this.largestBackwardStep,
    required this.firstProgress,
    required this.lastProgress,
  });

  final int segments;
  final int fixes;

  /// Fixes with a projected sample.
  final int projected;

  /// Largest |projected − true| distance over the projected fixes, metres.
  final double maximumError;

  /// Largest fall in progress from one projected fix to the next across the
  /// whole lap, segments included; 0 when it never falls.
  final double largestBackwardStep;
  final double firstProgress;
  final double lastProgress;

  /// Every fix projected, in one segment, within [errorMeters] of the truth.
  bool tracks(double errorMeters) =>
      segments == 1 && projected == fixes && maximumError <= errorMeters;

  @override
  String toString() =>
      '$segments segment(s), $projected/$fixes fixes, '
      'max error ${maximumError.toStringAsFixed(2)} m, '
      'largest backward step ${largestBackwardStep.toStringAsFixed(2)} m';
}

/// Projects [lap] onto [axis] with [projectLapTrace] and measures it against
/// the truth, scaled to the axis length.
ProjectionOutcome measureProjection(ProgressAxis axis, SyntheticTrack track, DrivenTrackLap lap) {
  final segments = projectLapTrace(axis, lap.session, 0.0, lap.endTime);
  final scale = axis.lengthMeters / track.lengthMeters;
  final truthAt = {for (var i = 0; i < lap.times.length; ++i) lap.times[i]: lap.truth[i] * scale};
  var maximumError = 0.0, backward = 0.0, projected = 0;
  double? previous;
  for (final segment in segments) {
    for (final sample in segment.samples) {
      ++projected;
      final truth = truthAt[sample.telemetryTime]!;
      maximumError = math.max(maximumError, (sample.progressMeters - truth).abs());
      if (previous != null) backward = math.max(backward, previous - sample.progressMeters);
      previous = sample.progressMeters;
    }
  }
  return ProjectionOutcome(
    segments: segments.length,
    fixes: lap.times.length,
    projected: projected,
    maximumError: maximumError,
    largestBackwardStep: backward,
    firstProgress: segments.isEmpty ? double.nan : segments.first.samples.first.progressMeters,
    lastProgress: segments.isEmpty ? double.nan : segments.last.samples.last.progressMeters,
  );
}
