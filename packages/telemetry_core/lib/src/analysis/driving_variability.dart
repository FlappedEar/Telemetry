// Port of FlappedEar Overlays native/src/telemetry/DrivingVariability.{h,cpp}
// (revision d4d1039, FET-33): braking, apex, exit and racing-line
// variability for one corner across a population of laps (KAN-63). Each lap
// contributes the same Corner Analyzer metrics measured on one shared axis;
// each metric is summarized with the consistency statistics (median,
// interquartile range, count). Measured and inferred braking points and
// throttle pickups are summarized separately and never mixed. The racing-line
// spread is the lateral offset of each lap from the reference line at the
// corner's geometric apex; it is reported next to the recording's typical GPS
// accuracy, and flagged as not resolvable when it is no larger than that.
import 'dart:math' as math;

import '../geometry.dart';
import '../speed_units.dart';
import 'consistency.dart';
import 'track_progress.dart';

const String drivingVariabilityAlgorithm = 'driving-variability-v1';

/// One lap's metrics of one corner.
final class CornerLapObservation {
  CornerLapObservation({this.lapReference});

  final Object? lapReference;
  double? brakingPointMeters;

  /// `measured` or `inferred`.
  String brakingProvenance = '';
  double? apexSpeed;
  double? minimumSpeed;
  double? exitSpeed;

  /// The unit of the speeds.
  String speedUnit = '';
  double? pickupMeters;

  /// `measured` or `inferred`.
  String pickupProvenance = '';

  /// Positive left of the reference line.
  double? lineOffsetMeters;

  /// The same at the corner's start and end (FlappedEar Telemetry only,
  /// FET-225), so the line's spread can be told on the way in and out.
  double? entryLineOffsetMeters;
  double? exitLineOffsetMeters;

  /// The recording's own accuracy at that point.
  double? gpsAccuracyMeters;
}

/// How repeatable one corner is.
final class CornerVariability {
  const CornerVariability({
    this.segmentId = '',
    this.name = '',
    this.brakingPointMeasured = const ConsistencySummary(),
    this.brakingPointInferred = const ConsistencySummary(),
    this.apexSpeed = const ConsistencySummary(),
    this.minimumSpeed = const ConsistencySummary(),
    this.exitSpeed = const ConsistencySummary(),
    this.pickupMeasured = const ConsistencySummary(),
    this.pickupInferred = const ConsistencySummary(),
    this.lineOffset = const ConsistencySummary(),
    this.typicalGpsAccuracyMeters,
    this.lineSpreadResolvable = false,
    this.entryLineOffset = const ConsistencySummary(),
    this.exitLineOffset = const ConsistencySummary(),
  });

  final String segmentId;
  final String name;
  final ConsistencySummary brakingPointMeasured;
  final ConsistencySummary brakingPointInferred;
  final ConsistencySummary apexSpeed;
  final ConsistencySummary minimumSpeed;
  final ConsistencySummary exitSpeed;
  final ConsistencySummary pickupMeasured;
  final ConsistencySummary pickupInferred;
  final ConsistencySummary lineOffset;

  /// Median accuracy of the observations.
  final double? typicalGpsAccuracyMeters;

  /// The line spread (IQR) is larger than the typical GPS accuracy, so the
  /// difference in line can be told apart from GPS noise.
  final bool lineSpreadResolvable;

  /// The line's offset at the corner's start and end (FET-225), each to be
  /// read against [typicalGpsAccuracyMeters] as [lineOffset] is.
  final ConsistencySummary entryLineOffset;
  final ConsistencySummary exitLineOffset;

  /// [entryLineOffset]'s spread is larger than the typical GPS accuracy.
  bool get entryLineResolvable => _resolvable(entryLineOffset);

  /// [exitLineOffset]'s spread is larger than the typical GPS accuracy.
  bool get exitLineResolvable => _resolvable(exitLineOffset);

  bool _resolvable(ConsistencySummary line) =>
      line.available &&
      typicalGpsAccuracyMeters != null &&
      line.interquartileRange! > typicalGpsAccuracyMeters!;
}

/// The variability of one corner over [observations].
CornerVariability summarizeCornerVariability(
  String segmentId,
  String name,
  List<CornerLapObservation> observations, {
  int minimumSamples = minimumConsistencySamples,
}) {
  final brakingMeasured = <double>[], brakingInferred = <double>[];
  final apex = <double>[], minimum = <double>[], exit = <double>[];
  final pickupMeasured = <double>[], pickupInferred = <double>[];
  final line = <double>[], accuracy = <double>[];
  final entryLine = <double>[], exitLine = <double>[];
  // Speeds are pooled only in one unit (see [sameSpeedUnit]); a corner
  // whose laps are in different units has no speed spread.
  String? speedUnit;
  var mixedUnits = false;
  for (final lap in observations) {
    if (lap.apexSpeed == null && lap.minimumSpeed == null && lap.exitSpeed == null) continue;
    final unit = speedUnit ??= lap.speedUnit;
    if (!sameSpeedUnit(unit, lap.speedUnit)) mixedUnits = true;
  }
  for (final lap in observations) {
    if (lap.brakingPointMeters case final braking?) {
      if (lap.brakingProvenance == 'measured') {
        brakingMeasured.add(braking);
      } else if (lap.brakingProvenance == 'inferred') {
        brakingInferred.add(braking);
      }
    }
    if (lap.pickupMeters case final pickup?) {
      if (lap.pickupProvenance == 'measured') {
        pickupMeasured.add(pickup);
      } else if (lap.pickupProvenance == 'inferred') {
        pickupInferred.add(pickup);
      }
    }
    if (!mixedUnits) {
      if (lap.apexSpeed case final value?) apex.add(value);
      if (lap.minimumSpeed case final value?) minimum.add(value);
      if (lap.exitSpeed case final value?) exit.add(value);
    }
    if (lap.lineOffsetMeters case final value?) line.add(value);
    if (lap.entryLineOffsetMeters case final value?) entryLine.add(value);
    if (lap.exitLineOffsetMeters case final value?) exitLine.add(value);
    if (lap.gpsAccuracyMeters case final value? when value.isFinite && value >= 0.0) {
      accuracy.add(value);
    }
  }
  ConsistencySummary summary(List<double> values) =>
      summarizeConsistency(values, minimumSamples: minimumSamples);
  final lineOffset = summary(line);
  final typical = summarizeConsistency(accuracy, minimumSamples: 1);
  final typicalAccuracy = typical.available ? typical.median : null;
  return CornerVariability(
    segmentId: segmentId,
    name: name,
    brakingPointMeasured: summary(brakingMeasured),
    brakingPointInferred: summary(brakingInferred),
    apexSpeed: summary(apex),
    minimumSpeed: summary(minimum),
    exitSpeed: summary(exit),
    pickupMeasured: summary(pickupMeasured),
    pickupInferred: summary(pickupInferred),
    lineOffset: lineOffset,
    typicalGpsAccuracyMeters: typicalAccuracy,
    // Without a stated accuracy there is nothing to compare against: the
    // spread is reported but never claimed resolvable.
    lineSpreadResolvable:
        lineOffset.available &&
        typicalAccuracy != null &&
        lineOffset.interquartileRange! > typicalAccuracy,
    entryLineOffset: summary(entryLine),
    exitLineOffset: summary(exitLine),
  );
}

/// Signed lateral distance (metres, positive to the left of travel) of
/// [localPoint] from [axis] at [progressMeters]; null outside the axis.
double? lateralOffsetMeters(ProgressAxis axis, double progressMeters, MetricPoint localPoint) {
  if (!axis.valid ||
      axis.points.length < 2 ||
      axis.cumulative.length != axis.points.length ||
      !progressMeters.isFinite ||
      progressMeters < 0.0 ||
      progressMeters > axis.lengthMeters) {
    return null;
  }
  var upper = 0;
  var high = axis.cumulative.length;
  while (upper < high) {
    final middle = (upper + high) >> 1;
    if (axis.cumulative[middle] < progressMeters) {
      upper = middle + 1;
    } else {
      high = middle;
    }
  }
  final index = upper.clamp(1, axis.points.length - 1);
  final a = axis.points[index - 1], b = axis.points[index];
  final span = axis.cumulative[index] - axis.cumulative[index - 1];
  final fraction = span > 0.0
      ? ((progressMeters - axis.cumulative[index - 1]) / span).clamp(0.0, 1.0)
      : 0.0;
  final onEast = a.eastMeters + (b.eastMeters - a.eastMeters) * fraction;
  final onNorth = a.northMeters + (b.northMeters - a.northMeters) * fraction;
  final directionEast = b.eastMeters - a.eastMeters;
  final directionNorth = b.northMeters - a.northMeters;
  final length = math.sqrt(directionEast * directionEast + directionNorth * directionNorth);
  if (length <= 0.0) return null;
  final offsetEast = localPoint.eastMeters - onEast;
  final offsetNorth = localPoint.northMeters - onNorth;
  return (directionEast * offsetNorth - directionNorth * offsetEast) / length;
}
