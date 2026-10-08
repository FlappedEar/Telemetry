// The physical unit of every speed analysis reads.
//
// A recording's parser keeps channel units exactly as the file declares
// them, so its source fingerprint matches what FlappedEar Overlays stores
// (`telemetry-v1`). A VBO, though, declares its speed unit only on a
// `[header]` line ("velocity kmh"), which the parser keeps as metadata, and
// some recordings declare none. [withEffectiveSpeedUnits] gives analysis one
// session in which every speed channel carries its unit: the one the
// recording declares, else the unit the user assumes for unlabelled speeds,
// else none. Two speeds are compared only in the same unit ([sameSpeedUnit]):
// km/h is never subtracted from mph, and a declared unit never from a speed
// with none. A speed with no unit left (nothing declared, nothing assumed)
// is read as km/h where a physical scale is needed, as Overlays reads it
// ([speedInMetresPerSecond]); the screens show it without a unit.
import 'channel_units.dart';
import 'telemetry_session.dart';

/// "km/h" or "mph" for a speed unit as recordings write it (`kmh`, `km/h`,
/// `kph`, `mph`), else empty.
String normalizedSpeedUnit(String unit) => switch (unit.trim().toLowerCase()) {
  'km/h' || 'kmh' || 'kph' || 'km/hr' => 'km/h',
  'mph' || 'mi/h' => 'mph',
  _ => '',
};

/// Whether a channel called [name] is a speed (`speed`, `velocity`,
/// `velocity-obd`, `velocity-calc`, …).
bool isSpeedChannel(String name) {
  final lower = name.toLowerCase();
  return lower == 'speed' || lower.startsWith('velocity');
}

/// Whether channel [name] of [session] is a speed: named as one or the
/// channel of its `speed` alias.
bool isSessionSpeedChannel(TelemetrySession session, String name) =>
    isSpeedChannel(name) || session.aliases['speed'] == name;

/// The speed unit [session] declares for channel [name]: the channel's own
/// unit (RCZ), else the VBO `[header]` line naming the channel, such as
/// `velocity kmh` (RaceChrono writes units there, which the parser keeps as
/// header metadata). "km/h" and "mph" however written, any other unit as
/// written. Empty when it declares none.
String declaredSpeedUnit(TelemetrySession session, String name) =>
    _declared(declaredChannelUnit(session, name));

// "km/h" or "mph" for those units however written; another unit (say
// "m/s") as written, never dropped.
String _declared(String unit) {
  final known = normalizedSpeedUnit(unit);
  return known.isNotEmpty ? known : unit.trim();
}

/// The metadata key [withEffectiveSpeedUnits] sets for a speed channel it
/// gave an assumed unit (`speedUnitAssumed.<channel>` holds the unit), so
/// that analysis can tell a unit the file declares from one the user assumed.
const String assumedSpeedUnitKeyPrefix = 'speedUnitAssumed.';

/// The speed unit the recording itself declares for channel [name] of
/// [session]: empty when it declares none, even when [withEffectiveSpeedUnits]
/// gave the channel an assumed one.
String fileDeclaredSpeedUnit(TelemetrySession session, String name) =>
    session.metadata.containsKey('$assumedSpeedUnitKeyPrefix$name')
    ? ''
    : declaredSpeedUnit(session, name);

/// The unit analysis reads channel [name] of [session] in: for a speed,
/// the unit the recording declares, else [assumed] (the unit the user
/// assumes for unlabelled speeds, "km/h", "mph" or empty); every other
/// channel its own unit.
String effectiveChannelUnit(TelemetrySession session, String name, {String assumed = ''}) {
  final channel = session.channels[name];
  if (channel == null) return '';
  if (!isSessionSpeedChannel(session, name)) return channel.unit;
  final declared = declaredSpeedUnit(session, name);
  if (declared.isNotEmpty) return declared;
  return normalizedSpeedUnit(assumed);
}

/// [session] with every speed channel carrying [effectiveChannelUnit]:
/// what analysis reads. The same session when nothing changes; samples are
/// shared, never copied or converted.
TelemetrySession withEffectiveSpeedUnits(TelemetrySession session, {String assumed = ''}) {
  Map<String, TelemetryChannel>? changed;
  Map<String, String>? marked;
  for (final MapEntry(key: name, value: channel) in session.channels.entries) {
    if (!isSessionSpeedChannel(session, name)) continue;
    final unit = effectiveChannelUnit(session, name, assumed: assumed);
    if (unit.isNotEmpty && declaredSpeedUnit(session, name).isEmpty) {
      (marked ??= Map.of(session.metadata))['$assumedSpeedUnitKeyPrefix$name'] = unit;
    }
    if (unit == channel.unit) continue;
    (changed ??= Map.of(session.channels))[name] = TelemetryChannel(
      name: channel.name,
      unit: unit,
      timestamps: channel.timestamps,
      values: channel.values,
    );
  }
  if (changed == null) return session;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: marked ?? session.metadata,
    channels: changed,
    aliases: session.aliases,
    warnings: session.warnings,
    timingGates: session.timingGates,
    sampleCount: session.sampleCount,
  );
}

/// Metres per second in one [unit] of speed; null for a unit not known.
/// No unit at all is km/h, as Overlays reads an unlabelled speed: in a day
/// it is left only when no recording declares a unit and none is assumed.
double? metresPerSecondPerSpeedUnit(String unit) => switch (unit.trim().toLowerCase()) {
  '' || 'km/h' || 'kmh' || 'kph' || 'km/hr' => 1 / 3.6,
  'mph' || 'mi/h' => 0.44704,
  'm/s' => 1.0,
  'kn' || 'kt' || 'knots' => 0.514444,
  _ => null,
};

/// [value] in [unit] as metres per second; null when [value] is null or
/// the unit is unknown (see [metresPerSecondPerSpeedUnit]).
double? speedInMetresPerSecond(double? value, String unit) {
  final factor = metresPerSecondPerSpeedUnit(unit);
  return value == null || factor == null ? null : value * factor;
}

/// Whether speeds in [a] and [b] can be subtracted as they are: the same
/// unit however it is written ("kmh", "km/h"), or both without one. A
/// declared unit and no unit differ: the unlabelled one may be either.
bool sameSpeedUnit(String a, String b) {
  final x = a.trim(), y = b.trim();
  if (x.isEmpty || y.isEmpty) return x.isEmpty && y.isEmpty;
  final known = normalizedSpeedUnit(x);
  return known.isNotEmpty ? known == normalizedSpeedUnit(y) : x.toLowerCase() == y.toLowerCase();
}
