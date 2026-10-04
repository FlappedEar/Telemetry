// The driver's corrections to a day's track segments (FET-34), as Overlays'
// segment review applies them (AnalysisControllerSegmentReview.cpp, KAN-49):
// each edit replaces the run's whole `trackSegments` with the result of
// track_segment_editing.dart, and a bounded history undoes and redoes them.
// The edits are kept here until the day is saved, which writes them as the
// run's approved segments (dayDocument's `trackSegments`); approved segments
// are never replaced by automatic ones on a later save. Restoring the
// automatic segments removes the group's approved segments, so the best lap's
// proposals are approved again, as for a new day.
//
// The optional proposal review (FET-56, day_segment_review.dart) approves
// proposals into the same `trackSegments` and stores rejections in the run's
// `trackSegmentReview`, as Overlays does (setSegmentProposalRejected, KAN-50);
// both go through the same history, so a rejection is undone like an edit.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart' show makeTrackSegment;

import '../analysis/track_segment_editing.dart';
import '../analysis/track_segment_review.dart';
import 'day_segment_review.dart';
import 'day_theoretical_best.dart';

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

List<Map<String, Object?>> _segmentsOf(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map<String, Object?>) item,
];

/// The name of the second part of a split segment, as Overlays names it.
String splitSegmentName(String name) => '${name.length > 150 ? name.substring(0, 150) : name} (2)';

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || !_sameJson(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; ++i) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Why a review action, an undo or a redo was not done, as a code the app
/// maps to its own text; [message] is the English text.
enum SegmentChangeIssue {
  saving('The day is being saved.'),
  segmentsUnavailable('The segments can be edited once the theoretical best is calculated.'),
  notReady('The proposals are not ready yet.'),
  noLongerAvailable('This proposal is no longer available.'),
  notOpen('Only open proposals can be rejected.'),
  notStored('The rejection cannot be stored.'),
  noneApproved('No proposal could be approved.'),
  nothingToUndo('Nothing to undo.'),
  nothingToRedo('Nothing to redo.'),
  historyCleared('The segments changed outside this editor, so the edit history was cleared.');

  const SegmentChangeIssue(this.message);

  final String message;
}

/// One change of a run's `trackSegments`, its `trackSegmentReview`, or both;
/// a null pair is a part the change leaves as it was. An empty review is no
/// review (the key is removed).
final class _Step {
  const _Step(this.runId, {this.before, this.after, this.reviewBefore, this.reviewAfter});

  final String runId;
  final List<Map<String, Object?>>? before;
  final List<Map<String, Object?>>? after;
  final Map<String, Object?>? reviewBefore;
  final Map<String, Object?>? reviewAfter;

  bool get changesSegments => before != null;
}

/// Unsaved segment edits of a day, by run id.
final class DaySegmentEdits {
  DaySegmentEdits({this.random});

  /// Mints the ids of split segments; secure when null.
  final math.Random? random;
  final Map<String, List<Map<String, Object?>>> _runs = {};
  final Map<String, Map<String, Object?>> _reviews = {};

  // Bounded like Overlays' SegmentEditHistory (50 steps).
  static const _historyLimit = 50;
  final List<_Step> _undo = [];
  final List<_Step> _redo = [];

  /// Each edited run's `trackSegments`; an empty list removes them.
  Map<String, List<Map<String, Object?>>> get runs => Map.unmodifiable(_runs);

  /// Each run's changed `trackSegmentReview` (the proposals rejected in the
  /// review); an empty map removes it.
  Map<String, Map<String, Object?>> get reviews => Map.unmodifiable(_reviews);
  bool get isEmpty => _runs.isEmpty && _reviews.isEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Whether the next undo or redo changes segments (and so the timing), not
  /// only review decisions.
  bool get undoChangesSegments => _undo.isNotEmpty && _undo.last.changesSegments;
  bool get redoChangesSegments => _redo.isNotEmpty && _redo.last.changesSegments;

  Map<String, Object?> _withEdits(Map<String, Object?> run) {
    final id = run['id'];
    final copy = {...run};
    if (_runs[id] case final segments?) copy['trackSegments'] = segments;
    if (_reviews[id] case final review?) {
      review.isEmpty ? copy.remove('trackSegmentReview') : copy['trackSegmentReview'] = review;
    }
    return copy;
  }

  /// [documentRuns] (a document's `event.runs`) with the edits applied, and
  /// a bare run for each edited run the document does not have yet.
  List<Object?> applyTo(Iterable<Object?> documentRuns) {
    final seen = <Object?>{};
    final result = <Object?>[
      for (final value in documentRuns)
        if (_object(value) case final run?
            when _runs.containsKey(run['id']) || _reviews.containsKey(run['id']))
          _withEdits(run)
        else
          value,
    ];
    for (final value in documentRuns) {
      seen.add(_object(value)?['id']);
    }
    for (final id in {..._runs.keys, ..._reviews.keys}) {
      if (!seen.contains(id)) result.add(_withEdits({'id': id}));
    }
    return result;
  }

  /// Keeps [result]'s automatic segments (proposed from the best lap
  /// because the group had none yet) as approved, as saving the day would,
  /// so the day's corners stay the same when sessions are added and the
  /// best lap moves. Not an edit: nothing to undo. [result] already carries
  /// this run's edits (an edit resets it), including a restore, which it
  /// replaces. Returns whether they were kept.
  bool keepAutomatic(DayTheoreticalBest result) {
    if (!result.automaticSegments ||
        result.state != DayTheoreticalBestState.ready ||
        result.segmentRunId.isEmpty ||
        result.runSegments.isEmpty) {
      return false;
    }
    _runs[result.segmentRunId] = [
      for (final segment in result.runSegments) {...segment},
    ];
    return true;
  }

  /// Forgets the edits once they are saved.
  void clear() {
    _runs.clear();
    _reviews.clear();
    _undo.clear();
    _redo.clear();
  }

  void _record(_Step step) {
    _redo.clear();
    _undo.add(step);
    while (_undo.length > _historyLimit) {
      _undo.removeAt(0);
    }
  }

  String _apply(DayTheoreticalBest result, SegmentEdit edit) {
    final segments = edit.segments;
    if (segments == null) return edit.error.isEmpty ? 'This edit is not possible.' : edit.error;
    if (!sameTrackSegments(result.runSegments, segments)) {
      _record(_Step(result.segmentRunId, before: result.runSegments, after: segments));
    }
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
    if (changed) {
      _undo.clear();
      _redo.clear();
    }
    return changed;
  }

  // The run [runId] of [documentRuns] with the edits applied.
  Map<String, Object?> _current(Iterable<Object?> documentRuns, String runId) {
    for (final value in applyTo(documentRuns)) {
      if (_object(value) case final run? when run['id'] == runId) return run;
    }
    return const {};
  }

  /// Rejects proposal [index] of [review] (or with [rejected] false, takes
  /// the rejection back), as Overlays' "Reject" and "Restore": only an open
  /// or rejected proposal, and stored in the run's `trackSegmentReview` with
  /// the other rejections. [result] gives the segments approved now and
  /// [documentRuns] the stored decisions. Returns why not, or null.
  SegmentChangeIssue? setRejected(
    DayTheoreticalBest result,
    DayProposalReview review,
    Iterable<Object?> documentRuns,
    int index, {
    bool rejected = true,
  }) {
    if (!review.ready || review.runId != result.segmentRunId) {
      return SegmentChangeIssue.notReady;
    }
    final stored = _object(_current(documentRuns, review.runId)['trackSegmentReview']);
    final items = review.items(result.runSegments, stored);
    if (index < 0 || index >= items.length) return SegmentChangeIssue.noLongerAvailable;
    final state = items[index].state;
    if (state != SegmentReviewState.proposed && state != SegmentReviewState.rejected) {
      return SegmentChangeIssue.notOpen;
    }
    final indexes = review.rejected(stored);
    rejected ? indexes.add(index) : indexes.remove(index);
    final ordered = indexes.toList()..sort();
    final proposals = review.proposals;
    final decisions = [
      for (final i in ordered)
        if (i >= 0 && i < proposals.length) proposals[i],
    ];
    final next = decisions.isEmpty
        ? <String, Object?>{}
        : makeTrackSegmentReview(review.groupId, decisions);
    if (decisions.isNotEmpty && next.isEmpty) return SegmentChangeIssue.notStored;
    final before = stored ?? const <String, Object?>{};
    if (_sameJson(before, next)) return null;
    _record(_Step(review.runId, reviewBefore: before, reviewAfter: next));
    _reviews[review.runId] = next;
    return null;
  }

  /// Approves every open proposal of [review] into the run's segments in
  /// order, whatever its boundary uncertainty, skipping any that would
  /// overlap or not validate (Overlays' "Approve all", KAN-136). Returns how
  /// many were approved, or why none.
  ({int approved, SegmentChangeIssue? issue}) approveAll(
    DayTheoreticalBest result,
    DayProposalReview review,
    Iterable<Object?> documentRuns, {
    math.Random? random,
  }) {
    final unavailable = _unavailable(result);
    if (unavailable != null) {
      return (approved: 0, issue: SegmentChangeIssue.segmentsUnavailable);
    }
    if (!review.ready || review.runId != result.segmentRunId) {
      return (approved: 0, issue: SegmentChangeIssue.notReady);
    }
    final stored = _object(_current(documentRuns, review.runId)['trackSegmentReview']);
    final items = review.items(result.runSegments, stored);
    Object? segments = result.runSegments;
    var approved = 0;
    for (final item in items) {
      if (item.state != SegmentReviewState.proposed) continue;
      final proposal = item.proposal;
      final segment = makeTrackSegment(
        proposal.type,
        proposal.name,
        proposal.start.progressMeters,
        proposal.end.progressMeters,
        review.groupId,
        random: random ?? this.random,
      );
      if (segment.isEmpty) continue;
      final next = withApprovedSegment(segments, segment, review.axisLengthMeters).segments;
      if (next == null) continue;
      segments = next;
      ++approved;
    }
    if (approved == 0) return (approved: 0, issue: SegmentChangeIssue.noneApproved);
    _apply(result, (segments: segments as List<Map<String, Object?>>, error: ''));
    return (approved: approved, issue: null);
  }

  SegmentChangeIssue? _step(Iterable<Object?> documentRuns, {required bool undo}) {
    final step = undo ? (_undo.isEmpty ? null : _undo.last) : (_redo.isEmpty ? null : _redo.last);
    if (step == null) {
      return undo ? SegmentChangeIssue.nothingToUndo : SegmentChangeIssue.nothingToRedo;
    }
    final run = _current(documentRuns, step.runId);
    // Never overwrite a change made outside this history.
    final segmentsExpected = undo ? step.after : step.before;
    final reviewExpected = undo ? step.reviewAfter : step.reviewBefore;
    if ((segmentsExpected != null &&
            !sameTrackSegments(_segmentsOf(run['trackSegments']), segmentsExpected)) ||
        (reviewExpected != null &&
            !_sameJson(
              _object(run['trackSegmentReview']) ?? const <String, Object?>{},
              reviewExpected,
            ))) {
      _undo.clear();
      _redo.clear();
      return SegmentChangeIssue.historyCleared;
    }
    if ((undo ? step.before : step.after) case final segments?) _runs[step.runId] = segments;
    if ((undo ? step.reviewBefore : step.reviewAfter) case final review?) {
      _reviews[step.runId] = review;
    }
    if (undo) {
      _redo.add(_undo.removeLast());
    } else {
      _undo.add(_redo.removeLast());
    }
    return null;
  }

  /// Undoes the last edit of [documentRuns]' segments.
  String undo(Iterable<Object?> documentRuns) => undoChange(documentRuns)?.message ?? '';

  /// Undoes the last edit, or says why not.
  SegmentChangeIssue? undoChange(Iterable<Object?> documentRuns) => _step(documentRuns, undo: true);

  /// Redoes the last undone edit.
  String redo(Iterable<Object?> documentRuns) => redoChange(documentRuns)?.message ?? '';

  /// Redoes the last undone edit, or says why not.
  SegmentChangeIssue? redoChange(Iterable<Object?> documentRuns) =>
      _step(documentRuns, undo: false);
}
