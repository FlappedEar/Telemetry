import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'support/sessions.dart';

/// The lap fixture resampled every 0.25 s, so a single defect lands inside a
/// lap rather than on a sample that arms or ends a gate pass.
TelemetrySession interiorGapFixture() {
  final session = parse(fixture('event-laps.vbo'));
  return editGps(session, (latTimes, latValues, lonTimes, lonValues) {
    void densify(List<double> times, List<double> values) {
      final t = List.of(times);
      final v = List.of(values);
      times.clear();
      values.clear();
      for (var index = 1; index < t.length; ++index) {
        for (var time = t[index - 1]; time < t[index]; time += 0.25) {
          final fraction = (time - t[index - 1]) / (t[index] - t[index - 1]);
          times.add(time);
          values.add(v[index - 1] + (v[index] - v[index - 1]) * fraction);
        }
      }
      times.add(t.last);
      values.add(v.last);
    }

    densify(latTimes, latValues);
    densify(lonTimes, lonValues);
  });
}

void main() {
  test('keeps a measured lap with an interior GPS gap, but not as a reference', () {
    final session = editGps(interiorGapFixture(), (latTimes, _, lonTimes, _) {
      for (final times in [latTimes, lonTimes]) {
        for (var i = 0; i < times.length; ++i) {
          if (times[i] >= 3.5) times[i] += 10.0;
        }
      }
    });
    final laps = deriveSourceLapSession(session);
    expect(laps.timedLaps, hasLength(3));
    expect(laps.timedLaps[0].durationSeconds, greaterThan(13.9));
    expect(laps.timedLaps[0].referenceIssue, LapReferenceIssue.gpsGap);
    expect(laps.timedLaps[0].referenceEligible, isFalse);
    expect(laps.lapTraces, hasLength(2));
    expect(laps.lapTraces.every((trace) => trace.lapNumber != 1), isTrue);
    expect(laps.timedLaps[laps.fastestLapIndex!].referenceEligible, isTrue);
  });

  for (final kind in ['missing coordinate', 'out-of-range coordinate', 'unaligned clocks']) {
    test('marks a lap with a $kind as invalid GPS', () {
      final session = editGps(interiorGapFixture(), (latTimes, latValues, lonTimes, _) {
        final interior = latTimes.indexOf(3.5);
        expect(interior, greaterThanOrEqualTo(0));
        if (kind == 'missing coordinate') latValues[interior] = double.nan;
        if (kind == 'out-of-range coordinate') latValues[interior] = 100.0;
        if (kind == 'unaligned clocks') lonTimes[interior] += 0.01;
      });
      final laps = deriveSourceLapSession(session);
      expect(laps.timedLaps, hasLength(3));
      expect(laps.timedLaps[0].referenceIssue, LapReferenceIssue.invalidGps);
      expect(laps.lapTraces, hasLength(2));
      expect(laps.fastestLapIndex, isNot(0));
      expect(laps.fastestLapIndex, isNotNull);
    });
  }

  test('has no best lap when every lap misses GPS', () {
    final session = editGps(interiorGapFixture(), (latTimes, latValues, _, _) {
      for (final time in [3.5, 7.5, 12.5]) {
        latValues[latTimes.indexOf(time)] = double.nan;
      }
    });
    final laps = deriveSourceLapSession(session);
    expect(laps.timedLaps, hasLength(3));
    expect(laps.fastestLapIndex, isNull);
    expect(laps.lapTraces, isEmpty);
    expect(laps.timedLaps.every((lap) => lap.deltaToBestSeconds == 0.0), isTrue);
  });

  test('ranks normal laps', () {
    final laps = deriveSourceLapSession(parse(fixture('event-laps.vbo')));
    expect(laps.timedLaps, hasLength(3));
    expect(laps.lapTraces, hasLength(3));
    expect(laps.fastestLapIndex, 0);
    expect(laps.timedLaps.every((lap) => lap.referenceEligible), isTrue);
    expect(laps.timedLaps[1].deltaToBestSeconds, closeTo(1.0, 0.001));
    expect(eligibleLapIndices(laps.timedLaps), [0, 1, 2]);
  });

  test('a user exclusion moves the best lap', () {
    final laps = deriveSourceLapSession(parse(fixture('event-laps.vbo')));
    final excluded = recomputeLapRanking(
      laps.withTimedLaps([
        laps.timedLaps[0].copyWith(userExclusionReason: 'traffic'),
        ...laps.timedLaps.skip(1),
      ], laps.fastestLapIndex),
    );
    expect(excluded.fastestLapIndex, 2);
    expect(excluded.timedLaps[0].deltaToBestSeconds, 0.0);
    expect(eligibleLapIndices(excluded.timedLaps), [1, 2]);
  });
}
