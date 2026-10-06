// The coach between sessions (FET-45): what to try in the next session,
// from the latest session's laps against the faster laps of the whole day.
//
// The rules, thresholds, confidence and plan are FlappedEar DrivingCoach's
// (docs/analysis-model.md, lib/core/analysis/opportunity_detector.dart and
// coaching_planner.dart at revision 7e21642). They are measured here on this
// app's own laps, track-progress axis and approved segments: DrivingCoach's
// parser, lap detector, distance normalizer and segmenter are not used.
//
// Where the measurements differ from DrivingCoach's:
// - Segments are the group's approved segments (corners only), so the lift,
//   braking and coasting of a corner are looked for from
//   [coachApproachMeters] before its entry to its exit.
// - Minimum and exit speed, the braking point and the throttle pickup are the
//   Corner Analyzer's ([DayCorner]); exit speed is the speed at the exit, not
//   a 10 m median.
// - Coasting is this app's measured coasting (both pedals recorded, see
//   driving_states.dart), which does not check longitudinal G; the
//   confidence is lowered as DrivingCoach lowers it without G coverage.
// - Patterns are looked for on every lap of the day so far, so one repeated
//   across sessions counts (owner's choice, 2026-10-04); the session coached
//   must still show it on at least half of its laps through the segment, and
//   its own laps give the values reported. References come from every
//   eligible lap of the group.
//
// A finding is a pattern that suggests an opportunity, never a promised
// gain: estimated time loss stays unknown, as in DrivingCoach.
import 'dart:math' as math;

import '../analysis/braking_onset.dart'
    show
        brakingAlreadyActive,
        brakingFollowsGap,
        brakingInterruptedByGap,
        brakingTruncatedAtWindowEnd;
import '../analysis/braking_source.dart' show brakingSourceQuality;
import '../analysis/coasting_analysis.dart';
import '../analysis/gg_pairs.dart' show buildGgPairs, ggMagnitude;
import '../analysis/corner_speeds.dart' show CornerSpeeds;
import '../analysis/driving_states.dart' show DrivingStateInterval, drivingStateMeasured;
import '../analysis/exit_metrics.dart' show exitFollowsGap, exitTruncated;
import '../analysis/outing_theoretical_best.dart' show OutingRun;
import '../operation.dart';
import '../analysis/track_progress.dart';
import '../speed_units.dart';
import '../telemetry_session.dart';
import 'day_analysis.dart';
import 'day_corners.dart';
import 'day_laps.dart';
import 'day_theoretical_best.dart';

const String dayCoachAlgorithm = 'coach-v1';

/// How far before a corner's entry its lift, braking and coasting are
/// looked for.
const double coachApproachMeters = 150.0;

/// Only findings this confident enter the plan.
const double coachPlanConfidence = 0.65;

/// A lap this much slower than its session's typical lap (the median, with
/// at least three laps) is not read for a pattern: traffic, a cool-down or a
/// warm-up lap says little about technique. It can still be a faster lap
/// for another.
const double coachSlowLapRatio = 1.05;

/// Throttle below this share of its travel is off for the coach's coasting:
/// a stretch held at light throttle (the driving states' coasting ends only
/// above 15 %) is not coasting.
const double coachThrottleOff = 0.03;

/// How far apart a session's braking points at a corner must be, and how
/// much farther apart than the day's three fastest laps', for the coach to
/// suggest braking at one marker.
const double coachBrakingSpreadMeters = 20.0;

/// How far from the session's typical (median) braking point at a corner a
/// lap's braking point is off it; at least two laps must be.
const double coachBrakingOffMeters = 10.0;

/// A braking onset shorter than this is a dab, not where the lap brakes for
/// the corner, and is not read for braking consistency.
const double coachBrakingMinSeconds = 0.5;

/// Onsets that are not a clean start of braking: braking already under way,
/// next to a gap in the data, or cut off by the window.
const _unclearOnset = {
  brakingAlreadyActive,
  brakingFollowsGap,
  brakingInterruptedByGap,
  brakingTruncatedAtWindowEnd,
};

/// A faster lap at most this many seconds faster than the lap compared is
/// preferred as its reference: a lap within reach, not only the day's best.
const double coachReachSeconds = 1.5;

/// Plan items are ranked by time lost in steps of this many seconds; within
/// a step, by how many laps show them (see [dayCoach]'s plan).
const double coachRankSeconds = 0.1;

/// A throttle pickup the car gains this many m/s on before it is released
/// drives out of an earlier apex (see [CoachKind.earlyThrottle]).
const double coachPickupGain = 1.5;

enum CoachKind {
  earlyLift,
  excessiveCoasting,
  lowMinimumSpeed,
  lateThrottle,

  /// The throttle is picked up after the braking, before the slow point,
  /// and released again.
  earlyThrottle,

  /// The session's braking points at a corner are spread out.
  inconsistentBraking,
  improving;

  /// Advice to change something; [improving] says to keep it.
  bool get corrective => this != improving;
}

/// What a [CoachEvidence] measures, for the app to name in its language.
enum CoachMetric {
  liftPoint,
  longestCoast,
  minimumSpeed,
  throttleReturn,
  segmentTime,
  exitSpeed,
  brakingStart,
  coastDistance,
  brakingSpread,

  /// The time through the straight right after the corner: a slow exit
  /// loses time there too.
  nextStraightTime,

  /// The share of a session's laps that pick up the throttle early and lift
  /// again, in percent: the goal check's measure for that focus.
  earlyThrottleShare,

  /// Where the throttle was first picked up after the braking: on a lap
  /// that lifted again before the slow point, against the faster laps'
  /// single pickup.
  firstThrottle,

  /// The mean combined (longitudinal and lateral) G through the corner, in
  /// g: how hard the car was worked there, not a share of the grip
  /// available.
  combinedG,

  /// The highest mean combined G at the corner: of this session's laps
  /// compared, against the day's laps so far (slow laps left out, the
  /// faster laps compared always in).
  highestCombinedG,
}

/// Why the plan is what it is, for the app to say in its language.
enum CoachReason {
  /// The plan has items.
  ready,

  /// The day's segments and sector times are not ready.
  noSegments,

  /// The session coached has no eligible lap in the group compared.
  noLapInGroup,

  /// The group has no approved corner.
  noCorners,

  /// The session coached has no recording to measure (moved or missing).
  noRecording,

  /// No lap of the session coached could be measured through a corner.
  noCornerMeasurements,

  /// No lap of the session coached has a faster lap to compare with.
  noFasterLap,

  /// Neither throttle nor brake is recorded, so only speeds can be compared,
  /// and they show no pattern.
  noPedals,

  /// Faster laps were compared, and they show no pattern.
  noPattern,

  /// A confident pattern was seen, but on fewer than three laps of the day
  /// so far.
  tooFewLaps,

  /// Patterns were found, but none is repeated and confident enough.
  belowThreshold,

  /// Patterns seen earlier today are not repeated on at least half of the
  /// session coached's laps compared (which do have faster laps).
  notInSession,
}

/// One measured comparison behind a finding.
final class CoachEvidence {
  CoachEvidence({
    required this.key,
    required this.metric,
    required this.observed,
    required this.reference,
    required this.unit,
    required List<DayLapRow> referenceLaps,
    required this.detail,
  }) : referenceLaps = List.unmodifiable(referenceLaps);

  final CoachMetric key;

  /// "Minimum speed", "Throttle return"... (English; the app maps [key]).
  final String metric;

  /// The median over the session coached's affected laps (the value
  /// itself for one lap).
  final double observed;

  /// The median over the faster laps (for [CoachKind.improving], the first
  /// of the improving laps).
  final double reference;
  final String unit;
  final List<DayLapRow> referenceLaps;

  /// What was measured and how.
  final String detail;
}

/// A pattern in one segment that suggests an opportunity, or an
/// improvement to keep.
final class CoachFinding {
  CoachFinding({
    required this.kind,
    required this.segmentId,
    required this.segmentName,
    required this.confidence,
    required List<CoachEvidence> evidence,
    required List<DayLapRow> affectedLaps,
    List<DayLapRow>? sessionLaps,
  }) : evidence = List.unmodifiable(evidence),
       affectedLaps = List.unmodifiable(affectedLaps),
       sessionLaps = List.unmodifiable(sessionLaps ?? affectedLaps);

  final CoachKind kind;
  final String segmentId;
  final String segmentName;

  /// A conservative support score from 0 to 0.9, not a probability.
  final double confidence;

  /// The first item is the pattern itself; then the segment time, the exit
  /// speed and, depending on [kind], the braking start or coasting distance.
  final List<CoachEvidence> evidence;

  /// Every lap of the day so far showing the pattern, in recording order,
  /// the session coached's among them.
  final List<DayLapRow> affectedLaps;

  /// The session coached's laps among [affectedLaps]: the laps the values
  /// reported come from.
  final List<DayLapRow> sessionLaps;

  bool get repeated => affectedLaps.length >= 2;

  /// What to try, without prescribing an exact point.
  String get action => switch (kind) {
    CoachKind.earlyLift =>
      'Try a slightly later lift within the approach you have already repeated '
          'successfully. Keep the braking point unchanged.',
    CoachKind.excessiveCoasting =>
      'Reduce the gap with neither pedal engaged. Focus on smoother pedal '
          'transitions. Keep the braking point unchanged.',
    CoachKind.lowMinimumSpeed =>
      'Repeat the line and approach from your faster laps, aiming for a '
          'smoother minimum-speed phase. Keep the exit as your check.',
    CoachKind.lateThrottle =>
      'Work toward a smooth, slightly earlier throttle return after the slow '
          'point, using your faster laps as a reference.',
    CoachKind.earlyThrottle =>
      'Wait to pick up the throttle until you can keep it on: one smooth '
          'pickup from the slow point, as on your faster laps.',
    CoachKind.inconsistentBraking =>
      'Pick one braking marker and brake at it every lap. Move it only once you '
          'hit it consistently.',
    CoachKind.improving =>
      'Keep the approach from your latest laps. Repeat it before making '
          'another change.',
  };
}

/// One item of the plan for the next session.
final class CoachItem {
  const CoachItem(this.finding);

  final CoachFinding finding;

  /// "Turn 3 — Reduce coasting".
  String get title {
    final label = switch (finding.kind) {
      CoachKind.earlyLift => 'Try a later lift',
      CoachKind.excessiveCoasting => 'Reduce coasting',
      CoachKind.lowMinimumSpeed => 'Keep more speed through the slow point',
      CoachKind.lateThrottle => 'Return to throttle sooner',
      CoachKind.earlyThrottle => 'Pick up the throttle once',
      CoachKind.inconsistentBraking => 'Brake at the same point every lap',
      CoachKind.improving => 'Keep current approach',
    };
    return '${finding.segmentName} — $label';
  }

  /// The measured pattern in one sentence.
  String get explanation {
    final metric = finding.evidence.first;
    String value(double v) => '${v.toStringAsFixed(1)} ${metric.unit}';
    if (finding.kind == CoachKind.improving) {
      return '${metric.metric} improved across three consecutive laps, from '
          '${value(metric.reference)} to ${value(metric.observed)}, with no '
          'material exit-speed penalty.';
    }
    return 'Your ${finding.repeated ? 'repeated' : 'single-lap'} pattern suggests an '
        'opportunity: ${metric.metric.toLowerCase()} was ${value(metric.observed)}, '
        'compared with ${value(metric.reference)} on '
        '${metric.referenceLaps.length == 1 ? 'your faster lap' : 'faster laps'}.';
  }

  String get action => finding.action;
}

/// How a session did on the main focus of the session before it.
enum CoachGoalOutcome {
  /// Better than in the session before.
  better,

  /// About the same as in the session before.
  unchanged,

  /// Worse than in the session before.
  worse,

  /// Fewer than two laps (three for the braking range) of either session
  /// have the measure at that segment.
  notMeasured,
}

/// The main focus the coach gave after the session before ([runName]),
/// measured again on the session coached: the median across each session's
/// laps at that segment (the braking range for the braking marker), slow
/// laps left out. Observed, not proof the advice caused it.
final class CoachGoalCheck {
  const CoachGoalCheck({
    required this.runId,
    required this.runName,
    required this.finding,
    required this.outcome,
    this.measuredName = '',
    this.before,
    this.now,
    this.beforeLaps = 0,
    this.nowLaps = 0,
  });

  /// The session before, whose main focus this is.
  final String runId;
  final String runName;

  /// That focus, as the coach gives it with the day's laps up to the
  /// session before; its first evidence row names the measure.
  final CoachFinding finding;

  final CoachGoalOutcome outcome;

  /// Today's corner the focus was measured at: the one overlapping it
  /// most, by name; empty when none does.
  final String measuredName;

  /// The measure across the session before's laps, and the session
  /// coached's ([finding]'s first evidence unit); null when not measured.
  final double? before;
  final double? now;
  final int beforeLaps;
  final int nowLaps;

  /// The measure: the focus's own, but for an early throttle the share of
  /// laps picking it up early ([CoachMetric.earlyThrottleShare]).
  CoachMetric get metric => finding.kind == CoachKind.earlyThrottle
      ? CoachMetric.earlyThrottleShare
      : finding.evidence.first.key;
  String get unit => finding.kind == CoachKind.earlyThrottle ? '%' : finding.evidence.first.unit;

  /// In English (the app words it from the fields).
  String get summary {
    final what =
        '${finding.segmentName}, '
        '${finding.kind == CoachKind.earlyThrottle ? 'laps picking up early' : finding.evidence.first.metric.toLowerCase()}';
    if (outcome == CoachGoalOutcome.notMeasured) {
      return 'Focus from $runName ($what): not measured in this session.';
    }
    String value(double v) => unit == 'm' ? '${v.round()} m' : '${v.toStringAsFixed(1)} $unit';
    final verdict = switch (outcome) {
      CoachGoalOutcome.better => 'better',
      CoachGoalOutcome.unchanged => 'about the same',
      CoachGoalOutcome.worse => 'worse',
      CoachGoalOutcome.notMeasured => '',
    };
    return 'Focus from $runName ($what): ${value(before!)} then, ${value(now!)} now: $verdict.';
  }
}

/// The coach's view of one session of a day.
final class DayCoach {
  DayCoach({
    this.runId = '',
    List<CoachFinding> findings = const [],
    List<CoachItem> plan = const [],
    required this.reason,
    this.speedsConverted = false,
    List<DayLapRow> slowLaps = const [],
    this.goal,
    this.previousRunId = '',
    this.speedUnit = 'km/h',
    this.perMetrePerSecond = 3.6,
    List<CoachCornerGoalValues> goalValues = const [],
  }) : findings = List.unmodifiable(findings),
       plan = List.unmodifiable(plan),
       slowLaps = List.unmodifiable(slowLaps),
       goalValues = List.unmodifiable(goalValues);

  /// The session before the one coached, among the group's laps; empty when
  /// there is none. The driver's own goals for the session coached are
  /// stored on it ([RunGoals]).
  final String previousRunId;

  /// The unit [goalValues]' minimum speeds are in, and how many of it make
  /// one metre per second (see [coachGoalOutcome]).
  final String speedUnit;
  final double perMetrePerSecond;

  /// Every corner's goal measures in the session coached and in
  /// [previousRunId], slow laps left out; empty when there is no session
  /// before. What the driver's own goals are checked against
  /// ([checkSessionGoals]).
  final List<CoachCornerGoalValues> goalValues;

  /// The session coached; empty when none could be.
  final String runId;

  /// Whether the speeds reported are converted to km/h because the laps
  /// compared are in different units; the app then does not show them.
  final bool speedsConverted;

  /// Every finding, planned or not.
  final List<CoachFinding> findings;

  /// The day's laps left out of the patterns as much slower than their
  /// session's typical lap ([coachSlowLapRatio]), in recording order.
  final List<DayLapRow> slowLaps;

  /// At most three items: at most two changes, in two different segments,
  /// and one improvement to keep when there is one. The first is the main
  /// focus ([focus]): the first change, or the improvement when there is no
  /// change; the others are for once it feels settled.
  final List<CoachItem> plan;

  /// The one thing to work on first; null when the plan is empty.
  CoachItem? get focus => plan.isEmpty ? null : plan.first;

  /// How the session coached did on the main focus the coach gave for the
  /// session before it; null when there was no such change to work on.
  final CoachGoalCheck? goal;

  final CoachReason reason;

  /// Why the plan is empty, or how to use it (English; the app maps
  /// [reason]).
  String get message => switch (reason) {
    CoachReason.ready => 'Work on the main focus first. Try the others only once it feels settled.',
    CoachReason.noSegments => 'The coach needs the day\'s segments and sector times first.',
    CoachReason.noLapInGroup => 'This session has no timed lap in the group compared.',
    CoachReason.noCorners => 'The group compared has no approved corner.',
    CoachReason.noRecording =>
      'This session\'s recording is not available, so it cannot be coached. Find it '
          'from the day page.',
    CoachReason.noCornerMeasurements =>
      'No lap of this session could be measured through a corner.',
    CoachReason.tooFewLaps =>
      'A pattern was seen on fewer than three laps today, too few to plan from.',
    CoachReason.noPattern =>
      'Compared with your faster laps, no pattern stands out. Keep building '
          'consistent laps.',
    CoachReason.noFasterLap =>
      'No lap of this session has a faster lap of the day to compare with.',
    CoachReason.noPedals =>
      'Throttle and brake are not recorded, so lift, coasting and throttle return '
          'cannot be compared, and the speeds show no repeated pattern.',
    CoachReason.belowThreshold =>
      'No repeated pattern clears the confidence threshold. Repeat a consistent '
          'run to build a stronger comparison.',
    CoachReason.notInSession =>
      'Patterns seen earlier today do not repeat on most of this session\'s laps.',
  };
}

/// A goal's measure across one session's laps at a corner: the median of
/// the lap values (the braking range, the share of laps picking up early)
/// and how many laps had it.
typedef CoachGoalValue = ({double value, int laps});

/// One corner's goal measures, by the kind of change a goal asks for: in
/// the session coached ([now]) and the session before ([before]). A kind
/// is missing where fewer than two laps (three for the braking range) have
/// the measure.
final class CoachCornerGoalValues {
  CoachCornerGoalValues({
    required this.segmentId,
    required this.name,
    required this.startProgressMeters,
    required this.endProgressMeters,
    Map<CoachKind, CoachGoalValue> before = const {},
    Map<CoachKind, CoachGoalValue> now = const {},
  }) : before = Map.unmodifiable(before),
       now = Map.unmodifiable(now);

  final String segmentId;
  final String name;

  /// The corner on the lap's shared axis, metres.
  final double startProgressMeters, endProgressMeters;
  final Map<CoachKind, CoachGoalValue> before, now;
}

/// One lap through one corner, as the rules read it.
final class _Passage {
  _Passage({
    required this.lap,
    required this.order,
    required this.seconds,
    required this.spacing,
    this.minimum,
    this.exit,
    this.lift,
    this.liftSeconds,
    this.braking,
    this.release,
    this.onset,
    this.pickup,
    this.coastSeconds,
    this.coastMeters,
    this.nextSeconds,
    this.throttleKnown = false,
    this.earlyPickup,
    this.combinedG,
  });

  final DayLapRow lap;

  /// Its position among the group's laps in recording order.
  final int order;

  /// Through the segment.
  final double seconds;

  /// Mean source sample spacing in the segment, metres.
  final double spacing;

  /// Metres per second.
  final double? minimum;
  final double? exit;

  /// Positions on the shared axis, metres.
  final double? lift;
  final double? braking;

  /// From [lift] to [braking], seconds; 0 when the pedals overlap.
  final double? liftSeconds;

  /// Where a measured braking ended, when nothing broke it up.
  final double? release;

  /// [braking] when it is a clean, sustained start of braking (see
  /// [_inconsistentBraking]).
  final double? onset;
  final double? pickup;

  /// The longest coast from the approach to the exit.
  final double? coastSeconds;
  final double? coastMeters;

  /// Through the straight right after the segment, when one follows it.
  final double? nextSeconds;

  /// Whether the throttle is known from the end of the braking to the slow
  /// point; then [earlyPickup] is where it was picked up and released
  /// again in between, or null when it was not.
  final bool throttleKnown;
  final double? earlyPickup;

  /// The mean combined G through the segment ([coachCombinedG]).
  final double? combinedG;

  double get lapSeconds => lap.durationSeconds;
}

/// The unit the coach reports speeds in: the one every corner's speeds are
/// in (an unlabelled speed read as km/h), else km/h, [converted]. Speeds are
/// compared in metres per second whatever their units, but not at all when
/// some laps declare a unit and others have none ([comparable]): the
/// unlabelled ones may be in either unit.
typedef _ShownSpeed = ({String unit, double perMetrePerSecond, bool converted, bool comparable});

_ShownSpeed _shownSpeed(List<DayCorner> corners) {
  final units = {
    for (final corner in corners)
      for (final (_, metrics) in corner.laps)
        if (metrics.speeds.valid) metrics.speeds.unit.trim(),
  };
  final keys = {
    for (final unit in units)
      unit.isEmpty
          ? 'km/h'
          : normalizedSpeedUnit(unit).isNotEmpty
          ? normalizedSpeedUnit(unit)
          : unit.toLowerCase(),
  };
  final single = keys.length == 1 ? keys.single : null;
  final unit = single != null && metresPerSecondPerSpeedUnit(single) != null ? single : 'km/h';
  return (
    unit: unit,
    perMetrePerSecond: 1 / metresPerSecondPerSpeedUnit(unit)!,
    converted: unit != single && keys.isNotEmpty,
    comparable: !(units.contains('') && units.any((unit) => unit.isNotEmpty)),
  );
}

/// Metres per second from a speed in [unit]; null for a unit not known.
double? _metersPerSecond(double? value, String unit) => speedInMetresPerSecond(value, unit);

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return double.nan;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// [channel]'s full travel: its values are a fraction (0..1) or a
/// percentage.
double _throttleScale(TelemetryChannel channel) {
  var peak = 0.0;
  for (final value in channel.values) {
    if (value.isFinite && value > peak) peak = value;
  }
  return channel.unit.trim() == '%' || peak > 1.5 ? 100.0 : 1.0;
}

/// Whether the car coasts from [fromTime] to [toTime]: the throttle
/// released (8 % or less, as [_liftProgress] reads a release) and the
/// brake under 10 %, both recorded throughout (no sample missing or
/// further than 0.5 s from either end or the one before), and the throttle
/// pressed (20 % or more) somewhere in the session.
bool _coastingThroughout(TelemetrySession session, double fromTime, double toTime) {
  bool below(String alias, double fraction) {
    final channel = session.channels[session.aliases[alias] ?? ''];
    if (channel == null || channel.sampleCount < 2) return false;
    final limit = fraction * _throttleScale(channel);
    final times = channel.timestamps, values = channel.values;
    var previous = fromTime;
    var count = 0;
    for (var i = 0; i < times.length; ++i) {
      final t = times[i];
      if (t < fromTime) continue;
      if (t >= toTime) break;
      if (t - previous > 0.5 || !values[i].isFinite || values[i] > limit) return false;
      previous = t;
      ++count;
    }
    return count >= 2 && toTime - previous <= 0.5;
  }

  // A throttle never pressed (unplugged, logging zeros) shows no lift.
  final throttle = session.channels[session.aliases['throttle'] ?? ''];
  if (throttle == null) return false;
  final pressed = 0.20 * _throttleScale(throttle);
  if (!throttle.values.any((v) => v.isFinite && v >= pressed)) return false;
  return below('throttle', 0.08) && below('brake', 0.10);
}

/// The longest stretch from [from] to [to] with the throttle off (below
/// [coachThrottleOff]), in seconds and metres along [trace]: zero for none,
/// null without a throttle channel. A sample that is not finite ends a
/// stretch.
({double seconds, double meters})? _offThrottle(
  TelemetrySession session,
  List<ProgressSegment> trace,
  double from,
  double to,
) {
  final channel = session.channels[session.aliases['throttle'] ?? ''];
  if (channel == null || channel.sampleCount < 2) return null;
  final times = channel.timestamps, values = channel.values;
  final off = coachThrottleOff * _throttleScale(channel);
  var best = (seconds: 0.0, meters: 0.0);
  double? since;
  void close(double end) {
    final start = since;
    since = null;
    if (start == null || end - start <= best.seconds) return;
    final a = progressAtTime(trace, start), b = progressAtTime(trace, end);
    if (a == null || b == null) return;
    best = (seconds: end - start, meters: math.max(0.0, b - a));
  }

  for (var i = 0; i < times.length; ++i) {
    final t = times[i];
    if (t < from) continue;
    if (t > to) break;
    final value = values[i];
    if (value.isFinite && value < off) {
      since ??= t;
    } else {
      close(t);
    }
  }
  close(to);
  return best;
}

/// The last sustained release of the throttle (from at least 20 % to at
/// most 8 % for 0.2 s and 3 m) starting between [fromTime] and 0.3 s after
/// [toTime], as a
/// position on [trace]; null without a throttle channel or a release.
double? _liftProgress(
  TelemetrySession session,
  List<ProgressSegment> trace,
  double fromTime,
  double toTime,
) {
  final channel = session.channels[session.aliases['throttle'] ?? ''];
  if (channel == null || channel.sampleCount < 2) return null;
  final times = channel.timestamps, values = channel.values;
  final scale = _throttleScale(channel);
  final high = 0.20 * scale, low = 0.08 * scale;
  double? result;
  var established = false;
  double? releasedAt;
  for (var i = 0; i < times.length; ++i) {
    final t = times[i];
    if (t < fromTime) continue;
    // A release may start up to 0.3 s after [toTime] (pedals overlapping at
    // the brake) and its confirmation may run past that, so a lift at the
    // brake point is seen rather than an earlier one.
    if (t > toTime + 0.3 && (releasedAt == null || t > toTime + 0.8)) break;
    final value = values[i];
    if (!value.isFinite) {
      established = false;
      releasedAt = null;
      continue;
    }
    if (value >= high) {
      established = true;
      releasedAt = null;
    } else if (value <= low && established) {
      releasedAt ??= t;
      final start = progressAtTime(trace, releasedAt);
      final now = progressAtTime(trace, t);
      if (t - releasedAt >= 0.2 && start != null && now != null && now - start >= 3.0) {
        result = start;
        established = false;
        releasedAt = null;
      }
    } else if (value > low) {
      releasedAt = null;
    }
  }
  return result;
}

/// The first throttle pickup from [fromTime] to [toTime] that is released
/// again before [toTime], as a position on [trace]: `at` is null when
/// there is none. A pickup holds the throttle at 20 % or more for 0.2 s
/// with the brake under 10 %; a release holds it at 8 % or less for 0.2 s
/// and 3 m. Not counted: a pickup ended by braking again (for the next
/// corner), or one after the car has slowed to a minimum and gained
/// [coachPickupGain] again, or gains that much before the release (speed
/// in m/s by [speedAt]): those drive out of an earlier apex. Null without
/// a throttle or brake channel or a speed there, or when a sample in
/// between is not finite.
({double? at})? _pickupThenLift(
  TelemetrySession session,
  List<ProgressSegment> trace,
  double fromTime,
  double toTime,
  double? Function(double time) speedAt,
) {
  final channel = session.channels[session.aliases['throttle'] ?? ''];
  final brake = session.channels[session.aliases['brake'] ?? ''];
  if (channel == null || channel.sampleCount < 2 || brake == null || brake.sampleCount < 2) {
    return null;
  }
  final times = channel.timestamps, values = channel.values;
  final scale = _throttleScale(channel);
  final high = 0.20 * scale, low = 0.08 * scale;
  // The throttle's scale heuristic suits the brake: a measured braking
  // (needed for the window) has the brake in % (see brakingUnitMismatch).
  final braking = 0.10 * _throttleScale(brake);
  // The slowest the car has been since [fromTime] or the last reset.
  var slowest = double.infinity;
  double? rising, pickedUp, releasedAt;
  for (var i = 0; i < times.length; ++i) {
    final t = times[i];
    if (t < fromTime) continue;
    if (t > toTime) break;
    final value = values[i];
    final pressure = session.valueAt('brake', t);
    final speed = speedAt(t);
    if (!value.isFinite || pressure == null || !pressure.isFinite || speed == null) return null;
    if (pressure >= braking) {
      // Braking again ends a pickup: it was for the next corner.
      rising = pickedUp = releasedAt = null;
      slowest = math.min(slowest, speed);
      continue;
    }
    if (pickedUp == null) {
      if (value >= high) {
        rising ??= t;
        if (t - rising >= 0.2) {
          // Past an earlier apex: the car slowed to a minimum and gained.
          if (speedAt(rising)! - slowest >= coachPickupGain) {
            rising = null;
            slowest = speed;
            continue;
          }
          pickedUp = rising;
        }
      } else {
        rising = null;
      }
      slowest = math.min(slowest, speed);
      continue;
    }
    if (value <= low) {
      releasedAt ??= t;
      final start = progressAtTime(trace, releasedAt);
      final now = progressAtTime(trace, t);
      if (t - releasedAt >= 0.2 && start != null && now != null && now - start >= 3.0) {
        final from = speedAt(pickedUp), to = speedAt(releasedAt);
        if (from == null || to == null) return null;
        if (to - from >= coachPickupGain) {
          // Driven out of an earlier apex: look for a stab after it.
          rising = pickedUp = releasedAt = null;
          slowest = speed;
          continue;
        }
        final at = progressAtTime(trace, pickedUp);
        return at == null ? null : (at: at);
      }
    } else {
      releasedAt = null;
    }
  }
  return (at: null);
}

/// The fewest G pairs a segment's mean combined G is taken from.
const int coachCombinedGMinimumPoints = 5;

/// The mean combined G ([ggMagnitude] of the longitudinal and lateral
/// acceleration pairs, [buildGgPairs]) from [start] to [end] along the
/// lap; null without both channels in a supported unit, with fewer than
/// [coachCombinedGMinimumPoints] pairs or with a lateral acceleration of
/// zeros only.
double? _meanCombinedG(
  TelemetrySession session,
  List<ProgressSegment> trace,
  double start,
  double end,
) {
  final from = timeAtProgress(trace, start), to = timeAtProgress(trace, end);
  if (from == null || to == null || to <= from) return null;
  final pairs = buildGgPairs(session, from, to);
  if (!pairs.valid || pairs.points.length < coachCombinedGMinimumPoints) return null;
  // A lateral channel of zeros is a placeholder, not a measurement.
  if (pairs.points.every((point) => point.lateralG == 0)) return null;
  var sum = 0.0;
  for (final point in pairs.points) {
    sum += ggMagnitude(point.longitudinalG, point.lateralG);
  }
  return sum / pairs.points.length;
}

/// The day's theoretical best as it stood before [runId] was added: of
/// the runs recorded before it ([dayWithRuns]), in the group [groupId] when
/// it is chosen again; null when no run comes before it. What [dayCoach]
/// takes as `before`.
DayTheoreticalBest? dayBeforeRun(
  DayAnalysis analysis,
  Map<String, OutingRun> runs,
  String runId, {
  Iterable<Object?> documentRuns = const [],
  Map<DayLapReference, String> exclusions = const {},
  String? groupId,
  math.Random? random,
  CancellationCheck? cancelled,
}) {
  final earlier = <String>{};
  for (final row in analysis.rows) {
    if (row.runId == runId) break;
    earlier.add(row.runId);
  }
  if (earlier.isEmpty) return null;
  final day = dayWithRuns(
    analysis,
    earlier,
    exclusions: exclusions,
    preferredGroupId: groupId,
    cancelled: cancelled,
  );
  return dayTheoreticalBest(
    day,
    {
      for (final MapEntry(:key, :value) in runs.entries)
        if (earlier.contains(key)) key: value,
    },
    // Segments saved on a later run (the best lap's, when it is later)
    // were not there then.
    documentRuns: [
      for (final run in documentRuns)
        if (run is Map && earlier.contains(run['id'])) run,
    ],
    random: random,
    cancelled: cancelled,
  );
}

/// What the coach suggests for the next session after session [runId] (the
/// day's latest), from [result]'s laps and corners and the day's recordings
/// in [sessions] by run id. Stops at [cancelled] with [OperationCancelled].
DayCoach dayCoach(
  DayTheoreticalBest result,
  Map<String, TelemetrySession?> sessions, {
  required String runId,
  DayTheoreticalBest? before,
  CancellationCheck? cancelled,
}) {
  final passages = <String, List<_Passage>>{};
  final coach = _dayCoach(result, sessions, runId: runId, passages: passages, cancelled: cancelled);
  if (coach.reason == CoachReason.noSegments) return coach;
  final goal = before == null
      ? null
      : _goalCheck(result, before, sessions, runId, passages, cancelled);
  final laps = [for (final sectors in result.laps) sectors.lap];
  final runs = <String>[];
  for (final lap in laps) {
    if (!runs.contains(lap.runId)) runs.add(lap.runId);
  }
  final at = runs.indexOf(runId);
  final previous = at >= 1 ? runs[at - 1] : '';
  final shown = _shownSpeed(result.corners);
  final values = previous.isEmpty
      ? const <CoachCornerGoalValues>[]
      : _cornerGoalValues(result, laps, passages, previous, runId, shown);
  return DayCoach(
    runId: coach.runId,
    findings: coach.findings,
    plan: coach.plan,
    reason: coach.reason,
    speedsConverted: coach.speedsConverted,
    slowLaps: coach.slowLaps,
    goal: goal,
    previousRunId: previous,
    speedUnit: shown.unit,
    perMetrePerSecond: shown.perMetrePerSecond,
    goalValues: values,
  );
}

/// The kinds of change a driver can set as a goal: every corrective kind.
const coachGoalKinds = [
  CoachKind.earlyLift,
  CoachKind.excessiveCoasting,
  CoachKind.lowMinimumSpeed,
  CoachKind.lateThrottle,
  CoachKind.earlyThrottle,
  CoachKind.inconsistentBraking,
];

/// Each corner's goal measures for [previous] and [coached], from
/// [passages], slow laps left out, as the main focus is measured.
List<CoachCornerGoalValues> _cornerGoalValues(
  DayTheoreticalBest result,
  List<DayLapRow> laps,
  Map<String, List<_Passage>> passages,
  String previous,
  String coached,
  _ShownSpeed shown,
) {
  final slow = {for (final lap in _slowLaps(laps)) lap.reference};
  return [
    for (final corner in result.corners)
      () {
        List<_Passage> of(String runId) => [
          for (final p in passages[corner.segmentId] ?? const <_Passage>[])
            if (p.lap.runId == runId && !slow.contains(p.lap.reference)) p,
        ];
        Map<CoachKind, CoachGoalValue> measure(List<_Passage> list) => {
          for (final kind in coachGoalKinds) kind: ?_goalValue(kind, list, shown),
        };
        return CoachCornerGoalValues(
          segmentId: corner.segmentId,
          name: corner.name,
          startProgressMeters: corner.startProgressMeters,
          endProgressMeters: corner.endProgressMeters,
          before: measure(of(previous)),
          now: measure(of(coached)),
        );
      }(),
  ];
}

/// One lap through one corner as the coach reads it, for a driver profile:
/// positions on the shared axis, metres. Each is null where the pedals
/// that show it were not recorded or not clear.
final class CoachCornerPassage {
  const CoachCornerPassage({
    required this.lap,
    this.liftSeconds,
    this.releaseMeters,
    this.pickupMeters,
    this.throttleKnown = false,
    this.pickupReleased = false,
  });

  final DayLapRow lap;

  /// From the last lift off the throttle to a measured braking point; 0
  /// when the pedals overlap.
  final double? liftSeconds;

  /// Where a measured braking ended.
  final double? releaseMeters;

  /// The measured throttle pickup at or after the slow point.
  final double? pickupMeters;

  /// Whether the throttle is known from the end of the braking to the slow
  /// point; then [pickupReleased] is whether the throttle was picked up and
  /// released again in between.
  final bool throttleKnown;
  final bool pickupReleased;
}

/// Every lap's passages through each corner of [result], by segment id,
/// read as [dayCoach] reads them; empty when [result] is not ready.
Map<String, List<CoachCornerPassage>> coachCornerPassages(
  DayTheoreticalBest result,
  Map<String, TelemetrySession?> sessions,
) {
  if (result.laps.isEmpty) return const {};
  final passages = <String, List<_Passage>>{};
  // Which session is coached changes the findings, never the passages.
  _dayCoach(result, sessions, runId: result.laps.first.lap.runId, passages: passages);
  final read = {
    for (final MapEntry(key: id, value: list) in passages.entries)
      id: List<CoachCornerPassage>.unmodifiable([
        for (final p in list)
          CoachCornerPassage(
            lap: p.lap,
            liftSeconds: p.liftSeconds,
            releaseMeters: p.release,
            pickupMeters: p.pickup,
            throttleKnown: p.throttleKnown,
            pickupReleased: p.earlyPickup != null,
          ),
      ]),
  };
  return read;
}

/// The coach of [runId] (see [dayCoach]); each corner's passages go in
/// [passages] by segment id.
DayCoach _dayCoach(
  DayTheoreticalBest result,
  Map<String, TelemetrySession?> sessions, {
  required String runId,
  Map<String, List<_Passage>>? passages,
  CancellationCheck? cancelled,
}) {
  final passagesOut = passages;
  final computed = result.computed;
  if (result.state != DayTheoreticalBestState.ready || computed == null) {
    return DayCoach(runId: runId, reason: CoachReason.noSegments);
  }
  // The group's laps in recording order, with their traces on the axis.
  final laps = [for (final sectors in result.laps) sectors.lap];
  final order = {for (var i = 0; i < laps.length; ++i) laps[i].reference: i};
  final traces = <DayLapReference, List<ProgressSegment>>{};
  for (var i = 0; i < computed.population.length; ++i) {
    final reference = computed.population[i].times.lapReference;
    if (reference is DayLapReference) traces[reference] = computed.traces[i];
  }
  final coached = runId;
  if (!laps.any((lap) => lap.runId == coached)) {
    return DayCoach(runId: coached, reason: CoachReason.noLapInGroup);
  }
  if (result.corners.isEmpty) {
    return DayCoach(runId: coached, reason: CoachReason.noCorners);
  }
  final shown = _shownSpeed(result.corners);
  final slow = _slowLaps(laps);
  final slowReferences = {for (final lap in slow) lap.reference};
  var pedals = false, faster = false, measured = false, earlier = false;

  // Each lap's coasting, once, by its approved segments.
  final coasting = <DayLapReference, CoastingSummary>{};
  CoastingSummary? coastingOf(DayLapRow lap) {
    final session = sessions[lap.runId];
    final trace = traces[lap.reference];
    if (session == null || trace == null) return null;
    return coasting[lap.reference] ??= summarizeCoasting(
      session,
      lap.start,
      lap.end,
      lapTrace: trace,
      approved: computed.approved,
    );
  }

  final findings = <CoachFinding>[];
  for (final corner in result.corners) {
    throwIfCancelled(cancelled);
    final index = corner.segmentIndex;
    final start = corner.startProgressMeters, end = corner.endProgressMeters;
    final passages = <_Passage>[];
    // The straight right after the corner, within the lap.
    final segments = computed.approved.segments;
    final next =
        index + 1 < segments.length &&
            segments[index + 1]['type'] == 'straight' &&
            (((segments[index + 1]['startProgressMeters'] as num?)?.toDouble() ?? -1.0) - end)
                    .abs() <=
                1e-6
        ? index + 1
        : null;
    for (final sectors in result.laps) {
      final lap = sectors.lap;
      final seconds = sectors.seconds(index);
      final nextSeconds = next == null ? null : sectors.seconds(next);
      final metrics = corner.metrics(lap.reference);
      final trace = traces[lap.reference];
      final session = sessions[lap.runId];
      if (seconds == null || metrics == null || trace == null || session == null) continue;
      final speeds = metrics.speeds;
      final braking = metrics.braking.method == 'measuredBrake'
          ? metrics.braking.brakingPointMeters
          : null;
      // For braking consistency: a measured, clean and sustained onset only.
      final onset =
          braking != null &&
              !metrics.braking.limitations.any(_unclearOnset.contains) &&
              (metrics.braking.brakingSeconds ?? 0) >= coachBrakingMinSeconds
          ? braking
          : null;
      // The first sustained throttle rise at or after the slow point, not cut
      // off by the segment's end or following a gap in the data.
      final rise = metrics.exit.pickup;
      final slowPoint = speeds.minimum.value == null ? null : speeds.minimum.progressMeters;
      final pickup =
          rise.method == 'measuredThrottle' &&
              rise.progressMeters != null &&
              slowPoint != null &&
              end > start &&
              // Within the position resolution of the slow point counts.
              rise.progressMeters! >= slowPoint - _slowPointTolerance(speeds) &&
              !rise.limitations.contains(exitTruncated) &&
              !rise.limitations.contains(exitFollowsGap)
          ? rise.progressMeters
          : null;
      // A brake that does not show the braking is no pedal (FET-204).
      if (lap.runId == coached &&
          (session.channels.containsKey(session.aliases['throttle'] ?? '') ||
              (session.channels.containsKey(session.aliases['brake'] ?? '') &&
                  !brakingSourceQuality(session).brakeRejected))) {
        pedals = true;
      }
      double? lift, liftSeconds;
      final from = start - coachApproachMeters;
      if (braking != null && end > start && from >= 0) {
        final fromTime = timeAtProgress(trace, from);
        final toTime = timeAtProgress(trace, braking);
        if (fromTime != null && toTime != null && toTime > fromTime) {
          lift = _liftProgress(session, trace, fromTime, toTime);
        }
      }
      // For the profile: from the lift to the braking. An approach reaching
      // back past start/finish starts at the lap's start; coasting through
      // the whole approach lifted before it, so at least that long.
      if (braking != null && end > start) {
        final fromTime = from <= 0 ? lap.start : timeAtProgress(trace, from);
        final toTime = timeAtProgress(trace, braking);
        if (fromTime != null && toTime != null && toTime > fromTime) {
          final at = from >= 0 ? lift : _liftProgress(session, trace, fromTime, toTime);
          final liftTime = at == null ? null : timeAtProgress(trace, at);
          if (liftTime != null) {
            liftSeconds = math.max(0.0, toTime - liftTime);
          } else if (_coastingThroughout(session, fromTime, toTime)) {
            liftSeconds = toTime - fromTime;
          }
        }
      }
      // A pickup between the end of the braking and the slow point,
      // released again.
      var throttleKnown = false;
      double? earlyPickup;
      final released =
          metrics.braking.method == 'measuredBrake' &&
              metrics.braking.brakingPointTime != null &&
              metrics.braking.brakingSeconds != null &&
              !metrics.braking.limitations.contains(brakingInterruptedByGap)
          ? metrics.braking.brakingPointTime! + metrics.braking.brakingSeconds!
          : null;
      final slowTime = slowPoint == null ? null : timeAtProgress(trace, slowPoint);
      if (released != null && slowTime != null && slowTime > released) {
        final found = _pickupThenLift(
          session,
          trace,
          released,
          slowTime,
          (t) => _metersPerSecond(session.valueAt('speed', t), speeds.unit),
        );
        if (found != null) {
          throttleKnown = true;
          earlyPickup = found.at;
        }
      }
      double? coastSeconds, coastMeters;
      final summary = coastingOf(lap);
      // An approach reaching back past start/finish starts at the lap's start;
      // a gap in the trace leaves the coast unknown.
      final windowStart = start - coachApproachMeters <= 0
          ? lap.start
          : timeAtProgress(trace, start - coachApproachMeters);
      final windowEnd = timeAtProgress(trace, end);
      if (summary != null &&
          summary.valid &&
          summary.provenance == drivingStateMeasured &&
          end > start &&
          windowStart != null &&
          windowEnd != null &&
          windowEnd > windowStart &&
          _covered(summary.known, windowStart, windowEnd) >= 0.9 * (windowEnd - windowStart)) {
        // The pedals were known through the window, so no episode means no
        // coasting rather than a gap in the data.
        coastSeconds = 0.0;
        coastMeters = 0.0;
        // Each episode counts for its part inside the window, and within it
        // only where the throttle is off: light throttle is not coasting.
        for (final episode in summary.episodes) {
          final from = math.max(episode.startTime, windowStart);
          final to = math.min(episode.endTime, windowEnd);
          if (to <= from) continue;
          final off = _offThrottle(session, trace, from, to);
          if (off == null) {
            coastSeconds = coastMeters = null;
            break;
          }
          if (off.seconds > coastSeconds!) {
            coastSeconds = off.seconds;
            coastMeters = off.meters;
          }
        }
      }
      passages.add(
        _Passage(
          lap: lap,
          order: order[lap.reference]!,
          seconds: seconds,
          spacing: speeds.meanSampleSpacingMeters,
          minimum: shown.comparable ? _metersPerSecond(speeds.minimum.value, speeds.unit) : null,
          exit: shown.comparable ? _metersPerSecond(speeds.exit.value, speeds.unit) : null,
          lift: lift,
          liftSeconds: liftSeconds,
          braking: braking,
          release: released == null ? null : progressAtTime(trace, released),
          onset: onset,
          pickup: pickup,
          coastSeconds: coastSeconds,
          coastMeters: coastMeters,
          nextSeconds: nextSeconds,
          throttleKnown: throttleKnown,
          earlyPickup: earlyPickup,
          combinedG: _meanCombinedG(session, trace, start, end),
        ),
      );
    }
    passagesOut?[corner.segmentId] = passages;
    if (passages.any((p) => p.lap.runId == coached)) measured = true;
    if (passages.length < 2) continue;
    if (_hasFasterLap(passages, coached)) faster = true;
    for (final kind in CoachKind.values) {
      // Braking consistency reads the session's laps together (below).
      if (!kind.corrective || kind == CoachKind.inconsistentBraking) continue;
      final finding = _corrective(
        kind,
        corner,
        passages,
        coached,
        shown,
        slow: slowReferences,
        onlyEarlier: () => earlier = true,
      );
      if (finding != null) findings.add(finding);
    }
    final braking = _inconsistentBraking(corner, passages, coached, slowReferences);
    if (braking != null) findings.add(braking);
    final improving = _improving(corner, passages, coached, shown, slowReferences);
    if (improving != null) findings.add(improving);
  }
  final plan = _plan(findings);
  return DayCoach(
    runId: coached,
    findings: findings,
    plan: plan,
    speedsConverted: shown.converted,
    slowLaps: slow,
    reason: plan.isNotEmpty
        ? CoachReason.ready
        : findings.any(
            (f) =>
                f.kind.corrective &&
                f.confidence >= coachPlanConfidence &&
                f.affectedLaps.length < 3,
          )
        ? CoachReason.tooFewLaps
        : findings.isNotEmpty
        ? CoachReason.belowThreshold
        : sessions[coached] == null
        ? CoachReason.noRecording
        : !measured
        ? CoachReason.noCornerMeasurements
        : !faster
        ? CoachReason.noFasterLap
        : earlier
        ? CoachReason.notInSession
        : !pedals
        ? CoachReason.noPedals
        : CoachReason.noPattern,
  );
}

/// How the session coached did on the main focus the coach gave for the
/// session before it, with [before], the day as it stood then; null when
/// there is no session before, [before] is not the day up to it, or its
/// focus was not a change. The focus is measured at the corner of today's
/// segments overlapping it most ([passages]).
CoachGoalCheck? _goalCheck(
  DayTheoreticalBest result,
  DayTheoreticalBest before,
  Map<String, TelemetrySession?> sessions,
  String coached,
  Map<String, List<_Passage>> passages,
  CancellationCheck? cancelled,
) {
  final laps = [for (final sectors in result.laps) sectors.lap];
  final runs = <String>[];
  for (final lap in laps) {
    if (!runs.contains(lap.runId)) runs.add(lap.runId);
  }
  final at = runs.indexOf(coached);
  if (at < 1) return null;
  final previous = runs[at - 1];
  final then = {for (final sectors in before.laps) sectors.lap.runId};
  if (!then.contains(previous) || then.contains(coached)) return null;
  final focus = _dayCoach(before, sessions, runId: previous, cancelled: cancelled).focus?.finding;
  if (focus == null || !focus.kind.corrective) return null;
  final runName = laps.firstWhere((lap) => lap.runId == previous).runName;
  CoachGoalCheck unmeasured([String measuredName = '']) => CoachGoalCheck(
    runId: previous,
    runName: runName,
    finding: focus,
    outcome: CoachGoalOutcome.notMeasured,
    measuredName: measuredName,
  );

  final shownCorner = before.corners.where((c) => c.segmentId == focus.segmentId).firstOrNull;
  if (shownCorner == null) return unmeasured();
  final match = coachMatchingSegment(
    (start: shownCorner.startProgressMeters, end: shownCorner.endProgressMeters),
    [for (final c in result.corners) (start: c.startProgressMeters, end: c.endProgressMeters)],
  );
  final corner = match == null ? null : result.corners[match];
  if (corner == null) return unmeasured();
  final slow = {for (final lap in _slowLaps(laps)) lap.reference};
  List<_Passage> of(String runId) => [
    for (final p in passages[corner.segmentId] ?? const <_Passage>[])
      if (p.lap.runId == runId && !slow.contains(p.lap.reference)) p,
  ];
  final shown = _shownSpeed(result.corners);
  final earlier = _goalValue(focus.kind, of(previous), shown);
  final now = _goalValue(focus.kind, of(coached), shown);
  if (earlier == null || now == null) return unmeasured(corner.name);
  final outcome = coachGoalOutcome(
    focus.kind,
    earlier.value,
    now.value,
    perMetrePerSecond: shown.perMetrePerSecond,
  );
  return CoachGoalCheck(
    runId: previous,
    runName: runName,
    finding: focus,
    outcome: outcome,
    measuredName: corner.name,
    before: earlier.value,
    now: now.value,
    beforeLaps: earlier.laps,
    nowLaps: now.laps,
  );
}

/// The index of the range in [today] overlapping [shown] most, by at
/// least half of the shorter of the two; null when none does. Ranges are
/// positions along the lap, in metres.
int? coachMatchingSegment(
  ({double start, double end}) shown,
  List<({double start, double end})> today,
) {
  int? best;
  var most = 0.0;
  for (var i = 0; i < today.length; ++i) {
    final range = today[i];
    final overlap = math.min(range.end, shown.end) - math.max(range.start, shown.start);
    final shorter = math.min(range.end - range.start, shown.end - shown.start);
    if (overlap > most && overlap >= shorter / 2) {
      most = overlap;
      best = i;
    }
  }
  return best;
}

/// Whether [now] is better than [before] for a focus of [kind], by a clear
/// step: a later lift and a higher minimum speed are better, and less
/// coasting, an earlier throttle return and a smaller braking range. The
/// step is 8 m for positions, 0.4 s of coasting, 1.4 m/s of minimum speed
/// (in the speeds' unit: [perMetrePerSecond] per m/s),
/// [coachBrakingOffMeters] of braking range and, for an early throttle,
/// 25 points of the share of laps picking it up early (fewer is better).
CoachGoalOutcome coachGoalOutcome(
  CoachKind kind,
  double before,
  double now, {
  double perMetrePerSecond = 3.6,
}) {
  final sign = switch (kind) {
    CoachKind.earlyLift || CoachKind.lowMinimumSpeed => 1.0,
    _ => -1.0,
  };
  final step = switch (kind) {
    CoachKind.excessiveCoasting => 0.4,
    CoachKind.lowMinimumSpeed => 1.4 * perMetrePerSecond,
    CoachKind.inconsistentBraking => coachBrakingOffMeters,
    CoachKind.earlyThrottle => 25.0,
    _ => 8.0,
  };
  final change = sign * (now - before);
  return change >= step
      ? CoachGoalOutcome.better
      : change <= -step
      ? CoachGoalOutcome.worse
      : CoachGoalOutcome.unchanged;
}

/// The goal's measure across [passages] (a session's laps at the goal's
/// segment): the median of the lap values, or the braking range; null
/// when fewer than two laps (three for the braking range) have it.
CoachGoalValue? _goalValue(CoachKind kind, List<_Passage> passages, _ShownSpeed shown) {
  double? read(_Passage p) => switch (kind) {
    CoachKind.earlyLift => p.lift,
    CoachKind.excessiveCoasting => p.coastSeconds,
    CoachKind.lowMinimumSpeed => p.minimum,
    CoachKind.lateThrottle => p.pickup,
    CoachKind.earlyThrottle => p.earlyPickup,
    CoachKind.inconsistentBraking => p.onset,
    CoachKind.improving => null,
  };
  final values = [for (final p in passages) ?read(p)];
  if (kind == CoachKind.earlyThrottle) {
    // The share of laps picking up early, of those with the throttle known.
    final known = passages.where((p) => p.throttleKnown).length;
    if (known < 2) return null;
    return (value: 100.0 * values.length / known, laps: known);
  }
  if (kind == CoachKind.inconsistentBraking) {
    if (values.length < 3) return null;
    return (value: values.reduce(math.max) - values.reduce(math.min), laps: values.length);
  }
  if (values.length < 2) return null;
  final median = _median(values);
  return (
    value: kind == CoachKind.lowMinimumSpeed ? median * shown.perMetrePerSecond : median,
    laps: values.length,
  );
}

/// The laps of [laps] (in recording order) much slower than their
/// session's median lap, for sessions of at least three laps.
List<DayLapRow> _slowLaps(List<DayLapRow> laps) {
  final bySession = <String, List<double>>{};
  for (final lap in laps) {
    (bySession[lap.runId] ??= []).add(lap.durationSeconds);
  }
  final typical = {
    for (final MapEntry(:key, :value) in bySession.entries)
      if (value.length >= 3) key: _median(value),
  };
  return [
    for (final lap in laps)
      if (typical[lap.runId] case final median?
          when lap.durationSeconds > median * coachSlowLapRatio)
        lap,
  ];
}

/// How far before the slow point a throttle return still counts as after
/// it: the speed minimum lags the pickup by up to half a second, and never
/// less than the position resolution.
double _slowPointTolerance(CornerSpeeds speeds) {
  final minimum = _metersPerSecond(speeds.minimum.value, speeds.unit) ?? 0.0;
  return math.max(math.max(3.0, speeds.meanSampleSpacingMeters), minimum * 0.5);
}

/// Seconds of [known] inside [from]..[to].
double _covered(List<DrivingStateInterval> known, double from, double to) {
  var seconds = 0.0;
  for (final interval in known) {
    final a = math.max(from, interval.start), b = math.min(to, interval.end);
    if (b > a) seconds += b - a;
  }
  return seconds;
}

/// A faster lap, with a faster passage, as [_corrective] compares.
bool _isFaster(_Passage reference, _Passage current) =>
    reference.lapSeconds < current.lapSeconds - 0.1 && reference.seconds < current.seconds - 0.05;

bool _hasFasterLap(List<_Passage> passages, String coached) => passages.any(
  (current) => current.lap.runId == coached && passages.any((p) => _isFaster(p, current)),
);

typedef _Observation = ({
  _Passage current,
  List<_Passage> references,
  double observed,
  double reference,
});

CoachFinding? _corrective(
  CoachKind kind,
  DayCorner corner,
  List<_Passage> passages,
  String coached,
  _ShownSpeed shown, {
  required Set<DayLapReference> slow,
  required void Function() onlyEarlier,
}) {
  final observations = <_Observation>[];
  // The session coached's laps that could show the pattern: with a faster
  // lap to compare with and the pattern's value measured.
  var compared = 0;
  var metric = '', unit = '';
  var key = CoachMetric.segmentTime;
  // Every lap of the day so far shows or does not show the pattern, so a
  // pattern repeated across sessions counts; the session coached must still
  // show it (see the end).
  for (final current in passages) {
    if (slow.contains(current.lap.reference)) continue;
    // Faster laps within reach first, by their time through the segment;
    // then the others, nearest in lap time first.
    bool reach(_Passage p) => current.lapSeconds - p.lapSeconds <= coachReachSeconds;
    final faster = passages.where((p) => _isFaster(p, current)).toList()
      ..sort((a, b) {
        final near = (reach(b) ? 1 : 0).compareTo(reach(a) ? 1 : 0);
        if (near != 0) return near;
        return reach(a) ? a.seconds.compareTo(b.seconds) : b.lapSeconds.compareTo(a.lapSeconds);
      });
    final references = faster.take(2).toList();
    if (references.isEmpty) continue;
    // Once the lap and its references can be compared, before the pattern
    // itself is tested.
    void count() {
      if (current.lap.runId == coached) ++compared;
    }

    final resolution = references.map((r) => r.spacing).fold(current.spacing, math.max);
    final threshold = math.max(8.0, resolution * 2);
    double? observed;
    final values = <double>[];
    switch (kind) {
      case CoachKind.earlyLift:
        final lift = current.lift, braking = current.braking;
        if (lift == null || braking == null) continue;
        observed = lift;
        metric = 'Lift point';
        key = CoachMetric.liftPoint;
        unit = 'm';
        for (final r in references) {
          if (r.lift == null ||
              r.braking == null ||
              (r.braking! - braking).abs() > math.max(10.0, resolution * 2)) {
            continue;
          }
          values.add(r.lift!);
        }
        if (values.length != references.length) continue;
        count();
        if (braking - lift < 5 || values.any((v) => v - lift < threshold)) continue;
      case CoachKind.excessiveCoasting:
        final coast = current.coastSeconds;
        metric = 'Longest coast';
        key = CoachMetric.longestCoast;
        unit = 's';
        if (coast == null) continue;
        observed = coast;
        values.addAll(references.map((r) => r.coastSeconds).whereType<double>());
        if (values.length != references.length) continue;
        count();
        if (coast < 0.7 || current.coastMeters! < threshold || values.any((v) => coast - v < 0.4)) {
          continue;
        }
      case CoachKind.lowMinimumSpeed:
        final minimum = current.minimum, exit = current.exit;
        metric = 'Minimum speed';
        key = CoachMetric.minimumSpeed;
        unit = shown.unit;
        if (minimum == null ||
            exit == null ||
            references.any((r) => r.minimum == null || r.exit == null)) {
          continue;
        }
        count();
        if (references.any((r) => r.minimum! - minimum < 1.4 || exit > r.exit! + 0.5)) {
          continue;
        }
        observed = minimum * shown.perMetrePerSecond;
        values.addAll(references.map((r) => r.minimum! * shown.perMetrePerSecond));
      case CoachKind.lateThrottle:
        final pickup = current.pickup;
        metric = 'Throttle return';
        key = CoachMetric.throttleReturn;
        unit = 'm';
        if (pickup == null || references.length < 2 || references.any((r) => r.pickup == null)) {
          continue;
        }
        observed = pickup;
        values.addAll(references.map((r) => r.pickup!));
        count();
        if (values.any((v) => pickup - v < threshold)) continue;
      case CoachKind.earlyThrottle:
        final early = current.earlyPickup;
        metric = 'First throttle pickup';
        key = CoachMetric.firstThrottle;
        unit = 'm';
        if (!current.throttleKnown || references.any((r) => !r.throttleKnown || r.pickup == null)) {
          continue;
        }
        count();
        // The faster laps pick up once.
        if (early == null || references.any((r) => r.earlyPickup != null)) continue;
        observed = early;
        values.addAll(references.map((r) => r.pickup!));
      case CoachKind.inconsistentBraking || CoachKind.improving:
        continue;
    }
    observations.add((
      current: current,
      references: references,
      observed: observed,
      reference: _median(values),
    ));
  }
  final repeatedRequired =
      kind == CoachKind.lowMinimumSpeed ||
      kind == CoachKind.lateThrottle ||
      kind == CoachKind.earlyThrottle;
  if (observations.isEmpty || (repeatedRequired && observations.length < 2)) return null;
  // The session coached must still show it, on at least half of its laps
  // compared: a pattern it has left behind is not advice for the next
  // session. Its laps give the values; the day's give the repetition and
  // the confidence (with the coarsest sample spacing of every lap used).
  final now = observations.where((o) => o.current.lap.runId == coached).toList();
  if (now.isEmpty || now.length * 2 < compared) {
    // Said only where the session could have shown it and earlier laps
    // repeated it.
    if (compared > 0 && observations.where((o) => o.current.lap.runId != coached).length >= 2) {
      onlyEarlier();
    }
    return null;
  }

  final referenceLaps = <DayLapRow>[];
  for (final o in now) {
    for (final r in o.references) {
      if (!referenceLaps.any((lap) => lap.reference == r.lap.reference)) {
        referenceLaps.add(r.lap);
      }
    }
  }
  referenceLaps.sort((a, b) => a.start.compareTo(b.start));
  final spacing = [
    for (final o in observations) ...[o.current.spacing, ...o.references.map((r) => r.spacing)],
  ].reduce((a, b) => !(a > 0) || !(b > 0) ? 0.0 : math.max(a, b));
  var confidence =
      0.48 + math.min(observations.length, 3) * 0.09 + (referenceLaps.length >= 2 ? 0.08 : 0.03);
  // An unknown spacing counts as sparse.
  if (!(spacing > 0) || spacing > 5) confidence -= 0.08;
  if (!(spacing > 0) || spacing > 10) confidence -= 0.12;
  // This app's coasting does not check longitudinal G.
  if (kind == CoachKind.excessiveCoasting) confidence -= 0.05;

  double medianOf(double Function(_Passage) read) => _median(now.map((o) => read(o.current)));
  double referenceOf(double Function(_Passage) read) =>
      _median(now.map((o) => _median(o.references.map(read))));
  final evidence = [
    CoachEvidence(
      key: key,
      metric: metric,
      observed: _median(now.map((o) => o.observed)),
      reference: _median(now.map((o) => o.reference)),
      unit: unit,
      referenceLaps: referenceLaps,
      detail:
          '${now.length == 1 ? 'One affected lap' : 'Median across ${now.length} affected laps'} '
          'of this session (laps of the day so far showing it: ${observations.length}); '
          '${referenceLaps.length == 1 ? 'compared with one faster lap' : 'median of the faster laps'}; '
          'every comparison uses a faster lap and a faster '
          'passage through this segment. Positions are along the lap from start/finish on '
          'the day\'s shared axis.',
    ),
    CoachEvidence(
      key: CoachMetric.segmentTime,
      metric: 'Segment time',
      observed: medianOf((p) => p.seconds),
      reference: referenceOf((p) => p.seconds),
      unit: 's',
      referenceLaps: referenceLaps,
      detail: 'Observed segment difference, not a predicted gain or a causal time-loss estimate.',
    ),
    if (now.every(
      (o) => o.current.nextSeconds != null && o.references.every((r) => r.nextSeconds != null),
    ))
      CoachEvidence(
        key: CoachMetric.nextStraightTime,
        metric: 'Straight after it',
        observed: medianOf((p) => p.nextSeconds!),
        reference: referenceOf((p) => p.nextSeconds!),
        unit: 's',
        referenceLaps: referenceLaps,
        detail:
            'Time through the straight right after this segment, counted with it. Observed, not '
            'proof that this segment caused it, and not a predicted gain.',
      ),
    if (now.every((o) => o.current.exit != null && o.references.every((r) => r.exit != null)))
      CoachEvidence(
        key: CoachMetric.exitSpeed,
        metric: 'Exit speed',
        observed: medianOf((p) => p.exit! * shown.perMetrePerSecond),
        reference: referenceOf((p) => p.exit! * shown.perMetrePerSecond),
        unit: shown.unit,
        referenceLaps: referenceLaps,
        detail: 'Speed at the segment\'s exit.',
      ),
    if (now.every(
      (o) => o.current.combinedG != null && o.references.every((r) => r.combinedG != null),
    ))
      CoachEvidence(
        key: CoachMetric.combinedG,
        metric: 'Mean combined G',
        observed: medianOf((p) => p.combinedG!),
        reference: referenceOf((p) => p.combinedG!),
        unit: 'g',
        referenceLaps: referenceLaps,
        detail:
            'Mean of the longitudinal and lateral acceleration combined through the segment. '
            'How hard the car was worked, not a share of the grip available.',
      ),
    if (now.every(
      (o) => o.current.combinedG != null && o.references.every((r) => r.combinedG != null),
    ))
      CoachEvidence(
        key: CoachMetric.highestCombinedG,
        metric: 'Highest mean combined G here',
        observed: now.map((o) => o.current.combinedG!).reduce(math.max),
        reference: [
          for (final p in passages)
            if (!slow.contains(p.lap.reference)) ?p.combinedG,
          for (final o in now)
            for (final r in o.references) r.combinedG!,
        ].reduce(math.max),
        unit: 'g',
        referenceLaps: referenceLaps,
        detail:
            'The highest on this session\'s laps compared, against the highest of the day\'s '
            'laps so far at this segment (slow laps left out).',
      ),
    if (kind == CoachKind.earlyLift)
      CoachEvidence(
        key: CoachMetric.brakingStart,
        metric: 'Braking start',
        observed: medianOf((p) => p.braking!),
        reference: referenceOf((p) => p.braking!),
        unit: 'm',
        referenceLaps: referenceLaps,
        detail: 'Brake points must agree within 10 m or twice the source sample spacing.',
      ),
    if (kind == CoachKind.excessiveCoasting)
      CoachEvidence(
        key: CoachMetric.coastDistance,
        metric: 'Coast distance',
        observed: medianOf((p) => p.coastMeters!),
        reference: referenceOf((p) => p.coastMeters!),
        unit: 'm',
        referenceLaps: referenceLaps,
        detail:
            'Both pedal channels must be recorded. Longitudinal G is not checked, so the '
            'confidence is lowered.',
      ),
  ];
  return CoachFinding(
    kind: kind,
    segmentId: corner.segmentId,
    segmentName: corner.name,
    confidence: confidence.clamp(0.0, 0.9),
    evidence: evidence,
    affectedLaps: [
      for (final o in [...observations]..sort((a, b) => a.current.order.compareTo(b.current.order)))
        o.current.lap,
    ],
    sessionLaps: [
      for (final o in [...now]..sort((a, b) => a.current.order.compareTo(b.current.order)))
        o.current.lap,
    ],
  );
}

/// The session coached's braking points at [corner] spread out: at least
/// two of its laps brake [coachBrakingOffMeters] (and two sample spacings)
/// or more from its typical (median) braking point, from at least three
/// laps with a clean, sustained, measured onset; the earliest and the latest
/// are at least [coachBrakingSpreadMeters] (and four sample spacings)
/// apart, and that much more than across the day's three fastest laps
/// there. Slow laps are left out.
CoachFinding? _inconsistentBraking(
  DayCorner corner,
  List<_Passage> passages,
  String coached,
  Set<DayLapReference> slow,
) {
  final measured = passages
      .where((p) => p.onset != null && !slow.contains(p.lap.reference))
      .toList();
  final own = measured.where((p) => p.lap.runId == coached).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  if (own.length < 3) return null;
  final fastest = ([
    ...measured,
  ]..sort((a, b) => a.lapSeconds.compareTo(b.lapSeconds))).take(3).toList();
  double spread(List<_Passage> laps) {
    final points = laps.map((p) => p.onset!);
    return points.reduce(math.max) - points.reduce(math.min);
  }

  final spacing = [
    ...own,
    ...fastest,
  ].map((p) => p.spacing).reduce((a, b) => !(a > 0) || !(b > 0) ? 0.0 : math.max(a, b));
  final typical = _median(own.map((p) => p.onset!));
  final off = [
    for (final p in own)
      if ((p.onset! - typical).abs() >= math.max(coachBrakingOffMeters, spacing * 2)) p,
  ];
  final observed = spread(own), reference = spread(fastest);
  if (off.length < 2 ||
      observed < math.max(coachBrakingSpreadMeters, spacing * 4) ||
      observed - reference < coachBrakingSpreadMeters) {
    return null;
  }
  var confidence = 0.48 + math.min(off.length, 3) * 0.09 + 0.08;
  // An unknown spacing counts as sparse.
  if (!(spacing > 0) || spacing > 5) confidence -= 0.08;
  if (!(spacing > 0) || spacing > 10) confidence -= 0.12;
  final referenceLaps = [for (final p in fastest) p.lap]
    ..sort((a, b) => a.start.compareTo(b.start));
  return CoachFinding(
    kind: CoachKind.inconsistentBraking,
    segmentId: corner.segmentId,
    segmentName: corner.name,
    confidence: confidence.clamp(0.0, 0.9),
    evidence: [
      CoachEvidence(
        key: CoachMetric.brakingSpread,
        metric: 'Braking point range',
        observed: observed,
        reference: reference,
        unit: 'm',
        referenceLaps: referenceLaps,
        detail:
            'From the earliest to the latest braking start across ${own.length} laps of this '
            'session, ${off.length} of them ${coachBrakingOffMeters.round()} m (and two sample spacings) or more from its '
            'typical braking point; compared with the day\'s three fastest laps (this '
            'session\'s among them when they are). Measured from the brake channel, clean '
            'onsets of at least ${coachBrakingMinSeconds.toStringAsFixed(1)} s only; positions '
            'are along the lap on the day\'s shared axis.',
      ),
      CoachEvidence(
        key: CoachMetric.brakingStart,
        metric: 'Braking start',
        observed: typical,
        reference: _median(fastest.map((p) => p.onset!)),
        unit: 'm',
        referenceLaps: referenceLaps,
        detail: 'The median braking start: where the fastest laps braked is a marker to try.',
      ),
      CoachEvidence(
        key: CoachMetric.segmentTime,
        metric: 'Segment time',
        observed: _median(own.map((p) => p.seconds)),
        reference: _median(fastest.map((p) => p.seconds)),
        unit: 's',
        referenceLaps: referenceLaps,
        detail: 'Observed segment difference, not a predicted gain or a causal time-loss estimate.',
      ),
      if ([...own, ...fastest].every((p) => p.nextSeconds != null))
        CoachEvidence(
          key: CoachMetric.nextStraightTime,
          metric: 'Straight after it',
          observed: _median(own.map((p) => p.nextSeconds!)),
          reference: _median(fastest.map((p) => p.nextSeconds!)),
          unit: 's',
          referenceLaps: referenceLaps,
          detail:
              'Time through the straight right after this segment, counted with it. Observed, '
              'not proof that this segment caused it, and not a predicted gain.',
        ),
    ],
    // Every lap read shows the spread; the laps off the typical point rank
    // it among the session's patterns.
    affectedLaps: [for (final p in own) p.lap],
    sessionLaps: [for (final p in off) p.lap],
  );
}

/// The last three consecutive laps of the coached session improving the
/// minimum speed or the throttle return, with the segment time, and
/// without losing exit speed.
CoachFinding? _improving(
  DayCorner corner,
  List<_Passage> passages,
  String coached,
  _ShownSpeed shown,
  Set<DayLapReference> slow,
) {
  // Slow laps are not read for a pattern; one among the last laps breaks
  // the run of consecutive laps.
  final own =
      passages.where((p) => p.lap.runId == coached && !slow.contains(p.lap.reference)).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
  if (own.length < 3) return null;
  final recent = own.sublist(own.length - 3);
  final a = recent[0], b = recent[1], c = recent[2];
  if (b.lap.lapNumber != a.lap.lapNumber + 1 ||
      c.lap.lapNumber != b.lap.lapNumber + 1 ||
      a.exit == null ||
      b.exit == null ||
      c.exit == null ||
      b.exit! < a.exit! - 0.5 ||
      c.exit! < b.exit! - 0.5 ||
      b.seconds >= a.seconds ||
      c.seconds >= b.seconds) {
    return null;
  }
  String metric, unit;
  CoachMetric key;
  double before, after;
  final (ma, mb, mc) = (a.minimum, b.minimum, c.minimum);
  final (pa, pb, pc) = (a.pickup, b.pickup, c.pickup);
  if (ma != null &&
      mb != null &&
      mc != null &&
      mb - ma >= 0.4 &&
      mc - mb >= 0.4 &&
      mc - ma >= 1.4) {
    metric = 'Minimum speed';
    key = CoachMetric.minimumSpeed;
    unit = shown.unit;
    before = ma * shown.perMetrePerSecond;
    after = mc * shown.perMetrePerSecond;
  } else if (pa != null &&
      pb != null &&
      pc != null &&
      pa - pb >= 4 &&
      pb - pc >= 4 &&
      pa - pc >= math.max(8.0, c.spacing * 2)) {
    metric = 'Throttle return';
    key = CoachMetric.throttleReturn;
    unit = 'm';
    before = pa;
    after = pc;
  } else {
    return null;
  }
  return CoachFinding(
    kind: CoachKind.improving,
    segmentId: corner.segmentId,
    segmentName: corner.name,
    confidence: !(c.spacing > 0) || c.spacing > 5 ? 0.69 : 0.79,
    evidence: [
      CoachEvidence(
        key: key,
        metric: metric,
        observed: after,
        reference: before,
        unit: unit,
        referenceLaps: [a.lap],
        detail:
            'Improved at each of the last three consecutive laps; the segment time also '
            'decreased.',
      ),
      CoachEvidence(
        key: CoachMetric.exitSpeed,
        metric: 'Exit speed',
        observed: c.exit! * shown.perMetrePerSecond,
        reference: a.exit! * shown.perMetrePerSecond,
        unit: shown.unit,
        referenceLaps: [a.lap],
        detail: 'No exit-speed drop greater than 1.8 km/h from one lap to the next.',
      ),
    ],
    affectedLaps: [for (final p in recent) p.lap],
  );
}

/// DrivingCoach's plan, with this app's rule that a typical value needs at
/// least three laps: findings at or above [coachPlanConfidence], a change
/// only when seen on three or more laps of the day so far, an
/// improvement suppressing changes in its segment, repeated patterns first,
/// then those on more laps of the session coached, then confidence and the observed segment-time gap; one item per segment,
/// at most two changes and one improvement kept when there is one, the changes
/// first (the first item is the main focus).
List<CoachItem> _plan(List<CoachFinding> findings) {
  final eligible = findings
      .where(
        (f) =>
            f.confidence >= coachPlanConfidence &&
            (!f.kind.corrective || f.affectedLaps.length >= 3),
      )
      .toList();
  final improving = {
    for (final f in eligible)
      if (!f.kind.corrective) f.segmentId,
  };
  eligible.removeWhere((f) => f.kind.corrective && improving.contains(f.segmentId));
  // The time lost through the segment and the straight right after it.
  double gap(CoachFinding f) {
    var lost = 0.0;
    for (final e in f.evidence) {
      if (e.key == CoachMetric.segmentTime || e.key == CoachMetric.nextStraightTime) {
        lost += e.observed - e.reference;
      }
    }
    return lost;
  }

  eligible.sort((a, b) {
    final repeated = (b.repeated ? 1 : 0).compareTo(a.repeated ? 1 : 0);
    if (repeated != 0) return repeated;
    // More time lost comes first, in steps of coachRankSeconds: smaller
    // differences are within the noise of the sector times.
    final lost = (gap(b) / coachRankSeconds).floor().compareTo((gap(a) / coachRankSeconds).floor());
    if (lost != 0) return lost;
    // A pattern more of the session coached's laps show comes first.
    final session = b.sessionLaps.length.compareTo(a.sessionLaps.length);
    if (session != 0) return session;
    final confidence = b.confidence.compareTo(a.confidence);
    if (confidence != 0) return confidence;
    final effect = gap(b).compareTo(gap(a));
    if (effect != 0) return effect;
    final segment = a.segmentId.compareTo(b.segmentId);
    return segment != 0 ? segment : a.kind.index.compareTo(b.kind.index);
  });
  final chosen = <CoachFinding>[];
  final positive = eligible.where((f) => !f.kind.corrective);
  if (positive.isNotEmpty) chosen.add(positive.first);
  for (final finding in eligible) {
    if (chosen.length == 3) break;
    if (chosen.any((f) => f.segmentId == finding.segmentId)) continue;
    final changes = chosen.where((f) => f.kind.corrective).length;
    if (finding.kind.corrective && changes >= 2) continue;
    if (!finding.kind.corrective && chosen.any((f) => !f.kind.corrective)) continue;
    // One braking marker to work on at a time.
    if (finding.kind == CoachKind.inconsistentBraking &&
        chosen.any((f) => f.kind == CoachKind.inconsistentBraking)) {
      continue;
    }
    chosen.add(finding);
  }
  // The first item is the main focus: the first change, or the improvement
  // to keep when there is no change.
  chosen.sort((a, b) {
    final change = (b.kind.corrective ? 1 : 0).compareTo(a.kind.corrective ? 1 : 0);
    return change != 0 ? change : eligible.indexOf(a).compareTo(eligible.indexOf(b));
  });
  return [for (final finding in chosen) CoachItem(finding)];
}
