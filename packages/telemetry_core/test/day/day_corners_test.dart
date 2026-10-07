import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

DayRunInput _run(String id, TelemetrySession session) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: 'a' * 63 + id.substring(id.length - 1),
  session: session,
  laps: deriveSourceLapSession(session),
);

// A lap at 30 m/s that brakes from [brake] m to [slow] m/s at 326 m (the
// second corner's entry), holds it to [hold] m and is back at 30 m/s 60 m
// later.
double Function(double) _lap(double brake, double slow, {double hold = 360}) => (d) {
  if (d < brake) return 30;
  if (d < 326) return 30 + (slow - 30) * (d - brake) / (326 - brake);
  if (d < hold) return slow;
  if (d < hold + 60) return slow + (30 - slow) * (d - hold) / 60;
  return 30;
};

final _laps = [_lap(250, 18), _lap(270, 20), _lap(240, 17, hold: 350)];

DayTheoreticalBest _day({bool pedals = true}) {
  final runs = [_run('run1', rectangleSession(_laps, pedals: pedals))];
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  return dayTheoreticalBest(analyzeDay(runs), outing, random: Random(1));
}

void main() {
  group('with throttle, brake and longitudinal G', () {
    final result = _day();
    final corner = result.corners[1];
    DayLapRow row(int number) => corner.laps.firstWhere((lap) => lap.$1.lapNumber == number).$1;

    test('has every corner segment in approved order, with every lap', () {
      expect(result.state, DayTheoreticalBestState.ready);
      expect(result.corners.map((c) => c.name), ['Corner 1', 'Corner 2', 'Corner 3', 'Corner 4']);
      for (final c in result.corners) {
        expect(result.segments[c.segmentIndex].segmentId, c.segmentId);
        expect(result.cornerAt(c.segmentIndex), same(c));
        expect(c.laps.length, result.laps.length);
        expect(c.bestLap!.reference, result.bestLap!.reference);
      }
      expect(result.cornerAt(1), isNull, reason: 'a straight');
      expect(corner.startProgressMeters, closeTo(326, 2));
    });

    test('measures speeds, the braking point and the pickup of each lap', () {
      final minimums = [for (final (_, m) in corner.laps) m.speeds.minimum.value!];
      expect(minimums[0], closeTo(18 * 3.6, 0.5));
      expect(minimums[1], closeTo(20 * 3.6, 0.5));
      expect(minimums[2], closeTo(17 * 3.6, 0.5));
      for (final (_, metrics) in corner.laps) {
        expect(metrics.speeds.provenance, 'measured');
        expect(metrics.speeds.entry.value, greaterThan(metrics.speeds.minimum.value! - 1e-6));
        expect(metrics.braking.method, brakingMethodMeasured);
        expect(metrics.braking.provenance, 'measured');
        expect(metrics.braking.peakDeceleration, greaterThan(0.3));
        expect(metrics.observation.minimumSpeed, metrics.speeds.minimum.value);
      }
      final before = [for (final (_, m) in corner.laps) m.braking.distanceBeforeEntryMeters!];
      expect(before[0], closeTo(326 - 250, 4));
      expect(before[1], closeTo(326 - 270, 4));
      expect(before[2], closeTo(326 - 240, 4));
      final pickup = corner.metrics(row(3).reference)!.exit.pickup;
      expect(pickup.method, pickupMethodMeasured);
      expect(pickup.progressMeters, closeTo(350, 4));
      // The straights before the other corners are flat out: no braking.
      expect(result.corners[0].laps.first.$2.braking.brakingPointMeters, isNull);
      expect(result.corners[0].laps.first.$2.braking.unavailableReason, brakingNoneDetected);
    });

    test('a corner whose tightest part cannot be told is not split, and says why '
        '(FET-221)', () {
      // The rectangle's corners turn in steps: more than one tight part.
      expect(corner.phaseSplit.unavailableReason, cornerPhaseMultipleApexes);
      final comparison = corner.compare(row(1).reference)!;
      expect(comparison.phases.unavailableReason, cornerPhaseMultipleApexes);
      expect(comparison.phaseDeltas, isNull);
    });

    test('compares a lap with the best lap and the best of the group', () {
      expect(corner.bestLap!.lapNumber, 2);
      final comparison = corner.compare(row(1).reference)!;
      expect(comparison.bestLap!.lapNumber, 2);
      expect(comparison.speeds.valid, isTrue);
      expect(comparison.speeds.minimumDelta, closeTo(-2 * 3.6, 0.5));
      // Lap 1 brakes about 20 m earlier along the lap.
      expect(comparison.braking.valid, isTrue);
      expect(comparison.braking.brakingPointDeltaMeters, closeTo(-20, 4));
      expect(comparison.highestMinimumSpeed!.lap.lapNumber, 2);
      expect(comparison.latestBrakingPoint!.lap.lapNumber, 2);
      expect(comparison.latestBrakingPoint!.value, closeTo(326 - 270, 4));
      expect(comparison.earliestPickup!.lap.lapNumber, 3);
      expect(comparison.earliestPickup!.value, closeTo(350 - corner.startProgressMeters, 4));

      final best = corner.compare(row(2).reference)!;
      expect(best.speeds.minimumDelta, 0);
      expect(best.braking.brakingPointDeltaMeters, 0);
      final other = row(1).reference;
      expect(
        corner.compare(
          DayLapReference(
            runId: 'run9',
            sourceRevision: other.sourceRevision,
            type: other.type,
            startTime: other.startTime,
            endTime: other.endTime,
          ),
        ),
        isNull,
      );
    });

    test('never takes a best braking point measured another way', () {
      final (row3, lap3) = corner.laps[2];
      final inferred = BrakingMetrics(segmentId: corner.segmentId, stamp: lap3.braking.stamp)
        ..valid = true
        ..method = brakingMethodInferred
        ..provenance = 'inferred'
        ..channel = 'longacc'
        ..brakingPointMeters = 320
        ..distanceBeforeEntryMeters = 6;
      final mixed = DayCorner(
        segmentIndex: corner.segmentIndex,
        segmentId: corner.segmentId,
        name: corner.name,
        startProgressMeters: corner.startProgressMeters,
        endProgressMeters: corner.endProgressMeters,
        laps: [
          corner.laps[0],
          corner.laps[1],
          (
            row3,
            CornerLapMetrics(
              lapReference: lap3.lapReference,
              speeds: lap3.speeds,
              braking: inferred,
              exit: lap3.exit,
              observation: lap3.observation,
            ),
          ),
        ],
        bestLap: corner.bestLap,
      );
      expect(mixed.compare(row(1).reference)!.latestBrakingPoint!.lap.lapNumber, 2);
      final own = mixed.compare(row3.reference)!;
      expect(own.braking.brakingPointDeltaMeters, isNull);
      expect(own.braking.unavailableReason, brakingMixedProvenance);
      expect(own.latestBrakingPoint!.lap.lapNumber, 3);
    });

    test('summarizes how repeatable each corner is', () {
      final row = result.segments[corner.segmentIndex];
      final variability = row.variability!;
      expect(variability.minimumSpeed.count, 3);
      expect(variability.brakingPointMeasured.count, 3);
      expect(variability.brakingPointInferred.count, 0);
      // The line where the corner starts, at its apex and where it ends.
      expect(variability.lineOffset.count, 3);
      expect(variability.entryLineOffset.count, 3);
      expect(variability.exitLineOffset.count, 3);
      for (final (_, metrics) in corner.laps) {
        expect(metrics.observation.entryLineOffsetMeters!.abs(), lessThan(5));
        expect(metrics.observation.exitLineOffsetMeters!.abs(), lessThan(5));
      }
      expect(result.segments[1].variability, isNull, reason: 'a straight');
    });

    test('classifies each corner from its shape and the laps (FET-220)', () {
      // Brakes from 30 m/s to about 18 m/s on every lap: over 40 km/h off.
      final braking = corner.classification;
      expect(braking.driving.approach, CornerApproach.heavyBraking);
      // From 30 m/s where braking starts to the typical lowest 18 m/s, read
      // from each lap's speed channel.
      expect(braking.driving.typicalSpeedShedMetresPerSecond, closeTo(12, 0.5));
      expect(braking.driving.shedLaps, 3);
      expect((braking.driving.brakingLaps, braking.driving.lapsMeasured), (3, 3));
      expect(braking.driving.brakingMethod, brakingMethodMeasured);
      expect(braking.driving.speedBand, CornerSpeedBand.slow);
      expect(braking.driving.typicalMinimumSpeedMetresPerSecond, closeTo(18, 0.5));
      // The same steps that leave it unsplit (FET-221) make it two tight parts.
      expect(braking.shape.shape, CornerShape.doubleApex);
      // The others are taken at a steady 30 m/s (108 km/h): flat and medium,
      // even though no lowest speed can be located in them.
      for (final index in [0, 2, 3]) {
        final other = result.corners[index].classification;
        expect(other.driving.approach, CornerApproach.flat);
        expect(other.driving.typicalSpeedLossFraction, closeTo(0, 1e-6));
        expect(other.driving.speedBand, CornerSpeedBand.medium);
        expect(other.shape.shape, CornerShape.singleApex);
      }
    });
  });

  test('without pedal channels the braking point and pickup are unavailable', () {
    final result = _day(pedals: false);
    final corner = result.corners[1];
    for (final (_, metrics) in corner.laps) {
      expect(metrics.speeds.minimum.value, isNotNull);
      expect(metrics.braking.brakingPointMeters, isNull);
      expect(metrics.braking.unavailableReason, isNotEmpty);
      expect(metrics.exit.pickup.progressMeters, isNull);
      expect(metrics.exit.pickup.unavailableReason, exitNoChannel);
    }
    final comparison = corner.compare(corner.laps.first.$1.reference)!;
    expect(comparison.latestBrakingPoint, isNull);
    expect(comparison.earliestPickup, isNull);
    expect(comparison.highestMinimumSpeed!.lap.lapNumber, 2);
    // No class from braking that cannot be measured; the speeds still give
    // the band (FET-220).
    expect(corner.classification.driving.approach, isNull);
    expect(corner.classification.driving.approachUnavailableReason, brakingNoChannel);
    expect(corner.classification.driving.speedBand, CornerSpeedBand.slow);
  });

  group('braking technique (FET-219)', () {
    // Harder braking than the others: from 30 to 12 m/s over 76 m, linear
    // in distance, so the deceleration starts at about 0.72 g and eases off.
    final laps = [_lap(250, 12), _lap(260, 12.5), _lap(240, 11.5)];
    DayTheoreticalBest day({bool pedals = true, bool lateral = true}) {
      final runs = [_run('run1', rectangleSession(laps, pedals: pedals, lateral: lateral))];
      final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
      return dayTheoreticalBest(analyzeDay(runs), outing, random: Random(1));
    }

    final result = day();
    final technique = result.corners[1].brakingTechnique;

    test('is measured on every ranked lap from the G channel, and typically', () {
      expect(technique.unavailableReason, isEmpty);
      expect(technique.source, brakingTechniqueFromG);
      expect(technique.laps.length, 3);
      expect(technique.lapsBraking, 3);
      for (final (_, lap) in technique.laps) {
        expect(lap.peakG, closeTo(0.73, 0.1)); // 0.66 to 0.81 g, lap by lap
        expect(lap.onsetTime, isNotNull);
      }
      expect(technique.peak.median, closeTo(0.72, 0.05));
      expect(technique.peak.laps, 3);
      // Trail braking: the speed falls to the corner's entry, where lateral
      // G starts, so there is little or none; it is still measured.
      expect(technique.trailSeconds.median, isNotNull);
      // The pedal is recorded at 10 Hz: its application and release are read.
      expect(technique.brakeRateHz, closeTo(10, 0.01));
    });

    test('leaves out laps the ranking does not rank', () {
      final ranked = {for (final lap in result.laps) lap.lap.reference};
      for (final (reference, _) in technique.laps) {
        expect(ranked, contains(reference));
      }
      // The recording's start before the gate and its end after the last
      // lap are not laps of the ranking.
      expect(technique.laps.length, ranked.length);
    });

    test('says why each lap is not known without a G channel or lateral G', () {
      final noLateral = day(lateral: false).corners[1].brakingTechnique;
      expect(noLateral.trailSeconds.median, isNull);
      expect(noLateral.trailSeconds.reason, brakingTechniqueNoLateral);
      // Without pedals there is no G channel: from the speed, and no
      // brake-to-throttle time.
      final fromSpeed = day(pedals: false).corners[1].brakingTechnique;
      expect(fromSpeed.source, brakingTechniqueFromSpeed);
      expect(fromSpeed.gChannelReason, brakingTechniqueGMissing);
      expect(fromSpeed.brakeToThrottle.reason, brakingTechniqueNoThrottle);
    });
  });
}
