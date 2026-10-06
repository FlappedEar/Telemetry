// Port of FlappedEar Overlays native/src/telemetry/OutingTheoreticalBest.{h,cpp}
// and the theoretical-best part of OutingTheoreticalBestResults.{h,cpp}
// (revision d4d1039, FET-32): a day's theoretical best and what is measured
// on its shared axis, and the published form the screens read.
//
// Overlays loads and verifies each recording from the project
// (`loadOutingLapDetail`); here the caller passes the sessions it already
// holds. Each corner's metrics (KAN-63: speeds, braking point, pickup, line)
// are kept in full for every lap, not only the observations Overlays keeps.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart' show TrackSegmentType, trackSegmentTypeName;

import '../geometry.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import 'braking_metrics.dart';
import 'consistency.dart';
import 'corner_speeds.dart';
import 'driving_variability.dart';
import 'exit_metrics.dart';
import 'sector_timing.dart';
import 'theoretical_best.dart';
import 'time_loss.dart';
import 'track_progress.dart';
import 'track_segment_review.dart';

/// One eligible lap of the population.
final class OutingLap {
  const OutingLap({
    required this.runId,
    required this.lapNumber,
    required this.start,
    required this.end,
    required this.reference,
  });

  final String runId;
  final int lapNumber;
  final double start;
  final double end;

  /// The lap's identity, compared with `==`.
  final Object? reference;
}

/// A run's recording and its laps (from `deriveSourceLapSession`).
final class OutingRun {
  const OutingRun(this.session, this.laps);

  final TelemetrySession session;
  final LapSession laps;
}

/// The Corner Analyzer's metrics of one corner on one lap, measured on the
/// shared axis, and the observation Overlays summarizes from them.
final class CornerLapMetrics {
  const CornerLapMetrics({
    required this.lapReference,
    required this.speeds,
    required this.braking,
    required this.exit,
    required this.observation,
  });

  final Object? lapReference;
  final CornerSpeeds speeds;
  final BrakingMetrics braking;
  final ExitMetrics exit;
  final CornerLapObservation observation;
}

/// The day's theoretical best and what is measured on its shared axis.
final class OutingTheoreticalBest {
  OutingTheoreticalBest({
    this.error = '',
    TheoreticalBestLap? best,
    this.actualBest,
    this.canonicalRunId = '',
    List<TimedLapSectors> population = const [],
    ApprovedSegmentation? approved,
    this.axisLengthMeters = 0.0,
    this.axis = const ProgressAxis(),
    List<List<ProgressSegment>> traces = const [],
    List<String> runIds = const [],
    Map<String, List<CornerLapMetrics>> cornerMetrics = const {},
  }) : best = best ?? TheoreticalBestLap(),
       approved = approved ?? ApprovedSegmentation(trackConfigurationReference: ''),
       population = List.unmodifiable(population),
       traces = List.unmodifiable(traces),
       runIds = List.unmodifiable(runIds),
       cornerMetrics = Map.unmodifiable({
         for (final entry in cornerMetrics.entries)
           entry.key: List<CornerLapMetrics>.unmodifiable(entry.value),
       });

  /// Set when the calculation failed or was cancelled.
  final String error;
  final TheoreticalBestLap best;

  /// The group's actual best lap timed on the same axis, so per-sector losses
  /// compare like with like.
  final LapSectorTimes? actualBest;
  final String canonicalRunId;

  /// Every eligible lap timed on the canonical axis, grouped by run.
  final List<TimedLapSectors> population;

  /// Each lap of [population]'s projection onto [axis], in the same order.
  final List<List<ProgressSegment>> traces;

  /// Each lap of [population]'s run, in the same order.
  final List<String> runIds;
  final ApprovedSegmentation approved;
  final double axisLengthMeters;

  /// Drawn as the track map.
  final ProgressAxis axis;

  /// Each corner segment's metrics on every lap of [population], in the same
  /// order, by segment id.
  final Map<String, List<CornerLapMetrics>> cornerMetrics;

  /// Each corner's observations, as Overlays keeps them (KAN-63).
  Map<String, List<CornerLapObservation>> get cornerObservations => {
    for (final entry in cornerMetrics.entries)
      entry.key: [for (final lap in entry.value) lap.observation],
  };
}

/// The Corner Analyzer's metrics of corner [segmentId] (from [start] to
/// [end]) on one lap, as `calculateOutingTheoreticalBest` measures them.
CornerLapMetrics measureCornerLap(
  ProgressAxis axis,
  TrackFeatures features,
  ApprovedSegmentation approved,
  String segmentId,
  double start,
  double end,
  List<ProgressSegment> trace,
  TelemetrySession session,
  double lapStart,
  double lapEnd,
  Object? lapReference,
) {
  final observation = CornerLapObservation(lapReference: lapReference);
  final speeds = computeCornerSpeeds(axis, features, approved, segmentId, trace, session);
  if (speeds.valid) {
    observation
      ..apexSpeed = speeds.apex.value
      ..minimumSpeed = speeds.minimum.value
      ..exitSpeed = speeds.exit.value
      ..speedUnit = speeds.unit;
  }
  final braking = computeBrakingMetrics(
    axis.lengthMeters,
    approved,
    segmentId,
    trace,
    session,
    lapStart,
    lapEnd,
  );
  if (braking.valid && braking.brakingPointMeters != null) {
    observation
      ..brakingPointMeters = braking.brakingPointMeters
      ..brakingProvenance = braking.provenance;
  }
  final exit = computeExitMetrics(axis.lengthMeters, approved, segmentId, trace, session, lapEnd);
  if (exit.valid && exit.pickup.progressMeters != null) {
    observation
      ..pickupMeters = exit.pickup.progressMeters
      ..pickupProvenance = exit.pickup.provenance;
  }
  // Line at the geometric apex when one exists, else mid-corner (a chain of
  // corners has several apexes).
  final middle = end >= start
      ? (start + end) / 2.0
      : (start + (end + axis.lengthMeters - start) / 2.0).remainder(axis.lengthMeters);
  final at = speeds.valid && speeds.apex.value != null ? speeds.apex.progressMeters : middle;
  final time = timeAtProgress(trace, at);
  if (time != null) {
    final latitude = session.valueAt('latitude', time);
    final longitude = session.valueAt('longitude', time);
    if (latitude != null && longitude != null) {
      observation.lineOffsetMeters = lateralOffsetMeters(
        axis,
        at,
        projectCoordinate(GeoCoordinate(latitude, longitude), axis.origin),
      );
    }
    observation.gpsAccuracyMeters = session.valueAt('accuracy', time);
  }
  // And where the corner starts and ends (FET-225). A corner starting or
  // ending at the timing gate is measured where the lap starts or ends: a
  // lap's trace begins after the gate, so no time has progress 0. A
  // boundary further than a metre off the axis is no data.
  double? offsetAt(double progress) {
    const gateTolerance = 1.0;
    if (!progress.isFinite ||
        progress < -gateTolerance ||
        progress > axis.lengthMeters + gateTolerance) {
      return null;
    }
    final time = progress <= 0.0
        ? lapStart
        : progress >= axis.lengthMeters
        ? lapEnd
        : timeAtProgress(trace, progress);
    if (time == null) return null;
    final latitude = session.valueAt('latitude', time);
    final longitude = session.valueAt('longitude', time);
    if (latitude == null || longitude == null) return null;
    return lateralOffsetMeters(
      axis,
      progress.clamp(0.0, axis.lengthMeters),
      projectCoordinate(GeoCoordinate(latitude, longitude), axis.origin),
    );
  }

  observation
    ..entryLineOffsetMeters = offsetAt(start)
    ..exitLineOffsetMeters = offsetAt(end);
  return CornerLapMetrics(
    lapReference: lapReference,
    speeds: speeds,
    braking: braking,
    exit: exit,
    observation: observation,
  );
}

/// Times every lap of [population] on one axis built from the canonical
/// run's fastest lap, against [approved] (the canonical run's approved
/// segments): sector times, the theoretical best, the actual best
/// ([actualBestReference]) on the same axis and each corner's speeds, braking,
/// pickup and line ([OutingTheoreticalBest.cornerMetrics]). A lap whose run is not in
/// [runs] contributes nothing. Never throws: failures and cancellation are
/// reported in [OutingTheoreticalBest.error].
OutingTheoreticalBest calculateOutingTheoreticalBest(
  List<OutingLap> population,
  Map<String, OutingRun> runs,
  ApprovedSegmentation approved,
  String canonicalRunId,
  Object? actualBestReference, {
  CancellationCheck? cancelled,
}) {
  try {
    // Grouped by run, in their order within each run.
    final indexed = [for (var i = 0; i < population.length; ++i) (i, population[i])]
      ..sort((a, b) {
        final byRun = a.$2.runId.compareTo(b.$2.runId);
        return byRun != 0 ? byRun : a.$1.compareTo(b.$1);
      });
    final laps = [for (final (_, lap) in indexed) lap];
    // The axis comes from the canonical run's fastest lap: the lap usually
    // reviewed, so segment bounds line up with the axis they were approved on.
    OutingLap? canonical;
    for (final lap in laps) {
      if (lap.runId != canonicalRunId) continue;
      if (canonical == null || lap.end - lap.start < canonical.end - canonical.start) {
        canonical = lap;
      }
    }
    if (canonical == null) {
      throw const _Failure('The canonical run has no eligible lap in this population.');
    }
    final axisRun = runs[canonicalRunId];
    final gate = axisRun?.laps.selectedStartGate;
    LapTrace? trace;
    for (final candidate in axisRun?.laps.lapTraces ?? const <LapTrace>[]) {
      if (candidate.lapNumber == canonical.lapNumber) {
        trace = candidate;
        break;
      }
    }
    if (gate == null || trace == null) {
      throw const _Failure('Could not build a shared track axis from the canonical run.');
    }
    final origin = geoMidpoint(gate.endpointA, gate.endpointB);
    final axis = buildProgressAxis(trace, origin, gate, cancelled: cancelled);
    if (!axis.valid) {
      throw const _Failure(
        "The shared track axis could not be built from the canonical run's GPS trace.",
      );
    }
    final features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
    final corners = <(String, double, double)>[
      for (final segment in approved.segments)
        if (segment['type'] == trackSegmentTypeName(TrackSegmentType.corner))
          (
            segment['id'] is String ? segment['id'] as String : '',
            (segment['startProgressMeters'] as num?)?.toDouble() ?? 0.0,
            (segment['endProgressMeters'] as num?)?.toDouble() ?? 0.0,
          ),
    ];
    final cornerMetrics = <String, List<CornerLapMetrics>>{};
    final times = <LapSectorTimes>[];
    final timed = <TimedLapSectors>[];
    final traces = <List<ProgressSegment>>[];
    final runIds = <String>[];
    LapSectorTimes? actualBest;
    for (final lap in laps) {
      throwIfCancelled(cancelled);
      final run = runs[lap.runId];
      if (run == null) continue; // this lap's recording is not available
      final projected = projectLapTrace(
        axis,
        run.session,
        lap.start,
        lap.end,
        cancelled: cancelled,
      );
      final result = computeLapSectorTimes(
        approved,
        axis.lengthMeters,
        projected,
        lap.start,
        lap.end,
        lap.reference,
      );
      times.add(result);
      timed.add(TimedLapSectors(result, lap.start));
      traces.add(projected);
      runIds.add(lap.runId);
      for (final (segmentId, start, end) in corners) {
        throwIfCancelled(cancelled);
        (cornerMetrics[segmentId] ??= []).add(
          measureCornerLap(
            axis,
            features,
            approved,
            segmentId,
            start,
            end,
            projected,
            run.session,
            lap.start,
            lap.end,
            lap.reference,
          ),
        );
      }
      if (actualBestReference != null && lap.reference == actualBestReference) actualBest = result;
    }
    return OutingTheoreticalBest(
      best: computeTheoreticalBest(approved, times),
      actualBest: actualBest,
      canonicalRunId: canonicalRunId,
      population: timed,
      traces: traces,
      runIds: runIds,
      approved: approved,
      axisLengthMeters: axis.lengthMeters,
      axis: axis,
      cornerMetrics: cornerMetrics,
    );
  } on OperationCancelled {
    return OutingTheoreticalBest(
      error: 'Theoretical best calculation was cancelled.',
      canonicalRunId: canonicalRunId,
    );
  } on _Failure catch (failure) {
    return OutingTheoreticalBest(error: failure.message, canonicalRunId: canonicalRunId);
  } on Exception catch (error) {
    return OutingTheoreticalBest(error: '$error', canonicalRunId: canonicalRunId);
  }
}

final class _Failure implements Exception {
  const _Failure(this.message);

  final String message;
}

/// Readable text for a theoretical-best unavailability reason.
String theoreticalBestReasonText(String reason) => switch (reason) {
  theoreticalBestNoApprovedSegmentation => 'No approved segments to measure sectors against.',
  theoreticalBestIncompleteCoverage =>
    'At least one sector has no fully covered time on any eligible lap, so no total is shown.',
  _ => reason,
};

/// A point of the track map, fitted to a unit square with north up and the
/// aspect ratio kept (x to the right, y down).
typedef MapPoint = ({double x, double y});

/// One approved segment in the published theoretical best.
final class TheoreticalBestRow {
  TheoreticalBestRow({
    required this.segmentId,
    required this.name,
    required this.type,
    required this.startProgressMeters,
    required this.endProgressMeters,
    this.seconds,
    this.sourceLapReference,
    this.unavailableReason = '',
    this.actualSeconds,
    this.lossSeconds,
    this.consistency = const ConsistencySummary(),
    this.variability,
    List<List<MapPoint>> parts = const [],
  }) : parts = List.unmodifiable(parts);

  final String segmentId;
  final String name;
  final String type;
  final double startProgressMeters;
  final double endProgressMeters;

  /// The fastest time through this segment.
  final double? seconds;

  /// The lap that recorded [seconds].
  final Object? sourceLapReference;

  /// Readable, when [seconds] is null.
  final String unavailableReason;

  /// The best lap's time through this segment.
  final double? actualSeconds;

  /// [actualSeconds] − [seconds]: what the best lap leaves here.
  final double? lossSeconds;

  /// How repeatable this segment is across the population.
  final ConsistencySummary consistency;

  /// How repeatable braking, speeds, pickup and line are, for a corner.
  final CornerVariability? variability;

  /// The segment's line on the map: one part, or two when it crosses the gate.
  final List<List<MapPoint>> parts;
}

/// The group's best lap in the published theoretical best.
final class TheoreticalBestActual {
  const TheoreticalBestActual({
    required this.reference,
    required this.lapSeconds,
    required this.coversWholeLap,
    this.sectorSumSeconds,
  });

  final Object? reference;
  final double lapSeconds;

  /// The approved segments tile the whole lap.
  final bool coversWholeLap;

  /// Its own times summed over the same segments, when every one is timed.
  final double? sectorSumSeconds;

  /// What "your best lap" shows: the lap time when the segments cover the
  /// whole lap, otherwise the sum over the same segments.
  double? get shownSeconds => coversWholeLap ? lapSeconds : sectorSumSeconds;
}

/// The theoretical best as the screens show it (Overlays'
/// `publishTheoreticalBest`).
final class TheoreticalBestSummary {
  TheoreticalBestSummary({
    required List<TheoreticalBestRow> sectors,
    required List<TheoreticalBestRow> gains,
    this.totalSeconds,
    this.actualBest,
    this.differenceSeconds,
    this.revision = '',
    this.trackConfigurationReference = '',
    List<MapPoint> outline = const [],
  }) : sectors = List.unmodifiable(sectors),
       gains = List.unmodifiable(gains),
       outline = List.unmodifiable(outline);

  /// In approved order.
  final List<TheoreticalBestRow> sectors;

  /// [sectors] by what the best lap loses there, largest first; segments
  /// without a loss last, in approved order.
  final List<TheoreticalBestRow> gains;
  final double? totalSeconds;
  final TheoreticalBestActual? actualBest;

  /// The time available: the best lap's sector sum minus [totalSeconds].
  final double? differenceSeconds;
  final String revision;
  final String trackConfigurationReference;

  /// The whole axis on the unit-square map, at most about 800 points.
  final List<MapPoint> outline;
}

/// The published form of a computed theoretical best.
TheoreticalBestSummary publishTheoreticalBest(OutingTheoreticalBest computed) {
  final actual = computed.actualBest;
  final bounds = <String, (double, double)>{};
  for (final segment in computed.approved.segments) {
    bounds[segment['id'] is String ? segment['id'] as String : ''] = (
      (segment['startProgressMeters'] as num?)?.toDouble() ?? 0.0,
      (segment['endProgressMeters'] as num?)?.toDouble() ?? 0.0,
    );
  }
  final consistency = computeSectorConsistency(computed.approved, computed.population);
  final observations = computed.cornerObservations;

  // The map: north up, fitted to a unit square with the aspect ratio kept.
  final axis = computed.axis;
  final hasMap =
      axis.valid && axis.points.length == axis.cumulative.length && axis.points.isNotEmpty;
  var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
  if (hasMap) {
    minX = maxX = axis.points.first.eastMeters;
    minY = maxY = axis.points.first.northMeters;
    for (final point in axis.points) {
      minX = math.min(minX, point.eastMeters);
      maxX = math.max(maxX, point.eastMeters);
      minY = math.min(minY, point.northMeters);
      maxY = math.max(maxY, point.northMeters);
    }
  }
  final span = [maxX - minX, maxY - minY, 1.0].reduce(math.max);
  final offsetX = (span - (maxX - minX)) / 2.0, offsetY = (span - (maxY - minY)) / 2.0;
  MapPoint normalized(MetricPoint point) => (
    x: (point.eastMeters - minX + offsetX) / span,
    y: (maxY - point.northMeters + offsetY) / span,
  );
  List<MapPoint> line(double from, double to) => [
    for (var i = 0; i < axis.points.length; ++i)
      if (axis.cumulative[i] >= from - 1e-6 && axis.cumulative[i] <= to + 1e-6)
        normalized(axis.points[i]),
  ];

  var actualSum = 0.0;
  var actualComplete = actual != null;
  final rows = <TheoreticalBestRow>[];
  for (final sector in computed.best.sectors) {
    final actualSeconds = actual?.sector(sector.segmentId)?.seconds;
    if (actualSeconds != null) {
      actualSum += actualSeconds;
    } else {
      actualComplete = false;
    }
    final (start, end) = bounds[sector.segmentId] ?? (0.0, 0.0);
    var summary = const ConsistencySummary();
    for (final candidate in consistency) {
      if (candidate.segmentId == sector.segmentId) summary = candidate.summary;
    }
    rows.add(
      TheoreticalBestRow(
        segmentId: sector.segmentId,
        name: sector.name,
        type: sector.type,
        startProgressMeters: start,
        endProgressMeters: end,
        seconds: sector.seconds,
        sourceLapReference: sector.seconds == null ? null : sector.sourceLapReference,
        unavailableReason: sector.seconds == null
            ? theoreticalBestReasonText(sector.unavailableReason)
            : '',
        actualSeconds: actualSeconds,
        lossSeconds: actualSeconds != null && sector.seconds != null
            ? actualSeconds - sector.seconds!
            : null,
        consistency: summary,
        variability: observations[sector.segmentId] == null
            ? null
            : summarizeCornerVariability(
                sector.segmentId,
                sector.name,
                observations[sector.segmentId]!,
              ),
        parts: !hasMap
            ? const []
            : end >= start
            ? [line(start, end)]
            : [line(start, axis.lengthMeters), line(0.0, end)],
      ),
    );
  }
  // Where the best lap loses time, largest first (stable).
  final order = [for (var i = 0; i < rows.length; ++i) i]
    ..sort((a, b) {
      final left = rows[a].lossSeconds ?? -1.0, right = rows[b].lossSeconds ?? -1.0;
      if (left != right) return left > right ? -1 : 1;
      return a.compareTo(b);
    });
  final total = computed.best.totalSeconds;
  final step = math.max(1, axis.points.length ~/ 800);
  return TheoreticalBestSummary(
    sectors: rows,
    gains: [for (final index in order) rows[index]],
    totalSeconds: total,
    actualBest: actual == null
        ? null
        : TheoreticalBestActual(
            reference: actual.lapReference,
            lapSeconds: actual.lapSeconds,
            coversWholeLap: actual.completePartition,
            sectorSumSeconds: actualComplete ? actualSum : null,
          ),
    differenceSeconds: actual != null && actualComplete && total != null ? actualSum - total : null,
    revision: computed.best.stamp.revision,
    trackConfigurationReference: computed.best.stamp.trackConfigurationReference,
    outline: hasMap
        ? [for (var i = 0; i < axis.points.length; i += step) normalized(axis.points[i])]
        : const [],
  );
}

/// Losses of each run's fastest lap, or with [allLaps] of every eligible lap,
/// against the actual best (Overlays' `rankOutingTimeLosses`). Unavailable
/// without a timed actual best.
TimeLossRanking rankOutingTimeLosses(
  OutingTheoreticalBest computed, {
  bool allLaps = false,
  int maximumResults = 50,
}) {
  final actual = computed.actualBest;
  if (actual == null) return TimeLossRanking(unavailableReason: timeLossNoReference);
  var start = 0.0;
  for (final lap in computed.population) {
    if (lap.times.lapReference == actual.lapReference) start = lap.startTime;
  }
  final reference = TimedLapSectors(actual, start);
  final List<TimedLapSectors> compared;
  if (allLaps) {
    compared = computed.population;
  } else {
    // Each run's fastest lap, so warm-up laps do not dominate.
    final fastest = <String, int>{};
    for (var i = 0; i < computed.population.length; ++i) {
      final lap = computed.population[i];
      final runId = computed.runIds[i];
      final current = fastest[runId];
      if (current == null || lap.times.lapSeconds < computed.population[current].times.lapSeconds) {
        fastest[runId] = i;
      }
    }
    compared = [for (final index in fastest.values) computed.population[index]];
  }
  return rankTimeLosses(
    computed.approved,
    computed.axisLengthMeters,
    compared,
    reference,
    maximumResults: maximumResults,
  );
}

/// The segments a population is timed against (Overlays'
/// `requestOutingTheoreticalBest`): approved segments are stored per run and
/// never merged, so the first run of [runIds], sorted by id, whose own
/// `trackSegments` ([storedSegments]) has segments approved for [groupId]
/// stands in for the whole population. Null when no run has any.
({String runId, ApprovedSegmentation approved})? canonicalSegmentation(
  Iterable<String> runIds,
  Object? Function(String runId) storedSegments,
  String groupId,
) {
  final order = runIds.toSet().toList()..sort();
  for (final runId in order) {
    final approved = approvedSegmentation(storedSegments(runId), groupId);
    if (approved.valid && approved.revision.isNotEmpty && approved.segments.isNotEmpty) {
      return (runId: runId, approved: approved);
    }
  }
  return null;
}
