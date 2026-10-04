import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../../packages/telemetry_core/test/rcz/rcz_fixture.dart';
import '../support/temp_directory.dart';

/// [path]'s source with adjacent string literals joined, so a text split
/// over lines reads as written.
String _source(String path) =>
    File(path)
        .readAsStringSync()
        .replaceAll(RegExp(r'''['"]\s*\n\s*['"]'''), '');

const _core = 'packages/telemetry_core/lib/src';
const _vboFile = '$_core/vbo/vbo_file.dart';
const _vboParser = '$_core/vbo/vbo_parser.dart';
const _vboScanner = '$_core/vbo/vbo_row_scanner.dart';
const _vboTimestamp = '$_core/vbo/vbo_timestamp.dart';
const _rczArchive = '$_core/rcz/rcz_archive.dart';
const _rczParser = '$_core/rcz/rcz_parser.dart';
const _recordingSource = '$_core/intake/recording_source.dart';
const _runner = 'lib/import/import_runner.dart';

String _vbo(String message) => '${VboParseError(message)}';
String _limit(String message) => '${ResourceLimitError(message)}';
String _rcz(String message) => '${RczFormatError(message)}';
String _recording(String message) => '${RecordingSourceError(message)}';

/// Each text as its source writes it (a reworded text fails here instead of
/// showing English to a Polish user), the text as shown, and its Polish.
typedef _Row = (
  String path,
  String literal,
  String shown,
  String Function(AppLocalizations l10n) polish,
);

final List<_Row> _rows = [
  // VBO reading.
  (
    _vboFile,
    r"'Could not open VBO: ${error.osError?.message ?? error.message}'",
    _vbo('Could not open VBO: Permission denied'),
    (l) => l.coreVboOpenFailed('Permission denied'),
  ),
  (
    _vboFile,
    r"'Could not read VBO: ${error.osError?.message ?? error.message}'",
    _vbo('Could not read VBO: Input/output error'),
    (l) => l.coreVboReadFailed('Input/output error'),
  ),
  for (final (path, text) in [
    (_vboParser, 'VBO has no [column names] section.'),
    (_vboParser, 'VBO contains no column names.'),
    (_vboParser, 'VBO derived timestamps are not strictly increasing.'),
    (_vboParser, 'VBO parser produced non-monotonic timestamps.'),
    (_vboParser, 'VBO contains more than one data or column-names section.'),
    (_vboParser, 'VBO UTC chronology exceeds the supported date range.'),
    (
      _vboTimestamp,
      'VBO timestamp exceeds the supported signed 64-bit microsecond range.',
    ),
  ])
    (path, "'$text'", _vbo(text), (l) => l.coreVboUnreadable(text)),
  (
    _vboParser,
    "'VBO has no [data] rows.'",
    _vbo('VBO has no [data] rows.'),
    (l) => l.coreVboNoData,
  ),
  (
    _vboParser,
    "'VBO contains no valid timestamped data rows.'",
    _vbo('VBO contains no valid timestamped data rows.'),
    (l) => l.coreVboNoValidRows,
  ),
  for (final (path, text, polish) in <(String, String, _Text)>[
    (
      _vboFile,
      'VBO exceeds the supported 128 MiB file size limit.',
      (l) => l.coreVboFileSize,
    ),
    (
      _vboParser,
      'VBO text exceeds the supported complexity limit.',
      (l) => l.coreVboComplexity,
    ),
    (
      _vboParser,
      'VBO has more values (rows x columns) than the supported 40 million.',
      (l) => l.coreVboTooManyValues,
    ),
    (
      _vboParser,
      'VBO contains a line longer than the supported 1 MiB limit.',
      (l) => l.coreVboLongLine,
    ),
    (_vboParser, 'VBO contains too many lines.', (l) => l.coreVboTooManyLines),
    (
      _vboParser,
      'VBO contains a section name longer than the supported 256 characters.',
      (l) => l.coreVboLongSectionName,
    ),
    (
      _vboParser,
      'VBO contains too many data rows.',
      (l) => l.coreVboTooManyRows,
    ),
    (
      _vboParser,
      'VBO header metadata exceeds the supported size.',
      (l) => l.coreVboHeaderSize,
    ),
    (
      _vboScanner,
      'VBO contains too many columns.',
      (l) => l.coreVboTooManyColumns,
    ),
    (
      _vboScanner,
      'VBO contains a field longer than the supported 64 KiB limit.',
      (l) => l.coreVboLongField,
    ),
    // Recording content.
    (
      _recordingSource,
      'Telemetry file exceeds the content identity size limit.',
      (l) => l.coreSourceIdentitySize,
    ),
    // A day's analysis.
    (
      '$_core/day/day_analysis.dart',
      'Too many recordings in this day.',
      (l) => l.coreDayTooManyRecordings,
    ),
    (
      '$_core/day/day_analysis.dart',
      'This day exceeds the 20,000 lap-section limit.',
      (l) => l.coreDayLapSectionLimit,
    ),
    (
      '$_core/day/track_inference.dart',
      'Too many lap traces for route inference.',
      (l) => l.coreRouteTooManyTraces,
    ),
    (
      '$_core/day/track_inference.dart',
      'Too many runs for route grouping.',
      (l) => l.coreRouteTooManyRuns,
    ),
    (
      '$_core/day/day_progression.dart',
      'Too many runs or lap sections for progression.',
      (l) => l.coreProgressionTooMany,
    ),
    (
      '$_core/day/day_laps.dart',
      'Too many lap sections in this recording.',
      (l) => l.coreRecordingTooManyLapSections,
    ),
    (
      '$_core/day/day_laps.dart',
      'Too many lap sections in this day.',
      (l) => l.coreDayTooManyLapSections,
    ),
    (
      '$_core/day/day_ranking.dart',
      'Too many laps or exclusions to rank this day.',
      (l) => l.coreRankingTooMany,
    ),
    (
      '$_core/laps/lap_detection.dart',
      'Lap detector produced too many accepted passes.',
      (l) => l.coreTooManyPasses,
    ),
    (
      '$_core/laps/lap_traces.dart',
      'Lap traces contain too many GPS points.',
      (l) => l.coreTooManyGpsPoints,
    ),
  ])
    (path, "'$text'", _limit(text), polish),
  // Recording content.
  for (final (text, polish) in <(String, _Text)>[
    ('Cannot read telemetry source.', (l) => l.coreSourceCannotRead),
    (
      'Telemetry source changed while reading; retry with a stable file.',
      (l) => l.coreSourceChangedWhileReading,
    ),
    (
      'Telemetry source read failed or was truncated.',
      (l) => l.coreSourceReadFailed,
    ),
  ])
    (_recordingSource, "'$text'", _recording(text), polish),
  // RCZ reading: "RCZ: " and the text.
  for (final (path, text) in [
    (_rczArchive, 'Decompression exceeded declared size.'),
    (_rczArchive, 'Corrupt compressed member.'),
    (_rczArchive, 'Missing ZIP directory.'),
    (_rczArchive, 'Invalid ZIP directory entry.'),
    (_rczArchive, 'Unsupported or malformed ZIP member.'),
    (_rczArchive, 'Invalid ZIP member offset.'),
    (_rczArchive, 'ZIP local header does not match the directory.'),
    (_rczArchive, 'ZIP size or checksum headers disagree.'),
    (_rczArchive, 'Invalid stored member size.'),
    (_rczArchive, 'Invalid directory member.'),
    (_rczArchive, 'Unexpected ZIP directory data.'),
    (_rczArchive, 'Overlapping ZIP members.'),
    (_rczArchive, 'Unsafe archive member path.'),
    (_rczArchive, 'Archive offset is outside the file.'),
    (_rczParser, 'Fragment does not start at the session origin.'),
    (_rczParser, 'Malformed channel filename.'),
    (_rczParser, 'Unsupported channel value encoding.'),
    (_rczParser, 'Invalid timestamp channel length.'),
    (_rczParser, 'Timestamp/value channel lengths differ.'),
  ])
    (path, "'$text'", _rcz(text), (l) => l.coreRczUnreadable(text)),
  for (final (path, literal, text) in [
    (
      _rczArchive,
      r"'Size or checksum mismatch in $name.'",
      'Size or checksum mismatch in session.json.',
    ),
    (
      _rczParser,
      r"'Invalid $name metadata.'",
      'Invalid sessionfragment.json metadata.',
    ),
    (
      _rczParser,
      r"'Timestamp/value length mismatch: $name'",
      'Timestamp/value length mismatch: channel_1_300_0_4_0',
    ),
  ])
    (path, literal, _rcz(text), (l) => l.coreRczUnreadable(text)),
  for (final (path, literal, text, polish) in <(String, String, String, _Text)>[
    (
      _rczArchive,
      r"'Missing $name.'",
      'Missing session.json.',
      (l) => l.coreRczMissing('session.json'),
    ),
    (
      _rczArchive,
      r"'$name exceeds its size limit.'",
      'session.json exceeds its size limit.',
      (l) => l.coreRczMemberTooLarge('session.json'),
    ),
    (
      _rczParser,
      r"'Multiple sources for ${map.alias} are unsupported.'",
      'Multiple sources for speed are unsupported.',
      (l) => l.coreRczMultipleSources('speed'),
    ),
    for (final (path, text, polish) in <(String, String, _Text)>[
      (
        _rczArchive,
        'Archive size is unsupported.',
        (l) => l.coreRczArchiveSize,
      ),
      (
        _rczArchive,
        'Unsupported ZIP64, split archive or directory limits.',
        (l) => l.coreRczZip64,
      ),
      (
        _rczArchive,
        'Symbolic links are unsupported.',
        (l) => l.coreRczSymlinks,
      ),
      (
        _rczArchive,
        'Duplicate member or archive resource limit exceeded.',
        (l) => l.coreRczDuplicateMember,
      ),
      (_rczArchive, 'Truncated archive.', (l) => l.coreRczTruncated),
      (
        _rczParser,
        'Metadata nesting/string limit exceeded.',
        (l) => l.coreRczMetadataNesting,
      ),
      (
        _rczParser,
        'Metadata array limit exceeded.',
        (l) => l.coreRczMetadataArray,
      ),
      (
        _rczParser,
        'Metadata object limit exceeded.',
        (l) => l.coreRczMetadataObject,
      ),
      (
        _rczParser,
        'Multi-session or resumed archives are not supported; share one '
            'uninterrupted session.',
        (l) => l.coreRczMultiSession,
      ),
      (
        _rczParser,
        'Unsupported session version.',
        (l) => l.coreRczSessionVersion,
      ),
      (
        _rczParser,
        'Resumed sessions are not supported yet.',
        (l) => l.coreRczResumed,
      ),
      (
        _rczParser,
        'Multiple position channels are unsupported.',
        (l) => l.coreRczMultiplePositions,
      ),
      (
        _rczParser,
        'Declared GPS channels are missing.',
        (l) => l.coreRczGpsMissing,
      ),
      (
        _rczParser,
        'Timestamp channel is nonmonotonic or outside the supported 24-hour '
            'session.',
        (l) => l.coreRczTimestamps,
      ),
      (
        _rczParser,
        'Decoded channel/sample budget exceeded.',
        (l) => l.coreRczChannelBudget,
      ),
      (
        _rczParser,
        'Decoded gap/sample budget exceeded.',
        (l) => l.coreRczGapBudget,
      ),
      (_rczParser, 'Too many timing gates.', (l) => l.coreRczTooManyGates),
      (
        _rczParser,
        'Invalid timing gate coordinates or geometry.',
        (l) => l.coreRczInvalidGate,
      ),
      (
        _rczParser,
        'Invalid timing gate endpoint.',
        (l) => l.coreRczInvalidGateEndpoint,
      ),
    ])
      (path, "'$text'", text, polish),
  ])
    (path, literal, _rcz(text), (l) => 'RCZ: ${polish(l)}'),
  // Adding recordings to a day.
  (
    _runner,
    r"'${p.basename(run.sourcePath)}: already in this day.'",
    'a.vbo: already in this day.',
    (l) => 'a.vbo: ${l.additionAlreadyInDay}',
  ),
  (
    _runner,
    r"'${p.basename(run.sourcePath)}: the same drive as $session in the "
        r"other format; kept as its alternative source.'",
    'a.rcz: the same drive as Session 2 in the other format; kept as its '
        'alternative source.',
    (l) => 'a.rcz: ${l.additionSameDriveKept(l.sessionName(2))}',
  ),
  (
    _runner,
    r"'${p.basename(run.sourcePath)}: the same drive as $session in the "
        r"other format; not added again.'",
    'a.rcz: the same drive as Session 2 in the other format; not added again.',
    (l) => 'a.rcz: ${l.additionSameDriveNotAdded(l.sessionName(2))}',
  ),
];

typedef _Text = String Function(AppLocalizations l10n);

void main() {
  final english = lookupAppLocalizations(const Locale('en'));
  final polish = lookupAppLocalizations(const Locale('pl'));

  test('telemetry_core\'s errors and notes are shown in the app language', () {
    final sources = <String, String>{};
    for (final (path, literal, shown, translation) in _rows) {
      final source = sources[path] ??= _source(path);
      expect(source, contains(literal), reason: path);
      // English shows the text as written; Polish translates it, also after
      // a file's name.
      expect(english.coreText(shown), shown);
      expect(english.coreText('a.vbo: $shown'), 'a.vbo: $shown');
      final translated = translation(polish);
      expect(translated, isNot(shown), reason: shown);
      expect(polish.coreText(shown), translated);
      expect(polish.coreText('x.vbo: $shown'), 'x.vbo: $translated');
    }
    expect(_rows, hasLength(greaterThanOrEqualTo(80)));
  });

  test('a text the app does not know is shown as written', () {
    for (final text in [
      'Unsupported format',
      'a.vbo: No such file or directory',
      'RCZ: No such file or directory',
      'RCZ: Missing',
      '',
    ]) {
      expect(polish.coreText(text), text);
      expect(english.coreText(text), text);
    }
  });

  group('errors of real recordings', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('core_text'));
    tearDown(() => deleteTemporaryDirectory(directory));

    String write(String name, List<int> bytes) {
      final path = '${directory.path}/$name';
      File(path).writeAsBytesSync(bytes);
      return path;
    }

    String error(void Function() read) {
      try {
        read();
      } on Exception catch (error) {
        return '$error';
      }
      fail('No error');
    }

    String rcz(List<int> bytes) =>
        error(() => RczParser.parseFile(write('a.rcz', bytes)));

    test('are translated', () {
      final members = fixtureMembers();
      final cases = <(String, String)>[
        (
          error(() => VboParser.parse('not telemetry')),
          polish.coreVboUnreadable('VBO has no [column names] section.'),
        ),
        (
          error(() => VboParser.parse('[column names]\ntime\n[data]\n')),
          polish.coreVboNoData,
        ),
        (rcz([1, 2, 3]), 'RCZ: ${polish.coreRczArchiveSize}'),
        (
          rcz(Uint8List(100)),
          polish.coreRczUnreadable('Missing ZIP directory.'),
        ),
        (
          rcz(zip({...members}..remove('session.json'))),
          'RCZ: ${polish.coreRczMissing('session.json')}',
        ),
        (
          rcz(zip({...members, 'session.json': text('x')})),
          polish.coreRczUnreadable('Invalid session.json metadata.'),
        ),
        (
          rcz(zip({...members, 'old/session.json': text('{}')})),
          'RCZ: ${polish.coreRczMultiSession}',
        ),
        (
          error(() => contentSha256('${directory.path}/none.vbo', 10)),
          polish.coreSourceCannotRead,
        ),
        (
          error(() => contentSha256(write('short.vbo', [1, 2, 3]), 10)),
          polish.coreSourceChangedWhileReading,
        ),
        (
          error(() => contentSha256(write('empty.vbo', []), 0)),
          polish.coreSourceIdentitySize,
        ),
      ];
      for (final (shown, translated) in cases) {
        expect(english.coreText(shown), shown);
        expect(polish.coreText(shown), translated, reason: shown);
      }
      final missing = error(
        () => parseVboFile('${directory.path}/missing.vbo'),
      );
      expect(missing, startsWith('Could not open VBO: '));
      expect(polish.coreText(missing), startsWith('Nie można otworzyć'));
    });
  });

  test('a day note, an addition error and a missing recording say a '
      'telemetry_core error in the app language', () {
    const limit = 'Too many lap sections in this recording.';
    expect(english.dayNote(limit), limit);
    expect(polish.dayNote(limit), polish.coreRecordingTooManyLapSections);
    expect(polish.dayNote(noGpsNote), polish.noteNoGps);

    const added = 'Nothing was added: Too many recordings in this day.';
    expect(english.additionError(added), added);
    expect(
      polish.additionError(added),
      polish.nothingAddedError(polish.coreDayTooManyRecordings),
    );
    const scan = 'The folder does not exist or is not a folder.';
    expect(english.additionError(scan), scan);
    expect(polish.additionError(scan), polish.importPageNoFolder);

    const truncated = 'RCZ: Truncated archive.';
    expect(english.missingReason(truncated), truncated);
    expect(polish.missingReason(truncated), 'RCZ: ${polish.coreRczTruncated}');
    expect(
      polish.missingReason('Recording not found.'),
      polish.missingRecordingNotFound,
    );

    const read = 'Cannot read telemetry source.';
    expect(english.taskFailure(read), read);
    expect(polish.taskFailure(read), polish.coreSourceCannotRead);
    expect(polish.taskFailure('The work stopped.'), polish.taskStopped);
  });
}
