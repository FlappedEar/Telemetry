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

/// Every combination of laps, one per segment, whose joins are possible
/// ([meets]: segment i meets i + 1; [closes]: the last meets the first):
/// the quickest total, by brute force.
double? _exhaustive(List<RealisticLapInput> laps, List<bool> meets, {bool closes = false}) {
  final count = meets.length + 1;
  bool joins(int j, int k, int i) {
    if (j == k) return true;
    final out = laps[j].exitSpeeds[i], into = laps[k].entrySpeeds[(i + 1) % count];
    return out != null && into != null && (out - into).abs() <= realisticJoinMetresPerSecond;
  }

  double? best;
  void walk(List<int> chosen, double total) {
    final segment = chosen.length;
    if (segment == count) {
      if (closes && !joins(chosen.last, chosen.first, count - 1)) return;
      if (best == null || total < best!) best = total;
      return;
    }
    for (var k = 0; k < laps.length; ++k) {
      final time = laps[k].times.sectors[segment].seconds;
      if (time == null) continue;
      if (segment > 0 && meets[segment - 1] && !joins(chosen.last, k, segment - 1)) continue;
      walk([...chosen, k], total + time);
    }
  }

  walk([], 0);
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

    test('a chain of segments that never joins says so', () {
      final laps = [
        _lap('A', [3, null, null], entry: [30, 30, 30], exit: [30, 30, 30]),
        _lap('B', [null, 4, 3], entry: [40, 40, 40], exit: [40, 40, 40]),
      ];
      final result = computeRealisticTheoreticalBest(_approved, laps);
      expect(result.totalSeconds, isNull);
      expect(result.unavailableReason, realisticNoJoin);
      expect(
        computeRealisticTheoreticalBest(_approved, []).unavailableReason,
        realisticIncompleteCoverage,
      );
    });

    test('a last segment across the gate joins the first', () {
      // c runs across the gate from 900 m to 50 m, where a starts.
      final across = approvedSegmentation([
        _segment('a', 50, 300),
        _segment('b', 300, 900),
        _segment('c', 900, 50),
      ], _group);
      // B is quickest through c but leaves it at 50 m/s; A enters a at 20.
      final laps = [
        _lap('A', [3, 4, 3], entry: [20, 30, 30], exit: [30, 30, 20], approved: across),
        _lap('B', [5, 4.5, 2], entry: [50, 30, 30], exit: [30, 30, 50], approved: across),
      ];
      final result = computeRealisticTheoreticalBest(across, laps);
      expect(result.totalSeconds, closeTo(10, 1e-9));
      expect([for (final s in result.segments) s.lapReference], ['A', 'A', 'A']);
      // Without the join across the gate, A, A, B would be quicker.
      expect(_exhaustive(laps, [true, true]), closeTo(9, 1e-9));
      expect(_exhaustive(laps, [true, true], closes: true), closeTo(10, 1e-9));
    });

    test('matches every combination tried by hand, and its joins hold', () {
      final random = Random(7);
      for (var round = 0; round < 2000; ++round) {
        final count = 1 + random.nextInt(6);
        // Segments of 100 m, some with a gap after them; the last may run
        // across the gate into the first.
        final wraps = count > 1 && random.nextBool();
        final segments = <Map<String, Object?>>[];
        var at = wraps ? 50.0 : 0.0;
        for (var i = 0; i < count; ++i) {
          final gap = i > 0 && random.nextInt(4) == 0 ? 10.0 : 0.0;
          final start = at + gap;
          final end = i == count - 1 && wraps ? 50.0 : start + 100;
          segments.add(_segment('s$i', start, i == count - 1 && wraps ? end : end));
          at = end;
        }
        if (wraps) segments.last['startProgressMeters'] = 900.0;
        final approved = approvedSegmentation(segments, _group);
        expect(approved.valid, isTrue, reason: '$segments');
        final meets = [
          for (var i = 0; i + 1 < count; ++i)
            segments[i]['endProgressMeters'] == segments[i + 1]['startProgressMeters'],
        ];
        final lapCount = 1 + random.nextInt(5);
        double? speed() => random.nextInt(8) == 0 ? null : 30 + random.nextDouble() * 2;
        double? time() => random.nextInt(10) == 0 ? null : 2 + random.nextDouble() * 3;
        final laps = [
          for (var k = 0; k < lapCount; ++k)
            _lap(
              'L$k',
              [for (var i = 0; i < count; ++i) time()],
              entry: [for (var i = 0; i < count; ++i) speed()],
              exit: [for (var i = 0; i < count; ++i) speed()],
              approved: approved,
            ),
        ];
        final result = computeRealisticTheoreticalBest(approved, laps);
        if (laps.every((l) => [...l.entrySpeeds, ...l.exitSpeeds].every((v) => v == null))) {
          // Without any speed no two laps can be said to join.
          expect(result.totalSeconds, isNull, reason: 'round $round');
          continue;
        }
        final expected = _exhaustive(laps, meets, closes: wraps);
        if (expected == null) {
          expect(result.totalSeconds, isNull, reason: 'round $round');
          continue;
        }
        expect(result.totalSeconds, closeTo(expected, 1e-9), reason: 'round $round');
        // The chain it names: each lap's own time, adding up, every join
        // within the tolerance.
        final lap = {for (final l in laps) l.times.lapReference: l};
        var sum = 0.0;
        for (final (i, segment) in result.segments.indexed) {
          final own = lap[segment.lapReference]!;
          expect(segment.seconds, own.times.sectors[i].seconds);
          sum += segment.seconds;
          final before = i == 0 ? count - 1 : i - 1;
          final met = i == 0 ? wraps : meets[before];
          final previous = result.segments[before].lapReference;
          if (!met || previous == segment.lapReference || count == 1) {
            expect(segment.joinMetresPerSecond, isNull);
            continue;
          }
          final out = lap[previous]!.exitSpeeds[before]!;
          final into = own.entrySpeeds[i]!;
          expect((out - into).abs(), lessThanOrEqualTo(realisticJoinMetresPerSecond));
          expect(segment.joinMetresPerSecond, closeTo((out - into).abs(), 1e-12));
        }
        expect(sum, closeTo(expected, 1e-9));
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
