// Port of FlappedEar Overlays native/src/telemetry/TimeLoss.{h,cpp}
// (revision d4d1039, FET-32): time-loss windows between two laps, one per
// approved segment, and the day's largest losses against a reference lap.
//
// Over a window the A-minus-B delta changes by exactly A's time through the
// window minus B's: the window's increment. Positive means A lost time there.
// The running delta at the window's entry and exit is reported separately:
// "A is 1.2 s behind here" is not "A lost 1.2 s here".
import 'package:fetproject/fetproject.dart' show TrackSegmentType, trackSegmentTypeName;

import 'sector_timing.dart';
import 'track_segment_review.dart';

/// The algorithm a [TimeLossObservations] result is stamped with.
const String timeLossAlgorithm = 'time-loss-windows-v1';

/// A window's role.
const String timeLossRoleCorner = 'corner';

/// A straight right after a corner, so time lost on the exit is not counted
/// in the corner.
const String timeLossRoleContinuation = 'continuation';
const String timeLossRoleStraight = 'straight';
const String timeLossRoleSector = 'sector';

/// Why a window has no increment: either lap has no complete time through it.
const String timeLossUntimed = 'untimed';

/// Two window ends closer than this are the same boundary.
const double timeLossAdjacencyMeters = 0.5;

/// Why two laps cannot be compared.
const String timeLossDifferentSegmentOrRevision = 'differentSegmentOrRevision';

/// Why there is no ranking: no reference lap.
const String timeLossNoReference = 'noReferenceLap';

/// One approved segment as a loss window between laps A and B.
final class TimeLossWindow {
  const TimeLossWindow({
    required this.segmentId,
    required this.name,
    required this.type,
    required this.role,
    this.cornerSegmentId = '',
    required this.startProgressMeters,
    required this.endProgressMeters,
    this.incrementSeconds,
    this.cumulativeAtStartSeconds,
    this.cumulativeAtEndSeconds,
    this.unavailableReason = '',
  });

  final String segmentId;
  final String name;
  final String type;
  final String role;

  /// For a continuation: the corner it follows.
  final String cornerSegmentId;
  final double startProgressMeters;
  final double endProgressMeters;

  /// A minus B through this window.
  final double? incrementSeconds;

  /// Running A-minus-B delta at entry.
  final double? cumulativeAtStartSeconds;

  /// Running A-minus-B delta at exit.
  final double? cumulativeAtEndSeconds;

  /// Set when [incrementSeconds] is null.
  final String unavailableReason;
}

/// Every window between two laps.
final class TimeLossObservations {
  TimeLossObservations({
    this.stamp = const SegmentationResultStamp(),
    List<TimeLossWindow> windows = const [],
    this.timedIncrementSumSeconds = 0.0,
    this.allWindowsTimed = false,
    this.unavailableReason = '',
    this.valid = false,
  }) : windows = List.unmodifiable(windows);

  final SegmentationResultStamp stamp;

  /// In track order.
  final List<TimeLossWindow> windows;

  /// Sum of every timed increment; the lap-time difference with a complete
  /// partition and every window timed.
  final double timedIncrementSumSeconds;
  final bool allWindowsTimed;
  final String unavailableReason;
  final bool valid;
}

bool _sameBoundary(double first, double second, double axisLengthMeters) {
  if ((first - second).abs() <= timeLossAdjacencyMeters) return true;
  // A corner ending at the gate continues onto a straight starting at it.
  return axisLengthMeters > 0.0 &&
      ((first - second).abs() - axisLengthMeters).abs() <= timeLossAdjacencyMeters;
}

bool _stampMatches(LapSectorTimes times, ApprovedSegmentation approved) =>
    times.valid &&
    times.stamp.revision == approved.revision &&
    times.stamp.trackConfigurationReference == approved.trackConfigurationReference;

bool _hasSegments(ApprovedSegmentation approved) =>
    approved.valid && approved.revision.isNotEmpty && approved.segments.isNotEmpty;

/// The windows between laps [a] and [b], both timed against [approved] on
/// one shared axis of [axisLengthMeters]. [lapStartA] and [lapStartB] are
/// the laps' timed starts, used only for the running deltas.
TimeLossObservations computeTimeLossObservations(
  ApprovedSegmentation approved,
  double axisLengthMeters,
  LapSectorTimes a,
  double lapStartA,
  LapSectorTimes b,
  double lapStartB,
) {
  if (!_hasSegments(approved)) {
    return TimeLossObservations(unavailableReason: 'noApprovedSegmentation');
  }
  if (!_stampMatches(a, approved) || !_stampMatches(b, approved)) {
    return TimeLossObservations(unavailableReason: timeLossDifferentSegmentOrRevision);
  }
  final ordered = [...a.sectors]
    ..sort((left, right) => left.startProgressMeters.compareTo(right.startProgressMeters));
  double? cumulative(double? timeA, double startA, double? timeB, double startB) =>
      timeA == null || timeB == null ? null : (timeA - startA) - (timeB - startB);

  final corner = trackSegmentTypeName(TrackSegmentType.corner);
  final straight = trackSegmentTypeName(TrackSegmentType.straight);
  var allTimed = true;
  var sum = 0.0;
  final windows = <TimeLossWindow>[];
  for (final sectorA in ordered) {
    var role = timeLossRoleSector, cornerId = '';
    if (sectorA.type == corner) {
      role = timeLossRoleCorner;
    } else if (sectorA.type == straight) {
      role = timeLossRoleStraight;
      for (final candidate in ordered) {
        if (candidate.type == corner &&
            _sameBoundary(
              candidate.endProgressMeters,
              sectorA.startProgressMeters,
              axisLengthMeters,
            )) {
          role = timeLossRoleContinuation;
          cornerId = candidate.segmentId;
          break;
        }
      }
    }
    final sectorB = b.sector(sectorA.segmentId);
    double? atStart, atEnd, increment;
    if (sectorB != null) {
      atStart = cumulative(sectorA.startTime, lapStartA, sectorB.startTime, lapStartB);
      atEnd = cumulative(sectorA.endTime, lapStartA, sectorB.endTime, lapStartB);
    }
    if (sectorB != null && sectorA.seconds != null && sectorB.seconds != null) {
      increment = sectorA.seconds! - sectorB.seconds!;
      // A gate-crossing window ends in the next lap's opening metres; its exit
      // is this lap's running delta plus the window's increment.
      if (sectorA.endProgressMeters < sectorA.startProgressMeters && atStart != null) {
        atEnd = atStart + increment;
      }
      sum += increment;
    } else {
      allTimed = false;
    }
    windows.add(
      TimeLossWindow(
        segmentId: sectorA.segmentId,
        name: sectorA.name,
        type: sectorA.type,
        role: role,
        cornerSegmentId: cornerId,
        startProgressMeters: sectorA.startProgressMeters,
        endProgressMeters: sectorA.endProgressMeters,
        incrementSeconds: increment,
        cumulativeAtStartSeconds: atStart,
        cumulativeAtEndSeconds: atEnd,
        unavailableReason: increment == null ? timeLossUntimed : '',
      ),
    );
  }
  return TimeLossObservations(
    stamp: segmentationResultStamp(approved, timeLossAlgorithm),
    windows: windows,
    timedIncrementSumSeconds: sum,
    allWindowsTimed: allTimed,
    valid: true,
  );
}

/// A lap's sector times with its timed start.
final class TimedLapSectors {
  const TimedLapSectors(this.times, this.startTime);

  final LapSectorTimes times;
  final double startTime;
}

/// One observed loss: a window where a lap took longer than the reference.
final class RankedTimeLoss {
  const RankedTimeLoss({
    required this.lapReference,
    required this.lapStartTime,
    required this.window,
    required this.lossSeconds,
    required this.coverageLap,
    required this.coverageReference,
  });

  final Object? lapReference;
  final double lapStartTime;
  final TimeLossWindow window;
  final double lossSeconds;

  /// Covered fraction of the window, 0 to 1.
  final double coverageLap;
  final double coverageReference;
}

/// The largest losses of a population of laps against a reference lap.
final class TimeLossRanking {
  TimeLossRanking({
    this.stamp = const SegmentationResultStamp(),
    this.referenceLap,
    List<RankedTimeLoss> losses = const [],
    this.observationCount = 0,
    this.comparedLapCount = 0,
    this.untimedWindowCount = 0,
    this.unavailableReason = '',
    this.valid = false,
  }) : losses = List.unmodifiable(losses);

  final SegmentationResultStamp stamp;
  final Object? referenceLap;

  /// Largest first, at most the requested count.
  final List<RankedTimeLoss> losses;

  /// Positive increments before truncation.
  final int observationCount;
  final int comparedLapCount;
  final int untimedWindowCount;
  final String unavailableReason;
  final bool valid;
}

/// Every positive increment of every lap of [laps] against [reference],
/// largest first, at most [maximumResults] (all when negative). Gains and
/// the reference lap itself are not losses. Ties are broken by track
/// position, then by lap start.
TimeLossRanking rankTimeLosses(
  ApprovedSegmentation approved,
  double axisLengthMeters,
  List<TimedLapSectors> laps,
  TimedLapSectors reference, {
  int maximumResults = 50,
}) {
  if (!reference.times.valid || reference.times.lapReference == null) {
    return TimeLossRanking(unavailableReason: timeLossNoReference);
  }
  if (!_hasSegments(approved)) {
    return TimeLossRanking(unavailableReason: 'noApprovedSegmentation');
  }
  double coverage(LapSectorTimes times, String segmentId) {
    final sector = times.sector(segmentId);
    if (sector == null || sector.lengthMeters <= 0.0) return 0.0;
    return (sector.coveredMeters / sector.lengthMeters).clamp(0.0, 1.0);
  }

  final losses = <RankedTimeLoss>[];
  var compared = 0, untimed = 0;
  for (final lap in laps) {
    if (lap.times.lapReference == reference.times.lapReference) continue;
    final observations = computeTimeLossObservations(
      approved,
      axisLengthMeters,
      lap.times,
      lap.startTime,
      reference.times,
      reference.startTime,
    );
    if (!observations.valid) continue;
    ++compared;
    for (final window in observations.windows) {
      final increment = window.incrementSeconds;
      if (increment == null) {
        ++untimed;
        continue;
      }
      if (increment <= 0.0) continue;
      losses.add(
        RankedTimeLoss(
          lapReference: lap.times.lapReference,
          lapStartTime: lap.startTime,
          window: window,
          lossSeconds: increment,
          coverageLap: coverage(lap.times, window.segmentId),
          coverageReference: coverage(reference.times, window.segmentId),
        ),
      );
    }
  }
  final count = losses.length;
  losses.sort((left, right) {
    if (left.lossSeconds != right.lossSeconds) {
      return left.lossSeconds > right.lossSeconds ? -1 : 1;
    }
    final byPosition = left.window.startProgressMeters.compareTo(right.window.startProgressMeters);
    if (byPosition != 0) return byPosition;
    return left.lapStartTime.compareTo(right.lapStartTime);
  });
  return TimeLossRanking(
    stamp: segmentationResultStamp(approved, timeLossAlgorithm),
    referenceLap: reference.times.lapReference,
    losses: maximumResults >= 0 && losses.length > maximumResults
        ? losses.sublist(0, maximumResults)
        : losses,
    observationCount: count,
    comparedLapCount: compared,
    untimedWindowCount: untimed,
    valid: true,
  );
}
