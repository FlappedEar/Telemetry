import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'recovery_store.dart';

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
  }) : runs = List.unmodifiable(runs),
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
       _writer = writer ?? saveDayDocument,
       _dirty = recovered {
    _scheduleRecovery();
  }

  /// A day opened from its document.
  DayResultsController.opened(
    OpenedDay day, {
    DocumentWriter? writer,
    RecoveryStore? recovery,
  }) : this(
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
       );

  /// An unsaved day restored from [recovery]'s snapshot: it has changes
  /// until saved, and saving it again goes where it was last saved.
  DayResultsController.recovered(
    OpenedDay day,
    DayRecovery snapshot, {
    DocumentWriter? writer,
    RecoveryStore? recovery,
  }) : this(
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
         recovered: true,
       );

  final List<NamedRun> runs;
  DayAnalysis _analysis;
  String? _groupId;
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

  /// Keeps the day while it has unsaved changes; none when null.
  final RecoveryStore? recovery;
  Timer? _recoveryTimer;

  /// The user's unsaved corrections to the segments.
  final DaySegmentEdits _segmentEdits = DaySegmentEdits();

  final TheoreticalBestRunner _theoreticalBestRunner;
  DayTheoreticalBest? _theoreticalBest;
  bool _theoreticalBestLoading = false;
  int _theoreticalBestGeneration = 0;
  bool _disposed = false;

  // The last recovery write or clear queued (see [queueRecovery]).
  Future<void> _recoveryWork = Future.value();

  /// How long changes wait before the unsaved day is written for recovery.
  static const recoveryDelay = Duration(milliseconds: 500);

  String get name => _name;

  /// Where the day was last saved or opened from; null for a new day.
  String? get documentPath => _documentPath;

  /// Whether there are changes since the day was saved or opened.
  bool get dirty => _dirty || _documentPath == null;
  bool get saving => _saving;

  /// Saves the day to [path]: the event, its runs and recordings, the
  /// layouts set by the user and the excluded laps. Throws
  /// [FetprojectError] when the document cannot be written; the previous
  /// file is then left as it was.
  Future<void> save(String path) async {
    if (_saving) throw const FetprojectError('A save is already running.');
    _saving = true;
    notifyListeners();
    try {
      final document = dayDocument(
        eventId: eventId,
        name: _name,
        runs: runs,
        analysis: _analysis,
        exclusions: _exclusions,
        projectPath: path,
        previous: _document,
        previousPath: _documentBase,
        trackSegments: _segmentEdits.runs,
      );
      await _writer(path, document);
      _document = document;
      _documentPath = path;
      _documentBase = path;
      _dirty = false;
      _segmentEdits.clear();
      // Automatic segments were approved by the save with their own ids:
      // edits start from the saved ones.
      if (_theoreticalBest?.automaticSegments ?? false) _resetTheoreticalBest();
      _recoveryTimer?.cancel();
      _enqueueRecovery(() => recovery?.clear());
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  DayAnalysis get analysis => _analysis;
  DayRanking? get ranking => _analysis.ranking;
  Map<DayLapReference, String> get exclusions => Map.unmodifiable(_exclusions);

  /// The recording of [runId].
  TelemetrySession? session(String runId) {
    for (final named in runs) {
      if (named.run.id == runId) return named.run.telemetry;
    }
    return null;
  }

  /// Shows [groupId]'s ranking first.
  void chooseGroup(String groupId) {
    if (groupId == _analysis.chosenGroupId) return;
    _groupId = groupId;
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
    _rerank();
  }

  /// The shown group's theoretical best, sector times and loss map; null
  /// until [requestTheoreticalBest] has finished for the current laps.
  DayTheoreticalBest? get theoreticalBest => _theoreticalBest;
  bool get theoreticalBestLoading => _theoreticalBestLoading;

  // Built outside the controller so the isolate's closure holds only its
  // inputs.
  static DayTheoreticalBest Function() _theoreticalBestJob(
    DayAnalysis analysis,
    Map<String, OutingRun> runs,
    List<Object?> documentRuns,
  ) =>
      () => dayTheoreticalBest(analysis, runs, documentRuns: documentRuns);

  /// Times every eligible lap of the shown group against its approved
  /// segments (proposed from the best lap when the day has none yet), in the
  /// background. A result for laps that changed meanwhile is dropped.
  Future<void> requestTheoreticalBest() async {
    if (_theoreticalBest != null || _theoreticalBestLoading) return;
    final generation = ++_theoreticalBestGeneration;
    _theoreticalBestLoading = true;
    notifyListeners();
    final documentRuns = _documentRuns;
    DayTheoreticalBest result;
    try {
      result = await _theoreticalBestRunner(
        _theoreticalBestJob(_analysis, outingRuns(runs), documentRuns),
      );
    } on Exception catch (error) {
      result = DayTheoreticalBest(
        groupId: _analysis.chosenGroupId ?? '',
        state: DayTheoreticalBestState.error,
        message: '$error',
      );
    }
    if (_disposed || generation != _theoreticalBestGeneration) return;
    _theoreticalBest = result;
    _theoreticalBestLoading = false;
    notifyListeners();
  }

  void _resetTheoreticalBest() {
    _theoreticalBest = null;
    _theoreticalBestLoading = false;
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
    _dirty = true;
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

  String _segmentHistory({required bool undo}) {
    if (_saving) return 'The day is being saved.';
    final saved = _savedRuns;
    final error = undo ? _segmentEdits.undo(saved) : _segmentEdits.redo(saved);
    if (error.isEmpty) {
      _segmentsChanged();
    } else {
      notifyListeners();
    }
    return error;
  }

  /// Undoes the last segment edit.
  String undoSegmentEdit() => _segmentHistory(undo: true);

  /// Redoes the last undone segment edit.
  String redoSegmentEdit() => _segmentHistory(undo: false);

  void _rerank() {
    _dirty = true;
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
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(recoveryDelay, _writeRecovery);
  }

  void _enqueueRecovery(Future<void>? Function() operation) {
    _recoveryWork = queueRecovery(() async {
      try {
        await operation();
      } on Exception catch (error) {
        debugPrint('Recovery snapshot not updated: $error');
      }
    });
  }

  void _writeRecovery() {
    final store = recovery;
    if (store == null || !dirty) return;
    // The document is built now, from the state the user sees.
    final runsNow = runs;
    final analysisNow = _analysis;
    final exclusionsNow = {..._exclusions};
    final segmentsNow = _segmentEdits.runs;
    final previous = _document;
    final previousBase = _documentBase;
    final original = _documentPath ?? '';
    _enqueueRecovery(() async {
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
          ),
          originalPath: original,
          basePath: base,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  /// Finishes recovery writes still waiting; for tests and app exit.
  Future<void> flushRecovery() {
    if (_recoveryTimer?.isActive ?? false) {
      _recoveryTimer!.cancel();
      _writeRecovery();
    }
    return _recoveryWork;
  }

  @override
  void dispose() {
    _disposed = true;
    // Changes made just before leaving the day are still kept.
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
