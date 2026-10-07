import 'package:telemetry_core/telemetry_core.dart';

import '../profile/profile_library.dart';
import 'reference_lap.dart';

/// Keeps a day's reference lap in the driver profile (FET-276, the owner's
/// choice of 2026-10-07): on the day's entry, by recording id and lap
/// number. A recording file is copied into the profile's `Recordings`
/// folder and kept by the copy's name, never as the path it had on this
/// computer; a lap of another day of the profile is kept as that day's
/// event id. Nothing is kept in the day file.
final class ProfileReferenceStore implements ReferenceStore {
  const ProfileReferenceStore(this.library, {required this.keepsDay});

  final ProfileLibrary library;

  /// Whether the day is kept in the profile, or will be (a new day is
  /// listed once it is saved): a day saved elsewhere has no entry there
  /// for the reference.
  final bool Function() keepsDay;

  @override
  Future<ReferenceChoice?> restore(String eventId) async {
    // In turn with the changes of references asked for before: a reference
    // being copied or cleared when the day was closed is seen as it ends.
    final reference = await library.restoreReference(eventId);
    switch (reference) {
      case null:
        return null;
      case final ProfileReferenceFile file:
        return ReferenceChoice(
          source: ReferenceFile(
            // Built from a checked hash and extension; null only for a
            // reference this version would not have kept.
            library.referenceFilePath(file) ?? '',
            label: file.name.isEmpty ? file.recordingId : file.name,
            expectedBytes: file.bytes,
          ),
          recordingId: file.recordingId,
          lapNumber: file.lapNumber,
        );
      case final ProfileReferenceDay day:
        final other = library.profile?.day(day.eventId);
        return ReferenceChoice(
          source: ReferenceProfileDay(
            // Empty when the day is no longer in the profile: the
            // reference is kept and says so.
            path: other == null ? '' : library.pathOf(other) ?? '',
            eventId: day.eventId,
            dayName: other?.name ?? day.name,
          ),
          recordingId: day.recordingId,
          lapNumber: day.lapNumber,
        );
    }
  }

  @override
  Future<bool> keep(String eventId, ReferenceChoice? choice) {
    // Asked of the library at once, not after an await, so that what is
    // kept and restored follows the order the page asked in.
    switch (choice?.source) {
      case null:
        return library.clearReference(eventId, when: keepsDay);
      case final ReferenceFile file:
        return library.setFileReference(
          eventId,
          source: file.path,
          name: file.name,
          recordingId: choice!.recordingId,
          lapNumber: choice.lapNumber,
          when: keepsDay,
        );
      case final ReferenceProfileDay day:
        return library.setDayReference(
          eventId,
          otherEventId: day.eventId,
          name: day.dayName,
          recordingId: choice!.recordingId,
          lapNumber: choice.lapNumber,
          when: keepsDay,
        );
    }
  }
}
