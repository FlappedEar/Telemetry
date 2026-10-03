import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// [value] with [digits] decimals: "12.5". Every language, Polish included,
/// uses a decimal point (the owner's choice, 2026-10-03), and there is no
/// grouping, so digits stay aligned.
String fixed(double value, int digits) => value.toStringAsFixed(digits);

/// A time as the app shows it: "28.662 s" below a minute, "1:49.898" from one
/// minute, "—" when there is no finite value. Rounded before minutes are
/// split.
String displayTime(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '—';
  final milliseconds = (seconds * 1000).round();
  if (milliseconds < 60000) {
    return '${fixed(milliseconds / 1000, 3)} s';
  }
  return formatLapTime(milliseconds / 1000, 3) ?? '—';
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

/// A local date and time in the app's language: "Oct 3, 2026, 06:30" in
/// English, "3 paź 2026, 06:30" in Polish.
String displayDateTime(DateTime time) {
  final local = time.toLocal();
  return '${DateFormat.yMMMd().format(local)}, ${DateFormat.Hm().format(local)}';
}
