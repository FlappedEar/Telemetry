import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../ui/theme.dart';
import 'corner_details.dart' show cornerPhaseReasonText;
import 'theoretical_best_card.dart' show TheoreticalBestText;
import 'touch.dart';

/// [metresPerSecond] as a speed difference in [unit], the unit every lap's
/// speed declares; in m/s when they declare none or different ones, so a
/// unit is never put on a number it was not measured in.
String phaseSpeedText(double metresPerSecond, String unit) {
  final factor = unit.isEmpty ? null : metresPerSecondPerSpeedUnit(unit);
  if (factor == null) return '${fixed(metresPerSecond, 1)}${unitSpace}m/s';
  return '${fixed(metresPerSecond / factor, 1)}$unitSpace$unit';
}

extension BestPhasesText on AppLocalizations {
  /// A part of a corner, or "Whole" for a segment taken whole.
  String phasePart(PhasePart part) => switch (part) {
    PhasePart.entry => cornerPhaseEntry,
    PhasePart.middle => cornerPhaseMiddle,
    PhasePart.exit => cornerPhaseExit,
    PhasePart.whole => bpWhole,
  };

  /// A piece by its segment's name, with its part when it is one:
  /// "Corner 4 · Entry", "Straight 2".
  String phasePieceName(PhasePiece piece) => piece.part == PhasePart.whole
      ? tbSegmentName(piece.name)
      : '${tbSegmentName(piece.name)} · ${phasePart(piece.part)}';
}

/// The best phases of the day (FET-226): every corner's best entry, middle
/// and exit and every other segment's fastest time, from the shown group's
/// ranked laps, as a target; what one lap loses against it, part by part;
/// how it relates to the theoretical bests; and where its parts, taken from
/// different laps, do not join. It comes with the theoretical best, worked
/// out in the same background job.
///
/// It is not offered as a reference in the lap comparison: it is pieces of
/// several laps, not one recording, so a Δ trace against it would join
/// traces the car never drove. Part by part is the honest view.
class BestPhasesCard extends StatefulWidget {
  const BestPhasesCard({
    super.key,
    required this.result,
    this.loading = false,
    this.sections,
  });

  /// Null while it is calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;

  /// Each session's segment times, for the best typical lap; null while
  /// they are worked out.
  final SectionProgression? sections;

  @override
  State<BestPhasesCard> createState() => _BestPhasesCardState();
}

class _BestPhasesCardState extends State<BestPhasesCard> {
  // Kept for the page: the list rebuilds the card when it scrolls back.
  late bool _open = readPageState<bool>(context, _openStorage) ?? false;
  late DayLapReference? _selected = readPageState(context, _lapStorage);
  static const _openStorage = 'bestPhasesOpen', _lapStorage = 'bestPhasesLap';

  void _toggle() {
    setState(() => _open = !_open);
    writePageState(context, _openStorage, _open);
  }

  void _choose(DayLapReference? reference) {
    setState(() => _selected = reference);
    writePageState(context, _lapStorage, reference);
  }

  // The chosen lap, or the best lap.
  DayLapSectors? _lap(DayTheoreticalBest result) {
    DayLapSectors? best;
    for (final lap in result.laps) {
      if (lap.lap.reference == _selected) return lap;
      if (lap.bestOfDay) best = lap;
    }
    return best ?? (result.laps.isEmpty ? null : result.laps.first);
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
    final phases = result?.bestPhases;
    final ready =
        !widget.loading &&
        result != null &&
        result.state == DayTheoreticalBestState.ready &&
        phases != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.bpHeading,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                TextButton(
                  key: const ValueKey('bestPhasesToggle'),
                  onPressed: _toggle,
                  child: Text(_open ? l10n.gripHide : l10n.gripShow),
                ),
              ],
            ),
            // Closed, the long day page keeps one line for it.
            Text(
              ready && phases.totalSeconds != null
                  ? l10n.bpSummaryTime(displayTime(phases.totalSeconds!))
                  : l10n.bpSummary,
              key: const ValueKey('bestPhasesSummary'),
              style: theme.textTheme.bodySmall,
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              if (widget.loading || result == null)
                Text(l10n.bpWorking, key: const ValueKey('bestPhasesWorking'))
              else if (!ready)
                Text(
                  l10n.bpUnavailable(l10n.tbDependent(result)),
                  key: const ValueKey('bestPhasesUnavailable'),
                )
              else
                ..._ready(context, result, phases),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _ready(
    BuildContext context,
    DayTheoreticalBest result,
    PhaseReference phases,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final lap = _lap(result);
    return [
      Text(l10n.bpIntro, style: theme.textTheme.bodySmall),
      if (!phases.valid) ...[
        const SizedBox(height: 8),
        Text(l10n.bpIncomplete, key: const ValueKey('bestPhasesIncomplete')),
      ],
      const SizedBox(height: 12),
      if (lap != null) _Headline(phases: phases, lap: lap),
      const SizedBox(height: 16),
      _Bests(result: result, phases: phases, sections: widget.sections),
      const SizedBox(height: 16),
      ..._joins(context, result, phases),
      if (lap != null) ...[
        const SizedBox(height: 16),
        Text(l10n.bpByPart, style: theme.textTheme.titleSmall),
        DropdownButton<DayLapReference>(
          key: const ValueKey('bestPhasesLap'),
          isExpanded: true,
          value: lap.lap.reference,
          items: [
            for (final candidate in result.laps)
              DropdownMenuItem(
                value: candidate.lap.reference,
                child: Text(
                  '${candidate.bestOfDay ? l10n.tbMarkedBest(l10n.lap(candidate.lap)) : l10n.lap(candidate.lap)}'
                  ' · ${displayTime(candidate.lap.durationSeconds)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _choose,
        ),
        ..._segments(context, result, phases, lap),
      ],
      const SizedBox(height: 12),
      Text(
        l10n.bpPiecesNote,
        key: const ValueKey('bestPhasesPiecesNote'),
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  // Where two laps meet and their speeds do not match.
  List<Widget> _joins(
    BuildContext context,
    DayTheoreticalBest result,
    PhaseReference phases,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tolerance = phaseSpeedText(
      realisticJoinMetresPerSecond,
      phases.speedUnit,
    );
    final apart = phases.joinsOf(PhaseJoin.apart);
    final joining = phases.joinsOf(PhaseJoin.joins);
    final unknown = phases.joinsOf(PhaseJoin.unknown);
    final checked = apart.length + joining.length;
    String before(PhaseReferencePiece piece) {
      final index = phases.pieces.indexOf(piece);
      return l10n.phasePieceName(
        phases.pieces[index == 0 ? phases.pieces.length - 1 : index - 1].piece,
      );
    }

    return [
      Text(l10n.bpJoinsTitle, style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        checked == 0 && unknown.isEmpty
            ? l10n.bpJoinsNone
            : apart.isEmpty
            ? l10n.bpJoinsAll(checked, tolerance)
            : l10n.bpJoinsApart(apart.length, checked, tolerance),
        key: const ValueKey('bestPhasesJoins'),
      ),
      for (final piece in apart)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 8),
          child: Text(
            l10n.bpJoinApart(
              '${before(piece)} → ${l10n.phasePieceName(piece.piece)}',
              phaseSpeedText(piece.joinMetresPerSecond!, phases.speedUnit),
            ),
            key: ValueKey('bestPhasesApart ${phases.pieces.indexOf(piece)}'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      if (unknown.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.bpJoinsUnknown(unknown.length),
            key: const ValueKey('bestPhasesJoinsUnknown'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(l10n.bpJoinsNote, style: theme.textTheme.bodySmall),
      ),
    ];
  }

  // Each segment in lap order: its parts (or itself whole), the lap each
  // best came from, and what the chosen lap loses there.
  List<Widget> _segments(
    BuildContext context,
    DayTheoreticalBest result,
    PhaseReference phases,
    DayLapSectors lap,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final losses = phases.lossesOf(lap.lap.reference);
    final own = phases.lapSeconds[lap.lap.reference];
    final groups = <int, List<int>>{};
    for (final (i, piece) in phases.pieces.indexed) {
      (groups[piece.piece.segmentIndex] ??= []).add(i);
    }
    final numbers = theme.textTheme.titleSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // With very large text a loss goes under its name, so rows fit a phone.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    Widget line(
      String label,
      String value, {
      Key? key,
      TextStyle? style,
      List<Widget> below = const [],
    }) {
      final shown = Text(
        value,
        style: style ?? numbers,
        textAlign: TextAlign.end,
      );
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(label), if (stacked) shown, ...below],
              ),
            ),
            if (!stacked) ...[const SizedBox(width: 8), shown],
          ],
        ),
      );
    }

    String loss(double? value) => value == null ? '—' : displayDelta(value);
    final widgets = <Widget>[];
    for (final MapEntry(key: segment, value: indices) in groups.entries) {
      final first = phases.pieces[indices.first].piece;
      final segmentLosses = [
        for (final i in indices) losses.isEmpty ? null : losses[i],
      ];
      final total = segmentLosses.contains(null)
          ? null
          : segmentLosses.fold(0.0, (sum, value) => sum + value!);
      final whole = first.part == PhasePart.whole;
      // A piece's best, the lap it came from, the chosen lap's own time,
      // and whether it joins the piece before.
      List<Widget> about(int i) {
        final piece = phases.pieces[i];
        final seconds = piece.seconds;
        final mine = own == null ? null : own[i];
        final source = seconds == null
            ? l10n.bpNoTime
            : l10n.bpBest(
                fixed(seconds, 3),
                _lapName(l10n, result, piece.lapReference),
              );
        final yours = mine == null
            ? l10n.bpLapNotTimed
            : piece.lapReference == lap.lap.reference
            ? l10n.bpLapSetIt
            : l10n.bpLapTime(fixed(mine, 3));
        return [
          Text(
            '$source · $yours',
            key: ValueKey('bestPhasesSource $i'),
            style: theme.textTheme.bodySmall,
          ),
          if (piece.join == PhaseJoin.apart)
            Text(
              l10n.bpDoesNotJoin(
                phaseSpeedText(piece.joinMetresPerSecond!, phases.speedUnit),
              ),
              key: ValueKey('bestPhasesPieceApart $i'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: FetColors.of(context).loss,
              ),
            ),
        ];
      }

      widgets.add(
        Padding(
          key: ValueKey('bestPhasesSegment $segment'),
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(
                l10n.tbSegmentName(first.name),
                loss(total),
                key: ValueKey('bestPhasesSegmentLoss $segment'),
                below: [
                  if (first.corner && whole)
                    Text(
                      l10n.cornerPhasesUnavailable(
                        cornerPhaseReasonText(l10n, first.splitReason),
                      ),
                      key: ValueKey('bestPhasesNotSplit $segment'),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (whole) ...about(indices.single),
                ],
              ),
              if (!whole)
                for (final i in indices)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: line(
                      l10n.phasePart(phases.pieces[i].piece.part),
                      loss(losses.isEmpty ? null : losses[i]),
                      key: ValueKey('bestPhasesPiece $i'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      below: about(i),
                    ),
                  ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }
}

/// The best phases' time, the chosen lap's time over the same pieces, and
/// what it loses.
class _Headline extends StatelessWidget {
  const _Headline({required this.phases, required this.lap});

  final PhaseReference phases;
  final DayLapSectors lap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final total = phases.totalSeconds;
    final own = phases.lapTotal(lap.lap.reference);
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
          l10n.bpHeading,
          total == null ? '—' : displayTime(total),
          const ValueKey('bestPhasesTime'),
          FetColors.of(context).reference,
        ),
        stat(
          l10n.lap(lap.lap),
          own == null ? '—' : displayTime(own),
          const ValueKey('bestPhasesLapTime'),
        ),
        stat(
          l10n.bpLoses,
          total == null || own == null ? '—' : displayDelta(own - total),
          const ValueKey('bestPhasesLoss'),
        ),
      ],
    );
  }
}

/// The best phases next to the theoretical bests: the same idea as the
/// fastest segments and segments that join at a finer grain, and a
/// different one from the best typical.
class _Bests extends StatelessWidget {
  const _Bests({required this.result, required this.phases, this.sections});

  final DayTheoreticalBest result;
  final PhaseReference phases;
  final SectionProgression? sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sections = this.sections;
    final typical = sections == null
        ? null
        : repeatableTheoreticalBest(sections);
    final realistic = result.realistic?.totalSeconds;
    String time(double? seconds) =>
        seconds == null ? '—' : displayTime(seconds);
    Widget row(String key, String label, String note, String value) => Padding(
      key: ValueKey(key),
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
            key: ValueKey('$key value'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.bpBestsTitle, style: theme.textTheme.titleSmall),
        row(
          'bestPhasesTotal',
          l10n.bpHeading,
          phases.valid ? l10n.bpTotalNote(phases.lapCount) : l10n.bpIncomplete,
          time(phases.totalSeconds),
        ),
        row(
          'bestPhasesRaw',
          l10n.tbRawLabel,
          l10n.bpRawNote,
          time(result.theoreticalBestSeconds),
        ),
        row(
          'bestPhasesJoined',
          l10n.bpJoinedLabel,
          switch (phases.joinedUnavailableReason) {
            '' when phases.joinedSeconds != null => l10n.bpJoinedNote(
              phaseSpeedText(realisticJoinMetresPerSecond, phases.speedUnit),
              phases.joinedLapCount,
            ),
            phaseReferenceNoSpeed => l10n.tbRealisticNoSpeed,
            phaseReferenceNoJoin => l10n.bpJoinedNoJoin,
            _ => l10n.bpIncomplete,
          },
          time(phases.joinedSeconds),
        ),
        row(
          'bestPhasesRealistic',
          l10n.tbRealisticLabel,
          l10n.bpRealisticNote,
          time(realistic),
        ),
        row(
          'bestPhasesTypical',
          l10n.tbRepeatableLabel,
          sections == null
              ? l10n.consistencyMeasuring
              : typical == null
              ? l10n.tbRepeatableNeedsLaps(minimumConsistencySamples)
              : l10n.bpTypicalNote,
          time(typical),
        ),
      ],
    );
  }
}
