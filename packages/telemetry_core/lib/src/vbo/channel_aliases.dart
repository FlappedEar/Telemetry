import '../telemetry_session.dart';

RegExp _pattern(String source) => RegExp(source, caseSensitive: false);

/// Semantic names and the column-name patterns that provide them, in priority
/// order. The first matching column in case-insensitive name order wins.
final List<(String, List<RegExp>)> _aliasPatterns = [
  (
    'speed',
    [
      _pattern(r'^velocity$'),
      _pattern(r'^gps.?speed'),
      _pattern(r'^speed$'),
      _pattern(r'^obd.?speed'),
    ],
  ),
  ('rpm', [_pattern(r'^rpm(?:[-_].*)?$'), _pattern(r'engine.?speed')]),
  ('throttle', [_pattern(r'throttle'), _pattern(r'accelerator.?pedal')]),
  (
    'brake',
    [_pattern(r'^brake(?:[-_].*)?$'), _pattern(r'brake.?pressure'), _pattern(r'brake.?pedal')],
  ),
  ('heartRate', [_pattern(r'heart.?rate'), _pattern(r'^hr$'), _pattern(r'^bpm$')]),
  ('latitude', [_pattern(r'^latitude$'), _pattern(r'^lat$')]),
  ('longitude', [_pattern(r'^longitude$'), _pattern(r'^lon(?:g)?$')]),
  (
    'lateralAcceleration',
    [
      _pattern(r'^latacc$'),
      _pattern(r'lat(?:eral)?.?(?:accel|acceleration|g)'),
      _pattern(r'^g.?x$'),
    ],
  ),
  (
    'longitudinalAcceleration',
    [
      _pattern(r'^longacc$'),
      _pattern(r'long(?:itudinal)?.?(?:accel|acceleration|g)'),
      _pattern(r'^g.?y$'),
    ],
  ),
];

/// RaceChrono's generic acceleration columns may hold zero placeholders; its
/// calculated vehicle acceleration is preferred when present.
const Map<String, String> _calculatedAcceleration = {
  'lateralAcceleration': 'latacc-calc',
  'longitudinalAcceleration': 'longacc-calc',
};

/// Maps semantic names to columns. [names] must be in [sortedChannelNames]
/// order.
Map<String, String> resolveAliases(List<String> names) {
  final aliases = <String, String>{};
  for (final (alias, patterns) in _aliasPatterns) {
    final calculated = _calculatedAcceleration[alias];
    if (calculated != null) {
      final found = names.where((name) => name.toLowerCase() == calculated).firstOrNull;
      if (found != null) {
        aliases[alias] = found;
        continue;
      }
    }
    for (final name in names) {
      if (patterns.any((pattern) => pattern.hasMatch(name))) {
        aliases[alias] = name;
        break;
      }
    }
  }
  return aliases;
}

final RegExp _acceleratorPedal = _pattern(r'^accelerator.?(?:pedal|pos)');

/// Points `throttle` at the driver's accelerator pedal when the recording has a
/// pedal channel with data. The throttle-plate channel stays available under
/// its own name.
void preferAcceleratorPedalForThrottle(
  Map<String, String> aliases,
  Map<String, TelemetryChannel> channels,
) {
  for (final name in sortedChannelNames(channels.keys)) {
    if (!_acceleratorPedal.hasMatch(name)) continue;
    if (channels[name]!.values.any((value) => value.isFinite)) {
      aliases['throttle'] = name;
      return;
    }
  }
}
