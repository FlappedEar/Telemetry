// Port of the G-G, driving-state and coasting functions of FlappedEar
// Overlays' analysis controller (revision d4d1039, FET-39):
// comparisonGgScatter and comparisonTrailBraking of
// native/src/app/AnalysisControllerCornerAnalyzer.cpp, and
// outingLapCoasting of AnalysisControllerSegmentReview.cpp for one lap.
// [comparisonDrivingStates] is Telemetry's own: the same driving states and
// coasting of both laps of a comparison over its shown range, for the
// comparison page.
//
// A range is in metres on the comparison's shared axis (lap A's own trace);
// each lap's part of it is found through its projection onto that axis.
import 'driving_states.dart';
import 'coasting_analysis.dart';
import 'gg_pairs.dart';
import 'lap_comparison.dart';
import 'track_progress.dart';

/// A lap's coverage of the range is incomplete: no time for one end.
const String drivingIncompleteCoverage = 'incompleteCoverage';

/// Braking or cornering cannot be told for this lap.
const String drivingStateUnknownReason = 'stateUnknown';

/// The times of [slot]'s lap at [fromMeters] and [toMeters] on the shared
/// axis; the lap's own bounds at the axis ends. Null without coverage.
(double, double)? comparisonTimeRange(
  LapComparison comparison,
  int slot,
  double fromMeters,
  double toMeters,
) {
  final length = comparison.axisLengthMeters;
  final lap = comparison.lap(slot);
  double? timeAt(double meters) {
    if (meters <= 1e-6) return lap.start;
    if (meters >= length - 1e-6) return lap.end;
    return timeAtProgress(comparison.trace(slot), meters);
  }

  final t0 = timeAt(fromMeters), t1 = timeAt(toMeters);
  if (t0 == null || t1 == null || !(t1 > t0)) return null;
  return (t0, t1);
}

double _clampToAxis(double meters, double length) =>
    meters < 0.0 ? 0.0 : (meters > length ? length : meters);

/// One lap's G-G over the range.
final class ComparisonGgLap {
  ComparisonGgLap.unavailable(this.unavailableReason)
    : valid = false,
      pairs = null,
      peaks = GgPeaks(),
      points = const [];

  ComparisonGgLap._(GgPairs this.pairs, this.peaks, this.points)
    : valid = true,
      unavailableReason = '';

  final bool valid;
  final String unavailableReason;

  /// Every pair of the range, with how they were formed.
  final GgPairs? pairs;

  /// From every pair, never from the thinned [points].
  final GgPeaks peaks;

  /// The pairs to draw: at most the requested number plus the peaks.
  final List<GgPoint> points;
}

/// Both laps' G-G over a range of the shared axis.
final class ComparisonGgScatter {
  const ComparisonGgScatter({
    required this.valid,
    this.startMeters = 0.0,
    this.endMeters = 0.0,
    this.laps = const [],
  });

  final bool valid;
  final double startMeters;
  final double endMeters;
  final List<ComparisonGgLap> laps;
  String get algorithm => ggPairsAlgorithm;
}

/// The G-G pairs of both laps between [startMeters] and [endMeters] of the
/// shared axis, with their peaks and at most [maximumPoints] points each to
/// draw.
ComparisonGgScatter comparisonGgScatter(
  LapComparison comparison,
  double startMeters,
  double endMeters,
  int maximumPoints,
) {
  if (!comparison.axis.valid) return const ComparisonGgScatter(valid: false);
  final length = comparison.axisLengthMeters;
  final from = _clampToAxis(startMeters, length), to = _clampToAxis(endMeters, length);
  final laps = <ComparisonGgLap>[];
  for (final slot in const [0, 1]) {
    final range = comparisonTimeRange(comparison, slot, from, to);
    if (range == null) {
      laps.add(ComparisonGgLap.unavailable(drivingIncompleteCoverage));
      continue;
    }
    final pairs = buildGgPairs(comparison.lap(slot).session, range.$1, range.$2);
    if (!pairs.valid) {
      laps.add(ComparisonGgLap.unavailable(pairs.unavailableReason));
      continue;
    }
    final peaks = computeGgPeaks(pairs.points);
    laps.add(ComparisonGgLap._(pairs, peaks, decimateGgPoints(pairs.points, peaks, maximumPoints)));
  }
  return ComparisonGgScatter(valid: true, startMeters: from, endMeters: to, laps: laps);
}

/// A part of a range, as fractions 0..1 of it.
typedef RangeFraction = ({double from, double to});

/// One lap's braking while cornering over a range.
final class TrailBrakingLap {
  TrailBrakingLap();

  bool valid = true;
  String unavailableReason = '';
  String brakingProvenance = '';
  String corneringProvenance = '';
  String brakeChannel = '';
  String lateralChannel = '';
  double overlapSeconds = 0.0;
  double overlapMeters = 0.0;
  double brakingSeconds = 0.0;
  double corneringSeconds = 0.0;
  final List<RangeFraction> brakingStrip = [];
  final List<RangeFraction> corneringStrip = [];
  final List<RangeFraction> overlapStrip = [];
}

final class ComparisonTrailBraking {
  const ComparisonTrailBraking({
    required this.valid,
    this.startMeters = 0.0,
    this.endMeters = 0.0,
    this.crossesStartFinish = false,
    this.laps = const [],
  });

  final bool valid;
  final double startMeters;
  final double endMeters;
  final bool crossesStartFinish;
  final List<TrailBrakingLap> laps;
  String get algorithm => drivingStatesAlgorithm;
}

/// Braking while cornering (KAN-93) over [startMeters]..[endMeters] of the
/// shared axis for both laps. A range with its start after its end crosses
/// start/finish: the lap's end, then its beginning, laid end to end.
ComparisonTrailBraking comparisonTrailBraking(
  LapComparison comparison,
  double startMeters,
  double endMeters,
) {
  if (!comparison.axis.valid) return const ComparisonTrailBraking(valid: false);
  final length = comparison.axisLengthMeters;
  final from = _clampToAxis(startMeters, length), to = _clampToAxis(endMeters, length);
  final ranges = from <= to ? [(from, to)] : [(from, length), (0.0, to)];
  var span = 0.0;
  for (final (a, b) in ranges) {
    span += b - a;
  }
  if (!(span > 0.0)) return const ComparisonTrailBraking(valid: false);
  final laps = <TrailBrakingLap>[];
  for (final slot in const [0, 1]) {
    final trace = comparison.trace(slot);
    final session = comparison.lap(slot).session;
    var lap = TrailBrakingLap();
    var offset = 0.0;
    void strip(List<DrivingStateInterval> intervals, double rangeStart, List<RangeFraction> out) {
      for (final interval in intervals) {
        final a = progressAtTime(trace, interval.start), b = progressAtTime(trace, interval.end);
        if (a == null || b == null) continue;
        out.add((from: (offset + a - rangeStart) / span, to: (offset + b - rangeStart) / span));
      }
    }

    for (final (rangeStart, rangeEnd) in ranges) {
      final times = comparisonTimeRange(comparison, slot, rangeStart, rangeEnd);
      if (times == null) {
        lap = TrailBrakingLap()
          ..valid = false
          ..unavailableReason = drivingIncompleteCoverage;
        break;
      }
      final states = classifyDrivingStates(session, times.$1, times.$2);
      final overlap = overlapOf(states.braking.active, states.cornering.active);
      lap.overlapSeconds += intervalSeconds(overlap);
      lap.overlapMeters += travelledMeters(session, overlap);
      lap.brakingSeconds += intervalSeconds(states.braking.active);
      lap.corneringSeconds += intervalSeconds(states.cornering.active);
      strip(states.braking.active, rangeStart, lap.brakingStrip);
      strip(states.cornering.active, rangeStart, lap.corneringStrip);
      strip(overlap, rangeStart, lap.overlapStrip);
      lap.brakingProvenance = states.braking.provenance;
      lap.corneringProvenance = states.cornering.provenance;
      lap.brakeChannel = states.braking.channel;
      lap.lateralChannel = states.cornering.channel;
      offset += rangeEnd - rangeStart;
    }
    if (lap.valid &&
        (lap.brakingProvenance == drivingStateUnknown ||
            lap.corneringProvenance == drivingStateUnknown)) {
      lap = TrailBrakingLap()
        ..valid = false
        ..unavailableReason = drivingStateUnknownReason
        ..brakingProvenance = lap.brakingProvenance
        ..corneringProvenance = lap.corneringProvenance;
    }
    laps.add(lap);
  }
  return ComparisonTrailBraking(
    valid: true,
    startMeters: from,
    endMeters: to,
    crossesStartFinish: from > to,
    laps: laps,
  );
}

/// One lap's driving states and coasting over a range of the shared axis.
final class LapDrivingStates {
  LapDrivingStates.unavailable(this.unavailableReason)
    : valid = false,
      startTime = 0.0,
      endTime = 0.0,
      states = DrivingStateClassification(),
      coasting = CoastingSummary(),
      overlap = const [],
      overlapMeters = 0.0;

  LapDrivingStates._(
    this.startTime,
    this.endTime,
    this.states,
    this.coasting,
    this.overlap,
    this.overlapMeters,
  ) : valid = true,
      unavailableReason = '';

  final bool valid;
  final String unavailableReason;

  /// The lap's part of the range, in recording time.
  final double startTime;
  final double endTime;
  final DrivingStateClassification states;

  /// Coasting episodes carry their positions on the shared axis.
  final CoastingSummary coasting;

  /// Braking while cornering.
  final List<DrivingStateInterval> overlap;
  final double overlapMeters;

  double get seconds => endTime - startTime;
}

/// Both laps' driving states and coasting between [startMeters] and
/// [endMeters] of the shared axis (start before end).
List<LapDrivingStates> comparisonDrivingStates(
  LapComparison comparison,
  double startMeters,
  double endMeters, {
  DrivingStateOptions options = const DrivingStateOptions(),
}) {
  if (!comparison.axis.valid) return const [];
  final length = comparison.axisLengthMeters;
  final from = _clampToAxis(startMeters, length), to = _clampToAxis(endMeters, length);
  return [
    for (final slot in const [0, 1]) _lapDrivingStates(comparison, slot, from, to, options),
  ];
}

LapDrivingStates _lapDrivingStates(
  LapComparison comparison,
  int slot,
  double from,
  double to,
  DrivingStateOptions options,
) {
  final range = comparisonTimeRange(comparison, slot, from, to);
  if (range == null) return LapDrivingStates.unavailable(drivingIncompleteCoverage);
  final session = comparison.lap(slot).session;
  final states = classifyDrivingStates(session, range.$1, range.$2, options);
  if (!states.valid) return LapDrivingStates.unavailable(drivingIncompleteCoverage);
  final coasting = summarizeCoasting(
    session,
    range.$1,
    range.$2,
    lapTrace: comparison.trace(slot),
    options: options,
  );
  final overlap = overlapOf(states.braking.active, states.cornering.active);
  return LapDrivingStates._(
    range.$1,
    range.$2,
    states,
    coasting,
    overlap,
    travelledMeters(session, overlap),
  );
}
