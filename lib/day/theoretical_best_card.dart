import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_controller.dart' show offersCalculateAgain;
import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import '../units.dart';
import 'corner_details.dart';
import 'time_losses_card.dart' show CompareLaps, lapStretch;
import 'touch.dart';
import 'track_map.dart';

/// The colour of a loss of [fraction] (0 to 1) of the largest: one hue, dim
/// to bright, as in Overlays' "Where your best lap can improve", ending in
/// the app's loss red (`FetColors.loss`) so it never reads as lap A's amber.
/// [loss] is the theme's loss red (`FetColors.of(context).loss`).
Color lossColor(double fraction, [Color? loss]) {
  return Color.lerp(
    Color.from(alpha: 1, red: 0.30, green: 0.36, blue: 0.42),
    loss ?? FetColors.dark.loss,
    fraction.clamp(0.0, 1.0),
  )!;
}

/// "C1" for "Corner 1", "S2" for "Straight 2", "C3–4" for "Corners 3–4".
String shortSegmentName(String name) {
  final match = RegExp(r'^(\w)\w*\s+(.+)$').firstMatch(name.trim());
  if (match == null) return name;
  return '${match.group(1)!.toUpperCase()}${match.group(2)}';
}

final _automaticSegmentName = RegExp(r'^(Corners?|Straight) (\d+(?:–\d+)?)$');

// A split segment's name, "Corner 3 (2)" (`splitSegmentName`).
final _splitSegmentName = RegExp(r'^(.+) \((\d+)\)$');

/// The theoretical best's texts from `telemetry_core` in the app's language.
extension TheoreticalBestText on AppLocalizations {
  /// An automatic segment name ("Corner 3", "Corners 3–4", "Straight 2"),
  /// also when split ("Corner 3 (2)"), in the app's language; a name the
  /// user gave is shown as written.
  String tbSegmentName(String name) {
    final split = _splitSegmentName.firstMatch(name);
    if (split != null) {
      final base = tbSegmentName(split.group(1)!);
      if (base != split.group(1)) return '$base (${split.group(2)})';
    }
    final match = _automaticSegmentName.firstMatch(name);
    if (match == null) return name;
    final number = match.group(2)!;
    return switch (match.group(1)) {
      'Corner' => tbSegmentCorner(number),
      'Corners' => tbSegmentCorners(number),
      _ => tbSegmentStraight(number),
    };
  }

  /// Why a card built on the theoretical best shows nothing: a failure is
  /// shown, with its retry, only on the Theoretical best card.
  String tbDependent(DayTheoreticalBest result) =>
      result.state == DayTheoreticalBestState.error
      ? tbFailedElsewhere
      : tbMessage(result.message);

  /// Why there is no theoretical best, or no total or segment time
  /// (`DayTheoreticalBest.message`, a segment's `unavailableReason`); a
  /// message the app does not know, such as an error, is shown as written.
  String tbMessage(String message) => switch (message) {
    'Confirm a compatible track configuration before calculating a '
        'theoretical best.' =>
      tbNoConfiguration,
    'No eligible laps in this group to calculate a theoretical best from.' =>
      tbNoEligibleLaps,
    'No run in this group has an approved segment review yet. '
        'Approve segments for at least one run first.' =>
      tbNoApprovedRun,
    automaticSegmentsLineDisagreement => tbBestLapOffLine,
    'No approved segments to measure sectors against.' => tbNoApprovedSegments,
    'At least one sector has no fully covered time on any eligible lap, so '
        'no total is shown.' =>
      tbIncompleteCoverage,
    'Theoretical best calculation was cancelled.' => tbCancelled,
    // A failure of the work itself ("The work stopped.") or another core
    // message, in the app's language where it is known.
    _ => taskFailure(message),
  };
}

/// A group's theoretical best: the best lap, the theoretical best and the
/// time available; a loss map (the best lap's trace, each segment coloured
/// by the time the chosen lap loses there to the fastest time); where that
/// time is; and every lap's sector times with the fastest of each segment
/// highlighted.
class TheoreticalBestCard extends StatefulWidget {
  const TheoreticalBestCard({
    super.key,
    required this.result,
    this.loading = false,
    this.path,
    this.gate,
    this.wide = false,
    this.onEditSegments,
    this.onAnalyze,
    this.onRetry,
    this.sections,
  });

  /// Calculates again after a failure or with nothing to use, as Overlays'
  /// "Calculate again"; no button when null.
  final VoidCallback? onRetry;

  /// Opens the segment editor; no button when null.
  final VoidCallback? onEditSegments;

  /// Opens two laps in the Corner Analyzer on a segment; no button when
  /// null.
  final CompareLaps? onAnalyze;

  /// Null while it is calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;

  /// Each session's segment times, for the best typical lap; null while
  /// they are worked out.
  final SectionProgression? sections;

  /// The best lap's trace, for the loss map.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;

  @override
  State<TheoreticalBestCard> createState() => _TheoreticalBestCardState();
}

/// Overlays' "Calculate again" under a theoretical best that failed or had
/// nothing to use.
class CalculateAgainButton extends StatelessWidget {
  const CalculateAgainButton(this.onPressed, {super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: OutlinedButton.icon(
      key: const ValueKey('calculateAgain'),
      onPressed: onPressed,
      icon: const Icon(Icons.refresh),
      label: Text(context.l10n.calculateAgain),
    ),
  );
}

class _TheoreticalBestCardState extends State<TheoreticalBestCard> {
  // Kept for the page: the list rebuilds the card when it scrolls back.
  late DayLapReference? _selected = readPageState(context, _storage);
  static const _storage = 'theoreticalBestLap';

  void _choose(DayLapReference? reference) {
    setState(() => _selected = reference);
    writePageState(context, _storage, reference);
  }

  // The segment of each fix of the best lap's trace, by its time.
  DayTheoreticalBest? _indexedResult;
  LapPath? _indexedPath;
  Map<double, int?> _segmentOfFix = const {};

  DayLapSectors? _selectedLap(DayTheoreticalBest result) {
    DayLapSectors? best;
    for (final lap in result.laps) {
      if (lap.lap.reference == _selected) return lap;
      if (lap.bestOfDay) best = lap;
    }
    return best ?? (result.laps.isEmpty ? null : result.laps.first);
  }

  Map<double, int?> _segments(DayTheoreticalBest result, LapPath path) {
    if (!identical(result, _indexedResult) || !identical(path, _indexedPath)) {
      _indexedResult = result;
      _indexedPath = path;
      final best = result.bestLap;
      _segmentOfFix = best == null
          ? const {}
          : {
              for (final segment in path.segments)
                for (final point in segment)
                  point.telemetryTime: result.segmentAtTime(
                    best,
                    point.telemetryTime,
                  ),
            };
    }
    return _segmentOfFix;
  }

  String _lapName(
    AppLocalizations l10n,
    DayTheoreticalBest result,
    Object? reference,
  ) {
    for (final lap in result.laps) {
      if (lap.lap.reference == reference) return l10n.lap(lap.lap);
    }
    return l10n.tbLapUnavailable;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = widget.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.theoreticalBestLabel, style: theme.textTheme.labelLarge),
            if (widget.loading || result == null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(semanticsLabel: l10n.tbTiming),
              const SizedBox(height: 8),
              Text(l10n.tbTiming),
            ] else if (result.state != DayTheoreticalBestState.ready) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.tbMessage(result.message)),
              ),
              if (widget.onRetry case final retry?
                  when offersCalculateAgain(result))
                CalculateAgainButton(retry),
            ] else
              ..._ready(context, result),
          ],
        ),
      ),
    );
  }

  List<Widget> _ready(BuildContext context, DayTheoreticalBest result) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final lap = _selectedLap(result);
    final path = widget.path;
    return [
      const SizedBox(height: 8),
      _Headline(result: result),

      if (result.message.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(l10n.tbMessage(result.message)),
      ],
      const SizedBox(height: 4),
      Text(
        '${l10n.tbIntro(result.segments.length, result.laps.length)}'
        '${result.automaticSegments
            ? ' ${l10n.tbSegmentsProposed}'
            : result.segmentsAutomatic
            ? ''
            : ' ${l10n.tbSegmentsCorrected}'}',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      _ThreeBests(result: result, sections: widget.sections),
      if (widget.onEditSegments != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('editSegments'),
            icon: const Icon(Icons.edit_road),
            label: Text(l10n.tbEditSegments),
            onPressed: widget.onEditSegments,
          ),
        ),
      if (lap != null) ...[
        const SizedBox(height: 16),
        Text(l10n.tbWhereTimeGoes, style: theme.textTheme.titleSmall),
        DropdownButton<DayLapReference>(
          key: const ValueKey('lossLap'),
          isExpanded: true,
          value: lap.lap.reference,
          items: [
            for (final candidate in result.laps)
              DropdownMenuItem(
                value: candidate.lap.reference,
                child: Text(
                  _markBest(
                    l10n,
                    '${l10n.lap(candidate.lap)} · '
                    '${displayTime(candidate.lap.durationSeconds)}',
                    candidate.bestOfDay,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _choose,
        ),
        if (path != null && !path.isEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: widget.wide ? 360 : 260,
            child: IgnorePointer(
              child: TrackMap(
                key: const ValueKey('lossMap'),
                interactive: false,
                path: path,
                gate: widget.gate,
                pointColor: _lossColors(result, lap, path),
                semanticLabel: l10n.tbMapLabel(l10n.lap(lap.lap)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _LossLegend(maximum: _maximumLoss(lap)),
        const SizedBox(height: 8),
        if (result.corners.isNotEmpty)
          Text(l10n.tbTapCorner, style: theme.textTheme.bodySmall),
        if (widget.onAnalyze != null)
          Text(l10n.tbCompareHint, style: theme.textTheme.bodySmall),
        ..._losses(context, result, lap),
      ],
      const SizedBox(height: 16),
      Text(l10n.tbSectorTimes, style: theme.textTheme.titleSmall),
      Text(l10n.tbSectorHint, style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      _SectorTable(
        result: result,
        selected: lap?.lap.reference,
        onSelect: _choose,
      ),
      ..._brakingTechnique(context, result),
      ..._variability(context, result),
    ];
  }

  // The day's braking technique over its corners (FET-219): the median of
  // each corner's typical value, from one source; nothing when no corner
  // has one.
  List<Widget> _brakingTechnique(
    BuildContext context,
    DayTheoreticalBest result,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final day = summarizeBrakingTechniqueDay([
      for (final corner in result.corners) corner.brakingTechnique,
    ]);
    if (!day.available) return const [];
    String bounded(String text, bool lower) =>
        lower ? l10n.brakingTechniqueAtLeast(text) : text;
    // A throttle slower than about 10 Hz places the pickup only to 0.1 s.
    final coarse = result.corners.any(
      (corner) => corner.brakingTechnique.throttleCoarse,
    );
    final figures = [
      if (day.hit case final hit?)
        l10n.brakingTechniqueDayHit(
          bounded('${fixed(hit, 2)}\u00a0g/s', day.hitAtLeast),
        ),
      if (day.release case final release?)
        l10n.brakingTechniqueDayRelease(
          bounded('${fixed(release, 2)}\u00a0g/s', day.releaseAtLeast),
        ),
      if (day.trailSeconds case final trail?)
        l10n.brakingTechniqueDayTrail('${fixed(trail, 2)}\u00a0s'),
      if (day.brakeToThrottle case final throttle?)
        l10n.brakingTechniqueDayThrottle(
          coarse
              ? l10n.brakingTechniqueAbout('${fixed(throttle, 1)}\u00a0s')
              : '${fixed(throttle, 2)}\u00a0s',
        ),
    ].join(', ');
    final source = switch ((day.source, day.unitAssumed)) {
      (brakingTechniqueFromSpeed, true) =>
        l10n.brakingTechniqueDayFromSpeedAssumed,
      (brakingTechniqueFromSpeed, false) => l10n.brakingTechniqueDayFromSpeed,
      (_, true) => l10n.brakingTechniqueDayFromGAssumed,
      _ => l10n.brakingTechniqueDayFromG,
    };
    return [
      const SizedBox(height: 16),
      Text(l10n.brakingTechniqueDayTitle, style: theme.textTheme.titleSmall),
      Text(
        [
          l10n.brakingTechniqueDaySummary(day.cornersBraked, source, figures),
          if (day.otherSourceCorners > 0)
            l10n.brakingTechniqueDayOtherSource(day.otherSourceCorners),
        ].join(' '),
        key: const ValueKey('brakingTechniqueDay'),
      ),
      Text(l10n.brakingTechniqueDayNote, style: theme.textTheme.bodySmall),
    ];
  }

  // Each corner's braking, speeds, pickup and line from lap to lap, as
  // Overlays lists them (driving_variability.dart).
  List<Widget> _variability(BuildContext context, DayTheoreticalBest result) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final corners = [
      for (final row in result.segments)
        if (row.variability case final variability?) (row, variability),
    ];
    return [
      const SizedBox(height: 16),
      Text(l10n.variabilityHeading, style: theme.textTheme.titleSmall),
      Text(l10n.variabilityIntro, style: theme.textTheme.bodySmall),
      if (corners.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.variabilityNone,
            key: const ValueKey('noVariability'),
          ),
        )
      else
        for (final (row, variability) in corners)
          _VariabilityTile(
            id: row.name,
            name: l10n.tbSegmentName(row.name),
            variability: variability,
          ),
    ];
  }

  double _maximumLoss(DayLapSectors lap) => math.max(
    0.001,
    lap.lossSeconds.fold(0.0, (high, loss) => math.max(high, loss ?? 0.0)),
  );

  Color? Function(PathPoint) _lossColors(
    DayTheoreticalBest result,
    DayLapSectors lap,
    LapPath path,
  ) {
    final segments = _segments(result, path);
    final maximum = _maximumLoss(lap);
    final neutral = Theme.of(context).colorScheme.outline;
    final red = FetColors.of(context).loss;
    return (point) {
      final index = segments[point.telemetryTime];
      if (index == null) return neutral;
      final loss = lap.lossSeconds[index];
      return loss == null ? neutral : lossColor(loss / maximum, red);
    };
  }

  List<Widget> _losses(
    BuildContext context,
    DayTheoreticalBest result,
    DayLapSectors lap,
  ) {
    final maximum = _maximumLoss(lap);
    final order = List.generate(result.segments.length, (index) => index)
      ..sort((a, b) {
        final left = lap.lossSeconds[a] ?? -1.0,
            right = lap.lossSeconds[b] ?? -1.0;
        return left != right ? right.compareTo(left) : a.compareTo(b);
      });
    return [
      for (final index in order) _lossRow(context, result, lap, index, maximum),
    ];
  }

  // One segment's loss; a corner also shows its minimum speed and braking
  // point against the best lap, and opens its details when tapped.
  Widget _lossRow(
    BuildContext context,
    DayTheoreticalBest result,
    DayLapSectors lap,
    int index,
    double maximum,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final segment = result.segments[index];
    final analyze = _analyze(result, lap, index);
    final corner = result.cornerAt(index);
    final comparison = corner?.compare(lap.lap.reference);
    speedUnitOf(context); // The summary's speeds follow the setting.
    final summary = comparison == null ? null : cornerSummary(l10n, comparison);
    final kind = corner == null
        ? null
        : cornerClassSummary(l10n, corner.classification);
    final loss = Text(
      lap.lossSeconds[index] == null
          ? '—'
          : '+${lap.lossSeconds[index]!.toStringAsFixed(3)}\u00a0s',
      textAlign: TextAlign.end,
      style: theme.textTheme.titleSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    // With very large text the loss goes under the segment's name, so the
    // row still fits a phone.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final row = Padding(
      // 36 + 12: a 48 dp row to tap.
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 36,
            decoration: BoxDecoration(
              color: lap.lossSeconds[index] == null
                  ? theme.colorScheme.outline
                  : lossColor(
                      lap.lossSeconds[index]! / maximum,
                      FetColors.of(context).loss,
                    ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.tbSegmentName(segment.name)),
                if (stacked) loss,
                // Wraps at 360 dp: the lap that set the time matters.
                Text(
                  _lossDetail(l10n, result, lap, index),
                  style: theme.textTheme.bodySmall,
                ),
                if (summary != null && summary.isNotEmpty)
                  Text(
                    summary,
                    key: ValueKey('cornerSummary ${corner!.name}'),
                    style: theme.textTheme.bodySmall,
                  ),
                // What kind of corner it is (FET-220), the same on every lap.
                if (kind != null)
                  Text(
                    kind,
                    key: ValueKey('cornerClassSummary ${corner!.name}'),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (!stacked) ...[const SizedBox(width: 8), loss],
          if (analyze != null)
            IconButton(
              key: ValueKey('lossAnalyze ${segment.name}'),
              tooltip: l10n.tbOpenInAnalyzer,
              icon: const Icon(Icons.compare_arrows),
              onPressed: analyze,
            )
          else if (comparison != null)
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        ],
      ),
    );
    if (corner == null || comparison == null) return row;
    return ButtonRow(
      // The analyze button stays its own, with its own action.
      merge: analyze == null,
      child: InkWell(
        key: ValueKey('lossRow ${corner.name}'),
        onTap: () => showCornerDetails(
          context,
          corner,
          lap.lap.reference,
          onAnalyze: analyze,
        ),
        child: row,
      ),
    );
  }

  // Opens [lap] (or, for the best lap, the lap that set the segment's
  // fastest time) against the best lap through segment [index].
  VoidCallback? _analyze(
    DayTheoreticalBest result,
    DayLapSectors lap,
    int index,
  ) {
    final onAnalyze = widget.onAnalyze;
    final segment = result.segments[index];
    if (onAnalyze == null) return null;
    final pair = dayTheoreticalBestSectorPair(
      result,
      segment.segmentId,
      lap: lap.lap,
    );
    if (pair == null) return null;
    final (a, b) = pair;
    return () => onAnalyze(
      a,
      b,
      lapStretch(
        result,
        a,
        segment.startProgressMeters,
        segment.endProgressMeters,
      ),
      segmentId: segment.segmentId,
    );
  }

  String _lossDetail(
    AppLocalizations l10n,
    DayTheoreticalBest result,
    DayLapSectors lap,
    int index,
  ) {
    final segment = result.segments[index];
    if (segment.seconds == null) {
      return l10n.tbMessage(segment.unavailableReason);
    }
    if (lap.lossSeconds[index] == null) {
      return l10n.tbNotCovered(displayTime(segment.seconds!));
    }
    if (segment.sourceLapReference == lap.lap.reference) {
      return l10n.tbFastestHere(displayTime(segment.seconds!));
    }
    return l10n.tbFastestBy(
      displayTime(segment.seconds!),
      _lapName(l10n, result, segment.sourceLapReference),
    );
  }
}

/// [text], marked as the best lap when [best].
String _markBest(AppLocalizations l10n, String text, bool best) =>
    best ? l10n.tbMarkedBest(text) : text;

/// The lines of one corner's [CornerVariability], as Overlays writes them:
/// a metric measured on no lap is left out, one on fewer than three laps
/// says so, and braking points and pickups say whether they were measured or
/// inferred.
List<String> variabilityLines(
  AppLocalizations l10n,
  CornerVariability variability,
  String speedUnit,
) {
  final unit = speedUnit.trim().isEmpty ? '' : '\u00a0${speedUnit.trim()}';
  String? spread(String label, ConsistencySummary summary, String provenance) {
    if (summary.count == 0) return null;
    final tail = '${l10n.variabilityLaps(summary.count)} · $provenance';
    if (!summary.available) return l10n.variabilityTooFew(label, tail);
    return l10n.variabilitySpread(
      label,
      '${fixed(summary.interquartileRange!, 1)}\u00a0m',
      tail,
    );
  }

  String? speed(String label, ConsistencySummary summary) {
    if (summary.count == 0) return null;
    final tail = l10n.variabilityLaps(summary.count);
    if (!summary.available) return l10n.variabilityTooFew(label, tail);
    return l10n.variabilityTypical(
      label,
      '${fixed(summary.median!, 1)}$unit',
      '${fixed(summary.interquartileRange!, 1)}$unit',
      tail,
    );
  }

  return [
    ?spread(
      l10n.variabilityBraking,
      variability.brakingPointMeasured,
      l10n.variabilityMeasured,
    ),
    ?spread(
      l10n.variabilityBraking,
      variability.brakingPointInferred,
      l10n.variabilityInferred,
    ),
    ?speed(l10n.variabilityApex, variability.apexSpeed),
    ?speed(l10n.variabilityMinimum, variability.minimumSpeed),
    ?speed(l10n.variabilityExit, variability.exitSpeed),
    ?spread(
      l10n.variabilityPickup,
      variability.pickupMeasured,
      l10n.variabilityMeasured,
    ),
    ?spread(
      l10n.variabilityPickup,
      variability.pickupInferred,
      l10n.variabilityInferred,
    ),
    ?_lineText(l10n, variability),
  ];
}

// The line's spread where the corner starts, at its apex and where it ends
// (FET-225), each part only when enough laps have it. Which parts cannot be
// told from GPS error is said only when the GPS accuracy is known.
String? _lineText(AppLocalizations l10n, CornerVariability variability) {
  final accuracy = variability.typicalGpsAccuracyMeters;
  final gps = accuracy == null
      ? l10n.variabilityGpsUnknown
      : l10n.variabilityGpsAccuracy(fixed(accuracy, accuracy < 1 ? 2 : 1));
  final apex = variability.lineOffset;
  final entry = variability.entryLineOffset;
  final exit = variability.exitLineOffset;
  final parts = [
    if (entry.available)
      (
        l10n.variabilityLineEntry(fixed(entry.interquartileRange!, 1)),
        l10n.variabilityLineEntryName,
        variability.entryLineResolvable,
      ),
    if (apex.available)
      (
        l10n.variabilityLineApex(fixed(apex.interquartileRange!, 1)),
        l10n.variabilityLineApexName,
        variability.lineSpreadResolvable,
      ),
    if (exit.available)
      (
        l10n.variabilityLineExit(fixed(exit.interquartileRange!, 1)),
        l10n.variabilityLineExitName,
        variability.exitLineResolvable,
      ),
  ];
  if (parts.isEmpty) return null;
  final unresolved = [
    if (accuracy != null)
      for (final (_, name, resolvable) in parts)
        if (!resolvable) name,
  ];
  return l10n.variabilityLineParts(
        [for (final (text, _, _) in parts) text].join(', '),
        gps,
      ) +
      (unresolved.isEmpty
          ? ''
          : l10n.variabilityLinePartsUnresolved(unresolved.join(', ')));
}

/// One corner's variability, folded to its name and first line.
class _VariabilityTile extends StatelessWidget {
  const _VariabilityTile({
    required this.id,
    required this.name,
    required this.variability,
  });

  /// The segment's stored name, for the key; [name] is the one shown.
  final String id;
  final String name;
  final CornerVariability variability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final lines = variabilityLines(l10n, variability, speedUnitOf(context));
    return ExpansionTile(
      key: ValueKey('variability $id'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      expandedAlignment: Alignment.centerLeft,
      title: Text(name),
      subtitle: Text(
        lines.isEmpty ? l10n.variabilityNotMeasured : lines.first,
        style: theme.textTheme.bodySmall,
      ),
      children: [
        for (final line in lines.skip(1))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(line, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.result});

  final DayTheoreticalBest result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final best = result.bestLapSeconds;
    final total = result.theoreticalBestSeconds;
    final available = result.availableSeconds;
    Widget stat(String label, String value, Key key, [Color? color]) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          value,
          key: key,
          style: theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        stat(
          result.summary?.actualBest?.coversWholeLap ?? true
              ? l10n.tbBestLap
              : l10n.tbBestLapSameSegments,
          best == null ? '—' : displayTime(best),
          const ValueKey('bestLapTime'),
        ),
        stat(
          l10n.theoreticalBestLabel,
          total == null ? '—' : displayTime(total),
          const ValueKey('theoreticalBestTime'),
          // Blue, as the day page's Theoretical best bar.
          FetColors.of(context).reference,
        ),
        stat(
          l10n.tbAvailable,
          available == null ? '—' : '${available.toStringAsFixed(3)}\u00a0s',
          const ValueKey('availableTime'),
          FetColors.of(context).gain,
        ),
      ],
    );
  }
}

/// The theoretical best three ways (FET-222): the fastest segments from any
/// lap, the fastest that join at the speed the car had, and each segment's
/// best typical time.
class _ThreeBests extends StatelessWidget {
  const _ThreeBests({required this.result, this.sections});

  final DayTheoreticalBest result;
  final SectionProgression? sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final raw = result.theoreticalBestSeconds;
    final realistic = result.realistic;
    final sections = this.sections;
    final repeatable = sections == null
        ? null
        : repeatableTheoreticalBest(sections);
    Widget row(String label, String note, String value, Key key) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(note, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            key: ValueKey('${(key as ValueKey<String>).value} value'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return Column(
      key: const ValueKey('threeBests'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.tbThreeTitle, style: theme.textTheme.titleSmall),
        row(
          l10n.tbRawLabel,
          l10n.tbRawNote,
          raw == null ? '—' : displayTime(raw),
          const ValueKey('rawBest'),
        ),
        row(
          l10n.tbRealisticLabel,
          switch (realistic) {
            final best? when best.valid => l10n.tbRealisticNote(
              fixed(realisticJoinMetresPerSecond * 3.6, 0),
              best.lapCount,
            ),
            RealisticTheoreticalBest(unavailableReason: realisticNoSpeed) =>
              l10n.tbRealisticNoSpeed,
            RealisticTheoreticalBest(unavailableReason: realisticNoJoin) =>
              l10n.tbRealisticNoJoin,
            _ => l10n.tbRealisticIncomplete,
          },
          realistic?.totalSeconds == null
              ? '—'
              : displayTime(realistic!.totalSeconds!),
          const ValueKey('realisticBest'),
        ),
        row(
          l10n.tbRepeatableLabel,
          sections == null
              ? l10n.consistencyMeasuring
              : repeatable == null
              ? l10n.tbRepeatableNeedsLaps(minimumConsistencySamples)
              : l10n.tbRepeatableNote,
          repeatable == null ? '—' : displayTime(repeatable),
          const ValueKey('repeatableBest'),
        ),
      ],
    );
  }
}

class _LossLegend extends StatelessWidget {
  const _LossLegend({required this.maximum});

  final double maximum;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Text('0\u00a0s', style: style),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(
                colors: [
                  lossColor(0, FetColors.of(context).loss),
                  lossColor(1, FetColors.of(context).loss),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('+${maximum.toStringAsFixed(3)}\u00a0s', style: style),
      ],
    );
  }
}

/// Laps by segments: the lap column stays while the segments scroll
/// sideways on a phone.
class _SectorTable extends StatelessWidget {
  const _SectorTable({
    required this.result,
    required this.selected,
    required this.onSelect,
  });

  final DayTheoreticalBest result;
  final DayLapReference? selected;
  final ValueChanged<DayLapReference> onSelect;

  static const _lapWidth = 112.0, _timeWidth = 80.0, _cellWidth = 64.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final scheme = theme.colorScheme;
    final segments = result.segments;
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = theme.textTheme.labelMedium;
    Widget name(String text, {TextStyle? style}) => TableCellText(
      text,
      style: style ?? theme.textTheme.bodyMedium,
      alignment: Alignment.centerLeft,
      maxLines: 2,
    );
    return StickyTable(
      key: const ValueKey('sectorTable'),
      firstWidth: _lapWidth,
      cellWidths: [_timeWidth, for (final _ in segments) _cellWidth],
      headerHeight: 44,
      header: StickyRow(
        first: name(l10n.tbLapColumn, style: label),
        cells: [
          TableCellText(l10n.tbTimeColumn, style: label),
          // The full name, on two lines: there is no hover to explain a
          // short one.
          for (final segment in segments)
            TableCellText(
              l10n.tbSegmentName(segment.name),
              style: label,
              maxLines: 2,
            ),
        ],
      ),
      rows: [
        for (final lap in result.laps)
          StickyRow(
            key: ValueKey('sectorRow ${lap.lap.displayName}'),
            onTap: () => onSelect(lap.lap.reference),
            color: lap.lap.reference == selected
                ? scheme.secondaryContainer
                : null,
            selected: lap.lap.reference == selected,
            semanticsLabel: [
              _markBest(l10n, l10n.lap(lap.lap), lap.bestOfDay),
              l10n.tbCellLabel(
                l10n.tbTimeColumn,
                displayTime(lap.lap.durationSeconds),
              ),
              for (var i = 0; i < segments.length; ++i)
                l10n.tbCellLabel(
                  l10n.tbSegmentName(segments[i].name),
                  _fastest(lap, i)
                      ? l10n.tbFastestCell(lap.seconds(i)!.toStringAsFixed(3))
                      : lap.seconds(i)?.toStringAsFixed(3) ?? '—',
                ),
            ].join('; '),
            first: name(_markBest(l10n, l10n.lap(lap.lap), lap.bestOfDay)),
            cells: [
              TableCellText(
                displayTime(lap.lap.durationSeconds),
                style: numbers,
              ),
              for (var i = 0; i < segments.length; ++i)
                _fastest(lap, i)
                    ? TableCellText(
                        lap.seconds(i)!.toStringAsFixed(3),
                        style: numbers?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                        color: scheme.primaryContainer,
                      )
                    : TableCellText(
                        lap.seconds(i)?.toStringAsFixed(3) ?? '—',
                        style: numbers,
                      ),
            ],
          ),
      ],
      footer: StickyRow(
        semanticsLabel: [
          l10n.tbFastestRow,
          l10n.tbCellLabel(
            l10n.tbTimeColumn,
            result.theoreticalBestSeconds == null
                ? '—'
                : displayTime(result.theoreticalBestSeconds!),
          ),
          for (final segment in segments)
            l10n.tbCellLabel(
              l10n.tbSegmentName(segment.name),
              segment.seconds?.toStringAsFixed(3) ?? '—',
            ),
        ].join('; '),
        first: name(l10n.tbFastestRow, style: label),
        cells: [
          TableCellText(
            result.theoreticalBestSeconds == null
                ? '—'
                : displayTime(result.theoreticalBestSeconds!),
            style: numbers?.copyWith(fontWeight: FontWeight.bold),
          ),
          for (final segment in segments)
            TableCellText(
              segment.seconds?.toStringAsFixed(3) ?? '—',
              style: numbers?.copyWith(fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  // The lap that set the segment's fastest time.
  bool _fastest(DayLapSectors lap, int index) {
    final segment = result.segments[index];
    return segment.seconds != null &&
        segment.sourceLapReference == lap.lap.reference;
  }
}
