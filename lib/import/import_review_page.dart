import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';
import 'import_runner.dart' show ReviewSession;

/// What the user confirmed in an import review.
final class ImportReviewResult {
  const ImportReviewResult({required this.choices, this.newDay = false});

  /// For each ready recording: a session of its own, skipped, or the same
  /// run as another recording or session ([ImportChoices]).
  final ImportChoices choices;

  /// The recordings start a new day instead of being added to the open one.
  final bool newDay;
}

/// A recording's length as minutes:seconds, "14:05", as Overlays' review
/// shows it.
String reviewDuration(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Opens the review of [plan] (FET-58): every recording found and what will
/// happen to it, the automatic choices first. Null when the user closed it.
///
/// [automatic] are the choices without review. When recordings are added to
/// a day ([adding]), [sessions] are the day's sessions a recording may be made the same
/// run as, [alreadyGrouped] those of them that have another recording
/// already, and [alreadyInDay] the recordings the day has (skipped). With
/// [automaticNewDay], "Start a new day" is offered with those choices; it
/// is unavailable while [newDayBlocked] (unsaved changes).
Future<ImportReviewResult?> showImportReview(
  BuildContext context, {
  required TelemetryImportPlan plan,
  required ImportChoices automatic,
  bool adding = false,
  List<ReviewSession> sessions = const [],
  Set<String> alreadyGrouped = const {},
  Set<String> alreadyInDay = const {},
  ImportChoices? automaticNewDay,
  bool newDayBlocked = false,
}) => Navigator.of(context).push<ImportReviewResult>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ImportReviewPage(
      plan: plan,
      automatic: automatic,
      adding: adding,
      sessions: sessions,
      alreadyGrouped: alreadyGrouped,
      alreadyInDay: alreadyInDay,
      automaticNewDay: automaticNewDay,
      newDayBlocked: newDayBlocked,
    ),
  ),
);

/// The review of an import or of an addition to a day; see
/// [showImportReview]. Pops with an [ImportReviewResult] when confirmed.
class ImportReviewPage extends StatefulWidget {
  const ImportReviewPage({
    super.key,
    required this.plan,
    required this.automatic,
    this.adding = false,
    this.sessions = const [],
    this.alreadyGrouped = const {},
    this.alreadyInDay = const {},
    this.automaticNewDay,
    this.newDayBlocked = false,
  });

  final TelemetryImportPlan plan;
  final ImportChoices automatic;
  final List<ReviewSession> sessions;
  final Set<String> alreadyGrouped;
  final Set<String> alreadyInDay;
  final ImportChoices? automaticNewDay;
  final bool newDayBlocked;

  /// Whether recordings are added to a day (rather than imported as one).
  final bool adding;

  @override
  State<ImportReviewPage> createState() => _ImportReviewPageState();
}

class _ImportReviewPageState extends State<ImportReviewPage> {
  bool _newDay = false;
  late ImportChoices _choices = Map.of(widget.automatic);

  late final Map<String, String> _names = {
    for (final run in widget.plan.runs) run.id: p.basename(run.sourcePath),
  };
  late final Map<String, TelemetryRunProposal> _runs = {
    for (final run in widget.plan.runs) run.id: run,
  };

  // The day's sessions take part only while adding to the day.
  bool get _appending => widget.adding && !_newDay;
  Set<String> get _sessionIds => _appending
      ? {for (final session in widget.sessions) session.runId}
      : const {};

  bool _locked(String runId) =>
      _appending && widget.alreadyInDay.contains(runId);

  void _setDestination(bool newDay) {
    if (newDay == _newDay) return;
    // As Overlays: changing where the recordings go starts the choices
    // again from that destination's automatic ones.
    setState(() {
      _newDay = newDay;
      _choices = Map.of(
        newDay ? widget.automaticNewDay ?? widget.automatic : widget.automatic,
      );
    });
  }

  void _choose(String runId, String group) => setState(() {
    _choices = releaseOrphanedChoices({
      ..._choices,
      runId: group,
    }, runs: _sessionIds);
  });

  ImportChoiceProblem? get _problem => checkImportChoices(
    _runs.keys,
    _choices,
    runs: _sessionIds,
    alreadyGrouped: _appending ? widget.alreadyGrouped : const {},
  );

  int get _newSessions =>
      _choices.entries.where((entry) => entry.key == entry.value).length;

  /// What [runId] may be the same run as: the other recordings imported as
  /// sessions of their own and, when adding, the day's sessions, each while
  /// it has no other recording yet.
  List<(String, String)> _targets(String runId) {
    int members(String group) => _choices.entries
        .where(
          (entry) =>
              entry.key != runId && entry.key != group && entry.value == group,
        )
        .length;
    bool open(String group) =>
        members(group) + 2 <= maximumRecordingsPerReviewedRun ||
        _choices[runId] == group;
    return [
      for (final run in widget.plan.runs)
        if (run.id != runId && _choices[run.id] == run.id && open(run.id))
          (run.id, _names[run.id]!),
      if (_appending)
        for (final session in widget.sessions)
          if (!widget.alreadyGrouped.contains(session.runId) &&
              open(session.runId))
            (session.runId, session.name),
    ];
  }

  String _problemText(ImportChoiceProblem problem) {
    final l10n = context.l10n;
    return switch (problem) {
      ImportChoiceProblem.targetNotRun ||
      ImportChoiceProblem.changed => l10n.reviewProblemTarget,
      ImportChoiceProblem.tooManyRecordings => l10n.reviewProblemTooMany,
      ImportChoiceProblem.nothingSelected => l10n.reviewProblemNothing,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final problem = _problem;
    final confirm = !widget.adding
        ? l10n.reviewConfirmImport
        : _newDay
        ? l10n.reviewConfirmNewDay
        : l10n.reviewConfirmAdd;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewImportTitle)),
      body: ListView(
        key: const ValueKey('importReviewList'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.reviewImportIntro, style: theme.textTheme.bodyLarge),
          if (widget.adding && widget.automaticNewDay != null) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const ValueKey('reviewDestination'),
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l10n.reviewDestinationAppend),
                ),
                ButtonSegment(
                  value: true,
                  enabled: !widget.newDayBlocked,
                  label: Text(l10n.reviewDestinationNewDay),
                ),
              ],
              selected: {_newDay},
              onSelectionChanged: (selected) =>
                  _setDestination(selected.single),
            ),
            if (widget.newDayBlocked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.reviewNewDayNeedsSave,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          const SizedBox(height: 8),
          for (final (index, file) in widget.plan.files.indexed)
            _file(context, index, file),
          const SizedBox(height: 12),
          Text(l10n.reviewSameRunHint, style: theme.textTheme.bodySmall),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  problem == null
                      ? l10n.reviewSessionCount(_newSessions)
                      : _problemText(problem),
                  key: const ValueKey('reviewSummary'),
                  style: problem == null
                      ? null
                      : TextStyle(color: theme.colorScheme.error),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: const ValueKey('confirmReview'),
                onPressed: problem != null
                    ? null
                    : () => Navigator.of(context).pop(
                        ImportReviewResult(
                          choices: Map.unmodifiable(_choices),
                          newDay: _newDay,
                        ),
                      ),
                child: Text(confirm),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _file(
    BuildContext context,
    int index,
    TelemetryImportFileResult file,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final name = p.basename(file.requestedPath);
    final run = file.status == TelemetryImportFileStatus.ready
        ? _runs[file.runId]
        : null;
    final lines = <Widget>[];
    if (run != null) {
      lines.add(
        Text(
          l10n.reviewRecordingSummary(
            reviewDuration(run.telemetry.duration),
            run.laps.timedLaps.length,
          ),
        ),
      );
      if (_locked(run.id)) {
        lines.add(Text(l10n.reviewAlreadyInDay));
      } else {
        final targets = _targets(run.id);
        final stored = _choices[run.id];
        final choice =
            stored == skipRecording ||
                targets.any((target) => target.$1 == stored)
            ? stored!
            : run.id;
        lines.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DropdownButton<String>(
              key: ValueKey('reviewChoice:$index'),
              isExpanded: true,
              value: choice,
              items: [
                DropdownMenuItem(
                  value: run.id,
                  child: Text(l10n.reviewChoiceNewSession),
                ),
                DropdownMenuItem(
                  value: skipRecording,
                  child: Text(l10n.reviewChoiceSkip),
                ),
                for (final (id, target) in targets)
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                      l10n.reviewChoiceSameRunAs(target),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _choose(run.id, value);
              },
            ),
          ),
        );
        for (final match in widget.plan.possibleSameRuns) {
          final other = match.firstRunId == run.id
              ? match.secondRunId
              : match.secondRunId == run.id
              ? match.firstRunId
              : null;
          if (other == null || !_names.containsKey(other)) continue;
          lines.add(
            Text(
              l10n.reviewPossibleSameRun(_names[other]!),
              style: theme.textTheme.bodySmall,
            ),
          );
        }
      }
    } else if (file.status == TelemetryImportFileStatus.duplicate) {
      lines.add(Text(l10n.reviewDuplicate(_names[file.runId] ?? '')));
    } else {
      lines.add(
        Text(
          l10n.reviewFailed(file.message),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );
    }
    return Card(
      key: ValueKey('reviewFile:$index'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            ...lines,
          ],
        ),
      ),
    );
  }
}
