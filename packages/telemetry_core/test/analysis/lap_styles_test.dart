// Lap styles (FET-223) on synthetic laps: every rule at and just past its
// boundary, thin data, and speeds kept in the unit they were read in.
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _source = 'inferredDeceleration|longacc';
const _throttle = 'measuredThrottle|accelerator';

// A lap with one sample per corner: braking [brake] m before each corner's
// entry, throttle [pickup] m after it, minimum speed [speed].
LapStyleInput _lap(
  int number,
  double seconds, {
  List<double?> brake = const [],
  List<double?> pickup = const [],
  List<double?> speed = const [],
  String unit = 'km/h',
  String brakeSource = _source,
  int? corners,
}) {
  final count =
      corners ?? [brake.length, pickup.length, speed.length].reduce((a, b) => a > b ? a : b);
  return LapStyleInput(
    lap: 'lap$number',
    seconds: seconds,
    corners: [
      for (var i = 0; i < count; ++i)
        LapCornerSample(
          cornerId: 'c$i',
          brakeBeforeEntryMeters: i < brake.length ? brake[i] : null,
          brakeSource: brakeSource,
          pickupAfterEntryMeters: i < pickup.length ? pickup[i] : null,
          pickupSource: _throttle,
          minimumSpeed: i < speed.length ? speed[i] : null,
          speedUnit: unit,
          speedSource: 'velocity',
        ),
    ],
  );
}

List<double> _all(double value, [int count = 4]) => List.filled(count, value);

/// Three plain laps (braking 50 m before, throttle 30 m after in four
/// corners) the rest are measured against, with [others] added.
List<LapStyleInput> _day(List<LapStyleInput> others) => [
  for (var i = 0; i < 3; ++i)
    _lap(i, 100.0 + i, brake: _all(50), pickup: _all(30), speed: _all(80)),
  ...others,
];

LapStyleResult _find(LapStyles styles, String lap) =>
    styles.laps.firstWhere((result) => result.lap == lap);

void main() {
  group('rules', () {
    test('a lap braking earlier and picking the throttle up later in most corners is '
        'conservative', () {
      final styles = computeLapStyles(
        _day([_lap(9, 103, brake: _all(62), pickup: _all(45), speed: _all(78))]),
      );
      final lap = _find(styles, 'lap9');
      expect(lap.style, LapStyle.conservative);
      expect(lap.brake.positive, 4);
      expect(lap.throttle.positive, 4);
      expect(lap.medianBrakeMeters, closeTo(12 * 3 / 4 + 12 / 4, 3));
      expect(lap.cornersCompared, 4);
    });

    test('braking later than typical in most corners is late braking', () {
      final styles = computeLapStyles(_day([_lap(9, 99, brake: _all(40), pickup: _all(30))]));
      final lap = _find(styles, 'lap9');
      expect(lap.style, LapStyle.lateBraking);
      expect(lap.brake.negative, 4);
      expect(lap.medianBrakeMeters, closeTo(-10, 2));
    });

    test('the throttle earlier than typical in most corners is early throttle', () {
      final styles = computeLapStyles(_day([_lap(9, 99, brake: _all(50), pickup: _all(15))]));
      expect(_find(styles, 'lap9').style, LapStyle.earlyThrottle);
    });

    test('late braking with early throttle is mixed, and so is earlier braking alone', () {
      final styles = computeLapStyles(
        _day([
          _lap(8, 99, brake: _all(40), pickup: _all(15)),
          _lap(9, 105, brake: _all(62), pickup: _all(30)),
        ]),
      );
      expect(_find(styles, 'lap8').style, LapStyle.mixed);
      // Earlier braking, throttle where it was: only half of "conservative".
      expect(_find(styles, 'lap9').style, LapStyle.mixed);
    });

    test('a lap near the typical in every corner is typical', () {
      final styles = computeLapStyles(_day([_lap(9, 101, brake: _all(52), pickup: _all(33))]));
      expect(_find(styles, 'lap9').style, LapStyle.typical);
    });

    test('a threshold is beyond, not at: exactly 5 m in braking is not later', () {
      // The typical of the three plain laps and this one is 50 m; the fourth
      // lap sits exactly the threshold away, then just past it.
      final at = computeLapStyles(_day([_lap(9, 99, brake: _all(50 - lapStylesBrakeMeters))]));
      expect(_find(at, 'lap9').brake.negative, 0);
      final past = computeLapStyles(
        _day([_lap(9, 99, brake: _all(50 - lapStylesBrakeMeters - 0.5))]),
      );
      expect(_find(past, 'lap9').brake.negative, 4);
    });

    test('"most" is more than half: two of four is not, three of four is', () {
      LapStyleInput lap(int n, List<double> brake) => _lap(n, 99, brake: brake);
      final half = computeLapStyles(
        _day([
          lap(9, [42, 42, 50, 50]),
        ]),
      );
      expect(_find(half, 'lap9').brake.negative, 2);
      expect(_find(half, 'lap9').style, LapStyle.typical);
      final most = computeLapStyles(
        _day([
          lap(9, [42, 42, 42, 50]),
        ]),
      );
      expect(_find(most, 'lap9').style, LapStyle.lateBraking);
    });

    test('fewer than three corners measured is not "most corners"', () {
      // Two corners measured late, but only two: not enough to call a style.
      final styles = computeLapStyles(
        _day([
          _lap(9, 99, brake: [30, 30, null, null]),
        ]),
      );
      final lap = _find(styles, 'lap9');
      expect(lap.brake.measured, 2);
      expect(lap.style, isNot(LapStyle.lateBraking));
    });

    test('a lap far from typical in most corners is an outlier', () {
      final styles = computeLapStyles(_day([_lap(9, 99, brake: _all(80), pickup: _all(30))]));
      final lap = _find(styles, 'lap9');
      expect(lap.style, LapStyle.outlier);
      expect(lap.outlierReason, LapOutlierReason.unlike);
      expect(lap.extremeCorners, 4);
    });

    test('a lap far from typical in only a few corners is not', () {
      final styles = computeLapStyles(
        _day([
          _lap(9, 99, brake: [80, 80, 50, 50], pickup: _all(30)),
        ]),
      );
      expect(_find(styles, 'lap9').outlierReason, LapOutlierReason.none);
    });

    test('a lap measured in too few corners is an outlier for lack of data', () {
      final styles = computeLapStyles(
        _day([
          LapStyleInput(
            lap: 'lap9',
            seconds: 99,
            corners: [
              const LapCornerSample(
                cornerId: 'c0',
                brakeBeforeEntryMeters: 50,
                brakeSource: _source,
              ),
            ],
          ),
        ]),
      );
      final lap = _find(styles, 'lap9');
      expect(lap.style, LapStyle.outlier);
      expect(lap.outlierReason, LapOutlierReason.fewCorners);
    });

    test('a slow lap is not an outlier for its speed alone', () {
      // Minimum speeds 30 percent under typical in every corner, driven the
      // same way: a slower lap, not a different style.
      final styles = computeLapStyles(
        _day([_lap(9, 120, brake: _all(50), pickup: _all(30), speed: _all(56))]),
      );
      final lap = _find(styles, 'lap9');
      expect(lap.style, LapStyle.typical);
      expect(lap.minimumSpeed.negative, 4);
      expect(lap.medianMinimumSpeed, closeTo(-24, 0.1));
    });
  });

  group('groups', () {
    final styles = computeLapStyles([
      ..._day([
        _lap(5, 98.5, brake: _all(40), pickup: _all(30)),
        _lap(6, 99.5, brake: _all(40), pickup: _all(30)),
        _lap(7, 120, brake: _all(40), pickup: _all(30)),
        _lap(8, 99, brake: _all(62), pickup: _all(45)),
      ]),
    ]);

    test('keep the quickest lap of each style and its gap to the day best', () {
      expect(styles.best!.lap, 'lap5');
      final late = styles.group(LapStyle.lateBraking)!;
      expect(late.laps.map((lap) => lap.lap), ['lap5', 'lap6', 'lap7']);
      expect(late.best.lap, 'lap5');
      expect(late.bestDeltaSeconds, 0);
      final conservative = styles.group(LapStyle.conservative)!;
      expect(conservative.best.lap, 'lap8');
      expect(conservative.bestDeltaSeconds, closeTo(0.5, 1e-9));
      expect(styles.bestLapGroup!.style, LapStyle.lateBraking);
    });

    test('give a typical time only with at least three laps', () {
      expect(styles.group(LapStyle.lateBraking)!.typicalSeconds, 99.5);
      expect(styles.group(LapStyle.conservative)!.typicalSeconds, isNull);
    });

    test('count how many of a style are among the quicker half', () {
      // Seven laps: the quicker half is the four quickest: 98.5, 99, 99.5, 100.
      expect(styles.group(LapStyle.lateBraking)!.quickerHalfCount, 2);
      expect(styles.group(LapStyle.conservative)!.quickerHalfCount, 1);
      expect(styles.group(LapStyle.typical)!.quickerHalfCount, 1);
    });

    test('list the styles in a fixed order, only those with laps', () {
      expect(styles.groups.map((group) => group.style), [
        LapStyle.conservative,
        LapStyle.lateBraking,
        LapStyle.typical,
      ]);
      expect(styles.group(LapStyle.outlier), isNull);
      expect(styles.lapCount, 7);
    });
  });

  group('thin data', () {
    test('fewer than three laps are not grouped', () {
      final styles = computeLapStyles([
        _lap(0, 100, brake: _all(50)),
        _lap(1, 101, brake: _all(50)),
      ]);
      expect(styles.available, isFalse);
      expect(styles.unavailableReason, lapStylesTooFewLaps);
      expect(styles.lapCount, 2);
      expect(styles.groups, isEmpty);
    });

    test('laps with no valid time are left out', () {
      final styles = computeLapStyles([
        _lap(0, double.nan, brake: _all(50)),
        _lap(1, 0, brake: _all(50)),
        _lap(2, 100, brake: _all(50)),
      ]);
      expect(styles.unavailableReason, lapStylesTooFewLaps);
      expect(styles.lapCount, 1);
    });

    test('three laps give a typical, two laps measured the same way do not', () {
      final styles = computeLapStyles([
        _lap(0, 100, brake: _all(50), pickup: _all(30)),
        _lap(1, 101, brake: _all(50), pickup: _all(30)),
        _lap(2, 102, brake: _all(70), pickup: _all(30), brakeSource: 'inferredDeceleration|other'),
      ]);
      // The third lap's braking came from another channel, so two laps share
      // a source: no typical for braking, and with the throttle only (four
      // corners) there is still a day.
      expect(styles.available, isTrue);
      expect(_find(styles, 'lap2').brake.measured, 0);
      expect(_find(styles, 'lap0').brake.measured, 0);
      expect(_find(styles, 'lap2').throttle.measured, 4);
    });

    test('fewer than three corners with a typical are not grouped', () {
      final styles = computeLapStyles([
        for (var i = 0; i < 4; ++i) _lap(i, 100.0 + i, brake: _all(50, 2)),
      ]);
      expect(styles.unavailableReason, lapStylesTooFewCorners);
      expect(styles.cornerCount, 2);
    });

    test('nothing measured at all is not grouped, and says why', () {
      final styles = computeLapStyles([for (var i = 0; i < 4; ++i) _lap(i, 100.0 + i, corners: 4)]);
      expect(styles.unavailableReason, lapStylesTooFewCorners);
      expect(styles.cornerCount, 0);
    });
  });

  group('speed units', () {
    test('speeds are compared in one unit only, never converted', () {
      // Three laps in km/h and three in mph at the same corners: each unit
      // has its own typical, and nothing is subtracted across them.
      final styles = computeLapStyles([
        for (var i = 0; i < 3; ++i)
          _lap(i, 100.0 + i, brake: _all(50), pickup: _all(30), speed: _all(80), unit: 'km/h'),
        for (var i = 3; i < 6; ++i)
          _lap(i, 100.0 + i, brake: _all(50), pickup: _all(30), speed: _all(50), unit: 'mph'),
        _lap(6, 99, brake: _all(50), pickup: _all(30), speed: _all(60), unit: 'km/h'),
      ]);
      final lap = _find(styles, 'lap6');
      expect(lap.speedUnit, 'km/h');
      // Against the km/h laps only (80, 80, 80, 60): the typical stays 80.
      expect(lap.medianMinimumSpeed, closeTo(-20, 1e-9));
      for (final other in styles.laps.where((l) => l.lap != 'lap6')) {
        expect(other.medianMinimumSpeed, closeTo(0, 1e-9), reason: '${other.lap}');
      }
    });

    test('"kmh" and "km/h" are one unit, an undeclared unit is its own', () {
      final styles = computeLapStyles([
        _lap(0, 100, brake: _all(50), pickup: _all(30), speed: _all(80), unit: 'km/h'),
        _lap(1, 101, brake: _all(50), pickup: _all(30), speed: _all(80), unit: 'kmh'),
        _lap(2, 102, brake: _all(50), pickup: _all(30), speed: _all(80), unit: ''),
        _lap(3, 103, brake: _all(50), pickup: _all(30), speed: _all(60), unit: 'km/h'),
      ]);
      // Two km/h laps and a third written "kmh": three in one unit; the
      // unlabelled one is not pooled with them.
      expect(_find(styles, 'lap3').medianMinimumSpeed, closeTo(-20, 1e-9));
      expect(_find(styles, 'lap2').medianMinimumSpeed, isNull);
      expect(_find(styles, 'lap2').speedUnit, '');
    });
  });
}
