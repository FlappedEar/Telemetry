import 'dart:typed_data';

import '../operation.dart';
import 'vbo_limits.dart';
import 'vbo_text.dart';

/// The cells of one row, plus how many fields the row had in total.
final class ScannedRow {
  ScannedRow(this.cells, this.count);

  /// At most `retainedColumns` cells; fields beyond that are counted only.
  final List<String> cells;
  final int count;
}

/// Splits a row into fields.
///
/// A row that contains a comma is comma-separated and each field is trimmed;
/// otherwise runs of ASCII white space separate fields. Several [lines] are
/// read as one row joined by spaces (a column-names section may wrap).
/// With [columnNames], more than [retainedColumns] fields is an error.
ScannedRow scanRow(
  List<String> lines,
  int retainedColumns,
  bool columnNames,
  CancellationCheck? cancelled,
) {
  var commaSeparated = false;
  _visitRow(lines, cancelled, (unit) {
    commaSeparated = unit == 0x2c;
    return !commaSeparated;
  });

  final cells = <String>[];
  var count = 0;
  final field = StringBuffer();
  var length = 0;
  var trimmedLength = 0;

  void tooManyColumns() => throw const ResourceLimitError('VBO contains too many columns.');

  void finishField() {
    if (!commaSeparated && length == 0) return;
    if (columnNames && count >= retainedColumns) tooManyColumns();
    if (count < retainedColumns) {
      final text = field.toString();
      cells.add(trimmedLength < text.length ? text.substring(0, trimmedLength) : text);
      field.clear();
    }
    ++count;
    length = trimmedLength = 0;
  }

  _visitRow(lines, cancelled, (unit) {
    final separator = commaSeparated ? unit == 0x2c : isAsciiSpace(unit);
    if (separator) {
      finishField();
      return true;
    }
    if (columnNames && count >= retainedColumns) tooManyColumns();
    final space = isUnicodeSpace(unit);
    // Comma fields drop leading white space; trailing white space is counted
    // but kept out of the field unless more text follows it.
    if (commaSeparated && length == 0 && space) return true;
    ++length;
    if (!commaSeparated || !space) {
      trimmedLength = length;
      if (trimmedLength > VboLimits.maximumFieldCharacters) {
        throw const ResourceLimitError(
          'VBO contains a field longer than the supported 64 KiB limit.',
        );
      }
    }
    if (count < retainedColumns && length <= VboLimits.maximumFieldCharacters) {
      field.writeCharCode(unit);
    }
    return true;
  });
  finishField();
  return ScannedRow(cells, count);
}

/// Calls [visit] for every UTF-16 unit of [lines], with a space between lines,
/// until it returns false. Polls [cancelled] every 4,096 units.
void _visitRow(List<String> lines, CancellationCheck? cancelled, bool Function(int unit) visit) {
  var visited = 0;
  for (var index = 0; index < lines.length; ++index) {
    if (index > 0 && !visit(0x20)) return;
    final line = lines[index];
    for (var position = 0; position < line.length; ++position) {
      if ((visited++ & 0xfff) == 0) throwIfCancelled(cancelled);
      if (!visit(line.codeUnitAt(position))) return;
    }
  }
}

/// Where each retained field of one data row starts and ends, as [scanRow]
/// would split it, without creating the field strings.
final class RowBounds {
  RowBounds(int retainedColumns)
    : starts = Int32List(retainedColumns),
      ends = Int32List(retainedColumns);

  /// Field `i` is `line.substring(starts[i], ends[i])` for `i < retained`.
  final Int32List starts;
  final Int32List ends;

  /// Fields kept: at most the number of retained columns.
  int retained = 0;

  /// Fields in the row, including those beyond the retained columns.
  int count = 0;

  /// Whether a field beyond the retained columns holds anything: trailing
  /// separators leave empty extra fields, which are harmless (FET-271).
  bool hasExtraValue = false;

  /// Splits [line] as `scanRow([line], retainedColumns, false, cancelled)`
  /// does: the same fields, the same trimming and the same field-length
  /// error.
  void scan(String line, CancellationCheck? cancelled) {
    final capacity = starts.length;
    retained = count = 0;
    hasExtraValue = false;
    final length = line.length;
    var commaSeparated = false;
    for (var position = 0; position < length; ++position) {
      if (line.codeUnitAt(position) == 0x2c) {
        commaSeparated = true;
        break;
      }
    }
    void field(int start, int end) {
      if (end - start > VboLimits.maximumFieldCharacters) {
        throw const ResourceLimitError(
          'VBO contains a field longer than the supported 64 KiB limit.',
        );
      }
      if (count < capacity) {
        starts[count] = start;
        ends[count] = end;
        retained = count + 1;
      } else if (end > start) {
        hasExtraValue = true;
      }
      ++count;
    }

    if (!commaSeparated) {
      // Runs of ASCII white space separate fields; there are no empty fields.
      var position = 0;
      while (position < length) {
        if ((position & 0xfff) == 0) throwIfCancelled(cancelled);
        if (isAsciiSpace(line.codeUnitAt(position))) {
          ++position;
          continue;
        }
        final start = position;
        while (position < length && !isAsciiSpace(line.codeUnitAt(position))) {
          ++position;
        }
        field(start, position);
      }
      return;
    }
    // Every comma ends a field, empty ones included; fields lose leading and
    // trailing white space.
    var start = 0;
    for (var position = 0; position <= length; ++position) {
      if ((position & 0xfff) == 0) throwIfCancelled(cancelled);
      if (position < length && line.codeUnitAt(position) != 0x2c) continue;
      var first = start, last = position;
      while (first < last && isUnicodeSpace(line.codeUnitAt(first))) {
        ++first;
      }
      while (last > first && isUnicodeSpace(line.codeUnitAt(last - 1))) {
        --last;
      }
      field(first, last);
      start = position + 1;
    }
  }
}
