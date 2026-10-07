// The reference lap a day keeps in the driver profile (FET-276): the format,
// its limits, merging, a bundle, deleting a day, and hostile input. Synthetic
// recordings only.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

final _sha = sha256;

/// A distinct 64-digit hash for each [i].
String _shaOf(int i) => 'b${i.toRadixString(16).padLeft(63, '0')}';

String _hash(List<int> bytes) => _sha.convert(bytes).toString();

ProfileReferenceFile _file({
  String sha = '',
  String extension = '.vbo',
  int bytes = 1000,
  String name = 'friend.vbo',
  int lap = 3,
  Map<String, Object?> unknown = const {},
}) => ProfileReferenceFile(
  recordingId: name,
  lapNumber: lap,
  sha256: sha.isEmpty ? 'a' * 64 : sha,
  extension: extension,
  bytes: bytes,
  name: name,
  unknown: unknown,
);

/// A profile of days `d0`, `d1`, … that only have a name (as days found in
/// the days folder do).
DriverProfile _days(int count) {
  var profile = DriverProfile.empty(Random(1));
  for (var i = 0; i < count; i++) {
    profile = addDayToProfile(
      profile,
      ProfileDayInput(eventId: 'd$i', file: 'Days/d$i.fetproject', name: 'Day $i'),
      defaultCarName: 'Car',
      defaultTrackName: 'Track',
      random: Random(i),
    );
  }
  return profile;
}

DriverProfile _roundTrip(DriverProfile profile) =>
    decodeDriverProfile(encodeDriverProfile(profile));

Map<String, Object?> _json(DriverProfile profile) =>
    jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;

Map<String, Object?> _dayJson(DriverProfile profile, String id) =>
    [for (final day in _json(profile)['days'] as List) day as Map<String, Object?>]
        .firstWhere((day) => day['eventId'] == id);

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('reference'));
  tearDown(() => directory.deleteSync(recursive: true));

  String root() => directory.resolveSymbolicLinksSync();

  group('the format', () {
    test('a reference is written on its day only when there is one, and read back', () {
      var profile = _days(2);
      expect(_dayJson(profile, 'd0').containsKey('reference'), isFalse);
      expect(profile.day('d0')!.reference, isNull);

      final file = _file(sha: 'b' * 64, bytes: 1234, name: 'friend.vbo', lap: 3);
      profile = setProfileDayReference(profile, 'd0', file);
      expect(_dayJson(profile, 'd0')['reference'], {
        'kind': 'file',
        'name': 'friend.vbo',
        'recordingId': 'friend.vbo',
        'lapNumber': 3,
        'sha256': 'b' * 64,
        'extension': '.vbo',
        'bytes': 1234,
      });
      // Nothing on the other day, and nothing on the track or the profile.
      expect(_dayJson(profile, 'd1').containsKey('reference'), isFalse);
      expect(jsonEncode(_json(profile)['tracks']), isNot(contains('friend')));

      profile = setProfileDayReference(
        profile,
        'd1',
        ProfileReferenceDay(recordingId: 'run9', lapNumber: 2, eventId: 'd0', name: 'Day 0'),
      );
      expect(_dayJson(profile, 'd1')['reference'], {
        'kind': 'day',
        'name': 'Day 0',
        'recordingId': 'run9',
        'lapNumber': 2,
        'eventId': 'd0',
      });

      final read = _roundTrip(profile);
      final readFile = read.day('d0')!.reference as ProfileReferenceFile;
      expect(readFile.sha256, 'b' * 64);
      expect(readFile.fileName, '${'b' * 64}.vbo');
      expect(readFile.file, 'Recordings/${'b' * 64}.vbo');
      expect(readFile.bytes, 1234);
      expect(readFile.lapNumber, 3);
      expect(readFile.recordingId, 'friend.vbo');
      final readDay = read.day('d1')!.reference as ProfileReferenceDay;
      expect(readDay.eventId, 'd0');
      expect(readDay.recordingId, 'run9');
      expect(encodeDriverProfile(read), encodeDriverProfile(profile));

      // Cleared, the key goes again.
      profile = setProfileDayReference(profile, 'd0', null);
      expect(_dayJson(profile, 'd0').containsKey('reference'), isFalse);
      expect(profile.day('d1')!.reference, isNotNull);
    });

    test('unknown keys are kept, on the reference and on the day', () {
      var profile = setProfileDayReference(_days(1), 'd0', _file(unknown: {'later': 7}));
      final json = _json(profile);
      final day = (json['days'] as List).single as Map<String, Object?>;
      day['futureDayKey'] = {
        'a': [1, 2],
      };
      (day['reference'] as Map<String, Object?>)['futureReferenceKey'] = 'kept';
      profile = decodeDriverProfile(jsonEncode(json));
      final again = _dayJson(_roundTrip(profile), 'd0');
      expect(again['futureDayKey'], {
        'a': [1, 2],
      });
      final reference = again['reference'] as Map<String, Object?>;
      expect(reference['futureReferenceKey'], 'kept');
      expect(reference['later'], 7);
      // Choosing another lap of the file keeps what is known of it.
      final file = profile.day('d0')!.reference as ProfileReferenceFile;
      profile = setProfileDayReference(profile, 'd0', file.withLap('friend.vbo', 5));
      expect(((_dayJson(profile, 'd0'))['reference'] as Map)['lapNumber'], 5);
      expect(((_dayJson(profile, 'd0'))['reference'] as Map)['futureReferenceKey'], 'kept');
      expect(_dayJson(profile, 'd0')['futureDayKey'], {
        'a': [1, 2],
      });
    });

    test(
      'a reference this version cannot read is kept as written and never refuses the profile',
      () {
        final unreadable = <Object?>[
          {'kind': 'tape', 'recordingId': 'x', 'lapNumber': 1},
          {
            'kind': 'file',
            'recordingId': 'x',
            'lapNumber': 1,
            'sha256': '../../etc/passwd',
            'extension': '.vbo',
            'bytes': 5,
          },
          {
            'kind': 'file',
            'recordingId': 'x',
            'lapNumber': 1,
            'sha256': 'A' * 64,
            'extension': '.vbo',
            'bytes': 5,
          },
          {
            'kind': 'file',
            'recordingId': 'x',
            'lapNumber': 1,
            'sha256': 'a' * 64,
            'extension': '.exe',
            'bytes': 5,
          },
          {
            'kind': 'file',
            'recordingId': 'x',
            'lapNumber': 1,
            'sha256': 'a' * 64,
            'extension': '/../.vbo',
            'bytes': 5,
          },
          {
            'kind': 'file',
            'recordingId': 'x',
            'lapNumber': 1,
            'sha256': 'a' * 64,
            'extension': '.vbo',
            'bytes': 0,
          },
          {
            'kind': 'file',
            'recordingId': 'x',
            'lapNumber': 1,
            'sha256': 'a' * 64,
            'extension': '.vbo',
            'bytes': maximumReferenceFileBytes + 1,
          },
          {
            'kind': 'file',
            'recordingId': 'x',
            'lapNumber': 0,
            'sha256': 'a' * 64,
            'extension': '.vbo',
            'bytes': 5,
          },
          {
            'kind': 'file',
            'recordingId': 'x',
            'lapNumber': 1.5,
            'sha256': 'a' * 64,
            'extension': '.vbo',
            'bytes': 5,
          },
          {
            'kind': 'file',
            'recordingId': '',
            'lapNumber': 1,
            'sha256': 'a' * 64,
            'extension': '.vbo',
            'bytes': 5,
          },
          {'kind': 'day', 'recordingId': 'x', 'lapNumber': 1},
          {'kind': 'day', 'recordingId': 'x', 'lapNumber': 1, 'eventId': 'd0'},
          'a path: /home/me/friend.vbo',
          42,
          [1],
          null,
        ];
        for (final value in unreadable) {
          final json = _json(_days(1));
          ((json['days'] as List).single as Map<String, Object?>)['reference'] = value;
          final profile = decodeDriverProfile(jsonEncode(json));
          final day = profile.day('d0')!;
          expect(day.reference, isNull, reason: '$value');
          // Written back as it was.
          final written = _dayJson(_roundTrip(profile), 'd0');
          if (value == null) continue;
          expect(written['reference'], value, reason: '$value');
        }
      },
    );

    test('setting or clearing a reference replaces one this version could not read', () {
      final json = _json(_days(1));
      ((json['days'] as List).single as Map<String, Object?>)['reference'] = {'kind': 'tape'};
      var profile = decodeDriverProfile(jsonEncode(json));
      expect(_dayJson(profile, 'd0')['reference'], {'kind': 'tape'});
      profile = setProfileDayReference(profile, 'd0', _file());
      expect((_dayJson(profile, 'd0')['reference'] as Map)['kind'], 'file');
      final cleared = setProfileDayReference(decodeDriverProfile(jsonEncode(json)), 'd0', null);
      expect(_dayJson(cleared, 'd0').containsKey('reference'), isFalse);
    });

    test('a day added again, or given weather or setups, keeps its reference', () {
      var profile = setProfileDayReference(_days(1), 'd0', _file(sha: 'c' * 64));
      profile = addDayToProfile(
        profile,
        ProfileDayInput(eventId: 'd0', file: 'Days/d0.fetproject', name: 'Renamed'),
        defaultCarName: 'Car',
        defaultTrackName: 'Track',
      );
      expect(profile.day('d0')!.name, 'Renamed');
      expect((profile.day('d0')!.reference as ProfileReferenceFile).sha256, 'c' * 64);
      expect(setProfileSessionWeather(profile, 'd0', const {}).day('d0')!.reference, isNotNull);
      expect(setProfileSessionSetups(profile, 'd0', const {}).day('d0')!.reference, isNotNull);
      expect(
        setProfileDayCar(profile, 'd0', profile.cars.single.id).day('d0')!.reference,
        isNotNull,
      );
    });

    test('a reference to a day not in the profile, or on a day not in it, is unchanged', () {
      final profile = _days(1);
      expect(identical(setProfileDayReference(profile, 'nope', _file()), profile), isTrue);
      // Clearing nothing changes nothing.
      expect(identical(setProfileDayReference(profile, 'd0', null), profile), isTrue);
      final set = setProfileDayReference(profile, 'd0', _file());
      expect(identical(setProfileDayReference(set, 'd0', _file()), set), isTrue);
    });

    test('a day removed takes its reference with it', () {
      var profile = setProfileDayReference(_days(2), 'd0', _file());
      profile = removeProfileDay(profile, 'd0');
      expect(jsonEncode(_json(profile)), isNot(contains('friend')));
    });

    test('names are bounded and tidied', () {
      final long = 'n' * 400;
      final profile = setProfileDayReference(
        _days(1),
        'd0',
        ProfileReferenceDay(
          recordingId: ' run\u0000 ',
          lapNumber: 1,
          eventId: 'd1',
          name: '$long ',
        ),
      );
      final day = profile.day('d0')!.reference as ProfileReferenceDay;
      expect(day.recordingId, 'run');
      expect(day.name.length, maximumReferenceNameCharacters);
    });
  });

  group('limits', () {
    test('a lap, a recording id and a recording the profile cannot keep are refused', () {
      final profile = _days(2);
      ProfileReferenceProblem? problem(ProfileReference reference, [String day = 'd0']) {
        try {
          setProfileDayReference(profile, day, reference);
          return null;
        } on ProfileReferenceError catch (error) {
          return error.problem;
        }
      }

      expect(problem(_file(lap: 0)), ProfileReferenceProblem.invalid);
      expect(problem(_file(lap: maximumReferenceLapNumber + 1)), ProfileReferenceProblem.invalid);
      expect(problem(_file(lap: maximumReferenceLapNumber)), isNull);
      expect(
        problem(ProfileReferenceDay(recordingId: ' ', lapNumber: 1, eventId: 'd1')),
        ProfileReferenceProblem.invalid,
      );
      expect(
        problem(ProfileReferenceDay(recordingId: 'r', lapNumber: 1, eventId: 'd0')),
        ProfileReferenceProblem.invalid,
        reason: 'a day is not its own reference',
      );
      expect(problem(_file(extension: '.exe')), ProfileReferenceProblem.fileType);
      expect(problem(_file(sha: 'xyz')), ProfileReferenceProblem.fileType);
      expect(problem(_file(bytes: 0)), ProfileReferenceProblem.fileEmpty);
      expect(
        problem(_file(bytes: maximumReferenceFileBytes + 1)),
        ProfileReferenceProblem.fileTooLarge,
      );
      expect(problem(_file(bytes: maximumReferenceFileBytes)), isNull);
    });

    test('a recording is counted once however many days use it, up to the most', () {
      var profile = _days(maximumReferenceFiles + 2);
      for (var i = 0; i < maximumReferenceFiles; i++) {
        profile = setProfileDayReference(
          profile,
          'd$i',
          _file(sha: i.toRadixString(16).padLeft(64, '0'), bytes: 100),
        );
      }
      // The same file for another day is the same copy: no room needed.
      final shared = setProfileDayReference(
        profile,
        'd$maximumReferenceFiles',
        _file(sha: '0'.padLeft(64, '0'), bytes: 100),
      );
      expect(shared.day('d$maximumReferenceFiles')!.reference, isNotNull);
      // A new file is the 33rd.
      expect(
        () => setProfileDayReference(
          profile,
          'd$maximumReferenceFiles',
          _file(sha: 'f' * 64, bytes: 100),
        ),
        throwsA(
          isA<ProfileReferenceError>().having(
            (error) => error.problem,
            'problem',
            ProfileReferenceProblem.tooManyFiles,
          ),
        ),
      );
      // A day that has a file may change to a new one: its own is freed.
      final swapped = setProfileDayReference(profile, 'd0', _file(sha: 'f' * 64, bytes: 100));
      expect(profileReferenceFiles(swapped), hasLength(maximumReferenceFiles));
      // The profile is unchanged by a refusal, and still reads.
      expect(profileReferenceFiles(profile), hasLength(maximumReferenceFiles));
      expect(_roundTrip(profile).days.where((day) => day.reference != null), hasLength(32));
    });

    test('all the recordings together take at most maximumReferenceBytes', () {
      var profile = _days(5);
      const each = maximumReferenceFileBytes;
      for (var i = 0; i < maximumReferenceBytes ~/ each; i++) {
        profile = setProfileDayReference(
          profile,
          'd$i',
          _file(sha: '$i'.padLeft(64, 'a'), bytes: each),
        );
      }
      expect(
        () => setProfileDayReference(profile, 'd4', _file(sha: 'e' * 64, bytes: 1)),
        throwsA(
          isA<ProfileReferenceError>().having(
            (error) => error.problem,
            'problem',
            ProfileReferenceProblem.tooMuch,
          ),
        ),
      );
    });

    test('a profile read with more than the limits is not refused', () {
      var profile = _days(maximumReferenceFiles + 3);
      final json = _json(profile);
      for (final (index, day) in (json['days'] as List).indexed) {
        (day as Map<String, Object?>)['reference'] = {
          'kind': 'file',
          'recordingId': 'f$index',
          'lapNumber': 1,
          'sha256': _shaOf(index),
          'extension': '.rcz',
          'bytes': 10,
        };
      }
      profile = decodeDriverProfile(jsonEncode(json));
      expect(profile.days.where((day) => day.reference != null), hasLength(35));
      // Changing a day to a file already there still works; a new one is
      // refused until room is made.
      expect(
        setProfileDayReference(
          profile,
          'd0',
          _file(sha: _shaOf(1), bytes: 10, extension: '.rcz'),
        ).day('d0')!.reference,
        isNotNull,
      );
      expect(
        () => setProfileDayReference(
          profile,
          'd0',
          _file(sha: 'f' * 64, bytes: 10, extension: '.rcz'),
        ),
        throwsA(isA<ProfileReferenceError>()),
      );
    });
  });

  group('the copy of a recording', () {
    String write(String name, List<int> content) {
      final path = p.join(root(), 'in', name);
      Directory(p.dirname(path)).createSync(recursive: true);
      File(path).writeAsBytesSync(content);
      return path;
    }

    test('is made once per content, named by its hash, whatever the file was called', () {
      final folder = p.join(root(), 'Profile');
      final content = utf8.encode(circuitVbo([30, 29, 31]));
      final first = keepReferenceFile(folder, write('Friend.VBO', content));
      expect(first.sha256, _hash(content));
      expect(first.extension, '.vbo');
      expect(first.bytes, content.length);
      final copy = p.join(folder, 'Recordings', '${first.sha256}.vbo');
      expect(File(copy).readAsBytesSync(), content);
      // Another file with the same content is the same copy.
      final second = keepReferenceFile(folder, write('instructor/other name.vbo', content));
      expect(second.sha256, first.sha256);
      expect(Directory(p.join(folder, 'Recordings')).listSync(), hasLength(1));
      // The copy has the reference's own name, never the source's path.
      final reference = first.reference('Friend.VBO', 'Friend.VBO', 2);
      expect(profileReferenceFilePath(folder, reference), copy);
      expect(
        jsonEncode(_json(setProfileDayReference(_days(1), 'd0', reference))),
        isNot(contains('/in/')),
      );
      // A damaged copy is replaced by the file just read.
      File(copy).writeAsBytesSync([...content]..[3] ^= 0xff);
      keepReferenceFile(folder, write('again.vbo', content));
      expect(File(copy).readAsBytesSync(), content);
    });

    test('refuses what is not a recording, is empty, too large or unreadable, leaving nothing', () {
      final folder = p.join(root(), 'Profile');
      void refused(String path, ProfileReferenceProblem problem) {
        expect(
          () => keepReferenceFile(folder, path),
          throwsA(isA<ProfileReferenceError>().having((e) => e.problem, 'problem', problem)),
          reason: path,
        );
      }

      refused(write('notes.txt', [1, 2, 3]), ProfileReferenceProblem.fileType);
      refused(write('empty.vbo', const []), ProfileReferenceProblem.fileEmpty);
      refused(p.join(root(), 'in', 'missing.vbo'), ProfileReferenceProblem.fileUnreadable);
      Directory(p.join(root(), 'in', 'folder.vbo')).createSync(recursive: true);
      refused(p.join(root(), 'in', 'folder.vbo'), ProfileReferenceProblem.fileUnreadable);
      final big = File(p.join(root(), 'in', 'big.rcz'))..createSync(recursive: true);
      final handle = big.openSync(mode: FileMode.write)
        ..truncateSync(maximumReferenceFileBytes + 1);
      handle.closeSync();
      refused(big.path, ProfileReferenceProblem.fileTooLarge);
      final recordings = Directory(p.join(folder, 'Recordings'));
      expect(!recordings.existsSync() || recordings.listSync().isEmpty, isTrue);
    });

    test('is deleted when nothing uses it, and kept while a day or reference does', () {
      final folder = p.join(root(), 'Profile');
      final content = utf8.encode(circuitVbo([30, 29, 31]));
      final copy = keepReferenceFile(folder, write('a.vbo', content));
      final reference = copy.reference('a.vbo', 'a.vbo', 1);
      final path = profileReferenceFilePath(folder, reference)!;
      expect(
        deleteUnusedReferenceFile(
          folder: folder,
          reference: reference,
          stillReferenced: {reference.fileName},
          dayPaths: const [],
        ),
        isFalse,
      );
      expect(File(path).existsSync(), isTrue);
      expect(
        deleteUnusedReferenceFile(
          folder: folder,
          reference: reference,
          stillReferenced: const {},
          dayPaths: [p.join(folder, 'Days', 'unreadable.fetproject')],
        ),
        isFalse,
        reason: 'a day that cannot be read may use it',
      );
      expect(
        deleteUnusedReferenceFile(
          folder: folder,
          reference: reference,
          stillReferenced: const {},
          dayPaths: const [],
        ),
        isTrue,
      );
      expect(File(path).existsSync(), isFalse);
    });

    test('is never found outside Recordings, whatever the profile says', () {
      final folder = p.join(root(), 'Profile');
      for (final bad in ['../../x', 'a/b', 'A' * 64, '${'a' * 63}/', '..']) {
        expect(profileReferenceFilePath(folder, _file(sha: bad)), isNull, reason: bad);
      }
      expect(profileReferenceFilePath(folder, _file(extension: '/../../x')), isNull);
      expect(
        p.isWithin(p.join(folder, 'Recordings'), profileReferenceFilePath(folder, _file())!),
        isTrue,
      );
    });
  });

  group('days and bundles', () {
    /// A day saved in the profile at [folder], its recordings written to
    /// [recordings] outside it.
    Future<DriverProfile> saveDay(
      DriverProfile profile,
      String folder,
      String recordings,
      String eventId,
      List<List<double>> sessions,
    ) async {
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
      return addDayToProfile(
        profile,
        ProfileDayInput.fromAnalysis(
          eventId: eventId,
          file: 'Days/$eventId.fetproject',
          name: 'Day $eventId',
          analysis: analysis,
        ),
        defaultCarName: 'Clio',
        defaultTrackName: 'Track',
        random: Random(eventId.hashCode),
      );
    }

    String friend(String name, List<double> speeds) {
      final path = p.join(root(), 'friend', name);
      Directory(p.dirname(path)).createSync(recursive: true);
      File(path).writeAsStringSync(circuitVbo(speeds));
      return path;
    }

    Future<(DriverProfile, String, ReferenceFileCopy)> twoDaysWithReference() async {
      final a = p.join(root(), 'A');
      var profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      profile = await saveDay(profile, a, p.join(a, 'in'), 'e2', [
        [31, 30, 29],
      ]);
      final copy = keepReferenceFile(a, friend('friend.vbo', [27, 26, 28]));
      profile = setProfileDayReference(
        profile,
        'e1',
        copy.reference('friend.vbo', 'friend.vbo', 2),
      );
      profile = setProfileDayReference(
        profile,
        'e2',
        copy.reference('friend.vbo', 'friend.vbo', 3),
      );
      return (profile, a, copy);
    }

    test('the references and their one copy travel in a bundle and are not duplicated', () async {
      final (profile, a, copy) = await twoDaysWithReference();
      final bundle = p.join(root(), 'driver$profileBundleExtension');
      final export = await writeProfileBundle(profile, a, bundle);
      expect(export.days, 2);
      expect(export.referencesMissing, 0);
      final names = [
        for (final entry in ZipDecoder().decodeBytes(File(bundle).readAsBytesSync())) entry.name,
      ];
      expect(
        names.where((name) => name == 'Recordings/${copy.sha256}.vbo'),
        hasLength(1),
        reason: 'two days, one copy',
      );
      // Two day recordings and the reference.
      expect(names.where((name) => name.startsWith('Recordings/')), hasLength(3));

      final b = p.join(root(), 'B');
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.added, ['e1', 'e2']);
      expect(read.referencesNotKept, isEmpty);
      expect(read.referencesMissing, 0);
      expect(read.recordings, 3);
      for (final id in ['e1', 'e2']) {
        final reference = read.profile.day(id)!.reference as ProfileReferenceFile;
        expect(reference.sha256, copy.sha256);
        expect(reference.lapNumber, id == 'e1' ? 2 : 3);
        final file = profileReferenceFilePath(b, reference)!;
        expect(_hash(File(file).readAsBytesSync()), copy.sha256);
      }
      // Reading it again adds nothing.
      final again = await readProfileBundle(read.profile, b, bundle);
      expect(again.added, isEmpty);
      expect(again.recordings, 0);
      expect(
        Directory(p.join(b, 'Recordings')).listSync().where((e) => e.path.endsWith('.vbo')),
        hasLength(3),
      );
    });

    test('a recording that is also a day recording is one file in the bundle', () async {
      final a = p.join(root(), 'A');
      var profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      // The reference is the very recording the day was made from, copied
      // by its content as a day's recording is named in a bundle.
      final copy = keepReferenceFile(a, p.join(a, 'in', 'e1-0.vbo'));
      profile = setProfileDayReference(profile, 'e1', copy.reference('e1-0.vbo', 'e1-0.vbo', 1));
      final bundle = p.join(root(), 'x$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final names = [
        for (final entry in ZipDecoder().decodeBytes(File(bundle).readAsBytesSync()))
          if (entry.name.startsWith('Recordings/')) entry.name,
      ];
      expect(names, ['Recordings/${copy.sha256}.vbo']);
      final b = p.join(root(), 'B');
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.added, ['e1']);
      expect(read.recordings, 1);
      expect(read.profile.day('e1')!.reference, isNotNull);
    });

    test(
      'a reference listed before the day recording of the same content shares its file',
      () async {
        final a = p.join(root(), 'A');
        var profile = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
          [30, 28, 31],
        ]);
        profile = await saveDay(profile, a, p.join(a, 'in'), 'e2', [
          [31, 30, 29],
        ]);
        // e1 takes e2's recording as its reference; e1 is written first.
        final copy = keepReferenceFile(a, p.join(a, 'in', 'e2-0.vbo'));
        profile = setProfileDayReference(profile, 'e1', copy.reference('e2-0.vbo', 'e2-0.vbo', 1));
        final bundle = p.join(root(), 'x$profileBundleExtension');
        await writeProfileBundle(profile, a, bundle);
        final names = [
          for (final entry in ZipDecoder().decodeBytes(File(bundle).readAsBytesSync()))
            if (entry.name.startsWith('Recordings/')) entry.name,
        ];
        expect(names, hasLength(2));
        expect(names, contains('Recordings/${copy.sha256}.vbo'));
        final b = p.join(root(), 'B');
        final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
        expect(read.added, ['e1', 'e2']);
        expect(read.recordings, 2);
        expect(read.referencesNotKept, isEmpty);
        final reference = read.profile.day('e1')!.reference as ProfileReferenceFile;
        expect(File(profileReferenceFilePath(b, reference)!).existsSync(), isTrue);
      },
    );

    test(
      'a day already here keeps its reference; one brought does not touch this profile\'s',
      () async {
        final (profile, a, copy) = await twoDaysWithReference();
        final bundle = p.join(root(), 'driver$profileBundleExtension');
        await writeProfileBundle(profile, a, bundle);
        final mine = setProfileDayReference(
          profile,
          'e1',
          ProfileReferenceDay(recordingId: 'run', lapNumber: 1, eventId: 'e2', name: 'Day e2'),
        );
        final read = await readProfileBundle(mine, a, bundle);
        expect(read.added, isEmpty);
        expect(read.alreadyHere, ['e1', 'e2']);
        expect(read.profile.day('e1')!.reference, isA<ProfileReferenceDay>());
        expect(copy.bytes, greaterThan(0));
      },
    );

    test('a reference missing from the bundle comes along and says so', () async {
      final (profile, a, copy) = await twoDaysWithReference();
      File(p.join(a, 'Recordings', '${copy.sha256}.vbo')).deleteSync();
      final bundle = p.join(root(), 'driver$profileBundleExtension');
      final export = await writeProfileBundle(profile, a, bundle);
      expect(export.referencesMissing, 1);
      final b = p.join(root(), 'B');
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.added, ['e1', 'e2']);
      expect(read.referencesMissing, 1);
      expect(read.profile.day('e1')!.reference, isNotNull);
      expect(
        File(
          profileReferenceFilePath(b, read.profile.day('e1')!.reference as ProfileReferenceFile)!,
        ).existsSync(),
        isFalse,
      );
    });

    String rewritten(String bundle, String path, List<int>? Function(String name) change) {
      final out = Archive();
      for (final entry in ZipDecoder().decodeBytes(File(bundle).readAsBytesSync())) {
        out.addFile(ArchiveFile.bytes(entry.name, change(entry.name) ?? entry.content));
      }
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(out));
      return path;
    }

    test('hostile references in a bundle write nothing or are left out', () async {
      final (profile, a, copy) = await twoDaysWithReference();
      final bundle = p.join(root(), 'driver$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final name = 'Recordings/${copy.sha256}.vbo';
      final b = p.join(root(), 'B');
      Directory(b).createSync();

      // Content that is not the hash it is named by.
      final damaged = rewritten(
        bundle,
        p.join(root(), 'damaged.feprofile'),
        (entry) => entry == name ? utf8.encode(circuitVbo([20, 20])) : null,
      );
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, damaged),
        throwsA(isA<ProfileBundleError>()),
      );
      expect(Directory(b).listSync(), isEmpty);

      // A recording larger than a reference may be.
      final index = jsonDecode(
        utf8.decode(
          ZipDecoder()
              .decodeBytes(File(bundle).readAsBytesSync())
              .findFile(profileIndexName)!
              .content,
        ),
      ) as Map<String, Object?>;
      for (final day in index['days'] as List) {
        ((day as Map<String, Object?>)['reference'] as Map<String, Object?>)['bytes'] = 99;
      }
      final lying = rewritten(
        bundle,
        p.join(root(), 'lying.feprofile'),
        (entry) => entry == profileIndexName ? utf8.encode(jsonEncode(index)) : null,
      );
      await expectLater(
        readProfileBundle(DriverProfile.empty(Random(2)), b, lying),
        throwsA(isA<ProfileBundleError>()),
        reason: 'the size the profile says is not the recording\'s',
      );
      expect(Directory(b).listSync(), isEmpty);

      // A reference naming a path instead of a hash is not read at all.
      for (final day in index['days'] as List) {
        ((day as Map<String, Object?>)['reference'] as Map<String, Object?>)['sha256'] =
            '../../../outside';
      }
      final outside = rewritten(
        bundle,
        p.join(root(), 'outside.feprofile'),
        (entry) => entry == profileIndexName ? utf8.encode(jsonEncode(index)) : null,
      );
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, outside);
      expect(read.added, ['e1', 'e2']);
      expect(read.profile.day('e1')!.reference, isNull);
      expect(File(p.join(root(), 'outside')).existsSync(), isFalse);
    });

    test('a different file of the same name in Recordings is never replaced', () async {
      final (profile, a, copy) = await twoDaysWithReference();
      final bundle = p.join(root(), 'driver$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final b = p.join(root(), 'B');
      Directory(p.join(b, 'Recordings')).createSync(recursive: true);
      final planted = File(p.join(b, 'Recordings', '${copy.sha256}.vbo'))
        ..writeAsStringSync('someone else\'s file');
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.added, ['e1', 'e2']);
      expect(planted.readAsStringSync(), 'someone else\'s file');
      expect(read.referencesNotKept, unorderedEquals(['e1', 'e2']));
      expect(read.profile.day('e1')!.reference, isNull);
      expect(read.profile.day('e2')!.reference, isNull);
      // Merged again from the bundle's own profile, they stay out.
      final again = mergeDriverProfile(
        DriverProfile.empty(Random(3)),
        read.source!,
        only: {...read.added},
      );
      expect(again.profile.day('e1')!.reference, isNull);
    });

    test('the same copy already in Recordings is reused, not copied again', () async {
      final (profile, a, copy) = await twoDaysWithReference();
      final bundle = p.join(root(), 'driver$profileBundleExtension');
      await writeProfileBundle(profile, a, bundle);
      final b = p.join(root(), 'B');
      final there = keepReferenceFile(b, p.join(a, 'Recordings', '${copy.sha256}.vbo'));
      expect(there.sha256, copy.sha256);
      final read = await readProfileBundle(DriverProfile.empty(Random(2)), b, bundle);
      expect(read.referencesNotKept, isEmpty);
      expect(read.recordings, 2, reason: 'the two day recordings; the reference was here');
      expect(read.profile.day('e1')!.reference, isNotNull);
    });

    test('a bundle past the limits of reference recordings brings its days without them', () async {
      final a = p.join(root(), 'A');
      var theirs = await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      final copy = keepReferenceFile(a, friend('f.vbo', [25, 25]));
      theirs = setProfileDayReference(theirs, 'e1', copy.reference('f.vbo', 'f.vbo', 1));
      final bundle = p.join(root(), 'driver$profileBundleExtension');
      await writeProfileBundle(theirs, a, bundle);
      // This profile already keeps the most.
      var mine = _days(maximumReferenceFiles);
      for (var i = 0; i < maximumReferenceFiles; i++) {
        mine = setProfileDayReference(
          mine,
          'd$i',
          _file(sha: 'c${i.toRadixString(16)}'.padLeft(64, '0'), bytes: 10),
        );
      }
      final b = p.join(root(), 'B');
      final read = await readProfileBundle(mine, b, bundle);
      expect(read.added, ['e1']);
      expect(read.referencesNotKept, ['e1']);
      expect(read.profile.day('e1')!.reference, isNull);
      expect(
        File(p.join(b, 'Recordings', '${copy.sha256}.vbo')).existsSync(),
        isFalse,
        reason: 'no copy was made for it',
      );
    });

    test('deleting a day deletes its copy unless another day or reference uses it', () async {
      final (profile, a, copy) = await twoDaysWithReference();
      final owned = [p.join(a, 'Recordings')];
      final file = p.join(a, 'Recordings', '${copy.sha256}.vbo');
      expect(File(file).existsSync(), isTrue);
      // e1 goes while e2's reference uses the same copy.
      var deleted = deleteDayFiles(
        dayPath: p.join(a, 'Days', 'e1.fetproject'),
        otherDayPaths: [p.join(a, 'Days', 'e2.fetproject')],
        ownedFolders: owned,
        referenceFile: file,
        otherReferenceFiles: [file],
      );
      expect(File(file).existsSync(), isTrue);
      expect(deleted.recordingsKept, 1);
      expect(File(p.join(a, 'Days', 'e1.fetproject')).existsSync(), isFalse);
      // e2 goes last: the copy goes with it.
      deleted = deleteDayFiles(
        dayPath: p.join(a, 'Days', 'e2.fetproject'),
        otherDayPaths: const [],
        ownedFolders: owned,
        referenceFile: file,
      );
      expect(File(file).existsSync(), isFalse);
      expect(deleted.recordings, greaterThanOrEqualTo(1));
      expect(profile.day('e1')!.reference, isNotNull);
    });

    test('a reference file outside the owned folders is never deleted with a day', () async {
      final a = p.join(root(), 'A');
      await saveDay(DriverProfile.empty(Random(1)), a, p.join(a, 'in'), 'e1', [
        [30, 28, 31],
      ]);
      final mine = friend('mine.vbo', [25, 25]);
      deleteDayFiles(
        dayPath: p.join(a, 'Days', 'e1.fetproject'),
        otherDayPaths: const [],
        ownedFolders: [p.join(a, 'Recordings')],
        referenceFile: mine,
      );
      expect(File(mine).existsSync(), isTrue);
    });
  });

  group('merging profiles', () {
    test('a day brings its reference and a copy both profiles use is one', () {
      final mine = _days(1);
      var theirs = DriverProfile.empty(Random(5));
      for (final id in ['x1', 'x2']) {
        theirs = addDayToProfile(
          theirs,
          ProfileDayInput(eventId: id, file: 'Days/$id.fetproject', name: id),
          defaultCarName: 'Car',
          defaultTrackName: 'T',
          random: Random(id.hashCode),
        );
      }
      theirs = setProfileDayReference(theirs, 'x1', _file(sha: 'd' * 64));
      theirs = setProfileDayReference(
        theirs,
        'x2',
        ProfileReferenceDay(recordingId: 'run', lapNumber: 4, eventId: 'x1', name: 'x1'),
      );
      var merge = mergeDriverProfile(
        setProfileDayReference(mine, 'd0', _file(sha: 'd' * 64)),
        theirs,
      );
      expect(merge.added, ['x1', 'x2']);
      expect(merge.referencesNotKept, isEmpty);
      expect(profileReferenceFiles(merge.profile), hasLength(1));
      expect(merge.profile.day('x2')!.reference, isA<ProfileReferenceDay>());
      expect((merge.profile.day('x2')!.reference as ProfileReferenceDay).eventId, 'x1');
      // A day already here is left as it is.
      merge = mergeDriverProfile(merge.profile, theirs);
      expect(merge.added, isEmpty);
      expect(identical(merge.profile.day('x1'), merge.profile.day('x1')), isTrue);
    });

    test('past the limit a day comes without its reference, which is reported', () {
      var mine = _days(maximumReferenceFiles);
      for (var i = 0; i < maximumReferenceFiles; i++) {
        mine = setProfileDayReference(mine, 'd$i', _file(sha: _shaOf(i), bytes: 10));
      }
      var theirs = DriverProfile.empty(Random(5));
      theirs = addDayToProfile(
        theirs,
        ProfileDayInput(eventId: 'x1', file: 'Days/x1.fetproject', name: 'x1'),
        defaultCarName: 'Car',
        defaultTrackName: 'T',
      );
      theirs = setProfileDayReference(theirs, 'x1', _file(sha: 'e' * 64));
      final merge = mergeDriverProfile(mine, theirs);
      expect(merge.added, ['x1']);
      expect(merge.referencesNotKept, ['x1']);
      expect(merge.profile.day('x1')!.reference, isNull);
      expect(_dayJson(merge.profile, 'x1').containsKey('reference'), isFalse);
    });

    test('a reference this version cannot read is carried as written', () {
      final json = _json(_days(1));
      ((json['days'] as List).single as Map<String, Object?>)['reference'] = {
        'kind': 'tape',
        'n': 1,
      };
      final theirs = decodeDriverProfile(jsonEncode(json));
      final merge = mergeDriverProfile(DriverProfile.empty(Random(9)), theirs);
      expect(merge.added, ['d0']);
      expect(_dayJson(merge.profile, 'd0')['reference'], {'kind': 'tape', 'n': 1});
    });
  });
}
