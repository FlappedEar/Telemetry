import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../channel_names.dart';
import '../l10n.dart';
import 'touch.dart';
import 'theoretical_best_card.dart' show CalculateAgainButton;
import '../ui/readable_list.dart';

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

/// [readableChannel] in the app's language: "Olej".
String channelLabel(AppLocalizations l10n, String name) =>
    switch (readableChannel(name)) {
      'Oil' => l10n.channelOil,
      'Coolant' => l10n.channelCoolant,
      'Intake air' => l10n.channelIntakeAir,
      'Gearbox' => l10n.channelGearbox,
      'Exhaust' => l10n.channelExhaust,
      'Ambient' => l10n.channelAmbient,
      final other => other,
    };

/// The name the driver gave channel [name] in settings, else
/// [channelLabel]; rebuilds [context] when a name changes.
String channelLabelIn(BuildContext context, String name) {
  final named = channelNameOf(context, name);
  return named == name ? channelLabel(context.l10n, name) : named;
}

/// A reason or error from `telemetry_core` channel summaries in the app's
/// language; a failure of the work itself is translated where it is known.
String _channelReason(AppLocalizations l10n, String reason) => switch (reason) {
  channelRecordingUnavailable => l10n.channelRecordingUnavailable,
  'Channel summaries were cancelled.' => l10n.channelSummariesCancelled,
  _ => l10n.taskFailure(reason),
};

/// The unit as shown: "°C" for a recording's "C".
String unitText(String unit) => switch (unit.trim()) {
  'C' || 'c' || '°C' || 'degC' => '°C',
  final other => other,
};

/// "104 °C", or "—" without a finite value: a missing value is never zero.
String channelValueText(double? value, String unit) {
  if (value == null || !value.isFinite) return '—';
  final suffix = unitText(unit);
  return '${value.toStringAsFixed(0)}${suffix.isEmpty ? '' : '\u00a0$suffix'}';
}

/// "mean 104 °C · 98 – 112 · 97% covered", "No valid samples" or "Not
/// recorded".
String channelSummaryText(
  AppLocalizations l10n,
  ChannelSummary? summary,
  String unit,
) {
  if (summary == null) return l10n.channelNotRecorded;
  if (!summary.valid) return l10n.channelNoValidSamples;
  return l10n.channelSummary(
        channelValueText(summary.mean, unit),
        channelValueText(summary.minimum, ''),
        channelValueText(summary.maximum, unit),
        (summary.coverage * 100).round(),
      ) +
      (summary.excludedArtifacts > 0
          ? ' · ${l10n.channelImplausibleLeftOut(summary.excludedArtifacts)}'
          : '');
}

String _clockText(double seconds) {
  final whole = seconds.round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

String _sectionText(AppLocalizations l10n, DayLapRow? row) =>
    switch (row?.type) {
      LapSectionType.outLap => l10n.channelOutLap,
      LapSectionType.inLap => l10n.channelInLap,
      LapSectionType.lap => l10n.channelLapSection(row!.lapNumber),
      _ => l10n.channelUnknownSection,
    };

/// "−12 °C in 1:40 (in lap) · …", or "none recorded".
String coolingText(AppLocalizations l10n, RunChannel channel) {
  if (channel.cooling.isEmpty) return l10n.channelCoolingNone;
  return [
    for (final cooling in channel.cooling)
      l10n.channelCoolingDrop(
            channelValueText(cooling.interval.drop, channel.unit),
            _clockText(cooling.interval.seconds),
          ) +
          (cooling.section == null
              ? ''
              : ' (${_sectionText(l10n, cooling.section)})'),
  ].join(' · ');
}

/// One line per metric: the coefficient, its strength, the laps behind it
/// and what the sign means in these laps. Never a cause.
String associationText(
  AppLocalizations l10n,
  String metric,
  RankCorrelation correlation,
) {
  final label = metric == 'lapTime'
      ? l10n.channelLapTime
      : l10n.channelStrongAcceleration;
  final rho = correlation.coefficient;
  if (rho == null) {
    if (correlation.unavailableReason == associationNoSpread) {
      return l10n.channelAssociationNoSpread(label, correlation.count);
    }
    return l10n.channelAssociationTooFew(
      label,
      correlation.count,
      minimumAssociationSamples,
    );
  }
  final strength = associationStrength(rho);
  final meaning = strength == 'weak'
      ? l10n.channelMeaningLittle
      : metric == 'lapTime'
      ? (rho < 0 ? l10n.channelMeaningQuicker : l10n.channelMeaningSlower)
      : (rho > 0 ? l10n.channelMeaningHarder : l10n.channelMeaningLess);
  return l10n.channelAssociation(
    label,
    '${rho > 0 ? '+' : ''}${rho.toStringAsFixed(2)}',
    switch (strength) {
      'weak' => l10n.channelStrengthWeak,
      'moderate' => l10n.channelStrengthModerate,
      'strong' => l10n.channelStrengthStrong,
      final other => other,
    },
    correlation.count,
    meaning,
  );
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
    this.onRetry,
    this.channelSource,
  });

  /// Null until the channel summaries are calculated.
  final DayChannelSummaries? channels;
  final TemperatureAssociations? associations;
  final bool loading;

  /// Summarizes the channels again after they failed.
  final VoidCallback? onRetry;

  /// Where a session's channel came from; its own recording when null.
  final ChannelSource? channelSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final channels = this.channels;
    final names = channels?.temperatureChannels ?? const <String>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.channelCarTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (loading || channels == null)
              Text(l10n.channelCarReading)
            else if (channels.error.isNotEmpty) ...[
              Text(_channelReason(l10n, channels.error)),
              if (onRetry case final retry?) CalculateAgainButton(retry),
            ] else if (names.isEmpty)
              Text(
                l10n.channelCarNoChannels,
                key: const ValueKey('carNoChannels'),
              )
            else ...[
              Text(l10n.channelCarIntro, style: theme.textTheme.bodySmall),
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
    final l10n = context.l10n;
    String unit = '';
    for (final run in channels.runs) {
      final channel = run.channel(name);
      if (channel != null && unit.isEmpty) unit = channel.unit;
    }
    return ButtonRow(
      child: InkWell(
        key: ValueKey('carChannel $name'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChannelPage(
              title: channelLabelIn(context, name),
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
                      '${channelLabelIn(context, name)} · $name'
                      '${unit.isEmpty ? ' · ${l10n.channelUnitsNotDeclared}' : ''}',
                      style: theme.textTheme.titleSmall,
                    ),
                    for (final run in channels.runs)
                      Text(
                        '${l10n.session(run.runName)}: ${run.unavailableReason.isNotEmpty ? _channelReason(l10n, run.unavailableReason) : channelSummaryText(l10n, run.channel(name)?.run, unit)}'
                        '${channelSourceSuffix(context, channelSource?.call(run.runId, name) ?? '')}',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (association != null) ...[
                      Text(
                        associationText(l10n, 'lapTime', association.lapTime),
                        key: ValueKey('carAssociation $name'),
                      ),
                      if (association.confoundedByOrder)
                        Text(
                          l10n.channelConfounded,
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
    final l10n = context.l10n;
    final association = this.association;
    return Scaffold(
      appBar: AppBar(
        title: Text(heartRate ? title : channelLabelIn(context, channel)),
      ),
      body: ReadableListView(
        children: [
          Text(
            heartRate
                ? l10n.channelHeartRateIntro
                : l10n.channelEverySectionIntro,
            style: theme.textTheme.bodySmall,
          ),
          for (final run in channels.runs) ..._run(context, run),
          if (association != null) ...[
            const SizedBox(height: 16),
            Text(
              l10n.channelWithLapPerformance,
              style: theme.textTheme.titleSmall,
            ),
            Text(associationText(l10n, 'lapTime', association.lapTime)),
            Text(
              associationText(l10n, 'acceleration', association.acceleration),
            ),
            if (association.confoundedByOrder)
              Text(
                (association.order.coefficient ?? 0) > 0
                    ? l10n.channelConfoundedRose(
                        association.order.coefficient!.toStringAsFixed(2),
                      )
                    : l10n.channelConfoundedFell(
                        association.order.coefficient!.toStringAsFixed(2),
                      ),
              ),
            const SizedBox(height: 4),
            Text(
              l10n.channelSpearman(
                (minimumAssociationCoverage * 100).round(),
                association.lowCoverageLaps,
                association.notRecordedLaps,
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _run(BuildContext context, RunChannelSummaries run) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final recorded = heartRate ? run.heartRate : run.channel(channel);
    return [
      const SizedBox(height: 12),
      Text(l10n.session(run.runName), style: theme.textTheme.titleSmall),
      if (run.unavailableReason.isNotEmpty)
        Text(_channelReason(l10n, run.unavailableReason))
      else if (recorded == null)
        Text(l10n.channelNotRecorded)
      else ...[
        Text(channelSummaryText(l10n, recorded.run, recorded.unit)),
        if (!heartRate) Text(l10n.channelCooling(coolingText(l10n, recorded))),
        for (final section in recorded.sections)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${l10n.lap(section.row).split(' · ').last}: '
              '${channelSummaryText(l10n, section.summary, recorded.unit)}',
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
    this.onRetry,
    this.onOpenLap,
    this.channelSource,
  });

  /// Null until the channel summaries are calculated.
  final DayChannelSummaries? channels;
  final bool loading;

  /// Summarizes the channels again after they failed.
  final VoidCallback? onRetry;
  final void Function(DayLapRow lap)? onOpenLap;

  /// Where a session's heart rate came from; its own recording when null.
  final ChannelSource? channelSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final channels = this.channels;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.channelDriverTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (loading || channels == null)
              Text(l10n.channelDriverReading)
            else if (channels.error.isNotEmpty) ...[
              Text(_channelReason(l10n, channels.error)),
              if (onRetry case final retry?) CalculateAgainButton(retry),
            ] else if (!channels.hasHeartRate)
              Text(
                l10n.channelDriverNoHeartRate,
                key: const ValueKey('driverNoHeartRate'),
              )
            else ...[
              Text(l10n.channelDriverIntro, style: theme.textTheme.bodySmall),
              for (final run in channels.runs) ..._run(context, run),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('driverDetails'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChannelPage(
                        title: l10n.channelHeartRate,
                        channel: '',
                        channels: channels,
                        heartRate: true,
                      ),
                    ),
                  ),
                  child: Text(l10n.channelEverySection),
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
    final l10n = context.l10n;
    final heart = run.heartRate;
    return [
      const SizedBox(height: 8),
      Text(l10n.session(run.runName), style: theme.textTheme.titleSmall),
      Text(
        run.unavailableReason.isNotEmpty
            ? _channelReason(l10n, run.unavailableReason)
            : '${channelSummaryText(l10n, heart?.run, heart?.unit ?? 'bpm')}'
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
                    l10n.channelLapMean(
                      section.row.lapNumber,
                      section.summary.valid
                          ? section.summary.mean!.toStringAsFixed(0)
                          : '—',
                    ),
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
