// Cases ported from FlappedEar Overlays' EventProjectTests (VBOOverlay
// ca2bde5).
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fetproject/fetproject.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String root;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('references');
    root = directory.resolveSymbolicLinksSync();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  String touch(String relative, [List<int> bytes = const []]) {
    final file = File(p.join(root, relative))..createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return file.path;
  }

  test('saves a relative path within two folders above the document', () {
    final recording = touch('outings/day/run.vbo');
    final reference = SourceReference(absolutePath: recording);
    expect(reference.toJson(p.join(root, 'outings/day/day.fetproject')), {
      'absolutePath': recording,
      'relativePath': 'run.vbo',
    });
    expect(
      reference.toJson(p.join(root, 'outings/day/a/b/day.fetproject')),
      containsPair('relativePath', '../../run.vbo'),
    );
    expect(
      reference.toJson(p.join(root, 'outings/day/a/b/c/day.fetproject')),
      isNot(contains('relativePath')),
    );
  });

  test('prefers the moved relative file to a stale absolute path', () {
    touch('a.vbo');
    Directory(p.join(root, 'new')).createSync();
    final json =
        SourceReference(
          relativePath: 'a.vbo',
          absolutePath: p.join(root, 'stale/a.vbo'),
          fingerprint: const {'digest': 'retained'},
        ).forSave(
          p.join(root, 'event.fetproject'),
          p.join(root, 'new/event.fetproject'),
        );
    expect(json['relativePath'], '../a.vbo');
    expect(json['fingerprint'], {'digest': 'retained'});
  });

  test('refuses relative paths deeper than two parents, and absolute ones', () {
    final far = touch('secret.vbo');
    Directory(p.join(root, 'layout/day')).createSync(recursive: true);
    Directory(p.join(root, 'a/b')).createSync(recursive: true);
    expect(
      const SourceReference(relativePath: '../../../secret.vbo')
          .resolve(p.join(root, 'layout/day/event.fetproject')),
      isEmpty,
    );
    expect(
      const SourceReference(relativePath: '../../secret.vbo')
          .resolve(p.join(root, 'a/b/event.fetproject')),
      far,
    );
    expect(
      SourceReference(relativePath: far)
          .resolve(p.join(root, 'layout/day/event.fetproject')),
      isEmpty,
    );
  });

  test('keeps missing references portable through directory symlinks', () {
    final real = Directory(p.join(root, 'real'))..createSync();
    final alias = p.join(root, 'alias');
    Link(alias).createSync(real.path);
    final rebased = const SourceReference(relativePath: 'missing.vbo').forSave(
      p.join(alias, 'event.fetproject'),
      p.join(alias, 'saved.fetproject'),
    );
    expect(rebased['relativePath'], 'missing.vbo');
    expect(rebased['absolutePath'], p.join(real.path, 'missing.vbo'));
  }, testOn: '!windows');

  test('rebases a reference to a new folder and keeps unknown keys', () {
    touch('old/run-b.mp4');
    Directory(p.join(root, 'new')).createSync();
    final rebased = rebaseReference(
      {'relativePath': 'run-b.mp4', 'futureVideo': true},
      p.join(root, 'old/event.fetproject'),
      p.join(root, 'new/event.fetproject'),
    );
    expect(rebased['relativePath'], '../old/run-b.mp4');
    expect(rebased['futureVideo'], isTrue);
  });

  test('samples the first, middle and last 64 KiB', () {
    final small = touch('small.vbo', [1, 2, 3]);
    expect(
      sampledSha256(small),
      sha256.convert([1, 2, 3, 1, 2, 3, 1, 2, 3]).toString(),
    );
    final bytes = List<int>.generate(300000, (i) => i * 7 % 251);
    final large = touch('large.vbo', bytes);
    const block = 65536;
    final middle = 300000 ~/ 2 - block ~/ 2;
    expect(
      sampledSha256(large),
      sha256.convert([
        ...bytes.sublist(0, block),
        ...bytes.sublist(middle, middle + block),
        ...bytes.sublist(300000 - block),
      ]).toString(),
    );
    expect(sampledSha256(p.join(root, 'none.vbo')), isEmpty);
  });

  test('reads absolute paths as Qt does on each platform', () {
    expect(qtIsAbsolutePath('/a', windows: false), isTrue);
    expect(qtIsAbsolutePath(':/qml', windows: false), isTrue);
    expect(qtIsAbsolutePath(r'C:\a', windows: false), isFalse);
    expect(qtIsAbsolutePath(r'C:\a', windows: true), isTrue);
    expect(qtIsAbsolutePath('a/b', windows: true), isFalse);
  });

  test('rounds durations to whole microseconds', () {
    expect(roundedMicroseconds(1.0000005), 1000001);
    expect(roundedMicroseconds(double.nan), 0);
  });
}
