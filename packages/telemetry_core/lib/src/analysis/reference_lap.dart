// A reference lap from outside the day (FET-175): a friend's or an
// instructor's recording, or a lap of one of the driver's earlier days,
// timed on today's start/finish line and compared with today's laps A/B
// style. The reference never joins the day: nothing here touches a day's
// analysis, ranking, theoretical best, progression, coach or document.
//
// Lap detection and the comparison are called as they are: the reference's
// laps come from [detectLaps] on today's start gate, and the comparison is
// a [LapComparison] with today's lap as A and the reference as B, so Δ is
// today − reference (positive when today's lap is behind).
import 'dart:typed_data';

import '../day/compatibility.dart';
import '../day/track_inference.dart';
import '../channel_units.dart';
import '../geometry.dart';
import '../laps/lap_detection.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import '../speed_units.dart';
import '../telemetry_session.dart';
import '../timing_gate.dart';
import 'corner_analyzer.dart';
import 'lap_comparison.dart';

/// How close (metres) a reference recording's GPS must come to today's
/// start/finish line to be timed on it; farther, it is another track.
const double referenceMaximumGateDistanceMeters = 500.0;

/// How much of today's lap's track axis (a fraction) the reference lap's
/// projection must cover for a lap Δ to be shown; less, and the two laps do
/// not follow one line from start to finish. On the real Jastrząb day a
/// reference covers 99.9 %.
const double referenceMinimumCoverage = 0.97;

/// Seconds of a reference recording kept either side of its candidate laps.
const double referenceTrimMarginSeconds = 5.0;

/// A lap of an earlier day whose start and end are each within this many
/// seconds of an excluded lap of that day is that lap.
const double referenceExclusionMatchSeconds = 1.0;

/// Why a reference cannot be timed on today's line.
enum ReferenceRefusal {
  /// It can: [ReferenceTiming.candidates] holds its laps.
  none,

  /// Today's start/finish line is not a valid gate.
  invalidGate,

  /// No recording has a usable GPS position.
  noGps,

  /// Its GPS never comes within [referenceMaximumGateDistanceMeters] of
  /// today's line: another track.
  wrongTrack,

  /// It is near today's line, but no complete lap of it crosses it.
  noTimedLap,

  /// Its laps go round today's route the other way.
  oppositeDirection,

  /// Its laps cross today's line but follow another layout.
  differentLayout,

  /// Every lap it has on today's route was excluded on its own day.
  onlyExcludedLaps,
}

/// What became of one recording of a reference.
enum ReferenceRecordingStatus {
  /// It has laps on today's line and route: kept.
  timed,

  /// No usable GPS position.
  noGps,

  /// Its GPS never comes within the distance limit of today's line.
  tooFar,

  /// Near the line, but no complete eligible lap crosses it.
  noTimedLap,

  /// Its laps go round today's route the other way.
  oppositeDirection,

  /// Its laps follow another layout.
  differentLayout,
}

/// Today's start/finish line and route, which a reference is timed on and
/// checked against.
final class ReferenceLine {
  const ReferenceLine({required this.gate, this.westPositive = false, this.route});

  /// Today's start/finish line, in the frame of today's GPS.
  final TimingGate gate;

  /// Today's recording gives longitudes west-positive (a VBO); a reference
  /// in the other convention is mirrored into today's frame.
  final bool westPositive;

  /// Today's lap's route; null when today's lap has none, and then laps are
  /// not checked against it.
  final RouteShape? route;

  /// The origin route shapes are measured around, as [inferTrack] does.
  GeoCoordinate get origin {
    final midpoint = geoMidpoint(gate.endpointA, gate.endpointB);
    return GeoCoordinate(
      midpoint.latitudeDegrees,
      (westPositive ? -1 : 1) * midpoint.longitudeDegrees,
    );
  }

  /// Whether laps timed on [other] are timed on this line: the same
  /// endpoints, once in one longitude convention. The route is not
  /// compared.
  bool sameLine(ReferenceLine? other) =>
      other != null && sameGate(other.gate, westPositive: other.westPositive);

  /// Whether [gate], given in the convention [westPositive] (this line's
  /// when null), has this line's endpoints.
  bool sameGate(TimingGate? gate, {bool? westPositive}) {
    if (gate == null) return false;
    final mirror = westPositive != null && westPositive != this.westPositive;
    GeoCoordinate frame(GeoCoordinate point) => mirror ? _mirrored(point) : point;
    return frame(gate.endpointA) == this.gate.endpointA &&
        frame(gate.endpointB) == this.gate.endpointB;
  }
}

/// Whether [session] gives longitudes west-positive (a VBO).
bool longitudeWestPositive(TelemetrySession session) =>
    session.metadata['gpsLongitudeConvention'] == 'west-positive';

/// Today's line from lap [lapNumber] of [laps] in [session]: its start gate
/// and the lap's route. Null without a start gate.
ReferenceLine? referenceLineOf(TelemetrySession session, LapSession laps, int lapNumber) {
  final gate = laps.selectedStartGate;
  if (gate == null) return null;
  final westPositive = longitudeWestPositive(session);
  final line = ReferenceLine(gate: gate, westPositive: westPositive);
  for (final trace in laps.lapTraces) {
    if (trace.lapNumber != lapNumber) continue;
    return ReferenceLine(
      gate: gate,
      westPositive: westPositive,
      route: lapRouteShape(trace, line.origin, westPositive: westPositive),
    );
  }
  return line;
}

/// An excluded lap of an earlier day, by its recording times.
typedef ReferenceExclusion = ({double start, double end, String reason});

/// One recording a reference may come from: a file, or one session of an
/// earlier day.
final class ReferenceRecording {
  const ReferenceRecording({
    required this.label,
    required this.session,
    this.id = '',
    this.exclusions = const [],
  });

  /// The file's name or the session's name ("Session 2"), as recorded.
  final String label;

  /// What identifies the recording within its source without a path: the
  /// run id of an earlier day's session, or the file's name.
  final String id;

  /// As parsed: units as the recording declares them. Once timed, mirrored
  /// into today's longitude convention and trimmed to its laps.
  final TelemetrySession session;

  /// The laps its day excluded; none for a file.
  final List<ReferenceExclusion> exclusions;
}

/// A timed lap of a reference recording on today's line.
final class ReferenceLapCandidate {
  const ReferenceLapCandidate({
    required this.recordingIndex,
    required this.recordingLabel,
    required this.lapNumber,
    required this.start,
    required this.end,
    this.recordingId = '',
    this.distanceMeters,
    this.excludedReason,
  });

  /// Its recording in [ReferenceTiming.recordings].
  final int recordingIndex;
  final String recordingLabel;

  /// [ReferenceRecording.id] of its recording.
  final String recordingId;

  /// Its number among the laps of its recording on today's line.
  final int lapNumber;

  /// Recording time in seconds.
  final double start;
  final double end;
  final double? distanceMeters;

  /// Why its day excluded it ('' without a reason); null when it was not
  /// excluded. An excluded lap is never the fastest, but can be chosen.
  final String? excludedReason;

  bool get excluded => excludedReason != null;

  double get durationSeconds => end - start;
}

/// A reference's recordings timed on today's start/finish line, or why
/// they could not be.
final class ReferenceTiming {
  ReferenceTiming._({
    required this.refusal,
    required this.line,
    this.nearestGateDistanceMeters,
    List<ReferenceRecordingStatus> statuses = const [],
    List<ReferenceRecording> recordings = const [],
    List<LapSession> laps = const [],
    List<ReferenceLapCandidate> candidates = const [],
  }) : statuses = List.unmodifiable(statuses),
       recordings = List.unmodifiable(recordings),
       laps = List.unmodifiable(laps),
       candidates = List.unmodifiable(candidates);

  final ReferenceRefusal refusal;

  /// Today's line and route the laps were timed and checked on.
  final ReferenceLine line;

  /// Today's start/finish line the laps were timed on.
  TimingGate get gate => line.gate;

  /// The closest any recording's GPS came to the line's centre; null
  /// without GPS.
  final double? nearestGateDistanceMeters;

  /// What became of each recording given, in the order given.
  final List<ReferenceRecordingStatus> statuses;

  /// The recordings with candidate laps only, mirrored into today's
  /// longitude convention and trimmed to their candidates' span: the rest
  /// is not kept.
  final List<ReferenceRecording> recordings;

  /// Each kept recording's laps on [gate], in [recordings] order.
  final List<LapSession> laps;

  /// Every complete lap on today's line and route, in recording order;
  /// also with [ReferenceRefusal.onlyExcludedLaps], so one can be chosen.
  final List<ReferenceLapCandidate> candidates;

  /// Today's lap had no route shape, so the laps were not checked against
  /// today's route.
  bool get routeUnchecked => line.route == null;

  bool get usable => refusal == ReferenceRefusal.none && candidates.isNotEmpty;

  /// The fastest of [candidates] not excluded on its day: the reference
  /// unless the driver picks another; null when there is none.
  ReferenceLapCandidate? get fastest {
    ReferenceLapCandidate? best;
    for (final candidate in candidates) {
      if (candidate.excluded) continue;
      if (best == null || candidate.durationSeconds < best.durationSeconds) best = candidate;
    }
    return best;
  }
}

/// The closest [session]'s GPS comes to [origin], in metres; null without
/// a valid fix.
double? _nearestDistance(
  TelemetrySession session,
  GeoCoordinate origin,
  CancellationCheck? cancelled,
) {
  final latitude = session.channels[session.aliases['latitude']];
  final longitude = session.channels[session.aliases['longitude']];
  if (latitude == null || longitude == null) return null;
  final count = latitude.values.length < longitude.values.length
      ? latitude.values.length
      : longitude.values.length;
  double? nearest;
  for (var index = 0; index < count; ++index) {
    if ((index & 0xfff) == 0) throwIfCancelled(cancelled);
    final coordinate = GeoCoordinate(latitude.values[index], longitude.values[index]);
    if (!isValidCoordinate(coordinate)) continue;
    // A position of exactly 0, 0 is a missing fix, not the Gulf of Guinea.
    if (coordinate.latitudeDegrees == 0.0 && coordinate.longitudeDegrees == 0.0) continue;
    final point = projectCoordinate(coordinate, origin);
    final distance = hypot(point.eastMeters, point.northMeters);
    if (!distance.isFinite) continue;
    if (nearest == null || distance < nearest) nearest = distance;
  }
  return nearest;
}

GeoCoordinate _mirrored(GeoCoordinate coordinate) =>
    GeoCoordinate(coordinate.latitudeDegrees, -coordinate.longitudeDegrees);

/// [session] with its longitudes in the convention [westPositive], as
/// [otherEligibleLapTraces] puts every run in one frame: a west-positive
/// VBO and an east-positive RCZ of one track are then on one line. The same
/// session when it already is.
TelemetrySession inLongitudeConvention(TelemetrySession session, {required bool westPositive}) {
  if (longitudeWestPositive(session) == westPositive) return session;
  final name = session.aliases['longitude'];
  final channel = session.channels[name];
  final values = Float32List(channel?.values.length ?? 0);
  for (var index = 0; index < values.length; ++index) {
    values[index] = -channel!.values[index];
  }
  final metadata = Map.of(session.metadata);
  if (westPositive) {
    metadata['gpsLongitudeConvention'] = 'west-positive';
  } else {
    metadata['gpsLongitudeConvention'] = 'east-positive';
  }
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: metadata,
    channels: {
      ...session.channels,
      if (channel != null)
        name!: TelemetryChannel(
          name: channel.name,
          unit: channel.unit,
          timestamps: channel.timestamps,
          values: adoptChannelValues(values),
        ),
    },
    aliases: session.aliases,
    warnings: session.warnings,
    timingGates: [
      for (final gate in session.timingGates)
        TimingGate(
          type: gate.type,
          sourceName: gate.sourceName,
          endpointA: _mirrored(gate.endpointA),
          endpointB: _mirrored(gate.endpointB),
          sourceDescription: gate.sourceDescription,
        ),
    ],
    sampleCount: session.sampleCount,
  );
}

/// [shape] driven the other way round.
RouteShape _reversed(RouteShape shape) => RouteShape(
  origin: shape.origin,
  points: List.unmodifiable(shape.points.reversed),
  lengthMeters: shape.lengthMeters,
  direction: shape.direction == TrackDirection.clockwise
      ? TrackDirection.counterclockwise
      : TrackDirection.clockwise,
);

/// [session]'s samples from [from] to [to] seconds, on its own clock.
TelemetrySession _trimmed(TelemetrySession session, double from, double to) {
  final channels = <String, TelemetryChannel>{};
  var samples = 0;
  session.channels.forEach((name, channel) {
    final first = lowerBound(channel.timestamps, from);
    var last = lowerBound(channel.timestamps, to, first);
    if (last < channel.timestamps.length && channel.timestamps[last] <= to) ++last;
    samples = last - first > samples ? last - first : samples;
    channels[name] = TelemetryChannel(
      name: channel.name,
      unit: channel.unit,
      timestamps: adoptChannelTimestamps(
        Float64List.fromList(Float64List.sublistView(channel.timestamps, first, last)),
      ),
      values: adoptChannelValues(
        Float32List.fromList(Float32List.sublistView(channel.values, first, last)),
      ),
    );
  });
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: session.metadata,
    channels: channels,
    aliases: session.aliases,
    warnings: session.warnings,
    timingGates: session.timingGates,
    sampleCount: samples,
  );
}

/// Times [recordings] on today's start/finish line [line] with the lap
/// detection the day uses ([detectLaps], unchanged), each first mirrored
/// into today's longitude convention. A recording whose GPS never comes
/// within [maximumGateDistanceMeters] of the line is not timed; when none
/// does, the reference is refused as another track. Only laps eligible as a
/// reference (complete GPS, plausible) that follow today's route in its
/// direction ([routesMatch]) are candidates; a lap its day excluded is
/// marked. Only recordings with candidates are kept, trimmed to them.
ReferenceTiming timeReferenceLaps(
  List<ReferenceRecording> recordings,
  ReferenceLine line, {
  double maximumGateDistanceMeters = referenceMaximumGateDistanceMeters,
  CancellationCheck? cancelled,
}) {
  throwIfCancelled(cancelled);
  final gate = line.gate;
  final origin = geoMidpoint(gate.endpointA, gate.endpointB);
  if (!isValidCoordinate(gate.endpointA) ||
      !isValidCoordinate(gate.endpointB) ||
      !isValidCoordinate(origin)) {
    return ReferenceTiming._(refusal: ReferenceRefusal.invalidGate, line: line);
  }
  double? nearest;
  final statuses = <ReferenceRecordingStatus>[];
  final kept = <ReferenceRecording>[];
  final laps = <LapSession>[];
  final candidates = <ReferenceLapCandidate>[];
  final route = line.route;
  for (final recording in recordings) {
    final session = inLongitudeConvention(recording.session, westPositive: line.westPositive);
    final distance = _nearestDistance(session, origin, cancelled);
    if (distance != null && (nearest == null || distance < nearest)) nearest = distance;
    if (distance == null) {
      statuses.add(ReferenceRecordingStatus.noGps);
      continue;
    }
    if (distance > maximumGateDistanceMeters) {
      statuses.add(ReferenceRecordingStatus.tooFar);
      continue;
    }
    final timed = detectLaps(session, gate, cancelled: cancelled);
    final traces = {for (final trace in timed.lapTraces) trace.lapNumber: trace};
    final own = <ReferenceLapCandidate>[];
    var eligible = 0, opposite = 0;
    for (final lap in timed.timedLaps) {
      if (!lap.referenceEligible) continue;
      ++eligible;
      if (route != null) {
        final trace = traces[lap.number];
        final shape = trace == null
            ? null
            : lapRouteShape(trace, line.origin, westPositive: line.westPositive);
        if (shape == null || !routesMatch(route, shape, cancelled: cancelled)) {
          // Today's route driven the other way round.
          if (shape != null && routesMatch(route, _reversed(shape), cancelled: cancelled)) {
            ++opposite;
          }
          continue;
        }
      }
      String? excludedReason;
      for (final exclusion in recording.exclusions) {
        if ((exclusion.start - lap.startTelemetryTime).abs() <= referenceExclusionMatchSeconds &&
            (exclusion.end - lap.endTelemetryTime).abs() <= referenceExclusionMatchSeconds) {
          excludedReason = exclusion.reason;
          break;
        }
      }
      own.add(
        ReferenceLapCandidate(
          recordingIndex: kept.length,
          recordingLabel: recording.label,
          recordingId: recording.id,
          lapNumber: lap.number,
          start: lap.startTelemetryTime,
          end: lap.endTelemetryTime,
          distanceMeters: lap.distanceMeters,
          excludedReason: excludedReason,
        ),
      );
    }
    if (own.isEmpty) {
      statuses.add(
        eligible == 0
            ? ReferenceRecordingStatus.noTimedLap
            : opposite > 0
            ? ReferenceRecordingStatus.oppositeDirection
            : ReferenceRecordingStatus.differentLayout,
      );
      continue;
    }
    statuses.add(ReferenceRecordingStatus.timed);
    var from = own.first.start, to = own.first.end;
    for (final lap in own) {
      if (lap.start < from) from = lap.start;
      if (lap.end > to) to = lap.end;
    }
    kept.add(
      ReferenceRecording(
        label: recording.label,
        id: recording.id,
        exclusions: recording.exclusions,
        session: _trimmed(
          session,
          from - referenceTrimMarginSeconds,
          to + referenceTrimMarginSeconds,
        ),
      ),
    );
    laps.add(timed);
    candidates.addAll(own);
  }
  final ReferenceRefusal refusal;
  if (nearest == null) {
    refusal = ReferenceRefusal.noGps;
  } else if (nearest > maximumGateDistanceMeters) {
    refusal = ReferenceRefusal.wrongTrack;
  } else if (candidates.isEmpty) {
    refusal = statuses.contains(ReferenceRecordingStatus.oppositeDirection)
        ? ReferenceRefusal.oppositeDirection
        : statuses.contains(ReferenceRecordingStatus.differentLayout)
        ? ReferenceRefusal.differentLayout
        : ReferenceRefusal.noTimedLap;
  } else if (candidates.every((lap) => lap.excluded)) {
    refusal = ReferenceRefusal.onlyExcludedLaps;
  } else {
    refusal = ReferenceRefusal.none;
  }
  // Laps its day excluded can still be chosen on purpose.
  final usable = refusal == ReferenceRefusal.none || refusal == ReferenceRefusal.onlyExcludedLaps;
  return ReferenceTiming._(
    refusal: refusal,
    line: line,
    nearestGateDistanceMeters: nearest,
    statuses: statuses,
    recordings: usable ? kept : const [],
    laps: usable ? laps : const [],
    candidates: usable ? candidates : const [],
  );
}

/// The unit one side of a reference comparison reads a channel in.
final class ReferenceUnit {
  const ReferenceUnit({
    this.recorded = false,
    this.unit = '',
    this.assumed = false,
    this.speed = false,
  });

  /// The side recorded the channel.
  final bool recorded;

  /// The unit analysis reads it in: the one its recording declares, else,
  /// for a speed, the one assumed in settings; empty when neither says.
  final String unit;

  /// [unit] is the assumption for an unlabelled speed, not declared.
  final bool assumed;

  /// The channel is a speed.
  final bool speed;
}

/// The units today's lap and the reference read a channel in, and whether
/// their values can be drawn on one axis or subtracted.
final class ReferenceChannelUnits {
  const ReferenceChannelUnits({required this.today, required this.reference});

  final ReferenceUnit today;
  final ReferenceUnit reference;

  /// Both recorded it in one unit ([sameSpeedUnit] for a speed): never
  /// pooled or subtracted otherwise. A speed needs a unit on both sides,
  /// declared or the assumption stated in settings: two unlabelled speeds
  /// from two loggers may be in different units.
  bool get comparable {
    if (!today.recorded || !reference.recorded) return false;
    if ((today.speed || reference.speed) && (today.unit.isEmpty || reference.unit.isEmpty)) {
      return false;
    }
    return sameSpeedUnit(today.unit, reference.unit);
  }
}

ReferenceUnit _unitOf(TelemetrySession session, String channel, String assumed) {
  final name = session.aliases[channel] ?? channel;
  final found = session.channels[name];
  if (found == null) return const ReferenceUnit();
  if (!isSessionSpeedChannel(session, name)) {
    // As declared: the channel's own unit, else the VBO [header] line.
    return ReferenceUnit(recorded: true, unit: declaredChannelUnit(session, name));
  }
  final declared = declaredSpeedUnit(session, name);
  if (declared.isNotEmpty) return ReferenceUnit(recorded: true, unit: declared, speed: true);
  final unit = normalizedSpeedUnit(assumed);
  return ReferenceUnit(recorded: true, unit: unit, assumed: unit.isNotEmpty, speed: true);
}

/// The units [today] and [reference] (both as parsed, so a declared unit
/// is told from an assumed one) read [channel] (a channel or an alias such
/// as `speed`) in, with [assumed] the unit assumed in settings for
/// unlabelled speeds.
ReferenceChannelUnits referenceChannelUnits(
  TelemetrySession today,
  TelemetrySession reference,
  String channel, {
  String assumed = '',
}) => ReferenceChannelUnits(
  today: _unitOf(today, channel, assumed),
  reference: _unitOf(reference, channel, assumed),
);

/// One segment of today's lap against the reference.
final class ReferenceSegmentTime {
  const ReferenceSegmentTime({
    required this.segment,
    this.todaySeconds,
    this.referenceSeconds,
    this.deltaSeconds,
    this.unavailableReason = '',
  });

  final ComparisonSegment segment;
  final double? todaySeconds;
  final double? referenceSeconds;

  /// Today − reference; positive when today's lap is behind. Null with
  /// [unavailableReason].
  final double? deltaSeconds;
  final String unavailableReason;
}

/// Today's lap (A) against a reference lap (B) on today's lap's track
/// axis, measured on [segmentation] (today's segments).
final class ReferenceLapComparison {
  ReferenceLapComparison({
    required this.today,
    required this.timing,
    required this.lap,
    required TelemetrySession referenceSession,
    this.segmentation = const ComparisonSegmentation(),
    this.cancelled,
  }) : reference = ComparisonLap(
         session: referenceSession,
         laps: timing.laps[lap.recordingIndex],
         start: lap.start,
         end: lap.end,
         lapNumber: lap.lapNumber,
       );

  final ComparisonLap today;
  final ReferenceTiming timing;
  final ReferenceLapCandidate lap;

  /// [lap] as lap B of the comparison.
  final ComparisonLap reference;
  final ComparisonSegmentation segmentation;
  final CancellationCheck? cancelled;

  /// The A/B comparison: today's lap A, the reference B.
  late final LapComparison comparison = LapComparison(today, reference, cancelled: cancelled);

  late final CornerAnalyzer _analyzer = CornerAnalyzer.of(comparison, segmentation);

  /// The fraction of today's lap's track axis the reference lap's
  /// projection covers: 0 without an axis.
  late final double coverage = () {
    final axis = comparison.axis;
    if (!axis.valid || axis.lengthMeters <= 0) return 0.0;
    final ranges = [
      for (final segment in comparison.trace(1))
        if (segment.samples.isNotEmpty)
          (segment.samples.first.progressMeters, segment.samples.last.progressMeters),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    var covered = 0.0, reached = 0.0;
    for (final (start, end) in ranges) {
      final from = start > reached ? start : reached;
      final to = end < axis.lengthMeters ? end : axis.lengthMeters;
      if (to > from) covered += to - from;
      if (to > reached) reached = to;
    }
    return (covered / axis.lengthMeters).clamp(0.0, 1.0);
  }();

  /// Today's lap time − the reference's; null when the reference lap covers
  /// less than [referenceMinimumCoverage] of today's lap's line, so the two
  /// are not the same lap of one track.
  double? get lapDeltaSeconds =>
      coverage < referenceMinimumCoverage ? null : (today.end - today.start) - lap.durationSeconds;

  /// Each of today's segments timed on both laps, in approved order; empty
  /// without segments or a shared axis.
  List<ReferenceSegmentTime> segmentTimes() {
    if (!comparison.axis.valid || segmentation.shared == null) return const [];
    return [
      for (final segment in _analyzer.segments)
        if (_analyzer.analyze(segment.id)?.sectorTime case final time?)
          ReferenceSegmentTime(
            segment: segment,
            todaySeconds: time.a.value,
            referenceSeconds: time.b.value,
            deltaSeconds: time.delta.value,
            unavailableReason: time.delta.value != null
                ? ''
                : time.delta.unavailableReason.isNotEmpty
                ? time.delta.unavailableReason
                : time.a.unavailableReason.isNotEmpty
                ? time.a.unavailableReason
                : time.b.unavailableReason,
          )
        else
          ReferenceSegmentTime(segment: segment, unavailableReason: analyzerIncompleteCoverage),
    ];
  }
}
