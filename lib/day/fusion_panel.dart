import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';
import 'day_results_controller.dart';

/// What a session's other recording (the RCZ of its VBO) added, in one
/// line, or why it was not combined; and for each channel the two
/// recordings disagree on, a choice between them. Nothing when the session
/// has no other recording, or when combining it added nothing and found no
/// disagreement.
class SessionFusion extends StatelessWidget {
  const SessionFusion({
    super.key,
    required this.controller,
    required this.runId,
  });

  final DayResultsController controller;
  final String runId;

  @override
  Widget build(BuildContext context) {
    final fusion = controller.fusion(runId);
    if (fusion == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final alternative = fusion.alternativeFormat?.name.toUpperCase() ?? '';
    if (!fusion.fused) {
      return Text(
        l10n.fusionNotCombined(alternative, l10n.fusionReason(fusion)),
        key: ValueKey('fusionNotCombined $runId'),
        style: theme.textTheme.bodySmall,
      );
    }
    var primary = '';
    for (final named in controller.runs) {
      if (named.run.id == runId) primary = named.run.format.name.toUpperCase();
    }
    final added = fusion.channelOrigins.values
        .where((rule) => rule == 'added')
        .length;
    final updating = controller.fusionUpdating(runId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Combined without adding anything, the session reads as before.
        if (added > 0)
          Text(
            l10n.fusionAdded(added, alternative),
            key: ValueKey('fusionSummary $runId'),
            style: theme.textTheme.bodySmall,
          ),
        for (final channel in fusion.conflicts) ...[
          const SizedBox(height: 8),
          Text(
            l10n.fusionConflict(channel.key, primary, alternative),
            key: ValueKey('fusionConflict $runId ${channel.key}'),
          ),
          const SizedBox(height: 4),
          // Stacked on phones, where the labels need the room.
          LayoutBuilder(
            builder: (context, constraints) => SegmentedButton<FusionRule>(
              key: ValueKey('fusionRule $runId ${channel.key}'),
              direction: constraints.maxWidth < 360
                  ? Axis.vertical
                  : Axis.horizontal,
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: FusionRule.primaryOnly,
                  label: Text(l10n.fusionKeepPrimary(primary)),
                ),
                ButtonSegment(
                  value: FusionRule.fillGaps,
                  label: Text(l10n.fusionFillGaps),
                ),
                ButtonSegment(
                  value: FusionRule.preferAlternative,
                  label: Text(l10n.fusionUseAlternative(alternative)),
                ),
              ],
              selected: {fusion.ruleOf(channel.key)},
              onSelectionChanged: updating
                  ? null
                  : (selection) => controller.setFusionRule(
                      runId,
                      channel.key,
                      selection.single,
                    ),
            ),
          ),
        ],
      ],
    );
  }
}
