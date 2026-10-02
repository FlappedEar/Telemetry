import 'dart:collection';
import 'dart:typed_data';

import 'timing_gate.dart';

/// How [TelemetrySession.valueAt] reads between two samples.
enum InterpolationMode {
  /// The closer sample; the earlier one on a tie.
  nearest,

  /// The sample at or before the time.
  previous,

  /// Straight line between two finite neighbours.
  linear,
}

/// One recorded quantity: strictly increasing times in seconds and float32
/// values, where NaN means no data.
final class TelemetryChannel {
  TelemetryChannel({
    required this.name,
    this.unit = '',
    required this.timestamps,
    required this.values,
  }) : baseIntervalSeconds = _medianInterval(timestamps);

  final String name;
  final String unit;
  final Float64List timestamps;
  final Float32List values;

  /// The median positive interval between samples, or 0 with fewer than two.
  final double baseIntervalSeconds;

  int get sampleCount => timestamps.length;

  static double _medianInterval(Float64List timestamps) {
    final intervals = <double>[];
    for (var index = 1; index < timestamps.length; ++index) {
      final interval = timestamps[index] - timestamps[index - 1];
      if (interval.isFinite && interval > 0.0) intervals.add(interval);
    }
    if (intervals.isEmpty) return 0.0;
    intervals.sort();
    return intervals[intervals.length ~/ 2];
  }
}

/// Longest interval between two samples that is still continuous data: three
/// times the channel's median interval, and at least [minimumSeconds].
double telemetryGapThreshold(TelemetryChannel channel, [double minimumSeconds = 0.0]) {
  final floor = minimumSeconds > 0.0 ? minimumSeconds : 0.0;
  final threshold = channel.baseIntervalSeconds * 3.0;
  return threshold > floor ? threshold : floor;
}

/// One imported recording. Immutable once built.
final class TelemetrySession {
  TelemetrySession({
    required this.duration,
    required this.startTime,
    required Map<String, String> metadata,
    required Map<String, TelemetryChannel> channels,
    required Map<String, String> aliases,
    required List<String> warnings,
    required List<TimingGate> timingGates,
    required this.sampleCount,
  }) : metadata = UnmodifiableMapView(Map.of(metadata)),
       channels = UnmodifiableMapView(Map.of(channels)),
       aliases = UnmodifiableMapView(Map.of(aliases)),
       warnings = List.unmodifiable(warnings),
       timingGates = List.unmodifiable(timingGates);

  /// Seconds from the first to the last accepted sample.
  final double duration;

  /// The first accepted timestamp as written in the file, before rebasing to 0.
  final double startTime;
  final Map<String, String> metadata;
  final Map<String, TelemetryChannel> channels;

  /// Semantic name (speed, latitude, throttle...) to channel name.
  final Map<String, String> aliases;
  final List<String> warnings;
  final List<TimingGate> timingGates;
  final int sampleCount;

  /// Channel names in case-insensitive order.
  List<String> channelNames() => sortedChannelNames(channels.keys);

  /// The channel named [name], or the channel an alias of that name points to.
  TelemetryChannel? channel(String name) => channels[aliases[name] ?? name];

  /// The value of [channelName] (or the channel its alias names) at [time].
  ///
  /// Null outside the channel's range and on missing samples. Linear reading
  /// needs two adjacent finite samples; gaps are never bridged.
  double? valueAt(
    String channelName,
    double time, [
    InterpolationMode mode = InterpolationMode.linear,
  ]) {
    final found = channel(channelName);
    if (found == null || found.timestamps.isEmpty || !time.isFinite) {
      return null;
    }
    final timestamps = found.timestamps;
    final values = found.values;
    if (timestamps.length != values.length || time < timestamps.first || time > timestamps.last) {
      return null;
    }
    final next = lowerBound(timestamps, time);
    double? finiteAt(int index) {
      final value = values[index];
      return value.isFinite ? value : null;
    }

    if (timestamps[next] == time) return finiteAt(next);
    if (next == 0) return null;
    final previous = next - 1;
    switch (mode) {
      case InterpolationMode.previous:
        return finiteAt(previous);
      case InterpolationMode.nearest:
        return time - timestamps[previous] <= timestamps[next] - time
            ? finiteAt(previous)
            : finiteAt(next);
      case InterpolationMode.linear:
        final span = timestamps[next] - timestamps[previous];
        final before = finiteAt(previous);
        final after = finiteAt(next);
        if (before == null || after == null || !span.isFinite || span <= 0.0) {
          return null;
        }
        final ratio = (time - timestamps[previous]) / span;
        final value = before + (after - before) * ratio;
        return value.isFinite ? value : null;
    }
  }

  /// Actual samples of [channelName] between [rangeStart] and [rangeEnd] (in
  /// either order), split at every missing value and at every interval longer
  /// than [telemetryGapThreshold], for analysis and plotting.
  ///
  /// Each of [maximumPoints] time buckets contributes its ordered minimum and
  /// maximum, so short extremes survive. When that still exceeds twice
  /// [maximumPoints], the overall minimum and maximum plus evenly spaced
  /// samples are kept. Empty for an invalid range, a missing or malformed
  /// channel, or no data in range; a zero-length range returns the raw samples.
  ///
  /// Port of `TelemetrySession::sampledSegments` in FlappedEar Overlays
  /// `native/src/telemetry/TelemetrySession.cpp` (revision d4d1039).
  List<List<SamplePoint>> sampledSegments(
    String channelName,
    double rangeStart,
    double rangeEnd,
    int maximumPoints,
  ) {
    if (!rangeStart.isFinite || !rangeEnd.isFinite || maximumPoints < 2) return [];
    if (rangeStart > rangeEnd) {
      final swap = rangeStart;
      rangeStart = rangeEnd;
      rangeEnd = swap;
    }
    final span = rangeEnd - rangeStart;
    // Finite endpoints can still subtract to infinity. Reject before bucket
    // arithmetic can produce NaN and reach a floating-to-integer conversion.
    if (!span.isFinite) return [];
    final found = channel(channelName);
    if (found == null ||
        found.timestamps.length != found.values.length ||
        found.timestamps.isEmpty) {
      return [];
    }

    final rawSegments = <List<SamplePoint>>[];
    var current = <SamplePoint>[];
    final gapThreshold = telemetryGapThreshold(found);
    for (var index = 0; index < found.timestamps.length; ++index) {
      final timestamp = found.timestamps[index];
      final double value = found.values[index];
      if (!timestamp.isFinite || timestamp < rangeStart || timestamp > rangeEnd) continue;
      if (!value.isFinite) {
        if (current.isNotEmpty) {
          rawSegments.add(current);
          current = [];
        }
        continue;
      }
      if (current.isNotEmpty &&
          gapThreshold > 0.0 &&
          timestamp - current.last.time > gapThreshold) {
        rawSegments.add(current);
        current = [];
      }
      current.add((time: timestamp, value: value));
    }
    if (current.isNotEmpty) rawSegments.add(current);
    if (rawSegments.isEmpty) return [];
    if (span <= 0.0) return rawSegments;

    final result = <List<SamplePoint>>[];
    for (final segment in rawSegments) {
      final reduced = <SamplePoint>[];
      var activeBucket = -1;
      var minimum = segment.first;
      var maximum = segment.first;
      void flushBucket() {
        if (activeBucket < 0) return;
        if (minimum.time <= maximum.time) {
          reduced.add(minimum);
          if (!_qtFuzzyEqualPoints(maximum, minimum)) reduced.add(maximum);
        } else {
          reduced.add(maximum);
          reduced.add(minimum);
        }
      }

      for (final point in segment) {
        final bucketPosition = (point.time - rangeStart) / span * maximumPoints;
        if (!bucketPosition.isFinite) return [];
        final bucket = bucketPosition.clamp(0.0, (maximumPoints - 1).toDouble()).toInt();
        if (bucket != activeBucket) {
          flushBucket();
          activeBucket = bucket;
          minimum = point;
          maximum = point;
        } else {
          if (point.value < minimum.value) minimum = point;
          if (point.value > maximum.value) maximum = point;
        }
      }
      flushBucket();
      if (reduced.isNotEmpty) result.add(reduced);
    }
    var totalPoints = 0;
    for (final segment in result) {
      totalPoints += segment.length;
    }
    final pointLimit = maximumPoints * 2;
    if (totalPoints <= pointLimit) return result;

    final candidateSegments = <int>[];
    final candidates = <SamplePoint>[];
    for (var segmentIndex = 0; segmentIndex < result.length; ++segmentIndex) {
      for (final point in result[segmentIndex]) {
        candidateSegments.add(segmentIndex);
        candidates.add(point);
      }
    }
    final selected = List<bool>.filled(candidates.length, false);
    var minimumIndex = 0;
    var maximumIndex = 0;
    for (var index = 1; index < candidates.length; ++index) {
      if (candidates[index].value < candidates[minimumIndex].value) minimumIndex = index;
      if (candidates[index].value > candidates[maximumIndex].value) maximumIndex = index;
    }
    selected[minimumIndex] = true;
    selected[maximumIndex] = true;
    final uniformBudget = pointLimit - 2 > 1 ? pointLimit - 2 : 1;
    for (var slot = 0; slot < uniformBudget; ++slot) {
      final index = uniformBudget == 1 ? 0 : slot * (candidates.length - 1) ~/ (uniformBudget - 1);
      selected[index] = true;
    }
    final bounded = <List<SamplePoint>>[];
    var previousSegment = -1;
    for (var index = 0; index < candidates.length; ++index) {
      if (!selected[index]) continue;
      if (bounded.isEmpty || candidateSegments[index] != previousSegment) bounded.add([]);
      bounded.last.add(candidates[index]);
      previousSegment = candidateSegments[index];
    }
    return bounded;
  }
}

/// One sample of a channel: telemetry time in seconds and its value.
typedef SamplePoint = ({double time, double value});

/// Qt's `QPointF` equality, which Overlays relies on: fuzzy to about 12
/// significant digits per coordinate.
bool _qtFuzzyEqualPoints(SamplePoint a, SamplePoint b) =>
    _qtFuzzyEqual(a.time, b.time) && _qtFuzzyEqual(a.value, b.value);

bool _qtFuzzyEqual(double a, double b) {
  if (a == 0.0 || b == 0.0) return (a - b).abs() <= 0.000000000001;
  final smaller = a.abs() < b.abs() ? a.abs() : b.abs();
  return (a - b).abs() * 1000000000000.0 <= smaller;
}

/// Sorts names case-insensitively; names equal apart from case keep a fixed
/// order by their exact spelling.
List<String> sortedChannelNames(Iterable<String> names) {
  final sorted = names.toList();
  sorted.sort((a, b) {
    final folded = a.toLowerCase().compareTo(b.toLowerCase());
    return folded != 0 ? folded : a.compareTo(b);
  });
  return sorted;
}

/// Index of the first element not less than [value] in ascending [list].
int lowerBound(List<double> list, double value, [int start = 0, int? end]) {
  var low = start;
  var high = end ?? list.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (list[middle] < value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// Index of the first element greater than [value] in ascending [list].
int upperBound(List<double> list, double value, [int start = 0, int? end]) {
  var low = start;
  var high = end ?? list.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (list[middle] <= value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}
