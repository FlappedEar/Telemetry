import 'dart:math';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';
const _otherGroup =
    'compatibility-v1:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

// A lap at [straight] m/s, slowed to [slow] m/s over [from, to] metres.
double Function(double) _lap(double straight, [double from = 0, double to = 0, double slow = 0]) =>
    (d) => d >= from && d <= to ? slow : straight;

DayRunInput _run(String id, TelemetrySession session) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
  session: session,
  laps: deriveSourceLapSession(session),
);

void main() {
  // Every lap loses time somewhere else, so the theoretical best takes
  // segments from several laps.
  final runs = [
    _run(
      'run1',
      rectangleSession([_lap(30, 50, 120, 20), _lap(31, 300, 400, 25), _lap(30, 550, 650, 22)]),
    ),
    _run('run2', rectangleSession([_lap(29, 0, 0, 0), _lap(30.5, 700, 780, 20)])),
  ];
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  final analysis = analyzeDay(runs);
  final shown = analysis.chosenGroup!;

  group('a day with segments proposed from its best lap', () {
    final result = dayTheoreticalBest(analysis, outing, random: Random(1));

    test('times every eligible lap and finds the time available', () {
      expect(result.state, DayTheoreticalBestState.ready);
      expect(result.message, isEmpty);
      expect(result.automaticSegments, isTrue);
      expect(result.groupId, shown.id);
      expect(result.laps.length, shown.eligibleLapCount);
      expect(result.bestLap!.reference, shown.ranking!.bestOfDay!.reference);
      expect(result.segments.length, 8);
      expect(result.segments.map((s) => s.type).toSet(), {'corner', 'straight'});
      final total = result.segments.fold(0.0, (sum, s) => sum + s.seconds!);
      expect(result.theoreticalBestSeconds, closeTo(total, 1e-9));
      expect(result.bestLapSeconds, result.bestLap!.durationSeconds);
      expect(
        result.availableSeconds,
        closeTo(result.bestLapSeconds! - result.theoreticalBestSeconds!, 1e-9),
      );
      expect(result.availableSeconds, greaterThan(0.1));
      // Several laps contribute a fastest segment.
      expect(result.segments.map((s) => s.sourceLapReference).toSet().length, greaterThan(1));
    });

    test('maps a lap between its time and the shared axis', () {
      final lap = result.laps.first.lap;
      final time = result.timeAt(lap, 300)!;
      expect(time, inInclusiveRange(lap.start, lap.end));
      expect(result.progressAt(lap, time), closeTo(300, 1e-6));
      expect(result.timeAt(lap, result.axisLengthMeters * 3), isNull);
    });

    test('gives each lap its loss to the fastest time of every segment', () {
      for (var i = 0; i < result.segments.length; ++i) {
        final losses = [for (final lap in result.laps) lap.lossSeconds[i]!];
        expect(losses.reduce(min), closeTo(0, 1e-12));
        expect(losses.every((loss) => loss >= 0), isTrue);
      }
      final best = result.laps.singleWhere((lap) => lap.bestOfDay);
      expect(best.lap.reference, result.bestLap!.reference);
      expect(best.totalLossSeconds, closeTo(result.availableSeconds!, 1e-9));
      for (final lap in result.laps) {
        expect(lap.times.completePartition, isTrue);
        expect(lap.times.partitionErrorSeconds, lessThan(sectorSumToleranceSeconds));
        expect(
          lap.totalLossSeconds,
          closeTo(lap.lap.durationSeconds - result.theoreticalBestSeconds!, 1e-9),
        );
      }
      // Recording order.
      expect(result.laps.map((lap) => lap.lap.displayName).toList(), [
        'Session 1 · LAP 1',
        'Session 1 · LAP 2',
        'Session 1 · LAP 3',
        'Session 2 · LAP 1',
        'Session 2 · LAP 2',
      ]);
    });

    test('places a lap\'s fixes in their segments', () {
      final best = result.bestLap!;
      final wrapping = result.segments.indexWhere(
        (s) => s.endProgressMeters < s.startProgressMeters,
      );
      expect(wrapping, 7);
      expect(result.segmentAt(0), wrapping);
      expect(result.segmentAt(result.computed!.axisLengthMeters - 1), wrapping);
      final middle =
          (result.segments[1].startProgressMeters + result.segments[1].endProgressMeters) / 2;
      expect(result.segmentAt(middle), 1);
      expect(result.segmentAtTime(best, best.start + 0.2), wrapping);
      expect(result.segmentAtTime(best, (best.start + best.end) / 2), isNotNull);
      expect(result.segmentAtTime(best, best.end + 100), isNull);
    });

    test('ranks the largest losses against the best lap', () {
      final runBests = result.timeLosses();
      expect(runBests.valid, isTrue);
      expect(runBests.referenceLap, result.bestLap!.reference);
      expect(runBests.comparedLapCount, 1); // the other session's best
      final all = result.timeLosses(allLaps: true);
      expect(all.comparedLapCount, 4);
      expect(all.losses, isNotEmpty);
      for (var i = 1; i < all.losses.length; ++i) {
        expect(all.losses[i].lossSeconds, lessThanOrEqualTo(all.losses[i - 1].lossSeconds));
      }
    });

    test('is computed for every resolved group', () {
      final all = dayTheoreticalBests(analysis, outing, random: Random(1));
      expect(all.keys, [shown.id]);
      expect(all[shown.id]!.theoreticalBestSeconds, result.theoreticalBestSeconds);
    });
  });

  test('uses the document\'s segments, from the first run by id', () {
    final best = shown.ranking!.bestOfDay!;
    final proposed = automaticTrackSegments(
      documentRuns: const [],
      groupId: shown.id,
      storedSegments: null,
      session: outing[best.runId]!.session,
      laps: outing[best.runId]!.laps,
      lapNumber: best.lapNumber,
      startTime: best.start,
      endTime: best.end,
      random: Random(3),
    )!;
    // Only the first four segments, stored in the second run.
    final partial = proposed.sublist(0, 4);
    final result = dayTheoreticalBest(
      analysis,
      outing,
      documentRuns: [
        {'id': 'run1'},
        {'id': 'run2', 'trackSegments': partial},
      ],
    );
    expect(result.automaticSegments, isFalse);
    expect(result.computed!.canonicalRunId, 'run2');
    expect(result.segments.map((s) => s.segmentId), [for (final s in partial) s['id']]);
    expect(result.summary!.actualBest!.coversWholeLap, isFalse);
    expect(result.bestLapSeconds, result.summary!.actualBest!.sectorSumSeconds);
    expect(result.bestLapSeconds, lessThan(best.durationSeconds));

    final both = dayTheoreticalBest(
      analysis,
      outing,
      documentRuns: [
        {'id': 'run2', 'trackSegments': partial},
        {'id': 'run1', 'trackSegments': proposed},
      ],
    );
    expect(both.computed!.canonicalRunId, 'run1');
    expect(both.segments.length, 8);
    expect(fet.validTrackSegments(proposed), isTrue);
  });

  test('says why there is no theoretical best', () {
    expect(
      dayTheoreticalBest(analysis, outing, groupId: 'unresolved:run1').message,
      'Confirm a compatible track configuration before calculating a theoretical best.',
    );
    final excluded = analyzeDay(
      runs,
      exclusions: {for (final lap in shown.ranking!.eligibleLaps) lap.reference: 'test'},
    );
    final none = dayTheoreticalBest(excluded, outing);
    expect(none.state, DayTheoreticalBestState.unavailable);
    expect(none.message, 'No eligible laps in this group to calculate a theoretical best from.');
    // Segments of another configuration in the best lap's run block the
    // automatic ones, as in Overlays.
    final best = shown.ranking!.bestOfDay!;
    final blocked = dayTheoreticalBest(
      analysis,
      outing,
      documentRuns: [
        {
          'id': best.runId,
          'trackSegments': [
            fet.makeTrackSegment(fet.TrackSegmentType.corner, 'Old', 10, 20, _otherGroup),
          ],
        },
      ],
    );
    expect(blocked.state, DayTheoreticalBestState.unavailable);
    expect(blocked.message, startsWith('No run in this group has an approved segment review yet.'));
    // A recording that is not available leaves the axis unbuilt.
    final missing = dayTheoreticalBest(analysis, const {});
    expect(missing.state, DayTheoreticalBestState.unavailable);
  });
}
