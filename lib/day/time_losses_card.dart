import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText, lossColor;
import 'track_map.dart';
import 'touch.dart';

/// Opens lap [a] against lap [b], showing [focus] of lap A first (its
/// recording times) when given; with [segmentId] (a segment of the
/// theoretical best) the Corner Analyzer opens on it, measured against the
/// theoretical best's segments.
typedef CompareLaps = void Function(
  DayLapRow a,
  DayLapRow b,
  (double, double)? focus, {
  String? segmentId,
});

/// [lap]'s recording times from [startMeters] to [endMeters] on the day's
/// shared axis, or null for a stretch across the line or without coverage.
(double, double)? lapStretch(
  DayTheoreticalBest result,
  DayLapRow lap,
  double startMeters,
  double endMeters,
) {
  if (!(endMeters > startMeters)) return null;
  final start = result.timeAt(lap, startMeters);
  final end = result.timeAt(lap, endMeters);
  return start == null || end == null || !(end > start) ? null : (start, end);
}

final _english = lookupAppLocalizations(const Locale('en'));

/// Readable text for why a time-loss list is unavailable, in English.
String timeLossReasonText(String reason) => _english.timeLossReason(reason);

/// "Straight 2 · after Corner 1" for a straight right after a corner, in
/// English.
String timeLossWindowName(PublishedTimeLoss loss) =>
    _english.timeLossWindow(loss);

final _lapLabel = RegExp(r'^(.+) · LAP (\d{1,9})$');

extension TimeLossText on AppLocalizations {
  /// A segment name proposed by `telemetry_core` ("Corner 1", "Straight 2",
  /// "Corners 3–5") in the app's language; a name the user gave is shown
  /// as written.
  String timeLossSegment(String name) => tbSegmentName(name);

  /// A lap label written by the day's analysis ("Session 3 · LAP 2") in the
  /// app's language; any other label is shown as written.
  String timeLossLapLabel(String label) {
    final match = _lapLabel.firstMatch(label);
    return match == null
        ? label
        : lapName(session(match.group(1)!), int.parse(match.group(2)!));
  }

  /// Why a time-loss list is unavailable; a reason the app does not know is
  /// shown as written.
  String timeLossReason(String reason) => switch (reason) {
    timeLossNoReference => timeLossReasonNoReference,
    timeLossBestLapUntimedMessage => timeLossReasonBestLapUntimed,
    _ => reason,
  };

  /// "Straight 2 · after Corner 1" for a straight right after a corner.
  String timeLossWindow(PublishedTimeLoss loss) {
    final name = timeLossSegment(loss.window.name);
    if (loss.window.role != timeLossRoleContinuation) return name;
    return loss.cornerName.isEmpty
        ? timeLossSegmentAfterTheCorner(name)
        : timeLossSegmentAfterCorner(name, timeLossSegment(loss.cornerName));
  }
}

String _lapName(
  AppLocalizations l10n,
  DayTheoreticalBest result,
  Object? reference,
) {
  for (final lap in result.laps) {
    if (lap.lap.reference == reference) return l10n.lap(lap.lap);
  }
  return l10n.timeLossLapUnavailable;
}

/// The day's largest observed time losses (Overlays' "Largest time
/// losses"): each session's best lap, or every lap, against the best lap,
/// one segment at a time, largest first. Tapping one opens its comparison.
class TimeLossesCard extends StatefulWidget {
  const TimeLossesCard({
    super.key,
    required this.result,
    this.loading = false,
    this.path,
    this.gate,
    this.wide = false,
    this.onOpenLap,
    this.onCompare,
  });

  /// Null while the theoretical best is calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;

  /// The best lap's trace, for the comparison's map.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;

  /// Opens a lap from a comparison; no button when null.
  final void Function(DayLapRow lap)? onOpenLap;
  final CompareLaps? onCompare;

  @override
  State<TimeLossesCard> createState() => _TimeLossesCardState();
}

class _TimeLossesCardState extends State<TimeLossesCard> {
  static const _shown = 8;
  // Kept for the page: the list rebuilds the card when it scrolls back.
  late bool _allLaps = readPageState(context, 'timeLossesAllLaps') ?? false;
  late bool _expanded = readPageState(context, 'timeLossesExpanded') ?? false;

  void _remember() {
    writePageState(context, 'timeLossesAllLaps', _allLaps);
    writePageState(context, 'timeLossesExpanded', _expanded);
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
            Text(l10n.timeLossTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (widget.loading || result == null)
              Text(l10n.timeLossLoading)
            else if (result.state != DayTheoreticalBestState.ready) ...[
              Text(l10n.tbDependent(result)),
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
    final summary = result.publishedTimeLosses(allLaps: _allLaps);
    final losses = summary.losses;
    final shown = _expanded ? losses : losses.take(_shown).toList();
    return [
      SegmentedButton<bool>(
        key: const ValueKey('timeLossScope'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: false,
            label: Text(l10n.timeLossScopeSessionBest),
          ),
          ButtonSegment(value: true, label: Text(l10n.timeLossScopeEveryLap)),
        ],
        selected: {_allLaps},
        onSelectionChanged: (selection) => setState(() {
          _allLaps = selection.single;
          _expanded = false;
          _remember();
        }),
      ),
      const SizedBox(height: 8),
      if (!summary.available)
        Text(l10n.timeLossReason(summary.message))
      // Nothing compared is not "no loss": say why, and what shows more.
      else if (summary.comparedLapCount == 0)
        Text(
          !_allLaps &&
                  {for (final lap in result.laps) lap.lap.runId}.length == 1
              ? l10n.timeLossOnlySessionBest
              : l10n.timeLossNoOtherLap,
          key: const ValueKey('timeLossNothingCompared'),
        )
      else ...[
        Text(
          [
            l10n.timeLossAgainst(_lapName(l10n, result, summary.referenceLap)),
            l10n.timeLossLapsCompared(summary.comparedLapCount),
            l10n.timeLossLossesObserved(summary.observationCount),
            if (summary.untimedWindowCount > 0)
              l10n.timeLossUntimedLeftOut(summary.untimedWindowCount),
          ].join(' · '),
          key: const ValueKey('timeLossSummary'),
        ),
        const SizedBox(height: 4),
        Text(l10n.timeLossExplanation, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (losses.isEmpty) Text(l10n.timeLossNone),
        for (var i = 0; i < shown.length; ++i)
          _lossRow(context, result, shown[i], i),
        if (losses.length > _shown && !_expanded)
          TextButton(
            key: const ValueKey('timeLossShowAll'),
            onPressed: () => setState(() {
              _expanded = true;
              _remember();
            }),
            child: Text(l10n.timeLossShowAll(losses.length)),
          ),
      ],
    ];
  }

  Widget _lossRow(
    BuildContext context,
    DayTheoreticalBest result,
    PublishedTimeLoss loss,
    int index,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return ButtonRow(
      child: InkWell(
        key: ValueKey('timeLoss $index'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TimeLossPage(
              result: result,
              loss: loss,
              path: widget.path,
              gate: widget.gate,
              wide: widget.wide,
              onOpenLap: widget.onOpenLap,
              onCompare: widget.onCompare,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wraps rather than cut "after Corner 4" at 360 dp.
                    Text(l10n.timeLossWindow(loss)),
                    Text(
                      _lapName(l10n, result, loss.lapReference),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                displayDelta(loss.lossSeconds),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// One time loss opened: the two laps' times through its segment and the
/// segment on the map.
class TimeLossPage extends StatefulWidget {
  const TimeLossPage({
    super.key,
    required this.result,
    required this.loss,
    this.path,
    this.gate,
    this.wide = false,
    this.onOpenLap,
    this.onCompare,
  });

  final DayTheoreticalBest result;
  final PublishedTimeLoss loss;

  /// The best lap's trace.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;
  final void Function(DayLapRow lap)? onOpenLap;
  final CompareLaps? onCompare;

  @override
  State<TimeLossPage> createState() => _TimeLossPageState();
}

class _TimeLossPageState extends State<TimeLossPage> {
  // Whether each fix of the best lap's trace is in the loss's segment.
  late final Map<double, bool> _inSegment = _segmentFixes();

  Map<double, bool> _segmentFixes() {
    final result = widget.result, path = widget.path, best = result.bestLap;
    if (path == null || best == null) return const {};
    final index = result.segments.indexWhere(
      (segment) => segment.segmentId == widget.loss.window.segmentId,
    );
    return {
      for (final segment in path.segments)
        for (final point in segment)
          point.telemetryTime:
              index >= 0 &&
              result.segmentAtTime(best, point.telemetryTime) == index,
    };
  }

  DayLapRow? _lap(Object? reference) {
    for (final lap in widget.result.laps) {
      if (lap.lap.reference == reference) return lap.lap;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final loss = widget.loss;
    final window = loss.window;
    final comparison = widget.result.compareLoss(loss);
    final lap = _lap(loss.lapReference);
    final reference = _lap(comparison?.referenceLap);
    final path = widget.path;
    final highlight = lossColor(1);
    final neutral = theme.colorScheme.outlineVariant;
    String time(double? seconds) =>
        seconds == null ? '—' : displayTime(seconds);
    Widget stat(String label, String value, Key key) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          value,
          key: key,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    final segment = l10n.timeLossSegment(window.name);
    final atStart = window.cumulativeAtStartSeconds,
        atEnd = window.cumulativeAtEndSeconds;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.timeLossWindow(loss))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.timeLossAgainstBestLap(
              lap == null ? l10n.timeLossLapUnavailable : l10n.lap(lap),
              reference == null
                  ? l10n.timeLossUnavailable
                  : l10n.lap(reference),
            ),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              stat(
                l10n.timeLossThisLap,
                time(comparison?.lapSeconds),
                const ValueKey('lossLapTime'),
              ),
              stat(
                l10n.timeLossBestLap,
                time(comparison?.referenceSeconds),
                const ValueKey('lossReferenceTime'),
              ),
              stat(
                l10n.timeLossDifference,
                comparison?.differenceSeconds == null
                    ? '—'
                    : displayDelta(comparison!.differenceSeconds!),
                const ValueKey('lossDifference'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.timeLossThrough(
              segment,
              window.startProgressMeters.round(),
              window.endProgressMeters.round(),
            ),
          ),
          if (atStart != null && atEnd != null)
            Text(
              l10n.timeLossGap(displayDelta(atStart), displayDelta(atEnd)),
              key: const ValueKey('lossGap'),
            ),
          if (loss.loss.coverageLap < 1 || loss.loss.coverageReference < 1)
            Text(l10n.timeLossNoGps, style: theme.textTheme.bodySmall),
          if (path != null && !path.isEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: widget.wide ? 420 : 300,
              child: IgnorePointer(
                child: TrackMap(
                  key: const ValueKey('timeLossMap'),
                  interactive: false,
                  path: path,
                  gate: widget.gate,
                  pointColor: (point) =>
                      _inSegment[point.telemetryTime] ?? false
                      ? highlight
                      : neutral,
                  semanticLabel: l10n.timeLossMapLabel(segment),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(l10n.timeLossDisclaimer, style: theme.textTheme.bodySmall),
          if (widget.onOpenLap != null && lap != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('lossOpenLap'),
                icon: const Icon(Icons.map_outlined),
                label: Text(l10n.timeLossOpenLap(l10n.lap(lap))),
                onPressed: () => widget.onOpenLap!(lap),
              ),
            ),
          if (widget.onCompare != null && lap != null && reference != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('lossCompare'),
                icon: const Icon(Icons.compare_arrows),
                label: Text(l10n.timeLossCompareWith(l10n.lap(reference))),
                onPressed: () => widget.onCompare!(
                  lap,
                  reference,
                  lapStretch(
                    widget.result,
                    lap,
                    window.startProgressMeters,
                    window.endProgressMeters,
                  ),
                  segmentId: window.segmentId,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
