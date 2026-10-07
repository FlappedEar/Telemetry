// A theoretical best whose segments join (FET-222, idea 6 of FET-217). The
// raw theoretical best takes each segment's fastest time from any lap, so a
// corner may be taken from a lap that entered it 15 km/h faster than the lap
// the straight before came from. A car cannot change speed at a line: here
// the fastest combination is chosen in which, wherever two laps meet, the
// speed leaving one segment and the speed entering the next differ by at
// most [realisticJoinMetresPerSecond]. Segments of one lap always join. The
// lap's own start, at the timing gate, is not joined to its end.
//
// Beside it, the repeatable theoretical best: the sum of each segment's
// quickest typical (median) time in one session, what the laps did through
// each segment as a rule rather than once.
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
  /// where the same lap continues, or for the first segment.
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
  List<RealisticLapInput> laps,
) {
  final ids = [
    for (final segment in approved.segments) segment['id'] is String ? segment['id'] as String : '',
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
  // Each lap's time and bounds through each segment, by approved order.
  SectorTime? sector(RealisticLapInput lap, int index) {
    for (final candidate in lap.times.sectors) {
      if (candidate.segmentId == ids[index]) return candidate;
    }
    return null;
  }

  final seconds = [
    for (final lap in population)
      [
        for (var i = 0; i < ids.length; ++i)
          if (sector(lap, i)?.seconds case final time? when time.isFinite) time else null,
      ],
  ];
  // Whether segment i ends where segment i + 1 starts, from any lap's bounds
  // (they are the approved segments', the same on every lap).
  final meets = List<bool>.filled(ids.length, false);
  for (var i = 0; i + 1 < ids.length; ++i) {
    for (final lap in population) {
      final a = sector(lap, i), b = sector(lap, i + 1);
      if (a == null || b == null) continue;
      meets[i] = (a.endProgressMeters - b.startProgressMeters).abs() <= realisticJoinGapMeters;
      break;
    }
  }
  if (!population.any((lap) => lap.entrySpeeds.any((v) => v != null))) {
    return RealisticTheoreticalBest(unavailableReason: realisticNoSpeed);
  }

  // The fastest time to the end of segment i finishing on lap k, and the lap
  // segment i - 1 came from.
  final best = [for (final _ in population) List<double?>.filled(ids.length, null)];
  final from = [for (final _ in population) List<int>.filled(ids.length, -1)];
  for (var k = 0; k < population.length; ++k) {
    best[k][0] = seconds[k][0];
  }
  for (var i = 1; i < ids.length; ++i) {
    for (var k = 0; k < population.length; ++k) {
      final time = seconds[k][i];
      if (time == null) continue;
      double? quickest;
      var source = -1;
      for (var j = 0; j < population.length; ++j) {
        final before = best[j][i - 1];
        if (before == null) continue;
        if (j != k && meets[i - 1]) {
          final out = population[j].exitSpeeds[i - 1], into = population[k].entrySpeeds[i];
          if (out == null || into == null || (out - into).abs() > realisticJoinMetresPerSecond) {
            continue;
          }
        }
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
  for (var k = 0; k < population.length; ++k) {
    final total = best[k][ids.length - 1];
    if (total != null && (last < 0 || total < best[last][ids.length - 1]!)) last = k;
  }
  if (last < 0) return RealisticTheoreticalBest(unavailableReason: realisticIncompleteCoverage);
  final chosen = List<int>.filled(ids.length, -1);
  for (var i = ids.length - 1, k = last; i >= 0; k = from[k][i], --i) {
    chosen[i] = k;
  }
  return RealisticTheoreticalBest(
    totalSeconds: best[last][ids.length - 1],
    segments: [
      for (var i = 0; i < ids.length; ++i)
        RealisticSegment(
          segmentId: ids[i],
          seconds: seconds[chosen[i]][i]!,
          lapReference: population[chosen[i]].times.lapReference,
          joinMetresPerSecond: i == 0 || chosen[i] == chosen[i - 1] || !meets[i - 1]
              ? null
              : (population[chosen[i - 1]].exitSpeeds[i - 1]! -
                        population[chosen[i]].entrySpeeds[i]!)
                    .abs(),
        ),
    ],
  );
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
