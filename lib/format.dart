import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

String? _separatorLocale;
String _separator = '.';

/// The decimal separator of the app's language: "." in English, "," in
/// Polish.
String get decimalSeparator {
  final locale = Intl.getCurrentLocale();
  if (locale != _separatorLocale) {
    _separatorLocale = locale;
    _separator = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
  }
  return _separator;
}

/// [value] with [digits] decimals in the app's language: "12.5" in
/// English, "12,5" in Polish. No grouping, so digits stay aligned.
String fixed(double value, int digits) =>
    value.toStringAsFixed(digits).replaceFirst('.', decimalSeparator);

/// A time as the app shows it: "28.662 s" below a minute, "1:49.898" from one
/// minute, "—" when there is no finite value. Rounded before minutes are
/// split. Polish uses a decimal comma: "1:49,898".
String displayTime(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '—';
  final milliseconds = (seconds * 1000).round();
  if (milliseconds < 60000) {
    return '${fixed(milliseconds / 1000, 3)} s';
  }
  final time = formatLapTime(milliseconds / 1000, 3);
  return time == null ? '—' : time.replaceFirst('.', decimalSeparator);
}

/// A signed difference in seconds: "+0.412 s", "−1.340 s", "—".
String displayDelta(double seconds) {
  if (!seconds.isFinite) return '—';
  final milliseconds = (seconds * 1000).round();
  final sign = milliseconds > 0
      ? '+'
      : milliseconds < 0
      ? '−'
      : '±';
  return '$sign${fixed(milliseconds.abs() / 1000, 3)} s';
}

/// A local date and time in the app's language: "3 Oct 2026, 06:30" in
/// English, "3 paź 2026, 06:30" in Polish.
String displayDateTime(DateTime time) {
  final local = time.toLocal();
  return '${DateFormat.yMMMd().format(local)}, ${DateFormat.Hm().format(local)}';
}
