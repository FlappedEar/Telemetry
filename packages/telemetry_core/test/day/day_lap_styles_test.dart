// The day's laps by style (FET-223) through the day's pipeline on the
// rectangle circuit: where braking started comes from the deceleration, not
// the brake pedal, units stay as read, and laps the ranking leaves out are
// not grouped.
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

double Function(double) _lap(double brake, double slow, {double hold = 360}) => (d) {
  if (d < brake) return 30;
  if (d < 326) return 30 + (slow - 30) * (d - brake) / (326 - brake);
  if (d < hold) return slow;
  if (d < hold + 60) return slow + (30 - slow) * (d - hold) / 60;
  return 30;
};

DayTheoreticalBest _day({bool pedals = true, String assumed = ''}) {
  final runs = [
    _run(
      'run1',
      withEffectiveSpeedUnits(
        rectangleSession([_lap(250, 18), _lap(270, 20), _lap(240, 17, hold: 350)], pedals: pedals),
        assumed: assumed,
      ),
    ),
  ];
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  return dayTheoreticalBest(analyzeDay(runs), outing, random: Random(1));
}

void main() {
  group('on the rectangle with pedals and longitudinal G', () {
    final result = _day();
    final styles = result.lapStyles!;
    final corner = result.corners[1];

    test('are worked out with the day, for the ranked laps only', () {
      expect(result.state, DayTheoreticalBestState.ready);
      expect(styles.inputs.length, 3);
      expect(styles.timedLapCount, 3);
      expect(
        {
          for (final input in styles.inputs)
            styles
                .rowOf(
                  LapStyleResult(lap: input.lap, seconds: input.seconds, style: LapStyle.typical),
                )
                .reference,
        },
        {for (final lap in result.laps) lap.lap.reference},
      );
    });

    test('read braking from the deceleration although the corner analysis used '
        'the pedal', () {
      for (final (_, metrics) in corner.laps) {
        expect(metrics.braking.method, brakingMethodMeasured);
      }
      final starts = <double>[];
      for (final input in styles.inputs) {
        final sample = input.corners.firstWhere((sample) => sample.cornerId == corner.segmentId);
        expect(sample.brakeSource, startsWith(brakingMethodInferred));
        expect(sample.brakeSource, endsWith('longacc'));
        starts.add(sample.brakeBeforeEntryMeters!);
      }
      expect(starts[0], closeTo(326 - 250, 5));
      expect(starts[1], closeTo(326 - 270, 5));
      expect(starts[2], closeTo(326 - 240, 5));
      expect(styles.brakeCornerFigures, 3);
      expect(styles.brakeUnavailableReason, isEmpty);
    });

    test('take the throttle pickup and the speeds from the corner analysis', () {
      final lap3 = corner.laps[2].$2;
      final sample = styles.inputs[2].corners.firstWhere((s) => s.cornerId == corner.segmentId);
      expect(sample.pickupAfterEntryMeters, closeTo(350 - corner.startProgressMeters, 4));
      expect(sample.pickupSource, startsWith(pickupMethodMeasured));
      expect(sample.minimumSpeed, lap3.speeds.minimum.value);
      expect(sample.exitSpeed, lap3.speeds.exit.value);
      expect(sample.speedUnit, lap3.speeds.unit);
    });

    test('say so when a speed has no declared unit, and keep an assumed one as set', () {
      // The rectangle declares no unit and none is assumed: read as it is,
      // and flagged.
      expect(styles.speedUnitMissing, isTrue);
      expect(styles.inputs.first.corners.first.speedUnit, isEmpty);
      expect(styles.brakeUnitAssumed, isTrue, reason: 'the longitudinal G declares no unit');
      final assumed = _day(assumed: 'mph').lapStyles!;
      expect(assumed.speedUnitMissing, isFalse);
      expect(assumed.inputs.first.corners.first.speedUnit, 'mph');
    });

    test('are not available from three laps in a handful of corners, and say why', () {
      // Only some of the rectangle's four corners have a typical in a measure:
      // whatever the count, a day that cannot be grouped says so.
      if (!styles.available) {
        expect(styles.styles.unavailableReason, lapStylesTooFewCorners);
      }
      expect(styles.styles.lapCount, 3);
    });
  });

  test('without pedal channels there is no braking point, and the reason is given', () {
    final styles = _day(pedals: false).lapStyles!;
    expect(styles.brakeCornerFigures, 0);
    expect(styles.throttleCornerFigures, 0);
    expect(styles.brakeUnavailableReason, isNotEmpty);
    expect(styles.available, isFalse);
  });

  test('a day without a result has no styles', () {
    final result = dayTheoreticalBest(analyzeDay(const []), const {});
    expect(result.lapStyles, isNull);
  });
}
