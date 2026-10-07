// How the driver brakes into each corner (FET-219, roadmap idea 3): the
// initial hit, the peak deceleration and where it falls, trail braking, the
// release into the apex and the time from braking to throttle, per lap and
// typically over the day's ranked laps.
//
// Everything comes from the longitudinal deceleration: the recorded
// longitudinal G when there is one with data, otherwise the speed's slope
// ("from speed"). The brake pedal is never read for a ramp or a release when
// it updates slower than [brakingTechniqueMinimumRateHz]: OBD pedals update
// about twice a second, and RaceChrono's VBO export draws straight lines
// between those updates at 10 Hz, so the effective rate is measured from the
// values ([channelUpdateRateHz]), not from the row rate. Trail braking is
// inferred from lateral G: there is no steering channel.
//
// Every figure is a time based measurement on one clock (the deceleration's
// samples); distances integrate the recorded speed. A corner that crosses
// start/finish (its end before its start) is measured on the lap whose end
// it begins at, reading the recording past the lap's end.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart' show TrackSegmentType, trackSegmentTypeName;

import '../speed_units.dart';
import '../telemetry_session.dart';
import 'braking_source.dart';
import 'consistency.dart';
import 'exit_metrics.dart' show measuredThrottlePickup;
import 'gg_pairs.dart' show standardGravity;
import 'pedal_scale.dart';
import 'track_progress.dart';

const String brakingTechniqueAlgorithm = 'braking-technique-v1';

/// Braking starts where the deceleration rises through
/// [brakingTechniqueOffG] on its way to [brakingTechniqueOnG] and ends where
/// it falls back below [brakingTechniqueOffG] (the braking onset's inferred
/// thresholds).
const double brakingTechniqueOnG = 0.30;
const double brakingTechniqueOffG = 0.15;

/// A braking shorter than this is a bump, not braking.
const double brakingTechniqueMinimumSeconds = 0.3;

/// Hit and release are read only from braking that peaks at least this hard.
const double brakingTechniqueMinimumPeakG = 0.40;

/// The hit runs from braking onset to this share of the peak, the release
/// from the last moment at this share of the peak to the end of braking.
const double brakingTechniquePeakShare = 0.85;

/// Samples a hit or a release must span, its ends included: fewer, and it
/// happened between two samples, too quick for the channel to show.
const int brakingTechniqueMinimumRampSamples = 3;

/// Trail braking: braking while the lateral G is at least this much.
const double brakingTechniqueTrailLateralG = 0.30;

/// Channels updating slower than this (about 10 Hz) give no ramp or release.
const double brakingTechniqueMinimumRateHz = 9.5;

/// How far before the corner's start braking is looked for, as the braking
/// point is (BrakingMetricsOptions.approachMeters).
const double brakingTechniqueApproachMeters = 200.0;

/// The speed's slope is a least-squares line over this long either side of
/// each sample, so GPS noise does not read as deceleration.
const double brakingTechniqueSpeedSlopeHalfWindowSeconds = 0.25;

/// Seconds of recording read beyond the corner's window, so a braking that
/// starts at its edge is seen whole.
const double brakingTechniqueSearchPadSeconds = 3.0;

/// A brake pedal (in %) is pressed from this value.
const double brakingTechniquePedalPressedPercent = 10.0;

/// Typical values need this many laps.
const int brakingTechniqueMinimumLaps = minimumConsistencySamples;

/// A channel whose moving values lie on straight lines at least this share
/// of the time is a slower signal drawn with straight lines; its update rate
/// is then read from the corners of those lines.
const double brakingTechniqueInterpolatedShare = 0.45;

/// Spacings between corners of straight lines needed before a channel is
/// judged drawn with lines: a recorded signal that really is straight for a
/// while (a constant deceleration) has few.
const int brakingTechniqueMinimumLineCorners = 10;

/// Lines drawn between updates bend at a regular spacing (the update
/// period): the interquartile range of the spacings is at most this share
/// of their median. The mean spacing is then the update interval.
const double brakingTechniqueLineSpacingSpread = 0.5;

/// Corners of straight lines count only when they are sharp: typically this
/// many times the values' resolution off the line.
const double brakingTechniqueSharpCornerRatio = 10.0;

/// Two samples apart, a channel moves when it changes by at least this share
/// of its range.
const double brakingTechniqueMovingShare = 0.02;

/// Moving steps needed to judge whether a channel is drawn with lines.
const int brakingTechniqueMinimumMovingSteps = 20;

/// Where the deceleration comes from.
const String brakingTechniqueFromG = 'longitudinalG';
const String brakingTechniqueFromSpeed = 'speed';

/// Reasons a figure is not known.
const String brakingTechniqueNoDeceleration = 'noDecelerationSource';
const String brakingTechniqueDecelerationTooSlow = 'decelerationTooSlow';
const String brakingTechniqueSpeedUnitUnknown = 'speedUnitUnknown';
const String brakingTechniqueNotCovered = 'notCovered';
const String brakingTechniqueNoBraking = 'noBraking';
const String brakingTechniqueAlreadyBraking = 'alreadyBraking';
const String brakingTechniqueGap = 'gap';
const String brakingTechniqueTruncated = 'truncated';
const String brakingTechniqueTooLight = 'brakingTooLight';
const String brakingTechniqueTooQuick = 'tooQuickForSamples';
const String brakingTechniqueNoLateral = 'noLateralChannel';
const String brakingTechniqueLateralPlaceholder = 'lateralChannelEmpty';
const String brakingTechniqueLateralTooSlow = 'lateralTooSlow';
const String brakingTechniqueUnitNotSupported = 'unitNotSupported';
const String brakingTechniqueNoThrottle = 'noThrottleChannel';
const String brakingTechniqueNoPickup = 'noPickup';
const String brakingTechniqueNoBrake = 'noBrakeChannel';
const String brakingTechniqueBrakeTooSlow = 'brakeChannelTooSlow';
const String brakingTechniqueBrakeNotUsed = 'brakeChannelNotUsed';
const String brakingTechniqueBrakeScaleUnknown = 'brakeScaleUnknown';
const String brakingTechniqueTooFewLaps = 'tooFewLaps';

/// Why the G channel was not used and the deceleration comes from speed.
const String brakingTechniqueGMissing = 'noGChannel';
const String brakingTechniqueGPlaceholder = 'gChannelEmpty';

/// How often [channel]'s values really change, in Hz, or null when that
/// cannot be told (fewer than two samples). The slowest of: its median
/// sample interval; the median time between value changes (a held value);
/// and, when its moving values mostly lie on straight lines
/// ([brakingTechniqueInterpolatedShare]), the time between the corners of
/// those lines (a slower signal interpolated at the row rate, as
/// RaceChrono's VBO export writes OBD channels).
double? channelUpdateRateHz(TelemetryChannel channel) {
  final cached = _rates[channel];
  if (cached != null) return cached.isNaN ? null : cached;
  final rate = _updateRate(channel);
  _rates[channel] = rate ?? double.nan;
  return rate;
}

final _rates = Expando<double>('channel update rate');

double? _updateRate(TelemetryChannel channel) {
  final base = channel.baseIntervalSeconds;
  final times = channel.timestamps, values = channel.values;
  if (!(base > 0.0) || times.length != values.length) return null;
  final gap = telemetryGapThreshold(channel);
  bool joined(int i) =>
      i > 0 && values[i].isFinite && values[i - 1].isFinite && times[i] - times[i - 1] <= gap;

  // Held values: the time between changes while the value moves.
  final changes = <double>[];
  double? lastChange;
  var lowest = double.infinity, highest = double.negativeInfinity;
  for (var i = 0; i < values.length; ++i) {
    if (values[i].isFinite) {
      lowest = math.min(lowest, values[i]);
      highest = math.max(highest, values[i]);
    }
    if (!joined(i)) {
      lastChange = null;
      continue;
    }
    if (values[i] == values[i - 1]) continue;
    if (lastChange != null && times[i] - lastChange <= 2.0) changes.add(times[i] - lastChange);
    lastChange = times[i];
  }
  var interval = base;
  if (changes.length >= brakingTechniqueMinimumMovingSteps) {
    changes.sort();
    interval = math.max(interval, changes[changes.length ~/ 2]);
  }
  final range = highest - lowest;
  if (!(range > 0)) return 1.0 / interval;

  // Straight lines: moving triples (their ends at least
  // [brakingTechniqueMovingShare] of the channel's range apart) whose middle
  // lies on the line between its neighbours to within the values' written
  // resolution (RaceChrono's VBO writes three decimals) and the rounding of
  // 32-bit samples. Corners come singly or in pairs (a corner between two
  // samples bends both triples around it); a longer run of bends is a
  // signal that bends at every sample.
  final tolerance = 1.5 * _writtenResolution(values);
  var moving = 0, straight = 0;
  final bends = <double>[];
  // Samples between consecutive corners within one moving stretch.
  final spacings = <int>[];
  int? lastCorner;
  final run = <int>[];
  void corner(int index) {
    if (lastCorner != null) spacings.add(index - lastCorner!);
    lastCorner = index;
  }

  void endRun({bool stretchEnds = false}) {
    if (run.isNotEmpty && run.length <= 2) {
      corner(run.first);
    } else {
      run.forEach(corner);
    }
    run.clear();
    if (stretchEnds) lastCorner = null;
  }

  for (var i = 1; i + 1 < values.length; ++i) {
    if (!joined(i) || !joined(i + 1)) {
      endRun(stretchEnds: true);
      continue;
    }
    final a = values[i - 1], b = values[i], c = values[i + 1];
    if ((c - a).abs() < math.max(4 * tolerance, brakingTechniqueMovingShare * range)) {
      endRun(stretchEnds: true);
      continue;
    }
    ++moving;
    final predicted = a + (c - a) * (times[i] - times[i - 1]) / (times[i + 1] - times[i - 1]);
    // Within the values' resolution, and the rounding of 32-bit samples.
    final size = math.max(a.abs(), math.max(b.abs(), c.abs()));
    final allowed = tolerance + 5e-7 * size;
    final off = (b - predicted).abs();
    if (off <= allowed) {
      ++straight;
      endRun();
    } else {
      run.add(i);
      bends.add(off / allowed);
    }
  }
  endRun(stretchEnds: true);
  // Lines drawn between updates: mostly straight, with sharp corners (far
  // beyond the resolution; a smooth curve written coarsely only just
  // leaves it) at a regular spacing, the update period.
  bends.sort();
  spacings.sort();
  if (moving >= brakingTechniqueMinimumMovingSteps &&
      straight >= brakingTechniqueInterpolatedShare * moving &&
      spacings.length >= brakingTechniqueMinimumLineCorners &&
      bends[bends.length ~/ 2] >= brakingTechniqueSharpCornerRatio) {
    double quantile(double q) => spacings[(q * (spacings.length - 1)).round()].toDouble();
    final median = quantile(0.5);
    // Corners a sample apart are a signal bending at its own rate (the
    // sharp edges of a pedal pressed and let off), not lines between
    // slower updates.
    if (median >= 2 &&
        quantile(0.75) - quantile(0.25) <= brakingTechniqueLineSpacingSpread * median) {
      // The mean spacing: an update period between two row intervals shows
      // as a mix of the two.
      final mean = spacings.fold(0, (sum, spacing) => sum + spacing) / spacings.length;
      interval = math.max(interval, base * mean);
    }
  }
  return 1.0 / interval;
}

// The step [values] are written in: 1, 0.1, … 0.000001 when every value
// is a whole number of it (to 32-bit rounding), else 0.
double _writtenResolution(Float32List values) {
  for (var k = 0; k <= 6; ++k) {
    final step = math.pow(10, -k).toDouble();
    var whole = true;
    for (final value in values) {
      if (!value.isFinite) continue;
      final units = value / step;
      if ((units - units.roundToDouble()).abs() > 0.01 + 2.4e-7 * value.abs() / step) {
        whole = false;
        break;
      }
    }
    if (whole) return step;
  }
  return 0.0;
}

/// Whether [channel] has no data: no finite value, or every finite value the
/// same (RaceChrono writes zero placeholders for channels it did not log).
bool brakingTechniquePlaceholder(TelemetryChannel channel) {
  double? first;
  for (final value in channel.values) {
    if (!value.isFinite) continue;
    first ??= value;
    if (value != first) return false;
  }
  return true;
}

/// G per one [unit] of acceleration ("g" or none, read as g; m/s²), or null.
double? _gPer(String unit) => switch (unit.trim().toLowerCase().replaceAll(' ', '')) {
  '' || 'g' => 1.0,
  'm/s2' || 'm/s^2' || 'm/s²' => 1 / standardGravity,
  _ => null,
};

/// One lap's braking into one corner.
final class BrakingTechniqueLap {
  /// Set when no braking zone was measured.
  String unavailableReason = '';

  /// [brakingTechniqueFromG] or [brakingTechniqueFromSpeed].
  String source = '';
  String channel = '';

  /// As the recording declares it; empty when undeclared ([unitAssumed]).
  String declaredUnit = '';

  /// No unit declared: a G channel read as g, a speed read as km/h.
  bool unitAssumed = false;

  /// The deceleration channel's update rate.
  double? rateHz;

  /// Why the G channel was not used when [source] is speed.
  String gChannelReason = '';

  /// The braking zone: onset, peak and end, recording times.
  double? onsetTime, peakTime, endTime;

  /// Deceleration in g, positive.
  double? peakG;
  double? zoneSeconds;

  /// From the recorded speed; null without one in a known unit.
  double? zoneMeters, peakAfterOnsetMeters;

  /// How far through the braking zone the peak falls, 0 to 1: by distance,
  /// or by time without a speed.
  double? peakFraction;

  /// G per second from onset to [brakingTechniquePeakShare] of the peak.
  double? hitGPerSecond;
  String hitReason = '';

  /// G per second from the last moment at [brakingTechniquePeakShare] of the
  /// peak to the end of braking.
  double? releaseGPerSecond;
  String releaseReason = '';

  /// Braking while the lateral G is at least
  /// [brakingTechniqueTrailLateralG] (inferred: no steering channel).
  double? trailSeconds, trailMeters;
  String trailReason = '';
  String lateralChannel = '';
  double? lateralRateHz;

  /// From the end of braking to the measured throttle pickup; negative when
  /// the throttle comes before the deceleration falls below
  /// [brakingTechniqueOffG].
  double? brakeToThrottleSeconds;
  String brakeToThrottleReason = '';
  String throttleChannel = '';
  double? throttleRateHz;

  /// The brake pedal: its update rate and, only from
  /// [brakingTechniqueMinimumRateHz], how fast it is pressed and let off,
  /// in % per second.
  String brakeChannel = '';
  double? brakeRateHz;
  double? pedalApplicationPerSecond, pedalReleasePerSecond;
  String pedalReason = '';

  /// The corner crosses start/finish, or its approach reaches before the
  /// lap's start: the recording beyond the lap was read.
  bool beyondLap = false;

  bool get measured => onsetTime != null;
}

/// A deceleration (or other) series: times and values, with NaN where data
/// is missing or a gap splits it.
typedef _Series = ({List<double> times, List<double> values});

_Series _channelSeries(TelemetryChannel channel, double from, double to, double scale) {
  final times = <double>[], values = <double>[];
  final gap = telemetryGapThreshold(channel);
  final begin = lowerBound(channel.timestamps, from);
  final end = upperBound(channel.timestamps, to);
  for (var i = begin; i < end; ++i) {
    final time = channel.timestamps[i];
    if (times.isNotEmpty && gap > 0.0 && time - times.last > gap && values.last.isFinite) {
      times.add((time + times.last) / 2);
      values.add(double.nan);
    }
    final double value = channel.values[i];
    times.add(time);
    values.add(value.isFinite ? value * scale : double.nan);
  }
  return (times: times, values: values);
}

// Deceleration in g from the speed's least-squares slope over
// [brakingTechniqueSpeedSlopeHalfWindowSeconds] either side of each sample.
_Series _speedDeceleration(TelemetryChannel speed, double factor, double from, double to) {
  final times = <double>[], values = <double>[];
  final t = speed.timestamps, v = speed.values;
  final gap = telemetryGapThreshold(speed);
  const half = brakingTechniqueSpeedSlopeHalfWindowSeconds;
  final begin = lowerBound(t, from), end = upperBound(t, to);
  for (var i = begin; i < end; ++i) {
    times.add(t[i]);
    var lo = i, hi = i;
    var broken = !v[i].isFinite;
    while (!broken && lo > 0 && t[i] - t[lo - 1] <= half) {
      if (!v[lo - 1].isFinite || t[lo] - t[lo - 1] > gap) broken = true;
      --lo;
    }
    while (!broken && hi + 1 < t.length && t[hi + 1] - t[i] <= half) {
      if (!v[hi + 1].isFinite || t[hi + 1] - t[hi] > gap) broken = true;
      ++hi;
    }
    // Both sides covered, so the slope is centred on the sample.
    final covered = t[i] - t[lo] >= 0.6 * half && t[hi] - t[i] >= 0.6 * half;
    if (broken || !covered || hi - lo + 1 < 4) {
      values.add(double.nan);
      continue;
    }
    var meanT = 0.0, meanV = 0.0;
    for (var k = lo; k <= hi; ++k) {
      meanT += t[k];
      meanV += v[k];
    }
    final n = hi - lo + 1;
    meanT /= n;
    meanV /= n;
    var sxy = 0.0, sxx = 0.0;
    for (var k = lo; k <= hi; ++k) {
      sxy += (t[k] - meanT) * (v[k] - meanV);
      sxx += (t[k] - meanT) * (t[k] - meanT);
    }
    values.add(sxx > 0 ? -(sxy / sxx) * factor / standardGravity : double.nan);
  }
  return (times: times, values: values);
}

double _cross(_Series s, int a, int b, double level) {
  final va = s.values[a], vb = s.values[b];
  if (va == vb) return s.times[b];
  return s.times[a] + (s.times[b] - s.times[a]) * (level - va) / (vb - va);
}

/// One braking episode in a series: the indices of its first and last
/// samples at or beyond [off], its onset and end crossings, and its peak.
typedef _Episode = ({int first, int last, double onset, double end, int peak, String reason});

// The first episode whose rise through [on] lies in [from]..[to]: from
// where the series rises through [off] to where it falls back below it.
_Episode? _firstEpisode(
  _Series s,
  double from,
  double to,
  double on,
  double off,
  double minimumSeconds,
) {
  final n = s.times.length;
  var i = lowerBound(s.times, from);
  final stop = upperBound(s.times, to);
  // Braking already under way where the window starts belongs to a braking
  // that started before it.
  if (i < stop && i > 0 && s.values[i] >= on && s.values[i - 1] >= on) {
    return (first: i, last: i, onset: 0, end: 0, peak: i, reason: brakingTechniqueAlreadyBraking);
  }
  for (; i < stop; ++i) {
    if (!(s.values[i] >= on)) continue;
    if (i > 0 && s.values[i - 1] >= on) continue;
    var first = i;
    while (first > 0 && s.values[first - 1] > off) {
      --first;
    }
    var last = i;
    while (last + 1 < n && s.values[last + 1] >= off) {
      ++last;
    }
    var peak = first;
    for (var k = first; k <= last; ++k) {
      if (s.values[k] > s.values[peak]) peak = k;
    }
    if (first == 0 || !s.values[first - 1].isFinite) {
      return (
        first: first,
        last: last,
        onset: 0,
        end: 0,
        peak: peak,
        reason: first == 0 ? brakingTechniqueAlreadyBraking : brakingTechniqueGap,
      );
    }
    if (last + 1 >= n || !s.values[last + 1].isFinite) {
      return (
        first: first,
        last: last,
        onset: 0,
        end: 0,
        peak: peak,
        reason: last + 1 >= n ? brakingTechniqueTruncated : brakingTechniqueGap,
      );
    }
    final onset = _cross(s, first - 1, first, off);
    final end = _cross(s, last, last + 1, off);
    if (end - onset < minimumSeconds) {
      i = last;
      continue;
    }
    return (first: first, last: last, onset: onset, end: end, peak: peak, reason: '');
  }
  return null;
}

typedef _Ramps = ({double? hit, String hitReason, double? release, String releaseReason});

// How fast [episode] rises from [off] to [share] of its peak and falls from
// there back to [off], in units per second.
_Ramps _ramps(_Series s, _Episode episode, double off, double minimumPeak) {
  final peak = s.values[episode.peak];
  if (peak < minimumPeak) {
    return (
      hit: null,
      hitReason: brakingTechniqueTooLight,
      release: null,
      releaseReason: brakingTechniqueTooLight,
    );
  }
  final level = brakingTechniquePeakShare * peak;
  var up = episode.first;
  while (s.values[up] < level) {
    ++up;
  }
  final upTime = _cross(s, up - 1, up, level);
  // Samples from the last one below [off] to the first at the level.
  final hitSamples = up - episode.first + 2;
  var down = episode.last;
  while (s.values[down] < level) {
    --down;
  }
  final downTime = _cross(s, down, down + 1, level);
  final releaseSamples = episode.last - down + 2;
  final hitSeconds = upTime - episode.onset, releaseSeconds = episode.end - downTime;
  final hitOk = hitSamples >= brakingTechniqueMinimumRampSamples && hitSeconds > 0;
  final releaseOk = releaseSamples >= brakingTechniqueMinimumRampSamples && releaseSeconds > 0;
  return (
    hit: hitOk ? (level - off) / hitSeconds : null,
    hitReason: hitOk ? '' : brakingTechniqueTooQuick,
    release: releaseOk ? (level - off) / releaseSeconds : null,
    releaseReason: releaseOk ? '' : brakingTechniqueTooQuick,
  );
}

/// The braking of one lap into one corner, over [windowStart]..[windowEnd]
/// (recording times: from where braking is looked for to the corner's end).
/// [beyondLap]: the window reaches beyond the lap's own bounds.
BrakingTechniqueLap measureBrakingTechnique(
  TelemetrySession session,
  double windowStart,
  double windowEnd, {
  bool beyondLap = false,
}) {
  final result = BrakingTechniqueLap()..beyondLap = beyondLap;
  if (!windowStart.isFinite || !windowEnd.isFinite || windowEnd <= windowStart) {
    result.unavailableReason = brakingTechniqueNotCovered;
    return result;
  }
  final from = windowStart - brakingTechniqueSearchPadSeconds;
  final to = windowEnd + brakingTechniqueSearchPadSeconds;

  // The speed, for distances and, without a G channel, the deceleration.
  final speed = session.channels[session.aliases['speed'] ?? ''];
  final speedFactor = speed == null || speed.timestamps.length != speed.values.length
      ? null
      : metresPerSecondPerSpeedUnit(speed.unit);

  // The deceleration: a G channel with data, else the speed.
  final gName = session.aliases['longitudinalAcceleration'] ?? '';
  final g = session.channels[gName];
  _Series? series;
  if (g == null || g.timestamps.length != g.values.length) {
    result.gChannelReason = brakingTechniqueGMissing;
  } else if (brakingTechniquePlaceholder(g)) {
    result.gChannelReason = brakingTechniqueGPlaceholder;
  } else {
    final factor = _gPer(g.unit);
    result
      ..source = brakingTechniqueFromG
      ..channel = gName
      ..declaredUnit = g.unit.trim()
      ..unitAssumed = g.unit.trim().isEmpty
      ..rateHz = channelUpdateRateHz(g);
    if (factor == null) {
      result.unavailableReason = brakingTechniqueUnitNotSupported;
      return result;
    }
    // Negative longitudinal G is braking.
    series = _channelSeries(g, from, to, -factor);
  }
  if (series == null) {
    if (speed == null || brakingTechniquePlaceholder(speed)) {
      result.unavailableReason = brakingTechniqueNoDeceleration;
      return result;
    }
    result
      ..source = brakingTechniqueFromSpeed
      ..channel = speed.name
      ..declaredUnit = speed.unit.trim()
      ..unitAssumed = speed.unit.trim().isEmpty
      ..rateHz = channelUpdateRateHz(speed);
    if (speedFactor == null) {
      result.unavailableReason = brakingTechniqueSpeedUnitUnknown;
      return result;
    }
    series = _speedDeceleration(speed, speedFactor, from, to);
  }
  if (!(result.rateHz != null && result.rateHz! >= brakingTechniqueMinimumRateHz)) {
    result.unavailableReason = brakingTechniqueDecelerationTooSlow;
    return result;
  }
  if (lowerBound(series.times, windowStart) >= upperBound(series.times, windowEnd)) {
    result.unavailableReason = brakingTechniqueNotCovered;
    return result;
  }

  final episode = _firstEpisode(
    series,
    windowStart,
    windowEnd,
    brakingTechniqueOnG,
    brakingTechniqueOffG,
    brakingTechniqueMinimumSeconds,
  );
  if (episode == null) {
    result.unavailableReason = brakingTechniqueNoBraking;
    return result;
  }
  if (episode.reason.isNotEmpty) {
    result.unavailableReason = episode.reason;
    return result;
  }
  final onset = episode.onset, end = episode.end;
  result
    ..onsetTime = onset
    ..endTime = end
    ..peakTime = series.times[episode.peak]
    ..peakG = series.values[episode.peak]
    ..zoneSeconds = end - onset;

  // Distances from the recorded speed, on the deceleration's clock.
  final timeline = [
    onset,
    for (var k = episode.first; k <= episode.last; ++k) series.times[k],
    end,
  ];
  double? speedAt(double time) {
    if (speed == null || speedFactor == null) return null;
    final value = telemetryValueAt(speed, time);
    return value == null ? null : value * speedFactor;
  }

  double? metres(double a, double b) {
    var total = 0.0;
    for (var k = 0; k + 1 < timeline.length; ++k) {
      final x = math.max(a, timeline[k]), y = math.min(b, timeline[k + 1]);
      if (y <= x) continue;
      final vx = speedAt(x), vy = speedAt(y);
      if (vx == null || vy == null) return null;
      total += (vx + vy) / 2 * (y - x);
    }
    return total;
  }

  result
    ..zoneMeters = metres(onset, end)
    ..peakAfterOnsetMeters = metres(onset, result.peakTime!);
  result.peakFraction = result.zoneMeters != null && result.zoneMeters! > 0
      ? result.peakAfterOnsetMeters! / result.zoneMeters!
      : (result.peakTime! - onset) / (end - onset);

  final ramps = _ramps(series, episode, brakingTechniqueOffG, brakingTechniqueMinimumPeakG);
  result
    ..hitGPerSecond = ramps.hit
    ..hitReason = ramps.hitReason
    ..releaseGPerSecond = ramps.release
    ..releaseReason = ramps.releaseReason;

  _trail(session, result, timeline, metres);
  _brakeToThrottle(session, result, windowEnd);
  _pedal(session, result);
  return result;
}

void _trail(
  TelemetrySession session,
  BrakingTechniqueLap result,
  List<double> timeline,
  double? Function(double, double) metres,
) {
  final name = session.aliases['lateralAcceleration'] ?? '';
  final lateral = session.channels[name];
  if (lateral == null || lateral.timestamps.length != lateral.values.length) {
    result.trailReason = brakingTechniqueNoLateral;
    return;
  }
  result
    ..lateralChannel = name
    ..lateralRateHz = channelUpdateRateHz(lateral);
  final factor = _gPer(lateral.unit);
  if (brakingTechniquePlaceholder(lateral)) {
    result.trailReason = brakingTechniqueLateralPlaceholder;
    return;
  }
  if (factor == null) {
    result.trailReason = brakingTechniqueUnitNotSupported;
    return;
  }
  if (!(result.lateralRateHz != null && result.lateralRateHz! >= brakingTechniqueMinimumRateHz)) {
    result.trailReason = brakingTechniqueLateralTooSlow;
    return;
  }
  var seconds = 0.0;
  double? distance = 0.0;
  for (var k = 0; k + 1 < timeline.length; ++k) {
    final a = timeline[k], b = timeline[k + 1];
    if (b <= a) continue;
    final value = telemetryValueAt(lateral, (a + b) / 2);
    if (value == null) {
      result.trailReason = brakingTechniqueGap;
      return;
    }
    if ((value * factor).abs() < brakingTechniqueTrailLateralG) continue;
    seconds += b - a;
    final piece = metres(a, b);
    distance = distance == null || piece == null ? null : distance + piece;
  }
  result
    ..trailSeconds = seconds
    ..trailMeters = distance;
}

// From the end of braking to the measured throttle's first sustained pickup
// after the peak (a blip of throttle on a downshift early in the braking is
// not a pickup), searched up to the corner's end.
void _brakeToThrottle(TelemetrySession session, BrakingTechniqueLap result, double windowEnd) {
  final name = session.aliases['throttle'] ?? '';
  final throttle = session.channels[name];
  if (throttle == null || brakingTechniquePlaceholder(throttle)) {
    result.brakeToThrottleReason = brakingTechniqueNoThrottle;
    return;
  }
  result
    ..throttleChannel = name
    ..throttleRateHz = channelUpdateRateHz(throttle);
  final pickup = measuredThrottlePickup(
    session,
    result.peakTime!,
    math.max(windowEnd, result.endTime!),
  );
  final time = pickup.telemetryTime;
  if (time == null) {
    result.brakeToThrottleReason = pickup.unavailableReason.isEmpty
        ? brakingTechniqueNoPickup
        : pickup.unavailableReason;
    return;
  }
  result.brakeToThrottleSeconds = time - result.endTime!;
}

void _pedal(TelemetrySession session, BrakingTechniqueLap result) {
  final quality = brakingSourceQuality(session);
  if (!quality.hasBrake) {
    result.pedalReason = brakingTechniqueNoBrake;
    return;
  }
  final brake = session.channels[quality.brakeName]!;
  result
    ..brakeChannel = quality.brakeName
    ..brakeRateHz = channelUpdateRateHz(brake);
  // A pedal slower than about 10 Hz shows when braking happens, not how the
  // pedal moves.
  if (!(result.brakeRateHz != null && result.brakeRateHz! >= brakingTechniqueMinimumRateHz)) {
    result.pedalReason = brakingTechniqueBrakeTooSlow;
    return;
  }
  if (brakingTechniquePlaceholder(brake) || !quality.brakeUsable) {
    result.pedalReason = quality.brakeScale == PedalScale.unknown
        ? brakingTechniqueBrakeScaleUnknown
        : brakingTechniqueBrakeNotUsed;
    return;
  }
  final unit = brake.unit.trim();
  if (unit.isNotEmpty && unit != '%') {
    result.pedalReason = brakingTechniqueUnitNotSupported;
    return;
  }
  final scale = quality.brakeScale == PedalScale.fraction ? 100.0 : 1.0;
  final series = _channelSeries(
    brake,
    result.onsetTime! - brakingTechniqueSearchPadSeconds,
    result.endTime! + brakingTechniqueSearchPadSeconds,
    scale,
  );
  // The pedal's press around the deceleration's onset.
  final episode = _firstEpisode(
    series,
    result.onsetTime! - 1.0,
    result.endTime!,
    brakingTechniquePedalPressedPercent,
    brakingTechniquePedalPressedPercent / 2,
    brakingTechniqueMinimumSeconds,
  );
  if (episode == null || episode.reason.isNotEmpty) {
    result.pedalReason = episode?.reason ?? brakingTechniqueNoBraking;
    return;
  }
  final ramps = _ramps(series, episode, brakingTechniquePedalPressedPercent / 2, 0);
  result
    ..pedalApplicationPerSecond = ramps.hit
    ..pedalReleasePerSecond = ramps.release
    ..pedalReason = ramps.hit == null ? ramps.hitReason : ramps.releaseReason;
}

/// The window braking into [segment] (an approved corner) is looked for on
/// one lap: from [brakingTechniqueApproachMeters] before its start (never
/// into the previous approved corner) to its end, as recording times. A
/// corner crossing start/finish (end before start) runs past the lap's end;
/// an approach reaching before the gate starts before the lap's start. Both
/// beyond-lap times are read from the lap's own pace ([lapStart] to [lapEnd]
/// over [axisLengthMeters]), only to bound the search. Null when [trace]
/// does not cover the corner.
({double start, double end, bool beyondLap})? brakingTechniqueWindow(
  double axisLengthMeters,
  List<Map<String, Object?>> segments,
  Map<String, Object?> segment,
  List<ProgressSegment> trace,
  double lapStart,
  double lapEnd,
) {
  double number(Object? value) => value is num ? value.toDouble() : double.nan;
  final start = number(segment['startProgressMeters']);
  final end = number(segment['endProgressMeters']);
  final length = axisLengthMeters;
  if (!start.isFinite || !end.isFinite || !(length > 0) || !(lapEnd > lapStart)) return null;
  // The approach, stopped at the end of the previous corner (across the
  // gate too).
  var approach = brakingTechniqueApproachMeters;
  for (final other in segments) {
    if (identical(other, segment) ||
        other['id'] == segment['id'] ||
        other['type'] != trackSegmentTypeName(TrackSegmentType.corner)) {
      continue;
    }
    final otherEnd = number(other['endProgressMeters']);
    if (!otherEnd.isFinite) continue;
    final back = (start - otherEnd) % length;
    if (back < approach) approach = back;
  }
  final pace = (lapEnd - lapStart) / length;
  double? at(double progress) {
    if (progress < 0) return lapStart + progress * pace;
    if (progress > length) return lapEnd + (progress - length) * pace;
    if (progress <= 1e-6) return lapStart;
    if (progress >= length - 1e-6) return lapEnd;
    return timeAtProgress(trace, progress);
  }

  final from = start - approach;
  final to = end < start ? end + length : end;
  final startTime = at(from), endTime = at(to);
  if (startTime == null || endTime == null || !(endTime > startTime)) return null;
  return (start: startTime, end: endTime, beyondLap: from < 0 || to > length);
}

/// One figure's typical value over the laps, or why there is none.
final class BrakingTechniqueTypical {
  const BrakingTechniqueTypical({this.median, this.spread, this.laps = 0, this.reason = ''});

  /// Median and interquartile range.
  final double? median, spread;

  /// Laps with a value.
  final int laps;

  /// Set when [median] is null.
  final String reason;
}

/// How a corner was braked into, lap by lap and typically.
final class BrakingTechnique {
  const BrakingTechnique({
    this.laps = const [],
    this.source = '',
    this.declaredUnit = '',
    this.unitAssumed = false,
    this.rateHz,
    this.gChannelReason = '',
    this.lapsMeasured = 0,
    this.lapsBraking = 0,
    this.otherSourceLaps = 0,
    this.unavailableReason = brakingTechniqueTooFewLaps,
    this.hit = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
    this.peak = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
    this.peakFraction = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
    this.release = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
    this.trailSeconds = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
    this.trailMeters = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
    this.brakeToThrottle = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
    this.pedalApplication = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
    this.pedalRelease = const BrakingTechniqueTypical(reason: brakingTechniqueTooFewLaps),
  });

  /// Every lap's measurement, keyed by its lap reference, in lap order.
  final List<(Object?, BrakingTechniqueLap)> laps;

  /// The deceleration source the typical values come from: the one most
  /// laps were measured from (a tie goes to the G channel); laps measured
  /// otherwise are never pooled with them ([otherSourceLaps]).
  final String source;
  final String declaredUnit;
  final bool unitAssumed;
  final double? rateHz;
  final String gChannelReason;

  /// Laps of [source] that were measured (braking found or found absent),
  /// and how many of them braked.
  final int lapsMeasured, lapsBraking;
  final int otherSourceLaps;

  /// Set when no typical braking zone is known: too few laps, or no
  /// braking on most of them.
  final String unavailableReason;

  final BrakingTechniqueTypical hit, peak, peakFraction, release;
  final BrakingTechniqueTypical trailSeconds, trailMeters, brakeToThrottle;
  final BrakingTechniqueTypical pedalApplication, pedalRelease;

  /// [reference]'s measurement, or null.
  BrakingTechniqueLap? lap(Object? reference) {
    for (final (key, lap) in laps) {
      if (key == reference) return lap;
    }
    return null;
  }

  /// The brake pedal's rate on the laps (the slowest), or null.
  double? get brakeRateHz => _slowest([for (final (_, lap) in laps) lap.brakeRateHz]);

  /// The throttle's rate on the laps (the slowest), or null.
  double? get throttleRateHz => _slowest([for (final (_, lap) in laps) lap.throttleRateHz]);

  /// The lateral G's rate on the laps (the slowest), or null.
  double? get lateralRateHz => _slowest([for (final (_, lap) in laps) lap.lateralRateHz]);
}

double? _slowest(List<double?> rates) {
  double? slowest;
  for (final rate in rates) {
    if (rate != null && (slowest == null || rate < slowest)) slowest = rate;
  }
  return slowest;
}

/// The typical braking of one corner over [laps] (lap reference and
/// measurement, ranked laps only). Values measured from a G channel and from
/// speed, or in different declared units, are never pooled.
BrakingTechnique summarizeBrakingTechnique(List<(Object?, BrakingTechniqueLap)> laps) {
  String key(BrakingTechniqueLap lap) => '${lap.source}|${lap.declaredUnit.toLowerCase()}';
  final groups = <String, List<BrakingTechniqueLap>>{};
  for (final (_, lap) in laps) {
    if (lap.source.isEmpty) continue;
    (groups[key(lap)] ??= []).add(lap);
  }
  if (groups.isEmpty) {
    return BrakingTechnique(
      laps: laps,
      unavailableReason: _commonReason([for (final (_, lap) in laps) lap.unavailableReason], 0),
    );
  }
  final chosen = groups.keys.reduce((a, b) {
    final countA = groups[a]!.length, countB = groups[b]!.length;
    if (countA != countB) return countA > countB ? a : b;
    return a.startsWith(brakingTechniqueFromG) ? a : b;
  });
  final group = groups[chosen]!;
  final first = group.first;
  final other = groups.values.fold(0, (sum, list) => sum + list.length) - group.length;
  final measured = [
    for (final lap in group)
      if (lap.measured || lap.unavailableReason == brakingTechniqueNoBraking) lap,
  ];
  final braking = [
    for (final lap in measured)
      if (lap.measured) lap,
  ];

  // A missing typical value says why: the most common reason of the
  // braking laps without one, when there are enough braking laps; else the
  // corner's own reason.
  BrakingTechniqueTypical typical(
    double? Function(BrakingTechniqueLap) read,
    String Function(BrakingTechniqueLap) why,
  ) {
    final values = [for (final lap in braking) ?read(lap)];
    final summary = summarizeConsistency(values, minimumSamples: brakingTechniqueMinimumLaps);
    if (summary.available) {
      return BrakingTechniqueTypical(
        median: summary.median,
        spread: summary.interquartileRange,
        laps: values.length,
      );
    }
    return BrakingTechniqueTypical(
      laps: values.length,
      reason: braking.length < brakingTechniqueMinimumLaps
          ? brakingTechniqueTooFewLaps
          : _commonReason([
              for (final lap in braking)
                if (read(lap) == null) why(lap),
            ], values.length),
    );
  }

  final String reason;
  if (measured.length < brakingTechniqueMinimumLaps) {
    reason = _commonReason([for (final lap in group) lap.unavailableReason], measured.length);
  } else if (braking.length * 2 < measured.length) {
    reason = brakingTechniqueNoBraking;
  } else {
    reason = braking.length < brakingTechniqueMinimumLaps ? brakingTechniqueTooFewLaps : '';
  }
  return BrakingTechnique(
    laps: laps,
    source: first.source,
    declaredUnit: first.declaredUnit,
    unitAssumed: first.unitAssumed,
    rateHz: _slowest([for (final lap in group) lap.rateHz]),
    gChannelReason: first.gChannelReason,
    lapsMeasured: measured.length,
    lapsBraking: braking.length,
    otherSourceLaps: other,
    unavailableReason: reason,
    hit: typical((lap) => lap.hitGPerSecond, (lap) => lap.hitReason),
    peak: typical((lap) => lap.peakG, (lap) => brakingTechniqueNotCovered),
    peakFraction: typical((lap) => lap.peakFraction, (lap) => brakingTechniqueNotCovered),
    release: typical((lap) => lap.releaseGPerSecond, (lap) => lap.releaseReason),
    trailSeconds: typical((lap) => lap.trailSeconds, (lap) => lap.trailReason),
    trailMeters: typical(
      (lap) => lap.trailMeters,
      (lap) => lap.trailReason.isEmpty ? brakingTechniqueSpeedUnitUnknown : lap.trailReason,
    ),
    brakeToThrottle: typical(
      (lap) => lap.brakeToThrottleSeconds,
      (lap) => lap.brakeToThrottleReason,
    ),
    pedalApplication: typical((lap) => lap.pedalApplicationPerSecond, (lap) => lap.pedalReason),
    pedalRelease: typical((lap) => lap.pedalReleasePerSecond, (lap) => lap.pedalReason),
  );
}

/// The day's braking over its corners: the median of each corner's typical
/// value, over the corners whose deceleration comes from one source in one
/// unit (the source most corners used).
final class BrakingTechniqueDay {
  const BrakingTechniqueDay({
    this.corners = 0,
    this.cornersBraked = 0,
    this.source = '',
    this.unitAssumed = false,
    this.hit,
    this.release,
    this.trailSeconds,
    this.brakeToThrottle,
    this.hitCorners = 0,
    this.releaseCorners = 0,
    this.trailCorners = 0,
    this.brakeToThrottleCorners = 0,
  });

  /// Corners considered, and those with a typical braking zone.
  final int corners, cornersBraked;
  final String source;
  final bool unitAssumed;
  final double? hit, release, trailSeconds, brakeToThrottle;
  final int hitCorners, releaseCorners, trailCorners, brakeToThrottleCorners;

  bool get available => hit != null || release != null || trailSeconds != null;
}

/// [corners]' braking techniques summed up for the day.
BrakingTechniqueDay summarizeBrakingTechniqueDay(List<BrakingTechnique> corners) {
  final braked = [
    for (final corner in corners)
      if (corner.unavailableReason.isEmpty) corner,
  ];
  if (braked.isEmpty) return BrakingTechniqueDay(corners: corners.length);
  final counts = <String, int>{};
  String key(BrakingTechnique corner) => '${corner.source}|${corner.declaredUnit.toLowerCase()}';
  for (final corner in braked) {
    counts[key(corner)] = (counts[key(corner)] ?? 0) + 1;
  }
  final chosen = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  final group = [
    for (final corner in braked)
      if (key(corner) == chosen) corner,
  ];
  (double?, int) median(BrakingTechniqueTypical Function(BrakingTechnique) read) {
    final values = [for (final corner in group) ?read(corner).median];
    final summary = summarizeConsistency(values, minimumSamples: 1);
    return (summary.median, values.length);
  }

  final hit = median((corner) => corner.hit);
  final release = median((corner) => corner.release);
  final trail = median((corner) => corner.trailSeconds);
  final throttle = median((corner) => corner.brakeToThrottle);
  return BrakingTechniqueDay(
    corners: corners.length,
    cornersBraked: group.length,
    source: group.first.source,
    unitAssumed: group.first.unitAssumed,
    hit: hit.$1,
    hitCorners: hit.$2,
    release: release.$1,
    releaseCorners: release.$2,
    trailSeconds: trail.$1,
    trailCorners: trail.$2,
    brakeToThrottle: throttle.$1,
    brakeToThrottleCorners: throttle.$2,
  );
}

// Why a value is missing: the most common reason of the laps without one,
// when those laps with the [usable] ones would have been enough; otherwise
// the day has too few laps.
String _commonReason(List<String> reasons, int usable) {
  final counts = <String, int>{};
  for (final reason in reasons) {
    if (reason.isNotEmpty) counts[reason] = (counts[reason] ?? 0) + 1;
  }
  if (counts.isEmpty) return brakingTechniqueTooFewLaps;
  final (reason, count) = counts.entries
      .map((entry) => (entry.key, entry.value))
      .reduce((a, b) => b.$2 > a.$2 ? b : a);
  return usable + count >= brakingTechniqueMinimumLaps ? reason : brakingTechniqueTooFewLaps;
}
