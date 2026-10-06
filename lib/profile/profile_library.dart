import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry_core/telemetry_core.dart';

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
  });

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
            : addDayToProfile(
                profile,
                ProfileDayInput(
                  eventId: day.eventId,
                  file: day.file,
                  name: day.name,
                ),
                defaultCarName: defaultCarName,
                defaultTrackName: defaultTrackName(profile.tracks.length + 1),
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
  /// weather ([ProfileDayInput.fromAnalysis]). Does nothing for a day saved
  /// elsewhere.
  Future<void> recordDay({
    required String eventId,
    required String path,
    required String name,
    required DayAnalysis analysis,
    Map<String, TelemetrySession?>? recordings,
    DayTheoreticalBest? theoreticalBest,
    Map<String, WeatherSummary?>? weather,
  }) async {
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
    Map<String, WeatherSummary?>? weather,
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
          trackName: defaultTrackName(profile.tracks.length + 1),
          recordings: recordings,
          theoreticalBest: theoreticalBest,
          weather: weather,
        ),
      );
    } on Object catch (error) {
      debugPrint('Day not measured for the profile: $error');
      return;
    }
    if (_recordings[eventId] != generation) return;
    _change(
      (profile) => addDayToProfile(
        profile,
        input,
        defaultCarName: defaultCarName,
        defaultTrackName: defaultTrackName(profile.tracks.length + 1),
      ),
    );
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
    required Map<String, WeatherSummary?>? weather,
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
      );

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
        if (read.added.isEmpty) return read;
        var result = read;
        try {
          // A day recorded while the bundle was read is kept: the bundle's
          // days are merged into the profile as it is now.
          final current = _profile!;
          var next = read.profile;
          if (!identical(current, profile)) {
            final merge = mergeDriverProfile(
              current,
              read.profile,
              only: {...read.added},
            );
            next = merge.profile;
            result = ProfileBundleImport(
              profile: next,
              added: merge.added,
              alreadyHere: [...read.alreadyHere, ...merge.alreadyHere],
              notAdded: [...read.notAdded, ...merge.notAdded],
              recordings: read.recordings,
            );
          }
          _profile = next;
          notifyListeners();
          final written = _writes.then(
            (_) => background(_writeJob(folder, next)),
          );
          _writes = written.then((_) {}, onError: (Object error) {});
          await written;
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

  void _change(DriverProfile Function(DriverProfile) change) {
    final profile = _profile;
    final folder = _folder;
    if (profile == null || folder == null) return;
    final DriverProfile next;
    try {
      next = change(profile);
    } on ProfileFormatError catch (error) {
      debugPrint('Driver profile not changed: ${error.message}');
      return;
    }
    if (identical(next, profile)) return;
    _profile = next;
    notifyListeners();
    _writes = _writes.then((_) => _write(folder, next, background));
  }

  /// Waits for the days being measured and the writes asked for so far.
  Future<void> flush() async {
    await Future.wait([..._measuring]);
    await _writes;
  }

  static Future<void> _write(
    String folder,
    DriverProfile profile,
    Future<R> Function<R>(FutureOr<R> Function()) background,
  ) async {
    try {
      await background(_writeJob(folder, profile));
    } on Object catch (error) {
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
