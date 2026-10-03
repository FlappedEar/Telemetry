// Port of the time-loss and section-progression parts of FlappedEar Overlays
// native/src/telemetry/OutingTheoreticalBestResults.{h,cpp} (revision
// d4d1039, FET-35): `publishTimeLossRanking` and `publishSectorProgression`,
// the forms Overlays' TimeLossDialog.qml and SectionProgressionView.qml read.
// Overlays publishes maps for QML; here they are typed. Lap labels are left
// to the caller, which knows the laps' names.
import 'consistency.dart';
import 'outing_theoretical_best.dart';
import 'time_loss.dart';

/// Why a published time-loss ranking is unavailable when the group's best
/// lap has no time on the approved segments.
const String timeLossBestLapUntimedMessage =
    "The group's best lap could not be timed against the approved segments.";

/// A run as the progression lists it, with the context recorded for it
/// (Overlays' run metadata: name, notes, conditions and setup changes).
final class ProgressionRunInfo {
  const ProgressionRunInfo({
    required this.id,
    required this.name,
    this.notes,
    this.conditions,
    this.setupChanges,
  });

  final String id;
  final String name;

  /// Null when not recorded.
  final String? notes, conditions, setupChanges;
}

/// One observed loss as the time-loss list shows it.
final class PublishedTimeLoss {
  const PublishedTimeLoss({required this.loss, this.cornerName = ''});

  final RankedTimeLoss loss;

  /// For a straight right after a corner, the corner's name.
  final String cornerName;

  TimeLossWindow get window => loss.window;
  Object? get lapReference => loss.lapReference;
  double get lossSeconds => loss.lossSeconds;
}

/// The day's largest observed losses (Overlays' "Largest time losses"), or
/// why there are none.
final class TimeLossSummary {
  TimeLossSummary({
    required this.available,
    this.message = '',
    List<PublishedTimeLoss> losses = const [],
    this.referenceLap,
    this.allLaps = false,
    this.observationCount = 0,
    this.comparedLapCount = 0,
    this.untimedWindowCount = 0,
    this.revision = '',
  }) : losses = List.unmodifiable(losses);

  final bool available;

  /// Why it is unavailable: a sentence, or Overlays' reason code.
  final String message;

  /// Largest first, at most 50.
  final List<PublishedTimeLoss> losses;

  /// The lap every loss is measured against: the group's best lap.
  final Object? referenceLap;

  /// Every eligible lap was compared, not only each run's best.
  final bool allLaps;

  /// Losses observed before the list was cut to 50.
  final int observationCount;
  final int comparedLapCount;

  /// Segments left out because a lap did not cover them fully.
  final int untimedWindowCount;
  final String revision;
}

/// The published time losses of a ready theoretical best: each run's best
/// lap, or with [allLaps] every eligible lap, against the group's best lap.
TimeLossSummary publishTimeLossRanking(OutingTheoreticalBest computed, {bool allLaps = false}) {
  if (computed.actualBest == null) {
    return TimeLossSummary(available: false, message: timeLossBestLapUntimedMessage);
  }
  final ranking = rankOutingTimeLosses(computed, allLaps: allLaps);
  if (!ranking.valid) {
    return TimeLossSummary(available: false, message: ranking.unavailableReason);
  }
  final names = {for (final sector in computed.best.sectors) sector.segmentId: sector.name};
  return TimeLossSummary(
    available: true,
    losses: [
      for (final loss in ranking.losses)
        PublishedTimeLoss(
          loss: loss,
          cornerName: loss.window.cornerSegmentId.isEmpty
              ? ''
              : names[loss.window.cornerSegmentId] ?? '',
        ),
    ],
    referenceLap: ranking.referenceLap,
    allLaps: allLaps,
    observationCount: ranking.observationCount,
    comparedLapCount: ranking.comparedLapCount,
    untimedWindowCount: ranking.untimedWindowCount,
    revision: ranking.stamp.revision,
  );
}

/// The two laps of a loss through its segment, for the comparison it opens.
final class TimeLossComparison {
  const TimeLossComparison({
    required this.lapReference,
    required this.referenceLap,
    this.lapSeconds,
    this.referenceSeconds,
  });

  final Object? lapReference;
  final Object? referenceLap;

  /// The lap's time through the segment, or null when not fully covered.
  final double? lapSeconds;

  /// The reference lap's time through the segment, or null.
  final double? referenceSeconds;

  /// [lapSeconds] − [referenceSeconds], or null.
  double? get differenceSeconds =>
      lapSeconds != null && referenceSeconds != null ? lapSeconds! - referenceSeconds! : null;
}

/// The times of [loss]'s lap and of the group's best lap through its
/// segment, on the shared axis.
TimeLossComparison compareTimeLoss(OutingTheoreticalBest computed, PublishedTimeLoss loss) {
  final segmentId = loss.window.segmentId;
  double? lapSeconds;
  for (final lap in computed.population) {
    if (lap.times.lapReference == loss.lapReference) {
      lapSeconds = lap.times.sector(segmentId)?.seconds;
    }
  }
  final reference = computed.actualBest;
  return TimeLossComparison(
    lapReference: loss.lapReference,
    referenceLap: reference?.lapReference,
    lapSeconds: lapSeconds,
    referenceSeconds: reference?.sector(segmentId)?.seconds,
  );
}

/// A run in the section progression, with its laps' consistency.
final class SectionProgressionSession {
  const SectionProgressionSession({required this.run, required this.laps});

  final ProgressionRunInfo run;

  /// The lap times of its laps in the population.
  final ConsistencySummary laps;

  String get runId => run.id;
}

/// One lap's time through one section.
final class SectionLapTime {
  const SectionLapTime(this.seconds, this.reference);

  final double seconds;
  final Object? reference;
}

/// One section in one run.
final class SectionProgressionCell {
  SectionProgressionCell({
    required this.runId,
    required this.summary,
    List<SectionLapTime> laps = const [],
  }) : laps = List.unmodifiable(laps);

  final String runId;

  /// Median and interquartile range, unavailable below three laps.
  final ConsistencySummary summary;

  /// The laps behind it, quickest first.
  final List<SectionLapTime> laps;
}

/// One section across the runs.
final class SectionProgressionRow {
  SectionProgressionRow({
    required this.segmentId,
    required this.name,
    required this.type,
    required List<SectionProgressionCell> cells,
    this.fastestTypical,
  }) : cells = List.unmodifiable(cells);

  final String segmentId;
  final String name;
  final String type;

  /// One per session, in session order.
  final List<SectionProgressionCell> cells;

  /// The quickest median of any run, when one has one.
  final double? fastestTypical;
}

/// Each section's typical time and spread per run (Overlays' "By section").
final class SectionProgression {
  SectionProgression({
    List<SectionProgressionSession> sessions = const [],
    List<SectionProgressionRow> segments = const [],
  }) : sessions = List.unmodifiable(sessions),
       segments = List.unmodifiable(segments);

  /// The runs with laps in the population, in [publishSectorProgression]'s
  /// order.
  final List<SectionProgressionSession> sessions;

  /// By where they start on the track.
  final List<SectionProgressionRow> segments;
}

/// Each approved section's median and interquartile range per run of
/// [order] (the progression's order; runs without laps in the population
/// are left out), across the laps timed on the shared axis.
SectionProgression publishSectorProgression(
  OutingTheoreticalBest computed,
  List<ProgressionRunInfo> order,
) {
  final byRun = <String, List<TimedLapSectors>>{};
  for (var i = 0; i < computed.population.length; ++i) {
    (byRun[computed.runIds[i]] ??= []).add(computed.population[i]);
  }
  final sessions = [
    for (final run in order)
      if (byRun[run.id] case final laps?)
        SectionProgressionSession(
          run: run,
          laps: summarizeConsistency([for (final lap in laps) lap.times.lapSeconds]),
        ),
  ];
  double start(Map<String, Object?> segment) =>
      (segment['startProgressMeters'] as num?)?.toDouble() ?? 0.0;
  String text(Object? value) => value is String ? value : '';
  final segments = [...computed.approved.segments];
  final indices = [for (var i = 0; i < segments.length; ++i) i]
    ..sort((a, b) {
      final order = start(segments[a]).compareTo(start(segments[b]));
      return order != 0 ? order : a.compareTo(b);
    });
  final rows = <SectionProgressionRow>[];
  for (final index in indices) {
    final segment = segments[index];
    final segmentId = text(segment['id']);
    double? fastestTypical;
    final cells = <SectionProgressionCell>[];
    for (final session in sessions) {
      final laps = <SectionLapTime>[];
      for (final lap in byRun[session.runId]!) {
        if (lap.times.stamp.revision != computed.approved.revision) continue;
        for (final sector in lap.times.sectors) {
          if (sector.segmentId != segmentId || sector.seconds == null) continue;
          laps.add(SectionLapTime(sector.seconds!, lap.times.lapReference));
        }
      }
      final summary = summarizeConsistency([for (final lap in laps) lap.seconds]);
      if (summary.available && (fastestTypical == null || summary.median! < fastestTypical)) {
        fastestTypical = summary.median;
      }
      cells.add(
        SectionProgressionCell(runId: session.runId, summary: summary, laps: _quickestFirst(laps)),
      );
    }
    rows.add(
      SectionProgressionRow(
        segmentId: segmentId,
        name: text(segment['name']),
        type: text(segment['type']),
        cells: cells,
        fastestTypical: fastestTypical,
      ),
    );
  }
  return SectionProgression(sessions: sessions, segments: rows);
}

// Stable, so equal times keep their population order.
List<SectionLapTime> _quickestFirst(List<SectionLapTime> laps) {
  final indices = [for (var i = 0; i < laps.length; ++i) i]
    ..sort((a, b) {
      final order = laps[a].seconds.compareTo(laps[b].seconds);
      return order != 0 ? order : a.compareTo(b);
    });
  return [for (final index in indices) laps[index]];
}
