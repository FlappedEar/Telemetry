// Editing approved track segments (analysis/track_segment_editing.dart, after
// Overlays' TrackSegmentEditingTests): stable ids, refused overlap and empty
// segments, splits and merges across the gate, bounded undo and redo,
// crossing-safe map picking, and the review state of proposals after edits.
import 'dart:math';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const double lap = 1000.0;
final reference = 'compatibility-v1:${'a' * 64}';
final other = 'compatibility-v1:${'b' * 64}';
final random = Random(7);

Map<String, Object?> segment(
  TrackSegmentType type,
  String name,
  double start,
  double end, [
  String? configuration,
]) => makeTrackSegment(type, name, start, end, configuration ?? reference, random: random);

Map<String, Object?> find(List<Map<String, Object?>> segments, Object? id) =>
    segments.firstWhere((segment) => segment['id'] == id, orElse: () => const {});

double startOf(Map<String, Object?> segment) => (segment['startProgressMeters'] as num).toDouble();
double endOf(Map<String, Object?> segment) => (segment['endProgressMeters'] as num).toDouble();

TrackSegmentProposal proposal(TrackSegmentType type, String name, double start, double end) =>
    TrackSegmentProposal(
      type: type,
      name: name,
      start: SegmentProposalBoundary(start, 7.0),
      end: SegmentProposalBoundary(end, 7.0),
    );

void main() {
  test('an edit keeps the id and changes the revision', () {
    final a = segment(TrackSegmentType.corner, 'Turn 1', 100, 200);
    final b = segment(TrackSegmentType.straight, 'Back straight', 200, 400);
    final stored = [a, b];
    final edited = withEditedSegment(
      stored,
      a['id']! as String,
      ' Hairpin ',
      'straight',
      100,
      200,
      false,
      lap,
    );
    expect(edited.error, isEmpty);
    expect(validTrackSegments(edited.segments), isTrue);
    final renamed = find(edited.segments!, a['id']);
    expect(renamed['name'], 'Hairpin');
    expect(renamed['type'], 'straight');
    expect(renamed['trackConfigurationReference'], reference);
    expect(find(edited.segments!, b['id']), b);
    // The input is never changed in place.
    expect(a['name'], 'Turn 1');
    final before = approvedSegmentation(stored, reference);
    final after = approvedSegmentation(edited.segments, reference);
    expect(before.revision, isNot(after.revision));
    expect(segmentationResultCurrent(segmentationResultStamp(before), after), isFalse);
  });

  test('joined neighbours move only when asked', () {
    final a = segment(TrackSegmentType.corner, 'Turn 1', 100, 200);
    final b = segment(TrackSegmentType.straight, 'Back straight', 200, 400);
    final id = a['id']! as String;
    final refused = withEditedSegment([a, b], id, 'Turn 1', 'corner', 100, 250, false, lap);
    expect(refused.segments, isNull);
    expect(refused.error, contains('overlap'));

    final joined = withEditedSegment([a, b], id, 'Turn 1', 'corner', 100, 250, true, lap).segments!;
    expect(endOf(find(joined, id)), 250);
    expect(startOf(find(joined, b['id'])), 250);
    expect(endOf(find(joined, b['id'])), 400);

    final empty = withEditedSegment([a, b], id, 'Turn 1', 'corner', 100, 400, true, lap);
    expect(empty.error, contains('empty'));

    final gap = withEditedSegment([a, b], id, 'Turn 1', 'corner', 100, 150, false, lap).segments!;
    expect(startOf(find(gap, b['id'])), 200);
  });

  test('invalid edits are refused with a reason', () {
    final a = segment(TrackSegmentType.corner, 'Turn 1', 100, 200);
    final id = a['id']! as String;
    final stored = [a];
    SegmentEdit edit(String name, String type, double start, double end, [Object? value]) =>
        withEditedSegment(value ?? stored, id, name, type, start, end, false, lap);
    expect(edit('Turn 1', 'corner', 150, 150).error, 'A segment cannot be empty.');
    expect(edit('Turn 1', 'corner', 100, lap + 1).error, 'Bounds must lie between 0 and 1000.0 m.');
    expect(edit('Turn 1', 'corner', double.nan, 10).segments, isNull);
    expect(edit(' ', 'corner', 100, 200).error, 'Enter a name of 1–160 characters.');
    expect(edit('Turn 1', 'chicane', 100, 200).error, 'Choose corner, straight or sector.');
    expect(
      withEditedSegment(stored, 'missing', 'Turn 1', 'corner', 100, 200, false, lap).error,
      'This segment is no longer approved.',
    );
    expect(edit('Turn 1', 'corner', 100, 200, 'not a list').error, contains('invalid'));
    final mixed = [a, segment(TrackSegmentType.straight, 'Other layout', 300, 400, other)];
    expect(
      edit('Turn 1', 'corner', 100, 150, mixed).error,
      contains('different track configuration'),
    );
  });

  test('a split keeps the first id', () {
    final a = segment(TrackSegmentType.corner, 'Turn 1', 100, 200);
    final b = segment(TrackSegmentType.straight, 'Back straight', 200, 400);
    final id = b['id']! as String;
    final split = withSplitSegment([a, b], id, 300, 'Back straight 2', lap).segments!;
    expect(split, hasLength(3));
    expect(validTrackSegments(split), isTrue);
    final first = find(split, id);
    expect((startOf(first), endOf(first), first['name']), (200.0, 300.0, 'Back straight'));
    final second = split[2];
    expect(second['id'], isNot(id));
    expect(second['name'], 'Back straight 2');
    expect(second['type'], 'straight');
    expect((startOf(second), endOf(second)), (300.0, 400.0));

    for (final at in [200.0, 400.0, 450.0]) {
      expect(withSplitSegment([a, b], id, at, 'X', lap).error, contains('Split inside'));
    }
    expect(withSplitSegment([a, b], id, 300, ' ', lap).error, contains('new segment'));
    expect(withSplitSegment([a, b], 'missing', 300, 'X', lap).segments, isNull);
  });

  test('splits at and across the gate', () {
    final wrap = segment(TrackSegmentType.straight, 'Main straight', 900, 50);
    final a = segment(TrackSegmentType.corner, 'Turn 1', 50, 200);
    final id = wrap['id']! as String;
    final afterGate = withSplitSegment([a, wrap], id, 20, 'Main straight 2', lap).segments!;
    expect(validTrackSegments(afterGate), isTrue);
    expect((startOf(find(afterGate, id)), endOf(find(afterGate, id))), (900.0, 20.0));
    expect(afterGate.last['id'], id);
    expect(startOf(afterGate.first), 20);

    final atGate = withSplitSegment([a, wrap], id, lap, 'Main straight 2', lap).segments!;
    expect(validTrackSegments(atGate), isTrue);
    expect(endOf(find(atGate, id)), lap);
    expect((startOf(atGate.first), endOf(atGate.first)), (0.0, 50.0));
  });

  test('merges only segments that share a boundary', () {
    final a = segment(TrackSegmentType.corner, 'Turn 1', 100, 200);
    final b = segment(TrackSegmentType.straight, 'Back straight', 200, 400);
    final c = segment(TrackSegmentType.corner, 'Turn 2', 500, 600);
    final merged = withMergedSegments(
      [a, b, c],
      b['id']! as String,
      a['id']! as String,
      lap,
    ).segments!;
    expect(merged, hasLength(2));
    final result = find(merged, a['id']);
    expect((startOf(result), endOf(result)), (100.0, 400.0));
    expect(result['name'], 'Turn 1');
    expect(result['type'], 'sector');
    expect(find(merged, b['id']), isEmpty);

    expect(
      withMergedSegments([a, b, c], b['id']! as String, c['id']! as String, lap).error,
      contains('share a boundary'),
    );
    expect(
      withMergedSegments([a, b, c], a['id']! as String, a['id']! as String, lap).segments,
      isNull,
    );

    final before = segment(TrackSegmentType.straight, 'Main A', 900, lap);
    final after = segment(TrackSegmentType.straight, 'Main B', 0, 50);
    final across = withMergedSegments(
      [after, before],
      before['id']! as String,
      after['id']! as String,
      lap,
    ).segments!;
    expect(across, hasLength(1));
    expect(
      (startOf(across.first), endOf(across.first), across.first['type']),
      (900.0, 50.0, 'straight'),
    );

    final half1 = segment(TrackSegmentType.sector, 'S1', 0, 500);
    final half2 = segment(TrackSegmentType.sector, 'S2', 500, lap);
    expect(
      withMergedSegments([half1, half2], half1['id']! as String, half2['id']! as String, lap).error,
      contains('whole lap'),
    );
  });

  test('a split never exceeds the segment bound', () {
    final stored = [
      for (var i = 0; i < maximumTrackSegments; ++i)
        segment(TrackSegmentType.sector, 'S$i', i * 10.0, i * 10.0 + 10.0),
    ];
    expect(validTrackSegments(stored), isTrue);
    expect(
      withSplitSegment(stored, stored.first['id']! as String, 5, 'Extra', lap).error,
      contains('At most'),
    );
  });

  test('history undoes and redoes within its bound', () {
    final s0 = <Map<String, Object?>>[];
    final s1 = [segment(TrackSegmentType.corner, 'Turn 1', 100, 200)];
    final s2 = [s1.first, segment(TrackSegmentType.straight, 'Back', 200, 400)];
    final history = SegmentEditHistory(2);
    expect(history.nextUndo, isNull);
    history.record('run', s0, [...s0]);
    expect(history.nextUndo, isNull);
    history
      ..record('run', s0, s1)
      ..record('run', s1, s2);
    expect(history.nextUndo!.after, s2);
    history.commitUndo();
    expect(history.nextUndo!.before, s0);
    expect(history.nextRedo!.after, s2);
    history.commitRedo();
    expect(history.nextRedo, isNull);
    history
      ..commitUndo()
      ..record('run', s1, s0);
    expect(history.nextRedo, isNull);
    history.record('run', s0, s2);
    expect(history.undoCount, 2);
    history.clear();
    expect((history.nextUndo, history.nextRedo), (null, null));
  });

  test('picks progress but refuses ambiguous crossings', () {
    final trace = [
      for (var i = 0; i <= 100; ++i) ProgressMapPoint(i.toDouble(), i / 100, i / 100),
      for (var i = 0; i <= 100; ++i) ProgressMapPoint(100.0 + i, 1 - i / 100, i / 100),
    ];
    final picked = pickProgressAt(trace, 0.25, 0.26, 0.03, 0.01, 30, 200);
    expect(picked.progressMeters, closeTo(25, 1));
    expect(pickProgressAt(trace, 0.5, 0.5, 0.03, 0.01, 30, 200).reason, 'ambiguous');
    expect(pickProgressAt(trace, 0.9, 0.3, 0.03, 0.01, 30, 200).reason, 'farFromTrack');
    expect(pickProgressAt(const [], 0.5, 0.5, 0.03, 0.01, 30, 200).reason, 'noTrace');
  });

  test('proposals show as approved, superseded or rejected after edits', () {
    final proposals = [
      proposal(TrackSegmentType.straight, 'Straight 1', 0, 100),
      proposal(TrackSegmentType.corner, 'Corner 1', 100, 200),
      proposal(TrackSegmentType.straight, 'Straight 2', 200, 1000),
    ];
    final stored = proposalsToTrackSegments(
      TrackSegmentProposals(proposals: proposals, valid: true),
      reference,
      random: random,
    );
    var items = reviewSegmentProposals(
      proposals,
      {},
      {},
      approvedSegmentation(stored, reference),
      lap,
    );
    expect(items.map((item) => item.state), everyElement(SegmentReviewState.approved));
    expect(items[1].approvedSegmentId, stored[1]['id']);

    final moved = withEditedSegment(
      stored,
      stored[1]['id']! as String,
      'Corner 1',
      'corner',
      90,
      200,
      true,
      lap,
    ).segments!;
    items = reviewSegmentProposals(proposals, {}, {2}, approvedSegmentation(moved, reference), lap);
    expect(items.map((item) => item.state.label), ['superseded', 'superseded', 'approved']);

    final removed = withoutApprovedSegment(stored, stored[2]['id']! as String)!;
    items = reviewSegmentProposals(
      proposals,
      {},
      {2},
      approvedSegmentation(removed, reference),
      lap,
    );
    expect(items.last.state, SegmentReviewState.rejected);
  });

  test('rejections are stored per configuration and proposal algorithm', () {
    final proposals = [
      proposal(TrackSegmentType.straight, 'Straight 1', 0, 100),
      proposal(TrackSegmentType.corner, 'Corner 1', 100, 200),
    ];
    final review = makeTrackSegmentReview(reference, [proposals[1]]);
    expect(validTrackSegmentReview(review), isTrue);
    expect(review['version'], trackSegmentReviewAlgorithm);
    expect(rejectedProposalIndexes(review, reference, proposals), {1});
    expect(rejectedProposalIndexes(review, other, proposals), isEmpty);
    expect(
      rejectedProposalIndexes(
        {...review, 'proposalAlgorithm': 'track-segment-proposal-v1'},
        reference,
        proposals,
      ),
      isEmpty,
    );
    expect(validTrackSegmentReview(null), isTrue);
    expect(validTrackSegmentReview({...review, 'extra': 1}), isFalse);
  });

  test('stamps round-trip through JSON', () {
    final approved = approvedSegmentation([segment(TrackSegmentType.corner, 'T', 1, 2)], reference);
    final stamp = segmentationResultStamp(approved, 'theoretical-best');
    final back = segmentationResultStampFromJson(segmentationResultStampToJson(stamp))!;
    expect(segmentationResultCurrent(back, approved, 'theoretical-best'), isTrue);
    expect(segmentationResultStampFromJson({'revision': approved.revision}), isNull);
  });

  test('segments of other configurations are dropped only on request', () {
    final a = segment(TrackSegmentType.corner, 'Turn 1', 100, 200);
    final o = segment(TrackSegmentType.corner, 'Other', 300, 400, other);
    expect(withoutOtherConfigurations([a, o], reference), [a]);
    expect(withoutOtherConfigurations(null, reference), isEmpty);
  });
}
