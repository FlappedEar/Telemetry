// What kind of corner each corner is (FET-220, roadmap idea 4): its shape,
// read from the track's curvature, and how the car went through it on the
// day's laps (braking, lift or flat, and how fast). Every class comes from
// fixed thresholds below, the same on every track, so a "heavy braking,
// slow, decreasing radius" corner means the same at any circuit.
//
// The shape is the line of the lap the shared axis was built from (the
// canonical run's fastest lap), so it is the same for every lap of the day.
// Long corner complexes are not split into single corners (FET-115): a
// segment with several tight parts is a double apex or a complex, as it is.
// The driving classes are typical values (medians) over the day's laps,
// never one lap's, and need at least three laps.
import 'dart:math' as math;

import '../speed_units.dart';
import 'braking_metrics.dart' show brakingNoneDetected;
import 'braking_onset.dart' show brakingMethodMeasured;
import 'consistency.dart';
import 'corner_phases.dart';
import 'gg_pairs.dart' show gPerAccelerationUnit, standardGravity;
import 'outing_theoretical_best.dart' show CornerLapMetrics;
import 'track_progress.dart';

const String cornerClassAlgorithm = 'corner-class-v1';

/// Fewer laps than this give no driving class (typical needs three).
const int cornerClassMinimumLaps = minimumConsistencySamples;

/// Braking is the corner's class when it was found on at least this share of
/// the laps measured the same way.
const double cornerClassBrakingLapShare = 0.5;

/// Braking that typically takes at least this much speed off is heavy
/// braking (40 km/h). The speed taken off is the braking's mean deceleration
/// times its duration ([BrakingMetrics]), so it needs a longitudinal G.
const double cornerClassHeavyBrakingMetresPerSecond = 40 / 3.6;

/// Without braking, a typical loss from the corner's entry speed to its
/// minimum of at least this fraction is a lift; less is flat.
const double cornerClassLiftSpeedLossFraction = 0.05;

/// A typical minimum speed below this is a slow corner (80 km/h).
const double cornerClassSlowBelowMetresPerSecond = 80 / 3.6;

/// A typical minimum speed from this up is a fast corner (130 km/h); in
/// between is medium.
const double cornerClassFastFromMetresPerSecond = 130 / 3.6;

/// Turning the other way at least this fraction of the corner's peak
/// curvature makes the segment a complex that changes direction.
const double cornerClassReversalRatio = 0.6;

/// The mean curvature of one half of the corner at least this many times the
/// other half's makes it a decreasing (second half tighter) or increasing
/// (first half tighter) radius.
const double cornerClassRadiusChangeRatio = 1.3;

/// A single tightest part whose middle lies at least this fraction of the
/// way through the corner is a late apex.
const double cornerClassLateApexFraction = 0.6;

/// Tight parts ([proposeCornerGeometryPhases]' apex regions) from this many
/// up make a complex rather than a double apex.
const int cornerClassComplexApexCount = 3;

/// Reasons a class is not given (with the phase and braking reasons).
const String cornerClassTooFewLaps = 'tooFewLaps';
const String cornerClassSpeedUnitUnknown = 'speedUnitUnknown';

/// The corner's shape.
enum CornerShape {
  /// One tightest part, about the same radius before and after it.
  singleApex,

  /// One tightest part, late in the corner.
  lateApex,

  /// Tightens: the second half turns harder than the first.
  decreasingRadius,

  /// Opens: the first half turns harder than the second.
  increasingRadius,

  /// Two separate tightest parts turning the same way.
  doubleApex,

  /// Three or more tight parts, or a change of direction: several corners
  /// in one segment (not split, FET-115).
  complex,
}

/// How the car went into the corner, typically.
enum CornerApproach { heavyBraking, braking, lift, flat }

/// How fast the corner is, by its typical minimum speed.
enum CornerSpeedBand { slow, medium, fast }

/// The corner's shape from the track's curvature, or why there is none.
final class CornerShapeClass {
  const CornerShapeClass({
    this.shape,
    this.unavailableReason = '',
    this.tightParts = 0,
    this.changesDirection = false,
    this.apexFraction,
    this.radiusRatio,
  });

  final CornerShape? shape;

  /// Set when [shape] is null.
  final String unavailableReason;

  /// Separate tightest parts turning the corner's way.
  final int tightParts;

  /// Turns the other way as hard as [cornerClassReversalRatio] of its peak.
  final bool changesDirection;

  /// How far through the corner (0 to 1) the single tightest part's middle
  /// lies; null with more than one.
  final double? apexFraction;

  /// Mean curvature of the second half over the first; null with more than
  /// one tightest part.
  final double? radiusRatio;
}

/// How the corner was driven on the day's laps, or why that is not known.
final class CornerDrivingClass {
  const CornerDrivingClass({
    this.approach,
    this.approachUnavailableReason = '',
    this.lapsMeasured = 0,
    this.brakingLaps = 0,
    this.brakingMethod = '',
    this.typicalSpeedShedMetresPerSecond,
    this.typicalPeakDecelerationG,
    this.decelerationLaps = 0,
    this.typicalSpeedLossFraction,
    this.typicalSpeedLossMetresPerSecond,
    this.speedBand,
    this.speedBandUnavailableReason = '',
    this.typicalMinimumSpeedMetresPerSecond,
    this.speedLaps = 0,
    this.speedUnit,
  });

  final CornerApproach? approach;

  /// Set when [approach] is null.
  final String approachUnavailableReason;

  /// Laps whose braking was measured one way ([brakingMethod]), braking or
  /// not, and how many of them braked.
  final int lapsMeasured, brakingLaps;

  /// `measuredBrake` or `inferredDeceleration`.
  final String brakingMethod;

  /// The speed braking took off and the peak deceleration, typically, over
  /// the braking laps with a deceleration ([decelerationLaps]); null below
  /// three, when braking is not split into heavy or not.
  final double? typicalSpeedShedMetresPerSecond, typicalPeakDecelerationG;
  final int decelerationLaps;

  /// From the corner's entry speed to its minimum, typically, as a fraction
  /// of the entry speed and (in a known unit) as a speed; set for a lift or
  /// flat.
  final double? typicalSpeedLossFraction, typicalSpeedLossMetresPerSecond;

  final CornerSpeedBand? speedBand;

  /// Set when [speedBand] is null.
  final String speedBandUnavailableReason;
  final double? typicalMinimumSpeedMetresPerSecond;
  final int speedLaps;

  /// The unit every lap's speeds here are recorded in; null when they
  /// differ, so no typical speed is shown in either.
  final String? speedUnit;

  /// [metresPerSecond] in [speedUnit], or null.
  double? inSpeedUnit(double? metresPerSecond) {
    final factor = speedUnit == null ? null : metresPerSecondPerSpeedUnit(speedUnit!);
    return metresPerSecond == null || factor == null ? null : metresPerSecond / factor;
  }
}

/// A corner's classes: the shape from the track and the approach and speed
/// from the day's laps.
final class CornerClassification {
  const CornerClassification({
    this.shape = const CornerShapeClass(unavailableReason: cornerPhaseInvalidInput),
    this.driving = const CornerDrivingClass(
      approachUnavailableReason: cornerClassTooFewLaps,
      speedBandUnavailableReason: cornerClassTooFewLaps,
    ),
  });

  final CornerShapeClass shape;
  final CornerDrivingClass driving;
}

/// The shape of [segment] (an approved corner) on [axis].
CornerShapeClass classifyCornerShape(
  ProgressAxis axis,
  TrackFeatures features,
  Map<String, Object?> segment,
) {
  final corner = cornerFromSegment(axis, features, segment);
  if (!(corner.lengthMeters > 0)) {
    return const CornerShapeClass(unavailableReason: cornerPhaseInvalidInput);
  }
  final phases = proposeCornerGeometryPhases(axis, features, corner);
  if (!phases.valid) return const CornerShapeClass(unavailableReason: cornerPhaseInvalidInput);
  if (phases.apex.unresolvedReason == cornerPhaseInsufficientGeometry) {
    return const CornerShapeClass(unavailableReason: cornerPhaseInsufficientGeometry);
  }
  final direction = corner.turnRadians != 0.0 ? corner.turnRadians : corner.peakCurvaturePerMeter;
  final sign = direction >= 0.0 ? 1.0 : -1.0;
  final turning = [
    for (final index in cornerSampleIndices(features, corner))
      sign * features.samples[index].curvaturePerMeter,
  ];
  final peak = turning.fold(0.0, math.max);
  final against = -turning.fold(0.0, math.min);
  final parts = phases.apexCandidatesMeters.length;
  final changesDirection = against >= cornerClassReversalRatio * peak;
  if (changesDirection || parts >= cornerClassComplexApexCount) {
    return CornerShapeClass(
      shape: CornerShape.complex,
      tightParts: parts,
      changesDirection: changesDirection,
    );
  }
  if (parts == 2) return const CornerShapeClass(shape: CornerShape.doubleApex, tightParts: 2);
  if (parts != 1) {
    return CornerShapeClass(unavailableReason: cornerPhaseInsufficientGeometry, tightParts: parts);
  }

  // Mean turning of each half, by sample count (the samples are evenly
  // spaced); turning the other way counts as none.
  double mean(Iterable<double> values) =>
      values.fold(0.0, (sum, value) => sum + math.max(0.0, value)) / values.length;
  final half = turning.length ~/ 2;
  final first = mean(turning.take(half));
  final second = mean(turning.skip(turning.length - half));
  final ratio = first > 0 ? second / first : null;
  final start = corner.start.progressMeters;
  final along = (phases.apexCandidatesMeters.first - start) % axis.lengthMeters;
  final fraction = (along / corner.lengthMeters).clamp(0.0, 1.0);
  final shape = ratio == null || ratio >= cornerClassRadiusChangeRatio
      ? CornerShape.decreasingRadius
      : ratio <= 1 / cornerClassRadiusChangeRatio
      ? CornerShape.increasingRadius
      : fraction >= cornerClassLateApexFraction
      ? CornerShape.lateApex
      : CornerShape.singleApex;
  return CornerShapeClass(shape: shape, tightParts: 1, apexFraction: fraction, radiusRatio: ratio);
}

/// How a corner was driven over [laps] (each lap's Corner Analyzer figures
/// there). Braking measured from a brake pedal and braking inferred from
/// deceleration are never pooled: the method most laps used decides.
CornerDrivingClass classifyCornerDriving(List<CornerLapMetrics> laps) {
  final units = [
    for (final lap in laps)
      if (lap.speeds.entry.value != null || _minimum(lap) != null) lap.speeds.unit,
  ];
  final unit = units.isEmpty || units.any((other) => !sameSpeedUnit(other, units.first))
      ? null
      : units.first;
  // How fast: the typical minimum speed, every lap in its own unit.
  final minimums = [
    for (final lap in laps) ?speedInMetresPerSecond(_minimum(lap), lap.speeds.unit),
  ];
  final unknownUnit = laps.any(
    (lap) => _minimum(lap) != null && metresPerSecondPerSpeedUnit(lap.speeds.unit) == null,
  );
  final typicalMinimum = summarizeConsistency(minimums);
  final speedBand = !typicalMinimum.available
      ? null
      : typicalMinimum.median! < cornerClassSlowBelowMetresPerSecond
      ? CornerSpeedBand.slow
      : typicalMinimum.median! < cornerClassFastFromMetresPerSecond
      ? CornerSpeedBand.medium
      : CornerSpeedBand.fast;
  final speedReason = speedBand != null
      ? ''
      : unknownUnit && minimums.length < cornerClassMinimumLaps
      ? cornerClassSpeedUnitUnknown
      : _commonReason([
          for (final lap in laps)
            if (_minimum(lap) == null) lap.speeds.minimum.unavailableReason,
        ], minimums.length);

  CornerDrivingClass result({
    CornerApproach? approach,
    String reason = '',
    int measured = 0,
    int braked = 0,
    String method = '',
    double? shed,
    double? peakG,
    int decelerationLaps = 0,
    double? loss,
    double? lossSpeed,
  }) => CornerDrivingClass(
    approach: approach,
    approachUnavailableReason: approach == null ? reason : '',
    lapsMeasured: measured,
    brakingLaps: braked,
    brakingMethod: method,
    typicalSpeedShedMetresPerSecond: shed,
    typicalPeakDecelerationG: peakG,
    decelerationLaps: decelerationLaps,
    typicalSpeedLossFraction: loss,
    typicalSpeedLossMetresPerSecond: lossSpeed,
    speedBand: speedBand,
    speedBandUnavailableReason: speedReason,
    typicalMinimumSpeedMetresPerSecond: speedBand == null ? null : typicalMinimum.median,
    speedLaps: minimums.length,
    speedUnit: unit,
  );

  // Braking or not: laps where braking was looked for and found, or found
  // not to happen.
  bool measuredBraking(CornerLapMetrics lap) =>
      lap.braking.valid &&
      lap.braking.method.isNotEmpty &&
      (lap.braking.brakingPointMeters != null ||
          lap.braking.unavailableReason == brakingNoneDetected);
  final byMethod = <String, List<CornerLapMetrics>>{};
  for (final lap in laps.where(measuredBraking)) {
    (byMethod[lap.braking.method] ??= []).add(lap);
  }
  if (byMethod.isEmpty) {
    return result(
      reason: _commonReason([for (final lap in laps) lap.braking.unavailableReason], 0),
    );
  }
  // The method most laps used; a tie goes to the brake pedal.
  final method = byMethod.keys.reduce((a, b) {
    final countA = byMethod[a]!.length, countB = byMethod[b]!.length;
    if (countA != countB) return countA > countB ? a : b;
    return a == brakingMethodMeasured ? a : b;
  });
  final measured = byMethod[method]!;
  if (measured.length < cornerClassMinimumLaps) {
    return result(reason: cornerClassTooFewLaps, measured: measured.length, method: method);
  }
  final braking = [
    for (final lap in measured)
      if (lap.braking.brakingPointMeters != null) lap,
  ];
  if (braking.length >= cornerClassBrakingLapShare * measured.length) {
    // Each braking lap's deceleration in g, read in the channel's unit.
    final decelerations = [
      for (final lap in braking)
        if (gPerAccelerationUnit(lap.braking.decelerationUnit) case final factor?)
          if ((
                lap.braking.peakDeceleration,
                lap.braking.meanDeceleration,
                lap.braking.brakingSeconds,
              )
              case (final peak?, final mean?, final seconds?))
            (peak: peak * factor, shed: mean * factor * standardGravity * seconds),
    ];
    final shed = summarizeConsistency([for (final lap in decelerations) lap.shed]);
    final peak = summarizeConsistency([for (final lap in decelerations) lap.peak]);
    final typicalShed = shed.available ? math.max(0.0, shed.median!) : null;
    return result(
      approach: typicalShed != null && typicalShed >= cornerClassHeavyBrakingMetresPerSecond
          ? CornerApproach.heavyBraking
          : CornerApproach.braking,
      measured: measured.length,
      braked: braking.length,
      method: method,
      shed: typicalShed,
      peakG: peak.available ? peak.median : null,
      decelerationLaps: decelerations.length,
    );
  }
  // No braking on most laps: a lift or flat, by the speed lost into the
  // corner (both speeds of one lap, so in one unit).
  final losses = [
    for (final lap in measured)
      if ((lap.speeds.entry.value, _minimum(lap)) case (final entry?, final minimum?)
          when entry > 0)
        (
          fraction: (entry - minimum) / entry,
          speed: speedInMetresPerSecond(entry - minimum, lap.speeds.unit),
        ),
  ];
  final typicalLoss = summarizeConsistency([for (final lap in losses) lap.fraction]);
  final typicalLossSpeed = summarizeConsistency([for (final lap in losses) ?lap.speed]);
  if (!typicalLoss.available) {
    return result(
      reason: _commonReason([
        for (final lap in measured)
          if (lap.speeds.entry.value == null)
            lap.speeds.entry.unavailableReason
          else if (_minimum(lap) == null)
            lap.speeds.minimum.unavailableReason,
      ], losses.length),
      measured: measured.length,
      braked: braking.length,
      method: method,
    );
  }
  final loss = math.max(0.0, typicalLoss.median!);
  return result(
    approach: loss >= cornerClassLiftSpeedLossFraction ? CornerApproach.lift : CornerApproach.flat,
    measured: measured.length,
    braked: braking.length,
    method: method,
    loss: loss,
    lossSpeed: typicalLossSpeed.available ? math.max(0.0, typicalLossSpeed.median!) : null,
  );
}

/// [segment]'s shape on [axis] and how [laps] drove it.
CornerClassification classifyCorner(
  ProgressAxis axis,
  TrackFeatures features,
  Map<String, Object?> segment,
  List<CornerLapMetrics> laps,
) => CornerClassification(
  shape: classifyCornerShape(axis, features, segment),
  driving: classifyCornerDriving(laps),
);

// The lap's minimum speed in the corner; a speed that does not change
// through it (no lowest point to locate) is its own minimum.
double? _minimum(CornerLapMetrics lap) =>
    lap.speeds.minimum.value ??
    (lap.speeds.minimum.unavailableReason == cornerPhaseFlatSpeed ? lap.speeds.entry.value : null);

// Why a value is missing: the most common reason of the laps without one,
// when those laps with the [usable] ones would have been enough; otherwise
// the day has too few laps.
String _commonReason(List<String> reasons, int usable) {
  final counts = <String, int>{};
  for (final reason in reasons) {
    if (reason.isNotEmpty) counts[reason] = (counts[reason] ?? 0) + 1;
  }
  if (counts.isEmpty) return cornerClassTooFewLaps;
  final (reason, count) = counts.entries
      .map((entry) => (entry.key, entry.value))
      .reduce((a, b) => b.$2 > a.$2 ? b : a);
  return usable + count >= cornerClassMinimumLaps ? reason : cornerClassTooFewLaps;
}
