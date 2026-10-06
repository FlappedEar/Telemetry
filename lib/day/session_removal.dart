import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';
import 'day_results_controller.dart';

/// A session just removed from a day (FET-241): what its day's document
/// held before, so Undo can put the session back while the day opened
/// without it has not changed since.
final class SessionRemoval {
  const SessionRemoval({
    required this.path,
    required this.before,
    required this.label,
    this.saves = 0,
  });

  /// Where the day is saved.
  final String path;

  /// The day's document with the session, as it was saved.
  final Map<String, Object?> before;

  /// "Session 2", as the page named it.
  final String label;

  /// The saves the day opened without the session makes by itself: one
  /// when the session held the day's corners, so the corners measured
  /// again on the best lap left are in the file at once.
  final int saves;
}

/// The removal each day, opened again without its session, can still undo.
final sessionRemovals = Expando<SessionRemoval>();

/// The document saved at the path given, before and without run [runId]
/// ([removeRunFromDayDocument]), and the day it opens to, before anything
/// is written: a [BackgroundJob] (top-level, so nothing of the page goes
/// with it to another isolate). [held segments] says the run held approved
/// segments (the day's corners), which go with it.
({
  Map<String, Object?> before,
  Map<String, Object?> after,
  OpenedDay day,
  bool heldSegments,
})
removeSessionJob(
  ({String path, String runId}) argument,
  CancellationCheck cancelled,
) {
  final before = readDayDocument(argument.path);
  final after = removeRunFromDayDocument(before, argument.runId);
  return (
    before: before,
    after: after,
    day: _open(after, argument.path, cancelled),
    heldSegments: dayRunHoldsSegments(before, argument.runId),
  );
}

/// [before] written back over the document saved at the path given, one
/// saved revision after it, and the day it opens to: Undo's
/// [BackgroundJob].
({Map<String, Object?> document, OpenedDay day}) restoreSessionJob(
  ({String path, Map<String, Object?> before}) argument,
  CancellationCheck cancelled,
) {
  final document = restoredDayDocument(
    argument.before,
    readDayDocument(argument.path),
  );
  return (document: document, day: _open(document, argument.path, cancelled));
}

OpenedDay _open(
  Map<String, Object?> document,
  String path,
  CancellationCheck cancelled,
) {
  return openDayDocument(document, path, cancelled: cancelled);
}

/// Asks which of [controller]'s sessions to remove; pops its run id, or
/// null when cancelled.
Future<String?> chooseSessionToRemove(
  BuildContext context,
  DayResultsController controller,
) {
  final l10n = context.l10n;
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.removeSessionChoose),
      children: [
        for (final named in controller.runs)
          SimpleDialogOption(
            key: ValueKey('removeSessionChoice ${named.run.id}'),
            onPressed: () => Navigator.pop(context, named.run.id),
            child: Text(l10n.session(named.name)),
          ),
        // Sessions whose recording could not be opened can go too.
        for (final recording in controller.missing)
          SimpleDialogOption(
            key: ValueKey('removeSessionChoice ${recording.runId}'),
            onPressed: () => Navigator.pop(context, recording.runId),
            child: Text(l10n.session(recording.name)),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

/// Asks to confirm that the session [label] leaves the day; with
/// [corners], that the day's corners were measured on it.
Future<bool> confirmSessionRemoval(
  BuildContext context,
  String label, {
  bool corners = false,
}) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.removeSessionTitle(label)),
      content: Text(
        [
          l10n.removeSessionBody,
          if (corners) l10n.removeSessionCorners,
        ].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('removeSessionConfirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.removeSessionConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
