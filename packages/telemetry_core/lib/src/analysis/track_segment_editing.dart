// Port of FlappedEar Overlays native/src/telemetry/TrackSegmentEditing.{h,cpp}
// (revision d4d1039, FET-34): editing a run's approved track segments.
//
// Every operation takes the run's stored `trackSegments` and returns a
// complete replacement list, or a reason. Results are always ordered,
// non-overlapping, bounded and valid; a segment that would become empty is
// refused. Identity is stable: an edited, moved or renamed segment keeps its
// id, a split keeps it on the first part and a merge keeps the earlier
// segment's. All stored segments must belong to one track configuration.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart'
    show
        TrackSegmentType,
        makeTrackSegment,
        maximumTrackSegments,
        qtTrimmed,
        trackSegmentTypeName,
        validTrackSegment,
        validTrackSegments;

import 'track_segment_proposals.dart';
import 'track_segment_review.dart';

/// The editing algorithm's tag.
const trackSegmentEditingAlgorithm = 'track-segment-editing-v1';

// Bounds survive a JSON round trip exactly; this only absorbs arithmetic noise.
const double _boundaryEpsilon = 1e-6;

/// The result of an edit: the new `trackSegments`, or null and why not.
typedef SegmentEdit = ({List<Map<String, Object?>>? segments, String error});

SegmentEdit _refused(String error) => (segments: null, error: error);

// Progress 0 and `length` are the same point on the loop (the gate).
bool _sameBoundary(double a, double b, double length) =>
    (a - b).abs() <= _boundaryEpsilon ||
    ((a - length).abs() <= _boundaryEpsilon && b.abs() <= _boundaryEpsilon) ||
    (a.abs() <= _boundaryEpsilon && (b - length).abs() <= _boundaryEpsilon);

// Distance travelled from `from` to `to` in the direction of the lap.
double _forward(double from, double to, double length) =>
    to >= from ? to - from : to + length - from;

double _startOf(Map<String, Object?> segment) => (segment['startProgressMeters'] as num).toDouble();
double _endOf(Map<String, Object?> segment) => (segment['endProgressMeters'] as num).toDouble();

bool _withinAxis(double meters, double length) =>
    meters.isFinite && meters >= 0.0 && meters <= length;

// A copy of every stored segment, or why they cannot be edited.
(List<Map<String, Object?>>?, String) _load(Object? storedSegments) {
  if (!validTrackSegments(storedSegments)) {
    return (null, 'The stored approved segments are invalid.');
  }
  final segments = [
    for (final value in (storedSegments as List?) ?? const []) {...value as Map<String, Object?>},
  ];
  for (final segment in segments) {
    if (segment['trackConfigurationReference'] != segments.first['trackConfigurationReference']) {
      return (
        null,
        'Segments approved for a different track configuration must be discarded first.',
      );
    }
  }
  return (segments, '');
}

int _indexOf(List<Map<String, Object?>> segments, String id) {
  for (var index = 0; index < segments.length; ++index) {
    if (segments[index]['id'] == id) return index;
  }
  return -1;
}

SegmentEdit _finalize(List<Map<String, Object?>> segments, double length) {
  for (final segment in segments) {
    if ((_startOf(segment) - _endOf(segment)).abs() <= _boundaryEpsilon) {
      return _refused('“${segment['name']}” would become empty.');
    }
    if (!validTrackSegment(segment)) return _refused('“${segment['name']}” would be invalid.');
  }
  for (var a = 0; a < segments.length; ++a) {
    for (var b = a + 1; b < segments.length; ++b) {
      if (progressRangesOverlap(
        ProgressRange(_startOf(segments[a]), _endOf(segments[a])),
        ProgressRange(_startOf(segments[b]), _endOf(segments[b])),
        length,
      )) {
        return _refused('“${segments[a]['name']}” would overlap “${segments[b]['name']}”.');
      }
    }
  }
  if (segments.length > maximumTrackSegments) {
    return _refused('At most $maximumTrackSegments segments can be approved.');
  }
  // Start order, with the one segment that crosses the gate last (a stable
  // sort, as std::stable_sort).
  final indexed = [for (var i = 0; i < segments.length; ++i) (i, segments[i])]
    ..sort((x, y) {
      final xWraps = _endOf(x.$2) < _startOf(x.$2);
      final yWraps = _endOf(y.$2) < _startOf(y.$2);
      if (xWraps != yWraps) return xWraps ? 1 : -1;
      final byStart = _startOf(x.$2).compareTo(_startOf(y.$2));
      return byStart != 0 ? byStart : x.$1.compareTo(y.$1);
    });
  final result = [for (final (_, segment) in indexed) segment];
  if (!validTrackSegments(result)) {
    return _refused('Only one segment may cross the start/finish line.');
  }
  return (segments: result, error: '');
}

/// [storedSegments] with segment [id] renamed to [name], retyped to [type]
/// (`corner`, `straight` or `sector`) and moved to [startMeters] to
/// [endMeters] on an axis of [lengthMeters]. With [keepAdjacentJoined], a
/// neighbour that shared a moved boundary moves with it.
SegmentEdit withEditedSegment(
  Object? storedSegments,
  String id,
  String name,
  String type,
  double startMeters,
  double endMeters,
  bool keepAdjacentJoined,
  double lengthMeters,
) {
  final invalid = proposalEditError(name, startMeters, endMeters, lengthMeters);
  if (invalid.isNotEmpty) return _refused(invalid);
  if (trackSegmentTypeFromName(type) == null) return _refused('Choose corner, straight or sector.');
  final (segments, error) = _load(storedSegments);
  if (segments == null) return _refused(error);
  final index = _indexOf(segments, id);
  if (index < 0) return _refused('This segment is no longer approved.');
  final oldStart = _startOf(segments[index]);
  final oldEnd = _endOf(segments[index]);
  if (keepAdjacentJoined) {
    for (var other = 0; other < segments.length; ++other) {
      if (other == index) continue;
      final neighbour = segments[other];
      if (!_sameBoundary(startMeters, oldStart, lengthMeters) &&
          _sameBoundary(_endOf(neighbour), oldStart, lengthMeters)) {
        neighbour['endProgressMeters'] = startMeters <= _boundaryEpsilon
            ? lengthMeters
            : startMeters;
      }
      if (!_sameBoundary(endMeters, oldEnd, lengthMeters) &&
          _sameBoundary(_startOf(neighbour), oldEnd, lengthMeters)) {
        neighbour['startProgressMeters'] = endMeters >= lengthMeters - _boundaryEpsilon
            ? 0.0
            : endMeters;
      }
    }
  }
  segments[index]
    ..['name'] = qtTrimmed(name)
    ..['type'] = type
    ..['startProgressMeters'] = startMeters
    ..['endProgressMeters'] = endMeters;
  return _finalize(segments, lengthMeters);
}

/// [storedSegments] with segment [id] split at [atMeters], strictly inside
/// it. The first part keeps the id and name; the second gets a fresh id
/// (from [random]) and [secondName].
SegmentEdit withSplitSegment(
  Object? storedSegments,
  String id,
  double atMeters,
  String secondName,
  double lengthMeters, {
  math.Random? random,
}) {
  if (!lengthMeters.isFinite || lengthMeters <= 0.0) {
    return _refused('The track axis is unavailable.');
  }
  final (segments, error) = _load(storedSegments);
  if (segments == null) return _refused(error);
  final index = _indexOf(segments, id);
  if (index < 0) return _refused('This segment is no longer approved.');
  final original = segments[index];
  final start = _startOf(original);
  final end = _endOf(original);
  final inside = _withinAxis(atMeters, lengthMeters);
  final before = inside ? _forward(start, atMeters, lengthMeters) : 0.0;
  final after = inside ? _forward(atMeters, end, lengthMeters) : 0.0;
  if (!(before > _boundaryEpsilon) ||
      !(after > _boundaryEpsilon) ||
      (before + after - _forward(start, end, lengthMeters)).abs() > _boundaryEpsilon) {
    return _refused('Split inside the segment, away from its ends.');
  }
  final atGate = atMeters <= _boundaryEpsilon || atMeters >= lengthMeters - _boundaryEpsilon;
  final second = makeTrackSegment(
    trackSegmentTypeFromName(original['type'] as String)!,
    qtTrimmed(secondName),
    atGate ? 0.0 : atMeters,
    end,
    original['trackConfigurationReference'] as String,
    random: random,
  );
  if (second.isEmpty) return _refused('Enter a name of 1–160 characters for the new segment.');
  original['endProgressMeters'] = atGate ? lengthMeters : atMeters;
  segments.add(second);
  return _finalize(segments, lengthMeters);
}

/// [storedSegments] with segments [firstId] and [secondId], which share a
/// boundary (in either order), merged into one. It keeps the earlier
/// segment's id and name; differing types become `sector`.
SegmentEdit withMergedSegments(
  Object? storedSegments,
  String firstId,
  String secondId,
  double lengthMeters,
) {
  if (!lengthMeters.isFinite || lengthMeters <= 0.0) {
    return _refused('The track axis is unavailable.');
  }
  final (segments, error) = _load(storedSegments);
  if (segments == null) return _refused(error);
  var first = _indexOf(segments, firstId);
  var second = _indexOf(segments, secondId);
  if (first < 0 || second < 0 || first == second) {
    return _refused('Choose two different approved segments.');
  }
  if (!_sameBoundary(_endOf(segments[first]), _startOf(segments[second]), lengthMeters)) {
    (first, second) = (second, first);
  }
  final earlier = segments[first];
  final later = segments[second];
  if (!_sameBoundary(_endOf(earlier), _startOf(later), lengthMeters)) {
    return _refused('Only segments that share a boundary can be merged.');
  }
  if (_sameBoundary(_startOf(earlier), _endOf(later), lengthMeters)) {
    return _refused('Merging would cover the whole lap; a segment needs distinct start and end.');
  }
  final merged = {...earlier, 'endProgressMeters': _endOf(later)};
  if (earlier['type'] != later['type']) {
    merged['type'] = trackSegmentTypeName(TrackSegmentType.sector);
  }
  segments[first] = merged;
  segments.removeAt(second);
  return _finalize(segments, lengthMeters);
}

/// One whole-list change of a run's segments.
final class SegmentEditStep {
  const SegmentEditStep(this.runId, this.before, this.after);

  final String runId;
  final List<Map<String, Object?>> before;
  final List<Map<String, Object?>> after;
}

bool _sameSegments(List<Map<String, Object?>> a, List<Map<String, Object?>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; ++i) {
    if (a[i].length != b[i].length) return false;
    for (final entry in a[i].entries) {
      if (!b[i].containsKey(entry.key) || b[i][entry.key] != entry.value) return false;
    }
  }
  return true;
}

/// Bounded undo and redo of whole-list segment changes within one editing
/// session. A step may only be applied while the run still holds exactly the
/// state the step left behind; the caller checks that and clears the history
/// otherwise ([sameTrackSegments]).
final class SegmentEditHistory {
  SegmentEditHistory([this.limit = 50]);

  final int limit;
  final List<SegmentEditStep> _undo = [];
  final List<SegmentEditStep> _redo = [];

  void record(String runId, List<Map<String, Object?>> before, List<Map<String, Object?>> after) {
    if (_sameSegments(before, after)) return;
    _redo.clear();
    _undo.add(SegmentEditStep(runId, before, after));
    while (_undo.length > math.max(1, limit)) {
      _undo.removeAt(0);
    }
  }

  SegmentEditStep? get nextUndo => _undo.isEmpty ? null : _undo.last;
  SegmentEditStep? get nextRedo => _redo.isEmpty ? null : _redo.last;

  void commitUndo() {
    if (_undo.isNotEmpty) _redo.add(_undo.removeLast());
  }

  void commitRedo() {
    if (_redo.isNotEmpty) _undo.add(_redo.removeLast());
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  int get undoCount => _undo.length;
  int get redoCount => _redo.length;
}

/// Whether two segment lists hold the same segments with the same values, in
/// the same order.
bool sameTrackSegments(List<Map<String, Object?>> a, List<Map<String, Object?>> b) =>
    _sameSegments(a, b);

/// A sample of a lap trace on the map: its progress and where it is drawn.
final class ProgressMapPoint {
  const ProgressMapPoint(this.progressMeters, this.x, this.y);

  final double progressMeters;
  final double x;
  final double y;
}

/// What [pickProgressAt] found: a progress, or why none (`noTrace`,
/// `farFromTrack` or `ambiguous`).
typedef ProgressPick = ({double? progressMeters, String reason});

/// Track progress at the point ([x], [y]) on the map: the nearest sample of
/// [trace] within [maximumDistance]. Refused as ambiguous when another sample
/// more than [separationMeters] away along the track is within
/// [ambiguityMargin] of the nearest distance (a crossing, or a nearby
/// parallel section).
ProgressPick pickProgressAt(
  List<ProgressMapPoint> trace,
  double x,
  double y,
  double maximumDistance,
  double ambiguityMargin,
  double separationMeters,
  double lengthMeters,
) {
  if (trace.isEmpty ||
      !x.isFinite ||
      !y.isFinite ||
      !lengthMeters.isFinite ||
      lengthMeters <= 0.0) {
    return (progressMeters: null, reason: 'noTrace');
  }
  double distanceTo(ProgressMapPoint sample) => _hypot(sample.x - x, sample.y - y);
  var nearest = 0;
  var nearestDistance = double.infinity;
  for (var index = 0; index < trace.length; ++index) {
    final distance = distanceTo(trace[index]);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = index;
    }
  }
  if (!(nearestDistance <= maximumDistance)) return (progressMeters: null, reason: 'farFromTrack');
  final progress = trace[nearest].progressMeters;
  for (final sample in trace) {
    final apart = (sample.progressMeters - progress).abs();
    if (math.min(apart, lengthMeters - apart) > separationMeters &&
        distanceTo(sample) <= nearestDistance + ambiguityMargin) {
      return (progressMeters: null, reason: 'ambiguous');
    }
  }
  return (progressMeters: progress, reason: '');
}

// std::hypot: scaled so it neither overflows nor underflows.
double _hypot(double a, double b) {
  final x = a.abs(), y = b.abs();
  final high = math.max(x, y), low = math.min(x, y);
  if (high == 0.0 || high.isInfinite) return high;
  final ratio = low / high;
  return high * math.sqrt(1.0 + ratio * ratio);
}
