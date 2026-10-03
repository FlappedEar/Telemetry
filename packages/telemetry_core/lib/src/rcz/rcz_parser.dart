// Port of the session layer of VBOOverlay native/src/telemetry/RczParser.cpp
// (FET-16): a RaceChrono RCZ shared session as a TelemetrySession. The format
// notes are VBOOverlay docs/rcz-format.md.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../geometry.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import '../timing_gate.dart';
import '../vbo/channel_aliases.dart';
import 'rcz_archive.dart';

Never _fail(String message) => throw RczFormatError(message);

/// Most samples on one clock.
const int maximumRczSamples = 2000000;

/// Most decoded values over all channels, gap markers included.
const int maximumRczDecodedValues = 8000000;

/// Most channels kept.
const int maximumRczChannels = 256;

const int _metadataBytes = 1024 * 1024;
const int _dayMilliseconds = 86400000;
const int _int32Max = 0x7fffffff, _int32Min = -0x80000000;

/// The accelerometer note every RCZ import carries.
const String rczAccelerationNote =
    'Recorded accelerometer channels, when present, are available as x_acc-acc, '
    'y_acc-acc and z_acc-acc in g. These are device axes, not calibrated vehicle '
    'lateral/longitudinal G. Calculated G and lean channels are not reconstructed.';

/// Reads RaceChrono RCZ shared sessions (format version 1).
abstract final class RczParser {
  /// Parses the RCZ archive at [path].
  ///
  /// Throws [RczFormatError] for a malformed or unsupported archive or
  /// session, and [OperationCancelled] when [cancelled] asks to stop. Only a
  /// flat, uninterrupted single session is accepted; resumed sessions,
  /// backups with several sessions, ZIP64 and encryption are refused rather
  /// than partly imported.
  static TelemetrySession parseFile(String path, {CancellationCheck? cancelled}) {
    final archive = RczArchive.open(path, cancelled: cancelled);
    try {
      return _RczSession(archive, cancelled).run();
    } finally {
      archive.close();
    }
  }
}

final class _Mapping {
  const _Mapping(this.name, this.unit, this.scale, [this.alias = '']);
  final String name, unit, alias;
  final double scale;
}

_Mapping? _mapping(int kind, int channel) {
  String axis(int offset) => String.fromCharCode('x'.codeUnitAt(0) + offset);
  if (kind == 1) {
    return switch (channel) {
      4 => const _Mapping('velocity', 'km/h', .0036, 'speed'),
      5 => const _Mapping('height', 'm', .001),
      6 => const _Mapping('heading', 'deg', .001),
      46 => const _Mapping('device_battery_level', '%', .001),
      30002 => const _Mapping('sats', '', 1),
      30003 => const _Mapping('fix_type', '', 1),
      30007 => const _Mapping('accuracy', 'm', .001),
      _ => null,
    };
  }
  if (kind == 5) {
    return switch (channel) {
      4 => const _Mapping('velocity-obd', 'km/h', 3.6),
      1002 => const _Mapping('brake_pos-obd', '%', 1, 'brake'),
      1005 => const _Mapping('gearbox_temp-obd', '°C', 1),
      10024 => const _Mapping('rpm-obd', 'rpm', 1, 'rpm'),
      10025 => const _Mapping('throttle_pos-obd', '%', 1, 'throttle'),
      10026 => const _Mapping('coolant_temp-obd', '°C', 1),
      10029 => const _Mapping('intake_temp-obd', '°C', 1),
      10066 => const _Mapping('engine_oil_temp-obd', '°C', 1),
      10071 => const _Mapping('accelerator_pos-obd', '%', 1),
      _ => null,
    };
  }
  if (kind == 6 && channel == 41) return const _Mapping('heart_rate-hrm', 'bpm', .001, 'heartRate');
  if (kind == 2 && channel >= 9 && channel <= 11) {
    return _Mapping('${axis(channel - 9)}_acc-acc', 'g', .0001);
  }
  if (kind == 3 && channel >= 12 && channel <= 14) {
    return _Mapping('${axis(channel - 12)}_rate_of_rotation-gyro', 'deg/s', .001);
  }
  if (kind == 8 && channel >= 28 && channel <= 30) {
    return _Mapping('${axis(channel - 28)}_magnetic_field-magn', 'µT', .001);
  }
  return null;
}

final RegExp _channelName = RegExp(r'^(channel2?)_([0-9]+)_([0-9]+)_([0-9]+)_([0-9]+)_([0-9]+)$');

/// A decimal field of a channel file name, as `QString::toInt` reads it: 0
/// when it does not fit a 32-bit int.
int _field(String digits) {
  final value = int.tryParse(digits);
  return value == null || value > _int32Max ? 0 : value;
}

void _validateJson(Object? value, [int depth = 0]) {
  if (depth > 24 || (value is String && value.length > 4096)) {
    _fail('Metadata nesting/string limit exceeded.');
  }
  if (value is List<Object?>) {
    if (value.length > 4096) _fail('Metadata array limit exceeded.');
    for (final item in value) {
      _validateJson(item, depth + 1);
    }
  } else if (value is Map<String, Object?>) {
    if (value.length > 4096) _fail('Metadata object limit exceeded.');
    for (final item in value.values) {
      _validateJson(item, depth + 1);
    }
  }
}

Map<String, Object?> _parseMetadata(Uint8List bytes, String name) {
  final Object? document;
  try {
    document = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    _fail('Invalid $name metadata.');
  }
  if (document is! Map<String, Object?>) _fail('Invalid $name metadata.');
  _validateJson(document);
  return document;
}

int _integer(Map<String, Object?> object, String name) {
  final value = object[name];
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > 9007199254740991 ||
      value.floor() != value) {
    _fail('Invalid $name metadata.');
  }
  return value.toInt();
}

// QJsonValue conversions with their defaults.
Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};
List<Object?> _array(Object? value) => value is List<Object?> ? value : const <Object?>[];
int _int(Object? value) =>
    value is num && value.isFinite && value.floor() == value && value.abs() <= _int32Max
    ? value.toInt()
    : 0;
double _double(Object? value, double fallback) => value is num ? value.toDouble() : fallback;
String _string(Object? value) => value is String ? value : '';

/// The next representable double after the non-negative [value], towards
/// +infinity or (when [up] is false) towards zero, as `std::nextafter`.
double _nextAfter(double value, {required bool up}) {
  final bits = ByteData(8)..setFloat64(0, value);
  final raw = bits.getInt64(0);
  if (!up && raw == 0) return value;
  bits.setInt64(0, up ? raw + 1 : raw - 1);
  return bits.getFloat64(0);
}

double _float32(double value) =>
    value.isFinite && value.abs() <= 3.4028234663852886e38 ? value : double.nan;

final class _RczSession {
  _RczSession(this.archive, this.cancelled);

  final RczArchive archive;
  final CancellationCheck? cancelled;
  final Map<String, String> metadata = {};
  final Map<String, TelemetryChannel> channels = {};
  final Map<String, String> aliases = {};
  final List<String> warnings = [];
  final List<TimingGate> gates = [];
  final Map<String, Float64List> clocks = {};
  int origin = 0, totalSamples = 0, sampleCount = 0;
  double duration = 0;

  TelemetrySession run() {
    // A shared single session has flat members. Backups and resumed archives
    // need a selection model; never import only the first fragment silently.
    if (archive.members.keys.any((name) => name.contains('/'))) {
      _fail(
        'Multi-session or resumed archives are not supported; share one uninterrupted session.',
      );
    }
    final info = _metadata('session.json');
    final fragment = _metadata('sessionfragment.json');
    if (_integer(info, 'version') != 1 || _integer(fragment, 'version') != 1) {
      _fail('Unsupported session version.');
    }
    for (final lap in _array(info['laps'])) {
      if (_int(_object(lap)['sessionResume']) != 0) {
        _fail('Resumed sessions are not supported yet.');
      }
    }
    origin = _integer(info, 'firstTimestamp');
    if (_integer(fragment, 'firstTimestamp') != origin) {
      _fail('Fragment does not start at the session origin.');
    }
    final primaryGps = _integer(fragment, 'primaryGpsDeviceIndex');
    metadata['format'] = 'RaceChrono RCZ v1';
    metadata['session'] = _string(info['trackName']);
    metadata['firstTimestampMilliseconds'] = '$origin';

    for (final name in archive.members.keys) {
      throwIfCancelled(cancelled);
      final match = _channelName.firstMatch(name);
      if (match == null) {
        if (name.startsWith('channel')) _fail('Malformed channel filename.');
        continue;
      }
      final kind = _field(match[2]!), device = _field(match[3]!);
      final channelId = _field(match[5]!), storage = _field(match[6]!);
      if (channelId == 1 || channelId == 2) continue; // Timestamps/distance are not sensor values.
      if (kind == 1 && device != primaryGps) continue; // Declared GPS, not a guessed device.
      final map = _mapping(kind, channelId);
      final position = kind == 1 && channelId == 3;
      if (map == null && !position) {
        warnings.add('Unsupported recorded channel: $name');
        continue;
      }
      if ((kind == 5 && (storage != 3 || match[1] != 'channel2')) ||
          (kind != 5 && !position && storage != 0) ||
          (position && storage != 1)) {
        _fail('Unsupported channel value encoding.');
      }
      final times = _timestamps('channel_${match[2]}_${match[3]}_${match[4]}_1_1');
      final bytes = archive.data(name);
      final stride = position || storage == 3 ? 8 : 4;
      if (bytes.length != times.length * stride) {
        _fail('Timestamp/value length mismatch: $name');
      }
      final data = ByteData.sublistView(bytes);
      final values = Float32List(times.length);
      final longitudes = position ? Float32List(times.length) : null;
      for (var index = 0, at = 0; at < bytes.length; ++index, at += stride) {
        if ((at & 0x7fff) == 0) throwIfCancelled(cancelled);
        double value;
        if (storage == 3) {
          value = data.getFloat64(at, Endian.little) * map!.scale;
        } else {
          final raw = data.getInt32(at, Endian.little);
          value = raw == _int32Max || raw == _int32Min
              ? double.nan
              : raw * (position ? 1.0 / 6000000.0 : map!.scale);
        }
        if (longitudes != null) {
          var longitude = data.getInt32(at + 4, Endian.little) / 6000000.0;
          if (!value.isFinite || value.abs() > 90 || longitude.abs() > 180) {
            value = double.nan;
            longitude = double.nan;
          }
          longitudes[index] = longitude;
        }
        values[index] = _float32(value);
      }
      if (longitudes != null) {
        if (aliases.containsKey('latitude')) _fail('Multiple position channels are unsupported.');
        _add(const _Mapping('lat', 'deg', 1, 'latitude'), times, values);
        _add(const _Mapping('long', 'deg', 1, 'longitude'), times, longitudes);
      } else {
        // No device-selection model exists for ambiguous semantic channels yet.
        if (map!.alias.isNotEmpty && aliases.containsKey(map.alias)) {
          _fail('Multiple sources for ${map.alias} are unsupported.');
        }
        _add(map, times, values);
      }
    }
    if (!aliases.containsKey('speed') || !aliases.containsKey('latitude')) {
      _fail('Declared GPS channels are missing.');
    }
    preferAcceleratorPedalForThrottle(aliases, channels);
    if (archive.members.containsKey('trackId.json')) {
      // Archive integrity and resource failures stay fatal, even for optional
      // metadata; invalid gate metadata only drops the gates.
      final bytes = archive.data('trackId.json', limit: _metadataBytes);
      try {
        _readGates(bytes);
      } on RczFormatError catch (error) {
        warnings.add(error.message);
      }
    }
    warnings.add(rczAccelerationNote);
    throwIfCancelled(cancelled);
    return TelemetrySession(
      duration: duration,
      startTime: (origin % _dayMilliseconds) / 1000.0,
      metadata: metadata,
      channels: channels,
      aliases: aliases,
      warnings: warnings,
      timingGates: gates,
      sampleCount: sampleCount,
    );
  }

  Map<String, Object?> _metadata(String name) =>
      _parseMetadata(archive.data(name, limit: _metadataBytes), name);

  Float64List _timestamps(String name) {
    final cached = clocks[name];
    if (cached != null) return cached;
    final bytes = archive.data(name);
    if (bytes.isEmpty || bytes.length % 8 != 0 || bytes.length ~/ 8 > maximumRczSamples) {
      _fail('Invalid timestamp channel length.');
    }
    final data = ByteData.sublistView(bytes);
    final result = Float64List(bytes.length ~/ 8);
    var previous = -1;
    for (var at = 0; at < bytes.length; at += 8) {
      if ((at & 0x7fff) == 0) throwIfCancelled(cancelled);
      final tick = data.getInt64(at, Endian.little);
      if (tick < origin || tick <= previous || tick - origin > _dayMilliseconds) {
        _fail('Timestamp channel is nonmonotonic or outside the supported 24-hour session.');
      }
      previous = tick;
      result[at ~/ 8] = (tick - origin) / 1000.0;
    }
    clocks[name] = result;
    return result;
  }

  void _add(_Mapping map, Float64List times, Float32List values) {
    if (times.length != values.length) _fail('Timestamp/value channel lengths differ.');
    totalSamples += values.length;
    if (totalSamples > maximumRczDecodedValues || channels.length >= maximumRczChannels) {
      _fail('Decoded channel/sample budget exceeded.');
    }
    var name = map.name;
    for (var suffix = 2; channels.containsKey(name); ++suffix) {
      name = '${map.name} ($suffix)';
    }
    sampleCount = math.max(sampleCount, times.length);
    // Recording gaps get a missing-value boundary on each side, so neither
    // analysis nor interpolation bridges them. Where they go depends on the
    // clock alone, so the channels of one clock share one timestamp list.
    final clock = _gapClock(times);
    totalSamples += clock.gaps.length * 2;
    if (clock.gaps.isNotEmpty && totalSamples > maximumRczDecodedValues) {
      _fail('Decoded gap/sample budget exceeded.');
    }
    final Float32List withGaps;
    if (clock.gaps.isEmpty) {
      withGaps = values;
    } else {
      withGaps = Float32List(clock.timestamps.length);
      var from = 0, to = 0;
      for (final gap in clock.gaps) {
        withGaps.setRange(to, to + gap - from, values, from);
        to += gap - from;
        withGaps[to++] = double.nan;
        withGaps[to++] = double.nan;
        from = gap;
      }
      withGaps.setRange(to, withGaps.length, values, from);
    }
    final channel = TelemetryChannel(
      name: name,
      unit: map.unit,
      timestamps: clock.timestamps,
      values: withGaps,
    );
    duration = math.max(duration, channel.timestamps.last);
    if (map.alias.isNotEmpty) aliases[map.alias] = name;
    channels[name] = channel;
  }

  // The clocks with their gap boundaries, by the raw clock.
  final Map<Float64List, ({Float64List timestamps, List<int> gaps})> _gapClocks = Map.identity();

  /// [times] with two boundary times around every interval longer than
  /// [telemetryGapThreshold], and the indices of [times] each gap precedes.
  ({Float64List timestamps, List<int> gaps}) _gapClock(Float64List times) {
    final cached = _gapClocks[times];
    if (cached != null) return cached;
    // The threshold depends on the timestamps only.
    final gapLimit = telemetryGapThreshold(
      TelemetryChannel(name: '', timestamps: times, values: Float32List(0)),
    );
    final gaps = <int>[];
    for (var index = 1; index < times.length; ++index) {
      if ((index & 0xfff) == 0) throwIfCancelled(cancelled);
      if (times[index] - times[index - 1] > gapLimit) gaps.add(index);
    }
    var timestamps = times;
    if (gaps.isNotEmpty) {
      timestamps = Float64List(times.length + gaps.length * 2);
      var from = 0, to = 0;
      for (final gap in gaps) {
        timestamps.setRange(to, to + gap - from, times, from);
        to += gap - from;
        timestamps[to++] = _nextAfter(times[gap - 1], up: true);
        timestamps[to++] = _nextAfter(times[gap], up: false);
        from = gap;
      }
      timestamps.setRange(to, timestamps.length, times, from);
    }
    return _gapClocks[times] = (timestamps: timestamps, gaps: gaps);
  }

  void _readGates(Uint8List bytes) {
    final track = _object(_parseMetadata(bytes, 'trackId.json')['track']);
    final traps = _array(track['traps']);
    if (traps.length > 64) _fail('Too many timing gates.');
    const radians = math.pi / 180.0, radius = 6371000.0;
    for (final value in traps) {
      final trap = _object(value);
      if (_int(trap['type']) != 3 || trap['uniDirectional'] != true) {
        warnings.add('Unsupported timing gate ignored.');
        continue;
      }
      final lat = _double(trap['centerLatitude'], 1e20) / 6000000.0;
      final lon = _double(trap['centerLongitude'], 1e20) / 6000000.0;
      final width = _double(trap['width'], -1) / 1000.0;
      final bearing = _double(trap['bearing'], -1) / 1000.0;
      if (!(lat.abs() < 89.0) ||
          !(lon.abs() <= 180) ||
          !(width > 0) ||
          width > 1000 ||
          !(bearing >= 0) ||
          bearing >= 360) {
        _fail('Invalid timing gate coordinates or geometry.');
      }
      // The trap stores its centre and travel bearing. The gate spans half its
      // width on each side, perpendicular to travel.
      final east = width * .5 * math.cos(bearing * radians);
      final north = -width * .5 * math.sin(bearing * radians);
      final deltaLat = north / (radius * radians);
      final deltaLon = east / (radius * radians * math.cos(lat * radians));
      final gate = TimingGate(
        type: TimingGateType.start,
        sourceName: 'Start',
        sourceDescription: _string(trap['name']),
        endpointA: GeoCoordinate(lat - deltaLat, lon - deltaLon),
        endpointB: GeoCoordinate(lat + deltaLat, lon + deltaLon),
      );
      if (!isValidCoordinate(gate.endpointB)) _fail('Invalid timing gate endpoint.');
      gates.add(gate);
    }
  }
}
