// The reference lap a day uses (FET-276, follow-up to FET-175): a friend's or
// an instructor's recording, or a lap from another day of the profile,
// kept on the day in the driver profile so it comes back when the day is
// opened again. Only the choice is kept here: the recording of a file
// reference is a copy in the profile's `Recordings` folder (content
// addressed, as a bundle keeps recordings), never a path on the user's
// computer.
part of 'driver_profile.dart';

/// The key of a day's reference in the profile.
const _referenceKey = 'reference';

/// The most distinct reference recordings the profile keeps copies of
/// (one copy however many days use it).
const maximumReferenceFiles = 32;

/// The largest reference recording kept: the size the importers read at
/// most (`VboLimits.maximumFileBytes`; an RCZ archive is also at most
/// 128 MiB), so a larger file could not be read again anyway.
const maximumReferenceFileBytes = 128 * 1024 * 1024;

/// The most all the reference recordings together take in the profile.
const maximumReferenceBytes = 512 * 1024 * 1024;

/// The largest lap number a reference names.
const maximumReferenceLapNumber = 100000;

/// The longest file name a reference keeps for display; longer is cut.
const maximumReferenceNameCharacters = 255;

/// The extensions of the recordings a reference keeps copies of, lower case.
const referenceFileExtensions = ['.vbo', '.rcz'];

/// What went wrong keeping a reference, for the app to say in words.
enum ProfileReferenceProblem {
  /// The profile already keeps [maximumReferenceFiles] reference recordings.
  tooManyFiles,

  /// All reference recordings together would pass [maximumReferenceBytes].
  tooMuch,

  /// The recording is larger than [maximumReferenceFileBytes].
  fileTooLarge,

  /// The recording is empty.
  fileEmpty,

  /// Not a `.vbo` or `.rcz` file.
  fileType,

  /// The recording could not be read or copied.
  fileUnreadable,

  /// The profile could not be written, or the day is not in it.
  notWritten,

  /// The reference itself is not one the profile can hold.
  invalid,
}

/// A reference that could not be kept.
final class ProfileReferenceError implements Exception {
  const ProfileReferenceError(this.problem, this.message);

  final ProfileReferenceProblem problem;
  final String message;

  @override
  String toString() => 'ProfileReferenceError: $message';
}

/// The reference lap of a day, as the profile keeps it: which source, which
/// recording of it and which lap on today's line. The lap is named by
/// [recordingId] and [lapNumber], never by the recording's position in its
/// source, which shifts when one of a day's recordings is missing.
sealed class ProfileReference {
  ProfileReference({
    required this.recordingId,
    required this.lapNumber,
    this.name = '',
    Map<String, Object?> unknown = const {},
  }) : unknown = Map.unmodifiable(unknown);

  /// The run id of the other day's session, or the recording's file name.
  final String recordingId;

  /// The lap's number in that recording, as it is timed on today's line.
  final int lapNumber;

  /// The file's name, or the other day's name when it was chosen, as the
  /// reference is named when its source is not found.
  final String name;

  /// Keys this version does not know, kept as read.
  final Map<String, Object?> unknown;
}

/// A recording file, kept as a copy in the profile's `Recordings` folder
/// under the SHA-256 of its content.
final class ProfileReferenceFile extends ProfileReference {
  ProfileReferenceFile({
    required super.recordingId,
    required super.lapNumber,
    required this.sha256,
    required this.extension,
    required this.bytes,
    super.name,
    super.unknown,
  });

  /// The content's SHA-256, 64 lower-case hex digits.
  final String sha256;

  /// `.vbo` or `.rcz`.
  final String extension;

  /// The copy's size in bytes.
  final int bytes;

  /// The copy's name in the profile's `Recordings` folder.
  String get fileName => '$sha256$extension';

  /// The copy, relative to the profile's folder.
  String get file => 'Recordings/$fileName';

  /// This file with another lap chosen.
  ProfileReferenceFile withLap(String recordingId, int lapNumber) => ProfileReferenceFile(
    recordingId: recordingId,
    lapNumber: lapNumber,
    sha256: sha256,
    extension: extension,
    bytes: bytes,
    name: name,
    unknown: unknown,
  );
}

/// A lap of another day of the profile, kept as that day's event id: it
/// works while the day is in the profile.
final class ProfileReferenceDay extends ProfileReference {
  ProfileReferenceDay({
    required super.recordingId,
    required super.lapNumber,
    required this.eventId,
    super.name,
    super.unknown,
  });

  /// The other day's `event.id`.
  final String eventId;
}

final _sha256 = RegExp(r'^[0-9a-f]{64}$');

/// A reference's text kept: no NUL, cut to [maximumProfileTextCharacters].
String _referenceText(String value) {
  final text = value.replaceAll('\u0000', '').trim();
  return text.length > maximumProfileTextCharacters
      ? text.substring(0, maximumProfileTextCharacters)
      : text;
}

/// [name] as a reference keeps it for display.
String _referenceName(String name) {
  final text = _referenceText(name);
  return text.length > maximumReferenceNameCharacters
      ? text.substring(0, maximumReferenceNameCharacters)
      : text;
}

Map<String, Object?> _encodeReference(ProfileReference reference) => {
  ...reference.unknown,
  'kind': switch (reference) {
    ProfileReferenceFile() => 'file',
    ProfileReferenceDay() => 'day',
  },
  if (reference.name.isNotEmpty) 'name': reference.name,
  'recordingId': reference.recordingId,
  'lapNumber': reference.lapNumber,
  ...switch (reference) {
    ProfileReferenceFile() => {
      'sha256': reference.sha256,
      'extension': reference.extension,
      'bytes': reference.bytes,
    },
    ProfileReferenceDay() => {'eventId': reference.eventId},
  },
};

/// The reference in [value], a day's `reference`, or null when there is
/// none or this version cannot read it (a kind it does not know, a value
/// out of range, a hash or extension that is not one). Never an error: the
/// object stays in the day's unknown keys and is written back unchanged.
/// [dayId] is the day it belongs to, which it cannot refer to itself.
ProfileReference? _reference(Object? value, String dayId) {
  if (value is! Map<String, Object?>) return null;
  final lap = value['lapNumber'];
  final recordingId = value['recordingId'];
  final name = value['name'] ?? '';
  if (lap is! int ||
      lap < 1 ||
      lap > maximumReferenceLapNumber ||
      recordingId is! String ||
      recordingId.trim().isEmpty ||
      recordingId.length > maximumProfileTextCharacters ||
      recordingId.contains('\u0000') ||
      name is! String ||
      name.length > maximumProfileTextCharacters ||
      name.contains('\u0000')) {
    return null;
  }
  switch (value['kind']) {
    case 'file':
      final sha = value['sha256'];
      final extension = value['extension'];
      final bytes = value['bytes'];
      if (sha is! String ||
          !_sha256.hasMatch(sha) ||
          extension is! String ||
          !referenceFileExtensions.contains(extension) ||
          bytes is! int ||
          bytes < 1 ||
          bytes > maximumReferenceFileBytes) {
        return null;
      }
      return ProfileReferenceFile(
        recordingId: recordingId,
        lapNumber: lap,
        sha256: sha,
        extension: extension,
        bytes: bytes,
        name: name,
        unknown: _without(value, const [
          'kind',
          'name',
          'recordingId',
          'lapNumber',
          'sha256',
          'extension',
          'bytes',
        ]),
      );
    case 'day':
      final eventId = value['eventId'];
      if (eventId is! String ||
          eventId.trim().isEmpty ||
          eventId.length > maximumProfileTextCharacters ||
          eventId.contains('\u0000') ||
          eventId == dayId) {
        return null;
      }
      return ProfileReferenceDay(
        recordingId: recordingId,
        lapNumber: lap,
        eventId: eventId,
        name: name,
        unknown: _without(value, const ['kind', 'name', 'recordingId', 'lapNumber', 'eventId']),
      );
  }
  return null;
}

/// The copies of reference recordings [profile] keeps, by file name
/// (`<sha256>.<extension>`) and their size, leaving out day [except]'s own.
Map<String, int> profileReferenceFiles(DriverProfile profile, {String? except}) => {
  for (final day in profile.days)
    if (day.eventId != except)
      if (day.reference case final ProfileReferenceFile file) file.fileName: file.bytes,
};

/// [reference] as a day keeps it, checked: the lap, the names, and for a
/// file the hash, extension and size. Throws [ProfileReferenceError].
ProfileReference _checkedReference(ProfileReference reference, String dayId) {
  final id = _referenceText(reference.recordingId);
  if (id.isEmpty || reference.lapNumber < 1 || reference.lapNumber > maximumReferenceLapNumber) {
    throw const ProfileReferenceError(
      ProfileReferenceProblem.invalid,
      'The reference names no recording or lap.',
    );
  }
  final name = _referenceName(reference.name);
  switch (reference) {
    case ProfileReferenceFile():
      if (!_sha256.hasMatch(reference.sha256) ||
          !referenceFileExtensions.contains(reference.extension)) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.fileType,
          'The reference recording is not a VBO or RCZ file.',
        );
      }
      if (reference.bytes < 1) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.fileEmpty,
          'The reference recording is empty.',
        );
      }
      if (reference.bytes > maximumReferenceFileBytes) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.fileTooLarge,
          'The reference recording is too large.',
        );
      }
      return ProfileReferenceFile(
        recordingId: id,
        lapNumber: reference.lapNumber,
        sha256: reference.sha256,
        extension: reference.extension,
        bytes: reference.bytes,
        name: name,
        unknown: reference.unknown,
      );
    case ProfileReferenceDay():
      final eventId = _referenceText(reference.eventId);
      if (eventId.isEmpty || eventId == dayId) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.invalid,
          'A day cannot be its own reference.',
        );
      }
      return ProfileReferenceDay(
        recordingId: id,
        lapNumber: reference.lapNumber,
        eventId: eventId,
        name: name,
        unknown: reference.unknown,
      );
  }
}

/// [reference] as day [eventId] of [profile] would keep it, after checking
/// it against the limits ([maximumReferenceFiles], [maximumReferenceBytes],
/// [maximumReferenceFileBytes]): a file reference counts its recording once
/// however many days use it. Throws [ProfileReferenceError].
ProfileReference checkProfileReference(
  DriverProfile profile,
  String eventId,
  ProfileReference reference,
) {
  final kept = _checkedReference(reference, eventId);
  if (kept is ProfileReferenceFile) {
    final others = profileReferenceFiles(profile, except: eventId);
    if (!others.containsKey(kept.fileName)) {
      if (others.length >= maximumReferenceFiles) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.tooManyFiles,
          'The profile already keeps the most reference recordings.',
        );
      }
      if (others.values.fold(0, (sum, bytes) => sum + bytes) + kept.bytes > maximumReferenceBytes) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.tooMuch,
          'The reference recordings would take too much room in the profile.',
        );
      }
    }
  }
  return kept;
}

/// [profile] with [reference] as day [eventId]'s reference lap; null
/// forgets it (an unreadable `reference` kept from a newer version goes
/// too). Unchanged when the day is not in the profile or nothing changes.
/// Throws [ProfileReferenceError] for what [checkProfileReference] refuses,
/// and the profile is unchanged. The copy of a recording itself is made
/// by [keepReferenceFile], before this.
DriverProfile setProfileDayReference(
  DriverProfile profile,
  String eventId,
  ProfileReference? reference,
) {
  final day = profile.day(eventId);
  if (day == null) return profile;
  final kept = reference == null ? null : checkProfileReference(profile, eventId, reference);
  if (kept == null
      ? day.reference == null && !day.unknown.containsKey(_referenceKey)
      : day.reference != null &&
            jsonEncode(_encodeReference(day.reference!)) == jsonEncode(_encodeReference(kept))) {
    return profile;
  }
  final entry = day._copy(reference: kept, replaceReference: true);
  _verified(_encodeDay(entry), _day);
  return profile._copy(
    days: [for (final other in profile.days) other.eventId == eventId ? entry : other],
  );
}

/// [profile] without the reference recording copies [drop] names (by file
/// name), forgetting the references that used them: such a day keeps its
/// other fields. Used when a copy cannot be placed. The same [profile] when
/// nothing is dropped.
DriverProfile removeProfileReferenceFiles(
  DriverProfile profile,
  Set<String> drop, {
  Set<String>? only,
}) {
  var changed = false;
  final days = [
    for (final day in profile.days)
      if (day.reference case final ProfileReferenceFile file
          when drop.contains(file.fileName) && (only == null || only.contains(day.eventId)))
        () {
          changed = true;
          return day._copy(replaceReference: true);
        }()
      else
        day,
  ];
  return changed ? profile._copy(days: days) : profile;
}
