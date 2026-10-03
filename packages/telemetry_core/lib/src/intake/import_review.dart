// The reviewed import of FlappedEar Overlays (BatchImportDialog.qml and
// DocumentControllerImport.cpp `confirmBatchImport`) (FET-58): before an
// import is committed, every recording found can be imported as a run of
// its own, skipped, or made the same run as another recording, which then
// supplies the run's laps and keeps the other as its alternative source.
import 'import_plan.dart';

/// The user's choice for each ready recording of a review, by run id: the
/// run id of the recording itself (a run of its own), [skipRecording], or
/// the run id of the run it belongs to ("Same run as"). As Overlays'
/// `choices` (`proposalId` to `groupId`).
typedef ImportChoices = Map<String, String>;

/// The choice that skips a recording (Overlays' empty `groupId`).
const String skipRecording = '';

/// Why [checkImportChoices] refuses a review.
enum ImportChoiceProblem {
  /// A ready recording has no choice, or a choice names a recording that was
  /// not reviewed: the recordings changed since the review.
  changed,

  /// A "Same run as" names a recording that is skipped or itself the same
  /// run as another one. Overlays: "A grouped source must point directly to
  /// a separate primary run".
  targetNotRun,

  /// A run would get more than [maximumRecordingsPerReviewedRun] recordings.
  tooManyRecordings,

  /// Every recording is skipped. Overlays: "Select at least one new run."
  nothingSelected,
}

/// The recordings a reviewed run may have: its own and one alternative, as
/// this app fuses one alternative into a run (Overlays allows eight).
const int maximumRecordingsPerReviewedRun = 2;

/// What happens to each recording of [plan] without review: each run is its
/// own, except an RCZ of a VBO's drive ([automaticVboPrimaries]).
ImportChoices automaticImportChoices(TelemetryImportPlan plan) => automaticVboPrimaries(plan);

/// Checks [choices] for the ready recordings [runIds] of a review, as
/// Overlays' `confirmBatchImport` does; null when they can be committed.
///
/// [runs] are runs that exist already (the day's sessions when adding to a
/// day): a recording may be the same run as one of them, which then counts
/// as a run of its own. [alreadyGrouped] are those of them that have an
/// alternative recording already.
ImportChoiceProblem? checkImportChoices(
  Iterable<String> runIds,
  ImportChoices choices, {
  Set<String> runs = const {},
  Set<String> alreadyGrouped = const {},
}) {
  final reviewed = runIds.toSet();
  if (reviewed.length != choices.length || !reviewed.every(choices.containsKey)) {
    return ImportChoiceProblem.changed;
  }
  final members = <String, int>{};
  var selected = false;
  for (final MapEntry(key: id, value: group) in choices.entries) {
    if (group == skipRecording) continue;
    selected = true;
    if (group == id) continue;
    if (runs.contains(group)) {
      if (alreadyGrouped.contains(group)) return ImportChoiceProblem.tooManyRecordings;
    } else if (!reviewed.contains(group)) {
      return ImportChoiceProblem.changed;
    } else if (choices[group] != group) {
      return ImportChoiceProblem.targetNotRun;
    }
    final count = members[group] = (members[group] ?? 0) + 1;
    if (count + 1 > maximumRecordingsPerReviewedRun) return ImportChoiceProblem.tooManyRecordings;
  }
  return selected ? null : ImportChoiceProblem.nothingSelected;
}

/// [choices] with every recording that is the same run as one that no longer
/// is a run of its own (skipped, or itself made the same run as another)
/// made a run of its own again, as a review does when the user changes the
/// run another recording belonged to.
ImportChoices releaseOrphanedChoices(ImportChoices choices, {Set<String> runs = const {}}) {
  final result = Map.of(choices);
  for (final MapEntry(key: id, value: group) in choices.entries) {
    if (group == skipRecording || group == id || runs.contains(group)) continue;
    if (result[group] != group) result[id] = id;
  }
  return result;
}

/// The runs of [plan] that [choices] import as runs of their own, in plan
/// order.
List<TelemetryRunProposal> chosenRuns(TelemetryImportPlan plan, ImportChoices choices) => [
  for (final run in plan.runs)
    if (choices[run.id] == run.id) run,
];
