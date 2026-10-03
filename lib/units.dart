import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// Which speed unit is written next to speeds. Only the label changes:
/// values are always shown as recorded, never converted.
enum SpeedUnitSetting {
  automatic('Automatic'),
  kilometresPerHour('km/h'),
  milesPerHour('mph');

  const SpeedUnitSetting(this.label);

  final String label;
}

/// The speed unit label chosen in settings, shared while the app runs and
/// kept in `settings.json` in the app's support folder.
final ValueNotifier<SpeedUnitSetting> speedUnitSetting = ValueNotifier(
  SpeedUnitSetting.automatic,
);

/// The speed unit detected from the open day's recordings ("km/h", "mph"),
/// or empty when they do not say or disagree. Set when a day opens.
String detectedSpeedUnit = '';

/// "km/h" or "mph" for a unit as recordings write it (`kmh`, `km/h`, `kph`,
/// `mph`), else empty.
String normalizedSpeedUnit(String unit) => switch (unit.trim().toLowerCase()) {
  'km/h' || 'kmh' || 'kph' || 'km/hr' => 'km/h',
  'mph' || 'mi/h' => 'mph',
  _ => '',
};

/// The speed unit [session] declares for its speed channel: the channel's
/// own unit (RCZ), else the VBO `[header]` line naming the channel, such as
/// `velocity kmh` (RaceChrono writes units there, which the parser keeps as
/// header metadata). Empty when it declares none.
String sessionSpeedUnit(TelemetrySession session) {
  final name = session.aliases['speed'] ?? 'speed';
  final own = normalizedSpeedUnit(session.channels[name]?.unit ?? '');
  if (own.isNotEmpty) return own;
  for (final MapEntry(:key, :value) in session.metadata.entries) {
    if (!key.startsWith('header.')) continue;
    final words = value.trim().split(RegExp(r'\s+'));
    if (words.length == 2 && words.first.toLowerCase() == name.toLowerCase()) {
      return normalizedSpeedUnit(words.last);
    }
  }
  return '';
}

/// The unit all of [sessions] declare, or empty when any declares none or
/// they disagree.
String commonSpeedUnit(Iterable<TelemetrySession> sessions) {
  String? common;
  for (final session in sessions) {
    final unit = sessionSpeedUnit(session);
    if (unit.isEmpty || (common != null && common != unit)) return '';
    common = unit;
  }
  return common ?? '';
}

/// The label written next to a speed whose channel declares [recorded]:
/// the unit chosen in settings, else the recorded unit, else the one
/// detected from the day's recordings. Empty when nothing says.
String speedUnitLabel([String recorded = '']) =>
    switch (speedUnitSetting.value) {
      SpeedUnitSetting.kilometresPerHour => 'km/h',
      SpeedUnitSetting.milesPerHour => 'mph',
      SpeedUnitSetting.automatic =>
        recorded.trim().isNotEmpty
            ? (normalizedSpeedUnit(recorded).isEmpty
                  ? recorded.trim()
                  : normalizedSpeedUnit(recorded))
            : detectedSpeedUnit,
    };

/// Whether a channel called [name] is a speed (`speed`, `velocity`,
/// `velocity-obd`, `velocity-calc`, …).
bool isSpeedChannel(String name) {
  final lower = name.toLowerCase();
  return lower == 'speed' || lower.startsWith('velocity');
}

/// The unit shown for channel [name] recorded with [unit]: speed channels
/// get [speedUnitLabel], every other channel its recorded unit.
String displayUnit(String name, String unit) =>
    isSpeedChannel(name) ? speedUnitLabel(unit) : unit;

/// Reads and keeps [speedUnitSetting] in `settings.json` in the app's
/// support folder. Off in `flutter test`.
Future<void> loadSettings() async {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return;
  final File file;
  try {
    file = File(
      p.join((await getApplicationSupportDirectory()).path, 'settings.json'),
    );
  } on Exception {
    return;
  }
  try {
    if (file.existsSync() && file.lengthSync() < 64 * 1024) {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map && json['speedUnit'] is String) {
        for (final value in SpeedUnitSetting.values) {
          if (value.name == json['speedUnit']) speedUnitSetting.value = value;
        }
      }
    }
  } on Exception catch (error) {
    debugPrint('Settings not read: $error');
  }
  speedUnitSetting.addListener(() async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'speedUnit': speedUnitSetting.value.name}),
      );
    } on Exception catch (error) {
      debugPrint('Settings not saved: $error');
    }
  });
}

/// Rebuilds what shows a speed unit when [speedUnitSetting] changes; put
/// above the app's navigator.
class SpeedUnitScope
    extends InheritedNotifier<ValueNotifier<SpeedUnitSetting>> {
  SpeedUnitScope({super.key, required super.child})
    : super(notifier: speedUnitSetting);
}

/// [speedUnitLabel], rebuilding [context] when the setting changes.
String speedUnitOf(BuildContext context, [String recorded = '']) {
  context.dependOnInheritedWidgetOfExactType<SpeedUnitScope>();
  return speedUnitLabel(recorded);
}

/// [displayUnit], rebuilding [context] when the setting changes.
String displayUnitOf(BuildContext context, String name, String unit) {
  context.dependOnInheritedWidgetOfExactType<SpeedUnitScope>();
  return displayUnit(name, unit);
}
