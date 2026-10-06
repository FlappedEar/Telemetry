import '../timing_gate.dart';

/// Whether laps could be derived from a recording, and why not.
enum LapSessionStatus {
  available,
  noSourceStartGate,
  ambiguousSourceStartGate,
  invalidGate,
  noUsableGps,
  noAcceptedPasses,
  insufficientPasses,
}

/// Thresholds for detecting start-gate passes. The defaults are the values
/// FlappedEar Overlays uses; [validate] gives the accepted ranges.
final class LapDetectionOptions {
  const LapDetectionOptions({
    this.innerCorridorMeters = 5.0,
    this.outerCorridorMeters = 10.0,
    this.minimumGroundSpeedMetersPerSecond = 2.0,
    this.minimumNormalSpeedMetersPerSecond = 2.0,
    this.minimumNormalMotionRatio = 0.10,
    this.refractorySeconds = 1.0,
    this.maximumClusterSeconds = 5.0,
    this.minimumGateLengthMeters = 1.0,
    this.maximumGateLengthMeters = 200.0,
    this.maximumAcceptedPasses = 100000,
  });

  /// A pass starts when the car's path comes this close to the gate.
  final double innerCorridorMeters;

  /// A pass ends when the path leaves this distance.
  final double outerCorridorMeters;
  final double minimumGroundSpeedMetersPerSecond;

  /// Speed across the gate line.
  final double minimumNormalSpeedMetersPerSecond;

  /// Share of the ground speed that must be across the gate line.
  final double minimumNormalMotionRatio;

  /// Time after an accepted pass before the next one can start.
  final double refractorySeconds;
  final double maximumClusterSeconds;
  final double minimumGateLengthMeters;
  final double maximumGateLengthMeters;
  final int maximumAcceptedPasses;

  /// Throws [ArgumentError] for values outside the supported ranges.
  void validate() {
    final values = [
      innerCorridorMeters,
      outerCorridorMeters,
      minimumGroundSpeedMetersPerSecond,
      minimumNormalSpeedMetersPerSecond,
      minimumNormalMotionRatio,
      refractorySeconds,
      maximumClusterSeconds,
      minimumGateLengthMeters,
      maximumGateLengthMeters,
    ];
    if (values.any((value) => !value.isFinite || value < 0.0) ||
        innerCorridorMeters > 50.0 ||
        outerCorridorMeters > 100.0 ||
        outerCorridorMeters <= innerCorridorMeters ||
        minimumNormalMotionRatio > 1.0 ||
        refractorySeconds > 10.0 ||
        maximumClusterSeconds <= 0.0 ||
        minimumGateLengthMeters <= 0.0 ||
        maximumGateLengthMeters > 1000.0 ||
        maximumGateLengthMeters < minimumGateLengthMeters ||
        maximumAcceptedPasses <= 0 ||
        maximumAcceptedPasses > 100000) {
      throw ArgumentError('Invalid lap-detection options.');
    }
  }
}

/// Counts of what the detector saw and rejected, for troubleshooting.
final class LapDetectionDiagnostics {
  int usableGpsSegments = 0;
  int candidateClusters = 0;
  int discardedGapClusters = 0;
  int rejectedSlowClusters = 0;
  int rejectedParallelClusters = 0;
  int rejectedLongClusters = 0;
  int rejectedOppositeDirectionClusters = 0;

  /// Passes that came near the gate but did not cross its line (FET-198).
  int rejectedNotCrossingClusters = 0;
  int invalidLapDurations = 0;
}

/// One accepted crossing of the start gate.
final class GatePass {
  const GatePass({
    required this.telemetryTime,
    required this.closestDistanceMeters,
    required this.direction,
    required this.gateFraction,
    required this.groundSpeedMetersPerSecond,
    required this.normalSpeedMetersPerSecond,
  });

  final double telemetryTime;
  final double closestDistanceMeters;

  /// +1 or −1: which side of the gate line the car crossed from. Not a
  /// clockwise or counterclockwise layout direction.
  final int direction;

  /// Where along the gate, 0 at endpoint A and 1 at endpoint B.
  final double gateFraction;
  final double groundSpeedMetersPerSecond;
  final double normalSpeedMetersPerSecond;
}

/// Why a measured lap cannot be ranked or used as a spatial reference.
enum LapReferenceIssue { none, gpsGap, invalidGps }

/// A gate-to-gate interval.
final class TimedLap {
  const TimedLap({
    required this.number,
    required this.startTelemetryTime,
    required this.endTelemetryTime,
    required this.durationSeconds,
    this.deltaToBestSeconds = 0.0,
    this.referenceIssue = LapReferenceIssue.none,
    this.userExclusionReason = '',
  });

  final int number;
  final double startTelemetryTime;
  final double endTelemetryTime;
  final double durationSeconds;

  /// Duration minus the fastest eligible lap's; 0 for an ineligible lap.
  final double deltaToBestSeconds;

  /// A measured lap stays visible even when its GPS cannot support ranking.
  final LapReferenceIssue referenceIssue;
  final String userExclusionReason;

  /// Whether the lap takes part in ranking, statistics and references.
  bool get referenceEligible =>
      referenceIssue == LapReferenceIssue.none && userExclusionReason.isEmpty;

  TimedLap copyWith({double? deltaToBestSeconds, String? userExclusionReason}) => TimedLap(
    number: number,
    startTelemetryTime: startTelemetryTime,
    endTelemetryTime: endTelemetryTime,
    durationSeconds: durationSeconds,
    deltaToBestSeconds: deltaToBestSeconds ?? this.deltaToBestSeconds,
    referenceIssue: referenceIssue,
    userExclusionReason: userExclusionReason ?? this.userExclusionReason,
  );
}

/// A position on a lap, in metres from the start gate's centre.
final class LapTracePoint {
  const LapTracePoint(this.telemetryTime, this.eastMeters, this.northMeters);

  final double telemetryTime;
  final double eastMeters;
  final double northMeters;
}

/// The path of one eligible lap, thinned to at most 4,096 points.
final class LapTrace {
  const LapTrace({
    required this.lapNumber,
    required this.startTelemetryTime,
    required this.durationSeconds,
    required this.points,
  });

  final int lapNumber;
  final double startTelemetryTime;
  final double durationSeconds;
  final List<LapTracePoint> points;
}

/// The laps of one recording.
final class LapSession {
  LapSession({
    required this.status,
    this.selectedStartGate,
    List<GatePass> acceptedPasses = const [],
    List<TimedLap> timedLaps = const [],
    List<LapTrace> lapTraces = const [],
    this.fastestLapIndex,
    LapDetectionDiagnostics? diagnostics,
  }) : acceptedPasses = List.unmodifiable(acceptedPasses),
       timedLaps = List.unmodifiable(timedLaps),
       lapTraces = List.unmodifiable(lapTraces),
       diagnostics = diagnostics ?? LapDetectionDiagnostics();

  final LapSessionStatus status;
  final TimingGate? selectedStartGate;
  final List<GatePass> acceptedPasses;
  final List<TimedLap> timedLaps;
  final List<LapTrace> lapTraces;

  /// Index into [timedLaps] of the fastest eligible lap.
  final int? fastestLapIndex;
  final LapDetectionDiagnostics diagnostics;

  LapSession withTimedLaps(List<TimedLap> laps, int? fastest) => LapSession(
    status: status,
    selectedStartGate: selectedStartGate,
    acceptedPasses: acceptedPasses,
    timedLaps: laps,
    lapTraces: lapTraces,
    fastestLapIndex: fastest,
    diagnostics: diagnostics,
  );
}
