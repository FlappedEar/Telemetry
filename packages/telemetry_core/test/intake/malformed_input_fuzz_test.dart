// Damaged recordings, as a phone can produce them (an export cut short, a
// copy with flipped bytes, lines lost or repeated), must end as a file
// error or an imported run: never as an exception, and never as an
// unexpected error in the parser, the laps or the day's analysis.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

// FUZZ_VARIANTS=500 dart test test/intake/malformed_input_fuzz_test.dart
// runs a longer search locally; CI keeps the default.
final _variantsPerFile = int.tryParse(Platform.environment['FUZZ_VARIANTS'] ?? '') ?? 24;
final _seed = int.tryParse(Platform.environment['FUZZ_SEED'] ?? '') ?? 20261004;

const _sources = [
  'test/parity/corpus/laps_clean.vbo',
  'test/parity/corpus/laps_gps_gap.vbo',
  'test/parity/corpus/laps_invalid_coordinate.vbo',
  'test/parity/corpus/laps_clockwise.vbo',
  'test/parity/corpus/gate_lines.vbo',
  'test/parity/corpus/racechrono_10_2_4.vbo',
  'test/parity/corpus/sections_and_metadata.vbo',
  'test/parity/corpus/segments_rectangle.vbo',
  'test/parity/corpus/midnight_and_mixed.vbo',
  'test/parity/rcz_corpus/basic.rcz',
  'test/parity/rcz_corpus/long.rcz',
  'test/parity/rcz_corpus/pedals.rcz',
  'test/parity/rcz_corpus/missing_values.rcz',
];

/// One damaged copy of [bytes]; [kind] picks the damage.
Uint8List _damage(Uint8List bytes, int kind, Random random) {
  if (bytes.isEmpty) return bytes;
  switch (kind % 6) {
    case 0: // Cut short anywhere.
      return Uint8List.sublistView(bytes, 0, random.nextInt(bytes.length));
    case 1: // A few bytes flipped.
      final copy = Uint8List.fromList(bytes);
      for (var i = 0; i < 1 + random.nextInt(8); ++i) {
        copy[random.nextInt(copy.length)] = random.nextInt(256);
      }
      return copy;
    case 2: // A run of bytes lost from the middle.
      final from = random.nextInt(bytes.length);
      final to = min(bytes.length, from + 1 + random.nextInt(4096));
      return Uint8List.fromList([...bytes.sublist(0, from), ...bytes.sublist(to)]);
    case 3: // A run of bytes repeated.
      final from = random.nextInt(bytes.length);
      final to = min(bytes.length, from + 1 + random.nextInt(4096));
      return Uint8List.fromList([
        ...bytes.sublist(0, to),
        ...bytes.sublist(from, to),
        ...bytes.sublist(to),
      ]);
    case 4: // Zeros written over a block, as a failed flash write leaves.
      final copy = Uint8List.fromList(bytes);
      final from = random.nextInt(copy.length);
      copy.fillRange(from, min(copy.length, from + 1 + random.nextInt(512)), 0);
      return copy;
    default: // Lines swapped (text) or a slice moved (binary).
      final a = random.nextInt(bytes.length), b = random.nextInt(bytes.length);
      final from = min(a, b), to = max(a, b);
      return Uint8List.fromList([
        ...bytes.sublist(to),
        ...bytes.sublist(from, to),
        ...bytes.sublist(0, from),
      ]);
  }
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('malformed_fuzz'));
  tearDown(() => directory.deleteSync(recursive: true));

  for (final source in _sources) {
    test('damaged copies of ${source.split('/').last} import or fail cleanly', () {
      final original = File(source).readAsBytesSync();
      final random = Random(_seed + _sources.indexOf(source));
      final extension = source.substring(source.lastIndexOf('.'));
      // In batches, as an import of a day takes them.
      for (var batch = 0; batch < _variantsPerFile; batch += 12) {
        final paths = <String>[];
        for (var i = batch; i < min(batch + 12, _variantsPerFile); ++i) {
          final path = '${directory.path}/damaged_$i$extension';
          File(path).writeAsBytesSync(_damage(original, i, random), flush: true);
          paths.add(path);
        }
        _importAndAnalyse(paths);
      }
    });
  }
}

void _importAndAnalyse(List<String> paths) {
  final plan = prepareTelemetryImport(paths);

  expect(plan.files, hasLength(paths.length));
  for (final file in plan.files) {
    expect(
      file.message,
      isNot(startsWith('Unexpected error')),
      reason: '${file.requestedPath}: ${file.message}',
    );
  }
  final runs = [
    for (final (:run, :name) in nameRunsInRecordingOrder(plan.runs))
      DayRunInput(
        runId: run.id,
        name: name,
        contentSha256: run.contentSha256,
        session: run.telemetry,
        laps: run.laps,
      ),
  ];
  final day = analyzeDay(runs);
  for (final message in day.messages) {
    expect(message.text, isNot(startsWith('Unexpected error')), reason: message.text);
  }
  for (final row in day.rows) {
    expect(row.durationSeconds.isFinite, isTrue, reason: row.displayName);
  }
}
