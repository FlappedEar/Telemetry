// What the user edits of a day: each session's name, notes, conditions and
// setup changes, its structured setup (FET-188, [RunSetup]), and the day's
// name (FET-52). The rules and the stored form
// follow FlappedEar Overlays' AnalysisController::updateRunMetadata and the
// event validation of EventProjectCodec, so a document edited in either app
// reads the same in the other.
import 'package:fetproject/fetproject.dart' as fet;

import 'run_setup.dart';

/// The longest session or day name, in UTF-16 code units.
const maximumDetailsNameCharacters = fet.maximumNameCharacters;

/// The longest note, conditions or setup changes, in UTF-16 code units.
const maximumDetailsTextCharacters = fet.maximumStringCharacters;

/// The document keys of a session's free text, in Overlays' order.
const runMetadataTextKeys = ['notes', 'conditions', 'setupChanges'];

/// A session's name, notes, conditions, setup changes and structured setup
/// as the user edits them. Empty text is "not recorded".
final class RunMetadata {
  const RunMetadata({
    required this.name,
    this.notes = '',
    this.conditions = '',
    this.setupChanges = '',
    this.setup = const RunSetup(),
  });

  /// [run]'s metadata as a document stores it (`event.runs[]`); a missing or
  /// null text is empty.
  factory RunMetadata.fromRun(Map<String, Object?> run) {
    String text(Object? value) => value is String ? value : '';
    return RunMetadata(
      name: text(run['name']),
      notes: text(run['notes']),
      conditions: text(run['conditions']),
      setupChanges: text(run['setupChanges']),
      setup: RunSetup.fromJson(run[runSetupKey]),
    );
  }

  final String name;
  final String notes;
  final String conditions;
  final String setupChanges;

  /// The structured setup (`setup`), which only Telemetry shows.
  final RunSetup setup;

  String _text(String key) => switch (key) {
    'notes' => notes,
    'conditions' => conditions,
    _ => setupChanges,
  };

  @override
  bool operator ==(Object other) =>
      other is RunMetadata &&
      other.name == name &&
      other.notes == notes &&
      other.conditions == conditions &&
      other.setupChanges == setupChanges &&
      other.setup == setup;

  @override
  int get hashCode => Object.hash(name, notes, conditions, setupChanges, setup);
}

/// Why [metadata] cannot be saved, or null when it can: the name must not be
/// blank and is at most 160 characters (UTF-16 code units, as Overlays counts
/// them); every text is at most 4096 and contains no NUL; the setup has no
/// [runSetupProblem].
String? runMetadataProblem(RunMetadata metadata) {
  if (metadata.name.trim().isEmpty) return 'The session needs a name.';
  if (metadata.name.length > fet.maximumNameCharacters) {
    return 'The name is longer than ${fet.maximumNameCharacters} characters.';
  }
  for (final text in [metadata.name, metadata.notes, metadata.conditions, metadata.setupChanges]) {
    if (text.length > fet.maximumStringCharacters) {
      return 'A text is longer than ${fet.maximumStringCharacters} characters.';
    }
    if (text.contains('\u0000')) return 'A text contains a NUL character.';
  }
  return runSetupProblem(metadata.setup);
}

/// Writes [metadata] into [run] (a document run) as Overlays does: the name
/// trimmed; each text as written, or null when blank; a text equal to what
/// is stored (a missing one reads as empty) is left alone, so an unchanged
/// record never gains keys; the setup is written by [applyRunSetup], which
/// Overlays does not do. Returns whether [run] changed. [metadata] must
/// have no [runMetadataProblem].
bool applyRunMetadata(Map<String, Object?> run, RunMetadata metadata) {
  assert(runMetadataProblem(metadata) == null);
  var changed = false;
  final name = metadata.name.trim();
  if (run['name'] != name) {
    run['name'] = name;
    changed = true;
  }
  for (final key in runMetadataTextKeys) {
    final value = metadata._text(key);
    final stored = run[key];
    // Qt's QJsonValue::toString(): a value that is not a string reads "".
    if ((stored is String ? stored : '') == value) continue;
    final next = value.trim().isEmpty ? null : value;
    if (run.containsKey(key) && stored == next) continue;
    run[key] = next;
    changed = true;
  }
  if (applyRunSetup(run, metadata.setup)) changed = true;
  return changed;
}

/// [runs] (a document's `event.runs`) with [edits] applied, by run id: an
/// edited run is a copy, the others are as they were. A run edited that is
/// not in [runs] is added as `{'id': ...}` with its metadata, so the edits of
/// a day not saved yet read like those of a saved one.
List<Object?> applyRunMetadataEdits(List<Object?> runs, Map<String, RunMetadata> edits) {
  if (edits.isEmpty) return runs;
  final seen = <String>{};
  final result = <Object?>[];
  for (final value in runs) {
    final id = value is Map<String, Object?> ? value['id'] : null;
    final edit = id is String ? edits[id] : null;
    if (edit == null) {
      result.add(value);
      continue;
    }
    seen.add(id! as String);
    final copy = {...value! as Map<String, Object?>};
    applyRunMetadata(copy, edit);
    result.add(copy);
  }
  for (final MapEntry(:key, :value) in edits.entries) {
    if (seen.contains(key)) continue;
    final run = <String, Object?>{'id': key};
    applyRunMetadata(run, value);
    result.add(run);
  }
  return result;
}

/// Why [name] cannot be the day's name (`event.name`), or null: it must not
/// be blank, at most 160 characters once trimmed, and contain no NUL, as
/// Overlays validates an event's name.
String? dayNameProblem(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'The day needs a name.';
  if (trimmed.length > fet.maximumNameCharacters) {
    return 'The name is longer than ${fet.maximumNameCharacters} characters.';
  }
  if (trimmed.contains('\u0000')) return 'The name contains a NUL character.';
  return null;
}
