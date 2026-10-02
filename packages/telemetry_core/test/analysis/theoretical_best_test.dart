import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _group = 'compatibility-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _otherGroup =
    'compatibility-v1:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

Map<String, Object?> _segment(String id, String type, double start, double end) => {
  'id': id,
  'type': type,
  'name': id.toUpperCase(),
  'startProgressMeters': start,
  'endProgressMeters': end,
  'trackConfigurationReference': _group,
};

ApprovedSegmentation _approved(List<Map<String, Object?>> segments) =>
    approvedSegmentation(segments, _group);

/// A lap of a 1000 m axis from [start] at [speed] m/s, sampled every 0.05 s
/// from progress [from] to [to], without the samples inside [gaps].
List<ProgressSegment> _lap(
  double start, {
  double speed = 100,
  double from = 3,
  double to = 997,
  List<(double, double)> gaps = const [],
}) {
  final result = <ProgressSegment>[];
  var current = <ProjectedSample>[];
  for (var i = 0; ; ++i) {
    final progress = from + speed * 0.05 * i;
    if (progress > to) break;
    if (gaps.any((gap) => progress > gap.$1 && progress < gap.$2)) {
      if (current.isNotEmpty) result.add(ProgressSegment(current));
      current = [];
      continue;
    }
    current.add(
      ProjectedSample(
        start + (progress - from) / speed + from / speed,
        progressMeters: progress,
        valid: true,
      ),
    );
  }
  if (current.isNotEmpty) result.add(ProgressSegment(current));
  return result;
}

final _partition = _approved([
  _segment('c1', 'corner', 0, 300),
  _segment('t1', 'straight', 300, 700),
  _segment('x1', 'sector', 700, 1000),
]);

LapSectorTimes _times(
  ApprovedSegmentation approved,
  List<ProgressSegment> lap,
  double start,
  Object reference, {
  double seconds = 10,
}) => computeLapSectorTimes(approved, 1000, lap, start, start + seconds, reference);

void main() {
  group('computeLapSectorTimes', () {
    test('times a complete partition from gate to gate', () {
      final times = _times(_partition, _lap(10), 10, 'a');
      expect(times.valid, isTrue);
      expect(times.stamp.calculationAlgorithm, sectorTimingAlgorithm);
      expect(times.stamp.revision, _partition.revision);
      expect(times.completePartition, isTrue);
      expect(
        [for (final s in times.sectors) s.seconds],
        [closeTo(3, 1e-9), closeTo(4, 1e-9), closeTo(3, 1e-9)],
      );
      expect(times.sectors.first.startTime, 10); // the lap's own start
      expect(times.sectors.last.endTime, 20);
      expect(times.sumSeconds, closeTo(10, 1e-9));
      expect(times.partitionErrorSeconds, closeTo(0, 1e-9));
      expect(times.sectors[1].coveredMeters, closeTo(400, 1e-9));
    });

    test('needs coverage up to the gate tolerance and through each boundary', () {
      final late = _times(_partition, _lap(10, from: 14), 10, 'a');
      expect(late.sectors.first.seconds, isNotNull);
      final later = _times(_partition, _lap(10, from: 16), 10, 'a');
      expect(later.sectors.first.seconds, isNull);
      expect(later.sectors.first.unavailableReason, sectorIncompleteCoverage);
      expect(later.sumSeconds, isNull);
      expect(later.completePartition, isTrue);
      final gap = _times(_partition, _lap(10, gaps: [(290, 310)]), 10, 'a');
      expect(gap.sectors[0].seconds, isNull);
      expect(gap.sectors[1].seconds, isNull);
      expect(gap.sectors[2].seconds, isNotNull);
    });

    test('times a segment across the gate within the lap', () {
      final wrapped = _approved([
        _segment('c1', 'corner', 100, 400),
        _segment('t1', 'straight', 400, 800),
        _segment('x1', 'sector', 800, 100),
      ]);
      final times = _times(wrapped, _lap(10), 10, 'a');
      expect(times.completePartition, isTrue);
      expect(times.sectors.last.seconds, closeTo(3, 1e-9)); // 2 s after 800 m + 1 s before 100 m
      expect(times.sectors.last.lengthMeters, 300);
      expect(times.sumSeconds, closeTo(10, 1e-9));
      final gap = _times(wrapped, _lap(10, gaps: [(40, 60)]), 10, 'a');
      expect(gap.sectors.last.seconds, isNull);
    });

    test('reports segments that do not tile the lap', () {
      final gapped = _approved([
        _segment('c1', 'corner', 0, 300),
        _segment('t1', 'straight', 400, 1000),
      ]);
      final times = _times(gapped, _lap(10), 10, 'a');
      expect(times.completePartition, isFalse);
      expect(times.sumSeconds, isNull);
      expect(times.sectors.every((s) => s.seconds != null), isTrue);
    });

    test('refuses invalid input', () {
      expect(computeLapSectorTimes(_partition, 0, _lap(10), 10, 20, 'a').valid, isFalse);
      expect(computeLapSectorTimes(_partition, 1000, _lap(10), 20, 20, 'a').valid, isFalse);
      expect(
        computeLapSectorTimes(approvedSegmentation('x', _group), 1000, _lap(10), 10, 20, 'a').valid,
        isFalse,
      );
      expect(projectedCoverageMeters(_lap(10), 250, 520, 1000), closeTo(270, 1e-9));
      expect(projectedCoverageMeters(_lap(10), 520, 250, 1000), 0);
    });
  });

  test('compareSectorTimes needs the same revision and the segment', () {
    final a = _times(_partition, _lap(10), 10, 'a');
    final b = _times(_partition, _lap(30, speed: 50, from: 1.5, to: 999), 30, 'b', seconds: 20);
    expect(compareSectorTimes(a, b, 't1').secondsDelta, closeTo(-4, 1e-9));
    expect(compareSectorTimes(a, b, 'none').unavailableReason, sectorTimeSegmentNotFound);
    final other = _times(_approved([_segment('t1', 'straight', 300, 700)]), _lap(10), 10, 'c');
    expect(
      compareSectorTimes(a, other, 't1').unavailableReason,
      sectorTimeDifferentSegmentOrRevision,
    );
  });

  group('computeTheoreticalBest', () {
    test('takes each segment\'s fastest time and its lap; the first wins a tie', () {
      final fast = _times(_partition, _lap(10), 10, 'fast');
      final slow = _times(
        _partition,
        _lap(30, speed: 50, from: 1.5, to: 999),
        30,
        'slow',
        seconds: 20,
      );
      final tie = _times(_partition, _lap(10), 10, 'tie');
      final best = computeTheoreticalBest(_partition, [slow, fast, tie]);
      expect(best.valid, isTrue);
      expect(best.stamp.calculationAlgorithm, theoreticalBestAlgorithm);
      expect(best.totalSeconds, closeTo(10, 1e-9));
      expect(best.sectors.map((s) => s.sourceLapReference), ['fast', 'fast', 'fast']);
    });

    test('ignores other revisions and withholds an incomplete total', () {
      final other = _times(_approved([_segment('c1', 'corner', 0, 300)]), _lap(10), 10, 'other');
      final gap = _times(_partition, _lap(10, gaps: [(400, 420)]), 10, 'gap');
      final best = computeTheoreticalBest(_partition, [other, gap]);
      expect(best.totalSeconds, isNull);
      expect(best.unavailableReason, theoreticalBestIncompleteCoverage);
      expect(best.sectors[1].unavailableReason, theoreticalBestIncompleteCoverage);
      expect(best.sectors[0].sourceLapReference, 'gap');
      final none = computeTheoreticalBest(_approved([]), [gap]);
      expect(none.valid, isFalse);
      expect(none.unavailableReason, theoreticalBestNoApprovedSegmentation);
      expect(
        theoreticalBestReasonText(none.unavailableReason),
        'No approved segments to measure sectors against.',
      );
    });
  });

  group('time loss', () {
    final approved = _approved([
      _segment('t0', 'straight', 0, 200),
      _segment('c1', 'corner', 200, 300),
      _segment('t1', 'straight', 300.4, 700),
      _segment('x1', 'sector', 700, 900),
      _segment('c2', 'corner', 900, 1000),
    ]);

    test('marks a straight after a corner as its continuation, across the gate too', () {
      final a = _times(approved, _lap(10, speed: 50, from: 1.5, to: 999), 10, 'a', seconds: 20);
      final b = _times(approved, _lap(30), 30, 'b');
      final observations = computeTimeLossObservations(approved, 1000, a, 10, b, 30);
      expect(observations.valid, isTrue);
      expect(observations.windows.map((w) => w.role), [
        timeLossRoleContinuation,
        timeLossRoleCorner,
        timeLossRoleContinuation,
        timeLossRoleSector,
        timeLossRoleCorner,
      ]);
      expect(observations.windows.first.cornerSegmentId, 'c2');
      expect(observations.windows[2].cornerSegmentId, 'c1');
      expect(observations.windows[1].incrementSeconds, closeTo(1, 1e-9));
      expect(observations.windows[1].cumulativeAtEndSeconds, closeTo(3, 1e-9));
      expect(observations.allWindowsTimed, isTrue); // the 0.4 m hole is no window
      expect(
        computeTimeLossObservations(_partition, 1000, a, 10, b, 30).unavailableReason,
        timeLossDifferentSegmentOrRevision,
      );
    });

    test('ranks positive increments, largest first, without the reference', () {
      final reference = TimedLapSectors(_times(approved, _lap(30), 30, 'ref'), 30);
      final slow = TimedLapSectors(
        _times(approved, _lap(10, speed: 50, from: 1.5, to: 999), 10, 'slow', seconds: 20),
        10,
      );
      final gap = TimedLapSectors(_times(approved, _lap(50, gaps: [(750, 760)]), 50, 'gap'), 50);
      final ranking = rankTimeLosses(
        approved,
        1000,
        [reference, slow, gap],
        reference,
        maximumResults: 2,
      );
      expect(ranking.valid, isTrue);
      expect(ranking.comparedLapCount, 2);
      expect(ranking.untimedWindowCount, 1);
      expect(ranking.observationCount, 5);
      expect(ranking.losses.length, 2);
      expect(ranking.losses.first.window.segmentId, 't1');
      expect(ranking.losses[1].lossSeconds, closeTo(2, 1e-9));
      expect(ranking.losses.first.lossSeconds, closeTo(4 - 0.004, 1e-9));
      expect(ranking.losses.first.coverageLap, 1);
      expect(
        rankTimeLosses(approved, 1000, [
          slow,
        ], TimedLapSectors(LapSectorTimes(lapReference: null), 0)).unavailableReason,
        timeLossNoReference,
      );
    });
  });

  group('consistency', () {
    test('interpolates quartiles and needs three finite samples', () {
      final summary = summarizeConsistency([4, 1, double.nan, 3, 2]);
      expect(summary.available, isTrue);
      expect(summary.count, 4);
      expect(
        [summary.minimum, summary.q1, summary.median, summary.q3, summary.maximum],
        [1, 1.75, 2.5, 3.25, 4],
      );
      expect(summary.interquartileRange, 1.5);
      final few = summarizeConsistency([1, 2]);
      expect(few.available, isFalse);
      expect(few.unavailableReason, consistencyTooFewSamples);
    });

    test('per segment across a population', () {
      final population = [
        for (var i = 0; i < 3; ++i)
          TimedLapSectors(
            _times(_partition, _lap(10.0 + 20 * i, speed: 100 - 10.0 * i), 10.0 + 20 * i, 'l$i'),
            10.0 + 20 * i,
          ),
      ];
      final sectors = computeSectorConsistency(_partition, population);
      expect(sectors.map((s) => s.segmentId), ['c1', 't1', 'x1']);
      expect(sectors[1].summary.count, 3);
      expect(sectors[1].summary.median, closeTo(400 / 90, 1e-9));
      expect(sectors[1].lapReferences, ['l0', 'l1', 'l2']);
    });
  });

  test('canonicalSegmentation picks the first run by id with segments for the group', () {
    final stored = {
      'b': [_segment('s', 'corner', 0, 10)],
      'a': [
        {..._segment('o', 'corner', 0, 10), 'trackConfigurationReference': _otherGroup},
      ],
      'c': [_segment('s', 'corner', 0, 20)],
    };
    final canonical = canonicalSegmentation(['c', 'b', 'a', 'b'], (id) => stored[id], _group);
    expect(canonical!.runId, 'b');
    expect(canonical.approved.segments.single['endProgressMeters'], 10);
    expect(canonicalSegmentation(['a'], (id) => stored[id], _group), isNull);
  });
}
