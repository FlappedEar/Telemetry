import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import 'channel_cards.dart';
import 'focus_areas_card.dart';

/// Exactly why a report result is missing; never a zero.
String reportMissingText(Map<String, Object?> result) {
  final reason = result['reason'] as String? ?? '';
  return switch (result['status']) {
    'computing' => 'Calculating…',
    'notComputed' => reason.isEmpty ? 'Not calculated yet.' : reason,
    'stale' =>
      reason.isEmpty ? 'Out of date after an analysis change.' : reason,
    _ => reason.isEmpty ? 'Unavailable.' : reason,
  };
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
    final groupLabel = report['groupLabel'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Day report')),
      body: ListView(
        key: const ValueKey('dayReport'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            groupLabel.isEmpty
                ? 'Choose a group of compatible laps on the results page.'
                : groupLabel,
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
                  reportMissingText(result),
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
      'Best lap and what is left',
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
                Text('Best lap', style: theme.textTheme.bodySmall),
                Text(
                  _time(value['seconds']),
                  key: const ValueKey('dayReportBestTime'),
                  style: theme.textTheme.headlineSmall,
                ),
                Text(value['label'] as String? ?? ''),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theoretical best', style: theme.textTheme.bodySmall),
                Text(
                  theoreticalAvailable ? _time(total['totalSeconds']) : '—',
                  key: const ValueKey('dayReportTheoreticalTime'),
                  style: theme.textTheme.headlineSmall,
                ),
                Text(
                  !theoreticalAvailable
                      ? reportMissingText(theoretical)
                      : difference != null
                      ? '${difference.toStringAsFixed(3)} s available across the approved segments'
                      : 'Some segments have no timed lap; no total.',
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
              label: const Text('Open best lap'),
              onPressed: () => onOpenLap!(_evidence(best, 0)),
            ),
          ),
      ],
    );
  }

  Widget _focus(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result('focusAreas');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final areas = (value['areas'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    final evidence = (result['evidence'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    return _card(
      context,
      'Where to look next',
      result,
      const ValueKey('dayReportFocus'),
      () => [
        Text(
          'Each starts with what was measured. The line under it is a '
          'hypothesis to check in the laps, not a cause or an instruction.',
          style: theme.textTheme.bodySmall,
        ),
        for (final (index, area) in areas.indexed) ...[
          const SizedBox(height: 8),
          Text(
            '${_kind(area['kind'])} · ${area['name']}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          Text(
            'Observed: ${area['observation']}',
            key: ValueKey('dayReportFocusObservation$index'),
          ),
          Text(
            'Hypothesis: ${area['hypothesis']}',
            key: ValueKey('dayReportFocusHypothesis$index'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          if (area['evidenceIndex'] case final int at when at < evidence.length)
            _row(
              context,
              'Compare ${evidence[at]['label']} with ${evidence[at]['againstLabel']} at ${area['name']}',
              '',
              reference: evidence[at]['reference'],
              key: ValueKey('dayReportFocusCompare$index'),
            ),
        ],
      ],
    );
  }

  String _kind(Object? code) {
    for (final kind in FocusAreaKind.values) {
      if (kind.code == code) return focusKindText(kind);
    }
    return '$code';
  }

  Widget _losses(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result('timeLosses');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final range = result['range'] as Map<String, Object?>? ?? const {};
    final losses = (value['losses'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    return _card(
      context,
      'Largest time losses',
      result,
      const ValueKey('dayReportLosses'),
      () => [
        Text(
          'Against ${value['referenceLabel']} · '
          '${range['comparedLapCount']} laps compared. An observed loss is '
          'not a guaranteed or necessarily safe gain.',
          style: theme.textTheme.bodySmall,
        ),
        for (final (index, loss) in losses.take(5).indexed)
          _row(
            context,
            '${displayDelta(_number(loss['lossSeconds']) ?? double.nan)} · ${loss['name']}'
            '${loss['role'] == timeLossRoleContinuation ? ' · after ${loss['cornerName'] ?? 'the corner'}' : ''}',
            loss['lapLabel'] as String? ?? '',
            reference: _evidence(result, index),
            key: ValueKey('dayReportLoss$index'),
          ),
      ],
    );
  }

  Widget _sessions(BuildContext context) {
    final result = _result('progression');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final runs = (value['runs'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    String delta(double seconds) {
      if (seconds.abs() < 0.0005) return 'same as the previous session';
      return '${seconds.abs().toStringAsFixed(3)} s '
          '${seconds < 0 ? 'faster' : 'slower'} than the previous session';
    }

    return _card(
      context,
      'Sessions',
      result,
      const ValueKey('dayReportSessions'),
      () => [
        for (final (index, run) in runs.indexed)
          _row(
            context,
            '${run['runName']} · '
                '${run['bestSeconds'] == null ? 'no eligible lap' : 'best ${_time(run['bestSeconds'])}'}'
                '${_number(run['bestDeltaPreviousSeconds']) == null ? '' : ' · ${delta(_number(run['bestDeltaPreviousSeconds'])!)}'}',
            '${run['eligibleLapCount']} of ${run['lapCount']} laps eligible'
                '${run['distribution'] is Map ? ' · median ${_time((run['distribution'] as Map)['median'])}' : ''}',
            reference: run['evidenceIndex'] is int
                ? _evidence(result, run['evidenceIndex'] as int)
                : null,
            key: ValueKey('dayReportSession$index'),
          ),
      ],
    );
  }

  Widget _consistency(BuildContext context) {
    final result = _result('consistency');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final range = result['range'] as Map<String, Object?>? ?? const {};
    final day = value['day'] as Map<String, Object?>?;
    return _card(
      context,
      'Consistency',
      result,
      const ValueKey('dayReportConsistency'),
      () => [
        Text(
          day == null
              ? ''
              : day['available'] == true
              ? 'Typical lap ${_time(day['median'])} · middle half within '
                    '${(_number(day['interquartileRange']) ?? double.nan).toStringAsFixed(3)} s · '
                    '${day['count']} laps'
              : 'Fewer than ${range['minimumSamples'] ?? minimumConsistencySamples} '
                    'eligible laps; no spread.',
          key: const ValueKey('dayReportConsistencyDay'),
        ),
      ],
    );
  }

  Widget _car(BuildContext context) {
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
      'Car',
      result,
      const ValueKey('dayReportCar'),
      () => [
        if (names.isEmpty) const Text('No valid temperature samples.'),
        for (final (index, name) in names.indexed)
          _row(
            context,
            '${readableChannel(name)} · peak '
            '${channelValueText(peaks[name]!.maximum, peaks[name]!.unit)} in ${peaks[name]!.run}',
            (cooling[name] ?? 0) > 0
                ? '${cooling[name]} recorded cooling intervals'
                : 'no recorded cooling',
            key: ValueKey('dayReportTemperature$index'),
          ),
      ],
    );
  }

  Widget _heartRate(BuildContext context) {
    final result = _result('heartRate');
    final value = result['value'] as Map<String, Object?>? ?? const {};
    final runs = (value['runs'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    return _card(
      context,
      'Heart rate',
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
              '${run['runName']} · '
              '${whole == null
                  ? 'Not recorded'
                  : !valid
                  ? 'No valid samples'
                  : 'mean ${channelValueText(_number(whole['mean']), '')} bpm · '
                        '${channelValueText(_number(whole['minimum']), '')} – '
                        '${channelValueText(_number(whole['maximum']), '')}'}',
              valid
                  ? '${((_number(whole!['coverage']) ?? 0) * 100).round()}% covered'
                  : '',
              key: ValueKey('dayReportHeartRate$index'),
            );
          }(),
      ],
    );
  }
}
