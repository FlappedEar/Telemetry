// Measuring the day's kept segments again on a new best lap they cannot time
// (FET-170, day/day_segment_remeasure.dart). Session 1 gives the day its
// automatic segments, which are kept; Session 2's laps are faster and run
// 25 m off Session 1's line on the left straight, beyond the projection's
// 20 m proximity, so the kept segments cannot time them there (12 m was
// enough before FET-257 kept laps a few metres off the line).
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';

DayRunInput _run(String id, TelemetrySession session) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
  session: session,
  laps: deriveSourceLapSession(session),
);

/// Off the line by [meters] in the middle of the left straight, eased in
/// and out.
double Function(double) _offLine(double meters) => (distance) {
  const from = 385.0, to = 465.0, ease = 25.0;
  if (distance <= from || distance >= to) return 0.0;
  final edge = math.min(distance - from, to - distance);
  if (edge >= ease) return meters;
  final x = edge / ease;
  return meters * x * x * (3 - 2 * x);
};

void main() {
  final first = _run('run1', rectangleSession([(_) => 30, (_) => 30.5, (_) => 30]));
  final second = _run(
    'run2',
    rectangleSession(
      [(_) => 33, (_) => 33.5, (_) => 33],
      westShifts: [_offLine(25), _offLine(25), _offLine(25)],
    ),
  );
  final outing = {
    for (final run in [first, second]) run.runId: OutingRun(run.session, run.laps),
  };
  final firstDay = analyzeDay([first]);
  final day = analyzeDay([first, second]);

  /// Session 1's automatic segments, kept as the day keeps them when a
  /// session is added; [change] edits them first.
  DaySegmentEdits kept([void Function(DaySegmentEdits, DayTheoreticalBest)? change]) {
    final edits = DaySegmentEdits(random: math.Random(1));
    var result = dayTheoreticalBest(firstDay, outing, random: math.Random(2));
    expect(result.automaticSegments, isTrue);
    expect(edits.keepAutomatic(result), isTrue);
    if (change != null) {
      result = dayTheoreticalBest(firstDay, outing, documentRuns: edits.applyTo(const []));
      change(edits, result);
    }
    return edits;
  }

  DayTheoreticalBest withSecond(DaySegmentEdits edits) =>
      dayTheoreticalBest(day, outing, documentRuns: edits.applyTo(const []));

  test('the fixture: the kept segments cannot time the new best lap', () {
    expect(day.groups.where((group) => group.resolved), hasLength(1));
    expect(day.ranking!.bestOfDay!.runId, 'run2');
    final result = withSecond(kept());
    expect(result.state, DayTheoreticalBestState.ready);
    expect(result.segmentRunId, 'run1');
    expect(bestLapHasUntimedSegment(result), isTrue);
  });

  test('measures them again on the best lap, which they then time', () {
    final edits = kept();
    final before = withSecond(edits);
    final after = remeasureDaySegments(
      day,
      outing,
      before,
      documentRuns: edits.applyTo(const []),
      random: math.Random(3),
    )!;
    expect(after.state, DayTheoreticalBestState.ready);
    expect(after.segmentRunId, 'run2');
    expect(after.automaticSegments, isFalse, reason: 'approved, as kept');
    expect(bestLapHasUntimedSegment(after), isFalse);
    expect(after.theoreticalBestSeconds, lessThanOrEqualTo(after.bestLapSeconds!));
    // Session 1 keeps no segments of the group; Session 2 has them.
    expect(after.remeasuredRuns['run1'], isEmpty);
    expect(after.remeasuredRuns['run2'], after.runSegments);

    // Kept as approved, the day gives the same result again, as opened.
    edits.adoptRemeasured(after.remeasuredRuns);
    expect(edits.canUndo, isFalse);
    final again = withSecond(edits);
    expect(again.automaticSegments, isFalse);
    expect(again.segmentRunId, 'run2');
    expect(again.theoreticalBestSeconds, after.theoreticalBestSeconds);
    expect(
      remeasureDaySegments(day, outing, again, documentRuns: edits.applyTo(const [])),
      isNull,
      reason: 'the best lap is timed now',
    );
  });

  // A run stores the segments of one configuration only (approveAllProposals).
  test("does nothing when the best lap's session has another group's segments", () {
    final edits = kept();
    final other = {
      'id': 'other-corner',
      'type': 'corner',
      'name': 'Elsewhere',
      'startProgressMeters': 10.0,
      'endProgressMeters': 20.0,
      'trackConfigurationReference': 'compatibility-v1:${'b' * 64}',
    };
    final documentRuns = [
      for (final run in edits.applyTo(const []))
        if (run case {'id': 'run2'})
          {
            ...run,
            'trackSegments': [...(run['trackSegments'] as List? ?? const []), other],
          }
        else
          run,
      if (!edits.applyTo(const []).any((run) => (run as Map)['id'] == 'run2'))
        {
          'id': 'run2',
          'trackSegments': [other],
        },
    ];
    final before = dayTheoreticalBest(day, outing, documentRuns: documentRuns);
    expect(bestLapHasUntimedSegment(before), isTrue);
    expect(remeasureDaySegments(day, outing, before, documentRuns: documentRuns), isNull);
  });

  test('keeps the names the driver gave', () {
    final edits = kept((edits, result) {
      final corner = result.runSegments.firstWhere((segment) => segment['type'] == 'corner');
      expect(
        edits.edit(
          result,
          corner['id']! as String,
          name: 'Hairpin',
          type: 'corner',
          startMeters: corner['startProgressMeters']! as double,
          endMeters: corner['endProgressMeters']! as double,
        ),
        isEmpty,
      );
    });
    final before = withSecond(edits);
    expect(before.runSegments.map((segment) => segment['name']), contains('Hairpin'));
    final after = remeasureDaySegments(day, outing, before, documentRuns: edits.applyTo(const []))!;
    expect(after.runSegments.where((segment) => segment['name'] == 'Hairpin'), hasLength(1));
    expect(after.segments.map((segment) => segment.name), contains('Hairpin'));
    expect(bestLapHasUntimedSegment(after), isFalse);
  });

  test('leaves segments the driver moved as they are', () {
    final edits = kept((edits, result) {
      final corner = result.runSegments.firstWhere((segment) => segment['type'] == 'corner');
      expect(
        edits.edit(
          result,
          corner['id']! as String,
          name: corner['name']! as String,
          type: 'corner',
          startMeters: (corner['startProgressMeters']! as double) - 5,
          endMeters: corner['endProgressMeters']! as double,
        ),
        isEmpty,
      );
    });
    final before = withSecond(edits);
    expect(bestLapHasUntimedSegment(before), isTrue);
    expect(
      remeasureDaySegments(day, outing, before, documentRuns: edits.applyTo(const [])),
      isNull,
    );
  });

  test('a best lap 12 m off the line on the straight is timed by the kept segments, at the '
      'times it has on the line', () {
    // Since FET-257 the projection keeps a fix 12 m off a straight with no
    // other part of the track near it, so the kept segments time such a lap
    // and nothing is measured again.
    DayRunInput faster(String id, double meters) => _run(
      id,
      rectangleSession(
        [(_) => 33, (_) => 33.5, (_) => 33],
        westShifts: [_offLine(meters), _offLine(meters), _offLine(meters)],
      ),
    );
    final off = faster('run3', 12.0), on = faster('run4', 0.0);
    final runs = {
      for (final run in [first, off, on]) run.runId: OutingRun(run.session, run.laps),
    };
    List<double?> bestLapSectors(DayRunInput run) {
      final day = analyzeDay([first, run]);
      expect(day.groups.where((group) => group.resolved), hasLength(1));
      expect(day.ranking!.bestOfDay!.runId, run.runId);
      final edits = kept();
      final result = dayTheoreticalBest(day, runs, documentRuns: edits.applyTo(const []));
      expect(result.state, DayTheoreticalBestState.ready);
      expect(result.segmentRunId, 'run1');
      expect(bestLapHasUntimedSegment(result), isFalse);
      expect(
        remeasureDaySegments(day, runs, result, documentRuns: edits.applyTo(const [])),
        isNull,
      );
      final best = result.laps.singleWhere((lap) => lap.bestOfDay);
      return [for (final sector in best.times.sectors) sector.seconds];
    }

    final offLine = bestLapSectors(off), onLine = bestLapSectors(on);
    expect(offLine, hasLength(onLine.length));
    for (var i = 0; i < onLine.length; ++i) {
      expect(offLine[i], closeTo(onLine[i]!, 0.02), reason: 'segment $i');
    }
  });

  test('does nothing while the best lap is timed', () {
    final edits = kept();
    final result = dayTheoreticalBest(firstDay, outing, documentRuns: edits.applyTo(const []));
    expect(bestLapHasUntimedSegment(result), isFalse);
    expect(
      remeasureDaySegments(firstDay, outing, result, documentRuns: edits.applyTo(const [])),
      isNull,
    );
  });
}
