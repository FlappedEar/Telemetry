import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('recording_source_'));
  tearDown(() => directory.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File(p.join(directory.path, name))..writeAsBytesSync(bytes);

  test('the format comes from the extension only, ignoring case', () {
    expect(recordingFormatOf('day/SESSION.RCZ'), RecordingFormat.rcz);
    expect(recordingFormatOf(r'C:\day\a.Vbo'), RecordingFormat.vbo);
    expect(recordingFormatOf('a.vbo.txt'), isNull);
    expect(recordingFormatOf('vbo'), isNull);
    expect(recordingFormatOf('a.'), isNull);
    expect(supportsRecordingPath('x.rcz'), isTrue);
  });

  test('identity is the SHA-256 of the content, not the name', () {
    // SHA-256("abc"), FIPS 180-2 test vector.
    const abc = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    final a = write('a.vbo', 'abc'.codeUnits);
    final b = write('renamed.rcz', 'abc'.codeUnits);
    expect(contentSha256(a.path, 3), abc);
    expect(contentSha256(b.path, 3), abc);
    expect(recordingSourceId(abc), 'sha256:$abc');
  });

  test('hashes across 64 KiB reads', () {
    final bytes = List<int>.generate(200 * 1024 + 7, (i) => i * 31 & 0xff);
    final file = write('big.vbo', bytes);
    final again = write('copy.vbo', bytes);
    final hash = contentSha256(file.path, bytes.length);
    expect(hash, hasLength(64));
    expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(contentSha256(again.path, bytes.length), hash);
    expect(contentSha256(write('other.vbo', [...bytes]..[0] ^= 1).path, bytes.length), isNot(hash));
  });

  test('size must be 1 B to 128 MiB', () {
    final file = write('a.vbo', [1]);
    expect(() => contentSha256(file.path, 0), throwsA(isA<ResourceLimitError>()));
    expect(
      () => contentSha256(file.path, maximumRecordingBytes + 1),
      throwsA(isA<ResourceLimitError>()),
    );
  });

  test('a file whose size differs from what was seen is refused', () {
    final file = write('a.vbo', [1, 2, 3]);
    expect(
      () => contentSha256(file.path, 4),
      throwsA(
        isA<RecordingSourceError>().having(
          (e) => e.message,
          'message',
          contains('changed while reading'),
        ),
      ),
    );
  });

  test('a missing file cannot be read', () {
    expect(
      () => contentSha256(p.join(directory.path, 'missing.vbo'), 3),
      throwsA(
        isA<RecordingSourceError>().having(
          (e) => e.message,
          'message',
          'Cannot read telemetry source.',
        ),
      ),
    );
  });

  test('cancellation', () {
    final file = write('a.vbo', List<int>.filled(300 * 1024, 7));
    var checks = 0;
    expect(
      () => contentSha256(file.path, 300 * 1024, cancelled: () => ++checks > 2),
      throwsA(isA<OperationCancelled>()),
    );
    expect(
      () => contentSha256(file.path, 300 * 1024, cancelled: () => true),
      throwsA(isA<OperationCancelled>()),
    );
  });
}
