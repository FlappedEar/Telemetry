// A theoretical best whose segments join (FET-222, idea 6 of FET-217). The
// raw theoretical best takes each segment's fastest time from any lap, so a
// corner may be taken from a lap that entered it 15 km/h faster than the lap
// the straight before came from. A car cannot change speed at a line: here
// the fastest combination is chosen in which, wherever two laps meet, the
// speed leaving one segment and the speed entering the next differ by at
// most [realisticJoinMetresPerSecond]. Segments of one lap always join.
// When the last segment runs across the timing gate and ends where the first
// starts, that join is checked too; otherwise the lap's start, at the gate,
// is not joined to its end. It is an estimate: matching speeds is necessary
// for two laps to join, not proof that the car could (two laps can be on
// different lines at the same speed), and at 1 g of braking 2 km/h is about
// 0.06 s, near the crossing time's own error at 10 Hz.
//
// Beside it, the repeatable theoretical best: the sum of each segment's
// quickest typical (median) time in one session, what the laps did through
// each segment as a rule rather than once.
import '../operation.dart';
import '../speed_units.dart';
import '../telemetry_session.dart';
import 'outing_results.dart';
import 'sector_timing.dart';
import 'track_segment_review.dart';

/// The largest speed difference, in m/s (2 km/h), at which two laps join.
/// GPS speed at 10 Hz or faster is good to a few tenths of a km/h; more than
/// this is a speed the car did not have at that point.
const double realisticJoinMetresPerSecond = 2 / 3.6;

/// Two segments meet when one ends within this distance of where the next
/// starts; segments further apart are not joined.
const double realisticJoinGapMeters = 0.5;

/// No approved segments, or a segment no lap timed.
const String realisticIncompleteCoverage = 'incompleteCoverage';

/// No lap records a speed in a known unit, so no two laps can be joined.
const String realisticNoSpeed = 'noSpeed';

/// Every segment is timed, but no laps join at every line between them.
const String realisticNoJoin = 'noJoin';

/// One lap of the population: its sector times and the speed at each
/// segment's start and end in m/s (null where the speed was not recorded).
final class RealisticLapInput {
  RealisticLapInput({
    required this.times,
    required List<double?> entrySpeeds,
    required List<double?> exitSpeeds,
  }) : entrySpeeds = List.unmodifiable(entrySpeeds),
       exitSpeeds = List.unmodifiable(exitSpeeds);

  final LapSectorTimes times;

  /// By approved segment, in approved order.
  final List<double?> entrySpeeds, exitSpeeds;
}

/// Where one segment of the realistic best comes from.
final class RealisticSegment {
  const RealisticSegment({
    required this.segmentId,
    required this.seconds,
    required this.lapReference,
    this.joinMetresPerSecond,
  });

  final String segmentId;
  final double seconds;
  final Object? lapReference;

  /// The speed difference with the segment before where two laps meet; null
  /// where the same lap continues or the segments do not meet (the first
  /// segment meets the last only when the last runs across the gate into
  /// it).
  final double? joinMetresPerSecond;
}

/// The realistic theoretical best: [totalSeconds] and where each segment
/// comes from, or why not.
final class RealisticTheoreticalBest {
  RealisticTheoreticalBest({
    List<RealisticSegment> segments = const [],
    this.totalSeconds,
    this.unavailableReason = '',
  }) : segments = List.unmodifiable(segments);

  /// In approved order.
  final List<RealisticSegment> segments;
  final double? totalSeconds;

  /// Non-empty: no total.
  final String unavailableReason;

  bool get valid => unavailableReason.isEmpty && totalSeconds != null;

  /// How many different laps it is made of.
  int get lapCount => {for (final segment in segments) segment.lapReference}.length;
}

/// The speed of [session] at [time] in m/s, by its speed channel; null when
/// not recorded there or in an unknown unit.
double? speedMetresPerSecondAt(TelemetrySession session, double? time) {
  if (time == null) return null;
  final channel = session.channel('speed');
  if (channel == null) return null;
  final value = session.valueAt('speed', time);
  final metres = speedInMetresPerSecond(value, channel.unit);
  return metres != null && metres.isFinite ? metres : null;
}

/// The fastest combination of [laps]' sector times through every approved
/// segment in which consecutive segments from different laps join within
/// [realisticJoinMetresPerSecond]. Laps not timed against [approved] are
/// left out, as the raw theoretical best leaves them out.
RealisticTheoreticalBest computeRealisticTheoreticalBest(
  ApprovedSegmentation approved,
  List<RealisticLapInput> laps, {
  CancellationCheck? cancelled,
}) {
  final segments = approved.segments;
  final ids = [
    for (final segment in segments) segment['id'] is String ? segment['id'] as String : '',
  ];
  if (!approved.valid || approved.revision.isEmpty || ids.isEmpty) {
    return RealisticTheoreticalBest(unavailableReason: realisticIncompleteCoverage);
  }
  final population = [
    for (final lap in laps)
      if (lap.times.valid &&
          lap.times.stamp.revision == approved.revision &&
          lap.times.stamp.trackConfigurationReference == approved.trackConfigurationReference &&
          lap.entrySpeeds.length == ids.length &&
          lap.exitSpeeds.length == ids.length)
        lap,
  ];
  final count = ids.length;
  final seconds = [
    for (final lap in population)
      [
        for (var i = 0; i < count; ++i)
          if (_sector(lap, ids[i])?.seconds case final time? when time.isFinite) time else null,
      ],
  ];
  if (population.isEmpty ||
      [for (var i = 0; i < count; ++i) i].any((i) => seconds.every((lap) => lap[i] == null))) {
    return RealisticTheoreticalBest(unavailableReason: realisticIncompleteCoverage);
  }
  if (!population.any((lap) => [...lap.entrySpeeds, ...lap.exitSpeeds].any((v) => v != null))) {
    return RealisticTheoreticalBest(unavailableReason: realisticNoSpeed);
  }

  final (:meets, :closes) = segmentsMeet(segments);
  final quickest = quickestJoinedChain(
    seconds: seconds,
    entrySpeeds: [for (final lap in population) lap.entrySpeeds],
    exitSpeeds: [for (final lap in population) lap.exitSpeeds],
    meets: meets,
    closes: closes,
    cancelled: cancelled,
  );
  if (quickest == null) return RealisticTheoreticalBest(unavailableReason: realisticNoJoin);
  final (total: total, laps: chosen) = quickest;
  double? joinAt(int i) {
    // The join into segment i from the one before it (for the first, the
    // last when the lap closes there).
    final before = i == 0 ? count - 1 : i - 1;
    final met = i == 0 ? closes : meets[before];
    if (!met || chosen[before] == chosen[i]) return null;
    return (population[chosen[before]].exitSpeeds[before]! - population[chosen[i]].entrySpeeds[i]!)
        .abs();
  }

  return RealisticTheoreticalBest(
    totalSeconds: total,
    segments: [
      for (var i = 0; i < count; ++i)
        RealisticSegment(
          segmentId: ids[i],
          seconds: seconds[chosen[i]][i]!,
          lapReference: population[chosen[i]].times.lapReference,
          joinMetresPerSecond: joinAt(i),
        ),
    ],
  );
}

/// Whether speeds [out] (leaving one stretch) and [into] (entering the next),
/// both in m/s, join: both known and at most [realisticJoinMetresPerSecond]
/// apart.
bool speedsJoin(double? out, double? into) =>
    out != null && into != null && (out - into).abs() <= realisticJoinMetresPerSecond;

/// Where consecutive [segments] (approved, in order) meet: [meets] has one
/// entry per pair (segment i ends within [realisticJoinGapMeters] of where
/// i + 1 starts), and [closes] says the last runs across the gate and ends
/// where the first starts. The same on every lap.
({List<bool> meets, bool closes}) segmentsMeet(List<Map<String, Object?>> segments) {
  final count = segments.length;
  double? bound(int i, String key) => switch (segments[i][key]) {
    final num value when value.isFinite => value.toDouble(),
    _ => null,
  };
  bool near(double? a, double? b) =>
      a != null && b != null && (a - b).abs() <= realisticJoinGapMeters;
  final meets = [
    for (var i = 0; i + 1 < count; ++i)
      near(bound(i, 'endProgressMeters'), bound(i + 1, 'startProgressMeters')),
  ];
  if (count < 2) return (meets: meets, closes: false);
  final lastStart = bound(count - 1, 'startProgressMeters');
  final lastEnd = bound(count - 1, 'endProgressMeters');
  final closes =
      lastStart != null &&
      lastEnd != null &&
      lastEnd < lastStart &&
      near(lastEnd, bound(0, 'startProgressMeters'));
  return (meets: meets, closes: closes);
}

/// The quickest chain through consecutive stretches, each taken from one
/// lap, in which wherever two different laps meet ([meets] between stretch
/// i and i + 1; with [closes], also from the last to the first) they
/// [speedsJoin]. [seconds], [entrySpeeds] and [exitSpeeds] are by lap, then
/// by stretch (m/s; null where not timed or not recorded). Returns the
/// total and the lap of each stretch, or null when no chain joins.
({double total, List<int> laps})? quickestJoinedChain({
  required List<List<double?>> seconds,
  required List<List<double?>> entrySpeeds,
  required List<List<double?>> exitSpeeds,
  required List<bool> meets,
  required bool closes,
  CancellationCheck? cancelled,
}) {
  final laps = seconds.length;
  if (laps == 0) return null;
  final count = seconds.first.length;
  if (count == 0) return null;

  // Whether lap j leaving stretch i joins lap k entering the next.
  bool joins(int j, int k, int i) =>
      j == k || speedsJoin(exitSpeeds[j][i], entrySpeeds[k][(i + 1) % count]);

  // The quickest chain with stretch 0 from [first] (any lap when null): its
  // total and the lap of each stretch.
  (double, List<int>)? chain(int? first) {
    final best = [for (var k = 0; k < laps; ++k) List<double?>.filled(count, null)];
    final from = [for (var k = 0; k < laps; ++k) List<int>.filled(count, -1)];
    for (var k = 0; k < laps; ++k) {
      if (first == null || first == k) best[k][0] = seconds[k][0];
    }
    for (var i = 1; i < count; ++i) {
      for (var k = 0; k < laps; ++k) {
        final time = seconds[k][i];
        if (time == null) continue;
        double? quickest;
        var source = -1;
        for (var j = 0; j < laps; ++j) {
          final before = best[j][i - 1];
          if (before == null || (meets[i - 1] && !joins(j, k, i - 1))) continue;
          if (quickest == null || before < quickest) {
            quickest = before;
            source = j;
          }
        }
        if (quickest != null) {
          best[k][i] = quickest + time;
          from[k][i] = source;
        }
      }
    }
    var last = -1;
    for (var k = 0; k < laps; ++k) {
      final total = best[k][count - 1];
      if (total == null || (closes && first != null && !joins(k, first, count - 1))) continue;
      if (last < 0 || total < best[last][count - 1]!) last = k;
    }
    if (last < 0) return null;
    final chosen = List<int>.filled(count, -1);
    for (var i = count - 1, k = last; i >= 0; k = from[k][i], --i) {
      chosen[i] = k;
    }
    return (best[last][count - 1]!, chosen);
  }

  (double, List<int>)? quickest;
  for (final first in closes ? [for (var k = 0; k < laps; ++k) k] : [null]) {
    throwIfCancelled(cancelled);
    final found = chain(first);
    if (found != null && (quickest == null || found.$1 < quickest.$1)) quickest = found;
  }
  return quickest == null ? null : (total: quickest.$1, laps: quickest.$2);
}

SectorTime? _sector(RealisticLapInput lap, String id) {
  for (final candidate in lap.times.sectors) {
    if (candidate.segmentId == id) return candidate;
  }
  return null;
}

/// The repeatable theoretical best: the sum of each segment's quickest
/// typical (median) time in one session ([SectionProgressionRow.fastestTypical]),
/// what the driver did through each segment as a rule in their best session
/// for it; null when a segment has no session with three laps through it.
double? repeatableTheoreticalBest(SectionProgression sections) {
  if (sections.segments.isEmpty) return null;
  var total = 0.0;
  for (final row in sections.segments) {
    final typical = row.fastestTypical;
    if (typical == null || !typical.isFinite) return null;
    total += typical;
  }
  return total;
}
