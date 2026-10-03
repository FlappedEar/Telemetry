// Port of FlappedEar Overlays native/src/telemetry/TemperatureAssociation.{h,cpp}
// (revision d4d1039, FET-36): how a recorded temperature moves together with
// a lap metric (lap time, strong acceleration) over a population of
// comparable laps (KAN-100). The measure is Spearman's rank correlation: both
// series are ranked (ties share their average rank) and the Pearson
// correlation of the ranks is reported, from -1 (one rises as the other
// falls) to +1 (both rise together). It describes a monotonic association in
// the observed laps only; it never establishes a critical temperature or a
// cause.
import 'dart:math' as math;

import '../telemetry_session.dart';

const String temperatureAssociationAlgorithm = 'spearman-rank-v1';
const int minimumAssociationSamples = 8;

/// A lap's temperature counts only when the sensor covered most of the lap.
const double minimumAssociationCoverage = 0.8;

/// Temperature rising (or falling) with the order of laps through the day at
/// least this strongly means any association cannot be told apart from
/// everything else that changes over a day (the driver, tyres, track, fuel).
const double associationOrderConfoundLevel = 0.6;

const String associationTooFewSamples = 'tooFewSamples';
const String associationNoSpread = 'noSpread';

/// Spearman's rank correlation of two series, or why there is none.
final class RankCorrelation {
  const RankCorrelation({this.count = 0, this.coefficient, this.unavailableReason = ''});

  /// Finite pairs used.
  final int count;

  /// Spearman's rho.
  final double? coefficient;
  final String unavailableReason;
}

// 1-based ranks; tied values share the average of their ranks.
List<double> _ranks(List<double> values) {
  final order = List<int>.generate(values.length, (index) => index)
    ..sort((a, b) => values[a].compareTo(values[b]));
  final result = List<double>.filled(values.length, 0.0);
  for (var start = 0; start < order.length;) {
    var end = start + 1;
    while (end < order.length && values[order[end]] == values[order[start]]) {
      ++end;
    }
    final rank = (start + 1 + end) / 2.0; // average of ranks start+1 .. end
    for (var index = start; index < end; ++index) {
      result[order[index]] = rank;
    }
    start = end;
  }
  return result;
}

/// Pairs with a non-finite value are skipped. Unavailable below [minimum]
/// pairs, or when either series has a single distinct value.
RankCorrelation spearmanCorrelation(
  List<double> x,
  List<double> y, [
  int minimum = minimumAssociationSamples,
]) {
  final a = <double>[], b = <double>[];
  for (var index = 0; index < math.min(x.length, y.length); ++index) {
    if (!x[index].isFinite || !y[index].isFinite) continue;
    a.add(x[index]);
    b.add(y[index]);
  }
  final count = a.length;
  if (count < math.max(minimum, 2)) {
    return RankCorrelation(count: count, unavailableReason: associationTooFewSamples);
  }
  final rankA = _ranks(a), rankB = _ranks(b);
  final mean = (count + 1) / 2.0; // the mean rank, ties included
  var covariance = 0.0, varianceA = 0.0, varianceB = 0.0;
  for (var index = 0; index < count; ++index) {
    final da = rankA[index] - mean, db = rankB[index] - mean;
    covariance += da * db;
    varianceA += da * da;
    varianceB += db * db;
  }
  if (!(varianceA > 0.0) || !(varianceB > 0.0)) {
    return RankCorrelation(count: count, unavailableReason: associationNoSpread);
  }
  return RankCorrelation(
    count: count,
    coefficient: (covariance / math.sqrt(varianceA * varianceB)).clamp(-1.0, 1.0),
  );
}

/// "weak" below 0.3 in magnitude, "moderate" below 0.6, otherwise "strong".
String associationStrength(double coefficient) {
  final magnitude = coefficient.abs();
  if (magnitude < 0.3) return 'weak';
  if (magnitude < 0.6) return 'moderate';
  return 'strong';
}

/// One lap: its temperature, its metric and its place in the day.
final class AssociationObservation {
  const AssociationObservation(this.temperature, this.value, this.order);

  final double temperature;

  /// The lap metric.
  final double value;

  /// Position in the day.
  final double order;
}

/// A temperature against a lap metric and against the time of day.
final class TemperatureAssociation {
  const TemperatureAssociation({
    this.withValue = const RankCorrelation(),
    this.withOrder = const RankCorrelation(),
    this.confoundedByOrder = false,
  });

  final RankCorrelation withValue;
  final RankCorrelation withOrder;

  /// The temperature follows the order of laps too strongly to tell an
  /// association apart from the day's progression.
  final bool confoundedByOrder;
}

/// Laps need at least this many positive longitudinal-G samples for a strong
/// acceleration.
const int minimumAccelerationSamples = 20;

/// A lap's strong acceleration, or none.
final class LapAcceleration {
  const LapAcceleration({this.strongG, this.channel = '', this.sampleCount = 0});

  final double? strongG;

  /// The recording's longitudinal acceleration channel, or empty.
  final String channel;

  /// Positive samples considered.
  final int sampleCount;
}

/// A lap's strong acceleration: the 90th percentile of its positive
/// longitudinal G samples (the `longitudinalAcceleration` alias, g or
/// undeclared units, |G| up to 4). A percentile rather than the peak, so one
/// noisy sample does not decide it. None with fewer than
/// [minimumAccelerationSamples] positive samples.
LapAcceleration lapStrongAcceleration(TelemetrySession session, double startTime, double endTime) {
  final channel = session.aliases['longitudinalAcceleration'] ?? '';
  final found = session.channels[channel];
  if (channel.isEmpty ||
      found == null ||
      found.timestamps.length != found.values.length ||
      !startTime.isFinite ||
      !endTime.isFinite ||
      endTime <= startTime) {
    return LapAcceleration(channel: channel);
  }
  final unit = found.unit.trim();
  if (unit.isNotEmpty && unit.toLowerCase() != 'g') return LapAcceleration(channel: channel);
  final times = found.timestamps;
  final positive = <double>[];
  for (
    var index = lowerBound(times, startTime);
    index < times.length && times[index] <= endTime;
    ++index
  ) {
    final double value = found.values[index];
    if (value.isFinite && value > 0.0 && value <= 4.0) positive.add(value);
  }
  if (positive.length < minimumAccelerationSamples) {
    return LapAcceleration(channel: channel, sampleCount: positive.length);
  }
  positive.sort();
  return LapAcceleration(
    strongG: positive[(0.9 * positive.length).ceil() - 1],
    channel: channel,
    sampleCount: positive.length,
  );
}

/// The temperatures of [observations] against their metric and against
/// their order.
TemperatureAssociation associateTemperature(
  List<AssociationObservation> observations, [
  int minimum = minimumAssociationSamples,
]) {
  final temperature = [for (final observation in observations) observation.temperature];
  final value = [for (final observation in observations) observation.value];
  final order = [for (final observation in observations) observation.order];
  final withValue = spearmanCorrelation(temperature, value, minimum);
  final withOrder = spearmanCorrelation(temperature, order, minimum);
  final orderCoefficient = withOrder.coefficient;
  return TemperatureAssociation(
    withValue: withValue,
    withOrder: withOrder,
    confoundedByOrder:
        orderCoefficient != null && orderCoefficient.abs() >= associationOrderConfoundLevel,
  );
}
