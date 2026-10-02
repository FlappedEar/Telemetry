import 'dart:async';
import 'dart:isolate';

import 'package:telemetry_core/telemetry_core.dart';

/// What the user chose: recordings and folders, in any mix.
typedef DayImportRequest = ({List<String> paths, bool includeSubfolders});

/// The scan and the prepared plan for one request.
final class DayImportOutcome {
  const DayImportOutcome({
    required this.scan,
    this.plan,
    this.runs = const [],
    this.analysis,
  });

  final TelemetryFolderScan scan;

  /// Null when the scan found nothing to import.
  final TelemetryImportPlan? plan;

  /// The primary runs, named "Session N" in recording order.
  final List<NamedRun> runs;

  /// The day's laps, groups and ranking; null without runs.
  final DayAnalysis? analysis;
}

/// The runs a plan imports: one per drive, the VBO when a VBO and an RCZ of
/// the same drive were recorded.
List<TelemetryRunProposal> primaryRuns(TelemetryImportPlan plan) {
  final groups = automaticVboPrimaries(plan);
  return [
    for (final run in plan.runs)
      if (groups[run.id] == run.id) run,
  ];
}

/// A running import. [result] completes with [OperationCancelled] after
/// [cancel].
abstract interface class DayImportJob {
  Future<DayImportOutcome> get result;
  void cancel();
}

/// Starts imports. Replaced by a fake in widget tests.
abstract interface class DayImporter {
  /// [progress] receives (processed, total) recordings.
  DayImportJob start(
    DayImportRequest request,
    void Function(int processed, int total) progress,
  );
}

/// Scans, prepares and analyses a day synchronously: the work done in the
/// background isolate.
DayImportOutcome runDayImport(
  DayImportRequest request, {
  CancellationCheck? cancelled,
  void Function(int processed, int total)? progress,
}) {
  final scan = scanTelemetrySources(
    request.paths,
    includeSubfolders: request.includeSubfolders,
    cancelled: cancelled,
  );
  if (scan.cancelled) throw const OperationCancelled();
  if (scan.error.isNotEmpty) return DayImportOutcome(scan: scan);
  final plan = prepareTelemetryImport(
    scan.files,
    cancelled: cancelled,
    progress: progress,
  );
  final runs = nameRunsInRecordingOrder(primaryRuns(plan));
  final analysis = runs.isEmpty
      ? null
      : analyzeDay([
          for (final named in runs)
            DayRunInput(
              runId: named.run.id,
              name: named.name,
              contentSha256: named.run.contentSha256,
              session: named.run.telemetry,
              laps: named.run.laps,
            ),
        ], cancelled: cancelled);
  return DayImportOutcome(
    scan: scan,
    plan: plan,
    runs: runs,
    analysis: analysis,
  );
}

/// Runs each import in its own isolate, off the interface thread. Cancel
/// stops the isolate at once; it only reads files, so nothing is left half
/// written, and no partial plan is ever delivered.
final class IsolateDayImporter implements DayImporter {
  const IsolateDayImporter();

  @override
  DayImportJob start(
    DayImportRequest request,
    void Function(int, int) progress,
  ) => _IsolateJob(request, progress);
}

final class _IsolateJob implements DayImportJob {
  _IsolateJob(DayImportRequest request, void Function(int, int) progress) {
    _port.listen((message) {
      switch (message) {
        case (int processed, int total):
          if (!_completer.isCompleted) progress(processed, total);
        case DayImportOutcome outcome:
          _finish(() => _completer.complete(outcome));
        case [Object? error, Object? stack]:
          // An uncaught error in the isolate.
          _finish(
            () => _completer.completeError(
              error ?? 'Import failed.',
              stack is String ? StackTrace.fromString(stack) : null,
            ),
          );
        case null:
          // The isolate exited without a result.
          _finish(
            () => _completer.completeError(
              StateError('The import stopped unexpectedly.'),
            ),
          );
      }
    });
    Isolate.spawn(
      _entry,
      (_port.sendPort, request),
      onError: _port.sendPort,
      onExit: _port.sendPort,
      debugName: 'day import',
    ).then(
      (isolate) {
        _isolate = isolate;
        if (_cancelled) isolate.kill(priority: Isolate.immediate);
      },
      onError: (Object error, StackTrace stack) =>
          _finish(() => _completer.completeError(error, stack)),
    );
  }

  final _port = ReceivePort();
  final _completer = Completer<DayImportOutcome>();
  Isolate? _isolate;
  bool _cancelled = false;

  @override
  Future<DayImportOutcome> get result => _completer.future;

  @override
  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _finish(() => _completer.completeError(const OperationCancelled()));
  }

  void _finish(void Function() complete) {
    if (_completer.isCompleted) return;
    _port.close();
    complete();
  }

  static void _entry((SendPort, DayImportRequest) message) {
    final (port, request) = message;
    final outcome = runDayImport(
      request,
      progress: (processed, total) => port.send((processed, total)),
    );
    Isolate.exit(port, outcome);
  }
}
