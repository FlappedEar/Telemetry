import 'dart:typed_data';

import '../geometry.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import '../timing_gate.dart';
import 'channel_aliases.dart';
import 'vbo_coordinates.dart';
import 'vbo_limits.dart';
import 'vbo_parser_error.dart';
import 'vbo_row_scanner.dart';
import 'vbo_text.dart';
import 'vbo_timestamp.dart';

export 'vbo_parser_error.dart';

final RegExp _sectionPattern = RegExp(r'^\[([^\]]+)\]$');
final RegExp _timeName = RegExp(r'^(?:time|timestamp|utc.?time)$', caseSensitive: false);
final RegExp _asciiSpaceRun = RegExp(r'[\t\n\x0B\f\r ]+');
final RegExp _metadataSeparator = RegExp('[:=]');
final RegExp _createdPattern = RegExp(
  r'^File created on (\d{2})/(\d{2})/(\d{4}) at (\d{2}):(\d{2}):(\d{2})$',
);

/// A time of day that moves backward is read as the clock passing midnight
/// when, read that way, it moved forward by at most this long (FET-211): a
/// dropout from 22:50 to 01:10 is a rollover. A longer "gap" is a clock
/// reset or a bad row, and a small step back (jitter, a daylight-saving
/// change) is too: those rows are skipped as moving backward. A clock reset
/// less than this long before midnight cannot be told from a rollover. Overlays
/// requires the time before to be after 23:00 and the time after to be
/// before 01:00 (departure: KAN-233).
const double vboMaximumRolloverGapSeconds = 3.0 * 3600.0;

const double _floatMax = 3.4028234663852886e38;

/// Reads RaceChrono VBO text exports into a [TelemetrySession].
///
/// Behaviour matches FlappedEar Overlays' parser, so both apps read the same
/// channels, samples and laps from a file (see the handover, section "VBO").
abstract final class VboParser {
  /// Parses decoded VBO [text]. Throws [VboParseError] for a file that is not
  /// a usable recording, [ResourceLimitError] when a size limit is exceeded,
  /// and [OperationCancelled] when [cancelled] asks to stop.
  static TelemetrySession parse(String text, {CancellationCheck? cancelled}) =>
      _VboParse(cancelled).run(text);

  /// Decodes UTF-8 [bytes] and parses them.
  static TelemetrySession parseBytes(Uint8List bytes, {CancellationCheck? cancelled}) {
    throwIfCancelled(cancelled);
    if (bytes.length > VboLimits.maximumFileBytes) {
      throw const ResourceLimitError('VBO exceeds the supported 128 MiB file size limit.');
    }
    return parse(decodeUtf8(bytes), cancelled: cancelled);
  }
}

class _VboParse {
  _VboParse(this.cancelled);

  final CancellationCheck? cancelled;
  final List<String> warnings = [];
  int omittedWarnings = 0;

  void warn(String warning) {
    if (warnings.length < VboLimits.maximumWarnings) {
      warnings.add(warning);
    } else {
      ++omittedWarnings;
    }
  }

  TelemetrySession run(String text) {
    throwIfCancelled(cancelled);
    if (text.length > VboLimits.maximumFileBytes) {
      throw const ResourceLimitError('VBO text exceeds the supported complexity limit.');
    }
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xfeff) text = text.substring(1);

    final sections = _splitSections(text);

    final timingLines = sections['laptiming'] ?? const <String>[];
    final coordinates = resolveCoordinateEvidence(sections, cancelled);
    final raceChrono = coordinates.raceChrono;
    final centreDirection = coordinates.centreDirection;
    final timingGates = <TimingGate>[];
    if (raceChrono && !centreDirection && timingLines.isNotEmpty) {
      warn(
        'Timing gates ignored: this RaceChrono exporter version has not been '
        'validated. Telemetry remains available.',
      );
    }
    var timingLimitWarned = false;
    for (var index = 0; index < timingLines.length; ++index) {
      if ((index & 0x3f) == 0) throwIfCancelled(cancelled);
      final unit = coordinates.unit;
      if (unit == null || (raceChrono && !centreDirection)) break;
      final parsed = parseTimingGate(timingLines[index], centreDirection, unit);
      final gate = parsed.gate;
      if (gate == null) {
        warn('Timing line ${index + 1} ignored: ${parsed.error}.');
        continue;
      }
      if (timingGates.length >= VboLimits.maximumTimingGates) {
        if (!timingLimitWarned) {
          warn('Additional timing gates ignored after the supported limit of 128.');
          timingLimitWarned = true;
        }
        continue;
      }
      timingGates.add(gate);
    }

    final metadata = _metadata(sections);

    List<String>? columnSection;
    List<String>? dataSection;
    for (final MapEntry(:key, :value) in sections.entries) {
      if ((columnSection == null || columnSection.isEmpty) && key.contains('column')) {
        columnSection = value;
      }
      if ((dataSection == null || dataSection.isEmpty) && key.startsWith('data')) {
        dataSection = value;
      }
    }
    if (columnSection == null || columnSection.isEmpty) {
      throw const VboParseError('VBO has no [column names] section.');
    }
    if (dataSection == null || dataSection.isEmpty) {
      throw const VboParseError('VBO has no [data] rows.');
    }

    var names = scanRow(columnSection, VboLimits.maximumColumns, true, cancelled).cells;
    if (names.isEmpty) throw const VboParseError('VBO contains no column names.');
    names = [for (final name in names) _normalizeName(name)];
    final hasCoordinates = names.any((name) => coordinateAxisForName(name) != null);
    if (coordinates.unit == null && (hasCoordinates || timingLines.isNotEmpty)) {
      warn(
        'GPS coordinates and timing gates unavailable: ${coordinates.error}. '
        'Other telemetry remains available.',
      );
    }
    // Derived metadata always overrides anything the file itself declares.
    metadata['gpsCoordinateUnit'] = switch (coordinates.unit) {
      CoordinateUnit.degrees => 'degrees',
      CoordinateUnit.arcMinutes => 'arc-minutes',
      null => 'unresolved',
    };
    metadata['gpsCoordinateEvidence'] = coordinates.source;
    metadata.remove('timingGateFormat');
    if (centreDirection && coordinates.unit != null) {
      metadata['timingGateFormat'] = 'racechrono-pro-10.2.4-centre-direction';
    }
    names = _uniqueNames(names);
    final timeIndex = names.indexWhere(_timeName.hasMatch);

    if (dataSection.length * names.length > VboLimits.maximumDecodedValues) {
      throw const ResourceLimitError(
        'VBO has more values (rows x columns) than the supported 40 million.',
      );
    }
    // Without a time column the samples have no time: a made-up clock (one
    // row a second, as Overlays does) would turn every time-based result
    // into a believable but wrong one (FET-203).
    if (timeIndex < 0) {
      throw const VboParseError(
        'VBO has no time column (time, timestamp or utc_time), so its samples cannot be timed.',
      );
    }

    final rawValues = [for (final _ in names) Float32List(dataSection.length)];
    final rawTimes = Float64List(dataSection.length);
    var accepted = 0;
    var shortRows = 0;
    var fullRows = 0;
    var extraRows = 0;
    double? origin;
    var originIsClock = false;
    double? previousAbsoluteTime;
    double? previousClockTime;
    var clockDayOffset = 0.0;
    // A rollover is confirmed by the next accepted row (FET-211): if a clock
    // row before that is back on the evening before (at or up to 3 h after
    // the time before the rollover), the "rollover" was one bad row, which
    // is dropped and the day offset restored. Two bad rows in a row confirm
    // each other; a bad last row cannot be told from a real midnight.
    ({int row, double absolute, double? clock, double offset, bool short, bool extra})?
    unconfirmedRollover;

    // Fields are read in place: no string per value.
    final row = RowBounds(names.length);
    final axes = [for (final name in names) coordinateAxisForName(name)];
    for (var rowIndex = 0; rowIndex < dataSection.length; ++rowIndex) {
      if ((rowIndex & 0xff) == 0) throwIfCancelled(cancelled);
      final line = dataSection[rowIndex];
      row.scan(line, cancelled);
      final cellCount = row.retained;
      final rowNumber = rowIndex + 1;
      if (cellCount < names.length) {
        warn('Row $rowNumber: missing ${names.length - cellCount} value(s).');
      }
      if (row.count > names.length) {
        warn('Row $rowNumber: ignored ${row.count - names.length} extra value(s).');
      }
      final timeText = timeIndex < cellCount
          ? line.substring(row.starts[timeIndex], row.ends[timeIndex])
          : null;
      final ParsedTimestamp? parsedTime = timeText != null ? parseTimestamp(timeText) : null;
      if (parsedTime == null) {
        warn('Row $rowNumber: invalid timestamp "${timeText ?? ''}"; row skipped.');
        continue;
      }
      var absoluteTime = checkedTime(parsedTime.seconds);
      final rollover = unconfirmedRollover;
      final beforeRollover = rollover?.clock;
      if (rollover != null &&
          beforeRollover != null &&
          parsedTime.format == TimestampFormat.clock &&
          parsedTime.seconds >= beforeRollover &&
          parsedTime.seconds - beforeRollover <= vboMaximumRolloverGapSeconds) {
        unconfirmedRollover = null;
        --accepted;
        // The dropped row is no evidence of the file's shape either.
        if (rollover.short) {
          --shortRows;
        } else {
          --fullRows;
        }
        if (rollover.extra) --extraRows;
        previousAbsoluteTime = rollover.absolute;
        previousClockTime = rollover.clock;
        clockDayOffset = rollover.offset;
        warn('Row ${rollover.row}: not a midnight rollover after all; row skipped.');
      }
      ({int row, double absolute, double? clock, double offset, bool short, bool extra})?
      rolledOver;
      if (parsedTime.format == TimestampFormat.clock) {
        if (previousClockTime != null &&
            previousAbsoluteTime != null &&
            parsedTime.seconds < previousClockTime &&
            parsedTime.seconds + 24.0 * 3600.0 - previousClockTime <=
                vboMaximumRolloverGapSeconds) {
          rolledOver = (
            row: rowNumber,
            absolute: previousAbsoluteTime,
            clock: previousClockTime,
            offset: clockDayOffset,
            short: cellCount < names.length,
            extra: row.hasExtraValue,
          );
          clockDayOffset = checkedTime(clockDayOffset + 24.0 * 3600.0);
          warn('Row $rowNumber: midnight rollover detected.');
        }
        absoluteTime = checkedTime(absoluteTime + clockDayOffset);
      }
      if (origin == null) {
        origin = absoluteTime;
        originIsClock = parsedTime.format == TimestampFormat.clock;
      }
      final timestamp = checkedTime(absoluteTime - origin);
      if (previousAbsoluteTime != null) {
        if (absoluteTime == previousAbsoluteTime) {
          // Keep the first row so every channel stays on one strictly
          // increasing clock.
          warn('Row $rowNumber: duplicate timestamp ${_fixed3(timestamp)}; later row skipped.');
          continue;
        }
        if (absoluteTime < previousAbsoluteTime) {
          warn(
            'Row $rowNumber: timestamp moved backward from '
            '${_fixed3(rawTimes[accepted - 1])} to ${_fixed3(timestamp)}; row skipped.',
          );
          continue;
        }
      }
      // Distinct absolute times can round to the same elapsed time.
      if (timestamp < 0.0 || (accepted > 0 && timestamp <= rawTimes[accepted - 1])) {
        throw const VboParseError('VBO derived timestamps are not strictly increasing.');
      }
      rawTimes[accepted] = timestamp;
      for (var column = 0; column < names.length; ++column) {
        final parsed = column < cellCount
            ? parseDecimalRange(line, row.starts[column], row.ends[column])
            : null;
        final normalized = parsed != null && parsed.isFinite
            ? normalizeAxisValue(axes[column], parsed, coordinates.unit)
            : double.nan;
        // Beyond the float range is no data, not infinity.
        rawValues[column][accepted] = normalized.isFinite && normalized.abs() <= _floatMax
            ? normalized
            : double.nan;
      }
      // Only rows that were kept count as evidence of the file's shape: a
      // full row skipped for its time must not outvote the short rows read.
      if (cellCount < names.length) {
        ++shortRows;
      } else {
        ++fullRows;
      }
      if (row.hasExtraValue) ++extraRows;
      ++accepted;
      unconfirmedRollover = rolledOver;
      previousAbsoluteTime = absoluteTime;
      previousClockTime = parsedTime.format == TimestampFormat.clock ? parsedTime.seconds : null;
    }
    // Values are matched to names by position, so a row short of values is
    // read as missing its trailing ones. When most rows are short and a name
    // stands before the time column, a name split in two ("UTC time") or a
    // dropped value moves the clock onto another column and times the rows
    // wrongly: refuse rather than guess (FET-242). A time column first cannot
    // move, so such a file is read, with each short row warned about.
    // Known limit, by design: a header listing trailing names that rows never
    // fill is refused although the clock would be safe (that cannot be told
    // from a split name).
    if (shortRows > fullRows && timeIndex > 0) {
      throw const VboParseError(
        'VBO header has more names than its rows have values, so the time column cannot be found with certainty.',
      );
    }
    // The mirror image (FET-271): when most rows have more values than the
    // header has names, an unnamed column may stand before the time column and
    // be read as the clock (an incrementing counter times the file at 1 Hz).
    // Refused for any time column position, since a leading value cannot be
    // told from a trailing one.
    if (extraRows > accepted - extraRows) {
      throw const VboParseError(
        'VBO rows have more values than its header has names, so the time column cannot be found with certainty.',
      );
    }
    if (omittedWarnings > 0) {
      warnings.add('… $omittedWarnings additional parser warnings omitted.');
    }
    if (accepted == 0) {
      throw const VboParseError('VBO contains no valid timestamped data rows.');
    }
    // Handed over to the channels, which share it read-only.
    final times = adoptChannelTimestamps(Float64List.sublistView(rawTimes, 0, accepted));
    for (var index = 1; index < times.length; ++index) {
      if ((index & 0xfff) == 0) throwIfCancelled(cancelled);
      if (!(times[index] > times[index - 1])) {
        throw const VboParseError('VBO parser produced non-monotonic timestamps.');
      }
    }

    final channels = <String, TelemetryChannel>{};
    for (var column = 0; column < names.length; ++column) {
      if ((column & 0x1f) == 0) throwIfCancelled(cancelled);
      if (column == timeIndex) continue;
      final values = adoptChannelValues(Float32List.sublistView(rawValues[column], 0, accepted));
      if (!values.any((value) => value.isFinite)) continue;
      channels[names[column]] = TelemetryChannel(
        name: names[column],
        timestamps: times,
        values: values,
      );
    }
    final duration = checkedTime(times.last - times.first);
    final startTime = checkedTime(origin ?? 0.0);
    metadata.remove('firstTimestampMilliseconds');
    metadata.remove('gpsLongitudeConvention');
    if (centreDirection && coordinates.unit != null) {
      metadata['gpsLongitudeConvention'] = 'west-positive';
    }
    if (raceChrono && originIsClock) {
      final milliseconds = _firstTimestampMilliseconds(sections[''] ?? const [], startTime);
      if (milliseconds != null) {
        metadata['firstTimestampMilliseconds'] = milliseconds.toString();
      }
    }
    final aliases = resolveAliases(sortedChannelNames(channels.keys), channels: channels);
    preferAcceleratorPedalForThrottle(aliases, channels);
    throwIfCancelled(cancelled);
    return TelemetrySession(
      duration: duration,
      startTime: startTime,
      metadata: metadata,
      channels: channels,
      aliases: aliases,
      warnings: warnings,
      timingGates: timingGates,
      sampleCount: accepted,
    );
  }

  /// Splits [text] into lines and groups them by section, in first-appearance
  /// order. Lines before any section header belong to the section named ''.
  /// Every limit is checked before a line string is created.
  Map<String, List<String>> _splitSections(String text) {
    final sections = <String, List<String>>{'': []};
    var section = '';
    var current = sections['']!;
    var dataRows = 0;
    String? dataSectionName;
    String? columnSectionName;
    var lineIndex = 0;
    var start = 0;
    final length = text.length;
    for (var position = 0; position <= length; ++position) {
      if ((position & 0xfff) == 0) throwIfCancelled(cancelled);
      if (position < length && text.codeUnitAt(position) != 0x0a) {
        final lineLength = position - start + 1;
        final crlf =
            text.codeUnitAt(position) == 0x0d &&
            position + 1 < length &&
            text.codeUnitAt(position + 1) == 0x0a;
        if (lineLength > VboLimits.maximumLineCharacters && !crlf) {
          throw const ResourceLimitError(
            'VBO contains a line longer than the supported 1 MiB limit.',
          );
        }
        continue;
      }
      if (++lineIndex > VboLimits.maximumLines) {
        throw const ResourceLimitError('VBO contains too many lines.');
      }
      if ((lineIndex & 0xff) == 0) throwIfCancelled(cancelled);
      var end = position;
      if (position < length && end > start && text.codeUnitAt(end - 1) == 0x0d) --end;
      final line = trimSpace(text.substring(start, end));
      start = position + 1;
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;
      final match = _sectionPattern.firstMatch(line);
      if (match != null) {
        final name = match[1]!;
        if (name.length > VboLimits.maximumSectionNameCharacters) {
          throw const ResourceLimitError(
            'VBO contains a section name longer than the supported 256 characters.',
          );
        }
        section = trimSpace(name).toLowerCase();
        // One data section and one column-names section; a repeated header of
        // the same section continues it.
        final data = section.startsWith('data');
        final columns = section.contains('column');
        if ((data && dataSectionName != null && dataSectionName != section) ||
            (columns && columnSectionName != null && columnSectionName != section)) {
          throw const VboParseError('VBO contains more than one data or column-names section.');
        }
        if (data) dataSectionName = section;
        if (columns) columnSectionName = section;
        current = sections.putIfAbsent(section, () => []);
      } else {
        if (section.startsWith('data') && ++dataRows > VboLimits.maximumDataRows) {
          throw const ResourceLimitError('VBO contains too many data rows.');
        }
        current.add(line);
      }
    }
    return sections;
  }

  /// `key: value` and `key = value` lines of every section other than the
  /// column names, the data and the timing lines. A line without a separator
  /// is kept under `<section>.<n>`.
  Map<String, String> _metadata(Map<String, List<String>> sections) {
    final metadata = <String, String>{};
    var entries = 0;
    var characters = 0;
    for (final MapEntry(:key, :value) in sections.entries) {
      throwIfCancelled(cancelled);
      if (key.contains('column') || key.contains('data') || key == 'laptiming') continue;
      for (final entry in value) {
        if ((entries & 0xff) == 0) throwIfCancelled(cancelled);
        characters += entry.length + key.length + 16;
        if (++entries > VboLimits.maximumMetadataEntries ||
            characters > VboLimits.maximumMetadataCharacters) {
          throw const ResourceLimitError('VBO header metadata exceeds the supported size.');
        }
        final separator = entry.indexOf(_metadataSeparator);
        if (separator >= 0) {
          metadata[_normalizeName(entry.substring(0, separator))] = trimSpace(
            entry.substring(separator + 1),
          );
        } else {
          metadata['$key.${metadata.length}'] = entry;
        }
      }
    }
    return metadata;
  }
}

/// Recording start as milliseconds since the Unix epoch, UTC, from exactly one
/// `File created on dd/MM/yyyy at HH:mm:ss` line. The first sample's clock
/// time gives the time of day; a start clock more than 12 hours before the
/// creation time is taken to be on the next day.
int? _firstTimestampMilliseconds(List<String> preamble, double startTime) {
  final lines = preamble.where((line) => line.startsWith('File created on ')).toList();
  if (lines.length != 1) return null;
  final match = _createdPattern.firstMatch(lines.single);
  if (match == null) return null;
  final day = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final year = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > _daysInMonth(year, month)) {
    return null;
  }
  if (hour > 23 || minute > 59 || second > 59) return null;
  var midnight = DateTime.utc(year, month, day);
  if (checkedTime(startTime + 12 * 3600) < hour * 3600 + minute * 60 + second) {
    midnight = DateTime.utc(year, month, day + 1);
  }
  final offset = (startTime * 1000.0).round();
  if (offset < 0) {
    throw const VboParseError('VBO UTC chronology exceeds the supported date range.');
  }
  return midnight.millisecondsSinceEpoch + offset;
}

int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

String _fixed3(double value) => value.toStringAsFixed(3);

/// Trims a column or metadata name, drops one pair of surrounding quotes and
/// collapses ASCII white-space runs to one space.
String _normalizeName(String name) {
  var text = trimSpace(name);
  if (text.length >= 2) {
    final first = text.codeUnitAt(0);
    final last = text.codeUnitAt(text.length - 1);
    if ((first == 0x27 && last == 0x27) || (first == 0x22 && last == 0x22)) {
      text = text.substring(1, text.length - 1);
    }
  }
  return text.replaceAll(_asciiSpaceRun, ' ');
}

/// Gives every column a unique, non-empty name: an empty header cell becomes
/// `column N`, and a repeated name becomes `name (2)`, `name (3)`... never
/// taking a name the header itself uses.
List<String> _uniqueNames(List<String> input) {
  final used = {
    for (final name in input)
      if (name.isNotEmpty) name,
  };
  final taken = <String>{};
  final counts = <String, int>{};
  final output = <String>[];
  for (var index = 0; index < input.length; ++index) {
    final base = input[index].isEmpty ? 'column ${index + 1}' : input[index];
    var name = base;
    if (taken.contains(name) || (input[index].isEmpty && used.contains(name))) {
      var count = counts[base] ?? 0;
      if (count < 1) count = 1;
      do {
        name = '$base (${++count})';
      } while (taken.contains(name) || used.contains(name));
      counts[base] = count;
    }
    taken.add(name);
    output.add(name);
  }
  return output;
}
