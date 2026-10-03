// Port of the Corner Analyzer of FlappedEar Overlays (revision d4d1039,
// FET-38): comparisonSharedSegmentation, comparisonApprovedSegments,
// comparisonSegmentMetrics (with segmentSpeeds) and
// comparisonTimeLossObservations of
// native/src/app/AnalysisControllerCornerAnalyzer.cpp, and
// comparisonHeartRate of AnalysisControllerChannelSummaries.cpp, as
// qml/ComparisonSegmentPanel.qml shows them. G-G, driving states and trail
// braking are FET-39 and not part of this file.
//
// Laps A and B are measured on the comparison's shared progress axis (lap A's
// own trace), never on a second alignment. Segments are only shown when both
// laps' approved segmentation is the same revision of the same track
// configuration, or, when the comparison was opened from the theoretical
// best, against the segmentation that result used. Δ is A − B.
import 'package:fetproject/fetproject.dart' show TrackSegmentType, trackSegmentTypeName;

import '../telemetry_session.dart';
import 'braking_metrics.dart';
import 'channel_summary.dart';
import 'corner_phases.dart';
import 'corner_speeds.dart';
import 'exit_metrics.dart';
import 'lap_comparison.dart';
import 'sector_timing.dart';
import 'time_loss.dart';
import 'track_progress.dart';
import 'track_segment_review.dart';

/// How a value shown by the Corner Analyzer was obtained (Overlays'
/// MetricProvenance): read from a recorded channel, calculated (a sector
/// time, an interpolated boundary crossing), inferred from another channel,
/// or not available.
const String metricMeasured = 'measured';
const String metricCalculated = 'calculated';
const String metricInferred = 'inferred';
const String metricUnavailable = 'unavailable';

/// Why a lap has no value over a range it does not fully cover.
const String analyzerIncompleteCoverage = 'incompleteCoverage';

/// One lap's value of one Corner Analyzer row.
final class AnalyzerValue {
  const AnalyzerValue({
    this.value,
    this.provenance = metricUnavailable,
    this.unavailableReason = '',
  });

  final double? value;

  /// [metricMeasured], [metricCalculated], [metricInferred] or
  /// [metricUnavailable].
  final String provenance;

  /// Why [value] is missing; empty when it is present or no reason is known.
  final String unavailableReason;
}

/// A row's A − B, or why there is none.
final class AnalyzerDelta {
  const AnalyzerDelta({this.value, this.unavailableReason = ''});

  final double? value;
  final String unavailableReason;
}

/// One row of the Corner Analyzer: lap A, lap B and A − B.
final class AnalyzerMetric {
  const AnalyzerMetric({required this.a, required this.b, required this.delta});

  final AnalyzerValue a;
  final AnalyzerValue b;
  final AnalyzerDelta delta;
}

AnalyzerValue _value(double? value, String provenance, [String reason = '']) => AnalyzerValue(
  value: value,
  provenance: provenance,
  unavailableReason: value == null ? reason : '',
);

AnalyzerDelta _delta(double? value, [String reason = '']) =>
    AnalyzerDelta(value: value, unavailableReason: value == null ? reason : '');

String _namedProvenance(String provenance, bool hasValue) {
  if (!hasValue) return metricUnavailable;
  if (provenance == metricMeasured) return metricMeasured;
  if (provenance == metricInferred) return metricInferred;
  return metricUnavailable;
}

String _cornerSpeedProvenance(CornerSpeeds speeds, CornerSpeedValue phase) {
  if (phase.value == null) return metricUnavailable;
  return speeds.provenance == metricMeasured ? metricMeasured : metricUnavailable;
}

/// One lap of a comparison as the Corner Analyzer reads it: its recording,
/// its projection onto the shared axis and its timed bounds.
final class CornerAnalyzerLap {
  const CornerAnalyzerLap({
    required this.session,
    required this.trace,
    required this.start,
    required this.end,
    this.reference,
  });

  final TelemetrySession session;
  final List<ProgressSegment> trace;

  /// Recording time in seconds.
  final double start;
  final double end;

  /// The lap's identity in its sector times.
  final Object? reference;
}

/// Measured speed at a segment's entry and exit and its extremes inside
/// (KAN-117), for every segment type. Read only from the recorded speed
/// channel, never derived from GPS positions.
final class SegmentSpeeds {
  const SegmentSpeeds({
    this.entry,
    this.exit,
    this.maximum,
    this.minimum,
    this.unavailableReason = '',
  });

  final double? entry;
  final double? exit;
  final double? maximum;
  final double? minimum;

  /// [cornerPhaseSpeedChannelMissing], [cornerPhaseCrossesGate] or
  /// [analyzerIncompleteCoverage] when a value is missing.
  final String unavailableReason;
}

/// The speeds of one lap from [startMeters] to [endMeters] of a shared axis
/// of [axisLengthMeters], the lap projected as [trace] and timed from
/// [lapStart] to [lapEnd].
SegmentSpeeds segmentSpeeds(
  TelemetrySession session,
  List<ProgressSegment> trace,
  double axisLengthMeters,
  double lapStart,
  double lapEnd,
  double startMeters,
  double endMeters,
) {
  if (!session.channels.containsKey(session.aliases['speed'] ?? 'speed')) {
    return const SegmentSpeeds(unavailableReason: cornerPhaseSpeedChannelMissing);
  }
  if (endMeters <= startMeters) {
    return const SegmentSpeeds(unavailableReason: cornerPhaseCrossesGate);
  }
  double? timeAt(double meters) {
    if (meters <= 1e-6) return lapStart;
    if (meters >= axisLengthMeters - 1e-6) return lapEnd;
    return timeAtProgress(trace, meters);
  }

  final start = timeAt(startMeters), end = timeAt(endMeters);
  final entry = start == null ? null : session.valueAt('speed', start);
  final exit = end == null ? null : session.valueAt('speed', end);
  double? maximum, minimum;
  for (final boundary in [entry, exit]) {
    if (boundary == null) continue;
    if (maximum == null || boundary > maximum) maximum = boundary;
    if (minimum == null || boundary < minimum) minimum = boundary;
  }
  if (start != null && end != null && end > start) {
    for (final segment in session.sampledSegments('speed', start, end, 4000)) {
      for (final point in segment) {
        final value = point.value;
        if (maximum == null || value > maximum) maximum = value;
        if (minimum == null || value < minimum) minimum = value;
      }
    }
  }
  return SegmentSpeeds(
    entry: entry,
    exit: exit,
    maximum: maximum,
    minimum: minimum,
    unavailableReason: entry == null || exit == null || maximum == null
        ? analyzerIncompleteCoverage
        : '',
  );
}

/// The segments two laps are compared on, or none.
final class ComparisonSegmentation {
  const ComparisonSegmentation({this.shared, this.borrowed = false});

  /// Null when the laps' segmentations differ and none was borrowed.
  final ApprovedSegmentation? shared;

  /// The segmentation of the theoretical best was used because the laps'
  /// own differ: its boundaries are distances along another lap's axis and
  /// can shift by a few metres on these laps.
  final bool borrowed;
}

/// The segmentation laps A and B share: their own approved segmentations
/// ([approvedA], [approvedB]) when they are the same revision of the same
/// track configuration; otherwise [canonical] (the segmentation the
/// theoretical best used, given only when the comparison was opened from it)
/// when both laps belong to the group it was approved for ([groupA] and
/// [groupB] equal and not empty).
ComparisonSegmentation comparisonSharedSegmentation(
  ApprovedSegmentation approvedA,
  ApprovedSegmentation approvedB, {
  ApprovedSegmentation? canonical,
  String groupA = '',
  String groupB = '',
}) {
  if (approvedA.valid &&
      approvedB.valid &&
      approvedA.revision.isNotEmpty &&
      approvedA.revision == approvedB.revision &&
      approvedA.trackConfigurationReference == approvedB.trackConfigurationReference) {
    return ComparisonSegmentation(shared: approvedA);
  }
  if (canonical == null ||
      groupA.isEmpty ||
      groupB != groupA ||
      !canonical.valid ||
      canonical.revision.isEmpty ||
      canonical.segments.isEmpty) {
    return const ComparisonSegmentation();
  }
  // Overlays shows its note unless both laps carry the same revision.
  final sameRevision =
      approvedA.valid && approvedA.revision.isNotEmpty && approvedA.revision == approvedB.revision;
  return ComparisonSegmentation(shared: canonical, borrowed: !sameRevision);
}

/// One approved segment both laps are compared on.
final class ComparisonSegment {
  const ComparisonSegment({
    required this.id,
    required this.name,
    required this.type,
    required this.startMeters,
    required this.endMeters,
  });

  final String id;
  final String name;

  /// `corner`, `straight` or `sector`.
  final String type;
  final double startMeters;

  /// Below [startMeters] for a segment across the start/finish line.
  final double endMeters;

  bool get corner => type == trackSegmentTypeName(TrackSegmentType.corner);

  /// The segment's length on an axis of [axisLengthMeters].
  double lengthOn(double axisLengthMeters) {
    final length = endMeters - startMeters;
    return length >= 0 ? length : length + axisLengthMeters;
  }
}

double _number(Object? value) => value is num ? value.toDouble() : 0.0;
String _text(Object? value) => value is String ? value : '';

/// The segments of [shared], in approved order; none without one.
List<ComparisonSegment> comparisonApprovedSegments(ApprovedSegmentation? shared) => [
  for (final segment in shared?.segments ?? const <Map<String, Object?>>[])
    ComparisonSegment(
      id: _text(segment['id']),
      name: _text(segment['name']),
      type: _text(segment['type']),
      startMeters: _number(segment['startProgressMeters']),
      endMeters: _number(segment['endProgressMeters']),
    ),
];

/// The measured entry, top, lowest and exit speed of a segment on both laps.
final class SegmentSpeedMetrics {
  const SegmentSpeedMetrics({
    required this.unit,
    required this.entry,
    required this.maximum,
    required this.minimum,
    required this.exit,
  });

  /// Lap A's speed unit.
  final String unit;
  final AnalyzerMetric entry;
  final AnalyzerMetric maximum;
  final AnalyzerMetric minimum;
  final AnalyzerMetric exit;
}

/// A corner's entry, apex, minimum and exit speed on both laps.
final class CornerSpeedMetrics {
  const CornerSpeedMetrics({
    required this.channel,
    required this.unit,
    required this.entry,
    required this.apex,
    required this.minimum,
    required this.exit,
  });

  final String channel;
  final String unit;
  final AnalyzerMetric entry;
  final AnalyzerMetric apex;
  final AnalyzerMetric minimum;
  final AnalyzerMetric exit;
}

/// A corner's braking point (metres along the lap), braking time and peak
/// deceleration on both laps.
final class BrakingAnalyzerMetrics {
  const BrakingAnalyzerMetrics({
    required this.point,
    required this.seconds,
    required this.peakDeceleration,
  });

  final AnalyzerMetric point;
  final AnalyzerMetric seconds;
  final AnalyzerMetric peakDeceleration;
}

/// A corner's throttle pickup (metres along the lap) and exit speed on both
/// laps.
final class ExitAnalyzerMetrics {
  const ExitAnalyzerMetrics({required this.pickup, required this.exitSpeed});

  final AnalyzerMetric pickup;
  final AnalyzerMetric exitSpeed;
}

/// Everything the Corner Analyzer shows of one segment for laps A and B
/// (Overlays' comparisonSegmentMetrics), with the per-lap results it was
/// read from.
final class SegmentAnalysis {
  SegmentAnalysis({
    required this.segment,
    this.sectorTime,
    required this.speeds,
    required this.segmentSpeeds,
    this.corner,
    this.braking,
    this.exitEffects,
    this.phases,
    this.cornerSpeeds,
    this.brakingMetrics,
    this.exitMetrics,
  });

  final ComparisonSegment segment;
  String get segmentId => segment.id;
  String get type => segment.type;

  /// Both laps timed through the segment; null when either lap's timing has
  /// no such segment.
  final AnalyzerMetric? sectorTime;
  final SegmentSpeedMetrics speeds;

  /// [speeds] per lap.
  final List<SegmentSpeeds> segmentSpeeds;

  /// Corners only, each when both laps' results are valid.
  final CornerSpeedMetrics? corner;
  final BrakingAnalyzerMetrics? braking;
  final ExitAnalyzerMetrics? exitEffects;

  /// The corner's geometric entry, apex and exit on the shared axis.
  final CornerGeometryPhases? phases;

  /// Corners only: lap A's and lap B's results in full.
  final List<CornerSpeeds>? cornerSpeeds;
  final List<BrakingMetrics>? brakingMetrics;
  final List<ExitMetrics>? exitMetrics;
}

/// One lap's heart rate over a range of the shared axis.
final class HeartRateLap {
  const HeartRateLap({required this.summary, this.channel = ''});

  /// Not valid with [analyzerIncompleteCoverage] when the lap does not
  /// cover the range, [channelSummaryMissing] when it is not recorded.
  final ChannelSummary summary;

  /// The recording's heart-rate channel; empty when there is none.
  final String channel;

  bool get valid => summary.valid;
}

/// Laps A and B's heart rate over a range of the shared axis.
final class ComparisonHeartRate {
  const ComparisonHeartRate({
    this.valid = false,
    this.laps = const [],
    this.startMeters = 0.0,
    this.endMeters = 0.0,
  });

  final bool valid;
  final List<HeartRateLap> laps;
  final double startMeters;

  /// Below [startMeters] for a range across the start/finish line, which
  /// combines the lap's end and its beginning.
  final double endMeters;

  bool get crossesStartFinish => startMeters > endMeters;
  String get algorithm => channelSummaryAlgorithm;
}

/// Lap A's time losses to lap B segment by segment, or why there are none.
final class ComparisonTimeLosses {
  const ComparisonTimeLosses({this.observations, this.lapDeltaSeconds});

  final TimeLossObservations? observations;

  /// A's lap time minus B's.
  final double? lapDeltaSeconds;

  bool get valid => observations != null && observations!.valid;
}

/// The Corner Analyzer of two laps compared on one shared axis: the segments
/// they are compared on and, per segment, both laps' figures. Each segment
/// is measured once, on first use.
final class CornerAnalyzer {
  CornerAnalyzer({
    required this.axis,
    required this.a,
    required this.b,
    this.segmentation = const ComparisonSegmentation(),
  }) : segments = List.unmodifiable(comparisonApprovedSegments(segmentation.shared));

  /// Lap A and lap B of [comparison] on its shared axis.
  factory CornerAnalyzer.of(
    LapComparison comparison, [
    ComparisonSegmentation segmentation = const ComparisonSegmentation(),
  ]) {
    CornerAnalyzerLap lap(int slot) {
      final source = comparison.lap(slot);
      return CornerAnalyzerLap(
        session: source.session,
        trace: comparison.trace(slot),
        start: source.start,
        end: source.end,
        reference: slot,
      );
    }

    return CornerAnalyzer(axis: comparison.axis, a: lap(0), b: lap(1), segmentation: segmentation);
  }

  final ProgressAxis axis;
  final CornerAnalyzerLap a;
  final CornerAnalyzerLap b;
  final ComparisonSegmentation segmentation;

  /// The approved segments both laps are compared on, in approved order.
  /// Empty when the laps' segmentations do not match.
  final List<ComparisonSegment> segments;

  double get axisLengthMeters => axis.valid ? axis.lengthMeters : 0.0;

  CornerAnalyzerLap lap(int slot) => slot == 0 ? a : b;

  ComparisonSegment? segment(String id) {
    for (final segment in segments) {
      if (segment.id == id) return segment;
    }
    return null;
  }

  TrackFeatures? _features;
  List<LapSectorTimes>? _times;
  final Map<String, SegmentAnalysis?> _analyses = {};

  TrackFeatures get _trackFeatures =>
      _features ??= computeTrackFeatures(axis, segmentReviewSmoothingMeters);

  List<LapSectorTimes> get _sectorTimes => _times ??= [
    for (final lap in [a, b])
      computeLapSectorTimes(
        segmentation.shared!,
        axis.lengthMeters,
        lap.trace,
        lap.start,
        lap.end,
        lap.reference,
      ),
  ];

  /// Both laps' figures through segment [segmentId]; null for an unknown
  /// segment or without a shared axis or segmentation.
  SegmentAnalysis? analyze(String segmentId) =>
      _analyses.putIfAbsent(segmentId, () => _analyze(segmentId));

  SegmentAnalysis? _analyze(String segmentId) {
    final shared = segmentation.shared;
    if (segmentId.isEmpty || !axis.valid || shared == null) return null;
    final segment = this.segment(segmentId);
    if (segment == null || segment.type.isEmpty) return null;
    final length = axis.lengthMeters;

    // Sector time: every segment type, not just corners.
    AnalyzerMetric? sectorTime;
    final times = _sectorTimes;
    final sectorA = times[0].sector(segmentId), sectorB = times[1].sector(segmentId);
    if (sectorA != null && sectorB != null) {
      final comparison = compareSectorTimes(times[0], times[1], segmentId);
      sectorTime = AnalyzerMetric(
        a: _value(
          sectorA.seconds,
          sectorA.seconds != null ? metricCalculated : metricUnavailable,
          sectorA.unavailableReason,
        ),
        b: _value(
          sectorB.seconds,
          sectorB.seconds != null ? metricCalculated : metricUnavailable,
          sectorB.unavailableReason,
        ),
        delta: _delta(comparison.secondsDelta, comparison.unavailableReason),
      );
    }

    // Entry and exit speed and the extremes inside, every segment type.
    final speeds = [
      for (final lap in [a, b])
        segmentSpeeds(
          lap.session,
          lap.trace,
          length,
          lap.start,
          lap.end,
          segment.startMeters,
          segment.endMeters,
        ),
    ];
    AnalyzerMetric row(double? valueA, double? valueB) => AnalyzerMetric(
      a: _value(
        valueA,
        valueA != null ? metricMeasured : metricUnavailable,
        speeds[0].unavailableReason,
      ),
      b: _value(
        valueB,
        valueB != null ? metricMeasured : metricUnavailable,
        speeds[1].unavailableReason,
      ),
      delta: _delta(valueA != null && valueB != null ? valueA - valueB : null),
    );
    final speedChannel = a.session.aliases['speed'] ?? 'speed';
    final speedMetrics = SegmentSpeedMetrics(
      unit: a.session.channels[speedChannel]?.unit ?? '',
      entry: row(speeds[0].entry, speeds[1].entry),
      maximum: row(speeds[0].maximum, speeds[1].maximum),
      minimum: row(speeds[0].minimum, speeds[1].minimum),
      exit: row(speeds[0].exit, speeds[1].exit),
    );
    if (segment.type != trackSegmentTypeName(TrackSegmentType.corner)) {
      return SegmentAnalysis(
        segment: segment,
        sectorTime: sectorTime,
        speeds: speedMetrics,
        segmentSpeeds: speeds,
      );
    }

    // Corner-only metrics, as the per-lap corner metrics measure them.
    final features = _trackFeatures;
    final stored = approvedSegmentById(shared, segmentId) ?? const <String, Object?>{};
    final phases = proposeCornerGeometryPhases(
      axis,
      features,
      cornerFromSegment(axis, features, stored),
    );

    final cornerSpeeds = [
      for (final lap in [a, b])
        computeCornerSpeeds(axis, features, shared, segmentId, lap.trace, lap.session),
    ];
    CornerSpeedMetrics? corner;
    if (cornerSpeeds[0].valid && cornerSpeeds[1].valid) {
      final comparison = compareCornerSpeeds(cornerSpeeds[0], cornerSpeeds[1]);
      AnalyzerMetric phase(CornerSpeedValue valueA, CornerSpeedValue valueB, double? delta) =>
          AnalyzerMetric(
            a: _value(
              valueA.value,
              _cornerSpeedProvenance(cornerSpeeds[0], valueA),
              valueA.unavailableReason,
            ),
            b: _value(
              valueB.value,
              _cornerSpeedProvenance(cornerSpeeds[1], valueB),
              valueB.unavailableReason,
            ),
            delta: _delta(delta, comparison.unavailableReason),
          );
      final speedsA = cornerSpeeds[0], speedsB = cornerSpeeds[1];
      corner = CornerSpeedMetrics(
        channel: speedsA.channel,
        unit: speedsA.unit,
        entry: phase(speedsA.entry, speedsB.entry, comparison.entryDelta),
        apex: phase(speedsA.apex, speedsB.apex, comparison.apexDelta),
        minimum: phase(speedsA.minimum, speedsB.minimum, comparison.minimumDelta),
        exit: phase(speedsA.exit, speedsB.exit, comparison.exitDelta),
      );
    }

    final braking = [
      for (final lap in [a, b])
        computeBrakingMetrics(
          length,
          shared,
          segmentId,
          lap.trace,
          lap.session,
          lap.start,
          lap.end,
        ),
    ];
    BrakingAnalyzerMetrics? brakingMetrics;
    if (braking[0].valid && braking[1].valid) {
      final comparison = compareBrakingMetrics(braking[0], braking[1]);
      AnalyzerMetric metric(
        double? Function(BrakingMetrics) read,
        double? delta, {
        bool deceleration = false,
      }) {
        AnalyzerValue side(BrakingMetrics lap) {
          final value = read(lap);
          return _value(
            value,
            _namedProvenance(lap.provenance, value != null),
            deceleration ? lap.decelerationUnavailableReason : lap.unavailableReason,
          );
        }

        return AnalyzerMetric(
          a: side(braking[0]),
          b: side(braking[1]),
          delta: _delta(delta, comparison.unavailableReason),
        );
      }

      brakingMetrics = BrakingAnalyzerMetrics(
        point: metric((lap) => lap.brakingPointMeters, comparison.brakingPointDeltaMeters),
        seconds: metric((lap) => lap.brakingSeconds, comparison.brakingSecondsDelta),
        peakDeceleration: metric(
          (lap) => lap.peakDeceleration,
          comparison.peakDecelerationDelta,
          deceleration: true,
        ),
      );
    }

    final exits = [
      for (final lap in [a, b])
        computeExitMetrics(length, shared, segmentId, lap.trace, lap.session, lap.end),
    ];
    ExitAnalyzerMetrics? exitEffects;
    if (exits[0].valid && exits[1].valid) {
      final comparison = compareExitMetrics(exits[0], exits[1]);
      AnalyzerValue pickup(ExitMetrics lap) => _value(
        lap.pickup.progressMeters,
        _namedProvenance(lap.pickup.provenance, lap.pickup.progressMeters != null),
        lap.pickup.unavailableReason,
      );
      AnalyzerValue exitSpeed(ExitMetrics lap) => _value(
        lap.exitSpeed,
        lap.exitSpeed != null ? metricMeasured : metricUnavailable,
        lap.downstreamUnavailableReason,
      );
      exitEffects = ExitAnalyzerMetrics(
        pickup: AnalyzerMetric(
          a: pickup(exits[0]),
          b: pickup(exits[1]),
          delta: _delta(comparison.pickupDeltaMeters, comparison.pickupUnavailableReason),
        ),
        exitSpeed: AnalyzerMetric(
          a: exitSpeed(exits[0]),
          b: exitSpeed(exits[1]),
          delta: _delta(comparison.exitSpeedDelta),
        ),
      );
    }

    return SegmentAnalysis(
      segment: segment,
      sectorTime: sectorTime,
      speeds: speedMetrics,
      segmentSpeeds: speeds,
      corner: corner,
      braking: brakingMetrics,
      exitEffects: exitEffects,
      phases: phases,
      cornerSpeeds: cornerSpeeds,
      brakingMetrics: braking,
      exitMetrics: exits,
    );
  }

  /// Both laps' heart rate from [startMeters] to [endMeters] of the shared
  /// axis (clamped to it). A range whose start is after its end crosses the
  /// start/finish line: the lap's end and its beginning, combined.
  ComparisonHeartRate heartRate(double startMeters, double endMeters) {
    if (!axis.valid) return const ComparisonHeartRate();
    final length = axis.lengthMeters;
    final from = startMeters.clamp(0.0, length), to = endMeters.clamp(0.0, length);
    final ranges = from <= to ? [(from, to)] : [(from, length), (0.0, to)];
    final laps = <HeartRateLap>[];
    for (final lap in [a, b]) {
      double? timeAt(double meters) {
        if (meters <= 1e-6) return lap.start;
        if (meters >= length - 1e-6) return lap.end;
        return timeAtProgress(lap.trace, meters);
      }

      final parts = <ChannelSummary>[];
      for (final (rangeStart, rangeEnd) in ranges) {
        final t0 = timeAt(rangeStart), t1 = timeAt(rangeEnd);
        if (t0 == null || t1 == null || t1 <= t0) {
          parts.clear();
          break;
        }
        parts.add(summarizeChannel(lap.session, 'heartRate', t0, t1, heartRateSummaryPolicy));
      }
      laps.add(
        parts.isEmpty
            ? const HeartRateLap(
                summary: ChannelSummary(unavailableReason: analyzerIncompleteCoverage),
              )
            : HeartRateLap(
                summary: combineChannelSummaries(parts),
                channel: lap.session.aliases['heartRate'] ?? '',
              ),
      );
    }
    return ComparisonHeartRate(
      valid: true,
      laps: List.unmodifiable(laps),
      startMeters: from,
      endMeters: to,
    );
  }

  /// Lap A's time to lap B in every segment, in travel order.
  ComparisonTimeLosses timeLosses() {
    final shared = segmentation.shared;
    if (shared == null || !axis.valid) return const ComparisonTimeLosses();
    final times = _sectorTimes;
    return ComparisonTimeLosses(
      observations: computeTimeLossObservations(
        shared,
        axis.lengthMeters,
        times[0],
        a.start,
        times[1],
        b.start,
      ),
      lapDeltaSeconds: (a.end - a.start) - (b.end - b.start),
    );
  }
}
