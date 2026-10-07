// Grip and balance proxies (FET-229) on synthetic recordings: every
// threshold at and just past its boundary, units kept as declared, and
// values measured differently never pooled.
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/src/telemetry_session.dart'
    show adoptChannelTimestamps, adoptChannelValues;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

typedef _Channel = (String unit, double Function(double t) value);

// A recording sampled at [hz] for [seconds]: each channel named as given,
// with its unit and value over time.
TelemetrySession _session(
  Map<String, _Channel> channels, {
  Map<String, String> aliases = const {},
  Map<String, String> metadata = const {},
  double seconds = 10,
  double hz = 10,
}) {
  final count = (seconds * hz).round() + 1;
  final clock = adoptChannelTimestamps(
    Float64List.fromList([for (var i = 0; i < count; ++i) i / hz]),
  );
  return TelemetrySession(
    duration: seconds,
    startTime: 0,
    metadata: metadata,
    channels: {
      for (final MapEntry(key: name, value: (unit, value)) in channels.entries)
        name: TelemetryChannel(
          name: name,
          unit: unit,
          timestamps: clock,
          values: adoptChannelValues(Float32List.fromList([for (final t in clock) value(t)])),
        ),
    },
    aliases: aliases,
    warnings: const [],
    timingGates: const [],
    sampleCount: count,
  );
}

const _accelerations = {
  'lateralAcceleration': 'latacc',
  'longitudinalAcceleration': 'longacc',
  'speed': 'velocity',
};

DayLapRow _row(int number, {String runId = 'run1'}) => DayLapRow(
  runId: runId,
  runName: 'Session 1',
  type: LapSectionType.lap,
  lapNumber: number,
  start: number * 100.0,
  end: number * 100.0 + 90,
  sourceRevision: 'a' * 64,
);

GripLapValue _value(
  int lap,
  double value, {
  GripSource source = const GripSource(channel: 'a', unit: 'g'),
}) => GripLapValue(lap: _row(lap), value: value, samples: 10, source: source);

void main() {
  group('aggregateGripLaps', () {
    test('the typical value needs three laps: two are not enough', () {
      final two = aggregateGripLaps([_value(1, 0.8), _value(2, 1.0)]);
      expect(two.peak, 1.0);
      expect(two.peakLap!.lapNumber, 2);
      expect(two.typical, isNull);
      expect(two.typicalReason, gripTooFewLaps);
      expect(two.lapCount, 2);
      final three = aggregateGripLaps([_value(1, 0.8), _value(2, 1.0), _value(3, 0.9)]);
      expect(gripMinimumTypicalLaps, 3);
      expect(three.typical, closeTo(0.9, 1e-12));
      expect(three.typicalReason, isEmpty);
      final four = aggregateGripLaps([
        _value(1, 0.8),
        _value(2, 1.0),
        _value(3, 0.9),
        _value(4, 0.7),
      ]);
      expect(four.typical, closeTo(0.85, 1e-12), reason: 'the median of an even count');
    });

    test('values measured differently are left out, never pooled', () {
      const other = GripSource(channel: 'a', unit: 'm/s²');
      final values = [_value(1, 0.8), _value(2, 0.9), _value(3, 9.0, source: other)];
      final most = aggregateGripLaps(values);
      expect(most.source.unit, 'g');
      expect(most.peak, 0.9);
      expect(most.lapCount, 2);
      expect(most.leftOut, 1);
      final preferred = aggregateGripLaps(values, prefer: _row(3).reference);
      expect(preferred.source.unit, 'm/s²');
      expect(preferred.peak, 9.0);
      expect(preferred.leftOut, 2);
      // An assumed g is not a declared g either.
      final assumed = aggregateGripLaps([
        _value(1, 0.8),
        _value(
          2,
          0.9,
          source: const GripSource(channel: 'a', unit: 'g', unitAssumed: true),
        ),
      ], prefer: _row(1).reference);
      expect(assumed.lapCount, 1);
      expect(assumed.leftOut, 1);
    });

    test('without any value, the reason most laps give', () {
      final none = aggregateGripLaps([
        GripLapValue(lap: _row(1), reason: gripTooFewSamples),
        GripLapValue(lap: _row(2), reason: gripNotTimed),
        GripLapValue(lap: _row(3), reason: gripNotTimed),
      ]);
      expect(none.known, isFalse);
      expect(none.reason, gripNotTimed);
      expect(none.typical, isNull);
      expect(aggregateGripLaps(const []).reason, gripTooFewLaps);
    });
  });

  group('units', () {
    test('a declared g and a declared m/s² are kept as declared', () {
      final g = GripChannels.of(
        _session({
          'latacc': ('g', (_) => 0.5),
          'longacc': ('m/s²', (_) => -4.0),
          'velocity': ('km/h', (_) => 90),
        }, aliases: _accelerations),
      );
      expect(g.lateralSource, const GripSource(channel: 'latacc', unit: 'g'));
      expect(g.longitudinalSource, const GripSource(channel: 'longacc', unit: 'm/s²'));
      expect(g.peakDeceleration(1, 2).value, closeTo(4.0, 1e-6), reason: 'not converted');
    });

    test('a unit declared on a VBO [header] line is declared', () {
      final g = GripChannels.of(
        _session(
          {'latacc-calc': ('', (_) => 0.5), 'velocity': ('km/h', (_) => 90)},
          aliases: {'lateralAcceleration': 'latacc-calc', 'speed': 'velocity'},
          metadata: {'header.12': 'latacc-calc g'},
        ),
      );
      expect(g.lateralSource.unit, 'g');
      expect(g.lateralSource.unitAssumed, isFalse);
    });

    test('an undeclared acceleration unit is g, marked assumed', () {
      final g = GripChannels.of(
        _session({
          'latacc': ('', (_) => 0.5),
          'longacc': ('', (_) => 0.1),
          'velocity': ('km/h', (_) => 90),
        }, aliases: _accelerations),
      );
      expect(g.lateralSource, const GripSource(channel: 'latacc', unit: 'g', unitAssumed: true));
      expect(g.longitudinalSource.unitAssumed, isTrue);
    });

    test('a unit not supported is not known, and no other channel stands in', () {
      final g = GripChannels.of(
        _session({
          'latacc': ('ft/s2', (_) => 10),
          'longacc': ('ft/s2', (_) => 10),
          'velocity': ('km/h', (t) => 50 + t),
        }, aliases: _accelerations),
      );
      expect(g.peakLateral(0, 5).reason, gripUnsupportedUnit);
      expect(g.peakDeceleration(0, 5).reason, gripUnsupportedUnit);
      expect(g.longitudinalSource.isNone, isTrue, reason: 'not replaced by the speed');
    });

    test('without a longitudinal channel the acceleration comes from speed', () {
      // 0.5 g: 3.6 × 0.5 × 9.80665 km/h more every second.
      final g = GripChannels.of(
        _session(
          {'velocity': ('km/h', (t) => 20 + 3.6 * 0.5 * standardGravity * t)},
          aliases: {'speed': 'velocity'},
        ),
      );
      expect(
        g.longitudinalSource,
        const GripSource(channel: 'velocity', unit: 'g', fromSpeed: true),
      );
      expect(g.meanAcceleration(2, 8).value, closeTo(0.5, 1e-3));
      expect(g.peakDeceleration(2, 8).reason, gripNoBraking);
      expect(g.peakLateral(2, 8).reason, gripNoLateralChannel);
      // The speed change is taken over ±0.25 s: none at the recording's edges.
      expect(gripSpeedDerivedHalfSpanSeconds, 0.25);
      expect(g.meanAcceleration(0, 0.2).reason, gripTooFewSamples);
      // A speed without a unit is read as km/h, and the value says so.
      final none = GripChannels.of(
        _session({'velocity': ('', (t) => 50)}, aliases: {'speed': 'velocity'}),
      );
      expect(none.longitudinalSource.unitAssumed, isTrue);
      final unknown = GripChannels.of(
        _session({'velocity': ('furlong/fortnight', (t) => 50)}, aliases: {'speed': 'velocity'}),
      );
      expect(unknown.meanAcceleration(1, 5).reason, gripSpeedUnitNotSupported);
      final nothing = GripChannels.of(_session({'other': ('', (t) => 1)}));
      expect(nothing.meanAcceleration(1, 5).reason, gripNoSpeedChannel);
    });
  });

  group('lap values', () {
    final g = GripChannels.of(
      _session({
        'latacc': ('g', (t) => t < 5 ? 0.4 + 0.1 * t : 4.0 + (t >= 6 ? 0.01 : 0)),
        'longacc': ('g', (t) => t < 5 ? -0.2 * t : 0.3),
        'velocity': ('km/h', (_) => 90),
      }, aliases: _accelerations),
    );

    test('needs five samples in the window: four are not enough', () {
      expect(gripMinimumWindowSamples, 5);
      // 10 Hz: 0.0, 0.1, 0.2, 0.3 are four samples, to 0.4 five.
      expect(g.peakLateral(0, 0.35).reason, gripTooFewSamples);
      expect(g.peakLateral(0, 0.4).value, closeTo(0.44, 1e-6));
      expect(g.peakLateral(0, 0.4).samples, 5);
    });

    test('a value beyond 4 g is left out, 4 g itself is kept', () {
      expect(g.peakLateral(5, 5.9).value, closeTo(4.0, 1e-6));
      expect(g.peakLateral(6, 7).reason, gripTooFewSamples, reason: 'all beyond 4 g');
    });

    test('braking is the highest deceleration; acceleration the mean', () {
      expect(g.peakDeceleration(0, 4).value, closeTo(0.8, 1e-6));
      expect(g.peakDeceleration(5, 7).reason, gripNoBraking);
      expect(g.meanAcceleration(5, 7).value, closeTo(0.3, 1e-6));
    });

    test('an m/s² limit is 4 g in m/s²', () {
      final metric = GripChannels.of(
        _session({
          'latacc': (
            'm/s2',
            (t) => t < 5 ? 4 * standardGravity - 0.01 : 4 * standardGravity + 0.01,
          ),
          'velocity': ('km/h', (_) => 90),
        }, aliases: _accelerations),
      );
      expect(metric.peakLateral(0, 4).value, closeTo(4 * standardGravity - 0.01, 1e-4));
      expect(metric.peakLateral(6, 9).reason, gripTooFewSamples);
    });
  });

  group('balance', () {
    // Cornering at [lateral] g and [speed] m/s with exactly the yaw rate that
    // needs ([ratio] times it).
    GripChannels corner({
      double lateral = 1.0,
      double speed = 20,
      double ratio = 1.0,
      String yawName = 'yaw_rate',
      String yawUnit = 'deg/s',
      double? until,
    }) => GripChannels.of(
      _session(
        {
          'latacc': ('g', (t) => until != null && t > until ? 0.0 : lateral),
          'velocity': ('km/h', (_) => speed * 3.6),
          yawName: (yawUnit, (_) => ratio * lateral * standardGravity / speed * 180 / pi),
        },
        aliases: {'lateralAcceleration': 'latacc', 'speed': 'velocity'},
      ),
    );

    test('a yaw rate matching the cornering reads 1', () {
      expect(corner().balance(0, 5).value, closeTo(1.0, 1e-4));
      expect(corner(ratio: 1.2).balance(0, 5).value, closeTo(1.2, 1e-4));
    });

    test('only cornering from 0.3 g: 0.29 g is left out', () {
      expect(gripBalanceMinimumLateralG, 0.3);
      expect(corner(lateral: 0.3).balance(0, 5).value, closeTo(1.0, 1e-3));
      expect(corner(lateral: 0.29).balance(0, 5).reason, gripTooFewSamples);
    });

    test('only from 10 m/s: 9.9 m/s is left out', () {
      expect(gripBalanceMinimumSpeedMetresPerSecond, 10.0);
      expect(corner(speed: 10).balance(0, 5).value, closeTo(1.0, 1e-3));
      expect(corner(speed: 9.9).balance(0, 5).reason, gripTooFewSamples);
    });

    test('needs ten such samples: nine are not enough', () {
      expect(gripBalanceMinimumSamples, 10);
      // Cornering up to 0.9 s: nine samples; to 1.0 s: ten.
      expect(corner(until: 0.85).balance(0, 5).reason, gripTooFewSamples);
      expect(corner(until: 0.95).balance(0, 5).samples, 10);
      expect(corner(until: 0.95).balance(0, 5).value, closeTo(1.0, 1e-4));
    });

    test('rad/s is read as radians', () {
      final radians = GripChannels.of(
        _session(
          {
            'latacc': ('g', (_) => 1.0),
            'velocity': ('km/h', (_) => 72),
            'YawRate': ('rad/s', (_) => standardGravity / 20),
          },
          aliases: {'lateralAcceleration': 'latacc', 'speed': 'velocity'},
        ),
      );
      expect(radians.balance(0, 5).value, closeTo(1.0, 1e-4));
    });

    test('a gyro in the device\'s axes is not the car\'s yaw rate', () {
      final device = corner(yawName: 'z_rate_of_rotation-gyro');
      expect(device.hasBalance, isFalse);
      expect(device.balance(0, 5).reason, gripDeviceAxesOnly);
    });

    test('a yaw rate without a known unit is not read', () {
      expect(corner(yawUnit: '').balance(0, 5).reason, gripYawUnitUnknown);
      expect(corner(yawUnit: 'rpm').balance(0, 5).reason, gripYawUnitUnknown);
    });

    test('without any rotation channel balance is not known', () {
      final none = GripChannels.of(
        _session({
          'latacc': ('g', (_) => 1.0),
          'velocity': ('km/h', (_) => 72),
        }, aliases: _accelerations),
      );
      expect(none.balance(0, 5).reason, gripNoYawChannel);
    });

    test('without lateral acceleration balance says so', () {
      final none = GripChannels.of(
        _session(
          {'velocity': ('km/h', (_) => 72), 'yaw_rate': ('deg/s', (_) => 10)},
          aliases: {'speed': 'velocity'},
        ),
      );
      expect(none.balance(0, 5).reason, gripNoLateralChannel);
    });
  });

  group('speed bands', () {
    // [speed] in [unit]; lateral 0.5 g throughout.
    GripChannels banded(String unit, double Function(double) speed) => GripChannels.of(
      _session(
        {'latacc': ('g', (_) => 0.5), 'longacc': ('g', (t) => -0.4), 'velocity': (unit, speed)},
        aliases: _accelerations,
        seconds: 20,
      ),
    );

    test('80 km/h starts the middle band; 79.9 km/h is below it', () {
      expect(gripBandEdgesKilometresPerHour, [80.0, 120.0]);
      final below = banded('km/h', (_) => 79.9).bandPeaks(0, 10);
      expect(below[0].lateral.value, closeTo(0.5, 1e-6));
      expect(below[1].lateral.reason, gripTooFewSamples);
      final at = banded('km/h', (_) => 80).bandPeaks(0, 10);
      expect(at[0].lateral.reason, gripTooFewSamples);
      expect(at[1].lateral.value, closeTo(0.5, 1e-6));
      expect(at[1].braking.value, closeTo(0.4, 1e-6));
      expect(at[1].accelerating.reason, gripNoAcceleration, reason: 'never accelerating');
      final high = banded('km/h', (_) => 120).bandPeaks(0, 10);
      expect(high[2].lateral.value, closeTo(0.5, 1e-6));
    });

    test('mph has its own edges; a speed with no unit uses km/h\'s', () {
      expect(gripBandEdgesMilesPerHour, [50.0, 75.0]);
      expect(banded('mph', (_) => 50).bandPeaks(0, 10)[1].lateral.value, isNotNull);
      expect(banded('mph', (_) => 49.9).bandPeaks(0, 10)[0].lateral.value, isNotNull);
      expect(banded('', (_) => 80).bandEdges, gripBandEdgesKilometresPerHour);
      expect(banded('m/s', (_) => 30).bandEdges, isNull);
      expect(banded('m/s', (_) => 30).bandPeaks(0, 10), isEmpty);
    });

    test('a band needs twenty samples on the lap: nineteen are not enough', () {
      expect(gripMinimumBandSamples, 20);
      // Below 80 km/h for 1.9 s (19 samples at 10 Hz) or 2.0 s (20 samples).
      final short = banded('km/h', (t) => t < 1.85 ? 60 : 100).bandPeaks(0, 10);
      expect(short[0].lateral.reason, gripTooFewSamples);
      expect(short[0].lateral.samples, 19);
      final enough = banded('km/h', (t) => t < 1.95 ? 60 : 100).bandPeaks(0, 10);
      expect(enough[0].lateral.samples, 20);
      expect(enough[0].lateral.value, closeTo(0.5, 1e-6));
    });
  });

  group('the day', () {
    // Three laps at 30 m/s braking to [slow] m/s into the second corner.
    double Function(double) lap(double brake, double slow) => (d) {
      if (d < brake) return 30;
      if (d < 326) return 30 + (slow - 30) * (d - brake) / (326 - brake);
      if (d < 360) return slow;
      if (d < 420) return slow + (30 - slow) * (d - 360) / 60;
      return 30;
    };

    DayRunInput run(TelemetrySession session) => DayRunInput(
      runId: 'run1',
      name: 'Session 1',
      contentSha256: 'a' * 64,
      session: session,
      laps: deriveSourceLapSession(session),
    );

    test('comes with the theoretical best, over the ranked laps only', () {
      final input = run(
        rectangleSession([lap(250, 18), lap(270, 20), lap(240, 17)], pedals: true, lateral: true),
      );
      final analysis = analyzeDay([input]);
      final result = dayTheoreticalBest(analysis, {
        'run1': OutingRun(input.session, input.laps),
      }, random: Random(1));
      expect(result.state, DayTheoreticalBestState.ready);
      final grip = result.grip!;
      final ranked = analysis.chosenGroup!.ranking!.eligibleLaps.length;
      expect(analysis.rows.length, greaterThan(ranked), reason: 'out and in laps are rows');
      expect(grip.sessions.single.lapCount, ranked);
      expect(grip.corners.map((c) => c.segmentId), result.corners.map((c) => c.segmentId));
      final second = grip.cornerAt(result.corners[1].segmentIndex)!;
      // 30 m/s round a 30 m radius would be 3.06 g; the slowest lap's 17 m/s
      // is 0.98 g. The rectangle's channels declare no unit: g is assumed.
      expect(second.lateral.source.unitAssumed, isTrue);
      expect(second.lateral.lapCount, ranked);
      expect(second.lateral.typical, isNotNull);
      expect(second.braking.peak, greaterThan(0.3));
      expect(second.traction.typical, isNotNull);
      expect(second.balance.reason, gripNoYawChannel);
      expect(grip.sessions.single.balance.reason, gripNoYawChannel);
      expect(result.withRemeasuredRuns(const {}).grip, same(grip));
    });

    test('a lap not timed through a corner, or without its recording, is not known', () {
      final input = run(
        rectangleSession([lap(250, 18), lap(270, 20), lap(240, 17)], pedals: true, lateral: true),
      );
      final analysis = analyzeDay([input]);
      final result = dayTheoreticalBest(analysis, {
        'run1': OutingRun(input.session, input.laps),
      }, random: Random(1));
      final rows = [for (final lap in result.laps) lap.lap];
      final untimed = dayGripProxies(rows, result.corners, (_) => input.session, (_, _) => null);
      expect(untimed.corners.first.lateral.reason, gripNotTimed);
      expect(untimed.corners.first.braking.reason, gripNotTimed);
      final missing = dayGripProxies(rows, result.corners, (_) => null, (_, _) => (0.0, 1.0));
      expect(missing.sessions.single.bandsReason, gripNoRecording);
      expect(missing.sessions.single.lapCount, rows.length);
      expect(missing.corners.first.traction.reason, gripNoRecording);
    });
  });

  group('placeholders of zeros', () {
    final zeros = GripChannels.of(
      _session({
        'latacc': ('g', (_) => 0.0),
        'longacc': ('g', (_) => 0.0),
        'velocity': ('km/h', (_) => 90),
      }, aliases: _accelerations),
    );

    test('a channel of zeros only is not known, never 0.00 g', () {
      expect(zeros.peakLateral(0, 5).reason, gripAllZero);
      expect(zeros.meanAcceleration(0, 5).reason, gripAllZero);
      expect(zeros.peakDeceleration(0, 5).reason, gripAllZero);
      final bands = zeros.bandPeaks(0, 10);
      expect(bands[1].lateral.reason, gripAllZero);
      expect(bands[1].braking.reason, gripAllZero);
      expect(bands[1].accelerating.reason, gripAllZero);
    });

    test('one sample off zero is a value', () {
      final one = GripChannels.of(
        _session({
          'latacc': ('g', (t) => t == 1.0 ? 0.2 : 0.0),
          'velocity': ('km/h', (_) => 90),
        }, aliases: _accelerations),
      );
      expect(one.peakLateral(0, 5).value, closeTo(0.2, 1e-6));
    });

    test('from speed, a steady speed is a real zero', () {
      final steady = GripChannels.of(
        _session({'velocity': ('km/h', (_) => 90)}, aliases: {'speed': 'velocity'}),
      );
      expect(steady.meanAcceleration(1, 5).value, 0.0);
      expect(steady.peakDeceleration(1, 5).reason, gripNoBraking);
    });
  });

  group('balance signs', () {
    // Cornering at 1 g and 20 m/s; the yaw rate matches it, with the sign
    // [sign] gives it at each time.
    GripChannels signed(double Function(double t) sign) => GripChannels.of(
      _session(
        {
          'latacc': ('g', (t) => 1.0),
          'velocity': ('km/h', (_) => 72),
          'yaw_rate': ('deg/s', (t) => sign(t) * standardGravity / 20 * 180 / pi),
        },
        aliases: {'lateralAcceleration': 'latacc', 'speed': 'velocity'},
      ),
    );

    test('a yaw rate of the other sign convention reads the same', () {
      expect(signed((_) => -1).balance(0, 5).value, closeTo(1.0, 1e-4));
    });

    test('the sign convention is the recording\'s: samples against it are skipped', () {
      // Against it from 8 s on (21 of 101 samples), and three times as large.
      final mixed = GripChannels.of(
        _session(
          {
            'latacc': ('g', (t) => 1.0),
            'velocity': ('km/h', (_) => 72),
            'yaw_rate': ('deg/s', (t) => (t < 7.95 ? 1 : -3) * standardGravity / 20 * 180 / pi),
          },
          aliases: {'lateralAcceleration': 'latacc', 'speed': 'velocity'},
        ),
      );
      expect(mixed.yawSignMatchesLateral, isTrue);
      final value = mixed.balance(0, 10);
      expect(value.value, closeTo(1.0, 1e-4));
      expect(value.samples, 80, reason: '0.0 to 7.9 s');
      // Decided once for the recording, not per window: in a window of only
      // samples against it, they are still skipped.
      expect(mixed.balance(8, 10).reason, gripTooFewSamples);
      expect(mixed.balance(8, 10).samples, 0);
    });

    test('a gyro named for yaw but in device axes is not the car\'s', () {
      final device = GripChannels.of(
        _session(
          {
            'latacc': ('g', (_) => 1.0),
            'velocity': ('km/h', (_) => 72),
            'yaw_rate-gyro': ('deg/s', (_) => 28),
          },
          aliases: {'lateralAcceleration': 'latacc', 'speed': 'velocity'},
        ),
      );
      expect(device.balance(0, 5).reason, gripDeviceAxesOnly);
    });

    test('a balance with a unit assumed says so', () {
      final assumed = GripChannels.of(
        _session(
          {
            'latacc': ('', (_) => 1.0),
            'velocity': ('km/h', (_) => 72),
            'yaw_rate': ('deg/s', (_) => standardGravity / 20 * 180 / pi),
          },
          aliases: {'lateralAcceleration': 'latacc', 'speed': 'velocity'},
        ),
      );
      expect(assumed.balance(0, 5).source.unitAssumed, isTrue);
    });
  });

  test('a speed without a unit gets km/h bands, marked assumed', () {
    final rows = [_row(0)];
    final grip = dayGripProxies(
      rows,
      const [],
      (_) => _session(
        {'latacc': ('g', (_) => 0.5), 'velocity': ('', (_) => 60)},
        aliases: _accelerations,
        seconds: 100,
      ),
      (_, _) => null,
    );
    final band = grip.sessions.single.bands.first;
    expect(band.upper, 80);
    expect(band.speedUnit, '');
    expect(band.speedUnitAssumed, isTrue);
  });

  test('laps without a value are counted', () {
    final figure = aggregateGripLaps([
      _value(1, 0.8),
      GripLapValue(lap: _row(2), reason: gripTooFewSamples),
    ]);
    expect(figure.lapCount, 1);
    expect(figure.unmeasured, 1);
    expect(aggregateGripLaps([GripLapValue(lap: _row(2), reason: gripNotTimed)]).unmeasured, 1);
  });

  test('a corner across the start/finish line is read from both stretches of the lap', () {
    double Function(double) lap(double brake, double slow) => (d) {
      if (d < brake) return 30;
      if (d < 326) return 30 + (slow - 30) * (d - brake) / (326 - brake);
      if (d < 360) return slow;
      if (d < 420) return slow + (30 - slow) * (d - 360) / 60;
      return 30;
    };
    final session = rectangleSession(
      [lap(250, 18), lap(270, 20), lap(240, 17)],
      pedals: true,
      lateral: true,
    );
    final input = DayRunInput(
      runId: 'run1',
      name: 'Session 1',
      contentSha256: 'a' * 64,
      session: session,
      laps: deriveSourceLapSession(session),
    );
    final result = dayTheoreticalBest(analyzeDay([input]), {
      'run1': OutingRun(input.session, input.laps),
    }, random: Random(1));
    // The second corner (where the laps brake and pick up again), stretched
    // back across the line to 60 m before it.
    final first = result.corners[1];
    final length = result.axisLengthMeters;
    final across = DayCorner(
      segmentIndex: 99,
      segmentId: 'across',
      name: 'Across',
      startProgressMeters: length - 60,
      endProgressMeters: first.endProgressMeters,
      laps: first.laps,
      traces: first.traces,
    );
    final rows = [for (final lap in result.laps) lap.lap];
    final grip = dayGripProxies(rows, [across], (_) => session, (_, _) => null);
    final corner = grip.corners.single;
    expect(corner.lateral.known, isTrue, reason: corner.lateral.reason);
    expect(corner.lateral.lapCount, rows.length);
    // Read on its own, the second corner.
    final alone = dayGripProxies(rows, [first], (_) => session, (lap, index) {
      final sectors = result.laps.firstWhere((l) => l.lap.reference == lap.reference).times.sectors;
      final s = sectors[first.segmentIndex];
      return (s.startTime!, s.endTime!);
    });
    // Its stretch after the line also holds the first corner, taken faster.
    expect(corner.lateral.peak, greaterThanOrEqualTo(alone.corners.single.lateral.peak!));
    expect(corner.braking.peak, closeTo(alone.corners.single.braking.peak!, 1e-6));
    expect(corner.traction.known, isTrue, reason: corner.traction.reason);
    expect(across.endProgressMeters, lessThan(across.startProgressMeters));
    // Without the crossing handled, the same corner would not be timed.
    final untimed = DayCorner(
      segmentIndex: 99,
      segmentId: 'inside',
      name: 'Inside',
      startProgressMeters: 10,
      endProgressMeters: first.endProgressMeters,
      laps: first.laps,
      traces: first.traces,
    );
    expect(
      dayGripProxies(rows, [untimed], (_) => session, (_, _) => null).corners.single.lateral.reason,
      gripNotTimed,
    );
  });

  group('the slowest point', () {
    // Slowest at 3 s; the speed is missing from 1.0 to 1.5 s.
    final gappy = GripChannels.of(
      _session(
        {'velocity': ('km/h', (t) => t >= 0.95 && t <= 1.55 ? double.nan : 60 + (t - 3).abs())},
        aliases: {'speed': 'velocity'},
      ),
    );

    test('is the lowest recorded speed in the stretches', () {
      expect(gappy.slowestTime([(2.0, 4.0)]), closeTo(3.0, 1e-9));
      expect(
        gappy.slowestTime([(2.0, 2.5), (3.5, 4.0)]),
        anyOf(closeTo(2.5, 1e-9), closeTo(3.5, 1e-9)),
      );
    });

    test('skips a stretch where the speed has a gap', () {
      expect(gappy.slowestTime([(0.0, 4.0)]), isNull);
      expect(gappy.slowestTime([(0.0, 4.0), (5.0, 6.0)]), closeTo(5.0, 1e-9));
    });

    test('skips a stretch whose ends lie past the samples', () {
      expect(gappy.slowestTime([(8.0, 12.0)]), isNull, reason: 'the recording ends at 10 s');
    });
  });
}
