import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import '../diagnostics/diagnostics_page.dart';
import '../format.dart';
import '../l10n.dart';
import '../import/day_import_page.dart'
    show PlatformRecordingPickers, RecordingPickers;
import '../settings_dialog.dart';
import 'channel_cards.dart';
import 'comparison_page.dart';
import 'consistency_card.dart';
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
import 'theoretical_best_card.dart';
import 'time_losses_card.dart';
import 'touch.dart';
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

  /// The summary's scroll position, on a phone's Results tab or the wide
  /// layout's left pane.
  final _summaryScroll = ScrollController();

  /// The phone layout's Results and Laps tabs; null in the wide layout.
  TabController? _tabs;

  /// The day opens on what to do in the next session: the Results tab,
  /// scrolled to the Next session card. Scrolled far below it, the card is
  /// not built, so the summary first goes back to the top, near the card.
  void _revealCoach() {
    _tabs?.animateTo(0);
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

  /// Two panes from this width; below it the summary and the laps are tabs.
  static const _twoPaneWidth = 900.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _page(context, constraints.maxWidth),
  );

  Widget _body(BuildContext context, bool wide, double mapHeight) {
    final summary = _summary(context, wide, mapHeight);
    final laps = _lapList(context);
    _tabs = wide ? null : DefaultTabController.maybeOf(context);
    if (!wide) {
      return TabBarView(
        children: [
          KeepAliveItem(
            child: ListView(
              key: const ValueKey('dayResultsSummary'),
              controller: _summaryScroll,
              padding: const EdgeInsets.all(16),
              children: summary,
            ),
          ),
          KeepAliveItem(
            child: ListView(
              key: const ValueKey('dayResultsLaps'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: laps,
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: ListView(
            key: const ValueKey('dayResultsSummary'),
            controller: _summaryScroll,
            padding: const EdgeInsets.all(16),
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
              diagnosticsMenuItem(context),
            ],
          ),
        ],
        bottom: wide
            ? null
            : const TabBar(
                tabs: [
                  Tab(text: 'Results'),
                  Tab(text: 'Laps'),
                ],
              ),
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
    final page = wide
        ? scaffold
        : DefaultTabController(length: 2, child: scaffold);
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
    final l10n = context.l10n;
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
                OutlinedButton.icon(
                  onPressed: _relinking ? null : _findRecordings,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(
                    _relinking ? 'Looking…' : 'Find recordings in a folder…',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
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
                Text('Best day', style: theme.textTheme.labelLarge),
                if (best == null)
                  Text(
                    _noBestReason(analysis, ranking),
                    style: theme.textTheme.titleMedium,
                  )
                else ...[
                  Text(
                    displayTime(best.durationSeconds),
                    style: theme.textTheme.displaySmall,
                  ),
                  Text(best.displayName, style: theme.textTheme.titleMedium),
                  if (ranking!.tieCount > 1)
                    Text(
                      '${ranking.tieCount} laps share this time; the earliest is shown.',
                    ),
                  if (path != null && !path.isEmpty) ...[
                    const SizedBox(height: 12),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: bestOfDay
          ? Icon(Icons.emoji_events, color: theme.colorScheme.primary)
          : bestOfRun
          ? const Icon(Icons.star_outline)
          : const SizedBox(width: 24),
      title: Text(row.displayName),
      subtitle: marks.isEmpty ? null : Text(marks.join(' · ')),
      trailing: Text(
        displayTime(row.durationSeconds),
        style: timed && issues.isEmpty
            ? theme.textTheme.titleMedium
            : theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
      ),
      onTap: () => _open(row),
    );
  }
}
