// A session in 30 seconds (FET-233, idea 18 of FET-217): its best lap
// against the day's earlier sessions, how repeatable its laps were against
// the session before, its biggest gain and loss and the biggest gap left to
// the quickest typical time of the day, the car's hottest temperatures and how the coach's goal
// went. Nothing is recalculated here: every number comes from results the
// day already computed (progression, section progression, coach, channel
// summaries).
import '../analysis/consistency.dart';
import '../analysis/outing_results.dart';
import 'car_watch.dart';
import 'day_channel_summaries.dart';
import 'day_coach.dart';
import 'day_laps.dart';
import 'day_progression.dart';

/// A change in a segment's typical time smaller than this, in seconds, is
/// not reported as a gain, a loss or a gap: it is within what a few laps
/// vary by.
const double sessionSummaryChangeSeconds = 0.05;

/// One segment's typical time in the session, against another.
final class SessionSegmentChange {
  const SessionSegmentChange({
    required this.segmentId,
    required this.name,
    required this.type,
    required this.seconds,
    required this.referenceSeconds,
  });

  final String segmentId;
  final String name;
  final String type;

  /// The session's typical (median) time through the segment.
  final double seconds;

  /// What it is compared with: the session before's typical time, or for
  /// the biggest gap left the quickest typical time of any session there.
  final double referenceSeconds;

  /// [seconds] − [referenceSeconds]: negative is quicker.
  double get deltaSeconds => seconds - referenceSeconds;
}

/// The hottest a recorded temperature got in the session, and in the
/// session before.
final class SessionTemperature {
  const SessionTemperature({
    required this.channel,
    required this.unit,
    required this.maximum,
    this.previousMaximum,
  });

  final String channel;

  /// As the recording declares it ("" when undeclared).
  final String unit;
  final double maximum;

  /// Null when the session before did not record it, or recorded it in
  /// another unit.
  final double? previousMaximum;
}

/// One session of a day in a few lines.
final class SessionSummary {
  SessionSummary({
    required this.runId,
    required this.runName,
    this.earlierSessions = 0,
    this.previousRunName,
    this.eligibleLapCount = 0,
    this.bestLap,
    this.earlierBestLap,
    this.lapSpread,
    this.previousLapSpread,
    this.segmentsCompared = 0,
    this.segmentsTimed = 0,
    this.sessionsTimed = 0,
    this.biggestGain,
    this.biggestLoss,
    this.biggestGap,
    List<SessionTemperature> temperatures = const [],
    this.temperatureReason = '',
    this.carWatch,
    this.goal,
  }) : temperatures = List.unmodifiable(temperatures);

  final String runId;
  final String runName;

  /// How many sessions of the group are listed before it.
  final int earlierSessions;

  /// The nearest session listed before it that has a ranked lap: what its
  /// spread, gains and losses are compared with. Null when none has.
  final String? previousRunName;

  /// Its laps the ranking counts.
  final int eligibleLapCount;

  /// Its best lap; null when none is eligible.
  final DayLapRow? bestLap;

  /// The quickest best lap of every other session of the group (listed
  /// before it or, without a recording clock, after it); null when none
  /// has one.
  final DayLapRow? earlierBestLap;

  /// Its lap times' interquartile range, and the session before's; null
  /// below [minimumConsistencySamples] eligible laps.
  final double? lapSpread, previousLapSpread;

  /// Segments with a typical time in both sessions.
  final int segmentsCompared;

  /// Segments with a typical time in this session.
  final int segmentsTimed;

  /// Sessions with laps timed through the segments.
  final int sessionsTimed;

  /// The segment whose typical time fell the most since the session
  /// before, and the one that rose the most; null when none moved by
  /// [sessionSummaryChangeSeconds] or more.
  final SessionSegmentChange? biggestGain, biggestLoss;

  /// The segment where its typical time is furthest above the quickest
  /// typical time of any session there, by [sessionSummaryChangeSeconds]
  /// or more; null when it has no typical time anywhere ([segmentsTimed]
  /// 0) or is within that of the quickest everywhere.
  final SessionSegmentChange? biggestGap;

  /// Each recorded temperature's maximum, in the day's channel order.
  final List<SessionTemperature> temperatures;

  /// Why there are no temperatures although the channel summaries are
  /// there: their calculation failed, or this session's recording could not
  /// be read (the summaries' own reason). Empty otherwise.
  final String temperatureReason;

  /// What the car did over its timed laps ([carWatch]); null while the
  /// channel summaries are not ready, or when its recording could not be
  /// read.
  final CarWatch? carWatch;

  /// How it did on the main focus the coach gave after the session before;
  /// null when the coach gave none or has not coached this session.
  final CoachGoalCheck? goal;

  bool get firstSession => earlierSessions == 0;

  /// Its best lap is quicker than every other session's, by at least a
  /// millisecond as times are shown.
  bool get newBest => (bestDeltaSeconds ?? 0) < 0;

  /// Its best lap minus the other sessions' best, rounded to the
  /// millisecond as times are shown: negative is quicker, 0 a tie.
  double? get bestDeltaSeconds {
    final best = bestLap, earlier = earlierBestLap;
    if (best == null || earlier == null) return null;
    return ((best.durationSeconds - earlier.durationSeconds) * 1000).round() / 1000;
  }
}

/// The summary of run [runId] of [progression]; null when the progression
/// does not list it. [sections] are the theoretical best's section
/// progression in the same order (null while it is calculated), [coach]
/// the coach's result and [channels] the day's channel summaries (each null
/// while not ready).
SessionSummary? summarizeSession(
  String runId, {
  required DayProgression progression,
  SectionProgression? sections,
  DayCoach? coach,
  DayChannelSummaries? channels,
}) {
  final index = progression.runs.indexWhere((run) => run.runId == runId);
  if (index < 0) return null;
  final run = progression.runs[index];
  ProgressionRun? previous;
  for (final earlier in progression.runs.take(index)) {
    if (earlier.state == ProgressionRunState.available) previous = earlier;
  }

  DayLapRow? earlierBest;
  for (final earlier in progression.runs) {
    if (earlier.runId == runId) continue;
    final best = earlier.bestLap;
    if (best != null &&
        (earlierBest == null || best.durationSeconds < earlierBest.durationSeconds)) {
      earlierBest = best;
    }
  }

  double? spread(ProgressionRun? run) {
    final distribution = run?.distribution;
    if (run == null || distribution == null) return null;
    if (run.eligibleLapCount < minimumConsistencySamples) return null;
    return distribution.q3 - distribution.q1;
  }

  var compared = 0, typical = 0;
  SessionSegmentChange? gain, loss, gap;
  if (sections != null) {
    final now = sections.sessions.indexWhere((session) => session.runId == runId);
    final previousId = previous?.runId;
    final before = previousId == null
        ? -1
        : sections.sessions.indexWhere((session) => session.runId == previousId);
    if (now >= 0) {
      for (final row in sections.segments) {
        final cell = row.cells[now].summary;
        if (!cell.available) continue;
        SessionSegmentChange against(double reference) => SessionSegmentChange(
          segmentId: row.segmentId,
          name: row.name,
          type: row.type,
          seconds: cell.median!,
          referenceSeconds: reference,
        );
        typical++;
        final fastest = row.fastestTypical;
        if (fastest != null) {
          final candidate = against(fastest);
          if (candidate.deltaSeconds >= sessionSummaryChangeSeconds &&
              (gap == null || candidate.deltaSeconds > gap.deltaSeconds)) {
            gap = candidate;
          }
        }
        if (before < 0) continue;
        final earlier = row.cells[before].summary;
        if (!earlier.available) continue;
        compared++;
        final change = against(earlier.median!);
        if (change.deltaSeconds <= -sessionSummaryChangeSeconds &&
            (gain == null || change.deltaSeconds < gain.deltaSeconds)) {
          gain = change;
        }
        if (change.deltaSeconds >= sessionSummaryChangeSeconds &&
            (loss == null || change.deltaSeconds > loss.deltaSeconds)) {
          loss = change;
        }
      }
    }
  }

  final temperatures = <SessionTemperature>[];
  var temperatureReason = '';
  CarWatch? watch;
  if (channels != null && channels.error.isNotEmpty) {
    temperatureReason = channels.error;
  } else if (channels != null) {
    RunChannelSummaries? of(String? id) {
      if (id == null) return null;
      for (final summaries in channels.runs) {
        if (summaries.runId == id) return summaries;
      }
      return null;
    }

    final own = of(runId), before = of(previous?.runId);
    if (own != null) watch = carWatch(own);
    if (own != null && own.unavailableReason.isNotEmpty) {
      temperatureReason = own.unavailableReason;
    }
    for (final name in channels.temperatureChannels) {
      final channel = own?.channel(name);
      final maximum = channel?.run.maximum;
      if (channel == null || maximum == null || !channel.run.valid) continue;
      final earlierChannel = before?.channel(name);
      final earlier = earlierChannel?.run;
      temperatures.add(
        SessionTemperature(
          channel: name,
          unit: channel.unit,
          maximum: maximum,
          previousMaximum:
              earlier != null && earlier.valid && _sameUnit(earlierChannel!.unit, channel.unit)
              ? earlier.maximum
              : null,
        ),
      );
    }
  }

  return SessionSummary(
    runId: runId,
    runName: run.runName,
    earlierSessions: index,
    previousRunName: previous?.runName,
    eligibleLapCount: run.eligibleLapCount,
    bestLap: run.bestLap,
    earlierBestLap: earlierBest,
    lapSpread: spread(run),
    previousLapSpread: spread(previous),
    segmentsCompared: compared,
    segmentsTimed: typical,
    sessionsTimed: sections?.sessions.length ?? 0,
    biggestGain: gain,
    biggestLoss: loss,
    biggestGap: gap,
    temperatures: temperatures,
    temperatureReason: temperatureReason,
    carWatch: watch,
    goal: coach != null && coach.runId == runId ? coach.goal : null,
  );
}

// Whether two declared temperature units are the same: "C", "°C" and "degC"
// are one unit; an undeclared unit only matches another undeclared one.
bool _sameUnit(String a, String b) {
  String normal(String unit) => switch (unit.trim()) {
    'C' || 'c' || '°C' || 'degC' => '°C',
    'F' || 'f' || '°F' || 'degF' => '°F',
    final other => other,
  };
  return normal(a) == normal(b);
}
