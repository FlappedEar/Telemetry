import 'package:telemetry_core/telemetry_core.dart' show unexpectedFileError;

import 'l10n.dart';

// The texts below are written as `telemetry_core` and the app's import
// write them; test/l10n/core_text_test.dart and
// test/import/import_messages_test.dart check each against its source.
// telemetry_core keeps its English (its tests and Overlays parity pin it);
// the app shows it in its own language here.

// What the import says (`DayImportFailed.message`, the notes of a scan and
// a plan) as written in `import_runner.dart`, `day_import_controller.dart`
// and `telemetry_core`'s folder scan.
final _folderTooMany = RegExp(
  r'^The folder holds (\d+) recordings; import at most (\d+) at a time\. '
  r'Choose a smaller folder\.$',
);
final _tooMany = RegExp(
  r'^That is (\d+) recordings; import at most (\d+) at a time\.$',
);
final _stoppedAfter = RegExp(
  r'^Stopped after (\d+) files and folders; recordings beyond that were '
  r'not scanned\.$',
);
final _tooDeep = RegExp(
  r'^(\d+) folder\(s\) deeper than (\d+) levels were not scanned\.$',
);
final _links = RegExp(r'^(\d+) link\(s\) were not followed\.$');
final _others = RegExp(
  r'^(\d+) other file\(s\) were ignored; only VBO and RCZ recordings are '
  r'imported\.$',
);
final _sameContent = RegExp(r'^same content as (.+); imported once\.$');
// Not the note of adding to a day, "... as Session 2 in the other format;
// kept as ...".
final _sameDrive = RegExp(
  r'^the same drive as ((?:(?! in the other format;).)+); kept as its '
  r'alternative source\.$',
);
// Adding to a day: "a.rcz: the same drive as Session 2 in the other format;
// kept as its alternative source." (`import_runner.dart`).
final _sameDriveOtherFormat = RegExp(
  r'^the same drive as (.+) in the other format; (kept as its alternative '
  r'source|not added again)\.$',
);

// VBO reading (`vbo/`).
final _vboOpen = RegExp(r'^Could not open VBO: (.*)$', dotAll: true);
final _vboRead = RegExp(r'^Could not read VBO: (.*)$', dotAll: true);

/// VBO errors about the file's inner structure, which a driver cannot act
/// on: said as one "cannot read" sentence keeping the detail as written.
const _vboUnreadable = {
  'VBO has no [column names] section.',
  'VBO contains no column names.',
  'VBO derived timestamps are not strictly increasing.',
  'VBO parser produced non-monotonic timestamps.',
  'VBO contains more than one data or column-names section.',
  'VBO UTC chronology exceeds the supported date range.',
  'VBO timestamp exceeds the supported signed 64-bit microsecond range.',
};

/// How `RczFormatError` starts every message.
const _rczPrefix = 'RCZ: ';

/// RCZ errors about the archive's inner structure, which a driver cannot
/// act on, after "RCZ: "; with [_rczUnreadablePatterns].
const _rczUnreadable = {
  'Decompression exceeded declared size.',
  'Corrupt compressed member.',
  'Missing ZIP directory.',
  'Invalid ZIP directory entry.',
  'Unsupported or malformed ZIP member.',
  'Invalid ZIP member offset.',
  'ZIP local header does not match the directory.',
  'ZIP size or checksum headers disagree.',
  'Invalid stored member size.',
  'Invalid directory member.',
  'Unexpected ZIP directory data.',
  'Overlapping ZIP members.',
  'Unsafe archive member path.',
  'Archive offset is outside the file.',
  'Fragment does not start at the session origin.',
  'Malformed channel filename.',
  'Unsupported channel value encoding.',
  'Invalid timestamp channel length.',
  'Timestamp/value channel lengths differ.',
};
final _rczUnreadablePatterns = [
  RegExp(r'^Size or checksum mismatch in .+\.$'),
  RegExp(r'^Invalid .+ metadata\.$'),
  RegExp(r'^Timestamp/value length mismatch: .+$'),
];
final _rczMissing = RegExp(r'^Missing (.+)\.$');
final _rczMemberTooLarge = RegExp(r'^(.+) exceeds its size limit\.$');
final _rczMultipleSources = RegExp(
  r'^Multiple sources for (.+) are unsupported\.$',
);

/// Errors and notes from `telemetry_core` and the import in the app's
/// language.
extension CoreText on AppLocalizations {
  /// An error or a note from `telemetry_core` or the import (a recording
  /// that cannot be read, a limit, a note of a scan or a plan), also one
  /// about a file or folder ("a.vbo: not found; not imported."), in the
  /// app's language. A text the app does not know, such as the system's
  /// reason a file could not be opened, is shown as written.
  String coreText(String text) {
    if (_known(text) case final known?) return known;
    // "name: text", the name being the part before the first ": " whose
    // text is known.
    for (
      var at = text.indexOf(': ');
      at >= 0;
      at = text.indexOf(': ', at + 2)
    ) {
      if (_known(text.substring(at + 2)) case final known?) {
        return '${text.substring(0, at)}: $known';
      }
    }
    return text;
  }

  String? _known(String message) =>
      _importMessage(message) ??
      _vboMessage(message) ??
      _rczMessage(message) ??
      _coreMessage(message);

  String? _importMessage(String message) {
    int number(Match match, int group) => int.parse(match.group(group)!);
    if (message.startsWith(unexpectedFileError)) {
      return importUnexpectedError(
        message.substring(unexpectedFileError.length),
      );
    }
    const failed = 'The import failed: ';
    if (message.startsWith(failed)) {
      return importPageImportFailed(coreText(message.substring(failed.length)));
    }
    if (_folderTooMany.firstMatch(message) case final match?) {
      return importPageFolderTooMany(number(match, 1), number(match, 2));
    }
    if (_tooMany.firstMatch(message) case final match?) {
      return importPageTooMany(number(match, 1), number(match, 2));
    }
    if (_stoppedAfter.firstMatch(message) case final match?) {
      return importPageStoppedAfter(number(match, 1));
    }
    if (_tooDeep.firstMatch(message) case final match?) {
      return importPageTooDeep(number(match, 1), number(match, 2));
    }
    if (_links.firstMatch(message) case final match?) {
      return importPageLinksSkipped(number(match, 1));
    }
    if (_others.firstMatch(message) case final match?) {
      return importPageOtherFilesSkipped(number(match, 1));
    }
    if (_sameContent.firstMatch(message) case final match?) {
      return importPageSameContent(match.group(1)!);
    }
    if (_sameDrive.firstMatch(message) case final match?) {
      return importPageSameDrive(match.group(1)!);
    }
    return switch (message) {
      'No recording could be imported.' => importPageNoRecording,
      'Import failed.' => importPageFailed,
      'Bad state: The import stopped unexpectedly.' =>
        importPageStoppedUnexpectedly,
      'The folder does not exist or is not a folder.' => importPageNoFolder,
      'Choose the folder itself, not a link to it.' => importPageFolderLink,
      'No VBO or RCZ recordings were found.' => importPageNoneFound,
      'No VBO or RCZ recordings were found (subfolders were not included).' =>
        importPageNoneFoundNoSubfolders,
      'No VBO or RCZ recordings to import.' => importPageNothingToImport,
      'not found; not imported.' => importPageFileNotFound,
      'a macOS metadata file, not a recording; not imported.' =>
        importPageMetadataFile,
      'a link; not followed.' => importPageFileLink,
      'not a VBO or RCZ recording; not imported.' => importPageNotRecording,
      'Choose a VBO or RaceChrono RCZ telemetry file.' => importPageChooseFile,
      'Telemetry source is not an existing regular file.' =>
        importPageNotRegularFile,
      'Too many files in one import; select a smaller batch.' =>
        importPageTooManyFiles,
      'Telemetry source path is too long.' => importPagePathTooLong,
      'Telemetry file is empty or exceeds the per-file import limit.' =>
        importPageFileSize,
      'Batch input-byte limit exceeded; import fewer recordings.' =>
        importPageBatchBytes,
      'Identical file content already present in this batch.' =>
        importPageIdenticalContent,
      'Telemetry source changed during import; retry with a stable file.' =>
        importPageSourceChanged,
      'Telemetry source has an invalid time range.' =>
        importPageInvalidTimeRange,
      'Telemetry source has mismatched channel timestamps and values.' =>
        importPageMismatchedChannels,
      'Batch decoded-sample limit exceeded; import fewer recordings.' =>
        importPageBatchSamples,
      'Source grouping exceeds the import limit.' => importPageGroupingLimit,
      _ => null,
    };
  }

  String? _vboMessage(String message) {
    if (_vboOpen.firstMatch(message) case final match?) {
      return coreVboOpenFailed(match.group(1)!);
    }
    if (_vboRead.firstMatch(message) case final match?) {
      return coreVboReadFailed(match.group(1)!);
    }
    if (_vboUnreadable.contains(message)) return coreVboUnreadable(message);
    return switch (message) {
      'VBO has no [data] rows.' => coreVboNoData,
      'VBO contains no valid timestamped data rows.' => coreVboNoValidRows,
      'VBO has no time column (time, timestamp or utc_time), so its samples cannot be timed.' =>
        coreVboNoTimeColumn,
      'VBO exceeds the supported 128 MiB file size limit.' => coreVboFileSize,
      'VBO text exceeds the supported complexity limit.' => coreVboComplexity,
      'VBO has more values (rows x columns) than the supported 40 million.' =>
        coreVboTooManyValues,
      'VBO contains a line longer than the supported 1 MiB limit.' =>
        coreVboLongLine,
      'VBO contains too many lines.' => coreVboTooManyLines,
      'VBO contains a section name longer than the supported 256 '
          'characters.' =>
        coreVboLongSectionName,
      'VBO contains too many data rows.' => coreVboTooManyRows,
      'VBO header metadata exceeds the supported size.' => coreVboHeaderSize,
      'VBO contains too many columns.' => coreVboTooManyColumns,
      'VBO contains a field longer than the supported 64 KiB limit.' =>
        coreVboLongField,
      _ => null,
    };
  }

  /// An `RczFormatError` ("RCZ: ..."); the prefix is kept before a known
  /// text, as written.
  String? _rczMessage(String message) {
    if (!message.startsWith(_rczPrefix)) return null;
    final text = message.substring(_rczPrefix.length);
    if (_rczUnreadable.contains(text) ||
        _rczUnreadablePatterns.any((pattern) => pattern.hasMatch(text))) {
      return coreRczUnreadable(text);
    }
    final String? known;
    if (_rczMissing.firstMatch(text) case final match?) {
      known = coreRczMissing(match.group(1)!);
    } else if (_rczMemberTooLarge.firstMatch(text) case final match?) {
      known = coreRczMemberTooLarge(match.group(1)!);
    } else if (_rczMultipleSources.firstMatch(text) case final match?) {
      known = coreRczMultipleSources(match.group(1)!);
    } else {
      known = switch (text) {
        'Archive size is unsupported.' => coreRczArchiveSize,
        'Unsupported ZIP64, split archive or directory limits.' => coreRczZip64,
        'Symbolic links are unsupported.' => coreRczSymlinks,
        'Duplicate member or archive resource limit exceeded.' =>
          coreRczDuplicateMember,
        'Truncated archive.' => coreRczTruncated,
        'Metadata nesting/string limit exceeded.' => coreRczMetadataNesting,
        'Metadata array limit exceeded.' => coreRczMetadataArray,
        'Metadata object limit exceeded.' => coreRczMetadataObject,
        'Multi-session or resumed archives are not supported; share one '
            'uninterrupted session.' =>
          coreRczMultiSession,
        'Unsupported session version.' => coreRczSessionVersion,
        'Resumed sessions are not supported yet.' => coreRczResumed,
        'Multiple position channels are unsupported.' =>
          coreRczMultiplePositions,
        'Declared GPS channels are missing.' => coreRczGpsMissing,
        'Timestamp channel is nonmonotonic or outside the supported 24-hour '
            'session.' =>
          coreRczTimestamps,
        'Decoded channel/sample budget exceeded.' => coreRczChannelBudget,
        'Decoded gap/sample budget exceeded.' => coreRczGapBudget,
        'Too many timing gates.' => coreRczTooManyGates,
        'Invalid timing gate coordinates or geometry.' => coreRczInvalidGate,
        'Invalid timing gate endpoint.' => coreRczInvalidGateEndpoint,
        _ => null,
      };
    }
    return known == null ? null : '$_rczPrefix$known';
  }

  /// Reading a recording's content, the limits of a day's analysis and
  /// notes of adding recordings to a day.
  String? _coreMessage(String message) {
    if (_sameDriveOtherFormat.firstMatch(message) case final match?) {
      final session = this.session(match.group(1)!);
      return match.group(2) == 'not added again'
          ? additionSameDriveNotAdded(session)
          : additionSameDriveKept(session);
    }
    return switch (message) {
      'Telemetry file exceeds the content identity size limit.' =>
        coreSourceIdentitySize,
      'Cannot read telemetry source.' => coreSourceCannotRead,
      'Telemetry source changed while reading; retry with a stable file.' =>
        coreSourceChangedWhileReading,
      'Telemetry source read failed or was truncated.' => coreSourceReadFailed,
      'Too many recordings in this day.' => coreDayTooManyRecordings,
      'This day exceeds the 20,000 lap-section limit.' =>
        coreDayLapSectionLimit,
      'Too many lap traces for route inference.' => coreRouteTooManyTraces,
      'Too many runs for route grouping.' => coreRouteTooManyRuns,
      'Too many runs or lap sections for progression.' =>
        coreProgressionTooMany,
      'Too many lap sections in this recording.' =>
        coreRecordingTooManyLapSections,
      'Too many lap sections in this day.' => coreDayTooManyLapSections,
      'Too many laps or exclusions to rank this day.' => coreRankingTooMany,
      'Lap detector produced too many accepted passes.' => coreTooManyPasses,
      'Lap traces contain too many GPS points.' => coreTooManyGpsPoints,
      'already in this day.' => additionAlreadyInDay,
      _ => null,
    };
  }
}
