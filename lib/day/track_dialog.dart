import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_results_controller.dart';
import 'track_map.dart';

/// Corrects one session's circuit: its layout name and direction, for it
/// alone or for every session on the same route, or back to the detected
/// route. Shows the session's whole GPS trace to check against.
class TrackDialog extends StatefulWidget {
  const TrackDialog({super.key, required this.controller, required this.runId});

  final DayResultsController controller;
  final String runId;

  @override
  State<TrackDialog> createState() => _TrackDialogState();
}

class _TrackDialogState extends State<TrackDialog> {
  late final TrackConfiguration? _manual = widget.controller.manualTrack(
    widget.runId,
  );
  late final TextEditingController _name = TextEditingController(
    text: _manual?.layoutId ?? '',
  );
  late TrackDirection? _direction =
      _manual?.direction ??
      widget.controller.analysis.inferences[widget.runId]?.route?.direction;
  late final List<String> _sameRoute = widget.controller.runsOnSameRoute(
    widget.runId,
  );
  bool _applyToSameRoute = true;
  late final LapPath? _trace = _wholeTrace();

  LapPath? _wholeTrace() {
    final session = widget.controller.session(widget.runId);
    if (session == null) return null;
    return lapPath(
      session,
      0,
      session.duration,
      origin: mapOrigin(session),
      maximumPoints: 3000,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _runName(String runId) {
    for (final named in widget.controller.runs) {
      if (named.run.id == runId) return named.name;
    }
    return runId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inference = widget.controller.analysis.inferences[widget.runId];
    final canSave = _name.text.trim().isNotEmpty && _direction != null;
    final session = widget.controller.session(widget.runId);
    final origin = session == null ? null : mapOrigin(session);
    return AlertDialog(
      title: Text('Circuit of ${_runName(widget.runId)}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inference?.route == null
                    ? 'No route was detected: ${inference?.reason ?? 'no laps'}'
                    : 'Detected route: ${inference!.route!.lengthMeters.toStringAsFixed(0)} m, '
                          '${inference.route!.direction.label.toLowerCase()} (inferred from GPS).',
                style: theme.textTheme.bodySmall,
              ),
              if (_trace != null && !_trace.isEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: TrackMap(
                    path: _trace,
                    gate: session == null || origin == null
                        ? null
                        : mapGate(session, origin),
                    semanticLabel:
                        'Whole GPS trace of ${_runName(widget.runId)}',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                maxLength: 128,
                decoration: const InputDecoration(
                  labelText: 'Layout name',
                  hintText: 'Jastrząb full circuit',
                ),
                onChanged: (_) => setState(() {}),
              ),
              SegmentedButton<TrackDirection>(
                emptySelectionAllowed: true,
                segments: [
                  for (final direction in TrackDirection.values)
                    ButtonSegment(
                      value: direction,
                      label: Text(direction.label),
                    ),
                ],
                selected: {?_direction},
                onSelectionChanged: (selection) =>
                    setState(() => _direction = selection.firstOrNull),
              ),
              if (_sameRoute.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _applyToSameRoute,
                  onChanged: (value) =>
                      setState(() => _applyToSameRoute = value ?? false),
                  title: Text(
                    'Also for the sessions on the same route: '
                    '${_sameRoute.map(_runName).join(', ')}',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (_manual != null)
          TextButton(
            onPressed: () {
              widget.controller.useDetectedRoute(widget.runId);
              Navigator.pop(context);
            },
            child: const Text('Use the detected route'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !canSave
              ? null
              : () {
                  widget.controller.setTrack(
                    [widget.runId, if (_applyToSameRoute) ..._sameRoute],
                    _name.text,
                    _direction!,
                  );
                  Navigator.pop(context);
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
