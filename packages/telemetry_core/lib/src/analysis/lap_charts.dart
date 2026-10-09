// Port of the lap-detail charts of FlappedEar Overlays (revision d4d1039,
// FET-37): AnalysisController::sessionSeries and the channel choice of
// AnalysisControllerOuting.cpp, which the lap page's charts draw on a time
// axis.
import '../telemetry_session.dart';
import '../speed_units.dart';
import 'angular_channels.dart';

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
    this.angular = false,
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
      brakingUp = false,
      angular = false;

  final List<List<ChartPoint>> segments;
  final double minimum;
  final double maximum;
  final String unit;

  /// Longitudinal acceleration: braking (negative) is drawn upward, without
  /// changing the values.
  final bool brakingUp;

  /// A compass direction ([isAngularChannel]): the points are unwrapped
  /// degrees, continuous across north, so a value is read as
  /// [normalizeDegrees] of it. [minimum] and [maximum] are unwrapped too.
  final bool angular;
  final String reason;

  bool get hasData => segments.isNotEmpty;
}

/// [channelName]'s samples in [start]..[end] (telemetry seconds) at up to
/// [maximumPoints] buckets (bounded to 2..2000), as a time-axis chart
/// (Overlays' `sessionSeries`).
///
/// A compass direction is drawn unwrapped ([ChartSeries.angular]), by whole
/// turns that put its first value at or after [angleReference] (seconds,
/// [start] when null) in 0 up to 360; charts of one lap at different zooms
/// pass the same reference so their lines agree.
ChartSeries timeSeries(
  TelemetrySession session,
  String channelName,
  double start,
  double end,
  int maximumPoints, {
  double? angleReference,
}) {
  final bounded = maximumPoints.clamp(2, 2000);
  final recorded = session.channel(channelName);
  final angular = recorded != null && isAngularChannel(recorded, session);
  final source = angular ? unwrappedAngleSession(recorded) : session;
  final sourceName = angular ? recorded.name : channelName;
  final sampled = source.sampledSegments(sourceName, start, end, bounded);
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
  var offset = 0.0;
  if (angular) {
    final reference =
        firstFiniteValueFrom(source, sourceName, angleReference ?? start) ??
        sampled.first.first.value;
    offset = degreesTurnOffset(reference);
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
            (x: span == 0.0 ? 0.0 : (sample.time - start) / span, y: sample.value + offset),
        ]),
    ]),
    minimum: minimum + offset,
    maximum: maximum + offset,
    unit: effectiveChannelUnit(session, resolved),
    brakingUp: resolved == (session.aliases['longitudinalAcceleration'] ?? ''),
    angular: angular,
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
