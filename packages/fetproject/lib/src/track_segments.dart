// Port of FlappedEar Overlays native/src/telemetry/TrackSegments.{h,cpp}
// (revision d4d1039, FET-31): the approved track segments a run stores in
// `trackSegments`, and how a document's segments are validated.
import 'dart:math';

import 'hash_ids.dart';

/// Most segments one run may store.
const int maximumTrackSegments = 64;

const int _maximumTrackSegmentIdCharacters = 128;
const int _maximumTrackSegmentNameCharacters = 160;

// Far beyond any real track length; this only keeps an imported or edited
// document from carrying an unbounded or non-finite progress value.
const double _maximumTrackSegmentProgressMeters = 1000000.0;

// Overlays checks `^compatibility-v1:[0-9a-f]{64}$` with PCRE2, where `$` also
// matches before a final newline (see README, "Behaviour carried over").
final _configurationReference = RegExp(r'^compatibility-v1:[0-9a-f]{64}\n?$');

/// The kind of a track segment.
enum TrackSegmentType {
  sector('sector'),
  corner('corner'),
  straight('straight');

  const TrackSegmentType(this.jsonName);

  /// The `type` stored in the document.
  final String jsonName;
}

/// The `type` stored for [type]: `sector`, `corner` or `straight`.
String trackSegmentTypeName(TrackSegmentType type) => type.jsonName;

bool _validSegmentText(Object? value, int limit) =>
    value is String &&
    qtTrimmed(value).isNotEmpty &&
    !value.contains('\u0000') &&
    value.length <= limit;

/// A new segment with a fresh random id (a version 4 UUID without braces, as
/// Qt's `QUuid::createUuid()` writes it). [trackConfigurationReference] is the
/// run's `compatibility-v1` group id. Returns an empty map when the segment
/// would not validate (an empty name, equal bounds, an unknown reference...).
///
/// Editing an existing segment's name or bounds keeps its id rather than
/// calling this again.
Map<String, Object?> makeTrackSegment(
  TrackSegmentType type,
  String name,
  double startProgressMeters,
  double endProgressMeters,
  String trackConfigurationReference, {
  Random? random,
}) {
  final segment = <String, Object?>{
    'id': newTrackSegmentId(random),
    'type': trackSegmentTypeName(type),
    'name': name,
    'startProgressMeters': startProgressMeters,
    'endProgressMeters': endProgressMeters,
    'trackConfigurationReference': trackConfigurationReference,
  };
  return validTrackSegment(segment) ? segment : <String, Object?>{};
}

/// A random version 4 UUID without braces, lowercase.
String newTrackSegmentId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = [for (var i = 0; i < 16; ++i) source.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')]
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Whether [segment] is one stored segment: exactly the six keys `id`,
/// `type`, `name`, `startProgressMeters`, `endProgressMeters` and
/// `trackConfigurationReference`, with a non-blank id (≤ 128 UTF-16 units)
/// and name (≤ 160), finite bounds in [0, 1e6] that differ, and a
/// `compatibility-v1` reference.
bool validTrackSegment(Map<String, Object?> segment) {
  if (segment.length != 6) return false;
  if (!_validSegmentText(segment['id'], _maximumTrackSegmentIdCharacters)) {
    return false;
  }
  if (!const ['sector', 'corner', 'straight'].contains(segment['type'])) {
    return false;
  }
  if (!_validSegmentText(segment['name'], _maximumTrackSegmentNameCharacters)) {
    return false;
  }
  final start = segment['startProgressMeters'];
  final end = segment['endProgressMeters'];
  if (start is! num || end is! num) return false;
  final a = start.toDouble(), b = end.toDouble();
  if (!a.isFinite || !b.isFinite) return false;
  if (a < 0 ||
      a > _maximumTrackSegmentProgressMeters ||
      b < 0 ||
      b > _maximumTrackSegmentProgressMeters) {
    return false;
  }
  if (a == b) return false; // a zero-length segment carries no evidence
  final reference = segment['trackConfigurationReference'];
  return reference is String && _configurationReference.hasMatch(reference);
}

/// Whether [value] is a valid `trackSegments` value: absent (null), or a list
/// of at most [maximumTrackSegments] valid segments with unique ids, in
/// non-decreasing start order, where only the last one may wrap across the
/// start/finish line (end before start).
bool validTrackSegments(Object? value) {
  if (value == null) return true;
  if (value is! List || value.length > maximumTrackSegments) return false;
  final ids = <String>{};
  var previousStart = -1.0;
  for (var index = 0; index < value.length; ++index) {
    final item = value[index];
    if (item is! Map<String, Object?> || !validTrackSegment(item)) return false;
    if (!ids.add(item['id'] as String)) return false;
    final start = (item['startProgressMeters'] as num).toDouble();
    final end = (item['endProgressMeters'] as num).toDouble();
    if (start < previousStart) return false;
    previousStart = start;
    // Only the final (highest-start) segment may wrap past the start/finish
    // line: the one physically meaningful case, a segment covering the gate.
    if (end < start && index != value.length - 1) return false;
  }
  return true;
}

/// The revision of a set of approved segments (Overlays'
/// `trackSegmentSetRevision`): a pure content hash, never stored.
String trackSegmentSetRevision(List<Object?> segments) =>
    trackSegmentsV1Revision(segments);
