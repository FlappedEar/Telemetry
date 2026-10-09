// Port of FlappedEar Overlays native/src/telemetry/GgPairs.{h,cpp}
// (revision d4d1039, FET-39): longitudinal/lateral acceleration pairs for a
// G-G diagram (KAN-65), their observed peaks (KAN-66) and a thinned set of
// points for drawing.
//
// Clock: the longitudinal channel's own samples are the clock. The lateral
// value at each of those times is the lateral sample at the same time when
// the two channels share a clock, otherwise a linear interpolation between
// the two lateral samples around it, but only when those samples are no
// further apart than the lateral channel's gap threshold. Gaps are never
// bridged; a longitudinal sample without a lateral value yields no point.
//
// Signs (as RaceChrono records them): longitudinal + accelerating,
// - braking; lateral + toward the left. Units: a declared "g" is used as is,
// "m/s2" / "m/s^2" / "m/s²" is converted (1 g = 9.80665 m/s²), an
// undeclared unit is kept and reported, any other unit makes the pairs
// unavailable rather than guessing. Outliers: a value beyond the plausible
// limit for a road car is excluded and counted, never clipped.
import 'dart:math' as math;

import '../channel_units.dart';
import '../geometry.dart' show hypot;
import '../telemetry_session.dart';

const String ggPairsAlgorithm = 'gg-pairs-v1';
const double ggPlausibleLimitG = 4.0;

/// Unavailable reasons.
const String ggMissingLongitudinal = 'missingLongitudinalAcceleration';
const String ggMissingLateral = 'missingLateralAcceleration';
const String ggUnsupportedUnit = 'unsupportedUnit';
const String ggNoOverlap = 'noOverlappingSamples';

/// One pair: the longitudinal sample's time and both accelerations in g.
final class GgPoint {
  const GgPoint(this.time, this.longitudinalG, this.lateralG);

  final double time;
  final double longitudinalG;
  final double lateralG;
}

/// The pairs of a time window and how they were formed.
final class GgPairs {
  GgPairs();

  final List<GgPoint> points = [];
  String longitudinalChannel = '';
  String lateralChannel = '';

  /// As declared by the recording; empty when undeclared.
  String longitudinalUnit = '';
  String lateralUnit = '';
  bool unitsDeclared = false;

  /// Lateral samples at exactly the longitudinal times.
  bool sharedClock = false;

  /// Largest time to the nearest lateral sample used.
  double maximumPairingOffsetSeconds = 0.0;

  /// Finite longitudinal samples in range.
  int candidateCount = 0;

  /// No lateral value without bridging a gap.
  int skippedForGap = 0;
  int excludedOutliers = 0;
  String unavailableReason = '';
  bool valid = false;
}

/// The pairs over [startTime]..[endTime] of the `longitudinalAcceleration`
/// and `lateralAcceleration` channels of [session].
GgPairs buildGgPairs(TelemetrySession session, double startTime, double endTime) {
  final result = GgPairs();
  result.longitudinalChannel = session.aliases['longitudinalAcceleration'] ?? '';
  result.lateralChannel = session.aliases['lateralAcceleration'] ?? '';
  final longitudinal = session.channels[result.longitudinalChannel];
  final lateral = session.channels[result.lateralChannel];
  if (result.longitudinalChannel.isEmpty || longitudinal == null) {
    result.unavailableReason = ggMissingLongitudinal;
    return result;
  }
  if (result.lateralChannel.isEmpty || lateral == null) {
    result.unavailableReason = ggMissingLateral;
    return result;
  }
  // The units the recording declares, a VBO's on its header line.
  result.longitudinalUnit = declaredChannelUnit(session, result.longitudinalChannel);
  result.lateralUnit = declaredChannelUnit(session, result.lateralChannel);
  result.unitsDeclared = result.longitudinalUnit.isNotEmpty && result.lateralUnit.isNotEmpty;
  final longitudinalFactor = accelerationGPerUnit(result.longitudinalUnit);
  final lateralFactor = accelerationGPerUnit(result.lateralUnit);
  if (longitudinalFactor == null || lateralFactor == null) {
    result.unavailableReason = ggUnsupportedUnit;
    return result;
  }
  if (!startTime.isFinite ||
      !endTime.isFinite ||
      endTime <= startTime ||
      longitudinal.timestamps.length != longitudinal.values.length ||
      lateral.timestamps.length != lateral.values.length ||
      lateral.timestamps.isEmpty) {
    result.unavailableReason = ggNoOverlap;
    return result;
  }
  result.valid = true;
  final lateralTimes = lateral.timestamps;
  final lateralValues = lateral.values;
  final gapLimit = telemetryGapThreshold(lateral);
  var shared = true;
  for (var i = 0; i < longitudinal.timestamps.length; ++i) {
    final time = longitudinal.timestamps[i];
    if (time < startTime || time > endTime) continue;
    final double longitudinalValue = longitudinal.values[i];
    if (!longitudinalValue.isFinite) continue;
    ++result.candidateCount;
    final nextIndex = lowerBound(lateralTimes, time);
    double? lateralValue;
    var offset = 0.0;
    if (nextIndex < lateralTimes.length && lateralTimes[nextIndex] == time) {
      final double value = lateralValues[nextIndex];
      if (value.isFinite) lateralValue = value;
    } else {
      shared = false;
      if (nextIndex > 0 && nextIndex < lateralTimes.length) {
        final before = lateralTimes[nextIndex - 1], after = lateralTimes[nextIndex];
        final double a = lateralValues[nextIndex - 1], b = lateralValues[nextIndex];
        if (after - before <= gapLimit && a.isFinite && b.isFinite) {
          lateralValue = a + (b - a) * (time - before) / (after - before);
          offset = math.min(time - before, after - time);
        }
      }
    }
    if (lateralValue == null) {
      ++result.skippedForGap;
      continue;
    }
    final longitudinalG = longitudinalValue * longitudinalFactor;
    final lateralG = lateralValue * lateralFactor;
    if (!longitudinalG.isFinite ||
        !lateralG.isFinite ||
        longitudinalG.abs() > ggPlausibleLimitG ||
        lateralG.abs() > ggPlausibleLimitG) {
      ++result.excludedOutliers;
      continue;
    }
    result.maximumPairingOffsetSeconds = math.max(result.maximumPairingOffsetSeconds, offset);
    result.points.add(GgPoint(time, longitudinalG, lateralG));
  }
  result.sharedClock = shared && result.candidateCount > 0;
  if (result.candidateCount == 0) result.unavailableReason = ggNoOverlap;
  return result;
}

/// One observed peak: its value (positive) and the pair it comes from.
final class GgPeak {
  const GgPeak(this.value, this.point);

  final double value;
  final GgPoint point;
}

/// Observed peaks of a set of pairs, always from every pair, never from a
/// thinned display subset. Braking is the most negative longitudinal value,
/// reported as a positive deceleration; combined is the largest magnitude
/// sqrt(longitudinal² + lateral²). Observed values, not a share of grip.
final class GgPeaks {
  GgPeak? lateral;
  GgPeak? braking;
  GgPeak? acceleration;
  GgPeak? combined;
  int sampleCount = 0;
}

/// sqrt(x² + y²), rounded exactly like Overlays' `std::hypot`.
double ggMagnitude(double x, double y) => hypot(x, y);

GgPeaks computeGgPeaks(List<GgPoint> points) {
  final peaks = GgPeaks()..sampleCount = points.length;
  GgPeak? consider(GgPeak? peak, double value, GgPoint point) =>
      value > 0.0 && (peak == null || value > peak.value) ? GgPeak(value, point) : peak;
  for (final point in points) {
    peaks.lateral = consider(peaks.lateral, point.lateralG.abs(), point);
    peaks.braking = consider(peaks.braking, -point.longitudinalG, point);
    peaks.acceleration = consider(peaks.acceleration, point.longitudinalG, point);
    peaks.combined = consider(
      peaks.combined,
      ggMagnitude(point.longitudinalG, point.lateralG),
      point,
    );
  }
  return peaks;
}

/// At most [maximumPoints] points for drawing, evenly spaced in time, plus
/// every peak point; the peaks themselves are unaffected.
List<GgPoint> decimateGgPoints(List<GgPoint> points, GgPeaks peaks, int maximumPoints) {
  if (maximumPoints <= 0 || points.length <= maximumPoints) return List.of(points);
  final result = <GgPoint>[];
  final step = points.length / maximumPoints;
  for (var k = 0; k < maximumPoints; ++k) {
    result.add(points[(k * step).toInt()]);
  }
  for (final peak in [peaks.lateral, peaks.braking, peaks.acceleration, peaks.combined]) {
    if (peak != null) result.add(peak.point);
  }
  return result;
}
