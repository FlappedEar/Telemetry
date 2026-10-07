import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import '../units.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText;

extension GripText on AppLocalizations {
  /// Why a grip figure is not known, as a short phrase. Every reason the
  /// core gives is mapped; an unknown one reads "not available".
  String gripReason(String reason) => switch (reason) {
    gripTooFewLaps => gripReasonTooFewLaps(gripMinimumTypicalLaps),
    gripTooFewSamples => gripReasonTooFewSamples,
    gripNoLateralChannel => gripReasonNoLateral,
    gripNoSpeedChannel => gripReasonNoSpeed,
    gripUnsupportedUnit => gripReasonUnsupportedUnit,
    gripSpeedUnitNotSupported => gripReasonSpeedUnit,
    gripNoYawChannel => gripReasonNoYaw,
    gripDeviceAxesOnly => gripReasonDeviceAxes,
    gripYawUnitUnknown => gripReasonYawUnit,
    gripNotTimed => gripReasonNotTimed,
    gripNoMinimumSpeed => gripReasonNoMinimum,
    gripNoBraking => gripReasonNoBraking,
    gripNoAcceleration => gripReasonNoAcceleration,
    gripAllZero => gripReasonAllZero,
    gripNoRecording => gripReasonNoRecording,
    _ => gripReasonOther,
  };
}

/// "0.72", "−0.05": two decimals with a real minus sign.
String gripNumber(double value) {
  final text = fixed(value.abs(), 2);
  return value < 0 && double.parse(text) != 0 ? '−$text' : text;
}

/// [value] with [source]'s unit as the recording declares it. An assumed g
/// says so; a value from the speed's change says so, and that km/h was
/// assumed for a speed without a unit.
String gripValueText(AppLocalizations l10n, double value, GripSource source) {
  final text = '${gripNumber(value)}\u00a0${source.unit}';
  if (source.fromSpeed) {
    return source.unitAssumed
        ? l10n.gripFromSpeedValueAssumed(text)
        : l10n.gripFromSpeedValue(text);
  }
  return source.unitAssumed ? l10n.gripAssumedUnit(text) : text;
}

/// A balance ratio, saying when a unit it was worked out from is assumed.
String gripBalanceText(AppLocalizations l10n, GripFigure figure) {
  final text = l10n.gripBalanceTypical(gripNumber(figure.typical!));
  return figure.source.unitAssumed ? l10n.gripBalanceUnitsAssumed(text) : text;
}

/// Grip and balance proxies of the shown group's ranked laps (FET-229): per
/// session in speed bands and per corner of the day, all inferred and
/// labelled so. They come with the theoretical best, worked out in the same
/// background job.
class GripProxiesCard extends StatefulWidget {
  const GripProxiesCard({
    super.key,
    required this.result,
    this.loading = false,
  });

  /// Null while it is calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;

  @override
  State<GripProxiesCard> createState() => _GripProxiesCardState();
}

class _GripProxiesCardState extends State<GripProxiesCard> {
  String? _runId;

  /// Shown in full; closed at first, as the day page is long.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = widget.result;
    final grip = result?.grip;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(l10n.gripHeading, style: theme.textTheme.labelLarge),
                      Container(
                        key: const ValueKey('gripInferred'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.gripInferredBadge,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('gripToggle'),
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? l10n.gripHide : l10n.gripShow),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Closed, the long day page keeps one line for it.
            Text(
              _open ? l10n.gripIntro(gripMinimumTypicalLaps) : l10n.gripSummary,
              style: theme.textTheme.bodySmall,
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              if (widget.loading || result == null)
                Text(l10n.gripWorking, key: const ValueKey('gripWorking'))
              else if (result.state != DayTheoreticalBestState.ready ||
                  grip == null)
                Text(
                  l10n.gripUnavailable,
                  key: const ValueKey('gripUnavailable'),
                )
              else ...[
                ..._sessions(context, grip),
                const SizedBox(height: 16),
                ..._corners(context, grip),
                const SizedBox(height: 16),
                Text(
                  l10n.gripMeaningHeading,
                  style: theme.textTheme.titleSmall,
                ),
                for (final text in [
                  l10n.gripMeaningCornering,
                  l10n.gripMeaningBraking,
                  l10n.gripMeaningExit,
                  l10n.gripMeaningBalance(
                    fixed(gripBalanceMinimumLateralG, 1),
                    fixed(gripBalanceMinimumSpeedMetresPerSecond, 0),
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(text, style: theme.textTheme.bodySmall),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _sessions(BuildContext context, DayGripProxies grip) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    if (grip.sessions.isEmpty) return const [];
    final session = grip.sessions.firstWhere(
      (session) => session.runId == _runId,
      orElse: () => grip.sessions.last,
    );
    final small = theme.textTheme.bodySmall;
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    // A speed without a unit gets km/h's edges: the number only, and the
    // band says km/h is assumed.
    String speed(double value, String unit) {
      if (unit.isEmpty) return fixed(value, 0);
      final shown = speedUnitOf(context, unit).trim();
      return shown.isEmpty ? fixed(value, 0) : '${fixed(value, 0)}\u00a0$shown';
    }

    String bandRange(GripBand band) => switch ((band.lower, band.upper)) {
      (null, final upper?) => l10n.gripBandBelow(speed(upper, band.speedUnit)),
      (final lower?, null) => l10n.gripBandAbove(speed(lower, band.speedUnit)),
      (final lower?, final upper?) => l10n.gripBandBetween(
        fixed(lower, 0),
        speed(upper, band.speedUnit),
      ),
      _ => '',
    };

    String bandName(GripBand band) {
      final name = bandRange(band);
      return band.speedUnitAssumed ? l10n.gripBandSpeedAssumed(name) : name;
    }

    Widget cell(GripFigure figure, String key) => Expanded(
      child: Column(
        key: ValueKey(key),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            figure.typical == null ? '—' : gripNumber(figure.typical!),
            style: numbers,
            textAlign: TextAlign.end,
          ),
          if (figure.peak != null)
            Text(
              l10n.gripPeak(gripNumber(figure.peak!)),
              style: small,
              textAlign: TextAlign.end,
            ),
        ],
      ),
    );

    final columns = [
      (l10n.gripCornering, (GripBand band) => band.lateral),
      (l10n.gripBraking, (GripBand band) => band.braking),
      (l10n.gripAccelerating, (GripBand band) => band.accelerating),
    ];
    final notes = <String>[];
    if (session.bands.isEmpty) {
      notes.add(
        l10n.gripNotKnownLine(
          l10n.gripBySession,
          l10n.gripReason(session.bandsReason),
        ),
      );
    } else {
      // Each column's unit once: its source is the session's own channel.
      final units = <String>[];
      final longitudinal = [
        for (final band in session.bands) ...[band.braking, band.accelerating],
      ].where((figure) => figure.known).map((figure) => figure.source);
      final lateral = session.bands
          .map((band) => band.lateral)
          .where((figure) => figure.known)
          .map((figure) => figure.source);
      void unitNote(String what, Iterable<GripSource> sources) {
        if (sources.isEmpty) return;
        final source = sources.first;
        units.add(
          source.fromSpeed
              ? source.unitAssumed
                    ? l10n.gripFromSpeedAssumedNote(what)
                    : l10n.gripFromSpeedNote(what)
              : source.unitAssumed
              ? l10n.gripAssumedNote(what)
              : l10n.gripUnitNote(what, source.unit),
        );
      }

      unitNote(l10n.gripCornering, lateral);
      unitNote(
        l10n.gripAnd(l10n.gripBraking, l10n.gripAccelerating.toLowerCase()),
        longitudinal,
      );
      notes.addAll(units);
      var fewLaps = false;
      for (final band in session.bands) {
        final byReason = <String, List<String>>{};
        for (final (name, read) in columns) {
          final figure = read(band);
          if (!figure.known) {
            byReason.putIfAbsent(figure.reason, () => []).add(name);
          } else if (figure.typical == null) {
            fewLaps = true;
          }
        }
        for (final MapEntry(key: reason, value: names) in byReason.entries) {
          notes.add(
            l10n.gripNotKnownLine(
              '${names.join(', ')} · ${bandName(band)}',
              l10n.gripReason(reason),
            ),
          );
        }
      }
      if (fewLaps) notes.add(l10n.gripTypicalNeedsLaps(gripMinimumTypicalLaps));
    }
    final balance = session.balance;
    notes.add(
      balance.typical != null
          ? '${l10n.gripBalance}: ${gripBalanceText(l10n, balance)}'
          : l10n.gripNotKnownLine(
              l10n.gripBalance,
              l10n.gripReason(
                balance.known ? balance.typicalReason : balance.reason,
              ),
            ),
    );

    return [
      Text(l10n.gripBySession, style: theme.textTheme.titleSmall),
      if (grip.sessions.length > 1)
        DropdownButton<String>(
          key: const ValueKey('gripSession'),
          isExpanded: true,
          value: session.runId,
          items: [
            for (final candidate in grip.sessions)
              DropdownMenuItem(
                value: candidate.runId,
                child: Text(
                  l10n.gripSessionLaps(
                    l10n.session(candidate.runName),
                    candidate.lapCount,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => setState(() => _runId = id),
        )
      else
        Text(
          l10n.gripSessionLaps(l10n.session(session.runName), session.lapCount),
        ),
      if (session.bands.isNotEmpty) ...[
        const SizedBox(height: 8),
        DefaultTextStyle.merge(
          style: theme.textTheme.labelMedium,
          child: Row(
            children: [
              Expanded(child: Text(l10n.gripSpeedColumn)),
              for (final (name, _) in columns)
                Expanded(child: Text(name, textAlign: TextAlign.end)),
            ],
          ),
        ),
        for (final (index, band) in session.bands.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(bandName(band))),
                cell(band.lateral, 'gripLateral $index'),
                cell(band.braking, 'gripBraking $index'),
                cell(band.accelerating, 'gripAccelerating $index'),
              ],
            ),
          ),
        Text(l10n.gripTableNote, style: small),
      ],
      for (final note in notes)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(note, style: small),
        ),
    ];
  }

  List<Widget> _corners(BuildContext context, DayGripProxies grip) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    if (grip.corners.isEmpty) return const [];

    // A known figure's typical value, peak and laps.
    String detail(GripFigure figure, {bool balance = false}) {
      if (balance) {
        return [
          gripBalanceText(l10n, figure),
          l10n.gripLapCount(figure.lapCount),
          if (figure.unmeasured > 0) l10n.gripNoValueLaps(figure.unmeasured),
        ].join(' · ');
      }
      final peak = gripValueText(l10n, figure.peak!, figure.source);
      final lap = figure.peakLap == null ? '—' : l10n.lap(figure.peakLap!);
      final parts = [
        if (figure.typical != null)
          l10n.gripTypicalPeak(
            gripValueText(l10n, figure.typical!, figure.source),
            peak,
            lap,
          )
        else
          l10n.gripPeakOnly(peak, lap, gripMinimumTypicalLaps),
        l10n.gripLapCount(figure.lapCount),
        if (figure.leftOut > 0) l10n.gripLeftOut(figure.leftOut),
        if (figure.unmeasured > 0) l10n.gripNoValueLaps(figure.unmeasured),
      ];
      return parts.join(' · ');
    }

    String summary(GripCorner corner) => [
      for (final (name, figure) in [
        (l10n.gripCornering, corner.lateral),
        (l10n.gripBraking, corner.braking),
        (l10n.gripExit, corner.traction),
      ])
        if (figure.typical case final typical?)
          l10n.gripCornerSummary(
            name,
            gripValueText(l10n, typical, figure.source),
          )
        else if (figure.peak case final peak?)
          l10n.gripCornerSummaryPeak(
            name,
            gripValueText(l10n, peak, figure.source),
          ),
    ].join(' · ');

    return [
      Text(l10n.gripByCorner, style: theme.textTheme.titleSmall),
      for (final corner in grip.corners)
        Theme(
          // No dividers above and below each corner when it opens.
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('gripCorner ${corner.name}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(l10n.tbSegmentName(corner.name)),
            subtitle: Text(summary(corner), style: theme.textTheme.bodySmall),
            children: [
              for (final (name, figure, balance) in [
                (l10n.gripCornering, corner.lateral, false),
                (l10n.gripBraking, corner.braking, false),
                (l10n.gripExit, corner.traction, false),
                (l10n.gripBalance, corner.balance, true),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    !figure.known
                        ? l10n.gripNotKnownLine(
                            name,
                            l10n.gripReason(figure.reason),
                          )
                        : balance && figure.typical == null
                        ? l10n.gripNotKnownLine(
                            name,
                            l10n.gripReason(figure.typicalReason),
                          )
                        : '$name: ${detail(figure, balance: balance)}',
                  ),
                ),
            ],
          ),
        ),
    ];
  }
}
