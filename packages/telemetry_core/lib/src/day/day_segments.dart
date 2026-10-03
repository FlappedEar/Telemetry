// The driver's corrections to a day's track segments (FET-34), as Overlays'
// segment review applies them (AnalysisControllerSegmentReview.cpp, KAN-49):
// each edit replaces the run's whole `trackSegments` with the result of
// track_segment_editing.dart, and a bounded history undoes and redoes them.
// The edits are kept here until the day is saved, which writes them as the
// run's approved segments (dayDocument's `trackSegments`); approved segments
// are never replaced by automatic ones on a later save. Restoring the
// automatic segments removes the group's approved segments, so the best lap's
// proposals are approved again, as for a new day.
import 'dart:math' as math;

import '../analysis/track_segment_editing.dart';
import '../analysis/track_segment_review.dart';
import 'day_theoretical_best.dart';

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

List<Map<String, Object?>> _segmentsOf(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map<String, Object?>) item,
];

/// The name of the second part of a split segment, as Overlays names it.
String splitSegmentName(String name) => '${name.length > 150 ? name.substring(0, 150) : name} (2)';

/// Unsaved segment edits of a day, by run id.
final class DaySegmentEdits {
  DaySegmentEdits({this.random});

  /// Mints the ids of split segments; secure when null.
  final math.Random? random;
  final Map<String, List<Map<String, Object?>>> _runs = {};
  final SegmentEditHistory _history = SegmentEditHistory();

  /// Each edited run's `trackSegments`; an empty list removes them.
  Map<String, List<Map<String, Object?>>> get runs => Map.unmodifiable(_runs);
  bool get isEmpty => _runs.isEmpty;
  bool get canUndo => _history.nextUndo != null;
  bool get canRedo => _history.nextRedo != null;

  /// [documentRuns] (a document's `event.runs`) with the edits applied, and
  /// a bare run for each edited run the document does not have yet.
  List<Object?> applyTo(Iterable<Object?> documentRuns) {
    final seen = <Object?>{};
    final result = <Object?>[
      for (final value in documentRuns)
        if (_object(value) case final run? when _runs.containsKey(run['id']))
          {...run, 'trackSegments': _runs[run['id']]}
        else
          value,
    ];
    for (final value in documentRuns) {
      seen.add(_object(value)?['id']);
    }
    for (final entry in _runs.entries) {
      if (!seen.contains(entry.key)) result.add({'id': entry.key, 'trackSegments': entry.value});
    }
    return result;
  }

  /// Forgets the edits once they are saved.
  void clear() {
    _runs.clear();
    _history.clear();
  }

  String _apply(DayTheoreticalBest result, SegmentEdit edit) {
    final segments = edit.segments;
    if (segments == null) return edit.error.isEmpty ? 'This edit is not possible.' : edit.error;
    _history.record(result.segmentRunId, result.runSegments, segments);
    _runs[result.segmentRunId] = segments;
    return '';
  }

  String? _unavailable(DayTheoreticalBest result) =>
      result.state != DayTheoreticalBestState.ready ||
          result.segmentRunId.isEmpty ||
          !(result.axisLengthMeters > 0)
      ? 'The segments can be edited once the theoretical best is calculated.'
      : null;

  /// Renames, retypes or moves segment [id] of [result]'s segments. With
  /// [keepAdjacentJoined], a neighbour that shared a moved boundary moves
  /// with it. Returns why not, or an empty string.
  String edit(
    DayTheoreticalBest result,
    String id, {
    required String name,
    required String type,
    required double startMeters,
    required double endMeters,
    bool keepAdjacentJoined = true,
  }) =>
      _unavailable(result) ??
      _apply(
        result,
        withEditedSegment(
          result.runSegments,
          id,
          name,
          type,
          startMeters,
          endMeters,
          keepAdjacentJoined,
          result.axisLengthMeters,
        ),
      );

  /// Splits segment [id] at [atMeters] on the shared axis.
  String split(DayTheoreticalBest result, String id, double atMeters) {
    final unavailable = _unavailable(result);
    if (unavailable != null) return unavailable;
    var name = '';
    for (final segment in result.runSegments) {
      if (segment['id'] == id) name = segment['name'] as String;
    }
    return _apply(
      result,
      withSplitSegment(
        result.runSegments,
        id,
        atMeters,
        splitSegmentName(name),
        result.axisLengthMeters,
        random: random,
      ),
    );
  }

  /// Merges segments [id] and [otherId], which share a boundary.
  String merge(DayTheoreticalBest result, String id, String otherId) =>
      _unavailable(result) ??
      _apply(result, withMergedSegments(result.runSegments, id, otherId, result.axisLengthMeters));

  /// Removes segment [id]. The last segment of the group stays: restoring
  /// the automatic segments replaces it instead.
  String remove(DayTheoreticalBest result, String id) {
    final unavailable = _unavailable(result);
    if (unavailable != null) return unavailable;
    if (result.segments.length <= 1) {
      return 'The theoretical best needs at least one segment. Restore the automatic segments instead.';
    }
    final segments = withoutApprovedSegment(result.runSegments, id);
    return _apply(result, (
      segments: segments,
      error: segments == null ? 'This segment is no longer approved.' : '',
    ));
  }

  /// Removes the segments approved for [groupId] from every run of
  /// [documentRuns] (with the edits applied), so the best lap's proposals
  /// are approved again. Segments of other configurations stay. Returns
  /// whether anything changed; the edit history is cleared.
  bool restoreAutomatic(Iterable<Object?> documentRuns, String groupId) {
    var changed = false;
    for (final value in applyTo(documentRuns)) {
      final run = _object(value);
      final id = run?['id'];
      if (run == null || id is! String) continue;
      final stored = _segmentsOf(run['trackSegments']);
      final kept = [
        for (final segment in stored)
          if (segment['trackConfigurationReference'] != groupId) segment,
      ];
      if (kept.length == stored.length) continue;
      _runs[id] = kept;
      changed = true;
    }
    if (changed) _history.clear();
    return changed;
  }

  String _step(Iterable<Object?> documentRuns, {required bool undo}) {
    final step = undo ? _history.nextUndo : _history.nextRedo;
    if (step == null) return undo ? 'Nothing to undo.' : 'Nothing to redo.';
    var current = <Map<String, Object?>>[];
    for (final value in applyTo(documentRuns)) {
      if (_object(value) case final run? when run['id'] == step.runId) {
        current = _segmentsOf(run['trackSegments']);
      }
    }
    // Never overwrite a change made outside this history.
    if (!sameTrackSegments(current, undo ? step.after : step.before)) {
      _history.clear();
      return 'The segments changed outside this editor, so the edit history was cleared.';
    }
    _runs[step.runId] = undo ? step.before : step.after;
    undo ? _history.commitUndo() : _history.commitRedo();
    return '';
  }

  /// Undoes the last edit of [documentRuns]' segments.
  String undo(Iterable<Object?> documentRuns) => _step(documentRuns, undo: true);

  /// Redoes the last undone edit.
  String redo(Iterable<Object?> documentRuns) => _step(documentRuns, undo: false);
}
