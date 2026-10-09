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

import '../channel_units.dart';
import '../speed_units.dart';
import '../telemetry_session.dart';
import 'braking_source.dart';
import 'consistency.dart';
import 'exit_metrics.dart' show exitScaleInferred, exitUnitUndeclared, measuredThrottlePickup;
import 'pedal_scale.dart';
import 'track_progress.dart';

const String brakingTechniqueAlgorithm = 'braking-technique-v2';

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

/// The hit runs from the last moment below [brakingTechniqueRampFloorShare]
/// of the peak (at least [brakingTechniqueOffG]) to this share of the peak;
/// the release from the last moment at this share back to that floor. A
/// coast or a light lift before the braking is not part of the hit.
const double brakingTechniquePeakShare = 0.85;
const double brakingTechniqueRampFloorShare = 0.25;

/// A dip before the rise (or after the fall) ends the ramp's search for its
/// start when it is at least this deep: [brakingTechniqueRampDipShare] of the
/// peak, at least [brakingTechniqueMinimumRampDipG] (above G noise).
const double brakingTechniqueRampDipShare = 0.10;
const double brakingTechniqueMinimumRampDipG = 0.03;

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

/// A throttle pickup later than this after braking ends is not this
/// corner's: a coast through a further corner of the segment.
const double brakingTechniqueMaximumBrakeToThrottleSeconds = 4.0;

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
const String brakingTechniqueBrakingAgain = 'brakingAgainBeforeThrottle';
const String brakingTechniqueCoasting = 'noThrottleSoonAfterBraking';
const String brakingTechniqueBrakeResampled = 'brakeChannelResampled';

/// Whether [name] is an OBD channel as RaceChrono's VBO export writes it
/// (`brake_pos-obd`, `accelerator_pos-obd`): resampled to the rows from an
/// update rate the file does not tell, so never read for a ramp.
bool brakingTechniqueResampledObd(String name) => name.toLowerCase().endsWith('-obd');

/// Why the G channel was not used and the deceleration comes from speed.
const String brakingTechniqueGMissing = 'noGChannel';
const String brakingTechniqueGPlaceholder = 'gChannelEmpty';

/// How often [channel]'s values really change, in Hz, or null when that
/// cannot be told (fewer than two samples). The slowest of: its median
/// sample interval; the median time between value changes (a held value);
/// when its moving values mostly lie on straight lines
/// ([brakingTechniqueInterpolatedShare]), the time between the corners of
/// those lines; and the longest period whose lines, bending only at updates
/// that may fall anywhere between the samples, fit the moving values (a
/// slower signal interpolated at the row rate, as RaceChrono's VBO export
/// writes OBD channels). Updates every 1.4 to 12 sample intervals are found;
/// a rate between about 7 Hz and the row rate may read as the row rate.
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
  final moveThreshold = math.max(4 * tolerance, brakingTechniqueMovingShare * range);
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
    if ((c - a).abs() < moveThreshold) {
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
  // Lines drawn between updates that do not fall on the samples, whatever
  // their phase: looked for only while the channel still seems fast enough
  // for a ramp (the fit is the costly part).
  if (1.0 / interval >= brakingTechniqueMinimumRateHz) {
    final knots = _knotPeriod(times, values, base, joined, moveThreshold, tolerance, range);
    if (knots != null) interval = math.max(interval, knots);
  }
  return 1.0 / interval;
}

/// The longest update period, in seconds, that [values]' moving stretches
/// look drawn with: straight lines between updates every period, wherever
/// those updates fall between the samples. For each candidate period
/// (1.4 to 12 sample intervals) and each of [_knotPhases] phases, the
/// stretches are fitted by least squares with lines that bend only at the
/// updates. A slower signal drawn with lines fits at its own phase and
/// misses by its corners half a period off; a signal moving at the sample
/// rate fits about equally badly at every phase. Null when none fits so.
double? _knotPeriod(
  Float64List times,
  Float32List values,
  double base,
  bool Function(int) joined,
  double moveThreshold,
  double tolerance,
  double range,
) {
  // Moving stretches, each with the samples either side of it: a step
  // moves when it is at least half of [moveThreshold] at 10 Hz rows, in
  // proportion at other row rates.
  final step = math.max(2 * tolerance, moveThreshold / 2 * math.min(1.0, base / 0.1));
  final stretches = <(int, int)>[];
  var total = 0;
  int? begin;
  void close(int end) {
    if (begin != null && end - begin! + 1 >= _knotMinimumStretch && total < _knotMaximumSamples) {
      stretches.add((begin!, end));
      total += end - begin! + 1;
    }
    begin = null;
  }

  for (var i = 1; i + 1 < values.length; ++i) {
    final moving =
        joined(i) &&
        joined(i + 1) &&
        math.max((values[i + 1] - values[i]).abs(), (values[i] - values[i - 1]).abs()) >= step;
    if (moving) {
      begin ??= i - 1;
    } else if (begin != null) {
      close(i);
    }
  }
  if (begin != null) close(values.length - 1);
  if (total < _knotMinimumSamples) return null;

  // What rounding to the written resolution leaves over, as an RMS.
  final floor = math.max(tolerance / 1.5 * 0.3, 1e-6 * range);
  // The noise on the moving stretches, from the median fourth difference
  // (white noise of deviation σ gives differences of deviation σ√70); a
  // smooth signal has next to none.
  final fourth = <double>[];
  for (final (a, b) in stretches) {
    for (var i = a; i + 4 <= b; ++i) {
      fourth.add(
        (values[i] - 4 * values[i + 1] + 6 * values[i + 2] - 4 * values[i + 3] + values[i + 4])
            .abs(),
      );
    }
  }
  fourth.sort();
  final noise = fourth.isEmpty ? 0.0 : fourth[fourth.length ~/ 2] / (0.6745 * math.sqrt(70));
  double? found;
  var tightest = double.infinity;
  for (final multiple in _knotPeriods) {
    final period = base * multiple;
    var best = double.infinity, worst = 0.0, bestPhase = 0.0;
    var counted = 0;
    // The RMS left over per degree of freedom at [phase], or null.
    double? leftOver(double phase) {
      var squares = 0.0;
      var samples = 0, free = 0;
      for (final (a, b) in stretches) {
        if (times[b] - times[a] < 2 * period) continue;
        final fit = _fitKnots(times, values, a, b, period, phase);
        squares += fit.squares;
        samples += b - a + 1;
        free += b - a + 1 - fit.knots.length;
      }
      if (samples == 0 || free <= 0) return null;
      counted = samples;
      return math.sqrt(squares / free);
    }

    for (var j = 0; j < _knotPhases; ++j) {
      final phase = period * j / _knotPhases;
      final rms = leftOver(phase);
      if (rms == null) break;
      if (rms < best) {
        best = rms;
        bestPhase = phase;
      }
      worst = math.max(worst, rms);
    }
    // The best phase, refined between its neighbours.
    var spacing = period / _knotPhases;
    for (var level = 0; level < 4 && best.isFinite; ++level) {
      spacing /= 4;
      final centre = bestPhase;
      for (final shift in [-3, -2, -1, 1, 2, 3]) {
        final phase = centre + shift * spacing;
        final rms = leftOver(phase);
        if (rms != null && rms < best) {
          best = rms;
          bestPhase = phase;
        }
      }
    }
    if (counted < _knotMinimumSamples || !best.isFinite) continue;
    // A slower signal's own period fits as well as any shorter one; a
    // smooth signal fits worse the fewer the knots.
    // Lines between updates fit to within the written resolution, or, on
    // a noisy signal, to within its noise and as well as any shorter
    // period. A whole number of samples per period puts every knot at the
    // same place between the samples, which can flatter a smooth signal, so
    // only the first way counts then.
    final whole = (multiple - multiple.roundToDouble()).abs() < 0.01;
    final fits =
        (best <= 3 * floor && best <= noise) ||
        (!whole && best <= 1.5 * tightest && best <= _knotNoiseShare * noise);
    tightest = math.min(tightest, best);
    if (!fits) continue;
    if (worst < _knotPhaseContrast * best || worst < 3 * floor) continue;
    // Lines between updates bend at most updates: count the knots, at the
    // best phase, whose bend stands out from what is left over.
    var knots = 0, bent = 0;
    for (final (a, b) in stretches) {
      if (times[b] - times[a] < 2 * period) continue;
      final fit = _fitKnots(times, values, a, b, period, bestPhase);
      final y = fit.knots;
      final first = ((times[a] - bestPhase) / period).floor();
      for (var k = 1; k + 1 < y.length; ++k) {
        // Knots at least half a period inside the stretch.
        final at = bestPhase + (first + k) * period;
        if (at < times[a] + period / 2 || at > times[b] - period / 2) continue;
        ++knots;
        final bend = (y[k + 1] - 2 * y[k] + y[k - 1]).abs();
        if (bend >= math.max(worst, 3 * math.max(best, floor))) ++bent;
      }
    }
    if (knots > 0 && bent >= _knotBentShare * knots) found = period;
  }
  return found;
}

const int _knotPhases = 10;
const int _knotMinimumStretch = 8;
const int _knotMinimumSamples = 60;
const int _knotMaximumSamples = 1500;
const double _knotPhaseContrast = 4.0;
const double _knotBentShare = 0.5;
const double _knotNoiseShare = 1.0;
final List<double> _knotPeriods = [
  for (var m = 14; m <= 40; ++m) m / 10,
  for (var m = 21; m <= 60; ++m) m / 5,
];

// Least squares of samples [a]..[b] by lines bending at knots every
// [period] from [phase]: their values at the knots, and the sum of squares
// left over.
({List<double> knots, double squares}) _fitKnots(
  Float64List times,
  Float32List values,
  int a,
  int b,
  double period,
  double phase,
) {
  final first = ((times[a] - phase) / period).floor();
  final count = ((times[b] - phase) / period).floor() - first + 2;
  final diagonal = List<double>.filled(count, 1e-9);
  final upper = List<double>.filled(count, 0.0);
  final right = List<double>.filled(count, 0.0);
  final offset = values[a].toDouble();
  for (var i = a; i <= b; ++i) {
    final x = (times[i] - phase) / period - first;
    final k = math.min(x.floor(), count - 2);
    final w = x - k, v = values[i] - offset;
    diagonal[k] += (1 - w) * (1 - w);
    diagonal[k + 1] += w * w;
    upper[k] += (1 - w) * w;
    right[k] += (1 - w) * v;
    right[k + 1] += w * v;
  }
  // Thomas algorithm for the symmetric tridiagonal system.
  final c = List<double>.filled(count, 0.0), d = List<double>.filled(count, 0.0);
  c[0] = upper[0] / diagonal[0];
  d[0] = right[0] / diagonal[0];
  for (var k = 1; k < count; ++k) {
    final m = diagonal[k] - upper[k - 1] * c[k - 1];
    c[k] = upper[k] / m;
    d[k] = (right[k] - upper[k - 1] * d[k - 1]) / m;
  }
  final y = List<double>.filled(count, 0.0);
  y[count - 1] = d[count - 1];
  for (var k = count - 2; k >= 0; --k) {
    y[k] = d[k] - c[k] * y[k + 1];
  }
  var squares = 0.0;
  for (var i = a; i <= b; ++i) {
    final x = (times[i] - phase) / period - first;
    final k = math.min(x.floor(), count - 2);
    final w = x - k;
    final r = values[i] - offset - ((1 - w) * y[k] + w * y[k + 1]);
    squares += r * r;
  }
  return (knots: y, squares: squares);
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
bool brakingTechniquePlaceholder(TelemetryChannel channel) =>
    _placeholders[channel] ??= _placeholder(channel);

final _placeholders = Expando<bool>('placeholder channel');

bool _placeholder(TelemetryChannel channel) {
  double? first;
  for (final value in channel.values) {
    if (!value.isFinite) continue;
    first ??= value;
    if (value != first) return false;
  }
  return true;
}

/// One lap's braking into one corner.
final class BrakingTechniqueLap {
  /// Set when no braking zone was measured.
  String unavailableReason = '';

  /// [brakingTechniqueFromG] or [brakingTechniqueFromSpeed].
  String source = '';
  String channel = '';

  /// As the recording declares it; empty when undeclared ([unitAssumed]).
  String declaredUnit = '';

  /// No unit declared: a G channel read as g, a speed read as km/h (or as
  /// the unit the user assumes for unlabelled speeds, [assumedUnit]).
  bool unitAssumed = false;

  /// The unit an undeclared speed was read in ("km/h" or "mph"), when
  /// [unitAssumed] and the deceleration comes from speed; else empty.
  String assumedUnit = '';

  /// The speed (which gives the metres, and the deceleration without a G
  /// channel) declares no unit: it was read in [speedAssumedUnit].
  bool speedUnitAssumed = false;
  String speedAssumedUnit = '';

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

  /// How far through the braking zone the peak falls, 0 to 1, by time
  /// (always: a distance needs a speed some laps may not have).
  double? peakFraction;

  /// G per second up to [brakingTechniquePeakShare] of the peak (see
  /// [brakingTechniqueRampFloorShare]). [hitAtLeast]: from speed, as fast as
  /// its smoothed slope can show, so the real hit may be quicker.
  double? hitGPerSecond;
  bool hitAtLeast = false;
  String hitReason = '';

  /// G per second from the last moment at [brakingTechniquePeakShare] of the
  /// peak back to the ramp floor; [releaseAtLeast] as [hitAtLeast].
  double? releaseGPerSecond;
  bool releaseAtLeast = false;
  String releaseReason = '';

  /// Braking while the lateral G is at least
  /// [brakingTechniqueTrailLateralG] (inferred: no steering channel).
  double? trailSeconds, trailMeters;
  String trailReason = '';
  String lateralChannel = '';
  double? lateralRateHz;

  /// The lateral G declares no unit and is read as g.
  bool lateralUnitAssumed = false;

  /// From the end of braking to the measured throttle pickup; negative when
  /// the throttle comes before the deceleration falls below
  /// [brakingTechniqueOffG].
  double? brakeToThrottleSeconds;
  String brakeToThrottleReason = '';
  String throttleChannel = '';
  double? throttleRateHz;

  /// The throttle declares no unit (read as %), or its 0–1 scale was
  /// inferred and read as 0–100 %.
  bool throttleUnitAssumed = false, throttleScaleInferred = false;

  /// The throttle is a resampled OBD column or slower than about 10 Hz: the
  /// pickup is placed only to its update interval.
  bool get throttleCoarse =>
      brakingTechniqueResampledObd(throttleChannel) ||
      !(throttleRateHz != null && throttleRateHz! >= brakingTechniqueMinimumRateHz);

  /// The brake pedal: its update rate and, only from
  /// [brakingTechniqueMinimumRateHz], how fast it is pressed and let off,
  /// in % per second.
  String brakeChannel = '';
  double? brakeRateHz;
  double? pedalApplicationPerSecond, pedalReleasePerSecond;
  String pedalReason = '';

  /// The brake declares no unit (read as %), or its 0–1 scale was inferred.
  bool brakeUnitAssumed = false, brakeScaleInferred = false;

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

typedef _Ramps = ({
  double? hit,
  bool hitAtLeast,
  String hitReason,
  double? release,
  bool releaseAtLeast,
  String releaseReason,
});

// How fast [episode] rises to [brakingTechniquePeakShare] of its peak from
// the last moment below its floor ([brakingTechniqueRampFloorShare] of the
// peak, at least [off]), and falls from there back to the floor, in units
// per second. A rate of at least [fastest] is as fast as the series can
// show (from speed, its smoothed slope), so it is marked "at least".
_Ramps _ramps(_Series s, _Episode episode, double off, double minimumPeak, {double? fastest}) {
  final peak = s.values[episode.peak];
  if (peak < minimumPeak) {
    return (
      hit: null,
      hitAtLeast: false,
      hitReason: brakingTechniqueTooLight,
      release: null,
      releaseAtLeast: false,
      releaseReason: brakingTechniqueTooLight,
    );
  }
  final level = brakingTechniquePeakShare * peak;
  final floor = math.max(off, brakingTechniqueRampFloorShare * peak);
  var up = episode.first;
  while (s.values[up] < level) {
    ++up;
  }
  final upTime = _cross(s, up - 1, up, level);
  // The hit starts at the last moment below the floor before the rise, or
  // at the last dip of at least [dip] before it when the signal stays above
  // the floor there (a lift between two brakings): walking back, the lowest
  // sample so far is the start once the signal climbs [dip] above it.
  final dip = math.max(brakingTechniqueMinimumRampDipG, brakingTechniqueRampDipShare * peak);
  var low = up - 1, lowest = up - 1;
  while (low > 0 && s.values[low] >= floor) {
    if (s.values[low] < s.values[lowest]) {
      lowest = low;
    } else if (s.values[low] > s.values[lowest] + dip) {
      break;
    }
    --low;
  }
  final double lowTime, lowValue;
  final int lowIndex;
  if (s.values[low] < floor) {
    lowIndex = low;
    lowTime = _cross(s, low, low + 1, floor);
    lowValue = floor;
  } else {
    lowIndex = lowest;
    lowTime = s.times[lowest];
    lowValue = s.values[lowest];
  }
  final hitSamples = up - lowIndex + 1;
  var down = episode.last;
  while (s.values[down] < level) {
    --down;
  }
  final downTime = _cross(s, down, down + 1, level);
  var high = down + 1, lastLow = down + 1;
  while (high < s.values.length - 1 && s.values[high] >= floor) {
    if (s.values[high] < s.values[lastLow]) {
      lastLow = high;
    } else if (s.values[high] > s.values[lastLow] + dip) {
      break;
    }
    ++high;
  }
  final double highTime, highValue;
  final int highIndex;
  if (s.values[high] < floor) {
    highIndex = high;
    highTime = _cross(s, high - 1, high, floor);
    highValue = floor;
  } else {
    highIndex = lastLow;
    highTime = s.times[lastLow];
    highValue = s.values[lastLow];
  }
  final releaseSamples = highIndex - down + 1;
  final hitSeconds = upTime - lowTime, releaseSeconds = highTime - downTime;
  final hitOk = hitSamples >= brakingTechniqueMinimumRampSamples && hitSeconds > 0;
  final releaseOk = releaseSamples >= brakingTechniqueMinimumRampSamples && releaseSeconds > 0;
  final hit = hitOk ? (level - lowValue) / hitSeconds : null;
  final release = releaseOk ? (level - highValue) / releaseSeconds : null;
  final hitLimit = fastest == null ? null : (level - lowValue) / fastest;
  final releaseLimit = fastest == null ? null : (level - highValue) / fastest;
  return (
    hit: hit,
    hitAtLeast: hit != null && hitLimit != null && hit >= hitLimit,
    hitReason: hitOk ? '' : brakingTechniqueTooQuick,
    release: release,
    releaseAtLeast: release != null && releaseLimit != null && release >= releaseLimit,
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
  // One unit for the label and the scale: what the file declares, else what
  // the analysed session carries (an assumed unit), else km/h.
  final speedDeclared = speed == null ? '' : fileDeclaredSpeedUnit(session, speed.name);
  final speedUnit = speedDeclared.isNotEmpty
      ? speedDeclared
      : speed == null
      ? ''
      : speed.unit.trim();
  final speedFactor = speed == null || speed.timestamps.length != speed.values.length
      ? null
      : metresPerSecondPerSpeedUnit(speedUnit);
  // Metres come from the speed whatever the deceleration comes from: an
  // undeclared speed unit is assumed there too, and says so.
  if (speedFactor != null && speedDeclared.isEmpty) {
    result
      ..speedUnitAssumed = true
      ..speedAssumedUnit = speedUnit.isEmpty ? 'km/h' : speedUnit;
  }

  // The deceleration: a G channel with data, else the speed.
  final gName = session.aliases['longitudinalAcceleration'] ?? '';
  final g = session.channels[gName];
  _Series? series;
  if (g == null || g.timestamps.length != g.values.length) {
    result.gChannelReason = brakingTechniqueGMissing;
  } else if (brakingTechniquePlaceholder(g)) {
    result.gChannelReason = brakingTechniqueGPlaceholder;
  } else {
    final unit = declaredChannelUnit(session, gName).trim();
    final factor = accelerationGPerUnit(unit);
    result
      ..source = brakingTechniqueFromG
      ..channel = gName
      ..declaredUnit = unit
      ..unitAssumed = unit.isEmpty
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
      ..declaredUnit = speedDeclared
      ..unitAssumed = speedDeclared.isEmpty
      ..assumedUnit = (speedDeclared.isEmpty ? (speedUnit.isEmpty ? 'km/h' : speedUnit) : '')
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
  result.peakFraction = (result.peakTime! - onset) / (end - onset);

  final ramps = _ramps(
    series,
    episode,
    brakingTechniqueOffG,
    brakingTechniqueMinimumPeakG,
    // The speed's slope spreads a step over its window.
    fastest: result.source == brakingTechniqueFromSpeed
        ? 2 * brakingTechniqueSpeedSlopeHalfWindowSeconds
        : null,
  );
  result
    ..hitGPerSecond = ramps.hit
    ..hitAtLeast = ramps.hitAtLeast
    ..hitReason = ramps.hitReason
    ..releaseGPerSecond = ramps.release
    ..releaseAtLeast = ramps.releaseAtLeast
    ..releaseReason = ramps.releaseReason;

  _trail(session, result, timeline, metres);
  // The throttle is looked for until braking starts again (a segment
  // holding two corners), or the corner's end.
  double? again;
  for (var k = episode.last + 1; k < series.times.length; ++k) {
    if (series.values[k] >= brakingTechniqueOnG && series.values[k - 1] < brakingTechniqueOnG) {
      again = _cross(series, k - 1, k, brakingTechniqueOnG);
      break;
    }
  }
  final pressed = _nextPress(session, end, windowEnd + brakingTechniqueSearchPadSeconds);
  if (pressed != null && (again == null || pressed < again)) again = pressed;
  _brakeToThrottle(session, result, windowEnd, again);
  _pedal(session, result);
  return result;
}

// The next time the brake pedal is pressed again after [after]: let off
// below half of [brakingTechniquePedalPressedPercent], then pressed past it.
// A pedal of any rate marks on and off; null without a usable pedal.
double? _nextPress(TelemetrySession session, double after, double until) {
  final quality = brakingSourceQuality(session);
  if (!quality.hasBrake || !quality.brakeUsable) return null;
  final brake = session.channels[quality.brakeName]!;
  if (brakingTechniquePlaceholder(brake)) return null;
  final scale = quality.brakeScale == PedalScale.fraction ? 100.0 : 1.0;
  final times = brake.timestamps, values = brake.values;
  var released = false;
  for (var i = lowerBound(times, after); i < times.length && times[i] <= until; ++i) {
    final value = values[i] * scale;
    if (!value.isFinite) continue;
    if (value < brakingTechniquePedalPressedPercent / 2) {
      released = true;
    } else if (released && value >= brakingTechniquePedalPressedPercent) {
      return times[i];
    }
  }
  return null;
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
  final unit = declaredChannelUnit(session, name).trim();
  result
    ..lateralChannel = name
    ..lateralRateHz = channelUpdateRateHz(lateral)
    ..lateralUnitAssumed = unit.isEmpty;
  final factor = accelerationGPerUnit(unit);
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
// not a pickup), searched up to the corner's end, and never past [again],
// where braking starts again.
void _brakeToThrottle(
  TelemetrySession session,
  BrakingTechniqueLap result,
  double windowEnd,
  double? again,
) {
  final name = session.aliases['throttle'] ?? '';
  final throttle = session.channels[name];
  if (throttle == null || brakingTechniquePlaceholder(throttle)) {
    result.brakeToThrottleReason = brakingTechniqueNoThrottle;
    return;
  }
  result
    ..throttleChannel = name
    ..throttleRateHz = channelUpdateRateHz(throttle);
  final searchEnd = math.max(windowEnd, result.endTime!);
  final pickup = measuredThrottlePickup(
    session,
    result.peakTime!,
    again == null ? searchEnd : math.min(searchEnd, again),
  );
  result
    ..throttleUnitAssumed = pickup.limitations.contains(exitUnitUndeclared)
    ..throttleScaleInferred = pickup.limitations.contains(exitScaleInferred);
  final time = pickup.telemetryTime;
  if (time == null) {
    result.brakeToThrottleReason = again != null && again < searchEnd
        ? brakingTechniqueBrakingAgain
        : pickup.unavailableReason.isEmpty
        ? brakingTechniqueNoPickup
        : pickup.unavailableReason;
    return;
  }
  if (time - result.endTime! > brakingTechniqueMaximumBrakeToThrottleSeconds) {
    result.brakeToThrottleReason = brakingTechniqueCoasting;
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
  // pedal moves. An OBD column of a VBO is resampled to the rows from an
  // update rate the file does not tell: never read for a ramp.
  if (!(result.brakeRateHz != null && result.brakeRateHz! >= brakingTechniqueMinimumRateHz)) {
    result.pedalReason = brakingTechniqueBrakeTooSlow;
    return;
  }
  if (brakingTechniqueResampledObd(quality.brakeName)) {
    result.pedalReason = brakingTechniqueBrakeResampled;
    return;
  }
  if (brakingTechniquePlaceholder(brake) || !quality.brakeUsable) {
    result.pedalReason = quality.brakeScale == PedalScale.unknown
        ? brakingTechniqueBrakeScaleUnknown
        : brakingTechniqueBrakeNotUsed;
    return;
  }
  final unit = declaredChannelUnit(session, quality.brakeName).trim();
  if (unit.isNotEmpty && unit != '%') {
    result.pedalReason = brakingTechniqueUnitNotSupported;
    return;
  }
  result
    ..brakeUnitAssumed = unit.isEmpty
    ..brakeScaleInferred = quality.brakeScale == PedalScale.fraction;
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
  const BrakingTechniqueTypical({
    this.median,
    this.spread,
    this.laps = 0,
    this.reason = '',
    this.atLeast = false,
    this.brakingLaps = 0,
    this.droppedReason = '',
  });

  /// The laps that braked, which [laps] of them have a value for.
  final int brakingLaps;

  /// The most common reason of the braking laps without a value.
  final String droppedReason;

  /// The typical rests on fewer than three quarters of the braking laps: it
  /// is shown with how many ([brakingLaps]) and why the others have none.
  bool get partial => median != null && laps * 4 < brakingLaps * 3;

  /// The typical rests on fewer than half of the braking laps: the laps
  /// that kept a value may not be the corner's usual ones, so the day's
  /// summary leaves the corner out.
  bool get minority => median != null && laps * 2 < brakingLaps;

  /// Some lap's value is only a lower bound (from speed, as fast as its
  /// smoothed slope shows), so the median is one too, and so is the
  /// interquartile range [spread].
  final bool atLeast;

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

  bool _any(bool Function(BrakingTechniqueLap) test) => laps.any((entry) => test(entry.$2));

  /// Some lap's metres come from a speed with no declared unit, read in
  /// [speedAssumedUnit] ("km/h" or "mph").
  bool get speedUnitAssumed => _any((lap) => lap.speedUnitAssumed);
  String get speedAssumedUnit {
    for (final (_, lap) in laps) {
      if (lap.speedUnitAssumed) return lap.speedAssumedUnit;
    }
    return '';
  }

  /// The unit an undeclared speed was read in ("km/h" or "mph") when
  /// [source] is speed and [unitAssumed]; else empty.
  String get assumedUnit {
    if (source != brakingTechniqueFromSpeed || !unitAssumed) return '';
    for (final (_, lap) in laps) {
      if (lap.source == source && lap.assumedUnit.isNotEmpty) return lap.assumedUnit;
    }
    return 'km/h';
  }

  /// Some lap read an undeclared unit as assumed: lateral G as g, the
  /// throttle or brake as %, or a 0–1 pedal scale as 0–100 %.
  bool get lateralUnitAssumed => _any((lap) => lap.lateralUnitAssumed);
  bool get throttleUnitAssumed => _any((lap) => lap.throttleUnitAssumed);
  bool get throttleScaleInferred => _any((lap) => lap.throttleScaleInferred);
  bool get brakeUnitAssumed => _any((lap) => lap.brakeUnitAssumed);
  bool get brakeScaleInferred => _any((lap) => lap.brakeScaleInferred);

  /// Some lap's throttle places its pickup only to its update interval.
  bool get throttleCoarse => _any((lap) => lap.throttleChannel.isNotEmpty && lap.throttleCoarse);

  /// Whether the brake is a resampled OBD column.
  bool get brakeResampled => _any((lap) => brakingTechniqueResampledObd(lap.brakeChannel));
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
    String Function(BrakingTechniqueLap) why, {
    bool Function(BrakingTechniqueLap)? atLeast,
  }) {
    final values = [for (final lap in braking) ?read(lap)];
    final summary = summarizeConsistency(values, minimumSamples: brakingTechniqueMinimumLaps);
    if (summary.available) {
      return BrakingTechniqueTypical(
        median: summary.median,
        spread: summary.interquartileRange,
        laps: values.length,
        atLeast: atLeast != null && braking.any((lap) => read(lap) != null && atLeast(lap)),
        brakingLaps: braking.length,
        droppedReason: values.length == braking.length
            ? ''
            : _mostCommon([
                for (final lap in braking)
                  if (read(lap) == null) why(lap),
              ]),
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
    hit: typical(
      (lap) => lap.hitGPerSecond,
      (lap) => lap.hitReason,
      atLeast: (lap) => lap.hitAtLeast,
    ),
    peak: typical((lap) => lap.peakG, (lap) => brakingTechniqueNotCovered),
    peakFraction: typical((lap) => lap.peakFraction, (lap) => brakingTechniqueNotCovered),
    release: typical(
      (lap) => lap.releaseGPerSecond,
      (lap) => lap.releaseReason,
      atLeast: (lap) => lap.releaseAtLeast,
    ),
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
    this.assumedUnit = '',
    this.hit,
    this.release,
    this.trailSeconds,
    this.brakeToThrottle,
    this.hitCorners = 0,
    this.releaseCorners = 0,
    this.trailCorners = 0,
    this.brakeToThrottleCorners = 0,
    this.otherSourceCorners = 0,
    this.minorityCorners = 0,
    this.hitAtLeast = false,
    this.releaseAtLeast = false,
  });

  /// Some corner's typical value is only a lower bound.
  final bool hitAtLeast, releaseAtLeast;

  /// Corners with a typical braking zone measured another way (G or speed,
  /// or another unit), left out.
  final int otherSourceCorners;

  /// Corners left out of some figure because it rested on under half of
  /// their braking laps.
  final int minorityCorners;

  /// Corners considered, and those with a typical braking zone.
  final int corners, cornersBraked;
  final String source;
  final bool unitAssumed;

  /// The unit an undeclared speed was read in, when [unitAssumed] and the
  /// source is speed.
  final String assumedUnit;
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
  // A corner whose figure rests on under half of its braking laps is left
  // out of that figure ([BrakingTechniqueDay.minorityCorners] counts them).
  final minority = <BrakingTechnique>{};
  (double?, int) median(BrakingTechniqueTypical Function(BrakingTechnique) read) {
    final values = <double>[];
    for (final corner in group) {
      final typical = read(corner);
      if (typical.median == null) continue;
      if (typical.minority) {
        minority.add(corner);
      } else {
        values.add(typical.median!);
      }
    }
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
    unitAssumed: group.any((corner) => corner.unitAssumed),
    assumedUnit: group
        .map((corner) => corner.assumedUnit)
        .firstWhere((u) => u.isNotEmpty, orElse: () => ''),
    hit: hit.$1,
    hitCorners: hit.$2,
    release: release.$1,
    releaseCorners: release.$2,
    trailSeconds: trail.$1,
    trailCorners: trail.$2,
    brakeToThrottle: throttle.$1,
    brakeToThrottleCorners: throttle.$2,
    otherSourceCorners: braked.length - group.length,
    minorityCorners: minority.length,
    hitAtLeast: group.any(
      (corner) => corner.hit.median != null && !corner.hit.minority && corner.hit.atLeast,
    ),
    releaseAtLeast: group.any(
      (corner) =>
          corner.release.median != null && !corner.release.minority && corner.release.atLeast,
    ),
  );
}

// The most common non-empty reason, or empty.
String _mostCommon(List<String> reasons) {
  final counts = <String, int>{};
  for (final reason in reasons) {
    if (reason.isNotEmpty) counts[reason] = (counts[reason] ?? 0) + 1;
  }
  if (counts.isEmpty) return '';
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
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
