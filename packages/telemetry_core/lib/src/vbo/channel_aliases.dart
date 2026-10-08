import '../telemetry_session.dart';

RegExp _pattern(String source) => RegExp(source, caseSensitive: false);

/// Semantic names and the column-name patterns that provide them. The first
/// matching column in case-insensitive name order wins unless it covers much
/// less of the recording than another (see [resolveAliases]).
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

/// Finite samples of a column cover the time between them when they are at
/// most three of its own median finite intervals apart, kept within these
/// bounds (FET-207). Counting time, not samples, keeps a slower channel
/// that is complete (an OBD pedal polled below 1 Hz) level with a faster
/// one; a column with a few scattered values covers almost nothing.
const double aliasCoverageMinimumGapSeconds = 1.0;
const double aliasCoverageMaximumGapSeconds = 5.0;

/// A column is passed over for another only when it covers less than this
/// share of the other's time (FET-207). Likewise the accelerator pedal
/// replaces the throttle only when it covers at least this share of the
/// throttle's time.
const double aliasMinimumCoverageShare = 0.5;

/// A varying column outranks constant ones only when it covers at least this
/// share of the best-covered candidate's time, so a few varying seconds do
/// not displace a complete constant column (a brake switch never pressed).
const double aliasVaryingMinimumShare = 0.05;

/// The seconds of [channel] its finite samples cover, and whether its
/// finite values vary.
(double, bool) _coverage(TelemetryChannel? channel) {
  if (channel == null || channel.timestamps.length != channel.values.length) return (0.0, false);
  final times = <double>[];
  double? first;
  var varies = false;
  for (var index = 0; index < channel.values.length; ++index) {
    final double value = channel.values[index];
    if (!value.isFinite) continue;
    times.add(channel.timestamps[index]);
    first ??= value;
    if (value != first) varies = true;
  }
  if (times.length < 2) return (0.0, varies);
  final intervals = [
    for (var index = 1; index < times.length; ++index) times[index] - times[index - 1],
  ]..sort();
  final median = intervals[intervals.length ~/ 2];
  final gap = (3.0 * median).clamp(aliasCoverageMinimumGapSeconds, aliasCoverageMaximumGapSeconds);
  var covered = 0.0;
  for (var index = 1; index < times.length; ++index) {
    final interval = times[index] - times[index - 1];
    if (interval <= gap) covered += interval;
  }
  return (covered, varies);
}

/// Of [candidates] (in priority order), the first unless another covers
/// more than twice its time: then the one covering most (the earliest on a
/// tie). Columns whose values vary come first: a constant column (all
/// zeros, say: RaceChrono writes placeholders) never displaces one that
/// varies, and gives way to any that varies over at least
/// [aliasVaryingMinimumShare] of the best coverage. Without
/// [channels] the first.
String? _bestCandidate(List<String> candidates, Map<String, TelemetryChannel>? channels) {
  if (candidates.isEmpty) return null;
  if (channels == null || candidates.length == 1) return candidates.first;
  final measured = [for (final name in candidates) _coverage(channels[name])];
  var most = 0.0;
  for (final (covered, _) in measured) {
    if (covered > most) most = covered;
  }
  // Varying with data over at least a few percent of the best coverage.
  bool eligible((double, bool) entry) =>
      entry.$2 && entry.$1 > 0.0 && entry.$1 >= aliasVaryingMinimumShare * most;
  final anyVaries = measured.any(eligible);
  var best = -1;
  for (var index = 0; index < measured.length; ++index) {
    final covered = measured[index].$1;
    if (anyVaries && !eligible(measured[index])) continue;
    if (best < 0 || covered > measured[best].$1) best = index;
  }
  if (best == 0) return candidates.first;
  final firstCovered = measured.first.$1;
  final firstEligible = !anyVaries || eligible(measured.first);
  return firstEligible && firstCovered >= aliasMinimumCoverageShare * measured[best].$1
      ? candidates.first
      : candidates[best];
}

/// Maps semantic names to columns. [names] must be in [sortedChannelNames]
/// order. With [channels], a column that matches first but covers little of
/// the recording gives way to a matching one with data (FET-207; Overlays takes the first
/// match by name: departure KAN-230): an alphabetical winner that is 95 %
/// NaN must not hide a full channel.
Map<String, String> resolveAliases(List<String> names, {Map<String, TelemetryChannel>? channels}) {
  final aliases = <String, String>{};
  for (final (alias, patterns) in _aliasPatterns) {
    final candidates = <String>[];
    final calculated = _calculatedAcceleration[alias];
    if (calculated != null) {
      candidates.addAll(names.where((name) => name.toLowerCase() == calculated).take(1));
    }
    for (final name in names) {
      if (!candidates.contains(name) && patterns.any((pattern) => pattern.hasMatch(name))) {
        candidates.add(name);
      }
    }
    final chosen = _bestCandidate(candidates, channels);
    if (chosen != null) aliases[alias] = chosen;
  }
  return aliases;
}

final RegExp _acceleratorPedal = _pattern(r'^accelerator.?(?:pedal|pos)');

/// Points `throttle` at the driver's accelerator pedal when the recording has a
/// pedal channel with data covering at least [aliasMinimumCoverageShare] of
/// the time the channel `throttle` names now covers (FET-207: a pedal with
/// one valid sample must not replace a full throttle; one logged slower but
/// throughout still does). The throttle-plate channel stays available under
/// its own name.
void preferAcceleratorPedalForThrottle(
  Map<String, String> aliases,
  Map<String, TelemetryChannel> channels,
) {
  final current = _coverage(channels[aliases['throttle'] ?? '']).$1;
  for (final name in sortedChannelNames(channels.keys)) {
    if (!_acceleratorPedal.hasMatch(name)) continue;
    final channel = channels[name]!;
    if (channel.values.any((value) => value.isFinite) &&
        _coverage(channel).$1 >= aliasMinimumCoverageShare * current) {
      aliases['throttle'] = name;
      return;
    }
  }
}
