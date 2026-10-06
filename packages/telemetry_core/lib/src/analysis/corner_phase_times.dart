// Where a corner's time came from (FET-221, idea 5 of FET-217): the corner
// split into entry, mid-corner and exit by its geometry, and each part timed
// on a lap's projected trace. The boundaries are track geometry shared by
// every lap on the axis (the start and end of the corner's tightest part,
// see proposeCornerGeometryPhases), so two laps are timed over the same
// metres and their parts add up to the corner's time. Nothing is a driving
// measurement: the minimum-speed point and the braking point stay per-lap
// figures elsewhere.
import 'corner_phases.dart';
import 'track_progress.dart';

/// The corner's start is not inside it ([CornerPhaseSplit.unavailableReason]
/// otherwise gives the geometry's own reason, such as
/// [cornerPhaseMultipleApexes]).
const String cornerPhaseTimesNotTimed = 'cornerPhaseNotTimed';

/// A corner's three parts on a shared axis, from its start to the start of
/// its tightest part ([entryEndMeters]), through it ([midEndMeters]), and on
/// to its end.
final class CornerPhaseSplit {
  const CornerPhaseSplit({
    this.startMeters = 0,
    this.entryEndMeters = 0,
    this.midEndMeters = 0,
    this.endMeters = 0,
    this.unavailableReason = '',
  });

  final double startMeters, entryEndMeters, midEndMeters, endMeters;

  /// Non-empty: the corner is not split.
  final String unavailableReason;

  bool get valid => unavailableReason.isEmpty;
}

/// [segment] (an approved corner on [axis]) split at the start and end of
/// its tightest part. A corner across the timing gate, or one whose tightest
/// part cannot be told (two of them, too little shape), is not split and
/// says why.
CornerPhaseSplit cornerPhaseSplit(
  ProgressAxis axis,
  TrackFeatures features,
  Map<String, Object?> segment,
) {
  final corner = cornerFromSegment(axis, features, segment);
  final start = corner.start.progressMeters, end = corner.end.progressMeters;
  if (!(corner.lengthMeters > 0)) {
    return const CornerPhaseSplit(unavailableReason: cornerPhaseInvalidInput);
  }
  if (end <= start) {
    return const CornerPhaseSplit(unavailableReason: cornerPhaseCrossesGate);
  }
  final phases = proposeCornerGeometryPhases(axis, features, corner);
  if (!phases.valid) {
    return const CornerPhaseSplit(unavailableReason: cornerPhaseInvalidInput);
  }
  if (!phases.apex.resolved) {
    return CornerPhaseSplit(unavailableReason: phases.apex.unresolvedReason);
  }
  final from = phases.apex.evidence['regionStartMeters'];
  final to = phases.apex.evidence['regionEndMeters'];
  if (from is! double || to is! double || !(from >= start && from <= to && to <= end)) {
    // The tightest part runs across the corner's start or end.
    return const CornerPhaseSplit(unavailableReason: cornerPhaseAtCornerBoundary);
  }
  return CornerPhaseSplit(
    startMeters: start,
    entryEndMeters: from,
    midEndMeters: to,
    endMeters: end,
  );
}

/// One lap's time through each part of a [CornerPhaseSplit], in seconds.
final class CornerPhaseTimes {
  const CornerPhaseTimes({this.entry, this.mid, this.exit, this.unavailableReason = ''});

  final double? entry, mid, exit;

  /// Non-empty: the lap is not timed through the parts.
  final String unavailableReason;

  bool get valid => unavailableReason.isEmpty;

  /// The three parts together: the time from the corner's start to its end.
  double? get total => valid ? entry! + mid! + exit! : null;
}

/// [trace]'s time through each part of [split]; not timed when the trace
/// does not cover a boundary (never bridged).
CornerPhaseTimes cornerPhaseTimes(CornerPhaseSplit split, List<ProgressSegment> trace) {
  if (!split.valid) return CornerPhaseTimes(unavailableReason: split.unavailableReason);
  final times = [
    for (final at in [split.startMeters, split.entryEndMeters, split.midEndMeters, split.endMeters])
      timeAtProgress(trace, at),
  ];
  if (times.contains(null) ||
      !(times[0]! <= times[1]! && times[1]! <= times[2]! && times[2]! <= times[3]!)) {
    return const CornerPhaseTimes(unavailableReason: cornerPhaseTimesNotTimed);
  }
  return CornerPhaseTimes(
    entry: times[1]! - times[0]!,
    mid: times[2]! - times[1]!,
    exit: times[3]! - times[2]!,
  );
}
