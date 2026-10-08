// What the car did over one session's laps (FET-228, idea 12 of FET-217): a
// temperature still rising at the end, and strong acceleration falling away.
// Both come from the channel summaries the Car card already shows (each
// section's maximum and strong acceleration, see day_channel_summaries.dart);
// nothing is measured differently. They are observations from the
// recording, not causes or a diagnosis.
import 'day_channel_summaries.dart';
import 'day_laps.dart';

/// Ranked laps at the end of a session a temperature's rise is read over.
const int carWatchLaps = 3;

/// The rise of a temperature's lap maximum over [carWatchLaps] laps, in °C
/// (in °F: × 1.8), from which it is still rising. A recording that does not
/// declare a unit is read as °C, as OBD temperatures are.
const double carWatchRiseCelsius = 8;

/// Ranked laps with strong acceleration needed before a fall is read.
const int carWatchAccelerationLaps = 4;

/// The share strong acceleration on the last ranked lap must be below the
/// session's highest on an earlier one to count as falling.
const double carWatchAccelerationFall = 0.05;

/// The smallest rise, in °C (in °F: × 1.8), named alongside a fall.
const double carWatchAlongsideCelsius = 2;

/// Whether a part of [CarWatch] could be read, and why not.
enum CarWatchStatus {
  /// Read; a finding may or may not have been noted.
  read,

  /// Not recorded on any of the session's ranked laps.
  notRecorded,

  /// Recorded, on too few ranked laps.
  needsLaps,

  /// Recorded, but missing on one of the laps it is read over (for
  /// acceleration: the last ranked lap).
  missingOnLap,
}

/// A temperature's lap maximum from lap [fromLap] to lap [toLap].
final class CarWatchRise {
  const CarWatchRise({
    required this.channel,
    required this.unit,
    required this.fromLap,
    required this.toLap,
    required this.from,
    required this.to,
  });

  final String channel;

  /// As the recording declares it ("" when undeclared).
  final String unit;

  /// Lap numbers as the day shows them.
  final int fromLap, toLap;
  final double from, to;

  double get rise => to - from;

  /// [rise] in °C.
  double get riseCelsius => _fahrenheit(unit) ? rise / 1.8 : rise;
}

/// Strong acceleration from the session's highest, on lap [fromLap], to the
/// last ranked lap [toLap] (see [lapStrongAcceleration]), and the temperature
/// that rose most over the same laps.
final class CarWatchFall {
  const CarWatchFall({
    required this.fromLap,
    required this.toLap,
    required this.from,
    required this.to,
    this.alongside,
  });

  final int fromLap, toLap;

  /// Strong acceleration, in g.
  final double from, to;

  /// The temperature whose lap maximum rose most from [fromLap] to [toLap],
  /// by [carWatchAlongsideCelsius] or more; null when none did.
  final CarWatchRise? alongside;

  /// How much lower [to] is than [from], as a share of [from].
  double get fall => (from - to) / from;
}

/// Strong acceleration on the last ranked lap ([toLap], [to] g) against the
/// session's highest on an earlier ranked lap ([fromLap], [from] g), whether
/// or not it fell far enough to be noted.
final class CarWatchPeak {
  const CarWatchPeak({
    required this.fromLap,
    required this.toLap,
    required this.from,
    required this.to,
  });

  final int fromLap, toLap;
  final double from, to;

  /// How much lower [to] is than [from], as a share of [from]; negative when
  /// the last lap is higher.
  double get lower => (from - to) / from;
}

/// One session's car observations.
final class CarWatch {
  CarWatch({
    required this.runId,
    required this.rankedLaps,
    required this.temperatures,
    required this.acceleration,
    this.accelerationLaps = 0,
    this.temperatureFromLap,
    this.temperatureToLap,
    List<CarWatchRise> rises = const [],
    this.fall,
    this.peak,
  }) : rises = List.unmodifiable(rises);

  final String runId;

  /// The session's ranked laps: timed laps the day compares (out and in
  /// laps, excluded, off-route and short laps are left out, so the pit
  /// lane, cooling down or a detour do not read as the car).
  final int rankedLaps;

  /// Whether the temperatures' rise could be read: [CarWatchStatus.read]
  /// when at least one temperature was recorded on each of the last
  /// [carWatchLaps] ranked laps; [CarWatchStatus.missingOnLap] when every
  /// one recorded is missing on one of them.
  final CarWatchStatus temperatures;

  /// Whether a fall in strong acceleration could be read.
  final CarWatchStatus acceleration;

  /// Ranked laps with strong acceleration.
  final int accelerationLaps;

  /// Temperatures still rising at the end, largest rise (in °C) first.
  final List<CarWatchRise> rises;

  /// The first and last ranked lap the temperatures were read over (lap
  /// numbers as the day shows them); set when [temperatures] is
  /// [CarWatchStatus.read].
  final int? temperatureFromLap, temperatureToLap;

  final CarWatchFall? fall;

  /// The last ranked lap's strong acceleration against the highest earlier
  /// one; set when [acceleration] is [CarWatchStatus.read].
  final CarWatchPeak? peak;

  /// Whether the session's laps recorded either.
  bool get recorded =>
      temperatures != CarWatchStatus.notRecorded || acceleration != CarWatchStatus.notRecorded;
}

bool _fahrenheit(String unit) => unit.trim().toLowerCase().endsWith('f');

/// [celsius] in [unit] (a declared °F, else °C).
double carWatchCelsiusIn(double celsius, String unit) =>
    _fahrenheit(unit) ? celsius * 1.8 : celsius;

/// What the car did over [run]'s ranked laps; null when its recording could
/// not be read.
CarWatch? carWatch(RunChannelSummaries run) {
  if (run.unavailableReason.isNotEmpty) return null;
  // Each channel's sections and the accelerations are built from the same
  // rows in the same order (summarizeDayChannels); a section whose row
  // differs is not read.
  final ranked = [
    for (var i = 0; i < run.laps.length; i++)
      if (run.laps[i].row case final row
          when row.type == LapSectionType.lap && row.referenceEligible && !row.groupMarked)
        i,
  ];

  double? maximumAt(RunChannel channel, int section) {
    if (section >= channel.sections.length) return null;
    final at = channel.sections[section];
    if (!identical(at.row, run.laps[section].row) && at.row != run.laps[section].row) return null;
    final maximum = at.summary.maximum;
    return at.summary.valid && maximum != null && maximum.isFinite ? maximum : null;
  }

  int lapAt(int section) => run.laps[section].row.lapNumber;

  CarWatchRise? riseOf(RunChannel channel, int from, int to) {
    final start = maximumAt(channel, from), end = maximumAt(channel, to);
    if (start == null || end == null) return null;
    return CarWatchRise(
      channel: channel.channel,
      unit: channel.unit,
      fromLap: lapAt(from),
      toLap: lapAt(to),
      from: start,
      to: end,
    );
  }

  // Temperatures: rising from the first of the last ranked laps to the last
  // (an unranked lap between them is skipped), and not falling on the last
  // step.
  final recordedChannels = [
    for (final channel in run.channels)
      if (ranked.any((section) => maximumAt(channel, section) != null)) channel,
  ];
  final rises = <CarWatchRise>[];
  CarWatchStatus temperatures;
  int? temperatureFromLap, temperatureToLap;
  if (recordedChannels.isEmpty) {
    temperatures = CarWatchStatus.notRecorded;
  } else if (ranked.length < carWatchLaps) {
    temperatures = CarWatchStatus.needsLaps;
  } else {
    temperatures = CarWatchStatus.missingOnLap;
    final last = ranked.sublist(ranked.length - carWatchLaps);
    temperatureFromLap = lapAt(last.first);
    temperatureToLap = lapAt(last.last);
    for (final channel in recordedChannels) {
      final values = [for (final section in last) maximumAt(channel, section)];
      if (values.contains(null)) continue;
      temperatures = CarWatchStatus.read;
      final rise = riseOf(channel, last.first, last.last)!;
      if (rise.rise >= carWatchCelsiusIn(carWatchRiseCelsius, channel.unit) &&
          values.last! >= values[values.length - 2]!) {
        rises.add(rise);
      }
    }
  }
  rises.sort((a, b) => b.riseCelsius.compareTo(a.riseCelsius));

  // Strong acceleration: the last ranked lap against the session's highest.
  double? strongAt(int section) {
    final g = run.laps[section].acceleration.strongG;
    return g != null && g.isFinite && g > 0 ? g : null;
  }

  final accelerated = [
    for (final section in ranked)
      if (strongAt(section) case final g?) (section: section, g: g),
  ];
  CarWatchFall? fall;
  CarWatchPeak? peak;
  final CarWatchStatus acceleration;
  if (accelerated.isEmpty) {
    acceleration = CarWatchStatus.notRecorded;
  } else if (ranked.length < carWatchAccelerationLaps) {
    acceleration = CarWatchStatus.needsLaps;
  } else if (accelerated.last.section != ranked.last) {
    acceleration = CarWatchStatus.missingOnLap;
  } else if (accelerated.length < carWatchAccelerationLaps) {
    acceleration = CarWatchStatus.needsLaps;
  } else {
    acceleration = CarWatchStatus.read;
    final last = accelerated.last;
    var highest = accelerated.first;
    for (final lap in accelerated.take(accelerated.length - 1)) {
      if (lap.g > highest.g) highest = lap;
    }
    peak = CarWatchPeak(
      fromLap: lapAt(highest.section),
      toLap: lapAt(last.section),
      from: highest.g,
      to: last.g,
    );
    if ((highest.g - last.g) / highest.g >= carWatchAccelerationFall) {
      CarWatchRise? alongside;
      for (final channel in recordedChannels) {
        final rise = riseOf(channel, highest.section, last.section);
        if (rise != null &&
            rise.riseCelsius >= carWatchAlongsideCelsius &&
            (alongside == null || rise.riseCelsius > alongside.riseCelsius)) {
          alongside = rise;
        }
      }
      fall = CarWatchFall(
        fromLap: lapAt(highest.section),
        toLap: lapAt(last.section),
        from: highest.g,
        to: last.g,
        alongside: alongside,
      );
    }
  }

  return CarWatch(
    runId: run.runId,
    rankedLaps: ranked.length,
    temperatures: temperatures,
    acceleration: acceleration,
    accelerationLaps: accelerated.length,
    temperatureFromLap: temperatures == CarWatchStatus.read ? temperatureFromLap : null,
    temperatureToLap: temperatures == CarWatchStatus.read ? temperatureToLap : null,
    rises: rises,
    fall: fall,
    peak: peak,
  );
}
