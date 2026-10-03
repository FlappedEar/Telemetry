import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';
import '../units.dart';

/// Why a corner figure is missing, in a short plain phrase (lower case, to
/// follow a colon or start a sentence). Every reason the corner analyses can
/// give is mapped; an unknown one reads "not available", never its
/// identifier.
String cornerReasonText(String reason) => switch (reason) {
  '' => 'not measured',
  // Braking.
  brakingNoneDetected => 'no braking detected',
  brakingNoChannel => 'no brake or deceleration channel',
  brakingInferenceDisabled => 'no brake channel',
  brakingDecelerationChannelMissing => 'no deceleration channel',
  brakingApproachClipped => 'approach cut off at the start/finish line',
  brakingApproachClippedAtCorner => 'approach runs into the previous corner',
  brakingAlreadyActive => 'already braking before the approach',
  brakingInterruptedByGap => 'braking interrupted by a recording gap',
  brakingNoSamples => 'no samples here',
  // Throttle pickup and exit.
  exitNoChannel => 'no throttle or acceleration channel',
  exitNoLift => 'no lift before the pickup',
  exitNoPickup => 'no pickup detected',
  exitFollowsGap => 'after a recording gap',
  exitTruncated => 'cut off at the lap end',
  // Shared by several analyses.
  analyzerIncompleteCoverage => 'lap not fully covered here',
  cornerPhaseCrossesGate => 'crosses the start/finish line',
  exitUnitMismatch => 'channel unit not supported',
  exitUnitUndeclared => 'channel unit not recorded',
  cornerPhaseSpeedChannelMissing => 'no speed channel',
  cornerSpeedMixedProvenance => 'measured differently on A and B',
  cornerSpeedDifferentSegmentOrRevision => 'segments differ between the laps',
  // Corner phases and speeds.
  cornerPhaseMultipleApexes => 'double apex: no single apex point',
  cornerPhaseFlatSpeed => 'no lowest point (constant speed)',
  cornerPhaseInsufficientGeometry => 'corner shape too unclear to place it',
  cornerPhaseInvalidInput => 'corner could not be measured',
  cornerPhaseBroadPeak => 'apex spread over a long arc',
  cornerPhaseAtCornerBoundary => 'at the edge of the corner',
  cornerSpeedNotACorner => 'not a corner',
  cornerSpeedSparseSamples => 'too few samples',
  // Sector times and summaries.
  sectorTimeSegmentNotFound => 'segment not found on this lap',
  channelSummaryMissing => 'not recorded',
  channelSummaryNoSamples => 'no valid samples',
  timeLossNoReference => 'no reference lap',
  timeLossUntimed => 'not timed',
  theoreticalBestNoApprovedSegmentation => 'no approved segments',
  drivingStateUnknownReason => 'driving state unknown',
  _ => 'not available',
};

String _speed(double? value) => value == null ? '—' : value.toStringAsFixed(1);

String _meters(double? value) =>
    value == null ? '—' : '${value < 0 ? '−' : ''}${value.abs().round()} m';

// A braking point as metres before the corner's start; negative is inside.
String _beforeEntry(double value) => value.round() >= 0
    ? '${value.round()} m before'
    : '${-value.round()} m into the corner';

// [_position] in the app's language.
String _positionText(AppLocalizations l10n, double delta) {
  if (!delta.isFinite) return '—';
  final metres = delta.abs().round();
  if (metres == 0) return l10n.cornerSamePosition;
  return delta > 0 ? l10n.cornerLater(metres) : l10n.cornerEarlier(metres);
}

/// Lap A (this lap) and lap B (the best lap), as Overlays colours them.
const Color lapAColor = Color(0xFF55E6A5), lapBColor = Color(0xFFD95926);

String _signed(double? value, int digits, [String unit = '']) {
  if (value == null || !value.isFinite) return '—';
  final text = value.abs().toStringAsFixed(digits);
  if (double.parse(text) == 0) return '±$text$unit';
  return '${value > 0 ? '+' : '−'}$text$unit';
}

// A position delta (A minus B along the lap) in words.
String _position(double? delta) {
  if (delta == null || !delta.isFinite) return '—';
  final metres = delta.abs().round();
  if (metres == 0) return 'same';
  return '$metres m ${delta > 0 ? 'later' : 'earlier'}';
}

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
    final own = comparison.metrics;
    final best = comparison.bestLapMetrics;
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
        return cornerReasonText(braking.unavailableReason);
      }
      final how = braking.provenance == 'inferred'
          ? 'Inferred from deceleration'
          : 'From the brake channel';
      if (best != null &&
          bestBraking?.brakingPointMeters != null &&
          comparison.braking.unavailableReason == 'mixedProvenance') {
        return '$how; the best lap was measured differently';
      }
      return how;
    }

    String pickupNote() {
      if (pickup.progressMeters == null) {
        return cornerReasonText(pickup.unavailableReason);
      }
      final how = pickup.provenance == 'inferred'
          ? 'Inferred from acceleration'
          : 'From the throttle channel';
      if (comparison.exit.pickupUnavailableReason == 'mixedProvenance') {
        return '$how; the best lap was measured differently';
      }
      return how;
    }

    String speedNote() {
      if (comparison.speeds.unavailableReason == 'mixedProvenance') {
        return 'The best lap’s speed was recorded differently';
      }
      if (own.speeds.minimum.value == null) {
        return 'Minimum: ${cornerReasonText(own.speeds.minimum.unavailableReason)}';
      }
      return '';
    }

    final group = <(String, DayCornerValue?, String Function(double))>[
      ('Highest minimum speed', comparison.highestMinimumSpeed, _speed),
      ('Highest exit speed', comparison.highestExitSpeed, _speed),
      ('Latest braking point', comparison.latestBrakingPoint, _beforeEntry),
      (
        'Earliest throttle pickup',
        comparison.earliestPickup,
        (v) => '${v.round()} m in',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(corner.name, style: theme.textTheme.titleLarge),
        Text(
          isBest
              ? '${comparison.lap.displayName} · the best lap'
              : '${comparison.lap.displayName} against the best lap, '
                    '${comparison.bestLap?.displayName ?? 'unavailable'}',
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
                  ('This lap', lapAColor),
                  ('Best lap', lapBColor),
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
          'Entry speed$speedUnit',
          _speed(own.speeds.entry.value),
          _speed(best?.speeds.entry.value),
          _signed(comparison.speeds.entryDelta, 1),
          key: const ValueKey('cornerEntrySpeed'),
        ),
        row(
          'Minimum speed$speedUnit',
          _speed(own.speeds.minimum.value),
          _speed(best?.speeds.minimum.value),
          _signed(comparison.speeds.minimumDelta, 1),
          key: const ValueKey('cornerMinimumSpeed'),
        ),
        row(
          'Exit speed$speedUnit',
          _speed(own.speeds.exit.value),
          _speed(best?.speeds.exit.value),
          _signed(comparison.speeds.exitDelta, 1),
          note: speedNote(),
          key: const ValueKey('cornerExitSpeed'),
        ),
        const Divider(),
        row(
          'Braking point, before the corner',
          _meters(braking.distanceBeforeEntryMeters),
          _meters(bestBraking?.distanceBeforeEntryMeters),
          _position(comparison.braking.brakingPointDeltaMeters),
          note: brakingNote(),
          key: const ValueKey('cornerBrakingPoint'),
        ),
        if (braking.brakingSeconds != null)
          row(
            'Braking time',
            '${braking.brakingSeconds!.toStringAsFixed(2)} s',
            bestBraking?.brakingSeconds == null
                ? '—'
                : '${bestBraking!.brakingSeconds!.toStringAsFixed(2)} s',
            _signed(comparison.braking.brakingSecondsDelta, 2, ' s'),
            key: const ValueKey('cornerBrakingTime'),
          ),
        if (braking.peakDeceleration != null)
          row(
            'Peak deceleration'
            '${braking.decelerationUnit.isEmpty ? '' : ' (${braking.decelerationUnit})'}',
            braking.peakDeceleration!.toStringAsFixed(2),
            bestBraking?.peakDeceleration?.toStringAsFixed(2) ?? '—',
            _signed(comparison.braking.peakDecelerationDelta, 2),
            key: const ValueKey('cornerPeakDeceleration'),
          ),
        const Divider(),
        row(
          'Throttle pickup, into the corner',
          _meters(afterEntry(pickup)),
          _meters(afterEntry(bestPickup)),
          _position(comparison.exit.pickupDeltaMeters),
          note: pickupNote(),
          key: const ValueKey('cornerPickup'),
        ),
        const SizedBox(height: 12),
        Text(
          'Best of ${corner.laps.length} laps',
          style: theme.textTheme.titleSmall,
        ),
        for (final (label, value, format) in group)
          Padding(
            key: ValueKey('cornerBest $label'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(label)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value == null ? '—' : format(value.value),
                      style: strong,
                    ),
                    if (value != null)
                      Text(
                        value.lap.displayName,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Braking point and pickup are distances from the corner’s start on '
          'the shared track axis. Later braking or an earlier pickup is not '
          'automatically faster. Laps measured another way are not compared.',
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
              Text('${corner.name}: this lap was not measured here.')
            else
              CornerDetails(corner: corner, comparison: comparison),
            if (onAnalyze != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  key: const ValueKey('cornerOpenAnalyzer'),
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('Open in the Corner Analyzer'),
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
    final speed = '${_speed(minimum)}${unit.isEmpty ? '' : ' $unit'}';
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
