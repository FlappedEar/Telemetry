// What kind of corner each corner is (FET-220, roadmap idea 4): its shape,
// read from the track's curvature, and how the car went through it on the
// day's laps (braking, lift or flat, and how fast). Every class comes from
// fixed thresholds below, the same on every track, so a "heavy braking,
// slow, decreasing radius" corner means the same at any circuit.
//
// The shape is the line of the lap the shared axis was built from (the
// canonical run's fastest lap), so it is the same for every lap of the day.
// It is measured over the part of the segment that turns, so where exactly
// the segment's bounds sit on the straights around it does not change it.
// The automatic proposals divide corner chains into single corners (FET-115);
// a segment that still holds several tight parts (a day saved by an earlier
// version, or corners the driver merged) is a double apex or a complex, as it
// is.
//
// The driving classes are typical values (medians) over the day's laps,
// never one lap's, and need at least three laps. Speeds come from the
// recorded speed channel; speeds in different units are never pooled.
import 'dart:math' as math;

import '../speed_units.dart';
import 'braking_metrics.dart' show brakingNoneDetected;
import 'braking_onset.dart' show brakingMethodMeasured;
import 'consistency.dart';
import 'corner_phases.dart';
import 'outing_theoretical_best.dart' show CornerLapMetrics;
import 'track_progress.dart';
import 'track_segment_proposals.dart' show SegmentProposalOptions;

const String cornerClassAlgorithm = 'corner-class-v2';

/// Fewer laps than this give no driving class (typical needs three).
const int cornerClassMinimumLaps = minimumConsistencySamples;

/// Braking is the corner's class when it was found on at least this share of
/// the laps measured the same way.
const double cornerClassBrakingLapShare = 0.5;

/// Braking is heavy when the speed typically drops by at least this much
/// (40 km/h) from where braking starts to the lowest speed in the corner,
/// both read from the speed channel. All braking up to the lowest point
/// counts, so a segment holding two corners is not read from its first
/// braking only.
const double cornerClassHeavyBrakingMetresPerSecond = 40 / 3.6;

/// Without braking, a typical loss from the corner's entry speed to its
/// minimum of at least this fraction is a lift; less is flat.
const double cornerClassLiftSpeedLossFraction = 0.05;

/// A typical minimum speed below this is a slow corner (80 km/h).
const double cornerClassSlowBelowMetresPerSecond = 80 / 3.6;

/// A typical minimum speed from this up is a fast corner (130 km/h); in
/// between is medium.
const double cornerClassFastFromMetresPerSecond = 130 / 3.6;

/// The turning part of a segment: from the first to the last point whose
/// curvature the corner's way reaches the segment proposals' corner
/// threshold (1/250 per metre), or half the segment's peak when that is
/// gentler. The shape is measured over this part only.
const double cornerClassTurningCurvaturePerMeter =
    SegmentProposalOptions.defaultCornerCurvaturePerMeter;

/// Turning the other way at least this fraction of the corner's peak
/// curvature makes the segment a complex that changes direction.
const double cornerClassReversalRatio = 0.6;

/// The mean curvature of one half of the turning part at least this many
/// times the other half's is a change of radius.
const double cornerClassRadiusChangeRatio = 1.3;

/// A change of radius is a decreasing radius only when the tightest part
/// reaches into the last this fraction of the turning part (it tightens to
/// the end), an increasing radius only when it starts in the first this
/// fraction (it opens from the start).
const double cornerClassRadiusEndFraction = 0.2;

/// Otherwise, a single tightest part whose middle lies at least this
/// fraction of the way through the turning part is a late apex.
const double cornerClassLateApexFraction = 0.6;

/// Tight parts ([proposeCornerGeometryPhases]' apex regions) from this many
/// up make a complex rather than a double apex.
const int cornerClassComplexApexCount = 3;

/// Reasons a class is not given (with the phase and braking reasons).
const String cornerClassTooFewLaps = 'tooFewLaps';
const String cornerClassSpeedUnitUnknown = 'speedUnitUnknown';

/// Not braking on most laps, but fewer than three laps without braking to
/// tell a lift from flat.
const String cornerClassTooFewLapsWithoutBraking = 'tooFewLapsWithoutBraking';

/// The corner's shape.
enum CornerShape {
  /// One tightest part, not late, neither tightening to the end nor opening
  /// from the start.
  singleApex,

  /// One tightest part, late in the corner, which opens again after it.
  lateApex,

  /// Tightens to the end: the second half turns harder than the first and
  /// the tightest part runs into the end.
  decreasingRadius,

  /// Opens from the start: the first half turns harder than the second and
  /// the tightest part starts at the beginning.
  increasingRadius,

  /// Two separate tightest parts turning the same way.
  doubleApex,

  /// Three or more tight parts, or a change of direction: several corners
  /// in one segment, classed as a whole (FET-115).
  complex,
}

/// How the car went into the corner, typically.
enum CornerApproach { heavyBraking, braking, lift, flat }

/// How fast the corner is, by its typical minimum speed.
enum CornerSpeedBand { slow, medium, fast }

/// The shape from measured curvature figures, by these rules in order:
/// 1. turning the other way at least [cornerClassReversalRatio] of the peak
///    ([reversalRatio]), or [cornerClassComplexApexCount] tight parts or
///    more: complex;
/// 2. two tight parts: double apex;
/// 3. [radiusRatio] (second half over first) at least
///    [cornerClassRadiusChangeRatio] and the tightest part ending in the
///    last [cornerClassRadiusEndFraction]: decreasing radius;
/// 4. [radiusRatio] at most its inverse and the tightest part starting in
///    the first [cornerClassRadiusEndFraction]: increasing radius;
/// 5. the tightest part's middle from [cornerClassLateApexFraction]: late
///    apex;
/// 6. otherwise single apex.
/// Fractions are of the turning part. Null without a tight part.
CornerShape? cornerShapeFor({
  required int tightParts,
  double reversalRatio = 0,
  double? radiusRatio,
  double? apexFraction,
  double? apexStartFraction,
  double? apexEndFraction,
}) {
  if (reversalRatio >= cornerClassReversalRatio || tightParts >= cornerClassComplexApexCount) {
    return CornerShape.complex;
  }
  if (tightParts == 2) return CornerShape.doubleApex;
  if (tightParts != 1) return null;
  if (radiusRatio != null &&
      radiusRatio >= cornerClassRadiusChangeRatio &&
      apexEndFraction != null &&
      apexEndFraction >= 1 - cornerClassRadiusEndFraction) {
    return CornerShape.decreasingRadius;
  }
  if (radiusRatio != null &&
      radiusRatio <= 1 / cornerClassRadiusChangeRatio &&
      apexStartFraction != null &&
      apexStartFraction <= cornerClassRadiusEndFraction) {
    return CornerShape.increasingRadius;
  }
  if (apexFraction != null && apexFraction >= cornerClassLateApexFraction) {
    return CornerShape.lateApex;
  }
  return CornerShape.singleApex;
}

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

  /// How far through the turning part (0 to 1) the single tightest part's
  /// middle lies; null with more than one.
  final double? apexFraction;

  /// Mean curvature of the turning part's second half over its first; null
  /// with more than one tightest part.
  final double? radiusRatio;
}

/// One lap's figures in a corner, with its recorded speed where braking
/// started (in the unit of [metrics]' speeds), when it braked.
typedef CornerClassLap = ({CornerLapMetrics metrics, double? speedAtBraking});

/// How the corner was driven on the day's laps, or why that is not known.
final class CornerDrivingClass {
  const CornerDrivingClass({
    this.approach,
    this.approachUnavailableReason = '',
    this.lapsMeasured = 0,
    this.brakingLaps = 0,
    this.brakingMethod = '',
    this.typicalSpeedShedMetresPerSecond,
    this.shedLaps = 0,
    this.heavyUnknownReason = '',
    this.typicalSpeedLossFraction,
    this.typicalSpeedLossMetresPerSecond,
    this.speedBand,
    this.speedBandUnavailableReason = '',
    this.typicalMinimumSpeedMetresPerSecond,
    this.speedLaps = 0,
    this.speedUnit,
    this.otherUnitLaps = 0,
  });

  final CornerApproach? approach;

  /// Set when [approach] is null.
  final String approachUnavailableReason;

  /// Laps whose braking was measured one way ([brakingMethod]), braking or
  /// not, and how many of them braked.
  final int lapsMeasured, brakingLaps;

  /// `measuredBrake` or `inferredDeceleration`.
  final String brakingMethod;

  /// From where braking starts to the lowest speed in the corner, typically,
  /// over [shedLaps] braking laps; null below three, when braking is not
  /// told heavy or not.
  final double? typicalSpeedShedMetresPerSecond;
  final int shedLaps;

  /// Why [heavyUnknown]: [cornerClassSpeedUnitUnknown] when the speeds'
  /// unit is not known; empty when too few laps have both speeds.
  final String heavyUnknownReason;

  /// Braking, but whether it is heavy is not known.
  bool get heavyUnknown =>
      approach == CornerApproach.braking && typicalSpeedShedMetresPerSecond == null;

  /// From the corner's entry speed to its minimum on the laps without
  /// braking, typically, as a fraction of the entry speed and as a speed;
  /// set for a lift or flat.
  final double? typicalSpeedLossFraction, typicalSpeedLossMetresPerSecond;

  final CornerSpeedBand? speedBand;

  /// Set when [speedBand] is null.
  final String speedBandUnavailableReason;
  final double? typicalMinimumSpeedMetresPerSecond;
  final int speedLaps;

  /// The unit of the laps whose speeds are used (as recorded, empty when
  /// unlabelled, read as km/h); null when none has a speed.
  final String? speedUnit;

  /// Laps with speeds in another unit, left out of every speed figure.
  final int otherUnitLaps;

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
  final parts = phases.apexCandidatesMeters.length;
  final reversal = peak > 0 ? -turning.fold(0.0, math.min) / peak : 0.0;
  if (parts != 1) {
    final shape = cornerShapeFor(tightParts: parts, reversalRatio: reversal);
    return CornerShapeClass(
      shape: shape,
      unavailableReason: shape == null ? cornerPhaseInsufficientGeometry : '',
      tightParts: parts,
      changesDirection: reversal >= cornerClassReversalRatio,
    );
  }

  // The turning part, and the tightest part inside it, as indices into
  // [turning]; both on the same evenly spaced samples.
  final threshold = math.min(cornerClassTurningCurvaturePerMeter, peak / 2);
  final first = turning.indexWhere((value) => value >= threshold);
  final last = turning.lastIndexWhere((value) => value >= threshold);
  final spacing = axis.spacingMeters;
  final start = corner.start.progressMeters;
  int along(Object? progress) =>
      ((((progress as double) - start) % axis.lengthMeters) / spacing).round();
  final regionStart = along(phases.apex.evidence['regionStartMeters']);
  final regionEnd = along(phases.apex.evidence['regionEndMeters']);
  final span = last - first;
  if (first < 0 || span < 2) {
    return const CornerShapeClass(unavailableReason: cornerPhaseInsufficientGeometry);
  }
  double fraction(num index) => ((index - first) / span).clamp(0.0, 1.0);

  // Mean turning of each half of the turning part; turning the other way
  // counts as none.
  double mean(Iterable<double> values) =>
      values.fold(0.0, (sum, value) => sum + math.max(0.0, value)) / values.length;
  final part = turning.sublist(first, last + 1);
  final half = part.length ~/ 2;
  final firstHalf = mean(part.take(half));
  final secondHalf = mean(part.skip(part.length - half));
  final ratio = firstHalf > 0 ? secondHalf / firstHalf : null;
  final apexFraction = fraction((regionStart + regionEnd) / 2);
  return CornerShapeClass(
    shape: cornerShapeFor(
      tightParts: 1,
      reversalRatio: reversal,
      radiusRatio: ratio ?? double.infinity,
      apexFraction: apexFraction,
      apexStartFraction: fraction(regionStart),
      apexEndFraction: fraction(regionEnd),
    ),
    tightParts: 1,
    changesDirection: reversal >= cornerClassReversalRatio,
    apexFraction: apexFraction,
    radiusRatio: ratio,
  );
}

/// How a corner was driven over [laps]. Braking measured from a brake pedal
/// and braking inferred from deceleration are never pooled: the method most
/// laps used decides. Speeds come only from the laps in the unit most laps
/// were recorded in (on an even split, the unit of the first such lap in
/// [laps]' order).
CornerDrivingClass classifyCornerDriving(List<CornerClassLap> laps) {
  // The speed unit: the largest group of laps recorded in one unit; on an
  // even split, the unit met first in lap order.
  final groups = <String, int>{};
  for (final (:metrics, speedAtBraking: _) in laps) {
    if (metrics.speeds.entry.value == null && _minimum(metrics) == null) continue;
    final unit = metrics.speeds.unit;
    final key = groups.keys.firstWhere((other) => sameSpeedUnit(other, unit), orElse: () => unit);
    groups[key] = (groups[key] ?? 0) + 1;
  }
  final unit = groups.isEmpty
      ? null
      : groups.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  final otherUnitLaps = unit == null ? 0 : groups.values.fold(0, (a, b) => a + b) - groups[unit]!;
  final factor = unit == null ? null : metresPerSecondPerSpeedUnit(unit);
  bool inUnit(CornerLapMetrics lap) => unit != null && sameSpeedUnit(lap.speeds.unit, unit);
  double? metresPerSecond(double? value) => value == null || factor == null ? null : value * factor;

  // How fast: the typical minimum speed.
  final minimums = [
    for (final (:metrics, speedAtBraking: _) in laps)
      if (inUnit(metrics)) ?metresPerSecond(_minimum(metrics)),
  ];
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
      : unit != null && factor == null
      ? cornerClassSpeedUnitUnknown
      : _commonReason([
          for (final (:metrics, speedAtBraking: _) in laps)
            if (_minimum(metrics) == null) metrics.speeds.minimum.unavailableReason,
        ], minimums.length);

  CornerDrivingClass result({
    CornerApproach? approach,
    String reason = '',
    int measured = 0,
    int braked = 0,
    String method = '',
    double? shed,
    int shedLaps = 0,
    String heavyUnknownReason = '',
    double? loss,
    double? lossSpeed,
  }) => CornerDrivingClass(
    approach: approach,
    approachUnavailableReason: approach == null ? reason : '',
    lapsMeasured: measured,
    brakingLaps: braked,
    brakingMethod: method,
    typicalSpeedShedMetresPerSecond: shed,
    shedLaps: shedLaps,
    heavyUnknownReason: heavyUnknownReason,
    typicalSpeedLossFraction: loss,
    typicalSpeedLossMetresPerSecond: lossSpeed,
    speedBand: speedBand,
    speedBandUnavailableReason: speedReason,
    typicalMinimumSpeedMetresPerSecond: speedBand == null ? null : typicalMinimum.median,
    speedLaps: minimums.length,
    speedUnit: unit,
    otherUnitLaps: otherUnitLaps,
  );

  // Braking or not: laps where braking was looked for and found, or found
  // not to happen.
  bool measuredBraking(CornerLapMetrics lap) =>
      lap.braking.valid &&
      lap.braking.method.isNotEmpty &&
      (lap.braking.brakingPointMeters != null ||
          lap.braking.unavailableReason == brakingNoneDetected);
  final byMethod = <String, List<CornerClassLap>>{};
  for (final lap in laps) {
    if (measuredBraking(lap.metrics)) (byMethod[lap.metrics.braking.method] ??= []).add(lap);
  }
  if (byMethod.isEmpty) {
    return result(
      reason: _commonReason([for (final lap in laps) lap.metrics.braking.unavailableReason], 0),
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
      if (lap.metrics.braking.brakingPointMeters != null) lap,
  ];
  if (braking.length >= cornerClassBrakingLapShare * measured.length) {
    // Where braking started to the lowest speed, from the speed channel.
    final sheds = [
      for (final (:metrics, :speedAtBraking) in braking)
        if (inUnit(metrics))
          if ((speedAtBraking, _minimum(metrics)) case (final from?, final lowest?))
            ?metresPerSecond(math.max(0.0, from - lowest)),
    ];
    final shed = summarizeConsistency(sheds);
    final typicalShed = shed.available ? shed.median : null;
    return result(
      approach: typicalShed != null && typicalShed >= cornerClassHeavyBrakingMetresPerSecond
          ? CornerApproach.heavyBraking
          : CornerApproach.braking,
      measured: measured.length,
      braked: braking.length,
      method: method,
      shed: typicalShed,
      shedLaps: sheds.length,
      heavyUnknownReason: typicalShed == null && unit != null && factor == null
          ? cornerClassSpeedUnitUnknown
          : '',
    );
  }
  // No braking on most laps: a lift or flat, by the speed those laps lost
  // into the corner.
  final coasting = [
    for (final lap in measured)
      if (lap.metrics.braking.brakingPointMeters == null) lap.metrics,
  ];
  final losses = [
    for (final lap in coasting)
      if (inUnit(lap))
        if ((lap.speeds.entry.value, _minimum(lap)) case (final entry?, final minimum?)
            when entry > 0)
          (fraction: (entry - minimum) / entry, speed: metresPerSecond(entry - minimum)),
  ];
  final typicalLoss = summarizeConsistency([for (final lap in losses) lap.fraction]);
  final typicalLossSpeed = summarizeConsistency([for (final lap in losses) ?lap.speed]);
  if (!typicalLoss.available) {
    return result(
      reason: coasting.length < cornerClassMinimumLaps
          ? cornerClassTooFewLapsWithoutBraking
          : _commonReason([
              for (final lap in coasting)
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
  List<CornerClassLap> laps,
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
