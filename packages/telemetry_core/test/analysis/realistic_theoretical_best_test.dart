import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _group = 'compatibility-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, Object?> _segment(String id, double start, double end) => {
  'id': id,
  'type': 'sector',
  'name': id.toUpperCase(),
  'startProgressMeters': start,
  'endProgressMeters': end,
  'trackConfigurationReference': _group,
};

// Three segments that meet: 0–300, 300–700, 700–1000 m.
final _approved = approvedSegmentation([
  _segment('a', 0, 300),
  _segment('b', 300, 700),
  _segment('c', 700, 1000),
], _group);

// Three segments with a gap between the first two.
final _apart = approvedSegmentation([
  _segment('a', 0, 300),
  _segment('b', 320, 700),
  _segment('c', 700, 1000),
], _group);

/// A lap through [approved]'s segments in [seconds], with [entry] and [exit]
/// speeds (m/s) at each one's start and end.
RealisticLapInput _lap(
  Object reference,
  List<double?> seconds, {
  required List<double?> entry,
  required List<double?> exit,
  ApprovedSegmentation? approved,
  String? revision,
}) {
  final on = approved ?? _approved;
  final stamp = segmentationResultStamp(on, sectorTimingAlgorithm);
  return RealisticLapInput(
    times: LapSectorTimes(
      lapReference: reference,
      stamp: revision == null
          ? stamp
          : SegmentationResultStamp(
              revision: revision,
              trackConfigurationReference: stamp.trackConfigurationReference,
            ),
      valid: true,
      sectors: [
        for (final (i, segment) in on.segments.indexed)
          SectorTime(
            segmentId: segment['id']! as String,
            name: segment['name']! as String,
            type: 'sector',
            startProgressMeters: segment['startProgressMeters']! as double,
            endProgressMeters: segment['endProgressMeters']! as double,
            seconds: seconds[i],
          ),
      ],
    ),
    entrySpeeds: entry,
    exitSpeeds: exit,
  );
}

/// Every combination of laps, one per segment, whose joins are possible:
/// the quickest total, by brute force.
double? _exhaustive(List<RealisticLapInput> laps, List<bool> meets) {
  double? best;
  void walk(int segment, int? previous, double total) {
    if (segment == meets.length + 1) {
      if (best == null || total < best!) best = total;
      return;
    }
    for (var k = 0; k < laps.length; ++k) {
      final time = laps[k].times.sectors[segment].seconds;
      if (time == null) continue;
      if (previous != null && previous != k && meets[segment - 1]) {
        final out = laps[previous].exitSpeeds[segment - 1], into = laps[k].entrySpeeds[segment];
        if (out == null || into == null || (out - into).abs() > realisticJoinMetresPerSecond) {
          continue;
        }
      }
      walk(segment + 1, k, total + time);
    }
  }

  walk(0, null, 0);
  return best;
}

void main() {
  group('computeRealisticTheoreticalBest', () {
    test('a quick segment entered at a speed no other lap left with is not used', () {
      // Lap B is quicker through a, but leaves it at 40 m/s; A enters b at 30.
      // B's own b is slow, so the raw best (B's a + A's b + c) is not
      // possible: the realistic best keeps A whole.
      final laps = [
        _lap('A', [3, 4, 3], entry: [30, 30, 30], exit: [30, 30, 30]),
        _lap('B', [2.5, 4.6, 3.2], entry: [30, 40, 30], exit: [40, 30, 30]),
      ];
      final result = computeRealisticTheoreticalBest(_approved, laps);
      expect(result.valid, isTrue);
      expect(result.totalSeconds, closeTo(10, 1e-9));
      expect([for (final s in result.segments) s.lapReference], ['A', 'A', 'A']);
      expect(result.lapCount, 1);
      expect(
        computeTheoreticalBest(_approved, [for (final l in laps) l.times]).totalSeconds,
        closeTo(9.5, 1e-9),
      );
    });

    test('laps join where their speeds match within the tolerance', () {
      final close = 30 + realisticJoinMetresPerSecond * 0.9;
      final laps = [
        _lap('A', [3, 4, 3], entry: [30, 30, 30], exit: [30, 30, 30]),
        _lap('B', [2.5, 4.6, 3.2], entry: [30, close, 30], exit: [close, 30, 30]),
      ];
      final result = computeRealisticTheoreticalBest(_approved, laps);
      expect(result.totalSeconds, closeTo(9.5, 1e-9));
      expect([for (final s in result.segments) s.lapReference], ['B', 'A', 'A']);
      expect(result.segments[0].joinMetresPerSecond, isNull);
      expect(result.segments[1].joinMetresPerSecond, closeTo(close - 30, 1e-9));
      // A continuing is not a join.
      expect(result.segments[2].joinMetresPerSecond, isNull);
    });

    test('one lap always continues, whatever its speeds', () {
      final laps = [
        _lap('A', [3, 4, 3], entry: [null, null, null], exit: [null, null, null]),
        _lap('B', [2.5, 4.6, 3.2], entry: [30, 40, 30], exit: [40, 30, 30]),
      ];
      final result = computeRealisticTheoreticalBest(_approved, laps);
      expect(result.totalSeconds, closeTo(10, 1e-9));
    });

    test('segments that do not meet join freely', () {
      final laps = [
        _lap('A', [3, 4, 3], entry: [30, 30, 30], exit: [30, 30, 30], approved: _apart),
        _lap('B', [2.5, 4.6, 3.2], entry: [30, 40, 30], exit: [40, 30, 30], approved: _apart),
      ];
      final result = computeRealisticTheoreticalBest(_apart, laps);
      expect(result.totalSeconds, closeTo(9.5, 1e-9));
      expect(result.segments[1].joinMetresPerSecond, isNull);
    });

    test('no speed on any lap says so', () {
      final laps = [
        _lap('A', [3, 4, 3], entry: [null, null, null], exit: [null, null, null]),
      ];
      final result = computeRealisticTheoreticalBest(_approved, laps);
      expect(result.valid, isFalse);
      expect(result.totalSeconds, isNull);
      expect(result.unavailableReason, realisticNoSpeed);
    });

    test('a segment no lap timed withholds the total', () {
      final laps = [
        _lap('A', [3, null, 3], entry: [30, 30, 30], exit: [30, 30, 30]),
        _lap('B', [3, 4, null], entry: [30, 30, 30], exit: [30, 30, 30]),
      ];
      final result = computeRealisticTheoreticalBest(_approved, laps);
      expect(result.totalSeconds, closeTo(10, 1e-9)); // A's a, B's b, A's c
      final none = computeRealisticTheoreticalBest(_approved, [
        _lap('A', [3, null, 3], entry: [30, 30, 30], exit: [30, 30, 30]),
      ]);
      expect(none.unavailableReason, realisticIncompleteCoverage);
      expect(none.totalSeconds, isNull);
    });

    test('a lap timed against other segments is left out', () {
      final laps = [
        _lap('A', [3, 4, 3], entry: [30, 30, 30], exit: [30, 30, 30]),
        _lap('B', [1, 1, 1], entry: [30, 30, 30], exit: [30, 30, 30], revision: 'old'),
      ];
      expect(computeRealisticTheoreticalBest(_approved, laps).totalSeconds, closeTo(10, 1e-9));
    });

    test('matches every combination tried by hand', () {
      final random = Random(7);
      for (var round = 0; round < 200; ++round) {
        final count = 1 + random.nextInt(5);
        double? speed() => random.nextInt(8) == 0 ? null : 30 + random.nextDouble() * 2;
        double? time() => random.nextInt(10) == 0 ? null : 2 + random.nextDouble() * 3;
        final laps = [
          for (var k = 0; k < count; ++k)
            _lap(
              'L$k',
              [time(), time(), time()],
              entry: [speed(), speed(), speed()],
              exit: [speed(), speed(), speed()],
            ),
        ];
        final expected = _exhaustive(laps, [true, true]);
        final result = computeRealisticTheoreticalBest(_approved, laps);
        if (expected == null) {
          expect(result.totalSeconds, isNull, reason: 'round $round');
        } else {
          expect(result.totalSeconds, closeTo(expected, 1e-9), reason: 'round $round');
          // The segments it names add up to it.
          expect(result.segments.fold(0.0, (sum, s) => sum + s.seconds), closeTo(expected, 1e-9));
        }
      }
    });
  });

  group('repeatableTheoreticalBest', () {
    SectionProgressionRow row(String id, double? typical) => SectionProgressionRow(
      segmentId: id,
      name: id,
      type: 'sector',
      cells: const [],
      fastestTypical: typical,
    );

    test('adds each segment\'s quickest typical time', () {
      expect(
        repeatableTheoreticalBest(SectionProgression(segments: [row('a', 3), row('b', 4.5)])),
        closeTo(7.5, 1e-9),
      );
    });

    test('is not shown when a segment has no typical time', () {
      expect(
        repeatableTheoreticalBest(SectionProgression(segments: [row('a', 3), row('b', null)])),
        isNull,
      );
      expect(repeatableTheoreticalBest(SectionProgression()), isNull);
    });
  });
}
