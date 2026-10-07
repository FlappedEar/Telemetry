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
}

/// One recording a reference may come from: a file, or one session of an
/// earlier day.
final class ReferenceRecording {
  const ReferenceRecording({required this.label, required this.session});

  /// The file's name or the session's name ("Session 2"), as recorded.
  final String label;

  /// As parsed: units as the recording declares them.
  final TelemetrySession session;
}

/// A timed lap of a reference recording on today's line.
final class ReferenceLapCandidate {
  const ReferenceLapCandidate({
    required this.recordingIndex,
    required this.recordingLabel,
    required this.lapNumber,
    required this.start,
    required this.end,
    this.distanceMeters,
  });

  /// Its recording in [ReferenceTiming.recordings].
  final int recordingIndex;
  final String recordingLabel;

  /// Its number among the laps of its recording on today's line.
  final int lapNumber;

  /// Recording time in seconds.
  final double start;
  final double end;
  final double? distanceMeters;

  double get durationSeconds => end - start;
}

/// A reference's recordings timed on today's start/finish line, or why
/// they could not be.
final class ReferenceTiming {
  ReferenceTiming._({
    required this.refusal,
    required this.gate,
    this.nearestGateDistanceMeters,
    List<ReferenceRecording> recordings = const [],
    List<LapSession> laps = const [],
    List<ReferenceLapCandidate> candidates = const [],
  }) : recordings = List.unmodifiable(recordings),
       laps = List.unmodifiable(laps),
       candidates = List.unmodifiable(candidates);

  final ReferenceRefusal refusal;

  /// Today's start/finish line the laps were timed on.
  final TimingGate gate;

  /// The closest any recording's GPS came to the line's centre; null
  /// without GPS.
  final double? nearestGateDistanceMeters;
  final List<ReferenceRecording> recordings;

  /// Each recording's laps on [gate], in [recordings] order (no laps for a
  /// recording too far from it).
  final List<LapSession> laps;

  /// Every complete lap eligible as a reference, in recording order.
  final List<ReferenceLapCandidate> candidates;

  bool get usable => refusal == ReferenceRefusal.none && candidates.isNotEmpty;

  /// The fastest of [candidates]: the reference unless the driver picks
  /// another; null when there is none.
  ReferenceLapCandidate? get fastest {
    ReferenceLapCandidate? best;
    for (final candidate in candidates) {
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

/// Times [recordings] on today's start/finish line [gate] with the lap
/// detection the day uses ([detectLaps], unchanged). A recording whose GPS
/// never comes within [maximumGateDistanceMeters] of the line is not timed;
/// when none does, the reference is refused as another track. Only laps
/// eligible as a reference (complete GPS, plausible) are candidates.
ReferenceTiming timeReferenceLaps(
  List<ReferenceRecording> recordings,
  TimingGate gate, {
  double maximumGateDistanceMeters = referenceMaximumGateDistanceMeters,
  CancellationCheck? cancelled,
}) {
  throwIfCancelled(cancelled);
  final origin = geoMidpoint(gate.endpointA, gate.endpointB);
  if (!isValidCoordinate(gate.endpointA) ||
      !isValidCoordinate(gate.endpointB) ||
      !isValidCoordinate(origin)) {
    return ReferenceTiming._(refusal: ReferenceRefusal.invalidGate, gate: gate);
  }
  double? nearest;
  final laps = <LapSession>[];
  final candidates = <ReferenceLapCandidate>[];
  for (var index = 0; index < recordings.length; ++index) {
    final recording = recordings[index];
    final distance = _nearestDistance(recording.session, origin, cancelled);
    if (distance != null && (nearest == null || distance < nearest)) nearest = distance;
    if (distance == null || distance > maximumGateDistanceMeters) {
      laps.add(LapSession(status: LapSessionStatus.noUsableGps, selectedStartGate: gate));
      continue;
    }
    final session = detectLaps(recording.session, gate, cancelled: cancelled);
    laps.add(session);
    for (final lap in session.timedLaps) {
      if (!lap.referenceEligible) continue;
      candidates.add(
        ReferenceLapCandidate(
          recordingIndex: index,
          recordingLabel: recording.label,
          lapNumber: lap.number,
          start: lap.startTelemetryTime,
          end: lap.endTelemetryTime,
          distanceMeters: lap.distanceMeters,
        ),
      );
    }
  }
  final refusal = nearest == null
      ? ReferenceRefusal.noGps
      : nearest > maximumGateDistanceMeters
      ? ReferenceRefusal.wrongTrack
      : candidates.isEmpty
      ? ReferenceRefusal.noTimedLap
      : ReferenceRefusal.none;
  return ReferenceTiming._(
    refusal: refusal,
    gate: gate,
    nearestGateDistanceMeters: nearest,
    recordings: recordings,
    laps: laps,
    candidates: refusal == ReferenceRefusal.none ? candidates : const [],
  );
}

/// The unit one side of a reference comparison reads a channel in.
final class ReferenceUnit {
  const ReferenceUnit({this.recorded = false, this.unit = '', this.assumed = false});

  /// The side recorded the channel.
  final bool recorded;

  /// The unit analysis reads it in: the one its recording declares, else,
  /// for a speed, the one assumed in settings; empty when neither says.
  final String unit;

  /// [unit] is the assumption for an unlabelled speed, not declared.
  final bool assumed;
}

/// The units today's lap and the reference read a channel in, and whether
/// their values can be drawn on one axis or subtracted.
final class ReferenceChannelUnits {
  const ReferenceChannelUnits({required this.today, required this.reference});

  final ReferenceUnit today;
  final ReferenceUnit reference;

  /// Both recorded it in one unit ([sameSpeedUnit] for a speed): never
  /// pooled or subtracted otherwise.
  bool get comparable {
    if (!today.recorded || !reference.recorded) return false;
    return sameSpeedUnit(today.unit, reference.unit);
  }
}

ReferenceUnit _unitOf(TelemetrySession session, String channel, String assumed) {
  final name = session.aliases[channel] ?? channel;
  final found = session.channels[name];
  if (found == null) return const ReferenceUnit();
  if (!isSessionSpeedChannel(session, name)) {
    return ReferenceUnit(recorded: true, unit: found.unit.trim());
  }
  final declared = declaredSpeedUnit(session, name);
  if (declared.isNotEmpty) return ReferenceUnit(recorded: true, unit: declared);
  final unit = normalizedSpeedUnit(assumed);
  return ReferenceUnit(recorded: true, unit: unit, assumed: unit.isNotEmpty);
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

  /// Today's lap time − the reference's.
  double get lapDeltaSeconds => (today.end - today.start) - lap.durationSeconds;

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
