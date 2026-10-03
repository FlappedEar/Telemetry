import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _configuration =
    'compatibility-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, Object?> _segment(String id, String type, double start, double end) => {
  'id': id,
  'type': type,
  'name': id.toUpperCase(),
  'startProgressMeters': start,
  'endProgressMeters': end,
  'trackConfigurationReference': _configuration,
};

// A lap at 100 m/s, `slow` times slower beyond 500 m.
List<ProgressSegment> _trace(double from, double slow) => [
  ProgressSegment([
    for (var i = 0; i < 200; ++i)
      ProjectedSample(
        from + 0.05 * i * (5.0 * i > 500 ? slow : 1.0),
        progressMeters: 5.0 * i,
        valid: true,
      ),
  ]),
];

void main() {
  final approved = approvedSegmentation([
    _segment('c1', 'corner', 0, 300),
    _segment('t1', 'straight', 300, 700),
    _segment('x1', 'sector', 700, 1000),
  ], _configuration);
  final other = approvedSegmentation([
    _segment('c1', 'corner', 0, 350),
    _segment('t1', 'straight', 350, 1000),
  ], _configuration);

  final laps = <(String, double, bool)>[
    ('a', 1.00, false),
    ('a', 1.02, false),
    ('a', 1.01, false),
    ('a', 1.00, true),
    ('b', 1.04, false),
    ('b', 1.03, false),
  ];
  final population = <TimedLapSectors>[];
  for (var i = 0; i < laps.length; ++i) {
    final (run, slow, useOther) = laps[i];
    final start = 10.0 + 20 * i;
    population.add(
      TimedLapSectors(
        computeLapSectorTimes(
          useOther ? other : approved,
          1000,
          _trace(start, slow),
          start,
          start + 10 * slow,
          '$run#$i',
        ),
        start,
      ),
    );
  }
  final computed = OutingTheoreticalBest(
    best: computeTheoreticalBest(approved, [for (final lap in population) lap.times]),
    actualBest: population.first.times,
    population: population,
    approved: approved,
    axisLengthMeters: 1000,
    runIds: [for (final lap in laps) lap.$1],
  );

  group('publishSectorProgression', () {
    final progression = publishSectorProgression(computed, const [
      ProgressionRunInfo(id: 'b', name: 'Run B', conditions: 'Damp'),
      ProgressionRunInfo(id: 'z', name: 'Run Z'),
      ProgressionRunInfo(id: 'a', name: 'Run A'),
    ]);

    test('lists runs with laps in the given order', () {
      expect([for (final session in progression.sessions) session.runId], ['b', 'a']);
      expect(progression.sessions.first.run.conditions, 'Damp');
      expect(progression.sessions.first.laps.available, isFalse);
      // Every lap of the run counts for its lap times, whatever its segments.
      expect(progression.sessions.last.laps.count, 4);
    });

    test('orders sections along the track and needs three laps for statistics', () {
      expect([for (final row in progression.segments) row.segmentId], ['c1', 't1', 'x1']);
      final straight = progression.segments[1];
      expect(straight.name, 'T1');
      expect(straight.type, 'straight');
      final [b, a] = straight.cells;
      expect(b.summary.available, isFalse);
      expect(b.summary.count, 2);
      expect(b.laps.length, 2);
      // The lap timed against other segments is left out.
      expect(a.summary.count, 3);
      expect(a.summary.median, a.laps[1].seconds);
      expect([for (final lap in a.laps) lap.reference], ['a#0', 'a#2', 'a#1']);
      expect(straight.fastestTypical, a.summary.median);
    });

    test('is empty without runs', () {
      final none = publishSectorProgression(computed, const []);
      expect(none.sessions, isEmpty);
      expect(none.segments.every((row) => row.cells.isEmpty && row.fastestTypical == null), isTrue);
    });
  });

  group('publishTimeLossRanking', () {
    test('ranks every lap against the best lap with corner names', () {
      final summary = publishTimeLossRanking(computed, allLaps: true);
      expect(summary.available, isTrue);
      expect(summary.allLaps, isTrue);
      expect(summary.referenceLap, 'a#0');
      expect(summary.revision, approved.revision);
      expect(summary.losses, isNotEmpty);
      for (final loss in summary.losses) {
        expect(loss.lossSeconds, greaterThan(0));
        expect(loss.lapReference, isNot('a#0'));
        expect(loss.cornerName, loss.window.role == timeLossRoleContinuation ? 'C1' : '');
      }
      final comparison = compareTimeLoss(computed, summary.losses.first);
      expect(comparison.referenceLap, 'a#0');
      expect(comparison.differenceSeconds, closeTo(summary.losses.first.lossSeconds, 1e-9));
    });

    test('compares only each run\'s best lap by default', () {
      final summary = publishTimeLossRanking(computed);
      expect(summary.allLaps, isFalse);
      // Run a's best is the reference itself.
      expect(summary.comparedLapCount, 1);
      expect({for (final loss in summary.losses) loss.lapReference}, {'b#5'});
    });

    test('is unavailable without a timed best lap', () {
      final summary = publishTimeLossRanking(
        OutingTheoreticalBest(population: population, approved: approved, runIds: ['a']),
      );
      expect(summary.available, isFalse);
      expect(summary.message, timeLossBestLapUntimedMessage);
      expect(summary.losses, isEmpty);
    });
  });

  test('a comparison misses a time the lap did not cover', () {
    const comparison = TimeLossComparison(lapReference: 'x', referenceLap: 'y', lapSeconds: 3.0);
    expect(comparison.differenceSeconds, isNull);
  });
}
