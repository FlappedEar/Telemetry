import '../geometry.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import '../timing_gate.dart';
import 'lap_ranking.dart';
import 'lap_session.dart';
import 'lap_traces.dart';
import 'segment_geometry.dart';

/// Laps from the recording's own start gate. Exactly one `Start` gate is
/// required; none or several give a status and no laps.
LapSession deriveSourceLapSession(
  TelemetrySession session, {
  LapDetectionOptions options = const LapDetectionOptions(),
  CancellationCheck? cancelled,
}) {
  throwIfCancelled(cancelled);
  TimingGate? startGate;
  for (final gate in session.timingGates) {
    if (gate.type != TimingGateType.start) continue;
    if (startGate != null) {
      return LapSession(status: LapSessionStatus.ambiguousSourceStartGate);
    }
    startGate = gate;
  }
  if (startGate == null) return LapSession(status: LapSessionStatus.noSourceStartGate);
  return detectLaps(session, startGate, options: options, cancelled: cancelled);
}

final class _GpsSample {
  const _GpsSample(this.time, this.point);

  final double time;
  final Vector2 point;
}

/// The GPS fix at [index], projected around [origin], or null when the two
/// channels disagree on its time or the coordinate is invalid.
_GpsSample? _gpsSampleAt(
  TelemetryChannel latitude,
  TelemetryChannel longitude,
  int index,
  GeoCoordinate origin,
) {
  if (index < 0 ||
      index >= latitude.timestamps.length ||
      index >= latitude.values.length ||
      index >= longitude.timestamps.length ||
      index >= longitude.values.length) {
    return null;
  }
  final latitudeTime = latitude.timestamps[index];
  final longitudeTime = longitude.timestamps[index];
  final coordinate = GeoCoordinate(latitude.values[index], longitude.values[index]);
  if (!latitudeTime.isFinite || latitudeTime != longitudeTime || !isValidCoordinate(coordinate)) {
    return null;
  }
  final projected = projectCoordinate(coordinate, origin);
  if (!projected.eastMeters.isFinite || !projected.northMeters.isFinite) return null;
  return _GpsSample(latitudeTime, Vector2(projected.eastMeters, projected.northMeters));
}

/// Groups consecutive GPS segments near the gate into one candidate pass.
final class _PassageCluster {
  bool active = false;
  double firstTime = 0.0;
  double lastTime = 0.0;
  Vector2 firstPoint = const Vector2(0.0, 0.0);
  Vector2 lastPoint = const Vector2(0.0, 0.0);
  double candidateTime = 0.0;
  double candidateDistance = double.infinity;
  double candidateGateFraction = 0.0;

  /// Side of the gate line the pass started on: −1, 0 (on the line) or +1.
  int firstSide = 0;

  /// Side of the gate line at the pass's latest point.
  int lastSide = 0;

  /// Whether a segment of the pass reached the gate line within the gate's
  /// span (widened by the inner corridor at each end).
  bool reachedLineInSpan = false;
}

/// Finds passes through [startGate] and the laps between them.
///
/// A pass is a run of GPS segments that comes within the inner corridor of the
/// gate and ends when the path leaves the outer corridor. It is accepted when
/// it is short, fast enough, crosses the gate rather than running along it,
/// and really crosses the line: it starts strictly on one side, ends on the
/// line or the other side, and reaches the line within the gate's span
/// (widened by the inner corridor at each end). Coming close and leaving on
/// the same side is not a pass (FET-198; Overlays accepts it).
/// The first accepted crossing direction locks; later passes the other way are
/// rejected. A GPS gap or invalid fix breaks continuity.
LapSession detectLaps(
  TelemetrySession session,
  TimingGate startGate, {
  LapDetectionOptions options = const LapDetectionOptions(),
  CancellationCheck? cancelled,
}) {
  options.validate();
  throwIfCancelled(cancelled);
  final diagnostics = LapDetectionDiagnostics();
  LapSession result(
    LapSessionStatus status, [
    List<GatePass> passes = const [],
    List<TimedLap> laps = const [],
    List<LapTrace> traces = const [],
    int? fastest,
  ]) => LapSession(
    status: status,
    selectedStartGate: startGate,
    acceptedPasses: passes,
    timedLaps: laps,
    lapTraces: traces,
    fastestLapIndex: fastest,
    diagnostics: diagnostics,
  );

  final origin = GeoCoordinate(
    (startGate.endpointA.latitudeDegrees + startGate.endpointB.latitudeDegrees) / 2.0,
    (startGate.endpointA.longitudeDegrees + startGate.endpointB.longitudeDegrees) / 2.0,
  );
  if (!isValidCoordinate(startGate.endpointA) ||
      !isValidCoordinate(startGate.endpointB) ||
      !isValidCoordinate(origin)) {
    return result(LapSessionStatus.invalidGate);
  }
  final projectedA = projectCoordinate(startGate.endpointA, origin);
  final projectedB = projectCoordinate(startGate.endpointB, origin);
  final gateA = Vector2(projectedA.eastMeters, projectedA.northMeters);
  final gateB = Vector2(projectedB.eastMeters, projectedB.northMeters);
  final gateVector = gateB - gateA;
  final gateLength = gateVector.length;
  if (!gateLength.isFinite ||
      gateLength < options.minimumGateLengthMeters ||
      gateLength > options.maximumGateLengthMeters) {
    return result(LapSessionStatus.invalidGate);
  }
  final gateNormal = Vector2(-gateVector.y / gateLength, gateVector.x / gateLength);
  double signedDistance(Vector2 point) => (point - gateA).dot(gateNormal);
  int sideOf(Vector2 point) {
    final distance = signedDistance(point);
    return distance > 0.0 ? 1 : (distance < 0.0 ? -1 : 0);
  }

  final spanTolerance = options.innerCorridorMeters / gateLength;

  /// Whether the segment touches or crosses the gate line, and does so within
  /// the widened gate span.
  bool reachesLineInSpan(Vector2 start, Vector2 end) {
    final startDistance = signedDistance(start);
    final endDistance = signedDistance(end);
    if (startDistance == 0.0) return false;
    if (endDistance != 0.0 && (endDistance > 0.0) == (startDistance > 0.0)) return false;
    final fraction = startDistance / (startDistance - endDistance);
    final point = start + (end - start) * fraction;
    final along = (point - gateA).dot(gateVector) / (gateLength * gateLength);
    return along.isFinite && along >= -spanTolerance && along <= 1.0 + spanTolerance;
  }

  final latitude = session.channels[session.aliases['latitude']];
  final longitude = session.channels[session.aliases['longitude']];
  if (latitude == null || longitude == null) return result(LapSessionStatus.noUsableGps);

  final sampleCount = [
    latitude.timestamps.length,
    latitude.values.length,
    longitude.timestamps.length,
    longitude.values.length,
  ].reduce((a, b) => a > b ? a : b);
  final latitudeGap = telemetryGapThreshold(latitude);
  final longitudeGap = telemetryGapThreshold(longitude);
  final gapThreshold = latitudeGap > longitudeGap ? latitudeGap : longitudeGap;

  final passes = <GatePass>[];
  _GpsSample? previous;
  var cluster = _PassageCluster();
  var armed = false;
  var acceptedDirection = 0;
  double? lastAcceptedTime;

  void discardContinuity() {
    if (cluster.active) ++diagnostics.discardedGapClusters;
    cluster = _PassageCluster();
    previous = null;
    armed = false;
  }

  void finalizeCluster() {
    if (!cluster.active) return;
    ++diagnostics.candidateClusters;
    final duration = cluster.lastTime - cluster.firstTime;
    final displacement = cluster.lastPoint - cluster.firstPoint;
    final groundSpeed = duration > 0.0 ? displacement.length / duration : 0.0;
    final normalSpeed = duration > 0.0 ? displacement.dot(gateNormal) / duration : 0.0;
    final normalRatio = groundSpeed > 0.0 ? normalSpeed.abs() / groundSpeed : 0.0;
    if (!duration.isFinite || duration <= 0.0 || duration > options.maximumClusterSeconds) {
      ++diagnostics.rejectedLongClusters;
    } else if (cluster.firstSide == 0 ||
        cluster.lastSide == cluster.firstSide ||
        !cluster.reachedLineInSpan) {
      ++diagnostics.rejectedNotCrossingClusters;
    } else if (!groundSpeed.isFinite || groundSpeed < options.minimumGroundSpeedMetersPerSecond) {
      ++diagnostics.rejectedSlowClusters;
    } else if (!normalSpeed.isFinite ||
        normalSpeed.abs() < options.minimumNormalSpeedMetersPerSecond ||
        !normalRatio.isFinite ||
        normalRatio < options.minimumNormalMotionRatio) {
      ++diagnostics.rejectedParallelClusters;
    } else {
      final direction = normalSpeed > 0.0 ? 1 : -1;
      if (acceptedDirection != 0 && direction != acceptedDirection) {
        ++diagnostics.rejectedOppositeDirectionClusters;
      } else {
        if (acceptedDirection == 0) acceptedDirection = direction;
        if (passes.length >= options.maximumAcceptedPasses) {
          throw const ResourceLimitError('Lap detector produced too many accepted passes.');
        }
        passes.add(
          GatePass(
            telemetryTime: cluster.candidateTime,
            closestDistanceMeters: cluster.candidateDistance,
            direction: direction,
            gateFraction: cluster.candidateGateFraction,
            groundSpeedMetersPerSecond: groundSpeed,
            normalSpeedMetersPerSecond: normalSpeed,
          ),
        );
        lastAcceptedTime = cluster.candidateTime;
      }
    }
    cluster = _PassageCluster();
    armed = false;
  }

  for (var index = 0; index < sampleCount; ++index) {
    if ((index & 0xff) == 0) throwIfCancelled(cancelled);
    final current = _gpsSampleAt(latitude, longitude, index, origin);
    if (current == null) {
      discardContinuity();
      continue;
    }
    final before = previous;
    if (before == null) {
      previous = current;
      continue;
    }
    final interval = current.time - before.time;
    if (!interval.isFinite || interval <= 0.0 || gapThreshold <= 0.0 || interval > gapThreshold) {
      discardContinuity();
      previous = current;
      continue;
    }
    ++diagnostics.usableGpsSegments;
    final closest = closestSegments(before.point, current.point, gateA, gateB);
    if (!closest.distanceMeters.isFinite) {
      discardContinuity();
      previous = current;
      continue;
    }
    final outsideOuter = closest.distanceMeters > options.outerCorridorMeters;
    if (cluster.active && outsideOuter) finalizeCluster();
    if (!cluster.active && outsideOuter) {
      final last = lastAcceptedTime;
      if (last == null || current.time - last >= options.refractorySeconds) armed = true;
    }
    if (armed && !cluster.active && closest.distanceMeters <= options.innerCorridorMeters) {
      cluster
        ..active = true
        ..firstTime = before.time
        ..lastTime = current.time
        ..firstPoint = before.point
        ..lastPoint = current.point
        ..candidateTime = before.time + closest.vehicleFraction * interval
        ..candidateDistance = closest.distanceMeters
        ..candidateGateFraction = closest.gateFraction
        ..firstSide = sideOf(before.point)
        ..lastSide = sideOf(current.point)
        ..reachedLineInSpan = reachesLineInSpan(before.point, current.point);
    } else if (cluster.active && !outsideOuter) {
      cluster
        ..lastTime = current.time
        ..lastPoint = current.point
        ..lastSide = sideOf(current.point);
      if (reachesLineInSpan(before.point, current.point)) cluster.reachedLineInSpan = true;
      if (closest.distanceMeters < cluster.candidateDistance) {
        cluster
          ..candidateTime = before.time + closest.vehicleFraction * interval
          ..candidateDistance = closest.distanceMeters
          ..candidateGateFraction = closest.gateFraction;
      }
    }
    previous = current;
  }
  finalizeCluster();
  throwIfCancelled(cancelled);
  if (diagnostics.usableGpsSegments == 0) return result(LapSessionStatus.noUsableGps);

  final laps = <TimedLap>[];
  for (var index = 1; index < passes.length; ++index) {
    final start = passes[index - 1].telemetryTime;
    final end = passes[index].telemetryTime;
    final duration = end - start;
    if (!duration.isFinite || duration <= 0.0) {
      ++diagnostics.invalidLapDurations;
      continue;
    }
    final lap = TimedLap(
      number: laps.length + 1,
      startTelemetryTime: start,
      endTelemetryTime: end,
      durationSeconds: duration,
    );
    laps.add(
      TimedLap(
        number: lap.number,
        startTelemetryTime: start,
        endTelemetryTime: end,
        durationSeconds: duration,
        referenceIssue: _referenceIssueForLap(session, lap, origin, cancelled),
      ),
    );
  }
  final (ranked, fastest) = rankLaps(laps);
  if (passes.isEmpty) {
    return result(LapSessionStatus.noAcceptedPasses, passes, ranked, const [], fastest);
  }
  if (ranked.isEmpty) {
    return result(LapSessionStatus.insufficientPasses, passes, ranked, const [], fastest);
  }
  final traces = buildLapTraces(session, ranked, origin, cancelled);
  return result(LapSessionStatus.available, passes, ranked, traces, fastest);
}

/// Whether the GPS covers [lap] without a gap or invalid fix, from the sample
/// at or before its start through the first sample at or after its end.
LapReferenceIssue _referenceIssueForLap(
  TelemetrySession session,
  TimedLap lap,
  GeoCoordinate origin,
  CancellationCheck? cancelled,
) {
  final latitude = session.channels[session.aliases['latitude']];
  final longitude = session.channels[session.aliases['longitude']];
  if (latitude == null ||
      longitude == null ||
      latitude.timestamps.length != latitude.values.length ||
      longitude.timestamps.length != longitude.values.length ||
      latitude.timestamps.length != longitude.timestamps.length ||
      latitude.timestamps.isEmpty) {
    return LapReferenceIssue.invalidGps;
  }
  final times = latitude.timestamps;
  var first = lowerBound(times, lap.startTelemetryTime);
  if (first != 0 && (first == times.length || times[first] > lap.startTelemetryTime)) --first;
  final last = lowerBound(times, lap.endTelemetryTime, first);
  if (first == times.length || times[first] > lap.startTelemetryTime || last == times.length) {
    return LapReferenceIssue.gpsGap;
  }
  final latitudeGap = telemetryGapThreshold(latitude);
  final longitudeGap = telemetryGapThreshold(longitude);
  final threshold = latitudeGap < longitudeGap ? latitudeGap : longitudeGap;
  double? previous;
  for (var index = first; index <= last; ++index) {
    if ((index & 0xff) == 0) throwIfCancelled(cancelled);
    final sample = _gpsSampleAt(latitude, longitude, index, origin);
    if (sample == null) return LapReferenceIssue.invalidGps;
    if (previous != null &&
        (sample.time <= previous || threshold <= 0.0 || sample.time - previous > threshold)) {
      return LapReferenceIssue.gpsGap;
    }
    previous = sample.time;
  }
  return LapReferenceIssue.none;
}
