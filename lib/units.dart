import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'channel_names.dart';

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

/// The speed unit each of the open day's recordings declares ("km/h",
/// "mph", or empty when it declares none). Set when a day opens.
List<String> declaredSpeedUnits = const [];

/// The speed unit [session] declares for its speed channel (see
/// [declaredSpeedUnit]).
String sessionSpeedUnit(TelemetrySession session) =>
    declaredSpeedUnit(session, session.aliases['speed'] ?? 'speed');

/// The speed units the open day's recordings declare per speed channel,
/// keyed by lower-case channel name: one entry per recording that has the
/// channel. Set when a day opens.
Map<String, List<String>> declaredChannelSpeedUnits = const {};

/// Sets [declaredSpeedUnits] and [declaredChannelSpeedUnits] for a day of
/// [sessions]; an empty list when no day is open.
void declareDaySpeedUnits(Iterable<TelemetrySession> sessions) {
  final byChannel = <String, List<String>>{};
  final day = <String>[];
  for (final session in sessions) {
    day.add(sessionSpeedUnit(session));
    final alias = session.aliases['speed'];
    for (final name in session.channels.keys) {
      if (!isSpeedChannel(name) && name != alias) continue;
      byChannel
          .putIfAbsent(name.toLowerCase(), () => [])
          .add(declaredSpeedUnit(session, name));
    }
  }
  declaredSpeedUnits = List.unmodifiable(day);
  declaredChannelSpeedUnits = Map.unmodifiable(byChannel);
}

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
  return daySpeedUnit(declaredSpeedUnits, speedUnitSetting.value.unit);
}

/// The unit shown for channel [name] recorded with [unit]: a speed channel
/// gets its recorded unit, else the unit the day's recordings declare for
/// that channel, with the setting's assumption only for recordings that
/// declare none (see [daySpeedUnit]); every other channel its recorded unit.
String displayUnit(String name, String unit) {
  if (!isSpeedChannel(name)) return unit;
  final declared = declaredChannelSpeedUnits[name.toLowerCase()];
  if (unit.trim().isNotEmpty || declared == null) return speedUnitLabel(unit);
  return daySpeedUnit(declared, speedUnitSetting.value.unit);
}

/// Reads and keeps [speedUnitSetting], [weatherLookupSetting],
/// [hideUnrankedLapsSetting], [channelNamesSetting] and
/// [listedChannelsSetting] in
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
  channelNamesSetting.addListener(write);
  listedChannelsSetting.addListener(write);
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
