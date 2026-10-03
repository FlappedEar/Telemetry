// "Make primary" for a run's recordings (FET-57), as FlappedEar Overlays'
// Run details does it (KAN-90: setRunPrimarySource): the run is read from
// another of its recordings. Its laps are derived again from that
// recording, its fusion no longer applies (the user sees the recording it
// replaced kept beside it, [RunFusionState.primaryOnly]) and a layout the
// user asserted for the old recording is not inherited. The document is
// written by [dayDocument]: the new `primaryTelemetrySourceId`, no `fusion`
// and the unknown track configuration of the new recording.
import 'dart:io';

import '../intake/import_plan.dart';
import '../intake/recording_source.dart';
import '../operation.dart';
import 'day_analysis.dart';
import 'day_laps.dart';

/// [run] (a day's run) read from its other [recording] instead: the run's
/// id, the recording's source id, file, content and laps.
TelemetryRunProposal runFromRecording(TelemetryRunProposal run, TelemetryRunProposal recording) =>
    TelemetryRunProposal(
      id: run.id,
      sourceId: recording.sourceId,
      sourcePath: recording.sourcePath,
      format: recording.format,
      contentSha256: recording.contentSha256,
      telemetry: recording.telemetry,
      laps: recording.laps,
    );

/// The lap rows, route and messages of run [runId] named [name] read from
/// its new primary [run] ([runFromRecording]), for [replaceDayRun]. The
/// day keeps [otherRows] lap sections of its other runs. Heavy: run it in
/// the background.
DayRunsPart analyzeNewPrimary(
  TelemetryRunProposal run,
  String name, {
  int otherRows = 0,
  CancellationCheck? cancelled,
}) => analyzeDayRuns(
  [
    DayRunInput(
      runId: run.id,
      name: name,
      contentSha256: run.contentSha256,
      session: run.telemetry,
      laps: run.laps,
    ),
  ],
  existingRows: otherRows,
  cancelled: cancelled,
);

/// The place of run [runId] in [day]'s order ([DayLapRow.sourceOrder]),
/// or [fallback] when it has no lap rows.
int runSourceOrder(DayAnalysis day, String runId, int fallback) {
  for (final DayLapRow row in day.rows) {
    if (row.runId == runId) return row.sourceOrder;
  }
  return fallback;
}

/// Why a recording cannot become a run's primary.
enum NewPrimaryProblem {
  /// The file is not where the day read it from any more.
  missing,

  /// The file there now holds other content than the recording read.
  changed,

  /// Its laps could not be derived.
  failed,
}

/// The lap rows, route and messages of [run] (see [analyzeNewPrimary]) once
/// its file is checked to be still the recording that was read, as
/// Overlays checks it before making it the primary: still there, with the
/// same content SHA-256. Otherwise why not, and nothing. Heavy: run it in
/// the background.
({DayRunsPart? part, NewPrimaryProblem? problem}) prepareNewPrimary(
  TelemetryRunProposal run,
  String name, {
  int otherRows = 0,
  CancellationCheck? cancelled,
}) {
  final file = File(run.sourcePath);
  final int size;
  try {
    if (!file.existsSync()) return (part: null, problem: NewPrimaryProblem.missing);
    size = file.lengthSync();
  } on FileSystemException {
    return (part: null, problem: NewPrimaryProblem.missing);
  }
  try {
    if (contentSha256(run.sourcePath, size, cancelled: cancelled) != run.contentSha256) {
      return (part: null, problem: NewPrimaryProblem.changed);
    }
  } on OperationCancelled {
    rethrow;
  } on Exception {
    return (part: null, problem: NewPrimaryProblem.changed);
  }
  try {
    return (
      part: analyzeNewPrimary(run, name, otherRows: otherRows, cancelled: cancelled),
      problem: null,
    );
  } on OperationCancelled {
    rethrow;
  } on Exception {
    return (part: null, problem: NewPrimaryProblem.failed);
  }
}
