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
