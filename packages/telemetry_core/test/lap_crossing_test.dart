// Truth tests for start-line crossings (FET-198): a pass is a real crossing
// of the gate line, whatever Overlays accepts.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'support/gate_path.dart';

void main() {
  test('a real crossing between two laps is accepted at the line', () {
    final path = GatePath()..points([(30.0, 0.0)]);
    path
      ..crossWestward()
      ..loopBackEast()
      ..crossWestward();
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.acceptedPasses, hasLength(2));
    expect(laps.timedLaps, hasLength(1));
    expect(laps.diagnostics.rejectedNotCrossingClusters, 0);
  });

  test('a same-side near miss at 2 m is not a pass and makes no lap', () {
    final path = GatePath()..points([(30.0, 0.0)]);
    path
      ..crossWestward()
      ..loopBackEast()
      // Fast in from the east to 2 m short of the line, then away east again
      // more slowly: enough motion across the line for the old detector.
      ..travel([(60.0, -20.0)])
      ..points([(30.0, -10.0), (2.0, 0.0), (6.0, 2.0), (9.0, 4.0), (13.0, 6.0), (17.0, 8.0)])
      ..travel([(80.0, 30.0), (80.0, 0.0), (30.0, 0.0)])
      ..crossWestward();
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.diagnostics.rejectedNotCrossingClusters, 1);
    expect(laps.acceptedPasses, hasLength(2));
    expect(laps.timedLaps, hasLength(1));
  });

  test('approaching and stopping 1 m before the line at the end is not a pass', () {
    final path = GatePath()
      ..points([(40.0, 0.0), (30.0, 0.0), (20.0, 0.0), (10.0, 0.0), (1.0, 0.0)]);
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.acceptedPasses, isEmpty);
    expect(laps.diagnostics.rejectedNotCrossingClusters, 1);
  });

  test('running along the line on one side is not a pass', () {
    final path = GatePath()..points([(3.0, -60.0)]);
    path.travel([(3.0, 60.0)], maximumStepMeters: 5.0);
    expect(detectLaps(path.session(), gatePathGate).acceptedPasses, isEmpty);
  });

  test('crossing the line just beyond the gate end, within the corridor, counts', () {
    // The gate ends at north 11.1; this crosses at north 14.
    final path = GatePath()..points([(30.0, 14.0)]);
    path.travel([(-30.0, 14.0)], maximumStepMeters: 6.0);
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.acceptedPasses, hasLength(1));
  });

  test('crossing and coming back to leave on the starting side is not a pass', () {
    final path = GatePath()
      ..points([(60.0, 0.0), (40.0, 0.0), (-3.0, 0.0), (-6.0, 2.0), (4.0, 5.0), (30.0, 6.0)])
      ..travel([(80.0, 6.0)]);
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.acceptedPasses, isEmpty);
    expect(laps.diagnostics.rejectedNotCrossingClusters, 1);
  });

  test('changing side only beyond the widened gate end is not a pass', () {
    // Diagonal: within 5 m of endpoint B (north 11.1) on the east side, then
    // over the line at about north 20, beyond the 5 m widening.
    final path = GatePath()..points([(40.0, 0.0), (25.0, 5.0), (4.0, 12.0), (-1.0, 20.0)]);
    path.travel([(-30.0, 60.0)]);
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.acceptedPasses, isEmpty);
    expect(laps.diagnostics.rejectedNotCrossingClusters, 1);
  });

  test('a pit lane crossing the line 8 m beyond the gate end is not a pass', () {
    final path = GatePath()..points([(40.0, 19.1)]);
    path.travel([(-40.0, 19.1)], maximumStepMeters: 4.0);
    expect(detectLaps(path.session(), gatePathGate).acceptedPasses, isEmpty);
  });

  test('arriving, oscillating by the line and leaving on the same side is not a pass', () {
    final path = GatePath()..points([(60.0, 0.0), (30.0, 0.0), (2.0, 0.0)]);
    for (var index = 0; index < 4; ++index) {
      path.points([(index.isEven ? -1.0 : 2.0, 0.0)]);
    }
    path.points([(9.0, 0.0), (30.0, 0.0), (60.0, 0.0)]);
    final laps = detectLaps(path.session(), gatePathGate);
    expect(laps.acceptedPasses, isEmpty);
    expect(laps.diagnostics.rejectedNotCrossingClusters, 1);
  });

  test('crossings are found at 1 Hz and at 100 Hz', () {
    final slow = GatePath(step: 1.0)
      ..points([(80.0, 0.0), (40.0, 0.0), (-10.0, 0.0), (-60.0, 0.0)]);
    final slowLaps = detectLaps(slow.session(), gatePathGate);
    expect(slowLaps.acceptedPasses, hasLength(1));
    // The line is crossed a fifth of the way from 40 m to −10 m, at 1.8 s.
    expect(slowLaps.acceptedPasses.single.telemetryTime, closeTo(1.8, 0.02));

    final fast = GatePath(step: 0.01)..points([(30.0, 0.0)]);
    fast.travel([(-30.0, 0.0)], maximumStepMeters: 0.3);
    final fastLaps = detectLaps(fast.session(), gatePathGate);
    expect(fastLaps.acceptedPasses, hasLength(1));
  });

  test('GPS oscillating around the line while stationary gives no pass', () {
    final path = GatePath();
    for (var index = 0; index < 100; ++index) {
      path.points([(index.isEven ? 3.0 : -3.0, 0.0)]);
    }
    expect(detectLaps(path.session(), gatePathGate).acceptedPasses, isEmpty);
  });

  test('invariant: a path that never reaches the line never gives a pass', () {
    final random = math.Random(198);
    for (var trial = 0; trial < 200; ++trial) {
      final path = GatePath(step: 0.1 + random.nextDouble() * 0.4)..points([(60.0, -40.0)]);
      for (var leg = 0; leg < 12; ++leg) {
        // Random waypoints east of the line, some within a metre of it.
        final e = random.nextBool()
            ? 1.0 + random.nextDouble() * 4.0
            : 1.0 + random.nextDouble() * 80.0;
        final n = -40.0 + random.nextDouble() * 80.0;
        path.travel([(e, n)], maximumStepMeters: 2.0 + random.nextDouble() * 20.0);
      }
      final laps = detectLaps(path.session(), gatePathGate);
      expect(laps.acceptedPasses, isEmpty, reason: 'trial $trial');
    }
  });
}
