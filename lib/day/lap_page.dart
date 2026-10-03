import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import 'day_results_controller.dart';
import 'track_map.dart';

/// One lap section: its time, where it stands in the day, and its trace on
/// the map coloured by speed, over the best lap of the day in grey.
class LapPage extends StatefulWidget {
  const LapPage({super.key, required this.controller, required this.row});

  final DayResultsController controller;
  final DayLapRow row;

  @override
  State<LapPage> createState() => _LapPageState();
}

class _LapPageState extends State<LapPage> {
  bool _showBest = true;

  // Static geometry: computed once per lap, never on rebuilds.
  late final GeoCoordinate? _origin;
  late final LapPath _path;
  late final (Offset, Offset)? _gate;
  DayLapReference? _bestReference;
  LapPath? _bestPath;

  @override
  void initState() {
    super.initState();
    final session = widget.controller.session(widget.row.runId);
    _origin = session == null ? null : mapOrigin(session);
    _path = session == null
        ? LapPath(origin: const GeoCoordinate(0, 0), segments: const [])
        : lapPath(session, widget.row.start, widget.row.end, origin: _origin);
    _gate = session == null || _origin == null
        ? null
        : mapGate(session, _origin);
  }

  LapPath? _best() {
    final best = widget.controller.ranking?.bestOfDay;
    if (best == null || best.reference == widget.row.reference) return null;
    if (_bestReference != best.reference) {
      final session = widget.controller.session(best.runId);
      _bestReference = best.reference;
      _bestPath = session == null
          ? null
          : lapPath(
              session,
              best.start,
              best.end,
              origin: _origin ?? _path.origin,
            );
    }
    return _bestPath;
  }

  Future<void> _exclude() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ExcludeDialog(),
    );
    if (reason != null) widget.controller.exclude(widget.row, reason);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(row.displayName)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final theme = Theme.of(context);
          final best = controller.ranking?.bestOfDay;
          final issues = controller.issues(row);
          final reason = controller.exclusionReason(row);
          final bestPath = _showBest ? _best() : null;
          final summary = <Widget>[
            Text(
              displayTime(row.durationSeconds),
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 4),
            if (controller.isBestOfDay(row))
              const Text('Best lap of the day')
            else if (best != null && row.type == LapSectionType.lap)
              Text(
                '${displayDelta(row.durationSeconds - best.durationSeconds)} '
                'to the best of the day (${best.displayName})',
              ),
            if (controller.isBestOfRun(row) && !controller.isBestOfDay(row))
              Text('Best lap of ${row.runName}'),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  issue == LapIssue.userExclusion && reason != null
                      ? 'Not ranked: excluded (“$reason”)'
                      : 'Not ranked: ${issue.label}',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (row.type == LapSectionType.lap) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (reason == null)
                    OutlinedButton.icon(
                      onPressed: _exclude,
                      icon: const Icon(Icons.block),
                      label: const Text('Exclude from ranking…'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => controller.include(row),
                      icon: const Icon(Icons.undo),
                      label: const Text('Include in ranking'),
                    ),
                ],
              ),
            ],
          ];
          final trace = _path.isEmpty
              ? const Center(child: Text('No GPS recorded for this section.'))
              : Card(
                  clipBehavior: Clip.antiAlias,
                  child: TrackMap(
                    path: _path,
                    reference: bestPath,
                    gate: _gate,
                    semanticLabel:
                        'Trace of ${row.displayName}, coloured by speed',
                  ),
                );
          final legend = <Widget>[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Speed', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                Expanded(child: SpeedLegend(path: _path)),
              ],
            ),
            if (best != null && best.reference != row.reference)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showBest,
                onChanged: (value) => setState(() => _showBest = value),
                title: Text('Show the best lap (${best.displayName}) in grey'),
              ),
          ];
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 800) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 300, child: ListView(children: summary)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: trace),
                            ...legend,
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              // A tall phone gives the map the rest of the screen; a short
              // one (a small phone sideways, or with large text) scrolls.
              if (constraints.maxHeight >= 600) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...summary,
                      const SizedBox(height: 12),
                      Expanded(child: trace),
                      ...legend,
                    ],
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ...summary,
                  const SizedBox(height: 12),
                  SizedBox(
                    height: (constraints.maxHeight - 48).clamp(220.0, 420.0),
                    child: trace,
                  ),
                  ...legend,
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ExcludeDialog extends StatefulWidget {
  const _ExcludeDialog();

  @override
  State<_ExcludeDialog> createState() => _ExcludeDialogState();
}

class _ExcludeDialogState extends State<_ExcludeDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Exclude this lap'),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: 256,
      decoration: const InputDecoration(
        labelText: 'Reason',
        hintText: 'Traffic, yellow flag…',
      ),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Exclude'),
      ),
    ],
  );
}
