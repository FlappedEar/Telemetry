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

/// The day of [eventId]'s file in [folder]'s days. Throws [FormatException]
/// for an id that is not one plain file name ([isProfileDayName]; `../x` would
/// leave `Days`).
String profileDayPath(String folder, String eventId) {
  if (!isProfileDayName(eventId)) {
    throw FormatException(
      'The day id cannot be a file name in the profile.',
      eventId,
    );
  }
  return p.join(folder, profileDaysFolder, '$eventId.fetproject');
}

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
    if (_folder != null) unawaited(_sweepCopies());
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
  String _newTrackName(DriverProfile profile, DayAnalysis analysis) =>
      _trackNameAt(
        profile,
        routeStart(analysis, analysis.chosenGroup?.runIds ?? const []),
      );

  /// The name of a new track whose route starts at [start] (see
  /// [_newTrackName]).
  String _trackNameAt(DriverProfile profile, GeoCoordinate? start) {
    final circuit = circuitDirectory.find(start);
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

  /// Every day of the profile measured again from its saved file and
  /// recordings (FET-196), as opening it would, one day at a time and off
  /// the UI thread: for a change to how sessions are measured. Levels need
  /// none of this: they are worked out from the measurements when read.
  /// Each day keeps its car, name and weather, and its track while its
  /// route matches it. Speeds without a unit are read as
  /// [assumedSpeedUnit]. [measuringAllProgress] counts the days as they are
  /// done; [stopMeasuringAll] stops after the day being measured. Returns how
  /// many days were measured and how many could not be (their file or a
  /// recording missing or unreadable: they keep what they had); null while
  /// a call is still running or without a profile.
  Future<({int measured, int failed})?> measureAllAgain({
    String assumedSpeedUnit = '',
  }) async {
    if (!_loaded) await load();
    final folder = _folder, profile = _profile;
    if (folder == null || profile == null || _measuringAll != null) {
      return null;
    }
    final days = [...profile.days];
    _stopMeasuringAll = false;
    _measuringAll = (done: 0, total: days.length);
    notifyListeners();
    var measured = 0, failed = 0;
    try {
      for (final (index, day) in days.indexed) {
        if (_stopMeasuringAll) break;
        if (await _measureAgain(folder, day, assumedSpeedUnit)) {
          ++measured;
        } else {
          ++failed;
        }
        _measuringAll = (done: index + 1, total: days.length);
        notifyListeners();
      }
    } finally {
      _measuringAll = null;
      notifyListeners();
    }
    return (measured: measured, failed: failed);
  }

  ({int done, int total})? _measuringAll;
  bool _stopMeasuringAll = false;

  /// While [measureAllAgain] runs, the days done and the total; else null.
  ({int done, int total})? get measuringAllProgress => _measuringAll;

  /// Whether [measureAllAgain] is running.
  bool get measuringAll => _measuringAll != null;

  /// Stops [measureAllAgain] once the day being measured is done.
  void stopMeasuringAll() => _stopMeasuringAll = true;

  /// [day] measured again from its file in [folder]; whether it was.
  Future<bool> _measureAgain(
    String folder,
    ProfileDay day,
    String assumed,
  ) async {
    final eventId = day.eventId;
    // A day page recording the day meanwhile wins, as a newer recording.
    final generation = (_recordings[eventId] ?? 0) + 1;
    _recordings[eventId] = generation;
    final measured = Completer<void>();
    _measuring.add(measured.future);
    try {
      final ({ProfileDayInput input, GeoCoordinate? start})? result;
      try {
        result = await background(
          _measureAgainJob(
            path: p.join(folder, day.file),
            eventId: eventId,
            file: day.file,
            assumedSpeedUnit: assumed,
          ),
        );
      } on Object catch (error) {
        debugPrint('Day $eventId not measured again: $error');
        return false;
      }
      if (result == null) return false;
      // A day deleted meanwhile is not brought back; one recorded by its
      // page meanwhile is newer.
      if (_recordings[eventId] != generation || _deleted.contains(eventId)) {
        return true;
      }
      final newer = _weather[eventId];
      final input = newer == null
          ? result.input
          : result.input.withWeather(newer);
      _change(
        (profile) => profile.day(eventId) == null
            ? profile
            : _withPendingReference(
                addDayToProfile(
                  profile,
                  input.withTrackName(_trackNameAt(profile, result!.start)),
                  defaultCarName: defaultCarName,
                  defaultTrackName: defaultTrackName(profile.tracks.length + 1),
                ),
                eventId,
              ),
      );
      return true;
    } finally {
      _measuring.remove(measured.future);
      measured.complete();
    }
  }

  // Takes only what it is given, so it can be sent to another isolate: the
  // day as opening it reads it, its theoretical best as the day page works
  // it out (from the recordings themselves), what each session measured
  // (with each run's alternative recording fused, as the day page records
  // it) and where its route starts, for a new track's name. Null when the
  // file holds another day, or a recording or alternative recording is
  // missing or unreadable: measuring without it would drop what it gave.
  static ({ProfileDayInput input, GeoCoordinate? start})? Function()
  _measureAgainJob({
    required String path,
    required String eventId,
    required String file,
    required String assumedSpeedUnit,
  }) => () {
    final opened = openDay(path);
    final analysis = opened.analysis;
    if (analysis == null ||
        opened.eventId != eventId ||
        opened.missing.isNotEmpty) {
      return null;
    }
    final fusions = fuseOpenedDay(opened);
    if (fusions.values.any(
      (fusion) => fusion.state == RunFusionState.unavailable,
    )) {
      return null;
    }
    final runs = [
      for (final named in opened.runs)
        (
          run: TelemetryRunProposal(
            id: named.run.id,
            sourceId: named.run.sourceId,
            sourcePath: named.run.sourcePath,
            format: named.run.format,
            contentSha256: named.run.contentSha256,
            telemetry: withEffectiveSpeedUnits(
              named.run.telemetry,
              assumed: assumedSpeedUnit,
            ),
            laps: named.run.laps,
          ),
          name: named.name,
        ),
    ];
    final event = opened.document['event'];
    final documentRuns = event is Map<String, Object?> && event['runs'] is List
        ? event['runs'] as List<Object?>
        : const <Object?>[];
    return (
      input: ProfileDayInput.fromAnalysis(
        eventId: eventId,
        file: file,
        name: opened.name,
        analysis: analysis,
        recordings: {
          for (final named in runs)
            named.run.id: switch (fusions[named.run.id]?.session) {
              final fused? => withEffectiveSpeedUnits(
                fused,
                assumed: assumedSpeedUnit,
              ),
              null => named.run.telemetry,
            },
        },
        theoreticalBest: dayTheoreticalBest(
          analysis,
          outingRuns(runs),
          documentRuns: documentRuns,
        ),
      ),
      start: routeStart(analysis, analysis.chosenGroup?.runIds ?? const []),
    );
  };

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
      // A reference waiting for a day that is not listed goes with it.
      final waiting = _pendingReferences.remove(eventId);
      await _forgetCopy(waiting);
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
      // Those waiting for their day (not listed yet) count too.
      for (final name in _pendingKept(except: eventId).keys)
        p.join(folder, profileRecordingsFolderName, name),
    ];
    // A document outside the profile's days is never deleted from here.
    final DayFilesDeleted deleted;
    final held = holds(path);
    try {
      deleted = held
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
    _droppedReferences.remove(eventId);
    _change((profile) => removeProfileDay(profile, eventId));
    // A document outside the profile's days stays, and so may what it
    // uses; the copy of the reference goes unless something uses it.
    if (!held) await _forgetCopy(reference, alsoDays: [path]);
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

  /// [referenceOf] once the changes of references asked for so far are
  /// done and the profile is read: a day closed and opened again, or a
  /// reference cleared and the day opened at once, sees what was asked.
  Future<ProfileReference?> restoreReference(String eventId) =>
      _referenceWork(() async {
        if (await _referenceFolder() == null) return null;
        return referenceOf(eventId);
      });

  /// Why the reference chosen for [eventId] before its day was listed in
  /// the profile was not kept when it was (the profile had reached the
  /// limits of reference recordings meanwhile); null otherwise. Listeners
  /// are told when it happens.
  ProfileReferenceError? referenceDropped(String eventId) =>
      _droppedReferences[eventId];

  final _droppedReferences = <String, ProfileReferenceError>{};

  /// The recordings (file name to bytes) the references waiting for their
  /// day keep, but for [except]'s: they count against the limits too.
  Map<String, int> _pendingKept({String? except}) => {
    for (final entry in _pendingReferences.entries)
      if (entry.value case final ProfileReferenceFile file
          when entry.key != except)
        file.fileName: file.bytes,
  };

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
  /// reference is called. A file already in `Recordings` is read and
  /// checked against its name, not trusted. Throws [ProfileReferenceError]
  /// when it could not be kept (not a VBO or RCZ file, too large, past the
  /// limits of reference recordings, unreadable, or the profile could not
  /// be written); then nothing is kept, and a copy made for it that nothing
  /// else uses is removed. False, with nothing done, when days are not kept
  /// in a profile or [when] (asked once the profile is read, and in turn
  /// with the other changes of references) says no.
  Future<bool> setFileReference(
    String eventId, {
    required String source,
    required String name,
    required String recordingId,
    required int lapNumber,
    bool Function()? when,
  }) => _referenceWork(() async {
    final folder = await _referenceFolder();
    if (folder == null || !(when?.call() ?? true)) return false;
    final ReferenceFileCopy copy = await background(_copyJob(folder, source));
    final reference = copy.reference(name, recordingId, lapNumber);
    try {
      await _setReference(eventId, reference);
    } on Object {
      await _forgetCopy(reference);
      rethrow;
    }
    return true;
  });

  /// Keeps lap [lapNumber] of [recordingId] (a session of the day) of
  /// another day of the profile, [otherEventId], as day [eventId]'s
  /// reference: only the other day's event id is kept, so it works while
  /// that day is in the profile. Throws [ProfileReferenceError]. False as
  /// [setFileReference].
  Future<bool> setDayReference(
    String eventId, {
    required String otherEventId,
    required String name,
    required String recordingId,
    required int lapNumber,
    bool Function()? when,
  }) => _referenceWork(() async {
    final folder = await _referenceFolder();
    if (folder == null || !(when?.call() ?? true)) return false;
    await _setReference(
      eventId,
      ProfileReferenceDay(
        recordingId: recordingId,
        lapNumber: lapNumber,
        eventId: otherEventId,
        name: name,
      ),
    );
    return true;
  });

  /// Forgets day [eventId]'s reference lap, and its copy of a recording
  /// unless another day or reference still uses it. False as
  /// [setFileReference].
  Future<bool> clearReference(String eventId, {bool Function()? when}) =>
      _referenceWork(() async {
        final folder = await _referenceFolder();
        if (folder == null || !(when?.call() ?? true)) return false;
        await _setReference(eventId, null);
        return true;
      });

  /// The profile folder once the profile is read; null when there is no
  /// profile.
  Future<String?> _referenceFolder() async {
    if (!_loaded) await load();
    return _profile == null ? null : _folder;
  }

  // Sets [reference] (null forgets it) and waits for it to be written.
  // Throws, with nothing kept, when it was not.
  Future<void> _setReference(
    String eventId,
    ProfileReference? reference,
  ) async {
    final profile = _profile!;
    final day = profile.day(eventId);
    final before = referenceOf(eventId);
    _droppedReferences.remove(eventId);
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
          alsoKept: _pendingKept(except: eventId),
        );
      }
    } else {
      final previous = day.reference;
      final change = _apply(
        (profile) => setProfileDayReference(
          profile,
          eventId,
          reference,
          alsoKept: _pendingKept(),
        ),
      );
      if (!change.applied) {
        throw const ProfileReferenceError(
          ProfileReferenceProblem.notWritten,
          'The profile could not be changed.',
        );
      }
      if (!await change.written) {
        // This very write did not reach the disk, so the reference is not
        // kept: taken back from the profile as it is now (days may have
        // been recorded since), and written again with the rest.
        _apply((profile) {
          final now = profile.day(eventId)?.reference;
          if (now == null && reference != null) return profile;
          if (now != null && !_sameReference(now, reference)) return profile;
          try {
            return setProfileDayReference(profile, eventId, previous);
          } on ProfileReferenceError {
            return profile;
          }
        });
        throw const ProfileReferenceError(
          ProfileReferenceProblem.notWritten,
          'The profile could not be written.',
        );
      }
    }
    if (before is ProfileReferenceFile) await _forgetCopy(before);
  }

  /// Whether [a] and [b] are the same choice: the same lap of the same
  /// recording or day.
  static bool _sameReference(ProfileReference? a, ProfileReference? b) =>
      switch ((a, b)) {
        (null, null) => true,
        (final ProfileReferenceFile a, final ProfileReferenceFile b) =>
          a.sha256 == b.sha256 &&
              a.recordingId == b.recordingId &&
              a.lapNumber == b.lapNumber,
        (final ProfileReferenceDay a, final ProfileReferenceDay b) =>
          a.eventId == b.eventId &&
              a.recordingId == b.recordingId &&
              a.lapNumber == b.lapNumber,
        _ => false,
      };

  /// A reference given to a day not listed before, now that it is. One the
  /// profile has no room for any more is dropped, and said: see
  /// [referenceDropped].
  DriverProfile _withPendingReference(DriverProfile profile, String eventId) {
    final pending = _pendingReferences[eventId];
    if (pending == null || profile.day(eventId) == null) return profile;
    _pendingReferences.remove(eventId);
    try {
      return setProfileDayReference(
        profile,
        eventId,
        pending,
        alsoKept: _pendingKept(),
      );
    } on ProfileReferenceError catch (error) {
      // Checked when it was given; the profile has changed since.
      debugPrint('Reference not kept: ${error.message}');
      _droppedReferences[eventId] = error;
      if (pending is ProfileReferenceFile) {
        unawaited(_referenceWork(() => _forgetCopy(pending)));
      }
      return profile;
    }
  }

  /// Deletes the copy of [reference]'s recording unless the profile's days
  /// or a day's recordings still use it. [alsoDays] are day files outside
  /// the days folder that are kept.
  Future<void> _forgetCopy(
    ProfileReference? reference, {
    List<String> alsoDays = const [],
  }) async {
    final folder = _folder, profile = _profile;
    if (reference is! ProfileReferenceFile ||
        folder == null ||
        profile == null) {
      return;
    }
    final used = {
      ...profileReferenceFiles(profile).keys,
      ..._pendingKept().keys,
    };
    final days = [
      for (final day in profile.days) pathOf(day)!,
      ..._dayFiles(folder),
      ...alsoDays,
    ];
    try {
      await background(_forgetJob(folder, reference, used, days));
    } on Object catch (error) {
      debugPrint('Reference recording copy not removed: $error');
    }
  }

  /// Deletes the reference recording copies no day and no reference uses
  /// (left by a crash, or a reference that was never kept), once at
  /// start-up; the files named like a copy only ([sweepReferenceFiles]).
  /// Waits its turn behind the imports and the changes of references, so no
  /// copy is being made or placed meanwhile, and does nothing while a
  /// reference waits for its day.
  Future<void> _sweepCopies() => _bundleWork<bool>(() async {
    await _referenceWork(() async {
      final folder = _folder, profile = _profile;
      if (folder == null || profile == null || _pendingReferences.isNotEmpty) {
        return;
      }
      await flush();
      final days = [
        for (final day in profile.days) pathOf(day)!,
        ..._dayFiles(folder),
      ];
      // A reference this version cannot read (a newer one's) may use any
      // copy it names, or any at all if it cannot even be searched.
      final unread = profileUnreadableReferenceFiles(profile);
      if (unread.unreadable) return;
      final used = {
        ...profileReferenceFiles(profile).keys,
        ...unread.fileNames,
      };
      try {
        final deleted = await background(_sweepJob(folder, used, days));
        if (deleted > 0) {
          debugPrint('Unused reference copies deleted: $deleted');
        }
      } on Object catch (error) {
        debugPrint('Reference recording copies not swept: $error');
      }
    });
    return true;
  });

  // Take only what they are given, so they can be sent to another isolate.
  static ReferenceFileCopy Function() _copyJob(String folder, String source) =>
      () => keepReferenceFile(folder, source);

  static int Function() _sweepJob(
    String folder,
    Set<String> used,
    List<String> days,
  ) =>
      () => sweepReferenceFiles(
        folder: folder,
        stillReferenced: used,
        dayPaths: days,
      );

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
  bool _change(DriverProfile Function(DriverProfile) change) =>
      _apply(change).applied;

  /// Like [_change], and says whether the write of this very change reached
  /// the disk: [written] is that write's own outcome, not whether another
  /// write failed. A [written] of false for a change not [applied] too.
  ({bool applied, Future<bool> written}) _apply(
    DriverProfile Function(DriverProfile) change,
  ) {
    final profile = _profile;
    final folder = _folder;
    if (profile == null || folder == null) {
      return (applied: false, written: Future.value(false));
    }
    final DriverProfile next;
    try {
      next = change(profile);
    } on ProfileFormatError catch (error) {
      debugPrint('Driver profile not changed: ${error.message}');
      return (applied: false, written: Future.value(false));
    }
    if (identical(next, profile)) {
      return (applied: true, written: Future.value(true));
    }
    _profile = next;
    notifyListeners();
    final written = _writes.then((_) => _write(folder, next, background));
    _writes = written;
    return (applied: true, written: written);
  }

  /// Waits for the days being measured and the writes asked for so far.
  Future<void> flush() async {
    await Future.wait([..._measuring]);
    await _writes;
  }

  // Whether the profile was written; never throws.
  Future<bool> _write(
    String folder,
    DriverProfile profile,
    Future<R> Function<R>(FutureOr<R> Function()) background,
  ) async {
    try {
      await background(_writeJob(folder, profile));
      return true;
    } on Object catch (error) {
      debugPrint('Driver profile not written: $error');
      return false;
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
