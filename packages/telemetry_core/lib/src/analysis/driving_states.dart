// Port of FlappedEar Overlays native/src/telemetry/DrivingStates.{h,cpp}
// (revision d4d1039, FET-39): when a lap is braking, accelerating,
// cornering or coasting, with the provenance of each (KAN-91).
//
// States may overlap where driving does: cornering with braking (trail
// braking), with accelerating or with coasting; braking with accelerating
// only when both pedals are measured (a lift-and-brake or left-foot overlap
// cannot be seen in one acceleration channel). Coasting is the time at speed
// when both pedal states are known to be off. A recorded pedal is never
// inferred: deceleration and acceleration stand in for a pedal only when the
// recording has no such pedal channel at all, and are labelled inferred.
import 'dart:math' as math;

import '../speed_units.dart';
import '../telemetry_session.dart';
import 'braking_onset.dart' show BrakingThreshold;

const String drivingStatesAlgorithm = 'driving-states-v1';

/// A recorded driver input or sensor.
const String drivingStateMeasured = 'measured';

/// Recorded by the logger from GPS (a "-calc" channel).
const String drivingStateCalculated = 'calculated';

/// Derived from acceleration, never a pedal.
const String drivingStateInferred = 'inferred';
const String drivingStateUnknown = 'unknown';

/// Thresholds of [classifyDrivingStates].
final class DrivingStateOptions {
  const DrivingStateOptions({
    this.measuredBrake = const BrakingThreshold(10.0, 5.0, '%'),
    this.measuredThrottle = const BrakingThreshold(15.0, 8.0, '%'),
    this.inferredBraking = const BrakingThreshold(0.15, 0.08, 'g'),
    this.inferredAcceleration = const BrakingThreshold(0.10, 0.05, 'g'),
    this.cornering = const BrakingThreshold(0.30, 0.20, 'g'),
    this.minimumSpeedKmh = 10.0,
    this.minimumDurationSeconds = 0.2,
    this.allowInferred = true,
  });

  final BrakingThreshold measuredBrake;
  final BrakingThreshold measuredThrottle;

  /// On negative longitudinal G.
  final BrakingThreshold inferredBraking;

  /// On positive longitudinal G.
  final BrakingThreshold inferredAcceleration;

  /// On |lateral G|.
  final BrakingThreshold cornering;

  /// Below it the car is not coasting (pit lane, stop).
  final double minimumSpeedKmh;

  /// Shorter episodes are spikes.
  final double minimumDurationSeconds;
  final bool allowInferred;
}

/// A time interval in recording seconds.
final class DrivingStateInterval {
  const DrivingStateInterval(this.start, this.end);

  final double start;
  final double end;

  double get seconds => end - start;

  @override
  String toString() => '[$start, $end]';
}

/// One state over the window: where it holds, where it is known (the
/// channel had data), and how it was obtained.
final class DrivingStateTrack {
  String provenance = drivingStateUnknown;

  /// The channel it was classified from; empty when unknown.
  String channel = '';

  /// As declared by the source.
  String unit = '';
  BrakingThreshold threshold = const BrakingThreshold(0.0, 0.0, '');
  final List<DrivingStateInterval> active = [];
  final List<DrivingStateInterval> known = [];

  /// Why the state is unknown throughout.
  String unresolvedReason = '';
  int rejectedSpikes = 0;

  bool get isKnown => provenance != drivingStateUnknown;
}

final class DrivingStateClassification {
  String algorithm = drivingStatesAlgorithm;
  double start = 0.0;
  double end = 0.0;
  final DrivingStateTrack braking = DrivingStateTrack();
  final DrivingStateTrack accelerating = DrivingStateTrack();
  final DrivingStateTrack cornering = DrivingStateTrack();
  final DrivingStateTrack coasting = DrivingStateTrack();
  bool valid = false;
}

typedef _Intervals = List<DrivingStateInterval>;

bool _validThreshold(BrakingThreshold threshold) =>
    threshold.on.isFinite &&
    threshold.off.isFinite &&
    threshold.off >= 0.0 &&
    threshold.on > threshold.off;

// An undeclared unit is used (the channel is named in the result); a
// declared one must be one of [accepted], ignoring case.
bool _unitMatches(String declared, List<String> accepted) {
  final unit = declared.trim();
  if (unit.isEmpty) return true;
  final folded = unit.toLowerCase();
  return accepted.any((candidate) => candidate.toLowerCase() == folded);
}

// Episodes where `magnitude(value)` rises to `on` and stays above `off`, and
// the spans where the channel has contiguous samples. Nothing is bridged
// across a gap or a non-finite sample.
void _classify(
  TelemetryChannel channel,
  double Function(double) magnitude,
  BrakingThreshold threshold,
  double minimumDuration,
  double start,
  double end,
  DrivingStateTrack track,
) {
  if (channel.timestamps.length != channel.values.length) return;
  final gapThreshold = telemetryGapThreshold(channel);
  final times = channel.timestamps;
  final begin = lowerBound(times, start);
  final last = upperBound(times, end);
  double? knownStart, activeStart;
  var previousTime = 0.0;
  var havePrevious = false;
  void closeActive(double at) {
    final from = activeStart;
    if (from == null) return;
    if (at - from >= minimumDuration) {
      track.active.add(DrivingStateInterval(from, at));
    } else {
      ++track.rejectedSpikes;
    }
    activeStart = null;
  }

  void closeKnown(double at) {
    closeActive(at);
    final from = knownStart;
    if (from != null && at > from) track.known.add(DrivingStateInterval(from, at));
    knownStart = null;
  }

  for (var index = begin; index < last; ++index) {
    final time = times[index];
    final double value = channel.values[index];
    final gap = havePrevious && gapThreshold > 0.0 && time - previousTime > gapThreshold;
    if (gap || !value.isFinite) closeKnown(previousTime);
    if (!value.isFinite) {
      havePrevious = false;
      continue;
    }
    knownStart ??= time;
    final level = magnitude(value);
    if (activeStart == null && level >= threshold.on) {
      activeStart = time;
    } else if (activeStart != null && level < threshold.off) {
      closeActive(time);
    }
    previousTime = time;
    havePrevious = true;
  }
  if (havePrevious) closeKnown(previousTime);
}

_Intervals _intersect(_Intervals a, _Intervals b) {
  final result = <DrivingStateInterval>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final start = math.max(a[i].start, b[j].start), end = math.min(a[i].end, b[j].end);
    if (end > start) result.add(DrivingStateInterval(start, end));
    if (a[i].end < b[j].end) {
      ++i;
    } else {
      ++j;
    }
  }
  return result;
}

_Intervals _unite(_Intervals intervals) {
  final sorted = List.of(intervals)..sort((x, y) => x.start.compareTo(y.start));
  final result = <DrivingStateInterval>[];
  for (final interval in sorted) {
    if (result.isNotEmpty && interval.start <= result.last.end) {
      result.last = DrivingStateInterval(
        result.last.start,
        math.max(result.last.end, interval.end),
      );
    } else {
      result.add(interval);
    }
  }
  return result;
}

_Intervals _subtract(_Intervals from, _Intervals removed) {
  final result = <DrivingStateInterval>[];
  for (final original in from) {
    var pieceStart = original.start;
    final pieceEnd = original.end;
    for (final cut in removed) {
      if (cut.end <= pieceStart || cut.start >= pieceEnd) continue;
      if (cut.start > pieceStart) result.add(DrivingStateInterval(pieceStart, cut.start));
      pieceStart = math.max(pieceStart, cut.end);
      if (pieceStart >= pieceEnd) break;
    }
    if (pieceEnd > pieceStart) result.add(DrivingStateInterval(pieceStart, pieceEnd));
  }
  return result;
}

(String, TelemetryChannel?) _aliasChannel(TelemetrySession session, String alias) {
  final name = session.aliases[alias] ?? '';
  final channel = session.channels[name];
  return (name, name.isEmpty ? null : channel);
}

// A pedal state from its measured channel, or inferred from longitudinal G
// when the pedal channel is missing (never when it is present but empty).
void _pedalState(
  TelemetrySession session,
  String pedalAlias,
  BrakingThreshold measured,
  BrakingThreshold inferred,
  double sign,
  DrivingStateOptions options,
  double start,
  double end,
  DrivingStateTrack track,
) {
  final (pedalName, pedal) = _aliasChannel(session, pedalAlias);
  if (pedal != null) {
    track.channel = pedalName;
    track.unit = pedal.unit;
    track.threshold = measured;
    if (!_unitMatches(pedal.unit, [measured.unit])) {
      track.unresolvedReason = 'unitMismatch';
      return;
    }
    track.provenance = drivingStateMeasured;
    _classify(pedal, (value) => value, measured, options.minimumDurationSeconds, start, end, track);
    return;
  }
  final (name, longitudinal) = _aliasChannel(session, 'longitudinalAcceleration');
  if (longitudinal == null) {
    track.unresolvedReason = 'noPedalOrAccelerationChannel';
    return;
  }
  if (!options.allowInferred) {
    track.unresolvedReason = 'inferenceDisabled';
    return;
  }
  track.channel = name;
  track.unit = longitudinal.unit;
  track.threshold = inferred;
  if (!_unitMatches(longitudinal.unit, [inferred.unit])) {
    track.unresolvedReason = 'unitMismatch';
    return;
  }
  track.provenance = drivingStateInferred;
  _classify(
    longitudinal,
    (value) => sign * value,
    inferred,
    options.minimumDurationSeconds,
    start,
    end,
    track,
  );
}

/// Classifies [startTime]..[endTime] of [session]. Channels: the `brake`
/// and `throttle` aliases (measured) and, when a pedal channel is missing
/// and inference is allowed, `longitudinalAcceleration` (inferred);
/// cornering from `lateralAcceleration`; coasting also needs `speed`.
/// Samples are not interpolated across gaps: a gap is unknown for every
/// state that uses the channel. A channel whose declared unit differs from
/// its threshold's is not used (the state is unknown), never rescaled.
DrivingStateClassification classifyDrivingStates(
  TelemetrySession session,
  double startTime,
  double endTime, [
  DrivingStateOptions options = const DrivingStateOptions(),
]) {
  final result = DrivingStateClassification();
  if (!startTime.isFinite ||
      !endTime.isFinite ||
      endTime <= startTime ||
      !_validThreshold(options.measuredBrake) ||
      !_validThreshold(options.measuredThrottle) ||
      !_validThreshold(options.inferredBraking) ||
      !_validThreshold(options.inferredAcceleration) ||
      !_validThreshold(options.cornering) ||
      !options.minimumSpeedKmh.isFinite ||
      options.minimumSpeedKmh < 0.0 ||
      !options.minimumDurationSeconds.isFinite ||
      options.minimumDurationSeconds <= 0.0) {
    return result;
  }
  result.valid = true;
  result.start = startTime;
  result.end = endTime;

  _pedalState(
    session,
    'brake',
    options.measuredBrake,
    options.inferredBraking,
    -1.0,
    options,
    startTime,
    endTime,
    result.braking,
  );
  _pedalState(
    session,
    'throttle',
    options.measuredThrottle,
    options.inferredAcceleration,
    1.0,
    options,
    startTime,
    endTime,
    result.accelerating,
  );

  final (lateralName, lateral) = _aliasChannel(session, 'lateralAcceleration');
  if (lateral != null) {
    final track = result.cornering;
    track.channel = lateralName;
    track.unit = lateral.unit;
    track.threshold = options.cornering;
    if (!_unitMatches(lateral.unit, [options.cornering.unit])) {
      track.unresolvedReason = 'unitMismatch';
    } else {
      track.provenance = lateralName.toLowerCase().endsWith('-calc')
          ? drivingStateCalculated
          : drivingStateMeasured;
      _classify(
        lateral,
        (value) => value.abs(),
        options.cornering,
        options.minimumDurationSeconds,
        startTime,
        endTime,
        track,
      );
    }
  } else {
    result.cornering.unresolvedReason = 'noLateralAccelerationChannel';
  }

  // Coasting: moving, both pedal states known, neither active.
  final coasting = result.coasting;
  final (speedName, speed) = _aliasChannel(session, 'speed');
  if (result.braking.provenance == drivingStateUnknown ||
      result.accelerating.provenance == drivingStateUnknown) {
    coasting.unresolvedReason = 'pedalStateUnknown';
  } else if (speed == null) {
    coasting.unresolvedReason = 'noSpeedChannel';
  } else if (!_unitMatches(speed.unit, const ['km/h', 'kmh'])) {
    coasting.unresolvedReason = 'unitMismatch';
  } else {
    final moving = DrivingStateTrack();
    final movingThreshold = BrakingThreshold(
      options.minimumSpeedKmh,
      math.max(0.0, options.minimumSpeedKmh - 2.0),
      'km/h',
    );
    _classify(
      speed,
      (value) => value,
      movingThreshold,
      options.minimumDurationSeconds,
      startTime,
      endTime,
      moving,
    );
    coasting.provenance =
        result.braking.provenance == drivingStateMeasured &&
            result.accelerating.provenance == drivingStateMeasured
        ? drivingStateMeasured
        : drivingStateInferred;
    coasting.channel = speedName;
    coasting.unit = speed.unit;
    coasting.threshold = movingThreshold;
    coasting.known.addAll(
      _intersect(
        _intersect(_unite(result.braking.known), _unite(result.accelerating.known)),
        _unite(moving.known),
      ),
    );
    final candidates = _subtract(
      _intersect(coasting.known, _unite(moving.active)),
      _unite([...result.braking.active, ...result.accelerating.active]),
    );
    for (final interval in candidates) {
      if (interval.end - interval.start >= options.minimumDurationSeconds) {
        coasting.active.add(interval);
      } else {
        ++coasting.rejectedSpikes;
      }
    }
  }
  return result;
}

/// Where two states hold together (for example braking while cornering).
List<DrivingStateInterval> overlapOf(
  List<DrivingStateInterval> first,
  List<DrivingStateInterval> second,
) => _intersect(_unite(first), _unite(second));

/// The total length of [intervals] in seconds.
double intervalSeconds(List<DrivingStateInterval> intervals) {
  var total = 0.0;
  for (final interval in intervals) {
    total += interval.end - interval.start;
  }
  return total;
}

/// Distance travelled over [intervals]: the `speed` alias integrated
/// between its samples in its own unit; nothing is counted across a missing
/// speed sample. 0 for a speed in a unit not known. Overlays (d4d1039) reads
/// every speed as km/h here; an mph speed differs from it on purpose.
double travelledMeters(TelemetrySession session, List<DrivingStateInterval> intervals) {
  final speed = session.channels[session.aliases['speed'] ?? ''];
  if (speed == null || speed.timestamps.length != speed.values.length) return 0.0;
  final factor = metresPerSecondPerSpeedUnit(speed.unit);
  if (factor == null) return 0.0;
  final times = speed.timestamps;
  var meters = 0.0;
  for (final interval in intervals) {
    for (
      var index = lowerBound(times, interval.start);
      index + 1 < times.length && times[index + 1] <= interval.end;
      ++index
    ) {
      final double a = speed.values[index], b = speed.values[index + 1];
      if (a.isFinite && b.isFinite) {
        meters += (a + b) / 2.0 * factor * (times[index + 1] - times[index]);
      }
    }
  }
  return meters;
}
