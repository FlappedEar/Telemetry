// Port of FlappedEar Overlays native/src/telemetry/ExitMetrics.{h,cpp}
// (revision d4d1039, FET-33): throttle pickup and downstream exit effects for
// one approved segment on one lap (KAN-54).
//
// Pickup is searched inside the segment ([start, end] on shared-axis
// progress): the first sustained rise after a lift. It is measured from the
// recorded throttle channel when one exists; only without it is a positive
// longitudinal-acceleration onset reported, labelled inferred.
//
// The downstream interval starts at the segment's end boundary and runs to
// the end of the adjoining approved straight (`followingStraight`) or,
// without one, `followMeters` further (`fixedDistance`). Exit speed, speed at
// the interval end and elapsed time over it are reported and compared; no
// cause is assigned to any difference.
import 'package:fetproject/fetproject.dart' show TrackSegmentType, trackSegmentTypeName;

import '../speed_units.dart';
import '../telemetry_session.dart';
import 'corner_speeds.dart' show approvedSegmentById;
import 'pedal_scale.dart';
import 'sector_timing.dart';
import 'track_progress.dart';
import 'track_segment_review.dart';

const String exitMetricsAlgorithm = 'exit-metrics-v1';

const String pickupMethodMeasured = 'measuredThrottle';
const String pickupMethodInferred = 'inferredAcceleration';
const String intervalFollowingStraight = 'followingStraight';
const String intervalFixedDistance = 'fixedDistance';

const String exitNoLift = 'noLift';
const String exitNoPickup = 'noPickupDetected';
const String exitNoChannel = 'noThrottleOrAccelerationChannel';
const String exitUnitMismatch = 'unitMismatch';
const String exitIncompleteCoverage = 'incompleteCoverage';
const String exitCrossesGate = 'crossesGate';
const String exitSpeedChannelMissing = 'speedChannelMissing';
const String exitFollowsGap = 'followsGap';
const String exitTruncated = 'truncatedAtWindowEnd';
const String exitUnitUndeclared = 'channelUnitUndeclared';

/// The throttle declares no unit, stays within 0..1 and nothing shows
/// whether that is a fraction or a few percent (FET-205).
const String exitScaleUnknown = 'channelScaleUnknown';

/// The throttle declares no unit and is read as a 0..1 fraction, as the
/// hard accelerations show (FET-205): thresholds are divided by 100.
const String exitScaleInferred = 'channelScaleInferred';
const String exitMixedProvenance = 'mixedProvenance';

const double _boundaryEpsilon = 1e-6;

/// Hysteresis thresholds of a pickup, in [unit].
final class ExitThreshold {
  const ExitThreshold(this.on, this.off, this.unit);

  final double on;
  final double off;
  final String unit;
}

/// Options of [computeExitMetrics].
final class ExitMetricsOptions {
  const ExitMetricsOptions({
    this.throttle = const ExitThreshold(20.0, 10.0, '%'),
    this.acceleration = const ExitThreshold(0.10, 0.05, 'g'),
    this.minimumDurationSeconds = 0.2,
    this.followMeters = 200.0,
  });

  final ExitThreshold throttle;
  final ExitThreshold acceleration;
  final double minimumDurationSeconds;
  final double followMeters;
}

/// Where the driver picks up the throttle in a segment.
final class ThrottlePickup {
  /// `measuredThrottle` or `inferredAcceleration`.
  String method = '';

  /// `measured` or `inferred`.
  String provenance = '';
  String channel = '';
  String unit = '';
  ExitThreshold threshold = const ExitThreshold(0.0, 0.0, '');
  double? progressMeters;
  double? telemetryTime;
  String unavailableReason = '';
  List<String> limitations = [];
}

/// The exit of one segment on one lap.
final class ExitMetrics {
  ExitMetrics({this.segmentId = '', this.stamp = const SegmentationResultStamp()});

  final String segmentId;
  final ThrottlePickup pickup = ThrottlePickup();

  /// `followingStraight` or `fixedDistance`.
  String intervalSource = '';
  double intervalStartMeters = 0.0;
  double intervalEndMeters = 0.0;
  String speedChannel = '';
  String speedUnit = '';

  /// At the segment end boundary.
  double? exitSpeed;
  double? intervalEndSpeed;

  /// Over the whole interval, only with continuous coverage.
  double? elapsedSeconds;
  String downstreamUnavailableReason = '';
  final SegmentationResultStamp stamp;
  bool valid = false;
}

bool _validThreshold(ExitThreshold threshold) =>
    threshold.on.isFinite &&
    threshold.off.isFinite &&
    threshold.off >= 0.0 &&
    threshold.on > threshold.off &&
    threshold.unit.trim().isNotEmpty;

typedef _Rise = ({double? time, List<String> limitations, String reason});

// The first rise to `on` after the channel was at or below `off`, sustained at
// or above `off` for `minimumDuration`. Raw samples only; gaps are never
// bridged.
_Rise _firstSustainedRise(
  TelemetryChannel channel,
  double on,
  double off,
  double minimumDuration,
  double startTime,
  double endTime,
) {
  final times = channel.timestamps;
  final values = channel.values;
  if (times.length != values.length) {
    return (time: null, limitations: const [], reason: exitIncompleteCoverage);
  }
  final gapThreshold = telemetryGapThreshold(channel);
  final begin = lowerBound(times, startTime);
  final end = upperBound(times, endTime);
  var lifted = false;
  var rising = false;
  var followsGap = false;
  var previousContiguous = false;
  var haveSample = false;
  var previousTime = 0.0;
  var previousValue = 0.0;
  var riseStart = 0.0;
  var riseLimitations = <String>[];
  var finite = 0;
  for (var index = begin; index < end; ++index) {
    final time = times[index];
    final double value = values[index];
    final gapBefore = haveSample && gapThreshold > 0.0 && time - previousTime > gapThreshold;
    if (!value.isFinite || gapBefore) {
      if (rising && previousTime - riseStart >= minimumDuration) {
        return (time: riseStart, limitations: riseLimitations, reason: '');
      }
      rising = false;
      followsGap = true;
      previousContiguous = false;
      if (!value.isFinite) {
        haveSample = false;
        continue;
      }
    }
    ++finite;
    if (!rising) {
      if (!lifted) {
        if (value <= off) lifted = true;
      } else if (value >= on) {
        rising = true;
        riseLimitations = [];
        if (previousContiguous && previousValue < on) {
          riseStart =
              previousTime + (time - previousTime) * (on - previousValue) / (value - previousValue);
        } else {
          riseStart = time;
        }
        if (followsGap) riseLimitations.add(exitFollowsGap);
      }
    } else if (value < off) {
      if (time - riseStart >= minimumDuration) {
        return (time: riseStart, limitations: riseLimitations, reason: '');
      }
      rising = false; // a brief spike, not a pickup
    }
    haveSample = true;
    previousContiguous = true;
    followsGap = false;
    previousTime = time;
    previousValue = value;
  }
  if (rising) {
    if (previousTime - riseStart < minimumDuration) riseLimitations.add(exitTruncated);
    return (time: riseStart, limitations: riseLimitations, reason: '');
  }
  return (
    time: null,
    limitations: const [],
    reason: finite == 0
        ? exitIncompleteCoverage
        : lifted
        ? exitNoPickup
        : exitNoLift,
  );
}

double? _speedAtProgress(
  List<ProgressSegment> lap,
  TelemetrySession session,
  String channel,
  double progress,
) {
  final time = timeAtProgress(lap, progress);
  return time == null ? null : session.valueAt(channel, time);
}

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

/// The throttle pickup and exit of [segmentId] on one lap. [lapEndTime] is
/// the lap's timed gate crossing, used when the interval ends at the gate.
ExitMetrics computeExitMetrics(
  double axisLengthMeters,
  ApprovedSegmentation approved,
  String segmentId,
  List<ProgressSegment> lapTrace,
  TelemetrySession session, [
  double? lapEndTime,
  ExitMetricsOptions options = const ExitMetricsOptions(),
]) {
  if (!approved.valid ||
      !axisLengthMeters.isFinite ||
      axisLengthMeters <= 0.0 ||
      !_validThreshold(options.throttle) ||
      !_validThreshold(options.acceleration) ||
      !options.minimumDurationSeconds.isFinite ||
      options.minimumDurationSeconds <= 0.0 ||
      !options.followMeters.isFinite ||
      options.followMeters <= 0.0) {
    return ExitMetrics();
  }
  final segment = approvedSegmentById(approved, segmentId);
  if (segment == null || segment.isEmpty) return ExitMetrics();
  final length = axisLengthMeters;
  final start = _number(segment['startProgressMeters']);
  final end = _number(segment['endProgressMeters']);
  final result = ExitMetrics(
    segmentId: segmentId,
    stamp: segmentationResultStamp(approved, exitMetricsAlgorithm),
  )..valid = true;
  if (end < start) {
    result.pickup.unavailableReason = exitCrossesGate;
    result.downstreamUnavailableReason = exitCrossesGate;
    return result;
  }

  // Pickup inside the segment.
  final pickup = result.pickup;
  final throttleName = session.aliases['throttle'] ?? '';
  final accelerationName = session.aliases['longitudinalAcceleration'] ?? '';
  final hasThrottle = throttleName.isNotEmpty && session.channels.containsKey(throttleName);
  final hasAcceleration =
      accelerationName.isNotEmpty && session.channels.containsKey(accelerationName);
  if (hasThrottle || hasAcceleration) {
    pickup
      ..method = hasThrottle ? pickupMethodMeasured : pickupMethodInferred
      ..provenance = hasThrottle ? 'measured' : 'inferred'
      ..channel = hasThrottle ? throttleName : accelerationName
      ..threshold = hasThrottle ? options.throttle : options.acceleration;
    final channel = session.channels[pickup.channel]!;
    pickup.unit = channel.unit;
    final declared = channel.unit.trim().isNotEmpty;
    final scale = hasThrottle ? throttleScale(session) : PedalScale.percent;
    if (scale == PedalScale.fraction) {
      pickup.threshold = ExitThreshold(
        options.throttle.on / 100.0,
        options.throttle.off / 100.0,
        '',
      );
    }
    final fromTime = timeAtProgress(lapTrace, start);
    // A segment ending at the gate ends at the lap's timed end; the
    // projection never reaches it exactly.
    final toTime = end >= length - _boundaryEpsilon && lapEndTime != null
        ? lapEndTime
        : timeAtProgress(lapTrace, end);
    if (declared &&
        channel.unit.trim().toLowerCase() != pickup.threshold.unit.trim().toLowerCase()) {
      pickup.unavailableReason = exitUnitMismatch;
    } else if (scale == PedalScale.unknown) {
      pickup.unavailableReason = exitScaleUnknown;
    } else if (fromTime == null || toTime == null || !(toTime > fromTime)) {
      pickup.unavailableReason = exitIncompleteCoverage;
    } else {
      final rise = _firstSustainedRise(
        channel,
        pickup.threshold.on,
        pickup.threshold.off,
        options.minimumDurationSeconds,
        fromTime,
        toTime,
      );
      if (rise.time == null) {
        pickup.unavailableReason = rise.reason;
      } else {
        pickup
          ..telemetryTime = rise.time
          ..progressMeters = progressAtTime(lapTrace, rise.time!)
          ..limitations = [
            ...rise.limitations,
            if (!declared) exitUnitUndeclared,
            if (scale == PedalScale.fraction) exitScaleInferred,
          ];
        if (pickup.progressMeters == null) pickup.unavailableReason = exitIncompleteCoverage;
      }
    }
  } else {
    pickup.unavailableReason = exitNoChannel;
  }

  // Downstream interval from the end boundary.
  result
    ..intervalStartMeters = end
    ..intervalSource = intervalFixedDistance
    ..intervalEndMeters = end + options.followMeters;
  for (final next in approved.segments) {
    if (next['type'] == trackSegmentTypeName(TrackSegmentType.straight) &&
        (_number(next['startProgressMeters']) - end).abs() <= _boundaryEpsilon &&
        _number(next['endProgressMeters']) > end) {
      result
        ..intervalSource = intervalFollowingStraight
        ..intervalEndMeters = _number(next['endProgressMeters']);
    }
  }
  final speedName = session.aliases['speed'] ?? '';
  if (speedName.isNotEmpty && session.channels.containsKey(speedName)) {
    result
      ..speedChannel = speedName
      ..speedUnit = session.channels[speedName]!.unit
      ..exitSpeed = _speedAtProgress(lapTrace, session, speedName, end);
  }
  if (result.intervalEndMeters > length + _boundaryEpsilon) {
    // The straight continues into the next lap.
    result.downstreamUnavailableReason = exitCrossesGate;
    return result;
  }
  final intervalLength = result.intervalEndMeters - result.intervalStartMeters;
  final startTime = timeAtProgress(lapTrace, result.intervalStartMeters);
  // An interval ending at the gate ends at the lap's timed end; the
  // projection never reaches it exactly.
  final endTime = result.intervalEndMeters >= length - _boundaryEpsilon
      ? lapEndTime
      : timeAtProgress(lapTrace, result.intervalEndMeters);
  if (projectedCoverageMeters(
            lapTrace,
            result.intervalStartMeters,
            result.intervalEndMeters,
            length,
          ) <
          intervalLength - _boundaryEpsilon ||
      startTime == null ||
      endTime == null) {
    result.downstreamUnavailableReason = exitIncompleteCoverage;
  } else {
    result.elapsedSeconds = endTime - startTime;
    if (result.speedChannel.isNotEmpty) {
      result.intervalEndSpeed = session.valueAt(speedName, endTime);
    }
  }
  if (result.speedChannel.isEmpty && result.downstreamUnavailableReason.isEmpty) {
    result.downstreamUnavailableReason = exitSpeedChannelMissing;
  }
  return result;
}

/// A minus B for the same segment, revision and interval. The pickup delta
/// is positive when A picks up later; it is withheld when methods differ.
final class ExitComparison {
  const ExitComparison({
    this.pickupDeltaMeters,
    this.exitSpeedDelta,
    this.intervalEndSpeedDelta,
    this.elapsedSecondsDelta,
    this.pickupUnavailableReason = '',
    this.valid = false,
  });

  final double? pickupDeltaMeters;
  final double? exitSpeedDelta;
  final double? intervalEndSpeedDelta;
  final double? elapsedSecondsDelta;
  final String pickupUnavailableReason;
  final bool valid;
}

double? _delta(double? x, double? y) => x != null && y != null ? x - y : null;

/// [a] minus [b].
ExitComparison compareExitMetrics(ExitMetrics a, ExitMetrics b) {
  if (!a.valid ||
      !b.valid ||
      a.segmentId != b.segmentId ||
      a.stamp.revision != b.stamp.revision ||
      a.stamp.trackConfigurationReference != b.stamp.trackConfigurationReference ||
      a.intervalSource != b.intervalSource ||
      a.intervalEndMeters != b.intervalEndMeters) {
    return const ExitComparison();
  }
  final sameSpeed = a.speedChannel == b.speedChannel && sameSpeedUnit(a.speedUnit, b.speedUnit);
  double? pickupDelta;
  var pickupReason = '';
  if (a.pickup.method != b.pickup.method || a.pickup.channel != b.pickup.channel) {
    pickupReason = exitMixedProvenance;
  } else if (a.pickup.progressMeters == null || b.pickup.progressMeters == null) {
    pickupReason = a.pickup.unavailableReason.isNotEmpty
        ? a.pickup.unavailableReason
        : b.pickup.unavailableReason;
  } else {
    pickupDelta = a.pickup.progressMeters! - b.pickup.progressMeters!;
  }
  return ExitComparison(
    pickupDeltaMeters: pickupDelta,
    exitSpeedDelta: sameSpeed ? _delta(a.exitSpeed, b.exitSpeed) : null,
    intervalEndSpeedDelta: sameSpeed ? _delta(a.intervalEndSpeed, b.intervalEndSpeed) : null,
    elapsedSecondsDelta: _delta(a.elapsedSeconds, b.elapsedSeconds),
    pickupUnavailableReason: pickupReason,
    valid: true,
  );
}
