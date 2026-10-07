// Which channel tells when the driver brakes (FET-204): the measured brake
// when it is trustworthy, otherwise the deceleration when that is, chosen
// by the quality of the data rather than by which channel exists. This
// departs from Overlays (d4d1039, BrakingOnset.cpp and DrivingStates.cpp),
// which use any brake channel that exists (KAN-227).
//
// The judgement uses fixed thresholds, never a caller's, so every analysis
// of one session (corner braking, driving states, the coach) uses the same
// source.
import '../telemetry_session.dart';
import 'pedal_scale.dart';

/// Fewer finite samples than this and a channel tells nothing.
const int brakingSourceMinimumSamples = 20;

/// A deceleration is usable when it reaches this many g somewhere.
const double brakingSourceUsableG = 0.30;

/// A hard braking seen in the deceleration: it reaches
/// [brakingSourceHardG] and stays beyond [brakingSourceUsableG] for at
/// least [brakingSourceHardSeconds], without a gap.
const double brakingSourceHardG = 0.45;
const double brakingSourceHardSeconds = 0.5;

/// A brake in % (or with no declared unit) is pressed from this value; a
/// brake read as a 0..1 fraction from [brakingSourcePressedFraction].
const double brakingSourcePressedPercent = 10.0;
const double brakingSourcePressedFraction = 0.10;

/// The brake may be pressed this long before the deceleration builds.
const double brakingSourceLeadSeconds = 0.5;

/// Hard brakings needed before the brake is judged against them, and the
/// share of them in which the brake must be pressed to be trusted.
const int brakingSourceMinimumHardBrakings = 3;
const double brakingSourceMinimumAgreement = 0.5;

/// What the session's brake and deceleration channels are worth.
final class BrakingSourceQuality {
  const BrakingSourceQuality({
    required this.brakeName,
    required this.decelerationName,
    required this.brakeUsable,
    required this.decelerationUsable,
    required this.hardBrakings,
    required this.hardBrakingsWithBrake,
    this.brakeScale = PedalScale.percent,
  });

  /// The `brake` alias's channel, or empty when there is none.
  final String brakeName;

  /// The `longitudinalAcceleration` alias's channel, or empty.
  final String decelerationName;

  /// The brake has enough finite samples and, when it is in % (or
  /// undeclared) and the deceleration shows enough hard brakings to judge
  /// it, is pressed in at least half of them. Without that evidence a brake
  /// with data is kept: a short session in the pit lane is never braked,
  /// and a brake in another unit is left to report its unit.
  final bool brakeUsable;

  /// The deceleration has enough samples in g (or no declared unit) and
  /// reaches [brakingSourceUsableG] somewhere.
  final bool decelerationUsable;

  /// Hard brakings in the deceleration, and how many of them the brake
  /// shows (0 and 0 when the brake was not judged against them).
  final int hardBrakings;
  final int hardBrakingsWithBrake;

  /// How the brake's values are read (FET-205): a brake with no unit that
  /// stays within 0..1 is a fraction when the hard brakings show it pressed
  /// at that scale, otherwise its scale is unknown and it is not usable.
  final PedalScale brakeScale;

  bool get hasBrake => brakeName.isNotEmpty;
  bool get hasDeceleration => decelerationName.isNotEmpty;

  /// A brake that is recorded but gives way to the deceleration: it has
  /// (almost) no data, or is not pressed in most of the hard brakings the
  /// deceleration shows. Only when the deceleration is usable.
  bool get brakeRejected => hasBrake && !brakeUsable && decelerationUsable;
}

final _cache = Expando<BrakingSourceQuality>('braking source quality');

/// The quality of [session]'s brake and deceleration channels, judged over
/// the whole recording, so every window of one session uses the same
/// source.
BrakingSourceQuality brakingSourceQuality(TelemetrySession session) =>
    _cache[session] ??= _assess(session);

String _aliasName(TelemetrySession session, String alias) {
  final name = session.aliases[alias] ?? '';
  return name.isNotEmpty && session.channels.containsKey(name) ? name : '';
}

int _finiteCount(TelemetryChannel channel) {
  var finite = 0;
  for (final value in channel.values) {
    if (value.isFinite) ++finite;
  }
  return finite;
}

BrakingSourceQuality _assess(TelemetrySession session) {
  final brakeName = _aliasName(session, 'brake');
  final decelerationName = _aliasName(session, 'longitudinalAcceleration');
  final brake = brakeName.isEmpty ? null : session.channels[brakeName]!;
  var deceleration = decelerationName.isEmpty ? null : session.channels[decelerationName]!;
  if (deceleration != null && deceleration.timestamps.length != deceleration.values.length) {
    deceleration = null;
  }

  var decelerationUsable = false;
  if (deceleration != null) {
    final unit = deceleration.unit.trim().toLowerCase();
    var lowest = double.infinity;
    for (final value in deceleration.values) {
      if (value.isFinite && value < lowest) lowest = value;
    }
    decelerationUsable =
        (unit.isEmpty || unit == 'g') &&
        _finiteCount(deceleration) >= brakingSourceMinimumSamples &&
        -lowest >= brakingSourceUsableG;
  }

  // A malformed brake is not judged here: the analyses report it.
  final brakeWellFormed = brake != null && brake.timestamps.length == brake.values.length;
  final brakeUnit = brake?.unit.trim() ?? '';
  final brakeHasData = brake != null && _finiteCount(brake) >= brakingSourceMinimumSamples;

  final runs = decelerationUsable
      ? longitudinalRuns(
          deceleration!,
          -1.0,
          brakingSourceHardG,
          brakingSourceUsableG,
          brakingSourceHardSeconds,
        )
      : const <(double, double)>[];
  final judged = brakeWellFormed && brakeHasData && (brakeUnit.isEmpty || brakeUnit == '%');
  final ambiguous = judged && pedalScaleAmbiguous(brake);
  final scale = !ambiguous
      ? PedalScale.percent
      : !decelerationUsable
      ? PedalScale.unknown
      : judgedPedalScale(
          brake,
          runs,
          longitudinalRuns(
            deceleration!,
            1.0,
            throttleScalePeakG,
            throttleScaleHoldG,
            throttleScaleSeconds,
          ),
          brakingSourcePressedFraction,
        );
  final pressedOn = scale == PedalScale.fraction
      ? brakingSourcePressedFraction
      : brakingSourcePressedPercent;
  var hard = 0, withBrake = 0;
  if (judged) {
    hard = runs.length;
    withBrake = runs.where((run) => pedalPressedIn(brake, run, pressedOn)).length;
  }

  final brakeUsable =
      brake != null &&
      scale != PedalScale.unknown &&
      (!brakeWellFormed ||
          (brakeHasData &&
              (hard < brakingSourceMinimumHardBrakings ||
                  withBrake >= brakingSourceMinimumAgreement * hard)));
  return BrakingSourceQuality(
    brakeName: brakeName,
    decelerationName: decelerationName,
    brakeUsable: brakeUsable,
    decelerationUsable: decelerationUsable,
    hardBrakings: hard,
    hardBrakingsWithBrake: withBrake,
    brakeScale: scale,
  );
}
