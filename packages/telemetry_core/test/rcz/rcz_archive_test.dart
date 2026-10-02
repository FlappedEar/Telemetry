import 'dart:io';
import 'dart:typed_data';

import 'package:telemetry_core/src/operation.dart';
import 'package:telemetry_core/src/rcz/rcz_archive.dart';
import 'package:test/test.dart';

import 'rcz_fixture.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('rcz_archive'));
  tearDown(() => temp.deleteSync(recursive: true));

  String write(Uint8List bytes) {
    final path = '${temp.path}/session.rcz';
    File(path).writeAsBytesSync(bytes, flush: true);
    return path;
  }

  Map<String, Uint8List> readAll(String path, {CancellationCheck? cancelled}) {
    final archive = RczArchive.open(path, cancelled: cancelled);
    try {
      return {for (final name in archive.members.keys) name: archive.data(name)};
    } finally {
      archive.close();
    }
  }

  for (final compressed in [true, false]) {
    test('reads ${compressed ? 'deflated' : 'stored'} members exactly', () {
      final files = fixtureMembers();
      final read = readAll(write(zip(files, compressed: compressed)));
      expect(read.keys, (files.keys.toList()..sort()));
      for (final name in files.keys) {
        expect(read[name], files[name], reason: name);
      }
    });
  }

  test('enforces a caller limit and reports a missing member', () {
    final archive = RczArchive.open(write(zip(fixtureMembers())));
    addTearDown(archive.close);
    expect(() => archive.data('session.json', limit: 10), throwsA(isA<RczFormatError>()));
    expect(() => archive.data('absent'), throwsA(isA<RczFormatError>()));
  });

  test('rejects unsafe member paths', () {
    for (final name in ['../x', '/x', r'a\b', 'c:x', 'a//b', './x', 'a/../b']) {
      final files = fixtureMembers()..[name] = text('{}');
      expect(() => readAll(write(zip(files))), throwsA(isA<RczFormatError>()), reason: name);
    }
  });

  group('rejects corrupt archives:', () {
    void corrupt(String kind, void Function(ByteData zip, int central) edit) {
      test(kind, () {
        final bytes = zip(fixtureMembers());
        final data = ByteData.sublistView(bytes);
        final central = data.getUint32(bytes.length - 22 + 16, Endian.little);
        edit(data, central);
        expect(() => readAll(write(bytes)), throwsA(isA<RczFormatError>()));
      });
    }

    test('truncated', () {
      final bytes = zip(fixtureMembers());
      expect(
        () => readAll(write(bytes.sublist(0, bytes.length - 5))),
        throwsA(isA<RczFormatError>()),
      );
    });
    corrupt('crc', (z, c) {
      z.setUint32(14, 123, Endian.little);
      z.setUint32(c + 16, 123, Endian.little);
    });
    for (final (kind, size) in [('bomb', 1), ('declared-limit', maximumRczMemberBytes + 1)]) {
      corrupt(kind, (z, c) {
        z.setUint32(22, size, Endian.little);
        z.setUint32(c + 24, size, Endian.little);
      });
    }
    corrupt('symlink', (z, c) => z.setUint32(c + 38, 0xa000 << 16, Endian.little));
    corrupt('overlap', (z, c) => z.setUint32(c + 42, c, Endian.little));
    corrupt('encrypted', (z, c) => z.setUint16(c + 8, 1, Endian.little));
    corrupt('zip64', (z, c) => z.setUint16(c + 6, 45, Endian.little));
    corrupt('corrupt deflate stream', (z, c) {
      final nameSize = z.getUint16(26, Endian.little);
      z.setUint8(30 + nameSize, 0xff);
    });
  });

  test('rejects archives that are empty or too small', () {
    expect(() => readAll(write(Uint8List(21))), throwsA(isA<RczFormatError>()));
    expect(() => readAll(write(zip({}))), throwsA(isA<RczFormatError>()));
  });

  test('cancels during decompression', () {
    final files = fixtureMembers()..['channel_1_300_0_1_1'] = Uint8List(2 * 1024 * 1024);
    var checks = 0;
    final cancelAt = files.length + 8;
    expect(
      () => readAll(write(zip(files)), cancelled: () => ++checks >= cancelAt),
      throwsA(isA<OperationCancelled>()),
    );
    expect(checks, cancelAt);
  });
}
