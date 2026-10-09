// Cases ported from FlappedEar Overlays' EventProjectTests (VBOOverlay
// ca2bde5); every document here is synthetic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart';
import 'package:fetproject/src/event_document.dart' show writeDocumentInPlace;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Map<String, Object?> source(String id, String path) => {
  'id': id,
  'reference': {'relativePath': path, 'futureReference': 42},
  'provenance': {'note': 'synthetic fixture'},
};

Map<String, Object?> run(String id, String path, num offset) => {
  'id': id,
  'name': id,
  'primaryTelemetrySourceId': '$id-source',
  'sources': <String, Object?>{
    'telemetry': <Object?>[source('$id-source', path)],
  },
  'sync': {'offset': offset, 'timeScale': 1, 'futureSync': true},
  'notes': 'Retain my setup notes',
};

/// Overlays' EventProjectFixture::project(), with unknown keys at each level,
/// as a reader returns it.
Map<String, Object?> project() =>
    qtJsonDecode(jsonEncode(_project())) as Map<String, Object?>;

Map<String, Object?> _project() {
  final first = run('run-a', 'run-a.vbo', 2.5);
  final sources = first['sources'] as Map<String, Object?>;
  (sources['telemetry'] as List).add(source('run-a-alternative', 'run-a.rcz'));
  sources['video'] = {'relativePath': 'run-a.mp4', 'futureVideo': 7};
  return {
    'version': 3,
    'scene': {'widgets': <Object?>[]},
    'event': {
      'id': 'event-identity',
      'name': 'Development event',
      'activeRunId': 'run-a',
      'runs': [first, run('run-b', 'run-b.vbo', -1.5)],
      'futureEvent': true,
    },
    'documentState': {'id': 'event-document', 'savedRevision': '4'},
    'futureRoot': 8,
  };
}

Map<String, Object?> event(Map<String, Object?> document) =>
    document['event'] as Map<String, Object?>;
List<Object?> runs(Map<String, Object?> document) =>
    event(document)['runs'] as List<Object?>;
Map<String, Object?> firstRun(Map<String, Object?> document) =>
    runs(document).first as Map<String, Object?>;

/// A fresh fixture with [mutate] applied.
Map<String, Object?> mutated(void Function(Map<String, Object?>) mutate) =>
    project()..let(mutate);

/// A fresh fixture with [mutate] applied to its first run.
Map<String, Object?> withRun(void Function(Map<String, Object?>) mutate) =>
    mutated((document) => mutate(firstRun(document)));

extension<T> on T {
  void let(void Function(T) action) => action(this);
}

final _a64 = 'a' * 64;

Map<String, Object?> unknownConfiguration(Map<String, Object?> run) => {
  'layoutId': null,
  'direction': 'unknown',
  'gateRevision': null,
  'sourceId': run['primaryTelemetrySourceId'],
  'sourceFingerprint': primaryFingerprint(run),
};

void main() {
  test('accepts the fixture and the Overlays sample document', () {
    expect(validateFetproject(project()), isNull);
    final sample = File('test/fixtures/event-demo.fetproject')
        .readAsBytesSync();
    final decoded = decodeFetproject(sample);
    expect(event(decoded)['activeRunId'], 'demo-laps');
  });

  test('accepts a document without a scene, but not a malformed scene', () {
    final analysisOnly = project()..remove('scene');
    expect(validateFetproject(analysisOnly), isNull);
    analysisOnly['scene'] = {'widgets': 'not an array'};
    expect(validateFetproject(analysisOnly), isNotNull);
  });

  test('refuses single-recording version 2 projects with a reason', () {
    final v2 = utf8.encode(jsonEncode(project()..['version'] = 2));
    expect(
      () => decodeFetproject(v2),
      throwsA(
        isA<FetprojectError>().having(
          (error) => error.message,
          'message',
          contains('version 2'),
        ),
      ),
    );
  });

  test('refuses oversized, deep and non-JSON documents', () {
    expect(
      () => decodeFetproject(List.filled(maximumProjectBytes + 1, 32)),
      throwsA(isA<FetprojectError>()),
    );
    expect(
      () => decodeFetproject(utf8.encode('{"version": 3,')),
      throwsA(isA<FetprojectError>()),
    );
    Object? deep = 1;
    for (var i = 0; i < 40; ++i) {
      deep = [deep];
    }
    expect(
      validateFetproject(project()..['futureRoot'] = deep),
      contains('nesting'),
    );
    expect(
      validateFetproject(project()..['futureRoot'] = 'x' * 4097),
      contains('JSON string'),
    );
  });

  test(
    'deeply nested JSON in a small document is a format error, not a crash',
    () {
      for (final depth in [40, 10000, 100000, 1000000]) {
        final bytes = utf8.encode('{"unknown":${'[' * depth}0${']' * depth}}');
        expect(
          () => decodeFetproject(bytes),
          throwsA(
            isA<FetprojectError>().having(
              (error) => error.message,
              'message',
              'JSON nesting exceeds $maximumJsonDepth levels.',
            ),
          ),
          reason: 'depth $depth',
        );
      }
    },
  );

  group('rejects malformed events', () {
    final cases = <String, Map<String, Object?>>{
      for (final key in ['sources', 'sync', 'videoPath', 'vboPath'])
        'root $key': mutated((d) => d[key] = <String, Object?>{}),
      'v2 event': mutated((d) => d['version'] = 2),
      'fractional version': mutated((d) => d['version'] = 3.1),
      'missing event': mutated((d) => d.remove('event')),
      'empty runs': mutated((d) => event(d)['runs'] = <Object?>[]),
      'unknown active run': mutated((d) => event(d)['activeRunId'] = 'missing'),
      'duplicate run': mutated((d) => runs(d).add(firstRun(project()))),
      'foreign primary': withRun(
        (r) => r['primaryTelemetrySourceId'] = 'run-b-source',
      ),
      'empty name': withRun((r) => r['name'] = '  '),
      'long name': withRun((r) => r['name'] = 'x' * 161),
      'NUL in name': withRun((r) => r['name'] = 'x\u0000'),
      'long id': withRun((r) => r['id'] = 'x' * 129),
      'text offset': withRun(
        (r) => r['sync'] = {'offset': '2.5', 'timeScale': 1.0},
      ),
      'zero scale': withRun((r) => r['sync'] = {'offset': 0, 'timeScale': 0}),
      'null sync': withRun((r) => r['sync'] = null),
      'no sources': withRun((r) => r['sources'] = <String, Object?>{}),
      'empty video': withRun(
        (r) => (r['sources'] as Map)['video'] = <String, Object?>{},
      ),
      'duplicate source': withRun((r) {
        final telemetry = (r['sources'] as Map)['telemetry'] as List;
        telemetry.add(telemetry.first);
      }),
      'cross-run source id': withRun((r) {
        final telemetry = (r['sources'] as Map)['telemetry'] as List;
        (telemetry[1] as Map)['id'] = 'run-b-source';
      }),
      'relative as absolute': withRun(
        (r) => (r['sources'] as Map)['video'] = {'absolutePath': 'camera.mp4'},
      ),
      'absolute as relative': withRun(
        (r) => (r['sources'] as Map)['video'] = {'relativePath': '/camera.mp4'},
      ),
      'fingerprint not an object': withRun(
        (r) => (r['sources'] as Map)['video'] = {
          'relativePath': 'camera.mp4',
          'fingerprint': 3,
        },
      ),
      'short content digest': withRun(
        (r) =>
            (((r['sources'] as Map)['telemetry'] as List).first
                    as Map)['contentSha256'] =
                'a',
      ),
      'notes not text': withRun((r) => r['notes'] = 42),
      'long notes': withRun((r) => r['conditions'] = 'x' * 4097),
    };
    cases.forEach((name, document) {
      test(name, () => expect(validateFetproject(document), isNotNull));
    });
  });

  test('keeps run metadata within bounds, including unknown text', () {
    for (final value in [null, '', 'x' * 4096]) {
      final document = withRun((r) {
        r['setupChanges'] = value;
        r['futureRun'] = {'retained': true};
      });
      expect(validateFetproject(document), isNull);
    }
  });

  test('bounds runs and sources', () {
    final document = project();
    event(document)['runs'] = [
      for (var i = 0; i < 64; ++i) run(i == 0 ? 'run-a' : '$i', 'a.vbo', 0),
    ];
    expect(validateFetproject(document), isNull);
    runs(document).add(run('excess', 'a.vbo', 0));
    expect(validateFetproject(document), contains('1–64 runs'));

    final crowded = withRun((r) {
      final telemetry = (r['sources'] as Map)['telemetry'] as List;
      for (var i = 2; i < 9; ++i) {
        telemetry.add(source('$i', 'a.rcz'));
      }
    });
    expect(validateFetproject(crowded), contains('1–8 telemetry sources'));
  });

  group('track configuration', () {
    Map<String, Object?> configured(String field, Object? value) =>
        withRun((r) {
          final config = unknownConfiguration(r);
          if (value == #absent) {
            config.remove(field);
          } else {
            config[field] = value;
          }
          r['trackConfiguration'] = config;
        });

    test('accepts the unknown configuration bound to the primary source', () {
      expect(
        validateFetproject(
          withRun((r) {
            r['trackConfiguration'] = unknownConfiguration(r);
          }),
        ),
        isNull,
      );
      expect(
        validateFetproject(configured('gateRevision', 'gates-v1:$_a64')),
        isNull,
      );
      // A final newline is rejected in both apps (KAN-181).
      expect(
        validateFetproject(configured('gateRevision', 'gates-v1:$_a64\n')),
        isNotNull,
      );
    });

    final invalid = <String, (String, Object?)>{
      'foreign source': ('sourceId', 'run-b-source'),
      'alternative source': ('sourceId', 'run-a-alternative'),
      'stale fingerprint': ('sourceFingerprint', {'digest': 'changed'}),
      'null fingerprint': ('sourceFingerprint', null),
      'empty layout': ('layoutId', '  '),
      'oversized layout': ('layoutId', 'x' * 129),
      'numeric layout': ('layoutId', 42),
      'missing layout': ('layoutId', #absent),
      'missing gate revision': ('gateRevision', #absent),
      'direction as a number': ('direction', 1),
      'unsupported direction': ('direction', 'forward'),
      'empty revision': ('gateRevision', ''),
      'bad revision': ('gateRevision', 'gates-v1:abc'),
    };
    invalid.forEach((name, change) {
      test('rejects $name', () {
        expect(
          validateFetproject(configured(change.$1, change.$2)),
          contains('Track configuration'),
        );
      });
    });
  });

  group('analysis decisions', () {
    Map<String, Object?> decided(Object? decisions) =>
        mutated((d) => event(d)['analysisDecisions'] = decisions);

    test('accepts saved groups, ranges and channels', () {
      for (final decisions in [
        <String, Object?>{},
        {'comparisonGroupId': null},
        {'comparisonGroupId': 'compatibility-v1:$_a64'},
        {
          'comparisonRange': {'startMeters': 0, 'endMeters': 1234.5},
        },
        {
          'comparisonChannels': ['speed', 'throttle'],
        },
        {
          'comparisonSlots': [null, null],
        },
      ]) {
        expect(validateFetproject(decided(decisions)), isNull);
      }
    });

    test('rejects malformed decisions', () {
      for (final decisions in [
        null,
        1,
        <Object?>[],
        {'comparisonGroupId': ''},
        {'comparisonGroupId': 'Group 1'},
        {'comparisonGroupId': 'compatibility-v1:${'a' * 65}'},
        {'comparisonGroupId': 'compatibility-v1:$_a64\n'},
        {
          'comparisonRange': {'startMeters': 10, 'endMeters': 5},
        },
        {
          'comparisonRange': {'startMeters': -1, 'endMeters': 5},
        },
        {
          'comparisonRange': {'endMeters': 5},
        },
        {
          'comparisonRange': {'startMeters': 0, 'endMeters': 2000000},
        },
        {
          'comparisonChannels': ['speed', 'speed'],
        },
        {
          'comparisonChannels': ['a', 'b', 'c', 'd', 'e'],
        },
        {
          'comparisonChannels': [''],
        },
        {
          'comparisonSlots': [null],
        },
      ]) {
        expect(validateFetproject(decided(decisions)), isNotNull);
      }
    });
  });

  group('lap exclusions', () {
    Map<String, Object?> reference({String type = 'LAP'}) => {
      'version': 1,
      'algorithm': lapReferenceAlgorithm,
      'eventId': 'event-identity',
      'runId': 'run-a',
      'sourceId': 'run-a-source',
      'sourceRevision': _a64,
      'derivationKey': 'b' * 64,
      'type': type,
      'startTime': 12.5,
      'endTime': 101.25,
    };
    Map<String, Object?> excluded(List<Object?> exclusions) =>
        mutated((d) => event(d)['lapExclusions'] = exclusions);

    test('accepts unique LAP references with reasons', () {
      expect(
        validateFetproject(
          excluded([
            {'reference': reference(), 'reason': 'Traffic'},
          ]),
        ),
        isNull,
      );
    });

    test('rejects duplicates, other types, foreign events and no reason', () {
      final entry = {'reference': reference(), 'reason': 'Traffic'};
      for (final exclusions in [
        [entry, entry],
        [
          {'reference': reference(type: 'OUT'), 'reason': 'Traffic'},
        ],
        [
          {
            'reference': {...reference(), 'eventId': 'other'},
            'reason': 'Traffic',
          },
        ],
        [
          {'reference': reference(), 'reason': ' '},
        ],
        [
          {'reference': reference(), 'reason': 'x' * 257},
        ],
        [
          {'reference': reference(), 'reason': 'Traffic', 'extra': 1},
        ],
        [
          {
            'reference': {...reference(), 'endTime': 1},
            'reason': 'Traffic',
          },
        ],
      ]) {
        expect(validateFetproject(excluded(exclusions)), isNotNull);
      }
      expect(
        validateFetproject(mutated((d) => event(d)['lapExclusions'] = null)),
        isNotNull,
      );
    });
  });

  test('bounds track inference provenance', () {
    final inference = {
      'algorithm': 'gps-route-v1',
      'sourceRevision': _a64,
      'gateRevision': 'gates-v1:${'b' * 64}',
      'layoutId': 'gps-route-v1:${'c' * 64}',
      'direction': 'clockwise',
    };
    expect(
      validateFetproject(withRun((r) => r['trackInference'] = inference)),
      isNull,
    );
    for (final (field, value) in <(String, Object?)>[
      ('algorithm', 'x' * 129),
      ('algorithm', 'bad\u0000'),
      ('sourceRevision', 'a' * 63),
      ('sourceRevision', 12),
      ('gateRevision', 'gates-v1:bad'),
      ('layoutId', 'gps-route-v1:'),
      ('layoutId', 'x' * 129),
      ('direction', 'unknown'),
    ]) {
      expect(
        validateFetproject(
          withRun((r) => r['trackInference'] = {...inference, field: value}),
        ),
        isNotNull,
        reason: '$field = $value',
      );
    }
    expect(
      validateFetproject(
        withRun(
          (r) => r['trackInference'] = {...inference}..remove('gateRevision'),
        ),
      ),
      isNotNull,
    );
  });

  test('bounds a refused source combination (FET-142)', () {
    bool valid(Object? candidate) =>
        validateFetproject(withRun((r) => r['fusionDeclined'] = candidate)) ==
        null;
    expect(valid('run-a-alternative'), isTrue);
    expect(valid('run-a-source'), isFalse, reason: 'the primary');
    expect(valid('run-b-source'), isFalse, reason: "another run's recording");
    expect(valid('missing'), isFalse);
    expect(valid(7), isFalse);
    expect(valid(null), isFalse);
  });

  test('bounds an approved source fusion', () {
    final fusion = {
      'algorithm': 'channel-fusion-v1',
      'alternativeSourceId': 'run-a-alternative',
      'primarySourceRevision': _a64,
      'alternativeSourceRevision': 'b' * 64,
      'clock': {
        'offsetSeconds': 12.5,
        'driftPpm': -40.0,
        'uncertaintySeconds': 0.05,
      },
      'rules': [
        {'key': 'speed', 'rule': 'fillGaps'},
      ],
    };
    bool valid(Object? candidate) =>
        validateFetproject(withRun((r) => r['fusion'] = candidate)) == null;
    expect(valid(fusion), isTrue);
    expect(valid({...fusion, 'alternativeSourceId': 'run-a-source'}), isFalse);
    expect(valid({...fusion, 'alternativeSourceId': 'run-b-source'}), isFalse);
    expect(valid({...fusion, 'primarySourceRevision': 'a' * 63}), isFalse);
    expect(
      valid({
        ...fusion,
        'clock': {...fusion['clock'] as Map, 'driftPpm': 5000.0},
      }),
      isFalse,
    );
    expect(
      valid({
        ...fusion,
        'rules': [
          {'key': 'speed', 'rule': 'fillGaps'},
          {'key': 'speed', 'rule': 'primaryOnly'},
        ],
      }),
      isFalse,
    );
    expect(valid(7), isFalse);
  });

  test('checks video chapters start with the video itself', () {
    final first = {
      'relativePath': 'GX010123.MP4',
      'fingerprint': {'kind': 'video-v1'},
    };
    Map<String, Object?> chapter(String path, num duration) => {
      'relativePath': path,
      'durationSeconds': duration,
    };
    bool valid(List<Object?> chapters) =>
        validateFetproject(
          withRun(
            (r) => (r['sources'] as Map)['video'] = {
              ...first,
              'chapters': chapters,
            },
          ),
        ) ==
        null;
    final firstChapter = {...first, 'durationSeconds': 530.53};
    expect(
      valid([
        firstChapter,
        chapter('GX020123.MP4', 530.53),
        chapter('GX030123.MP4', 100),
      ]),
      isTrue,
    );
    expect(valid([firstChapter]), isFalse);
    expect(
      valid([chapter('GX020123.MP4', 530), chapter('GX030123.MP4', 100)]),
      isFalse,
    );
    expect(valid([firstChapter, chapter('GX020123.MP4', 90000)]), isFalse);
    expect(valid([firstChapter, chapter('/absolute.MP4', 1)]), isFalse);
  });

  group('writing', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('fetproject'));
    tearDown(() => directory.deleteSync(recursive: true));

    test(
      'writes indented JSON that reads back equal, unknown keys kept',
      () async {
        final path = p.join(directory.path, 'day.fetproject');
        await writeFetproject(path, project());
        final text = File(path).readAsStringSync();
        expect(text, startsWith('{\n    "documentState": {\n        "id"'));
        expect(text, endsWith('}\n'));
        expect(text, contains('"widgets": [\n        ]'));
        final read = await readFetproject(path);
        expect(qtCompactJson(read), qtCompactJson(project()));
        expect(read['futureRoot'], 8);
        expect(event(read)['futureEvent'], isTrue);
        expect(directory.listSync(), hasLength(1));
      },
    );

    test('replaces a document whole and refuses an invalid one', () async {
      final path = p.join(directory.path, 'day.fetproject');
      await writeFetproject(path, project());
      final before = File(path).readAsStringSync();
      await expectLater(
        writeFetproject(path, project()..['version'] = 4),
        throwsA(isA<FetprojectError>()),
      );
      expect(File(path).readAsStringSync(), before);
      final renamed = project();
      event(renamed)['name'] = 'Renamed day';
      await writeFetproject(path, renamed);
      expect(event(await readFetproject(path))['name'], 'Renamed day');
      expect(directory.listSync(), hasLength(1));
    });

    test(
      'writes in place when only the document may be written',
      () async {
        // The macOS sandbox grants the file chosen in the save panel, not
        // its folder: a folder without write permission stands in for it.
        final path = p.join(directory.path, 'day.fetproject');
        await writeFetproject(path, project());
        final renamed = project();
        event(renamed)['name'] = 'Renamed day';
        await Process.run('chmod', ['555', directory.path]);
        addTearDown(() => Process.run('chmod', ['755', directory.path]));
        await writeFetproject(path, renamed);
        expect(event(await readFetproject(path))['name'], 'Renamed day');
        expect(directory.listSync(), hasLength(1));
      },
      skip: Platform.isWindows || _isRoot()
          ? 'Needs folder permissions that bind this user'
          : false,
    );

    group('in place', () {
      // A write that stops partway, as a full disk does: the file is cut.
      Future<void> cutWrite(File file, List<int> bytes) async {
        await file.writeAsBytes(bytes.sublist(0, bytes.length ~/ 3));
        throw const FileSystemException('No space left on device');
      }

      test('a write cut partway restores the previous document', () async {
        final path = p.join(directory.path, 'day.fetproject');
        await writeFetproject(path, project());
        final before = File(path).readAsBytesSync();
        var calls = 0;
        await expectLater(
          writeDocumentInPlace(
            path,
            utf8.encode('{"replacement": true}' * 50),
            write: (file, bytes) async {
              // The first call is the save, the second the restore.
              if (calls++ == 0) return cutWrite(file, bytes);
              await file.writeAsBytes(bytes, flush: true);
            },
          ),
          throwsA(
            isA<FetprojectError>().having(
              (error) => error.message,
              'message',
              'Could not save the project: No space left on device; '
                  'the previously saved version is unchanged',
            ),
          ),
        );
        expect(File(path).readAsBytesSync(), before);
      });

      test('a write that reads back differently restores it too', () async {
        final path = p.join(directory.path, 'day.fetproject');
        await writeFetproject(path, project());
        final before = File(path).readAsBytesSync();
        var calls = 0;
        await expectLater(
          writeDocumentInPlace(
            path,
            utf8.encode('new document'),
            write: (file, bytes) async => file.writeAsBytes(
              calls++ == 0 ? utf8.encode('new docu') : bytes,
              flush: true,
            ),
          ),
          throwsA(
            isA<FetprojectError>().having(
              (error) => error.message,
              'message',
              endsWith(
                'reads back differently; '
                'the previously saved version is unchanged',
              ),
            ),
          ),
        );
        expect(File(path).readAsBytesSync(), before);
      });

      test('a new document cut partway is removed', () async {
        final path = p.join(directory.path, 'new.fetproject');
        await expectLater(
          writeDocumentInPlace(path, utf8.encode('x' * 90), write: cutWrite),
          throwsA(
            isA<FetprojectError>().having(
              (error) => error.message,
              'message',
              endsWith('; nothing was saved'),
            ),
          ),
        );
        expect(File(path).existsSync(), isFalse);
      });

      test('a write refused before it starts leaves the document', () async {
        final path = p.join(directory.path, 'day.fetproject');
        await writeFetproject(path, project());
        final before = File(path).readAsBytesSync();
        await expectLater(
          writeDocumentInPlace(
            path,
            utf8.encode('new'),
            write: (file, bytes) async =>
                throw const FileSystemException('Permission denied'),
          ),
          throwsA(
            isA<FetprojectError>().having(
              (error) => error.message,
              'message',
              endsWith('; the previously saved version is unchanged'),
            ),
          ),
        );
        expect(File(path).readAsBytesSync(), before);
      });

      test('a successful write replaces the document', () async {
        final path = p.join(directory.path, 'day.fetproject');
        await writeFetproject(path, project());
        await writeDocumentInPlace(path, utf8.encode('replaced'));
        expect(File(path).readAsStringSync(), 'replaced');
      });
    });

    // Arek's second audit, finding 3: an in-place write the app does not
    // live to finish (killed, a power cut) runs no restore.
    group('journal of an in-place write', () {
      late String journal, path;
      late List<int> next;
      setUp(() async {
        journal = p.join(directory.path, 'journal');
        path = p.join(directory.path, 'day.fetproject');
        await writeFetproject(path, project());
        next = utf8.encode(encodeFetproject(project()..['name'] = 'Renamed'));
      });
      List<String> journalled() => Directory(journal).existsSync()
          ? [
              for (final file in Directory(journal).listSync())
                p.extension(file.path),
            ]
          : const [];

      test('holds the new document while it is written, then goes', () async {
        List<String>? during;
        await writeDocumentInPlace(
          path,
          next,
          journalDirectory: journal,
          write: (file, bytes) async {
            during = journalled()..sort();
            await file.writeAsBytes(bytes, flush: true);
          },
        );
        expect(during, ['.fetproject', '.path']);
        expect(journalled(), isEmpty);
        expect(File(path).readAsBytesSync(), next);
      });

      test('a failed write that is restored leaves no journal', () async {
        await expectLater(
          writeDocumentInPlace(
            path,
            next,
            journalDirectory: journal,
            write: (file, bytes) async =>
                throw const FileSystemException('Permission denied'),
          ),
          throwsA(isA<FetprojectError>()),
        );
        expect(journalled(), isEmpty);
      });

      test(
        'a failed write that leaves the file cut keeps the journal',
        () async {
          // The disk fills partway, and writing the old version back fails too.
          await expectLater(
            writeDocumentInPlace(
              path,
              next,
              journalDirectory: journal,
              write: (file, bytes) async {
                file.writeAsBytesSync(bytes.sublist(0, 10), flush: true);
                throw const FileSystemException('No space left on device');
              },
            ),
            throwsA(
              isA<FetprojectError>().having(
                (error) => error.message,
                'message',
                contains('may be incomplete'),
              ),
            ),
          );
          expect(journalled(), hasLength(2));
          expect(
            await completeInterruptedSave(path, journalDirectory: journal),
            InterruptedSave.completed,
          );
          expect(File(path).readAsBytesSync(), next);
        },
      );

      test('a restored file that was no document is not replaced', () async {
        File(path).writeAsStringSync('notes, not a document');
        await expectLater(
          writeDocumentInPlace(
            path,
            next,
            journalDirectory: journal,
            write: (file, bytes) async =>
                throw const FileSystemException('Permission denied'),
          ),
          throwsA(isA<FetprojectError>()),
        );
        expect(journalled(), isEmpty);
        expect(
          await completeInterruptedSave(path, journalDirectory: journal),
          InterruptedSave.none,
        );
        expect(File(path).readAsStringSync(), 'notes, not a document');
      });

      test('a file deleted after a cut save is not recreated', () async {
        final cut = Completer<void>();
        unawaited(
          writeDocumentInPlace(
            path,
            next,
            journalDirectory: journal,
            write: (file, bytes) async {
              file.writeAsBytesSync(bytes.sublist(0, 10), flush: true);
              cut.complete();
              await Completer<void>().future;
            },
          ),
        );
        await cut.future;
        File(path).deleteSync();
        expect(
          await completeInterruptedSave(path, journalDirectory: journal),
          InterruptedSave.none,
        );
        expect(File(path).existsSync(), isFalse);
        expect(journalled(), isEmpty);
      });

      test('a save cut by the app ending is finished when opened', () async {
        // The app ends partway through the write: the file is cut and
        // nothing after the write runs.
        final cut = Completer<void>();
        unawaited(
          writeDocumentInPlace(
            path,
            next,
            journalDirectory: journal,
            write: (file, bytes) async {
              file.writeAsBytesSync(
                bytes.sublist(0, bytes.length ~/ 3),
                flush: true,
              );
              cut.complete();
              await Completer<void>().future;
            },
          ),
        );
        await cut.future;
        expect(
          () => decodeFetproject(File(path).readAsBytesSync()),
          throwsA(isA<FetprojectError>()),
        );
        expect(journalled(), hasLength(2));
        expect(
          await completeInterruptedSave(path, journalDirectory: journal),
          InterruptedSave.completed,
        );
        expect(File(path).readAsBytesSync(), next);
        expect(journalled(), isEmpty);
        expect(
          await completeInterruptedSave(path, journalDirectory: journal),
          InterruptedSave.none,
        );
      });

      test('a whole document is never replaced from the journal', () async {
        final before = File(path).readAsBytesSync();
        // The app ended before the write began: the file is the old one.
        final writing = Completer<void>();
        unawaited(
          writeDocumentInPlace(
            path,
            next,
            journalDirectory: journal,
            write: (file, bytes) {
              writing.complete();
              return Completer<void>().future;
            },
          ),
        );
        await writing.future;
        expect(
          await completeInterruptedSave(path, journalDirectory: journal),
          InterruptedSave.fileWhole,
        );
        expect(File(path).readAsBytesSync(), before);
        expect(journalled(), isEmpty);
      });

      test('the journal of another file is left alone', () async {
        final other = p.join(directory.path, 'other.fetproject');
        await writeFetproject(other, project());
        final cut = Completer<void>();
        unawaited(
          writeDocumentInPlace(
            other,
            next,
            journalDirectory: journal,
            write: (file, bytes) async {
              file.writeAsBytesSync(bytes.sublist(0, 10), flush: true);
              cut.complete();
              await Completer<void>().future;
            },
          ),
        );
        await cut.future;
        expect(
          await completeInterruptedSave(path, journalDirectory: journal),
          InterruptedSave.none,
        );
        expect(journalled(), hasLength(2));
      });
    });
  });
}

bool _isRoot() =>
    !Platform.isWindows &&
    (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
