// What kind of corner each corner is (corner_classes.dart, FET-220): the
// shape from the track's curvature on synthetic loops, the shape rules at
// each threshold, and the braking, lift or flat and speed band from the
// day's laps against the fixed thresholds.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/synthetic_loop.dart';

final _configuration = 'compatibility-v1:${'c' * 64}';

// The shape of [arcs], between two 100 m straights, approved as one corner
// from [before] metres before their start to [after] metres after their
// end.
CornerShapeClass _shape(List<LoopStep> arcs, {double before = 0, double after = 0}) {
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
    (100 - before) * scale,
    (100 + arcsLength + after) * scale,
    _configuration,
  );
  return classifyCornerShape(axis, features, segment);
}

double _length(LoopStep step) =>
    step.degrees == 0 ? step.meters : step.degrees.abs() * math.pi / 180 * step.radiusMeters;

// One lap's figures in a corner: entry and minimum speed and the speed
// where braking started ([atBraking]) in [unit], and braking found
// ([braked]), found not to happen, or not measurable ([brakingReason]).
CornerClassLap _lap({
  double entry = 100,
  double? minimum = 60,
  String minimumReason = '',
  String unit = 'km/h',
  bool braked = true,
  double? atBraking = 120,
  String method = brakingMethodInferred,
  String brakingReason = '',
}) {
  final braking = BrakingMetrics(segmentId: 'c1')
    ..valid = true
    ..method = brakingReason == brakingNoChannel ? '' : method;
  if (brakingReason.isNotEmpty) {
    braking.unavailableReason = brakingReason;
  } else if (braked) {
    braking
      ..brakingPointMeters = 100
      ..brakingPointTime = 10
      ..distanceBeforeEntryMeters = 20;
  } else {
    braking.unavailableReason = brakingNoneDetected;
  }
  return (
    metrics: CornerLapMetrics(
      lapReference: null,
      speeds: CornerSpeeds(
        channel: 'speed',
        unit: unit,
        provenance: 'measured',
        entry: CornerSpeedValue(value: entry),
        minimum: CornerSpeedValue(value: minimum, unavailableReason: minimumReason),
        valid: true,
      ),
      braking: braking,
      exit: ExitMetrics(),
      observation: CornerLapObservation(),
    ),
    speedAtBraking: braked && brakingReason.isEmpty ? atBraking : null,
  );
}

List<CornerClassLap> _three({
  double entry = 100,
  double? minimum = 60,
  String unit = 'km/h',
  bool braked = true,
  double? atBraking = 120,
}) => [
  for (var i = 0; i < 3; i++)
    _lap(entry: entry, minimum: minimum, unit: unit, braked: braked, atBraking: atBraking),
];

void main() {
  group('shape, from the track', () {
    test('one tight part in the middle is a single apex', () {
      final shape = _shape([arc(60, 50), arc(60, 12), arc(60, 50)]);
      expect(shape.shape, CornerShape.singleApex);
      expect(shape.tightParts, 1);
      expect(shape.apexFraction, closeTo(0.5, 0.1));
      expect(shape.unavailableReason, isEmpty);
    });

    test('the shape does not depend on where the bounds sit on the straights', () {
      for (final (before, after) in [(0.0, 0.0), (20.0, 0.0), (0.0, 20.0), (20.0, 20.0)]) {
        final shape = _shape([arc(90, 30)], before: before, after: after);
        expect(shape.shape, CornerShape.singleApex, reason: 'padded $before/$after');
        // A bound cut on the arc itself loses half the smoothing there, but
        // the halves stay within the rule's limits.
        expect(
          shape.radiusRatio,
          inExclusiveRange(1 / cornerClassRadiusChangeRatio, cornerClassRadiusChangeRatio),
          reason: 'padded $before/$after',
        );
        expect(shape.apexFraction, closeTo(0.5, 0.06), reason: 'padded $before/$after');
      }
      final tightening = [arc(90, 60), arc(90, 15)];
      for (final (before, after) in [(0.0, 0.0), (20.0, 0.0), (0.0, 20.0)]) {
        expect(
          _shape(tightening, before: before, after: after).shape,
          CornerShape.decreasingRadius,
          reason: 'padded $before/$after',
        );
      }
    });

    test('tightening to the end is a decreasing radius, opening from the start an '
        'increasing radius', () {
      final tightening = _shape([arc(90, 60), arc(90, 15)]);
      expect(tightening.shape, CornerShape.decreasingRadius);
      expect(tightening.radiusRatio, greaterThanOrEqualTo(cornerClassRadiusChangeRatio));
      final opening = _shape([arc(90, 15), arc(90, 60)]);
      expect(opening.shape, CornerShape.increasingRadius);
      expect(opening.radiusRatio, lessThanOrEqualTo(1 / cornerClassRadiusChangeRatio));
    });

    test('a tight part late in the corner that opens again after it is a late apex, '
        'not a decreasing radius', () {
      final shape = _shape([arc(90, 60), arc(60, 15), arc(30, 60)]);
      expect(shape.shape, CornerShape.lateApex);
      expect(shape.apexFraction, greaterThanOrEqualTo(cornerClassLateApexFraction));
      // The second half turns harder, but the corner does not tighten to
      // the end.
      expect(shape.radiusRatio, greaterThanOrEqualTo(cornerClassRadiusChangeRatio));
    });

    test('two tight parts are a double apex, three a complex (FET-115)', () {
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
      final length = math.pi * 20;
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

    test('the rules at each threshold, in order', () {
      CornerShape? one({
        double reversal = 0,
        double ratio = 1,
        double apex = 0.5,
        double start = 0.4,
        double end = 0.6,
      }) => cornerShapeFor(
        tightParts: 1,
        reversalRatio: reversal,
        radiusRatio: ratio,
        apexFraction: apex,
        apexStartFraction: start,
        apexEndFraction: end,
      );
      // Turning the other way.
      expect(one(reversal: 0.59), CornerShape.singleApex);
      expect(one(reversal: 0.6), CornerShape.complex);
      // Tight parts.
      expect(cornerShapeFor(tightParts: 0), isNull);
      expect(cornerShapeFor(tightParts: 2), CornerShape.doubleApex);
      expect(cornerShapeFor(tightParts: 3), CornerShape.complex);
      // Decreasing radius: ratio and tight part running into the end.
      expect(one(ratio: 1.29, apex: 0.5, start: 0.8, end: 0.8), CornerShape.singleApex);
      expect(one(ratio: 1.3, apex: 0.5, start: 0.8, end: 0.8), CornerShape.decreasingRadius);
      expect(one(ratio: 1.3, apex: 0.7, start: 0.6, end: 0.79), CornerShape.lateApex);
      // Increasing radius: ratio and tight part starting at the beginning.
      expect(one(ratio: 1 / 1.29, start: 0.2), CornerShape.singleApex);
      expect(one(ratio: 1 / 1.3, start: 0.2), CornerShape.increasingRadius);
      expect(one(ratio: 1 / 1.3, start: 0.21), CornerShape.singleApex);
      // Late apex.
      expect(one(apex: 0.59), CornerShape.singleApex);
      expect(one(apex: 0.6), CornerShape.lateApex);
    });
  });

  group('approach and speed, from the laps', () {
    test('a typical 40 km/h from braking to the lowest speed is heavy braking', () {
      // 99.9 to 60: 39.9 km/h; 100 to 60: 40 km/h.
      expect(classifyCornerDriving(_three(atBraking: 99.9)).approach, CornerApproach.braking);
      final heavy = classifyCornerDriving(_three(atBraking: 100));
      expect(heavy.approach, CornerApproach.heavyBraking);
      expect(heavy.typicalSpeedShedMetresPerSecond! * 3.6, closeTo(40, 1e-9));
      expect((heavy.brakingLaps, heavy.lapsMeasured, heavy.shedLaps), (3, 3, 3));
      expect(heavy.brakingMethod, brakingMethodInferred);
      expect(heavy.heavyUnknown, isFalse);
      // In mph: 25 mph is 40.2 km/h.
      expect(
        classifyCornerDriving(_three(unit: 'mph', atBraking: 60, minimum: 35)).approach,
        CornerApproach.heavyBraking,
      );
    });

    test('braking without the speed where it started is not told heavy or not', () {
      final driving = classifyCornerDriving(_three(atBraking: null));
      expect(driving.approach, CornerApproach.braking);
      expect(driving.heavyUnknown, isTrue);
      expect(driving.typicalSpeedShedMetresPerSecond, isNull);
      expect(driving.shedLaps, 0);
    });

    test('without braking, losing 5 % of the entry speed is a lift; less is flat', () {
      final lift = classifyCornerDriving(_three(braked: false, minimum: 95));
      expect(lift.approach, CornerApproach.lift);
      expect(lift.typicalSpeedLossFraction, closeTo(0.05, 1e-9));
      expect(lift.typicalSpeedLossMetresPerSecond! * 3.6, closeTo(5, 1e-9));
      expect(lift.brakingLaps, 0);
      final flat = classifyCornerDriving(_three(braked: false, minimum: 95.1));
      expect(flat.approach, CornerApproach.flat);
    });

    test('a lift or flat reads the speed lost on the laps without braking only', () {
      final driving = classifyCornerDriving([
        _lap(minimum: 50),
        for (var i = 0; i < 3; i++) _lap(braked: false, minimum: 99),
      ]);
      expect((driving.brakingLaps, driving.lapsMeasured), (1, 4));
      expect(driving.approach, CornerApproach.flat);
      expect(driving.typicalSpeedLossFraction, closeTo(0.01, 1e-9));
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
        _lap(atBraking: 110),
        _lap(atBraking: 110),
        _lap(braked: false, minimum: 99),
        _lap(braked: false, minimum: 99),
      ]);
      expect((half.brakingLaps, half.lapsMeasured), (2, 4));
      // The typical speed taken off needs three braking laps.
      expect(half.approach, CornerApproach.braking);
      expect(half.heavyUnknown, isTrue);
      final once = classifyCornerDriving([
        _lap(),
        _lap(braked: false, minimum: 99),
        _lap(braked: false, minimum: 99),
      ]);
      // Not braking on most laps, but only two laps without braking to read
      // a lift or flat from.
      expect(once.approach, isNull);
      expect(once.approachUnavailableReason, cornerClassTooFewLaps);
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
          classifyCornerDriving(_three(minimum: minimum, unit: unit)).speedBand;
      expect(band(79.9), CornerSpeedBand.slow);
      expect(band(80), CornerSpeedBand.medium);
      expect(band(129.9), CornerSpeedBand.medium);
      expect(band(130), CornerSpeedBand.fast);
      expect(band(50, 'mph'), CornerSpeedBand.medium); // 80.5 km/h
      expect(band(22, 'm/s'), CornerSpeedBand.slow);
      final typical = classifyCornerDriving([
        for (final minimum in [60.0, 70.0, 200.0]) _lap(minimum: minimum),
      ]);
      expect(typical.typicalMinimumSpeedMetresPerSecond! * 3.6, closeTo(70, 1e-9));
      // Shown back in the laps' own unit.
      final miles = classifyCornerDriving(_three(unit: 'mph'));
      expect(miles.speedUnit, 'mph');
      expect(miles.inSpeedUnit(miles.typicalMinimumSpeedMetresPerSecond), closeTo(60, 1e-9));
    });

    test('an unknown speed unit gives no speed figures, and says why', () {
      final unknown = classifyCornerDriving(_three(unit: 'furlong/fortnight'));
      expect(unknown.speedBand, isNull);
      expect(unknown.speedBandUnavailableReason, cornerClassSpeedUnitUnknown);
      expect(unknown.approach, CornerApproach.braking);
      expect(unknown.heavyUnknown, isTrue);
      final coasting = classifyCornerDriving(
        _three(unit: 'furlong/fortnight', braked: false, minimum: 90),
      );
      // The share of the entry speed lost needs no unit; the speed does.
      expect(coasting.approach, CornerApproach.lift);
      expect(coasting.typicalSpeedLossMetresPerSecond, isNull);
    });

    test('speeds in different units are never pooled: the unit most laps used counts', () {
      // Two laps in km/h, three unlabelled (read as km/h, but never pooled
      // with a declared unit).
      final mixed = classifyCornerDriving([
        _lap(unit: 'km/h', minimum: 140),
        _lap(unit: 'kmh', minimum: 140),
        for (var i = 0; i < 3; i++) _lap(unit: '', minimum: 60),
      ]);
      expect(mixed.speedUnit, '');
      expect(mixed.otherUnitLaps, 2);
      expect(mixed.speedLaps, 3);
      expect(mixed.speedBand, CornerSpeedBand.slow);
      expect(mixed.shedLaps, 3);
      // Spellings of one unit are one unit.
      final spellings = classifyCornerDriving([
        _lap(unit: 'km/h'),
        _lap(unit: 'kmh'),
        _lap(unit: 'KPH'),
      ]);
      expect(spellings.otherUnitLaps, 0);
      expect(spellings.speedLaps, 3);
      // Too few laps in the unit counted: no band, too few laps.
      final split = classifyCornerDriving([
        _lap(unit: 'mph'),
        _lap(unit: 'mph'),
        _lap(unit: 'km/h'),
        _lap(unit: 'km/h'),
      ]);
      expect(split.speedBand, isNull);
      expect(split.otherUnitLaps, 2);
      expect(split.heavyUnknown, isTrue);
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
