// One physical drive written in different units must give the same analysis
// (FET-288, the audit of 9 October 2026, findings F04 to F06): a VBO
// declares most units only on its `[header]` line, and an RCZ on the channel;
// either way a calculation reads the quantity in the unit declared and
// converts it, never reading m/s² as g, °F as °C or mph as km/h. Stored
// data and the source fingerprint are untouched, and a unit nothing can read
// says so rather than being read as the default.
import 'dart:io';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

// --- A drive in physical units -------------------------------------------

const double _g = standardGravity;

/// Longitudinal acceleration in m/s²: braking 6 m/s² (0.61 g) for 3 s, then
/// accelerating 3 m/s² (0.31 g) for 3 s.
double _longitudinal(double t) => t >= 5 && t < 8
    ? -6.0
    : t >= 12 && t < 15
    ? 3.0
    : 0.0;

/// Lateral acceleration in m/s²: a 0.51 g corner.
double _lateral(double t) => t >= 10 && t < 14 ? 5.0 : 0.0;

const _seconds = 20.0;
final List<double> _times = [for (var k = 0; k <= 200; ++k) k * 0.1];

/// The drive as a VBO whose accelerations are written in [accelerationUnit]
/// (`g` or `m/s2`, and so on) and declared on the header line only.
String _vbo({
  String accelerationUnit = 'g',
  String speedUnit = 'kmh',
  double speed = 90.0,
  bool declareUnits = true,
}) {
  // The physical values are in m/s²; written in g they are divided by gravity
  // (independently of the code under test).
  final inGravities = accelerationUnit == 'g';
  String written(double metresPerSecondSquared) =>
      (inGravities ? metresPerSecondSquared / _g : metresPerSecondSquared).toStringAsFixed(5);
  final rows = [
    for (final t in _times)
      '${t.toStringAsFixed(1)} $speed ${written(_longitudinal(t))} ${written(_lateral(t))}',
  ];
  return '''[header]
velocity${declareUnits ? ' $speedUnit' : ''}
longacc${declareUnits ? ' $accelerationUnit' : ''}
latacc${declareUnits ? ' $accelerationUnit' : ''}
[column names]
time velocity longacc latacc
[data]
${rows.join('\n')}
''';
}

/// [session] with the units the header declares given to the channels
/// themselves, as an RCZ writes them.
TelemetrySession _channelUnits(TelemetrySession session) => TelemetrySession(
  duration: session.duration,
  startTime: session.startTime,
  metadata: const {},
  channels: {
    for (final MapEntry(:key, :value) in session.channels.entries)
      key: TelemetryChannel(
        name: value.name,
        unit: declaredChannelUnit(session, key),
        timestamps: value.timestamps,
        values: value.values,
      ),
  },
  aliases: session.aliases,
  warnings: session.warnings,
  timingGates: session.timingGates,
  sampleCount: session.sampleCount,
);

void _expectSameIntervals(
  List<DrivingStateInterval> actual,
  List<DrivingStateInterval> expected,
  String reason,
) {
  expect(actual.length, expected.length, reason: reason);
  for (var i = 0; i < expected.length; ++i) {
    expect(actual[i].start, closeTo(expected[i].start, 1e-9), reason: reason);
    expect(actual[i].end, closeTo(expected[i].end, 1e-9), reason: reason);
  }
}

void main() {
  group('how a declaration is read (FET-288)', () {
    TelemetrySession withHeader(String line, {String unit = ''}) => TelemetrySession(
      duration: 1.0,
      startTime: 0.0,
      metadata: {'header.1': line},
      channels: {
        'x': TelemetryChannel(
          name: 'x',
          unit: unit,
          timestamps: Float64List.fromList([0.0, 1.0]),
          values: Float32List.fromList([1.0, 2.0]),
        ),
      },
      aliases: const {},
      warnings: const [],
      timingGates: const [],
      sampleCount: 2,
    );

    test('a unit of several words is kept whole', () {
      expect(declaredChannelUnit(withHeader('x deg C'), 'x'), 'deg C');
      expect(temperatureUnitOf('deg C'), TemperatureUnit.celsius);
      expect(temperatureUnitOf('º F'), TemperatureUnit.fahrenheit);
      expect(temperatureUnitOf('deg. F'), TemperatureUnit.fahrenheit);
    });

    test('an acceleration unit that cannot be read keeps its own spelling', () {
      final view = accelerationInG(withHeader('x ft/s2'), 'x')!;
      expect(view.supported, isFalse);
      expect(view.unit, 'ft/s2');
    });
  });

  group('F04: acceleration in m/s² is not read as g', () {
    // The same drive: written in g, in m/s² however spelled, with the unit
    // on the header line and on the channel.
    final reference = VboParser.parse(_vbo());
    final variants = <String, TelemetrySession>{
      'header m/s2': VboParser.parse(_vbo(accelerationUnit: 'm/s2')),
      'header m/s²': VboParser.parse(_vbo(accelerationUnit: 'm/s²')),
      'header M/S^2': VboParser.parse(_vbo(accelerationUnit: 'M/S^2')),
      'channel m/s2': _channelUnits(VboParser.parse(_vbo(accelerationUnit: 'm/s2'))),
      'channel g': _channelUnits(reference),
    };

    test('the parser keeps the units as the file writes them', () {
      final parsed = variants['header m/s2']!;
      expect(parsed.channels['longacc']!.unit, isEmpty);
      expect(declaredChannelUnit(parsed, 'longacc'), 'm/s2');
    });

    for (final MapEntry(key: name, value: session) in variants.entries) {
      group(name, () {
        test('the G-G pairs are the same in g', () {
          final want = buildGgPairs(reference, 0, _seconds);
          final got = buildGgPairs(session, 0, _seconds);
          expect(got.valid, isTrue);
          expect(got.unitsDeclared, isTrue);
          expect(got.points.length, want.points.length);
          for (var i = 0; i < want.points.length; ++i) {
            expect(got.points[i].longitudinalG, closeTo(want.points[i].longitudinalG, 1e-4));
            expect(got.points[i].lateralG, closeTo(want.points[i].lateralG, 1e-4));
          }
          // The audit's case: 6 m/s² of braking is 0.61 g, not 6 g.
          final braking = got.points.map((p) => p.longitudinalG).reduce((a, b) => a < b ? a : b);
          expect(braking, closeTo(-6 / _g, 1e-4));
          final peaks = computeGgPeaks(got.points), wanted = computeGgPeaks(want.points);
          expect(peaks.braking!.value, closeTo(wanted.braking!.value, 1e-4));
          expect(peaks.lateral!.value, closeTo(wanted.lateral!.value, 1e-4));
        });

        test('the deceleration is usable and the braking is found where it is', () {
          expect(brakingSourceQuality(session).decelerationUsable, isTrue);
          final want = detectBrakingOnsets(reference, 0, _seconds);
          final got = detectBrakingOnsets(session, 0, _seconds);
          expect(got.unresolvedReason, isEmpty);
          expect(got.method, brakingMethodInferred);
          expect(got.threshold.unit, 'g');
          expect(got.candidates.length, 1);
          expect(got.candidates.length, want.candidates.length);
          expect(
            got.candidates.first.telemetryTime,
            closeTo(want.candidates.first.telemetryTime, 1e-3),
          );
          expect(
            got.candidates.first.durationSeconds,
            closeTo(want.candidates.first.durationSeconds, 1e-3),
          );
          expect(got.candidates.first.peakValue, closeTo(want.candidates.first.peakValue, 1e-4));
          expect(got.candidates.first.uncertaintyReasons, isNot(contains(brakingUnitUndeclared)));
        });

        test('the driving states and the strong acceleration are the same', () {
          final want = classifyDrivingStates(reference, 0, _seconds);
          final got = classifyDrivingStates(session, 0, _seconds);
          for (final (what, actual, expected) in [
            ('braking', got.braking, want.braking),
            ('accelerating', got.accelerating, want.accelerating),
            ('cornering', got.cornering, want.cornering),
          ]) {
            expect(actual.unresolvedReason, isEmpty, reason: what);
            expect(actual.provenance, expected.provenance, reason: what);
            _expectSameIntervals(actual.active, expected.active, what);
            _expectSameIntervals(actual.known, expected.known, what);
          }
          expect(got.braking.active, isNotEmpty);
          expect(got.cornering.active, isNotEmpty);
          final strong = lapStrongAcceleration(session, 0, _seconds);
          final wanted = lapStrongAcceleration(reference, 0, _seconds);
          expect(strong.strongG, isNotNull);
          expect(strong.strongG!, closeTo(wanted.strongG!, 1e-4));
          expect(strong.strongG!, closeTo(3 / _g, 1e-3));
        });
      });
    }

    test('the source fingerprint and the parsed samples do not change', () {
      final directory = Directory.systemTemp.createTempSync('fet-units');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/drive.vbo')
        ..writeAsStringSync(_vbo(accelerationUnit: 'm/s2'));
      final session = VboParser.parse(file.readAsStringSync());
      final before = telemetryFingerprint(file.path, session);
      final samples = Float32List.fromList(session.channels['longacc']!.values);
      buildGgPairs(session, 0, _seconds);
      detectBrakingOnsets(session, 0, _seconds);
      classifyDrivingStates(session, 0, _seconds);
      lapStrongAcceleration(session, 0, _seconds);
      expect(telemetryFingerprint(file.path, session), before);
      expect(session.channels['longacc']!.values, samples);
      expect(session.channels['longacc']!.unit, isEmpty);
      expect([
        for (final c in before['channels']! as List) (c as Map)['unit'],
      ], everyElement(isEmpty));
    });

    test('a unit nothing can read gives a reason, not g', () {
      final session = VboParser.parse(_vbo(accelerationUnit: 'furlong/s2'));
      expect(buildGgPairs(session, 0, _seconds).unavailableReason, ggUnsupportedUnit);
      expect(brakingSourceQuality(session).decelerationUsable, isFalse);
      expect(detectBrakingOnsets(session, 0, _seconds).unresolvedReason, brakingUnitMismatch);
      final states = classifyDrivingStates(session, 0, _seconds);
      expect(states.braking.unresolvedReason, 'unitMismatch');
      expect(states.accelerating.unresolvedReason, 'unitMismatch');
      expect(states.cornering.unresolvedReason, 'unitMismatch');
      expect(lapStrongAcceleration(session, 0, _seconds).strongG, isNull);
    });

    test('no declared unit is still read as g, and says so', () {
      final session = VboParser.parse(_vbo(declareUnits: false));
      final pairs = buildGgPairs(session, 0, _seconds);
      expect(pairs.valid, isTrue);
      expect(pairs.unitsDeclared, isFalse);
      expect(
        detectBrakingOnsets(session, 0, _seconds).candidates.first.uncertaintyReasons,
        contains(brakingUnitUndeclared),
      );
    });

    test('a header unit of g is found for the G-G diagram and the braking metrics', () {
      // FET-264: the VBO declares g only on the header line.
      final pairs = buildGgPairs(reference, 0, _seconds);
      expect(pairs.longitudinalUnit, 'g');
      expect(pairs.unitsDeclared, isTrue);
    });
  });

  group('F05: temperatures are judged in their own unit', () {
    // One oil temperature curve: 130 °C, one 300 °C spike (implausible),
    // one exact zero (an OBD placeholder), the rest 126–134 °C.
    final celsius = [for (var k = 0; k < 60; ++k) 130.0 + (k % 5) - 2];
    celsius[10] = 300.0;
    celsius[20] = 0.0;
    final units = <String, double Function(double)>{
      '°C': (c) => c,
      'C': (c) => c,
      'degC': (c) => c,
      '°F': (c) => c * 1.8 + 32,
      'F': (c) => c * 1.8 + 32,
      'degF': (c) => c * 1.8 + 32,
      'K': (c) => c + 273.15,
    };

    TelemetrySession session(
      String unit,
      double Function(double) convert,
      List<double> series, {
      bool declareOnHeader = false,
    }) {
      final times = Float64List.fromList([for (var k = 0; k < series.length; ++k) k.toDouble()]);
      // The placeholder zero stays zero in every unit: an adapter reports 0
      // before its first answer, not 0 °C.
      final values = Float32List.fromList([for (final c in series) c == 0.0 ? 0.0 : convert(c)]);
      return TelemetrySession(
        duration: series.length - 1.0,
        startTime: 0,
        metadata: declareOnHeader ? {'header.1': 'temp_oil $unit'} : const {},
        channels: {
          'temp_oil': TelemetryChannel(
            name: 'temp_oil',
            unit: declareOnHeader ? '' : unit,
            timestamps: times,
            values: values,
          ),
        },
        aliases: const {},
        warnings: const [],
        timingGates: const [],
        sampleCount: series.length,
      );
    }

    final reference = summarizeChannel(
      session('°C', units['°C']!, celsius),
      'temp_oil',
      0,
      59,
      temperatureSummaryPolicy,
    );

    test('the audit case: 130 °C is valid whatever the unit', () {
      for (final MapEntry(key: unit, value: convert) in units.entries) {
        for (final onHeader in [false, true]) {
          final summary = summarizeChannel(
            session(unit, convert, [130, 130, 130], declareOnHeader: onHeader),
            'temp_oil',
            0,
            2,
            temperatureSummaryPolicy,
          );
          expect(summary.valid, isTrue, reason: '$unit header: $onHeader');
          expect(summary.excludedArtifacts, 0, reason: unit);
          expect(summary.unit, unit, reason: unit);
          // The same 130 °C, as the sensor writes it.
          final written =
              const {'°F': 266.0, 'F': 266.0, 'degF': 266.0, 'K': 403.15}[unit] ?? 130.0;
          expect(summary.mean, closeTo(written, 1e-3), reason: unit);
          expect(temperatureUnitOf(unit)!.toCelsius(written), closeTo(130, 1e-9), reason: unit);
        }
      }
    });

    test('the same curve gives the same counts, coverage and mean', () {
      expect(reference.valid, isTrue);
      expect(reference.excludedArtifacts, 2);
      for (final MapEntry(key: unit, value: convert) in units.entries) {
        for (final onHeader in [false, true]) {
          final summary = summarizeChannel(
            session(unit, convert, celsius, declareOnHeader: onHeader),
            'temp_oil',
            0,
            59,
            temperatureSummaryPolicy,
          );
          final kind = temperatureUnitOf(unit)!;
          expect(summary.valid, isTrue, reason: unit);
          expect(summary.sampleCount, reference.sampleCount, reason: unit);
          expect(summary.excludedArtifacts, reference.excludedArtifacts, reason: unit);
          expect(summary.coverage, closeTo(reference.coverage, 1e-9), reason: unit);
          expect(kind.toCelsius(summary.mean!), closeTo(reference.mean!, 1e-3), reason: unit);
          expect(kind.toCelsius(summary.maximum!), closeTo(reference.maximum!, 1e-3), reason: unit);
          expect(kind.toCelsius(summary.minimum!), closeTo(reference.minimum!, 1e-3), reason: unit);
        }
      }
    });

    test('the limits are the same temperatures in every unit', () {
      // 249 °C is plausible, 251 °C is not, in °F and K too.
      for (final MapEntry(key: unit, value: convert) in units.entries) {
        final summary = summarizeChannel(
          session(unit, convert, [100, 249, 251, 100, -41, -39]),
          'temp_oil',
          0,
          5,
          temperatureSummaryPolicy,
        );
        expect(summary.excludedArtifacts, 2, reason: unit);
        expect(summary.sampleCount, 4, reason: unit);
      }
    });

    test('a summarizer and a cooling search read the unit too', () {
      // 120 °C falling to 100 °C over 100 s: a cooling of 20 °C.
      final falling = [for (var k = 0; k < 101; ++k) 120.0 - 20 * k / 100];
      final want = findCoolingIntervals(
        session('°C', units['°C']!, falling),
        'temp_oil',
        temperatureSummaryPolicy,
      );
      expect(want, hasLength(1));
      for (final MapEntry(key: unit, value: convert) in units.entries) {
        final fahrenheit = temperatureUnitOf(unit) == TemperatureUnit.fahrenheit;
        final data = session(unit, convert, falling);
        final got = findCoolingIntervals(data, 'temp_oil', temperatureSummaryPolicy);
        expect(got, hasLength(1), reason: unit);
        expect(got.single.startTime, closeTo(want.single.startTime, 1e-9), reason: unit);
        expect(got.single.endTime, closeTo(want.single.endTime, 1e-9), reason: unit);
        expect(
          got.single.drop,
          closeTo(want.single.drop * (fahrenheit ? 1.8 : 1.0), 1e-3),
          reason: unit,
        );
        final summarizer = ChannelSummarizer(data, 'temp_oil', temperatureSummaryPolicy);
        expect(summarizer.unit, unit);
        expect(summarizer.summarize(0, 100).valid, isTrue, reason: unit);
      }
      // A drop of 4 °C is under the 5 °C needed in °C, °F (7.2) and K.
      final small = [for (var k = 0; k < 101; ++k) 120.0 - 4 * k / 100];
      for (final MapEntry(key: unit, value: convert) in units.entries) {
        expect(
          findCoolingIntervals(session(unit, convert, small), 'temp_oil', temperatureSummaryPolicy),
          isEmpty,
          reason: unit,
        );
      }
    });

    test('a temperature in a unit that is not known has no summary and says why', () {
      final data = session('rankine', (c) => c * 1.8 + 491.67, celsius);
      final summary = summarizeChannel(data, 'temp_oil', 0, 59, temperatureSummaryPolicy);
      expect(summary.valid, isFalse);
      expect(summary.unavailableReason, channelSummaryUnsupportedUnit);
      expect(summary.unit, 'rankine');
      final summarizer = ChannelSummarizer(data, 'temp_oil', temperatureSummaryPolicy);
      expect(summarizer.summarize(0, 59).unavailableReason, channelSummaryUnsupportedUnit);
      expect(findCoolingIntervals(data, 'temp_oil', temperatureSummaryPolicy), isEmpty);
      // Heart rate has no such unit and is read as before.
      final heart = summarizeChannel(data, 'temp_oil', 0, 59, heartRateSummaryPolicy);
      expect(heart.unavailableReason, isNot(channelSummaryUnsupportedUnit));
    });

    test('no unit is °C, as OBD temperatures are', () {
      final summary = summarizeChannel(
        session('', (c) => c, celsius),
        'temp_oil',
        0,
        59,
        temperatureSummaryPolicy,
      );
      expect(summary.valid, isTrue);
      expect(summary.sampleCount, reference.sampleCount);
      expect(temperatureUnitOf(''), TemperatureUnit.celsius);
      expect(temperatureUnitOf('rankine'), isNull);
    });
  });

  group('F06: speed in any unit gives the same coasting', () {
    // 10 s at 60 mph = 26.8224 m/s with both pedals off.
    const metresPerSecond = 26.8224;
    TelemetrySession coasting(String unit, double speed, {bool onHeader = false}) {
      final times = Float64List.fromList([for (var k = 0; k <= 200; ++k) k * .05]);
      TelemetryChannel channel(String name, String unit, double value) => TelemetryChannel(
        name: name,
        unit: unit,
        timestamps: times,
        values: Float32List.fromList(List.filled(times.length, value)),
      );
      return TelemetrySession(
        duration: 10,
        startTime: 0,
        metadata: onHeader ? {'header.1': 'velocity $unit'} : const {},
        channels: {
          'velocity': channel('velocity', onHeader ? '' : unit, speed),
          'brake': channel('brake', '%', 0),
          'throttle': channel('throttle', '%', 0),
        },
        aliases: const {'speed': 'velocity', 'brake': 'brake', 'throttle': 'throttle'},
        warnings: const [],
        timingGates: const [],
        sampleCount: times.length,
      );
    }

    final spellings = <String, double>{
      'km/h': metresPerSecond * 3.6,
      'kmh': metresPerSecond * 3.6,
      'KPH': metresPerSecond * 3.6,
      'mph': metresPerSecond / 0.44704,
      'MPH': metresPerSecond / 0.44704,
      'mi/h': metresPerSecond / 0.44704,
      'm/s': metresPerSecond,
    };

    test('seconds and metres are the same in km/h, mph and m/s', () {
      for (final MapEntry(key: unit, value: speed) in spellings.entries) {
        for (final onHeader in [false, true]) {
          final summary = summarizeCoasting(coasting(unit, speed, onHeader: onHeader), 0, 10);
          final reason = '$unit header: $onHeader';
          expect(summary.unresolvedReason, isEmpty, reason: reason);
          expect(summary.coastingSeconds, closeTo(10, 1e-6), reason: reason);
          expect(summary.coastingMeters, closeTo(268.224, 0.01), reason: reason);
          expect(summary.episodes, hasLength(1), reason: reason);
        }
      }
    });

    test('the audit case: 60 mph is no longer a unit mismatch', () {
      final summary = summarizeCoasting(coasting('mph', 60), 0, 10);
      expect(summary.unresolvedReason, isEmpty);
      expect(summary.coastingSeconds, closeTo(10, 1e-6));
      expect(summary.coastingMeters, closeTo(268.224, 0.01));
    });

    test('moving is judged in the speed\'s own unit', () {
      // 10 km/h is 6.2 mph: 5 mph (8 km/h) is standing, 7 mph (11 km/h) is moving.
      expect(summarizeCoasting(coasting('mph', 5), 0, 10).coastingSeconds, 0);
      expect(summarizeCoasting(coasting('km/h', 8.04672), 0, 10).coastingSeconds, 0);
      expect(summarizeCoasting(coasting('mph', 7), 0, 10).coastingSeconds, closeTo(10, 1e-6));
      expect(
        summarizeCoasting(coasting('km/h', 11.26541), 0, 10).coastingSeconds,
        closeTo(10, 1e-6),
      );
      expect(summarizeCoasting(coasting('m/s', 2.5), 0, 10).coastingSeconds, 0);
      expect(summarizeCoasting(coasting('m/s', 3.0), 0, 10).coastingSeconds, closeTo(10, 1e-6));
    });

    test('the distance travelled over an interval follows the unit', () {
      final span = [const DrivingStateInterval(2, 6)];
      for (final MapEntry(key: unit, value: speed) in spellings.entries) {
        expect(
          travelledMeters(coasting(unit, speed), span),
          closeTo(4 * metresPerSecond, 0.01),
          reason: unit,
        );
        expect(
          travelledMeters(coasting(unit, speed, onHeader: true), span),
          closeTo(4 * metresPerSecond, 0.01),
          reason: unit,
        );
      }
    });

    test('a speed with no unit is km/h, or the unit the user assumes', () {
      final unlabelled = coasting('', 60);
      expect(summarizeCoasting(unlabelled, 0, 10).coastingMeters, closeTo(166.667, 0.01));
      final assumedMph = withEffectiveSpeedUnits(unlabelled, assumed: 'mph');
      expect(summarizeCoasting(assumedMph, 0, 10).coastingMeters, closeTo(268.224, 0.01));
      // A declared unit is never overridden by the assumption.
      final declared = withEffectiveSpeedUnits(coasting('km/h', 60), assumed: 'mph');
      expect(summarizeCoasting(declared, 0, 10).coastingMeters, closeTo(166.667, 0.01));
    });

    test('a unit nothing can read gives a reason and no distance', () {
      final summary = summarizeCoasting(coasting('furlongs/h', 60), 0, 10);
      expect(summary.unresolvedReason, 'unitMismatch');
      expect(summary.coastingSeconds, 0);
      expect(summary.coastingMeters, 0);
      expect(travelledMeters(coasting('furlongs/h', 60), [const DrivingStateInterval(0, 5)]), 0);
    });
  });
}
