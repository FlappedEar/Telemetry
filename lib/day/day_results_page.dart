import 'dart:async';
import 'dart:math' as math;
import 'dart:isolate';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import '../diagnostics/diagnostics_page.dart';
import '../format.dart';
import '../import/day_import_page.dart'
    show PlatformRecordingPickers, RecordingPickers, isDesktopPlatform;
import '../import/import_review_page.dart';
import '../l10n.dart';
import '../profile/profile_library.dart';
import '../settings_dialog.dart';
import '../units.dart' show hideUnrankedLapsSetting;
import 'background_task.dart';
import 'channel_cards.dart';
import 'comparison_page.dart';
import 'consistency_card.dart';
import 'corner_details.dart' show lapAColor, lapBColor;
import 'day_results_controller.dart';
import 'day_report_page.dart';
import 'document_pickers.dart';
import 'focus_areas_card.dart';
import 'fusion_panel.dart';
import 'next_session_card.dart';
import 'lap_page.dart';
import 'progression_card.dart';
import 'recovery_store.dart';
import 'reveal.dart';
import 'segment_editor_page.dart';
import 'session_details_dialog.dart';
import 'theoretical_best_card.dart';
import 'time_losses_card.dart';
import '../ui/readable_list.dart';
import '../ui/headline_bar.dart';
import '../ui/theme.dart';
import 'track_dialog.dart';
import 'track_map.dart';
import 'weather_text.dart';

/// The day at a glance, led by the best lap: "Best lap of the day · 1:49.898 ·
/// Session 5 · LAP 2", the group compared, each session's best, and every
/// lap section in recording order.
class DayResultsPage extends StatefulWidget {
  /// A day just imported.
  DayResultsPage({
    super.key,
    required List<NamedRun> runs,
    required DayAnalysis analysis,
    this.documents = const PlatformDocumentPickers(),
    this.pickers = const PlatformRecordingPickers(),
    this.recovery,
    this.library,
  }) : replace = null,
       startNewDay = null,
       _create = (() => DayResultsController(
         runs: runs,
         analysis: analysis,
         recovery: recovery,
       ));

  /// A day opened from its document.
  DayResultsPage.opened({
    super.key,
    required OpenedDay day,
    this.documents = const PlatformDocumentPickers(),
    this.pickers = const PlatformRecordingPickers(),
    this.recovery,
    this.library,
  }) : replace = null,
       startNewDay = null,
       _create = (() => DayResultsController.opened(day, recovery: recovery));

  /// A day held by [controller], which the page then owns. With [replace],
  /// a day opened again with its recordings found elsewhere goes to
  /// [replace] as this page closes, for the caller to show; otherwise this
  /// page is replaced by one of that day.
  DayResultsPage.controller({
    super.key,
    required DayResultsController controller,
    this.documents = const PlatformDocumentPickers(),
    this.pickers = const PlatformRecordingPickers(),
    this.recovery,
    this.replace,
    this.startNewDay,
    this.library,
  }) : _create = (() => controller);

  final DayResultsController Function() _create;
  final DocumentPickers documents;

  /// Chooses recordings to add to the day.
  final RecordingPickers pickers;

  /// Keeps the day while it has unsaved changes; none when null.
  final RecoveryStore? recovery;

  /// The driver profile the day is saved in, by itself and without a save
  /// dialog; when null, days are saved where [documents] says.
  final ProfileLibrary? library;

  /// Takes the day opened again in place of this one; see
  /// [DayResultsPage.controller].
  final ValueChanged<DayResultsController>? replace;

  /// Starts importing recordings reviewed while this day was shown as a new
  /// day instead (FET-58): "Start a new day" in the review. Returns whether
  /// it started; only then does this page close. Not offered when null.
  final bool Function(List<String> paths, ImportChoices choices)? startNewDay;

  @override
  State<DayResultsPage> createState() => _DayResultsPageState();
}

class _DayResultsPageState extends State<DayResultsPage> {
  late final DayResultsController _controller = widget._create();
  bool _relinking = false;

  // The section shown: on a phone the bottom bar's Day, Laps or Compare; on a
  // wide screen the rail's Day (summary and laps side by side) or Compare.
  _Section _section = _Section.day;
  // Reading the recordings again ("Retry recordings"): the running task and
  // its generation, so a result after the page moved on is dropped.
  BackgroundTask<OpenedDay>? _retryTask;
  int _retryGeneration = 0;

  // The best lap's trace, recomputed only when the best lap changes.
  DayLapReference? _mapReference;
  LapPath? _mapPath;
  (Offset, Offset)? _mapGate;

  DayAddition? _reported;

  // Writes waiting changes for recovery when the app goes to the background
  // or is closed, where the operating system may end it without warning.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        unawaited(_controller.flushRecovery());
      }
    },
    // On desktop, quitting waits briefly for the write.
    onExitRequested: () async {
      await Future.wait([
        _controller.flushRecovery(),
        if (widget.library case final library?) library.flush(),
      ]).timeout(const Duration(seconds: 2), onTimeout: () => const []);
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportAddition);
    _controller.addListener(_libraryChanged);
    _startLibrary();
    // An addition made before the page opened, such as a shared recording
    // added to today's day, is reported once the page is shown.
    if (_controller.lastAddition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportAddition());
    }
    _lifecycle;
  }

  @override
  void dispose() {
    ++_retryGeneration;
    _retryTask?.cancel();
    _controller.removeListener(_reportAddition);
    _controller.removeListener(_libraryChanged);
    _autosave?.cancel();
    _lifecycle.dispose();
    _summaryScroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Says what the last addition of recordings did, from this page or a
  /// recording shared to the app while the day is open.
  void _reportAddition() {
    final addition = _controller.lastAddition;
    if (addition == null || identical(addition, _reported) || !mounted) return;
    _reported = addition;
    final l10n = context.l10n;
    final added = addition.added;
    final lines = [
      if (addition.reviewChanged)
        l10n.reviewChanged
      else if (addition.choicesRefused)
        l10n.reviewChoicesRefused
      else if (addition.error.isNotEmpty)
        l10n.additionError(addition.error)
      else if (added.isEmpty &&
          addition.combined.isEmpty &&
          addition.notCombined.isEmpty)
        l10n.nothingAdded
      else ...[
        if (added.isNotEmpty)
          l10n.addedToDay(added.map(l10n.session).join(', ')),
        if (addition.combined.isNotEmpty)
          l10n.fusionCombinedWith(
            RecordingFormat.rcz.name.toUpperCase(),
            addition.combined.map(l10n.session).join(', '),
          ),
        if (addition.notCombined.isNotEmpty)
          l10n.fusionAddedNotCombined(
            RecordingFormat.rcz.name.toUpperCase(),
            addition.notCombined.map(l10n.session).join(', '),
          ),
      ],
      if (addition.savedTo != null) l10n.savedAs(p.basename(addition.savedTo!)),
      if (addition.saveError.isNotEmpty) l10n.notSaved(addition.saveError),
      ...addition.notes.map(l10n.coreText),
    ];
    _tell(lines.join('\n'));
    if (added.isNotEmpty) _revealCoach();
  }

  final _coachKey = GlobalKey();

  /// The summary's scroll position, in a phone's Day section or the wide
  /// layout's left pane.
  final _summaryScroll = ScrollController();

  /// The day opens on what to do in the next session: the Day section,
  /// scrolled to the Next session card. Scrolled far below it, the card is
  /// not built, so the summary first goes back to the top, near the card.
  void _revealCoach() {
    if (_section != _Section.day) setState(() => _section = _Section.day);
    void reveal({required bool again}) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final card = _coachKey.currentContext;
        if (card != null) {
          revealSettled(card, current: () => _coachKey.currentContext);
        } else if (again && _summaryScroll.hasClients) {
          _summaryScroll.jumpTo(0);
          reveal(again: false);
        }
      });
    }

    reveal(again: true);
  }

  Future<void> _addRecordings() async {
    final paths = await widget.pickers.pickRecordings();
    if (paths.isEmpty || !mounted) return;
    // A session's clock check or primary change finishes first.
    if (_controller.recordingsBusy) {
      _tell(context.l10n.recordingsBusyAdd);
      return;
    }
    await _controller.addRecordings(paths);
  }

  // Reading recordings for the review of an addition.
  bool _preparingReview = false;

  /// Chooses recordings and opens their review (FET-58) before anything is
  /// added: each one a new session, skipped or the same run as another
  /// recording or session, added to this day or, with no unsaved changes,
  /// as a new day.
  Future<void> _addAndReview() async {
    final paths = await widget.pickers.pickRecordings();
    if (paths.isEmpty || !mounted) return;
    setState(() => _preparingReview = true);
    final DayAdditionReview? review;
    try {
      review = await _controller.reviewAddition(paths);
    } finally {
      if (mounted) setState(() => _preparingReview = false);
    }
    final plan = review?.plan;
    if (review == null || !mounted) return;
    if (plan == null) {
      _tell(
        [
          context.l10n.additionError(review.error),
          ...review.notes.map(context.l10n.coreText),
        ].join('\n'),
      );
      return;
    }
    final result = await showImportReview(
      context,
      plan: plan,
      automatic: review.automatic,
      adding: true,
      sessions: review.sessions,
      alreadyGrouped: review.alreadyGrouped,
      alreadyInDay: review.alreadyInDay,
      automaticNewDay: widget.startNewDay == null
          ? null
          : review.automaticNewDay,
      newDayBlocked: _controller.dirty || _controller.adding,
    );
    if (result == null || !mounted) return;
    final startNewDay = widget.startNewDay;
    if (result.newDay && startNewDay != null) {
      // Saved meanwhile is fine; changed meanwhile is not left behind.
      if (_controller.dirty || _controller.adding) {
        _tell(context.l10n.reviewNewDayNeedsSave);
        return;
      }
      // Started first, closed after: a refused start leaves the day open.
      if (startNewDay(paths, result.choices)) {
        Navigator.of(context).pop();
      } else {
        _tell(context.l10n.importBusy);
      }
      return;
    }
    await _controller.addRecordings(
      paths,
      review: review,
      choices: result.choices,
    );
  }

  void _open(DayLapRow row) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LapPage(controller: _controller, row: row),
    ),
  );

  // With [segmentId], from a result of the theoretical best: the Corner
  // Analyzer opens on that segment, measured against its segments.
  Future<void> _compare(
    DayLapRow a,
    DayLapRow b,
    (double, double)? focus, {
    String? segmentId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ComparisonPage(
        controller: _controller,
        a: a,
        b: b,
        focus: focus,
        segmentId: segmentId,
        fromTheoreticalBest: segmentId != null,
      ),
    ),
  );

  /// Asks for lap A, then lap B of its group, and compares them.
  Future<void> _pickComparison() async {
    final a = await pickComparisonLap(
      context,
      title: context.l10n.pickLapA,
      candidates: _controller.comparisonCandidates(),
    );
    if (a == null || !mounted) return;
    final b = await pickComparisonLap(
      context,
      title: context.l10n.pickLapB(context.l10n.lap(a)),
      candidates: [
        for (final row in _controller.comparisonCandidates(a))
          if (row.reference != a.reference) row,
      ],
      suggested: _controller.comparisonPartner(a),
    );
    if (b == null || !mounted) return;
    await _compare(a, b, null);
  }

  void _openReport() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => DayReportPage(
          report: _controller.dayReportDocument,
          onOpenLap: (reference) {
            final row = _controller.lapRow(reference);
            if (row != null) _open(row);
          },
        ),
      ),
    ),
  );

  LapPath? _bestPath(DayLapRow best) {
    if (_mapReference != best.reference) {
      _mapReference = best.reference;
      final session = _controller.session(best.runId);
      final origin = session == null ? null : mapOrigin(session);
      _mapPath = session == null
          ? null
          : lapPath(session, best.start, best.end, origin: origin);
      _mapGate = session == null || origin == null
          ? null
          : mapGate(session, origin);
    }
    return _mapPath;
  }

  int _recordedSaves = -1;

  /// Whether the library was read, so the day is kept in it.
  bool _libraryReady = false;
  Timer? _autosave;

  /// How long the day stays unchanged before a change is saved by itself.
  static const _autosaveDelay = Duration(seconds: 2);

  /// Keeps the day in the driver profile: a day shown from the profile has
  /// its summary brought up to date, a new day is saved in it at once, and
  /// every change after that is saved by itself, without asking (session
  /// preparation is automatic).
  Future<void> _startLibrary() async {
    final library = widget.library;
    if (library == null) return;
    await library.load();
    if (!mounted || !library.available) return;
    _libraryReady = true;
    _recordSave(force: true);
    if (_controller.documentPath == null && !_controller.saving) {
      await _save();
    } else {
      _scheduleAutosave();
    }
  }

  void _libraryChanged() {
    _recordSave();
    _scheduleAutosave();
  }

  /// Saves a day kept in the library once it stayed unchanged for
  /// [_autosaveDelay].
  void _scheduleAutosave() {
    if (!_libraryReady || !_inLibrary || !_autosaveAllowed) return;
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      if (mounted && _autosaveAllowed) unawaited(_save(quiet: true));
    });
  }

  /// Whether going back first saves the day's changes in the library,
  /// after the save running, if any.
  bool get _saveBeforeLeaving =>
      _libraryReady &&
      _inLibrary &&
      _controller.dirty &&
      !_controller.adding &&
      !_controller.recordingsBusy &&
      !_controller.savingWaitsForRecordings &&
      !_relinking &&
      !_preparingReview;

  bool _leaving = false;

  /// Saves the day in the library, then leaves it, saved or not: changes
  /// not saved are kept for recovery, as on any day left unsaved. Stays
  /// when a page was opened over the day meanwhile.
  Future<void> _saveThenLeave() async {
    if (_leaving) return;
    _leaving = true;
    _autosave?.cancel();
    final route = ModalRoute.of(context);
    try {
      await _save(quiet: true);
    } finally {
      _leaving = false;
      // Not while work begun meanwhile holds the day open (see canPop).
      if (mounted &&
          (route?.isCurrent ?? false) &&
          !_controller.adding &&
          !_controller.recordingsBusy &&
          !_controller.savingWaitsForRecordings &&
          !_relinking &&
          !_preparingReview) {
        Navigator.of(context).pop();
      }
    }
  }

  bool get _autosaveAllowed =>
      _controller.dirty &&
      !_controller.saving &&
      !_controller.adding &&
      !_relinking &&
      !_preparingReview;

  /// After each save into the profile, the profile records the day.
  void _recordSave({bool force = false}) =>
      _record(widget.library, _controller, force: force);

  /// Records [controller]'s day in [library] after a save; called with
  /// what the page held, so a save finishing after the page was left is
  /// recorded too.
  void _record(
    ProfileLibrary? library,
    DayResultsController controller, {
    bool force = false,
  }) {
    final path = controller.documentPath;
    if (library == null || path == null || !library.holds(path)) return;
    if (!force && controller.saveCount == _recordedSaves) return;
    _recordedSaves = controller.saveCount;
    unawaited(
      library.recordDay(
        eventId: controller.eventId,
        path: path,
        name: controller.name,
        analysis: controller.analysis,
      ),
    );
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Whether the day is saved in the driver profile, or will be.
  bool get _inLibrary {
    final library = widget.library;
    if (library == null || !library.available) return false;
    final path = _controller.documentPath;
    return path == null || library.holds(path);
  }

  /// Saves the day; with [quiet] (a save by itself) only a failure is said.
  Future<void> _save({bool choose = false, bool quiet = false}) async {
    if (choose && _inLibrary) return _export();
    final library = widget.library;
    final controller = _controller;
    try {
      final path = choose || controller.documentPath == null
          ? _inLibrary
                ? await library!.dayPath(controller.eventId)
                : await widget.documents.saveLocation(controller.name)
          : controller.documentPath;
      if (path == null || !mounted) return;
      // A day saved as a file never replaces one of the library's days.
      if (!_inLibrary && (library?.holds(path) ?? false)) {
        _tell(context.l10n.notSavedInLibrary);
        return;
      }
      await controller.save(path);
      _record(library, controller);
      if (mounted && !quiet) {
        _tell(
          library != null && library.holds(path)
              ? (_controller.dirty
                    ? context.l10n.savedToLibraryChangesPending
                    : context.l10n.savedToLibrary)
              : _controller.dirty
              ? context.l10n.savedAsChangesPending(p.basename(path))
              : context.l10n.savedAs(p.basename(path)),
        );
      }
    } on Exception catch (error) {
      if (mounted) _tell(context.l10n.notSaved('$error'));
    }
  }

  /// Writes a copy of the day for FlappedEar Overlays where the user
  /// chooses; the day stays in the profile.
  Future<void> _export() async {
    final path = await widget.documents.saveLocation(_controller.name);
    if (path == null || !mounted) return;
    // The library's own files are never replaced by an export.
    if (widget.library?.holds(path) ?? false) {
      _tell(context.l10n.exportNotInLibrary);
      return;
    }
    try {
      await _controller.exportCopy(path);
      if (mounted) _tell(context.l10n.exportedAs(p.basename(path)));
    } on Exception catch (error) {
      if (mounted) _tell(context.l10n.notExported('$error'));
    }
  }

  // Built outside the state so the isolate's closure holds only its inputs.
  static RelinkedDay Function() _relinkJob(
    String path,
    String folder,
    List<MissingRecording> missing,
    List<MissingRecording> alternatives,
  ) =>
      () => relinkDay(path, folder, missing, missingAlternatives: alternatives);

  /// Looks for the missing recordings in a folder the user picks, by their
  /// content as Overlays relinks them (a file only named like one is not
  /// used), and opens the day again with the ones found. Sessions' RCZs that
  /// could not be used are looked for too (one of the same name is used
  /// when it is the same drive). The day then has changes: saving writes
  /// where the recordings are now.
  Future<void> _findRecordings() async {
    final path = _controller.documentPath;
    if (path == null) return;
    if (_controller.adding) {
      _tell(context.l10n.waitThenFindRecordings);
      return;
    }
    if (_controller.recordingsBusy) {
      _tell(context.l10n.recordingsBusyFind);
      return;
    }
    if (_controller.dirty) {
      _tell(context.l10n.saveThenFindRecordings);
      return;
    }
    final folder = await widget.documents.pickFolder();
    if (folder == null || !mounted) return;
    setState(() => _relinking = true);
    try {
      final missing = _controller.missing;
      final alternatives = _controller.missingAlternatives;
      final sessions = _controller.runs.length;
      final (:day, :search, :differentAlternatives) = await Isolate.run(
        _relinkJob(path, folder, missing, alternatives),
      );
      if (!mounted) return;
      // The day is opened again from its saved document: a recording added
      // meanwhile, such as a shared one, would not be in it.
      if (_controller.adding ||
          _controller.dirty ||
          _controller.runs.length != sessions) {
        _tell(context.l10n.recordingsAddedMeanwhile);
        return;
      }
      // A session's recordings being checked or changed would be dropped.
      if (_controller.recordingsBusy) {
        _tell(context.l10n.recordingsBusyFind);
        return;
      }
      // An RCZ found only by its name that is not the same drive: said, not
      // used.
      final differentRcz = [
        for (final file in differentAlternatives.values) p.basename(file),
      ];
      final rczMessage = differentRcz.isEmpty
          ? null
          : context.l10n.fusionRelinkDifferent(differentRcz.join(', '));
      final used = {
        for (final runId in search.alternatives.keys)
          if (!differentAlternatives.containsKey(runId)) runId,
      };
      if (day.missing.length == missing.length && used.isEmpty) {
        final names = [
          for (final recording in missing)
            if (search.different.containsKey(recording.runId))
              p.basename(search.different[recording.runId]!),
        ];
        final l10n = context.l10n;
        _tell(
          [
            if (names.isNotEmpty)
              l10n.relinkDifferentRecordings(names.length, names.join(', ')),
            ?rczMessage,
            if (names.isEmpty && rczMessage == null) l10n.relinkNothingFound,
          ].join('\n'),
        );
        return;
      }
      if (rczMessage != null) _tell(rczMessage);
      if (day.analysis == null) return;
      final replace = widget.replace;
      if (replace != null) {
        replace(
          DayResultsController.opened(
            day,
            recovery: widget.recovery,
            appender: _controller.appender,
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DayResultsPage.opened(
            day: day,
            documents: widget.documents,
            recovery: widget.recovery,
            library: widget.library,
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) _tell(context.l10n.dayReopenFailed('$error'));
    } finally {
      if (mounted) setState(() => _relinking = false);
    }
  }

  /// Opens the day again from its saved document with the recordings where
  /// it says they are, as Overlays' "Retry recordings" reads them again: a
  /// drive that was not connected, say. Recordings found are checked by
  /// their content like any opened day's; the day is shown again when more
  /// of them open, or to line up its RCZs again. Cancelled when the page
  /// closes.
  Future<void> _retryRecordings() async {
    final path = _controller.documentPath;
    if (path == null) return;
    final l10n = context.l10n;
    if (_controller.adding) {
      _tell(l10n.retryRecordingsWaitAdding);
      return;
    }
    if (_controller.recordingsBusy) {
      _tell(l10n.recordingsBusyRetry);
      return;
    }
    if (_controller.dirty) {
      _tell(l10n.retryRecordingsSaveFirst);
      return;
    }
    final generation = ++_retryGeneration;
    final missing = _controller.missing.length;
    final sessions = _controller.runs.length;
    final shown = {for (final named in _controller.runs) named.run.id};
    final alternatives = _controller.missingAlternatives
        .where((recording) => shown.contains(recording.runId))
        .length;
    setState(() => _relinking = true);
    final task = _retryTask = runInBackground(reopenDay, path);
    try {
      final day = await task.result;
      if (!mounted || generation != _retryGeneration) return;
      if (_controller.adding || _controller.runs.length != sessions) {
        _tell(l10n.retryRecordingsAddedMeanwhile);
        return;
      }
      if (_controller.dirty) {
        _tell(l10n.retryRecordingsChangedMeanwhile);
        return;
      }
      // A session's recordings being checked or changed would be dropped.
      if (_controller.recordingsBusy) {
        _tell(l10n.recordingsBusyRetry);
        return;
      }
      if (day.missing.length >= missing && alternatives == 0) {
        _tell(l10n.retryRecordingsStill);
        return;
      }
      if (day.analysis == null) {
        _tell(l10n.retryRecordingsNone);
        return;
      }
      final replace = widget.replace;
      if (replace != null) {
        replace(
          DayResultsController.opened(
            day,
            recovery: widget.recovery,
            appender: _controller.appender,
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DayResultsPage.opened(
            day: day,
            documents: widget.documents,
            recovery: widget.recovery,
            library: widget.library,
          ),
        ),
      );
    } on OperationCancelled {
      return;
    } on BackgroundTaskFailed catch (error) {
      if (mounted && generation == _retryGeneration) {
        _tell(l10n.retryRecordingsFailed(l10n.taskFailure(error.message)));
      }
    } finally {
      if (identical(_retryTask, task)) _retryTask = null;
      if (mounted && generation == _retryGeneration) {
        setState(() => _relinking = false);
      }
    }
  }

  /// Two panes and a side rail from this width; below it the summary, the
  /// laps and Compare are sections of a bottom bar.
  static const _twoPaneWidth = 900.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _page(context, constraints.maxWidth),
  );

  Widget _body(BuildContext context, bool wide, double mapHeight) {
    final summary = _summary(context, wide, mapHeight);
    final laps = _lapList(context);
    final compare = _comparePane(context);
    if (!wide) {
      // Every section stays built, so each keeps its scroll position.
      return IndexedStack(
        index: _section.index,
        children: [
          ListView(
            key: const ValueKey('dayResultsSummary'),
            controller: _summaryScroll,
            padding: const EdgeInsets.all(16),
            // The headline bars and the best lap's map push the Next session
            // card down; build it from the top so it can be revealed.
            scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
            children: summary,
          ),
          ListView(
            key: const ValueKey('dayResultsLaps'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: laps,
          ),
          ListView(
            key: const ValueKey('dayResultsCompare'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: compare,
          ),
        ],
      );
    }
    final comparing = _section == _Section.compare;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab moves through one pane at a time, not across the three by
        // position.
        FocusTraversalGroup(
          child: NavigationRail(
            key: const ValueKey('daySections'),
            selectedIndex: comparing ? 1 : 0,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (index) => setState(
              () => _section = index == 1 ? _Section.compare : _Section.day,
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.flag_outlined),
                selectedIcon: const Icon(Icons.flag),
                label: Text(context.l10n.daySectionDay),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.compare_arrows),
                label: Text(context.l10n.daySectionCompare),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        if (comparing)
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  key: const ValueKey('dayResultsCompare'),
                  padding: const EdgeInsets.all(16),
                  children: compare,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FocusTraversalGroup(
                      child: ListView(
                        key: const ValueKey('dayResultsSummary'),
                        controller: _summaryScroll,
                        // At most 840 wide, centred in what the laps leave.
                        padding: readablePadding(
                          constraints.maxWidth -
                              math.min(constraints.maxWidth * 4 / 9, 520),
                        ),
                        // As on a phone: the Next session card is built from
                        // the top.
                        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                        children: summary,
                      ),
                    ),
                  ),
                  // Four ninths of the width, at most 520: on a large screen
                  // a lap's time stays near its name.
                  SizedBox(
                    width: math.min(constraints.maxWidth * 4 / 9, 520),
                    child: FocusTraversalGroup(
                      child: ListView(
                        key: const ValueKey('dayResultsLaps'),
                        padding: const EdgeInsets.all(16),
                        children: laps,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _page(BuildContext context, double width) {
    final wide = width >= _twoPaneWidth;
    // The trace keeps a similar shape from a small phone to a tablet in
    // portrait: about 0.6 of the card's width.
    final mapHeight = wide ? 360.0 : ((width - 64) * 0.6).clamp(200.0, 420.0);
    // On a phone Settings moves into the menu, so the day's name has room.
    final compact = width < 600;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Text(
            _controller.documentPath == null
                ? context.l10n.dayResultsTitle
                : '${_controller.name}${_controller.dirty ? ' •' : ''}',
          ),
        ),
        actions: [
          if (!compact) const SettingsButton(),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => IconButton(
              tooltip: context.l10n.save,
              icon: const Icon(Icons.save_outlined),
              onPressed: _controller.saving || !_controller.dirty
                  ? null
                  : () => _save(),
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => IconButton(
              key: const ValueKey('addRecordings'),
              tooltip: context.l10n.addRecordings,
              icon: const Icon(Icons.playlist_add),
              onPressed:
                  _controller.adding ||
                      _controller.saving ||
                      _relinking ||
                      _preparingReview ||
                      _controller.recordingsBusy
                  ? null
                  : _addRecordings,
            ),
          ),
          IconButton(
            key: const ValueKey('openDayReport'),
            tooltip: context.l10n.dayReport,
            icon: const Icon(Icons.summarize_outlined),
            onPressed: _openReport,
          ),
          PopupMenuButton<void>(
            key: const ValueKey('moreMenu'),
            tooltip: context.l10n.moreActions,
            itemBuilder: (context) => [
              if (compact)
                PopupMenuItem(
                  key: const ValueKey('settingsMenuItem'),
                  height: kMinInteractiveDimension,
                  onTap: () => showDialog<void>(
                    context: this.context,
                    builder: (_) => const SettingsDialog(),
                  ),
                  child: Text(context.l10n.settings),
                ),
              if (!_inLibrary || isDesktopPlatform(defaultTargetPlatform))
                PopupMenuItem(
                  key: const ValueKey('saveAsOrExport'),
                  height: kMinInteractiveDimension,
                  onTap: () => _save(choose: true),
                  child: Text(
                    _inLibrary
                        ? context.l10n.exportForOverlays
                        : context.l10n.saveAs,
                  ),
                ),
              PopupMenuItem(
                key: const ValueKey('addAndReviewRecordings'),
                height: kMinInteractiveDimension,
                enabled:
                    !_controller.adding &&
                    !_controller.saving &&
                    !_relinking &&
                    !_preparingReview,
                onTap: _addAndReview,
                child: Text(context.l10n.addAndReviewRecordings),
              ),
              PopupMenuItem(
                key: const ValueKey('renameDay'),
                height: kMinInteractiveDimension,
                onTap: () => showDialog<void>(
                  context: this.context,
                  builder: (_) => RenameDayDialog(controller: _controller),
                ),
                child: Text(context.l10n.renameDayMenu),
              ),
              diagnosticsMenuItem(context),
            ],
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              key: const ValueKey('daySections'),
              selectedIndex: _section.index,
              onDestinationSelected: (index) =>
                  setState(() => _section = _Section.values[index]),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.flag_outlined),
                  selectedIcon: const Icon(Icons.flag),
                  label: context.l10n.daySectionDay,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.format_list_numbered),
                  label: context.l10n.daySectionLaps,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.compare_arrows),
                  label: context.l10n.daySectionCompare,
                ),
              ],
            ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          children: [
            if (_controller.adding)
              _Working(
                key: const ValueKey('addingRecordings'),
                text: context.l10n.addingRecordings,
              )
            else if (_preparingReview)
              _Working(
                key: const ValueKey('preparingReview'),
                text: context.l10n.reviewPreparing,
              ),
            Expanded(child: _body(context, wide, mapHeight)),
          ],
        ),
      ),
    );
    // Ctrl+S (Cmd+S on a Mac) saves, like the Save button.
    void saveShortcut() {
      if (!_controller.saving && _controller.dirty) unawaited(_save());
    }

    final page = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            saveShortcut,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            saveShortcut,
      },
      child: Focus(autofocus: true, child: scaffold),
    );
    // A session being added is part of the day: the day stays open until it
    // is in, so it is saved or kept for recovery with it.
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => PopScope(
        canPop:
            !_controller.adding &&
            !_controller.recordingsBusy &&
            !_controller.savingWaitsForRecordings &&
            !_saveBeforeLeaving,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_saveBeforeLeaving) {
            unawaited(_saveThenLeave());
            return;
          }
          _tell(
            _controller.adding
                ? context.l10n.waitUntilSessionAdded
                : _controller.savingWaitsForRecordings
                ? context.l10n.waitUntilRecordingsSaved
                : context.l10n.recordingsBusyLeave,
          );
        },
        child: child!,
      ),
      child: page,
    );
  }

  List<Widget> _summary(BuildContext context, bool wide, double mapHeight) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = FetColors.of(context);
    final analysis = _controller.analysis;
    final ranking = _controller.ranking;
    final best = ranking?.bestOfDay;
    final resolved = analysis.groups.where((group) => group.resolved).toList();
    final path = best == null ? null : _bestPath(best);
    final missing = _controller.missing;
    // Sessions shown without their RCZ, which was not found or is another
    // recording: found again like the sessions' own recordings.
    final shown = {for (final named in _controller.runs) named.run.id};
    final alternatives = [
      for (final recording in _controller.missingAlternatives)
        if (shown.contains(recording.runId)) recording,
    ];
    return [
      if (missing.isNotEmpty || alternatives.isNotEmpty) ...[
        Card(
          key: const ValueKey('missingRecordings'),
          color: missing.isEmpty
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (missing.isNotEmpty) ...[
                  Text(
                    l10n.sessionsNotOpened(missing.length),
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final recording in missing)
                    Text(
                      '${l10n.session(recording.name)}: ${recording.path} · ${l10n.missingReason(recording.reason)}',
                    ),
                  const SizedBox(height: 4),
                  Text(l10n.missingSessionsKept),
                ],
                if (alternatives.isNotEmpty) ...[
                  if (missing.isNotEmpty) const SizedBox(height: 8),
                  Text(
                    l10n.fusionMissingTitle(
                      alternatives.length,
                      RecordingFormat.rcz.name.toUpperCase(),
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final recording in alternatives)
                    Text(
                      l10n.fusionMissingLine(
                        l10n.session(recording.name),
                        recording.path,
                        l10n.fusionReasonText(
                          recording.reason,
                          unavailable: true,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _relinking ? null : _findRecordings,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(
                        _relinking
                            ? l10n.lookingForRecordings
                            : l10n.findRecordingsInFolder,
                      ),
                    ),
                    if (_controller.documentPath != null)
                      OutlinedButton.icon(
                        key: const ValueKey('retryRecordings'),
                        onPressed: _relinking ? null : _retryRecordings,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _retryTask != null
                              ? l10n.retryRecordingsLooking
                              : l10n.retryRecordings,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (best != null) ...[
        HeadlineBar(
          key: const ValueKey('dayBestBar'),
          label: l10n.dayBestLabel,
          title: l10n.lap(best),
          time: displayTime(best.durationSeconds),
          color: colors.you,
          onColor: colors.onLap,
          onTap: () => _open(best),
        ),
        if (_controller.theoreticalBest?.theoreticalBestSeconds
            case final seconds?) ...[
          const SizedBox(height: 4),
          HeadlineBar(
            key: const ValueKey('dayTheoreticalBar'),
            label: l10n.theoreticalBestLabel,
            title: l10n.theoreticalBestHint,
            time: displayTime(seconds),
            color: colors.reference,
            onColor: colors.onLap,
          ),
        ],
        const SizedBox(height: 8),
      ],
      Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: best == null ? null : () => _open(best),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (best == null) ...[
                  Text(l10n.dayBestLabel, style: theme.textTheme.labelLarge),
                  Text(
                    _noBestReason(analysis, ranking),
                    style: theme.textTheme.titleMedium,
                  ),
                  // The way out: the circuit the app could not identify.
                  if (analysis.chosenGroup == null)
                    if (analysis.groups
                            .where((group) => !group.resolved)
                            .firstOrNull
                        case final group?) ...[
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        key: const ValueKey('setCircuit'),
                        onPressed: () => _editCircuit(group.runIds.first),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(l10n.setCircuit),
                      ),
                    ],
                ] else ...[
                  if (ranking!.tieCount > 1)
                    Text(l10n.lapsShareBestTime(ranking.tieCount)),
                  if (path != null && !path.isEmpty) ...[
                    SizedBox(
                      height: mapHeight,
                      child: IgnorePointer(
                        child: TrackMap(
                          interactive: false,
                          path: path,
                          gate: _mapGate,
                          semanticLabel: l10n.bestLapTrace,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SpeedLegend(path: path),
                    const SizedBox(height: 4),
                    Text(l10n.tapToOpenLap, style: theme.textTheme.bodySmall),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (resolved.length > 1) ...[
        Text(l10n.comparedLaps, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        DropdownButton<String>(
          isExpanded: true,
          value: analysis.chosenGroupId,
          items: [
            for (final group in resolved)
              DropdownMenuItem(
                value: group.id,
                child: Text(
                  l10n.groupLapCount(
                    _groupLabel(group),
                    group.eligibleLapCount,
                    group.lapCount,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            if (id != null) _controller.chooseGroup(id);
          },
        ),
        const SizedBox(height: 12),
      ],
      if (analysis.chosenGroup case final group?)
        Text(
          '${_groupLabel(group)} · '
          '${l10n.lapsRanked(group.lapCount, group.eligibleLapCount)}',
          style: theme.textTheme.bodyMedium,
        ),
      if (best != null) ...[
        // What to do next first: the coach's suggestions, then the
        // observations to look at.
        const SizedBox(height: 12),
        NextSessionCard(
          key: _coachKey,
          coach: _controller.coach,
          result: _controller.theoreticalBest,
          session: _controller.latestRunName,
          lapLabel: _controller.lapLabel,
          loading: _controller.coachLoading,
          error: _controller.coachError,
          path: path,
          gate: _mapGate,
          wide: wide,
          speedsConverted: _controller.coachSpeedsConverted,
          withoutTheoreticalBest: _controller.coachWithoutTheoreticalBest,
          onRetry: _controller.retryCoach,
        ),
        const SizedBox(height: 12),
        FocusAreasCard(
          result: _controller.theoreticalBest,
          loading: _controller.theoreticalBestLoading,
          areas: _controller.focusAreas,
          lapLabel: _controller.lapLabel,
          path: path,
          gate: _mapGate,
          wide: wide,
          onOpenLap: _open,
          onCompare: _compare,
        ),
        const SizedBox(height: 12),
        _theoreticalBest(path, wide),
        const SizedBox(height: 12),
        TimeLossesCard(
          result: _controller.theoreticalBest,
          loading: _controller.theoreticalBestLoading,
          path: path,
          gate: _mapGate,
          wide: wide,
          onOpenLap: _open,
          onCompare: _compare,
        ),
        const SizedBox(height: 12),
        ConsistencyCard(
          laps: _controller.lapConsistency,
          result: _controller.theoreticalBest,
          loading: _controller.theoreticalBestLoading,
        ),
        const SizedBox(height: 12),
        ProgressionCard(
          progression: _controller.progression,
          result: _controller.theoreticalBest,
          loading: _controller.theoreticalBestLoading,
          onOpenLap: _open,
          weatherOf: _controller.weather.of,
        ),
      ],
      const SizedBox(height: 12),
      ..._channelCards(),
      if (ranking != null && ranking.runs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(l10n.bestLapOfEachSession, style: theme.textTheme.titleSmall),
        for (final run in ranking.runs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.session(run.runName)),
            subtitle: Text(
              run.bestLap == null
                  ? l10n.noRankedLap(run.lapCount)
                  : '${l10n.lap(run.bestLap!).split(' · ').last} · '
                        '${l10n.lapsRanked(run.lapCount, run.eligibleLapCount)}'
                        '${run.eligibleLapCount >= 3 ? ' · ${l10n.typicalTime(displayTime(run.distribution!.median))}' : ''}',
            ),
            trailing: run.bestLap == null
                ? null
                : Text(
                    displayTime(run.bestLap!.durationSeconds),
                    key: ValueKey('sessionBest ${run.runId}'),
                    // The best lap of the day in purple, as in the lap list.
                    style: _controller.isBestOfDay(run.bestLap!)
                        ? theme.textTheme.titleMedium?.copyWith(
                            color: FetColors.of(context).dayBest,
                            fontWeight: FontWeight.w700,
                          )
                        : theme.textTheme.titleMedium,
                  ),
            onTap: run.bestLap == null ? null : () => _open(run.bestLap!),
          ),
      ],
      for (final group in analysis.groups.where((group) => !group.resolved))
        ListTile(
          key: ValueKey('unresolved ${group.id}'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline),
          title: Text(_groupLabel(group)),
          subtitle: Text(l10n.circuitNotIdentified),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editCircuit(group.runIds.first),
        ),
      const SizedBox(height: 12),
      Text(
        context.l10n.sessionDetailsHeading,
        style: theme.textTheme.titleSmall,
      ),
      for (final named in _controller.runs)
        ListTile(
          key: ValueKey('sessionDetails ${named.run.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.session(named.name)),
          subtitle: Text(
            _detailsText(named.run.id),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.edit_note),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => SessionDetailsDialog(
              controller: _controller,
              runId: named.run.id,
            ),
          ),
        ),
      if (_controller.weather.any)
        Text(
          '${l10n.weatherModelled} ${weatherCredit(l10n)}',
          key: const ValueKey('sessionDetailsWeatherCredit'),
          style: theme.textTheme.bodySmall,
        ),
      const SizedBox(height: 12),
      Text(l10n.circuits, style: theme.textTheme.titleSmall),
      for (final named in _controller.runs) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.session(named.name)),
          subtitle: Text(_circuitText(named.run.id)),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editCircuit(named.run.id),
        ),
        SessionFusion(controller: _controller, runId: named.run.id),
      ],
      if (analysis.messages.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(l10n.notes, style: theme.textTheme.titleSmall),
        for (final message in analysis.messages)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${_runName(message.runId)}${l10n.dayNote(message.text)}',
            ),
          ),
      ],
    ];
  }

  // The car's temperatures and the driver's heart rate, summarized once
  // for the day in the background.
  List<Widget> _channelCards() {
    final channels = _controller.channelSummaries;
    final loading = _controller.channelSummariesLoading;
    if (channels == null && !loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.requestChannelSummaries();
      });
    }
    return [
      CarCard(
        channels: channels,
        associations: _controller.temperatureAssociations,
        loading: loading,
        onRetry: _controller.retryChannelSummaries,
        channelSource: _controller.channelSource,
      ),
      const SizedBox(height: 12),
      DriverCard(
        channels: channels,
        loading: loading,
        onRetry: _controller.retryChannelSummaries,
        onOpenLap: _open,
        channelSource: _controller.channelSource,
      ),
    ];
  }

  Widget _theoreticalBest(LapPath? path, bool wide) {
    final result = _controller.theoreticalBest;
    if (result == null && !_controller.theoreticalBestLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.requestTheoreticalBest();
      });
    }
    return TheoreticalBestCard(
      result: result,
      loading: _controller.theoreticalBestLoading,
      path: path,
      gate: _mapGate,
      wide: wide,
      onAnalyze: _compare,
      onRetry: _controller.retryTheoreticalBest,
      onEditSegments: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SegmentEditorPage(
            controller: _controller,
            path: path,
            gate: _mapGate,
          ),
        ),
      ),
    );
  }

  String _circuitText(String runId) {
    final l10n = context.l10n;
    final analysis = _controller.analysis;
    final configuration =
        analysis.configurations[runId] ?? const TrackConfiguration();
    final manual = _controller.manualTrack(runId) != null;
    DayGroup? group;
    for (final candidate in analysis.groups) {
      if (candidate.runIds.contains(runId)) group = candidate;
    }
    final layout = _layout(configuration);
    final direction = configuration.direction == null
        ? l10n.directionUnknown
        : l10n.direction(configuration.direction!);
    return '$layout · $direction · '
        '${manual ? l10n.circuitSetByYou : l10n.circuitInferredFromGps}'
        '${group == null ? '' : ' · ${_groupLabel(group).split(' · ').first}'}';
  }

  String _layout(TrackConfiguration configuration) =>
      configuration.layoutId == null
      ? context.l10n.circuitNotIdentifiedShort
      : configuration.detectedRoute
      ? context.l10n.detectedRoute
      : configuration.layoutId!;

  /// A group's label in the app's language, built as `telemetry_core`
  /// builds `DayGroup.label`: resolved groups are numbered in order.
  String _groupLabel(DayGroup group) {
    final l10n = context.l10n;
    final groups = _controller.analysis.groups;
    if (!group.resolved) {
      final runId = group.runIds.first;
      final name = [
        for (final named in _controller.runs)
          if (named.run.id == runId) named.name,
      ].firstOrNull;
      return name == null
          ? group.label
          : l10n.circuitGroupUnresolved(l10n.session(name));
    }
    final direction = group.configuration.direction;
    if (direction == null) return group.label;
    final number =
        groups.where((other) => other.resolved).toList().indexOf(group) + 1;
    return l10n.circuitGroup(
      number,
      _layout(group.configuration),
      l10n.direction(direction),
    );
  }

  // A session's conditions, setup changes and notes on one line each, and
  // its weather.
  String _detailsText(String runId) {
    final l10n = context.l10n;
    final details = _controller.runMetadata(runId);
    final lines = [
      for (final (label, text) in [
        (l10n.sessionDetailsConditions, details.conditions),
        (l10n.sessionDetailsSetup, details.setupChanges),
        (l10n.sessionDetailsNotes, details.notes),
      ])
        if (text.trim().isNotEmpty) '$label: ${text.trim()}',
    ];
    final weather = switch (_controller.weather.of(runId)) {
      final shown? => weatherShortText(l10n, shown),
      null => null,
    };
    return [
      lines.isEmpty ? l10n.sessionDetailsNone : lines.join('\n'),
      if (weather != null) l10n.progressionWeather(weather),
    ].join('\n');
  }

  String _runName(String runId) {
    for (final named in _controller.runs) {
      if (named.run.id == runId) return '${context.l10n.session(named.name)}: ';
    }
    return '';
  }

  void _editCircuit(String runId) => showDialog<void>(
    context: context,
    builder: (_) => TrackDialog(controller: _controller, runId: runId),
  );

  String _noBestReason(DayAnalysis analysis, DayRanking? ranking) {
    if (analysis.chosenGroup == null) return context.l10n.noBestLapNoCircuit;
    return context.l10n.noBestLapNoRankable;
  }

  /// Compare: pick any two laps, or open a suggested pair, each session's
  /// best lap against the best of the day.
  List<Widget> _comparePane(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = FetColors.of(context);
    final best = _controller.ranking?.bestOfDay;
    final canPick = _controller.comparisonCandidates().length >= 2;
    final pairs = [
      if (best != null)
        for (final run in _controller.ranking!.runs)
          if (run.bestLap case final lap?)
            if (lap.reference != best.reference &&
                _controller.comparable(lap, best))
              lap,
    ];
    Widget chip(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(3)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: colors.onLap),
      ),
    );
    return [
      Text(l10n.daySectionCompare, style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        canPick ? l10n.compareIntro : l10n.compareNeedsTwoLaps,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      if (canPick)
        FilledButton.icon(
          key: const ValueKey('comparePick'),
          onPressed: _pickComparison,
          icon: const Icon(Icons.compare_arrows),
          label: Text(l10n.comparePickTwoLaps),
        ),
      if (best != null && pairs.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(l10n.compareAgainstBest, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final lap in pairs)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: ValueKey('comparePair-${lap.reference}'),
              title: Text(l10n.lap(lap)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    chip(
                      l10n.compareLapA(displayTime(lap.durationSeconds)),
                      lapAColor,
                    ),
                    chip(
                      l10n.compareLapB(displayTime(best.durationSeconds)),
                      lapBColor,
                    ),
                  ],
                ),
              ),
              trailing: Text(
                displayDelta(lap.durationSeconds - best.durationSeconds),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: FetTheme.mono,
                  // A lap tied with the best has lost nothing.
                  color: lap.durationSeconds > best.durationSeconds
                      ? colors.loss
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => _compare(lap, best, null),
            ),
          ),
      ],
    ];
  }

  List<Widget> _lapList(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return [
      // The button moves under the title when large text needs the room.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.daySectionLaps, style: theme.textTheme.titleSmall),
          if (_controller.comparisonCandidates().length >= 2)
            Wrap(
              children: [
                // The comparison saved with the day, as it was left.
                if (_controller.savedComparisonPair case (final a, final b))
                  TextButton.icon(
                    key: const ValueKey('lapsLastComparison'),
                    onPressed: () => _compare(a, b, null),
                    icon: const Icon(Icons.history),
                    label: Text(context.l10n.lapsLastComparison),
                  ),
                TextButton.icon(
                  key: const ValueKey('lapsCompare'),
                  onPressed: _pickComparison,
                  icon: const Icon(Icons.compare_arrows),
                  label: Text(context.l10n.lapsCompareTwo),
                ),
              ],
            ),
        ],
      ),
      ..._lapRows(context),
    ];
  }

  /// The lap list's rows. The laps that are not ranked (out and in laps,
  /// sections without a start/finish pass, excluded laps, laps with an
  /// issue) are hidden while the setting says so and the day has a ranked
  /// lap to show instead; a button shows or hides them. The day keeps every
  /// lap either way.
  List<Widget> _lapRows(BuildContext context) {
    final l10n = context.l10n;
    final rows = _controller.analysis.rows;
    final ranked = {
      for (final row in rows)
        if (row.type == LapSectionType.lap && _controller.issues(row).isEmpty)
          row.reference,
    };
    final unranked = rows.length - ranked.length;
    if (unranked == 0 || unranked == rows.length) {
      return [for (final row in rows) _lapTile(context, row)];
    }
    final hide = hideUnrankedLapsSetting.value;
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('lapsUnrankedToggle'),
          onPressed: () =>
              setState(() => hideUnrankedLapsSetting.value = !hide),
          icon: Icon(
            hide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          label: Text(
            hide ? l10n.lapsShowUnranked(unranked) : l10n.lapsHideUnranked,
          ),
        ),
      ),
      for (final row in rows)
        if (!hide || ranked.contains(row.reference)) _lapTile(context, row),
    ];
  }

  Widget _lapTile(BuildContext context, DayLapRow row) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final issues = _controller.issues(row);
    final timed = row.type == LapSectionType.lap;
    final bestOfDay = _controller.isBestOfDay(row);
    final bestOfRun = _controller.isBestOfRun(row);
    final marks = [
      if (bestOfDay)
        l10n.bestOfDay
      else if (bestOfRun)
        l10n.bestOfSession(l10n.session(row.runName)),
      if (timed && issues.isNotEmpty)
        issues.contains(LapIssue.userExclusion)
            ? switch (_controller.exclusionReason(row)) {
                final reason? when reason.isNotEmpty => l10n.lapExcluded(
                  reason,
                ),
                _ => l10n.lapExcludedNoReason,
              }
            : l10n.lapNotRanked(l10n.lapIssue(issues.first)),
      if (!timed)
        row.type == LapSectionType.unknown
            ? l10n.noStartFinishPass
            : l10n.notTimed,
    ];
    // As on a timing screen: purple marks the best of the day, green the
    // best of its session, on the edge and in the time.
    final colors = FetColors.of(context);
    final ranked = timed && issues.isEmpty;
    final mark = bestOfDay
        ? colors.dayBest
        : bestOfRun
        ? colors.gain
        : null;
    final best = _controller.ranking?.bestOfDay;
    final delta = ranked && best != null && !bestOfDay
        ? row.durationSeconds - best.durationSeconds
        : null;
    final timeStyle = theme.textTheme.titleMedium?.copyWith(
      fontFamily: FetTheme.mono,
      fontWeight: mark == null ? FontWeight.w500 : FontWeight.w700,
      color: !ranked ? theme.colorScheme.outline : mark,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: mark ?? Colors.transparent, width: 3),
        ),
      ),
      // A row rather than a ListTile, which fixes its height: with large
      // text the time and its gap grow the row instead of overflowing it.
      // A button to a screen reader, as the ListTile was.
      child: MergeSemantics(
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: () => _open(row),
            child: ConstrainedBox(
              // A ListTile's heights: 56 for one line, 72 for two, less on a
              // desktop's compact density.
              constraints: BoxConstraints(
                minHeight:
                    (marks.isEmpty ? 56 : 72) +
                    theme.visualDensity.baseSizeAdjustment.dy,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.lap(row), style: theme.textTheme.bodyLarge),
                          if (marks.isNotEmpty)
                            Text(
                              marks.join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          displayTime(row.durationSeconds),
                          style: timeStyle,
                        ),
                        if (delta != null)
                          Text(
                            displayDelta(delta),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: FetTheme.mono,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Section { day, laps, compare }

/// The day saved at [path] opened again, as [DayResultsPage]'s "Retry
/// recordings" runs it in the background: top-level, so that nothing of
/// the page goes with it to the other isolate.
OpenedDay reopenDay(String path, CancellationCheck cancelled) =>
    openDay(path, cancelled: cancelled);

/// Work under way on the whole day: a strip and what it is, readable at a
/// glance on a large window.
class _Working extends StatelessWidget {
  const _Working({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LinearProgressIndicator(semanticsLabel: text),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: ExcludeSemantics(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    ],
  );
}
