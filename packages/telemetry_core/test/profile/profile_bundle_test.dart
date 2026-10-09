import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
    double latitude = 52.0,
    Map<String, Object?>? firstSetup,
  }) async {
    Directory(recordings).createSync(recursive: true);
    final paths = [
      for (final (index, speeds) in sessions.indexed)
        () {
          final path = p.join(recordings, '$eventId-$index.vbo');
          File(path).writeAsStringSync(circuitVbo(speeds, latitude: latitude));
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
        setups: firstSetup == null ? null : {runs.first.run.id: ProfileSetup.of(firstSetup)},
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

    test('a session setup comes along as stored, unknown keys included', () async {
      final a = p.join(root(), 'A');
      final setup = {
        'version': runSetupVersion,
        'pressureUnit': 'psi',
        'coldPressure': {'fl': 28.5, 'fr': 28.5, 'rl': 27, 'rr': 27, 'spare': 1},
        'tyre': 'Pirelli',
        'fuelStartLitres': 20,
        'camber': -2.5,
      };
      final profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
        [29, 32],
      ], firstSetup: setup);
      final bundle = p.join(root(), 'a$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final read = await readProfileBundle(
        DriverProfile.empty(Random(2)),
        p.join(root(), 'B'),
        bundle,
      );
      final sessions = read.profile.day('e1')!.sessions;
      expect(sessions.first.setup!.json, setup);
      expect(sessions.first.setup!.setup.pressureUnit, PressureUnit.psi);
      expect(sessions.first.setup!.setup.cold.fl, 28.5);
      expect(sessions[1].setup, isNull);
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
      // Each corner keeps the day's segment it was measured at, now on this
      // track's corner (FET-184).
      final segments = dayCornerIds(there.day('e1')!)!;
      expect(segments, hasLength(there.day('e1')!.sessions.single.stats!.corners.length));
      final merged = dayCornerIds(day)!;
      expect(merged.keys, segments.keys);
      for (final corner in corners) {
        expect(merged[corner.segmentId], corner.cornerId);
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

    test(
      'a recording this app may not read is missing, not a failed export',
      () async {
        final a = p.join(root(), 'A');
        final imported = p.join(a, 'in');
        final profile = await saveDay(DriverProfile.empty(Random(1)), a, imported, 'e1', [
          [30, 28, 31],
        ]);
        // The macOS sandbox shows a file outside the app's folders but will
        // not open it.
        Process.runSync('chmod', ['000', p.join(imported, 'e1-0.vbo')]);
        addTearDown(() => Process.runSync('chmod', ['644', p.join(imported, 'e1-0.vbo')]));
        final bundle = p.join(root(), 'a$profileBundleExtension');
        final export = await writeProfileBundle(profile, a, bundle);
        expect(export.days, 1);
        expect(export.recordingsMissing, 1);
        expect(File(bundle).existsSync(), isTrue);
      },
      skip: Platform.isWindows || Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
          ? 'Needs a user the file mode applies to.'
          : false,
    );

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

    test('a day that cannot be read writes nothing', () async {
      final a = p.join(root(), 'A');
      var profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      profile = await saveDay(profile, a, p.join(a, 'in'), 'e2', [
        [31, 29, 30],
      ]);
      final bundle = p.join(root(), 'a$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final archive = ZipDecoder().decodeBytes(File(bundle).readAsBytesSync());
      final damaged = Archive();
      for (final entry in archive) {
        damaged.addFile(
          entry.name == 'Days/e2.fetproject'
              ? ArchiveFile.string(entry.name, 'not json')
              : ArchiveFile.bytes(entry.name, entry.content),
        );
      }
      final path = p.join(root(), 'damaged$profileBundleExtension');
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(damaged));
      final b = p.join(root(), 'B');
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, path),
        throwsA(isA<ProfileBundleError>()),
      );
      expect(Directory(b).existsSync(), isFalse);
    });

    /// [bundle] with each entry [change] returns content for replaced, at
    /// [path].
    String rewritten(String bundle, String path, List<int>? Function(String name) change) {
      final archive = ZipDecoder().decodeBytes(File(bundle).readAsBytesSync());
      final out = Archive();
      for (final entry in archive) {
        out.addFile(ArchiveFile.bytes(entry.name, change(entry.name) ?? entry.content));
      }
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(out));
      return path;
    }

    /// [bytes] with every little-endian 32-bit [from] (a size in the zip's
    /// headers) made [to].
    List<int> patched(List<int> bytes, int from, int to) {
      final out = [...bytes];
      List<int> le(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
      final needle = le(from), value = le(to);
      for (var i = 0; i + 4 <= out.length; i++) {
        if (out[i] == needle[0] &&
            out[i + 1] == needle[1] &&
            out[i + 2] == needle[2] &&
            out[i + 3] == needle[3]) {
          out.setRange(i, i + 4, value);
        }
      }
      return out;
    }

    test('a recording damaged after the first day writes nothing', () async {
      final a = p.join(root(), 'A');
      var profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      profile = await saveDay(profile, a, p.join(a, 'in'), 'e2', [
        [31, 29, 30],
      ]);
      final bundle = p.join(root(), 'a$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final names = [
        for (final entry in ZipDecoder().decodeBytes(File(bundle).readAsBytesSync()))
          if (entry.name.startsWith('Recordings/')) entry.name,
      ];
      expect(names, hasLength(2));
      // The last recording, its content changed but not its size.
      final damaged = rewritten(bundle, p.join(root(), 'damaged.feprofile'), (name) {
        if (name != names.last) return null;
        final original = ZipDecoder()
            .decodeBytes(File(bundle).readAsBytesSync())
            .findFile(name)!
            .content;
        return [...original]..[original.length ~/ 2] ^= 0xff;
      });
      final b = p.join(root(), 'B');
      Directory(b).createSync();
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, damaged),
        throwsA(isA<ProfileBundleError>()),
      );
      expect(Directory(b).listSync(), isEmpty, reason: 'no day, recording or staging left');
      // The whole bundle then adds both days.
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.added, ['e1', 'e2']);
    });

    test('an entry unpacking to more than it declares is refused', () async {
      final a = p.join(root(), 'A');
      final profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      final bundle = p.join(root(), 'a$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      const size = 1000003;
      final b = p.join(root(), 'B');
      Directory(b).createSync();
      // A recording that would unpack to far more than it says.
      final recording = rewritten(
        bundle,
        p.join(root(), 'big.feprofile'),
        (name) => name.startsWith('Recordings/') ? List<int>.filled(size, 0) : null,
      );
      File(recording).writeAsBytesSync(patched(File(recording).readAsBytesSync(), size, 10));
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, recording),
        throwsA(isA<ProfileBundleError>()),
      );
      expect(Directory(b).listSync(), isEmpty);
      // So would the profile, read into memory.
      final index = rewritten(
        bundle,
        p.join(root(), 'index.feprofile'),
        (name) => name == profileIndexName ? List<int>.filled(size, 0x20) : null,
      );
      File(index).writeAsBytesSync(patched(File(index).readAsBytesSync(), size, 10));
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, index),
        throwsA(isA<ProfileBundleError>()),
      );
      expect(Directory(b).listSync(), isEmpty);
    });

    test(
      'another car and circuit are added; a different recording of the same name is kept',
      () async {
        final a = p.join(root(), 'A');
        final b = p.join(root(), 'B');
        final there = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
          [30, 28, 31],
        ]);
        final here = await saveDay(
          DriverProfile.empty(Random(2)),
          b,
          p.join(b, 'in'),
          'h1',
          [
            [29, 30, 31],
          ],
          car: 'Civic',
          latitude: 50,
        );
        final bundle = p.join(root(), 'a$profileBundleExtension');
        await writeProfileBundle(there, a, bundle);
        final name = [
          for (final entry in ZipDecoder().decodeBytes(File(bundle).readAsBytesSync()))
            if (entry.name.startsWith('Recordings/')) entry,
        ].single;
        // Here already: another file by that name, of the same size.
        File(p.join(b, 'Recordings', p.basename(name.name)))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List<int>.filled(name.size, 7));
        final read = await readProfileBundle(here, b, bundle);
        expect(read.added, ['e1']);
        expect(read.profile.cars.map((car) => car.name), ['Civic', 'Clio']);
        expect(read.profile.tracks, hasLength(2));
        expect(read.profile.lastCarId, here.lastCarId);
        final day = read.profile.day('e1')!;
        expect(day.carId, there.cars.single.id);
        expect(day.trackId, there.tracks.single.id);
        final ids = {for (final corner in read.profile.track(day.trackId!)!.corners) corner.id};
        for (final corner in day.sessions.single.stats!.corners) {
          expect(ids, contains(corner.cornerId));
        }
        final opened = openDay(p.join(b, 'Days', 'e1.fetproject'));
        expect(opened.missing, isEmpty);
        expect(
          File(p.join(b, 'Recordings', p.basename(name.name))).readAsBytesSync().first,
          7,
          reason: 'the file already here is left as it is',
        );
        expect(
          File(
            p.join(
              b,
              'Recordings',
              '${p.basenameWithoutExtension(name.name)} (2)${p.extension(name.name)}',
            ),
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('a day that is another day inside is refused', () async {
      final a = p.join(root(), 'A');
      final profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      final bundle = p.join(root(), 'a$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final other = rewritten(bundle, p.join(root(), 'other-day.feprofile'), (name) {
        if (name != 'Days/e1.fetproject') return null;
        final text = utf8.decode(
          ZipDecoder().decodeBytes(File(bundle).readAsBytesSync()).findFile(name)!.content,
        );
        return utf8.encode(text.replaceAll('"e1"', '"e9"'));
      });
      final b = p.join(root(), 'B');
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, other),
        throwsA(isA<ProfileBundleError>()),
      );
      expect(Directory(b).existsSync(), isFalse);
    });

    test('a small file unpacking to far more than it says stays small in memory', () async {
      // 512 MiB of zeros, deflated a piece at a time, said to be 1000 bytes.
      final deflated = BytesBuilder(copy: false);
      final sink = ZLibCodec(raw: true).encoder.startChunkedConversion(_Collect(deflated.add));
      final zeros = Uint8List(1024 * 1024);
      for (var mebibyte = 0; mebibyte < 512; mebibyte++) {
        sink.add(zeros);
      }
      sink.close();
      final bomb = deflated.takeBytes();
      final script = p.join(root(), 'read_bomb.dart');
      File(script).writeAsStringSync('''
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';

Future<void> main(List<String> arguments) async {
  Future<String> read(String bundle) async {
    try {
      await readProfileBundle(DriverProfile.empty(Random(2)), arguments[2], bundle);
    } on Object catch (caught) {
      return caught.runtimeType.toString();
    }
    return 'none';
  }

  // Once small, so what the first read sets up is not counted.
  await read(arguments[0]);
  final before = ProcessInfo.maxRss;
  final error = await read(arguments[1]);
  stdout.write('\$error \${ProcessInfo.maxRss - before}');
}
''');
      // Compiled first, in a process of its own: the compiler's memory is not
      // the read's.
      final dill = p.join(root(), 'read_bomb.dill');
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        '--packages=${p.join(Directory.current.path, '.dart_tool', 'package_config.json')}',
        script,
        '-o',
        dill,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stdout}${compiled.stderr}');
      final small = p.join(root(), 'small$profileBundleExtension');
      File(small).writeAsBytesSync(
        _zip([
          (
            name: 'bundle.json',
            data: [...ZLibCodec(raw: true).encoder.convert(Uint8List(2 * 1024 * 1024))],
            method: 8,
            size: 1000,
            crc: 0,
            flags: 0,
          ),
        ]),
      );
      final b = p.join(root(), 'B');
      for (final (label, madeBy, attributes) in [
        ('a file', 20, 0),
        // archive's own decoder would unpack a Unix link whole.
        ('a link', 0x0314, 0xa1ff << 16),
      ]) {
        final path = p.join(root(), 'bomb$profileBundleExtension');
        File(path).writeAsBytesSync(
          _zip(
            [(name: 'bundle.json', data: bomb, method: 8, size: 1000, crc: 0, flags: 0)],
            madeBy: madeBy,
            attributes: attributes,
          ),
        );
        // In a process of its own, whose peak memory is this read's alone.
        final run = await Process.run(Platform.resolvedExecutable, [dill, small, path, b]);
        expect(run.exitCode, 0, reason: '$label: ${run.stderr}');
        final [error, grew] = (run.stdout as String).trim().split(' ');
        expect(error, 'ProfileBundleError', reason: label);
        expect(int.parse(grew), lessThan(128 * 1024 * 1024), reason: label);
      }
      expect(Directory(b).existsSync(), isFalse);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('an encrypted, oddly packed or damaged entry is refused', () async {
      final manifest = utf8.encode('{"format":"$profileBundleFormat","version":1}');
      final crc = getCrc32(manifest);
      final b = p.join(root(), 'B');
      for (final (label, entry) in [
        (
          'encrypted',
          (
            name: 'bundle.json',
            data: manifest,
            method: 0,
            size: manifest.length,
            crc: crc,
            flags: 1,
          ),
        ),
        (
          'bzip2',
          (
            name: 'bundle.json',
            data: manifest,
            method: 12,
            size: manifest.length,
            crc: crc,
            flags: 0,
          ),
        ),
        (
          'bad deflate',
          (
            name: 'bundle.json',
            data: [0xff, 0xff, 0xff, 0xff],
            method: 8,
            size: manifest.length,
            crc: crc,
            flags: 0,
          ),
        ),
        (
          'wrong checksum',
          (
            name: 'bundle.json',
            data: manifest,
            method: 0,
            size: manifest.length,
            crc: crc ^ 1,
            flags: 0,
          ),
        ),
      ]) {
        final path = p.join(root(), '$label$profileBundleExtension');
        File(path).writeAsBytesSync(_zip([entry]));
        await expectLater(
          readProfileBundle(DriverProfile.empty(Random(2)), b, path),
          throwsA(isA<ProfileBundleError>()),
          reason: label,
        );
      }
      expect(Directory(b).existsSync(), isFalse);
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
      for (final name in [
        r'Recordings\..\..\evil.txt',
        'C:/evil.txt',
        '/evil.txt',
        'Recordings/C:evil.vbo',
        'Recordings/CON.vbo',
        'Recordings/evil.',
        'Days/e1.txt',
      ]) {
        final hostile = await zip('hostile.feprofile', {
          'bundle.json': manifest,
          'driver.feprofile': encodeDriverProfile(empty),
          name: 'x',
        });
        await expectLater(
          readProfileBundle(empty, b, hostile),
          throwsA(isA<ProfileBundleError>()),
          reason: name,
        );
      }
      final unversioned = await zip('unversioned.feprofile', {
        'bundle.json': '{"format":"$profileBundleFormat","version":"1"}',
        'driver.feprofile': encodeDriverProfile(empty),
      });
      await expectLater(
        readProfileBundle(empty, b, unversioned),
        throwsA(isA<ProfileBundleError>()),
      );
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

  group('days whose file names differ only by letter case', () {
    /// A bundle of the days [ids]. Ids the exporter would not write together
    /// (the same but for letter case) are exported with a `~` and renamed
    /// in the zip, as a bundle from a case-sensitive volume or another
    /// writer would hold them.
    Future<String> bundleOf(List<String> ids) async {
      final a = p.join(root(), 'A');
      var profile = DriverProfile.empty(Random(1));
      final seen = <String>{};
      final exported = [for (final id in ids) seen.add(id.toLowerCase()) ? id : '$id~'];
      for (final id in exported) {
        profile = await saveDay(profile, a, p.join(a, 'in'), id, [
          [30, 28, 31],
        ]);
      }
      final bundle = p.join(root(), 'x${ids.join()}$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      if (exported.every((id) => !id.endsWith('~'))) return bundle;
      final out = Archive();
      for (final entry in ZipDecoder().decodeBytes(File(bundle).readAsBytesSync())) {
        final content = entry.name.startsWith('Recordings/')
            ? entry.content as List<int>
            : utf8.encode(utf8.decode(entry.content as List<int>).replaceAll('~', ''));
        out.addFile(ArchiveFile.bytes(entry.name.replaceAll('~', ''), content));
      }
      final renamed = p.join(root(), 'renamed${ids.join()}$profileBundleExtension');
      File(renamed).writeAsBytesSync(ZipEncoder().encodeBytes(out));
      return renamed;
    }

    test('the exporter leaves out the second of two such days and says so', () async {
      final a = p.join(root(), 'A');
      var profile = DriverProfile.empty(Random(1));
      for (final id in ['Day', 'day']) {
        profile = await saveDay(profile, a, p.join(a, 'in'), id, [
          [30, 28, 31],
        ]);
      }
      final bundle = p.join(root(), 'both$profileBundleExtension');
      final written = await writeProfileBundle(profile, a, bundle);
      expect(written.days, 1);
      expect(written.daysMissing, ['day']);
    });

    test('are refused together, writing nothing and keeping both ids', () async {
      final bundle = await bundleOf(['A', 'a']);
      final b = p.join(root(), 'B');
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, bundle),
        throwsA(
          isA<ProfileBundleError>().having((e) => e.message, 'message', contains('letter case')),
        ),
      );
      expect(Directory(b).existsSync(), isFalse);
    });

    test('a day here whose name differs only by case refuses the bundle too', () async {
      final b = p.join(root(), 'B');
      final first = await readProfileBundle(
        DriverProfile.empty(Random(2)),
        b,
        await bundleOf(['A']),
      );
      expect(first.added, ['A']);
      final other = await bundleOf(['a']);
      await expectLater(
        readProfileBundle(first.profile, b, other),
        throwsA(isA<ProfileBundleError>()),
      );
      expect(Directory(p.join(b, 'Days')).listSync().map((e) => p.basename(e.path)), [
        'A.fetproject',
      ]);
      // The same id again is the same day, not a collision.
      final again = await readProfileBundle(first.profile, b, await bundleOf(['A']));
      expect(again.alreadyHere, ['A']);
      expect(again.added, isEmpty);
    });

    test('days that differ by more than case are added', () async {
      final read = await readProfileBundle(
        DriverProfile.empty(Random(2)),
        p.join(root(), 'B'),
        await bundleOf(['A', 'b']),
      );
      expect(read.added..sort(), ['A', 'b']);
    });
  });

  group('a bundle past the limits', () {
    final manifest = '{"format":"$profileBundleFormat","version":1}';

    _Entry stored(String name, List<int> data, {int? size}) => (
      name: name,
      data: data,
      method: 0,
      size: size ?? data.length,
      crc: getCrc32(data),
      flags: 0,
    );

    /// A bundle of the given entries as a real encoder would write them.
    Future<String> zipOf(String name, Map<String, List<int>> files) async {
      final path = p.join(root(), name);
      final encoder = ZipFileEncoder()..create(path);
      files.forEach((entry, data) => encoder.addArchiveFile(ArchiveFile.bytes(entry, data)));
      await encoder.close();
      return path;
    }

    Future<void> expectRefused(String bundle, Pattern message) async {
      final b = p.join(root(), 'B');
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, bundle),
        throwsA(isA<ProfileBundleError>().having((e) => e.message, 'message', contains(message))),
      );
      // Nothing written: not the folder, not a staging folder.
      expect(Directory(b).existsSync(), isFalse);
    }

    final empty = encodeDriverProfile(DriverProfile.empty(Random(1))).codeUnits;

    test('more recordings than a bundle may hold is refused', () async {
      final bundle = await zipOf('many.feprofile', {
        'bundle.json': utf8.encode(manifest),
        profileIndexName: empty,
        for (var i = 0; i <= maximumBundleRecordings; i++) 'Recordings/r$i.vbo': const [],
      });
      await expectRefused(bundle, 'too many recordings');
    });

    test('a directory that says it lists more entries than allowed is refused unread', () async {
      final good = _zip([stored('bundle.json', utf8.encode(manifest))]);
      final end = good.length - 22;
      for (final (count, size) in [
        (0xffff, 100),
        (10, 0x7fffffff),
        (10, maximumBundleDirectoryBytes + 1),
      ]) {
        final bytes = [...good];
        final view = ByteData.sublistView(Uint8List.fromList(bytes));
        view.setUint16(end + 10, count, Endian.little);
        view.setUint32(end + 12, size, Endian.little);
        final path = p.join(root(), 'directory.feprofile');
        File(path).writeAsBytesSync(view.buffer.asUint8List());
        await expectRefused(path, 'too many files');
      }
    });

    test('a zip64 directory with an enormous entry count is refused', () async {
      final good = _zip([stored('bundle.json', utf8.encode(manifest))]);
      final end = good.length - 22;
      final source = ByteData.sublistView(Uint8List.fromList(good));
      final record = ByteData(56)
        ..setUint32(0, 0x06064b50, Endian.little)
        ..setUint64(4, 44, Endian.little)
        ..setUint16(12, 45, Endian.little)
        ..setUint16(14, 45, Endian.little)
        ..setUint64(24, 1 << 40, Endian.little)
        ..setUint64(32, 1 << 40, Endian.little)
        ..setUint64(40, source.getUint32(end + 12, Endian.little), Endian.little)
        ..setUint64(48, source.getUint32(end + 16, Endian.little), Endian.little);
      final locator = ByteData(20)
        ..setUint32(0, 0x07064b50, Endian.little)
        ..setUint64(8, end, Endian.little)
        ..setUint32(16, 1, Endian.little);
      final tail = ByteData.sublistView(Uint8List.fromList(good.sublist(end)))
        ..setUint16(10, 0xffff, Endian.little)
        ..setUint32(12, 0xffffffff, Endian.little);
      final path = p.join(root(), 'zip64.feprofile');
      File(path).writeAsBytesSync([
        ...good.sublist(0, end),
        ...record.buffer.asUint8List(),
        ...locator.buffer.asUint8List(),
        ...tail.buffer.asUint8List(),
      ]);
      await expectRefused(path, 'too many files');
    });

    test('a zip64 size past 2^63 does not hide what the other entries declare', () async {
      // One entry whose zip64 extra field makes its size negative, and five
      // days declaring nearly 4 GB each.
      final out = BytesBuilder();
      void u16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);
      void u32(int v) => out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
      final central = BytesBuilder();
      var index = 0;
      for (final name in [
        'Days/neg.fetproject',
        for (var i = 0; i < 5; i++) 'Days/d$i.fetproject',
      ]) {
        final negative = index++ == 0;
        final bytes = utf8.encode(name);
        final offset = out.length;
        u32(0x04034b50);
        for (final v in [20, 0, 0, 0, 0x21]) {
          u16(v);
        }
        u32(0);
        u32(1);
        u32(1);
        u16(bytes.length);
        u16(0);
        out
          ..add(bytes)
          ..addByte(0);
        u32Central(BytesBuilder b, int v) =>
            b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
        void u16Central(int v) => central.add([v & 0xff, (v >> 8) & 0xff]);
        u32Central(central, 0x02014b50);
        for (final v in [45, 45, 0, 0, 0, 0x21]) {
          u16Central(v);
        }
        u32Central(central, 0);
        u32Central(central, 1);
        u32Central(central, negative ? 0xffffffff : 3900000000);
        for (final v in [bytes.length, negative ? 12 : 0, 0, 0, 0]) {
          u16Central(v);
        }
        u32Central(central, 0);
        u32Central(central, offset);
        central.add(bytes);
        if (negative) {
          u16Central(1);
          u16Central(8);
          central.add([0, 0, 0, 0, 0, 0, 0, 0x80]);
        }
      }
      final start = out.length;
      final directory = central.takeBytes();
      out.add(directory);
      u32(0x06054b50);
      for (final v in [0, 0, 6, 6]) {
        u16(v);
      }
      u32(directory.length);
      u32(start);
      u16(0);
      final bundle = p.join(root(), 'negative.feprofile');
      File(bundle).writeAsBytesSync(out.takeBytes());
      await expectRefused(bundle, 'cannot be right');
    });

    test('a long archive comment does not hide the zip64 directory record', () async {
      final good = _zip([stored('bundle.json', utf8.encode(manifest))]);
      final end = good.length - 22;
      final source = ByteData.sublistView(Uint8List.fromList(good));
      final record = ByteData(56)
        ..setUint32(0, 0x06064b50, Endian.little)
        ..setUint64(4, 44, Endian.little)
        ..setUint64(24, 1 << 40, Endian.little)
        ..setUint64(32, 1 << 40, Endian.little)
        ..setUint64(40, source.getUint32(end + 12, Endian.little), Endian.little)
        ..setUint64(48, source.getUint32(end + 16, Endian.little), Endian.little);
      final locator = ByteData(20)
        ..setUint32(0, 0x07064b50, Endian.little)
        ..setUint64(8, end, Endian.little)
        ..setUint32(16, 1, Endian.little);
      // The 32-bit fields stay small: only the zip64 record is enormous.
      final tail = ByteData.sublistView(Uint8List.fromList(good.sublist(end)));
      final path = p.join(root(), 'comment.feprofile');
      File(path).writeAsBytesSync([
        ...good.sublist(0, end),
        ...record.buffer.asUint8List(),
        ...locator.buffer.asUint8List(),
        ...tail.buffer.asUint8List().sublist(0, 20),
        0xff,
        0xff,
        ...List.filled(0xffff, 0x20),
      ]);
      await expectRefused(path, 'too many files');
    });

    test('entries declaring more together than may be unpacked are refused', () async {
      // Five days of nearly 4 GB each, declared and never unpacked.
      final bundle = p.join(root(), 'expands.feprofile');
      File(bundle).writeAsBytesSync(
        _zip([
          stored('bundle.json', utf8.encode(manifest)),
          stored(profileIndexName, empty),
          for (var i = 0; i < 5; i++) stored('Days/d$i.fetproject', const [0], size: 3900000000),
        ]),
      );
      await expectRefused(bundle, 'unpacks to more');
    });

    test('a recording larger than the importers read is refused with its bundle', () async {
      final bundle = p.join(root(), 'large.feprofile');
      File(bundle).writeAsBytesSync(
        _zip([
          stored('bundle.json', utf8.encode(manifest)),
          stored(profileIndexName, empty),
          stored('Recordings/big.vbo', const [0], size: maximumBundleRecordingBytes + 1),
        ]),
      );
      await expectRefused(bundle, 'too large');
    });

    test('a bundle file larger than may be read is refused', () async {
      final bundle = File(p.join(root(), 'huge.feprofile'));
      final file = bundle.openSync(mode: FileMode.write)
        ..truncateSync(maximumBundleArchiveBytes + 1);
      file.closeSync();
      await expectRefused(bundle.path, 'too large');
    });

    test('a recording past the limit is left out of the bundle, the rest travels', () async {
      final a = p.join(root(), 'A');
      final imported = p.join(a, 'in');
      final profile = await saveDay(DriverProfile.empty(Random(1)), a, imported, 'e1', [
        [30, 28, 31],
      ]);
      // A sparse file one byte past what the importers read.
      final recording = File(p.join(imported, 'e1-0.vbo')).openSync(mode: FileMode.write)
        ..truncateSync(maximumBundleRecordingBytes + 1);
      recording.closeSync();
      final bundle = p.join(root(), 'a$profileBundleExtension');
      final written = await writeProfileBundle(profile, a, bundle);
      expect(written.recordingsMissing, 1);
      final read = await readProfileBundle(
        DriverProfile.empty(Random(2)),
        p.join(root(), 'B'),
        bundle,
      );
      expect(read.added, ['e1']);
      expect(read.recordings, 0);
    });
  });

  test('only a plain file name is a day name', () {
    for (final id in ['e1', 'A', '0123456789abcdef', 'day 1', 'Ünï']) {
      expect(isProfileDayName(id), isTrue, reason: id);
    }
    for (final id in [
      '../escaped',
      '..',
      '.',
      '',
      'a/b',
      r'a\b',
      '/abs',
      'C:evil',
      '.hidden',
      'CON',
      'a*b',
      'a\u0000b',
    ]) {
      expect(isProfileDayName(id), isFalse, reason: id);
    }
  });
}

final class _Collect implements Sink<List<int>> {
  _Collect(this._add);

  final void Function(List<int>) _add;

  @override
  void add(List<int> data) => _add(data);

  @override
  void close() {}
}

typedef _Entry = ({String name, List<int> data, int method, int size, int crc, int flags});

/// A zip of [entries] as given, headers and all, so a test can say what a
/// real encoder would not.
List<int> _zip(List<_Entry> entries, {int madeBy = 20, int attributes = 0}) {
  final out = BytesBuilder();
  void u16(BytesBuilder to, int v) => to.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(BytesBuilder to, int v) =>
      to.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  final central = BytesBuilder();
  for (final entry in entries) {
    final offset = out.length;
    final name = utf8.encode(entry.name);
    u32(out, 0x04034b50);
    for (final v in [20, entry.flags, entry.method, 0, 0x21]) {
      u16(out, v);
    }
    u32(out, entry.crc);
    u32(out, entry.data.length);
    u32(out, entry.size);
    u16(out, name.length);
    u16(out, 0);
    out
      ..add(name)
      ..add(entry.data);
    u32(central, 0x02014b50);
    for (final v in [madeBy, 20, entry.flags, entry.method, 0, 0x21]) {
      u16(central, v);
    }
    u32(central, entry.crc);
    u32(central, entry.data.length);
    u32(central, entry.size);
    for (final v in [name.length, 0, 0, 0, 0]) {
      u16(central, v);
    }
    u32(central, attributes);
    u32(central, offset);
    central.add(name);
  }
  final start = out.length;
  final directory = central.takeBytes();
  out.add(directory);
  u32(out, 0x06054b50);
  for (final v in [0, 0, entries.length, entries.length]) {
    u16(out, v);
  }
  u32(out, directory.length);
  u32(out, start);
  u16(out, 0);
  return out.takeBytes();
}
