// The Corner Analyzer's figures of a group's corners (FET-33): for every
// corner segment of the theoretical best, each eligible lap's entry, minimum
// and exit speed, braking point and braking, and throttle pickup and exit, as
// Overlays' calculateOutingTheoreticalBest measures them on the shared axis;
// the best value of each across the group's laps; and one lap compared with
// the group's best lap as Overlays' Corner Analyzer compares two laps
// (ComparisonSegmentPanel): never across different channels, units or
// methods.
import '../speed_units.dart';
import '../analysis/braking_metrics.dart';
import '../analysis/corner_speeds.dart';
import '../analysis/exit_metrics.dart';
import '../analysis/outing_theoretical_best.dart';
import 'day_laps.dart';

/// One value of one lap.
typedef DayCornerValue = ({double value, DayLapRow lap});

/// A corner's figures on one lap, compared with the group's best lap and with
/// the best value of the group's laps.
final class DayCornerComparison {
  const DayCornerComparison({
    required this.lap,
    required this.metrics,
    this.bestLap,
    this.bestLapMetrics,
    this.speeds = const CornerSpeedsComparison(),
    this.braking = const BrakingComparison(),
    this.exit = const ExitComparison(),
    this.highestEntrySpeed,
    this.highestMinimumSpeed,
    this.highestExitSpeed,
    this.latestBrakingPoint,
    this.earliestPickup,
  });

  final DayLapRow lap;
  final CornerLapMetrics metrics;

  /// The group's best lap and its figures here.
  final DayLapRow? bestLap;
  final CornerLapMetrics? bestLapMetrics;

  /// [metrics] minus [bestLapMetrics] (Overlays' A minus B): a positive
  /// braking-point or pickup delta is later along the lap.
  final CornerSpeedsComparison speeds;
  final BrakingComparison braking;
  final ExitComparison exit;

  /// The best of the group's laps read from the same channel as this lap.
  final DayCornerValue? highestEntrySpeed;
  final DayCornerValue? highestMinimumSpeed;
  final DayCornerValue? highestExitSpeed;

  /// The braking point furthest along the lap, as metres before the
  /// segment's entry, of the laps measured by the same method and channel.
  final DayCornerValue? latestBrakingPoint;

  /// The pickup nearest the segment's entry, as metres after it, of the laps
  /// measured by the same method and channel.
  final DayCornerValue? earliestPickup;
}

/// One corner segment of the group with every timed lap's figures.
final class DayCorner {
  DayCorner({
    required this.segmentIndex,
    required this.segmentId,
    required this.name,
    required this.startProgressMeters,
    required this.endProgressMeters,
    required List<(DayLapRow, CornerLapMetrics)> laps,
    this.bestLap,
  }) : laps = List.unmodifiable(laps);

  /// The segment's position among the approved segments.
  final int segmentIndex;
  final String segmentId;
  final String name;
  final double startProgressMeters;
  final double endProgressMeters;

  /// Every timed lap's figures here, in recording order.
  final List<(DayLapRow, CornerLapMetrics)> laps;

  /// The group's best lap.
  final DayLapRow? bestLap;

  /// [reference]'s figures here, or null.
  CornerLapMetrics? metrics(DayLapReference reference) {
    for (final (row, metrics) in laps) {
      if (row.reference == reference) return metrics;
    }
    return null;
  }

  /// [reference]'s figures compared with the best lap and the group's best
  /// values; null when the lap was not timed here.
  DayCornerComparison? compare(DayLapReference reference) {
    DayLapRow? lap;
    CornerLapMetrics? chosen;
    CornerLapMetrics? best;
    for (final (row, metrics) in laps) {
      if (row.reference == reference) (lap, chosen) = (row, metrics);
      if (row.reference == bestLap?.reference) best = metrics;
    }
    if (lap == null || chosen == null) return null;
    final own = chosen;

    DayCornerValue? highest(double? Function(CornerSpeeds) read) {
      DayCornerValue? result;
      for (final (row, metrics) in laps) {
        final speeds = metrics.speeds;
        if (speeds.provenance != own.speeds.provenance ||
            speeds.channel != own.speeds.channel ||
            !sameSpeedUnit(speeds.unit, own.speeds.unit)) {
          continue;
        }
        final value = read(speeds);
        if (value != null && (result == null || value > result.value)) {
          result = (value: value, lap: row);
        }
      }
      return result;
    }

    // Braking points and pickups compare only within one method and channel:
    // this lap's, or else the best lap's, or else the first measured one's.
    BrakingMetrics? brakingReference;
    for (final candidate in [chosen, ?best, for (final (_, metrics) in laps) metrics]) {
      if (candidate.braking.brakingPointMeters != null) {
        brakingReference = candidate.braking;
        break;
      }
    }
    DayCornerValue? latest;
    for (final (row, metrics) in laps) {
      final braking = metrics.braking;
      final before = braking.distanceBeforeEntryMeters;
      if (before == null ||
          brakingReference == null ||
          braking.method != brakingReference.method ||
          braking.channel != brakingReference.channel) {
        continue;
      }
      if (latest == null || before < latest.value) latest = (value: before, lap: row);
    }
    ThrottlePickup? pickupReference;
    for (final candidate in [chosen, ?best, for (final (_, metrics) in laps) metrics]) {
      if (candidate.exit.pickup.progressMeters != null) {
        pickupReference = candidate.exit.pickup;
        break;
      }
    }
    DayCornerValue? earliest;
    for (final (row, metrics) in laps) {
      final pickup = metrics.exit.pickup;
      final progress = pickup.progressMeters;
      if (progress == null ||
          pickupReference == null ||
          pickup.method != pickupReference.method ||
          pickup.channel != pickupReference.channel) {
        continue;
      }
      final after = progress - startProgressMeters;
      if (earliest == null || after < earliest.value) earliest = (value: after, lap: row);
    }

    return DayCornerComparison(
      lap: lap,
      metrics: chosen,
      bestLap: best == null ? null : bestLap,
      bestLapMetrics: best,
      speeds: best == null
          ? const CornerSpeedsComparison()
          : compareCornerSpeeds(chosen.speeds, best.speeds),
      braking: best == null
          ? const BrakingComparison()
          : compareBrakingMetrics(chosen.braking, best.braking),
      exit: best == null ? const ExitComparison() : compareExitMetrics(chosen.exit, best.exit),
      highestEntrySpeed: highest((speeds) => speeds.entry.value),
      highestMinimumSpeed: highest((speeds) => speeds.minimum.value),
      highestExitSpeed: highest((speeds) => speeds.exit.value),
      latestBrakingPoint: latest,
      earliestPickup: earliest,
    );
  }
}

/// The corner segments of [computed] with every lap of [rows] timed there,
/// in approved order.
List<DayCorner> dayCorners(
  OutingTheoreticalBest computed,
  List<DayLapRow> rows,
  DayLapRow? bestLap,
) {
  final result = <DayCorner>[];
  final segments = computed.approved.segments;
  for (var index = 0; index < segments.length; ++index) {
    final segment = segments[index];
    final id = segment['id'];
    if (id is! String) continue;
    final metrics = computed.cornerMetrics[id];
    if (metrics == null) continue;
    final byReference = {for (final lap in metrics) lap.lapReference: lap};
    result.add(
      DayCorner(
        segmentIndex: index,
        segmentId: id,
        name: segment['name'] is String ? segment['name'] as String : id,
        startProgressMeters: (segment['startProgressMeters'] as num?)?.toDouble() ?? 0.0,
        endProgressMeters: (segment['endProgressMeters'] as num?)?.toDouble() ?? 0.0,
        laps: [
          for (final row in rows)
            if (byReference[row.reference] case final lap?) (row, lap),
        ],
        bestLap: bestLap,
      ),
    );
  }
  return result;
}
