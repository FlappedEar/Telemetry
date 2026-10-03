import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';

/// The format of the other recording a session's channel came from ("RCZ"),
/// or empty when it is the session's own (see
/// `DayResultsController.channelSource`).
typedef ChannelSource = String Function(String runId, String channel);

/// " · from RCZ" after a channel's line when [source] says it came from
/// another recording; empty otherwise.
String channelSourceSuffix(BuildContext context, String source) =>
    source.isEmpty ? '' : ' · ${context.l10n.channelFromSource(source)}';

/// "Oil" for an oil temperature channel; other names as recorded.
String readableChannel(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('oil')) return 'Oil';
  if (lower.contains('coolant') || lower.contains('water')) return 'Coolant';
  if (lower.contains('intake') || lower.contains('iat')) return 'Intake air';
  if (lower.contains('gear') || lower.contains('trans')) return 'Gearbox';
  if (lower.contains('exhaust') || lower.contains('egt')) return 'Exhaust';
  if (lower.contains('ambient')) return 'Ambient';
  return name;
}

/// The unit as shown: "°C" for a recording's "C".
String unitText(String unit) => switch (unit.trim()) {
  'C' || 'c' || '°C' || 'degC' => '°C',
  final other => other,
};

/// "104 °C", or "—" without a finite value: a missing value is never zero.
String channelValueText(double? value, String unit) {
  if (value == null || !value.isFinite) return '—';
  final suffix = unitText(unit);
  return '${value.toStringAsFixed(0)}${suffix.isEmpty ? '' : ' $suffix'}';
}

/// "mean 104 °C · 98 – 112 · 97% covered", "No valid samples" or "Not
/// recorded".
String channelSummaryText(ChannelSummary? summary, String unit) {
  if (summary == null) return 'Not recorded';
  if (!summary.valid) return 'No valid samples';
  return 'mean ${channelValueText(summary.mean, unit)} · '
      '${channelValueText(summary.minimum, '')} – ${channelValueText(summary.maximum, unit)} · '
      '${(summary.coverage * 100).round()}% covered'
      '${summary.excludedArtifacts > 0 ? ' · ${summary.excludedArtifacts} implausible left out' : ''}';
}

String _clockText(double seconds) {
  final whole = seconds.round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

String _sectionText(DayLapRow? row) => switch (row?.type) {
  LapSectionType.outLap => 'out lap',
  LapSectionType.inLap => 'in lap',
  LapSectionType.lap => 'lap ${row!.lapNumber}',
  _ => 'unknown section',
};

/// "−12 °C in 1:40 (in lap) · …", or "none recorded".
String coolingText(RunChannel channel) {
  if (channel.cooling.isEmpty) return 'none recorded';
  return [
    for (final cooling in channel.cooling)
      '−${channelValueText(cooling.interval.drop, channel.unit)} in '
          '${_clockText(cooling.interval.seconds)}'
          '${cooling.section == null ? '' : ' (${_sectionText(cooling.section)})'}',
  ].join(' · ');
}

/// One line per metric: the coefficient, its strength, the laps behind it
/// and what the sign means in these laps. Never a cause.
String associationText(String metric, RankCorrelation correlation) {
  final label = metric == 'lapTime' ? 'Lap time' : 'Strong acceleration';
  final rho = correlation.coefficient;
  if (rho == null) {
    if (correlation.unavailableReason == associationNoSpread) {
      return '$label: the temperature (or the metric) did not vary over '
          '${correlation.count} laps.';
    }
    return '$label: ${correlation.count} comparable laps with this '
        'temperature; at least $minimumAssociationSamples are needed.';
  }
  final strength = associationStrength(rho);
  final meaning = strength == 'weak'
      ? 'little association'
      : metric == 'lapTime'
      ? (rho < 0 ? 'hotter laps were quicker' : 'hotter laps were slower')
      : (rho > 0
            ? 'hotter laps accelerated harder'
            : 'hotter laps accelerated less');
  return '$label: ρ ${rho > 0 ? '+' : ''}${rho.toStringAsFixed(2)} · '
      '$strength · ${correlation.count} laps — $meaning';
}

/// The day's recorded temperatures (Overlays' "Car"): each channel per
/// session, its continuously recorded cooling and how it moved with lap
/// performance over the compared laps. Observations only.
class CarCard extends StatelessWidget {
  const CarCard({
    super.key,
    required this.channels,
    this.associations,
    this.loading = false,
    this.channelSource,
  });

  /// Null until the channel summaries are calculated.
  final DayChannelSummaries? channels;
  final TemperatureAssociations? associations;
  final bool loading;

  /// Where a session's channel came from; its own recording when null.
  final ChannelSource? channelSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channels = this.channels;
    final names = channels?.temperatureChannels ?? const <String>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Car', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (loading || channels == null)
              const Text("Reading each session's recorded temperatures…")
            else if (channels.error.isNotEmpty)
              Text(channels.error)
            else if (names.isEmpty)
              const Text(
                'None of the recordings contain a temperature channel.',
                key: ValueKey('carNoChannels'),
              )
            else ...[
              Text(
                'Each session on its own, in recording order. Gaps in a '
                'recording are never bridged; implausible readings and '
                'placeholder zeros are left out and counted. Cooling is a '
                'continuously recorded drop of at least 5° over at least '
                '30 s.',
                style: theme.textTheme.bodySmall,
              ),
              for (final name in names)
                _channel(context, channels, name, associations?.channel(name)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _channel(
    BuildContext context,
    DayChannelSummaries channels,
    String name,
    ChannelAssociation? association,
  ) {
    final theme = Theme.of(context);
    String unit = '';
    for (final run in channels.runs) {
      final channel = run.channel(name);
      if (channel != null && unit.isEmpty) unit = channel.unit;
    }
    return InkWell(
      key: ValueKey('carChannel $name'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChannelPage(
            title: readableChannel(name),
            channel: name,
            channels: channels,
            association: association,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${readableChannel(name)} · $name'
                    '${unit.isEmpty ? ' · units not declared by the recording' : ''}',
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final run in channels.runs)
                    Text(
                      '${run.runName}: ${run.unavailableReason.isNotEmpty ? run.unavailableReason : channelSummaryText(run.channel(name)?.run, unit)}'
                      '${channelSourceSuffix(context, channelSource?.call(run.runId, name) ?? '')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (association != null) ...[
                    Text(
                      associationText('lapTime', association.lapTime),
                      key: ValueKey('carAssociation $name'),
                    ),
                    if (association.confoundedByOrder)
                      Text(
                        'The temperature also changed through the day, so this '
                        'cannot be told apart from everything else that changed: '
                        'the driver, tyres, track and fuel.',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// One recorded channel opened: every session's sections, its cooling and,
/// for a temperature, how it moved with lap performance.
class ChannelPage extends StatelessWidget {
  const ChannelPage({
    super.key,
    required this.title,
    required this.channel,
    required this.channels,
    this.association,
    this.heartRate = false,
  });

  final String title;
  final String channel;
  final DayChannelSummaries channels;
  final ChannelAssociation? association;

  /// Shows each run's heart rate instead of the temperature [channel].
  final bool heartRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final association = this.association;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            heartRate
                ? 'Observed values from the recording, not an assessment.'
                : 'Every recorded section of each session.',
            style: theme.textTheme.bodySmall,
          ),
          for (final run in channels.runs) ..._run(context, run),
          if (association != null) ...[
            const SizedBox(height: 16),
            Text('With lap performance', style: theme.textTheme.titleSmall),
            Text(associationText('lapTime', association.lapTime)),
            Text(associationText('acceleration', association.acceleration)),
            if (association.confoundedByOrder)
              Text(
                'The temperature also ${(association.order.coefficient ?? 0) > 0 ? 'rose' : 'fell'} '
                'through the day (ρ ${association.order.coefficient!.toStringAsFixed(2)} '
                'with the order of laps), so this cannot be told apart from '
                'everything else that changed over the day: the driver, tyres, '
                'track and fuel.',
              ),
            const SizedBox(height: 4),
            Text(
              "Spearman rank correlation over the day's compared laps whose "
              'sensor covered at least '
              '${(minimumAssociationCoverage * 100).round()}% of the lap. '
              '${association.lowCoverageLaps} left out for low coverage, '
              '${association.notRecordedLaps} without a valid reading. It '
              'describes how the two moved together on this day; it does not '
              'establish a critical temperature or a cause.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _run(BuildContext context, RunChannelSummaries run) {
    final theme = Theme.of(context);
    final recorded = heartRate ? run.heartRate : run.channel(channel);
    return [
      const SizedBox(height: 12),
      Text(run.runName, style: theme.textTheme.titleSmall),
      if (run.unavailableReason.isNotEmpty)
        Text(run.unavailableReason)
      else if (recorded == null)
        const Text('Not recorded')
      else ...[
        Text(channelSummaryText(recorded.run, recorded.unit)),
        if (!heartRate) Text('Cooling: ${coolingText(recorded)}'),
        for (final section in recorded.sections)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${section.row.displayName.split(' · ').last}: '
              '${channelSummaryText(section.summary, recorded.unit)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    ];
  }
}

/// The driver's recorded heart rate (Overlays' heart-rate card): each
/// session's mean and range and each lap's mean. Observed values, not an
/// assessment.
class DriverCard extends StatelessWidget {
  const DriverCard({
    super.key,
    required this.channels,
    this.loading = false,
    this.onOpenLap,
    this.channelSource,
  });

  /// Null until the channel summaries are calculated.
  final DayChannelSummaries? channels;
  final bool loading;
  final void Function(DayLapRow lap)? onOpenLap;

  /// Where a session's heart rate came from; its own recording when null.
  final ChannelSource? channelSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channels = this.channels;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (loading || channels == null)
              const Text("Reading each session's recorded heart rate…")
            else if (channels.error.isNotEmpty)
              Text(channels.error)
            else if (!channels.hasHeartRate)
              const Text(
                'No heart rate recorded.',
                key: ValueKey('driverNoHeartRate'),
              )
            else ...[
              Text(
                'Heart rate from the recordings: observed values, not an '
                'assessment. Per lap: mean bpm; tap a lap to open it.',
                style: theme.textTheme.bodySmall,
              ),
              for (final run in channels.runs) ..._run(context, run),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('driverDetails'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChannelPage(
                        title: 'Heart rate',
                        channel: '',
                        channels: channels,
                        heartRate: true,
                      ),
                    ),
                  ),
                  child: const Text('Every section…'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _run(BuildContext context, RunChannelSummaries run) {
    final theme = Theme.of(context);
    final heart = run.heartRate;
    return [
      const SizedBox(height: 8),
      Text(run.runName, style: theme.textTheme.titleSmall),
      Text(
        run.unavailableReason.isNotEmpty
            ? run.unavailableReason
            : '${channelSummaryText(heart?.run, heart?.unit ?? 'bpm')}'
                  '${heart == null ? '' : channelSourceSuffix(context, channelSource?.call(run.runId, heart.channel) ?? '')}',
        key: ValueKey('heartRate ${run.runId}'),
      ),
      if (heart != null)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final section in heart.sections)
              if (section.row.type == LapSectionType.lap)
                ActionChip(
                  label: Text(
                    'LAP ${section.row.lapNumber} · '
                    '${section.summary.valid ? section.summary.mean!.toStringAsFixed(0) : '—'}',
                  ),
                  onPressed: onOpenLap == null
                      ? null
                      : () => onOpenLap!(section.row),
                ),
          ],
        ),
    ];
  }
}
