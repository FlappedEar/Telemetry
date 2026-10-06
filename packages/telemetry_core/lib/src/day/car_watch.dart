// What the car did over one session's timed laps (FET-228, idea 12 of
// FET-217): a temperature still rising at the end, and strong acceleration
// falling away. Both come from the channel summaries the Car card already
// shows (each section's maximum and strong acceleration, see
// day_channel_summaries.dart); nothing is measured differently. They are
// observations from the recording, not causes or a diagnosis.
import 'day_channel_summaries.dart';
import 'day_laps.dart';

/// Timed laps at the end of a session a temperature's rise is read over.
const int carWatchLaps = 3;

/// The rise of a temperature's lap maximum over [carWatchLaps] laps, in °C
/// (in °F: × 1.8), from which it is still rising. A recording that does not
/// declare a unit is read as °C, as OBD temperatures are.
const double carWatchRiseCelsius = 8;

/// Timed laps with strong acceleration needed before a fall is read.
const int carWatchAccelerationLaps = 4;

/// The share strong acceleration on the last timed lap must be below the
/// session's highest on an earlier lap to count as falling.
const double carWatchAccelerationFall = 0.05;

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
}

/// Strong acceleration from the session's highest, on lap [fromLap], to the
/// last timed lap [toLap] (see [lapStrongAcceleration]), and the temperature
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

  /// The temperature whose lap maximum rose most from [fromLap] to [toLap];
  /// null when none rose.
  final CarWatchRise? alongside;

  /// How much lower [to] is than [from], as a share of [from].
  double get fall => (from - to) / from;
}

/// One session's car observations.
final class CarWatch {
  CarWatch({
    required this.runId,
    required this.timedLaps,
    List<CarWatchRise> rises = const [],
    this.fall,
    this.temperaturesRead = 0,
    this.accelerationLaps = 0,
    this.recorded = false,
  }) : rises = List.unmodifiable(rises);

  final String runId;

  /// The session's timed laps (out and in laps are left out: the pit lane
  /// and cooling down are not the car at speed).
  final int timedLaps;

  /// Temperatures still rising at the end, largest rise first.
  final List<CarWatchRise> rises;

  final CarWatchFall? fall;

  /// Temperatures recorded on each of the last [carWatchLaps] timed laps,
  /// so their rise could be read.
  final int temperaturesRead;

  /// Timed laps with strong acceleration.
  final int accelerationLaps;

  /// Whether the recording has a temperature or strong acceleration on any
  /// timed lap, read or not.
  final bool recorded;

  /// Whether anything could be read at all.
  bool get read => temperaturesRead > 0 || accelerationLaps >= carWatchAccelerationLaps;

  bool get settled => rises.isEmpty && fall == null;
}

/// The threshold of [carWatchRiseCelsius] in [unit].
double carWatchRiseIn(String unit) {
  final lower = unit.trim().toLowerCase();
  return lower.endsWith('f') ? carWatchRiseCelsius * 1.8 : carWatchRiseCelsius;
}

/// What the car did over [run]'s timed laps; null when its recording could
/// not be read.
CarWatch? carWatch(RunChannelSummaries run) {
  if (run.unavailableReason.isNotEmpty) return null;
  // Sections and accelerations come in the same order.
  final timed = [
    for (var i = 0; i < run.laps.length; i++)
      if (run.laps[i].row.type == LapSectionType.lap) i,
  ];

  double? maximumAt(RunChannel channel, int section) {
    if (section >= channel.sections.length) return null;
    final summary = channel.sections[section].summary;
    final maximum = summary.maximum;
    return summary.valid && maximum != null && maximum.isFinite ? maximum : null;
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

  final rises = <CarWatchRise>[];
  var read = 0;
  if (timed.length >= carWatchLaps) {
    final last = timed.sublist(timed.length - carWatchLaps);
    for (final channel in run.channels) {
      if (last.any((section) => maximumAt(channel, section) == null)) continue;
      read++;
      final rise = riseOf(channel, last.first, last.last)!;
      if (rise.rise >= carWatchRiseIn(channel.unit)) rises.add(rise);
    }
  }
  rises.sort((a, b) => b.rise.compareTo(a.rise));

  final accelerated = [
    for (final section in timed)
      if (run.laps[section].acceleration.strongG case final g? when g.isFinite && g > 0)
        (section: section, g: g),
  ];
  CarWatchFall? fall;
  if (accelerated.length >= carWatchAccelerationLaps && accelerated.last.section == timed.last) {
    final last = accelerated.last;
    var highest = accelerated.first;
    for (final lap in accelerated.take(accelerated.length - 1)) {
      if (lap.g > highest.g) highest = lap;
    }
    if ((highest.g - last.g) / highest.g >= carWatchAccelerationFall) {
      CarWatchRise? alongside;
      for (final channel in run.channels) {
        final rise = riseOf(channel, highest.section, last.section);
        if (rise != null && rise.rise > 0 && (alongside == null || rise.rise > alongside.rise)) {
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
    timedLaps: timed.length,
    rises: rises,
    fall: fall,
    temperaturesRead: read,
    accelerationLaps: accelerated.length,
    recorded:
        accelerated.isNotEmpty ||
        run.channels.any((channel) => timed.any((section) => maximumAt(channel, section) != null)),
  );
}
