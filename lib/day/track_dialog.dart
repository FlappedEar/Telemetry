import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
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
      if (named.run.id == runId) return context.l10n.session(named.name);
    }
    return runId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final inference = widget.controller.analysis.inferences[widget.runId];
    final canSave = _name.text.trim().isNotEmpty && _direction != null;
    final session = widget.controller.session(widget.runId);
    final origin = session == null ? null : mapOrigin(session);
    return AlertDialog(
      title: Text(l10n.trackDialogTitle(_runName(widget.runId))),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inference?.route == null
                    ? l10n.trackDialogNoRoute(
                        inference == null || inference.reason.isEmpty
                            ? l10n.trackDialogNoLaps
                            : l10n.routeReason(inference.reason),
                      )
                    : l10n.trackDialogDetectedRoute(
                        fixed(inference!.route!.lengthMeters, 0),
                        l10n.directionInSentence(inference.route!.direction),
                      ),
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
                    semanticLabel: l10n.trackDialogWholeTrace(
                      _runName(widget.runId),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                maxLength: 128,
                decoration: InputDecoration(
                  labelText: l10n.trackDialogLayoutName,
                  hintText: l10n.trackDialogLayoutHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
              // Stacked on phones, where the Polish labels are too long
              // to share a row.
              LayoutBuilder(
                builder: (context, constraints) =>
                    SegmentedButton<TrackDirection>(
                      direction: constraints.maxWidth < 360
                          ? Axis.vertical
                          : Axis.horizontal,
                      emptySelectionAllowed: true,
                      segments: [
                        for (final direction in TrackDirection.values)
                          ButtonSegment(
                            value: direction,
                            label: Text(l10n.direction(direction)),
                          ),
                      ],
                      selected: {?_direction},
                      onSelectionChanged: (selection) =>
                          setState(() => _direction = selection.firstOrNull),
                    ),
              ),
              if (_sameRoute.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _applyToSameRoute,
                  onChanged: (value) =>
                      setState(() => _applyToSameRoute = value ?? false),
                  title: Text(
                    l10n.trackDialogSameRoute(
                      _sameRoute.map(_runName).join(', '),
                    ),
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
            child: Text(l10n.trackDialogUseDetected),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
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
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
