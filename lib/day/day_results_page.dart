import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import 'day_results_controller.dart';
import 'lap_page.dart';
import 'track_dialog.dart';
import 'track_map.dart';

/// The day at a glance, led by the best lap: "Best day · 1:49.898 ·
/// Session 5 · LAP 2", the group compared, each session's best, and every
/// lap section in recording order.
class DayResultsPage extends StatefulWidget {
  const DayResultsPage({super.key, required this.runs, required this.analysis});

  final List<NamedRun> runs;
  final DayAnalysis analysis;

  @override
  State<DayResultsPage> createState() => _DayResultsPageState();
}

class _DayResultsPageState extends State<DayResultsPage> {
  late final DayResultsController _controller = DayResultsController(
    runs: widget.runs,
    analysis: widget.analysis,
  );

  // The best lap's trace, recomputed only when the best lap changes.
  DayLapReference? _mapReference;
  LapPath? _mapPath;
  (Offset, Offset)? _mapGate;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(DayLapRow row) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LapPage(controller: _controller, row: row),
    ),
  );

  LapPath? _bestPath(DayLapRow best) {
    if (_mapReference != best.reference) {
      _mapReference = best.reference;
      final session = _controller.session(best.runId);
      final origin = session == null ? null : mapOrigin(session);
      _mapPath = session == null
          ? null
          : lapPath(session, best.start, best.end, origin: origin);
      _mapGate = session == null || origin == null
          ? null
          : mapGate(session, origin);
    }
    return _mapPath;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day results')),
    body: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final summary = _summary(context, wide);
          final laps = _lapList(context);
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [...summary, const SizedBox(height: 16), ...laps],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: summary,
                ),
              ),
              Expanded(
                flex: 4,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: laps,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  List<Widget> _summary(BuildContext context, bool wide) {
    final theme = Theme.of(context);
    final analysis = _controller.analysis;
    final ranking = _controller.ranking;
    final best = ranking?.bestOfDay;
    final resolved = analysis.groups.where((group) => group.resolved).toList();
    final path = best == null ? null : _bestPath(best);
    return [
      Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: best == null ? null : () => _open(best),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best day', style: theme.textTheme.labelLarge),
                if (best == null)
                  Text(
                    _noBestReason(analysis, ranking),
                    style: theme.textTheme.titleMedium,
                  )
                else ...[
                  Text(
                    displayTime(best.durationSeconds),
                    style: theme.textTheme.displaySmall,
                  ),
                  Text(best.displayName, style: theme.textTheme.titleMedium),
                  if (ranking!.tieCount > 1)
                    Text(
                      '${ranking.tieCount} laps share this time; the earliest is shown.',
                    ),
                  if (path != null && !path.isEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: wide ? 360 : 240,
                      child: IgnorePointer(
                        child: TrackMap(
                          path: path,
                          gate: _mapGate,
                          semanticLabel:
                              'Trace of the best lap, coloured by speed',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SpeedLegend(path: path),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to open the lap.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (resolved.length > 1) ...[
        Text('Compared laps', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        DropdownButton<String>(
          isExpanded: true,
          value: analysis.chosenGroupId,
          items: [
            for (final group in resolved)
              DropdownMenuItem(
                value: group.id,
                child: Text(
                  '${group.label} · ${group.eligibleLapCount}/${group.lapCount} laps',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            if (id != null) _controller.chooseGroup(id);
          },
        ),
        const SizedBox(height: 12),
      ],
      if (analysis.chosenGroup case final group?)
        Text(
          '${group.label} · ${group.eligibleLapCount} of ${group.lapCount} laps ranked',
          style: theme.textTheme.bodyMedium,
        ),
      if (ranking != null && ranking.runs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Best lap of each session', style: theme.textTheme.titleSmall),
        for (final run in ranking.runs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(run.runName),
            subtitle: Text(
              run.bestLap == null
                  ? 'No ranked lap · ${run.lapCount} ${run.lapCount == 1 ? 'lap' : 'laps'}'
                  : '${run.bestLap!.displayName.split(' · ').last} · '
                        '${run.eligibleLapCount} of ${run.lapCount} laps ranked'
                        '${run.eligibleLapCount >= 3 ? ' · typical ${displayTime(run.distribution!.median)}' : ''}',
            ),
            trailing: run.bestLap == null
                ? null
                : Text(
                    displayTime(run.bestLap!.durationSeconds),
                    style: theme.textTheme.titleMedium,
                  ),
            onTap: run.bestLap == null ? null : () => _open(run.bestLap!),
          ),
      ],
      for (final group in analysis.groups.where((group) => !group.resolved))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline),
          title: Text(group.label),
          subtitle: const Text(
            'Its circuit could not be identified, so its laps are not compared.',
          ),
        ),
      const SizedBox(height: 12),
      Text('Circuits', style: theme.textTheme.titleSmall),
      for (final named in _controller.runs)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(named.name),
          subtitle: Text(_circuitText(named.run.id)),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) =>
                TrackDialog(controller: _controller, runId: named.run.id),
          ),
        ),
      if (analysis.messages.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Notes', style: theme.textTheme.titleSmall),
        for (final message in analysis.messages)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${_runName(message.runId)}${message.text}'),
          ),
      ],
    ];
  }

  String _circuitText(String runId) {
    final analysis = _controller.analysis;
    final configuration =
        analysis.configurations[runId] ?? const TrackConfiguration();
    final manual = _controller.manualTrack(runId) != null;
    String? groupLabel;
    for (final group in analysis.groups) {
      if (group.runIds.contains(runId)) groupLabel = group.label;
    }
    final layout = configuration.layoutId == null
        ? 'Not identified'
        : configuration.detectedRoute
        ? 'Detected route'
        : configuration.layoutId!;
    final direction = configuration.direction?.label ?? 'direction unknown';
    return '$layout · $direction · ${manual ? 'set by you' : 'inferred from GPS'}'
        '${groupLabel == null ? '' : ' · ${groupLabel.split(' · ').first}'}';
  }

  String _runName(String runId) {
    for (final named in _controller.runs) {
      if (named.run.id == runId) return '${named.name}: ';
    }
    return '';
  }

  String _noBestReason(DayAnalysis analysis, DayRanking? ranking) {
    if (analysis.chosenGroup == null) {
      return 'No best lap: no session has enough complete GPS laps to identify its circuit.';
    }
    return 'No best lap: no lap of this group can be ranked.';
  }

  List<Widget> _lapList(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text('Laps', style: theme.textTheme.titleSmall),
      for (final row in _controller.analysis.rows) _lapTile(context, row),
    ];
  }

  Widget _lapTile(BuildContext context, DayLapRow row) {
    final theme = Theme.of(context);
    final issues = _controller.issues(row);
    final timed = row.type == LapSectionType.lap;
    final bestOfDay = _controller.isBestOfDay(row);
    final bestOfRun = _controller.isBestOfRun(row);
    final marks = [
      if (bestOfDay)
        'Best of the day'
      else if (bestOfRun)
        'Best of ${row.runName}',
      if (timed && issues.isNotEmpty)
        issues.contains(LapIssue.userExclusion)
            ? 'Excluded: ${_controller.exclusionReason(row)}'
            : 'Not ranked: ${issues.first.label}',
      if (!timed)
        row.type == LapSectionType.unknown
            ? 'No start/finish pass'
            : 'Not timed',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: bestOfDay
          ? Icon(Icons.emoji_events, color: theme.colorScheme.primary)
          : bestOfRun
          ? const Icon(Icons.star_outline)
          : const SizedBox(width: 24),
      title: Text(row.displayName),
      subtitle: marks.isEmpty ? null : Text(marks.join(' · ')),
      trailing: Text(
        displayTime(row.durationSeconds),
        style: timed && issues.isEmpty
            ? theme.textTheme.titleMedium
            : theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
      ),
      onTap: () => _open(row),
    );
  }
}
