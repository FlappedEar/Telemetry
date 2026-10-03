import 'dart:async';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import '../diagnostics/app_diagnostics.dart';

/// What the user chose: recordings and folders, in any mix.
typedef DayImportRequest = ({List<String> paths, bool includeSubfolders});

/// The scan and the prepared plan for one request.
final class DayImportOutcome {
  const DayImportOutcome({
    required this.scan,
    this.plan,
    this.runs = const [],
    this.analysis,
    this.alternatives = const {},
    this.steps = const [],
  });

  final TelemetryFolderScan scan;

  /// Null when the scan found nothing to import.
  final TelemetryImportPlan? plan;

  /// The primary runs, named "Session N" in recording order.
  final List<NamedRun> runs;

  /// The day's laps, groups and ranking; null without runs.
  final DayAnalysis? analysis;

  /// Each run's RCZ of the same drive, by run id: aligned and fused in the
  /// background once the day shows.
  final Map<String, TelemetryRunProposal> alternatives;

  /// How long each step took in the background, in order.
  final List<DiagnosticStep> steps;
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
  final steps = <DiagnosticStep>[];
  final clock = Stopwatch()..start();
  void step(String name) {
    steps.add((name: name, duration: clock.elapsed));
    clock.reset();
  }

  final scan = scanTelemetrySources(
    request.paths,
    includeSubfolders: request.includeSubfolders,
    cancelled: cancelled,
  );
  if (scan.cancelled) throw const OperationCancelled();
  if (scan.error.isNotEmpty) return DayImportOutcome(scan: scan);
  step(DiagnosticSteps.scan);
  final plan = prepareTelemetryImport(
    scan.files,
    cancelled: cancelled,
    progress: progress,
  );
  final runs = nameRunsInRecordingOrder(primaryRuns(plan));
  step(DiagnosticSteps.parse);
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
  if (analysis != null) step(DiagnosticSteps.analysis);
  return DayImportOutcome(
    scan: scan,
    plan: plan,
    runs: runs,
    analysis: analysis,
    alternatives: importedAlternatives(plan, [
      for (final named in runs) named.run,
    ]),
    steps: steps,
  );
}

/// What the user should know about a prepared plan: recordings skipped,
/// imported once as duplicates, failed, or kept as another recording's
/// alternative source.
List<String> importPlanNotes(
  TelemetryFolderScan scan,
  TelemetryImportPlan plan,
) {
  final notes = [...scan.notes];
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
  for (final run in plan.runs) {
    final primary = groups[run.id];
    if (primary != null && primary != run.id) {
      notes.add(
        '${names[run.id]}: the same drive as ${names[primary]}; kept as its '
        'alternative source.',
      );
    }
  }
  return notes;
}

/// Recordings to add to a day that already has [runIds] (its runs and its
/// missing runs, [runCount] in all) and [rowCount] lap sections. With
/// [sameDayAs] (a recording start of the day, milliseconds since the
/// epoch), recordings are added only when every new one started on that
/// local calendar date. [alternatives] maps a recording's run id to the
/// day's session it is the other format of (a VBO and an RCZ of one drive);
/// those are not added. [alternativeOf] maps those that are an RCZ to the
/// day's VBO run they become the alternative recording of (aligned and
/// fused in the background once added).
typedef DayAppendRequest = ({
  List<String> paths,
  Set<String> runIds,
  int runCount,
  int rowCount,
  int? sameDayAs,
  Map<String, String> alternatives,
  Map<String, String> alternativeOf,
});

/// Whether [a] and [b] (milliseconds since the epoch) fall on one local
/// calendar date.
bool sameLocalDate(int a, int b) {
  final x = DateTime.fromMillisecondsSinceEpoch(a);
  final y = DateTime.fromMillisecondsSinceEpoch(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// The runs a request adds and their part of the day.
final class DayAppendOutcome {
  const DayAppendOutcome({
    required this.notes,
    this.runs = const [],
    this.part,
    this.alternatives = const {},
    this.error = '',
    this.otherDay = false,
  });

  /// Nothing was added: a new recording did not start on the day's date
  /// (or has no date), as [DayAppendRequest.sameDayAs] asked.
  final bool otherDay;

  /// The new runs, named after the day's sessions in recording order.
  final List<NamedRun> runs;

  /// Their lap rows and routes; null when nothing is added.
  final DayRunsPart? part;

  /// The RCZ of each new run, and each RCZ added to one of the day's runs
  /// ([DayAppendRequest.alternativeOf]), by run id: not aligned yet.
  final Map<String, TelemetryRunProposal> alternatives;

  /// What was skipped, already in the day or failed, for the user.
  final List<String> notes;

  /// Why nothing could be read at all; empty otherwise.
  final String error;
}

/// Prepares only the recordings of [request] that are not in the day yet:
/// the work done in the background isolate. The day's own runs are not read
/// again.
DayAppendOutcome runDayAppend(
  DayAppendRequest request, {
  CancellationCheck? cancelled,
  void Function(int processed, int total)? progress,
}) {
  final scan = scanTelemetrySources(
    request.paths,
    includeSubfolders: false,
    cancelled: cancelled,
  );
  if (scan.cancelled) throw const OperationCancelled();
  if (scan.error.isNotEmpty) {
    return DayAppendOutcome(notes: scan.notes, error: scan.error);
  }
  final plan = prepareTelemetryImport(
    scan.files,
    cancelled: cancelled,
    progress: progress,
  );
  final notes = importPlanNotes(scan, plan);
  final added = <TelemetryRunProposal>[];
  final alternatives = <String, TelemetryRunProposal>{};
  for (final run in primaryRuns(plan)) {
    final session = request.alternatives[run.id];
    final primary = request.alternativeOf[run.id];
    if (request.runIds.contains(run.id)) {
      notes.add('${p.basename(run.sourcePath)}: already in this day.');
    } else if (session != null && primary != null) {
      alternatives[primary] = run;
      notes.add(
        '${p.basename(run.sourcePath)}: the same drive as $session in the other '
        'format; kept as its alternative source.',
      );
    } else if (session != null) {
      notes.add(
        '${p.basename(run.sourcePath)}: the same drive as $session in the other '
        'format; not added again.',
      );
    } else {
      added.add(run);
    }
  }
  if (added.isEmpty) {
    return DayAppendOutcome(notes: notes, alternatives: alternatives);
  }
  final day = request.sameDayAs;
  if (day != null &&
      !added.every((run) {
        final start = recordingTimestamp(run.telemetry);
        return start != null && sameLocalDate(start, day);
      })) {
    return DayAppendOutcome(notes: notes, otherDay: true);
  }
  final runs = nameRunsInRecordingOrder(added, existingRuns: request.runCount);
  final part = analyzeDayRuns(
    [
      for (final named in runs)
        DayRunInput(
          runId: named.run.id,
          name: named.name,
          contentSha256: named.run.contentSha256,
          session: named.run.telemetry,
          laps: named.run.laps,
        ),
    ],
    existingRuns: request.runCount,
    existingRows: request.rowCount,
    cancelled: cancelled,
  );
  alternatives.addAll(importedAlternatives(plan, added));
  return DayAppendOutcome(
    notes: notes,
    runs: runs,
    part: part,
    alternatives: alternatives,
  );
}

/// A running addition to a day. [result] completes with
/// [OperationCancelled] after [cancel].
abstract interface class DayAppendJob {
  Future<DayAppendOutcome> get result;
  void cancel();
}

/// Starts additions to a day. Replaced by a fake in widget tests.
abstract interface class DayAppender {
  DayAppendJob start(
    DayAppendRequest request,
    void Function(int processed, int total) progress,
  );
}

/// Prepares each addition in its own isolate, like [IsolateDayImporter].
final class IsolateDayAppender implements DayAppender {
  const IsolateDayAppender();

  @override
  DayAppendJob start(
    DayAppendRequest request,
    void Function(int, int) progress,
  ) => _IsolateAppendJob(request, progress);
}

final class _IsolateAppendJob
    extends _IsolateJob<DayAppendRequest, DayAppendOutcome>
    implements DayAppendJob {
  _IsolateAppendJob(super.request, super.progress) : super(entry: _run);

  static DayAppendOutcome _run(
    DayAppendRequest request,
    void Function(int, int) progress,
  ) => runDayAppend(request, progress: progress);
}

/// Runs each import in its own isolate, off the interface thread (see
/// [_IsolateJob]).
final class IsolateDayImporter implements DayImporter {
  const IsolateDayImporter();

  @override
  DayImportJob start(
    DayImportRequest request,
    void Function(int, int) progress,
  ) => _IsolateImportJob(request, progress);
}

final class _IsolateImportJob
    extends _IsolateJob<DayImportRequest, DayImportOutcome>
    implements DayImportJob {
  _IsolateImportJob(super.request, super.progress) : super(entry: _run);

  static DayImportOutcome _run(
    DayImportRequest request,
    void Function(int, int) progress,
  ) => runDayImport(request, progress: progress);
}

/// Runs [entry] on a request in its own isolate. Cancel stops the isolate at
/// once; it only reads files, so nothing is left half written, and no
/// partial result is ever delivered.
abstract class _IsolateJob<R, O> {
  _IsolateJob(
    R request,
    void Function(int, int) progress, {
    required O Function(R, void Function(int, int)) entry,
  }) {
    _port.listen((message) {
      switch (message) {
        case (int processed, int total):
          if (!_completer.isCompleted) progress(processed, total);
        case O outcome:
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
      _entry<R, O>,
      (_port.sendPort, request, entry),
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
  final _completer = Completer<O>();
  Isolate? _isolate;
  bool _cancelled = false;

  Future<O> get result => _completer.future;

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

  static void _entry<R, O>(
    (SendPort, R, O Function(R, void Function(int, int))) message,
  ) {
    final (port, request, entry) = message;
    final outcome = entry(
      request,
      (processed, total) => port.send((processed, total)),
    );
    Isolate.exit(port, outcome);
  }
}
