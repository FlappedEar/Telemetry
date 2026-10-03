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
// - A lap is "affected" only in the session coached (the latest); references
//   come from every eligible lap of the group.
//
// A finding is a pattern that suggests an opportunity, never a promised
// gain: estimated time loss stays unknown, as in DrivingCoach.
import 'dart:math' as math;

import '../analysis/coasting_analysis.dart';
import '../analysis/driving_states.dart' show drivingStateMeasured;
import '../analysis/track_progress.dart';
import '../telemetry_session.dart';
import 'day_corners.dart';
import 'day_laps.dart';
import 'day_theoretical_best.dart';

const String dayCoachAlgorithm = 'coach-v1';

/// How far before a corner's entry its lift, braking and coasting are
/// looked for.
const double coachApproachMeters = 150.0;

/// Only findings this confident enter the plan.
const double coachPlanConfidence = 0.65;

enum CoachKind {
  earlyLift,
  excessiveCoasting,
  lowMinimumSpeed,
  lateThrottle,
  improving;

  /// Advice to change something; [improving] says to keep it.
  bool get corrective => this != improving;
}

/// One measured comparison behind a finding.
final class CoachEvidence {
  CoachEvidence({
    required this.metric,
    required this.observed,
    required this.reference,
    required this.unit,
    required List<DayLapRow> referenceLaps,
    required this.detail,
  }) : referenceLaps = List.unmodifiable(referenceLaps);

  /// "Minimum speed", "Throttle return"...
  final String metric;

  /// The median over the affected laps.
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
  }) : evidence = List.unmodifiable(evidence),
       affectedLaps = List.unmodifiable(affectedLaps);

  final CoachKind kind;
  final String segmentId;
  final String segmentName;

  /// A conservative support score from 0 to 0.9, not a probability.
  final double confidence;

  /// The first item is the pattern itself; then the segment time, the exit
  /// speed and, depending on [kind], the braking start or coasting distance.
  final List<CoachEvidence> evidence;
  final List<DayLapRow> affectedLaps;

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
        'compared with ${value(metric.reference)} on faster laps.';
  }

  String get action => finding.action;
}

/// The coach's view of one session of a day.
final class DayCoach {
  DayCoach({
    this.runId = '',
    List<CoachFinding> findings = const [],
    List<CoachItem> plan = const [],
    this.message = '',
  }) : findings = List.unmodifiable(findings),
       plan = List.unmodifiable(plan);

  /// The session coached; empty when none could be.
  final String runId;

  /// Every finding, planned or not.
  final List<CoachFinding> findings;

  /// At most three items: at most two changes, in two different segments,
  /// and one improvement to keep when there is one.
  final List<CoachItem> plan;

  /// Why the plan is empty, or how to use it.
  final String message;
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
    this.braking,
    this.pickup,
    this.coastSeconds,
    this.coastMeters,
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
  final double? pickup;

  /// The longest coast from the approach to the exit.
  final double? coastSeconds;
  final double? coastMeters;

  double get lapSeconds => lap.durationSeconds;
}

/// Metres per second from a speed in [unit]; null for a unit not known.
double? _metersPerSecond(double? value, String unit) {
  if (value == null) return null;
  return switch (unit.trim().toLowerCase()) {
    '' || 'km/h' || 'kmh' || 'kph' => value / 3.6,
    'mph' => value * 0.44704,
    'm/s' => value,
    'kn' || 'kt' || 'knots' => value * 0.514444,
    _ => null,
  };
}

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return double.nan;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// The last sustained release of the throttle (from at least 20 % to at
/// most 8 % for 0.2 s and 3 m) between [fromTime] and [toTime], as a
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
  var peak = 0.0;
  for (final value in values) {
    if (value.isFinite && value > peak) peak = value;
  }
  // A fraction (0..1) or a percentage.
  final scale = channel.unit.trim() == '%' || peak > 1.5 ? 100.0 : 1.0;
  final high = 0.20 * scale, low = 0.08 * scale;
  double? result;
  var established = false;
  double? releasedAt;
  for (var i = 0; i < times.length; ++i) {
    final t = times[i];
    if (t < fromTime) continue;
    if (t > toTime) break;
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

/// What the coach suggests for the next session after session [runId] (by
/// default the group's latest), from [result]'s laps and corners and the
/// day's recordings in [sessions] by run id.
DayCoach dayCoach(
  DayTheoreticalBest result,
  Map<String, TelemetrySession?> sessions, {
  String? runId,
}) {
  final computed = result.computed;
  if (result.state != DayTheoreticalBestState.ready || computed == null) {
    return DayCoach(message: 'The coach needs the day\'s segments and sector times first.');
  }
  // The group's laps in recording order, with their traces on the axis.
  final laps = [for (final sectors in result.laps) sectors.lap];
  final order = {for (var i = 0; i < laps.length; ++i) laps[i].reference: i};
  final traces = <DayLapReference, List<ProgressSegment>>{};
  for (var i = 0; i < computed.population.length; ++i) {
    final reference = computed.population[i].times.lapReference;
    if (reference is DayLapReference) traces[reference] = computed.traces[i];
  }
  final coached = runId ?? (laps.isEmpty ? '' : laps.last.runId);
  if (!laps.any((lap) => lap.runId == coached)) {
    return DayCoach(message: 'This session has no timed lap in the group compared.');
  }

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
    final index = corner.segmentIndex;
    final start = corner.startProgressMeters, end = corner.endProgressMeters;
    final passages = <_Passage>[];
    for (final sectors in result.laps) {
      final lap = sectors.lap;
      final seconds = sectors.seconds(index);
      final metrics = corner.metrics(lap.reference);
      final trace = traces[lap.reference];
      final session = sessions[lap.runId];
      if (seconds == null || metrics == null || trace == null || session == null) continue;
      final speeds = metrics.speeds;
      final braking = metrics.braking.method == 'measuredBrake'
          ? metrics.braking.brakingPointMeters
          : null;
      final pickup = metrics.exit.pickup.method == 'measuredThrottle'
          ? metrics.exit.pickup.progressMeters
          : null;
      double? lift;
      final from = start - coachApproachMeters;
      if (braking != null && end > start && from >= 0) {
        final fromTime = timeAtProgress(trace, from);
        final toTime = timeAtProgress(trace, braking);
        if (fromTime != null && toTime != null && toTime > fromTime) {
          lift = _liftProgress(session, trace, fromTime, toTime);
        }
      }
      double? coastSeconds, coastMeters;
      final summary = coastingOf(lap);
      if (summary != null &&
          summary.valid &&
          summary.provenance == drivingStateMeasured &&
          end > start) {
        coastSeconds = 0.0;
        coastMeters = 0.0;
        for (final episode in summary.episodes) {
          final at = episode.startProgressMeters;
          if (at == null || at < start - coachApproachMeters || at > end) continue;
          if (episode.seconds > coastSeconds!) {
            coastSeconds = episode.seconds;
            coastMeters = episode.meters;
          }
        }
      }
      passages.add(
        _Passage(
          lap: lap,
          order: order[lap.reference]!,
          seconds: seconds,
          spacing: speeds.meanSampleSpacingMeters,
          minimum: _metersPerSecond(speeds.minimum.value, speeds.unit),
          exit: _metersPerSecond(speeds.exit.value, speeds.unit),
          lift: lift,
          braking: braking,
          pickup: pickup,
          coastSeconds: coastSeconds,
          coastMeters: coastMeters,
        ),
      );
    }
    if (passages.length < 2) continue;
    for (final kind in CoachKind.values) {
      if (!kind.corrective) continue;
      final finding = _corrective(kind, corner, passages, coached);
      if (finding != null) findings.add(finding);
    }
    final improving = _improving(corner, passages, coached);
    if (improving != null) findings.add(improving);
  }
  final plan = _plan(findings);
  return DayCoach(
    runId: coached,
    findings: findings,
    plan: plan,
    message: plan.isEmpty
        ? 'No repeated pattern clears the confidence threshold. Repeat a consistent '
              'run to build a stronger comparison.'
        : 'Choose one focus at a time for your next run.',
  );
}

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
) {
  final observations = <_Observation>[];
  var metric = '', unit = '';
  for (final current in passages) {
    if (current.lap.runId != coached) continue;
    final faster =
        passages
            .where(
              (p) => p.lapSeconds < current.lapSeconds - 0.1 && p.seconds < current.seconds - 0.05,
            )
            .toList()
          ..sort((a, b) => a.seconds.compareTo(b.seconds));
    final references = faster.take(2).toList();
    if (references.isEmpty) continue;
    final resolution = references.map((r) => r.spacing).fold(current.spacing, math.max);
    final threshold = math.max(8.0, resolution * 2);
    double? observed;
    final values = <double>[];
    switch (kind) {
      case CoachKind.earlyLift:
        final lift = current.lift, braking = current.braking;
        if (lift == null || braking == null || braking - lift < 5) continue;
        observed = lift;
        metric = 'Lift point';
        unit = 'm';
        for (final r in references) {
          if (r.lift == null ||
              r.braking == null ||
              (r.braking! - braking).abs() > math.max(10.0, resolution * 2)) {
            continue;
          }
          values.add(r.lift!);
        }
        if (values.length != references.length || values.any((v) => v - lift < threshold)) {
          continue;
        }
      case CoachKind.excessiveCoasting:
        final coast = current.coastSeconds;
        metric = 'Longest coast';
        unit = 's';
        if (coast == null || coast < 0.7 || current.coastMeters! < threshold) continue;
        observed = coast;
        values.addAll(references.map((r) => r.coastSeconds).whereType<double>());
        if (values.length != references.length || values.any((v) => coast - v < 0.4)) continue;
      case CoachKind.lowMinimumSpeed:
        final minimum = current.minimum, exit = current.exit;
        metric = 'Minimum speed';
        unit = 'km/h';
        if (minimum == null ||
            exit == null ||
            references.any(
              (r) =>
                  r.minimum == null ||
                  r.exit == null ||
                  r.minimum! - minimum < 1.4 ||
                  exit > r.exit! + 0.5,
            )) {
          continue;
        }
        observed = minimum * 3.6;
        values.addAll(references.map((r) => r.minimum! * 3.6));
      case CoachKind.lateThrottle:
        final pickup = current.pickup;
        metric = 'Throttle return';
        unit = 'm';
        if (pickup == null || references.length < 2 || references.any((r) => r.pickup == null)) {
          continue;
        }
        observed = pickup;
        values.addAll(references.map((r) => r.pickup!));
        if (values.any((v) => pickup - v < threshold)) continue;
      case CoachKind.improving:
        continue;
    }
    observations.add((
      current: current,
      references: references,
      observed: observed,
      reference: _median(values),
    ));
  }
  final repeatedRequired = kind == CoachKind.lowMinimumSpeed || kind == CoachKind.lateThrottle;
  if (observations.isEmpty || (repeatedRequired && observations.length < 2)) return null;

  final referenceLaps = <DayLapRow>[];
  for (final o in observations) {
    for (final r in o.references) {
      if (!referenceLaps.any((lap) => lap.reference == r.lap.reference)) {
        referenceLaps.add(r.lap);
      }
    }
  }
  referenceLaps.sort((a, b) => a.start.compareTo(b.start));
  final spacing = observations.map((o) => o.current.spacing).reduce(math.max);
  var confidence =
      0.48 + math.min(observations.length, 3) * 0.09 + (referenceLaps.length >= 2 ? 0.08 : 0.03);
  if (spacing > 5) confidence -= 0.08;
  if (spacing > 10) confidence -= 0.12;
  // This app's coasting does not check longitudinal G.
  if (kind == CoachKind.excessiveCoasting) confidence -= 0.05;

  double medianOf(double Function(_Passage) read) =>
      _median(observations.map((o) => read(o.current)));
  double referenceOf(double Function(_Passage) read) =>
      _median(observations.map((o) => _median(o.references.map(read))));
  final evidence = [
    CoachEvidence(
      metric: metric,
      observed: _median(observations.map((o) => o.observed)),
      reference: _median(observations.map((o) => o.reference)),
      unit: unit,
      referenceLaps: referenceLaps,
      detail:
          'Median across affected laps; every comparison uses a faster lap and a faster '
          'passage through this segment. Positions are along the lap from start/finish on '
          'the day\'s shared axis.',
    ),
    CoachEvidence(
      metric: 'Segment time',
      observed: medianOf((p) => p.seconds),
      reference: referenceOf((p) => p.seconds),
      unit: 's',
      referenceLaps: referenceLaps,
      detail: 'Observed segment difference, not a predicted gain or a causal time-loss estimate.',
    ),
    if (observations.every(
      (o) => o.current.exit != null && o.references.every((r) => r.exit != null),
    ))
      CoachEvidence(
        metric: 'Exit speed',
        observed: medianOf((p) => p.exit! * 3.6),
        reference: referenceOf((p) => p.exit! * 3.6),
        unit: 'km/h',
        referenceLaps: referenceLaps,
        detail: 'Speed at the segment\'s exit.',
      ),
    if (kind == CoachKind.earlyLift)
      CoachEvidence(
        metric: 'Braking start',
        observed: medianOf((p) => p.braking!),
        reference: referenceOf((p) => p.braking!),
        unit: 'm',
        referenceLaps: referenceLaps,
        detail: 'Brake points must agree within 10 m or twice the source sample spacing.',
      ),
    if (kind == CoachKind.excessiveCoasting)
      CoachEvidence(
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
    affectedLaps: [for (final o in observations) o.current.lap],
  );
}

/// The last three consecutive laps of the coached session improving the
/// minimum speed or the throttle return, with the segment time, and
/// without losing exit speed.
CoachFinding? _improving(DayCorner corner, List<_Passage> passages, String coached) {
  final own = passages.where((p) => p.lap.runId == coached).toList()
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
    unit = 'km/h';
    before = ma * 3.6;
    after = mc * 3.6;
  } else if (pa != null &&
      pb != null &&
      pc != null &&
      pa - pb >= 4 &&
      pb - pc >= 4 &&
      pa - pc >= math.max(8.0, c.spacing * 2)) {
    metric = 'Throttle return';
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
    confidence: c.spacing > 5 ? 0.69 : 0.79,
    evidence: [
      CoachEvidence(
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
        metric: 'Exit speed',
        observed: c.exit! * 3.6,
        reference: a.exit! * 3.6,
        unit: 'km/h',
        referenceLaps: [a.lap],
        detail: 'No exit-speed drop greater than 1.8 km/h from one lap to the next.',
      ),
    ],
    affectedLaps: [for (final p in recent) p.lap],
  );
}

/// DrivingCoach's plan: findings at or above [coachPlanConfidence], an
/// improvement suppressing changes in its segment, repeated patterns first,
/// then confidence and the observed segment-time gap; one item per segment,
/// at most two changes and one improvement kept when there is one.
List<CoachItem> _plan(List<CoachFinding> findings) {
  final eligible = findings.where((f) => f.confidence >= coachPlanConfidence).toList();
  final improving = {
    for (final f in eligible)
      if (!f.kind.corrective) f.segmentId,
  };
  eligible.removeWhere((f) => f.kind.corrective && improving.contains(f.segmentId));
  double gap(CoachFinding f) {
    for (final e in f.evidence) {
      if (e.metric == 'Segment time') return e.observed - e.reference;
    }
    return 0.0;
  }

  eligible.sort((a, b) {
    final repeated = (b.repeated ? 1 : 0).compareTo(a.repeated ? 1 : 0);
    if (repeated != 0) return repeated;
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
    chosen.add(finding);
  }
  chosen.sort((a, b) => eligible.indexOf(a).compareTo(eligible.indexOf(b)));
  return [for (final finding in chosen) CoachItem(finding)];
}
