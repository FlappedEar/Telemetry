import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

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
      _ => l10n.cornerDetailsReasonNotAvailable,
    };

// Why a corner is not split, or a lap not timed through its parts.
String _phaseReason(AppLocalizations l10n, String reason) =>
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
                _phaseReason(l10n, comparison.bestLapPhases.unavailableReason),
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
                _phaseReason(l10n, comparison.phases.unavailableReason),
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
