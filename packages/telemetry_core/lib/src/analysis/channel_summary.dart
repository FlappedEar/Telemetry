// Port of FlappedEar Overlays native/src/telemetry/ChannelSummary.{h,cpp}
// (revision d4d1039, FET-36): summaries of one recorded channel over a time
// interval (KAN-67, KAN-69) and its continuously recorded cooling (KAN-68).
//
// Mean: time-weighted. Consecutive valid samples closer together than the
// channel's gap threshold are joined linearly; the mean is the integral of
// that line over the covered time divided by the covered time. A gap is never
// bridged, so a dropout neither pulls the mean nor counts as covered.
// Coverage: covered time / interval length (0..1).
// Artifacts (always counted, never silently dropped):
//  - a value outside the policy's plausible range is excluded;
//  - with zeroIsPlaceholder, an exact 0 is excluded when the channel's typical
//    (median) value is far from zero: OBD adapters report 0 before a first
//    response or after a dropout.
// Units are reported as declared ("" when the recording does not declare
// them).
import '../telemetry_session.dart';

const String channelSummaryAlgorithm = 'channel-summary-v1';

/// The channel is not in the recording.
const String channelSummaryMissing = 'channelMissing';

/// The channel has no valid sample in the interval.
const String channelSummaryNoSamples = 'noValidSamples';

/// What counts as a plausible sample of a channel.
final class ChannelSummaryPolicy {
  const ChannelSummaryPolicy({
    this.minimumPlausible = double.negativeInfinity,
    this.maximumPlausible = double.infinity,
    this.zeroIsPlaceholder = false,
    this.placeholderTypicalAbove = 20.0,
  });

  final double minimumPlausible;
  final double maximumPlausible;

  /// An exact zero may be a placeholder (see [zeroIsPlaceholder]).
  final bool zeroIsPlaceholder;

  /// Zero counts as a placeholder only when the channel's median is above
  /// this.
  final double placeholderTypicalAbove;
}

/// Temperatures (°C): -40..250 plausible, exact zeros are placeholders.
const ChannelSummaryPolicy temperatureSummaryPolicy = ChannelSummaryPolicy(
  minimumPlausible: -40.0,
  maximumPlausible: 250.0,
  zeroIsPlaceholder: true,
);

/// Heart rate (bpm): 30..230 plausible.
const ChannelSummaryPolicy heartRateSummaryPolicy = ChannelSummaryPolicy(
  minimumPlausible: 30.0,
  maximumPlausible: 230.0,
);

/// Whether an exact zero in [channel] is a placeholder under [policy]: only
/// when the policy says so and the channel's median is above its typical
/// level.
bool zeroIsPlaceholder(TelemetryChannel channel, ChannelSummaryPolicy policy) {
  if (!policy.zeroIsPlaceholder) return false;
  final finite = <double>[
    for (final value in channel.values)
      if (value.isFinite) value,
  ];
  if (finite.isEmpty) return false;
  finite.sort();
  return finite[finite.length ~/ 2].abs() > policy.placeholderTypicalAbove;
}

/// A finite sample inside the policy's plausible range that is not a
/// placeholder.
bool plausibleSample(double value, ChannelSummaryPolicy policy, bool zeroPlaceholder) =>
    value.isFinite &&
    value >= policy.minimumPlausible &&
    value <= policy.maximumPlausible &&
    !(zeroPlaceholder && value == 0.0);

/// One recorded channel over an interval, or why there is nothing.
final class ChannelSummary {
  const ChannelSummary({
    this.channel = '',
    this.unit = '',
    this.startTime = 0.0,
    this.endTime = 0.0,
    this.sampleCount = 0,
    this.excludedArtifacts = 0,
    this.minimum,
    this.maximum,
    this.mean,
    this.minimumTime,
    this.maximumTime,
    this.coveredSeconds = 0.0,
    this.coverage = 0.0,
    this.unavailableReason = '',
    this.valid = false,
  });

  /// The channel's name in the recording (an alias resolved).
  final String channel;
  final String unit;
  final double startTime;
  final double endTime;

  /// Valid samples used.
  final int sampleCount;

  /// Implausible values and placeholders left out.
  final int excludedArtifacts;
  final double? minimum, maximum, mean;
  final double? minimumTime, maximumTime;
  final double coveredSeconds;

  /// [coveredSeconds] over the interval's length, 0..1.
  final double coverage;

  /// [channelSummaryMissing] or [channelSummaryNoSamples] when not [valid].
  final String unavailableReason;
  final bool valid;
}

/// The channel [channelOrAlias] of [session] from [startTime] to [endTime].
ChannelSummary summarizeChannel(
  TelemetrySession session,
  String channelOrAlias,
  double startTime,
  double endTime,
  ChannelSummaryPolicy policy,
) {
  final name = session.aliases[channelOrAlias] ?? channelOrAlias;
  final found = session.channels[name];
  if (found == null || found.timestamps.length != found.values.length) {
    return ChannelSummary(
      channel: name,
      startTime: startTime,
      endTime: endTime,
      unavailableReason: channelSummaryMissing,
    );
  }
  return _summarize(found, startTime, endTime, policy, null);
}

// [zeroPlaceholder] is computed from the whole channel when null; callers
// summarizing one channel many times pass it once.
ChannelSummary _summarize(
  TelemetryChannel channel,
  double startTime,
  double endTime,
  ChannelSummaryPolicy policy,
  bool? zeroPlaceholder,
) {
  ChannelSummary unavailable(String reason, {int excluded = 0}) => ChannelSummary(
    channel: channel.name,
    unit: channel.unit,
    startTime: startTime,
    endTime: endTime,
    excludedArtifacts: excluded,
    unavailableReason: reason,
  );
  if (!startTime.isFinite || !endTime.isFinite || endTime <= startTime) {
    return unavailable(channelSummaryNoSamples);
  }
  final placeholder = zeroPlaceholder ?? zeroIsPlaceholder(channel, policy);
  final gapLimit = telemetryGapThreshold(channel);
  final times = channel.timestamps, values = channel.values;
  var sampleCount = 0, excluded = 0;
  double? minimum, maximum, minimumTime, maximumTime;
  double? previousTime, previousValue;
  var integral = 0.0, covered = 0.0;
  // Timestamps are strictly increasing: only the samples inside the interval
  // are visited.
  for (var i = lowerBound(times, startTime); i < times.length; ++i) {
    final time = times[i];
    if (time > endTime) break;
    final double value = values[i];
    if (!value.isFinite) {
      previousTime = previousValue = null;
      continue;
    }
    if (value < policy.minimumPlausible ||
        value > policy.maximumPlausible ||
        (placeholder && value == 0.0)) {
      ++excluded;
      previousTime = previousValue = null; // never join across an excluded sample
      continue;
    }
    ++sampleCount;
    if (minimum == null || value < minimum) {
      minimum = value;
      minimumTime = time;
    }
    if (maximum == null || value > maximum) {
      maximum = value;
      maximumTime = time;
    }
    if (previousTime != null && time - previousTime <= gapLimit) {
      final span = time - previousTime;
      integral += span * (value + previousValue!) / 2.0;
      covered += span;
    }
    previousTime = time;
    previousValue = value;
  }
  if (sampleCount == 0) return unavailable(channelSummaryNoSamples, excluded: excluded);
  return ChannelSummary(
    channel: channel.name,
    unit: channel.unit,
    startTime: startTime,
    endTime: endTime,
    sampleCount: sampleCount,
    excludedArtifacts: excluded,
    minimum: minimum,
    maximum: maximum,
    // A single isolated sample has a value but no covered time.
    mean: covered > 0.0 ? integral / covered : minimum,
    minimumTime: minimumTime,
    maximumTime: maximumTime,
    coveredSeconds: covered,
    coverage: (covered / (endTime - startTime)).clamp(0.0, 1.0),
    valid: true,
  );
}

/// Summarizes one channel of one recording many times: the placeholder
/// decision is taken once for the whole channel.
final class ChannelSummarizer {
  ChannelSummarizer(TelemetrySession session, String channelOrAlias, this.policy)
    : name = session.aliases[channelOrAlias] ?? channelOrAlias,
      _channel = _usable(session.channels[session.aliases[channelOrAlias] ?? channelOrAlias]) {
    final channel = _channel;
    _placeholder = channel != null && zeroIsPlaceholder(channel, policy);
  }

  static TelemetryChannel? _usable(TelemetryChannel? channel) =>
      channel != null && channel.timestamps.length == channel.values.length ? channel : null;

  final String name;
  final ChannelSummaryPolicy policy;
  final TelemetryChannel? _channel;
  late final bool _placeholder;

  /// The same as [summarizeChannel] over [startTime]..[endTime].
  ChannelSummary summarize(double startTime, double endTime) {
    final channel = _channel;
    if (channel == null) {
      return ChannelSummary(
        channel: name,
        startTime: startTime,
        endTime: endTime,
        unavailableReason: channelSummaryMissing,
      );
    }
    return _summarize(channel, startTime, endTime, policy, _placeholder);
  }
}

/// One summary of disjoint intervals of the same channel, for example a
/// track segment that crosses the start/finish line and so covers the end
/// and the start of a lap (KAN-70). The mean is weighted by each part's
/// covered time; coverage is covered time over the parts' total length.
/// The start and end are those of the first and last part. Valid when any
/// part is valid.
ChannelSummary combineChannelSummaries(List<ChannelSummary> parts) {
  if (parts.length == 1) return parts.first;
  if (parts.isEmpty) return const ChannelSummary(unavailableReason: channelSummaryNoSamples);
  var length = 0.0, weighted = 0.0, covered = 0.0;
  var sampleCount = 0, excluded = 0;
  double? minimum, maximum, minimumTime, maximumTime;
  for (final part in parts) {
    final span = part.endTime - part.startTime;
    length += span > 0.0 ? span : 0.0;
    excluded += part.excludedArtifacts;
    if (!part.valid) continue;
    sampleCount += part.sampleCount;
    covered += part.coveredSeconds;
    weighted += part.mean! * part.coveredSeconds;
    if (minimum == null || part.minimum! < minimum) {
      minimum = part.minimum;
      minimumTime = part.minimumTime;
    }
    if (maximum == null || part.maximum! > maximum) {
      maximum = part.maximum;
      maximumTime = part.maximumTime;
    }
  }
  final first = parts.first;
  if (minimum == null || covered <= 0.0) {
    // Missing everywhere stays "missing"; otherwise there were no usable
    // samples.
    final missing = parts.every((part) => part.unavailableReason == channelSummaryMissing);
    return ChannelSummary(
      channel: first.channel,
      unit: first.unit,
      startTime: first.startTime,
      endTime: parts.last.endTime,
      sampleCount: sampleCount,
      excludedArtifacts: excluded,
      unavailableReason: missing ? channelSummaryMissing : channelSummaryNoSamples,
    );
  }
  return ChannelSummary(
    channel: first.channel,
    unit: first.unit,
    startTime: first.startTime,
    endTime: parts.last.endTime,
    sampleCount: sampleCount,
    excludedArtifacts: excluded,
    minimum: minimum,
    maximum: maximum,
    mean: weighted / covered,
    minimumTime: minimumTime,
    maximumTime: maximumTime,
    coveredSeconds: covered,
    coverage: length > 0.0 ? (covered / length).clamp(0.0, 1.0) : 0.0,
    valid: true,
  );
}

/// The recording's own temperature channels (name contains "temp", any
/// case), in name order. Never invented: an absent sensor is simply not
/// listed.
List<String> recordedTemperatureChannels(TelemetrySession session) => [
  for (final name in session.channelNames())
    if (name.toLowerCase().contains('temp')) name,
];

/// A continuously recorded cooling interval (KAN-68): from a local peak to
/// the following trough within one stretch of recording without a gap.
final class CoolingInterval {
  const CoolingInterval({
    required this.startTime,
    required this.endTime,
    required this.startValue,
    required this.endValue,
  });

  final double startTime;
  final double endTime;

  /// Smoothed values at the peak and the trough.
  final double startValue;
  final double endValue;

  double get drop => startValue - endValue;
  double get seconds => endTime - startTime;
}

/// What counts as cooling.
final class CoolingOptions {
  const CoolingOptions({
    this.minimumDrop = 5.0,
    this.minimumSeconds = 30.0,
    this.smoothingSeconds = 5.0,
  });

  final double minimumDrop;
  final double minimumSeconds;

  /// Values are smoothed with a centred moving average over this first, so
  /// sensor quantization does not split one cooling into many.
  final double smoothingSeconds;
}

/// Every continuously recorded cooling of [channelOrAlias]: dropping by at
/// least [CoolingOptions.minimumDrop] over at least
/// [CoolingOptions.minimumSeconds]. A gap (or an excluded artifact) ends a
/// stretch, so no interval ever spans an unrecorded break.
List<CoolingInterval> findCoolingIntervals(
  TelemetrySession session,
  String channelOrAlias,
  ChannelSummaryPolicy policy, {
  CoolingOptions options = const CoolingOptions(),
}) {
  final intervals = <CoolingInterval>[];
  final channel = session.channels[session.aliases[channelOrAlias] ?? channelOrAlias];
  if (channel == null || channel.timestamps.length != channel.values.length) return intervals;
  final placeholder = zeroIsPlaceholder(channel, policy);
  final gapLimit = telemetryGapThreshold(channel);
  // Split into continuously recorded stretches of valid samples.
  final stretches = <List<(double, double)>>[[]];
  var previousTime = double.negativeInfinity;
  for (var i = 0; i < channel.timestamps.length; ++i) {
    final time = channel.timestamps[i];
    final double value = channel.values[i];
    final valid = plausibleSample(value, policy, placeholder);
    if (!valid || time - previousTime > gapLimit) {
      if (stretches.last.isNotEmpty) stretches.add([]);
    }
    if (!valid) continue;
    stretches.last.add((time, value));
    previousTime = time;
  }
  for (final stretch in stretches) {
    if (stretch.length < 3) continue;
    // Centred moving average over the smoothing window (two pointers).
    final smooth = List<double>.filled(stretch.length, 0.0);
    var lo = 0, hi = 0;
    var sum = 0.0;
    final half = options.smoothingSeconds / 2.0;
    for (var i = 0; i < stretch.length; ++i) {
      while (hi < stretch.length && stretch[hi].$1 <= stretch[i].$1 + half) {
        sum += stretch[hi++].$2;
      }
      while (stretch[lo].$1 < stretch[i].$1 - half) {
        sum -= stretch[lo++].$2;
      }
      smooth[i] = sum / (hi - lo);
    }
    // Peak -> following trough, walking the smoothed series once.
    var peak = 0, trough = 0;
    var falling = false;
    void close() {
      final interval = CoolingInterval(
        startTime: stretch[peak].$1,
        endTime: stretch[trough].$1,
        startValue: smooth[peak],
        endValue: smooth[trough],
      );
      if (interval.drop >= options.minimumDrop && interval.seconds >= options.minimumSeconds) {
        intervals.add(interval);
      }
    }

    for (var i = 1; i < stretch.length; ++i) {
      if (!falling) {
        if (smooth[i] >= smooth[peak]) {
          peak = i;
          continue;
        }
        if (smooth[peak] - smooth[i] > 0.0) {
          falling = true;
          trough = i;
        }
      } else {
        if (smooth[i] < smooth[trough] - 1e-9) {
          trough = i;
          continue;
        }
        if (smooth[i] <= smooth[trough] + 1e-9) continue; // a flat bottom does not extend it
        // Rising again: close this cooling when the rise is real, not noise.
        if (smooth[i] - smooth[trough] >= 1.0) {
          close();
          falling = false;
          peak = i;
        }
      }
    }
    if (falling) close();
  }
  return intervals;
}
