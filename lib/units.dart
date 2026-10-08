import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'channel_names.dart';
import 'day/day_context.dart';
import 'ui/theme.dart';

/// The unit assumed for speeds whose recordings do not declare one. A unit a
/// recording declares is always shown as declared and never overridden;
/// values are never converted. The names stay as stored in `settings.json`.
enum SpeedUnitSetting {
  automatic('None'),
  kilometresPerHour('km/h'),
  milesPerHour('mph');

  const SpeedUnitSetting(this.label);

  final String label;

  /// The assumed unit ("km/h", "mph"), or empty when none is assumed.
  String get unit => switch (this) {
    SpeedUnitSetting.automatic => '',
    SpeedUnitSetting.kilometresPerHour => 'km/h',
    SpeedUnitSetting.milesPerHour => 'mph',
  };
}

/// The unit assumed for unlabelled speeds, chosen in settings, shared while
/// the app runs and kept in `settings.json` in the app's support folder.
final ValueNotifier<SpeedUnitSetting> speedUnitSetting = ValueNotifier(
  SpeedUnitSetting.automatic,
);

/// Whether the weather of sessions is looked up (the session's rounded
/// position and date are sent to the weather service), chosen in settings
/// and kept in `settings.json` with [speedUnitSetting]. On by default.
final ValueNotifier<bool> weatherLookupSetting = ValueNotifier(true);

/// Whether the lap list hides the laps that are not ranked (out and in
/// laps, sections without a start/finish pass, excluded laps and laps with
/// an issue), chosen with the list's
/// show and hide button and kept in `settings.json`. On by default. Only
/// the list changes: the day and its recordings keep every lap.
final ValueNotifier<bool> hideUnrankedLapsSetting = ValueNotifier(true);

/// Whether the app looks for a newer release on GitHub when it starts (at
/// most once a day), chosen in settings and kept in `settings.json`. On by
/// default; "Check for updates" in settings works either way.
final ValueNotifier<bool> updateCheckSetting = ValueNotifier(true);

/// How the app looks (dark, or sunlight for reading outdoors), chosen in
/// settings and kept in `settings.json`. Dark by default.
final ValueNotifier<AppLook> appLookSetting = ValueNotifier(AppLook.dark);

/// Whether the screen stays on while the Coach place is shown, chosen in
/// settings and kept in `settings.json`. On by default.
final ValueNotifier<bool> keepScreenOnSetting = ValueNotifier(true);

/// When the app last looked for a newer release on its own; kept in
/// `settings.json` so the check on launch runs at most once a day.
final ValueNotifier<DateTime?> lastUpdateCheck = ValueNotifier(null);

/// When the circuit list was last fetched; null before the first time.
final ValueNotifier<DateTime?> lastCircuitCheck = ValueNotifier(null);

/// The speed unit [session] declares for its speed channel (see
/// [declaredSpeedUnit]).
String sessionSpeedUnit(TelemetrySession session) =>
    declaredSpeedUnit(session, session.aliases['speed'] ?? 'speed');

/// The unit of the open day's speeds: each recording's declared unit, with
/// [assumed] standing in for the recordings that declare none. Empty when
/// that leaves any recording without a unit or the recordings disagree, so
/// a declared unit is never replaced by another label.
String daySpeedUnit(List<String> declared, String assumed) {
  String? common;
  for (final unit in declared) {
    final own = unit.isEmpty ? assumed : unit;
    if (own.isEmpty || (common != null && common != own)) return '';
    common = own;
  }
  return common ?? '';
}

/// The label written next to a speed whose channel declares [recorded]: the
/// recorded unit when there is one, never overridden; else the open day's
/// speed unit ([daySpeedUnit] with the assumption chosen in settings).
/// Empty when nothing says.
String speedUnitLabel([String recorded = '']) {
  final own = recorded.trim();
  if (own.isNotEmpty) {
    final normalized = normalizedSpeedUnit(own);
    return normalized.isEmpty ? own : normalized;
  }
  return daySpeedUnit(openDayContext.speedUnits, speedUnitSetting.value.unit);
}

/// The unit shown for channel [name] recorded with [unit]: a speed channel
/// gets its recorded unit, else the unit the day's recordings declare for
/// that channel, with the setting's assumption only for recordings that
/// declare none (see [daySpeedUnit]); every other channel its recorded unit.
String displayUnit(String name, String unit) {
  if (!isSpeedChannel(name)) return unit;
  final declared = openDayContext.channelSpeedUnits[name.toLowerCase()];
  if (unit.trim().isNotEmpty || declared == null) return speedUnitLabel(unit);
  return daySpeedUnit(declared, speedUnitSetting.value.unit);
}

/// Reads and keeps [speedUnitSetting], [weatherLookupSetting],
/// [hideUnrankedLapsSetting], [updateCheckSetting], [lastUpdateCheck],
/// [lastCircuitCheck],
/// [appLookSetting], [keepScreenOnSetting], [channelNamesSetting] and [listedChannelsSetting] in
/// `settings.json` in the app's support folder. Off in `flutter test`.
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
      if (json is Map && json['weatherLookup'] is bool) {
        weatherLookupSetting.value = json['weatherLookup'] as bool;
      }
      if (json is Map && json['updateCheck'] is bool) {
        updateCheckSetting.value = json['updateCheck'] as bool;
      }
      if (json is Map && json['lastUpdateCheck'] is String) {
        lastUpdateCheck.value = DateTime.tryParse(
          json['lastUpdateCheck'] as String,
        );
      }
      if (json is Map && json['lastCircuitCheck'] is String) {
        lastCircuitCheck.value = DateTime.tryParse(
          json['lastCircuitCheck'] as String,
        );
      }
      if (json is Map && json['look'] is String) {
        for (final value in AppLook.values) {
          if (value.name == json['look']) appLookSetting.value = value;
        }
      }
      if (json is Map && json['keepScreenOn'] is bool) {
        keepScreenOnSetting.value = json['keepScreenOn'] as bool;
      }
      if (json is Map && json['hideUnrankedLaps'] is bool) {
        hideUnrankedLapsSetting.value = json['hideUnrankedLaps'] as bool;
      }
      if (json is Map) {
        listedChannelsSetting.value = readListedChannels(
          json['listedChannels'],
        );
        channelNamesSetting.value = readChannelNames(json['channelNames']);
      }
    }
  } on Exception catch (error) {
    debugPrint('Settings not read: $error');
  }
  // One write at a time, after typing settles, into a temporary file moved
  // over settings.json: a write cut short never leaves half a file.
  Timer? pending;
  var writing = Future<void>.value();
  Future<void> save() async {
    final text = jsonEncode({
      'speedUnit': speedUnitSetting.value.name,
      'weatherLookup': weatherLookupSetting.value,
      'hideUnrankedLaps': hideUnrankedLapsSetting.value,
      'updateCheck': updateCheckSetting.value,
      'look': appLookSetting.value.name,
      'keepScreenOn': keepScreenOnSetting.value,
      if (lastUpdateCheck.value case final checked?)
        'lastUpdateCheck': checked.toUtc().toIso8601String(),
      if (lastCircuitCheck.value case final checked?)
        'lastCircuitCheck': checked.toUtc().toIso8601String(),
      'channelNames': channelNamesSetting.value,
      'listedChannels': listedChannelsSetting.value,
    });
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
    } on Object catch (error) {
      // Any failure, so the next write still runs.
      debugPrint('Settings not saved: $error');
    }
  }

  void flush() {
    pending?.cancel();
    pending = null;
    writing = writing.then((_) => save());
  }

  void write() {
    pending?.cancel();
    pending = Timer(const Duration(milliseconds: 400), flush);
  }

  // A change still waiting is written when the app leaves the screen.
  AppLifecycleListener(
    onPause: () {
      if (pending != null) flush();
    },
    onDetach: () {
      if (pending != null) flush();
    },
  );

  speedUnitSetting.addListener(write);
  weatherLookupSetting.addListener(write);
  hideUnrankedLapsSetting.addListener(write);
  updateCheckSetting.addListener(write);
  lastUpdateCheck.addListener(write);
  lastCircuitCheck.addListener(write);
  appLookSetting.addListener(write);
  keepScreenOnSetting.addListener(write);
  channelNamesSetting.addListener(write);
  listedChannelsSetting.addListener(write);
}

/// Rebuilds what shows a speed unit when [speedUnitSetting] changes; put
/// above the app's navigator. (A day's own units are read as it builds:
/// [openDayContext] changes while pages close, when nothing may rebuild.)
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
