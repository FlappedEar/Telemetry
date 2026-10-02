import 'package:telemetry_core/telemetry_core.dart';

/// A time as the app shows it: "28.662 s" below a minute, "1:49.898" from one
/// minute, "—" when there is no finite value. Rounded before minutes are
/// split.
String displayTime(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '—';
  final milliseconds = (seconds * 1000).round();
  if (milliseconds < 60000) {
    return '${(milliseconds / 1000).toStringAsFixed(3)} s';
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
  return '$sign${(milliseconds.abs() / 1000).toStringAsFixed(3)} s';
}
