import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// What a save wrote, as it was when the document was taken: the day's
/// name, its analysis and recordings, and the decisions that analysis was
/// computed under ([DayResultsController.decisionsKey]).
///
/// The driver profile's summary of a day is measured from this, never from
/// the live state, which can be edits ahead of the file while the writer
/// runs (audit F09). Immutable, so a late reader sees what the file holds.
final class SavedDay {
  SavedDay({
    required this.revision,
    required this.name,
    required this.analysis,
    required Map<String, TelemetrySession?> recordings,
    required this.decisionsKey,
    this.theoreticalBest,
  }) : recordings = Map.unmodifiable(recordings);

  /// The controller's revision the document was taken at.
  final int revision;
  final String name;
  final DayAnalysis analysis;

  /// Each run's recording by run id.
  final Map<String, TelemetrySession?> recordings;

  /// The decisions [analysis] stood under.
  final List<int> decisionsKey;

  /// The theoretical best worked out under [decisionsKey] when the document
  /// was taken; null when it was not (yet).
  final DayTheoreticalBest? theoreticalBest;
}

/// Which [SavedDay] stands for the day in the file: the day as opened, then
/// as each successful save wrote it. Held by the day's controller, which
/// takes the snapshots.
final class SavedDayTracker {
  SavedDay? _day;

  /// The day as the file holds it; null for a day never saved and for one
  /// restored with changes the file does not hold.
  SavedDay? get day => _day;

  /// The day as opened from its file, with no changes since.
  void opened(SavedDay taken) => _day = taken;

  /// A save of [taken] reached the file.
  void saved(SavedDay taken) => _day = taken;

  /// Saving may have approved automatic segments, which the decisions key
  /// reads, without changing the analysis. With the day unchanged since the
  /// document was taken, the caller gives the [key] it stands under now;
  /// with [dropBest], the theoretical best taken with the save goes, as it
  /// was worked out on the automatic segments: the one worked out again
  /// under the approved segments replaces it.
  void afterSave({List<int>? key, bool dropBest = false}) {
    final saved = _day;
    if (saved == null) return;
    _day = SavedDay(
      revision: saved.revision,
      name: saved.name,
      analysis: saved.analysis,
      recordings: saved.recordings,
      decisionsKey: key ?? saved.decisionsKey,
      theoreticalBest: dropBest ? null : saved.theoreticalBest,
    );
  }

  /// The theoretical best for the saved day: the [live] one when it was
  /// worked out ([liveKey]) under the decisions the saved day stands under
  /// and is not being calculated again, else the one the save took; null
  /// when there is none.
  DayTheoreticalBest? bestFor(
    DayTheoreticalBest? live,
    List<int> liveKey, {
    required bool loading,
  }) {
    final saved = _day;
    if (saved == null) return null;
    if (!loading && live != null && listEquals(liveKey, saved.decisionsKey)) {
      return live;
    }
    return saved.theoreticalBest;
  }
}
