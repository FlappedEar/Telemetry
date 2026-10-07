import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/label_value_row.dart';
import '../units.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText;

/// Why a corner figure is missing, in a short plain phrase (lower case, to
/// follow a colon or start a sentence). Every reason the corner analyses can
/// give is mapped; an unknown one reads "not available", never its
/// identifier.
String cornerReasonText(AppLocalizations l10n, String reason) =>
    switch (reason) {
      '' => l10n.cornerDetailsReasonNotMeasured,
      // Braking.
      brakingNoneDetected => l10n.cornerDetailsReasonNoBraking,
      brakingNoChannel => l10n.cornerDetailsReasonNoBrakeOrDeceleration,
      brakingInferenceDisabled => l10n.cornerDetailsReasonNoBrakeChannel,
      brakingDecelerationChannelMissing =>
        l10n.cornerDetailsReasonNoDecelerationChannel,
      brakingApproachClipped => l10n.cornerDetailsReasonApproachClipped,
      brakingApproachClippedAtCorner =>
        l10n.cornerDetailsReasonApproachInPreviousCorner,
      brakingAlreadyActive => l10n.cornerDetailsReasonAlreadyBraking,
      brakingInterruptedByGap => l10n.cornerDetailsReasonBrakingGap,
      brakingNoSamples => l10n.cornerDetailsReasonNoSamplesHere,
      brakingBrakeChannelNotUsed => l10n.cornerDetailsReasonBrakeChannelNotUsed,
      // Throttle pickup and exit.
      exitNoChannel => l10n.cornerDetailsReasonNoThrottleOrAcceleration,
      exitNoLift => l10n.cornerDetailsReasonNoLift,
      exitNoPickup => l10n.cornerDetailsReasonNoPickup,
      exitFollowsGap => l10n.cornerDetailsReasonAfterGap,
      exitTruncated => l10n.cornerDetailsReasonCutAtLapEnd,
      // Shared by several analyses.
      analyzerIncompleteCoverage ||
      cornerPhaseTimesNotTimed => l10n.cornerDetailsReasonNotCovered,
      cornerPhaseCrossesGate => l10n.cornerDetailsReasonCrossesGate,
      exitUnitMismatch => l10n.cornerDetailsReasonUnitNotSupported,
      exitUnitUndeclared => l10n.cornerDetailsReasonUnitNotRecorded,
      exitScaleUnknown => l10n.cornerDetailsReasonScaleUnknown,
      exitScaleInferred => l10n.cornerDetailsReasonScaleInferred,
      cornerPhaseSpeedChannelMissing => l10n.cornerDetailsReasonNoSpeedChannel,
      cornerSpeedMixedProvenance => l10n.cornerDetailsReasonMixedProvenance,
      cornerSpeedDifferentSegmentOrRevision =>
        l10n.cornerDetailsReasonSegmentsDiffer,
      // Corner phases and speeds.
      cornerPhaseMultipleApexes => l10n.cornerDetailsReasonDoubleApex,
      cornerPhaseFlatSpeed => l10n.cornerDetailsReasonFlatSpeed,
      cornerPhaseInsufficientGeometry =>
        l10n.cornerDetailsReasonUnclearGeometry,
      cornerPhaseInvalidInput => l10n.cornerDetailsReasonInvalidInput,
      cornerPhaseBroadPeak => l10n.cornerDetailsReasonBroadApex,
      cornerPhaseAtCornerBoundary => l10n.cornerDetailsReasonAtBoundary,
      cornerSpeedNotACorner => l10n.cornerDetailsReasonNotACorner,
      cornerSpeedSparseSamples => l10n.cornerDetailsReasonSparseSamples,
      // Sector times and summaries.
      sectorTimeSegmentNotFound => l10n.cornerDetailsReasonSegmentNotFound,
      channelSummaryMissing => l10n.cornerDetailsReasonNotRecorded,
      channelSummaryNoSamples => l10n.cornerDetailsReasonNoValidSamples,
      timeLossNoReference => l10n.cornerDetailsReasonNoReference,
      timeLossUntimed => l10n.cornerDetailsReasonNotTimed,
      theoreticalBestNoApprovedSegmentation =>
        l10n.cornerDetailsReasonNoApprovedSegments,
      drivingStateUnknownReason => l10n.cornerDetailsReasonDrivingStateUnknown,
      // Corner classes.
      cornerClassTooFewLaps => l10n.cornerClassReasonTooFewLaps,
      cornerClassSpeedUnitUnknown => l10n.cornerClassReasonSpeedUnit,
      cornerClassTooFewLapsWithoutBraking =>
        l10n.cornerClassReasonTooFewLapsWithoutBraking,
      _ => l10n.cornerDetailsReasonNotAvailable,
    };

/// Why a corner is not split, or a lap not timed through its parts.
String cornerPhaseReasonText(AppLocalizations l10n, String reason) =>
    reason == cornerPhaseMultipleApexes
    ? l10n.cornerPhasesMoreThanOneTightPart
    : cornerReasonText(l10n, reason);

double _hundredths(double value) => (value * 100).round() / 100;

String _seconds(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(2)}\u00a0s';

String _speed(double? value) => value == null ? '—' : value.toStringAsFixed(1);

String _meters(double? value) => value == null
    ? '—'
    : '${value < 0 ? '−' : ''}${value.abs().round()}\u00a0m';

// A braking point as metres before the corner's start; negative is inside.
String _beforeEntry(AppLocalizations l10n, double value) => value.round() >= 0
    ? l10n.cornerBeforeEntry(value.round())
    : l10n.cornerIntoCorner(-value.round());

// [_position] in the app's language.
String _positionText(AppLocalizations l10n, double delta) {
  if (!delta.isFinite) return '—';
  final metres = delta.abs().round();
  if (metres == 0) return l10n.cornerSamePosition;
  return delta > 0 ? l10n.cornerLater(metres) : l10n.cornerEarlier(metres);
}

/// Lap A (this lap) and lap B (the best lap): A is amber like "you" in the
/// theme, B is the blue reference.
const Color lapAColor = Color(0xFFFCB203), lapBColor = Color(0xFF3D8BFF);

String _signed(double? value, int digits, [String unit = '']) {
  if (value == null || !value.isFinite) return '—';
  final text = value.abs().toStringAsFixed(digits);
  if (double.parse(text) == 0) return '±$text$unit';
  return '${value > 0 ? '+' : '−'}$text$unit';
}

// A position delta (A minus B along the lap) in words.
String _position(AppLocalizations l10n, double? delta) =>
    delta == null ? '—' : _positionText(l10n, delta);

/// A corner's figures on one lap: entry, minimum and exit speed, the braking
/// point and braking, and the throttle pickup, against the group's best lap
/// (as Overlays' Corner Analyzer compares two laps) and the best of every
/// lap of the group. A figure measured differently on the two laps is never
/// compared.
class CornerDetails extends StatelessWidget {
  const CornerDetails({
    super.key,
    required this.corner,
    required this.comparison,
  });

  final DayCorner corner;
  final DayCornerComparison comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final own = comparison.metrics;
    // The best lap's speeds are shown beside this lap's only in its unit.
    final bestMetrics = comparison.bestLapMetrics;
    final bestSpeeds =
        bestMetrics != null &&
            sameSpeedUnit(bestMetrics.speeds.unit, own.speeds.unit)
        ? bestMetrics.speeds
        : null;
    final best = bestMetrics;
    final isBest = comparison.bestLap?.reference == comparison.lap.reference;
    final unit = speedUnitOf(context, own.speeds.unit).trim();
    final speedUnit = unit.isEmpty ? '' : ' ($unit)';
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final strong = numbers?.copyWith(fontWeight: FontWeight.w600);

    Widget row(
      String label,
      String value,
      String bestValue,
      String delta, {
      String? note,
      Key? key,
    }) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              SizedBox(
                width: 64,
                child: Text(value, style: strong, textAlign: TextAlign.end),
              ),
              if (!isBest) ...[
                SizedBox(
                  width: 64,
                  child: Text(
                    bestValue,
                    style: numbers,
                    textAlign: TextAlign.end,
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(delta, style: numbers, textAlign: TextAlign.end),
                ),
              ],
            ],
          ),
          if (note != null && note.isNotEmpty)
            Text(note, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    final braking = own.braking;
    final bestBraking = best?.braking;
    final pickup = own.exit.pickup;
    final bestPickup = best?.exit.pickup;
    double? afterEntry(ThrottlePickup? pickup) => pickup?.progressMeters == null
        ? null
        : pickup!.progressMeters! - corner.startProgressMeters;

    String brakingNote() {
      if (braking.brakingPointMeters == null) {
        return cornerReasonText(l10n, braking.unavailableReason);
      }
      final how = braking.provenance != 'inferred'
          ? l10n.cornerDetailsFromBrakeChannel
          : braking.limitations.contains(brakingBrakeChannelNotUsed)
          ? l10n.cornerDetailsFromDecelerationBrakeUnused
          : braking.limitations.contains(brakingScaleUnknown)
          ? l10n.cornerDetailsFromDecelerationBrakeScaleUnknown
          : l10n.cornerDetailsFromDeceleration;
      if (best != null &&
          bestBraking?.brakingPointMeters != null &&
          comparison.braking.unavailableReason == 'mixedProvenance') {
        return l10n.cornerDetailsBestMeasuredDifferently(how);
      }
      return how;
    }

    String pickupNote() {
      if (pickup.progressMeters == null) {
        return cornerReasonText(l10n, pickup.unavailableReason);
      }
      final how = pickup.provenance == 'inferred'
          ? l10n.cornerDetailsFromAcceleration
          : l10n.cornerDetailsFromThrottleChannel;
      if (comparison.exit.pickupUnavailableReason == 'mixedProvenance') {
        return l10n.cornerDetailsBestMeasuredDifferently(how);
      }
      return how;
    }

    String speedNote() {
      if (comparison.speeds.unavailableReason == 'mixedProvenance') {
        return l10n.cornerDetailsBestSpeedDifferent;
      }
      if (own.speeds.minimum.value == null) {
        return l10n.cornerDetailsMinimumMissing(
          cornerReasonText(l10n, own.speeds.minimum.unavailableReason),
        );
      }
      return '';
    }

    // The English label names the row's key.
    final group = <(String, String, DayCornerValue?, String Function(double))>[
      (
        'Highest minimum speed',
        l10n.cornerDetailsHighestMinimumSpeed,
        comparison.highestMinimumSpeed,
        _speed,
      ),
      (
        'Highest exit speed',
        l10n.cornerDetailsHighestExitSpeed,
        comparison.highestExitSpeed,
        _speed,
      ),
      (
        'Latest braking point',
        l10n.cornerDetailsLatestBrakingPoint,
        comparison.latestBrakingPoint,
        (v) => _beforeEntry(l10n, v),
      ),
      (
        'Earliest throttle pickup',
        l10n.cornerDetailsEarliestPickup,
        comparison.earliestPickup,
        (v) => l10n.cornerDetailsMetresIn(v.round()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.tbSegmentName(corner.name),
          style: theme.textTheme.titleLarge,
        ),
        Text(
          isBest
              ? l10n.cornerDetailsIsBestLap(l10n.lap(comparison.lap))
              : l10n.cornerDetailsAgainstBestLap(
                  l10n.lap(comparison.lap),
                  switch (comparison.bestLap) {
                    final best? => l10n.lap(best),
                    null => l10n.cornerDetailsBestLapUnavailable,
                  },
                ),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (!isBest)
          DefaultTextStyle.merge(
            style: theme.textTheme.labelMedium,
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                for (final (label, colour) in [
                  (l10n.cornerDetailsThisLap, lapAColor),
                  (l10n.cornerDetailsBestLap, lapBColor),
                ])
                  SizedBox(
                    width: 64,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colour,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(label),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(
                  width: 92,
                  child: Text('Δ', textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
        row(
          l10n.cornerDetailsEntrySpeed(speedUnit),
          _speed(own.speeds.entry.value),
          _speed(bestSpeeds?.entry.value),
          _signed(comparison.speeds.entryDelta, 1),
          key: const ValueKey('cornerEntrySpeed'),
        ),
        row(
          l10n.cornerDetailsMinimumSpeed(speedUnit),
          _speed(own.speeds.minimum.value),
          _speed(bestSpeeds?.minimum.value),
          _signed(comparison.speeds.minimumDelta, 1),
          key: const ValueKey('cornerMinimumSpeed'),
        ),
        row(
          l10n.cornerDetailsExitSpeed(speedUnit),
          _speed(own.speeds.exit.value),
          _speed(bestSpeeds?.exit.value),
          _signed(comparison.speeds.exitDelta, 1),
          note: speedNote(),
          key: const ValueKey('cornerExitSpeed'),
        ),
        const Divider(),
        row(
          l10n.cornerDetailsBrakingPoint,
          _meters(braking.distanceBeforeEntryMeters),
          _meters(bestBraking?.distanceBeforeEntryMeters),
          _position(l10n, comparison.braking.brakingPointDeltaMeters),
          note: brakingNote(),
          key: const ValueKey('cornerBrakingPoint'),
        ),
        if (braking.brakingSeconds != null)
          row(
            l10n.cornerDetailsBrakingTime,
            '${braking.brakingSeconds!.toStringAsFixed(2)}\u00a0s',
            bestBraking?.brakingSeconds == null
                ? '—'
                : '${bestBraking!.brakingSeconds!.toStringAsFixed(2)}\u00a0s',
            _signed(comparison.braking.brakingSecondsDelta, 2, '\u00a0s'),
            key: const ValueKey('cornerBrakingTime'),
          ),
        if (braking.peakDeceleration != null)
          row(
            l10n.cornerDetailsPeakDeceleration(
              braking.decelerationUnit.isEmpty
                  ? ''
                  : ' (${braking.decelerationUnit})',
            ),
            braking.peakDeceleration!.toStringAsFixed(2),
            bestBraking?.peakDeceleration?.toStringAsFixed(2) ?? '—',
            _signed(comparison.braking.peakDecelerationDelta, 2),
            key: const ValueKey('cornerPeakDeceleration'),
          ),
        const Divider(),
        row(
          l10n.cornerDetailsPickup,
          _meters(afterEntry(pickup)),
          _meters(afterEntry(bestPickup)),
          _position(l10n, comparison.exit.pickupDeltaMeters),
          note: pickupNote(),
          key: const ValueKey('cornerPickup'),
        ),
        const Divider(),
        // Where the corner's time came from (FET-221): the same metres on
        // both laps, split by the track's shape.
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.cornerPhasesTitle,
            key: const ValueKey('cornerPhasesTitle'),
            style: theme.textTheme.titleSmall,
          ),
        ),
        if (comparison.phases.valid) ...[
          for (final (key, label, own, best, delta) in [
            (
              'cornerPhaseEntry',
              l10n.cornerPhaseEntry,
              comparison.phases.entry,
              comparison.bestLapPhases.entry,
              comparison.phaseDeltas?.entry,
            ),
            (
              'cornerPhaseMiddle',
              l10n.cornerPhaseMiddle,
              comparison.phases.mid,
              comparison.bestLapPhases.mid,
              comparison.phaseDeltas?.mid,
            ),
            (
              'cornerPhaseExit',
              l10n.cornerPhaseExit,
              comparison.phases.exit,
              comparison.bestLapPhases.exit,
              comparison.phaseDeltas?.exit,
            ),
          ])
            row(
              label,
              _seconds(own),
              _seconds(best),
              // From the values as shown, so the columns agree.
              _signed(
                delta == null ? null : _hundredths(own!) - _hundredths(best!),
                2,
                '\u00a0s',
              ),
              key: ValueKey(key),
            ),
          if (comparison.bestLap != null && !comparison.bestLapPhases.valid)
            Text(
              l10n.cornerPhasesBestNotTimed(
                cornerPhaseReasonText(
                  l10n,
                  comparison.bestLapPhases.unavailableReason,
                ),
              ),
              key: const ValueKey('cornerPhasesBestReason'),
              style: theme.textTheme.bodySmall,
            ),
          Text(
            l10n.cornerPhasesNote,
            key: const ValueKey('cornerPhasesNote'),
            style: theme.textTheme.bodySmall,
          ),
        ] else
          Padding(
            key: const ValueKey('cornerPhasesReason'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              l10n.cornerPhasesUnavailable(
                cornerPhaseReasonText(
                  l10n,
                  comparison.phases.unavailableReason,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          l10n.cornerDetailsBestOfLaps(corner.laps.length),
          style: theme.textTheme.titleSmall,
        ),
        for (final (label, text, value, format) in group)
          Padding(
            key: ValueKey('cornerBest $label'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: LabelValueRow(
              crossAxisAlignment: CrossAxisAlignment.start,
              label: Text(text),
              // Wraps under large text instead of running off the sheet.
              value: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value == null ? '—' : format(value.value),
                    textAlign: TextAlign.end,
                    style: strong,
                  ),
                  if (value != null)
                    Text(
                      l10n.lap(value.lap),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(l10n.cornerDetailsExplanation, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        CornerClassSection(classification: corner.classification),
        const SizedBox(height: 12),
        BrakingTechniqueSection(
          technique: corner.brakingTechnique,
          lap: comparison.lap.reference,
        ),
      ],
    );
  }
}

/// [shape] in the app's language.
String cornerShapeText(AppLocalizations l10n, CornerShape shape) =>
    switch (shape) {
      CornerShape.singleApex => l10n.cornerShapeSingleApex,
      CornerShape.lateApex => l10n.cornerShapeLateApex,
      CornerShape.decreasingRadius => l10n.cornerShapeDecreasingRadius,
      CornerShape.increasingRadius => l10n.cornerShapeIncreasingRadius,
      CornerShape.doubleApex => l10n.cornerShapeDoubleApex,
      CornerShape.complex => l10n.cornerShapeComplex,
    };

/// [driving]'s approach in the app's language (braking whose heaviness is
/// not known says so), or null when it is not known.
String? cornerApproachText(AppLocalizations l10n, CornerDrivingClass driving) =>
    switch (driving.approach) {
      null => null,
      CornerApproach.heavyBraking => l10n.cornerApproachHeavyBraking,
      CornerApproach.braking =>
        driving.heavyUnknown
            ? l10n.cornerApproachBrakingHeavyUnknown
            : l10n.cornerApproachBraking,
      CornerApproach.lift => l10n.cornerApproachLift,
      CornerApproach.flat => l10n.cornerApproachFlat,
    };

/// [band] in the app's language.
String cornerSpeedBandText(AppLocalizations l10n, CornerSpeedBand band) =>
    switch (band) {
      CornerSpeedBand.slow => l10n.cornerSpeedSlow,
      CornerSpeedBand.medium => l10n.cornerSpeedMedium,
      CornerSpeedBand.fast => l10n.cornerSpeedFast,
    };

/// The corner's classes that are known, on one line ("Heavy braking · Slow
/// corner · Decreasing radius"); null when none is.
String? cornerClassSummary(
  AppLocalizations l10n,
  CornerClassification classification,
) {
  final parts = [
    ?cornerApproachText(l10n, classification.driving),
    if (classification.driving.speedBand case final band?)
      cornerSpeedBandText(l10n, band),
    if (classification.shape.shape case final shape?)
      cornerShapeText(l10n, shape),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// What kind of corner it is (FET-220): its shape from the track, and its
/// braking and speed from the day's laps, each with what it was read from,
/// or why it is not known.
class CornerClassSection extends StatelessWidget {
  const CornerClassSection({super.key, required this.classification});

  final CornerClassification classification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final shape = classification.shape;
    final driving = classification.driving;
    // Unlabelled speeds are read as km/h, and say so.
    final label = driving.speedUnit == null
        ? ''
        : speedUnitOf(context, driving.speedUnit!).trim();
    final unit = label.isEmpty && driving.speedUnit != null
        ? l10n.cornerClassAssumedKmh
        : label;
    // A typical speed in the laps' unit, with the unit when one is known.
    String speed(double? metresPerSecond) {
      final value = switch (driving.inSpeedUnit(metresPerSecond)) {
        final value? => fixed(value, 0),
        null => null,
      };
      if (value == null) return '';
      return unit.isEmpty ? value : '$value\u00a0$unit';
    }

    final how = driving.brakingMethod == brakingMethodMeasured
        ? l10n.cornerClassFromBrakePedal
        : l10n.cornerClassFromDeceleration;

    Widget item(String key, String label, String? value, String note) =>
        Padding(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              if (value != null)
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (note.isNotEmpty) Text(note, style: theme.textTheme.bodySmall),
            ],
          ),
        );

    String unavailable(String reason) =>
        l10n.cornerClassUnavailable(cornerReasonText(l10n, reason));

    final shapeNote = switch (shape.shape) {
      null => unavailable(shape.unavailableReason),
      CornerShape.singleApex => l10n.cornerShapeNoteSingle,
      CornerShape.lateApex => l10n.cornerShapeNoteLate,
      CornerShape.decreasingRadius =>
        shape.radiusRatio == null
            ? ''
            : l10n.cornerShapeNoteDecreasing(fixed(shape.radiusRatio!, 1)),
      CornerShape.increasingRadius =>
        shape.radiusRatio == null || !(shape.radiusRatio! > 0)
            ? ''
            : l10n.cornerShapeNoteIncreasing(fixed(1 / shape.radiusRatio!, 1)),
      CornerShape.doubleApex => l10n.cornerShapeNoteDouble,
      CornerShape.complex =>
        shape.changesDirection
            ? l10n.cornerShapeNoteDirection
            : l10n.cornerShapeNoteComplex(shape.tightParts),
    };
    final notBraking = driving.lapsMeasured - driving.brakingLaps;
    final approachNote = switch (driving.approach) {
      null => unavailable(driving.approachUnavailableReason),
      CornerApproach.heavyBraking || CornerApproach.braking =>
        driving.heavyUnknownReason.isNotEmpty
            ? l10n.cornerApproachNoteNoShedReason(
                how,
                driving.brakingLaps,
                driving.lapsMeasured,
                cornerReasonText(l10n, driving.heavyUnknownReason),
              )
            : speed(driving.typicalSpeedShedMetresPerSecond).isEmpty
            ? l10n.cornerApproachNoteNoShed(
                how,
                driving.brakingLaps,
                driving.lapsMeasured,
              )
            : l10n.cornerApproachNoteShed(
                speed(driving.typicalSpeedShedMetresPerSecond),
                how,
                driving.brakingLaps,
                driving.lapsMeasured,
              ),
      CornerApproach.lift || CornerApproach.flat =>
        speed(driving.typicalSpeedLossMetresPerSecond).isEmpty
            ? l10n.cornerApproachNoteNoBrakingNoSpeed(
                how,
                notBraking,
                driving.lapsMeasured,
              )
            : l10n.cornerApproachNoteNoBraking(
                speed(driving.typicalSpeedLossMetresPerSecond),
                how,
                notBraking,
                driving.lapsMeasured,
              ),
    };
    final speedNote = [
      driving.speedBand == null
          ? unavailable(driving.speedBandUnavailableReason)
          : l10n.cornerSpeedNote(
              speed(driving.typicalMinimumSpeedMetresPerSecond),
              driving.speedLaps,
            ),
      if (driving.otherUnitLaps > 0)
        l10n.cornerClassOtherUnits(driving.otherUnitLaps),
    ].join(' ');

    return Column(
      key: const ValueKey('cornerClass'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.cornerClassTitle,
          key: const ValueKey('cornerClassTitle'),
          style: theme.textTheme.titleSmall,
        ),
        item(
          'cornerClassApproach',
          l10n.cornerClassApproach,
          cornerApproachText(l10n, driving),
          approachNote,
        ),
        item(
          'cornerClassSpeed',
          l10n.cornerClassSpeed,
          switch (driving.speedBand) {
            final band? => cornerSpeedBandText(l10n, band),
            null => null,
          },
          speedNote,
        ),
        item('cornerClassShape', l10n.cornerClassShape, switch (shape.shape) {
          final value? => cornerShapeText(l10n, value),
          null => null,
        }, shapeNote),
        Text(l10n.cornerClassNote, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _rate(double? hz) => hz == null ? '—' : fixed(hz, 1);

/// Why a braking technique figure is not known, in a short plain phrase;
/// a channel too slow says its rate ([rate]). Reasons it shares with the
/// other corner analyses read as they do.
String brakingTechniqueReasonText(
  AppLocalizations l10n,
  String reason, {
  double? rate,
}) => switch (reason) {
  brakingTechniqueNoDeceleration => l10n.brakingTechniqueReasonNoDeceleration,
  brakingTechniqueDecelerationTooSlow => l10n.brakingTechniqueReasonTooSlow(
    _rate(rate),
  ),
  brakingTechniqueSpeedUnitUnknown => l10n.cornerClassReasonSpeedUnit,
  brakingTechniqueNotCovered => l10n.cornerDetailsReasonNotCovered,
  brakingTechniqueNoBraking => l10n.brakingTechniqueReasonNoBraking,
  brakingTechniqueAlreadyBraking => l10n.cornerDetailsReasonAlreadyBraking,
  brakingTechniqueGap => l10n.brakingTechniqueReasonGap,
  brakingTechniqueTruncated => l10n.brakingTechniqueReasonTruncated,
  brakingTechniqueTooLight => l10n.brakingTechniqueReasonTooLight,
  brakingTechniqueTooQuick => l10n.brakingTechniqueReasonTooQuick,
  brakingTechniqueNoLateral => l10n.brakingTechniqueReasonNoLateral,
  brakingTechniqueLateralPlaceholder => l10n.brakingTechniqueReasonLateralEmpty,
  brakingTechniqueLateralTooSlow => l10n.brakingTechniqueReasonLateralTooSlow(
    _rate(rate),
  ),
  brakingTechniqueUnitNotSupported => l10n.cornerDetailsReasonUnitNotSupported,
  brakingTechniqueNoThrottle => l10n.brakingTechniqueReasonNoThrottle,
  brakingTechniqueNoPickup => l10n.cornerDetailsReasonNoPickup,
  brakingTechniqueNoBrake => l10n.brakingTechniqueReasonNoBrake,
  brakingTechniqueBrakeTooSlow => l10n.brakingTechniqueReasonBrakeTooSlow(
    _rate(rate),
  ),
  brakingTechniqueBrakeNotUsed => l10n.cornerDetailsReasonBrakeChannelNotUsed,
  brakingTechniqueBrakeScaleUnknown => l10n.cornerDetailsReasonScaleUnknown,
  brakingTechniqueTooFewLaps => l10n.cornerClassReasonTooFewLaps,
  brakingTechniqueBrakingAgain => l10n.brakingTechniqueReasonBrakingAgain,
  brakingTechniqueCoasting => l10n.brakingTechniqueReasonCoasting,
  brakingTechniqueBrakeResampled => l10n.brakingTechniqueReasonBrakeResampled,
  _ => cornerReasonText(l10n, reason),
};

/// How the corner is braked into (FET-219): this lap's and the typical
/// initial hit, peak deceleration, trail braking (inferred), release and
/// brake-to-throttle time, with what they come from, and why any is not
/// known. The brake pedal's own ramp is shown only from a channel of about
/// 10 Hz; a slower one says its rate.
class BrakingTechniqueSection extends StatelessWidget {
  const BrakingTechniqueSection({
    super.key,
    required this.technique,
    required this.lap,
  });

  final BrakingTechnique technique;

  /// The lap the details are for.
  final DayLapReference lap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final own = technique.lap(lap);
    String reason(String reason, {double? rate}) =>
        brakingTechniqueReasonText(l10n, reason, rate: rate);

    Widget item(String key, String label, String value, [String note = '']) =>
        Padding(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (note.isNotEmpty) Text(note, style: theme.textTheme.bodySmall),
            ],
          ),
        );

    // "This lap 0.84 g/s · typical 0.70 g/s (16 laps)", each part saying
    // why when it is not known.
    String values(
      double? Function(BrakingTechniqueLap) read,
      String Function(BrakingTechniqueLap) why,
      BrakingTechniqueTypical typical,
      String Function(double) format, {
      double? rate,
      bool Function(BrakingTechniqueLap)? atLeast,
    }) {
      final mine = own == null ? null : read(own);
      String bounded(String text, bool lower) =>
          lower ? l10n.brakingTechniqueAtLeast(text) : text;
      return [
        if (own != null)
          mine != null
              ? l10n.brakingTechniqueThisLap(
                  bounded(format(mine), atLeast != null && atLeast(own)),
                )
              : l10n.brakingTechniqueThisLapUnknown(
                  reason(
                    own.measured ? why(own) : own.unavailableReason,
                    rate: rate ?? own.rateHz,
                  ),
                ),
        typical.median != null
            ? l10n.brakingTechniqueTypical(
                bounded(format(typical.median!), typical.atLeast),
                typical.laps,
              )
            : l10n.brakingTechniqueTypicalUnknown(
                reason(typical.reason, rate: rate ?? technique.rateHz),
              ),
      ].join(' · ');
    }

    // A typical resting on under three quarters of the braking laps says
    // how many, and why the others have none.
    String subset(BrakingTechniqueTypical typical) {
      if (!typical.partial) return '';
      final dropped = typical.droppedReason;
      return switch (dropped) {
        brakingTechniqueBrakingAgain || brakingTechniqueCoasting =>
          l10n.brakingTechniqueSubsetBraked(typical.laps, typical.brakingLaps),
        _ => l10n.brakingTechniqueSubsetOther(
          typical.laps,
          typical.brakingLaps,
          reason(dropped, rate: technique.rateHz),
        ),
      };
    }

    String notes(List<String> parts) =>
        parts.where((part) => part.isNotEmpty).join(' ');

    String gPerSecond(double value) => '${fixed(value, 2)}\u00a0g/s';
    String g(double value) => '${fixed(value, 2)}\u00a0g';
    String seconds(double value) => '${fixed(value, 2)}\u00a0s';

    final title = Text(
      l10n.brakingTechniqueTitle,
      key: const ValueKey('brakingTechniqueTitle'),
      style: theme.textTheme.titleSmall,
    );
    final rate = _rate(technique.rateHz);
    final noG = technique.gChannelReason == brakingTechniqueGPlaceholder
        ? l10n.brakingTechniqueGChannelEmpty
        : l10n.brakingTechniqueNoGChannel;
    final source = switch (technique.source) {
      brakingTechniqueFromG when technique.unitAssumed =>
        l10n.brakingTechniqueFromGAssumed(rate),
      brakingTechniqueFromG => l10n.brakingTechniqueFromG(rate),
      brakingTechniqueFromSpeed when technique.unitAssumed =>
        l10n.brakingTechniqueFromSpeedAssumed(
          rate,
          technique.assumedUnit.isEmpty ? 'km/h' : technique.assumedUnit,
          noG,
        ),
      brakingTechniqueFromSpeed => l10n.brakingTechniqueFromSpeed(rate, noG),
      _ => '',
    };
    final counts = [
      if (source.isNotEmpty) source,
      if (technique.lapsMeasured > 0)
        l10n.brakingTechniqueBrakingLaps(
          technique.lapsBraking,
          technique.lapsMeasured,
        ),
      if (technique.otherSourceLaps > 0)
        l10n.brakingTechniqueOtherSource(technique.otherSourceLaps),
    ].join(' ');
    if (technique.unavailableReason.isNotEmpty &&
        (own == null || !own.measured)) {
      return Column(
        key: const ValueKey('brakingTechnique'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          Padding(
            key: const ValueKey('brakingTechniqueReason'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              l10n.brakingTechniqueUnavailable(
                reason(
                  own != null && own.unavailableReason.isNotEmpty
                      ? own.unavailableReason
                      : technique.unavailableReason,
                  rate: own?.rateHz ?? technique.rateHz,
                ),
              ),
            ),
          ),
          if (counts.isNotEmpty) Text(counts, style: theme.textTheme.bodySmall),
        ],
      );
    }

    // Where the peak falls, by time: this lap's, and the typical third.
    final peakNotes = [
      if (own != null && own.measured)
        l10n.brakingTechniquePeakWhere(
          fixed(own.peakTime! - own.onsetTime!, 1),
          fixed(own.zoneSeconds!, 1),
        ),
      switch (technique.peakFraction.median) {
        null => '',
        < 1 / 3 => l10n.brakingTechniquePeakEarly,
        < 2 / 3 => l10n.brakingTechniquePeakMiddle,
        _ => l10n.brakingTechniquePeakLate,
      },
    ].where((note) => note.isNotEmpty).join(' ');
    final throttleRate = technique.throttleRateHz;
    final hasThrottle = technique.laps.any(
      (entry) => entry.$2.throttleChannel.isNotEmpty,
    );
    final brakeRate = technique.brakeRateHz;
    final hasBrake = technique.laps.any(
      (entry) => entry.$2.brakeChannel.isNotEmpty,
    );
    final pedalSlow =
        brakeRate != null && brakeRate < brakingTechniqueMinimumRateHz;

    return Column(
      key: const ValueKey('brakingTechnique'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        if (counts.isNotEmpty)
          Text(
            counts,
            key: const ValueKey('brakingTechniqueSource'),
            style: theme.textTheme.bodySmall,
          ),
        item(
          'brakingTechniqueHit',
          l10n.brakingTechniqueHit,
          values(
            (lap) => lap.hitGPerSecond,
            (lap) => lap.hitReason,
            technique.hit,
            gPerSecond,
            atLeast: (lap) => lap.hitAtLeast,
          ),
          subset(technique.hit),
        ),
        item(
          'brakingTechniquePeak',
          l10n.brakingTechniquePeak,
          values(
            (lap) => lap.peakG,
            (lap) => brakingTechniqueNotCovered,
            technique.peak,
            g,
          ),
          notes([peakNotes, subset(technique.peak)]),
        ),
        item(
          'brakingTechniqueTrail',
          l10n.brakingTechniqueTrail,
          values(
            (lap) => lap.trailSeconds,
            (lap) => lap.trailReason,
            technique.trailSeconds,
            (value) => seconds(value),
            rate: technique.lateralRateHz,
          ),
          notes([
            [
              if (own?.trailMeters != null)
                l10n.brakingTechniqueThisLap(_meters(own!.trailMeters)),
              l10n.brakingTechniqueTrailNote,
              if (technique.lateralUnitAssumed)
                l10n.brakingTechniqueLateralAssumed,
            ].join(' · '),
            subset(technique.trailSeconds),
          ]),
        ),
        item(
          'brakingTechniqueRelease',
          l10n.brakingTechniqueRelease,
          values(
            (lap) => lap.releaseGPerSecond,
            (lap) => lap.releaseReason,
            technique.release,
            gPerSecond,
            atLeast: (lap) => lap.releaseAtLeast,
          ),
          subset(technique.release),
        ),
        if (hasThrottle)
          item(
            'brakingTechniqueThrottle',
            l10n.brakingTechniqueBrakeToThrottle,
            values(
              (lap) => lap.brakeToThrottleSeconds,
              (lap) => lap.brakeToThrottleReason,
              technique.brakeToThrottle,
              // A throttle slower than about 10 Hz places the pickup only
              // to its update interval: to 0.1 s, and "about".
              technique.throttleCoarse
                  ? (value) =>
                        l10n.brakingTechniqueAbout('${fixed(value, 1)}\u00a0s')
                  : seconds,
            ),
            [
              if (throttleRate != null)
                l10n.brakingTechniqueThrottleNote(
                  _rate(throttleRate),
                  fixed(1 / throttleRate, 1),
                ),
              if (technique.throttleUnitAssumed)
                l10n.brakingTechniqueThrottleAssumed,
              if (technique.throttleScaleInferred)
                l10n.brakingTechniqueThrottleScaleInferred,
              subset(technique.brakeToThrottle),
            ].join(' '),
          ),
        if (hasBrake)
          pedalSlow
              ? Padding(
                  key: const ValueKey('brakingTechniquePedal'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.brakingTechniquePedal,
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        l10n.brakingTechniquePedalSlow(_rate(brakeRate)),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              : item(
                  'brakingTechniquePedal',
                  l10n.brakingTechniquePedal,
                  [
                    values(
                      (lap) => lap.pedalApplicationPerSecond,
                      (lap) => lap.pedalReason,
                      technique.pedalApplication,
                      (value) => '${fixed(value, 0)}\u00a0%/s',
                      rate: brakeRate,
                    ),
                    values(
                      (lap) => lap.pedalReleasePerSecond,
                      (lap) => lap.pedalReason,
                      technique.pedalRelease,
                      (value) => '${fixed(value, 0)}\u00a0%/s',
                      rate: brakeRate,
                    ),
                  ].join('\n'),
                  [
                    if (technique.brakeUnitAssumed)
                      l10n.brakingTechniqueBrakeAssumed,
                    if (technique.brakeScaleInferred)
                      l10n.brakingTechniqueBrakeScaleInferred,
                  ].join(' '),
                ),
        Text(
          l10n.brakingTechniqueNote,
          key: const ValueKey('brakingTechniqueNote'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Shows [corner] on [lap] in a bottom sheet.
/// With [onAnalyze], a button opens the corner in the Corner Analyzer.
Future<void> showCornerDetails(
  BuildContext context,
  DayCorner corner,
  DayLapReference lap, {
  VoidCallback? onAnalyze,
}) {
  final comparison = corner.compare(lap);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // A strip of the page stays visible above a long sheet, so a tap there
    // closes it on a small phone too.
    constraints: BoxConstraints(
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (comparison == null)
              Text(
                context.l10n.cornerDetailsNotMeasured(
                  context.l10n.tbSegmentName(corner.name),
                ),
              )
            else
              CornerDetails(corner: corner, comparison: comparison),
            if (onAnalyze != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  key: const ValueKey('cornerOpenAnalyzer'),
                  icon: const Icon(Icons.compare_arrows),
                  label: Text(context.l10n.tbOpenInAnalyzer),
                  onPressed: () {
                    Navigator.pop(context);
                    onAnalyze();
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// One line for a corner's row: the lap's minimum speed and braking point
/// against the best lap.
String cornerSummary(AppLocalizations l10n, DayCornerComparison comparison) {
  final own = comparison.metrics;
  final best = comparison.bestLapMetrics;
  final isBest = comparison.bestLap?.reference == comparison.lap.reference;
  final unit = speedUnitLabel(own.speeds.unit).trim();
  final parts = <String>[];
  final minimum = own.speeds.minimum.value;
  if (minimum != null) {
    final bestMinimum = best?.speeds.minimum.value;
    final speed = '${_speed(minimum)}${unit.isEmpty ? '' : '\u00a0$unit'}';
    parts.add(
      isBest || bestMinimum == null || comparison.speeds.minimumDelta == null
          ? l10n.cornerSummaryMin(speed)
          : l10n.cornerSummaryMinWithBest(speed, _speed(bestMinimum)),
    );
  }
  final before = own.braking.distanceBeforeEntryMeters;
  if (before != null) {
    final delta = comparison.braking.brakingPointDeltaMeters;
    final where = before.round() >= 0
        ? l10n.cornerBeforeEntry(before.round())
        : l10n.cornerIntoCorner(-before.round());
    parts.add(
      isBest || delta == null
          ? l10n.cornerSummaryBrakes(where)
          : l10n.cornerSummaryBrakesWithBest(where, _positionText(l10n, delta)),
    );
  }
  return parts.join(' · ');
}
