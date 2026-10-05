import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../channel_names.dart';
import '../format.dart';
import '../l10n.dart';
import 'channel_cards.dart';
import 'day_results_controller.dart';

/// What a session's other recording (the RCZ of its VBO) added, in one
/// quiet line, or why it was not combined; and for each channel the two
/// recordings disagree on, a choice between them. While it is being aligned
/// in the background, a line saying so. Nothing when the session has no
/// other recording.
///
/// Below it, the session's recordings (FET-57): "Check clock" measures how
/// the two clocks line up, to accept (combine) or refuse (keep apart), and
/// "Make … primary" reads the session from the other recording.
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
    var primary = '';
    for (final named in controller.runs) {
      if (named.run.id == runId) primary = named.run.format.name.toUpperCase();
    }
    if (controller.primaryChanging(runId)) {
      return _Working(
        text: l10n.recordingsChangingPrimary(alternative),
        textKey: ValueKey('primaryChanging $runId'),
        onStop: () => controller.stopRecordingsWork(runId),
        stopKey: ValueKey('stopRecordingsWork $runId'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _state(context, fusion, primary, alternative),
        if (controller.recordingsProblem(runId) case final problem?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              switch (problem) {
                RecordingsProblem.clockFailed => l10n.recordingsClockFailed,
                RecordingsProblem.primaryMissing =>
                  l10n.recordingsPrimaryMissing(alternative),
                RecordingsProblem.primaryChanged =>
                  l10n.recordingsPrimaryChanged(alternative),
                RecordingsProblem.primaryFailed => l10n.recordingsPrimaryFailed(
                  alternative,
                ),
                RecordingsProblem.unsaved => l10n.recordingsUnsaved,
              },
              key: ValueKey('recordingsProblem $runId'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (controller.clockChecking(runId))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _Working(
              text: l10n.clockChecking(primary, alternative),
              textKey: ValueKey('clockChecking $runId'),
              onStop: () => controller.stopRecordingsWork(runId),
              stopKey: ValueKey('stopRecordingsWork $runId'),
            ),
          )
        else if (controller.clockCheck(runId) case final check?)
          _ClockReview(
            controller: controller,
            runId: runId,
            check: check,
            primary: primary,
            alternative: alternative,
          )
        else if (controller.recordingsEditable(runId))
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: ValueKey('checkClock $runId'),
                onPressed: () => controller.checkClock(runId),
                child: Text(l10n.recordingsCheckClock),
              ),
              if (fusion.fused)
                TextButton(
                  key: ValueKey('dontCombine $runId'),
                  onPressed: () => controller.refuseClock(runId),
                  child: Text(l10n.recordingsDontCombine),
                ),
              TextButton(
                key: ValueKey('makePrimary $runId'),
                onPressed: () => controller.makePrimary(runId),
                child: Text(l10n.recordingsMakePrimary(alternative)),
              ),
            ],
          ),
      ],
    );
  }

  // What the other recording does for the session now.
  Widget _state(
    BuildContext context,
    RunFusion fusion,
    String primary,
    String alternative,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (fusion.state == RunFusionState.primaryOnly) {
      return Text(
        _combinedWhenReopened(primary, alternative)
            ? l10n.recordingsKeptApartUntilReopened(alternative)
            : l10n.recordingsKeptApart(alternative),
        key: ValueKey('fusionKeptApart $runId'),
        style: theme.textTheme.bodySmall,
      );
    }
    if (!fusion.fused) {
      return Text(
        l10n.fusionNotCombined(alternative, l10n.fusionReason(fusion)),
        key: ValueKey('fusionNotCombined $runId'),
        style: theme.textTheme.bodySmall,
      );
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
              fusionChannelName(
                l10n,
                channel,
                named: (name) => channelNameOf(context, name),
              ),
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

/// Whether the day's file cannot keep a VBO session's RCZ apart: it is
/// lined up and combined again when the day is opened (FET-51), as the file
/// has no place for a refusal.
bool _combinedWhenReopened(String primary, String alternative) =>
    primary == RecordingFormat.vbo.name.toUpperCase() &&
    alternative == RecordingFormat.rcz.name.toUpperCase();

/// A clock check of a session's recordings, measured and waiting for the
/// user: what was measured, and accept (only when the clocks line up) or
/// refuse.
class _ClockReview extends StatelessWidget {
  const _ClockReview({
    required this.controller,
    required this.runId,
    required this.check,
    required this.primary,
    required this.alternative,
  });

  final DayResultsController controller;
  final String runId;
  final RunFusion check;
  final String primary;
  final String alternative;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final alignment = check.alignment;
    final lines = <String>[
      check.fused
          ? l10n.clockAligned
          : l10n.clockNotAligned(l10n.fusionReason(check)),
      if (alignment?.offset case final offset?)
        l10n.clockMeasured(
          primary,
          alternative,
          _offset(offset),
          '${fixed(alignment!.uncertaintySeconds ?? 0, 2)}\u00a0s',
        ),
      if (alignment?.driftPpm case final drift?)
        l10n.clockDrift(fixed(drift, 0)),
      if (alignment != null && alignment.correlation > -1)
        l10n.clockCorrelation(
          fixed(alignment.correlation, 3),
          '${fixed(alignment.overlapSeconds, 0)}\u00a0s',
          alignment.usedWindows,
          alignment.windows.length,
        ),
      if (alignment != null)
        alignment.declaredOffset == null
            ? l10n.clockNoDeclared
            : l10n.clockDeclared(_offset(alignment.declaredOffset!)),
    ];
    final reopened = _combinedWhenReopened(primary, alternative);
    return Padding(
      key: ValueKey('clockReview $runId'),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(line, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            l10n.clockRefuseNote(primary, alternative),
            style: theme.textTheme.bodySmall,
          ),
          if (reopened)
            Text(
              l10n.clockReopenNote(alternative),
              key: ValueKey('clockReopenNote $runId'),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton(
                key: ValueKey('acceptClock $runId'),
                // Not while recordings are added: the check may not be of
                // the recording the session ends up with.
                onPressed: controller.clockAcceptable(runId)
                    ? () => controller.acceptClock(runId)
                    : null,
                child: Text(l10n.clockAccept),
              ),
              OutlinedButton(
                key: ValueKey('refuseClock $runId'),
                onPressed: () => controller.refuseClock(runId),
                child: Text(l10n.clockRefuse),
              ),
            ],
          ),
        ],
      ),
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
  return '$sign${fixed(hundredths.abs() / 100, 2)}\u00a0s';
}

/// A channel both recordings measured, as the user knows it: "Speed",
/// "Satellites", the name the driver gave it ([named]), or a temperature in
/// the app's language ("Temperatura oleju"); any other channel as recorded,
/// so "Oil Pressure" or "Gear" never reads as a temperature.
String fusionChannelName(
  AppLocalizations l10n,
  FusedChannel channel, {
  String Function(String channel) named = channelDisplayName,
}) => switch (channel.key.toLowerCase()) {
  'speed' => l10n.fusionChannelSpeed,
  'latitude' => l10n.fusionChannelLatitude,
  'longitude' => l10n.fusionChannelLongitude,
  'sats' || 'satellites' => l10n.fusionChannelSatellites,
  _ when named(channel.name) != channel.name => named(channel.name),
  _ when _isTemperature(channel) => channelLabel(l10n, channel.name),
  _ => channel.name,
};

/// A temperature by its unit ("C", "°F") or its name ("Oil Temp").
bool _isTemperature(FusedChannel channel) =>
    const {'°C', '°F', 'F', 'degF'}.contains(unitText(channel.unit)) ||
    channel.name.toLowerCase().contains('temp');

/// What runs for a session's recordings, with a button that stops it.
class _Working extends StatelessWidget {
  const _Working({
    required this.text,
    required this.textKey,
    required this.onStop,
    required this.stopKey,
  });

  final String text;
  final Key textKey;
  final VoidCallback onStop;
  final Key stopKey;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    children: [
      Text(text, key: textKey, style: Theme.of(context).textTheme.bodySmall),
      TextButton(
        key: stopKey,
        onPressed: onStop,
        child: Text(context.l10n.cancel),
      ),
    ],
  );
}
