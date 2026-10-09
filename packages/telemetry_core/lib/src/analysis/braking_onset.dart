// Port of FlappedEar Overlays native/src/telemetry/BrakingOnset.{h,cpp}
// (revision d4d1039, FET-33): where braking episodes start inside a time
// window, from the measured brake channel or, when there is no trustworthy
// one, from deceleration (FET-204: by quality, not by which exists;
// braking_source.dart).
import 'dart:math' as math;

import '../channel_units.dart';
import '../telemetry_session.dart';
import 'braking_source.dart';
import 'pedal_scale.dart';
import 'track_progress.dart';

const String brakingOnsetAlgorithm = 'braking-onset-v1';

const String brakingMethodMeasured = 'measuredBrake';
const String brakingMethodInferred = 'inferredDeceleration';
const String brakingProvenanceMeasured = 'measured';
const String brakingProvenanceInferred = 'inferred';

/// Unresolved reasons (no candidates).
const String brakingNoChannel = 'noBrakeOrDecelerationChannel';
const String brakingInferenceDisabled = 'inferenceDisabled';
const String brakingUnitMismatch = 'unitMismatch';
const String brakingNoSamples = 'noSamplesInWindow';

/// The brake declares no unit, stays within 0..1 and nothing shows whether
/// that is a fraction or a few percent (FET-205, pedal_scale.dart).
const String brakingScaleUnknown = 'channelScaleUnknown';

/// Candidate uncertainty reasons.
const String brakingFollowsGap = 'followsGap';
const String brakingAlreadyActive = 'alreadyBrakingAtWindowStart';
const String brakingInterruptedByGap = 'interruptedByGap';
const String brakingTruncatedAtWindowEnd = 'truncatedAtWindowEnd';
const String brakingUnitUndeclared = 'channelUnitUndeclared';

/// The session has a brake channel, but it does not show the braking (no
/// data, or not pressed in most hard brakings), so deceleration is used
/// (FET-204, braking_source.dart).
const String brakingBrakeChannelNotUsed = 'brakeChannelNotUsed';

/// The brake declares no unit and is read as a 0..1 fraction, as the hard
/// brakings show (FET-205): thresholds are divided by 100.
const String brakingScaleInferred = 'channelScaleInferred';

/// Hysteresis thresholds on braking magnitude, in [unit]. For deceleration
/// the magnitude is the negated longitudinal acceleration (negative G is
/// braking).
final class BrakingThreshold {
  const BrakingThreshold(this.on, this.off, this.unit);

  final double on;
  final double off;
  final String unit;
}

/// Thresholds of [detectBrakingOnsets].
final class BrakingOnsetOptions {
  const BrakingOnsetOptions({
    this.measuredBrake = const BrakingThreshold(10.0, 5.0, '%'),
    this.inferredDeceleration = const BrakingThreshold(0.30, 0.15, 'g'),
    this.minimumDurationSeconds = 0.2,
    this.allowInferred = true,
  });

  final BrakingThreshold measuredBrake;
  final BrakingThreshold inferredDeceleration;

  /// Shorter episodes are rejected as spikes.
  final double minimumDurationSeconds;
  final bool allowInferred;
}

/// One braking episode's start.
final class BrakingOnsetCandidate {
  BrakingOnsetCandidate({
    required this.telemetryTime,
    required this.toleranceSeconds,
    required this.durationSeconds,
    required this.peakValue,
    this.progressMeters,
    List<String>? uncertaintyReasons,
  }) : uncertaintyReasons = uncertaintyReasons ?? [];

  final double telemetryTime;
  final double toleranceSeconds;
  final double durationSeconds;

  /// Channel value in its own sign convention.
  final double peakValue;
  final double? progressMeters;
  final List<String> uncertaintyReasons;
}

/// The braking episodes of a window.
final class BrakingOnsetDetection {
  BrakingOnsetDetection({
    this.method = '',
    this.provenance = '',
    this.channel = '',
    this.channelUnit = '',
    this.threshold = const BrakingThreshold(0.0, 0.0, ''),
    this.minimumDurationSeconds = 0.0,
    List<BrakingOnsetCandidate>? candidates,
    this.rejectedSpikes = 0,
    this.gaps = 0,
    this.unresolvedReason = '',
    this.valid = false,
  }) : candidates = candidates ?? [];

  String method;
  String provenance;
  String channel;

  /// As declared by the source; empty when undeclared.
  String channelUnit;
  BrakingThreshold threshold;
  double minimumDurationSeconds;
  final List<BrakingOnsetCandidate> candidates;
  int rejectedSpikes;
  int gaps;
  String unresolvedReason;
  bool valid;
}

bool _validThreshold(BrakingThreshold threshold) =>
    threshold.on.isFinite &&
    threshold.off.isFinite &&
    threshold.off > 0.0 &&
    threshold.on > threshold.off &&
    threshold.unit.trim().isNotEmpty;

final class _Episode {
  double onset = 0.0;
  double tolerance = 0.0;
  double peak = 0.0;
  double lastTime = 0.0;
  final List<String> reasons = [];
}

/// Uses the measured `brake` channel unless [brakingSourceQuality] rejects
/// it for the whole session, and never substitutes deceleration for it in
/// one window, even where brake data is missing there. A session without a
/// brake channel, or with a rejected one (each candidate then carries
/// [brakingBrakeChannelNotUsed]), falls back to `longitudinalAcceleration`,
/// labelled inferred. Raw samples in [startTime]..[endTime] are scanned
/// without interpolation across gaps; [lapTrace], when given, maps onsets to
/// progress.
BrakingOnsetDetection detectBrakingOnsets(
  TelemetrySession session,
  double startTime,
  double endTime, {
  BrakingOnsetOptions options = const BrakingOnsetOptions(),
  List<ProgressSegment>? lapTrace,
}) {
  final result = BrakingOnsetDetection();
  if (!startTime.isFinite ||
      !endTime.isFinite ||
      endTime <= startTime ||
      !_validThreshold(options.measuredBrake) ||
      !_validThreshold(options.inferredDeceleration) ||
      !options.minimumDurationSeconds.isFinite ||
      options.minimumDurationSeconds <= 0.0) {
    return result;
  }
  result.valid = true;
  result.minimumDurationSeconds = options.minimumDurationSeconds;

  final quality = brakingSourceQuality(session);
  final brakeName = quality.brakeName;
  final decelerationName = quality.decelerationName;
  // A brake with no data, or not pressed in most hard brakings, gives way
  // to a usable deceleration.
  final brakeRejected = quality.brakeRejected && options.allowInferred;
  final hasBrake = quality.hasBrake && !brakeRejected;
  final hasDeceleration = quality.hasDeceleration;
  var sign = 1.0;
  final fraction = hasBrake && quality.brakeScale == PedalScale.fraction;
  if (hasBrake) {
    result.method = brakingMethodMeasured;
    result.provenance = brakingProvenanceMeasured;
    result.channel = brakeName;
    result.threshold = fraction
        ? BrakingThreshold(options.measuredBrake.on / 100.0, options.measuredBrake.off / 100.0, '')
        : options.measuredBrake;
    if (quality.brakeScale == PedalScale.unknown) {
      result.channelUnit = declaredChannelUnit(session, brakeName);
      result.unresolvedReason = brakingScaleUnknown;
      return result;
    }
  } else if (hasDeceleration) {
    result.method = brakingMethodInferred;
    result.provenance = brakingProvenanceInferred;
    result.channel = decelerationName;
    result.threshold = options.inferredDeceleration;
    sign = -1.0; // negative longitudinal G is braking
    if (!options.allowInferred) {
      result.unresolvedReason = brakingInferenceDisabled;
      return result;
    }
  } else {
    result.unresolvedReason = brakingNoChannel;
    return result;
  }

  // The unit the recording declares (a VBO on its header line). A pedal is
  // read in its own unit; a deceleration in g, whichever unit it is
  // declared in, so a channel in m/s² reaches the same thresholds as one
  // in g. A unit that cannot be read is a mismatch, never the default.
  final TelemetryChannel channel;
  final String declaredUnit;
  final bool unitReadable;
  if (hasBrake) {
    channel = session.channels[result.channel]!;
    declaredUnit = declaredChannelUnit(session, result.channel);
    unitReadable =
        declaredUnit.isEmpty ||
        declaredUnit.toLowerCase() == result.threshold.unit.trim().toLowerCase();
  } else {
    final view = accelerationInG(session, result.channel)!;
    channel = view.channel;
    declaredUnit = view.declaredUnit;
    unitReadable = view.supported;
  }
  result.channelUnit = declaredUnit;
  final unitDeclared = declaredUnit.isNotEmpty;
  if (!unitReadable) {
    result.unresolvedReason = brakingUnitMismatch;
    return result;
  }
  if (channel.timestamps.length != channel.values.length) {
    result.unresolvedReason = brakingNoSamples;
    return result;
  }

  final gapThreshold = telemetryGapThreshold(channel);
  final times = channel.timestamps;
  final begin = lowerBound(times, startTime);
  final end = upperBound(times, endTime);

  _Episode? episode;
  var haveSample = false;
  var finiteSamples = 0;
  var previousContiguous = false;
  var followsGap = false;
  var previousTime = 0.0;
  var previousMagnitude = 0.0;

  void close(double endTimeValue, String? truncation) {
    final current = episode!;
    final duration = endTimeValue - current.onset;
    if (duration < options.minimumDurationSeconds && truncation == null) {
      ++result.rejectedSpikes;
    } else {
      result.candidates.add(
        BrakingOnsetCandidate(
          telemetryTime: current.onset,
          toleranceSeconds: current.tolerance,
          durationSeconds: duration,
          peakValue: sign * current.peak,
          uncertaintyReasons: [
            ...current.reasons,
            ?truncation,
            if (!unitDeclared) brakingUnitUndeclared,
            if (brakeRejected)
              quality.brakeScale == PedalScale.unknown
                  ? brakingScaleUnknown
                  : brakingBrakeChannelNotUsed,
            if (fraction) brakingScaleInferred,
          ],
          progressMeters: lapTrace == null ? null : progressAtTime(lapTrace, current.onset),
        ),
      );
    }
    episode = null;
  }

  for (var index = begin; index < end; ++index) {
    final time = times[index];
    final double raw = channel.values[index];
    final gapBefore = haveSample && gapThreshold > 0.0 && time - previousTime > gapThreshold;
    if (!raw.isFinite || gapBefore) {
      if (!followsGap) ++result.gaps;
      if (episode != null) close(episode!.lastTime, brakingInterruptedByGap);
      followsGap = true;
      previousContiguous = false;
      if (!raw.isFinite) {
        haveSample = false;
        continue;
      }
    }
    ++finiteSamples;
    final magnitude = sign * raw;
    if (episode == null && magnitude >= result.threshold.on) {
      final started = _Episode();
      if (previousContiguous && previousMagnitude < result.threshold.on) {
        final fraction =
            (result.threshold.on - previousMagnitude) / (magnitude - previousMagnitude);
        started.onset = previousTime + (time - previousTime) * fraction;
        started.tolerance = time - previousTime;
      } else {
        started.onset = time;
        started.tolerance = channel.baseIntervalSeconds;
        started.reasons.add(followsGap ? brakingFollowsGap : brakingAlreadyActive);
      }
      started.peak = magnitude;
      started.lastTime = time;
      episode = started;
    } else if (episode != null && magnitude < result.threshold.off) {
      close(time, null);
    } else if (episode != null) {
      episode!.peak = math.max(episode!.peak, magnitude);
      episode!.lastTime = time;
    }
    haveSample = true;
    previousContiguous = true;
    followsGap = false;
    previousTime = time;
    previousMagnitude = magnitude;
  }
  if (episode != null) close(episode!.lastTime, brakingTruncatedAtWindowEnd);
  if (finiteSamples == 0) result.unresolvedReason = brakingNoSamples;
  return result;
}
