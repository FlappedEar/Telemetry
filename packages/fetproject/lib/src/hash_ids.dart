import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'qt_json.dart';

/// Content ids stored in `.fetproject` documents, computed exactly as
/// FlappedEar Overlays computes them (KAN-170).
///
/// Each id is SHA-256 over Qt's compact JSON of a basis object. Lap
/// exclusions, comparison slots and segments refer to these ids, so a
/// difference of one byte makes them stop matching in the other app.

/// The algorithm stamp inside the `track-segments-v1` basis.
const trackSegmentAlgorithm = 'track-segment-v2';

/// The kind of a timing gate.
enum TimingGateType { start, split, unknown }

/// A timing gate as the recording declares it, in the recording's own
/// longitude convention.
typedef TimingGateEndpoints = ({
  TimingGateType type,
  double aLatitude,
  double aLongitude,
  double bLatitude,
  double bLongitude,
});

/// Most gates a recording may declare for the revision to be resolved.
const maximumRevisionGates = 128;

// Strict: a trailing newline is not a known revision (KAN-181). `gates-v1` is
// the revision earlier versions saved (see [gatesV1Revision]); `gates-v2` is
// the one written now (see [gatesV2Revision]).
final _gatesPattern = RegExp(r'^gates-v[12]:[0-9a-f]{64}$');

String _sha256(Object? basis) =>
    sha256.convert(qtCompactJsonBytes(basis)).toString();

bool _validCoordinate(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude.abs() <= 90.0 &&
    longitude.abs() <= 180.0;

/// The legacy `gates-v1` revision of a recording's ordered timing gates, or `null`
/// when it is unresolved: more than [maximumRevisionGates] gates, an invalid
/// coordinate, a gate of unknown type, or not exactly one start gate.
///
/// [westPositive] is true when the recording's longitudes are west-positive;
/// the revision is always computed in east-positive coordinates.
String? gatesV1Revision(
  List<TimingGateEndpoints> gates, {
  required bool westPositive,
}) {
  if (gates.length > maximumRevisionGates) return null;
  var starts = 0;
  final basis = <Object?>[];
  double longitude(double value) => westPositive ? -value : value;
  for (final gate in gates) {
    if (!_validCoordinate(gate.aLatitude, gate.aLongitude) ||
        !_validCoordinate(gate.bLatitude, gate.bLongitude) ||
        gate.type == TimingGateType.unknown) {
      return null;
    }
    if (gate.type == TimingGateType.start) starts++;
    basis.add([
      gate.type == TimingGateType.start ? 'start' : 'split',
      gate.aLatitude,
      longitude(gate.aLongitude),
      gate.bLatitude,
      longitude(gate.bLongitude),
    ]);
  }
  if (starts != 1) return null;
  return 'gates-v1:${_sha256(basis)}';
}

const _gateCentreCellDegrees = 100000;

/// The `gates-v2` revision of a recording's ordered timing gates, or `null`
/// when it is unresolved (the same cases as [gatesV1Revision]).
///
/// A gate is identified by what makes laps timed against it comparable: its
/// type, its centre (to 1e-5°, about a metre) and the bearing of its line
/// (to a degree, modulo 180°). The order of the endpoints and the width are
/// not part of it, and the coordinates are not hashed as stored. One start
/// line therefore gives one revision whichever recording format declared it
/// (RaceChrono's VBO writes a centre and a direction, its RCZ a centre, a
/// width and a bearing, and the two round differently and list the
/// endpoints in opposite order; FET-250).
String? gatesV2Revision(
  List<TimingGateEndpoints> gates, {
  required bool westPositive,
}) {
  if (gates.length > maximumRevisionGates) return null;
  var starts = 0;
  final basis = <Object?>[];
  double longitude(double value) => westPositive ? -value : value;
  for (final gate in gates) {
    if (!_validCoordinate(gate.aLatitude, gate.aLongitude) ||
        !_validCoordinate(gate.bLatitude, gate.bLongitude) ||
        gate.type == TimingGateType.unknown) {
      return null;
    }
    if (gate.type == TimingGateType.start) starts++;
    final aLongitude = longitude(gate.aLongitude);
    final bLongitude = longitude(gate.bLongitude);
    final latitude = (gate.aLatitude + gate.bLatitude) / 2;
    var spanLongitude = bLongitude - aLongitude;
    if (spanLongitude > 180) spanLongitude -= 360;
    if (spanLongitude < -180) spanLongitude += 360;
    final north = gate.bLatitude - gate.aLatitude;
    final east = spanLongitude * math.cos(latitude * math.pi / 180);
    if (north == 0 && east == 0) return null;
    final bearing =
        (math.atan2(east, north) * 180 / math.pi).roundToDouble() % 180;
    // The centre of a gate over the antimeridian is taken on the short side.
    var centreLongitude = aLongitude + spanLongitude / 2;
    if (centreLongitude > 180) centreLongitude -= 360;
    if (centreLongitude < -180) centreLongitude += 360;
    var longitudeCell = (centreLongitude * _gateCentreCellDegrees).round();
    // -180° and 180° are one meridian.
    if (longitudeCell == -180 * _gateCentreCellDegrees) {
      longitudeCell = 180 * _gateCentreCellDegrees;
    }
    basis.add([
      gate.type == TimingGateType.start ? 'start' : 'split',
      (latitude * _gateCentreCellDegrees).round(),
      longitudeCell,
      bearing.round(),
    ]);
  }
  if (starts != 1) return null;
  return 'gates-v2:${_sha256(basis)}';
}

bool _knownLayout(Map<String, Object?> configuration) {
  final value = configuration['layoutId'];
  return value is String &&
      qtTrimmed(value).isNotEmpty &&
      value.length <= 128 &&
      !value.contains('\u0000');
}

bool _knownDirection(Map<String, Object?> configuration) {
  final value = configuration['direction'];
  return value == 'clockwise' || value == 'counterclockwise';
}

bool _knownGates(Map<String, Object?> configuration) {
  final value = configuration['gateRevision'];
  return value is String && _gatesPattern.hasMatch(value);
}

/// The `compatibility-v1` group of a run's `trackConfiguration`, or `null`
/// when its layout, direction or gate revision is unresolved. Laps compare
/// only within one group.
String? compatibilityV1Id(Map<String, Object?> configuration) {
  if (!_knownLayout(configuration) ||
      !_knownDirection(configuration) ||
      !_knownGates(configuration)) {
    return null;
  }
  return 'compatibility-v1:${_sha256({'version': 1, 'layoutId': configuration['layoutId'], 'direction': configuration['direction'], 'gateRevision': configuration['gateRevision']})}';
}

/// The `track-segments-v1` revision of an approved segment list, as stored
/// in a run's `trackSegments`.
String trackSegmentsV1Revision(List<Object?> segments) =>
    'track-segments-v1:${_sha256({'version': trackSegmentAlgorithm, 'segments': segments})}';

Map<String, Object?> _primaryFingerprint(Map<String, Object?> run) {
  final sources = run['sources'];
  final telemetry = sources is Map ? sources['telemetry'] : null;
  if (telemetry is List) {
    for (final source in telemetry) {
      if (source is Map && source['id'] == run['primaryTelemetrySourceId']) {
        final reference = source['reference'];
        final fingerprint = reference is Map ? reference['fingerprint'] : null;
        return fingerprint is Map ? fingerprint.cast<String, Object?>() : {};
      }
    }
  }
  return {};
}

/// The `trackConfiguration` of [run], or the unknown configuration Overlays
/// assumes when the run has none.
Map<String, Object?> runTrackConfiguration(Map<String, Object?> run) {
  if (run.containsKey('trackConfiguration')) {
    final value = run['trackConfiguration'];
    return value is Map ? value.cast<String, Object?>() : {};
  }
  final sourceId = run['primaryTelemetrySourceId'];
  return {
    'layoutId': null,
    'direction': 'unknown',
    'gateRevision': null,
    'sourceId': sourceId is String ? sourceId : '',
    'sourceFingerprint': _primaryFingerprint(run),
  };
}

/// The `lap-derivation-v1` key of [run], as stored in every lap reference's
/// `derivationKey` (64 lowercase hex digits, no prefix).
String lapDerivationV1Key(Map<String, Object?> run) => _sha256({
  'version': 'lap-derivation-v1',
  'runId': run['id'],
  'sourceId': run['primaryTelemetrySourceId'],
  'sourceFingerprint': _primaryFingerprint(run),
  'trackConfiguration': runTrackConfiguration(run),
});

/// The matching key of a lap reference: its compact JSON.
String lapReferenceKey(Map<String, Object?> reference) =>
    qtCompactJson(reference);

/// [value] as Qt's `QString::trimmed()` returns it: without leading and
/// trailing characters for which `QChar::isSpace()` is true.
String qtTrimmed(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && _qtIsSpace(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _qtIsSpace(value.codeUnitAt(end - 1))) {
    end--;
  }
  return value.substring(start, end);
}

// QChar::isSpace(): tab to carriage return, space, U+0085, U+00A0, and the
// Unicode separators (Zs, Zl, Zp).
bool _qtIsSpace(int unit) =>
    (unit >= 0x09 && unit <= 0x0d) ||
    unit == 0x20 ||
    unit == 0x85 ||
    unit == 0xa0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200a) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202f ||
    unit == 0x205f ||
    unit == 0x3000;
