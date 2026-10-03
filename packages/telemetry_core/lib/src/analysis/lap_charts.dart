// Port of the lap-detail charts of FlappedEar Overlays (revision d4d1039,
// FET-37): AnalysisController::sessionSeries and the channel choice of
// AnalysisControllerOuting.cpp, which the lap page's charts draw on a time
// axis.
import '../telemetry_session.dart';

/// The channel is not in the recording.
const String chartReasonChannelMissing = 'channelMissing';

/// The range asked for is not a finite range.
const String chartReasonInvalidRange = 'invalidRange';

/// The channel's times and values do not pair up, or it has no sample.
const String chartReasonChannelMalformed = 'channelMalformed';

/// One point of a chart: [x] across the shown range (0 at its start, 1 at
/// its end) and the value.
typedef ChartPoint = ({double x, double y});

/// What a chart draws for one channel over one range: runs of points that
/// are never joined across a gap, their value range and the channel's unit.
/// Empty with no [reason] when the range simply has no data; [reason] says
/// what went wrong otherwise, so "no data here" is never confused with a
/// failure.
final class ChartSeries {
  const ChartSeries({
    this.segments = const [],
    this.minimum = 0.0,
    this.maximum = 0.0,
    this.unit = '',
    this.brakingUp = false,
    this.reason = '',
  });

  /// Nothing to draw and nothing wrong.
  static const empty = ChartSeries();

  /// Nothing to draw because of [reason].
  const ChartSeries.failed(this.reason)
    : segments = const [],
      minimum = 0.0,
      maximum = 0.0,
      unit = '',
      brakingUp = false;

  final List<List<ChartPoint>> segments;
  final double minimum;
  final double maximum;
  final String unit;

  /// Longitudinal acceleration: braking (negative) is drawn upward, without
  /// changing the values.
  final bool brakingUp;
  final String reason;

  bool get hasData => segments.isNotEmpty;
}

/// [channelName]'s samples in [start]..[end] (telemetry seconds) at up to
/// [maximumPoints] buckets (bounded to 2..2000), as a time-axis chart
/// (Overlays' `sessionSeries`).
ChartSeries timeSeries(
  TelemetrySession session,
  String channelName,
  double start,
  double end,
  int maximumPoints,
) {
  final bounded = maximumPoints.clamp(2, 2000);
  final sampled = session.sampledSegments(channelName, start, end, bounded);
  if (sampled.isEmpty) {
    // Why sampledSegments returned nothing, as Overlays' status reports it.
    if (!start.isFinite || !end.isFinite || !(end - start).abs().isFinite) {
      return const ChartSeries.failed(chartReasonInvalidRange);
    }
    final channel = session.channel(channelName);
    if (channel == null) return const ChartSeries.failed(chartReasonChannelMissing);
    if (channel.timestamps.length != channel.values.length || channel.timestamps.isEmpty) {
      return const ChartSeries.failed(chartReasonChannelMalformed);
    }
    return ChartSeries.empty;
  }
  var minimum = sampled.first.first.value;
  var maximum = minimum;
  for (final segment in sampled) {
    for (final sample in segment) {
      if (sample.value < minimum) minimum = sample.value;
      if (sample.value > maximum) maximum = sample.value;
    }
  }
  final span = end - start;
  final resolved = session.aliases[channelName] ?? channelName;
  return ChartSeries(
    segments: List.unmodifiable([
      for (final segment in sampled)
        List<ChartPoint>.unmodifiable([
          for (final sample in segment)
            (x: span == 0.0 ? 0.0 : (sample.time - start) / span, y: sample.value),
        ]),
    ]),
    minimum: minimum,
    maximum: maximum,
    unit: session.channels[resolved]?.unit ?? '',
    brakingUp: resolved == (session.aliases['longitudinalAcceleration'] ?? ''),
  );
}

/// Most charts a lap or comparison shows at once.
const int maximumChartChannels = 4;

/// The channels a lap's charts show first: the remembered choice
/// ([remembered], those the recording has, at most four), otherwise the
/// recording's speed, lateral and longitudinal G, as in Overlays. With
/// [includePedals] the fourth chart goes to the throttle, or else the brake,
/// when recorded (Telemetry's addition: Overlays shows them only when added).
/// [pending] (a channel asked for, such as a focus area's) comes first.
List<String> lapChartChannels(
  TelemetrySession session, {
  List<String>? remembered,
  String pending = '',
  bool includePedals = true,
}) {
  final channels = <String>[];
  if (remembered != null) {
    for (final name in remembered) {
      if (session.channels.containsKey(name) && !channels.contains(name)) channels.add(name);
      if (channels.length == maximumChartChannels) break;
    }
  } else {
    for (final alias in const ['speed', 'lateralAcceleration', 'longitudinalAcceleration']) {
      final name = session.aliases[alias] ?? alias;
      if (session.channels.containsKey(name) && !channels.contains(name)) channels.add(name);
    }
    if (includePedals) {
      for (final alias in const ['throttle', 'brake']) {
        final name = session.aliases[alias];
        if (name == null || !session.channels.containsKey(name) || channels.contains(name)) {
          continue;
        }
        if (channels.length < maximumChartChannels) channels.add(name);
        break;
      }
    }
  }
  if (session.channels.containsKey(pending)) {
    channels
      ..remove(pending)
      ..insert(0, pending);
    while (channels.length > maximumChartChannels) {
      channels.removeLast();
    }
  }
  return channels;
}

/// The value of [series] nearest to [x] (0..1 across its range), or null
/// without data: what Overlays' comparison charts read out at the cursor.
double? nearestChartValue(ChartSeries series, double x) {
  double? best;
  var bestDistance = double.infinity;
  for (final segment in series.segments) {
    for (final point in segment) {
      final distance = (point.x - x).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = point.y;
      }
    }
  }
  return best;
}
