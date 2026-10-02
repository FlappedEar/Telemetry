// Port of FlappedEar Overlays native/src/telemetry/Consistency.{h,cpp}
// (revision d4d1039, FET-32): how repeatable lap and sector times are.
// "Typical" is the median; the spread is the interquartile range, the time
// between the 25th and 75th percentile, so a warm-up or traffic lap does not
// dominate it. Quantiles interpolate linearly between ordered samples.
import 'time_loss.dart';
import 'track_segment_review.dart';

const String consistencyAlgorithm = 'consistency-iqr-v1';

/// Fewer samples than this give no statistics.
const int minimumConsistencySamples = 3;
const String consistencyTooFewSamples = 'tooFewSamples';

/// Quartiles of a set of times, or why there are none.
final class ConsistencySummary {
  const ConsistencySummary({
    this.count = 0,
    this.minimum,
    this.q1,
    this.median,
    this.q3,
    this.maximum,
    this.interquartileRange,
    this.unavailableReason = '',
    this.available = false,
  });

  /// Finite samples considered.
  final int count;
  final double? minimum, q1, median, q3, maximum;

  /// [q3] − [q1], seconds.
  final double? interquartileRange;

  /// Set when [count] is below the minimum.
  final String unavailableReason;
  final bool available;
}

/// Quartiles of the finite [values], unavailable below [minimumSamples].
ConsistencySummary summarizeConsistency(
  Iterable<double> values, {
  int minimumSamples = minimumConsistencySamples,
}) {
  final sorted = [
    for (final value in values)
      if (value.isFinite) value,
  ];
  if (sorted.length < (minimumSamples < 1 ? 1 : minimumSamples)) {
    return ConsistencySummary(count: sorted.length, unavailableReason: consistencyTooFewSamples);
  }
  sorted.sort();
  double quantile(double fraction) {
    final position = fraction * (sorted.length - 1);
    final lower = position.floor(), upper = position.ceil();
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }

  final q1 = quantile(0.25), q3 = quantile(0.75);
  return ConsistencySummary(
    count: sorted.length,
    minimum: sorted.first,
    q1: q1,
    median: quantile(0.5),
    q3: q3,
    maximum: sorted.last,
    interquartileRange: q3 - q1,
    available: true,
  );
}

/// One approved segment's consistency across a population.
final class SectorConsistency {
  SectorConsistency({
    required this.segmentId,
    required this.name,
    required this.type,
    required this.summary,
    List<Object?> lapReferences = const [],
  }) : lapReferences = List.unmodifiable(lapReferences);

  final String segmentId;
  final String name;
  final String type;
  final ConsistencySummary summary;

  /// Laps with a time in this segment.
  final List<Object?> lapReferences;
}

/// Each approved segment's consistency across [population], laps timed on
/// one shared axis; laps of another revision are ignored.
List<SectorConsistency> computeSectorConsistency(
  ApprovedSegmentation approved,
  List<TimedLapSectors> population, {
  int minimumSamples = minimumConsistencySamples,
}) {
  if (!approved.valid || approved.revision.isEmpty) return const [];
  return [
    for (final segment in approved.segments)
      () {
        final id = segment['id'] is String ? segment['id'] as String : '';
        final times = <double>[];
        final laps = <Object?>[];
        for (final lap in population) {
          if (!lap.times.valid ||
              lap.times.stamp.revision != approved.revision ||
              lap.times.stamp.trackConfigurationReference != approved.trackConfigurationReference) {
            continue;
          }
          for (final candidate in lap.times.sectors) {
            if (candidate.segmentId != id || candidate.seconds == null) continue;
            times.add(candidate.seconds!);
            laps.add(lap.times.lapReference);
          }
        }
        return SectorConsistency(
          segmentId: id,
          name: segment['name'] is String ? segment['name'] as String : '',
          type: segment['type'] is String ? segment['type'] as String : '',
          summary: summarizeConsistency(times, minimumSamples: minimumSamples),
          lapReferences: laps,
        );
      }(),
  ];
}
