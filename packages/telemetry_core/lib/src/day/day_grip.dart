// Grip and balance proxies (FET-229): what the recorded accelerations, speed
// and (when there is one) yaw rate say about how hard the car was worked,
// per corner of the day and per session, over the group's ranked laps.
//
// Everything here is inferred. No steering angle, tyre or wheel-speed data is
// recorded, so these are not grip limits and not causes: the highest
// cornering, braking and accelerating force the laps reached, and, only with
// a vehicle yaw-rate channel, how the car's rotation compared with what its
// cornering force and speed need.
//
// Rules: a value keeps the unit its channel declares ("g" or an m/s² unit),
// never relabelled or converted for display; an undeclared acceleration unit
// is read as g and marked assumed; values measured from different channels,
// units or methods are never pooled; laps that are not ranked never reach
// this (the caller passes the group's eligible laps); a figure with too few
// samples or laps is not known, with the reason.
import 'dart:math' as math;

import '../analysis/gg_pairs.dart' show ggPlausibleLimitG, standardGravity;
import '../operation.dart';
import '../speed_units.dart';
import '../telemetry_session.dart';
import 'day_corners.dart';
import 'day_laps.dart';

const String gripProxiesAlgorithm = 'grip-proxies-v1';

/// A typical value (the median of the laps' values) needs at least this many
/// laps, as every typical value of the app does.
const int gripMinimumTypicalLaps = 3;

/// A lap's value through a part of a corner needs at least this many finite
/// samples there.
const int gripMinimumWindowSamples = 5;

/// A lap's value in a speed band of a session needs at least this many
/// finite samples in that band.
const int gripMinimumBandSamples = 20;

/// Balance is read only where the car corners with at least this lateral
/// acceleration (g) …
const double gripBalanceMinimumLateralG = 0.3;

/// … at no less than this speed (m/s): below it the ratio's speed term is
/// too noisy to mean anything.
const double gripBalanceMinimumSpeedMetresPerSecond = 10.0;

/// A lap's balance needs at least this many such samples.
const int gripBalanceMinimumSamples = 10;

/// Acceleration derived from speed is the speed change over this many
/// seconds either side of each speed sample.
const double gripSpeedDerivedHalfSpanSeconds = 0.25;

/// The edges between the low, medium and high speed bands of a session, in
/// the speed channel's own unit: km/h (also for a speed with no unit, which
/// analysis reads as km/h) and mph.
const List<double> gripBandEdgesKilometresPerHour = [80.0, 120.0];
const List<double> gripBandEdgesMilesPerHour = [50.0, 75.0];

/// Why a figure is not known.
const String gripTooFewLaps = 'tooFewLaps';
const String gripTooFewSamples = 'tooFewSamples';
const String gripNoLateralChannel = 'noLateralAcceleration';
const String gripNoSpeedChannel = 'noSpeedChannel';
const String gripUnsupportedUnit = 'unsupportedUnit';
const String gripSpeedUnitNotSupported = 'speedUnitNotSupported';
const String gripNoYawChannel = 'noYawRateChannel';
const String gripDeviceAxesOnly = 'deviceAxesOnly';
const String gripYawUnitUnknown = 'yawUnitUnknown';
const String gripNotTimed = 'notTimed';
const String gripNoMinimumSpeed = 'noMinimumSpeed';
const String gripNoBraking = 'noBraking';
const String gripNoRecording = 'noRecording';

/// Where a value comes from: its channel and unit as declared, or the speed
/// channel (acceleration derived from speed, in g).
final class GripSource {
  const GripSource({
    this.channel = '',
    this.unit = '',
    this.unitAssumed = false,
    this.fromSpeed = false,
  });

  static const GripSource none = GripSource();

  final String channel;

  /// As the recording declares it; "g" for a value derived from speed and
  /// for an undeclared acceleration unit ([unitAssumed]).
  final String unit;

  /// The recording declares no unit, and g is assumed (for a value derived
  /// from speed: the speed has no unit and km/h is assumed, as analysis
  /// reads such a speed).
  final bool unitAssumed;

  /// Derived from the speed channel's change over time.
  final bool fromSpeed;

  bool get isNone => channel.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is GripSource &&
      other.channel == channel &&
      other.unit == unit &&
      other.unitAssumed == unitAssumed &&
      other.fromSpeed == fromSpeed;

  @override
  int get hashCode => Object.hash(channel, unit, unitAssumed, fromSpeed);
}

/// One lap's value, or why it has none.
final class GripLapValue {
  const GripLapValue({
    this.lap,
    this.value,
    this.samples = 0,
    this.source = GripSource.none,
    this.reason = '',
  });

  final DayLapRow? lap;

  /// In [source]'s unit; a ratio for balance.
  final double? value;

  /// Finite samples it was taken from.
  final int samples;
  final GripSource source;

  /// Set when [value] is null.
  final String reason;

  GripLapValue withLap(DayLapRow lap) =>
      GripLapValue(lap: lap, value: value, samples: samples, source: source, reason: reason);
}

/// One figure over the laps: the highest lap value and the typical (median)
/// one, from laps measured the same way.
final class GripFigure {
  const GripFigure({
    this.peak,
    this.peakLap,
    this.typical,
    this.lapCount = 0,
    this.leftOut = 0,
    this.source = GripSource.none,
    this.reason = '',
    this.typicalReason = '',
  });

  /// The highest of the laps' values; null with [reason].
  final double? peak;
  final DayLapRow? peakLap;

  /// The median of the laps' values; null with [typicalReason] (at least
  /// [gripMinimumTypicalLaps] laps are needed).
  final double? typical;

  /// Laps the figure is taken from.
  final int lapCount;

  /// Laps with a value measured differently (another channel, unit or
  /// method), left out rather than pooled.
  final int leftOut;
  final GripSource source;
  final String reason;
  final String typicalReason;

  bool get known => peak != null;
}

/// The median of [values] (not empty).
double _median(List<double> values) {
  final sorted = List.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// [values] over the laps: those measured like [prefer]'s value when it has
/// one, else like the most laps (the earliest on a tie); the rest are left
/// out and counted. Without any value, the reason most laps give.
GripFigure aggregateGripLaps(List<GripLapValue> values, {DayLapReference? prefer}) {
  final measured = [
    for (final value in values)
      if (value.value != null) value,
  ];
  if (measured.isEmpty) {
    final counts = <String, int>{};
    for (final value in values) {
      counts[value.reason] = (counts[value.reason] ?? 0) + 1;
    }
    var reason = gripTooFewLaps;
    var most = 0;
    for (final MapEntry(:key, :value) in counts.entries) {
      if (value > most && key.isNotEmpty) (reason, most) = (key, value);
    }
    return GripFigure(reason: reason, typicalReason: reason);
  }
  GripSource? source;
  for (final value in measured) {
    if (prefer != null && value.lap?.reference == prefer) source = value.source;
  }
  if (source == null) {
    final counts = <GripSource, int>{};
    for (final value in measured) {
      counts[value.source] = (counts[value.source] ?? 0) + 1;
    }
    var most = 0;
    for (final MapEntry(:key, :value) in counts.entries) {
      if (value > most) (source, most) = (key, value);
    }
  }
  final kept = [
    for (final value in measured)
      if (value.source == source) value,
  ];
  var peak = kept.first;
  for (final value in kept) {
    if (value.value! > peak.value!) peak = value;
  }
  final enough = kept.length >= gripMinimumTypicalLaps;
  return GripFigure(
    peak: peak.value,
    peakLap: peak.lap,
    typical: enough ? _median([for (final value in kept) value.value!]) : null,
    lapCount: kept.length,
    leftOut: measured.length - kept.length,
    source: source!,
    typicalReason: enough ? '' : gripTooFewLaps,
  );
}

// Factor from an acceleration unit to g, or null for one not supported.
double? _gPerUnit(String unit) {
  final normalized = unit.trim().toLowerCase().replaceAll(' ', '');
  if (normalized.isEmpty || normalized == 'g') return 1.0;
  if (normalized == 'm/s2' || normalized == 'm/s^2' || normalized == 'm/s²') {
    return 1.0 / standardGravity;
  }
  return null;
}

/// The unit [session] declares for channel [name]: its own, else the VBO
/// `[header]` line naming it ("latacc-calc g"), as [declaredSpeedUnit] reads
/// a speed's; empty when it declares none.
String declaredChannelUnit(TelemetrySession session, String name) {
  final own = session.channels[name]?.unit.trim() ?? '';
  return own.isNotEmpty ? own : declaredSpeedUnit(session, name);
}

/// A channel name that is the car's yaw rate.
final RegExp _yawName = RegExp(r'yaw', caseSensitive: false);

/// A rotation rate in the logging device's own axes (a phone's gyro), which
/// is the car's yaw only when the device is mounted level and square.
final RegExp _deviceRotation = RegExp(r'rate[ _-]?of[ _-]?rotation|gyro', caseSensitive: false);

// Radians per second per unit of a yaw rate, or null for one not known.
double? _radiansPerSecondPerUnit(String unit) =>
    switch (unit.trim().toLowerCase().replaceAll(' ', '')) {
      'deg/s' || '°/s' || 'degrees/s' || 'dps' => math.pi / 180.0,
      'rad/s' => 1.0,
      _ => null,
    };

/// The channels of one recording the proxies read, resolved once.
final class GripChannels {
  GripChannels._(this.session);

  /// Resolves [session]'s lateral and longitudinal acceleration, speed and
  /// yaw-rate channels.
  factory GripChannels.of(TelemetrySession session) {
    final result = GripChannels._(session);
    final speed = session.channel('speed');
    if (speed != null) {
      result.speed = speed;
      result.speedFactor = metresPerSecondPerSpeedUnit(speed.unit);
    }
    final lateral = session.channel('lateralAcceleration');
    if (lateral == null) {
      result.lateralReason = gripNoLateralChannel;
    } else if (_gPerUnit(declaredChannelUnit(session, lateral.name)) == null) {
      result.lateralReason = gripUnsupportedUnit;
    } else {
      result.lateral = lateral;
      result.lateralSource = _accelerationSource(session, lateral);
    }
    final longitudinal = session.channel('longitudinalAcceleration');
    if (longitudinal != null) {
      // A channel there but in a unit not supported is not replaced by the
      // speed: another channel is never substituted silently.
      if (_gPerUnit(declaredChannelUnit(session, longitudinal.name)) == null) {
        result.longitudinalReason = gripUnsupportedUnit;
      } else {
        result.longitudinal = longitudinal;
        result.longitudinalSource = _accelerationSource(session, longitudinal);
      }
    } else if (speed == null) {
      result.longitudinalReason = gripNoSpeedChannel;
    } else if (result.speedFactor == null) {
      result.longitudinalReason = gripSpeedUnitNotSupported;
    } else {
      result.longitudinalSource = GripSource(
        channel: speed.name,
        unit: 'g',
        unitAssumed: speed.unit.trim().isEmpty,
        fromSpeed: true,
      );
    }
    // The car's yaw rate: a channel named for it, in a known unit. A gyro in
    // the device's axes is not taken for it.
    var yawReason = gripNoYawChannel;
    for (final name in sortedChannelNames(session.channels.keys)) {
      final channel = session.channels[name]!;
      if (_yawName.hasMatch(name)) {
        final factor = _radiansPerSecondPerUnit(declaredChannelUnit(session, name));
        if (factor == null) {
          yawReason = gripYawUnitUnknown;
          continue;
        }
        result.yaw = channel;
        result.yawFactor = factor;
        yawReason = '';
        break;
      }
      if (_deviceRotation.hasMatch(name) && yawReason == gripNoYawChannel) {
        yawReason = gripDeviceAxesOnly;
      }
    }
    result.yawReason = yawReason;
    if (yawReason.isEmpty && result.lateral == null) result.yawReason = result.lateralReason;
    if (yawReason.isEmpty && result.speedFactor == null) {
      result.yawReason = speed == null ? gripNoSpeedChannel : gripSpeedUnitNotSupported;
    }
    return result;
  }

  static GripSource _accelerationSource(TelemetrySession session, TelemetryChannel channel) {
    final declared = declaredChannelUnit(session, channel.name);
    return GripSource(
      channel: channel.name,
      unit: declared.isEmpty ? 'g' : declared,
      unitAssumed: declared.isEmpty,
    );
  }

  final TelemetrySession session;
  TelemetryChannel? speed;

  /// Metres per second per unit of [speed]; null when not known.
  double? speedFactor;

  TelemetryChannel? lateral;
  GripSource lateralSource = GripSource.none;
  String lateralReason = '';

  /// Null with a [longitudinalSource] from speed.
  TelemetryChannel? longitudinal;
  GripSource longitudinalSource = GripSource.none;
  String longitudinalReason = '';

  TelemetryChannel? yaw;
  double yawFactor = 1.0;

  /// Why there is no balance; empty when it can be read.
  String yawReason = '';

  /// Whether balance can be read at all.
  bool get hasBalance => yaw != null && yawReason.isEmpty;

  // The plausible limit in [source]'s unit (as the G-G pairs exclude).
  static double _limit(GripSource source) =>
      source.fromSpeed ? ggPlausibleLimitG : ggPlausibleLimitG / _gPerUnit(source.unit)!;

  /// [channel]'s finite, plausible samples from [start] to [end].
  Iterable<(double, double)> _samples(
    TelemetryChannel channel,
    GripSource source,
    double start,
    double end,
  ) sync* {
    if (!start.isFinite || !end.isFinite || end <= start) return;
    final limit = _limit(source);
    final times = channel.timestamps;
    for (var i = math.max(0, lowerBound(times, start)); i < times.length; ++i) {
      final time = times[i];
      if (time > end) break;
      final double value = channel.values[i];
      if (!value.isFinite || value.abs() > limit) continue;
      yield (time, value);
    }
  }

  /// The longitudinal acceleration (+ accelerating, − braking) in
  /// [longitudinalSource]'s unit from [start] to [end]: the channel's
  /// samples, or the speed's change around each speed sample.
  Iterable<(double, double)> longitudinalSamples(double start, double end) sync* {
    final channel = longitudinal;
    if (channel != null) {
      yield* _samples(channel, longitudinalSource, start, end);
      return;
    }
    final speed = this.speed, factor = speedFactor;
    if (!longitudinalSource.fromSpeed || speed == null || factor == null) return;
    if (!start.isFinite || !end.isFinite || end <= start) return;
    const h = gripSpeedDerivedHalfSpanSeconds;
    final times = speed.timestamps;
    for (var i = math.max(0, lowerBound(times, start)); i < times.length; ++i) {
      final time = times[i];
      if (time > end) break;
      final before = session.valueAt(speed.name, time - h);
      final after = session.valueAt(speed.name, time + h);
      if (before == null || after == null) continue;
      final g = (after - before) * factor / (2 * h) / standardGravity;
      if (!g.isFinite || g.abs() > ggPlausibleLimitG) continue;
      yield (time, g);
    }
  }

  /// The lateral acceleration in [lateralSource]'s unit from [start] to
  /// [end].
  Iterable<(double, double)> lateralSamples(double start, double end) {
    final channel = lateral;
    return channel == null ? const [] : _samples(channel, lateralSource, start, end);
  }

  /// The highest lateral acceleration (either way) from [start] to [end].
  GripLapValue peakLateral(double start, double end) {
    if (lateral == null) return GripLapValue(reason: lateralReason);
    var count = 0;
    var peak = 0.0;
    for (final (_, value) in lateralSamples(start, end)) {
      ++count;
      peak = math.max(peak, value.abs());
    }
    if (count < gripMinimumWindowSamples) return const GripLapValue(reason: gripTooFewSamples);
    return GripLapValue(value: peak, samples: count, source: lateralSource);
  }

  /// The highest deceleration (positive) from [start] to [end].
  GripLapValue peakDeceleration(double start, double end) {
    if (longitudinalSource.isNone) return GripLapValue(reason: longitudinalReason);
    var count = 0;
    var peak = 0.0;
    for (final (_, value) in longitudinalSamples(start, end)) {
      ++count;
      peak = math.max(peak, -value);
    }
    if (count < gripMinimumWindowSamples) return const GripLapValue(reason: gripTooFewSamples);
    if (peak <= 0.0) return GripLapValue(samples: count, reason: gripNoBraking);
    return GripLapValue(value: peak, samples: count, source: longitudinalSource);
  }

  /// The mean longitudinal acceleration from [start] to [end] (negative
  /// while still slowing).
  GripLapValue meanAcceleration(double start, double end) {
    if (longitudinalSource.isNone) return GripLapValue(reason: longitudinalReason);
    var count = 0;
    var sum = 0.0;
    for (final (_, value) in longitudinalSamples(start, end)) {
      ++count;
      sum += value;
    }
    if (count < gripMinimumWindowSamples) return const GripLapValue(reason: gripTooFewSamples);
    return GripLapValue(value: sum / count, samples: count, source: longitudinalSource);
  }

  /// The speed at [time] in metres per second, or null.
  double? speedMetresPerSecond(double time) {
    final speed = this.speed, factor = speedFactor;
    if (speed == null || factor == null) return null;
    final value = session.valueAt(speed.name, time);
    return value == null ? null : value * factor;
  }

  /// The median of the yaw rate over the yaw rate the cornering force and
  /// speed need (lateral acceleration ÷ speed), from [start] to [end], over
  /// the samples cornering with at least [gripBalanceMinimumLateralG] at
  /// [gripBalanceMinimumSpeedMetresPerSecond] or more. 1 means the car
  /// rotated as its path curved; above 1 it rotated more, below less.
  GripLapValue balance(double start, double end) {
    final yaw = this.yaw;
    if (!hasBalance || yaw == null) return GripLapValue(reason: yawReason);
    final toG = _gPerUnit(lateralSource.unit)!;
    final ratios = <double>[];
    for (final (time, value) in lateralSamples(start, end)) {
      final lateralG = value.abs() * toG;
      if (lateralG < gripBalanceMinimumLateralG) continue;
      final speed = speedMetresPerSecond(time);
      if (speed == null || speed < gripBalanceMinimumSpeedMetresPerSecond) continue;
      final rate = session.valueAt(yaw.name, time);
      if (rate == null) continue;
      final needed = lateralG * standardGravity / speed;
      final ratio = rate.abs() * yawFactor / needed;
      if (ratio.isFinite) ratios.add(ratio);
    }
    if (ratios.length < gripBalanceMinimumSamples) {
      return GripLapValue(samples: ratios.length, reason: gripTooFewSamples);
    }
    return GripLapValue(
      value: _median(ratios),
      samples: ratios.length,
      source: GripSource(
        channel: yaw.name,
        unit: declaredChannelUnit(session, yaw.name),
        unitAssumed: lateralSource.unitAssumed || (speed?.unit.trim().isEmpty ?? false),
      ),
    );
  }

  /// The edges of the speed bands in the speed's own unit, or null when the
  /// unit has none.
  List<double>? get bandEdges => switch (normalizedSpeedUnit(speed?.unit ?? '')) {
    _ when speed == null => null,
    'km/h' => gripBandEdgesKilometresPerHour,
    'mph' => gripBandEdgesMilesPerHour,
    _ when speed!.unit.trim().isEmpty => gripBandEdgesKilometresPerHour,
    _ => null,
  };

  /// Each speed band's highest lateral acceleration, deceleration and
  /// acceleration from [start] to [end], in band order.
  List<({GripLapValue lateral, GripLapValue braking, GripLapValue accelerating})> bandPeaks(
    double start,
    double end,
  ) {
    final edges = bandEdges;
    if (edges == null) return const [];
    final speed = this.speed!;
    int? band(double time) {
      final value = session.valueAt(speed.name, time);
      if (value == null) return null;
      var index = 0;
      while (index < edges.length && value >= edges[index]) {
        ++index;
      }
      return index;
    }

    final count = edges.length + 1;
    final lateralPeaks = List.filled(count, 0.0), lateralCounts = List.filled(count, 0);
    for (final (time, value) in lateralSamples(start, end)) {
      final index = band(time);
      if (index == null) continue;
      ++lateralCounts[index];
      lateralPeaks[index] = math.max(lateralPeaks[index], value.abs());
    }
    final braking = List.filled(count, 0.0), accelerating = List.filled(count, 0.0);
    final longitudinalCounts = List.filled(count, 0);
    for (final (time, value) in longitudinalSamples(start, end)) {
      final index = band(time);
      if (index == null) continue;
      ++longitudinalCounts[index];
      braking[index] = math.max(braking[index], -value);
      accelerating[index] = math.max(accelerating[index], value);
    }
    GripLapValue lapValue(GripSource source, String reason, int samples, double peak) {
      if (source.isNone) return GripLapValue(reason: reason);
      if (samples < gripMinimumBandSamples) {
        return GripLapValue(samples: samples, reason: gripTooFewSamples);
      }
      if (peak <= 0.0) return GripLapValue(samples: samples, reason: gripNoBraking);
      return GripLapValue(value: peak, samples: samples, source: source);
    }

    return [
      for (var i = 0; i < count; ++i)
        (
          lateral: lapValue(lateralSource, lateralReason, lateralCounts[i], lateralPeaks[i]),
          braking: lapValue(
            longitudinalSource,
            longitudinalReason,
            longitudinalCounts[i],
            braking[i],
          ),
          accelerating: lapValue(
            longitudinalSource,
            longitudinalReason,
            longitudinalCounts[i],
            accelerating[i],
          ),
        ),
    ];
  }
}

/// One corner's proxies over the group's ranked laps timed there.
final class GripCorner {
  const GripCorner({
    required this.segmentIndex,
    required this.segmentId,
    required this.name,
    this.lateral = const GripFigure(),
    this.braking = const GripFigure(),
    this.traction = const GripFigure(),
    this.balance = const GripFigure(),
  });

  final int segmentIndex;
  final String segmentId;
  final String name;

  /// Each lap's highest lateral acceleration between the corner's start and
  /// end.
  final GripFigure lateral;

  /// Each lap's highest deceleration from its braking point (or the
  /// corner's start without one) to its slowest point in the corner.
  final GripFigure braking;

  /// Each lap's mean acceleration from its slowest point to the corner's
  /// end.
  final GripFigure traction;

  /// Each lap's median ratio of yaw rate to the yaw rate its cornering
  /// needs ([GripChannels.balance]), through the corner.
  final GripFigure balance;
}

/// One speed band of a session.
final class GripBand {
  const GripBand({
    required this.lower,
    required this.upper,
    required this.speedUnit,
    this.lateral = const GripFigure(),
    this.braking = const GripFigure(),
    this.accelerating = const GripFigure(),
  });

  /// In the session's speed unit ([speedUnit], as declared; empty when it
  /// has none): null for the open ends.
  final double? lower, upper;
  final String speedUnit;

  /// Each lap's highest value in this band.
  final GripFigure lateral, braking, accelerating;
}

/// One session's proxies over its ranked laps.
final class GripSession {
  GripSession({
    required this.runId,
    required this.runName,
    required this.lapCount,
    List<GripBand> bands = const [],
    this.bandsReason = '',
    this.balance = const GripFigure(),
  }) : bands = List.unmodifiable(bands);

  final String runId;
  final String runName;

  /// The session's ranked laps.
  final int lapCount;

  /// Low to high speed; empty with [bandsReason].
  final List<GripBand> bands;
  final String bandsReason;

  /// Each lap's median balance ratio over the whole lap.
  final GripFigure balance;
}

/// The grip and balance proxies of a group's ranked laps.
final class DayGripProxies {
  DayGripProxies({List<GripSession> sessions = const [], List<GripCorner> corners = const []})
    : sessions = List.unmodifiable(sessions),
      corners = List.unmodifiable(corners);

  /// In recording order.
  final List<GripSession> sessions;

  /// In approved order.
  final List<GripCorner> corners;

  /// The proxies of the corner at segment [index], or null.
  GripCorner? cornerAt(int index) {
    for (final corner in corners) {
      if (corner.segmentIndex == index) return corner;
    }
    return null;
  }
}

/// The proxies of [rows] (the group's ranked laps, in recording order) and
/// of [corners] (the day's corners, timed on those laps), each lap read from
/// [sessionOf] its run. [sectorTimes] gives a lap's start and end times
/// through segment [index], or null where it was not timed.
DayGripProxies dayGripProxies(
  List<DayLapRow> rows,
  List<DayCorner> corners,
  TelemetrySession? Function(String runId) sessionOf,
  (double, double)? Function(DayLapRow lap, int segmentIndex) sectorTimes, {
  DayLapReference? bestLap,
  CancellationCheck? cancelled,
}) {
  final channels = <String, GripChannels?>{};
  GripChannels? channelsOf(String runId) => channels.putIfAbsent(runId, () {
    final session = sessionOf(runId);
    return session == null ? null : GripChannels.of(session);
  });

  final sessions = <GripSession>[];
  final runIds = <String>[];
  for (final row in rows) {
    if (!runIds.contains(row.runId)) runIds.add(row.runId);
  }
  for (final runId in runIds) {
    throwIfCancelled(cancelled);
    final laps = [
      for (final row in rows)
        if (row.runId == runId) row,
    ];
    final reader = channelsOf(runId);
    if (reader == null) {
      sessions.add(
        GripSession(
          runId: runId,
          runName: laps.first.runName,
          lapCount: laps.length,
          bandsReason: gripNoRecording,
          balance: const GripFigure(reason: gripNoRecording, typicalReason: gripNoRecording),
        ),
      );
      continue;
    }
    final edges = reader.bandEdges;
    final perLap = [for (final lap in laps) reader.bandPeaks(lap.start, lap.end)];
    final bands = <GripBand>[];
    if (edges != null) {
      for (var i = 0; i <= edges.length; ++i) {
        GripFigure figure(GripLapValue Function(int lap) read) =>
            aggregateGripLaps([for (var k = 0; k < laps.length; ++k) read(k).withLap(laps[k])]);
        bands.add(
          GripBand(
            lower: i == 0 ? null : edges[i - 1],
            upper: i == edges.length ? null : edges[i],
            speedUnit: normalizedSpeedUnit(reader.speed!.unit),
            lateral: figure((k) => perLap[k][i].lateral),
            braking: figure((k) => perLap[k][i].braking),
            accelerating: figure((k) => perLap[k][i].accelerating),
          ),
        );
      }
    }
    sessions.add(
      GripSession(
        runId: runId,
        runName: laps.first.runName,
        lapCount: laps.length,
        bands: bands,
        bandsReason: edges != null
            ? ''
            : reader.speed == null
            ? gripNoSpeedChannel
            : gripSpeedUnitNotSupported,
        balance: aggregateGripLaps([
          for (final lap in laps) reader.balance(lap.start, lap.end).withLap(lap),
        ]),
      ),
    );
  }

  final gripCorners = <GripCorner>[];
  for (final corner in corners) {
    throwIfCancelled(cancelled);
    final lateral = <GripLapValue>[],
        braking = <GripLapValue>[],
        traction = <GripLapValue>[],
        balance = <GripLapValue>[];
    for (final (lap, metrics) in corner.laps) {
      final reader = channelsOf(lap.runId);
      final window = sectorTimes(lap, corner.segmentIndex);
      if (reader == null || window == null) {
        final missing = GripLapValue(
          lap: lap,
          reason: reader == null ? gripNoRecording : gripNotTimed,
        );
        lateral.add(missing);
        braking.add(missing);
        traction.add(missing);
        balance.add(missing);
        continue;
      }
      final (start, end) = window;
      lateral.add(reader.peakLateral(start, end).withLap(lap));
      balance.add(reader.balance(start, end).withLap(lap));
      final slowest = metrics.speeds.minimum.telemetryTime;
      if (slowest == null || slowest < start || slowest > end) {
        braking.add(GripLapValue(lap: lap, reason: gripNoMinimumSpeed));
        traction.add(GripLapValue(lap: lap, reason: gripNoMinimumSpeed));
        continue;
      }
      final brakingPoint = metrics.braking.brakingPointTime;
      final from = brakingPoint != null && brakingPoint < slowest ? brakingPoint : start;
      braking.add(reader.peakDeceleration(from, slowest).withLap(lap));
      traction.add(reader.meanAcceleration(slowest, end).withLap(lap));
    }
    gripCorners.add(
      GripCorner(
        segmentIndex: corner.segmentIndex,
        segmentId: corner.segmentId,
        name: corner.name,
        lateral: aggregateGripLaps(lateral, prefer: bestLap),
        braking: aggregateGripLaps(braking, prefer: bestLap),
        traction: aggregateGripLaps(traction, prefer: bestLap),
        balance: aggregateGripLaps(balance, prefer: bestLap),
      ),
    );
  }
  return DayGripProxies(sessions: sessions, corners: gripCorners);
}
