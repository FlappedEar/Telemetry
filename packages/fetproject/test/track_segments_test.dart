import 'dart:math';

import 'package:fetproject/fetproject.dart';
import 'package:test/test.dart';

final _group = 'compatibility-v1:${'0f' * 32}';

Map<String, Object?> _segment(String id, double start, double end) => {
  'id': id,
  'type': 'corner',
  'name': 'Corner $id',
  'startProgressMeters': start,
  'endProgressMeters': end,
  'trackConfigurationReference': _group,
};

void main() {
  test('makeTrackSegment gives a valid segment with a fresh UUID', () {
    final segment = makeTrackSegment(
      TrackSegmentType.straight,
      'Straight 1',
      10.0,
      120.5,
      _group,
    );
    expect(validTrackSegment(segment), isTrue);
    expect(segment['type'], 'straight');
    expect(segment['name'], 'Straight 1');
    expect(segment['startProgressMeters'], 10.0);
    expect(segment['endProgressMeters'], 120.5);
    expect(segment['trackConfigurationReference'], _group);
    expect(
      segment['id'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    final again = makeTrackSegment(
      TrackSegmentType.straight,
      'Straight 1',
      10.0,
      120.5,
      _group,
    );
    expect(again['id'], isNot(segment['id']));
    expect(
      makeTrackSegment(
        TrackSegmentType.corner,
        'C',
        1,
        2,
        _group,
        random: Random(3),
      )['id'],
      makeTrackSegment(
        TrackSegmentType.corner,
        'C',
        1,
        2,
        _group,
        random: Random(3),
      )['id'],
    );
  });

  test('makeTrackSegment refuses what would not validate', () {
    expect(
      makeTrackSegment(TrackSegmentType.corner, ' ', 1, 2, _group),
      isEmpty,
    );
    expect(
      makeTrackSegment(TrackSegmentType.corner, 'C', 2, 2, _group),
      isEmpty,
    );
    expect(
      makeTrackSegment(TrackSegmentType.corner, 'C', -1, 2, _group),
      isEmpty,
    );
    expect(
      makeTrackSegment(TrackSegmentType.corner, 'C', 1, double.nan, _group),
      isEmpty,
    );
    expect(
      makeTrackSegment(TrackSegmentType.corner, 'C', 1, 2, 'unresolved:run'),
      isEmpty,
    );
  });

  test('validTrackSegment', () {
    final segment = _segment('a', 10, 50);
    expect(validTrackSegment(segment), isTrue);
    expect(validTrackSegment({...segment, 'extra': 1}), isFalse);
    expect(validTrackSegment({...segment}..remove('name')), isFalse);
    expect(validTrackSegment({...segment, 'type': 'Corner'}), isFalse);
    expect(validTrackSegment({...segment, 'name': '  '}), isFalse);
    expect(validTrackSegment({...segment, 'name': 'n' * 160}), isTrue);
    expect(validTrackSegment({...segment, 'name': 'n' * 161}), isFalse);
    expect(validTrackSegment({...segment, 'id': 'i' * 129}), isFalse);
    expect(validTrackSegment({...segment, 'id': 'a\u0000'}), isFalse);
    expect(validTrackSegment({...segment, 'startProgressMeters': 10}), isTrue);
    expect(
      validTrackSegment({...segment, 'startProgressMeters': '10'}),
      isFalse,
    );
    expect(
      validTrackSegment({...segment, 'endProgressMeters': 1000000.5}),
      isFalse,
    );
    // PCRE's `$` also matches before a final newline, as in Overlays.
    expect(
      validTrackSegment({
        ...segment,
        'trackConfigurationReference': '$_group\n',
      }),
      isTrue,
    );
    expect(
      validTrackSegment({
        ...segment,
        'trackConfigurationReference': '${_group}0',
      }),
      isFalse,
    );
  });

  test('validTrackSegments', () {
    final a = _segment('a', 10, 50),
        b = _segment('b', 50, 200),
        wrap = _segment('w', 900, 20);
    expect(validTrackSegments(null), isTrue);
    expect(validTrackSegments(<Object?>[]), isTrue);
    expect(validTrackSegments([a, b, wrap]), isTrue);
    expect(validTrackSegments([wrap, a]), isFalse);
    expect(validTrackSegments([b, a]), isFalse);
    expect(validTrackSegments([a, _segment('a', 60, 70)]), isFalse);
    expect(
      validTrackSegments([
        for (var i = 0; i < 65; ++i) _segment('s$i', i + 1.0, i + 2.0),
      ]),
      isFalse,
    );
    expect(
      validTrackSegments([
        for (var i = 0; i < 64; ++i) _segment('s$i', i + 1.0, i + 2.0),
      ]),
      isTrue,
    );
    expect(validTrackSegments(a), isFalse);
    expect(validTrackSegments([1]), isFalse);
  });

  test('trackSegmentSetRevision is the track-segments-v1 revision', () {
    expect(
      trackSegmentSetRevision([_segment('a', 10, 50)]),
      startsWith('track-segments-v1:'),
    );
    expect(
      trackSegmentSetRevision([_segment('a', 10, 50)]),
      trackSegmentsV1Revision([_segment('a', 10, 50)]),
    );
  });
}
