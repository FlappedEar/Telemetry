// The G-G envelope of each session of a day (FET-230): how much combined
// grip the driver used in each direction (braking, accelerating, turning
// and the combinations), session by session, and the directions in which
// the latest session stays short of the day's best envelope.
//
// Built on the G-G pairs of the comparison page (`gg_pairs.dart`): the same
// channels (`longitudinalAcceleration` and `lateralAcceleration` aliases),
// units, gap rule and outlier limit. Only the laps the caller passes count;
// the day cards pass the shown group's eligible laps, so out laps, in laps
// and excluded laps are left out.
//
// Per direction the envelope is the 95th percentile of the combined G
// sqrt(longitudinal² + lateral²) of the samples pointing that way, not the
// peak, so one noisy sample does not set it. A sample below
// [ggEnvelopeMinimumG] has no meaningful direction and is left out. A
// direction with fewer than [ggEnvelopeMinimumSamples] samples has no value.
// Observed accelerations, not a share of available grip.
import 'dart:math' as math;

import '../analysis/gg_pairs.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import 'day_channel_summaries.dart' show channelRecordingUnavailable;
import 'day_laps.dart';

const String ggEnvelopeAlgorithm = 'gg-envelope-v1';

/// The percentile of combined G that makes a direction's envelope.
const double ggEnvelopePercentile = 0.95;

/// Samples with a smaller combined G have no meaningful direction.
const double ggEnvelopeMinimumG = 0.1;

/// Samples a direction needs for a value.
const int ggEnvelopeMinimumSamples = 25;

/// The latest session leaves a direction's envelope unused when it stays
/// this far below the day's best in that direction (both in g).
const double ggEnvelopeUnusedMarginG = 0.1;

/// Why a session has no envelope, besides the G-G pairs' own reasons
/// ([ggMissingLongitudinal], [ggMissingLateral], [ggUnsupportedUnit],
/// [ggNoOverlap]) and [channelRecordingUnavailable].
const String ggEnvelopeTooFewSamples = 'tooFewSamples';

/// The eight directions of a G-G diagram, 45° each, anticlockwise from
/// accelerating as the driver feels them (left is the recording's positive
/// lateral G).
enum GgDirection {
  accelerating,
  acceleratingLeft,
  left,
  brakingLeft,
  braking,
  brakingRight,
  right,
  acceleratingRight;

  /// The direction's centre in radians from accelerating, toward the left.
  double get angle => index * math.pi / 4;
}

/// The direction a pair points to: the 45° sector around its angle.
GgDirection ggDirectionOf(double longitudinalG, double lateralG) {
  final sector = (math.atan2(lateralG, longitudinalG) / (math.pi / 4)).round();
  return GgDirection.values[sector % 8];
}

/// Whether a G channel was calculated by the logger (RaceChrono's `-calc`
/// channels, from GPS) rather than measured by an accelerometer.
bool ggChannelCalculated(String channel) => channel.toLowerCase().endsWith('-calc');

/// One direction of one session's envelope.
final class GgEnvelopeSector {
  const GgEnvelopeSector({required this.direction, required this.sampleCount, this.valueG});

  final GgDirection direction;

  /// The [ggEnvelopePercentile] of combined G in g; null with fewer than
  /// [ggEnvelopeMinimumSamples] samples.
  final double? valueG;

  /// Samples pointing this way.
  final int sampleCount;
}

/// One session's envelope over its laps.
final class SessionGgEnvelope {
  SessionGgEnvelope({
    required this.runId,
    required this.runName,
    required this.lapCount,
    this.lapsWithG = 0,
    List<GgEnvelopeSector> sectors = const [],
    this.unavailableReason = '',
    this.longitudinalChannel = '',
    this.lateralChannel = '',
    this.unitsDeclared = false,
    this.sampleCount = 0,
    this.neutralSamples = 0,
    this.excludedOutliers = 0,
  }) : sectors = List.unmodifiable(sectors);

  final String runId;
  final String runName;

  /// Laps passed for the session.
  final int lapCount;

  /// Laps with G pairs.
  final int lapsWithG;

  /// One per [GgDirection], in its order; empty when unavailable.
  final List<GgEnvelopeSector> sectors;

  /// Why there is no envelope; empty when there is one.
  final String unavailableReason;
  final String longitudinalChannel;
  final String lateralChannel;

  /// Whether both channels declare their unit.
  final bool unitsDeclared;

  /// G-G pairs over the laps, the neutral ones included.
  final int sampleCount;

  /// Pairs below [ggEnvelopeMinimumG], in no direction.
  final int neutralSamples;

  /// Pairs beyond the plausible limit, left out.
  final int excludedOutliers;

  bool get valid => unavailableReason.isEmpty;

  /// Whether either channel was calculated by the logger.
  bool get calculated =>
      ggChannelCalculated(longitudinalChannel) || ggChannelCalculated(lateralChannel);

  /// The envelope in [direction] in g, or null.
  double? valueG(GgDirection direction) =>
      sectors.length == GgDirection.values.length ? sectors[direction.index].valueG : null;
}

/// The day's best envelope in one direction and the session it comes from.
final class GgEnvelopeBest {
  const GgEnvelopeBest({
    required this.direction,
    required this.valueG,
    required this.runId,
    required this.runName,
  });

  final GgDirection direction;
  final double valueG;
  final String runId;
  final String runName;
}

/// A direction in which the latest session stays at least
/// [ggEnvelopeUnusedMarginG] below the day's best.
final class GgUnusedDirection {
  const GgUnusedDirection({required this.latestG, required this.best});

  final double latestG;
  final GgEnvelopeBest best;

  GgDirection get direction => best.direction;

  /// The best minus the latest, in g (positive).
  double get shortfallG => best.valueG - latestG;
}

/// Every session's envelope, the day's best and what the latest session
/// leaves unused.
final class DayGgEnvelope {
  DayGgEnvelope({
    List<SessionGgEnvelope> sessions = const [],
    List<GgEnvelopeBest?> best = const [],
    this.latestRunId = '',
    List<GgUnusedDirection> unused = const [],
    this.error = '',
  }) : sessions = List.unmodifiable(sessions),
       best = List.unmodifiable(best),
       unused = List.unmodifiable(unused);

  /// In recording order.
  final List<SessionGgEnvelope> sessions;

  /// One per [GgDirection]; null where no session has a value.
  final List<GgEnvelopeBest?> best;

  /// The last session in recording order; empty without sessions.
  final String latestRunId;

  /// The latest session's unused directions, in [GgDirection] order. Only
  /// where both it and an earlier session have a value.
  final List<GgUnusedDirection> unused;

  /// Set when the calculation failed or was cancelled.
  final String error;

  SessionGgEnvelope? get latest {
    for (final session in sessions) {
      if (session.runId == latestRunId) return session;
    }
    return null;
  }

  /// Whether any session has an envelope.
  bool get any => sessions.any((session) => session.valid);
}

/// [session] with only what the envelope reads (its G channels and their
/// aliases), to send to a background isolate without the rest.
TelemetrySession ggEnvelopeSession(TelemetrySession session) {
  final aliases = <String, String>{};
  final channels = <String, TelemetryChannel>{};
  for (final alias in const ['longitudinalAcceleration', 'lateralAcceleration']) {
    final name = session.aliases[alias];
    final channel = session.channels[name];
    if (name == null || channel == null) continue;
    aliases[alias] = name;
    channels[name] = channel;
  }
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: const {},
    channels: channels,
    aliases: aliases,
    warnings: const [],
    timingGates: const [],
    sampleCount: session.sampleCount,
  );
}

SessionGgEnvelope _sessionEnvelope(
  String runId,
  List<DayLapRow> laps,
  TelemetrySession? session,
  CancellationCheck? cancelled,
) {
  final runName = laps.first.runName;
  if (session == null) {
    return SessionGgEnvelope(
      runId: runId,
      runName: runName,
      lapCount: laps.length,
      unavailableReason: channelRecordingUnavailable,
    );
  }
  final magnitudes = [for (final _ in GgDirection.values) <double>[]];
  var lapsWithG = 0, samples = 0, neutral = 0, outliers = 0;
  var longitudinal = '', lateral = '', declared = false, reason = '';
  for (final lap in laps) {
    throwIfCancelled(cancelled);
    final pairs = buildGgPairs(session, lap.start, lap.end);
    longitudinal = pairs.longitudinalChannel;
    lateral = pairs.lateralChannel;
    if (!pairs.valid) {
      // A missing channel or unit is the session's; a lap without
      // samples only counts for less.
      if (pairs.unavailableReason != ggNoOverlap || reason.isEmpty) {
        reason = pairs.unavailableReason;
      }
      continue;
    }
    declared = pairs.unitsDeclared;
    outliers += pairs.excludedOutliers;
    if (pairs.points.isEmpty) continue;
    ++lapsWithG;
    for (final point in pairs.points) {
      ++samples;
      final combined = ggMagnitude(point.longitudinalG, point.lateralG);
      if (combined < ggEnvelopeMinimumG) {
        ++neutral;
        continue;
      }
      magnitudes[ggDirectionOf(point.longitudinalG, point.lateralG).index].add(combined);
    }
  }
  final sectors = [
    for (final direction in GgDirection.values)
      () {
        final values = magnitudes[direction.index];
        if (values.length < ggEnvelopeMinimumSamples) {
          return GgEnvelopeSector(direction: direction, sampleCount: values.length);
        }
        values.sort();
        return GgEnvelopeSector(
          direction: direction,
          sampleCount: values.length,
          valueG: values[(ggEnvelopePercentile * values.length).ceil() - 1],
        );
      }(),
  ];
  final String unavailable;
  if (lapsWithG == 0) {
    unavailable = reason.isEmpty ? ggNoOverlap : reason;
  } else if (sectors.every((sector) => sector.valueG == null)) {
    unavailable = ggEnvelopeTooFewSamples;
  } else {
    unavailable = '';
  }
  return SessionGgEnvelope(
    runId: runId,
    runName: runName,
    lapCount: laps.length,
    lapsWithG: lapsWithG,
    sectors: unavailable.isEmpty ? sectors : const [],
    unavailableReason: unavailable,
    longitudinalChannel: longitudinal,
    lateralChannel: lateral,
    unitsDeclared: declared,
    sampleCount: samples,
    neutralSamples: neutral,
    excludedOutliers: outliers,
  );
}

/// The G-G envelope of each session over its laps among [laps] (the day
/// cards pass the shown group's eligible laps, `dayEligibleLaps`; any
/// other section is ignored), in recording order; the day's best per
/// direction; and the directions in which the latest session stays at
/// least [ggEnvelopeUnusedMarginG] below the best of an earlier one.
/// [sessions] are the runs' recordings by run id; a run without one says
/// why. Cooperatively cancellable; a cancelled calculation says so in
/// [DayGgEnvelope.error].
DayGgEnvelope dayGgEnvelope(
  List<DayLapRow> laps,
  Map<String, TelemetrySession?> sessions, {
  CancellationCheck? cancelled,
}) {
  final byRun = <String, List<DayLapRow>>{};
  for (final row in sortDayLaps(laps)) {
    if (row.type != LapSectionType.lap) continue;
    (byRun[row.runId] ??= []).add(row);
  }
  final envelopes = <SessionGgEnvelope>[];
  try {
    for (final MapEntry(key: runId, value: runLaps) in byRun.entries) {
      envelopes.add(_sessionEnvelope(runId, runLaps, sessions[runId], cancelled));
    }
  } on OperationCancelled {
    return DayGgEnvelope(error: 'The G-G envelope was cancelled.');
  }
  final best = <GgEnvelopeBest?>[
    for (final direction in GgDirection.values)
      () {
        GgEnvelopeBest? found;
        for (final envelope in envelopes) {
          final value = envelope.valueG(direction);
          if (value != null && (found == null || value > found.valueG)) {
            found = GgEnvelopeBest(
              direction: direction,
              valueG: value,
              runId: envelope.runId,
              runName: envelope.runName,
            );
          }
        }
        return found;
      }(),
  ];
  final latest = envelopes.isEmpty ? null : envelopes.last;
  final unused = <GgUnusedDirection>[];
  if (latest != null && latest.valid) {
    for (final direction in GgDirection.values) {
      final top = best[direction.index];
      final value = latest.valueG(direction);
      if (top == null || value == null || top.runId == latest.runId) continue;
      // Rounded to the milligram, so a shortfall of exactly the margin
      // counts however the floats fall.
      if (((top.valueG - value) * 1000).round() >= (ggEnvelopeUnusedMarginG * 1000).round()) {
        unused.add(GgUnusedDirection(latestG: value, best: top));
      }
    }
  }
  return DayGgEnvelope(
    sessions: envelopes,
    best: best,
    latestRunId: latest?.runId ?? '',
    unused: unused,
  );
}
