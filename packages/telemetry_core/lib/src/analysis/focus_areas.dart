// Port of FlappedEar Overlays native/src/telemetry/FocusAreas.{h,cpp}
// (revision d4d1039, FET-36): a short list of areas to inspect next,
// selected from computed observations only (KAN-73). Each area states an
// observation (a measured number with its metric and sample count)
// separately from a hypothesis (what might be worth comparing). A hypothesis
// never claims a cause and never recommends a driving change as safe or
// faster: in particular a braking spread says nothing about whether earlier
// or later braking is better. Each area names the pair of laps to compare as
// its evidence.
import 'dart:math' as math;

import '../speed_units.dart';
import 'consistency.dart';
import 'driving_variability.dart';

const String focusAreasAlgorithm = 'focus-areas-v1';

// Thresholds below which an observation is not worth a focus area.
const double focusMinimumSectorGapSeconds = 0.05;
const double focusMinimumLossSeconds = 0.05;
const double focusMinimumBrakingSpreadMeters = 10.0;

/// Of the median minimum speed.
const double focusMinimumSpeedSpreadFraction = 0.05;

/// The best lap against the fastest recorded time through one sector.
final class FocusSectorGap {
  const FocusSectorGap({
    required this.segmentId,
    required this.name,
    required this.gapSeconds,
    required this.bestLap,
    required this.bestLapLabel,
    required this.sourceLap,
    required this.sourceLapLabel,
  });

  final String segmentId;
  final String name;

  /// The best lap's sector time minus the fastest recorded.
  final double gapSeconds;
  final Object? bestLap;
  final String bestLapLabel;
  final Object? sourceLap;
  final String sourceLapLabel;
}

/// One lap's loss through one window against the reference lap.
final class FocusLoss {
  const FocusLoss({
    required this.segmentId,
    required this.name,
    required this.lossSeconds,
    required this.lap,
  });

  final String segmentId;
  final String name;
  final double lossSeconds;
  final Object? lap;
}

/// One corner's observations on every lap.
final class FocusCorner {
  FocusCorner({
    required this.segmentId,
    required this.name,
    List<CornerLapObservation> observations = const [],
  }) : observations = List.unmodifiable(observations);

  final String segmentId;
  final String name;
  final List<CornerLapObservation> observations;
}

/// What the focus areas are selected from.
final class FocusInputs {
  FocusInputs({
    this.referenceLap,
    this.referenceLabel = '',
    this.comparedLapCount = 0,
    List<FocusSectorGap> gaps = const [],
    List<FocusLoss> losses = const [],
    List<FocusCorner> corners = const [],
    this.speedUnit = '',
  }) : gaps = List.unmodifiable(gaps),
       losses = List.unmodifiable(losses),
       corners = List.unmodifiable(corners);

  /// The group's best lap.
  final Object? referenceLap;
  final String referenceLabel;

  /// Laps the losses were observed on.
  final int comparedLapCount;
  final List<FocusSectorGap> gaps;
  final List<FocusLoss> losses;
  final List<FocusCorner> corners;
  final String speedUnit;
}

/// What a focus area is about.
enum FocusAreaKind {
  sectorGap('sectorGap'),
  repeatedLoss('repeatedLoss'),
  brakingSpread('brakingSpread'),
  minimumSpeedSpread('minimumSpeedSpread');

  const FocusAreaKind(this.code);

  /// The name in the day report.
  final String code;
}

/// One area to inspect next.
final class FocusArea {
  const FocusArea({
    required this.kind,
    required this.segmentId,
    required this.name,
    required this.observation,
    required this.hypothesis,
    required this.metric,
    required this.value,
    required this.unit,
    required this.sampleCount,
    required this.lap,
    required this.against,
    required this.score,
  });

  final FocusAreaKind kind;
  final String segmentId;
  final String name;

  /// Measured, with numbers.
  final String observation;

  /// What may be worth comparing; never causal.
  final String hypothesis;

  /// The measure behind [value], e.g. `sectorGapSeconds`.
  final String metric;
  final double value;
  final String unit;
  final int sampleCount;

  /// Evidence: compare [lap] against [against] through the segment.
  final Object? lap;
  final Object? against;

  /// Orders the areas of one kind.
  final double score;
}

String _seconds(double value) => value.toStringAsFixed(3);

List<FocusArea> _sectorGapAreas(FocusInputs inputs) => [
  for (final gap in inputs.gaps)
    if (gap.gapSeconds.isFinite && gap.gapSeconds >= focusMinimumSectorGapSeconds)
      FocusArea(
        kind: FocusAreaKind.sectorGap,
        segmentId: gap.segmentId,
        name: gap.name,
        metric: 'sectorGapSeconds',
        value: gap.gapSeconds,
        unit: 's',
        sampleCount: 2,
        observation:
            'Your best lap (${gap.bestLapLabel}) was ${_seconds(gap.gapSeconds)} s slower through '
            '${gap.name} than ${gap.sourceLapLabel}, the fastest recorded there.',
        hypothesis:
            'Comparing the two laps through ${gap.name} may show where the time went: where '
            'braking starts, the lowest speed, and when the throttle comes back.',
        lap: gap.bestLap,
        against: gap.sourceLap,
        score: gap.gapSeconds,
      ),
];

List<FocusArea> _repeatedLossAreas(FocusInputs inputs) {
  final areas = <FocusArea>[];
  final bySegment = <String, List<FocusLoss>>{};
  for (final loss in inputs.losses) {
    if (!loss.lossSeconds.isFinite || loss.lossSeconds < focusMinimumLossSeconds) continue;
    (bySegment[loss.segmentId] ??= []).add(loss);
  }
  for (final MapEntry(key: segmentId, value: segmentLosses) in bySegment.entries) {
    if (segmentLosses.length < minimumConsistencySamples) continue; // a pattern needs repeats
    final losses = _sortedBy(segmentLosses, (loss) => loss.lossSeconds);
    final summary = summarizeConsistency([for (final loss in losses) loss.lossSeconds]);
    if (!summary.available) continue;
    final median = summary.median!;
    // The lap closest to the median is the typical example.
    var typical = losses.first;
    for (final loss in losses) {
      if ((loss.lossSeconds - median).abs() < (typical.lossSeconds - median).abs()) typical = loss;
    }
    final name = losses.first.name;
    areas.add(
      FocusArea(
        kind: FocusAreaKind.repeatedLoss,
        segmentId: segmentId,
        name: name,
        metric: 'medianLossSeconds',
        value: median,
        unit: 's',
        sampleCount: losses.length,
        observation:
            'In ${losses.length} of ${math.max(inputs.comparedLapCount, losses.length)} compared '
            'laps you lost time through $name against ${inputs.referenceLabel} '
            '(median ${_seconds(median)} s).',
        hypothesis:
            'Because it repeats, comparing a typical lap with ${inputs.referenceLabel} through '
            '$name may show a pattern rather than a one-off.',
        lap: typical.lap,
        against: inputs.referenceLap,
        score: median * losses.length,
      ),
    );
  }
  return areas;
}

List<FocusArea> _variabilityAreas(FocusInputs inputs, {required bool braking}) {
  final areas = <FocusArea>[];
  for (final corner in inputs.corners) {
    final values = <(double, CornerLapObservation)>[];
    for (final observation in corner.observations) {
      // Only the measured braking point: an inferred one is not mixed in.
      if (braking &&
          observation.brakingPointMeters != null &&
          observation.brakingProvenance == 'measured') {
        values.add((observation.brakingPointMeters!, observation));
      }
      if (!braking && observation.minimumSpeed != null) {
        values.add((observation.minimumSpeed!, observation));
      }
    }
    // Speeds in different units are not one spread (see [sameSpeedUnit]).
    if (!braking &&
        values.any((value) => !sameSpeedUnit(value.$2.speedUnit, values.first.$2.speedUnit))) {
      continue;
    }
    final numbers = [for (final value in values) value.$1];
    final summary = summarizeConsistency(numbers);
    if (!summary.available) continue;
    final spread = summary.interquartileRange!;
    final median = summary.median!;
    if (braking
        ? spread < focusMinimumBrakingSpreadMeters
        : spread < focusMinimumSpeedSpreadFraction * median.abs()) {
      continue;
    }
    final sorted = _sortedBy(values, (value) => value.$1);
    final lap = sorted.first.$2.lapReference, against = sorted.last.$2.lapReference;
    final name = corner.name;
    final spreadText = spread.toStringAsFixed(1);
    if (braking) {
      areas.add(
        FocusArea(
          kind: FocusAreaKind.brakingSpread,
          segmentId: corner.segmentId,
          name: name,
          metric: 'brakingPointInterquartileRangeMeters',
          value: spread,
          unit: 'm',
          sampleCount: numbers.length,
          observation:
              'Where braking starts for $name varies by $spreadText m across the middle half '
              'of ${numbers.length} laps (measured from the brake signal).',
          hypothesis:
              'A more repeatable braking reference for $name may be worth checking. This does '
              'not show whether earlier or later braking is faster or safe; compare the earliest '
              'and the latest example.',
          lap: lap,
          against: against,
          score: spread,
        ),
      );
    } else {
      final unit = inputs.speedUnit.isEmpty ? '' : ' ${inputs.speedUnit}';
      areas.add(
        FocusArea(
          kind: FocusAreaKind.minimumSpeedSpread,
          segmentId: corner.segmentId,
          name: name,
          metric: 'minimumSpeedInterquartileRange',
          value: spread,
          unit: inputs.speedUnit,
          sampleCount: numbers.length,
          observation:
              'The lowest speed through $name varies by $spreadText$unit across the middle half '
              'of ${numbers.length} laps (median ${median.toStringAsFixed(1)}$unit).'
              '${inputs.speedUnit.isEmpty ? " Speeds are in the recording's own units." : ''}',
          hypothesis:
              'Comparing the slowest and the fastest example through $name may show what '
              'differs; a higher minimum speed is not by itself better.',
          lap: lap,
          against: against,
          score: spread / math.max(1e-9, median.abs()),
        ),
      );
    }
  }
  return areas;
}

// Stable: equal keys keep their order.
List<T> _sortedBy<T>(List<T> items, double Function(T item) key) {
  final order = List<int>.generate(items.length, (index) => index)
    ..sort((a, b) {
      final byKey = key(items[a]).compareTo(key(items[b]));
      return byKey != 0 ? byKey : a.compareTo(b);
    });
  return [for (final index in order) items[index]];
}

/// At most [maximum] areas, at most one per segment. The first round takes
/// the strongest area of each kind in the order sector gap, repeated loss,
/// braking spread, minimum-speed spread; remaining places are filled
/// round-robin in the same kind order, each kind by score. Deterministic for
/// equal scores (segment id).
List<FocusArea> selectFocusAreas(FocusInputs inputs, {int maximum = 3}) {
  final kinds = [
    _sectorGapAreas(inputs),
    _repeatedLossAreas(inputs),
    _variabilityAreas(inputs, braking: true),
    _variabilityAreas(inputs, braking: false),
  ];
  for (var k = 0; k < kinds.length; ++k) {
    final areas = kinds[k];
    final order = List<int>.generate(areas.length, (index) => index)
      ..sort((a, b) {
        final left = areas[a], right = areas[b];
        if (left.score != right.score) return left.score > right.score ? -1 : 1;
        final byId = left.segmentId.compareTo(right.segmentId);
        return byId != 0 ? byId : a.compareTo(b);
      });
    kinds[k] = [for (final index in order) areas[index]];
  }
  final selected = <FocusArea>[];
  final segments = <String>{};
  final next = List<int>.filled(kinds.length, 0);
  // Round one: the strongest of each kind; then fill in kind order.
  for (var round = 0; round < 2 && selected.length < maximum; ++round) {
    var progress = true;
    while (progress && selected.length < maximum) {
      progress = false;
      for (var kind = 0; kind < kinds.length && selected.length < maximum; ++kind) {
        while (next[kind] < kinds[kind].length &&
            segments.contains(kinds[kind][next[kind]].segmentId)) {
          ++next[kind];
        }
        if (next[kind] >= kinds[kind].length) continue;
        final area = kinds[kind][next[kind]];
        selected.add(area);
        segments.add(area.segmentId);
        ++next[kind];
        progress = round == 1; // round one takes one of each kind only
      }
      if (round == 0) break;
    }
  }
  return selected;
}
