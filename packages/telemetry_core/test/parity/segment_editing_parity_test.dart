// Compares the Dart port of segment editing and review
// (analysis/track_segment_editing.dart and the review states and decisions of
// track_segment_review.dart) with FlappedEar Overlays' C++ implementation.
//
// test/parity/segment_editing_reference.json is the output of
// tool/cpp_segment_editing_dump run over test/parity/corpus/*.vbo and
// test/fixtures/*.vbo (see tool/README.md). For each file it holds the
// automatic segments of the first reference-eligible lap with ids s0, s1, ...
// and every edit made on them; ids minted by a split are renamed n0, n1, ...
// in order of appearance, on both sides. Results, errors, states and indexes
// must match exactly; progress to 1e-9.
//
// FET_EDITING_REFERENCE and FET_EDITING_DIRS (colon-separated) run the same
// checks against another reference and its recordings, for local runs only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

var _maximumDifference = 0.0;

void main() {
  final referencePath =
      Platform.environment['FET_EDITING_REFERENCE'] ?? 'test/parity/segment_editing_reference.json';
  final directories =
      (Platform.environment['FET_EDITING_DIRS'] ?? 'test/parity/corpus:test/fixtures').split(':');
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final files = (reference['files'] as List).cast<Map<String, Object?>>();
  final cases = reference['cases'] as Map<String, Object?>;
  final configuration = cases['configuration'] as String;

  tearDownAll(() {
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      stdout.writeln('largest difference: $_maximumDifference');
    }
  });

  String pathOf(String name) => directories
      .map((directory) => '$directory/$name')
      .firstWhere((path) => File(path).existsSync());

  test('the reference has files', () => expect(files, isNotEmpty));

  for (final entry in files) {
    final name = entry['file'] as String;
    test(name, () {
      final session = parseVboFile(pathOf(name));
      final laps = deriveSourceLapSession(session);
      final lap = laps.timedLaps.firstWhere((lap) => lap.number == entry['lapNumber']);
      final review = computeSegmentReview(
        session,
        laps,
        lapNumber: lap.number,
        startTime: lap.startTelemetryTime,
        endTime: lap.endTelemetryTime,
        splitCornerChains: false, // Overlays' proposals, chains kept
      );
      final length = review.axis.lengthMeters;
      _close(length, entry['lengthMeters']);
      final proposals = review.proposals.proposals;
      final expectedProposals = (entry['proposals'] as List).cast<Map<String, Object?>>();
      expect(proposals.length, expectedProposals.length, reason: name);
      for (var i = 0; i < proposals.length; ++i) {
        expect(proposals[i].type.jsonName, expectedProposals[i]['type']);
        expect(proposals[i].name, expectedProposals[i]['name']);
        _close(proposals[i].start.progressMeters, expectedProposals[i]['start'], absolute: 1e-9);
        _close(proposals[i].end.progressMeters, expectedProposals[i]['end'], absolute: 1e-9);
      }

      // The Dart automatic approval, with the tool's ids.
      final approved = approveAllProposals(null, review, configuration, random: Random(1))!;
      final automatic = [
        for (var i = 0; i < approved.length; ++i) {...approved[i], 'id': 's$i'},
      ];
      _expectSegments(automatic, entry['automatic'], name);

      final edits = entry['edits'] as Map<String, Object?>;
      for (final item in (edits['single'] as List).cast<Map<String, Object?>>()) {
        final known = {for (final segment in automatic) segment['id'] as String};
        final (segments, error) = _apply(automatic, item, length);
        expect(error, item['error'], reason: '$name $item');
        _expectSegments(_normalized(segments, known, [0]), item['result'], '$name $item');
      }

      Object? state = automatic;
      final known = {for (final segment in automatic) segment['id'] as String};
      final counter = [0];
      for (final item in (edits['chain'] as List).cast<Map<String, Object?>>()) {
        final (segments, error) = _apply(state, item, length);
        expect(error, item['error'], reason: '$name chain $item');
        final result = _normalized(segments, known, counter);
        _expectSegments(result, item['result'], '$name chain $item');
        if (result != null) state = result;
      }

      final rejected = {proposals.length - 1};
      _expectItems(
        reviewSegmentProposals(
          proposals,
          {},
          rejected,
          approvedSegmentation(automatic, configuration),
          length,
        ),
        edits['reviewAutomatic'],
      );
      _expectItems(
        reviewSegmentProposals(
          proposals,
          {0},
          rejected,
          approvedSegmentation(state, configuration),
          length,
        ),
        edits['reviewEdited'],
      );
      final decisions = makeTrackSegmentReview(configuration, [proposals.first, proposals.last]);
      _expectJson(decisions, edits['decisions']);
      expect(
        rejectedProposalIndexes(decisions, configuration, proposals).toList()..sort(),
        edits['rejectedIndexes'],
      );
      expect(
        rejectedProposalIndexes(
          decisions,
          'compatibility-v1:${'fedcba9876543210' * 4}',
          proposals,
        ).length,
        edits['rejectedOther'],
      );
    });
  }

  test('editing cases', () {
    for (final item in (cases['editing'] as List).cast<Map<String, Object?>>()) {
      final stored = item['stored'];
      final (segments, error) = _apply(stored, item, _number(item['lengthMeters']));
      expect(error, item['error'], reason: '$item');
      final known = {
        if (stored is List)
          for (final segment in stored) (segment as Map<String, Object?>)['id'] as String,
      };
      _expectSegments(_normalized(segments, known, [0]), item['result'], '$item');
    }
  });

  test('validProposalEdit', () {
    for (final item in (cases['validProposalEdit'] as List).cast<Map<String, Object?>>()) {
      final error = proposalEditError(
        item['name'] as String,
        _number(item['start']),
        _number(item['end']),
        _number(item['lengthMeters']),
      );
      expect(error.isEmpty, item['valid'], reason: '$item');
      expect(error, item['error'], reason: '$item');
      expect(
        validProposalEdit(
          item['name'] as String,
          _number(item['start']),
          _number(item['end']),
          _number(item['lengthMeters']),
        ),
        item['valid'],
      );
    }
  });

  test('withoutOtherConfigurations', () {
    for (final item in (cases['withoutOtherConfigurations'] as List).cast<Map<String, Object?>>()) {
      expect(withoutOtherConfigurations(item['stored'], configuration), item['result']);
    }
  });

  test('validTrackSegmentReview', () {
    for (final item in (cases['validTrackSegmentReview'] as List).cast<Map<String, Object?>>()) {
      expect(validTrackSegmentReview(item['value']), item['valid'], reason: '${item['value']}');
    }
  });

  test('segmentation result stamps', () {
    for (final item in (cases['stamps'] as List).cast<Map<String, Object?>>()) {
      final stamp = segmentationResultStampFromJson(item['value']);
      expect(
        stamp == null ? null : segmentationResultStampToJson(stamp),
        item['stamp'],
        reason: '${item['value']}',
      );
    }
  });

  test('SegmentEditHistory', () {
    for (final item in (cases['history'] as List).cast<Map<String, Object?>>()) {
      final states = [
        for (final state in item['states'] as List)
          [for (final segment in state as List) segment as Map<String, Object?>],
      ];
      int index(List<Map<String, Object?>> value) =>
          states.indexWhere((state) => sameTrackSegments(state, value));
      final history = SegmentEditHistory(item['limit'] as int);
      for (final step in (item['steps'] as List).cast<Map<String, Object?>>()) {
        switch (step['op']) {
          case 'record':
            history.record('run', states[step['before'] as int], states[step['after'] as int]);
          case 'undo':
            history.commitUndo();
          case 'redo':
            history.commitRedo();
          default:
            history.clear();
        }
        expect(history.undoCount, step['undoCount'], reason: '$step');
        expect(history.redoCount, step['redoCount'], reason: '$step');
        final undo = history.nextUndo, redo = history.nextRedo;
        expect(undo == null ? null : [index(undo.before), index(undo.after)], step['nextUndo']);
        expect(redo == null ? null : [index(redo.before), index(redo.after)], step['nextRedo']);
      }
    }
  });

  test('pickProgressAt', () {
    final pick = cases['pick'] as Map<String, Object?>;
    final trace = [
      for (final point in (pick['trace'] as List).cast<List<Object?>>())
        ProgressMapPoint(_number(point[0]), _number(point[1]), _number(point[2])),
    ];
    for (final item in (pick['cases'] as List).cast<Map<String, Object?>>()) {
      final result = pickProgressAt(
        trace,
        _number(item['x']),
        _number(item['y']),
        _number(item['maximumDistance']),
        _number(item['ambiguityMargin']),
        _number(item['separationMeters']),
        _number(item['lengthMeters']),
      );
      expect(result.reason, item['reason'], reason: '$item');
      expect(result.progressMeters, item['progressMeters'], reason: '$item');
    }
    expect(pickProgressAt(const [], 0.5, 0.5, 0.03, 0.01, 30, 200).reason, pick['emptyReason']);
  });

  test('reviewSegmentProposals and decisions', () {
    for (final group in (cases['review'] as List).cast<Map<String, Object?>>()) {
      final proposals = [
        for (final item in (group['proposals'] as List).cast<Map<String, Object?>>())
          TrackSegmentProposal(
            type: trackSegmentTypeFromName(item['type'] as String)!,
            name: item['name'] as String,
            start: SegmentProposalBoundary(_number(item['start']), 7.0),
            end: SegmentProposalBoundary(_number(item['end']), 7.0),
          ),
      ];
      for (final item in (group['cases'] as List).cast<Map<String, Object?>>()) {
        _expectItems(
          reviewSegmentProposals(
            proposals,
            {...(item['edited'] as List).cast<int>()},
            {...(item['rejected'] as List).cast<int>()},
            approvedSegmentation(item['stored'], configuration),
            _number(item['lengthMeters']),
          ),
          item['items'],
        );
      }
      for (final item in (group['decisions'] as List).cast<Map<String, Object?>>()) {
        final review = makeTrackSegmentReview(configuration, [
          for (final index in (item['rejected'] as List).cast<int>()) proposals[index],
        ]);
        _expectJson(review, item['review']);
        expect(
          rejectedProposalIndexes(review, configuration, proposals).toList()..sort(),
          item['found'],
        );
      }
    }
  });
}

/// One edit of the reference applied to [stored].
(List<Map<String, Object?>>?, String) _apply(
  Object? stored,
  Map<String, Object?> args,
  double length,
) {
  final id = args['id'] as String;
  switch (args['op']) {
    case 'edit':
      final edit = withEditedSegment(
        stored,
        id,
        args['name'] as String,
        args['type'] as String,
        _number(args['start']),
        _number(args['end']),
        args['joined'] as bool,
        length,
      );
      return (edit.segments, edit.error);
    case 'split':
      final edit = withSplitSegment(
        stored,
        id,
        _number(args['at']),
        args['name'] as String,
        length,
      );
      return (edit.segments, edit.error);
    case 'merge':
      final edit = withMergedSegments(stored, id, args['other'] as String, length);
      return (edit.segments, edit.error);
    case 'remove':
      return (withoutApprovedSegment(stored, id), '');
  }
  throw StateError('unknown op ${args['op']}');
}

/// [segments] with each id not in [known] renamed n0, n1, ... from
/// [counter], as the tool does.
List<Map<String, Object?>>? _normalized(
  List<Map<String, Object?>>? segments,
  Set<String> known,
  List<int> counter,
) {
  if (segments == null) return null;
  return [
    for (final segment in segments)
      if (known.contains(segment['id']))
        segment
      else
        () {
          final renamed = 'n${counter[0]++}';
          known.add(renamed);
          return {...segment, 'id': renamed};
        }(),
  ];
}

void _expectSegments(List<Map<String, Object?>>? actual, Object? expected, String what) {
  if (expected == null) {
    expect(actual, isNull, reason: what);
    return;
  }
  final want = (expected as List).cast<Map<String, Object?>>();
  expect(actual, isNotNull, reason: what);
  expect(actual!.length, want.length, reason: what);
  expect(validTrackSegments(actual), isTrue, reason: what);
  for (var i = 0; i < actual.length; ++i) {
    expect(actual[i].keys.toSet(), want[i].keys.toSet(), reason: what);
    for (final key in ['id', 'type', 'name', 'trackConfigurationReference']) {
      expect(actual[i][key], want[i][key], reason: '$what $key');
    }
    for (final key in ['startProgressMeters', 'endProgressMeters']) {
      _close(_number(actual[i][key]), want[i][key], absolute: 1e-9);
    }
  }
}

void _expectItems(List<SegmentReviewItem> actual, Object? expected) {
  final want = (expected as List).cast<Map<String, Object?>>();
  expect(actual.length, want.length);
  for (var i = 0; i < actual.length; ++i) {
    expect(actual[i].state.label, want[i]['state'], reason: 'item $i');
    expect(actual[i].approvedSegmentId, want[i]['approvedSegmentId'], reason: 'item $i');
    expect(actual[i].edited, want[i]['edited'], reason: 'item $i');
  }
}

// Qt writes a whole double without a fraction; compare numbers by value.
void _expectJson(Object? actual, Object? expected) {
  if (actual is num && expected is num) {
    _close(actual.toDouble(), expected, absolute: 1e-9);
  } else if (actual is Map && expected is Map) {
    expect(actual.keys.toSet(), expected.keys.toSet());
    for (final key in actual.keys) {
      _expectJson(actual[key], expected[key]);
    }
  } else if (actual is List && expected is List) {
    expect(actual.length, expected.length);
    for (var i = 0; i < actual.length; ++i) {
      _expectJson(actual[i], expected[i]);
    }
  } else {
    expect(actual, expected);
  }
}

double _number(Object? value) => value == null ? double.nan : (value as num).toDouble();

void _close(double actual, Object? expected, {double absolute = 0.0}) {
  final value = _number(expected);
  final difference = (actual - value).abs();
  if (difference > _maximumDifference) _maximumDifference = difference;
  final tolerance = max(absolute, 1e-9 * value.abs());
  if (tolerance == 0.0) {
    expect(actual, value);
  } else {
    expect(actual, closeTo(value, tolerance));
  }
}
