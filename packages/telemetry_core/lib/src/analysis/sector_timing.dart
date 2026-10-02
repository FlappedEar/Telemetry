// Port of FlappedEar Overlays native/src/telemetry/SectorTiming.{h,cpp}
// (revision d4d1039, FET-32): sector times per lap from the approved segments.
// Boundary crossings are interpolated on the lap's projection onto the shared
// progress axis; the gate boundaries (progress 0 and the axis length) use the
// lap's own timed start and end.
import 'dart:math' as math;

import 'track_progress.dart';
import 'track_segment_review.dart';

/// The algorithm a [LapSectorTimes] result is stamped with.
const String sectorTimingAlgorithm = 'sector-timing-v1';

/// A complete partition's sector times must sum to the lap time within this.
const double sectorSumToleranceSeconds = 0.001;

/// Projection of a gate-to-gate lap starts and ends a few samples inside the
/// gate; coverage within this distance of either gate counts as reaching it.
const double gateCoverageToleranceMeters = 15.0;

/// Why a sector has no time: no longer produced (a sector crossing the gate is
/// timed within the lap, its part after its start plus its part before its
/// end), kept for stored results.
const String sectorCrossesGate = 'crossesGate';

/// Why a sector has no time: a GPS or projection gap inside it or at a
/// boundary.
const String sectorIncompleteCoverage = 'incompleteCoverage';

/// Why two laps' sectors cannot be compared.
const String sectorTimeDifferentSegmentOrRevision = 'differentSegmentOrRevision';
const String sectorTimeSegmentNotFound = 'segmentNotFound';

const double _boundaryEpsilon = 1e-6;

/// One approved segment timed on one lap.
final class SectorTime {
  const SectorTime({
    required this.segmentId,
    required this.name,
    required this.type,
    required this.startProgressMeters,
    required this.endProgressMeters,
    this.lengthMeters = 0.0,
    this.coveredMeters = 0.0,
    this.startTime,
    this.endTime,
    this.seconds,
    this.unavailableReason = '',
  });

  final String segmentId;
  final String name;

  /// `sector`, `corner` or `straight`.
  final String type;
  final double startProgressMeters;

  /// Below [startProgressMeters] when the segment crosses the gate.
  final double endProgressMeters;
  final double lengthMeters;

  /// Projected coverage of the lap inside the sector.
  final double coveredMeters;

  /// Telemetry time at the start boundary.
  final double? startTime;

  /// Telemetry time at the end boundary.
  final double? endTime;

  /// Only when the whole sector is covered.
  final double? seconds;

  /// Set when [seconds] is null.
  final String unavailableReason;
}

/// Every approved segment timed on one lap.
final class LapSectorTimes {
  LapSectorTimes({
    required this.lapReference,
    this.stamp = const SegmentationResultStamp(),
    List<SectorTime> sectors = const [],
    this.completePartition = false,
    this.lapSeconds = 0.0,
    this.sumSeconds,
    this.partitionErrorSeconds,
    this.valid = false,
  }) : sectors = List.unmodifiable(sectors);

  /// The lap's identity; compared with `==`.
  final Object? lapReference;
  final SegmentationResultStamp stamp;

  /// In approved order.
  final List<SectorTime> sectors;

  /// True when the approved segments tile the whole lap without gaps, so their
  /// times can be compared with the lap time.
  final bool completePartition;
  final double lapSeconds;

  /// With a complete partition and every sector timed.
  final double? sumSeconds;

  /// |[sumSeconds] − [lapSeconds]|.
  final double? partitionErrorSeconds;
  final bool valid;

  /// The sector of [segmentId], or null.
  SectorTime? sector(String segmentId) {
    for (final sector in sectors) {
      if (sector.segmentId == segmentId) return sector;
    }
    return null;
  }
}

typedef _Range = ({double start, double end});

// Progress ranges the lap's projection covers, merged, with the ends snapped
// to the gate when they stop within the gate tolerance of it.
List<_Range> _coverage(List<ProgressSegment> lap, double length) {
  final ranges = <_Range>[
    for (final segment in lap)
      if (segment.samples.isNotEmpty)
        (start: segment.samples.first.progressMeters, end: segment.samples.last.progressMeters),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Range>[];
  for (final range in ranges) {
    if (merged.isNotEmpty && range.start <= merged.last.end + _boundaryEpsilon) {
      merged.last = (start: merged.last.start, end: math.max(merged.last.end, range.end));
    } else {
      merged.add(range);
    }
  }
  if (merged.isNotEmpty) {
    if (merged.first.start <= gateCoverageToleranceMeters) {
      merged.first = (start: 0.0, end: merged.first.end);
    }
    if (merged.last.end >= length - gateCoverageToleranceMeters) {
      merged.last = (start: merged.last.start, end: length);
    }
  }
  return merged;
}

double _coveredWithin(List<_Range> ranges, double from, double to) {
  var covered = 0.0;
  for (final range in ranges) {
    covered += math.max(0.0, math.min(range.end, to) - math.max(range.start, from));
  }
  return covered;
}

bool _fullyCovered(List<_Range> ranges, double from, double to) => ranges.any(
  (range) => range.start <= from + _boundaryEpsilon && range.end >= to - _boundaryEpsilon,
);

double? _crossingTime(
  List<ProgressSegment> lap,
  double progress,
  double length,
  double lapStartTime,
  double lapEndTime,
) {
  if (progress <= _boundaryEpsilon) return lapStartTime;
  if (progress >= length - _boundaryEpsilon) return lapEndTime;
  return timeAtProgress(lap, progress);
}

double _number(Object? value) => value is num ? value.toDouble() : 0.0;
String _text(Object? value) => value is String ? value : '';

/// The time of every approved segment of [approved] on one lap: [lapTrace]
/// is the lap's projection onto the axis (of [axisLengthMeters]) the
/// segments were approved on, timed from [lapStartTime] to [lapEndTime].
LapSectorTimes computeLapSectorTimes(
  ApprovedSegmentation approved,
  double axisLengthMeters,
  List<ProgressSegment> lapTrace,
  double lapStartTime,
  double lapEndTime,
  Object? lapReference,
) {
  if (!approved.valid ||
      !axisLengthMeters.isFinite ||
      axisLengthMeters <= 0.0 ||
      !lapStartTime.isFinite ||
      !lapEndTime.isFinite ||
      lapEndTime <= lapStartTime) {
    return LapSectorTimes(lapReference: lapReference);
  }
  final length = axisLengthMeters;
  final ranges = _coverage(lapTrace, length);
  final lapSeconds = lapEndTime - lapStartTime;

  var allTimed = approved.segments.isNotEmpty;
  var sum = 0.0;
  final tiles = <_Range>[]; // every segment's extent on [0, length], split at the gate
  final sectors = <SectorTime>[];
  for (final segment in approved.segments) {
    final start = _number(segment['startProgressMeters']);
    final end = _number(segment['endProgressMeters']);
    final startTime = _crossingTime(lapTrace, start, length, lapStartTime, lapEndTime);
    final endTime = _crossingTime(lapTrace, end, length, lapStartTime, lapEndTime);
    double sectorLength, covered;
    double? seconds;
    if (end < start) {
      // Its two parts lie at opposite ends of a gate-to-gate lap: timed within
      // this lap as the part after its start plus the part before its end.
      // Each part must be fully covered.
      sectorLength = end + length - start;
      covered = _coveredWithin(ranges, start, length) + _coveredWithin(ranges, 0.0, end);
      tiles
        ..add((start: start, end: length))
        ..add((start: 0.0, end: end));
      if (_fullyCovered(ranges, start, length) &&
          _fullyCovered(ranges, 0.0, end) &&
          startTime != null &&
          endTime != null &&
          lapEndTime - startTime > 0.0 &&
          endTime - lapStartTime > 0.0) {
        seconds = (lapEndTime - startTime) + (endTime - lapStartTime);
      }
    } else {
      sectorLength = end - start;
      covered = _coveredWithin(ranges, start, end);
      tiles.add((start: start, end: end));
      if (_fullyCovered(ranges, start, end) &&
          startTime != null &&
          endTime != null &&
          endTime > startTime) {
        seconds = endTime - startTime;
      }
    }
    if (seconds != null) {
      sum += seconds;
    } else {
      allTimed = false;
    }
    sectors.add(
      SectorTime(
        segmentId: _text(segment['id']),
        name: _text(segment['name']),
        type: _text(segment['type']),
        startProgressMeters: start,
        endProgressMeters: end,
        lengthMeters: sectorLength,
        coveredMeters: covered,
        startTime: startTime,
        endTime: endTime,
        seconds: seconds,
        unavailableReason: seconds == null ? sectorIncompleteCoverage : '',
      ),
    );
  }
  tiles.sort((a, b) => a.start.compareTo(b.start));
  var complete = tiles.isNotEmpty;
  var reached = 0.0;
  for (final tile in tiles) {
    if ((tile.start - reached).abs() > _boundaryEpsilon) complete = false;
    reached = tile.end;
  }
  if (complete && (reached - length).abs() > _boundaryEpsilon) complete = false;
  return LapSectorTimes(
    lapReference: lapReference,
    stamp: segmentationResultStamp(approved, sectorTimingAlgorithm),
    sectors: sectors,
    completePartition: complete,
    lapSeconds: lapSeconds,
    sumSeconds: complete && allTimed ? sum : null,
    partitionErrorSeconds: complete && allTimed ? (sum - lapSeconds).abs() : null,
    valid: true,
  );
}

/// Metres of [fromMeters]..[toMeters] covered by the lap's projection, with
/// the same gate tolerance as sector timing.
double projectedCoverageMeters(
  List<ProgressSegment> lapTrace,
  double fromMeters,
  double toMeters,
  double axisLengthMeters,
) {
  if (!axisLengthMeters.isFinite || axisLengthMeters <= 0.0 || !(toMeters >= fromMeters)) {
    return 0.0;
  }
  return _coveredWithin(_coverage(lapTrace, axisLengthMeters), fromMeters, toMeters);
}

/// Lap A's time minus lap B's through one segment.
final class SectorTimeComparison {
  const SectorTimeComparison({this.secondsDelta, this.unavailableReason = '', this.valid = false});

  final double? secondsDelta;
  final String unavailableReason;
  final bool valid;
}

/// A minus B for [segmentId], from two laps' results for the same approved
/// revision.
SectorTimeComparison compareSectorTimes(LapSectorTimes a, LapSectorTimes b, String segmentId) {
  if (!a.valid ||
      !b.valid ||
      a.stamp.revision != b.stamp.revision ||
      a.stamp.trackConfigurationReference != b.stamp.trackConfigurationReference) {
    return const SectorTimeComparison(unavailableReason: sectorTimeDifferentSegmentOrRevision);
  }
  final sectorA = a.sector(segmentId), sectorB = b.sector(segmentId);
  if (sectorA == null || sectorB == null) {
    return const SectorTimeComparison(unavailableReason: sectorTimeSegmentNotFound);
  }
  if (sectorA.seconds != null && sectorB.seconds != null) {
    return SectorTimeComparison(secondsDelta: sectorA.seconds! - sectorB.seconds!, valid: true);
  }
  return SectorTimeComparison(
    unavailableReason: sectorA.unavailableReason.isNotEmpty
        ? sectorA.unavailableReason
        : sectorB.unavailableReason,
    valid: true,
  );
}
