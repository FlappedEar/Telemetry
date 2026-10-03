// Port of FlappedEar Overlays native/src/telemetry/OutingChannelSummaries.{h,cpp}
// and of AnalysisController::outingTemperatureAssociations
// (native/src/app/AnalysisControllerChannelSummaries.cpp, revision d4d1039,
// FET-36): the recorded channel summaries of every run and recorded section
// of a day (KAN-67/68/69), each section's strong acceleration and how each
// temperature moves with lap performance over the comparable laps (KAN-100).
// They do not depend on segmentation or on the compared group: vehicle
// health applies to every run.
//
// Overlays loads and verifies each recording from the project
// (`loadOutingLapDetail`); here the caller passes the sessions it already
// holds, and a run without one says why.
import '../analysis/channel_summary.dart';
import '../analysis/temperature_association.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import 'day_laps.dart';

/// Bins of a run's trend trace.
const int channelTrendBins = 120;

/// Why a run has no channel summaries when its recording is not loaded.
const String channelRecordingUnavailable = 'Recording unavailable.';

/// One channel over one recorded section (OUT, a lap, IN).
final class ChannelSection {
  const ChannelSection({required this.row, required this.summary});

  final DayLapRow row;
  final ChannelSummary summary;
}

/// One bin of a trend trace: its middle and the channel's mean there.
typedef ChannelTrendPoint = ({double time, double mean});

/// A continuously recorded cooling and the section it started in.
final class ChannelCooling {
  const ChannelCooling({required this.interval, this.section});

  final CoolingInterval interval;

  /// The recorded section the cooling started in (a cool-down lap, the pit
  /// lane), or null.
  final DayLapRow? section;
}

/// One recorded channel of one run.
final class RunChannel {
  RunChannel({
    required this.channel,
    required this.unit,
    required this.run,
    List<ChannelSection> sections = const [],
    List<ChannelTrendPoint?> trace = const [],
    List<ChannelCooling> cooling = const [],
  }) : sections = List.unmodifiable(sections),
       trace = List.unmodifiable(trace),
       cooling = List.unmodifiable(cooling);

  final String channel;
  final String unit;

  /// The whole recording.
  final ChannelSummary run;

  /// Every recorded section of the run, in the day's order.
  final List<ChannelSection> sections;

  /// [channelTrendBins] bins over the recording; a bin inside a recording
  /// gap is null (never interpolated), so a drawn curve breaks there.
  final List<ChannelTrendPoint?> trace;

  /// Continuously recorded cooling (temperatures only).
  final List<ChannelCooling> cooling;
}

/// One section's strong acceleration (KAN-100).
final class SectionAcceleration {
  const SectionAcceleration({required this.row, required this.acceleration});

  final DayLapRow row;
  final LapAcceleration acceleration;
}

/// One run's recorded channels.
final class RunChannelSummaries {
  RunChannelSummaries({
    required this.runId,
    required this.runName,
    this.unavailableReason = '',
    List<RunChannel> channels = const [],
    List<SectionAcceleration> laps = const [],
    this.heartRate,
  }) : channels = List.unmodifiable(channels),
       laps = List.unmodifiable(laps);

  final String runId;
  final String runName;

  /// Why the recording could not be read; empty when it was.
  final String unavailableReason;

  /// Every recorded temperature channel, in name order.
  final List<RunChannel> channels;

  /// Every section's strong acceleration, in the same order as the
  /// sections.
  final List<SectionAcceleration> laps;

  /// The recording's own heart-rate channel, when it has one.
  final RunChannel? heartRate;

  /// The temperature channel [name], or null.
  RunChannel? channel(String name) {
    for (final channel in channels) {
      if (channel.channel == name) return channel;
    }
    return null;
  }
}

/// The channel summaries of a day's runs.
final class DayChannelSummaries {
  DayChannelSummaries({List<RunChannelSummaries> runs = const [], this.error = ''})
    : runs = List.unmodifiable(runs);

  /// In first-seen order of the day's sections.
  final List<RunChannelSummaries> runs;

  /// Set when the calculation failed or was cancelled.
  final String error;

  /// Temperature channel names, first seen across runs.
  List<String> get temperatureChannels {
    final names = <String>[];
    for (final run in runs) {
      for (final channel in run.channels) {
        if (!names.contains(channel.channel)) names.add(channel.channel);
      }
    }
    return names;
  }

  /// Whether any run has a heart-rate channel.
  bool get hasHeartRate => runs.any((run) => run.heartRate != null);
}

List<ChannelTrendPoint?> _trend(ChannelSummarizer summarizer, double start, double end) {
  if (end <= start) return const [];
  final width = (end - start) / channelTrendBins;
  return [
    for (var bin = 0; bin < channelTrendBins; ++bin)
      () {
        final from = start + bin * width;
        final summary = summarizer.summarize(from, from + width);
        return summary.valid ? (time: from + width / 2, mean: summary.mean!) : null;
      }(),
  ];
}

RunChannel _runChannel(
  TelemetrySession session,
  String name,
  List<DayLapRow> rows,
  ChannelSummaryPolicy policy, {
  required bool cooling,
}) {
  final summarizer = ChannelSummarizer(session, name, policy);
  final channel = session.channels[name]!;
  final times = channel.timestamps;
  final start = times.isEmpty ? 0.0 : times.first;
  final end = times.isEmpty ? 0.0 : times.last;
  return RunChannel(
    channel: name,
    unit: channel.unit,
    run: summarizer.summarize(start, session.duration + start),
    sections: [
      for (final row in rows)
        ChannelSection(row: row, summary: summarizer.summarize(row.start, row.end)),
    ],
    trace: _trend(summarizer, start, end),
    cooling: cooling
        ? [
            for (final interval in findCoolingIntervals(session, name, policy))
              ChannelCooling(
                interval: interval,
                section: rows
                    .where((row) => interval.startTime >= row.start && interval.startTime < row.end)
                    .firstOrNull,
              ),
          ]
        : const [],
  );
}

/// Per run (in first-seen order of [rows], the day's sections): every
/// recorded temperature channel with its whole-recording summary, one
/// summary per recorded section, a bounded gap-aware trend trace and the
/// continuously recorded cooling; heart rate from the recording's own
/// channel; and each section's strong acceleration. [sessions] are the
/// runs' recordings by run id; a run without one says why. Cooperatively
/// cancellable; a cancelled or failed calculation says so in
/// [DayChannelSummaries.error].
DayChannelSummaries summarizeDayChannels(
  List<DayLapRow> rows,
  Map<String, TelemetrySession?> sessions, {
  CancellationCheck? cancelled,
}) {
  final byRun = <String, List<DayLapRow>>{};
  for (final row in rows) {
    (byRun[row.runId] ??= []).add(row);
  }
  final runs = <RunChannelSummaries>[];
  try {
    for (final MapEntry(key: runId, value: runRows) in byRun.entries) {
      throwIfCancelled(cancelled);
      final runName = runRows.first.runName;
      final session = sessions[runId];
      if (session == null) {
        runs.add(
          RunChannelSummaries(
            runId: runId,
            runName: runName,
            unavailableReason: channelRecordingUnavailable,
          ),
        );
        continue;
      }
      final channels = <RunChannel>[];
      for (final name in recordedTemperatureChannels(session)) {
        throwIfCancelled(cancelled);
        channels.add(_runChannel(session, name, runRows, temperatureSummaryPolicy, cooling: true));
      }
      // KAN-69: heart rate from the recording's own heart-rate channel (the
      // imported VBO/RCZ; never a separate source).
      final heartRate = session.aliases['heartRate'] ?? '';
      runs.add(
        RunChannelSummaries(
          runId: runId,
          runName: runName,
          channels: channels,
          laps: [
            for (final row in runRows)
              SectionAcceleration(
                row: row,
                acceleration: lapStrongAcceleration(session, row.start, row.end),
              ),
          ],
          heartRate: heartRate.isNotEmpty && session.channels.containsKey(heartRate)
              ? _runChannel(session, heartRate, runRows, heartRateSummaryPolicy, cooling: false)
              : null,
        ),
      );
    }
  } on OperationCancelled {
    return DayChannelSummaries(runs: runs, error: 'Channel summaries were cancelled.');
  }
  return DayChannelSummaries(runs: runs);
}

/// One eligible lap in a temperature association.
final class AssociationLap {
  const AssociationLap({
    required this.row,
    required this.temperature,
    required this.lapTime,
    required this.coverage,
    this.strongAccelerationG,
  });

  final DayLapRow row;

  /// The channel's mean over the lap.
  final double temperature;
  final double lapTime;
  final double coverage;
  final double? strongAccelerationG;
}

/// One temperature channel against lap performance.
final class ChannelAssociation {
  ChannelAssociation({
    required this.channel,
    required this.unit,
    required this.lapTime,
    required this.acceleration,
    required this.order,
    required this.confoundedByOrder,
    required this.lowCoverageLaps,
    required this.notRecordedLaps,
    List<AssociationLap> observations = const [],
  }) : observations = List.unmodifiable(observations);

  final String channel;
  final String unit;

  /// The temperature against lap time.
  final RankCorrelation lapTime;

  /// The temperature against strong acceleration.
  final RankCorrelation acceleration;

  /// The temperature against the order of the laps through the day.
  final RankCorrelation order;
  final bool confoundedByOrder;

  /// Eligible laps left out because the sensor covered too little of them.
  final int lowCoverageLaps;

  /// Eligible laps without a valid recorded temperature.
  final int notRecordedLaps;

  /// The laps behind it, in day order.
  final List<AssociationLap> observations;
}

/// Every recorded temperature of a day against lap performance.
final class TemperatureAssociations {
  TemperatureAssociations({this.eligibleLaps = 0, List<ChannelAssociation> channels = const []})
    : channels = List.unmodifiable(channels);

  final int eligibleLaps;

  /// In first-seen order across runs.
  final List<ChannelAssociation> channels;

  /// The association of [name], or null.
  ChannelAssociation? channel(String name) {
    for (final channel in channels) {
      if (channel.channel == name) return channel;
    }
    return null;
  }
}

/// How each temperature of [summaries] moves with lap time and strong
/// acceleration over the [eligible] laps (the compared group's eligible
/// laps), and with the order of those laps through the day: runs in their
/// order and laps in run order. A lap counts when the sensor covered at
/// least [minimumAssociationCoverage] of it.
TemperatureAssociations dayTemperatureAssociations(
  DayChannelSummaries summaries,
  Iterable<DayLapReference> eligible,
) {
  final eligibleKeys = eligible.toSet();
  final names = <String>[];
  final units = <String, String>{};
  for (final run in summaries.runs) {
    for (final channel in run.channels) {
      if (!names.contains(channel.channel)) {
        names.add(channel.channel);
        units[channel.channel] = channel.unit;
      }
    }
  }
  final channels = <ChannelAssociation>[];
  for (final name in names) {
    final lapTimes = <AssociationObservation>[], accelerations = <AssociationObservation>[];
    final observations = <AssociationLap>[];
    var lowCoverage = 0, notRecorded = 0;
    for (final run in summaries.runs) {
      RunChannel? channel;
      for (final candidate in run.channels) {
        if (candidate.channel == name) channel = candidate;
      }
      final sections = channel?.sections ?? const <ChannelSection>[];
      for (var index = 0; index < run.laps.length; ++index) {
        final lap = run.laps[index];
        if (!eligibleKeys.contains(lap.row.reference)) continue;
        final section = index < sections.length ? sections[index].summary : null;
        if (section == null || !section.valid) {
          ++notRecorded;
          continue;
        }
        if (section.coverage < minimumAssociationCoverage) {
          ++lowCoverage;
          continue;
        }
        final temperature = section.mean!;
        final lapTime = lap.row.end - lap.row.start;
        // Order through the day: runs are in recording order and laps in run
        // order (each run's clock only orders its own laps).
        final order = observations.length.toDouble();
        lapTimes.add(AssociationObservation(temperature, lapTime, order));
        final strong = lap.acceleration.strongG;
        if (strong != null) accelerations.add(AssociationObservation(temperature, strong, order));
        observations.add(
          AssociationLap(
            row: lap.row,
            temperature: temperature,
            lapTime: lapTime,
            coverage: section.coverage,
            strongAccelerationG: strong,
          ),
        );
      }
    }
    final withLapTime = associateTemperature(lapTimes);
    final withAcceleration = associateTemperature(accelerations);
    channels.add(
      ChannelAssociation(
        channel: name,
        unit: units[name] ?? '',
        lapTime: withLapTime.withValue,
        acceleration: withAcceleration.withValue,
        order: withLapTime.withOrder,
        confoundedByOrder: withLapTime.confoundedByOrder,
        lowCoverageLaps: lowCoverage,
        notRecordedLaps: notRecorded,
        observations: observations,
      ),
    );
  }
  return TemperatureAssociations(eligibleLaps: eligibleKeys.length, channels: channels);
}

/// A [ChannelSummary] as the day report (and Overlays' screens) write it.
Map<String, Object?> channelSummaryMap(ChannelSummary summary) => {
  'valid': summary.valid,
  'sampleCount': summary.sampleCount,
  'excludedArtifacts': summary.excludedArtifacts,
  'coverage': summary.coverage,
  'coveredSeconds': summary.coveredSeconds,
  'startTime': summary.startTime,
  'endTime': summary.endTime,
  if (!summary.valid)
    'unavailableReason': summary.unavailableReason
  else ...{
    'minimum': summary.minimum,
    'maximum': summary.maximum,
    'mean': summary.mean,
    'minimumTime': summary.minimumTime,
    'maximumTime': summary.maximumTime,
  },
};
