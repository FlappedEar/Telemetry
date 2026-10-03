import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'channel_cards.dart';
import 'day_results_controller.dart';

/// What a session's other recording (the RCZ of its VBO) added, in one
/// quiet line, or why it was not combined; and for each channel the two
/// recordings disagree on, a choice between them. While it is being aligned
/// in the background, a line saying so. Nothing when the session has no
/// other recording.
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pending = controller.fusionPending(runId);
    if (pending != null) {
      return Text(
        l10n.fusionPending(pending),
        key: ValueKey('fusionPending $runId'),
        style: theme.textTheme.bodySmall,
      );
    }
    if (fusion == null) return const SizedBox.shrink();
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
        if (added > 0)
          Text(
            l10n.fusionAdded(added, alternative),
            key: ValueKey('fusionSummary $runId'),
            style: theme.textTheme.bodySmall,
          )
        else if (fusion.conflicts.isEmpty)
          // Combined without adding anything: the session reads as before.
          Text(
            l10n.fusionLinedUp(
              alternative,
              _offset(fusion.clock.offsetSeconds),
            ),
            key: ValueKey('fusionSummary $runId'),
            style: theme.textTheme.bodySmall,
          ),
        for (final channel in fusion.conflicts) ...[
          const SizedBox(height: 8),
          Text(
            l10n.fusionConflict(
              fusionChannelName(l10n, channel),
              primary,
              alternative,
            ),
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

/// The clock offset found: "−0.14 s", "+0.10 s".
String _offset(double seconds) {
  final hundredths = (seconds * 100).round();
  final sign = hundredths > 0
      ? '+'
      : hundredths < 0
      ? '−'
      : '±';
  return '$sign${fixed(hundredths.abs() / 100, 2)} s';
}

/// A channel both recordings measured, as the user knows it: "Speed",
/// "Satellites", "Oil".
String fusionChannelName(AppLocalizations l10n, FusedChannel channel) =>
    switch (channel.key.toLowerCase()) {
      'speed' => l10n.fusionChannelSpeed,
      'latitude' => l10n.fusionChannelLatitude,
      'longitude' => l10n.fusionChannelLongitude,
      'sats' || 'satellites' => l10n.fusionChannelSatellites,
      _ => readableChannel(channel.name),
    };
