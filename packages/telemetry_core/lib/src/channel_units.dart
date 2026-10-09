// The unit a recording declares for a channel, and how analysis reads
// quantities in it.
//
// The parser keeps units exactly as the file writes them (they are part of
// the source fingerprint), and a VBO writes most of them only on a `[header]`
// line, so a parsed channel's own `unit` is often empty. Analysis therefore
// never reads `TelemetryChannel.unit` for meaning: it asks this file.
// [declaredChannelUnit] is the one place a declaration is recovered (a speed
// goes through `effectiveChannelUnit` in speed_units.dart, which adds the
// unit the user assumes for unlabelled speeds). Stored data is never
// converted or relabelled; a calculation converts the quantity it reads:
//  - acceleration: [accelerationGPerUnit], [accelerationInG];
//  - temperature: [TemperatureUnit], [temperatureUnitOf].
// A declared unit a calculation cannot read is reported as unsupported with
// an explicit reason, never read as the default unit.
import 'dart:typed_data';

import 'telemetry_session.dart';

/// Standard gravity in m/s²: one g.
const double standardGravity = 9.80665;

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
    if (words.length >= 2 && words.first.toLowerCase() == name.toLowerCase()) {
      return words.skip(1).join(' ');
    }
  }
  return '';
}

String _unitKey(String unit) => unit.trim().toLowerCase().replaceAll(' ', '');

/// Gravities in one [unit] of acceleration: "g" and no unit at all (loggers
/// record g, often unlabelled, and the result says it was assumed) are g,
/// "m/s2", "m/s^2" and "m/s²" are metres per second squared. Null for a unit
/// not known.
double? accelerationGPerUnit(String unit) => switch (_unitKey(unit)) {
  '' || 'g' => 1.0,
  'm/s2' || 'm/s^2' || 'm/s²' => 1.0 / standardGravity,
  _ => null,
};

/// An acceleration channel as a calculation reads it: in g.
final class AccelerationInG {
  const AccelerationInG({
    required this.channel,
    required this.declaredUnit,
    required this.supported,
  });

  /// The samples in g, with unit "g", when the recording declares a unit
  /// that is known; the channel as recorded when it declares none (it is
  /// read as g and [declared] is false) or declares one not [supported].
  final TelemetryChannel channel;

  /// The unit the recording declares, as written; empty when it declares none.
  final String declaredUnit;

  /// Whether the declared unit is one a calculation can read as g.
  final bool supported;

  bool get declared => declaredUnit.isNotEmpty;

  /// The unit [channel]'s samples are in: the declared spelling of g as
  /// written, "g" for a unit converted to it, empty when none is declared
  /// (the samples are read as g all the same).
  String get unit => !declared || !supported
      ? declaredUnit
      : accelerationGPerUnit(declaredUnit) == 1.0
      ? declaredUnit
      : 'g';
}

final _accelerationViews = Expando<Map<String, TelemetryChannel>>('acceleration in g');

/// Channel [name] of [session] as an acceleration in g: its declared unit
/// recovered from the header when the channel carries none, and its samples
/// converted when that unit is m/s². Null when the session has no such
/// channel. Built once per channel and unit; the recorded samples are not
/// touched.
AccelerationInG? accelerationInG(TelemetrySession session, String name) {
  final found = session.channels[name];
  if (found == null) return null;
  final unit = declaredChannelUnit(session, name);
  final factor = accelerationGPerUnit(unit);
  if (factor == null) {
    return AccelerationInG(channel: found, declaredUnit: unit, supported: false);
  }
  if (unit.isEmpty) {
    return AccelerationInG(channel: found, declaredUnit: unit, supported: true);
  }
  final key = _unitKey(unit);
  final converted = (_accelerationViews[found] ??= {})[key] ??= factor == 1.0 && found.unit == 'g'
      ? found
      : TelemetryChannel(
          name: found.name,
          unit: 'g',
          timestamps: found.timestamps,
          values: factor == 1.0 ? found.values : _scaled(found.values, factor),
        );
  return AccelerationInG(channel: converted, declaredUnit: unit, supported: true);
}

/// [accelerationInG] of the channel the alias [alias] (for example
/// `longitudinalAcceleration`) names; null when it names none.
AccelerationInG? accelerationAliasInG(TelemetrySession session, String alias) {
  final name = session.aliases[alias] ?? '';
  return name.isEmpty ? null : accelerationInG(session, name);
}

Float32List _scaled(Float32List values, double factor) {
  final result = Float32List(values.length);
  for (var index = 0; index < values.length; ++index) {
    result[index] = values[index] * factor;
  }
  return adoptChannelValues(result);
}

/// A unit a temperature is recorded in.
enum TemperatureUnit {
  celsius,
  fahrenheit,
  kelvin;

  /// [celsius] degrees Celsius in this unit.
  double fromCelsius(double celsius) => switch (this) {
    TemperatureUnit.celsius => celsius,
    TemperatureUnit.fahrenheit => celsius * 1.8 + 32.0,
    TemperatureUnit.kelvin => celsius + 273.15,
  };

  /// [value] in this unit as degrees Celsius.
  double toCelsius(double value) => switch (this) {
    TemperatureUnit.celsius => value,
    TemperatureUnit.fahrenheit => (value - 32.0) / 1.8,
    TemperatureUnit.kelvin => value - 273.15,
  };

  /// A difference of [celsius] degrees Celsius in this unit's degrees (a
  /// rise or a drop: no offset).
  double differenceFromCelsius(double celsius) => switch (this) {
    TemperatureUnit.fahrenheit => celsius * 1.8,
    _ => celsius,
  };
}

/// The temperature unit a recording's [declared] unit names ("°C", "C",
/// "degC", "°F", "F", "degF", "K", in any case and spacing; none at all is
/// °C, as OBD temperatures are); null for a unit not known.
TemperatureUnit? temperatureUnitOf(String declared) =>
    switch (_unitKey(declared).replaceAll('°', '').replaceAll('º', '').replaceAll('deg.', 'deg')) {
      '' || 'c' || 'degc' || 'celsius' => TemperatureUnit.celsius,
      'f' || 'degf' || 'fahrenheit' => TemperatureUnit.fahrenheit,
      'k' || 'kelvin' => TemperatureUnit.kelvin,
      _ => null,
    };
