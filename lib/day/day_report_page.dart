import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'channel_cards.dart';
import 'focus_areas_card.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText;
import 'time_losses_card.dart' show TimeLossText;

/// Exactly why a report result is missing; never a zero.
String reportMissingText(AppLocalizations l10n, Map<String, Object?> result) {
  final reason = result['reason'] as String? ?? '';
  return switch (result['status']) {
    'computing' => l10n.reportCalculating,
    'notComputed' =>
      reason.isEmpty ? l10n.reportNotCalculated : _reason(l10n, reason),
    'stale' => reason.isEmpty ? l10n.reportOutOfDate : _reason(l10n, reason),
    _ => reason.isEmpty ? l10n.reportUnavailable : _reason(l10n, reason),
  };
}

// A reason the report writes (its own, the theoretical best's, the time
// losses' or the channel summaries') in the app's language; one the app
// does not know, such as an error, is shown as written.
String _reason(AppLocalizations l10n, String reason) => switch (reason) {
  'Not calculated yet.' => l10n.reportNotCalculated,
  'Not in this report.' => l10n.reportNotInReport,
  'The analysis decisions changed after this result was computed.' =>
    l10n.reportStale,
  'Choose a compatibility group.' => l10n.reportChooseGroup,
  'No eligible lap in this group.' => l10n.reportNoEligibleLap,
  'No session in this group.' => l10n.reportNoSession,
  'No eligible laps to summarize.' => l10n.reportNoEligibleLaps,
  'No loss, sector gap or spread is large enough to single out.' =>
    l10n.focusNone,
  'No heart rate recorded.' => l10n.reportNoHeartRate,
  'No temperature recorded.' => l10n.reportNoTemperature,
  channelRecordingUnavailable => l10n.channelRecordingUnavailable,
  'Channel summaries were cancelled.' => l10n.channelSummariesCancelled,
  _ when l10n.tbMessage(reason) != reason => l10n.tbMessage(reason),
  _ => l10n.timeLossReason(reason),
};

final _resolvedGroup = RegExp(
  r'^Group (\d{1,9}) · (.+) · (Clockwise|Counterclockwise)$',
);
final _unresolvedGroup = RegExp(r'^Unresolved · (.+)$');

// A group label written by `telemetry_core` (`DayGroup.label`) in the
// app's language; any other label is shown as written.
String _groupLabel(AppLocalizations l10n, String label) {
  final resolved = _resolvedGroup.firstMatch(label);
  if (resolved != null) {
    final layout = resolved[2]!;
    return l10n.circuitGroup(
      int.parse(resolved[1]!),
      layout == 'Detected route' ? l10n.detectedRoute : layout,
      l10n.direction(
        resolved[3] == 'Clockwise'
            ? TrackDirection.clockwise
            : TrackDirection.counterclockwise,
      ),
    );
  }
  final unresolved = _unresolvedGroup.firstMatch(label);
  return unresolved == null
      ? label
      : l10n.circuitGroupUnresolved(l10n.session(unresolved[1]!));
}

// A focus area as the report writes it, in the app's language: its
// observation and hypothesis as `telemetry_core` wrote them when the app
// does not recognise them.
({String observation, String hypothesis}) _focusTexts(
  AppLocalizations l10n,
  FocusAreaKind? kind,
  Map<String, Object?> area,
) {
  final observation = '${area['observation']}';
  final hypothesis = '${area['hypothesis']}';
  if (kind == null) return (observation: observation, hypothesis: hypothesis);
  final focus = FocusArea(
    kind: kind,
    segmentId: '${area['segmentId']}',
    name: '${area['name']}',
    observation: observation,
    hypothesis: hypothesis,
    metric: '${area['metric']}',
    value: _number(area['value']) ?? double.nan,
    unit: '${area['unit']}',
    sampleCount: area['sampleCount'] as int? ?? 0,
    lap: null,
    against: null,
    score: 0,
  );
  return (
    observation: l10n.focusAreaObservation(focus),
    hypothesis: l10n.focusAreaHypothesis(focus),
  );
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

String _time(Object? seconds) {
  final value = _number(seconds);
  return value == null ? '—' : displayTime(value);
}

/// The day report (Overlays' "Day report"): the day's results as computed
/// elsewhere, each card leading to its evidence. Nothing is recalculated
/// here, and a card without a result says exactly why.
class DayReportPage extends StatelessWidget {
  const DayReportPage({super.key, required this.report, this.onOpenLap});

  /// The document of [buildOutingDayReport].
  final Map<String, Object?> report;

  /// Opens a lap from its reference as the report writes it; no button when
  /// null.
  final void Function(Object? reference)? onOpenLap;

  Map<String, Object?> _result(String id) {
    for (final value in report['results'] as List? ?? const []) {
      if (value is Map<String, Object?> && value['id'] == id) return value;
    }
    return const {'status': 'unavailable', 'reason': 'Not in this report.'};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final groupLabel = report['groupLabel'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dayReport)),
      body: ListView(
        key: const ValueKey('dayReport'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            groupLabel.isEmpty
                ? l10n.reportGroupNone
                : _groupLabel(l10n, groupLabel),
            key: const ValueKey('dayReportGroup'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _best(context),
          _focus(context),
          _losses(context),
          _sessions(context),
          _consistency(context),
          _car(context),
          _heartRate(context),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    String heading,
    Map<String, Object?> result,
    Key key,
    List<Widget> Function() body,
  ) {
    final theme = Theme.of(context);
    final available = result['status'] == 'available';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(heading, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              if (!available)
                Text(
                  reportMissingText(context.l10n, result),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              else
                ...body(),
            ],
          ),
        ),
      ),
    );
  }

  // A tappable row of the report: a lap, a loss or a session.
  Widget _row(
    BuildContext context,
    String primary,
    String secondary, {
    Object? reference,
    Key? key,
  }) {
    final theme = Theme.of(context);
    final open = onOpenLap;
    return InkWell(
      key: key,
      onTap: open == null || reference == null ? null : () => open(reference),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(primary),
                  if (secondary.isNotEmpty)
                    Text(secondary, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (open != null && reference != null)
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }

  Object? _evidence(Map<String, Object?> result, int index) {
    final evidence = result['evidence'] as List? ?? const [];
    if (index < 0 || index >= evidence.length) return null;
    final item = evidence[index];
    return item is Map<String, Object?> ? item['reference'] : null;
  }

  Widget _best(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final best = _result('bestLap');
    final theoretical = _result('theoreticalBest');
    final value = best['value'] as Map<String, Object?>? ?? const {};
    final total = theoretical['value'] is Map
        ? (theoretical['value'] as Map<String, Object?>)
        : const <String, Object?>{};
    final theoreticalAvailable = theoretical['status'] == 'available';
    final difference = _number(total['differenceSeconds']);
    return _card(
      context,
      l10n.reportBestTitle,
      best,
      const ValueKey('dayReportBest'),
      () => [
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reportBestLap, style: theme.textTheme.bodySmall),
                Text(
                  _time(value['seconds']),
                  key: const ValueKey('dayReportBestTime'),
                  style: theme.textTheme.headlineSmall,
                ),
                Text(l10n.timeLossLapLabel(value['label'] as String? ?? '')),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.reportTheoreticalBest,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  theoreticalAvailable ? _time(total['totalSeconds']) : '—',
                  key: const ValueKey('dayReportTheoreticalTime'),
                  style: theme.textTheme.headlineSmall,
                ),
                Text(
                  !theoreticalAvailable
                      ? reportMissingText(l10n, theoretical)
                      : difference != null
                      ? l10n.reportTheoreticalAvailable(
                          difference.toStringAsFixed(3),
                        )
                      : l10n.reportTheoreticalNoTotal,
                  key: const ValueKey('dayReportTheoreticalNote'),
                ),
              ],
            ),
          ],
        ),
        if (onOpenLap != null && _evidence(best, 0) != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('dayReportOpenBestLap'),
              icon: const Icon(Icons.map_outlined),
              label: Text(l10n.reportOpenBestLap),
              onPressed: () => onOpenLap!(_evidence(best, 0)),
            ),
          ),
      ],
    );
  }

  Widget _focus(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = _result('focusAreas');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final areas = (value['areas'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    final evidence = (result['evidence'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    return _card(
      context,
      l10n.focusTitle,
      result,
      const ValueKey('dayReportFocus'),
      () => [
        Text(l10n.reportFocusIntro, style: theme.textTheme.bodySmall),
        for (final (index, area) in areas.indexed) ...[
          const SizedBox(height: 8),
          Text(
            '${_kind(l10n, area['kind'])} · '
            '${l10n.timeLossSegment('${area['name']}')}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            l10n.focusObserved(
              _focusTexts(l10n, _kindOf(area['kind']), area).observation,
            ),
            key: ValueKey('dayReportFocusObservation$index'),
          ),
          Text(
            l10n.focusHypothesis(
              _focusTexts(l10n, _kindOf(area['kind']), area).hypothesis,
            ),
            key: ValueKey('dayReportFocusHypothesis$index'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          if (area['evidenceIndex'] case final int at when at < evidence.length)
            _row(
              context,
              l10n.reportFocusCompare(
                l10n.timeLossLapLabel('${evidence[at]['label']}'),
                l10n.timeLossLapLabel('${evidence[at]['againstLabel']}'),
                l10n.timeLossSegment('${area['name']}'),
              ),
              '',
              reference: evidence[at]['reference'],
              key: ValueKey('dayReportFocusCompare$index'),
            ),
        ],
      ],
    );
  }

  FocusAreaKind? _kindOf(Object? code) {
    for (final kind in FocusAreaKind.values) {
      if (kind.code == code) return kind;
    }
    return null;
  }

  String _kind(AppLocalizations l10n, Object? code) {
    final kind = _kindOf(code);
    return kind == null ? '$code' : l10n.focusAreaKind(kind);
  }

  Widget _losses(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = _result('timeLosses');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final range = result['range'] as Map<String, Object?>? ?? const {};
    final losses = (value['losses'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    String name(Map<String, Object?> loss) {
      final segment = l10n.timeLossSegment('${loss['name']}');
      if (loss['role'] != timeLossRoleContinuation) return segment;
      final corner = loss['cornerName'] as String?;
      return corner == null
          ? l10n.timeLossSegmentAfterTheCorner(segment)
          : l10n.timeLossSegmentAfterCorner(
              segment,
              l10n.timeLossSegment(corner),
            );
    }

    return _card(
      context,
      l10n.reportLossesTitle,
      result,
      const ValueKey('dayReportLosses'),
      () => [
        Text(
          l10n.reportLossesIntro(
            l10n.timeLossLapLabel('${value['referenceLabel']}'),
            (range['comparedLapCount'] as num?)?.toInt() ?? 0,
          ),
          style: theme.textTheme.bodySmall,
        ),
        for (final (index, loss) in losses.take(5).indexed)
          _row(
            context,
            '${displayDelta(_number(loss['lossSeconds']) ?? double.nan)} · '
            '${name(loss)}',
            l10n.timeLossLapLabel(loss['lapLabel'] as String? ?? ''),
            reference: _evidence(result, index),
            key: ValueKey('dayReportLoss$index'),
          ),
      ],
    );
  }

  Widget _sessions(BuildContext context) {
    final l10n = context.l10n;
    final result = _result('progression');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final runs = (value['runs'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    String delta(double seconds) {
      if (seconds.abs() < 0.0005) return l10n.reportSameAsPrevious;
      final difference = seconds.abs().toStringAsFixed(3);
      return seconds < 0
          ? l10n.reportFasterThanPrevious(difference)
          : l10n.reportSlowerThanPrevious(difference);
    }

    return _card(
      context,
      l10n.reportSessionsTitle,
      result,
      const ValueKey('dayReportSessions'),
      () => [
        for (final (index, run) in runs.indexed)
          _row(
            context,
            '${l10n.session('${run['runName']}')} · '
                '${run['bestSeconds'] == null ? l10n.reportNoEligibleLapShort : l10n.reportSessionBest(_time(run['bestSeconds']))}'
                '${_number(run['bestDeltaPreviousSeconds']) == null ? '' : ' · ${delta(_number(run['bestDeltaPreviousSeconds'])!)}'}',
            '${l10n.reportEligibleLaps((run['eligibleLapCount'] as num?)?.toInt() ?? 0, (run['lapCount'] as num?)?.toInt() ?? 0)}'
                '${run['distribution'] is Map ? ' · ${l10n.reportMedian(_time((run['distribution'] as Map)['median']))}' : ''}',
            reference: run['evidenceIndex'] is int
                ? _evidence(result, run['evidenceIndex'] as int)
                : null,
            key: ValueKey('dayReportSession$index'),
          ),
      ],
    );
  }

  Widget _consistency(BuildContext context) {
    final l10n = context.l10n;
    final result = _result('consistency');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final range = result['range'] as Map<String, Object?>? ?? const {};
    final day = value['day'] as Map<String, Object?>?;
    return _card(
      context,
      l10n.consistencyHeading,
      result,
      const ValueKey('dayReportConsistency'),
      () => [
        Text(
          day == null
              ? ''
              : day['available'] == true
              ? l10n.reportConsistencyDay(
                  _time(day['median']),
                  (_number(day['interquartileRange']) ?? double.nan)
                      .toStringAsFixed(3),
                  (day['count'] as num?)?.toInt() ?? 0,
                )
              : l10n.reportConsistencyTooFew(
                  (range['minimumSamples'] as num?)?.toInt() ??
                      minimumConsistencySamples,
                ),
          key: const ValueKey('dayReportConsistencyDay'),
        ),
      ],
    );
  }

  Widget _car(BuildContext context) {
    final l10n = context.l10n;
    final result = _result('temperatures');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    // The peak of each recorded temperature across the day, and where.
    final peaks = <String, ({double maximum, String unit, String run})>{};
    final cooling = <String, int>{};
    for (final run
        in (value['runs'] as List? ?? const []).cast<Map<String, Object?>>()) {
      for (final channel
          in (run['channels'] as List? ?? const [])
              .cast<Map<String, Object?>>()) {
        final name = channel['channel'] as String;
        cooling[name] =
            (cooling[name] ?? 0) + (channel['coolingCount'] as int? ?? 0);
        final whole = channel['run'] as Map<String, Object?>? ?? const {};
        final maximum = _number(whole['maximum']);
        if (whole['valid'] != true || maximum == null) continue;
        final current = peaks[name];
        if (current == null || maximum > current.maximum) {
          peaks[name] = (
            maximum: maximum,
            unit: channel['unit'] as String? ?? '',
            run: run['runName'] as String? ?? '',
          );
        }
      }
    }
    final names = peaks.keys.toList()..sort();
    return _card(
      context,
      l10n.channelCarTitle,
      result,
      const ValueKey('dayReportCar'),
      () => [
        if (names.isEmpty) Text(l10n.reportNoTemperatureSamples),
        for (final (index, name) in names.indexed)
          _row(
            context,
            l10n.reportCarPeak(
              channelLabel(l10n, name),
              channelValueText(peaks[name]!.maximum, peaks[name]!.unit),
              l10n.session(peaks[name]!.run),
            ),
            (cooling[name] ?? 0) > 0
                ? l10n.reportCoolingIntervals(cooling[name]!)
                : l10n.reportNoCooling,
            key: ValueKey('dayReportTemperature$index'),
          ),
      ],
    );
  }

  Widget _heartRate(BuildContext context) {
    final l10n = context.l10n;
    final result = _result('heartRate');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final runs = (value['runs'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    return _card(
      context,
      l10n.channelHeartRate,
      result,
      const ValueKey('dayReportHeartRate'),
      () => [
        for (final (index, run) in runs.indexed)
          () {
            final heart = run['heartRate'] as Map<String, Object?>?;
            final whole = heart?['run'] as Map<String, Object?>?;
            final valid = whole?['valid'] == true;
            return _row(
              context,
              '${l10n.session('${run['runName']}')} · '
              '${whole == null
                  ? l10n.channelNotRecorded
                  : !valid
                  ? l10n.channelNoValidSamples
                  : l10n.reportHeartRateSummary(channelValueText(_number(whole['mean']), ''), channelValueText(_number(whole['minimum']), ''), channelValueText(_number(whole['maximum']), ''))}',
              valid
                  ? l10n.reportCovered(
                      ((_number(whole!['coverage']) ?? 0) * 100).round(),
                    )
                  : '',
              key: ValueKey('dayReportHeartRate$index'),
            );
          }(),
      ],
    );
  }
}
