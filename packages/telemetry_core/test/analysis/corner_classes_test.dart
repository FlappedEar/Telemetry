// What kind of corner each corner is (corner_classes.dart, FET-220): the
// shape from the track's curvature on synthetic loops, and the braking,
// lift or flat and speed band from the day's laps against the fixed
// thresholds.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/synthetic_loop.dart';

final _configuration = 'compatibility-v1:${'c' * 64}';

// The shape of [arcs], between two 100 m straights, approved as one corner
// from their start to their end.
CornerShapeClass _shape(List<LoopStep> arcs) {
  final half = [straight(100), ...arcs, straight(100)];
  final axis = buildLoopAxis(half);
  final features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
  // The loop's length per metre of path, so the bounds land on the arcs.
  final pathLength = 2 * half.fold(0.0, (sum, step) => sum + _length(step));
  final scale = axis.lengthMeters / pathLength;
  final arcsLength = arcs.fold(0.0, (sum, step) => sum + _length(step));
  final segment = makeTrackSegment(
    TrackSegmentType.corner,
    'Corner 1',
    100 * scale,
    (100 + arcsLength) * scale,
    _configuration,
  );
  return classifyCornerShape(axis, features, segment);
}

double _length(LoopStep step) =>
    step.degrees == 0 ? step.meters : step.degrees.abs() * math.pi / 180 * step.radiusMeters;

// One lap's figures in a corner: entry and minimum speed in [unit], and
// braking found ([braked]), found not to happen, or not measurable
// ([brakingReason]).
CornerLapMetrics _lap({
  double entry = 100,
  double? minimum = 60,
  String minimumReason = '',
  String unit = 'km/h',
  bool braked = true,
  String method = brakingMethodInferred,
  String brakingReason = '',
  double? peak = 0.9,
  double? mean = 0.6,
  double? seconds = 2.0,
  String decelerationUnit = 'g',
}) {
  final braking = BrakingMetrics(segmentId: 'c1')
    ..valid = true
    ..method = brakingReason == brakingNoChannel ? '' : method;
  if (brakingReason.isNotEmpty) {
    braking.unavailableReason = brakingReason;
  } else if (braked) {
    braking
      ..brakingPointMeters = 100
      ..distanceBeforeEntryMeters = 20
      ..brakingSeconds = seconds
      ..peakDeceleration = peak
      ..meanDeceleration = mean
      ..decelerationUnit = decelerationUnit;
  } else {
    braking.unavailableReason = brakingNoneDetected;
  }
  return CornerLapMetrics(
    lapReference: null,
    speeds: CornerSpeeds(
      unit: unit,
      provenance: 'measured',
      entry: CornerSpeedValue(value: entry),
      minimum: CornerSpeedValue(value: minimum, unavailableReason: minimumReason),
      valid: true,
    ),
    braking: braking,
    exit: ExitMetrics(),
    observation: CornerLapObservation(),
  );
}

void main() {
  group('shape, from the track', () {
    test('one tight part in the middle is a single apex', () {
      final shape = _shape([arc(60, 50), arc(60, 12), arc(60, 50)]);
      expect(shape.shape, CornerShape.singleApex);
      expect(shape.tightParts, 1);
      expect(shape.apexFraction, closeTo(0.5, 0.1));
      expect(
        shape.radiusRatio,
        inExclusiveRange(1 / cornerClassRadiusChangeRatio, cornerClassRadiusChangeRatio),
      );
      expect(shape.unavailableReason, isEmpty);
    });

    test('a corner that tightens is a decreasing radius, one that opens an increasing '
        'radius', () {
      final tightening = _shape([arc(90, 60), arc(90, 15)]);
      expect(tightening.shape, CornerShape.decreasingRadius);
      expect(tightening.radiusRatio, greaterThanOrEqualTo(cornerClassRadiusChangeRatio));
      final opening = _shape([arc(90, 15), arc(90, 60)]);
      expect(opening.shape, CornerShape.increasingRadius);
      expect(opening.radiusRatio, lessThanOrEqualTo(1 / cornerClassRadiusChangeRatio));
    });

    test('a short tight part late in an even corner is a late apex', () {
      final shape = _shape([arc(110, 40), arc(20, 15), arc(50, 40)]);
      expect(shape.shape, CornerShape.lateApex);
      expect(shape.apexFraction, greaterThanOrEqualTo(cornerClassLateApexFraction));
      expect(shape.radiusRatio, lessThan(cornerClassRadiusChangeRatio));
    });

    test('two tight parts are a double apex, three a complex, not split (FET-115)', () {
      final double = _shape([arc(45, 12), arc(90, 60), arc(45, 12)]);
      expect(double.shape, CornerShape.doubleApex);
      expect(double.tightParts, 2);
      expect(double.apexFraction, isNull);
      final complex = _shape([arc(40, 12), arc(30, 60), arc(40, 12), arc(30, 60), arc(40, 12)]);
      expect(complex.shape, CornerShape.complex);
      expect(complex.tightParts, greaterThanOrEqualTo(cornerClassComplexApexCount));
      expect(complex.changesDirection, isFalse);
    });

    test('turning one way then the other is a complex that changes direction', () {
      final half = [straight(100), arc(90, 20), arc(-90, 20), straight(50), arc(180, 40)];
      final axis = buildLoopAxis([...half, straight(100)]);
      final features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
      final length = 2 * math.pi / 2 * 20;
      final pathLength = 2 * (100 + length + 50 + math.pi * 40 + 100);
      final scale = axis.lengthMeters / pathLength;
      final shape = classifyCornerShape(
        axis,
        features,
        makeTrackSegment(
          TrackSegmentType.corner,
          'Corners 1–2',
          100 * scale,
          (100 + length) * scale,
          _configuration,
        ),
      );
      expect(shape.shape, CornerShape.complex);
      expect(shape.changesDirection, isTrue);
    });

    test('a segment that does not turn has no shape, and says why', () {
      final axis = buildLoopAxis(stadium());
      final features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
      final straightPart = classifyCornerShape(
        axis,
        features,
        makeTrackSegment(TrackSegmentType.corner, 'Corner 1', 10, 60, _configuration),
      );
      expect(straightPart.shape, isNull);
      expect(straightPart.unavailableReason, cornerPhaseInsufficientGeometry);
      expect(
        classifyCornerShape(
          const ProgressAxis(),
          const TrackFeatures(),
          const {},
        ).unavailableReason,
        cornerPhaseInvalidInput,
      );
    });
  });

  group('approach and speed, from the laps', () {
    test('braking that takes 40 km/h off is heavy braking; less is braking', () {
      // 0.6 g for 2 s takes 42 km/h off.
      final heavy = classifyCornerDriving([for (var i = 0; i < 3; i++) _lap()]);
      expect(heavy.approach, CornerApproach.heavyBraking);
      expect(heavy.typicalSpeedShedMetresPerSecond! * 3.6, closeTo(0.6 * 9.80665 * 2 * 3.6, 1e-6));
      expect(heavy.typicalPeakDecelerationG, 0.9);
      expect((heavy.brakingLaps, heavy.lapsMeasured, heavy.decelerationLaps), (3, 3, 3));
      expect(heavy.brakingMethod, brakingMethodInferred);
      // 0.5 g for 2 s: 35 km/h.
      final braking = classifyCornerDriving([for (var i = 0; i < 3; i++) _lap(mean: 0.5)]);
      expect(braking.approach, CornerApproach.braking);
      // m/s² is read as g.
      final metric = classifyCornerDriving([
        for (var i = 0; i < 3; i++) _lap(mean: 0.6 * 9.80665, peak: 9, decelerationUnit: 'm/s²'),
      ]);
      expect(metric.approach, CornerApproach.heavyBraking);
      expect(metric.typicalPeakDecelerationG, closeTo(9 / 9.80665, 1e-9));
    });

    test('braking without a deceleration is braking, not split into heavy or not', () {
      final driving = classifyCornerDriving([
        for (var i = 0; i < 3; i++) _lap(method: brakingMethodMeasured, peak: null, mean: null),
      ]);
      expect(driving.approach, CornerApproach.braking);
      expect(driving.typicalSpeedShedMetresPerSecond, isNull);
      expect(driving.decelerationLaps, 0);
      // A unit that is not an acceleration is not read.
      final unknown = classifyCornerDriving([
        for (var i = 0; i < 3; i++) _lap(decelerationUnit: 'bar'),
      ]);
      expect(unknown.approach, CornerApproach.braking);
      expect(unknown.typicalSpeedShedMetresPerSecond, isNull);
    });

    test('without braking, losing 5 % of the entry speed is a lift; less is flat', () {
      final lift = classifyCornerDriving([
        for (final minimum in [94.0, 90.0, 92.0]) _lap(braked: false, minimum: minimum),
      ]);
      expect(lift.approach, CornerApproach.lift);
      expect(lift.typicalSpeedLossFraction, closeTo(0.08, 1e-9));
      expect(lift.typicalSpeedLossMetresPerSecond! * 3.6, closeTo(8, 1e-9));
      expect(lift.brakingLaps, 0);
      final flat = classifyCornerDriving([
        for (final minimum in [98.0, 97.0, 99.0]) _lap(braked: false, minimum: minimum),
      ]);
      expect(flat.approach, CornerApproach.flat);
      expect(flat.typicalSpeedLossFraction, closeTo(0.02, 1e-9));
    });

    test('a speed that does not change through the corner is its own minimum', () {
      final steady = classifyCornerDriving([
        for (var i = 0; i < 3; i++)
          _lap(braked: false, entry: 140, minimum: null, minimumReason: cornerPhaseFlatSpeed),
      ]);
      expect(steady.approach, CornerApproach.flat);
      expect(steady.speedBand, CornerSpeedBand.fast);
      // Any other missing minimum is missing, with its reason.
      final uncovered = classifyCornerDriving([
        for (var i = 0; i < 3; i++)
          _lap(braked: false, minimum: null, minimumReason: cornerPhaseIncompleteCoverage),
      ]);
      expect(uncovered.approach, isNull);
      expect(uncovered.approachUnavailableReason, cornerPhaseIncompleteCoverage);
      expect(uncovered.speedBandUnavailableReason, cornerPhaseIncompleteCoverage);
    });

    test('braking on half the laps or more is braking', () {
      final half = classifyCornerDriving([
        _lap(),
        _lap(),
        _lap(braked: false, minimum: 99),
        _lap(braked: false, minimum: 99),
      ]);
      expect((half.brakingLaps, half.lapsMeasured), (2, 4));
      // The typical shed needs three braking laps: not split into heavy.
      expect(half.approach, CornerApproach.braking);
      expect(half.typicalSpeedShedMetresPerSecond, isNull);
      final once = classifyCornerDriving([
        _lap(),
        _lap(braked: false, minimum: 99),
        _lap(braked: false, minimum: 99),
      ]);
      expect(once.approach, CornerApproach.flat);
    });

    test('a brake pedal and deceleration are never pooled: the method most laps used '
        'decides', () {
      final driving = classifyCornerDriving([
        _lap(method: brakingMethodMeasured),
        _lap(method: brakingMethodMeasured),
        for (var i = 0; i < 3; i++) _lap(braked: false, minimum: 99),
      ]);
      expect(driving.brakingMethod, brakingMethodInferred);
      expect((driving.brakingLaps, driving.lapsMeasured), (0, 3));
      expect(driving.approach, CornerApproach.flat);
    });

    test('the speed band comes from the typical minimum speed, in its unit', () {
      CornerSpeedBand? band(double minimum, [String unit = 'km/h']) =>
          classifyCornerDriving([for (var i = 0; i < 3; i++) _lap(minimum: minimum, unit: unit)])
              .speedBand;
      expect(band(79.9), CornerSpeedBand.slow);
      expect(band(80), CornerSpeedBand.medium);
      expect(band(129.9), CornerSpeedBand.medium);
      expect(band(130), CornerSpeedBand.fast);
      expect(band(50, 'mph'), CornerSpeedBand.medium); // 80.5 km/h
      expect(band(22, 'm/s'), CornerSpeedBand.slow);
      final unknown = classifyCornerDriving([
        for (var i = 0; i < 3; i++) _lap(minimum: 60, unit: 'furlong/fortnight'),
      ]);
      expect(unknown.speedBand, isNull);
      expect(unknown.speedBandUnavailableReason, cornerClassSpeedUnitUnknown);
      final typical = classifyCornerDriving([
        for (final minimum in [60.0, 70.0, 200.0]) _lap(minimum: minimum),
      ]);
      expect(typical.typicalMinimumSpeedMetresPerSecond! * 3.6, closeTo(70, 1e-9));
      // Shown back in the laps' own unit; laps in different units show none.
      final miles = classifyCornerDriving([for (var i = 0; i < 3; i++) _lap(unit: 'mph')]);
      expect(miles.speedUnit, 'mph');
      expect(miles.inSpeedUnit(miles.typicalMinimumSpeedMetresPerSecond), closeTo(60, 1e-9));
      final mixed = classifyCornerDriving([
        _lap(unit: 'mph'),
        _lap(unit: 'km/h'),
        _lap(unit: 'kmh'),
      ]);
      expect(mixed.speedBand, CornerSpeedBand.slow);
      expect(mixed.speedUnit, isNull);
      expect(mixed.inSpeedUnit(mixed.typicalMinimumSpeedMetresPerSecond), isNull);
    });

    test('fewer than three laps give no class, and say why', () {
      final driving = classifyCornerDriving([_lap(), _lap()]);
      expect(driving.approach, isNull);
      expect(driving.approachUnavailableReason, cornerClassTooFewLaps);
      expect(driving.speedBand, isNull);
      expect(driving.speedBandUnavailableReason, cornerClassTooFewLaps);
      expect(classifyCornerDriving(const []).approachUnavailableReason, cornerClassTooFewLaps);
    });

    test('a corner whose braking cannot be measured gives that reason', () {
      final driving = classifyCornerDriving([
        for (var i = 0; i < 3; i++) _lap(brakingReason: brakingNoChannel),
      ]);
      expect(driving.approach, isNull);
      expect(driving.approachUnavailableReason, brakingNoChannel);
      // The speeds still give the band.
      expect(driving.speedBand, CornerSpeedBand.slow);
      final gate = classifyCornerDriving([
        for (var i = 0; i < 3; i++) _lap(brakingReason: brakingSegmentCrossesGate),
      ]);
      expect(gate.approachUnavailableReason, brakingSegmentCrossesGate);
    });
  });
}
