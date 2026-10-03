import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import '../diagnostics/diagnostics_page.dart';
import '../format.dart';
import '../import/day_import_page.dart'
    show PlatformRecordingPickers, RecordingPickers;
import '../l10n.dart';
import '../settings_dialog.dart';
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
import 'segment_editor_page.dart';
import 'session_details_dialog.dart';
import 'theoretical_best_card.dart';
import 'time_losses_card.dart';
import '../ui/theme.dart';
import 'track_dialog.dart';
import 'track_map.dart';

/// The day at a glance, led by the best lap: "Best day · 1:49.898 ·
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
  }) : replace = null,
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
  }) : replace = null,
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
  }) : _create = (() => controller);

  final DayResultsController Function() _create;
  final DocumentPickers documents;

  /// Chooses recordings to add to the day.
  final RecordingPickers pickers;

  /// Keeps the day while it has unsaved changes; none when null.
  final RecoveryStore? recovery;

  /// Takes the day opened again in place of this one; see
  /// [DayResultsPage.controller].
  final ValueChanged<DayResultsController>? replace;

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
      await _controller.flushRecovery().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportAddition);
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
    final added = addition.added;
    final l10n = context.l10n;
    final lines = [
      if (addition.error.isNotEmpty)
        addition.error
      else if (added.isEmpty &&
          addition.combined.isEmpty &&
          addition.notCombined.isEmpty)
        'Nothing was added.'
      else ...[
        if (added.isNotEmpty) '${added.join(', ')} added to the day.',
        if (addition.combined.isNotEmpty)
          context.l10n.fusionCombinedWith(
            RecordingFormat.rcz.name.toUpperCase(),
            addition.combined.map(context.l10n.session).join(', '),
          ),
        if (addition.notCombined.isNotEmpty)
          l10n.fusionAddedNotCombined(
            RecordingFormat.rcz.name.toUpperCase(),
            addition.notCombined.map(l10n.session).join(', '),
          ),
      ],
      if (addition.savedTo != null)
        'Saved as ${p.basename(addition.savedTo!)}.',
      if (addition.saveError.isNotEmpty) 'Not saved: ${addition.saveError}',
      ...addition.notes,
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
          Scrollable.ensureVisible(
            card,
            duration: const Duration(milliseconds: 300),
          );
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
    await _controller.addRecordings(paths);
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
      title: 'Lap A',
      candidates: _controller.comparisonCandidates(),
    );
    if (a == null || !mounted) return;
    final b = await pickComparisonLap(
      context,
      title: 'Compare ${a.displayName} with',
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

  void _tell(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save({bool choose = false}) async {
    final path = choose || _controller.documentPath == null
        ? await widget.documents.saveLocation(_controller.name)
        : _controller.documentPath;
    if (path == null || !mounted) return;
    try {
      await _controller.save(path);
      if (mounted) {
        _tell(
          _controller.dirty
              ? 'Saved as ${p.basename(path)}. Changes made while saving '
                    'are not saved yet.'
              : 'Saved as ${p.basename(path)}.',
        );
      }
    } on Exception catch (error) {
      if (mounted) _tell('Not saved: $error');
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
      _tell('Wait until the recordings are added, then find the others.');
      return;
    }
    if (_controller.dirty) {
      _tell('Save the day first, then find its recordings.');
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
        _tell('Recordings were added meanwhile. Find the recordings again.');
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
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) _tell('The day could not be opened again: $error');
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
          ),
        ),
      );
    } on OperationCancelled {
      return;
    } on BackgroundTaskFailed catch (error) {
      if (mounted && generation == _retryGeneration) {
        _tell(l10n.retryRecordingsFailed(error.message));
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
        NavigationRail(
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
        else ...[
          Expanded(
            flex: 5,
            child: ListView(
              key: const ValueKey('dayResultsSummary'),
              controller: _summaryScroll,
              padding: const EdgeInsets.all(16),
              // As on a phone: the Next session card is built from the top.
              scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
              children: summary,
            ),
          ),
          Expanded(
            flex: 4,
            child: ListView(
              key: const ValueKey('dayResultsLaps'),
              padding: const EdgeInsets.all(16),
              children: laps,
            ),
          ),
        ],
      ],
    );
  }

  Widget _page(BuildContext context, double width) {
    final wide = width >= _twoPaneWidth;
    // The trace keeps a similar shape from a small phone to a tablet in
    // portrait: about 0.6 of the card's width.
    final mapHeight = wide ? 360.0 : ((width - 64) * 0.6).clamp(200.0, 420.0);
    final scaffold = Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Text(
            _controller.documentPath == null
                ? 'Day results'
                : '${_controller.name}${_controller.dirty ? ' •' : ''}',
          ),
        ),
        actions: [
          const SettingsButton(),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => IconButton(
              tooltip: 'Save',
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
              tooltip: 'Add recordings',
              icon: const Icon(Icons.playlist_add),
              onPressed: _controller.adding || _controller.saving || _relinking
                  ? null
                  : _addRecordings,
            ),
          ),
          IconButton(
            key: const ValueKey('openDayReport'),
            tooltip: 'Day report',
            icon: const Icon(Icons.summarize_outlined),
            onPressed: _openReport,
          ),
          PopupMenuButton<void>(
            key: const ValueKey('moreMenu'),
            tooltip: 'More',
            itemBuilder: (context) => [
              PopupMenuItem(
                height: kMinInteractiveDimension,
                onTap: () => _save(choose: true),
                child: const Text('Save as…'),
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
              const LinearProgressIndicator(
                key: ValueKey('addingRecordings'),
                semanticsLabel: 'Adding recordings',
              ),
            Expanded(child: _body(context, wide, mapHeight)),
          ],
        ),
      ),
    );
    final page = scaffold;
    // A session being added is part of the day: the day stays open until it
    // is in, so it is saved or kept for recovery with it.
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => PopScope(
        canPop: !_controller.adding,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _tell('Wait until the session is added.');
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
                    missing.length == 1
                        ? '1 session could not be opened'
                        : '${missing.length} sessions could not be opened',
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final recording in missing)
                    Text(
                      '${recording.name}: ${recording.path} · ${recording.reason}',
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'They stay in the day when it is saved, but are not shown.',
                  ),
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
                            ? 'Looking…'
                            : 'Find recordings in a folder…',
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
        _HeadlineBar(
          key: const ValueKey('dayBestBar'),
          label: l10n.dayBestLabel,
          title: best.displayName,
          time: displayTime(best.durationSeconds),
          color: colors.you,
          onColor: colors.onLap,
          onTap: () => _open(best),
        ),
        if (_controller.theoreticalBest?.theoreticalBestSeconds
            case final seconds?) ...[
          const SizedBox(height: 4),
          _HeadlineBar(
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
                ] else ...[
                  if (ranking!.tieCount > 1)
                    Text(
                      '${ranking.tieCount} laps share this time; the earliest is shown.',
                    ),
                  if (path != null && !path.isEmpty) ...[
                    SizedBox(
                      height: mapHeight,
                      child: IgnorePointer(
                        child: TrackMap(
                          interactive: false,
                          path: path,
                          gate: _mapGate,
                          semanticLabel:
                              'Trace of the best lap, coloured by speed',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SpeedLegend(path: path),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to open the lap.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (resolved.length > 1) ...[
        Text('Compared laps', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        DropdownButton<String>(
          isExpanded: true,
          value: analysis.chosenGroupId,
          items: [
            for (final group in resolved)
              DropdownMenuItem(
                value: group.id,
                child: Text(
                  '${group.label} · ${group.eligibleLapCount}/${group.lapCount} laps',
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
          '${group.label} · ${group.eligibleLapCount} of ${group.lapCount} laps ranked',
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
          onRetry: _controller.retryTheoreticalBest,
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
        ),
      ],
      const SizedBox(height: 12),
      ..._channelCards(),
      if (ranking != null && ranking.runs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Best lap of each session', style: theme.textTheme.titleSmall),
        for (final run in ranking.runs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(run.runName),
            subtitle: Text(
              run.bestLap == null
                  ? 'No ranked lap · ${run.lapCount} ${run.lapCount == 1 ? 'lap' : 'laps'}'
                  : '${run.bestLap!.displayName.split(' · ').last} · '
                        '${run.eligibleLapCount} of ${run.lapCount} laps ranked'
                        '${run.eligibleLapCount >= 3 ? ' · typical ${displayTime(run.distribution!.median)}' : ''}',
            ),
            trailing: run.bestLap == null
                ? null
                : Text(
                    displayTime(run.bestLap!.durationSeconds),
                    style: theme.textTheme.titleMedium,
                  ),
            onTap: run.bestLap == null ? null : () => _open(run.bestLap!),
          ),
      ],
      for (final group in analysis.groups.where((group) => !group.resolved))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline),
          title: Text(group.label),
          subtitle: const Text(
            'Its circuit could not be identified, so its laps are not compared.',
          ),
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
      const SizedBox(height: 12),
      Text('Circuits', style: theme.textTheme.titleSmall),
      for (final named in _controller.runs) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(named.name),
          subtitle: Text(_circuitText(named.run.id)),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) =>
                TrackDialog(controller: _controller, runId: named.run.id),
          ),
        ),
        SessionFusion(controller: _controller, runId: named.run.id),
      ],
      if (analysis.messages.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Notes', style: theme.textTheme.titleSmall),
        for (final message in analysis.messages)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${_runName(message.runId)}${message.text}'),
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
        channelSource: _controller.channelSource,
      ),
      const SizedBox(height: 12),
      DriverCard(
        channels: channels,
        loading: loading,
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
    final analysis = _controller.analysis;
    final configuration =
        analysis.configurations[runId] ?? const TrackConfiguration();
    final manual = _controller.manualTrack(runId) != null;
    String? groupLabel;
    for (final group in analysis.groups) {
      if (group.runIds.contains(runId)) groupLabel = group.label;
    }
    final layout = configuration.layoutId == null
        ? 'Not identified'
        : configuration.detectedRoute
        ? 'Detected route'
        : configuration.layoutId!;
    final direction = configuration.direction?.label ?? 'direction unknown';
    return '$layout · $direction · ${manual ? 'set by you' : 'inferred from GPS'}'
        '${groupLabel == null ? '' : ' · ${groupLabel.split(' · ').first}'}';
  }

  // A session's conditions, setup changes and notes on one line each.
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
    return lines.isEmpty ? l10n.sessionDetailsNone : lines.join('\n');
  }

  String _runName(String runId) {
    for (final named in _controller.runs) {
      if (named.run.id == runId) return '${named.name}: ';
    }
    return '';
  }

  String _noBestReason(DayAnalysis analysis, DayRanking? ranking) {
    if (analysis.chosenGroup == null) {
      return 'No best lap: no session has enough complete GPS laps to identify its circuit.';
    }
    return 'No best lap: no lap of this group can be ranked.';
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
              title: Text(lap.displayName),
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
    return [
      // The button moves under the title when large text needs the room.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Laps', style: theme.textTheme.titleSmall),
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
      for (final row in _controller.analysis.rows) _lapTile(context, row),
    ];
  }

  Widget _lapTile(BuildContext context, DayLapRow row) {
    final theme = Theme.of(context);
    final issues = _controller.issues(row);
    final timed = row.type == LapSectionType.lap;
    final bestOfDay = _controller.isBestOfDay(row);
    final bestOfRun = _controller.isBestOfRun(row);
    final marks = [
      if (bestOfDay)
        'Best of the day'
      else if (bestOfRun)
        'Best of ${row.runName}',
      if (timed && issues.isNotEmpty)
        issues.contains(LapIssue.userExclusion)
            ? 'Excluded: ${_controller.exclusionReason(row)}'
            : 'Not ranked: ${issues.first.label}',
      if (!timed)
        row.type == LapSectionType.unknown
            ? 'No start/finish pass'
            : 'Not timed',
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
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12),
        title: Text(row.displayName),
        subtitle: marks.isEmpty ? null : Text(marks.join(' · ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(displayTime(row.durationSeconds), style: timeStyle),
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
        onTap: () => _open(row),
      ),
    );
  }
}

enum _Section { day, laps, compare }

/// A headline result as a filled bar, as on a timing screen: a small label
/// and a name on the left, the time large on the right.
class _HeadlineBar extends StatelessWidget {
  const _HeadlineBar({
    super.key,
    required this.label,
    required this.title,
    required this.time,
    required this.color,
    required this.onColor,
    this.onTap,
  });

  final String label;
  final String title;
  final String time;
  final Color color;
  final Color onColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: color,
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: text.labelSmall?.copyWith(
                          color: onColor,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        title,
                        style: text.titleSmall?.copyWith(color: onColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  time,
                  style: text.headlineSmall?.copyWith(
                    fontFamily: FetTheme.mono,
                    fontWeight: FontWeight.w700,
                    color: onColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The day saved at [path] opened again, as [DayResultsPage]'s "Retry
/// recordings" runs it in the background: top-level, so that nothing of
/// the page goes with it to the other isolate.
OpenedDay reopenDay(String path, CancellationCheck cancelled) =>
    openDay(path, cancelled: cancelled);
