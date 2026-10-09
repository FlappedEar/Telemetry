// The scale of a pedal channel that declares no unit (FET-205): 0..100 %
// or a 0..1 fraction. A 0..1 pedal read as % never reaches its thresholds,
// so it would show no braking or throttle at all; one read as a fraction by
// mistake would turn sensor noise into pedal use. The fraction is taken
// only when the longitudinal G shows the pedal working at that scale;
// otherwise the scale is reported unknown, never guessed. Overlays reads
// such a pedal in % (departure: KAN-228).
import '../channel_units.dart';
import '../telemetry_session.dart';

/// How a pedal channel's values are read.
enum PedalScale {
  /// 0..100 (declared %, or undeclared with values beyond 0..1).
  percent,

  /// 0..1, inferred from the longitudinal G (undeclared).
  fraction,

  /// Undeclared, within 0..1, and nothing shows which scale it is.
  unknown,
}

/// Values up to this (with no unit declared) could be either scale.
const double pedalScaleFractionMaximum = 1.5;

/// A channel varying less than this never moved: not a scale question.
const double pedalScaleMinimumRange = 0.05;

/// Fewer finite samples than this and a channel tells nothing.
const int pedalScaleMinimumSamples = 20;

/// Events in the longitudinal G needed to judge a scale, and the share of
/// them in which the pedal must be pressed at the fraction scale.
const int pedalScaleMinimumEvents = 3;
const double pedalScaleMinimumAgreement = 0.5;

/// The pedal may be pressed this long before the G builds.
const double pedalScaleLeadSeconds = 0.5;

/// Whether [channel] declares no unit ([unit] is the unit its recording
/// declares for it, [declaredChannelUnit]) and stays within 0..1 while
/// moving: its scale cannot be told from its values.
bool pedalScaleAmbiguous(TelemetryChannel channel, String unit) {
  if (unit.trim().isNotEmpty) return false;
  var finite = 0;
  var lowest = double.infinity, highest = double.negativeInfinity;
  for (final value in channel.values) {
    if (!value.isFinite) continue;
    ++finite;
    if (value < lowest) lowest = value;
    if (value > highest) highest = value;
  }
  return finite >= pedalScaleMinimumSamples &&
      highest <= pedalScaleFractionMaximum &&
      highest - lowest >= pedalScaleMinimumRange;
}

/// The runs of [acceleration] (in g, or undeclared) where `sign * value`
/// reaches [peak] and stays at or beyond [hold] for at least [seconds],
/// without a gap, as (start, end) times. [hold] must not exceed [peak].
List<(double, double)> longitudinalRuns(
  TelemetryChannel acceleration,
  double sign,
  double peak,
  double hold,
  double seconds,
) {
  final runs = <(double, double)>[];
  final times = acceleration.timestamps, values = acceleration.values;
  if (times.length != values.length) return runs;
  final gap = telemetryGapThreshold(acceleration);
  var index = 0;
  while (index < values.length) {
    if (!(sign * values[index] >= peak)) {
      ++index;
      continue;
    }
    final start = times[index];
    var end = index + 1;
    while (end < values.length &&
        sign * values[end] >= hold &&
        !(gap > 0.0 && times[end] - times[end - 1] > gap)) {
      ++end;
    }
    final finish = times[end - 1];
    index = end;
    if (finish - start >= seconds) runs.add((start, finish));
  }
  return runs;
}

/// Whether [pedal] reaches [on] from [pedalScaleLeadSeconds] before to the
/// end of [run].
bool pedalPressedIn(TelemetryChannel pedal, (double, double) run, double on) {
  final times = pedal.timestamps;
  if (times.length != pedal.values.length) return false;
  final (from, to) = run;
  for (
    var index = lowerBound(times, from - pedalScaleLeadSeconds);
    index < times.length && times[index] <= to;
    ++index
  ) {
    if (pedal.values[index] >= on) return true;
  }
  return false;
}

/// A pedal is released over a run when at least this share of its samples
/// there are below the fraction threshold (a heel-and-toe blip is short).
const double pedalScaleReleasedShare = 0.8;

/// Whether [pedal] is released over [run]: at least
/// [pedalScaleReleasedShare] of its finite samples there are below [on].
/// False without samples.
bool pedalReleasedIn(TelemetryChannel pedal, (double, double) run, double on) {
  final times = pedal.timestamps;
  if (times.length != pedal.values.length) return false;
  final (from, to) = run;
  var count = 0, below = 0;
  for (var index = lowerBound(times, from); index < times.length && times[index] <= to; ++index) {
    final value = pedal.values[index];
    if (!value.isFinite) continue;
    ++count;
    if (value < on) ++below;
  }
  return count > 0 && below >= pedalScaleReleasedShare * count;
}

/// The scale of an ambiguous pedal judged against the G: a fraction when
/// it reaches [fractionOn] in at least half of the [pressed] runs (where
/// the pedal should work) and stays below it in at least half of the
/// [released] runs (where it should not), with [pedalScaleMinimumEvents]
/// or more of each; otherwise unknown. Both are needed: noise that is
/// above [fractionOn] everywhere also "presses" in every run.
PedalScale judgedPedalScale(
  TelemetryChannel pedal,
  List<(double, double)> pressed,
  List<(double, double)> released,
  double fractionOn,
) {
  if (pressed.length < pedalScaleMinimumEvents || released.length < pedalScaleMinimumEvents) {
    return PedalScale.unknown;
  }
  final pressedCount = pressed.where((run) => pedalPressedIn(pedal, run, fractionOn)).length;
  final releasedCount = released.where((run) => pedalReleasedIn(pedal, run, fractionOn)).length;
  return pressedCount >= pedalScaleMinimumAgreement * pressed.length &&
          releasedCount >= pedalScaleMinimumAgreement * released.length
      ? PedalScale.fraction
      : PedalScale.unknown;
}

/// A hard acceleration seen in the longitudinal G: it reaches this many g
/// and stays at or beyond [throttleScaleHoldG] for [throttleScaleSeconds].
const double throttleScalePeakG = 0.20;
const double throttleScaleHoldG = 0.10;
const double throttleScaleSeconds = 1.0;

/// A throttle in 0..1 is pressed from this fraction.
const double throttleScaleFractionOn = 0.20;

final _throttleScales = Expando<PedalScale>('throttle scale');

/// The scale of [session]'s `throttle` channel, judged over the whole
/// recording against its hard accelerations.
PedalScale throttleScale(TelemetrySession session) =>
    _throttleScales[session] ??= _throttleScale(session);

PedalScale _throttleScale(TelemetrySession session) {
  final name = session.aliases['throttle'] ?? '';
  final throttle = session.channels[name];
  if (throttle == null || !pedalScaleAmbiguous(throttle, declaredChannelUnit(session, name))) {
    return PedalScale.percent;
  }
  // The longitudinal G in g, whichever unit it is declared in.
  final view = accelerationAliasInG(session, 'longitudinalAcceleration');
  if (view == null || !view.supported) return PedalScale.unknown;
  final acceleration = view.channel;
  return judgedPedalScale(
    throttle,
    longitudinalRuns(
      acceleration,
      1.0,
      throttleScalePeakG,
      throttleScaleHoldG,
      throttleScaleSeconds,
    ),
    longitudinalRuns(acceleration, -1.0, 0.45, 0.30, 0.5),
    throttleScaleFractionOn,
  );
}
