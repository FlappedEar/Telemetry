// Port of the A/B lap comparison of FlappedEar Overlays (revision d4d1039,
// FET-37): native/src/app/AnalysisControllerComparison.cpp (the shared
// progress axis, channel and Δ time series by progress, positions on the
// overlay map), AnalysisControllerMapLayers.cpp (the map's colour layers),
// comparisonPreferredChannels of AnalysisControllerCornerAnalyzer.cpp and
// the default channels of qml/ComparisonDetailPanel.qml. Video is not part
// of Telemetry, so AnalysisControllerComparisonVideo.cpp is not ported.
//
// Both laps are drawn on one track-position axis built from lap A's own
// trace, so a corner sits at the same position for both even on different
// lines. Δ is A − B: positive means A is behind.
import '../geometry.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import 'angular_channels.dart';
import 'channel_summary.dart';
import 'lap_charts.dart';
import 'map_layers.dart';
import 'outing_theoretical_best.dart' show MapPoint;
import 'track_progress.dart';

/// The Δ time pseudo-channel of the comparison charts: the cumulative time
/// gap between the laps at the same track position, not a recorded channel.
const String deltaTimeChannel = 'Δ time';

/// One lap of a comparison: its recording, the recording's laps (lap A's
/// trace and start gate build the shared axis) and its bounds.
final class ComparisonLap {
  const ComparisonLap({
    required this.session,
    required this.laps,
    required this.start,
    required this.end,
    required this.lapNumber,
  });

  final TelemetrySession session;
  final LapSession laps;

  /// Recording time in seconds.
  final double start;
  final double end;

  /// The lap's number in its recording, which finds its trace.
  final int lapNumber;
}

/// A layer the overlay map can colour a lap's line by.
final class MapLayerOption {
  const MapLayerOption({
    required this.id,
    required this.label,
    required this.available,
    this.temperature = false,
  });

  final String id;
  final String label;

  /// Recorded on at least one of the laps (the Δ time: the shared axis
  /// exists).
  final bool available;
  final bool temperature;
}

/// One lap's line on the overlay map coloured by a layer, or why not.
final class ComparisonMapLayer {
  const ComparisonMapLayer({
    required this.id,
    this.label = '',
    this.scale = '',
    this.slot = 0,
    this.negativeLabel = '',
    this.positiveLabel = '',
    this.valid = false,
    this.reason = '',
    this.channel = '',
    this.unit = '',
    this.provenance = '',
    this.trace = const MapLayerTrace(),
  });

  final String id;
  final String label;

  /// `sequential`, or `diverging` (signed, centred on zero).
  final String scale;
  final int slot;

  /// What each end of a diverging scale means.
  final String negativeLabel;
  final String positiveLabel;
  final bool valid;

  /// Why there is no layer: `pairNotReady`, `unknownLayer`,
  /// `noProgressAxis`, `channelMissing` or `noSamples`.
  final String reason;

  /// The recording's channel, for a channel layer.
  final String channel;
  final String unit;

  /// `measured`, or `calculated` (the Δ time, or a `-calc` channel).
  final String provenance;
  final MapLayerTrace trace;

  String get algorithm => mapLayerAlgorithm;
  bool get diverging => scale == 'diverging';
}

/// The layer id prefix of a recorded temperature.
const String temperatureLayerPrefix = 'temperature:';

/// Positions the map layers sample along the shared axis.
const int mapLayerPoints = 800;

final class _LayerSpec {
  const _LayerSpec(
    this.id,
    this.label,
    this.alias,
    this.scale, [
    this.negativeLabel = '',
    this.positiveLabel = '',
    this.temperature = false,
  ]);

  final String id;
  final String label;

  /// The channel alias, or the channel itself for a temperature.
  final String alias;
  final String scale;
  final String negativeLabel;
  final String positiveLabel;
  final bool temperature;
}

const List<_LayerSpec> _fixedLayers = [
  _LayerSpec('speed', 'Speed', 'speed', 'sequential'),
  _LayerSpec('delta', 'Δ time (A−B)', '', 'diverging', 'A ahead', 'A behind'),
  _LayerSpec('lateralG', 'Lateral G', 'lateralAcceleration', 'diverging', '−', '+'),
  _LayerSpec(
    'longitudinalG',
    'Longitudinal G',
    'longitudinalAcceleration',
    'diverging',
    'braking',
    'accelerating',
  ),
  _LayerSpec('throttle', 'Throttle', 'throttle', 'sequential'),
  _LayerSpec('brake', 'Brake (measured)', 'brake', 'sequential'),
];

/// Two laps of one compatible group compared on a shared track-position
/// axis. The axis, both projections and the shared map are computed once,
/// on first use; everything else is a pure function of them.
final class LapComparison {
  LapComparison(this.a, this.b, {this.cancelled});

  /// Lap A (green) and lap B (orange).
  final ComparisonLap a;
  final ComparisonLap b;

  /// Checked while the axis and projections are computed.
  final CancellationCheck? cancelled;

  ComparisonLap lap(int slot) => slot == 0 ? a : b;

  ProgressAxis? _axis;
  List<List<ProgressSegment>> _traces = const [[], []];
  MapGeometry? _geometry;
  List<List<List<MapPoint>>>? _overlayTracks;

  void _ensureAxis() {
    if (_axis != null) return;
    var axis = const ProgressAxis();
    final gate = a.laps.selectedStartGate;
    LapTrace? trace;
    for (final candidate in a.laps.lapTraces) {
      if (candidate.lapNumber == a.lapNumber) {
        trace = candidate;
        break;
      }
    }
    if (gate != null && trace != null) {
      final origin = GeoCoordinate(
        (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
        (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
      );
      axis = buildProgressAxis(trace, origin, gate, cancelled: cancelled);
    }
    if (axis.valid) {
      _traces = [
        projectLapTrace(axis, a.session, a.start, a.end, cancelled: cancelled),
        projectLapTrace(axis, b.session, b.start, b.end, cancelled: cancelled),
      ];
    }
    _axis = axis;
  }

  void _ensureGeometry() {
    if (_geometry != null) return;
    final geometry = sharedMapGeometry(a.session, a.start, a.end, b.session, b.start, b.end);
    _overlayTracks = [
      geometry.valid ? mapTrace(a.session, a.start, a.end, geometry) : const [],
      geometry.valid ? mapTrace(b.session, b.start, b.end, geometry) : const [],
    ];
    _geometry = geometry;
  }

  /// The shared axis, from lap A's trace and start gate.
  ProgressAxis get axis {
    _ensureAxis();
    return _axis!;
  }

  /// The length of the shared axis in metres; 0 without one.
  double get axisLengthMeters => axis.valid ? axis.lengthMeters : 0.0;

  /// Lap [slot]'s projection onto the shared axis.
  List<ProgressSegment> trace(int slot) {
    _ensureAxis();
    return _traces[slot];
  }

  /// The overlay map's normalization, shared by both laps.
  MapGeometry get geometry {
    _ensureGeometry();
    return _geometry!;
  }

  /// Lap [slot]'s trace on the overlay map, runs split at GPS gaps.
  List<List<MapPoint>> overlayTrack(int slot) {
    if (slot < 0 || slot > 1) return const [];
    _ensureGeometry();
    return _overlayTracks![slot];
  }

  /// Channels both recordings have, in lap A's order.
  List<String> get availableChannels {
    final other = b.session.channels;
    return [
      for (final name in a.session.channelNames())
        if (other.containsKey(name)) name,
    ];
  }

  /// The recording's own names for speed, throttle and brake among
  /// [availableChannels] (for example "velocity", "throttle_pos").
  List<String> get preferredChannels {
    final available = availableChannels;
    if (available.isEmpty) return const [];
    final preferred = <String>[];
    for (final alias in const ['speed', 'throttle', 'brake']) {
      final name = a.session.aliases[alias] ?? alias;
      if (available.contains(name) && !preferred.contains(name)) preferred.add(name);
    }
    return preferred;
  }

  /// What the charts can show: Δ time, then the shared channels.
  List<String> get chartChannels {
    final available = availableChannels;
    return available.isEmpty ? const [] : [deltaTimeChannel, ...available];
  }

  /// The charts shown first: Δ time and the preferred channels, at most four.
  List<String> get defaultChartChannels {
    final available = chartChannels;
    if (available.isEmpty) return const [];
    final preferred = [deltaTimeChannel, ...preferredChannels];
    final picked = [
      for (final channel in preferred)
        if (available.contains(channel)) channel,
    ];
    return picked.isNotEmpty
        ? picked.take(maximumChartChannels).toList()
        : available.take(available.length < 2 ? available.length : 2).toList();
  }

  /// Lap [slot]'s recording time at [progressMeters] on the shared axis, or
  /// null where its projection has no coverage.
  double? timeAt(int slot, double progressMeters) {
    if (slot < 0 || slot > 1 || !axis.valid) return null;
    return timeAtProgress(trace(slot), progressMeters);
  }

  /// Lap [slot]'s position on the overlay map at [progressMeters], or null.
  MapPoint? positionAt(int slot, double progressMeters) {
    final time = timeAt(slot, progressMeters);
    if (time == null || !geometry.valid) return null;
    return mapPointAt(lap(slot).session, time, geometry);
  }

  /// The Δ time (A − B, seconds) over [startProgress]..[endProgress], from
  /// the delta of the whole lap at (range / [maximumPoints]) steps; x is
  /// across the range.
  ChartSeries deltaSeries(double startProgress, double endProgress, int maximumPoints) {
    if (maximumPoints < 2 || !axis.valid) return ChartSeries.empty;
    if (!startProgress.isFinite || !endProgress.isFinite || endProgress <= startProgress) {
      return const ChartSeries.failed(chartReasonInvalidRange);
    }
    final series = computeDeltaSeries(
      trace(0),
      trace(1),
      (endProgress - startProgress) / maximumPoints,
      cancelled: cancelled,
    );
    final segments = <List<ChartPoint>>[];
    var minimum = 0.0, maximum = 0.0;
    var haveExtent = false;
    for (final run in series) {
      final points = <ChartPoint>[];
      for (final point in run) {
        if (point.progressMeters < startProgress || point.progressMeters > endProgress) continue;
        if (!haveExtent) {
          minimum = maximum = point.deltaSeconds;
          haveExtent = true;
        } else {
          if (point.deltaSeconds < minimum) minimum = point.deltaSeconds;
          if (point.deltaSeconds > maximum) maximum = point.deltaSeconds;
        }
        points.add((
          x: (point.progressMeters - startProgress) / (endProgress - startProgress),
          y: point.deltaSeconds,
        ));
      }
      if (points.isNotEmpty) segments.add(List.unmodifiable(points));
    }
    if (segments.isEmpty) return ChartSeries.empty;
    return ChartSeries(
      segments: List.unmodifiable(segments),
      minimum: minimum,
      maximum: maximum,
      unit: 's',
    );
  }

  /// The whole turns added to lap [slot]'s unwrapped compass direction
  /// [channel]: lap A's first value from its start goes in 0 up to 360, and
  /// lap B's within half a turn of lap A's, so the two lines overlay at any
  /// zoom. Null when the lap has no value of it.
  double? _angleOffset(int slot, String channel) {
    double? start(int slot) {
      final recorded = lap(slot).session.channel(channel);
      if (recorded == null || !isAngularChannel(recorded)) return null;
      return firstFiniteValueFrom(unwrappedAngleSession(recorded), recorded.name, lap(slot).start);
    }

    final first = start(0);
    if (slot == 0) return first == null ? null : degreesTurnOffset(first);
    final own = start(1);
    if (own == null) return null;
    if (first == null) return degreesTurnOffset(own);
    return degreesTurnOffsetNear(own, first + degreesTurnOffset(first));
  }

  /// Lap [slot]'s [channel] at [maximumPoints] evenly spaced positions over
  /// [startProgress]..[endProgress], read at the lap's own time there. A
  /// discrete channel (the gear) keeps its previous value instead of being
  /// interpolated. A channel the lap did not record reports
  /// [chartReasonChannelMissing], never another lap's data. A compass
  /// direction is read unwrapped ([ChartSeries.angular], [_angleOffset]), so
  /// it is never interpolated the long way round across north.
  ChartSeries channelSeries(
    int slot,
    String channel,
    double startProgress,
    double endProgress,
    int maximumPoints,
  ) {
    if (slot < 0 || slot > 1 || maximumPoints < 2) return ChartSeries.empty;
    final session = lap(slot).session;
    final resolved = session.aliases[channel] ?? channel;
    final found = session.channels[resolved];
    if (found == null) return const ChartSeries.failed(chartReasonChannelMissing);
    if (!startProgress.isFinite || !endProgress.isFinite || endProgress <= startProgress) {
      return const ChartSeries.failed(chartReasonInvalidRange);
    }
    if (!axis.valid) return const ChartSeries.failed(chartReasonChannelMissing);
    final interpolation = channel.toLowerCase() == 'gear'
        ? InterpolationMode.previous
        : InterpolationMode.linear;
    final angular = isAngularChannel(found);
    final source = angular ? unwrappedAngleSession(found) : session;
    final sourceName = angular ? found.name : channel;
    final offset = angular ? _angleOffset(slot, channel) ?? 0.0 : 0.0;
    final span = endProgress - startProgress;
    final segments = <List<ChartPoint>>[];
    var current = <ChartPoint>[];
    var minimum = 0.0, maximum = 0.0;
    var haveExtent = false;
    final projection = trace(slot);
    for (var index = 0; index < maximumPoints; ++index) {
      final target = startProgress + span * index / (maximumPoints - 1);
      final time = timeAtProgress(projection, target);
      final read = time == null ? null : source.valueAt(sourceName, time, interpolation);
      final value = read == null ? null : read + offset;
      if (value == null) {
        if (current.isNotEmpty) {
          segments.add(List.unmodifiable(current));
          current = [];
        }
        continue;
      }
      if (!haveExtent) {
        minimum = maximum = value;
        haveExtent = true;
      } else {
        if (value < minimum) minimum = value;
        if (value > maximum) maximum = value;
      }
      current.add((x: (target - startProgress) / span, y: value));
    }
    if (current.isNotEmpty) segments.add(List.unmodifiable(current));
    if (segments.isEmpty) return ChartSeries.empty;
    return ChartSeries(
      segments: List.unmodifiable(segments),
      minimum: minimum,
      maximum: maximum,
      unit: found.unit,
      brakingUp: resolved == (session.aliases['longitudinalAcceleration'] ?? ''),
      angular: angular,
    );
  }

  /// The overlay map's layers: the fixed ones, then each temperature either
  /// lap recorded (in name order), or one unavailable "Temperature" entry
  /// when neither recorded one, never invented.
  List<MapLayerOption> get mapLayerOptions {
    final temperatures = <String>[];
    for (final session in [a.session, b.session]) {
      for (final name in recordedTemperatureChannels(session)) {
        if (!temperatures.contains(name)) temperatures.add(name);
      }
    }
    temperatures.sort();
    final specs = [
      ..._fixedLayers,
      for (final name in temperatures)
        _LayerSpec('$temperatureLayerPrefix$name', name, name, 'sequential', '', '', true),
    ];
    final options = <MapLayerOption>[
      for (final spec in specs)
        MapLayerOption(
          id: spec.id,
          label: spec.label,
          available: spec.id == 'delta'
              ? axis.valid
              : _layerChannel(a.session, spec) != null || _layerChannel(b.session, spec) != null,
          temperature: spec.temperature,
        ),
    ];
    if (temperatures.isEmpty) {
      options.add(
        const MapLayerOption(
          id: 'temperature',
          label: 'Temperature',
          available: false,
          temperature: true,
        ),
      );
    }
    return options;
  }

  static String? _layerChannel(TelemetrySession session, _LayerSpec spec) {
    final name = spec.temperature ? spec.alias : session.aliases[spec.alias] ?? '';
    return name.isEmpty || !session.channels.containsKey(name) ? null : name;
  }

  /// Lap [slot]'s line on the overlay map coloured by layer [layerId]: a
  /// recorded channel (never inferred: no brake channel means no brake
  /// layer) or the Δ time, sampled at [mapLayerPoints] positions along the
  /// shared axis.
  ComparisonMapLayer mapLayer(String layerId, int slot) {
    if (slot < 0 || slot > 1) return ComparisonMapLayer(id: layerId, reason: 'pairNotReady');
    _LayerSpec? spec;
    for (final candidate in _fixedLayers) {
      if (candidate.id == layerId) spec = candidate;
    }
    if (spec == null && layerId.startsWith(temperatureLayerPrefix)) {
      final name = layerId.substring(temperatureLayerPrefix.length);
      spec = _LayerSpec(layerId, name, name, 'sequential', '', '', true);
    }
    if (spec == null) return ComparisonMapLayer(id: layerId, reason: 'unknownLayer');
    ComparisonMapLayer result({
      bool valid = false,
      String reason = '',
      String channel = '',
      String unit = '',
      String provenance = '',
      MapLayerTrace trace = const MapLayerTrace(),
    }) => ComparisonMapLayer(
      id: spec!.id,
      label: spec.label,
      scale: spec.scale,
      slot: slot,
      negativeLabel: spec.negativeLabel,
      positiveLabel: spec.positiveLabel,
      valid: valid,
      reason: reason,
      channel: channel,
      unit: unit,
      provenance: provenance,
      trace: trace,
    );
    if (!axis.valid || !geometry.valid) return result(reason: 'noProgressAxis');
    final session = lap(slot).session;
    final projection = trace(slot);
    final length = axis.lengthMeters;
    List<List<ProgressValue>> values;
    String channel = '', unit, provenance;
    if (spec.id == 'delta') {
      // The pair's delta at each position, drawn where the chosen lap was.
      values = [
        for (final run in computeDeltaSeries(
          trace(0),
          trace(1),
          length / mapLayerPoints,
          cancelled: cancelled,
        ))
          [for (final point in run) (progress: point.progressMeters, value: point.deltaSeconds)],
      ];
      unit = 's';
      provenance = 'calculated';
    } else {
      final name = _layerChannel(session, spec);
      if (name == null) return result(reason: 'channelMissing');
      values = channelAlongProgress(
        session,
        name,
        projection,
        length,
        mapLayerPoints,
        spec.temperature ? temperatureSummaryPolicy : const ChannelSummaryPolicy(),
      );
      channel = name;
      unit = session.channels[name]!.unit;
      provenance = name.toLowerCase().endsWith('-calc') ? 'calculated' : 'measured';
    }
    final layer = placeOnMap(session, projection, geometry, values);
    if (layer.polylines.isEmpty) {
      return result(reason: 'noSamples', channel: channel, unit: unit, provenance: provenance);
    }
    return result(valid: true, channel: channel, unit: unit, provenance: provenance, trace: layer);
  }
}
