import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('bundle'));
  tearDown(() => directory.deleteSync(recursive: true));

  String root() => directory.resolveSymbolicLinksSync();

  /// A day saved in the profile at [folder] from recordings written to
  /// [recordings] (outside the profile, as an import leaves them), added to
  /// [profile].
  Future<DriverProfile> saveDay(
    DriverProfile profile,
    String folder,
    String recordings,
    String eventId,
    List<List<double>> sessions, {
    String car = 'Clio',
  }) async {
    Directory(recordings).createSync(recursive: true);
    final paths = [
      for (final (index, speeds) in sessions.indexed)
        () {
          final path = p.join(recordings, '$eventId-$index.vbo');
          File(path).writeAsStringSync(circuitVbo(speeds));
          return path;
        }(),
    ];
    final runs = nameRunsInRecordingOrder(prepareTelemetryImport(paths).runs);
    final analysis = analyzeDay([
      for (final named in runs)
        DayRunInput(
          runId: named.run.id,
          name: named.name,
          contentSha256: named.run.contentSha256,
          session: named.run.telemetry,
          laps: named.run.laps,
        ),
    ]);
    final path = p.join(folder, 'Days', '$eventId.fetproject');
    Directory(p.dirname(path)).createSync(recursive: true);
    await saveDayDocument(
      path,
      dayDocument(
        eventId: eventId,
        name: 'Day $eventId',
        runs: runs,
        analysis: analysis,
        projectPath: path,
      ),
    );
    final recordingsById = {for (final named in runs) named.run.id: named.run.telemetry};
    final best = dayTheoreticalBest(analysis, outingRuns(runs), random: Random(1));
    final next = addDayToProfile(
      profile,
      ProfileDayInput.fromAnalysis(
        eventId: eventId,
        file: 'Days/$eventId.fetproject',
        name: 'Day $eventId',
        analysis: analysis,
        recordings: recordingsById,
        theoreticalBest: best,
      ),
      defaultCarName: car,
      defaultTrackName: 'Track',
      random: Random(eventId.hashCode),
    );
    return next;
  }

  group('a profile moved to another device', () {
    test('its days open there with every recording, and again adds nothing', () async {
      final a = p.join(root(), 'A', 'Profile');
      final imported = p.join(root(), 'A', 'Imported');
      var profile = DriverProfile.empty(Random(1));
      profile = await saveDay(profile, a, imported, 'e1', [
        [30, 28, 31],
        [29, 32],
      ]);
      profile = await saveDay(profile, a, imported, 'e2', [
        [31, 30, 29],
      ]);
      expect(profile.days, hasLength(2));
      expect(profile.tracks, hasLength(1));
      expect(profile.tracks.single.corners, isNotEmpty);

      final bundle = p.join(root(), 'driver$profileBundleExtension');
      final export = await writeProfileBundle(profile, a, bundle);
      expect(export.days, 2);
      expect(export.recordings, 3);
      expect(export.daysMissing, isEmpty);
      expect(export.recordingsMissing, 0);
      expect(File('$bundle.partial').existsSync(), isFalse);
      // The original recordings are gone: the other device has only the
      // bundle.
      Directory(imported).deleteSync(recursive: true);

      final b = p.join(root(), 'B', 'Profile');
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.added, ['e1', 'e2']);
      expect(read.recordings, 3);
      expect(read.profile.days.map((d) => d.file), ['Days/e1.fetproject', 'Days/e2.fetproject']);
      expect(read.profile.cars.single.name, 'Clio');
      expect(read.profile.tracks.single.corners, hasLength(profile.tracks.single.corners.length));
      // Every session's corners and figures came along.
      for (final day in profile.days) {
        final there = read.profile.day(day.eventId)!;
        for (final (index, session) in day.sessions.indexed) {
          final stats = there.sessions[index].stats!;
          expect(stats.corners.length, session.stats!.corners.length);
          expect(stats.distanceMeters, session.stats!.distanceMeters);
        }
      }
      for (final eventId in ['e1', 'e2']) {
        final opened = openDay(p.join(b, 'Days', '$eventId.fetproject'));
        expect(opened.missing, isEmpty, reason: eventId);
        expect(opened.analysis, isNotNull);
      }
      expect(Directory(p.join(b, 'Recordings')).listSync(), hasLength(3));

      // Read again: nothing new, nothing written.
      final again = await readProfileBundle(read.profile, b, bundle);
      expect(again.added, isEmpty);
      expect(again.alreadyHere, ['e1', 'e2']);
      expect(again.recordings, 0);
      expect(Directory(p.join(b, 'Recordings')).listSync(), hasLength(3));
    });

    test("joins this device's car and track, its corners placed on this track's", () async {
      final a = p.join(root(), 'A');
      final b = p.join(root(), 'B');
      final there = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      final here = await saveDay(DriverProfile.empty(Random(2)), b, p.join(b, 'in'), 'h1', [
        [29, 30, 31],
      ], car: 'clio ');
      final bundle = p.join(root(), 'a$profileBundleExtension');
      await writeProfileBundle(there, a, bundle);
      final read = await readProfileBundle(here, b, bundle);
      expect(read.added, ['e1']);
      expect(read.profile.cars, hasLength(1));
      expect(read.profile.tracks, hasLength(1));
      final track = read.profile.tracks.single;
      final ids = {for (final corner in track.corners) corner.id};
      final day = read.profile.day('e1')!;
      expect(day.carId, here.cars.single.id);
      expect(day.trackId, track.id);
      final corners = day.sessions.single.stats!.corners;
      expect(corners, isNotEmpty);
      for (final corner in corners) {
        expect(ids, contains(corner.cornerId));
      }
      // The same circuit: its corners are this track's, none added.
      expect(track.corners, hasLength(here.tracks.single.corners.length));
      // Which car new days take is this device's.
      expect(read.profile.lastCarId, here.lastCarId);
    });

    test('a day whose recordings are missing comes along and says so there', () async {
      final a = p.join(root(), 'A');
      final imported = p.join(a, 'in');
      final profile = await saveDay(DriverProfile.empty(Random(1)), a, imported, 'e1', [
        [30, 28, 31],
      ]);
      File(p.join(imported, 'e1-0.vbo')).deleteSync();
      final bundle = p.join(root(), 'a$profileBundleExtension');
      final export = await writeProfileBundle(profile, a, bundle);
      expect(export.recordingsMissing, 1);
      expect(export.recordings, 0);
      final b = p.join(root(), 'B');
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.added, ['e1']);
      expect(openDay(p.join(b, 'Days', 'e1.fetproject')).missing, hasLength(1));
    });

    test('a day already in the folder is not written over', () async {
      final a = p.join(root(), 'A');
      final profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      final bundle = p.join(root(), 'a$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final b = p.join(root(), 'B');
      final existing = File(p.join(b, 'Days', 'e1.fetproject'))
        ..createSync(recursive: true)
        ..writeAsStringSync('mine');
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.added, isEmpty);
      expect(read.alreadyHere, ['e1']);
      expect(existing.readAsStringSync(), 'mine');
    });

    test('a file that is not a bundle, or reaches outside it, writes nothing', () async {
      final b = p.join(root(), 'B');
      final empty = DriverProfile.empty(Random(2));
      final text = File(p.join(root(), 'notes.feprofile'))..writeAsStringSync('{}');
      await expectLater(readProfileBundle(empty, b, text.path), throwsA(isA<ProfileBundleError>()));

      Future<String> zip(String name, Map<String, String> files) async {
        final path = p.join(root(), name);
        final encoder = ZipFileEncoder()..create(path);
        files.forEach(
          (entry, content) => encoder.addArchiveFile(ArchiveFile.string(entry, content)),
        );
        await encoder.close();
        return path;
      }

      final manifest = '{"format":"$profileBundleFormat","version":1}';
      final outside = await zip('outside.feprofile', {
        'bundle.json': manifest,
        'driver.feprofile': encodeDriverProfile(empty),
        '../evil.txt': 'x',
      });
      await expectLater(readProfileBundle(empty, b, outside), throwsA(isA<ProfileBundleError>()));
      final nested = await zip('nested.feprofile', {
        'bundle.json': manifest,
        'driver.feprofile': encodeDriverProfile(empty),
        'Recordings/a/b.vbo': 'x',
      });
      await expectLater(readProfileBundle(empty, b, nested), throwsA(isA<ProfileBundleError>()));
      final other = await zip('other.feprofile', {'bundle.json': '{"format":"something"}'});
      await expectLater(readProfileBundle(empty, b, other), throwsA(isA<ProfileBundleError>()));
      final newer = await zip('newer.feprofile', {
        'bundle.json': '{"format":"$profileBundleFormat","version":2}',
        'driver.feprofile': encodeDriverProfile(empty),
      });
      await expectLater(readProfileBundle(empty, b, newer), throwsA(isA<ProfileBundleError>()));
      expect(Directory(b).existsSync(), isFalse);
      expect(File(p.join(root(), 'evil.txt')).existsSync(), isFalse);
    });
  });
}
