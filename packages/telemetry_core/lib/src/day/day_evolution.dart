// How lap times move through each session of a group (FET-227): every timed
// lap by its number and the time since the session's first timed lap began,
// the first lap in the session's middle half of lap times or quicker (and
// whether later laps kept getting quicker), and each session against the one
// listed before it at the same lap numbers. Laps are the ranking's: a lap
// the ranking leaves out is listed with its reasons but never measured.
//
// These are observations in recording order only. Tyre temperature, the
// track rubbering in, fuel, traffic and the driver learning the track all
// change together through a session and a day, so nothing here tells them
// apart; no track temperature is recorded.
import '../analysis/consistency.dart';
import '../operation.dart';
import 'compatibility.dart';
import 'day_analysis.dart';
import 'day_laps.dart';
import 'day_progression.dart';
import 'day_ranking.dart';

/// One timed lap of a session.
final class EvolutionLap {
  EvolutionLap({
    required this.row,
    required this.secondsSinceFirstLap,
    required this.eligible,
    List<LapIssue> issues = const [],
    this.userReason = '',
    this.atPace = false,
  }) : issues = List.unmodifiable(issues);

  final DayLapRow row;

  /// The lap's start minus the start of the session's first timed lap. Not
  /// from the recording's start: a recording can begin in the paddock, long
  /// before the car leaves the pits.
  final double secondsSinceFirstLap;

  /// Ranked; a lap that is not is listed but not measured.
  final bool eligible;

  /// Why the ranking leaves it out; empty when [eligible].
  final List<LapIssue> issues;

  /// The reason the user gave when they excluded the lap.
  final String userReason;

  /// Eligible and no slower than the session's [SessionEvolution.paceLimitSeconds].
  final bool atPace;

  int get lapNumber => row.lapNumber;
  double get seconds => row.durationSeconds;
}

/// One session of the group.
final class SessionEvolution {
  SessionEvolution({
    required this.run,
    List<EvolutionLap> laps = const [],
    this.typicalSeconds,
    this.paceLimitSeconds,
    this.paceLapNumber,
    this.lapsBeforePace = 0,
    this.notCountedBeforePace = 0,
    this.quickerLaterLap,
    this.previousRunId,
    this.previousRunName,
    this.sameLapsCount = 0,
    this.sameLapsDeltaSeconds,
  }) : laps = List.unmodifiable(laps);

  /// The session as the progression lists it.
  final ProgressionRun run;

  /// Its timed laps in recording order.
  final List<EvolutionLap> laps;

  /// The median of its eligible laps, with at least [minimumConsistencySamples].
  final double? typicalSeconds;

  /// The slow edge of the middle half of its eligible laps (the upper
  /// quartile). Null below [minimumConsistencySamples] eligible laps.
  final double? paceLimitSeconds;

  /// The first eligible lap in the middle half of the session's laps or
  /// quicker (no slower than [paceLimitSeconds]). Not the session's full
  /// pace when later laps kept getting quicker ([quickerLaterLap]).
  final int? paceLapNumber;

  /// Timed laps before [paceLapNumber], those not measured included.
  final int lapsBeforePace;

  /// Of [lapsBeforePace], the laps the ranking leaves out: whether they were
  /// slower is not known.
  final int notCountedBeforePace;

  /// The quickest eligible lap after [paceLapNumber], when it is quicker than
  /// the whole middle half of the session's laps (below the lower
  /// quartile): the session kept getting quicker after that lap.
  final EvolutionLap? quickerLaterLap;

  /// The session listed before it, if any.
  final String? previousRunId, previousRunName;

  /// Lap numbers where both it and the previous session have an eligible lap.
  final int sameLapsCount;

  /// The median of its lap minus the previous session's lap at the same lap
  /// number, with at least [minimumConsistencySamples] such pairs; negative
  /// when it was quicker.
  final double? sameLapsDeltaSeconds;

  String get runId => run.runId;
  String get runName => run.runName;
}

/// The sessions of one group in the progression's order.
final class DayEvolution {
  DayEvolution({
    required this.groupId,
    List<SessionEvolution> sessions = const [],
    this.minimumSeconds,
    this.maximumSeconds,
  }) : sessions = List.unmodifiable(sessions);

  final String? groupId;
  final List<SessionEvolution> sessions;

  /// The quickest and slowest eligible lap of any session: a shared scale.
  final double? minimumSeconds, maximumSeconds;

  /// The highest lap number of any session, 0 without laps.
  int get maximumLapNumber {
    var highest = 0;
    for (final session in sessions) {
      for (final lap in session.laps) {
        if (lap.lapNumber > highest) highest = lap.lapNumber;
      }
    }
    return highest;
  }

  /// Whether any session has a timed lap.
  bool get hasLaps => sessions.any((session) => session.laps.isNotEmpty);
}

/// The evolution of [progression]'s sessions over the day's [rows], with
/// [ranking] (the same group) deciding which laps are measured.
DayEvolution summarizeDayEvolution(
  List<DayLapRow> rows,
  DayRanking ranking,
  DayProgression progression,
) {
  if (rows.length > maximumDayLapRows || progression.runs.length > 64) {
    throw const ResourceLimitError('Too many runs or lap sections for evolution.');
  }
  final group = progression.groupId;
  if (group == null || group != ranking.groupId) return DayEvolution(groupId: group);
  final listed = {for (final run in progression.runs) run.runId};
  final laps = <String, List<DayLapRow>>{};
  for (final row in rows) {
    if (!listed.contains(row.runId)) continue;
    if (row.type == LapSectionType.lap) (laps[row.runId] ??= []).add(row);
  }
  final eligible = {for (final row in ranking.eligibleLaps) row.reference};
  final sessions = <SessionEvolution>[];
  double? minimum, maximum;
  SessionEvolution? previous;
  for (final run in progression.runs) {
    final excluded = {for (final lap in run.excludedLaps) lap.row.reference: lap};
    final timed = (laps[run.runId] ?? <DayLapRow>[])
      ..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));
    // The ranking's quartiles of the run's eligible laps.
    final distribution = run.eligibleLapCount >= minimumConsistencySamples
        ? run.distribution
        : null;
    final limit = distribution?.q3;
    final firstLap = timed.isEmpty ? 0.0 : timed.first.start;
    final evolutionLaps = <EvolutionLap>[];
    int? paceLap;
    var before = 0, notCounted = 0;
    for (final row in timed) {
      final measured = eligible.contains(row.reference);
      final atPace = measured && limit != null && row.durationSeconds <= limit;
      if (measured) {
        final seconds = row.durationSeconds;
        if (minimum == null || seconds < minimum) minimum = seconds;
        if (maximum == null || seconds > maximum) maximum = seconds;
      }
      if (limit != null && paceLap == null) {
        if (atPace) {
          paceLap = row.lapNumber;
        } else {
          ++before;
          if (!measured) ++notCounted;
        }
      }
      evolutionLaps.add(
        EvolutionLap(
          row: row,
          secondsSinceFirstLap: row.start - firstLap,
          eligible: measured,
          issues: measured ? const [] : (excluded[row.reference]?.issues ?? const []),
          userReason: measured ? '' : (excluded[row.reference]?.userReason ?? ''),
          atPace: atPace,
        ),
      );
    }
    EvolutionLap? quicker;
    if (paceLap != null && distribution != null) {
      var after = false;
      for (final lap in evolutionLaps) {
        if (after &&
            lap.eligible &&
            lap.seconds < distribution.q1 &&
            (quicker == null || lap.seconds < quicker.seconds)) {
          quicker = lap;
        }
        if (lap.lapNumber == paceLap && lap.eligible) after = true;
      }
    }
    var pairs = 0;
    double? sameLaps;
    if (previous != null) {
      final earlier = {
        for (final lap in previous.laps)
          if (lap.eligible) lap.lapNumber: lap.seconds,
      };
      final differences = [
        for (final lap in evolutionLaps)
          if (lap.eligible && earlier[lap.lapNumber] != null) lap.seconds - earlier[lap.lapNumber]!,
      ];
      pairs = differences.length;
      sameLaps = summarizeConsistency(differences).median;
    }
    final session = SessionEvolution(
      run: run,
      laps: evolutionLaps,
      typicalSeconds: distribution?.median,
      paceLimitSeconds: limit,
      paceLapNumber: paceLap,
      lapsBeforePace: paceLap == null ? 0 : before,
      notCountedBeforePace: paceLap == null ? 0 : notCounted,
      quickerLaterLap: quicker,
      previousRunId: previous?.runId,
      previousRunName: previous?.runName,
      sameLapsCount: pairs,
      sameLapsDeltaSeconds: sameLaps,
    );
    sessions.add(session);
    previous = session;
  }
  return DayEvolution(
    groupId: group,
    sessions: sessions,
    minimumSeconds: minimum,
    maximumSeconds: maximum,
  );
}

/// [summarizeDayEvolution] of [progression]'s group in [analysis].
DayEvolution dayEvolution(DayAnalysis analysis, DayProgression progression) {
  final id = progression.groupId;
  for (final group in analysis.groups) {
    if (group.id == id && group.resolved) {
      if (group.ranking case final ranking?) {
        return summarizeDayEvolution(analysis.rows, ranking, progression);
      }
    }
  }
  return DayEvolution(groupId: id);
}
