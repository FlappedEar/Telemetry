import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import '../diagnostics/app_diagnostics.dart';
import 'import_runner.dart';

/// Where an import stands.
sealed class DayImportState {
  const DayImportState();
}

final class DayImportIdle extends DayImportState {
  const DayImportIdle();
}

final class DayImportWorking extends DayImportState {
  const DayImportWorking({this.processed = 0, this.total = 0});

  /// Recordings prepared so far; 0 of 0 while still looking for recordings.
  final int processed;
  final int total;
}

final class DayImportFinished extends DayImportState {
  const DayImportFinished({
    required this.runs,
    required this.notes,
    this.analysis,
  });

  /// Primary runs, named "Session N" in recording order.
  final List<NamedRun> runs;

  /// The day's laps, groups and ranking.
  final DayAnalysis? analysis;

  /// What was skipped, grouped or failed, for the user.
  final List<String> notes;
}

final class DayImportFailed extends DayImportState {
  const DayImportFailed({required this.message, this.notes = const []});
  final String message;
  final List<String> notes;
}

final class DayImportCancelled extends DayImportState {
  const DayImportCancelled();
}

/// Runs one day import at a time and publishes its state. A result is
/// committed only while its generation is current, so a cancelled or
/// superseded import never changes what is shown.
final class DayImportController extends ChangeNotifier {
  DayImportController({
    this.importer = const IsolateDayImporter(),
    AppDiagnostics? diagnostics,
  }) : diagnostics = diagnostics ?? appDiagnostics;

  final DayImporter importer;

  /// Where a finished import's times and counts go.
  final AppDiagnostics diagnostics;
  final ImportGeneration _generation = ImportGeneration();
  DayImportJob? _job;
  DayImportState _state = const DayImportIdle();

  DayImportState get state => _state;
  bool get isWorking => _state is DayImportWorking;

  /// Starts importing [paths]. Returns false, changing nothing, while another
  /// import is running.
  bool start(List<String> paths, {required bool includeSubfolders}) {
    if (isWorking || paths.isEmpty) return false;
    final ticket = _generation.begin(paths);
    final clock = Stopwatch()..start();
    _set(const DayImportWorking());
    final job = importer.start(
      (paths: List.of(paths), includeSubfolders: includeSubfolders),
      (processed, total) {
        if (_generation.isCurrent(ticket)) {
          _set(DayImportWorking(processed: processed, total: total));
        }
      },
    );
    _job = job;
    job.result.then(
      (outcome) {
        if (!_generation.isCurrent(ticket)) return;
        final state = _finished(outcome);
        if (state is DayImportFinished) {
          _record(outcome, state.runs, clock.elapsed);
        }
        _set(state);
      },
      onError: (Object error) {
        if (!_generation.isCurrent(ticket)) return;
        _set(
          error is OperationCancelled
              ? const DayImportCancelled()
              : DayImportFailed(message: 'The import failed: $error'),
        );
      },
    );
    return true;
  }

  /// Stops the running import; nothing from it is kept.
  void cancel() {
    if (!isWorking) return;
    _generation.invalidate();
    _job?.cancel();
    _job = null;
    _set(const DayImportCancelled());
  }

  @override
  void dispose() {
    _generation.invalidate();
    _job?.cancel();
    super.dispose();
  }

  void _record(DayImportOutcome outcome, List<NamedRun> runs, Duration total) {
    var samples = 0, channelSamples = 0;
    for (final named in runs) {
      final session = named.run.telemetry;
      samples += session.sampleCount;
      for (final channel in session.channels.values) {
        channelSamples += channel.sampleCount;
      }
    }
    diagnostics.recordImport(
      ImportDiagnostics(
        steps: [
          ...outcome.steps,
          (name: DiagnosticSteps.importTotal, duration: total),
        ],
        recordings: outcome.plan?.runs.length ?? 0,
        sessions: runs.length,
        samples: samples,
        channelSamples: channelSamples,
      ),
    );
  }

  void _set(DayImportState state) {
    _state = state;
    notifyListeners();
  }
}

DayImportState _finished(DayImportOutcome outcome) {
  final notes = [...outcome.scan.notes];
  final plan = outcome.plan;
  if (plan == null) {
    return DayImportFailed(message: outcome.scan.error, notes: notes);
  }
  final names = {
    for (final run in plan.runs) run.id: p.basename(run.sourcePath),
  };
  for (final file in plan.files) {
    final name = p.basename(file.requestedPath);
    switch (file.status) {
      case TelemetryImportFileStatus.ready:
        break;
      case TelemetryImportFileStatus.duplicate:
        notes.add(
          '$name: same content as ${names[file.runId]}; imported once.',
        );
      case TelemetryImportFileStatus.error:
        notes.add('$name: ${file.message}');
    }
  }
  final groups = automaticVboPrimaries(plan);
  final primaries = primaryRuns(plan);
  for (final run in plan.runs) {
    final primary = groups[run.id];
    if (primary != null && primary != run.id) {
      notes.add(
        '${names[run.id]}: the same drive as ${names[primary]}; kept as its alternative '
        'source, channels are not combined.',
      );
    }
  }
  if (primaries.isEmpty) {
    return DayImportFailed(
      message: 'No recording could be imported.',
      notes: notes,
    );
  }
  return DayImportFinished(
    runs: outcome.runs.isNotEmpty
        ? outcome.runs
        : nameRunsInRecordingOrder(primaries),
    notes: notes,
    analysis: outcome.analysis,
  );
}
