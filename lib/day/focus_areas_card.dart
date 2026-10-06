import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'touch.dart';
import '../ui/theme.dart';
import '../units.dart';
import 'corner_details.dart' show lapAColor, lapBColor;
import 'theoretical_best_card.dart' show TheoreticalBestText;
import 'time_losses_card.dart' show CompareLaps, TimeLossText, lapStretch;
import 'track_map.dart';
import '../ui/readable_list.dart';

final _english = lookupAppLocalizations(const Locale('en'));

/// The heading of a focus area's kind, in English.
String focusKindText(FocusAreaKind kind) => _english.focusAreaKind(kind);

typedef _FocusTexts = ({String observation, String hypothesis});

extension FocusAreaText on AppLocalizations {
  /// The heading of a focus area's kind.
  String focusAreaKind(FocusAreaKind kind) => switch (kind) {
    FocusAreaKind.sectorGap => focusKindSectorGap,
    FocusAreaKind.repeatedLoss => focusKindRepeatedLoss,
    FocusAreaKind.brakingSpread => focusKindBrakingSpread,
    FocusAreaKind.minimumSpeedSpread => focusKindMinimumSpeedSpread,
  };

  /// What [area] measured, in the app's language; as written by
  /// `telemetry_core` when the app does not recognise the text.
  String focusAreaObservation(FocusArea area) =>
      _focusTexts(this, area)?.observation ?? area.observation;

  /// What [area] suggests checking, in the app's language; as written by
  /// `telemetry_core` when the app does not recognise the text.
  String focusAreaHypothesis(FocusArea area) =>
      _focusTexts(this, area)?.hypothesis ?? area.hypothesis;
}

// [area]'s observation and hypothesis in [l10n]'s language, rebuilt from the
// numbers and names in the English texts of `telemetry_core`. Null when the
// texts are not the ones this app knows: the English rebuilt from the same
// parts must equal them.
_FocusTexts? _focusTexts(AppLocalizations l10n, FocusArea area) {
  final texts = _focusTextsIn(l10n, area, translate: true);
  final english = _focusTextsIn(_english, area, translate: false);
  if (texts == null ||
      english == null ||
      // The app keeps a unit with its number by a no-break space; the core
      // writes a plain one.
      _plain(english.observation) != area.observation ||
      _plain(english.hypothesis) != area.hypothesis) {
    return null;
  }
  return texts;
}

String _plain(String text) => text.replaceAll(unitSpace, ' ');

_FocusTexts? _focusTextsIn(
  AppLocalizations l10n,
  FocusArea area, {
  required bool translate,
}) {
  final name = RegExp.escape(area.name);
  final segment = translate ? l10n.timeLossSegment(area.name) : area.name;
  String lap(String label) => translate ? l10n.timeLossLapLabel(label) : label;
  RegExpMatch? match(String pattern) =>
      RegExp(pattern).firstMatch(area.observation);
  switch (area.kind) {
    case FocusAreaKind.sectorGap:
      final m = match(
        r'^Your best lap \((.*)\) was (\S+) s slower through '
        '$name'
        r' than (.*), the fastest recorded there\.$',
      );
      if (m == null) return null;
      return (
        observation: l10n.focusObservationSectorGap(
          lap(m[1]!),
          m[2]!,
          segment,
          lap(m[3]!),
        ),
        hypothesis: l10n.focusHypothesisSectorGap(segment),
      );
    case FocusAreaKind.repeatedLoss:
      final m = match(
        r'^In (\d+) of (\d+) compared laps you lost time through '
        '$name'
        r' against (.*) \(median (\S+) s\)\.$',
      );
      if (m == null) return null;
      final reference = lap(m[3]!);
      return (
        observation: l10n.focusObservationRepeatedLoss(
          m[1]!,
          m[2]!,
          segment,
          reference,
          m[4]!,
        ),
        hypothesis: l10n.focusHypothesisRepeatedLoss(reference, segment),
      );
    case FocusAreaKind.brakingSpread:
      final m = match(
        r'^Where braking starts for '
        '$name'
        r' varies by (\S+) m across the middle half of (\d+) laps '
        r'\(measured from the brake signal\)\.$',
      );
      if (m == null) return null;
      return (
        observation: l10n.focusObservationBrakingSpread(segment, m[1]!, m[2]!),
        hypothesis: l10n.focusHypothesisBrakingSpread(segment),
      );
    case FocusAreaKind.minimumSpeedSpread:
      final m = match(
        r'^The lowest speed through '
        '$name'
        r' varies by (\S+?)(| \S.*?) across the middle half of (\d+) laps '
        r"\(median (\S+?)\2\)\.( Speeds are in the recording's own units\.)?$",
      );
      if (m == null) return null;
      final observation = l10n.focusObservationMinimumSpeedSpread(
        segment,
        '${m[1]}${m[2]}',
        m[3]!,
        '${m[4]}${m[2]}',
      );
      return (
        observation: m[5] == null
            ? observation
            : '$observation ${l10n.focusObservationRecordingUnits}',
        hypothesis: l10n.focusHypothesisMinimumSpeedSpread(segment),
      );
  }
}

/// "Earlier visits here" under each focus area, from [profile]'s visits to
/// the track of day [eventId] in its car before it ([cornerBefore]), each
/// track corner worked out once. [spans] are all the day's corners on the
/// ground ([measureCornerSpans]), matched to the track's as adding the day
/// placed them. Null, so no line, when the day is not in [profile], its
/// track is unknown or no corner of the day is on the ground.
String? Function(FocusArea area)? focusBefore(
  AppLocalizations l10n,
  DriverProfile? profile,
  String eventId,
  List<DayCornerSpan> spans,
) {
  final today = profile?.day(eventId);
  final track = today?.trackId == null ? null : profile!.track(today!.trackId!);
  if (profile == null || today == null || track == null || spans.isEmpty) {
    return null;
  }
  final corners = matchTrackCorners(track, spans);
  final texts = <String, String>{};
  String text(String cornerId) {
    final before = cornerBefore(profile, today, cornerId);
    if (before == null) return l10n.focusBeforeNotCorner;
    final name = before.corner.name;
    if (before.visits == 0) return l10n.focusBeforeNone(name);
    if (before.measured == 0) return l10n.focusBeforeNotMeasured(name);
    final last = before.lastLost;
    if (last == null) return l10n.focusBeforeNever(before.measured, name);
    if (before.notOnLastTwo) {
      return l10n.focusBeforeNotLastTwo(before.lost, before.measured, name);
    }
    final start = last.startMilliseconds;
    return l10n.focusBeforeLost(
      before.lost,
      before.measured,
      name,
      start == null
          ? l10n.profileUndated
          : DateFormat.yMMMd().format(
              DateTime.fromMillisecondsSinceEpoch(start),
            ),
    );
  }

  return (area) => switch (corners[area.segmentId]) {
    final cornerId? => texts.putIfAbsent(cornerId, () => text(cornerId)),
    null => l10n.focusBeforeNotCorner,
  };
}

/// Where to look next (Overlays' focus areas): at most three areas selected
/// from measured losses, sector gaps and corner spreads. Each shows what was
/// measured apart from a hypothesis to check; neither is a cause or an
/// instruction. Tapping an area compares its two laps.
class FocusAreasCard extends StatelessWidget {
  const FocusAreasCard({
    super.key,
    required this.result,
    required this.areas,
    required this.lapLabel,
    this.loading = false,
    this.path,
    this.gate,
    this.wide = false,
    this.onOpenLap,
    this.onCompare,
    this.before,
  });

  /// Null while the theoretical best is calculated for the first time.
  final DayTheoreticalBest? result;
  final List<FocusArea> areas;
  final String Function(Object? reference) lapLabel;
  final bool loading;

  /// What earlier visits say about an area ([focusBefore]); null for none.
  final String? Function(FocusArea area)? before;

  /// The best lap's trace, for the comparison's map.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;
  final void Function(DayLapRow lap)? onOpenLap;
  final CompareLaps? onCompare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = this.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.focusTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (loading || result == null)
              Text(l10n.focusLoading)
            else if (result.state != DayTheoreticalBestState.ready)
              Text(l10n.tbDependent(result))
            else if (result.computed?.actualBest == null)
              Text(l10n.timeLossReasonBestLapUntimed)
            else if (areas.isEmpty)
              Text(l10n.focusNone, key: const ValueKey('focusAreasNone'))
            else ...[
              Text(l10n.focusIntro, style: theme.textTheme.bodySmall),
              for (var i = 0; i < areas.length; ++i)
                _area(context, result, areas[i], i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _area(
    BuildContext context,
    DayTheoreticalBest result,
    FocusArea area,
    int index,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final before = this.before?.call(area);
    return ButtonRow(
      child: InkWell(
        key: ValueKey('focusArea $index'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FocusAreaPage(
              result: result,
              area: area,
              lapLabel: lapLabel,
              path: path,
              gate: gate,
              wide: wide,
              onOpenLap: onOpenLap,
              onCompare: onCompare,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.focusAreaKind(area.kind)} · '
                      '${l10n.timeLossSegment(area.name)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(l10n.focusObserved(l10n.focusAreaObservation(area))),
                    const SizedBox(height: 2),
                    Text(
                      l10n.focusHypothesis(l10n.focusAreaHypothesis(area)),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (before != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        before,
                        key: ValueKey('focusBefore $index'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      l10n.focusCompareLaps(
                        _label(l10n, area.lap),
                        _label(l10n, area.against),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  String _label(AppLocalizations l10n, Object? reference) {
    final label = lapLabel(reference);
    return label.isEmpty
        ? l10n.focusLapUnavailable
        : l10n.timeLossLapLabel(label);
  }
}

/// One focus area opened: the two laps through its segment, what was
/// measured on each and the segment on the map.
class FocusAreaPage extends StatefulWidget {
  const FocusAreaPage({
    super.key,
    required this.result,
    required this.area,
    required this.lapLabel,
    this.path,
    this.gate,
    this.wide = false,
    this.onOpenLap,
    this.onCompare,
  });

  final DayTheoreticalBest result;
  final FocusArea area;
  final String Function(Object? reference) lapLabel;

  /// The best lap's trace.
  final LapPath? path;
  final (Offset, Offset)? gate;
  final bool wide;
  final void Function(DayLapRow lap)? onOpenLap;
  final CompareLaps? onCompare;

  @override
  State<FocusAreaPage> createState() => _FocusAreaPageState();
}

class _FocusAreaPageState extends State<FocusAreaPage> {
  late final int _segment = widget.result.segments.indexWhere(
    (segment) => segment.segmentId == widget.area.segmentId,
  );

  // Whether each fix of the best lap's trace is in the area's segment.
  late final Map<double, bool> _inSegment = _segmentFixes();

  Map<double, bool> _segmentFixes() {
    final result = widget.result, path = widget.path, best = result.bestLap;
    if (path == null || best == null || _segment < 0) return const {};
    return {
      for (final segment in path.segments)
        for (final point in segment)
          point.telemetryTime:
              result.segmentAtTime(best, point.telemetryTime) == _segment,
    };
  }

  DayLapSectors? _lap(Object? reference) {
    for (final lap in widget.result.laps) {
      if (lap.lap.reference == reference) return lap;
    }
    return null;
  }

  CornerLapObservation? _observation(Object? reference) {
    final observations =
        widget.result.computed?.cornerObservations[widget.area.segmentId] ??
        const [];
    for (final observation in observations) {
      if (observation.lapReference == reference) return observation;
    }
    return null;
  }

  // What the area measured on one lap: its time through the segment, and
  // for a corner spread its braking point or lowest speed.
  String _measure(AppLocalizations l10n, Object? reference) {
    final lap = _lap(reference);
    final seconds = lap == null || _segment < 0 ? null : lap.seconds(_segment);
    final parts = [seconds == null ? l10n.focusNotTimed : displayTime(seconds)];
    final observation = _observation(reference);
    switch (widget.area.kind) {
      case FocusAreaKind.brakingSpread:
        final meters = observation?.brakingPointMeters;
        parts.add(
          meters == null
              ? l10n.focusBrakingNotMeasured
              : l10n.focusBrakingStarts(meters.round()),
        );
      case FocusAreaKind.minimumSpeedSpread:
        final speed = observation?.minimumSpeed;
        final label = speedUnitOf(context, widget.area.unit);
        final unit = label.isEmpty ? '' : '\u00a0$label';
        parts.add(
          speed == null
              ? l10n.focusLowestSpeedNotMeasured
              : l10n.focusLowestSpeed('${speed.toStringAsFixed(1)}$unit'),
        );
      case FocusAreaKind.sectorGap || FocusAreaKind.repeatedLoss:
        break;
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final area = widget.area;
    final path = widget.path;
    final segment = l10n.timeLossSegment(area.name);
    final first = _lap(area.lap)?.lap, second = _lap(area.against)?.lap;
    String label(Object? reference) {
      final label = widget.lapLabel(reference);
      return label.isEmpty
          ? l10n.timeLossUnavailable
          : l10n.timeLossLapLabel(label);
    }

    Widget lapRow(String role, Object? reference, Color color, Key key) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: Container(width: 12, height: 12, color: color),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$role · ${label(reference)}',
                style: theme.textTheme.titleSmall,
              ),
              Text(_measure(l10n, reference), key: key),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(segment)),
      body: ReadableListView(
        children: [
          Text(
            l10n.focusAreaKind(area.kind),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.focusObserved(l10n.focusAreaObservation(area)),
            style: theme.textTheme.titleMedium,
            key: const ValueKey('focusObservation'),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.focusHypothesis(l10n.focusAreaHypothesis(area)),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
            key: const ValueKey('focusHypothesis'),
          ),
          const SizedBox(height: 16),
          Text(l10n.focusThrough(segment), style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          lapRow('A', area.lap, lapAColor, const ValueKey('focusLapA')),
          const SizedBox(height: 8),
          lapRow('B', area.against, lapBColor, const ValueKey('focusLapB')),
          if (path != null && !path.isEmpty && _segment >= 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: widget.wide ? 420 : 300,
              child: IgnorePointer(
                child: TrackMap(
                  key: const ValueKey('focusMap'),
                  interactive: false,
                  path: path,
                  gate: widget.gate,
                  pointColor: (point) =>
                      _inSegment[point.telemetryTime] ?? false
                      // The best lap's trace, in the day best's purple:
                      // it is neither lap A nor, necessarily, lap B.
                      ? FetColors.of(context).dayBest
                      : theme.colorScheme.outlineVariant,
                  semanticLabel: l10n.timeLossMapLabel(segment),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(l10n.focusDisclaimer, style: theme.textTheme.bodySmall),
          if (widget.onOpenLap != null)
            Wrap(
              spacing: 8,
              children: [
                for (final (key, lap) in [('A', first), ('B', second)])
                  if (lap != null)
                    TextButton.icon(
                      key: ValueKey('focusOpenLap$key'),
                      style: TextButton.styleFrom(
                        foregroundColor: key == 'A' ? lapAColor : lapBColor,
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(l10n.timeLossOpenLap(l10n.lap(lap))),
                      onPressed: () => widget.onOpenLap!(lap),
                    ),
              ],
            ),
          if (widget.onCompare != null &&
              first != null &&
              second != null &&
              first.reference != second.reference)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('focusCompare'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                ),
                icon: const Icon(Icons.compare_arrows),
                label: Text(l10n.focusCompareAB),
                onPressed: () => widget.onCompare!(
                  first,
                  second,
                  _segment < 0
                      ? null
                      : lapStretch(
                          widget.result,
                          first,
                          widget.result.segments[_segment].startProgressMeters,
                          widget.result.segments[_segment].endProgressMeters,
                        ),
                  segmentId: _segment < 0
                      ? null
                      : widget.result.segments[_segment].segmentId,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
