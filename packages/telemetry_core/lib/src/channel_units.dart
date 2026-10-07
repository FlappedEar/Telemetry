// The unit a recording declares for a channel, whatever the channel is.
import 'telemetry_session.dart';

/// The unit [session] declares for channel [name], as written: the
/// channel's own unit (RCZ, or a VBO column unit), else the VBO `[header]`
/// line naming the channel, such as `latacc-calc g` (RaceChrono writes
/// units there, which the parser keeps as header metadata). Empty when it
/// declares none. Never normalized or relabelled.
String declaredChannelUnit(TelemetrySession session, String name) {
  final own = session.channels[name]?.unit.trim() ?? '';
  if (own.isNotEmpty) return own;
  for (final MapEntry(:key, :value) in session.metadata.entries) {
    if (!key.startsWith('header.')) continue;
    final words = value.trim().split(RegExp(r'\s+'));
    if (words.length == 2 && words.first.toLowerCase() == name.toLowerCase()) {
      return words.last.trim();
    }
  }
  return '';
}
