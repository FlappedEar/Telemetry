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
