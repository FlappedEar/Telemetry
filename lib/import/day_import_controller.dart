import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../diagnostics/app_diagnostics.dart';
import '../diagnostics/app_errors.dart';
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
    this.alternatives = const {},
  });

  /// Primary runs, named "Session N" in recording order.
  final List<NamedRun> runs;

  /// The day's laps, groups and ranking.
  final DayAnalysis? analysis;

  /// Each run's RCZ, by run id: aligned and fused once the day shows.
  final Map<String, TelemetryRunProposal> alternatives;

  /// What was skipped, grouped or failed, for the user.
  final List<String> notes;
}

final class DayImportFailed extends DayImportState {
  const DayImportFailed({
    required this.message,
    this.notes = const [],
    this.reviewChanged = false,
  });
  final String message;
  final List<String> notes;

  /// Nothing was imported because the recordings changed after the review
  /// ([message] is empty; the page says so).
  final bool reviewChanged;
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
  /// import is running. With [choices] (from a review), the recordings are
  /// imported as the user chose.
  bool start(
    List<String> paths, {
    required bool includeSubfolders,
    ImportChoices? choices,
  }) {
    if (isWorking || paths.isEmpty) return false;
    _import(paths, includeSubfolders: includeSubfolders, choices: choices);
    return true;
  }

  void _import(
    List<String> paths, {
    required bool includeSubfolders,
    ImportChoices? choices,
  }) {
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
      choices: choices,
    );
    _job = job;
    job.result.then(
      (outcome) {
        if (!_generation.isCurrent(ticket)) return;
        appErrorReporter.coreDefects(
          plan: outcome.plan,
          messages: outcome.analysis?.messages ?? const [],
        );
        final state = _finished(outcome);
        if (state is DayImportFinished) {
          _record(outcome, state.runs, clock.elapsed);
        }
        _set(state);
      },
      onError: (Object error, StackTrace stack) {
        if (!_generation.isCurrent(ticket)) return;
        // A defect, not a bad recording: kept for a bug report.
        if (error is Error) reportError(error, stack, context: 'Importing');
        _set(
          error is OperationCancelled
              ? const DayImportCancelled()
              : DayImportFailed(message: 'The import failed: $error'),
        );
      },
    );
  }

  /// Forgets a finished import once its day has been shown: from then on
  /// the day lives in its controller, its recovery snapshot or its saved
  /// document, and a fresh day built from this result would replace it.
  void clearFinished() {
    if (_state is! DayImportFinished) return;
    _set(const DayImportIdle());
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
  final plan = outcome.plan;
  if (plan == null) {
    return DayImportFailed(
      message: outcome.scan.error,
      notes: outcome.scan.notes,
    );
  }
  if (outcome.reviewChanged) {
    return DayImportFailed(
      message: '',
      notes: outcome.scan.notes,
      reviewChanged: true,
    );
  }
  final choices = outcome.choices;
  final notes = importPlanNotes(outcome.scan, plan, choices: choices);
  final primaries = primaryRuns(plan, choices: choices);
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
    alternatives: outcome.alternatives,
  );
}
