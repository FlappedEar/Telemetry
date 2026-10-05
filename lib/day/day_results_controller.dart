import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max, min;

import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../diagnostics/app_diagnostics.dart';
import '../diagnostics/app_errors.dart';
import '../import/import_runner.dart';
import '../units.dart';
import 'background_task.dart';
import 'channel_sources.dart';
import 'coach_job.dart';
import 'day_weather.dart';
import 'recovery_store.dart';
import 'recovery_writes.dart';
import 'save_journal.dart';
import 'segment_remeasure.dart';

export 'coach_job.dart' show CoachJob, CoachRunner, defaultCoachRunner;

/// Saves a document. Replaced by a fake in widget tests.
typedef DocumentWriter = Future<void> Function(
  String path,
  Map<String, Object?> document,
);

/// Runs a theoretical-best calculation. Replaced in widget tests, which run
/// it on the test's own thread.
typedef TheoreticalBestRunner = Future<DayTheoreticalBest> Function(
  DayTheoreticalBest Function() job,
);

/// In a background isolate, or directly under `flutter test`.
Future<DayTheoreticalBest> defaultTheoreticalBestRunner(
  DayTheoreticalBest Function() job,
) => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? Future.microtask(job)
    : Isolate.run(job);

/// Computes the segment proposals the review shows. Replaced in widget
/// tests like [TheoreticalBestRunner].
typedef SegmentReviewRunner = Future<DayProposalReview> Function(
  DayProposalReview Function() job,
);

/// In a background isolate, or directly under `flutter test`.
Future<DayProposalReview> defaultSegmentReviewRunner(
  DayProposalReview Function() job,
) => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? Future.microtask(job)
    : Isolate.run(job);

/// Summarizes the day's recorded channels. Replaced in widget tests, which
/// run it on the test's own thread.
typedef ChannelSummariesRunner = Future<DayChannelSummaries> Function(
  DayChannelSummaries Function() job,
);

/// In a background isolate, or directly under `flutter test`.
Future<DayChannelSummaries> defaultChannelSummariesRunner(
  DayChannelSummaries Function() job,
) => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? Future.microtask(job)
    : Isolate.run(job);

/// Aligns and fuses a run's alternative recording, or fuses it again with
/// a changed rule; stops at [cancelled] with [OperationCancelled].
typedef FusionJob = RunFusion? Function(CancellationCheck cancelled);

/// A running [FusionJob]. [result] completes with [OperationCancelled]
/// after [cancel].
abstract interface class FusionTask {
  Future<RunFusion?> get result;
  void cancel();
}

/// The reason of a run's fusion when aligning its new recording failed
/// (the job stopped with an error): the recording stays saved, and the day
/// opened again tries once more, as it fuses a VBO session's RCZ by itself.
/// Other recordings paired in a review are not tried again: an RCZ
/// session's VBO is kept beside it, and any other pair (two VBOs, say)
/// stays in the file with the session but is not shown, as the day opened
/// again does with them (see [DayResultsController.save]).
const fusionFailedReason = 'Aligning failed.';

/// What reading a session's other recording as its primary gave: its part
/// of the day, or why not.
typedef PreparedPrimary = ({DayRunsPart? part, NewPrimaryProblem? problem});

/// Why a session's clock check or primary change failed (FET-57), for the
/// page to say.
enum RecordingsProblem {
  /// The clocks could not be compared.
  clockFailed,

  /// The other recording's file is not where it was read from.
  primaryMissing,

  /// The other recording's file holds other content now.
  primaryChanged,

  /// The other recording could not be read as the session.
  primaryFailed,

  /// The day has unsaved changes: the primary changes only on a saved day.
  unsaved,
}

/// Starts a [FusionJob]. Replaced in widget tests, which run it on the
/// test's own thread.
typedef FusionRunner = FusionTask Function(FusionJob job);

/// In a background isolate, stopped at once when cancelled; directly under
/// `flutter test`, stopped at its next cancellation check.
FusionTask defaultFusionRunner(FusionJob job) =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? _InlineFusionTask(job)
    : isolateFusionRunner(job);

/// Runs [job] in its own isolate, killed when cancelled.
FusionTask isolateFusionRunner(FusionJob job) => _IsolateFusionTask(job);

final class _InlineFusionTask implements FusionTask {
  _InlineFusionTask(FusionJob job) {
    result = Future.microtask(() => job(() => _cancelled));
  }

  bool _cancelled = false;

  @override
  late final Future<RunFusion?> result;

  @override
  void cancel() => _cancelled = true;
}

/// What a fusion isolate sends back.
final class _FusionResult {
  const _FusionResult(this.fusion);
  final RunFusion? fusion;
}

final class _IsolateFusionTask implements FusionTask {
  _IsolateFusionTask(FusionJob job) {
    _port.listen((message) {
      switch (message) {
        case _FusionResult(:final fusion):
          _finish(() => _done.complete(fusion));
        case [Object? error, Object? stack]:
          _finish(
            () => _done.completeError(
              error ?? 'Not combined.',
              stack is String ? StackTrace.fromString(stack) : null,
            ),
          );
        default:
          _finish(
            () => _done.completeError(
              StateError('The alignment stopped unexpectedly.'),
            ),
          );
      }
    });
    Isolate.spawn(
      _entry,
      (_port.sendPort, job),
      onError: _port.sendPort,
      onExit: _port.sendPort,
      debugName: 'fusion',
    ).then(
      (isolate) {
        _isolate = isolate;
        if (_cancelled) isolate.kill(priority: Isolate.immediate);
      },
      onError: (Object error, StackTrace stack) =>
          _finish(() => _done.completeError(error, stack)),
    );
  }

  final _port = ReceivePort();
  final _done = Completer<RunFusion?>();
  Isolate? _isolate;
  bool _cancelled = false;

  @override
  Future<RunFusion?> get result => _done.future;

  @override
  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _finish(() => _done.completeError(const OperationCancelled()));
  }

  void _finish(void Function() complete) {
    if (_done.isCompleted) return;
    _port.close();
    complete();
  }

  static void _entry((SendPort, FusionJob) message) {
    final (port, job) = message;
    Isolate.exit(port, _FusionResult(job(() => false)));
  }
}

/// The results of one imported day and the user's choices on them: the group
/// shown and the laps excluded. Re-ranking keeps rows and routes, so it runs
/// on the interface thread.
final class DayResultsController extends ChangeNotifier {
  DayResultsController({
    required List<NamedRun> runs,
    required DayAnalysis analysis,
    String? eventId,
    String? name,
    Map<DayLapReference, String> exclusions = const {},
    this.missing = const [],
    String? openedFrom,
    Map<String, Object?>? openedDocument,
    String? documentBase,
    DocumentWriter? writer,
    this.recovery,
    bool recovered = false,
    TheoreticalBestRunner? theoreticalBestRunner,
    CoachRunner? coachRunner,
    SegmentReviewRunner? segmentReviewRunner,
    ChannelSummariesRunner? channelSummariesRunner,
    FusionRunner? fusionRunner,
    DayAppender? appender,
    ImportPreparer? preparer,
    bool changed = false,
    AppDiagnostics? diagnostics,
    Map<String, RunFusion> fusions = const {},
    Map<String, TelemetryRunProposal> alternatives = const {},
    Map<String, DocumentAlternative> documentAlternatives = const {},
    DayWeather? weather,
  }) : _runs = [...runs],
       weather =
           weather ??
           DayWeather(
             fetcher: defaultWeatherFetcher,
             enabled: weatherLookupSetting,
           ),
       _documentAlternatives = {...documentAlternatives},
       _fusions = {...fusions},
       _fusionRunner = fusionRunner ?? defaultFusionRunner,
       _coachJob = LatestCoachJob(coachRunner ?? defaultCoachRunner),
       _segmentReviewRunner = segmentReviewRunner ?? defaultSegmentReviewRunner,
       _appender = appender ?? const IsolateDayAppender(),
       _preparer = preparer ?? const IsolateImportPreparer(),
       diagnostics = diagnostics ?? appDiagnostics,
       _channelSummariesRunner =
           channelSummariesRunner ?? defaultChannelSummariesRunner,
       _theoreticalBestRunner =
           theoreticalBestRunner ?? defaultTheoreticalBestRunner,
       _analysis = analysis,
       _groupId = analysis.chosenGroupId,
       eventId = eventId ?? newEventId(),
       _name = name ?? defaultDayName(runs),
       _exclusions = {...exclusions},
       _documentPath = openedFrom,
       _document = openedDocument,
       _documentBase = documentBase ?? openedFrom ?? '',
       _writer = writer ?? saveDayWithJournal,
       _dirty = recovered || changed {
    declareDaySpeedUnits([for (final run in runs) run.run.telemetry]);
    _declaredSpeedUnits = declaredSpeedUnits;
    speedUnitSetting.addListener(_speedUnitAssumed);
    _declareChannelSources();
    // A restored day is what its snapshot holds: written again only when it
    // changes, so a day restored and not taken leaves the snapshot as it was.
    if (!recovered) _scheduleRecovery();
    // The results show first; each run's alternative recording is aligned
    // and fused in the background and applied when done.
    for (final MapEntry(:key, :value) in alternatives.entries) {
      _startFusion(key, recording: value);
    }
    for (final MapEntry(:key, :value) in documentAlternatives.entries) {
      _startFusion(key, reference: value);
    }
    this.weather.onFetched = _weatherFetched;
    this.weather.sync(runs, _savedRuns);
  }

  /// A day opened from its document. A day whose recordings were found in
  /// a new place has changes until saved.
  DayResultsController.opened(
    OpenedDay day, {
    DocumentWriter? writer,
    RecoveryStore? recovery,
    DayAppender? appender,
    ImportPreparer? preparer,
    FusionRunner? fusionRunner,
    DayWeather? weather,
  }) : this(
         appender: appender,
         preparer: preparer,
         fusionRunner: fusionRunner,
         weather: weather,
         runs: day.runs,
         analysis: day.analysis!,
         eventId: day.eventId,
         name: day.name,
         exclusions: day.exclusions,
         missing: day.missing,
         openedFrom: day.path,
         openedDocument: day.document,
         writer: writer,
         recovery: recovery,
         documentAlternatives: day.alternatives,
         changed: day.relinked.isNotEmpty,
       );

  /// An unsaved day restored from [recovery]'s snapshot: it has changes
  /// until saved, and saving it again goes where it was last saved.
  DayResultsController.recovered(
    OpenedDay day,
    DayRecovery snapshot, {
    DocumentWriter? writer,
    RecoveryStore? recovery,
    DayAppender? appender,
    ImportPreparer? preparer,
    FusionRunner? fusionRunner,
  }) : this(
         appender: appender,
         preparer: preparer,
         fusionRunner: fusionRunner,
         runs: day.runs,
         analysis: day.analysis!,
         eventId: day.eventId,
         name: day.name,
         exclusions: day.exclusions,
         missing: day.missing,
         openedFrom: snapshot.originalPath.isEmpty
             ? null
             : snapshot.originalPath,
         openedDocument: day.document,
         documentBase: snapshot.basePath,
         writer: writer,
         recovery: recovery,
         documentAlternatives: day.alternatives,
         recovered: true,
       );

  final List<NamedRun> _runs;

  /// The day's runs whose recordings were read, in the order added.
  List<NamedRun> get runs => List.unmodifiable(_runs);

  // Each run's alternative recording (the RCZ of its VBO) and its fusion.
  final Map<String, RunFusion> _fusions;
  final FusionRunner _fusionRunner;
  final Map<String, int> _fusionGenerations = {};
  // Runs being fused again after a rule changed, with that change's
  // generation.
  final Map<String, int> _fusionUpdating = {};

  // The alternative recordings the document names, by run id, also of runs
  // whose recording is missing.
  final Map<String, DocumentAlternative> _documentAlternatives;

  // Runs whose alternative recording is being aligned and fused, with its
  // format.
  final Map<String, RecordingFormat?> _fusionPending = {};

  // Recordings added as runs' alternatives (by an import or an addition)
  // that are not fused yet: saved as the runs' sources meanwhile. The day
  // opened again aligns only a VBO session's RCZ by itself, so [save] waits
  // for the others ([_reviewedPairingPending]).
  final Map<String, TelemetryRunProposal> _pendingRecordings = {};

  // Completed whenever a run's alignment ends, for a save waiting on
  // recordings paired in a review.
  Completer<void>? _pairingWaiter;

  /// Whether [recording], saved as [primary]'s source without a `fusion`
  /// decision, is aligned and fused by itself when the day opens again:
  /// only a VBO session's RCZ (FET-57). Of any other pair, which only a
  /// review makes, the day opened again keeps an RCZ session's VBO beside
  /// it ([_keptBesideWhenOpened]); anything else stays in the document with
  /// the session and is not shown.
  static bool _fusedWhenOpened(
    TelemetryRunProposal primary,
    TelemetryRunProposal recording,
  ) =>
      primary.format == RecordingFormat.vbo &&
      recording.format == RecordingFormat.rcz;

  /// Whether [recording], saved as [primary]'s source without a `fusion`
  /// decision, is kept beside the session, not fused, when the day opens
  /// again: an RCZ session's VBO (FET-57).
  static bool _keptBesideWhenOpened(
    TelemetryRunProposal primary,
    TelemetryRunProposal recording,
  ) =>
      primary.format == RecordingFormat.rcz &&
      recording.format == RecordingFormat.vbo;

  /// Whether a save is waiting until a recording paired in a review is
  /// lined up with its session (see [save]): the day is not left meanwhile,
  /// or the file would not say how the pair is fused.
  bool get savingWaitsForRecordings => _saveWaiting;
  bool _saveWaiting = false;

  // Whether a recording paired in a review is still being aligned with a
  // session the day opened again would not fuse it with: saved now, the
  // document would not say the pair is to be fused.
  bool get _reviewedPairingPending {
    for (final runId in _fusionPending.keys) {
      final recording = _pendingRecordings[runId];
      final named = _named(runId);
      if (recording != null &&
          named != null &&
          !_fusedWhenOpened(named.run, recording)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _reviewedPairingsSettled() async {
    while (!_disposed && _reviewedPairingPending) {
      await (_pairingWaiter ??= Completer<void>()).future;
    }
  }

  void _alignmentEnded() {
    final waiter = _pairingWaiter;
    _pairingWaiter = null;
    waiter?.complete();
  }

  // The background work running for each run, stopped when the day closes
  // or a newer request for the run supersedes it.
  final Map<String, FusionTask> _fusionTasks = {};
  final List<Future<void> Function()> _fusionQueue = [];
  int _fusionsRunning = 0;
  Completer<void>? _fusionsSettled;

  /// How many runs are aligned at once: each isolate holds both recordings.
  @visibleForTesting
  static int fusionSlots = kIsWeb
      ? 1
      : max(1, min(3, Platform.numberOfProcessors - 1));

  /// [runId]'s alternative recording and what fusing it did; null when the
  /// run has none, or while it is still being aligned ([fusionPending]).
  RunFusion? fusion(String runId) => _fusions[runId];

  /// The format of [runId]'s alternative recording ("RCZ") while it is
  /// being aligned and fused in the background; null otherwise.
  String? fusionPending(String runId) => _fusionPending.containsKey(runId)
      ? _fusionPending[runId]?.name.toUpperCase() ?? ''
      : null;

  /// Completes once no alternative recording is being aligned or fused,
  /// and the day saved again after one an addition brought.
  Future<void> get fusionsSettled {
    if (_fusionsIdle) return Future.value();
    return (_fusionsSettled ??= Completer<void>()).future;
  }

  bool get _fusionsIdle =>
      _fusionPending.isEmpty &&
      _fusionUpdating.isEmpty &&
      _clocksChecking.isEmpty &&
      _primaryChanging.isEmpty &&
      _savingAfterFusion == 0;

  // Saves after an addition's alternative recording was fused, running.
  int _savingAfterFusion = 0;

  void _settleFusions() {
    if (!_fusionsIdle) return;
    final settled = _fusionsSettled;
    _fusionsSettled = null;
    settled?.complete();
  }

  /// Whether [runId] is being fused again after a rule changed.
  bool fusionUpdating(String runId) => _fusionUpdating.containsKey(runId);

  /// The alternative recordings that could not be used because they were
  /// not found where the document says, or the file there is another
  /// recording: what "Find recordings in a folder" also looks for. Runs
  /// whose own recording is [missing] count too.
  List<MissingRecording> get missingAlternatives => [
    for (final recording in missing)
      if (_documentAlternatives[recording.runId] case final alternative?)
        alternative.missing(recording.name, 'Recording not found.'),
    for (final named in _runs)
      if ((_documentAlternatives[named.run.id], _fusions[named.run.id])
          case (
            final alternative?,
            RunFusion(state: RunFusionState.unavailable, :final reason),
          )
          when alternative.sourceId ==
                  _fusions[named.run.id]!.alternativeSourceId &&
              reason != fusionFailedReason)
        alternative.missing(named.name, reason),
  ];

  /// The format of the recording channel [channel] of [runId]'s session
  /// came from in whole or in part ("RCZ"), when that is not the run's own
  /// recording; empty otherwise.
  String channelSource(String runId, String channel) {
    final fusion = _fusions[runId];
    if (fusion == null || !fusion.channelOrigins.containsKey(channel)) {
      return '';
    }
    return fusion.alternativeFormat?.name.toUpperCase() ?? '';
  }

  /// Every channel of [runId]'s session that came from another recording,
  /// with that recording's format (see [channelSource]).
  Map<String, String> channelSources(String runId) => {
    for (final channel
        in _fusions[runId]?.channelOrigins.keys ?? const <String>[])
      channel: channelSource(runId, channel),
  };

  // This day's [dayChannelSources] and [dayRecordedChannels], cleared when
  // it closes unless another day has declared its own since.
  Map<String, String> _declaredChannelSources = const {};
  List<String> _declaredRecordedChannels = const [];

  void _declareChannelSources() {
    final sources = <String, String>{};
    final recorded = <String>{};
    for (final named in _runs) {
      sources.addAll(channelSources(named.run.id));
      recorded
        ..addAll(named.run.telemetry.channelNames())
        ..addAll(sources.keys);
    }
    dayChannelSources = _declaredChannelSources = Map.unmodifiable(sources);
    dayRecordedChannels = _declaredRecordedChannels = List.unmodifiable(
      recorded.toList()..sort(),
    );
  }

  // [runs] with each fused session in place of its recording: what the
  // analysis that reads channels uses. Laps stay the primary's own.
  List<NamedRun>? _channelRuns;
  // Built again whenever the fusions or the runs change, also when a run
  // is added some other way than [addRecordings].
  List<NamedRun> get _analysisRuns => _channelRuns?.length == _runs.length
      ? _channelRuns!
      : _channelRuns = [
          for (final named in _runs)
            _analysed(named, _fusions[named.run.id]?.session),
        ];

  // [runs] as the analysis that does not read fused channels sees them
  // (theoretical best, coach, segment review): each recording with its
  // speeds in their effective unit (see [_analysed]).
  // Kept while [_runs] holds the same runs it was built from.
  List<NamedRun>? _recordingRuns;
  List<NamedRun> _recordingRunsFor = const [];
  List<NamedRun> get _unitRuns {
    final built = _recordingRuns;
    if (built != null &&
        _recordingRunsFor.length == _runs.length &&
        Iterable<int>.generate(_runs.length)
            .every((i) => _recordingRunsFor[i] == _runs[i])) {
      return built;
    }
    _recordingRunsFor = List.of(_runs);
    return _recordingRuns = [for (final named in _runs) _analysed(named)];
  }

  // [named] (with [telemetry] in place of its recording) as every analysis
  // reads it: each speed channel carrying the unit its recording declares,
  // else the one assumed for unlabelled speeds in settings
  // ([withEffectiveSpeedUnits]). The recording itself stays as parsed, so
  // its saved fingerprint matches what Overlays writes.
  static NamedRun _analysed(NamedRun named, [TelemetrySession? telemetry]) {
    final session = withEffectiveSpeedUnits(
      telemetry ?? named.run.telemetry,
      assumed: speedUnitSetting.value.unit,
    );
    if (identical(session, named.run.telemetry)) return named;
    return (
      run: TelemetryRunProposal(
        id: named.run.id,
        sourceId: named.run.sourceId,
        sourcePath: named.run.sourcePath,
        format: named.run.format,
        contentSha256: named.run.contentSha256,
        telemetry: session,
        laps: named.run.laps,
      ),
      name: named.name,
    );
  }

  // The unit assumed for unlabelled speeds changed: what reads speeds is
  // calculated again in the new unit.
  void _speedUnitAssumed() {
    if (_disposed) return;
    _channelRuns = _recordingRuns = null;
    _comparisons.clear();
    // A review on its way was measured in the old unit.
    ++_segmentReviewGeneration;
    _segmentReviewLoading = false;
    _segmentReviewFor = null;
    _resetTheoreticalBest();
    _resetChannelSummaries();
    notifyListeners();
  }

  NamedRun? _named(String runId) {
    for (final named in _runs) {
      if (named.run.id == runId) return named;
    }
    return null;
  }

  // Built outside the controller so the isolate's closure holds only its
  // inputs.
  static FusionJob _fusionJob(
    RunFusion fusion,
    TelemetryRunProposal primary,
    String key,
    FusionRule rule,
  ) =>
      (cancelled) =>
          withFusionRule(fusion, primary, key, rule, cancelled: cancelled);

  static FusionJob _resolveJob(
    TelemetryRunProposal primary,
    TelemetryRunProposal? recording,
    DocumentAlternative? reference,
    Map<String, Object?>? decision,
  ) =>
      (cancelled) => recording != null
      ? fuseWithDecision(primary, recording, decision, cancelled: cancelled)
      : resolveDocumentAlternative(primary, reference!, cancelled: cancelled);

  /// [runId]'s fusion decision as last saved or made: what an RCZ added
  /// to the session again starts from, keeping the user's rules.
  Map<String, Object?>? _decisionOf(String runId) {
    if (_fusions[runId]?.decision case final decision?) return decision;
    final event = _document?['event'];
    final runs = event is Map ? event['runs'] : null;
    for (final run in runs is List ? runs : const []) {
      if (run is Map && run['id'] == runId && run['fusion'] is Map) {
        return (run['fusion'] as Map).cast<String, Object?>();
      }
    }
    return _documentAlternatives[runId]?.decision;
  }

  /// Runs [job] for [runId] in the background; a newer request for the run
  /// stops it.
  Future<RunFusion?> _runFusionTask(String runId, FusionJob job) async {
    _fusionTasks.remove(runId)?.cancel();
    final task = _fusionRunner(job);
    _fusionTasks[runId] = task;
    try {
      return await task.result;
    } finally {
      if (identical(_fusionTasks[runId], task)) _fusionTasks.remove(runId);
    }
  }

  /// Aligns and fuses [runId]'s alternative recording in the background:
  /// [recording] already read (an import or an addition), or the document's
  /// [reference] to it. The result is applied only while it is still the
  /// latest asked for the run and the run's recording is the same.
  /// [addition] saves a day with a file again once it is applied, as the
  /// addition did.
  void _startFusion(
    String runId, {
    TelemetryRunProposal? recording,
    DocumentAlternative? reference,
    bool addition = false,
  }) {
    final named = _named(runId);
    if (named == null || _disposed) return;
    final generation = _nextRecordingGeneration(runId);
    // What ran for the run before is superseded.
    _fusionTasks.remove(runId)?.cancel();
    if (recording != null) _pendingRecordings[runId] = recording;
    if (reference != null && reference.path.isEmpty) {
      // Nothing to read: known at once, and nothing changes.
      _fusionPending.remove(runId);
      _alignmentEnded();
      _fusions[runId] = RunFusion.unavailable(
        primarySourceId: named.run.sourceId,
        primaryRevision: named.run.contentSha256,
        alternativeSourceId: reference.sourceId,
        alternativeFormat: reference.format,
        reason: 'Recording not found.',
      );
      _settleFusions();
      return;
    }
    _fusionPending[runId] = recording?.format ?? reference?.format;
    final primary = named.run;
    final decision = recording == null ? null : _decisionOf(runId);
    _fusionQueue.add(() async {
      // Not started once the day closed or a newer request superseded it.
      if (_disposed || _fusionGenerations[runId] != generation) return;
      final clock = Stopwatch()..start();
      RunFusion? result;
      try {
        result = await _runFusionTask(
          runId,
          _resolveJob(primary, recording, reference, decision),
        );
      } on OperationCancelled {
        return;
      } on Object catch (error) {
        debugPrint('Not combined: $error');
      }
      _fusionDone(
        runId,
        generation,
        primary,
        result,
        fromRecording: recording != null,
        addition: addition,
        elapsed: clock.elapsed,
      );
    });
    _runFusions();
  }

  void _runFusions() {
    while (_fusionsRunning < fusionSlots && _fusionQueue.isNotEmpty) {
      final job = _fusionQueue.removeAt(0);
      ++_fusionsRunning;
      unawaited(
        job().whenComplete(() {
          --_fusionsRunning;
          _runFusions();
        }),
      );
    }
  }

  void _fusionDone(
    String runId,
    int generation,
    TelemetryRunProposal primary,
    RunFusion? result, {
    required bool fromRecording,
    required bool addition,
    required Duration elapsed,
  }) {
    // A result for a run that was asked again, or whose day closed, is not
    // used.
    if (_disposed || _fusionGenerations[runId] != generation) return;
    _fusionPending.remove(runId);
    _alignmentEnded();
    // Without a result (the job failed, or the run's recording is not the
    // one it was started for), a recording that was added is still saved
    // as the run's source. A VBO session's RCZ stays in
    // [_pendingRecordings], so the day opened again tries once more. Any
    // other pair, which only a review makes, is shown as the day opened
    // again will show it, so the session and the file agree: an RCZ
    // session's VBO is kept beside it, not fused ("Check clock" tries
    // again); anything else (two VBOs, say) stays in [_pendingRecordings],
    // saved with the session as its source, and is not shown.
    final named = _named(runId);
    final recording = _pendingRecordings[runId];
    if (result == null &&
        fromRecording &&
        recording != null &&
        named != null &&
        named.run.contentSha256 == primary.contentSha256) {
      if (_fusedWhenOpened(primary, recording)) {
        // The run shows that its new recording is not combined, not the
        // fusion of the one it replaces (whose rules would not be saved).
        _fusions[runId] = RunFusion.unavailable(
          primarySourceId: primary.sourceId,
          primaryRevision: primary.contentSha256,
          alternativeSourceId: recording.sourceId,
          alternativeFormat: recording.format,
          reason: fusionFailedReason,
        );
      } else {
        if (_keptBesideWhenOpened(primary, recording)) {
          _fusions[runId] = RunFusion.primaryOnly(
            primary: primary,
            alternative: recording,
          );
          _pendingRecordings.remove(runId);
        } else {
          _fusions.remove(runId);
        }
        // A save made meanwhile left the day unsaved: saved again.
        _revision++;
        _dirty = true;
        final path = _documentPath;
        if (addition && path != null) {
          unawaited(_saveAfterFusion(path));
        } else if (!_saving) {
          _scheduleRecovery();
        }
      }
      _fusionsChanged();
      if (addition && !_disposed) {
        if (_waitingAdditions > 0) {
          // Said with the addition, which has not reported yet.
          _notCombinedWhileAdding.add(named.name);
        } else {
          _lastAddition = DayAddition(
            notes: const [],
            notCombined: [named.name],
          );
        }
      }
    }
    if (result != null &&
        named != null &&
        named.run.contentSha256 == primary.contentSha256) {
      diagnostics.recordStep(DiagnosticSteps.fusion, elapsed);
      _fusions[runId] = result;
      if (result.alternative != null) _pendingRecordings.remove(runId);
      _fusionsChanged();
      // A decision applied as saved changes nothing. A new recording, a new
      // decision or a source entry to update is a change of the day.
      if (fromRecording ||
          (result.fused && !result.fromDocument) ||
          result.documentChanged) {
        _revision++;
        _dirty = true;
        final path = _documentPath;
        if (addition && path != null) {
          unawaited(_saveAfterFusion(path));
        } else if (!_saving) {
          _scheduleRecovery();
        }
      }
    }
    notifyListeners();
    _settleFusions();
  }

  /// The weather of the day's sessions (see [DayWeather]).
  final DayWeather weather;

  // Runs added to the day while it is open.
  final Set<String> _addedRunIds = {};

  // A session's weather arrived. A session added to a saved day that has no
  // other unsaved change is saved again with it, as the addition was; any
  // other weather is written with the day's next save, and does not make
  // the day unsaved (nor saves edits the user has not saved).
  void _weatherFetched(String runId) {
    if (_disposed) return;
    notifyListeners();
    final path = _documentPath;
    if (path != null && _addedRunIds.contains(runId)) {
      unawaited(_saveWeather(path, runId));
    }
  }

  Future<void> _saveWeather(String path, String runId) async {
    while (_saving) {
      await _saveDone?.future;
    }
    if (_disposed || _documentPath == null || _dirty) return;
    final wanted = weather.fetched[runId];
    if (wanted == null) return;
    for (final value in _savedRuns) {
      if (value case final Map<String, Object?> run when run['id'] == runId) {
        final saved = SessionWeather.fromJson(run[sessionWeatherKey]);
        if (saved?.fetchedMilliseconds == wanted.fetchedMilliseconds &&
            saved?.sourceRevision == wanted.sourceRevision) {
          return;
        }
      }
    }
    try {
      await save(_documentPath ?? path);
    } on Exception catch (error) {
      debugPrint('Weather not saved: $error');
      if (!_disposed) _scheduleRecovery();
    }
  }

  // The alternative recording of an addition to a saved day: saved again,
  // as the addition was; kept for recovery when that fails.
  Future<void> _saveAfterFusion(String path) async {
    ++_savingAfterFusion;
    try {
      while (_saving) {
        await _saveDone?.future;
      }
      if (_disposed || !_dirty) return;
      await save(_documentPath ?? path);
    } on Exception catch (error) {
      debugPrint('Not saved: $error');
      if (!_disposed) _scheduleRecovery();
    } finally {
      --_savingAfterFusion;
      _settleFusions();
    }
  }

  /// Uses [rule] for channel [key] of [runId], where its two recordings
  /// disagree: [FusionRule.primaryOnly] keeps the primary recording,
  /// [FusionRule.fillGaps] fills its gaps from the alternative and
  /// [FusionRule.preferAlternative] uses the alternative. Fused again in
  /// the background; lap rows, timing and rankings never change.
  Future<void> setFusionRule(String runId, String key, FusionRule rule) async {
    final fusion = _fusions[runId];
    final named = _named(runId);
    if (fusion == null || named == null || !fusion.fused || _disposed) return;
    if (fusion.ruleOf(key) == rule && !_fusionUpdating.containsKey(runId)) {
      return;
    }
    final generation = _nextRecordingGeneration(runId);
    _fusionUpdating[runId] = generation;
    notifyListeners();
    RunFusion? result;
    try {
      result = await _runFusionTask(
        runId,
        _fusionJob(fusion, named.run, key, rule),
      );
    } on OperationCancelled {
      // Superseded, or the day closed.
    } on Object catch (error) {
      debugPrint('Fusion not changed: $error');
    } finally {
      // Whatever happened, the run's choices are usable again unless a
      // newer rule change runs.
      if (_fusionUpdating[runId] == generation) _fusionUpdating.remove(runId);
    }
    if (_disposed) return;
    if (_fusionGenerations[runId] != generation) {
      notifyListeners();
      _settleFusions();
      return;
    }
    // Only the fusion it started from is replaced.
    if (result != null && identical(_fusions[runId], fusion)) {
      _fusions[runId] = result;
      _fusionsChanged();
      _revision++;
      _dirty = true;
      _scheduleRecovery();
    }
    notifyListeners();
    _settleFusions();
  }

  // Runs whose clocks are being compared (FET-57), with that check's
  // generation, and the checks done that wait for the user to accept or
  // refuse them, with the fusion each was made against: a check is
  // accepted only while that is still the run's.
  final Map<String, int> _clocksChecking = {};
  final Map<String, ({RunFusion check, RunFusion base})> _clockChecks = {};

  // Runs whose primary recording is being changed, with that change's
  // generation, and the background work reading the new one.
  final Map<String, int> _primaryChanging = {};
  final Map<String, BackgroundTask<PreparedPrimary>> _primaryTasks = {};

  // Why the last check or primary change of a run failed, until the next.
  final Map<String, RecordingsProblem> _recordingsProblems = {};

  // Work waiting for a slot of [fusionSlots] ([_inSlot]); failed with
  // [OperationCancelled] when the day closes.
  final Set<Completer<Object?>> _slotWaiters = {};

  /// Whether [runId]'s clocks are being compared ([checkClock]).
  bool clockChecking(String runId) => _clocksChecking.containsKey(runId);

  /// The clock check of [runId] waiting to be accepted ([acceptClock]) or
  /// refused ([refuseClock]); null when there is none.
  RunFusion? clockCheck(String runId) => _clockChecks[runId]?.check;

  /// Whether [runId]'s primary recording is being changed ([makePrimary]).
  bool primaryChanging(String runId) => _primaryChanging.containsKey(runId);

  /// Why [runId]'s last clock check or primary change failed; null when it
  /// did not.
  RecordingsProblem? recordingsProblem(String runId) =>
      _recordingsProblems[runId];

  /// Whether a clock check or a primary change runs for any session: the
  /// day is not opened again or closed meanwhile.
  bool get recordingsBusy =>
      _clocksChecking.isNotEmpty || _primaryChanging.isNotEmpty;

  /// Whether [runId]'s clock check or primary change runs, so it can be
  /// stopped ([stopRecordingsWork]).
  bool recordingsWorking(String runId) =>
      _clocksChecking.containsKey(runId) || _primaryChanging.containsKey(runId);

  /// Stops [runId]'s clock check or primary change, which can take a while
  /// on a long session: nothing changes, as if it had not been asked, and
  /// the day can be left or closed again at once.
  void stopRecordingsWork(String runId) {
    if (_disposed || !recordingsWorking(runId)) return;
    _nextRecordingGeneration(runId);
    _clocksChecking.remove(runId);
    _primaryChanging.remove(runId);
    _fusionTasks.remove(runId)?.cancel();
    _primaryTasks.remove(runId)?.cancel();
    notifyListeners();
    _settleFusions();
  }

  /// Whether [runId]'s recordings can be changed now: it has another
  /// recording that was read, and nothing runs for it or adds to the day.
  bool recordingsEditable(String runId) =>
      !_disposed &&
      _fusions[runId]?.alternative != null &&
      _recordingsIdle(runId) &&
      !adding;

  bool _recordingsIdle(String runId) =>
      !_fusionPending.containsKey(runId) &&
      !_fusionUpdating.containsKey(runId) &&
      !_clocksChecking.containsKey(runId) &&
      !_primaryChanging.containsKey(runId);

  /// A new generation for [runId]'s recordings: a fusion, rule change or
  /// check still running for the run is not used, and a clock check
  /// waiting for the user no longer applies.
  int _nextRecordingGeneration(String runId) {
    _clockChecks.remove(runId);
    return _fusionGenerations[runId] = (_fusionGenerations[runId] ?? 0) + 1;
  }

  /// Runs [work] once one of the [fusionSlots] is free, as the background
  /// alignments run.
  Future<T> _inSlot<T>(Future<T> Function() work) {
    final done = Completer<Object?>();
    _slotWaiters.add(done);
    _fusionQueue.add(() async {
      if (!_slotWaiters.remove(done)) return;
      try {
        done.complete(await work());
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    _runFusions();
    return done.future.then((value) => value as T);
  }

  static FusionJob _clockJob(
    TelemetryRunProposal primary,
    TelemetryRunProposal alternative,
    Map<String, Object?>? decision,
  ) =>
      (cancelled) =>
          checkRunClock(primary, alternative, decision, cancelled: cancelled);

  /// Compares the clocks of [runId]'s recordings again in the background
  /// (FET-57, Overlays' "Check clock"): the measured offset waits in
  /// [clockCheck] for the user to accept or refuse it. Nothing changes
  /// until then.
  Future<void> checkClock(String runId) async {
    final fusion = _fusions[runId];
    final named = _named(runId);
    final alternative = fusion?.alternative;
    if (named == null || alternative == null || !recordingsEditable(runId)) {
      return;
    }
    final generation = _nextRecordingGeneration(runId);
    _clocksChecking[runId] = generation;
    _recordingsProblems.remove(runId);
    notifyListeners();
    RunFusion? result;
    var failed = false;
    try {
      result = await _inSlot(() async {
        if (_disposed || _fusionGenerations[runId] != generation) {
          throw const OperationCancelled();
        }
        return _runFusionTask(
          runId,
          _clockJob(named.run, alternative, _decisionOf(runId)),
        );
      });
      failed = result == null;
    } on OperationCancelled {
      // Superseded, or the day closed.
    } on Object catch (error) {
      debugPrint('Clocks not compared: $error');
      failed = true;
    } finally {
      if (_clocksChecking[runId] == generation) _clocksChecking.remove(runId);
    }
    if (_disposed) return;
    final current =
        _fusionGenerations[runId] == generation &&
        identical(_fusions[runId], fusion) &&
        identical(_named(runId), named);
    if (current && result != null) {
      _clockChecks[runId] = (check: result, base: fusion!);
    } else if (current && failed) {
      _recordingsProblems[runId] = RecordingsProblem.clockFailed;
    }
    notifyListeners();
    _settleFusions();
  }

  /// Whether [runId]'s waiting clock check can be accepted now
  /// ([acceptClock]): its clocks line up, and no recording is being added.
  bool clockAcceptable(String runId) {
    final waiting = _clockChecks[runId];
    return waiting != null &&
        waiting.check.fused &&
        !adding &&
        _recordingsIdle(runId) &&
        identical(_fusions[runId], waiting.base);
  }

  /// Accepts [runId]'s clock check: when its clocks line up, the other
  /// recording is fused with the measured clock, as Overlays approves a
  /// fusion; saved with the day. Nothing happens when the run's fusion or
  /// recordings changed since the check (it is no longer shown).
  void acceptClock(String runId) {
    final waiting = _clockChecks[runId];
    final named = _named(runId);
    if (waiting == null ||
        !waiting.check.fused ||
        _disposed ||
        named == null ||
        adding ||
        !_recordingsIdle(runId) ||
        !identical(_fusions[runId], waiting.base) ||
        named.run.sourceId != waiting.check.primarySourceId ||
        named.run.contentSha256 != waiting.check.primaryRevision) {
      return;
    }
    _nextRecordingGeneration(runId);
    _fusions[runId] = waiting.check;
    _recordingsChanged();
  }

  /// Refuses [runId]'s clock alignment: the other recording is kept beside
  /// the primary and not fused, and the run's analysis reads the primary
  /// only. Saved as Overlays saves a removed fusion: the run has no
  /// `fusion` decision.
  void refuseClock(String runId) {
    final fusion = _fusions[runId];
    final named = _named(runId);
    final alternative = fusion?.alternative;
    if (named == null ||
        alternative == null ||
        _disposed ||
        adding ||
        !_recordingsIdle(runId)) {
      return;
    }
    final waiting = _clockChecks[runId];
    final check = waiting != null && identical(waiting.base, fusion)
        ? waiting.check
        : null;
    _recordingsProblems.remove(runId);
    _nextRecordingGeneration(runId);
    if (fusion!.state == RunFusionState.primaryOnly) {
      notifyListeners();
      return;
    }
    _fusionTasks.remove(runId)?.cancel();
    _fusions[runId] = RunFusion.primaryOnly(
      primary: named.run,
      alternative: alternative,
      alignment: check?.alignment ?? fusion.alignment,
    );
    _recordingsChanged();
  }

  // A run's recordings changed how the run is analysed: what reads
  // channels is calculated again, and the day is saved with it.
  void _recordingsChanged() {
    _fusionsChanged();
    _revision++;
    _dirty = true;
    _scheduleRecovery();
    notifyListeners();
    _settleFusions();
  }

  static PreparedPrimary _primaryJob(
    (TelemetryRunProposal, String, int) argument,
    CancellationCheck cancelled,
  ) => prepareNewPrimary(
    argument.$1,
    argument.$2,
    otherRows: argument.$3,
    cancelled: cancelled,
  );

  /// Makes [runId]'s other recording its primary (FET-57, Overlays' "Make
  /// primary"): its file is checked to be still the recording read, its
  /// laps are derived again in the background and the day is grouped and
  /// ranked again; every result is calculated again. The recording it
  /// replaces is kept beside it, not fused, and a layout set for the run is
  /// not kept, as in Overlays. Saved with the day. When the file is gone or
  /// changed, nothing changes and [recordingsProblem] says why.
  Future<void> makePrimary(String runId) async {
    final fusion = _fusions[runId];
    final named = _named(runId);
    final alternative = fusion?.alternative;
    if (named == null || alternative == null || !recordingsEditable(runId)) {
      return;
    }
    // Lap choices are the saved document's when the primary changes, so
    // the session and the file name the same laps (Overlays commits them
    // at once).
    if (dirty || _saving) {
      _recordingsProblems[runId] = RecordingsProblem.unsaved;
      notifyListeners();
      return;
    }
    final revision = _revision;
    final generation = _nextRecordingGeneration(runId);
    _fusionTasks.remove(runId)?.cancel();
    _recordingsProblems.remove(runId);
    _primaryChanging[runId] = generation;
    notifyListeners();
    final primary = runFromRecording(named.run, alternative);
    PreparedPrimary? prepared;
    try {
      prepared = await _inSlot(() async {
        if (_disposed || _fusionGenerations[runId] != generation) {
          throw const OperationCancelled();
        }
        final otherRows = _analysis.rows
            .where((row) => row.runId != runId)
            .length;
        final task = runInBackground(_primaryJob, (
          primary,
          named.name,
          otherRows,
        ));
        _primaryTasks[runId] = task;
        try {
          return await task.result;
        } finally {
          if (identical(_primaryTasks[runId], task)) {
            _primaryTasks.remove(runId);
          }
        }
      });
    } on OperationCancelled {
      // Superseded, or the day closed.
    } on Object catch (error) {
      debugPrint('Primary not changed: $error');
      prepared = (part: null, problem: NewPrimaryProblem.failed);
    } finally {
      if (_primaryChanging[runId] == generation) _primaryChanging.remove(runId);
    }
    if (_disposed) return;
    final part = prepared?.part;
    if (prepared == null ||
        _fusionGenerations[runId] != generation ||
        !identical(_named(runId), named) ||
        !identical(_fusions[runId], fusion)) {
      notifyListeners();
      _settleFusions();
      return;
    }
    if (part != null && (_revision != revision || dirty || _saving)) {
      // The day changed meanwhile: its unsaved choices would not carry over.
      _recordingsProblems[runId] = RecordingsProblem.unsaved;
      notifyListeners();
      _settleFusions();
      return;
    }
    if (part == null) {
      _recordingsProblems[runId] = switch (prepared.problem) {
        NewPrimaryProblem.missing => RecordingsProblem.primaryMissing,
        NewPrimaryProblem.changed => RecordingsProblem.primaryChanged,
        _ => RecordingsProblem.primaryFailed,
      };
      notifyListeners();
      _settleFusions();
      return;
    }
    final index = _runs.indexOf(named);
    _runs[index] = (run: primary, name: named.name);
    weather.sync(runs, _savedRuns);
    _pendingRecordings.remove(runId);
    _fusions[runId] = RunFusion.primaryOnly(
      primary: primary,
      alternative: named.run,
    );
    // The run's lap choices are rebuilt from the saved document: the
    // exclusions it keeps for the new primary's laps that still apply (the
    // same content and lap derivation). Those of the old primary stay in
    // the document as stored, for switching back. The comparison pair
    // saved stays as stored too; it applies while its laps do.
    _exclusions.removeWhere((reference, _) => reference.runId == runId);
    _exclusions.addAll(recordingExclusions(_document, runId, primary));
    _comparisonChoice = ComparisonDecisions(
      range: _comparisonChoice.range,
      channels: _comparisonChoice.channels,
    );
    final manual = {..._analysis.manualTracks}..remove(runId);
    _analysis = replaceDayRun(
      _analysis,
      runId,
      part,
      sourceOrder: runSourceOrder(_analysis, runId, index),
      manualTracks: manual,
      exclusions: _exclusions,
      preferredGroupId: _groupChosen ? _groupId : _savedGroupId,
    );
    if (!_groupChosen ||
        !_analysis.groups.any((group) => group.id == _groupId)) {
      _groupId = _analysis.chosenGroupId;
    }
    _channelRuns = _recordingRuns = null;
    if (identical(declaredSpeedUnits, _declaredSpeedUnits)) {
      declareDaySpeedUnits([for (final run in _runs) run.run.telemetry]);
      _declaredSpeedUnits = declaredSpeedUnits;
    }
    if (identical(dayChannelSources, _declaredChannelSources)) {
      _declareChannelSources();
    }
    _explainedFor = null;
    _additionClock = null;
    _resetTheoreticalBest();
    _resetChannelSummaries();
    _recordingsChanged();
  }

  // The fused sessions changed: what reads channels is calculated again.
  void _fusionsChanged() {
    _channelRuns = _recordingRuns = null;
    _comparisons.clear();
    _resetChannelSummaries();
    if (identical(dayChannelSources, _declaredChannelSources)) {
      _declareChannelSources();
    }
  }

  /// Where background calculation times go.
  final AppDiagnostics diagnostics;
  DayAnalysis _analysis;
  String? _groupId;

  // Whether the group shown was picked for the day (by the user, or to follow
  // a session whose layout the user set) rather than the default.
  bool _groupChosen = false;

  // Whether the user chose the group in the group picker: only then is it
  // saved (FET-53), as Overlays saves it only from its group picker, so a
  // day whose group was never chosen stays "automatic" in Overlays.
  bool _groupDecided = false;

  // The comparison set up in this app since the day was opened (FET-53);
  // its null fields keep the document's.
  ComparisonDecisions _comparisonChoice = const ComparisonDecisions();
  final Map<DayLapReference, String> _exclusions;

  /// The event's identity, kept across saves.
  final String eventId;

  /// Runs of the opened document whose recordings could not be used. They
  /// stay in the document when it is saved.
  final List<MissingRecording> missing;
  final DocumentWriter _writer;
  String _name;
  String? _documentPath;
  Map<String, Object?>? _document;

  // The path [_document]'s relative paths are relative to.
  String _documentBase;
  bool _dirty;
  bool _saving = false;

  // Counts the user's changes, so a save knows whether the day changed
  // while its snapshot was being written.
  int _revision = 0;

  /// Keeps the day while it has unsaved changes; none when null.
  final RecoveryStore? recovery;
  final _recoveryWrites = RecoveryWrites(recoveryDelay);

  /// The user's unsaved corrections to the segments.
  final DaySegmentEdits _segmentEdits = DaySegmentEdits();

  final TheoreticalBestRunner _theoreticalBestRunner;
  // The coach's plan being prepared, stopped when the day it is for
  // changes or the day closes.
  final LatestCoachJob _coachJob;
  final SegmentReviewRunner _segmentReviewRunner;
  DayProposalReview? _segmentReview;
  bool _segmentReviewLoading = false;
  int _segmentReviewGeneration = 0;
  DayTheoreticalBest? _segmentReviewFor;
  DayCoach? _coach;
  bool _coachLoading = false;
  DayTheoreticalBest? _theoreticalBest;
  bool _theoreticalBestLoading = false;
  int _theoreticalBestGeneration = 0;
  bool _disposed = false;

  // This day's [declaredSpeedUnits], cleared when it closes unless another
  // day has opened since.
  late List<String> _declaredSpeedUnits;

  /// How long changes wait before the unsaved day is written for recovery.
  static const recoveryDelay = Duration(milliseconds: 500);

  String get name => _name;

  /// Where the day was last saved or opened from; null for a new day.
  String? get documentPath => _documentPath;

  /// Whether there are changes since the day was saved or opened.
  bool get dirty => _dirty || _documentPath == null;
  bool get saving => _saving;

  /// The day as a document written at [path], with [metadata] as the
  /// sessions' details.
  Map<String, Object?> _documentAt(
    String path,
    Map<String, RunMetadata> metadata,
  ) => dayDocument(
    eventId: eventId,
    name: _name,
    runs: runs,
    analysis: _analysis,
    exclusions: _exclusions,
    projectPath: path,
    previous: _document,
    previousPath: _documentBase,
    trackSegments: _segmentEdits.runs,
    trackSegmentReviews: _segmentEdits.reviews,
    groupChosen: _groupDecided,
    comparison: _comparisonChoice,
    fusions: _fusions,
    pendingAlternatives: _pendingRecordings,
    runMetadata: metadata,
    weather: weather.fetched,
  );

  int _saveCount = 0;

  /// How many times the day was saved by [save]; a listener sees it change
  /// when a save finished.
  int get saveCount => _saveCount;

  /// Writes a copy of the day, as it is now, to [path] for FlappedEar
  /// Overlays: its recordings referenced from there. The day itself stays
  /// where it is saved, with its changes still to save. Throws
  /// [FetprojectError] when the copy cannot be written.
  Future<void> exportCopy(String path) async {
    while (_saving) {
      await _saveDone?.future;
    }
    await _writer(path, _documentAt(path, {..._metadataEdits}));
  }

  /// Saves the day to [path]: the event, its runs and recordings, the
  /// layouts set by the user and the excluded laps. Throws
  /// [FetprojectError] when the document cannot be written; the previous
  /// file is then left as it was. Where only the file itself may be
  /// written, such as in the macOS sandbox, it is written in place and,
  /// after a failure, restored when possible (see `writeFetproject`).
  ///
  /// A recording paired with a session in a review that the day opened
  /// again would not fuse by itself (anything but a VBO session's RCZ) is
  /// waited for while it is being aligned, so the file says how the pair
  /// is fused: Overlays' schema has no way to say a pair is still to be
  /// fused. With [settle] false (the save right after an addition, so the
  /// added recordings are on disk at once) the day is written without
  /// waiting and stays unsaved until it is saved again after the
  /// alignment.
  Future<void> save(String path, {bool settle = true}) async {
    // One save at a time: a save asked for while another runs, such as
    // Save as… during the save after adding a session, follows it.
    while (_saving) {
      await _saveDone?.future;
    }
    _saving = true;
    final done = _saveDone = Completer<void>();
    if (!_disposed) notifyListeners();
    try {
      // Taken at once otherwise: changes made from here on are not saved.
      // The page is not left while the save waits; a day closed meanwhile
      // all the same (the app quitting) is written as it is, without the
      // pair's fusion, rather than not at all.
      if (settle && _reviewedPairingPending) {
        _saveWaiting = true;
        if (!_disposed) notifyListeners();
        try {
          await _reviewedPairingsSettled();
        } finally {
          _saveWaiting = false;
          // The page may be left again now, while the file is written.
          if (!_disposed) notifyListeners();
        }
      }
      final pairingPending = _reviewedPairingPending;
      final revision = _revision;
      final metadataNow = {..._metadataEdits};
      final document = _documentAt(path, metadataNow);
      // Changes still waiting for the recovery snapshot are written to it
      // first: where the file is written in place (the macOS sandbox), the
      // app ending partway would cut it, and the snapshot then still holds
      // every change (Arek's second audit, finding 3).
      if (_recoveryWrites.waiting) await flushRecovery();
      await _writer(path, document);
      _document = document;
      // The details saved are in the document now; later edits stay.
      for (final MapEntry(:key, :value) in metadataNow.entries) {
        if (_metadataEdits[key] == value) _metadataEdits.remove(key);
      }
      _documentPath = path;
      _documentBase = path;
      ++_saveCount;
      // Segment edits wait while saving, so the saved ones are all of them.
      _segmentEdits.clear();
      // Automatic segments were approved by the save with their own ids:
      // edits start from the saved ones.
      if (_theoreticalBest?.automaticSegments ?? false) _resetTheoreticalBest();
      if (_revision == revision && !pairingPending) {
        _dirty = false;
        _recoveryWrites
          ..cancel()
          ..enqueue(() => _clearOwnRecovery(recovery, eventId));
      } else {
        // The day changed while the snapshot was written: those changes
        // are not in the file, so the day stays unsaved and recoverable.
        _dirty = true;
        // An addition saves the day again right after, and keeps it for
        // recovery itself if that fails: a saved day does not go through
        // the recovery slot, which may hold another day's unsaved work.
        if (_waitingAdditions == 0) _scheduleRecovery();
      }
    } finally {
      _saving = false;
      done.complete();
      if (!_disposed) notifyListeners();
    }
  }

  // Completes when the running save has finished.
  Completer<void>? _saveDone;

  // Clears the recovery slot when it holds this day: a save never removes
  // another day's unsaved work.
  static Future<void> _clearOwnRecovery(
    RecoveryStore? store,
    String eventId,
  ) async {
    if (store == null) return;
    final kept = await store.load();
    final event = kept?.document['event'];
    if (kept == null || (event is Map && event['id'] == eventId)) {
      await store.clear();
    }
  }

  /// Prepares an addition: its [DayAppendOutcome], or the [DayAddition]
  /// saying why nothing was added.
  Future<Object> _prepare(DayAppendRequest request) async {
    final job = _appender.start(request, (_, _) {});
    _appendJob = job;
    try {
      return await job.result;
    } on OperationCancelled {
      return DayAddition(
        notes: const [],
        error: 'Adding was cancelled.',
        closed: _disposed,
      );
    } on Object catch (error) {
      return DayAddition(notes: const [], error: 'Nothing was added: $error');
    } finally {
      if (identical(_appendJob, job)) _appendJob = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// The group the day's document saved as shown, which leads when the day
  /// is opened again, as it does here: an added session does not change it.
  String? get _savedGroupId {
    final event = _document?['event'];
    final decisions = event is Map ? event['analysisDecisions'] : null;
    final group = decisions is Map ? decisions['comparisonGroupId'] : null;
    return group is String ? group : null;
  }

  /// The new [runs] that are another format of one of the day's sessions,
  /// with that session. Like an import, only one-to-one matches count.
  Map<String, NamedRun> _otherFormats(List<NamedRun> runs) {
    final matches = <(NamedRun, NamedRun)>[];
    for (final added in runs) {
      for (final named in _runs) {
        if (sameDriveInOtherFormat(added.run, named.run)) {
          matches.add((added, named));
        }
      }
    }
    int count(NamedRun named) => matches
        .where(
          (match) => identical(match.$1, named) || identical(match.$2, named),
        )
        .length;
    return {
      for (final (added, named) in matches)
        if (count(added) == 1 && count(named) == 1) added.run.id: named,
    };
  }

  final DayAppender _appender;

  /// Prepares recordings for the review of an addition (FET-58).
  final ImportPreparer _preparer;
  ImportPreparer get preparer => _preparer;
  ImportPreviewJob? _previewJob;

  /// Reads [paths] for the user's review of adding them to the day
  /// (FET-58): what happens to each recording without review, which of the
  /// day's sessions one may join, and which the day has already. Nothing is
  /// added. Null when the day was closed or the reading was cancelled.
  Future<DayAdditionReview?> reviewAddition(List<String> paths) async {
    if (_disposed || paths.isEmpty) return null;
    _previewJob?.cancel();
    final job = _preparer.start((
      paths: List.of(paths),
      includeSubfolders: false,
    ), (_, _) {});
    _previewJob = job;
    final ImportPreview preview;
    try {
      preview = await job.result;
    } on OperationCancelled {
      return null;
    } on Object catch (error) {
      return DayAdditionReview._failed('$error', const []);
    } finally {
      if (identical(_previewJob, job)) _previewJob = null;
    }
    if (_disposed) return null;
    final plan = preview.plan;
    if (plan == null) {
      return DayAdditionReview._failed(preview.scan.error, preview.scan.notes);
    }
    if (plan.runs.isEmpty) {
      return DayAdditionReview._failed(
        'No recording could be imported.',
        importPlanNotes(preview.scan, plan),
      );
    }
    final inDay = {
      for (final named in _runs) named.run.id,
      for (final recording in missing) recording.runId,
    };
    final grouped = _sessionsWithOtherRecording();
    final sessions = {for (final named in _runs) named.run.id};
    // As adding without review does: the automatic grouping within the
    // recordings, then an RCZ of one of the day's VBO sessions joins it, and
    // another format of a session is not added again.
    final automatic = automaticImportChoices(plan);
    // As Overlays: a recording grouped with one the day has is a run again.
    final groups = {
      for (final MapEntry(:key, :value) in automatic.entries)
        key: inDay.contains(value) ? key : value,
    };
    final others = _otherFormats([
      for (final run in plan.runs)
        if (groups[run.id] == run.id && !inDay.contains(run.id))
          (run: run, name: ''),
    ]);
    final choices = <String, String>{};
    for (final run in plan.runs) {
      final group = groups[run.id]!;
      final session = others[run.id]?.run;
      choices[run.id] = inDay.contains(run.id)
          ? skipRecording
          : group != run.id
          ? group
          : session == null
          ? run.id
          : run.format == RecordingFormat.rcz &&
                session.format == RecordingFormat.vbo &&
                !grouped.contains(session.id)
          ? session.id
          : skipRecording;
    }
    return DayAdditionReview._(
      plan: plan,
      automatic: releaseOrphanedChoices(choices, runs: sessions),
      automaticNewDay: automatic,
      sessions: [
        for (final named in _runs) (runId: named.run.id, name: named.name),
      ],
      alreadyGrouped: grouped,
      alreadyInDay: inDay,
      runCount: _runs.length + missing.length,
    );
  }

  /// The day's sessions that have a recording besides their primary in any
  /// state: fused, being aligned, kept beside it, not found or not usable,
  /// or only named by the saved document. A review never gives them another
  /// one, so no recording of theirs is ever replaced (FET-58).
  Set<String> _sessionsWithOtherRecording() {
    final documentRuns = <String, int>{};
    final event = _document?['event'];
    if (event is Map && event['runs'] is List) {
      for (final run in event['runs'] as List) {
        if (run is! Map || run['id'] is! String) continue;
        final sources = run['sources'];
        final telemetry = sources is Map ? sources['telemetry'] : null;
        documentRuns[run['id'] as String] = telemetry is List
            ? telemetry.length
            : 0;
      }
    }
    return {
      for (final named in _runs)
        if (_fusions.containsKey(named.run.id) ||
            _pendingRecordings.containsKey(named.run.id) ||
            _fusionPending.containsKey(named.run.id) ||
            _documentAlternatives.containsKey(named.run.id) ||
            (documentRuns[named.run.id] ?? 0) > 1)
          named.run.id,
    };
  }

  /// Prepares the recordings added to the day.
  DayAppender get appender => _appender;
  DayAppendJob? _appendJob;

  /// Whether recordings are being added to the day, or wait to be.
  bool get adding => _waitingAdditions > 0;
  int _waitingAdditions = 0;
  // Completes when the last addition asked for has finished; null when
  // none has been asked for.
  Future<void>? _additions;

  // Sessions whose added RCZ failed to align before their addition reported.
  final List<String> _notCombinedWhileAdding = [];

  /// Adds the recordings at [paths] that are not in the day yet as its next
  /// sessions. Only they are read; the day is grouped and ranked again with
  /// the user's layouts, exclusions and chosen group, and a day that has
  /// been saved is saved again where it was. Additions run one after
  /// another, in the order asked. With [sameDayOnly], nothing is added
  /// unless every new recording started on the day's date
  /// ([DayAddition.otherDay]). [since], when given, runs from when the
  /// recordings arrived (a share opening the day first), for the
  /// diagnostics; else the time is measured from this call, waiting for
  /// earlier additions included.
  ///
  /// With [review] and [choices] (FET-58), the recordings are added as the
  /// user chose in [review] instead of the automatic grouping; nothing is
  /// added when the day or the recordings changed since
  /// ([DayAddition.reviewChanged]), or when [choices] are ones the review
  /// does not accept ([DayAddition.choicesRefused]).
  Future<DayAddition> addRecordings(
    List<String> paths, {
    bool sameDayOnly = false,
    Stopwatch? since,
    DayAdditionReview? review,
    ImportChoices? choices,
  }) async {
    final clock = since ?? (Stopwatch()..start());
    if (paths.isEmpty) return const DayAddition(notes: []);
    if (_disposed) {
      return const DayAddition(
        notes: [],
        error: 'The day was closed.',
        closed: true,
      );
    }
    ++_waitingAdditions;
    notifyListeners();
    final previous = _additions;
    final done = Completer<void>();
    _additions = done.future;
    DayAddition addition;
    try {
      if (previous != null) await previous;
      addition = await _add(
        paths,
        sameDayOnly: sameDayOnly,
        clock: clock,
        review: review,
        choices: choices,
      );
      if (_notCombinedWhileAdding.isNotEmpty) {
        addition = addition._notCombined([..._notCombinedWhileAdding]);
        _notCombinedWhileAdding.clear();
      }
    } finally {
      --_waitingAdditions;
      done.complete();
    }
    if (!_disposed) {
      _lastAddition = addition;
      notifyListeners();
    }
    return addition;
  }

  Future<DayAddition> _add(
    List<String> paths, {
    required bool sameDayOnly,
    required Stopwatch clock,
    DayAdditionReview? review,
    ImportChoices? choices,
  }) async {
    if (_disposed) {
      return const DayAddition(
        notes: [],
        error: 'The day was closed.',
        closed: true,
      );
    }
    int? sameDayAs;
    if (sameDayOnly) {
      for (final named in _runs) {
        final start = recordingTimestamp(named.run.telemetry);
        if (start != null && (sameDayAs == null || start > sameDayAs)) {
          sameDayAs = start;
        }
      }
      if (sameDayAs == null) {
        return const DayAddition(notes: [], otherDay: true);
      }
    }
    final reviewed = review != null && choices != null;
    if (reviewed &&
        (review.runCount != _runs.length + missing.length ||
            !setEquals(
              {for (final session in review.sessions) session.runId},
              {for (final named in _runs) named.run.id},
            ) ||
            !setEquals(review.alreadyGrouped, _sessionsWithOtherRecording()))) {
      // A session was added (shared, say), or one got another recording,
      // while the review was open.
      return const DayAddition(notes: [], reviewChanged: true);
    }
    if (reviewed && choices.values.any(review.alreadyGrouped.contains)) {
      // Never replaces a session's other recording.
      return const DayAddition(notes: [], reviewChanged: true);
    }
    if (reviewed &&
        checkImportChoices(
              [for (final run in review.plan?.runs ?? const []) run.id],
              choices,
              runs: {for (final session in review.sessions) session.runId},
              alreadyGrouped: review.alreadyGrouped,
            ) !=
            null) {
      // Choices the review would not have confirmed (the page checks them
      // the same way): nothing is added.
      return const DayAddition(notes: [], choicesRefused: true);
    }
    final names = {for (final named in _runs) named.run.id: named.name};
    final request = (
      paths: List.of(paths),
      runIds: {
        for (final named in _runs) named.run.id,
        for (final recording in missing) recording.runId,
      },
      runCount: _runs.length + missing.length,
      rowCount: _analysis.rows.length,
      sameDayAs: sameDayAs,
      // The recordings the user made the same run as one of the sessions.
      alternatives: <String, String>{
        if (reviewed)
          for (final MapEntry(:key, :value) in choices.entries)
            if (key != value && names[value] != null) key: names[value]!,
      },
      alternativeOf: <String, String>{
        if (reviewed)
          for (final MapEntry(:key, :value) in choices.entries)
            if (key != value && names.containsKey(value)) key: value,
      },
      choices: reviewed ? Map.of(choices) : null,
    );
    var prepared = await _prepare(request);
    if (prepared case DayAppendOutcome(:final runs)
        when runs.isNotEmpty && !reviewed) {
      // A VBO and an RCZ of one drive are one session, also when they come
      // one at a time: prepare again without the day's other formats.
      final alternatives = _otherFormats(runs);
      if (alternatives.isNotEmpty && !_disposed) {
        // An RCZ of a VBO session without one becomes its alternative.
        final formats = {for (final named in runs) named.run.id: named.run};
        prepared = await _prepare((
          paths: request.paths,
          runIds: request.runIds,
          runCount: request.runCount,
          rowCount: request.rowCount,
          sameDayAs: request.sameDayAs,
          alternatives: {
            for (final MapEntry(:key, :value) in alternatives.entries)
              key: value.name,
          },
          alternativeOf: {
            for (final MapEntry(:key, :value) in alternatives.entries)
              if (formats[key]?.format == RecordingFormat.rcz &&
                  value.run.format == RecordingFormat.vbo &&
                  !(_fusions[value.run.id]?.fused ?? false))
                key: value.run.id,
          },
          choices: null,
        ));
      }
    }
    if (prepared is DayAddition) return prepared;
    final outcome = prepared as DayAppendOutcome;
    if (outcome.reviewChanged) {
      return DayAddition(notes: outcome.notes, reviewChanged: true);
    }
    final part = outcome.part;
    appErrorReporter.coreDefects(
      messages: part?.messages ?? const [],
      notes: outcome.notes,
    );
    if (_disposed) {
      return const DayAddition(
        notes: [],
        error: 'The day was closed.',
        closed: true,
      );
    }
    final adding = part != null && outcome.runs.isNotEmpty;
    // An RCZ for one of the day's sessions is added to it, not as a session.
    final combined = [
      for (final named in _runs)
        if (outcome.alternatives.containsKey(named.run.id)) named.name,
    ];
    if (!adding && combined.isEmpty) {
      return DayAddition(
        notes: outcome.notes,
        error: outcome.error,
        otherDay: outcome.otherDay,
      );
    }
    if (adding) {
      try {
        _analysis = extendDay(
          _analysis,
          part,
          manualTracks: _analysis.manualTracks,
          exclusions: _exclusions,
          preferredGroupId: _groupChosen ? _groupId : _savedGroupId,
        );
      } on Exception catch (error) {
        return DayAddition(
          notes: outcome.notes,
          error: 'Nothing was added: $error',
        );
      }
    }
    final existing = {for (final named in _runs) named.run.id};
    _runs.addAll(outcome.runs);
    _addedRunIds.addAll([for (final named in outcome.runs) named.run.id]);
    weather.sync(runs, _savedRuns);
    // What reads channels includes the new sessions.
    _channelRuns = _recordingRuns = null;
    // The new session's speed unit counts as much as the others'.
    if (identical(declaredSpeedUnits, _declaredSpeedUnits)) {
      declareDaySpeedUnits([for (final run in _runs) run.run.telemetry]);
      _declaredSpeedUnits = declaredSpeedUnits;
    }
    if (identical(dayChannelSources, _declaredChannelSources)) {
      _declareChannelSources();
    }
    if (!_groupChosen) _groupId = _analysis.chosenGroupId;
    _dirty = true;
    _revision++;
    if (adding) {
      // The day's corners stay the ones in use when sessions are added: the
      // automatic segments are kept, as saving would keep them, rather than
      // proposed again from a new best lap. Before the first theoretical
      // best is ready no corners were shown yet, so there are none to keep.
      if (_theoreticalBest case final best?) _segmentEdits.keepAutomatic(best);
      _resetTheoreticalBest();
      // Unless the kept corners cannot time a new best lap (FET-170).
      final added = {for (final named in outcome.runs) named.run.id};
      _remeasure.added([
        for (final group in _analysis.groups)
          if (group.runIds.any(added.contains)) group.id,
      ]);
    }
    _resetChannelSummaries();
    // Each RCZ is aligned and fused once the sessions show. One added to a
    // session that already names an RCZ (one that was not found, say) takes
    // that source's place rather than adding another.
    for (final MapEntry(key: runId, value: recording)
        in outcome.alternatives.entries) {
      final sourceId =
          _fusions[runId]?.alternativeSourceId ??
          _documentAlternatives[runId]?.sourceId;
      _startFusion(
        runId,
        recording: existing.contains(runId) && sourceId != null
            ? TelemetryRunProposal(
                id: recording.id,
                sourceId: sourceId,
                sourcePath: recording.sourcePath,
                format: recording.format,
                contentSha256: recording.contentSha256,
                telemetry: recording.telemetry,
                laps: recording.laps,
              )
            : recording,
        addition: true,
      );
    }
    // A day with a file is saved again below; only a day without one is
    // kept for recovery now, so a share into a saved day does not replace
    // the unsaved day the recovery slot may hold.
    if (_documentPath == null && !_saving) _scheduleRecovery();
    diagnostics.recordStep(DiagnosticSteps.addSession, clock.elapsed);
    // Measured on to the coach's plan for it (see _requestCoach).
    _additionClock = clock;
    notifyListeners();
    var saveError = '';
    // A save running now may have been asked for a new file: the day is
    // saved where that save leaves it.
    while (_saving) {
      await _saveDone?.future;
    }
    final path = _documentPath;
    if (path != null && _dirty) {
      try {
        await save(path, settle: false);
      } on Exception catch (error) {
        saveError = '$error';
      }
    }
    // Not saved: kept for recovery, also when the day was closed meanwhile.
    if (_dirty && (path == null || saveError.isNotEmpty)) {
      if (_disposed) {
        _writeRecovery();
      } else {
        _scheduleRecovery();
      }
    }
    return DayAddition(
      added: [for (final named in outcome.runs) named.name],
      combined: combined,
      notes: outcome.notes,
      savedTo: path != null && saveError.isEmpty ? path : null,
      saveError: saveError,
    );
  }

  /// The last addition that finished, for the page to report; null before
  /// the first.
  DayAddition? get lastAddition => _lastAddition;
  DayAddition? _lastAddition;

  /// Stops adding recordings; nothing from it is kept.
  void cancelAdding() => _appendJob?.cancel();

  DayAnalysis get analysis => _analysis;
  DayRanking? get ranking => _analysis.ranking;
  Map<DayLapReference, String> get exclusions => Map.unmodifiable(_exclusions);

  /// The session of [runId] as the analysis that reads channels sees it:
  /// its recording with the channels fused from its alternative recording.
  /// Laps and lap timing come from the recording alone.
  TelemetrySession? session(String runId) {
    for (final named in runs) {
      if (named.run.id == runId) {
        return _analysed(named, _fusions[runId]?.session).run.telemetry;
      }
    }
    return null;
  }

  /// The comparison saved with the day, with what was set up since: laps
  /// of this day (null when not one of its laps), range and charts.
  ComparisonDecisions get savedComparison {
    final document = _document;
    final saved = document == null
        ? const ComparisonDecisions()
        : documentComparison(document, _runs);
    return saved.overriddenBy(_comparisonChoice);
  }

  /// The saved pair (A, B) when both are still eligible laps of one group,
  /// or null.
  (DayLapRow, DayLapRow)? get savedComparisonPair {
    final slots = savedComparison.slots;
    if (slots == null || slots.length != 2) return null;
    DayLapRow? rowOf(DayLapReference? reference) {
      if (reference == null) return null;
      for (final row in _analysis.rows) {
        if (row.reference == reference) return row;
      }
      return null;
    }

    final a = rowOf(slots[0]), b = rowOf(slots[1]);
    if (a == null || b == null || a.reference == b.reference) return null;
    return comparable(a, b) ? (a, b) : null;
  }

  // Records a change of the comparison decisions: saved with the day.
  void _chooseComparison(ComparisonDecisions choice) {
    final before = savedComparison;
    final after = before.overriddenBy(choice);
    bool sameList<T>(List<T>? x, List<T>? y) =>
        x == null ? y == null : y != null && listEquals(x, y);
    if (sameList(before.slots, after.slots) &&
        before.range == after.range &&
        sameList(before.channels, after.channels)) {
      return;
    }
    _comparisonChoice = _comparisonChoice.overriddenBy(choice);
    _revision++;
    _dirty = true;
    _scheduleRecovery();
    notifyListeners();
  }

  /// The comparison page shows [a] against [b]: saved as the day's
  /// comparison (Overlays' `comparisonSlots`).
  void rememberComparisonPair(DayLapRow a, DayLapRow b) =>
      _chooseComparison(ComparisonDecisions(slots: [a.reference, b.reference]));

  /// The comparison shows [start]..[end] meters of its axis.
  void rememberComparisonRange(double start, double end) {
    if (!ComparisonDecisions.validRange((start, end))) return;
    _chooseComparison(ComparisonDecisions(range: (start, end)));
  }

  /// The comparison shows the charts [channels].
  void rememberComparisonChannels(List<String> channels) {
    if (!ComparisonDecisions.validChannels(channels)) return;
    _chooseComparison(ComparisonDecisions(channels: [...channels]));
  }

  /// The laps [row] can be compared with: the eligible laps of its group.
  List<DayLapRow> comparisonCandidates([DayLapRow? row]) =>
      dayComparisonCandidates(_analysis, row);

  /// Whether [a] and [b] are two eligible laps of one group.
  bool comparable(DayLapRow a, DayLapRow b) =>
      dayLapsComparable(_analysis, a, b);

  /// The best lap to compare [row] with: the best of the group, or of its
  /// session with [sameRun]; when that is [row] itself, the next fastest.
  DayLapRow? comparisonPartner(DayLapRow row, {bool sameRun = false}) {
    final best = dayBestComparisonLap(_analysis, row, sameRun: sameRun);
    if (best != null && best.reference != row.reference) return best;
    final others = [
      for (final candidate in comparisonCandidates(row))
        if (candidate.reference != row.reference &&
            (!sameRun || candidate.runId == row.runId))
          candidate,
    ]..sort((x, y) => x.durationSeconds.compareTo(y.durationSeconds));
    return others.firstOrNull;
  }

  // The last comparisons built, kept while their pages are open.
  final _comparisons = <(DayLapReference, DayLapReference), LapComparison>{};

  /// [a] against [b] on a shared track-position axis, built once per pair
  /// from the day's recordings; null when either is not a timed lap here.
  LapComparison? comparison(DayLapRow a, DayLapRow b) {
    final key = (a.reference, b.reference);
    final cached = _comparisons.remove(key);
    if (cached != null) return _comparisons[key] = cached;
    final lapA = dayComparisonLap(_analysisRuns, a);
    final lapB = dayComparisonLap(_analysisRuns, b);
    if (lapA == null || lapB == null) return null;
    final built = LapComparison(lapA, lapB);
    _comparisons[key] = built;
    while (_comparisons.length > 4) {
      _comparisons.remove(_comparisons.keys.first);
    }
    return built;
  }

  // The Corner Analyzers of the last comparisons; dropped on any change of
  // the day, since their segments may have changed.
  final _analyzers =
      <(DayLapReference, DayLapReference, bool), DayCornerAnalyzer>{};

  @override
  void notifyListeners() {
    _analyzers.clear();
    super.notifyListeners();
  }

  /// The Corner Analyzer of [a] against [b]: the approved segments both
  /// laps' runs share or, with [fromTheoreticalBest] (opened from a result
  /// of it), the theoretical best's segments when theirs differ, as
  /// Overlays measures evidence against the segments that led to it. Null
  /// without a shared axis.
  DayCornerAnalyzer? cornerAnalyzer(
    DayLapRow a,
    DayLapRow b, {
    bool fromTheoreticalBest = false,
  }) {
    final comparison = this.comparison(a, b);
    if (comparison == null || !comparison.axis.valid) return null;
    final key = (a.reference, b.reference, fromTheoreticalBest);
    final cached = _analyzers.remove(key);
    if (cached != null && identical(cached.analyzer.axis, comparison.axis)) {
      return _analyzers[key] = cached;
    }
    final result = _theoreticalBestLoading ? null : _theoreticalBest;
    final documentRuns = _documentRuns;
    final own = dayComparisonSegmentation(
      _analysis,
      a,
      b,
      documentRuns: documentRuns,
    );
    final borrowed = result == null
        ? own
        : dayComparisonSegmentation(
            _analysis,
            a,
            b,
            documentRuns: documentRuns,
            theoreticalBest: result,
          );
    final used = fromTheoreticalBest ? borrowed : own;
    var note = '';
    if (used.borrowed && used.shared != null && result != null) {
      final best = result.bestLap;
      note = result.automaticSegments && best != null
          ? 'Segments proposed from ${best.displayName}, as used by the '
                'sector theoretical best; saving the day approves them. '
                'Boundaries are distances along that lap\'s axis, so they '
                'can shift by a few metres on these laps.'
          : 'Segments approved on ${_runName(result.segmentRunId)}, as used '
                'by the sector theoretical best. Boundaries are distances '
                'along that run\'s axis, so they can shift by a few metres on '
                'these laps.';
    }
    final built = _analyzers[key] = DayCornerAnalyzer(
      analyzer: CornerAnalyzer.of(comparison, used),
      note: note,
      theoreticalBestAvailable:
          !fromTheoreticalBest && own.shared == null && borrowed.shared != null,
    );
    while (_analyzers.length > 4) {
      _analyzers.remove(_analyzers.keys.first);
    }
    return built;
  }

  String _runName(String runId) {
    for (final row in _analysis.rows) {
      if (row.runId == runId) return row.runName;
    }
    return runId;
  }

  /// Shows [groupId]'s ranking first.
  void chooseGroup(String groupId) {
    if (groupId == _analysis.chosenGroupId) {
      // Picking the group already shown is still a choice, saved as
      // Overlays saves it, unless the day already saves that group.
      if (_groupDecided || _savedGroupId == groupId) return;
      _groupId = groupId;
      _groupChosen = true;
      _groupDecided = true;
      _revision++;
      _dirty = true;
      _scheduleRecovery();
      notifyListeners();
      return;
    }
    _groupId = groupId;
    _groupChosen = true;
    _groupDecided = true;
    _rerank();
  }

  /// Leaves [row] out of the ranking with [reason]; an empty reason is
  /// refused.
  bool exclude(DayLapRow row, String reason) {
    final trimmed = reason.trim();
    if (row.type != LapSectionType.lap ||
        trimmed.isEmpty ||
        trimmed.length > 256) {
      return false;
    }
    // The same reason again changes nothing, so the day stays as it was.
    if (_exclusions[row.reference] == trimmed) return true;
    _exclusions[row.reference] = trimmed;
    _rerank();
    return true;
  }

  void include(DayLapRow row) {
    if (_exclusions.remove(row.reference) != null) _rerank();
  }

  /// The user's reason for excluding [row], or null.
  String? exclusionReason(DayLapRow row) => _exclusions[row.reference];

  /// The user's layout name and direction for [runId], or null when the
  /// detected route is used.
  TrackConfiguration? manualTrack(String runId) =>
      _analysis.manualTracks[runId];

  /// Runs other than [runId] whose detected route matches its route.
  List<String> runsOnSameRoute(String runId) {
    final route = _analysis.inferences[runId]?.route;
    if (route == null) return const [];
    final matching = <String>[];
    for (final named in runs) {
      final other = _analysis.inferences[named.run.id]?.route;
      if (named.run.id != runId && other != null && routesMatch(route, other)) {
        matching.add(named.run.id);
      }
    }
    return matching;
  }

  /// Sets the layout name and direction of [runIds]. A manual layout always
  /// wins over the detected route.
  bool setTrack(
    List<String> runIds,
    String layoutName,
    TrackDirection direction,
  ) {
    final name = layoutName.trim();
    if (runIds.isEmpty ||
        name.isEmpty ||
        name.length > 128 ||
        name.contains('\u0000')) {
      return false;
    }
    _regroup({
      ..._analysis.manualTracks,
      for (final id in runIds)
        id: TrackConfiguration(layoutId: name, direction: direction),
    }, runIds.first);
    return true;
  }

  /// Goes back to the detected route for [runId].
  void useDetectedRoute(String runId) {
    if (!_analysis.manualTracks.containsKey(runId)) return;
    _regroup({..._analysis.manualTracks}..remove(runId), runId);
  }

  /// Groups again and shows the group of [followRunId], whose group id has
  /// just changed.
  void _regroup(Map<String, TrackConfiguration> manual, String followRunId) {
    _analysis = regroupDay(
      _analysis,
      manualTracks: manual,
      exclusions: _exclusions,
    );
    final follow = _analysis.configurations[followRunId]?.compatibilityGroupId;
    _groupId = follow ?? _analysis.chosenGroupId;
    _groupChosen = true;
    _rerank();
  }

  // The progression and lap consistency of [_explainedFor].
  DayAnalysis? _explainedFor;
  DayProgression? _progression;
  LapConsistency? _lapConsistency;

  void _explain() {
    if (identical(_explainedFor, _analysis)) return;
    _explainedFor = _analysis;
    _progression = dayProgression(_analysis, progressionRuns);
    _lapConsistency = dayLapConsistency(_analysis);
  }

  /// The day's runs with the notes, conditions and setup changes the
  /// document records for them.
  List<ProgressionRunInfo> get progressionRuns =>
      progressionRunInfo(runs, documentRuns: _metadataRuns);

  // The document's runs with the unsaved edits of their details.
  List<Object?> get _metadataRuns =>
      applyRunMetadataEdits(_savedRuns, _metadataEdits);

  // The user's unsaved edits of sessions' details, by run id.
  final Map<String, RunMetadata> _metadataEdits = {};

  /// [runId]'s name, notes, conditions and setup changes as the user sees
  /// them, unsaved edits included.
  RunMetadata runMetadata(String runId) {
    final edited = _metadataEdits[runId];
    if (edited != null) return edited;
    final named = _named(runId);
    for (final value in _savedRuns) {
      if (value case final Map<String, Object?> run when run['id'] == runId) {
        final stored = RunMetadata.fromRun(run);
        return RunMetadata(
          name: named?.name ?? stored.name,
          notes: stored.notes,
          conditions: stored.conditions,
          setupChanges: stored.setupChanges,
        );
      }
    }
    return RunMetadata(name: named?.name ?? '');
  }

  /// Edits [runId]'s name, notes, conditions and setup changes, as
  /// FlappedEar Overlays edits them ([applyRunMetadata]): the day then has
  /// unsaved changes. Returns why not ([runMetadataProblem]), or null.
  String? updateRunMetadata(String runId, RunMetadata metadata) {
    final named = _named(runId);
    if (named == null) return 'The session is not in this day.';
    final problem = runMetadataProblem(metadata);
    if (problem != null) return problem;
    final current = runMetadata(runId);
    final run = <String, Object?>{
      'name': current.name,
      for (final MapEntry(:key, :value) in {
        'notes': current.notes,
        'conditions': current.conditions,
        'setupChanges': current.setupChanges,
      }.entries)
        if (value.isNotEmpty) key: value,
    };
    if (!applyRunMetadata(run, metadata)) return null;
    final name = metadata.name.trim();
    _metadataEdits[runId] = RunMetadata(
      name: name,
      notes: metadata.notes,
      conditions: metadata.conditions,
      setupChanges: metadata.setupChanges,
    );
    if (name != named.name) {
      _runs[_runs.indexOf(named)] = (run: named.run, name: name);
      _channelRuns = _recordingRuns = null;
      _analysis = renameDayRun(
        _analysis,
        runId,
        name,
        exclusions: _exclusions,
        preferredGroupId: _groupId,
      );
      // Their results name the session.
      _resetTheoreticalBest();
      _resetChannelSummaries();
    }
    _explainedFor = null;
    _detailsChanged();
    return null;
  }

  /// Renames the day (the document's event name, which Overlays shows too).
  /// Returns why not ([dayNameProblem]), or null.
  String? renameDay(String name) {
    final problem = dayNameProblem(name);
    if (problem != null) return problem;
    final trimmed = name.trim();
    if (trimmed == _name) return null;
    _name = trimmed;
    _detailsChanged();
    return null;
  }

  void _detailsChanged() {
    _revision++;
    _dirty = true;
    _scheduleRecovery();
    notifyListeners();
  }

  /// The shown group's runs in recording order with their best laps.
  DayProgression get progression {
    _explain();
    return _progression!;
  }

  /// How repeatable the shown group's lap times are.
  LapConsistency get lapConsistency {
    _explain();
    return _lapConsistency!;
  }

  /// The shown group's theoretical best, sector times and loss map; null
  /// until [requestTheoreticalBest] has finished for the current laps.
  DayTheoreticalBest? get theoreticalBest => _theoreticalBest;
  bool get theoreticalBestLoading => _theoreticalBestLoading;

  // Built outside the controller so the isolate's closure holds only its
  // inputs.
  // With [remeasure], segments that cannot time the best lap are measured
  // again on it (remeasureDaySegments).
  static DayTheoreticalBest Function() _theoreticalBestJob(
    DayAnalysis analysis,
    Map<String, OutingRun> runs,
    List<Object?> documentRuns, {
    bool remeasure = false,
  }) => () {
    final result = dayTheoreticalBest(
      analysis,
      runs,
      documentRuns: documentRuns,
    );
    if (!remeasure) return result;
    return remeasureDaySegments(
          analysis,
          runs,
          result,
          documentRuns: documentRuns,
        ) ??
        result;
  };

  /// The groups whose kept corners are measured again on a new best lap
  /// they cannot time (FET-170).
  final _remeasure = SegmentRemeasure();

  /// Times every eligible lap of the shown group against its approved
  /// segments (proposed from the best lap when the day has none yet), in the
  /// background. A result for laps that changed meanwhile is dropped.
  Future<void> requestTheoreticalBest() async {
    if (_theoreticalBest != null || _theoreticalBestLoading) return;
    final generation = ++_theoreticalBestGeneration;
    _theoreticalBestLoading = true;
    notifyListeners();
    final documentRuns = _documentRuns;
    _theoreticalKey = decisionsKey;
    final remeasure = _remeasure.pendingFor(_analysis.chosenGroupId);
    DayTheoreticalBest result;
    final clock = Stopwatch()..start();
    try {
      result = await _theoreticalBestRunner(
        _theoreticalBestJob(
          _analysis,
          outingRuns(_unitRuns),
          documentRuns,
          remeasure: remeasure,
        ),
      );
      diagnostics.recordStep(DiagnosticSteps.theoreticalBest, clock.elapsed);
    } on Object catch (error) {
      result = DayTheoreticalBest(
        groupId: _analysis.chosenGroupId ?? '',
        state: DayTheoreticalBestState.error,
        message: '$error',
      );
    }
    if (_disposed || generation != _theoreticalBestGeneration) return;
    if (result.remeasuredRuns.isNotEmpty) {
      // A save running now clears the segment edits when it ends: they are
      // kept after it.
      while (_saving) {
        await _saveDone?.future;
      }
      if (_disposed || generation != _theoreticalBestGeneration) return;
      // Kept as approved, as saving keeps automatic segments; not an edit,
      // so nothing to undo. The day is saved with them.
      _segmentEdits.adoptRemeasured(result.remeasuredRuns);
      _theoreticalKey = decisionsKey;
      _dirty = true;
      _revision++;
      _scheduleRecovery();
    }
    if (remeasure && result.state != DayTheoreticalBestState.error) {
      _remeasure.settled(result.groupId);
    }
    _theoreticalBest = result;
    _theoreticalBestLoading = false;
    notifyListeners();
    unawaited(_requestCoach(result, generation));
  }

  /// Calculates the theoretical best again when it failed or had nothing to
  /// use (Overlays' "Calculate again"). A result still on its way for the
  /// earlier request is dropped by its generation. Returns whether it
  /// started.
  bool retryTheoreticalBest() {
    final result = _theoreticalBest;
    if (_disposed ||
        _theoreticalBestLoading ||
        result == null ||
        !offersCalculateAgain(result)) {
      return false;
    }
    _resetTheoreticalBest();
    unawaited(requestTheoreticalBest());
    return true;
  }

  /// The coach's plan for the next session after the day's latest session,
  /// from the theoretical best; null while it is prepared.
  DayCoach? get coach => _coach;
  bool get coachLoading => _theoreticalBestLoading || _coachLoading;

  /// Whether the coach cannot run because the theoretical best failed.
  bool get coachWithoutTheoreticalBest =>
      _theoreticalBest?.state == DayTheoreticalBestState.error;

  /// Running from the start of the last addition until the coach's plan
  /// for it, a save of automatic segments and its recalculation included;
  /// null once measured, or when it failed or the user changed the day
  /// meanwhile.
  Stopwatch? _additionClock;

  /// Why the coach could not run; empty when it ran.
  String get coachError => _coachError;
  String _coachError = '';

  /// The session recorded last, which the coach coaches: by recording time,
  /// or the one added last when it has no recording time.
  String get latestRunId {
    if (_runs.isEmpty) return '';
    var latest = _runs.last;
    if (recordingTimestamp(latest.run.telemetry) == null) return latest.run.id;
    int? latestStart;
    for (final named in _runs) {
      final start = recordingTimestamp(named.run.telemetry);
      if (start != null && (latestStart == null || start >= latestStart)) {
        latest = named;
        latestStart = start;
      }
    }
    return latest.run.id;
  }

  /// Whether the coach's speeds are converted values: the laps it compared
  /// are in different units (declared, or assumed in settings), so it
  /// reports them all in km/h. Speeds are then not shown (see
  /// [coachSpeedLabel]). Also when the day's recordings are in different
  /// units, whichever laps the coach compared.
  bool get coachSpeedsConverted {
    if (_coach?.speedsConverted ?? false) return true;
    final units = <String>{};
    for (final named in _unitRuns) {
      final session = named.run.telemetry;
      final own = session.channels[session.aliases['speed'] ?? '']?.unit.trim();
      if (own == null) continue;
      units.add(own.isEmpty ? 'km/h' : normalizedSpeedUnit(own));
    }
    return units.length > 1;
  }

  /// The name of [latestRunId]: "Session 4".
  String get latestRunName {
    final id = latestRunId;
    for (final named in _runs) {
      if (named.run.id == id) return named.name;
    }
    return '';
  }

  // [analysis], [runs], [documentRuns] and [exclusions] rebuild the day as
  // it stood before [runId], to check the main focus given then.
  static CoachJob _coachJobFor(
    DayTheoreticalBest result,
    Map<String, TelemetrySession?> sessions,
    String runId, {
    required DayAnalysis analysis,
    required Map<String, OutingRun> runs,
    required List<Object?> documentRuns,
    required Map<DayLapReference, String> exclusions,
  }) =>
      (cancelled) => dayCoach(
        result,
        sessions,
        runId: runId,
        before: dayBeforeRun(
          analysis,
          runs,
          runId,
          documentRuns: documentRuns,
          exclusions: exclusions,
          groupId: result.groupId,
          cancelled: cancelled,
        ),
        cancelled: cancelled,
      );

  /// Prepares the coach's plan again after it failed. Returns whether it
  /// started.
  bool retryCoach() {
    final result = _theoreticalBest;
    if (result == null || _coachLoading || _coachError.isEmpty) return false;
    // The card shows the coach preparing, not the old failure.
    _coachError = '';
    unawaited(_requestCoach(result, _theoreticalBestGeneration));
    return true;
  }

  Future<void> _requestCoach(DayTheoreticalBest result, int generation) async {
    if (result.state == DayTheoreticalBestState.error) {
      // The coach needs the sector times, which failed (see
      // [coachWithoutTheoreticalBest]).
      _additionClock = null;
      _coach = null;
      _coachError = '';
      _coachLoading = false;
      notifyListeners();
      return;
    }
    _coachLoading = true;
    notifyListeners();
    final clock = Stopwatch()..start();
    // A plan still being prepared for the day as it was is stopped.
    final outcome = await _coachJob.run(
      _coachJobFor(
        result,
        {for (final named in _unitRuns) named.run.id: named.run.telemetry},
        latestRunId,
        analysis: _analysis,
        runs: outingRuns(_unitRuns),
        documentRuns: _documentRuns,
        exclusions: {..._exclusions},
      ),
    );
    if (outcome == null ||
        _disposed ||
        generation != _theoreticalBestGeneration) {
      return;
    }
    final (:coach, :error) = outcome;
    if (coach != null) {
      diagnostics.recordStep(DiagnosticSteps.coach, clock.elapsed);
      if (_additionClock case final added?) {
        diagnostics.recordStep(DiagnosticSteps.addToCoach, added.elapsed);
      }
    }
    _additionClock = null;
    _coach = coach;
    _coachError = error;
    _coachLoading = false;
    notifyListeners();
  }

  /// The analysis decisions the shown group is computed under (see
  /// [dayDecisionsKey]).
  List<int> get decisionsKey => dayDecisionsKey(
    _analysis,
    documentRuns: _documentRuns,
    exclusions: _exclusions,
  );

  // The decisions [_theoreticalBest] was requested under.
  List<int> _theoreticalKey = const [];

  /// The areas to inspect next, from the theoretical best; empty until it
  /// is calculated or when nothing stands out.
  List<FocusArea> get focusAreas {
    final result = _theoreticalBest;
    if (result == null || _theoreticalBestLoading) return const [];
    if (!identical(_focusFor, result)) {
      _focusFor = result;
      _focusAreas = dayFocusAreas(result, lapLabel);
    }
    return _focusAreas;
  }

  DayTheoreticalBest? _focusFor;
  List<FocusArea> _focusAreas = const [];

  /// "Session 3 · LAP 2" for a lap reference, or empty.
  String lapLabel(Object? reference) {
    final row = lapRow(reference);
    return row == null ? '' : '${row.runName} · LAP ${row.lapNumber}';
  }

  /// The lap section of [reference]: a [DayLapReference] or one as the day
  /// report writes it.
  DayLapRow? lapRow(Object? reference) {
    if (!identical(_rowsFor, _analysis.rows)) {
      _rowsFor = _analysis.rows;
      _rowsByReference = {for (final row in _analysis.rows) row.reference: row};
    }
    if (reference is DayLapReference) return _rowsByReference[reference];
    if (reference is Map<String, Object?>) {
      for (final row in _analysis.rows) {
        final json = dayLapReferenceJson(row.reference);
        if (json.entries.every(
          (entry) => reference[entry.key] == entry.value,
        )) {
          return row;
        }
      }
    }
    return null;
  }

  List<DayLapRow>? _rowsFor;
  Map<DayLapReference, DayLapRow> _rowsByReference = const {};

  final ChannelSummariesRunner _channelSummariesRunner;
  DayChannelSummaries? _channelSummaries;
  bool _channelSummariesLoading = false;
  int _channelSummariesGeneration = 0;

  void _resetChannelSummaries() {
    _channelSummaries = null;
    _channelSummariesLoading = false;
    ++_channelSummariesGeneration;
  }

  /// The recorded temperatures and heart rate of every run and section;
  /// null until [requestChannelSummaries] has finished. They do not depend
  /// on the group or the segments.
  DayChannelSummaries? get channelSummaries => _channelSummaries;
  bool get channelSummariesLoading => _channelSummariesLoading;

  static DayChannelSummaries Function() _channelSummariesJob(
    List<DayLapRow> rows,
    Map<String, TelemetrySession?> sessions,
  ) =>
      () => summarizeDayChannels(rows, sessions);

  /// Summarizes the recorded channels of every run in the background.
  Future<void> requestChannelSummaries() async {
    if (_channelSummaries != null || _channelSummariesLoading) return;
    final generation = ++_channelSummariesGeneration;
    _channelSummariesLoading = true;
    notifyListeners();
    DayChannelSummaries result;
    final clock = Stopwatch()..start();
    try {
      result = await _channelSummariesRunner(
        _channelSummariesJob(_analysis.rows, {
          for (final named in _analysisRuns) named.run.id: named.run.telemetry,
        }),
      );
      diagnostics.recordStep(DiagnosticSteps.channelSummaries, clock.elapsed);
    } on Object catch (error) {
      result = DayChannelSummaries(error: '$error');
    }
    if (_disposed || generation != _channelSummariesGeneration) return;
    _channelSummaries = result;
    _channelSummariesLoading = false;
    notifyListeners();
  }

  /// Summarizes the channels again after they failed. Returns whether it
  /// started.
  bool retryChannelSummaries() {
    final failed = _channelSummaries;
    if (failed == null || failed.error.isEmpty) return false;
    _channelSummaries = null;
    unawaited(requestChannelSummaries());
    return true;
  }

  /// How each recorded temperature moves with lap time and strong
  /// acceleration over the shown group's eligible laps; null until the
  /// channel summaries are calculated.
  TemperatureAssociations? get temperatureAssociations {
    final channels = _channelSummaries;
    if (channels == null) return null;
    if (!identical(_associationsFor, channels) ||
        !identical(_associationsAnalysis, _analysis)) {
      _associationsFor = channels;
      _associationsAnalysis = _analysis;
      _associations = dayTemperatureAssociations(channels, [
        for (final row in dayEligibleLaps(_analysis)) row.reference,
      ]);
    }
    return _associations;
  }

  DayChannelSummaries? _associationsFor;
  DayAnalysis? _associationsAnalysis;
  TemperatureAssociations? _associations;

  /// The day report (Overlays' "Day report") of what has been calculated:
  /// nothing is calculated for it, and a result not calculated yet says so.
  Map<String, Object?> get dayReportDocument => dayReport(
    analysis: _analysis,
    eventId: eventId,
    runs: progressionRuns,
    decisionsKey: decisionsKey,
    theoretical: _theoreticalBestLoading ? null : _theoreticalBest,
    theoreticalLoading: _theoreticalBestLoading,
    theoreticalKey: _theoreticalKey,
    channels: _channelSummariesLoading ? null : _channelSummaries,
    channelsLoading: _channelSummariesLoading,
  );

  void _resetTheoreticalBest() {
    _theoreticalBest = null;
    _theoreticalBestLoading = false;
    _coach = null;
    _coachError = '';
    _coachLoading = false;
    _coachJob.cancel();
    ++_theoreticalBestGeneration;
  }

  // The runs of the document the day was last saved or opened as.
  List<Object?> get _savedRuns {
    final event = _document?['event'];
    return event is Map<String, Object?> && event['runs'] is List
        ? event['runs'] as List<Object?>
        : const <Object?>[];
  }

  // The document's runs with the unsaved segment edits.
  List<Object?> get _documentRuns => _segmentEdits.applyTo(_savedRuns);

  /// Whether an edit of the segments can be undone or redone.
  bool get canUndoSegmentEdit => _segmentEdits.canUndo;
  bool get canRedoSegmentEdit => _segmentEdits.canRedo;

  // Applies one segment edit: the day changes and the theoretical best,
  // losses and corner details are calculated again.
  String _segmentEdit(String Function(DayTheoreticalBest result) edit) {
    final result = _theoreticalBest;
    if (_saving) return 'The day is being saved.';
    if (result == null || _theoreticalBestLoading) {
      return 'The segments can be edited once the theoretical best is calculated.';
    }
    final error = edit(result);
    if (error.isEmpty) _segmentsChanged();
    return error;
  }

  void _segmentsChanged() {
    _revision++;
    _dirty = true;
    // The user's change ends the measurement of the last addition.
    _additionClock = null;
    _resetTheoreticalBest();
    _scheduleRecovery();
    notifyListeners();
  }

  /// Renames, retypes or moves approved segment [id]; with
  /// [keepAdjacentJoined] a neighbour sharing a moved boundary moves too.
  /// Returns why not, or an empty string.
  String editSegment(
    String id, {
    required String name,
    required String type,
    required double startMeters,
    required double endMeters,
    bool keepAdjacentJoined = true,
  }) => _segmentEdit(
    (result) => _segmentEdits.edit(
      result,
      id,
      name: name,
      type: type,
      startMeters: startMeters,
      endMeters: endMeters,
      keepAdjacentJoined: keepAdjacentJoined,
    ),
  );

  /// Splits segment [id] at [atMeters] on the shared axis.
  String splitSegment(String id, double atMeters) =>
      _segmentEdit((result) => _segmentEdits.split(result, id, atMeters));

  /// Merges segment [id] with [otherId], which shares a boundary with it.
  String mergeSegments(String id, String otherId) =>
      _segmentEdit((result) => _segmentEdits.merge(result, id, otherId));

  /// Removes segment [id]; the last one stays.
  String removeSegment(String id) =>
      _segmentEdit((result) => _segmentEdits.remove(result, id));

  /// Goes back to the best lap's automatic segments.
  String restoreAutomaticSegments() => _segmentEdit((result) {
    final saved = _savedRuns;
    return _segmentEdits.restoreAutomatic(saved, result.groupId)
        ? ''
        : 'The segments are already the automatic ones.';
  });

  SegmentChangeIssue? _segmentHistory({required bool undo}) {
    if (_saving) return SegmentChangeIssue.saving;
    final saved = _savedRuns;
    final timing = undo
        ? _segmentEdits.undoChangesSegments
        : _segmentEdits.redoChangesSegments;
    final issue = undo
        ? _segmentEdits.undoChange(saved)
        : _segmentEdits.redoChange(saved);
    if (issue == null && timing) {
      _segmentsChanged();
    } else if (issue == null) {
      _reviewDecisionChanged();
    } else {
      notifyListeners();
    }
    return issue;
  }

  // A review decision changed the day but not its segments, so nothing is
  // timed again.
  void _reviewDecisionChanged() {
    _revision++;
    _dirty = true;
    _additionClock = null;
    _scheduleRecovery();
    notifyListeners();
  }

  /// The proposals of the lap the day's segments are measured on, for the
  /// optional segment review (FET-56); null until [requestSegmentReview] has
  /// computed them for the current theoretical best.
  DayProposalReview? get segmentReview {
    final result = _theoreticalBest;
    final review = _segmentReview;
    return result == null || review == null || !review.matches(result)
        ? null
        : review;
  }

  bool get segmentReviewLoading => _segmentReviewLoading;

  /// Each proposal of [segmentReview] and its state against the segments
  /// approved now and the rejections stored with the day.
  List<SegmentReviewItem> get segmentReviewItems {
    final result = _theoreticalBest;
    final review = segmentReview;
    if (result == null || review == null || _theoreticalBestLoading) {
      return const [];
    }
    return review.items(result.runSegments, _storedReview(review.runId));
  }

  Object? _storedReview(String runId) {
    for (final value in _documentRuns) {
      if (value is Map<String, Object?> && value['id'] == runId) {
        return value['trackSegmentReview'];
      }
    }
    return null;
  }

  /// Computes the proposals of the lap the theoretical best's segments are
  /// measured on, in the background; with [recompute], again even when they
  /// are there (Overlays' "Recompute proposals"). A result for a lap that
  /// is no longer the one reviewed is dropped.
  Future<void> requestSegmentReview({bool recompute = false}) async {
    final result = _theoreticalBest;
    if (_disposed ||
        result == null ||
        _theoreticalBestLoading ||
        result.state != DayTheoreticalBestState.ready) {
      return;
    }
    if (!recompute && (_segmentReviewLoading || segmentReview != null)) return;
    // Once per theoretical best unless asked to recompute: a review that
    // does not match its result is never computed again and again.
    if (!recompute && identical(_segmentReviewFor, result)) return;
    _segmentReviewFor = result;
    final generation = ++_segmentReviewGeneration;
    _segmentReviewLoading = true;
    notifyListeners();
    final lap = segmentReviewLap(result);
    final run = lap == null ? null : outingRuns(_unitRuns)[lap.runId];
    DayProposalReview review;
    try {
      review = await _segmentReviewRunner(_segmentReviewJob(result, lap, run));
    } on Object catch (error) {
      review = DayProposalReview(
        groupId: result.groupId,
        runId: result.segmentRunId,
        lap: lap,
        message: '$error',
        failed: true,
      );
    }
    if (_disposed || generation != _segmentReviewGeneration) return;
    _segmentReview = review;
    _segmentReviewLoading = false;
    notifyListeners();
  }

  // Built outside the controller so the isolate's closure holds only its
  // inputs.
  static DayProposalReview Function() _segmentReviewJob(
    DayTheoreticalBest result,
    DayLapRow? lap,
    OutingRun? run,
  ) {
    // Only what the review needs crosses to the isolate.
    final shell = DayTheoreticalBest(
      groupId: result.groupId,
      state: result.state,
      segmentRunId: result.segmentRunId,
    );
    return () => dayProposalReview(shell, lap, run);
  }

  /// Computes the proposals again (Overlays' "Recompute proposals").
  Future<void> recomputeSegmentProposals() =>
      requestSegmentReview(recompute: true);

  /// Rejects proposal [index] of [segmentReview], or with [rejected] false
  /// takes the rejection back. The decision is saved with the day and
  /// undone like an edit; the segments do not change. Returns why not, or
  /// null.
  SegmentChangeIssue? rejectSegmentProposal(int index, {bool rejected = true}) {
    final result = _theoreticalBest;
    final review = segmentReview;
    if (_saving) return SegmentChangeIssue.saving;
    if (result == null || review == null || _theoreticalBestLoading) {
      return SegmentChangeIssue.notReady;
    }
    final issue = _segmentEdits.setRejected(
      result,
      review,
      _savedRuns,
      index,
      rejected: rejected,
    );
    if (issue == null) _reviewDecisionChanged();
    return issue;
  }

  /// Approves every open proposal of [segmentReview] (rejected ones stay
  /// out), as Overlays' "Approve all". Every lap is timed again. Returns
  /// how many were approved, or why none.
  ({int approved, SegmentChangeIssue? issue}) approveAllSegmentProposals() {
    final result = _theoreticalBest;
    final review = segmentReview;
    if (_saving) return (approved: 0, issue: SegmentChangeIssue.saving);
    if (result == null || review == null || _theoreticalBestLoading) {
      return (approved: 0, issue: SegmentChangeIssue.notReady);
    }
    final outcome = _segmentEdits.approveAll(result, review, _savedRuns);
    if (outcome.issue == null) _segmentsChanged();
    return outcome;
  }

  /// Undoes the last segment edit.
  String undoSegmentEdit() => undoSegmentChange()?.message ?? '';

  /// Redoes the last undone segment edit.
  String redoSegmentEdit() => redoSegmentChange()?.message ?? '';

  /// Undoes the last change of the segments or of a review decision, or
  /// says why not.
  SegmentChangeIssue? undoSegmentChange() => _segmentHistory(undo: true);

  /// Redoes the last undone change, or says why not.
  SegmentChangeIssue? redoSegmentChange() => _segmentHistory(undo: false);

  void _rerank() {
    _revision++;
    _dirty = true;
    // The user's change ends the measurement of the last addition.
    _additionClock = null;
    _resetTheoreticalBest();
    _analysis = rerankDay(
      _analysis,
      exclusions: _exclusions,
      preferredGroupId: _groupId,
    );
    _scheduleRecovery();
    notifyListeners();
  }

  /// Writes the unsaved day for recovery shortly, once changes settle.
  void _scheduleRecovery() {
    if (recovery == null || !dirty) return;
    _recoveryWrites.schedule(_writeRecovery);
  }

  void _writeRecovery() {
    final store = recovery;
    if (store == null || !dirty) return;
    // The document is built now, from the state the user sees.
    final runsNow = runs;
    final analysisNow = _analysis;
    final exclusionsNow = {..._exclusions};
    final segmentsNow = _segmentEdits.runs;
    final reviewsNow = _segmentEdits.reviews;
    final groupChosenNow = _groupDecided;
    final comparisonNow = _comparisonChoice;
    final fusionsNow = {..._fusions};
    final pendingNow = {..._pendingRecordings};
    final metadataNow = {..._metadataEdits};
    final weatherNow = weather.fetched;
    final previous = _document;
    final previousBase = _documentBase;
    final original = _documentPath ?? '';
    _recoveryWrites.enqueue(() async {
      final path = await store.path();
      if (path == null) return;
      final base = original.isEmpty ? path : original;
      await store.write(
        DayRecovery(
          document: dayDocument(
            eventId: eventId,
            name: _name,
            runs: runsNow,
            analysis: analysisNow,
            exclusions: exclusionsNow,
            projectPath: base,
            previous: previous,
            previousPath: previousBase,
            trackSegments: segmentsNow,
            trackSegmentReviews: reviewsNow,
            groupChosen: groupChosenNow,
            comparison: comparisonNow,
            fusions: fusionsNow,
            pendingAlternatives: pendingNow,
            runMetadata: metadataNow,
            weather: weatherNow,
          ),
          originalPath: original,
          basePath: base,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  /// Finishes recovery writes still waiting; for tests and app exit.
  Future<void> flushRecovery() => _recoveryWrites.flush(_writeRecovery);

  /// Disposes a day that was never shown without writing its recovery
  /// snapshot, so the snapshot it may have been restored from stays as it
  /// was.
  void discard() {
    _recoveryWrites.cancel();
    dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _coachJob.cancel();
    speedUnitSetting.removeListener(_speedUnitAssumed);
    weather.dispose();
    // Alignments not started are dropped; running ones are stopped.
    _fusionQueue.clear();
    for (final waiter in _slotWaiters) {
      waiter.completeError(const OperationCancelled());
    }
    _slotWaiters.clear();
    for (final task in _fusionTasks.values) {
      task.cancel();
    }
    _fusionTasks.clear();
    for (final task in _primaryTasks.values) {
      task.cancel();
    }
    _primaryTasks.clear();
    final settled = _fusionsSettled;
    _fusionsSettled = null;
    settled?.complete();
    _alignmentEnded();
    if (identical(declaredSpeedUnits, _declaredSpeedUnits)) {
      declareDaySpeedUnits(const []);
    }
    if (identical(dayChannelSources, _declaredChannelSources)) {
      dayChannelSources = const {};
    }
    if (identical(dayRecordedChannels, _declaredRecordedChannels)) {
      dayRecordedChannels = const [];
    }
    _appendJob?.cancel();
    _previewJob?.cancel();
    // Changes made just before leaving the day are still written; best
    // effort, as the app may end before the write finishes.
    unawaited(flushRecovery());
    super.dispose();
  }

  /// Why [row] is not ranked in the shown group; empty when it is ranked.
  List<LapIssue> issues(DayLapRow row) {
    final chosen = _analysis.chosenGroup;
    final configuration =
        _analysis.configurations[row.runId] ?? const TrackConfiguration();
    final issues = dayLapIssues(
      row,
      configuration,
      userExclusionReason: _exclusions[row.reference] ?? '',
    );
    if (chosen != null && configuration.compatibilityGroupId != chosen.id) {
      for (final issue in lapCompatibilityIssues(
        configuration,
        reference: chosen.configuration,
      )) {
        if (!issues.contains(issue)) issues.insert(0, issue);
      }
    }
    return issues;
  }

  /// Whether [row] is the best lap of the day in the shown group.
  bool isBestOfDay(DayLapRow row) =>
      ranking?.bestOfDay?.reference == row.reference;

  /// Whether [row] is its run's best lap in the shown group.
  bool isBestOfRun(DayLapRow row) =>
      ranking?.runs.any((run) => run.bestLap?.reference == row.reference) ??
      false;
}

/// The Corner Analyzer of a comparison, with how its segments were chosen.
final class DayCornerAnalyzer {
  const DayCornerAnalyzer({
    required this.analyzer,
    this.note = '',
    this.theoreticalBestAvailable = false,
  });

  final CornerAnalyzer analyzer;

  /// Why the segments are another run's or the theoretical best's; empty
  /// when they are both laps' own.
  final String note;

  /// The laps share no segments, but the theoretical best's would apply.
  final bool theoreticalBestAvailable;
}

/// Recordings read for the review of adding them to a day (FET-58); see
/// [DayResultsController.reviewAddition].
final class DayAdditionReview {
  const DayAdditionReview._({
    required TelemetryImportPlan this.plan,
    required this.automatic,
    required this.automaticNewDay,
    required this.sessions,
    required this.alreadyGrouped,
    required this.alreadyInDay,
    required this.runCount,
  }) : error = '',
       notes = const [];

  const DayAdditionReview._failed(this.error, this.notes)
    : plan = null,
      automatic = const {},
      automaticNewDay = const {},
      sessions = const [],
      alreadyGrouped = const {},
      alreadyInDay = const {},
      runCount = 0;

  /// The recordings read; null when none could be ([error]).
  final TelemetryImportPlan? plan;

  /// What happens to each recording when added without review.
  final ImportChoices automatic;

  /// What happens to each recording when it starts a new day instead.
  final ImportChoices automaticNewDay;

  /// The day's sessions a recording may be made the same run as.
  final List<ReviewSession> sessions;

  /// Those of [sessions] that have another recording already.
  final Set<String> alreadyGrouped;

  /// The recordings the day has already, by run id.
  final Set<String> alreadyInDay;

  /// The day's sessions when the review was prepared.
  final int runCount;

  /// Why nothing can be reviewed; empty otherwise.
  final String error;
  final List<String> notes;
}

/// What adding recordings to a day did.
final class DayAddition {
  const DayAddition({
    this.added = const [],
    this.combined = const [],
    this.notCombined = const [],
    required this.notes,
    this.error = '',
    this.savedTo,
    this.saveError = '',
    this.otherDay = false,
    this.closed = false,
    this.reviewChanged = false,
    this.choicesRefused = false,
  });

  /// Nothing was added: the choices it was asked with are ones the review
  /// does not accept ([checkImportChoices]), such as every file skipped
  /// (FET-58).
  final bool choicesRefused;

  /// Nothing was added: the day or the recordings changed after the review
  /// they were added with (FET-58).
  final bool reviewChanged;

  /// Nothing was added: the recordings are from another day than this one
  /// (asked with `sameDayOnly`).
  final bool otherDay;

  /// Nothing was added because the day was closed first.
  final bool closed;

  /// The new sessions' names, "Session 4".
  final List<String> added;

  /// The day's sessions that got the RCZ added as their alternative
  /// recording.
  final List<String> combined;

  /// The day's sessions whose added RCZ could not be combined after all
  /// (aligning it failed). It stays saved with them.
  final List<String> notCombined;

  /// This addition, with [sessions] not combined after all.
  DayAddition _notCombined(List<String> sessions) => DayAddition(
    added: added,
    combined: [
      for (final name in combined)
        if (!sessions.contains(name)) name,
    ],
    notCombined: sessions,
    notes: notes,
    error: error,
    savedTo: savedTo,
    saveError: saveError,
    otherDay: otherDay,
    closed: closed,
    reviewChanged: reviewChanged,
    choicesRefused: choicesRefused,
  );

  /// What was skipped, already in the day or failed.
  final List<String> notes;

  /// Why nothing was added; empty otherwise.
  final String error;

  /// Where the day was saved again with the new sessions; null when it has
  /// not been saved yet, or the save failed ([saveError]).
  final String? savedTo;
  final String saveError;
}

/// Whether [result] offers "Calculate again": as in Overlays, only when
/// it is unavailable or the calculation failed.
bool offersCalculateAgain(DayTheoreticalBest result) => switch (result.state) {
  DayTheoreticalBestState.unavailable || DayTheoreticalBestState.error => true,
  DayTheoreticalBestState.ready => false,
};
