// Port of FlappedEar Overlays native/src/telemetry/CornerSpeeds.{h,cpp}
// (revision d4d1039, FET-33): Corner Analyzer speeds for one approved segment
// on one lap (KAN-52): entry and exit speeds at the segment boundaries, the
// speed at the geometric apex and, separately, the lap's minimum speed inside
// the segment. The apex is never taken to be the minimum-speed point.
import 'package:fetproject/fetproject.dart' show TrackSegmentType, trackSegmentTypeName;

import '../speed_units.dart';
import '../telemetry_session.dart';
import 'corner_phases.dart';
import 'sector_timing.dart';
import 'track_progress.dart';
import 'track_segment_review.dart';

const String cornerSpeedsAlgorithm = 'corner-speeds-v1';

/// Speed samples further apart than this along the corner make every value
/// explicitly limited (`sparseSamples`), not silently precise.
const double sparseSampleSpacingMeters = 10.0;

const String cornerSpeedNotACorner = 'notACorner';
const String cornerSpeedSparseSamples = 'sparseSamples';
const String cornerSpeedMixedProvenance = 'mixedProvenance';
const String cornerSpeedDifferentSegmentOrRevision = 'differentSegmentOrRevision';

/// One speed of a corner.
final class CornerSpeedValue {
  CornerSpeedValue({
    this.value,
    this.progressMeters = 0.0,
    this.telemetryTime,
    this.unavailableReason = '',
    List<String>? limitations,
  }) : limitations = limitations ?? [];

  /// In the speed channel's unit.
  final double? value;
  double progressMeters;
  final double? telemetryTime;

  /// Set when [value] is null.
  final String unavailableReason;

  /// Present values that are less certain.
  final List<String> limitations;
}

/// The speeds of one segment on one lap.
final class CornerSpeeds {
  CornerSpeeds({
    this.segmentId = '',
    this.name = '',
    this.type = '',
    this.channel = '',
    this.unit = '',
    this.provenance = '',
    CornerSpeedValue? entry,
    CornerSpeedValue? apex,
    CornerSpeedValue? minimum,
    CornerSpeedValue? exit,
    this.lengthMeters = 0.0,
    this.coveredMeters = 0.0,
    this.meanSampleSpacingMeters = 0.0,
    this.stamp = const SegmentationResultStamp(),
    this.valid = false,
  }) : entry = entry ?? CornerSpeedValue(),
       apex = apex ?? CornerSpeedValue(),
       minimum = minimum ?? CornerSpeedValue(),
       exit = exit ?? CornerSpeedValue();

  final String segmentId;
  final String name;
  final String type;
  final String channel;
  final String unit;

  /// `measured` when read from the recorded speed channel, otherwise
  /// `unavailable`.
  final String provenance;
  final CornerSpeedValue entry;
  final CornerSpeedValue apex;
  final CornerSpeedValue minimum;
  final CornerSpeedValue exit;
  final double lengthMeters;
  final double coveredMeters;

  /// 0 when it could not be measured.
  final double meanSampleSpacingMeters;
  final SegmentationResultStamp stamp;
  final bool valid;
}

CornerSpeedValue _unavailable(double progress, String reason) =>
    CornerSpeedValue(progressMeters: progress, unavailableReason: reason);

// The recorded speed at a progress value of this lap; never bridged across a gap.
CornerSpeedValue _speedAt(
  List<ProgressSegment> lap,
  TelemetrySession session,
  String channel,
  double progress,
) {
  final time = timeAtProgress(lap, progress);
  if (time == null) return _unavailable(progress, cornerPhaseIncompleteCoverage);
  final speed = session.valueAt(channel, time);
  if (speed == null) return _unavailable(progress, cornerPhaseIncompleteCoverage);
  return CornerSpeedValue(value: speed, progressMeters: progress, telemetryTime: time);
}

/// The approved segment [segmentId] of [approved], or null.
Map<String, Object?>? approvedSegmentById(ApprovedSegmentation approved, String segmentId) {
  Map<String, Object?>? found;
  for (final segment in approved.segments) {
    if (segment['id'] == segmentId) found = segment;
  }
  return found;
}

double _number(Object? value) => value is num ? value.toDouble() : 0.0;
String _text(Object? value) => value is String ? value : '';

/// The speeds of [segmentId] on one lap. [axis] and [features] are the shared
/// progress axis the segments were approved on and its
/// [computeTrackFeatures]; [lapTrace] is the lap's projection on it.
CornerSpeeds computeCornerSpeeds(
  ProgressAxis axis,
  TrackFeatures features,
  ApprovedSegmentation approved,
  String segmentId,
  List<ProgressSegment> lapTrace,
  TelemetrySession session,
) {
  if (!axis.valid || !features.valid || !approved.valid) return CornerSpeeds();
  final segment = approvedSegmentById(approved, segmentId);
  if (segment == null || segment.isEmpty) return CornerSpeeds();

  final length = axis.lengthMeters;
  final start = _number(segment['startProgressMeters']);
  final end = _number(segment['endProgressMeters']);
  final name = _text(segment['name']);
  final type = _text(segment['type']);
  final stamp = segmentationResultStamp(approved, cornerSpeedsAlgorithm);
  final segmentLength = end >= start ? end - start : end + length - start;
  CornerSpeeds make({
    String channel = '',
    String unit = '',
    required String provenance,
    required CornerSpeedValue entry,
    required CornerSpeedValue apex,
    required CornerSpeedValue minimum,
    required CornerSpeedValue exit,
    double coveredMeters = 0.0,
    double meanSampleSpacingMeters = 0.0,
  }) => CornerSpeeds(
    segmentId: segmentId,
    name: name,
    type: type,
    channel: channel,
    unit: unit,
    provenance: provenance,
    entry: entry,
    apex: apex,
    minimum: minimum,
    exit: exit,
    lengthMeters: segmentLength,
    coveredMeters: coveredMeters,
    meanSampleSpacingMeters: meanSampleSpacingMeters,
    stamp: stamp,
    valid: true,
  );

  final channel = session.aliases['speed'] ?? '';
  final speedChannel = session.channels[channel];
  if (channel.isEmpty || speedChannel == null) {
    return make(
      provenance: 'unavailable',
      entry: _unavailable(start, cornerPhaseSpeedChannelMissing),
      apex: _unavailable(0.0, cornerPhaseSpeedChannelMissing),
      minimum: _unavailable(0.0, cornerPhaseSpeedChannelMissing),
      exit: _unavailable(end, cornerPhaseSpeedChannelMissing),
    );
  }

  if (end < start) {
    // The corner's two halves lie at opposite ends of a gate-to-gate lap.
    return make(
      channel: channel,
      unit: effectiveChannelUnit(session, speedChannel.name),
      provenance: 'measured',
      coveredMeters:
          projectedCoverageMeters(lapTrace, start, length, length) +
          projectedCoverageMeters(lapTrace, 0.0, end, length),
      entry: _unavailable(start, cornerPhaseCrossesGate),
      apex: _unavailable(0.0, cornerPhaseCrossesGate),
      minimum: _unavailable(0.0, cornerPhaseCrossesGate),
      exit: _unavailable(end, cornerPhaseCrossesGate),
    );
  }
  final covered = projectedCoverageMeters(lapTrace, start, end, length);
  final entry = _speedAt(lapTrace, session, channel, start);
  final exit = _speedAt(lapTrace, session, channel, end);

  final corner = cornerFromSegment(axis, features, segment);
  final CornerSpeedValue apex;
  if (type != trackSegmentTypeName(TrackSegmentType.corner)) {
    apex = _unavailable(0.0, cornerSpeedNotACorner);
  } else {
    final phases = proposeCornerGeometryPhases(axis, features, corner);
    if (!phases.valid) {
      apex = _unavailable(0.0, cornerPhaseInvalidInput);
    } else if (!phases.apex.resolved) {
      apex = _unavailable(0.0, phases.apex.unresolvedReason);
    } else {
      apex = _speedAt(lapTrace, session, channel, phases.apex.progressMeters)
        ..limitations.addAll(phases.apex.uncertaintyReasons);
    }
  }

  final located = locateMinimumSpeed(axis, corner, lapTrace, session, 1.0);
  final minimum = located.resolved
      ? CornerSpeedValue(
          value: _number(located.evidence['minimumValue']),
          progressMeters: located.progressMeters,
          telemetryTime: _number(located.evidence['telemetryTime']),
          limitations: [...located.uncertaintyReasons],
        )
      : _unavailable(0.0, located.unresolvedReason);

  // Sample density of the recorded channel between the boundary crossings.
  var spacing = 0.0;
  final entryTime = entry.telemetryTime, exitTime = exit.telemetryTime;
  if (entryTime != null && exitTime != null && exitTime > entryTime) {
    final times = speedChannel.timestamps;
    final samples = upperBound(times, exitTime) - lowerBound(times, entryTime);
    spacing = samples >= 2 ? segmentLength / (samples - 1) : segmentLength;
    if (spacing > sparseSampleSpacingMeters) {
      for (final value in [entry, apex, minimum, exit]) {
        if (value.value != null) value.limitations.add(cornerSpeedSparseSamples);
      }
    }
  }
  return make(
    channel: channel,
    unit: effectiveChannelUnit(session, speedChannel.name),
    provenance: 'measured',
    coveredMeters: covered,
    entry: entry,
    apex: apex,
    minimum: minimum,
    exit: exit,
    meanSampleSpacingMeters: spacing,
  );
}

/// A minus B for the same segment and approved revision (KAN-55). Values read
/// from different channels, units or provenance are never compared.
final class CornerSpeedsComparison {
  const CornerSpeedsComparison({
    this.entryDelta,
    this.apexDelta,
    this.minimumDelta,
    this.exitDelta,
    this.unavailableReason = '',
    this.valid = false,
  });

  final double? entryDelta;
  final double? apexDelta;
  final double? minimumDelta;
  final double? exitDelta;
  final String unavailableReason;
  final bool valid;
}

double? _delta(double? x, double? y) => x != null && y != null ? x - y : null;

/// [a] minus [b].
CornerSpeedsComparison compareCornerSpeeds(CornerSpeeds a, CornerSpeeds b) {
  if (!a.valid ||
      !b.valid ||
      a.segmentId != b.segmentId ||
      a.stamp.revision != b.stamp.revision ||
      a.stamp.trackConfigurationReference != b.stamp.trackConfigurationReference) {
    return const CornerSpeedsComparison(unavailableReason: cornerSpeedDifferentSegmentOrRevision);
  }
  // Speeds in different units are measured differently (see [sameSpeedUnit]).
  if (a.provenance != b.provenance || a.channel != b.channel || !sameSpeedUnit(a.unit, b.unit)) {
    return const CornerSpeedsComparison(unavailableReason: cornerSpeedMixedProvenance);
  }
  return CornerSpeedsComparison(
    entryDelta: _delta(a.entry.value, b.entry.value),
    apexDelta: _delta(a.apex.value, b.apex.value),
    minimumDelta: _delta(a.minimum.value, b.minimum.value),
    exitDelta: _delta(a.exit.value, b.exit.value),
    valid: true,
  );
}
