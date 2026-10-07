import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../circuits/circuit_directory.dart';

/// The name of the driver profile file in the profile folder.
const profileFileName = 'driver.feprofile';

/// The folder in the profile folder that holds the days.
const profileDaysFolder = 'Days';

/// Where the driver profile lives: a folder holding [profileFileName] and
/// the days. Replaced by a fake in widget tests.
abstract interface class ProfileStore {
  /// The profile folder; null when there is none (tests, web).
  Future<String?> folder();
}

/// `Profile` in the app's support folder. Off in `flutter test`.
final class PlatformProfileStore implements ProfileStore {
  const PlatformProfileStore();

  static bool get _enabled =>
      !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Future<String?> folder() async {
    if (!_enabled) return null;
    try {
      return p.join((await getApplicationSupportDirectory()).path, 'Profile');
    } on Exception {
      return null;
    }
  }
}

/// A profile folder chosen by a test.
final class FolderProfileStore implements ProfileStore {
  const FolderProfileStore(this.path);

  final String path;

  @override
  Future<String?> folder() async => path;
}

/// Folders holding only recording copies the app made, besides the
/// profile's own `Recordings`: on Android the folders files shared to or
/// picked in the app are copied to (`incoming` and `picked` in its files
/// folder, see MainActivity.copyBatch), on iOS the Inbox shared files
/// arrive in. A recording there that no day uses any more is deleted with
/// the last day using it. None elsewhere and in `flutter test`.
Future<List<String>> platformOwnedRecordingFolders() async {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
    return const [];
  }
  try {
    if (Platform.isAndroid) {
      final files = (await getApplicationSupportDirectory()).path;
      return [p.join(files, 'incoming'), p.join(files, 'picked')];
    }
    if (Platform.isIOS) {
      return [p.join((await getApplicationDocumentsDirectory()).path, 'Inbox')];
    }
  } on Exception {
    // None.
  }
  return const [];
}

/// The day of [eventId]'s file in [folder]'s days.
String profileDayPath(String folder, String eventId) =>
    p.join(folder, profileDaysFolder, '$eventId.fetproject');

/// The driver profile the app keeps: loaded once, changed by the day pages
/// and the library page, and written after each change, one write at a time
/// and off the UI thread.
///
/// A profile file that cannot be read is never written over: it is kept
/// beside as `driver.feprofile.unreadable-<time>` and a new profile starts.
class ProfileLibrary extends ChangeNotifier {
  ProfileLibrary({
    this.store = const PlatformProfileStore(),
    required this.defaultCarName,
    required this.defaultTrackName,
    this.background = Isolate.run,
    this.ownedRecordingFolders = platformOwnedRecordingFolders,
  });

  /// Folders besides the profile's own `Recordings` where every recording
  /// is a copy the app made ([platformOwnedRecordingFolders]).
  final Future<List<String>> Function() ownedRecordingFolders;

  /// Runs reading and writing the profile off the UI thread; widget tests
  /// run it in place, on their fake clock.
  final Future<R> Function<R>(FutureOr<R> Function() computation) background;

  final ProfileStore store;

  /// The name of the first car, made when the first day is added.
  final String defaultCarName;

  /// The name of a new track, from its number in the profile ("Track 2").
  final String Function(int number) defaultTrackName;

  DriverProfile? _profile;
  String? _folder;
  Future<void>? _loading;
  Future<void> _writes = Future.value();

  /// The profile; null until [load] finished or when there is no folder.
  DriverProfile? get profile => _profile;

  /// The profile folder; null until [load] finished or when there is none.
  String? get folder => _folder;

  /// Whether days are kept in the profile.
  bool get available => _folder != null && _profile != null;

  bool _loaded = false;

  /// Whether [load] finished, with or without a profile.
  bool get loaded => _loaded;

  /// Reads the profile once; later calls wait for the first. Once read, a
  /// call returns a future of the caller's own zone.
  Future<void> load() => _loaded ? Future.value() : _loading ??= _load();

  Future<void> _load() async {
    try {
      await _read();
    } finally {
      _loaded = true;
      // Also when there is no profile, so a page waiting for it says so.
      notifyListeners();
    }
  }

  Future<void> _read() async {
    final folder = await store.folder();
    if (folder == null) return;
    final file = File(p.join(folder, profileFileName));
    DriverProfile profile;
    try {
      profile = file.existsSync()
          ? await background(() => decodeDriverProfile(file.readAsStringSync()))
          : DriverProfile.empty();
    } on ProfileFormatError catch (error) {
      debugPrint('Driver profile not read: ${error.message}');
      // A newer version's profile is whole: days are saved as before, with
      // no library, until that version runs again.
      if (error.newerVersion) return;
      try {
        file.renameSync(
          '${file.path}.unreadable-${DateTime.now().millisecondsSinceEpoch}',
        );
      } on FileSystemException catch (error) {
        // Kept where it is; not written over (see below).
        debugPrint('Unreadable driver profile not moved: $error');
        return;
      }
      profile = DriverProfile.empty();
    } on Object catch (error) {
      // Not read this time (locked, say): left as it is, with no library
      // until the app starts again.
      debugPrint('Driver profile not read: $error');
      return;
    }
    _folder = folder;
    _profile = profile;
    await _recordUnlisted(folder, profile);
    notifyListeners();
  }

  /// Adds the days saved in the profile's days folder that the profile does
  /// not list, such as a day whose page was left before the profile was
  /// written, or a profile started again: by their name, until each is
  /// opened and its sessions are recorded.
  Future<void> _recordUnlisted(String folder, DriverProfile profile) async {
    final listed = {for (final day in profile.days) day.file};
    final List<({String eventId, String name, String file})> unlisted;
    try {
      unlisted = await background(_unlistedJob(folder, listed));
    } on Object catch (error) {
      debugPrint('Days folder not read: $error');
      return;
    }
    for (final day in unlisted) {
      _change(
        (profile) => profile.days.any((known) => known.eventId == day.eventId)
            ? profile
            : _withPendingReference(
                addDayToProfile(
                  profile,
                  ProfileDayInput(
                    eventId: day.eventId,
                    file: day.file,
                    name: day.name,
                  ),
                  defaultCarName: defaultCarName,
                  defaultTrackName: defaultTrackName(profile.tracks.length + 1),
                ),
                day.eventId,
              ),
      );
    }
  }

  // Built outside the instance so the isolate's closure holds only its
  // inputs.
  static List<({String eventId, String name, String file})> Function()
  _unlistedJob(String folder, Set<String> listed) =>
      () => _unlistedDays(folder, listed);

  static List<({String eventId, String name, String file})> _unlistedDays(
    String folder,
    Set<String> listed,
  ) {
    final days = Directory(p.join(folder, profileDaysFolder));
    if (!days.existsSync()) return const [];
    final found = <({String eventId, String name, String file})>[];
    for (final entry in days.listSync()) {
      if (entry is! File || p.extension(entry.path) != '.fetproject') continue;
      final file = p.relative(entry.path, from: folder).replaceAll(r'\', '/');
      if (listed.contains(file)) continue;
      try {
        final document = jsonDecode(entry.readAsStringSync());
        if (document case {
          'event': {'id': final String eventId, 'name': final String name},
        }) {
          found.add((eventId: eventId, name: name, file: file));
        }
      } on Object catch (error) {
        debugPrint('Day not listed in the profile: ${entry.path}: $error');
      }
    }
    return found;
  }

  /// Where the day of [eventId] is saved in the profile; null when days are
  /// not kept in a profile.
  Future<String?> dayPath(String eventId) async {
    await load();
    final folder = _folder;
    if (folder == null) return null;
    final path = profileDayPath(folder, eventId);
    // Saving writes the file only; its folder is made here.
    Directory(p.dirname(path)).createSync(recursive: true);
    return path;
  }

  /// Whether [path] is a day saved in the profile.
  bool holds(String path) {
    final folder = _folder;
    return folder != null &&
        p.isWithin(p.join(folder, profileDaysFolder), path);
  }

  /// The full path of [day]'s document.
  String? pathOf(ProfileDay day) {
    final folder = _folder;
    // The profile keeps '/' separators; the path uses the platform's.
    return folder == null ? null : p.joinAll([folder, ...day.file.split('/')]);
  }

  /// Records the day of [eventId] saved at [path] with [analysis] in the
  /// profile: a new day takes the last car and its track is recognised
  /// by its route. With its [recordings] and [theoreticalBest], what each
  /// session measured, and with [weather] (by run id) each session's
  /// weather ([ProfileDayInput.fromAnalysis]). With [setups] (by run id,
  /// each run's setup as the day was saved), each session's setup, which
  /// replaces the profile's; without it, the profile's are kept. The
  /// setups go to a day the profile already lists at once, without
  /// waiting for the measure, and are held as [givenSetups] meanwhile, so
  /// a measure that fails does not lose them. Does nothing for a day saved
  /// elsewhere.
  Future<void> recordDay({
    required String eventId,
    required String path,
    required String name,
    required DayAnalysis analysis,
    Map<String, TelemetrySession?>? recordings,
    DayTheoreticalBest? theoreticalBest,
    Map<String, ProfileWeather?>? weather,
    Map<String, ProfileSetup?>? setups,
  }) async {
    // A day deleted is not listed again by a page that still held it.
    if (_deleted.contains(eventId)) return;
    _keepWeather(eventId, weather);
    if (setups != null) {
      _setups[eventId] = Map.unmodifiable(setups);
      if (holds(path)) {
        _change((profile) => setProfileSessionSetups(profile, eventId, setups));
      }
    }
    // A [flush] right after waits for the day being measured and written.
    final measured = Completer<void>();
    _measuring.add(measured.future);
    try {
      await _recordDay(
        eventId: eventId,
        path: path,
        name: name,
        analysis: analysis,
        recordings: recordings,
        theoreticalBest: theoreticalBest,
        weather: weather,
        setups: setups,
      );
    } finally {
      _measuring.remove(measured.future);
      measured.complete();
    }
  }

  Future<void> _recordDay({
    required String eventId,
    required String path,
    required String name,
    required DayAnalysis analysis,
    Map<String, TelemetrySession?>? recordings,
    DayTheoreticalBest? theoreticalBest,
    Map<String, ProfileWeather?>? weather,
    Map<String, ProfileSetup?>? setups,
  }) async {
    if (!_loaded) await load();
    final folder = _folder;
    final profile = _profile;
    if (folder == null || profile == null || !holds(path)) return;
    // Measuring reads every lap's pedals at every corner as the coach does:
    // off the UI thread. A newer recording of the same day wins.
    final generation = (_recordings[eventId] ?? 0) + 1;
    _recordings[eventId] = generation;
    final ProfileDayInput input;
    try {
      input = await background(
        _measureJob(
          eventId: eventId,
          file: p.relative(path, from: folder).replaceAll(r'\', '/'),
          name: name,
          analysis: analysis,
          trackName: _newTrackName(profile, analysis),
          recordings: recordings,
          theoreticalBest: theoreticalBest,
          weather: weather,
          setups: setups,
        ),
      );
    } on Object catch (error) {
      debugPrint('Day not measured for the profile: $error');
      return;
    }
    if (_recordings[eventId] != generation || _deleted.contains(eventId)) {
      return;
    }
    // Weather given since this recording began is newer than its own.
    final newer = _weather[eventId];
    // A record without setups (a restored day not saved since) takes the
    // setups last given, such as those of a save whose measure failed.
    final held = input.setupsGiven ? null : _setups[eventId];
    _change((profile) {
      final next = addDayToProfile(
        profile,
        newer == null ? input : input.withWeather(newer),
        defaultCarName: defaultCarName,
        defaultTrackName: defaultTrackName(profile.tracks.length + 1),
      );
      return _withPendingReference(
        held == null ? next : setProfileSessionSetups(next, eventId, held),
        eventId,
      );
    });
  }

  /// The name of a new track of [analysis]: the circuit its route starts
  /// on, numbered when the profile has a track of that name already (another
  /// layout there); else [defaultTrackName].
  String _newTrackName(DriverProfile profile, DayAnalysis analysis) {
    final circuit = circuitDirectory.find(
      routeStart(analysis, analysis.chosenGroup?.runIds ?? const []),
    );
    if (circuit == null) return defaultTrackName(profile.tracks.length + 1);
    final taken = {for (final track in profile.tracks) track.name};
    var name = circuit.name;
    for (var number = 2; taken.contains(name); ++number) {
      name = '${circuit.name} $number';
    }
    return name;
  }

  /// The latest [recordDay] of each day, by event id.
  final _recordings = <String, int>{};

  /// The [recordDay]s still measuring.
  final _measuring = <Future<void>>{};

  // Takes only what it is given, so it can be sent to another isolate.
  static ProfileDayInput Function() _measureJob({
    required String eventId,
    required String file,
    required String name,
    required DayAnalysis analysis,
    required String trackName,
    required Map<String, TelemetrySession?>? recordings,
    required DayTheoreticalBest? theoreticalBest,
    required Map<String, ProfileWeather?>? weather,
    required Map<String, ProfileSetup?>? setups,
  }) =>
      () => ProfileDayInput.fromAnalysis(
        eventId: eventId,
        file: file,
        name: name,
        analysis: analysis,
        trackName: trackName,
        recordings: recordings,
        theoreticalBest: theoreticalBest,
        weather: weather,
        setups: setups,
      );

  /// Day [eventId]'s sessions with [weather] (by run id), as it arrives
  /// after the day was recorded: only the weather is swapped, nothing is
  /// measured again. Sessions the profile does not list for the day are
  /// left out. The weather is also held for the day's next [recordDay],
  /// which applies it over its own (older) weather, so it is not lost when
  /// the day is not in the profile yet, is being measured, or a measure
  /// fails. Returns whether the profile changed now.
  bool recordWeather(String eventId, Map<String, ProfileWeather> weather) {
    _keepWeather(eventId, weather);
    final before = _profile;
    _change((profile) => setProfileSessionWeather(profile, eventId, weather));
    return !identical(before, _profile);
  }

  /// The setups last given for day [eventId] with [recordDay] (by run id,
  /// as saved), or null: what the profile gets once the day is recorded.
  Map<String, ProfileSetup?>? givenSetups(String eventId) => _setups[eventId];

  final _setups = <String, Map<String, ProfileSetup?>>{};

  /// The latest weather given for each day, by event id and run id.
  final _weather = <String, Map<String, ProfileWeather>>{};

  void _keepWeather(String eventId, Map<String, ProfileWeather?>? weather) {
    if (weather == null) return;
    final kept = _weather[eventId] ??= {};
    for (final MapEntry(:key, :value) in weather.entries) {
      if (value != null) kept[key] = value;
    }
  }

  /// Day [eventId] driven in car [carId], which new days then take.
  void setDayCar(String eventId, String carId) =>
      _change((profile) => setProfileDayCar(profile, eventId, carId));

  /// A new car named [name], which new days then take; returns its id.
  String? addCar(String name) {
    String? id;
    _change((profile) {
      final next = addProfileCar(profile, name);
      id = next.cars.last.id;
      return next;
    });
    return id;
  }

  void renameCar(String carId, String name) =>
      _change((profile) => renameProfileCar(profile, carId, name));

  void renameTrack(String trackId, String name) =>
      _change((profile) => renameProfileTrack(profile, trackId, name));

  /// Deletes day [eventId]: its document, its place in the profile with
  /// every number of its sessions, and the recording copies the app made
  /// that no other day of the profile uses ([deleteDayFiles]). Recordings
  /// anywhere else are the driver's own files and stay. Null when the
  /// profile has no such day. Throws when the document could not be
  /// deleted; the profile then still lists the day.
  Future<DayFilesDeleted?> deleteDay(String eventId) =>
      _referenceWork(() => _deleteDay(eventId));

  Future<DayFilesDeleted?> _deleteDay(String eventId) async {
    if (!_loaded) await load();
    _deleted.add(eventId);
    // A measure of the day still running would list it again.
    _recordings[eventId] = (_recordings[eventId] ?? 0) + 1;
    await flush();
    final profile = _profile;
    final folder = _folder;
    final day = profile?.day(eventId);
    if (profile == null || folder == null || day == null) {
      _deleted.remove(eventId);
      return null;
    }
    final path = pathOf(day)!;
    // Every day in the days folder, listed in the profile or not yet.
    final others = [
      for (final other in profile.days)
        if (other.eventId != eventId) pathOf(other)!,
      ..._dayFiles(folder),
    ];
    final owned = [
      p.join(folder, profileRecordingsFolderName),
      ...await ownedRecordingFolders(),
    ];
    // The day's own reference lap goes with it (the copy of its recording
    // unless another day's reference still uses it); other days' references
    // to this day stay, and say so when opened.
    final reference = day.reference;
    final referenceFile = reference is ProfileReferenceFile
        ? profileReferenceFilePath(folder, reference)
        : null;
    final otherReferences = [
      for (final other in profile.days)
        if (other.eventId != eventId)
          if (other.reference case final ProfileReferenceFile file)
            ?profileReferenceFilePath(folder, file),
    ];
    // A document outside the profile's days is never deleted from here.
    final DayFilesDeleted deleted;
    try {
      deleted = holds(path)
          ? await background(
              _deleteJob(path, others, owned, referenceFile, otherReferences),
            )
          : const DayFilesDeleted(recordings: 0, recordingsKept: 0);
    } on Object {
      // Still listed, so it may be recorded again.
      _deleted.remove(eventId);
      rethrow;
    }
    _weather.remove(eventId);
    _setups.remove(eventId);
    _pendingReferences.remove(eventId);
    _change((profile) => removeProfileDay(profile, eventId));
    return deleted;
  }

  static List<String> _dayFiles(String folder) {
    try {
      final days = Directory(p.join(folder, profileDaysFolder));
      if (!days.existsSync()) return const [];
      return [
        for (final entry in days.listSync())
          if (entry is File && p.extension(entry.path) == '.fetproject')
            entry.path,
      ];
    } on FileSystemException {
      return const [];
    }
  }

  /// The days deleted while the app runs: never recorded again.
  final _deleted = <String>{};

  // Takes only what it is given, so it can be sent to another isolate.
  static DayFilesDeleted Function() _deleteJob(
    String path,
    List<String> others,
    List<String> owned,
    String? referenceFile,
    List<String> otherReferences,
  ) =>
      () => deleteDayFiles(
        dayPath: path,
        otherDayPaths: others,
        ownedFolders: owned,
        referenceFile: referenceFile,
        otherReferenceFiles: otherReferences,
      );

  /// Keeps [notebook] as track [trackId]'s ([setProfileTrackNotebook]).
  /// False when it could not be kept: no profile, or past its limits.
  bool setTrackNotebook(String trackId, TrackNotebook notebook) =>
      _change((profile) => setProfileTrackNotebook(profile, trackId, notebook));

  // ---------------------------------------------------------------------
  // Reference laps (FET-276)

  /// A reference chosen for a day the profile does not list yet (a new
  /// day is listed once it is measured), by event id: given to the day
  /// when it is added.
  final _pendingReferences = <String, ProfileReference>{};

  /// One change of a reference at a time: the copy of a recording, the
  /// profile and the removal of a copy nothing uses any more must not
  /// interleave with those of another day.
  Future<void> _references = Future.value();

  Future<R> _referenceWork<R>(Future<R> Function() work) async {
    final previous = _references;
    final done = Completer<void>();
    _references = done.future;
    try {
      await previous;
      return await work();
    } finally {
      done.complete();
    }
  }

  /// The reference lap kept for day [eventId]: the one given for a day not
  /// listed yet, else the day's own; null when none.
  ProfileReference? referenceOf(String eventId) =>
      _pendingReferences[eventId] ?? _profile?.day(eventId)?.reference;

  /// Where the copy of [reference]'s recording is; null when it cannot be
  /// found from the profile ([profileReferenceFilePath]).
  String? referenceFilePath(ProfileReferenceFile reference) {
    final folder = _folder;
    return folder == null ? null : profileReferenceFilePath(folder, reference);
  }

  /// Keeps the lap [lapNumber] of [recordingId] in the recording file
  /// [source] as day [eventId]'s reference: the file is copied into the
  /// profile's `Recordings` folder (named by its hash, once however many
  /// days use it), and only the choice and that name are kept in the
  /// profile, never [source]'s path. [name] is the file's name as the
  /// reference is called. A file already in `Recordings` is not copied
  /// again. Throws [ProfileReferenceError] when it could not be kept (not
  /// a VBO or RCZ file, too large, past the limits of reference
  /// recordings, unreadable, or the profile could not be written); then
  /// nothing is kept, and a copy made for it that nothing else uses is
  /// removed.
  Future<void> setFileReference(
    String eventId, {
    required String source,
    required String name,
    required String recordingId,
    required int lapNumber,
  }) => _referenceWork(() async {
    final folder = await _referenceFolder();
    final ReferenceFileCopy copy = await background(_copyJob(folder, source));
    final reference = copy.reference(name, recordingId, lapNumber);
    try {
      await _setReference(eventId, reference);
    } on Object {
      await _forgetCopy(reference);
      rethrow;
    }
  });

  /// Keeps lap [lapNumber] of [recordingId] (a session of the day) of
  /// another day of the profile, [otherEventId], as day [eventId]'s
  /// reference: only the other day's event id is kept, so it works while
  /// that day is in the profile. Throws [ProfileReferenceError].
  Future<void> setDayReference(
    String eventId, {
    required String otherEventId,
    required String name,
    required String recordingId,
    required int lapNumber,
  }) => _referenceWork(() async {
    await _referenceFolder();
    await _setReference(
      eventId,
      ProfileReferenceDay(
        recordingId: recordingId,
        lapNumber: lapNumber,
        eventId: otherEventId,
        name: name,
      ),
    );
  });

  /// Forgets day [eventId]'s reference lap, and its copy of a recording
  /// unless another day or reference still uses it.
  Future<void> clearReference(String eventId) => _referenceWork(() async {
    await _referenceFolder();
    await _setReference(eventId, null);
  });

  Future<String> _referenceFolder() async {
    if (!_loaded) await load();
    final folder = _folder;
    if (folder == null || _profile == null) {
      throw const ProfileReferenceError(
        ProfileReferenceProblem.notWritten,
        'Days are not kept in a profile.',
      );
    }
    return folder;
  }

  // Sets [reference] (null forgets it) and waits for it to be written.
  Future<void> _setReference(
    String eventId,
    ProfileReference? reference,
  ) async {
    final profile = _profile!;
    final day = profile.day(eventId);
    final before = referenceOf(eventId);
    if (day == null) {
      // Not listed yet: given to the day when it is, if it is going to be.
      if (_deleted.contains(eventId)) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.notWritten,
          'The day is not in the profile.',
        );
      }
      if (reference == null) {
        _pendingReferences.remove(eventId);
      } else {
        _pendingReferences[eventId] = checkProfileReference(
          profile,
          eventId,
          reference,
        );
      }
    } else {
      final failures = _writeFailures;
      _change((profile) => setProfileDayReference(profile, eventId, reference));
      final changed = _profile;
      await flush();
      if (_writeFailures != failures) {
        // Not on disk, so not kept: the profile is as it was.
        if (identical(_profile, changed) && !identical(changed, profile)) {
          _profile = profile;
          notifyListeners();
        }
        throw const ProfileReferenceError(
          ProfileReferenceProblem.notWritten,
          'The profile could not be written.',
        );
      }
    }
    if (before is ProfileReferenceFile) await _forgetCopy(before);
  }

  /// A reference given to a day not listed before, now that it is.
  DriverProfile _withPendingReference(DriverProfile profile, String eventId) {
    final pending = _pendingReferences.remove(eventId);
    if (pending == null || profile.day(eventId) == null) return profile;
    try {
      return setProfileDayReference(profile, eventId, pending);
    } on ProfileReferenceError catch (error) {
      // Checked when it was given; the profile has changed since.
      debugPrint('Reference not kept: ${error.message}');
      return profile;
    }
  }

  /// Deletes the copy of [reference]'s recording unless the profile's days
  /// or a day's recordings still use it.
  Future<void> _forgetCopy(ProfileReference? reference) async {
    final folder = _folder, profile = _profile;
    if (reference is! ProfileReferenceFile ||
        folder == null ||
        profile == null) {
      return;
    }
    final used = {
      ...profileReferenceFiles(profile).keys,
      for (final pending in _pendingReferences.values)
        if (pending is ProfileReferenceFile) pending.fileName,
    };
    final days = [
      for (final day in profile.days) pathOf(day)!,
      ..._dayFiles(folder),
    ];
    try {
      await background(_forgetJob(folder, reference, used, days));
    } on Object catch (error) {
      debugPrint('Reference recording copy not removed: $error');
    }
  }

  // Take only what they are given, so they can be sent to another isolate.
  static ReferenceFileCopy Function() _copyJob(String folder, String source) =>
      () => _copyReferenceFile(folder, source);

  static bool Function() _forgetJob(
    String folder,
    ProfileReferenceFile reference,
    Set<String> used,
    List<String> days,
  ) =>
      () => deleteUnusedReferenceFile(
        folder: folder,
        reference: reference,
        stillReferenced: used,
        dayPaths: days,
      );

  static ReferenceFileCopy _copyReferenceFile(String folder, String source) {
    // A recording that is already one of the profile's copies is not
    // copied onto itself.
    final recordings = p.join(folder, profileRecordingsFolderName);
    final name = p.basename(source);
    final match = RegExp(r'^([0-9a-f]{64})(\.vbo|\.rcz)$').firstMatch(name);
    if (match != null &&
        p.equals(p.dirname(source), recordings) &&
        File(source).existsSync()) {
      final bytes = File(source).lengthSync();
      if (bytes > 0 && bytes <= maximumReferenceFileBytes) {
        return ReferenceFileCopy(
          sha256: match.group(1)!,
          extension: match.group(2)!,
          bytes: bytes,
        );
      }
    }
    return keepReferenceFile(folder, source);
  }

  /// Writes the profile, its days and their recordings to one bundle at
  /// [target] ([writeProfileBundle]), once the changes asked for so far are
  /// written. Null when there is no profile.
  Future<ProfileBundleExport?> exportBundle(String target) =>
      _bundleWork(() async {
        await flush();
        final profile = _profile;
        final folder = _folder;
        if (profile == null || folder == null) return null;
        return background(_exportJob(profile, folder, target));
      });

  /// Adds the days of the bundle at [bundle] this profile does not have,
  /// with their recordings ([readProfileBundle]), and writes the profile.
  /// Null when there is no profile; throws [ProfileBundleError] for a file
  /// that is not a bundle, and [ProfileNotSaved] when the days were copied
  /// but the profile listing them could not be written.
  Future<ProfileBundleImport?> importBundle(String bundle) =>
      _bundleWork(() async {
        await flush();
        final profile = _profile;
        final folder = _folder;
        if (profile == null || folder == null) return null;
        final read = await background(_importJob(profile, folder, bundle));
        // A day deleted earlier and brought back is the profile's again.
        _deleted.removeAll(read.added);
        if (read.added.isEmpty && read.notebooks.isEmpty) return read;
        var result = read;
        // Copies placed for a reference this profile had no room for.
        final noRoom = <ProfileReference>[];
        try {
          // A day recorded while the bundle was read is kept: the bundle's
          // days are merged into the profile as it is now.
          final current = _profile!;
          var next = read.profile;
          if (!identical(current, profile)) {
            // From the bundle's own profile: this profile as it was when
            // the bundle was read would bring back notebook edits made
            // meanwhile.
            final merge = mergeDriverProfile(
              current,
              read.source ?? read.profile,
              only: {...read.added},
            );
            next = merge.profile;
            result = ProfileBundleImport(
              profile: next,
              added: merge.added,
              alreadyHere: [...read.alreadyHere, ...merge.alreadyHere],
              notAdded: [...read.notAdded, ...merge.notAdded],
              recordings: read.recordings,
              notebooks: merge.notebooks,
              notebookCut: merge.notebookCut,
              referencesNotKept: [
                ...read.referencesNotKept,
                ...merge.referencesNotKept,
              ],
              referencesMissing: read.referencesMissing,
              source: read.source,
            );
            for (final eventId in merge.referencesNotKept) {
              if (read.profile.day(eventId)?.reference case final reference?) {
                noRoom.add(reference);
              }
            }
          }
          _profile = next;
          notifyListeners();
          final written = _writes.then(
            (_) => background(_writeJob(folder, next)),
          );
          _writes = written.then((_) {}, onError: (Object error) {});
          await written;
          for (final reference in noRoom) {
            await _referenceWork(() => _forgetCopy(reference));
          }
        } on Object catch (error) {
          debugPrint('Imported days not written to the profile: $error');
          throw ProfileNotSaved(result);
        }
        return result;
      });

  // One export or import at a time: two imports of one bundle would write
  // the same days.
  Future<R?> _bundleWork<R>(Future<R?> Function() work) async {
    if (!_loaded) await load();
    final previous = _bundles;
    final done = Completer<void>();
    _bundles = done.future;
    try {
      await previous;
      return await work();
    } finally {
      done.complete();
    }
  }

  Future<void> _bundles = Future.value();

  // Take only what they are given, so they can be sent to another isolate.
  static Future<ProfileBundleExport> Function() _exportJob(
    DriverProfile profile,
    String folder,
    String target,
  ) =>
      () => writeProfileBundle(profile, folder, target);

  static Future<ProfileBundleImport> Function() _importJob(
    DriverProfile profile,
    String folder,
    String bundle,
  ) =>
      () => readProfileBundle(profile, folder, bundle);

  // False when there is no profile or the change is past its limits.
  bool _change(DriverProfile Function(DriverProfile) change) {
    final profile = _profile;
    final folder = _folder;
    if (profile == null || folder == null) return false;
    final DriverProfile next;
    try {
      next = change(profile);
    } on ProfileFormatError catch (error) {
      debugPrint('Driver profile not changed: ${error.message}');
      return false;
    }
    if (identical(next, profile)) return true;
    _profile = next;
    notifyListeners();
    _writes = _writes.then((_) => _write(folder, next, background));
    return true;
  }

  /// How many writes of the profile failed so far: a change that must be
  /// told as not saved ([setFileReference]) compares it before and after.
  int _writeFailures = 0;

  /// Waits for the days being measured and the writes asked for so far.
  Future<void> flush() async {
    await Future.wait([..._measuring]);
    await _writes;
  }

  Future<void> _write(
    String folder,
    DriverProfile profile,
    Future<R> Function<R>(FutureOr<R> Function()) background,
  ) async {
    try {
      await background(_writeJob(folder, profile));
    } on Object catch (error) {
      ++_writeFailures;
      debugPrint('Driver profile not written: $error');
    }
  }

  // Encoded, written and moved into place together, in the background: a
  // temporary file renamed over the profile, so a write cut short leaves
  // the previous profile whole.
  static void Function() _writeJob(String folder, DriverProfile profile) => () {
    final text = encodeDriverProfile(profile);
    Directory(folder).createSync(recursive: true);
    final target = p.join(folder, profileFileName);
    File('$target.saving')
      ..writeAsStringSync(text, flush: true)
      ..renameSync(target);
  };
}

/// The days of a bundle were copied, but the profile listing them could
/// not be written: they are listed again, under the last car, when the app
/// next starts.
final class ProfileNotSaved implements Exception {
  const ProfileNotSaved(this.import);

  final ProfileBundleImport import;

  @override
  String toString() => 'The profile with the imported days was not written.';
}
