// Ports VBOOverlay TelemetryCoreTests::scansFoldersForRecordingsWithinBounds and
// ::combinesDroppedFilesAndFolders (KAN-87, KAN-88, KAN-173).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String root;
  String at(String name) => p.join(root, name);
  void write(String name) => (File(at(name))..createSync(recursive: true)).writeAsStringSync('x');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('folder_scan_');
    root = p.normalize(directory.path);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  group('scanTelemetryFolder', () {
    setUp(() {
      Directory(at('sub/deeper/deepest')).createSync(recursive: true);
      Directory(at('.Trashes')).createSync();
      for (final name in [
        'a.VBO',
        'b.rcz',
        'notes.txt',
        '.hidden.vbo',
        '._a.VBO',
        '.Trashes/f.vbo', //
        'sub/c.vbo',
        'sub/._c.vbo',
        'sub/deeper/d.rcz',
        'sub/deeper/deepest/e.vbo',
      ]) {
        write(name);
      }
    });

    test('top level only, skipping dot entries and other files', () {
      final top = scanTelemetryFolder(root, includeSubfolders: false);
      expect(top.error, isEmpty);
      expect(top.files, [at('a.VBO'), at('b.rcz')]);
      expect(top.notes.join(' '), contains('1 other file(s) were ignored'));
    });

    test('subfolders, sorted', () {
      final all = scanTelemetryFolder(root, includeSubfolders: true);
      expect(all.files, hasLength(5));
      expect(all.files, contains(at('sub/deeper/deepest/e.vbo')));
      expect(all.files, orderedEquals([...all.files]..sort()));
    });

    test('depth limit', () {
      final bounded = scanTelemetryFolder(
        root,
        includeSubfolders: true,
        limits: const TelemetryFolderScanLimits(maximumDepth: 1),
      );
      expect(bounded.files, [at('a.VBO'), at('b.rcz'), at('sub/c.vbo')]);
      expect(
        bounded.notes.join(' '),
        contains('1 folder(s) deeper than 1 levels were not scanned'),
      );
    });

    test('links are never followed, and a linked root is refused', () {
      Link(at('sub/loop')).createSync(root);
      Link(at('sub/linked.vbo')).createSync(at('a.VBO'));
      final linked = scanTelemetryFolder(root, includeSubfolders: true);
      expect(linked.files, hasLength(5));
      expect(linked.notes.join(' '), contains('2 link(s) were not followed'));
      expect(scanTelemetryFolder(at('sub/loop'), includeSubfolders: true).error, isNotEmpty);
    }, testOn: '!windows');

    test('more recordings than a batch is an error, not a truncation', () {
      final tooMany = scanTelemetryFolder(
        root,
        includeSubfolders: true,
        limits: const TelemetryFolderScanLimits(maximumFiles: 2),
      );
      expect(tooMany.files, isEmpty);
      expect(tooMany.error, contains('holds 5 recordings; import at most 2'));
    });

    test('entry limit', () {
      final stopped = scanTelemetryFolder(
        root,
        includeSubfolders: true,
        limits: const TelemetryFolderScanLimits(maximumEntries: 2),
      );
      expect(stopped.notes.join(' '), contains('Stopped after 2 files and folders'));
    });

    test('limits can only be lowered', () {
      final raised = scanTelemetryFolder(
        root,
        includeSubfolders: true,
        limits: const TelemetryFolderScanLimits(maximumFiles: 1000, maximumDepth: 100),
      );
      expect(raised.files, hasLength(5));
    });

    test('cancellation returns nothing', () {
      var checks = 0;
      final cancelled = scanTelemetryFolder(
        root,
        includeSubfolders: true,
        cancelled: () => ++checks > 3,
      );
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.files, isEmpty);
    });

    test('missing folder, a file, and an empty folder', () {
      expect(scanTelemetryFolder(at('missing'), includeSubfolders: true).error, isNotEmpty);
      expect(scanTelemetryFolder(at('a.VBO'), includeSubfolders: true).error, isNotEmpty);
      expect(scanTelemetryFolder('', includeSubfolders: true).error, isNotEmpty);
      Directory(at('empty')).createSync();
      expect(
        scanTelemetryFolder(at('empty'), includeSubfolders: false).error,
        contains('No VBO or RCZ recordings were found (subfolders were not included)'),
      );
    });
  });

  group('scanTelemetrySources', () {
    setUp(() {
      Directory(at('day/sub')).createSync(recursive: true);
      Directory(at('empty')).createSync();
      for (final name in [
        'loose.vbo',
        '._loose.vbo',
        'photo.jpg',
        'day/a.vbo',
        'day/._a.vbo',
        'day/b.RCZ',
        'day/sub/c.vbo',
      ]) {
        write(name);
      }
    });

    test('a mix of dropped items becomes one list with a note for everything skipped', () {
      final mixed = scanTelemetrySources([
        at('loose.vbo'),
        at('._loose.vbo'),
        at('photo.jpg'),
        at('missing.vbo'), //
        at('day'), at('day/a.vbo'), at('empty'),
      ], includeSubfolders: false);
      expect(mixed.error, isEmpty);
      // day/a.vbo arrives twice and counts once; sidecars are never recordings.
      expect(mixed.files, [at('loose.vbo'), at('day/a.vbo'), at('day/b.RCZ')]);
      final notes = mixed.notes.join('\n');
      expect(notes, contains('._loose.vbo: a macOS metadata file, not a recording; not imported.'));
      expect(notes, contains('photo.jpg: not a VBO or RCZ recording; not imported.'));
      expect(notes, contains('missing.vbo: not found; not imported.'));
      expect(notes, contains('empty: No VBO or RCZ recordings were found'));
    });

    test('subfolders, and the single-folder and nothing-to-import errors', () {
      expect(scanTelemetrySources([at('day')], includeSubfolders: true).files, hasLength(3));
      expect(
        scanTelemetrySources([at('empty')], includeSubfolders: false).error,
        contains('No VBO or RCZ recordings were found'),
      );
      final nothing = scanTelemetrySources([at('photo.jpg')], includeSubfolders: false);
      expect(nothing.error, 'No VBO or RCZ recordings to import.');
      expect(nothing.notes.join(' '), contains('photo.jpg'));
    });

    test('a linked file is reported, not followed', () {
      Link(at('linked.vbo')).createSync(at('loose.vbo'));
      final scan = scanTelemetrySources([at('linked.vbo')], includeSubfolders: false);
      expect(scan.files, isEmpty);
      expect(scan.notes.join(' '), contains('linked.vbo: a link; not followed.'));
    }, testOn: '!windows');

    test('total limit and cancellation', () {
      expect(
        scanTelemetrySources(
          [at('day'), at('loose.vbo')],
          includeSubfolders: false,
          limits: const TelemetryFolderScanLimits(maximumFiles: 2),
        ).error,
        contains('That is 3 recordings; import at most 2'),
      );
      var checks = 0;
      expect(
        scanTelemetrySources(
          [at('day'), at('loose.vbo')],
          includeSubfolders: true,
          cancelled: () => ++checks > 2,
        ).cancelled,
        isTrue,
      );
    });
  });
}
