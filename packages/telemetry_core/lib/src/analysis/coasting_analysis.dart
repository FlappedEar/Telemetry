// Port of FlappedEar Overlays native/src/telemetry/CoastingAnalysis.{h,cpp}
// (revision d4d1039, FET-39): where and how long a lap coasts (time at
// speed with neither pedal active, see driving_states.dart) per episode,
// per approved segment and for the lap (KAN-92). An observation, not a
// verdict: coasting is sometimes the right thing to do (a lift to settle the
// car, traffic), so nothing here calls it a loss.
import '../telemetry_session.dart';
import 'driving_states.dart';
import 'track_progress.dart';
import 'track_segment_review.dart' show ApprovedSegmentation;

const String coastingAlgorithm = 'coasting-v1';

/// One coasting episode.
final class CoastingEpisode {
  CoastingEpisode(this.startTime, this.endTime) : seconds = endTime - startTime;

  final double startTime;
  final double endTime;
  final double seconds;

  /// Speed integrated over the episode.
  double meters = 0.0;
  double? startProgressMeters;
  double? endProgressMeters;

  /// The approved segment where it starts; empty when none.
  String segmentId = '';
}

/// Coasting inside one approved segment.
final class CoastingSegment {
  CoastingSegment(this.segmentId, this.name, this.type);

  final String segmentId;
  final String name;
  final String type;
  double seconds = 0.0;
  double meters = 0.0;
  int episodes = 0;
}

final class CoastingSummary {
  String algorithm = coastingAlgorithm;

  /// `measured` when both pedals are recorded, `inferred` when derived from
  /// acceleration, `unknown` when it cannot be told (see [unresolvedReason]).
  String provenance = drivingStateUnknown;
  String unresolvedReason = '';
  double lapSeconds = 0.0;

  /// Time the pedal states and speed were known.
  double knownSeconds = 0.0;

  /// Where they were known.
  final List<DrivingStateInterval> known = [];
  double coastingSeconds = 0.0;
  double coastingMeters = 0.0;
  final List<CoastingEpisode> episodes = [];

  /// Approved segments in axis order, with zero rows kept.
  final List<CoastingSegment> segments = [];
  bool valid = false;
}

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

String _string(Object? value) => value is String ? value : '';

bool _contains(Map<String, Object?> segment, double progress) {
  final start = _number(segment['startProgressMeters']);
  final end = _number(segment['endProgressMeters']);
  // A segment across start/finish has end < start.
  return start <= end ? progress >= start && progress < end : progress >= start || progress < end;
}

/// Coasting over [startTime]..[endTime]. [lapTrace] maps time to the lap's
/// progress (episode positions, segment attribution); [approved] gives the
/// segments to attribute to. Either may be null: the lap totals remain.
CoastingSummary summarizeCoasting(
  TelemetrySession session,
  double startTime,
  double endTime, {
  List<ProgressSegment>? lapTrace,
  ApprovedSegmentation? approved,
  DrivingStateOptions options = const DrivingStateOptions(),
}) {
  final summary = CoastingSummary();
  final states = classifyDrivingStates(session, startTime, endTime, options);
  if (!states.valid) return summary;
  summary.valid = true;
  summary.lapSeconds = endTime - startTime;
  summary.provenance = states.coasting.provenance;
  summary.unresolvedReason = states.coasting.unresolvedReason;
  for (final known in states.coasting.known) {
    summary.knownSeconds += known.end - known.start;
    summary.known.add(known);
  }
  final segments = <Map<String, Object?>>[];
  if (approved != null) {
    for (final segment in approved.segments) {
      segments.add(segment);
      summary.segments.add(
        CoastingSegment(_string(segment['id']), _string(segment['name']), _string(segment['type'])),
      );
    }
  }
  int segmentAt(double time) {
    if (lapTrace == null || segments.isEmpty) return -1;
    final progress = progressAtTime(lapTrace, time);
    if (progress == null) return -1;
    for (var i = 0; i < segments.length; ++i) {
      if (_contains(segments[i], progress)) return i;
    }
    return -1;
  }

  final speedChannel = session.channels[session.aliases['speed'] ?? ''];
  for (final interval in states.coasting.active) {
    final episode = CoastingEpisode(interval.start, interval.end);
    if (lapTrace != null) {
      episode.startProgressMeters = progressAtTime(lapTrace, interval.start);
      episode.endProgressMeters = progressAtTime(lapTrace, interval.end);
    }
    final startSegment = segmentAt(interval.start);
    if (startSegment >= 0) {
      episode.segmentId = summary.segments[startSegment].segmentId;
      ++summary.segments[startSegment].episodes;
    }
    // Distance and segment shares from the speed samples inside the episode.
    if (speedChannel != null) {
      final times = speedChannel.timestamps;
      final values = speedChannel.values;
      for (
        var index = lowerBound(times, interval.start);
        index + 1 < times.length && times[index + 1] <= interval.end;
        ++index
      ) {
        final double a = values[index], b = values[index + 1];
        if (!a.isFinite || !b.isFinite) continue;
        final seconds = times[index + 1] - times[index];
        final meters = (a + b) / 2.0 / 3.6 * seconds;
        episode.meters += meters;
        final segment = segmentAt((times[index] + times[index + 1]) / 2.0);
        if (segment >= 0) {
          summary.segments[segment].seconds += seconds;
          summary.segments[segment].meters += meters;
        }
      }
    }
    summary.coastingSeconds += episode.seconds;
    summary.coastingMeters += episode.meters;
    summary.episodes.add(episode);
  }
  return summary;
}
