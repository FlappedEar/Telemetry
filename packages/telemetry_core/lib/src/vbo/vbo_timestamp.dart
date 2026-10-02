import 'vbo_parser_error.dart';
import 'vbo_text.dart';

enum TimestampFormat { relativeSeconds, clock }

final class ParsedTimestamp {
  const ParsedTimestamp(this.seconds, this.format);

  final double seconds;
  final TimestampFormat format;
}

const double _microsecondLimit = 9223372036854775808.0; // 2^63

/// Returns [seconds] when it fits a signed 64-bit count of microseconds
/// (documents fingerprint durations that way); throws otherwise.
double checkedTime(double seconds) {
  final microseconds = seconds * 1000000.0;
  if (!seconds.isFinite ||
      !microseconds.isFinite ||
      microseconds <= -_microsecondLimit ||
      microseconds >= _microsecondLimit) {
    throw const VboParseError(
      'VBO timestamp exceeds the supported signed 64-bit microsecond range.',
    );
  }
  return seconds;
}

final RegExp _colonClock = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2}(?:\.\d+)?)$');
final RegExp _compactCandidate = RegExp(r'^\d{6}(?:\..*)?$');
final RegExp _compactClock = RegExp(r'^(\d{2})(\d{2})(\d{2})(?:\.(\d+))?$');

/// Reads a time cell: `HH:MM:SS[.f]` or six-digit `HHMMSS[.f]` as a clock
/// time, otherwise plain seconds. The clock forms are recognised from the
/// text, so `003059.500` is 00:30:59.5 and not 3,059.5 seconds.
ParsedTimestamp? parseTimestamp(String value) {
  final text = trimSpace(value);
  if (text.contains(':')) {
    final match = _colonClock.firstMatch(text);
    if (match == null) return null;
    final hours = int.parse(match[1]!);
    final minutes = int.parse(match[2]!);
    final seconds = parseDecimal(match[3]!);
    if (seconds == null ||
        !seconds.isFinite ||
        hours >= 24 ||
        minutes >= 60 ||
        seconds < 0.0 ||
        seconds >= 60.0) {
      return null;
    }
    return ParsedTimestamp(hours * 3600.0 + minutes * 60.0 + seconds, TimestampFormat.clock);
  }
  if (_compactCandidate.hasMatch(text)) {
    final match = _compactClock.firstMatch(text);
    if (match == null) return null;
    final hours = int.parse(match[1]!);
    final minutes = int.parse(match[2]!);
    final wholeSeconds = int.parse(match[3]!);
    final fraction = match[4];
    final seconds =
        wholeSeconds +
        (fraction == null || fraction.isEmpty ? 0.0 : (parseDecimal('0.$fraction') ?? 0.0));
    if (!seconds.isFinite || hours >= 24 || minutes >= 60 || seconds >= 60.0) {
      return null;
    }
    return ParsedTimestamp(hours * 3600.0 + minutes * 60.0 + seconds, TimestampFormat.clock);
  }
  final numeric = parseDecimal(text);
  if (numeric == null || !numeric.isFinite) return null;
  return ParsedTimestamp(numeric, TimestampFormat.relativeSeconds);
}
