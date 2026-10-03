import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import 'day_results_controller.dart';
import 'document_pickers.dart';
import 'lap_page.dart';
import 'recovery_store.dart';
import 'segment_editor_page.dart';
import 'theoretical_best_card.dart';
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
    this.recovery,
  }) : _create = (() => DayResultsController(
         runs: runs,
         analysis: analysis,
         recovery: recovery,
       ));

  /// A day opened from its document.
  DayResultsPage.opened({
    super.key,
    required OpenedDay day,
    this.documents = const PlatformDocumentPickers(),
    this.recovery,
  }) : _create = (() => DayResultsController.opened(day, recovery: recovery));

  /// A day held by [controller], which the page then owns.
  DayResultsPage.controller({
    super.key,
    required DayResultsController controller,
    this.documents = const PlatformDocumentPickers(),
    this.recovery,
  }) : _create = (() => controller);

  final DayResultsController Function() _create;
  final DocumentPickers documents;

  /// Keeps the day while it has unsaved changes; none when null.
  final RecoveryStore? recovery;

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(DayLapRow row) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LapPage(controller: _controller, row: row),
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
      if (mounted) _tell('Saved as ${p.basename(path)}.');
    } on Exception catch (error) {
      if (mounted) _tell('Not saved: $error');
    }
  }

  // Built outside the state so the isolate's closure holds only its inputs.
  static OpenedDay Function() _relinkJob(
    String path,
    String folder,
    List<MissingRecording> missing,
  ) =>
      () => openDay(path, relinked: findRecordings(folder, missing));

  /// Looks for the missing recordings in a folder the user picks and opens
  /// the day again with the ones found.
  Future<void> _findRecordings() async {
    final path = _controller.documentPath;
    if (path == null) return;
    if (_controller.dirty) {
      _tell('Save the day first, then find its recordings.');
      return;
    }
    final folder = await widget.documents.pickFolder();
    if (folder == null || !mounted) return;
    setState(() => _relinking = true);
    try {
      final missing = _controller.missing;
      final day = await Isolate.run(_relinkJob(path, folder, missing));
      if (!mounted) return;
      if (day.missing.length == missing.length) {
        _tell('No missing recording was found in that folder.');
        return;
      }
      if (day.analysis == null) return;
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
          PopupMenuButton<void>(
            tooltip: 'More',
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => _save(choose: true),
                child: const Text('Save as…'),
              ),
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
        builder: (context, _) {
          final summary = _summary(context, wide, mapHeight);
          final laps = _lapList(context);
          if (!wide) {
            return TabBarView(
              children: [
                _KeepAlive(
                  child: ListView(
                    key: const ValueKey('dayResultsSummary'),
                    padding: const EdgeInsets.all(16),
                    children: summary,
                  ),
                ),
                _KeepAlive(
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
        },
      ),
    );
    return wide ? scaffold : DefaultTabController(length: 2, child: scaffold);
  }

  List<Widget> _summary(BuildContext context, bool wide, double mapHeight) {
    final theme = Theme.of(context);
    final analysis = _controller.analysis;
    final ranking = _controller.ranking;
    final best = ranking?.bestOfDay;
    final resolved = analysis.groups.where((group) => group.resolved).toList();
    final path = best == null ? null : _bestPath(best);
    final missing = _controller.missing;
    return [
      if (missing.isNotEmpty) ...[
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
        const SizedBox(height: 12),
        _theoreticalBest(path, wide),
      ],
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
      for (final named in _controller.runs)
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
      Text('Laps', style: theme.textTheme.titleSmall),
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

/// Keeps a tab's scroll position and state, such as the lap chosen in the
/// theoretical best, while the other tab is shown.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
