// Port of FlappedEar Overlays native/src/telemetry/TheoreticalBest.{h,cpp}
// (revision d4d1039, FET-32): for each approved segment, the fastest time any
// lap of a compatible population actually recorded. Every contributing lap
// was timed against the same approved revision, so each segment's winner is
// a real, attributable result.
import 'sector_timing.dart';
import 'track_segment_review.dart';

/// The algorithm a [TheoreticalBestLap] is stamped with.
const String theoreticalBestAlgorithm = 'theoretical-best-v1';

/// No approved segments to measure sectors against.
const String theoreticalBestNoApprovedSegmentation = 'noApprovedSegmentation';

/// At least one segment has no valid time on any lap; the total is withheld,
/// the other segments still show.
const String theoreticalBestIncompleteCoverage = 'incompleteCoverage';

/// The fastest time through one approved segment.
final class TheoreticalBestSector {
  const TheoreticalBestSector({
    required this.segmentId,
    required this.name,
    required this.type,
    this.seconds,
    this.sourceLapReference,
    this.unavailableReason = '',
  });

  final String segmentId;
  final String name;
  final String type;

  /// The fastest valid time across the population.
  final double? seconds;

  /// The lap that recorded it.
  final Object? sourceLapReference;

  /// Set when [seconds] is null.
  final String unavailableReason;
}

/// A theoretical best lap: the fastest time of every approved segment.
final class TheoreticalBestLap {
  TheoreticalBestLap({
    this.stamp = const SegmentationResultStamp(),
    List<TheoreticalBestSector> sectors = const [],
    this.totalSeconds,
    this.unavailableReason = '',
    this.valid = false,
  }) : sectors = List.unmodifiable(sectors);

  final SegmentationResultStamp stamp;

  /// In approved order.
  final List<TheoreticalBestSector> sectors;

  /// Only when every sector has a time.
  final double? totalSeconds;

  /// Set when [totalSeconds] is null or nothing was computed.
  final String unavailableReason;

  /// Approved segments existed and the computation ran.
  final bool valid;
}

/// The fastest valid time of each approved segment across [population], the
/// laps' own sector times on the axis of [approved]. A result for another
/// revision or track configuration is ignored. Only laps already filtered
/// into the compatible population (exclusions applied) should be passed.
/// The first lap with the fastest time wins a tie.
TheoreticalBestLap computeTheoreticalBest(
  ApprovedSegmentation approved,
  List<LapSectorTimes> population,
) {
  if (!approved.valid || approved.revision.isEmpty || approved.segments.isEmpty) {
    return TheoreticalBestLap(unavailableReason: theoreticalBestNoApprovedSegmentation);
  }
  var total = 0.0;
  var complete = true;
  final sectors = <TheoreticalBestSector>[];
  for (final segment in approved.segments) {
    final id = segment['id'] is String ? segment['id'] as String : '';
    double? seconds;
    Object? source;
    for (final lap in population) {
      if (!lap.valid ||
          lap.stamp.revision != approved.revision ||
          lap.stamp.trackConfigurationReference != approved.trackConfigurationReference) {
        continue;
      }
      for (final candidate in lap.sectors) {
        final time = candidate.seconds;
        if (candidate.segmentId != id || time == null) continue;
        if (seconds == null || time < seconds) {
          seconds = time;
          source = lap.lapReference;
        }
      }
    }
    if (seconds == null) {
      complete = false;
    } else {
      total += seconds;
    }
    sectors.add(
      TheoreticalBestSector(
        segmentId: id,
        name: segment['name'] is String ? segment['name'] as String : '',
        type: segment['type'] is String ? segment['type'] as String : '',
        seconds: seconds,
        sourceLapReference: source,
        unavailableReason: seconds == null ? theoreticalBestIncompleteCoverage : '',
      ),
    );
  }
  return TheoreticalBestLap(
    stamp: segmentationResultStamp(approved, theoreticalBestAlgorithm),
    sectors: sectors,
    totalSeconds: complete ? total : null,
    unavailableReason: complete ? '' : theoreticalBestIncompleteCoverage,
    valid: true,
  );
}
