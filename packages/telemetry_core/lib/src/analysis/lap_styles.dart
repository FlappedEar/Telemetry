// Lap styles (FET-223, roadmap idea 7): the day's ranked laps grouped by how
// they were driven, with the quickest lap of each group.
//
// Each lap is compared with the day's typical lap, corner by corner: where
// braking started (metres before the corner's entry), where the throttle was
// picked up (metres after it), and the minimum and exit speed. The typical
// value is the median of the day's laps at that corner, and needs at least
// [lapStylesMinimumLaps] laps measured the same way. A lap's style then comes
// from plain counting rules, never from clustering:
//
//  * conservative: braking earlier than typical AND throttle later than
//    typical, each in most of the corners it was measured in;
//  * late braking: braking later than typical in most corners;
//  * early throttle: throttle earlier than typical in most corners;
//  * mixed: two of those at once, or one leaning without the other half;
//  * typical: none of them;
//  * outlier: unlike the day's other laps (braking or throttle point three
//    times the threshold or more from typical in more than half of its
//    corners), or measured in too few corners to say anything.
//
// "Most" means more than half of the corners where the lap has a figure, and
// at least [lapStylesMinimumCorners] of them. Every threshold is a constant
// below, to be tuned by the owner.
//
// What this is not: a cause. The styles describe where each lap sat against
// the day's other laps, from a handful of laps per session; a quick lap in a
// style does not show that the style made it quick. Nothing here converts a
// unit: speeds are compared only within one channel and unit, and a speed
// without a declared unit stays marked unit-less for the screens to say so.
import 'dart:math' as math;

import '../speed_units.dart';

const String lapStylesAlgorithm = 'lap-styles-v1';

/// A typical value, and a day to group at all, needs at least this many laps.
const int lapStylesMinimumLaps = 3;

/// "Most corners" needs at least this many corners with a figure, and a lap
/// measured in fewer corners than this (or than half the day's usable
/// corners) is an outlier for lack of data.
const int lapStylesMinimumCorners = 3;

/// Braking counts as earlier or later than typical beyond this many metres.
/// A 10 Hz GPS fix at 100 km/h moves about 2.8 m per sample, and the onset
/// is interpolated between two, so a smaller difference is not told apart.
const double lapStylesBrakeMeters = 5.0;

/// Throttle counts as earlier or later beyond this many metres. Larger than
/// the brake's: the throttle channel of an OBD recording updates about twice
/// a second, so its pickup is read to within roughly 10 m at 80 km/h.
const double lapStylesThrottleMeters = 10.0;

/// A speed counts as higher or lower than typical beyond this share of the
/// typical value (a ratio, so it holds in any speed unit).
const double lapStylesSpeedShare = 0.03;

/// A corner is "far from typical" at this many times a threshold.
const double lapStylesExtremeFactor = 3.0;

/// A lap is unlike the day's others when more than this share of the corners
/// it was compared in are far from typical.
const double lapStylesExtremeCornerShare = 0.5;

/// Why a lap or the day could not be grouped.
const String lapStylesTooFewLaps = 'tooFewLaps';
const String lapStylesTooFewCorners = 'tooFewCorners';

/// The style of one lap.
enum LapStyle { conservative, lateBraking, earlyThrottle, mixed, typical, outlier }

/// Why a lap is an outlier.
enum LapOutlierReason {
  /// Not an outlier.
  none,

  /// Far from the day's typical in most of its corners.
  unlike,

  /// Measured in too few corners to be grouped by its driving.
  fewCorners,
}

/// What one lap measured at one corner. Sources say which channel and method
/// a figure came from; figures are only compared with the same source.
final class LapCornerSample {
  const LapCornerSample({
    required this.cornerId,
    this.brakeBeforeEntryMeters,
    this.brakeSource = '',
    this.pickupAfterEntryMeters,
    this.pickupSource = '',
    this.minimumSpeed,
    this.exitSpeed,
    this.speedUnit = '',
    this.speedSource = '',
  });

  final String cornerId;

  /// Metres between where braking started and the corner's entry; larger is
  /// earlier.
  final double? brakeBeforeEntryMeters;
  final String brakeSource;

  /// Metres between the corner's entry and where the throttle was picked
  /// up; larger is later.
  final double? pickupAfterEntryMeters;
  final String pickupSource;

  /// The slowest and the exit speed, in [speedUnit] as the recording
  /// declares it (empty when it declares none).
  final double? minimumSpeed;
  final double? exitSpeed;
  final String speedUnit;
  final String speedSource;
}

/// One ranked lap and its corners.
final class LapStyleInput {
  const LapStyleInput({required this.lap, required this.seconds, required this.corners});

  /// Whatever identifies the lap to the caller.
  final Object lap;
  final double seconds;
  final List<LapCornerSample> corners;
}

/// A lap's figures at one corner minus the day's typical there; each is null
/// where there is no typical (too few laps measured the same way).
final class LapCornerDeviation {
  const LapCornerDeviation({
    required this.cornerId,
    this.brakeMeters,
    this.pickupMeters,
    this.minimumSpeed,
    this.minimumSpeedShare,
    this.exitSpeed,
    this.exitSpeedShare,
  });

  final String cornerId;

  /// Positive: braking started earlier than typical.
  final double? brakeMeters;

  /// Positive: the throttle came later than typical.
  final double? pickupMeters;

  /// Positive: faster than typical, in the lap's speed unit, and as a share
  /// of the typical speed.
  final double? minimumSpeed, minimumSpeedShare;
  final double? exitSpeed, exitSpeedShare;

  bool get hasFigure =>
      brakeMeters != null || pickupMeters != null || minimumSpeed != null || exitSpeed != null;

  /// Has a braking or throttle figure: the ones a style is told from.
  bool get hasTiming => brakeMeters != null || pickupMeters != null;

  /// Far from typical in braking or throttle, at [lapStylesExtremeFactor]
  /// times its threshold. Speeds are left out: they move with the lap's pace
  /// (a day's laps speed up as the driver learns the track), so a slow lap
  /// is not unlike the others in how it was driven.
  bool get extreme =>
      (brakeMeters?.abs() ?? 0.0) >= lapStylesExtremeFactor * lapStylesBrakeMeters ||
      (pickupMeters?.abs() ?? 0.0) >= lapStylesExtremeFactor * lapStylesThrottleMeters;
}

/// How often a lap sat beyond a threshold either side of typical in one
/// measure.
final class LapTraitCount {
  const LapTraitCount({this.measured = 0, this.positive = 0, this.negative = 0});

  /// Corners with a figure.
  final int measured;

  /// Corners beyond the threshold on the positive side (earlier braking,
  /// later throttle, higher speed) and on the negative side.
  final int positive, negative;

  /// More than half the measured corners, and at least
  /// [lapStylesMinimumCorners] of them.
  bool get mostlyPositive => measured >= lapStylesMinimumCorners && positive * 2 > measured;
  bool get mostlyNegative => measured >= lapStylesMinimumCorners && negative * 2 > measured;
}

/// One lap with its style and the figures behind it.
final class LapStyleResult {
  LapStyleResult({
    required this.lap,
    required this.seconds,
    required this.style,
    this.outlierReason = LapOutlierReason.none,
    List<LapCornerDeviation> corners = const [],
    this.brake = const LapTraitCount(),
    this.throttle = const LapTraitCount(),
    this.minimumSpeed = const LapTraitCount(),
    this.exitSpeed = const LapTraitCount(),
    this.medianBrakeMeters,
    this.medianPickupMeters,
    this.medianMinimumSpeed,
    this.medianExitSpeed,
    this.speedUnit = '',
    this.cornersCompared = 0,
    this.extremeCorners = 0,
  }) : corners = List.unmodifiable(corners);

  final Object lap;
  final double seconds;
  final LapStyle style;
  final LapOutlierReason outlierReason;

  /// The lap minus the day's typical at each corner it was compared in.
  final List<LapCornerDeviation> corners;

  /// Braking point (positive: earlier), throttle pickup (positive: later),
  /// minimum and exit speed (positive: higher).
  final LapTraitCount brake, throttle, minimumSpeed, exitSpeed;

  /// The median over the corners measured, signed as above; null where no
  /// corner was measured. The speeds are in [speedUnit].
  final double? medianBrakeMeters, medianPickupMeters, medianMinimumSpeed, medianExitSpeed;

  /// The unit the lap's speeds were read in, as declared; empty when the
  /// recording declares none.
  final String speedUnit;

  /// Corners with a braking or throttle figure, and of them the
  /// far-from-typical ones.
  final int cornersCompared, extremeCorners;
}

/// The laps of one style.
final class LapStyleGroup {
  LapStyleGroup({
    required this.style,
    required List<LapStyleResult> laps,
    required this.bestDeltaSeconds,
    required this.quickerHalfCount,
    this.typicalSeconds,
  }) : laps = List.unmodifiable(laps);

  final LapStyle style;

  /// Quickest first.
  final List<LapStyleResult> laps;

  LapStyleResult get best => laps.first;

  /// The group's best lap minus the day's best lap.
  final double bestDeltaSeconds;

  /// How many of the group's laps are among the quicker half of the day's.
  final int quickerHalfCount;

  /// The median lap time of the group, with at least [lapStylesMinimumLaps]
  /// laps.
  final double? typicalSeconds;
}

/// The day's laps by style.
final class LapStyles {
  LapStyles({
    this.unavailableReason = '',
    this.lapCount = 0,
    this.cornerCount = 0,
    List<LapStyleResult> laps = const [],
    List<LapStyleGroup> groups = const [],
    this.best,
  }) : laps = List.unmodifiable(laps),
       groups = List.unmodifiable(groups);

  /// Set when nothing could be grouped.
  final String unavailableReason;

  /// Laps given, and corners at which the day has a typical braking or
  /// throttle point.
  final int lapCount, cornerCount;

  /// Every lap, in the order given.
  final List<LapStyleResult> laps;

  /// The styles with laps, in [LapStyle] order.
  final List<LapStyleGroup> groups;

  /// The day's quickest lap.
  final LapStyleResult? best;

  bool get available => unavailableReason.isEmpty;

  LapStyleGroup? group(LapStyle style) {
    for (final group in groups) {
      if (group.style == style) return group;
    }
    return null;
  }

  /// The group the day's best lap is in.
  LapStyleGroup? get bestLapGroup => best == null ? null : group(best!.style);
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0;
}

/// A speed's group key: the channel and the unit as the speed units compare
/// them ("km/h" however written; another unit as written).
String _speedKey(LapCornerSample sample) {
  final known = normalizedSpeedUnit(sample.speedUnit);
  final unit = known.isNotEmpty ? known : sample.speedUnit.trim().toLowerCase();
  return '${sample.speedSource}|$unit';
}

/// The typical values of one measure at one corner, by source key.
typedef _Typicals = Map<String, double>;

_Typicals _typicals(List<(String, double)> values) {
  final byKey = <String, List<double>>{};
  for (final (key, value) in values) {
    if (value.isFinite) (byKey[key] ??= []).add(value);
  }
  return {
    for (final MapEntry(:key, :value) in byKey.entries)
      if (value.length >= lapStylesMinimumLaps) key: _median(value),
  };
}

/// [laps] (the day's ranked laps) grouped by style. Laps whose time is not a
/// positive number are left out. Never throws.
LapStyles computeLapStyles(List<LapStyleInput> laps) {
  final valid = [
    for (final lap in laps)
      if (lap.seconds.isFinite && lap.seconds > 0.0) lap,
  ];
  if (valid.length < lapStylesMinimumLaps) {
    return LapStyles(unavailableReason: lapStylesTooFewLaps, lapCount: valid.length);
  }

  final cornerIds = <String>[];
  final seen = <String>{};
  for (final lap in valid) {
    for (final sample in lap.corners) {
      if (seen.add(sample.cornerId)) cornerIds.add(sample.cornerId);
    }
  }
  final samplesAt = <String, List<(int, LapCornerSample)>>{for (final id in cornerIds) id: []};
  for (var i = 0; i < valid.length; ++i) {
    // A lap that lists a corner twice counts its first figures only.
    final listed = <String>{};
    for (final sample in valid[i].corners) {
      if (listed.add(sample.cornerId)) samplesAt[sample.cornerId]!.add((i, sample));
    }
  }

  // Typical values per corner and measure.
  final brakeTypical = <String, _Typicals>{};
  final pickupTypical = <String, _Typicals>{};
  final minimumTypical = <String, _Typicals>{};
  final exitTypical = <String, _Typicals>{};
  for (final id in cornerIds) {
    final samples = [for (final (_, sample) in samplesAt[id]!) sample];
    brakeTypical[id] = _typicals([
      for (final s in samples)
        if (s.brakeBeforeEntryMeters != null) (s.brakeSource, s.brakeBeforeEntryMeters!),
    ]);
    pickupTypical[id] = _typicals([
      for (final s in samples)
        if (s.pickupAfterEntryMeters != null) (s.pickupSource, s.pickupAfterEntryMeters!),
    ]);
    minimumTypical[id] = _typicals([
      for (final s in samples)
        if (s.minimumSpeed != null) (_speedKey(s), s.minimumSpeed!),
    ]);
    exitTypical[id] = _typicals([
      for (final s in samples)
        if (s.exitSpeed != null) (_speedKey(s), s.exitSpeed!),
    ]);
  }

  // Each lap's deviations.
  final deviations = <List<LapCornerDeviation>>[];
  final usable = <String>{};
  for (final lap in valid) {
    final listed = <String>{};
    final list = <LapCornerDeviation>[];
    for (final s in lap.corners) {
      if (!listed.add(s.cornerId)) continue;
      final id = s.cornerId;
      double? brake, pickup, minimum, minimumShare, exit, exitShare;
      final brakeBase = s.brakeBeforeEntryMeters == null ? null : brakeTypical[id]![s.brakeSource];
      if (brakeBase != null) brake = s.brakeBeforeEntryMeters! - brakeBase;
      final pickupBase = s.pickupAfterEntryMeters == null
          ? null
          : pickupTypical[id]![s.pickupSource];
      if (pickupBase != null) pickup = s.pickupAfterEntryMeters! - pickupBase;
      final key = _speedKey(s);
      final minimumBase = s.minimumSpeed == null ? null : minimumTypical[id]![key];
      if (minimumBase != null && s.minimumSpeed!.isFinite) {
        minimum = s.minimumSpeed! - minimumBase;
        minimumShare = minimumBase > 0.0 ? minimum / minimumBase : null;
      }
      final exitBase = s.exitSpeed == null ? null : exitTypical[id]![key];
      if (exitBase != null && s.exitSpeed!.isFinite) {
        exit = s.exitSpeed! - exitBase;
        exitShare = exitBase > 0.0 ? exit / exitBase : null;
      }
      final deviation = LapCornerDeviation(
        cornerId: id,
        brakeMeters: brake,
        pickupMeters: pickup,
        minimumSpeed: minimum,
        minimumSpeedShare: minimumShare,
        exitSpeed: exit,
        exitSpeedShare: exitShare,
      );
      if (deviation.hasFigure) list.add(deviation);
      // Speeds follow a lap's pace, so only braking and throttle make a
      // corner count towards telling a style.
      if (deviation.hasTiming) usable.add(id);
    }
    deviations.add(list);
  }
  if (usable.length < lapStylesMinimumCorners) {
    return LapStyles(
      unavailableReason: lapStylesTooFewCorners,
      lapCount: valid.length,
      cornerCount: usable.length,
    );
  }
  final enough = math.max(lapStylesMinimumCorners, (usable.length / 2.0).ceil());

  LapTraitCount count(
    List<LapCornerDeviation> list,
    double? Function(LapCornerDeviation) read,
    double threshold,
  ) {
    var measured = 0, positive = 0, negative = 0;
    for (final deviation in list) {
      final value = read(deviation);
      if (value == null) continue;
      ++measured;
      if (value > threshold) ++positive;
      if (value < -threshold) ++negative;
    }
    return LapTraitCount(measured: measured, positive: positive, negative: negative);
  }

  double? median(List<LapCornerDeviation> list, double? Function(LapCornerDeviation) read) {
    final values = [for (final deviation in list) ?read(deviation)];
    return values.isEmpty ? null : _median(values);
  }

  final results = <LapStyleResult>[];
  for (var i = 0; i < valid.length; ++i) {
    final input = valid[i];
    final list = deviations[i];
    final brake = count(list, (d) => d.brakeMeters, lapStylesBrakeMeters);
    final throttle = count(list, (d) => d.pickupMeters, lapStylesThrottleMeters);
    final minimum = count(list, (d) => d.minimumSpeedShare, lapStylesSpeedShare);
    final exit = count(list, (d) => d.exitSpeedShare, lapStylesSpeedShare);
    final extreme = list.where((d) => d.extreme).length;
    final timed = list.where((d) => d.hasTiming).length;
    String unit = '';
    for (final sample in input.corners) {
      if (sample.minimumSpeed != null || sample.exitSpeed != null) {
        unit = sample.speedUnit;
        break;
      }
    }
    final LapStyle style;
    var reason = LapOutlierReason.none;
    if (timed < enough) {
      style = LapStyle.outlier;
      reason = LapOutlierReason.fewCorners;
    } else if (extreme > 0 && extreme > lapStylesExtremeCornerShare * timed) {
      style = LapStyle.outlier;
      reason = LapOutlierReason.unlike;
    } else {
      final conservative = brake.mostlyPositive && throttle.mostlyPositive;
      final late = brake.mostlyNegative;
      final early = throttle.mostlyNegative;
      final leaning = brake.mostlyPositive || throttle.mostlyPositive;
      final fired = [conservative, late, early].where((fires) => fires).length;
      style = fired == 1
          ? (conservative
                ? LapStyle.conservative
                : late
                ? LapStyle.lateBraking
                : LapStyle.earlyThrottle)
          : fired > 1 || leaning
          ? LapStyle.mixed
          : LapStyle.typical;
    }
    results.add(
      LapStyleResult(
        lap: input.lap,
        seconds: input.seconds,
        style: style,
        outlierReason: reason,
        corners: list,
        brake: brake,
        throttle: throttle,
        minimumSpeed: minimum,
        exitSpeed: exit,
        medianBrakeMeters: median(list, (d) => d.brakeMeters),
        medianPickupMeters: median(list, (d) => d.pickupMeters),
        medianMinimumSpeed: median(list, (d) => d.minimumSpeed),
        medianExitSpeed: median(list, (d) => d.exitSpeed),
        speedUnit: unit,
        cornersCompared: timed,
        extremeCorners: extreme,
      ),
    );
  }

  // The day's quickest lap first among equals as given.
  var best = results.first;
  for (final result in results) {
    if (result.seconds < best.seconds) best = result;
  }
  final order = [...results]..sort((a, b) => a.seconds.compareTo(b.seconds));
  final quicker = {for (final result in order.take((order.length + 1) ~/ 2)) result};
  final groups = <LapStyleGroup>[];
  for (final style in LapStyle.values) {
    final members = [
      for (final result in order)
        if (result.style == style) result,
    ];
    if (members.isEmpty) continue;
    groups.add(
      LapStyleGroup(
        style: style,
        laps: members,
        bestDeltaSeconds: members.first.seconds - best.seconds,
        quickerHalfCount: members.where(quicker.contains).length,
        typicalSeconds: members.length >= lapStylesMinimumLaps
            ? _median([for (final member in members) member.seconds])
            : null,
      ),
    );
  }
  return LapStyles(
    lapCount: valid.length,
    cornerCount: usable.length,
    laps: results,
    groups: groups,
    best: best,
  );
}
